# 原始查询

实体 API 适合常规单表操作。遇到复杂统计、批量写入、特殊 JOIN 或数据库函数时，可以直接使用 `FastDb::query()` 和 `FastDb::rawQuery()`。

两种入口的主要区别：

| 入口 | 参数 | 是否支持绑定参数 | 返回值 |
| --- | --- | --- | --- |
| `query()` | `QueryBuilder` 或构建回调 | 支持 | `QueryResult` |
| `rawQuery()` | 完整 SQL 字符串 | 不单独支持 | `QueryResult` |

包含外部输入时优先使用 `QueryBuilder` 和绑定参数，不要把输入值直接拼进 SQL。

## 执行 QueryBuilder

先创建构建器，再传给 FastDb：

```php
use EasySwoole\FastDb\FastDb;
use EasySwoole\Mysqli\QueryBuilder;

$query = new QueryBuilder();
$query->where('status', 1)
    ->where('score', 10, '>=')
    ->orderBy('id', 'DESC')
    ->get('users', 20, ['id', 'name', 'score']);

$result = FastDb::getInstance()->query($query);
$rows = $result->getResult();
$first = $result->getResultOne();
```

`get()`、`insert()`、`update()`、`delete()` 或 `raw()` 等方法用于完成最终 SQL 构建。如果只调用 `where()` 而没有指定最终操作，FastDb 无法执行一条完整查询。

## 使用构建回调

`query()` 也接受回调。FastDb 会创建 `QueryBuilder` 并传入回调：

```php
$result = FastDb::getInstance()->query(
    function (QueryBuilder $query): void {
        $query->where('status', 1)
            ->orderBy('id', 'DESC')
            ->get('users', 20, ['id', 'name']);
    }
);

$rows = $result->getResult();
```

回调必须在返回前完成最终构建动作。这个写法适合只使用一次的查询；需要复用、调试或捕获构建器信息时，显式创建 `QueryBuilder` 更直观。

## 参数化原始 SQL

复杂 SQL 可以交给 `QueryBuilder::raw()`，第二个参数提供绑定值：

```php
$query = new QueryBuilder();
$query->raw(
    'SELECT id, name, score
     FROM users
     WHERE status = ? AND score >= ?
     ORDER BY id DESC
     LIMIT 20',
    [1, 10]
);

$result = FastDb::getInstance()->query($query, timeout: 1.0);
$rows = $result->getResult();
```

占位符只用于数据值，表名、字段名和排序方向等 SQL 标识符不能通过普通参数绑定。动态标识符必须由应用白名单决定：

```php
$allowedOrder = ['id', 'score', 'created_at'];
$orderField = in_array($inputOrder, $allowedOrder, true)
    ? $inputOrder
    : 'id';

$query = new QueryBuilder();
$query->orderBy($orderField, 'DESC')
    ->get('users', 20, ['id', 'name']);
```

## 使用 rawQuery

`rawQuery()` 直接执行完整 SQL 字符串：

```php
$db = FastDb::getInstance();

$result = $db->rawQuery(
    'SELECT CURRENT_TIMESTAMP AS current_time',
    timeout: 1.0
);

$row = $result->getResultOne();
```

方法签名：

```php
rawQuery(string $sql, ?float $timeout = null): QueryResult
```

`rawQuery()` 没有单独的绑定参数参数，因此只适合完全由应用控制的固定 SQL。下面是危险写法：

```php
// 错误：用户输入被直接拼进 SQL
FastDb::getInstance()->rawQuery(
    "SELECT * FROM users WHERE email = '{$email}'"
);
```

包含动态值时应改用 `QueryBuilder::raw($sql, $params)`：

```php
$query = new QueryBuilder();
$query->raw(
    'SELECT * FROM users WHERE email = ?',
    [$email]
);

$result = FastDb::getInstance()->query($query);
```

## 插入

```php
$result = FastDb::getInstance()->query(
    function (QueryBuilder $query): void {
        $query->insert('users', [
            'name' => 'Alice',
            'email' => 'alice@example.com',
            'status' => 1,
            'score' => 0,
            'created_at' => date('Y-m-d H:i:s'),
            'updated_at' => date('Y-m-d H:i:s'),
        ]);
    }
);

$connection = $result->getConnection();
$affectedRows = $connection->getLastAffectRows();
$insertId = $connection->getLastInsertId();
```

## 批量插入

FastDb 实体当前没有 `insertAll()`，可以使用底层构建器：

