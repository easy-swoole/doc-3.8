# HTTP 跨服务链路传递

跨服务调用使用 W3C Trace Context 的 `traceparent`：

```text
traceparent: 00-{trace-id}-{parent-span-id}-{flags}
```

## 解析 Header

```php
function parseTraceparent(?string $header): ?array
{
    if ($header === null) {
        return null;
    }

    $header = strtolower(trim($header));
    if (!preg_match(
        '/^00-([0-9a-f]{32})-([0-9a-f]{16})-([0-9a-f]{2})$/',
        $header,
        $matches
    )) {
        return null;
    }

    if (trim($matches[1], '0') === '' || trim($matches[2], '0') === '') {
        return null;
    }

    return [
        'trace_id' => $matches[1],
        'parent_span_id' => $matches[2],
        'flags' => $matches[3],
    ];
}

function buildTraceparent(
    string $traceId,
    string $parentSpanId,
    string $flags = '01'
): string {
    return sprintf('00-%s-%s-%s', $traceId, $parentSpanId, $flags);
}
```

外部 Header 不可信。格式错误、ID 全零或版本不支持时，应忽略它并创建新 Trace。

## 服务端继续上游链路

```php
use EasySwoole\Trace\Trace;

$incoming = parseTraceparent(
    $this->request()->getHeaderLine('traceparent')
);

$trace = $incoming === null
    ? new Trace('user-service.request', params: [
        'method' => $this->request()->getMethod(),
        'route' => '/users/{id}',
    ])
    : new Trace(
        name: 'user-service.request',
        traceId: $incoming['trace_id'],
        parentSpanId: $incoming['parent_span_id'],
        params: ['route' => '/users/{id}'],
    );

// 没有合法上游 Header 时，示例默认记录为采样状态。
$traceFlags = $incoming['flags'] ?? '01';
```

## 调用下游服务

先创建代表这次 HTTP 客户端调用的 Span，然后把它的 Span ID 作为下游 Parent Span ID：

```php
use EasySwoole\HttpClient\HttpClient;

$remote = $trace->parallel('HTTP GET order-service', [
    'host' => 'order-service',
    'route' => '/orders',
]);

$traceparent = buildTraceparent(
    $trace->traceId(),
    $remote->spanId(),
    $traceFlags
);

$client = new HttpClient(
    'http://order-service/orders?user_id=10001'
);
$client->setHeader('traceparent', $traceparent, false);

try {
    $response = $client->get();

    if ($response->getErrCode() !== 0) {
        throw new RuntimeException($response->getErrMsg());
    }

    if ($response->getStatusCode() >= 500) {
        throw new RuntimeException('order-service returned 5xx');
    }

    $remote->endCall();
} catch (Throwable $error) {
    $remote->fail($error);
    throw $error;
}
```

下游服务解析 Header 后，用相同 Trace ID 和收到的 Parent Span ID 创建自己的根节点：

```text
user-service.request
└── HTTP GET order-service
    └── order-service.request
        └── OrderController::list
```

## 接入位置

实际项目应把以下逻辑放到统一入口，不要复制到每个控制器：

- HTTP 请求开始：解析 `traceparent`，创建根 Trace。
- HTTP 客户端调用前：创建 Span 并注入 Header。
- 请求结束的 `finally`：结束根 Trace 并批量持久化。
- 异常入口：把当前节点和根节点标记为异常。

组件不会自动执行采样。需要采样时，应用应读取并传播 Trace Flags，并决定是否保存这条 Trace。
