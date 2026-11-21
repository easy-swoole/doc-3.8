# 查询日志

FastDb 可以通过全局查询回调记录 SQL、绑定参数、执行耗时和异常。查询日志主要用于回答下面的问题：

- 一次请求执行了哪些 SQL。
- 哪些 SQL 执行失败以及错误码是什么。
- 哪些 SQL 超过慢查询阈值。
- 是否出现重复查询或 N+1 查询。

生产环境不建议毫无筛选地永久记录所有查询。高并发服务中，全量 SQL 日志本身可能产生大量磁盘 I/O，并泄露敏感参数。

## QueryResult 提供的信息

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

归还连接时由连接池执行的提交或回滚不进入查询回调和查询栈，参见[连接归还策略](/FastDb/connection.md#归还连接时的事务策略)。

## 注册全局查询日志

建议在项目根目录 `EasySwooleEvent.php` 的 `initialize()` 中完成连接注册后设置回调：

```php
use App\Database\FastDbQueryLogger;
use EasySwoole\FastDb\FastDb;

public static function initialize()
{
    // 此处先完成 FastDb addDb() 连接注册

    FastDb::getInstance()->setOnQuery(
        [FastDbQueryLogger::class, 'record']
    );
}
```

`setOnQuery()` 设置的是当前 FastDb 单例的全局回调。通过实体、`query()`、`rawQuery()` 以及实际执行的 `begin()`、`commit()`、`rollback()` 都会进入该回调。

再次调用 `setOnQuery()` 会替换之前的全局回调。如果项目既要记录普通 SQL 又要监控慢查询，应在同一个回调中完成分类，或者由这个回调转发给多个日志处理器。

## 完整日志处理器

新建 `App/Database/FastDbQueryLogger.php`：

```php
<?php

namespace App\Database;

use EasySwoole\EasySwoole\Logger;
use EasySwoole\FastDb\Mysql\QueryResult;

final class FastDbQueryLogger
{
    private const SLOW_QUERY_MS = 200;

    // 开发环境可以设为 true；生产环境通常只记录失败和慢查询
    private const RECORD_ALL = false;

    public static function record(QueryResult $result): void
    {
        try {
            $exception = $result->getException();
            $durationMs = round($result->getDuration() * 1000, 2);

            $sql = $result->getLastPrepareQuery();
            $params = $result->getLastBindParams();

            $isSlow = $durationMs >= self::SLOW_QUERY_MS;
            $isFailed = $exception !== null;

            if (!self::RECORD_ALL && !$isSlow && !$isFailed) {
                return;
            }

            $type = $isFailed
                ? 'query_error'
                : ($isSlow ? 'slow_query' : 'query');

            $context = [
                'type' => $type,
                'sql' => $sql,
                'params' => self::maskParams($params),
                'duration_ms' => $durationMs,
                'started_at' => date(
                    'Y-m-d H:i:s',
                    (int) $result->getStartTime()
                ),
                'error_code' => $exception ? $exception->getCode() : null,
                'error_message' => $exception ? $exception->getMessage() : null,
            ];

            $message = (string) json_encode(
                $context,
                JSON_UNESCAPED_UNICODE
                | JSON_UNESCAPED_SLASHES
                | JSON_INVALID_UTF8_SUBSTITUTE
                | JSON_PARTIAL_OUTPUT_ON_ERROR
            );

            if ($isSlow || $isFailed) {
                Logger::getInstance()->warning($message, 'fast-db');
            } else {
                Logger::getInstance()->info($message, 'fast-db');
            }
        } catch (\Throwable $loggerError) {
            // 日志失败不能让已经成功的数据库操作被业务误判为失败
            error_log('FastDb query logger failed: ' . $loggerError->getMessage());
        }
    }

    private static function maskParams(array $params): array
    {
        $masked = [];

        foreach ($params as $key => $value) {
            $keyText = strtolower((string) $key);

            if (preg_match('/password|passwd|token|secret/', $keyText)) {
                $masked[$key] = '***';
                continue;
            }

            if (is_string($value) && strlen($value) > 500) {
                $masked[$key] = substr($value, 0, 500) . '...';
                continue;
            }

            $masked[$key] = $value;
        }

        return $masked;
    }
}
```

绑定参数通常是按位置排列的数组，不能总是从键名判断其含义。上面的脱敏方法只是基础保护。对于登录、支付等敏感查询，更可靠的方式是：

- 不记录绑定值，只记录参数数量和类型。
- 在业务层标记敏感查询并跳过参数日志。
- 对邮箱、手机号、证件号等数据使用专门的脱敏规则。
- 限制 SQL 日志文件的系统访问权限和保留时间。

## 如何定义慢查询

示例将：

```php
private const SLOW_QUERY_MS = 200;
```

作为慢查询阈值。这个值不是固定标准，应根据接口延迟目标设置。例如接口 P99 目标为 200ms，单条 SQL 阈值可能要设置为 50ms 或 100ms，而不是等到 SQL 本身超过 200ms 才报警。

`QueryResult::getDuration()` 使用单调时钟计算执行时间，系统时间校准不会影响耗时结果。该耗时从 FastDb 获得连接后开始，因此：

```text
记录的 duration
  = SQL 发送、MySQL 执行、结果传输和解析时间
  ≠ 等待连接池 + 建立连接 + SQL 执行的完整业务耗时
```

如果接口很慢但所有 SQL 日志都很快，还需要检查连接池等待、外部 HTTP、Redis、文件 I/O 和业务计算。

## 从日志找出慢查询

查询 EasySwoole 日志目录中标记为 `slow_query` 的记录：

```bash
rg '"type":"slow_query"' Log/
```

查询数据库错误：

```bash
rg '"type":"query_error"' Log/
```

重点观察：

- `duration_ms` 最大的 SQL。
- 同一个 SQL 是否在一次请求中重复执行很多次。
- `params` 不同但 SQL 模板相同的查询是否出现 N+1。
- 慢查询是否集中在某个时间段。
- 是否伴随锁等待、死锁、超时或连接中断错误。

找到 SQL 后，在测试环境或只读副本中使用 MySQL `EXPLAIN` 检查执行计划：

```sql
EXPLAIN
SELECT id, name, score
FROM users
WHERE status = 1
ORDER BY id DESC
LIMIT 20;
```

主要检查：

- 是否使用预期索引。
- `type` 是否出现代价较高的全表扫描。
- `rows` 估算扫描量是否过大。
- `Extra` 是否出现临时表或额外排序。
- WHERE、JOIN 和 ORDER BY 使用的字段是否有合适的联合索引。

不要看到慢查询就盲目添加单列索引。索引应结合完整 SQL、字段选择性、联合索引最左前缀和写入成本设计。

## 单次查询日志

如果只想观察某次静态查询，可以传入 `onQuery`：

```php
use App\Database\FastDbQueryLogger;

$user = User::findRecord(
    1,
    onQuery: [FastDbQueryLogger::class, 'record']
);
```

`findAll()`、`fastUpdate()` 和 `fastDelete()` 也提供 `$onQuery` 参数。

实体实例可以设置自己的回调：

```php
$entity = new User();
$entity->setOnQuery([FastDbQueryLogger::class, 'record']);
$result = $entity->all();
$entity->setOnQuery(null);
```

全局回调和单次/实体回调可以同时执行。如果它们使用同一个记录方法，同一条 SQL 会产生重复日志，应根据需要只保留一种注册方式。

## 使用查询栈排查重复查询

```php
$db->configureQueryStack(true, maxStackSize: 2);
$db->rawQuery('SELECT 11'); // 首次借连接时先记 connectionAcquire，再记 query，共占两条。
$db->rawQuery('SELECT 22');
$db->rawQuery('SELECT 33');

$stack = $db->getQueryStack(); // 当前协程记录数组，未记录时 null。
$first = $db->getQueryStack(0); // SELECT 22，SELECT 11 已淘汰。
$last = $db->getQueryStack(-1); // SELECT 33。
$previous = $db->getQueryStack(-2); // SELECT 22。
$missing = $db->getQueryStack(100); // null。
$db->configureQueryStack(false, maxStackSize: 2); // 停止追加，保持相同容量下的已有记录。
```

`configureQueryStack(bool $enabled, int $maxStackSize = 256): static` 的容量必须是正整数，配置属于该 FastDb 实例；每个协程分别保留最近 N 条事件，包含 `query` 和 `connectionAcquire`，达到容量时淘汰最旧项。返回数组始终按保留记录的先后顺序排列；正索引 0 表示当前保留的最旧项，-1 表示最新项，越界返回 null。首次查询若需要借连接会产生两条事件，复用连接的后续查询只有 `query` 事件。

每次启停调用都会应用 `maxStackSize`，缩小容量会立即裁剪该实例所有已有协程栈，包括关闭时。关闭只停止追加，不主动清空，但 `configureQueryStack(false)` 也会应用默认容量 256：此前容量大于 256 时，已有记录会缩到最近 256 条。需要保留更大容量下的现有记录，可显式传原容量，例如 `configureQueryStack(false, maxStackSize: 1024)`。协程退出或回收上下文时清理其记录。

每项 `QueryStack` 的公共字段均为只读。

| 字段 | 含义 |
| --- | --- |
| `type` | 普通 SQL 为 `query`，独立连接获取事件为 `connectionAcquire` |
| `connectionName` | 本次操作的连接名快照，失败时也可定位尝试借用的连接 |
| `rawQuery` | 原始 SQL 文本，构建器查询和连接获取事件为 null |
| `duration` | 当前事件耗时，秒；query 为驱动执行阶段，connectionAcquire 为本次 getObj() 的获取总耗时 |
| `exception` | SQL 执行异常，或连接获取事件中实际向外抛出的借用异常；成功时为 null |
| `startTime` / `endTime` | 记录的起止 Unix 时间戳，用于日志定位；耗时字段使用单调时钟 |

主查询与 `SELECT FOUND_ROWS() as count` 各有一条 trace，各自触发全局 `onQuery`。FastDb 对每条 SQL 先记录 trace，再通知回调。主查询或其回调抛异常时，列表停止执行，总数 SQL 不会发出。总数 SQL 的回调抛异常时，异常直接传播，已记录的 trace 保留。查询栈和查询结果共享同一份 SQL 快照。

普通 SQL 记录的异常来自该 SQL 执行结果，不把 SQL 成功后日志回调再抛出的错误改记为 SQL 失败。获取连接失败时，栈中的 `exception` 则保留实际向调用方抛出的那个异常。

#### 连接获取的独立事件

通过 FastDb 真正执行一次 `getObj()` 新借连接，无论由 `query()`、`rawQuery()`、直接 `begin()`，还是 `invoke()`、`transaction()` 触发，都生成一条独立的 `type = 'connectionAcquire'` 事件。复用已有连接不生成获取事件；向 `begin()` 显式传入已有 Connection 也不借连接。连接池内部的创建、健康检查与重试包含在这一条事件里，不拆成多条。配置校验、`testDb()` 和 `preConnect()` 不属于这段借用计时。

借用失败同样记录独立获取事件。`duration` 是获取历时，连接名及实际向外抛出的异常可见。连接获取事件的两个 SQL getter 返回 null，绑定参数返回 `[]`。没有执行 SQL 时，不生成 `query` 事件，也不调用全局 `onQuery`。

仅在借用入口已启用查询栈时启动获取计时，记录完成时若已关闭则丢弃事件；入口关闭、借用过程中才开启时，该次借用不补记获取事件，之后的查询执行可正常入栈。`query(callable)` 的构建阶段可以开启查询栈，之后执行的 SQL 会按当时的配置记录。

```php
$db->configureQueryStack(true, maxStackSize: 256);
try {
    $db->rawQuery('SELECT 1');
} catch (Throwable $error) {
    $event = $db->getQueryStack(-1);
    if ($event !== null && $event->type === 'connectionAcquire') {
        $acquireMs = $event->duration * 1000;
        $connectionName = $event->connectionName;
        $sameException = $event->exception === $error;
    }
    throw $error;
}
```

## 回调的异常边界

查询失败时，日志回调中的 `getException()` 是本次执行异常，回调完成后原异常仍会继续抛给业务代码。

查询已经成功后，如果日志回调自身抛出异常，该异常也可能传播给调用者，让业务误以为数据库执行失败。日志处理器应像完整示例一样捕获自身异常，避免日志系统改变数据库操作结果。

事务提交尤其需要注意：日志回调异常发生时，数据库可能已经完成提交，不能因此直接重试整个业务。

## 源码依据

- [`easyswoole/fast-db` 3.1.2 · GitHub](https://github.com/easy-swoole/fast-db/tree/3.1.2)

- [FastDb 查询回调与查询栈（3.1.2）](https://github.com/easy-swoole/fast-db/blob/3.1.2/src/FastDb.php)
- [QueryResult（3.1.2）](https://github.com/easy-swoole/fast-db/blob/3.1.2/src/Mysql/QueryResult.php)
- [QueryStack（3.1.2）](https://github.com/easy-swoole/fast-db/blob/3.1.2/src/Beans/QueryStack.php)
