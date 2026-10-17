# RabbitMQ 客户端：发布消息与可靠投递

第一章已通过默认交换机把字符串发给 `docs.hello`。这里改用上一章创建的 `docs.events` 交换机和 `docs.orders` 队列，演示业务常用的 JSON 消息。以下代码均放在协程内、取得 `$channel` 之后执行；完整建连代码见[安装与连接](/Client/RabbitMq/index.md)。

## 发布 JSON 消息

```php
$body = json_encode(['orderId' => 1001], JSON_THROW_ON_ERROR);

$channel->publish(
    body: $body,
    exchange: 'docs.events',
    routingKey: 'order.created',
    properties: [
        'content_type' => 'application/json',
        'delivery_mode' => 2,
        'message_id' => 'order-1001',
    ],
);
```

`body` 是消息内容，`exchange` 是投递入口，`routingKey` 决定匹配哪条绑定规则，`properties` 是附加属性。`publish()` 完成写入后即返回，并不表示 Broker 已确认接收。`delivery_mode => 2` 是持久化消息标记；它需要配合 durable 队列使用。业务仍需用订单 ID 等唯一键处理重复投递。

## 等待 Broker 确认

```php
use EasySwoole\AMQP\Exception\MessageReturnedException;

try {
    $channel->publishConfirmed(
        body: $body,
        exchange: 'docs.events',
        routingKey: 'order.created',
        properties: ['delivery_mode' => 2, 'content_type' => 'application/json'],
        mandatory: true,
        timeout: 5.0,
    );
} catch (MessageReturnedException $error) {
    // Exchange 找不到匹配队列；记录并按业务决定重试或报警。
    error_log($error->returnedMessage->replyText);
    throw $error;
}
```

这里的 Publisher Confirm 是“Broker 确认收到了发布操作”，不是“消费者已处理”。首次 `publishConfirmed()` 会自动启用它。Broker NACK 会抛出 `PublisherNackException`；`mandatory: true` 可让不可路由消息通过 `MessageReturnedException` 暴露出来。仅有发布 ACK 不代表消息必然路由到队列，所以需要确认路由时应同时使用 `mandatory`。

## 批量发布

```php
$result = $channel->publisherBatch()
    ->publish('first', 'docs.events', 'order.created')
    ->publish('second', 'docs.events', 'order.created')
    ->wait(timeout: 5.0);

if (!$result->allAcknowledged() || $result->returned !== []) {
    // 检查 $result->nacked 和 $result->returned，按业务 ID 补偿。
    throw new RuntimeException('部分消息未获确认');
}
```

批次序号从 1 开始，可通过 `$result->acked`、`$result->nacked`、`$result->returned` 查看结果。批量确认适合吞吐较高的场景，但应用要保留“序号 → 业务消息”的映射，才能处理部分失败。客户端不会自动重放未确认消息；超时或断线时确认边界可能不明，重试应具备幂等性。

下一章：[消费、确认与进程部署](/Client/RabbitMq/consume.md)。

## 源码依据

- [Channel 发布 API](https://github.com/easy-swoole/amqp/blob/main/src/Channel.php)
- [PublisherBatch](https://github.com/easy-swoole/amqp/blob/main/src/PublisherBatch.php)
