# NSQ 客户端：发布消息

下面的 `$producer` 是按[安装与连接](/Client/Nsq/index.md)创建的 `Nsq` 对象。所有示例都应在协程内运行，并在使用结束后调用 `close()`。

## 普通、批量和延迟发布

```php
$producer->publish('orders.created', '{"orderId":1001}');

$producer->multiPublish('orders.created', [
    '{"orderId":1002}',
    '{"orderId":1003}',
]);

// 1000 毫秒后投递；单位是毫秒。
$producer->deferredPublish('orders.created', '{"orderId":1004}', 1000);
```

消息正文是非空的二进制字符串；组件不会自动把数组转成 JSON。业务传数组时先编码：

```php
$body = json_encode(['orderId' => 1005], JSON_THROW_ON_ERROR);
$producer->publish('orders.created', $body);
```

`multiPublish()` 的消息列表至少要有一项。topic 与 channel 名称仅允许字母、数字、`.`、`_`、`-`，也可以使用 `#ephemeral` 后缀；总长度不能超过 64 字节。延迟发布的最大延迟受 nsqd 配置约束。

## 在控制器中发布

例如已有订单创建逻辑执行成功后，在 `App/HttpController/Order.php` 的 Action 中发布事件：

```php
use EasySwoole\Nsq\Config;
use EasySwoole\Nsq\Nsq;

public function create(): void
{
    // 示例订单号；实际项目应先完成参数校验和订单持久化。
    $orderId = 1005;
    $producer = new Nsq(new Config(host: '127.0.0.1', port: 4150));

    try {
        $producer->publish(
            'orders.created',
            json_encode(['orderId' => $orderId], JSON_THROW_ON_ERROR)
        );
        $this->writeJson(200, ['orderId' => $orderId]);
    } finally {
        $producer->close();
    }
}
```

这里直接发布会让 HTTP 请求等待 nsqd 的 `OK`。如果业务需要数据库写入与消息发布保持一致，还应设计事务消息、outbox 或补偿机制；单靠先写库再调用 `publish()` 不能保证两者原子成功。

## 失败与重试边界

`publish()` 收到 nsqd 的 `OK` 才算成功。连接断开或超时后，客户端不会自动重发，因为消息可能已被服务端接收，只是响应丢失。业务如果决定重试，应让消费者按订单号等业务标识去重。不要把“没收到 OK”直接等同于“消息没发出去”。

下一章：[订阅与消费](/Client/Nsq/consume.md)。

## 源码依据

- [Nsq 发布方法](https://github.com/easy-swoole/nsq/blob/2.x/src/Nsq.php)
- [Packet 命令编码](https://github.com/easy-swoole/nsq/blob/2.x/src/Wire/Packet.php)
