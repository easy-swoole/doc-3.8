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

$affectedRows = $result->getAffectedRows();
$insertId = $result->getInsertId();
```

## 批量插入与更新

`fastInsertAll(iterable $rows, ?string $tableName = null, ?callable $onQuery = null, int $batchSize = 500): int|string` 把数据库格式的关联数组分批插入：

```php
$affected = User::fastInsertAll([
    ['name' => 'Alice', 'status' => 1, 'score' => 10],
    ['score' => 20, 'name' => 'Bob', 'status' => 1], // 字段顺序可以不同。
], batchSize: 500);
```

输入可以是数组、Generator 或其他 iterable。每行必须是非空的数据库字段关联数组，同一批内必须使用相同的字段集合，由 mysqli 构建 SQL 时校验；只重排键顺序可以，不会自动补 null。各批独立执行，允许不同批次使用不同字段集合。每行按迭代读取时的标量值进入缓冲，后续修改行内标量引用不会改写已读取的行。JSON 等属性应先转成数据库可写的值；不会对每行应用实体转换器或插入钩子，也不回填自增 ID 或实体比较基准。

#### 使用生成器控制批次内存

```php
function userRows(): \Generator
{
    for ($i = 1; $i <= 2000; $i++) {
        yield ['name' => 'User-' . $i, 'status' => 1, 'score' => $i];
    }
}

$affected = User::fastInsertAll(userRows(), tableName: 'users', batchSize: 500);
```

框架只缓冲当前批次，不会先把整个生成器转成数组，也不逐行创建模型。`batchSize` 按行数控制，默认 500；小于或等于 0 会抛出 `InvalidArgumentException`。空输入在 batchSize 有效时返回 0，不构造模型、不执行 SQL，也不校验未使用的更新列。非空有效输入省略表名时，在首次写入前仅初始化一个模型来取得表名，这个模型自身的默认初始化与 `OnInitialize` 仍会执行；显式给出有效表名则不构造模型。

#### 主键或唯一键冲突时更新

`fastUpsert(iterable $rows, array $updateColumns, ?string $tableName = null, ?callable $onQuery = null, int $batchSize = 500): int|string` 使用同样的分批规则。冲突由数据库已有的主键或唯一索引决定，不会自行选择业务字段作为唯一键：

```php
$affected = User::fastUpsert([
    ['id' => 1, 'name' => 'Alice', 'score' => 10],
    ['id' => 2, 'name' => 'Bob', 'score' => 20],
], ['name', 'score'], batchSize: 500);

// 列表项使用本次输入的对应列；关联项使用固定值或 mysqli Expression。
$affected = User::fastUpsert([
    ['id' => 1, 'name' => 'Alice', 'score' => 10],
], [
    'name',
    'status' => 1,
    'score' => QueryBuilder::rawExpression('`users`.`score` + ?', [5]),
], tableName: 'users', batchSize: 500);
```

`$updateColumns` 沿用 mysqli 的 `upsert()` 规则；列表列名需存在于每条输入行中。非空输入的空更新列由 mysqli 抛出 `InvalidArgumentException`；`$rows` 为空时直接返回 0。固定值及表达式应用于发生冲突的行，插入新行仍使用输入值或数据库默认值。需要逐实体转换、钩子和主键回填时，继续使用实体 `insert($updateDuplicateCols)`。

返回值是各批数据库 `affectedRows` 的合计，不是输入行数或自增 ID 列表。upsert 的插入、实际更新和未改变值可能产生不同的影响行数，应按数据库语义理解；合计超出 PHP 整数范围时返回十进制字符串，保留精度。

#### 回调、连接与失败处理

每批使用 FastDb 统一执行入口，触发全局查询日志及传入的 `$onQuery`；该回调收到本批的 `QueryResult`，不是整次批量操作的累计结果。整次操作固定入口选中的连接；默认表名需要模型初始化时，以该初始化和表名求值后选中的连接为准。生成器可以自行切换选库，后续批次仍写入原定数据库。

方法不自动开启事务，也不自动重试。后续批次的字段校验、生成器、SQL 或回调发生异常时，前面的批次可能已经成功；查询成功后的回调异常也不代表该批 SQL 已回滚。需要整次原子性时，使用同一连接的显式事务，例如：

```php
$db = FastDb::getInstance();
$db->begin();
$connection = $db->currentConnection();
try {
    $affected = User::fastInsertAll(userRows(), tableName: 'users', batchSize: 500);
    $db->commit($connection);
} catch (\Throwable $error) {
    $db->rollback($connection);
    throw $error;
}
```

显式保存连接可以保证生成器改变当前选库后，仍对实际写入连接提交或回滚；提交结果不明时仍需按事务章节说明核实。若调用前已有事务，应由该事务的拥有者决定提交或回滚。需要更多 SQL 构建选项时，仍可通过 `FastDb::query()` 使用底层 `QueryBuilder::insertAll()` / `upsert()`。

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

$updated = $updateResult->getAffectedRows();
```

