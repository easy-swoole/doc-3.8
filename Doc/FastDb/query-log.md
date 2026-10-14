# 查询日志

FastDb 可以通过全局查询回调记录 SQL、绑定参数、执行耗时和异常。查询日志主要用于回答下面的问题：

- 一次请求执行了哪些 SQL。
- 哪些 SQL 执行失败以及错误码是什么。
- 哪些 SQL 超过慢查询阈值。
- 是否出现重复查询或 N+1 查询。

生产环境不建议毫无筛选地永久记录所有查询。高并发服务中，全量 SQL 日志本身可能产生大量磁盘 I/O，并泄露敏感参数。

## QueryResult 提供的信息

查询回调接收 `EasySwoole\FastDb\Mysql\QueryResult`：

| 方法 | 内容 |
| --- | --- |
| `getDuration()` | SQL 执行耗时，单位为秒 |
| `getStartTime()` | 开始执行的 Unix 时间戳 |
| `getEndTime()` | 结束执行的 Unix 时间戳 |
| `getQueryBuilder()` | QueryBuilder 查询的快照 |
| `getRawSql()` | `rawQuery()` 或事务使用的原始 SQL |
| `getException()` | 查询失败时的异常对象 |
| `getResult()` | 查询执行结果，失败时通常为 `null` |
| `getConnection()` | 本次查询实际使用的连接 |

QueryBuilder 查询应分别记录预处理 SQL 和绑定参数：

```php
$builder = $result->getQueryBuilder();
$sql = $result->getRawSql()
    ?? ($builder ? $builder->getLastPrepareQuery() : null);
$params = $builder ? $builder->getLastBindParams() : [];
```

优先使用 `getLastPrepareQuery()` 和 `getLastBindParams()`，不要把用于调试展示的占位符替换文本当成数据库实际执行形式。

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
            $builder = $result->getQueryBuilder();
            $exception = $result->getException();
            $durationMs = round($result->getDuration() * 1000, 2);

            $sql = $result->getRawSql()
                ?? ($builder ? $builder->getLastPrepareQuery() : null);
            $params = $builder ? $builder->getLastBindParams() : [];

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

FastDb 可以在当前协程中暂存查询记录：

```php
$db = FastDb::getInstance();
$db->isEnableQueryStack(true);

// 执行业务查询

$all = $db->getQueryStack();
$last = $db->getQueryStack(-1);
$previous = $db->getQueryStack(-2);

$db->isEnableQueryStack(false);
```

每条 `QueryStack` 包含：

- `connectionName`
- `query`：QueryBuilder 快照
- `rawQuery`：原始 SQL
- `startTime`、`endTime`
- `duration`：秒

查询栈按协程保存，并在协程退出或回收上下文时清理。开启后会持续积累记录，不建议在长生命周期协程中永久启用；更适合开发、测试或针对特定问题临时开启。

## 回调的异常边界

查询失败时，日志回调中的 `getException()` 是本次执行异常，回调完成后原异常仍会继续抛给业务代码。

查询已经成功后，如果日志回调自身抛出异常，该异常也可能传播给调用者，让业务误以为数据库执行失败。日志处理器应像完整示例一样捕获自身异常，避免日志系统改变数据库操作结果。

事务提交尤其需要注意：日志回调异常发生时，数据库可能已经完成提交，不能因此直接重试整个业务。

## 源码依据

- [FastDb 查询回调与查询栈](https://github.com/easy-swoole/fast-db/blob/3.x/src/FastDb.php)
- [QueryResult](https://github.com/easy-swoole/fast-db/blob/3.x/src/Mysql/QueryResult.php)
- [QueryStack](https://github.com/easy-swoole/fast-db/blob/3.x/src/Beans/QueryStack.php)
