# Trace 调用链与状态

## Trace ID、Span ID 与父节点

一条调用链共享一个 Trace ID，每个节点拥有独立 Span ID：

```php
$traceId = $trace->traceId();
$spanId = $point->spanId();
$parentSpanId = $point->parentSpanId();
```

- Trace ID 是 32 位非零小写十六进制字符串。
- Span ID 是 16 位非零小写十六进制字符串。
- 根节点的 Parent Span ID 通常为 `null`。

## 完整调用链示例

下面模拟一次“查询用户详情”的请求。控制器调用用户服务，用户服务同时查询 MySQL 和 Redis，其中 MySQL 正常完成，Redis 被标记为超时：

```php
<?php

use EasySwoole\Trace\Trace;
use EasySwoole\Trace\Utility;

$trace = new Trace('HTTP GET /users/{id}', params: [
    'user_id' => 10001,
]);

$controller = $trace->next('UserController::profile');
$service = $controller->next('UserService::find');

// 两个节点拥有相同的父节点，表示它们是并列调用。
$mysql = $service->parallel('MySQL: select user');
$redis = $service->parallel('Redis: get user cache');

// 此处仅用 usleep 模拟实际调用耗时。
usleep(2_000);
$mysql->setParams(['rows' => 1]);
$mysql->endCall();

usleep(1_000);
$redis->timeout('cache timeout');

// 子节点结束后，再从内到外结束父节点。
$service->endCall();
$controller->endCall();
$trace->endCall();

echo Utility::toTree($trace);
```

这段代码形成的节点结构如下：

```text
HTTP GET /users/{id}                    根 Trace
└── UserController::profile             串行节点
    └── UserService::find                串行节点
        ├── MySQL: select user           并列节点，执行成功
        └── Redis: get user cache        并列节点，执行超时
```

`Utility::toTree()` 的输出类似下面这样。Trace ID、Span ID 和耗时每次运行都会变化：

```text
Trace: 4e3c54a3f2034df2a385b5541f322784
HTTP GET /users/{id} [serial | success | 3.287 ms] (span: 86e8f1b94736d821)
└── UserController::profile [serial | success | 3.274 ms] (span: e360db797334f9f4)
    └── UserService::find [serial | success | 3.268 ms] (span: 3c41f537e312840c)
        ├── MySQL: select user [parallel | success | 2.139 ms] (span: 65d029530998430f)
        └── Redis: get user cache [parallel | timeout | 3.254 ms] (span: 93d1f78dc05053e3) error: cache timeout
```

从输出中可以直接看到：

- 第一行的 Trace ID 用来检索整条调用链。
- 方括号依次显示节点类型、执行状态和耗时。
- 每一行末尾的 Span ID 用于定位单个调用节点。
- 缩进和连接线表示父子关系，两个 `parallel` 节点位于同一级。
- 超时或异常节点会在末尾显示错误信息。

如果需要把结果交给日志系统、数据库或前端页面，也可以取得结构化数据：

```php
// 包含当前节点和所有子节点的嵌套数组。
$tree = $trace->toArray();

// 扁平的 SpanBean 列表，更适合批量写入数据库。
$spans = $trace->spans();

echo json_encode($tree, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
```

## next：串行后继

```php
$controller = $trace->next('controller');
$service = $controller->next('service');
$database = $service->next('database');
```

每个节点最多只能有一个 `next()`。第二次从同一节点调用会抛出 `LogicException`：

```php
$trace->next('first');
$trace->next('second'); // 错误
```

需要记录并列调用时，应使用 `parallel()`。

## parallel：并行关系

```php
$orders = $service->parallel('order-service');
$coupons = $service->parallel('coupon-service');

go(function () use ($orders): void {
    try {
        // 调用订单服务。
        $orders->endCall();
    } catch (Throwable $error) {
        $orders->fail($error);
    }
});

go(function () use ($coupons): void {
    try {
        // 调用优惠券服务。
        $coupons->endCall();
    } catch (Throwable $error) {
        $coupons->fail($error);
    }
});
```

`parallel()` 只记录父子关系，不会创建协程；上例中的 `go()` 才是真正并发执行。

## 正常、异常与超时

```php
$point->endCall();
$point->fail($error);
$point->timeout('order-service deadline exceeded');
```

对应状态：

| 状态 | 含义 |
| --- | --- |
| `running` | 节点仍在执行 |
| `success` | 正常结束 |
| `exception` | 捕获到异常 |
| `timeout` | 业务明确标记超时 |
| `abandoned` | 节点没有被业务代码正常结束，由父节点、协程 defer 或析构兜底收口 |

结束方法是幂等的，第一次结束后再次调用不会覆盖状态。

## 父节点收口

```php
$first = $point->parallel('service-1');
$second = $point->parallel('service-2');

$first->endCall();
$point->endCall();
```

因为 `$second` 没有结束，父节点结束时它会自动变成 `abandoned`。父节点结束后不能继续创建 `next()` 或 `parallel()`，所以并行任务完成前不要提前结束父节点。

## 节点由谁结束

2.0.2 的 `SpanBean` 增加了 `endedBy`，用于区分正常收口与兜底收口：

| `ended_by` | 对应枚举 | 产生条件 |
| --- | --- | --- |
| `manual` | `EndTrigger::Manual` | 显式调用 `endCall()`、`fail()` 或 `timeout()` |
| `parent` | `EndTrigger::Parent` | 父节点结束时递归收口尚未结束的后代 |
| `coroutine_defer` | `EndTrigger::CoroutineDefer` | 在 Swoole 协程中创建的节点到协程结束时仍未结束 |
| `destructor` | `EndTrigger::Destructor` | 对象析构时节点仍未结束 |
| `null` | — | 节点仍处于 `running` 状态 |

```php
use EasySwoole\Trace\EndTrigger;

$point->endCall();
$span = $point->toSpanBean();

if ($span->endedBy === EndTrigger::Manual) {
    // 节点由业务代码正常结束。
}
```

`coroutine_defer` 和 `destructor` 只对当前节点进行兜底收口，不会递归修改仍被其他代码持有的子节点；显式结束父节点时，才会将未结束的后代统一标记为 `parent`。可以在监控中统计非 `manual` 节点，以发现遗漏的结束调用。

## 记录和更新参数

```php
$point->setParams([
    'user_id' => 10001,
    'result_count' => 20,
]);

$params = $point->params();
```

参数必须可以 JSON 编码。组件不限制大小，应用应自行控制字段和长度。

## 获取耗时和状态

```php
$durationMs = $point->durationMs();
$status = $point->status();
$children = $point->children();
```

耗时由 `hrtime()` 单调时钟计算，不受系统时间校准影响。用于展示和查询的 Unix 微秒时间保存在 SpanBean 中。