```php
$deleteResult = FastDb::getInstance()->query(
    function (QueryBuilder $query): void {
        $query->where('id', 10)
            ->delete('users');
    }
);

$deleted = $deleteResult->getAffectedRows();
```

调用更新和删除前，应确认构建器确实包含 WHERE 条件。底层 QueryBuilder 不会替业务判断是否允许全表操作。

## QueryResult

| 方法 | 返回内容 |
| --- | --- |
| `getResult()` | SELECT 等返回行数组，写入/DDL 通常返回 bool；查询失败回调中为 null |
| `getResultOne()` | 数组结果的第一行，否则 null |
| `getException(): ?Throwable` | 执行失败时的异常对象；成功或未设置时为 null |
| `getConnectionName()` | 本次查询的执行连接名快照（string），供慢日志和异常定位使用 |
| `getAffectedRows()` | 本次成功查询的影响行数快照；未取得结果或查询失败时为 null |
| `getInsertId()` | 本次成功查询的自增 ID 快照；未取得结果或查询失败时为 null |
| `getLastQuery(): ?string` | 按需展开绑定参数生成日志 SQL |
| `getLastPrepareQuery(): ?string` | 保留占位符的 SQL |
| `getLastBindParams(): array` | 按占位符顺序排列的绑定参数 |
| `getRawSql()` | 原始 SQL 文本；构建器查询时通常 null |
| `getDuration(): float` | 查询执行阶段耗时，秒；不含获取连接及日志回调 |
| `getStartTime()` / `getEndTime()` | Unix 时间戳，用于日志定位；查询执行耗时使用 getDuration() |

查询回调接收只读 `QueryResult`。`QueryResult`、`QueryStack` 和 `TimeoutException` 使用相同的日志读取方法。原始 SQL 和事务操作的 SQL getter 返回执行文本，绑定参数为 `[]`。构建器查询的日志快照保存 mysqli 的只读编译结果，调用 `getLastQuery()` 时才按编译时的引号规则展开参数。自定义构建器应在构建阶段设置最终 SQL 和绑定参数。

写入结果的影响行数和 insert id 从 `QueryResult` 快照读取。

```php
$affected = $result->getAffectedRows();
$insertId = $result->getInsertId();
```

查询结果和查询栈记录实际执行连接的名称。SQL 执行失败时也会记录该名称。

FastDb 的 `query()` 和 `rawQuery()` 每次执行一条 SQL。Connection 返回后立即保存结果行、影响行数、自增 ID、SQL、参数和耗时。查询结果只反映本次执行，读取新数据需要再次查询。

Connection 的 `getLastAffectRows()` / `getLastInsertId()` 始终表示最后一条实际执行 SQL 的元数据，包括分页总数查询。通过 FastDb 执行时，使用返回的 `QueryResult` 获取该次操作的影响行数和自增 ID。