```php
$result = FastDb::getInstance()->query(
    function (QueryBuilder $query): void {
        $query->insertAll('users', [
            [
                'name' => 'Alice',
                'email' => 'alice@example.com',
                'status' => 1,
                'score' => 10,
                'created_at' => date('Y-m-d H:i:s'),
                'updated_at' => date('Y-m-d H:i:s'),
            ],
            [
                'name' => 'Bob',
                'email' => 'bob@example.com',
                'status' => 1,
                'score' => 20,
                'created_at' => date('Y-m-d H:i:s'),
                'updated_at' => date('Y-m-d H:i:s'),
            ],
        ]);
    }
);

$affectedRows = $result->getConnection()->getLastAffectRows();
```

底层写入不会执行实体的字段转换和生命周期钩子，数据必须已经符合数据库格式。

## 更新和删除

```php
$updateResult = FastDb::getInstance()->query(
    function (QueryBuilder $query): void {
        $query->where('id', 10)
            ->update('users', [
                'status' => 0,
                'updated_at' => date('Y-m-d H:i:s'),
            ]);
    }
);

$updated = $updateResult->getConnection()->getLastAffectRows();
```

```php
$deleteResult = FastDb::getInstance()->query(
    function (QueryBuilder $query): void {
        $query->where('id', 10)
            ->delete('users');
    }
);

$deleted = $deleteResult->getConnection()->getLastAffectRows();
```

调用更新和删除前，应确认构建器确实包含 WHERE 条件。底层 QueryBuilder 不会替业务判断是否允许全表操作。

## QueryResult

`query()` 和 `rawQuery()` 都返回 `EasySwoole\FastDb\Mysql\QueryResult`：

| 方法 | 内容 |
| --- | --- |
| `getResult()` | 查询行数组；写入或 DDL 通常是布尔结果 |
| `getResultOne()` | 查询结果第一行，没有时返回 `null` |
| `getException()` | 执行失败时的异常对象 |
| `getConnection()` | 本次查询实际使用的连接 |
| `getQueryBuilder()` | QueryBuilder 的快照，rawQuery 时为 `null` |
| `getRawSql()` | rawQuery 的 SQL，构建器查询通常为 `null` |
| `getDuration()` | 本次执行耗时，单位为秒 |

影响行数和自增 ID 保存在 Connection 上：

```php
$connection = $result->getConnection();
$affectedRows = $connection->getLastAffectRows();
$insertId = $connection->getLastInsertId();
```

这些值会被该连接的下一条 SQL 更新，应在当前调用返回后立即读取。

## 在事务中执行

FastDb 会在同一协程、同一连接名中复用事务连接，因此可以在事务内使用两种查询入口：

```php
$db = FastDb::getInstance();
$db->begin();

try {
    $query = new QueryBuilder();
    $query->raw(
        'UPDATE users SET score = score + ? WHERE id = ?',
        [10, 1]
    );

    $db->query($query, timeout: 1.0);
    $db->commit();
} catch (\Throwable $exception) {
    $db->rollback();
    throw $exception;
}
```

不要在事务中把查询放进新的子协程，否则子协程可能取得另一条连接。

## 查询超时

`query()` 和 `rawQuery()` 的第二个参数控制本次 SQL 执行超时：

```php
use EasySwoole\FastDb\Exception\TimeoutException;

try {
    $result = FastDb::getInstance()->query($query, timeout: 0.5);
} catch (TimeoutException $error) {
    $sql = $error->getRawSql();
    $builder = $error->getQueryBuilder();
    $params = $builder ? $builder->getLastBindParams() : [];

    // 记录脱敏后的 SQL、参数和异常信息
    throw $error;
}
```

三个超时控制的阶段不同：

```text
getObjectTimeout  → 等待连接池对象
maxConnectTime    → 建立数据库连接
query timeout     → 执行本次 SQL
```

查询超时不代表整个业务从开始到结束的总耗时上限。提交事务超时时还可能出现服务端已提交、客户端没有及时收到响应的情况，不能直接重复业务操作。

## 源码依据

- [FastDb query/rawQuery](https://github.com/easy-swoole/fast-db/blob/3.x/src/FastDb.php)
- [QueryResult](https://github.com/easy-swoole/fast-db/blob/3.x/src/Mysql/QueryResult.php)
- [EasySwoole Mysqli QueryBuilder](https://github.com/easy-swoole/mysqli/blob/5.x/src/QueryBuilder.php)
