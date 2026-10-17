# NSQ 客户端：服务发现与故障处理

生产环境有多个 nsqd 时，可以先向 nsqlookupd 查询某个 topic 的生产节点，再按应用策略连接这些节点。服务发现只返回地址，不会自动创建消费者、分配负载或持续刷新节点列表。

## 查询 nsqlookupd

```php
use EasySwoole\Nsq\Lookup\Nsqlookupd;

$lookup = new Nsqlookupd([
    'http://lookup-1.internal:4161',
    'http://lookup-2.internal:4161',
]);

$endpoints = $lookup->lookupHosts('orders.created');
// 例如 ['10.0.0.8:4150', '10.0.0.9:4150']。
```

这段代码必须在协程内运行。客户端会合并并去重成功节点的结果；如果所有查询都失败，抛出 `LookupException`。返回空数组是合法结果，可能表示当前没有该 topic 的生产节点。这里的地址是 nsqd TCP 地址，不是 HTTP URL。

## 根据发现结果连接

```php
use EasySwoole\Nsq\Config;
use EasySwoole\Nsq\Nsq;

$endpoint = $endpoints[0] ?? null;
if ($endpoint === null) {
    throw new \RuntimeException('没有可用的 nsqd 节点');
}

$address = parse_url('tcp://' . $endpoint);
if (!is_array($address) || !isset($address['host'], $address['port'])) {
    throw new \RuntimeException('nsqd 地址格式不正确');
}

$client = new Nsq(new Config(
    host: trim($address['host'], '[]'),
    port: (int) $address['port'],
));

try {
    $client->publish('orders.created', '{"orderId":1001}');
} finally {
    $client->close();
}
```

示例只选择一个节点，确保本次消息只发布一次。生产环境应自行实现节点选择、失败切换和定期刷新；消费端则通常为每个目标 nsqd 建立独立连接，每条连接由自己的协程管理。不要跨协程共享同一个 `Nsq` 实例。

## HTTPS 发现

nsqlookupd 使用 HTTPS 和私有 CA 时：

```php
use EasySwoole\Nsq\Lookup\Nsqlookupd;
use EasySwoole\Nsq\TlsConfig;

$lookup = new Nsqlookupd(
    ['https://lookup.internal:4162'],
    tls: new TlsConfig(caFile: '/run/secrets/nsq-ca.pem'),
);
```

显式提供发现用 TLS 配置时，列表中的地址都必须是 HTTPS。lookupd 的 HTTPS 只保护发现请求；发现出来的 nsqd TCP 连接是否启用 TLS，由创建 `Nsq` 时的 `Config::tls` 独立决定。

## 连接错误与重连

| 异常 | 常见原因 |
| --- | --- |
| `ConnectionException` | TCP 断开、超时、TLS 协商或握手失败 |
| `ReadException` | 帧损坏、过大或响应顺序不符合协议 |
| `ServerException` | nsqd 返回 `E_*` 错误帧 |
| `LookupException` | 所有 lookupd 请求失败或响应无效 |

发布失败时不自动重发，因为服务端可能已经收到消息，只是 `OK` 丢失。消费连接断开后应创建新客户端、重新 `subscribe()`，再恢复消费循环；旧连接收到的 `Message` 不能在新连接上 FIN 或 REQ。重试时要有退避和告警，并为业务处理设计幂等性。

## 源码依据

- [Nsqlookupd](https://github.com/easy-swoole/nsq/blob/2.x/src/Lookup/Nsqlookupd.php)
- [Nsq 客户端](https://github.com/easy-swoole/nsq/blob/2.x/src/Nsq.php)