影响行数和自增 ID 类型为 `int|string|null`，超大无符号值保留为字符串，未查询或查询失败时为 null。影响行数与自增 ID 在查询成功后、日志回调执行前记录为快照，不会被后续 SQL 覆盖。`query()` 和 `rawQuery()` 的可选 `$timeout` 控制本次查询超时。

直接使用 `FastDb::query()` 执行带 `SQL_CALC_FOUND_ROWS` 的查询时，如需总数，应紧接着调用 `rawQuery()` 执行 `SELECT FOUND_ROWS()`，并把主查询的 `getConnectionName()` 传给 `connection:`。实体分页入口会执行这一步，总数通过 `ListResult::totalCount()` 读取。

`getDuration()` 只记录驱动执行阶段，排除 SQL 构建、获取连接、池连接淘汰和查询观察回调。

连接获取耗时通过查询栈的独立 `connectionAcquire` 事件读取，不分摊给某条 SQL 或 QueryResult。计时覆盖连接池 `getObj()` 阶段，包含排队、按需新建连接、健康检查及重试；它不是纯粹的队列等待时间。业务端到端耗时还包含进入查询执行阶段前的构建和业务代码等阶段，需要另行计时。

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

`FastDb::query()`、`rawQuery()` 及 `begin()` / `commit()` / `rollback()` 的执行超时抛出 `EasySwoole\FastDb\Exception\TimeoutException`。异常创建时保存只读 SQL 上下文。message 保持底层错误消息，不拼接 SQL 或参数。

| 方法 | 返回内容 |
| --- | --- |
| `getRawSql(): ?string` | 对应 SQL；预处理查询保留占位符，事务 SQL 包含 flags |
| `getLastQuery(): ?string` | 按需展开绑定参数的日志 SQL |
| `getLastPrepareQuery(): ?string` | 保留占位符的 SQL |
| `getLastBindParams(): array` | 按占位符顺序排列的绑定参数 |
| `getPrevious()` | 原始 mysqli 超时异常；错误码和 message 保持一致 |

```php
use EasySwoole\FastDb\Exception\TimeoutException;

$query = new QueryBuilder();
$query->raw('SELECT SLEEP(?)', [1]);
try {
    $db->query($query, timeout: 0.05);
} catch (TimeoutException $error) {
    $sql = $error->getLastPrepareQuery(); // SELECT SLEEP(?)
    $params = $error->getLastBindParams(); // [1]
    $message = $error->getMessage(); // 原始超时消息。
    $cause = $error->getPrevious();
    // 将 message、sql、params 按需交给日志系统。
    throw $error;
}
```

原始查询及事务超时可直接使用 `getRawSql()` 定位，例如 `COMMIT AND NO CHAIN NO RELEASE`。预处理查询使用 `getLastPrepareQuery()` 和 `getLastBindParams()` 获取 SQL 模板及参数。

FastDb 的超时异常继承 `EasySwoole\FastDb\Exception\Exception`。调用方可捕获 `EasySwoole\FastDb\Exception\TimeoutException`，或 FastDb 通用 `Exception`；它不继承 mysqli 异常，原始 mysqli 超时实例保存在 `getPrevious()` 中。

这里覆盖 FastDb Connection 的 query/rawQuery 执行路径；获取连接前的连接池等待或建连失败、直接使用依赖 Client/prepare 的异常遵循各自入口。记录绑定参数时应按业务需要保护敏感数据。提交超时的结果需要核实，不能据此直接认定回滚。

## 源码依据

- [FastDb query/rawQuery](https://github.com/easy-swoole/fast-db/blob/3.1.1/src/FastDb.php)
- [QueryResult](https://github.com/easy-swoole/fast-db/blob/3.1.1/src/Mysql/QueryResult.php)
- [EasySwoole Mysqli QueryBuilder](https://github.com/easy-swoole/mysqli/blob/5.x/src/QueryBuilder.php)
