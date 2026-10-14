# 事务与行锁

FastDb 的事务由 `FastDb` 单例管理。事务期间，当前协程和当前连接名的查询复用同一个数据库连接，直至提交、回滚或连接回收。

## 基本事务

```php
use App\Model\User;
use EasySwoole\FastDb\FastDb;

$db = FastDb::getInstance();

if (!$db->begin()) {
    throw new \RuntimeException('Cannot begin transaction');
}

try {
    $user = User::findRecord(1, selectForUpdate: true);

    if ($user === null) {
        throw new \RuntimeException('User not found');
    }

    $user->score += 10;
    $user->updated_at = date('Y-m-d H:i:s');

    if (!$user->update()) {
        throw new \RuntimeException('Update failed');
    }

    if (!$db->commit()) {
        throw new \RuntimeException('Commit failed');
    }
} catch (\Throwable $exception) {
    try {
        $db->rollback();
    } catch (\Throwable $rollbackError) {
        // 记录回滚失败，不要覆盖原异常
    }

    throw $exception;
}
```

`selectForUpdate: true` 生成锁定查询。行锁必须在事务内使用，并尽量缩短持锁时间。

## 调用顺序

```text
FastDb::begin()
  → 当前协程从当前连接池取得 Connection A
  → Connection A 执行 START TRANSACTION
  → 实体查询和写入继续复用 Connection A
  → commit() 或 rollback()
  → 协程结束或 recycleContext() 后归还连接
```

不要在事务中创建子协程执行需要原子性的 SQL。子协程具有不同协程上下文，可能取得另一条连接，不属于外层事务。

## 事务方法

| 方法 | 说明 |
| --- | --- |
| `begin($client = null, $flags = ..., $timeout = null)` | 开始事务，已有事务时返回 `true` |
| `commit($client = null, $flags = ..., $timeout = null)` | 提交，没有活动事务时返回 `true` |
| `rollback($client = null, $flags = ..., $timeout = null)` | 回滚，没有活动事务时返回 `true` |
| `isInTransaction($connection = null)` | 检查当前或指定连接的事务状态 |

事务方法的参数顺序是 `(client, flags, timeout)`。

## flags 和超时

```php
use EasySwoole\Mysqli\Transaction\TransactionCompletionFlags;
use EasySwoole\Mysqli\Transaction\TransactionStartFlags;

FastDb::getInstance()->begin(
    flags: TransactionStartFlags::ReadWrite,
    timeout: 1.0
);

FastDb::getInstance()->commit(
    flags: TransactionCompletionFlags::NoChainNoRelease,
    timeout: 1.0
);
```

flags 必须传对应枚举，不能传整数或另一种事务枚举。常见开始模式：

- `None`：普通 `START TRANSACTION`。
- `ReadWrite`：显式读写事务。
- `ReadOnly`：只读事务。
- `ConsistentSnapshot`：请求一致性快照。

FastDb 默认使用 `NoChainNoRelease` 完成事务，即结束当前事务、不自动开始下一事务并保留连接。

## 实例链式行锁

```php
$entity = new User();
$entity->queryLimit()
    ->where('id', 1)
    ->selectForUpdate();

$result = $entity->all();
$user = $result->first();
```

也可以使用：

```php
$result = $entity->all(true);
```

查询、更新和提交必须保持在同一协程、同一 FastDb 连接名内。

## 多数据库事务

切换连接后开始的事务只属于该连接：

```php
use EasySwoole\FastDb\FastDb;

FastDb::getInstance()->selectConnection('reporting');
FastDb::getInstance()->begin();

try {
    // reporting 数据库操作
    FastDb::getInstance()->commit();
} catch (\Throwable $exception) {
    FastDb::getInstance()->rollback();
    throw $exception;
}
```

在两个数据库连接上分别开启事务，不构成分布式事务，无法保证两边同时提交或同时回滚。

## 回收保护和异常

连接回收时，如果仍处于未提交事务，FastDb 会尝试回滚；回滚失败的连接会从连接池丢弃。这只是防止带事务状态的脏连接被复用，不能替代显式异常处理。

InnoDB 死锁错误 1213 会使整个事务回滚，组件清理事务标记，但不会自动重试。业务如果满足幂等条件，可以有限次数重试整个事务。锁等待超时 1205 和普通 SQL 错误仍需显式回滚。

事务或提交超时时，服务端可能已经提交、客户端只是未及时收到响应。不能看到超时就直接再次提交或重复业务，应通过业务唯一键、流水记录等方式核实最终状态。

## 使用建议

- 数据表使用 InnoDB。
- 在事务开始前完成参数校验。
- 事务中不要请求第三方 HTTP 服务或执行长时间计算。
- 多处更新按固定顺序加锁，降低死锁概率。
- Redis、消息队列和第三方接口不会随 MySQL 事务回滚。
- DDL 可能隐式提交，不要混入普通业务事务。
- 多次 `begin()` 不会建立嵌套事务或 Savepoint。

## 源码依据

- [FastDb 事务实现](https://github.com/easy-swoole/fast-db/blob/3.x/src/FastDb.php)
- [TransactionTest](https://github.com/easy-swoole/fast-db/blob/3.x/tests/TransactionTest.php)
- [MySQL Connection](https://github.com/easy-swoole/fast-db/blob/3.x/src/Mysql/Connection.php)
