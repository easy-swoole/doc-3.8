# Trace 持久化与展示

## 获取 SpanBean

```php
$current = $point->toSpanBean();
$allSpans = $trace->spans();
$onlyCurrent = $point->spans(onlySelf: true);
```

`spans()` 返回扁平的 `SpanBean[]`，适合批量入库；`toArray()` 返回带递归 `children` 的树，适合展示。

## Span 字段

| 数据库字段 | 类型 | 说明 |
| --- | --- | --- |
| `trace_id` | `char(32)` | 调用链 ID |
| `span_id` | `char(16)` | 节点 ID |
| `parent_span_id` | `char(16) null` | 父节点 ID |
| `name` | `varchar` | 节点名称 |
| `type` | `varchar` | `serial` 或 `parallel` |
| `status` | `varchar` | 执行状态 |
| `started_at_unix_us` | `bigint` | 开始 Unix 微秒时间 |
| `ended_at_unix_us` | `bigint null` | 结束 Unix 微秒时间 |
| `duration_us` | `bigint` | 单调时钟耗时 |
| `params` | `json` | 节点参数 |
| `error` | `text null` | 异常类和消息 |
| `ended_by` | `varchar null` | `manual`、`parent`、`coroutine_defer` 或 `destructor`；运行中为 `null` |

数据库必须为 `(trace_id, span_id)` 建立唯一索引，支持协程节点后续 upsert。

## 批量保存

```php
$rows = array_map(
    static function ($span): array {
        $row = $span->toArray();
        $row['params'] = json_encode(
            $row['params'],
            JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR
        );
        return $row;
    },
    $trace->spans()
);

$repository->insertMany($rows);
$trace->markPersisted();
```

只有数据库事务提交成功后才能调用 `markPersisted()`。

## 协程延迟节点补写

外层请求可能先入库，内部协程稍后才创建或结束节点。2.0.2 可以通过 `setAutoPersist()` 设置自动补写回调：

```php
use EasySwoole\Trace\TracePoint;

$toRow = static function ($span): array {
    $row = $span->toArray();
    $row['params'] = json_encode(
        $row['params'],
        JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR
    );
    return $row;
};

$trace->setAutoPersist(
    static function (TracePoint $point) use ($repository, $toRow): void {
        $rows = array_map(
            $toRow,
            $point->spans(onlySelf: true)
        );

        $repository->upsertMany($rows);
    }
);
```

回调会传播给设置前已经存在的后代节点，也会传播给之后通过 `next()` 和 `parallel()` 创建的节点。自动回调应只补写当前节点，因此使用 `spans(onlySelf: true)`，不能每次重复保存整棵树。

### 外层先保存、协程稍后结束

如果内部协程需要在外层首次保存后继续建立节点，应先创建一个保持运行状态的协程范围：

```php
use EasySwoole\Trace\TracePoint;

$toRow = static function ($span): array {
    $row = $span->toArray();
    $row['params'] = json_encode(
        $row['params'],
        JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR
    );
    return $row;
};

$trace->setAutoPersist(
    static function (TracePoint $point) use ($repository, $toRow): void {
        $repository->upsertMany(array_map(
            $toRow,
            $point->spans(onlySelf: true)
        ));
    }
);

$asyncScope = $trace->parallel('async-scope');

// 首次保存当前已有节点；事务提交后再标记。
$repository->upsertMany(array_map(
    $toRow,
    $trace->spans()
));
$trace->markPersisted();

go(static function () use ($asyncScope): void {
    $task = $asyncScope->next('send-notification');

    try {
        // 执行异步业务。
        $task->endCall();
        $task->persistIfNeeded();
    } catch (Throwable $error) {
        $task->fail($error);
        $task->persistIfNeeded();
    }

    $asyncScope->endCall();
    $asyncScope->persistIfNeeded();
});
```

父节点一旦结束便不能再创建子节点，所以不能在启动协程前先结束 `$asyncScope`。

### defer、析构与主动补写

节点在 Swoole 协程中创建时，会自动注册一次 `Coroutine::defer()`。协程结束时，如果节点仍未结束，会被标记为 `abandoned`，结束来源为 `coroutine_defer`，随后执行自动持久化回调。

没有安装 Swoole 或当前不在协程中时不会注册 defer；对象析构时仍会进行兜底，结束来源为 `destructor`。析构时间不确定，所以业务流程可控时应显式结束并主动补写：

协程结束前优先主动执行：

```php
$didPersist = $point->persistIfNeeded();
```

`persistIfNeeded()` 只有在节点尚未标记持久化且已经配置回调时才执行，并返回 `true`；否则返回 `false`。回调成功后只标记当前节点，不会顺带标记其子节点。

节点执行 `endCall()`、`fail()`、`timeout()` 或 `setParams()` 后会重新变成未持久化状态，方便把最终状态 upsert 回数据库。自动持久化回调失败时节点不会被标记成功，并产生 `E_USER_WARNING`。

析构和 defer 都只是兜底，不保证在业务期望的准确时刻执行。回调应保持短小，不能依赖已经释放的连接，也不要强引用当前 Trace 形成引用环。数据库应使用 `(trace_id, span_id)` 唯一索引和 upsert，应对同一节点的状态补写。

可以通过 `ended_by` 找出没有被业务代码正常关闭的节点：

```sql
SELECT *
FROM trace_spans
WHERE ended_by IN ('parent', 'coroutine_defer', 'destructor');
```

## 从数据库恢复

```php
use EasySwoole\Trace\Bean\SpanBean;
use EasySwoole\Trace\Utility;

$rows = $repository->findByTraceId($traceId);
$beans = array_map(
    static fn (array $row): SpanBean => SpanBean::fromArray($row),
    $rows
);

$trace = Utility::restoreFromBeans($beans);
```

`SpanBean::fromArray()` 使用 snake_case 数据库字段；`params` 可以是数组或 JSON 字符串，数据库驱动返回的数字字符串也可以还原为整数。`status`、`type`、ID、时间和 `ended_by` 会被严格校验，非法值会抛出 `InvalidArgumentException`。

必须查询该 Trace 的完整节点集合。缺少父节点、重复 Span ID、多根或循环关系都会导致恢复失败。

## 输出调用树

文本输出：

```php
echo Utility::toTree($trace);
```

树形数组和 JSON：

```php
$tree = $trace->toArray();

echo json_encode(
    $trace,
    JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR
);
```

生产环境应按 Trace ID 查询，不要把所有 Span 全量加载到内存。参数和错误信息展示前还需要做权限控制及敏感信息脱敏。
