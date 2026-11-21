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

## 回调事务

`transaction(callable $callback, TransactionStartFlags $flags = TransactionStartFlags::None, ?float $timeout = null): mixed` 在入口选中的实际连接上管理回调事务。回调接收当前 `FastDb` 实例，也可使用无参数闭包；正常完成时返回回调的原始返回值，包括 false、null 或对象。

```php
$db = FastDb::getInstance();
$updated = $db->transaction(function (FastDb $db): bool {
    $user = User::findRecord(1, selectForUpdate: true);
    if ($user === null) {
        throw new RuntimeException('User not found');
    }
    $user->score += 10;
    if (!$user->update()) {
        throw new RuntimeException('Update failed');
    }
    return true;
}, flags: TransactionStartFlags::ReadWrite, timeout: 1.0);
```

`transaction()` 使用自身的事务生命周期。子类覆写 `begin()`、`commit()` 或 `rollback()` 时，覆写只作用于显式调用这些入口。入口连接没有事务时，本层先开始事务，回调正常返回后提交；开始或业务回调抛异常时，入口连接仍有活动事务才尝试回滚，随后抛出原异常。开始失败不会执行回调。返回严格的 `false` 也是正常返回，会提交；需要让拥有层回滚时应抛出异常。

#### 同连接嵌套与已有手动事务

入口连接已经有事务时，本层只执行回调，不发送 BEGIN、COMMIT 或 ROLLBACK。`flags` 和 `timeout` 仅用于本层实际发送的事务 SQL。

同连接的内层异常被外层业务捕获后，外层可以正常提交，包括内层在异常前已经执行的写入。内层异常若继续逃出最外层拥有者，才由该拥有者回滚：

```php
$db->transaction(function (FastDb $db): void {
    try {
        $db->transaction(function (FastDb $db): void {
            // 与外层使用同一个数据库事务。
            throw new RuntimeException('Inner operation failed');
        });
    } catch (RuntimeException $error) {
        // 已捕获异常；外层正常返回时仍会提交。
    }
});
```

事务原本由手工 `begin()` 开启时，`transaction()` 同样只加入并执行回调。无论回调返回还是抛异常，都由手工事务的调用方决定何时提交或回滚；框架不额外标记该事务。

#### 连接选择与 A → B → A

拥有层固定入口的实际 Connection，结束时始终操作该连接；回调改变选库，不会让 helper 提交其他连接。方法本身不恢复选库，也不会把回调中的全部 SQL 强制路由到入口连接。需要退出时恢复连接名，可配合 `withConnection()`。

A → B → A 时，A、B 各自尚无事务的外层分别开始一个事务，重新进入 A 的内层只加入 A。

假设已通过 `addDb()` 注册名为 `A`、`B` 的连接，进入示例前两者都没有事务。下面在 A 写入、切到 B 读取，再回到 A 写入：

```php
$db = FastDb::getInstance();
$db->withConnection('A', function (FastDb $db): void {
    $db->transaction(function (FastDb $db): void {
        // 开始 A 的事务。
        User::fastUpdate(1, ['status' => 1]);

        $db->withConnection('B', function (FastDb $db): void {
            $db->transaction(function (FastDb $db): void {
                // 开始 B 的独立事务，当前查询使用 B。
                User::findRecord(1);

                $db->withConnection('A', function (FastDb $db): void {
                    $db->transaction(function (FastDb $db): void {
                        // 复用外层 A 的连接和事务，不重复 BEGIN。
                        User::fastUpdate(1, ['score' => 20]);
                    }); // 只退出内层回调，不提交 A。
                }); // 恢复选择 B。

                User::findRecord(2); // 继续使用 B。
            }); // 正常返回，提交 B。
        }); // 恢复选择 A。

        User::fastUpdate(1, ['status' => 2]); // 仍在最外层 A 的事务中。
    }); // 正常返回，提交 A，包括内层 A 的写入。
}); // 恢复进入示例前的连接名。
```

发生异常时：

- 内层 A 的异常被业务捕获后，A、B 都可以继续正常提交；没有自动的局部回滚。
- 异常逐层逃出时，各个拥有层分别回滚自己的连接。
- B 已经提交后，A 随后回滚不会撤销 B；两个连接没有分布式事务协调。

#### flags、超时和提交失败

拥有层使用 flags 开始事务，timeout 分别传给本层实际发送的 BEGIN、COMMIT、ROLLBACK。每条控制 SQL 都有独立的单次预算；这不是 PHP 回调或整个事务的累计期限，业务 SQL 仍使用各自查询参数或连接配置。连接池等待也不包含在控制 SQL 超时内。

开始或业务回调抛出的异常优先于回滚清理异常，回滚失败不会替换原异常。提交发生在业务回调正常返回之后：提交本身或其日志回调抛出的异常直接向外传播，不自动重试，也不自动追加 ROLLBACK。尤其 COMMIT 已成功后的日志异常不能视为数据库未提交；提交超时、断线等结果不明时，由业务核实最终状态并处理。

helper 不解析 SQL 白名单，不管理 savepoint，不跟踪事务代次，也不阻止回调手工开始、提交、回滚或执行会隐式提交的 SQL。这些操作对事务边界及业务原子性的影响由调用方负责。

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

连接归还时，FastDb 按 `transactionRecycleAction` 处理未结束事务，默认回滚。`Commit` 会提交，`None` 会把事务及锁保留到下一次借用。配置示例和异常路径见[归还连接时的事务策略](/FastDb/connection.md#归还连接时的事务策略)。业务代码应明确管理事务边界。

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

- [`easyswoole/fast-db` 3.1.2 · GitHub](https://github.com/easy-swoole/fast-db/tree/3.1.2)

- [FastDb 事务实现（3.1.2）](https://github.com/easy-swoole/fast-db/blob/3.1.2/src/FastDb.php)
- [TransactionTest（3.1.2）](https://github.com/easy-swoole/fast-db/blob/3.1.2/tests/TransactionTest.php)
- [MySQL Connection（3.1.2）](https://github.com/easy-swoole/fast-db/blob/3.1.2/src/Mysql/Connection.php)
