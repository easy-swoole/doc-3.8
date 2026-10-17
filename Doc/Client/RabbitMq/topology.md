# RabbitMQ 客户端：交换机、队列与绑定

上一节用默认交换机直接把消息发给 `docs.hello` 队列。一个队列足够完成入门实验；当消息需要按规则进入不同队列时，才需要自己声明 Exchange 和绑定。

发布者先把消息交给 Exchange（交换机），它根据 routing key（路由键）和 Binding（绑定规则）选择 Queue（队列），消费者只从队列取消息。例如“订单创建”消息使用 `order.created` 作为路由键，`order.*` 绑定规则就能匹配它。路由键只是字符串，不会自动创建队列。

## 声明与绑定

以下代码放在协程内、取得 `$channel = $client->channel()` 后执行；完整建连代码见[安装与连接](/Client/RabbitMq/index.md)。如果只是照着第一章发一条消息，可以先跳过本章。下面是为订单事件准备一个可复用的消息路径。

```php
$channel->exchangeDeclare(
    exchange: 'docs.events',
    type: 'topic',
    durable: true,
);

$declared = $channel->queueDeclare(
    queue: 'docs.orders',
    durable: true,
);

$channel->queueBind(
    queue: $declared['queue'],
    exchange: 'docs.events',
    routingKey: 'order.*',
);
```

执行后形成 `docs.events` →（匹配 `order.*`）→ `docs.orders`。此时发布到 `docs.events`、路由键为 `order.created` 的消息会进入 `docs.orders`；写成 `user.created` 则不会匹配。下一章会实际发布订单消息。

`queueDeclare()` 返回 `queue`、`messageCount`、`consumerCount`。队列名传空字符串时由 Broker 分配名称。示例使用固定名称，重启后可以继续消费同一队列；重复声明时参数须与已有队列一致，否则 Broker 会关闭该 Channel。

| Exchange 类型 | 路由方式 | 常见用途 |
| --- | --- | --- |
| `direct` | routing key 精确匹配 | 按类型或业务 ID 分发 |
| `topic` | `*` 匹配一个词，`#` 匹配零个或多个词 | 事件订阅 |
| `fanout` | 忽略 routing key，广播到所有绑定队列 | 广播通知 |
| `headers` | 根据消息 headers 与绑定参数匹配 | 按多维属性路由 |

默认交换机的名称为 `''`，发布时将队列名作为 `routingKey`，无需显式绑定。例如 `$channel->publish('hello', routingKey: 'docs.orders')`。

`durable: true` 使 Exchange/Queue 在 Broker 重启后仍存在，但消息本身还需要设置 `delivery_mode => 2`；需要确认 Broker 接收时还要使用 Publisher Confirm。临时回复队列可考虑 `exclusive: true, autoDelete: true`，其生命周期与连接相关。

其他拓扑方法包括 `queueUnbind()`、`queuePurge()`、`queueDelete()`、`exchangeBind()`、`exchangeUnbind()`、`exchangeDelete()`。删除或清空会影响正在使用该队列的业务，请只对明确目标执行。

下一章：[发布消息与可靠投递](/Client/RabbitMq/publish.md)。

## 源码依据

- [Channel 拓扑 API](https://github.com/easy-swoole/amqp/blob/main/src/Channel.php)
