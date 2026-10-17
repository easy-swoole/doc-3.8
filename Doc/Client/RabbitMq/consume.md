# RabbitMQ 客户端：消费、确认与进程部署

第一章已经用 `get()` 取回 `docs.hello` 的字符串消息。这里改用前两章建立的 `docs.orders` 队列接收订单 JSON。消息体始终是字符串；如果发布的是 JSON，消费时要自行解码和校验。以下代码放在协程内、取得 `$channel` 之后执行。

## 单次拉取

```php
$message = $channel->get('docs.orders', timeout: 3.0);
if ($message === null) {
    echo "队列暂时为空\n";
} else {
    try {
        $order = json_decode($message->body, true, 512, JSON_THROW_ON_ERROR);
        // 在这里处理 $order，并以 orderId 做幂等判断。
        $channel->ack($message->deliveryTag);
    } catch (Throwable $error) {
        $channel->nack($message->deliveryTag, requeue: true);
        throw $error;
    }
}
```

`get()` 返回 `null` 代表队列当前为空。`deliveryTag` 是本次投递在当前 Channel 上的编号，只能在这个 Channel 上确认。`ack()` 表示处理成功；`nack(..., requeue: true)` 表示处理失败并要求重新入队。若设置 `autoAck: true`，Broker 会在投递时确认，处理失败也无法再 NACK，因此关键业务建议使用手动确认。

## 持续消费

```php
use EasySwoole\AMQP\Channel;
use EasySwoole\AMQP\Message;

$channel->qos(prefetchCount: 20);
$channel->consume(
    queue: 'docs.orders',
    handler: function (Message $message, Channel $channel): bool {
        $order = json_decode($message->body, true, 512, JSON_THROW_ON_ERROR);
        (new \App\Service\OrderHandler())->handle((int) $order['orderId']);
        return true; // 自动发送 ACK。
    },
);
```

`consume()` 会持续等待新消息，不会像 `get()` 那样取一条就返回。`qos(prefetchCount: 20)` 限制尚未确认的在途消息数。手动确认模式下，回调返回 `false` 会 NACK 并重新入队；返回其他值（包括 `null`）会 ACK；抛出异常时客户端尽力 NACK 并重新抛出。回调中若已调用 `ack()`、`nack()` 或 `reject()`，客户端不会重复确认。不要对永久失败的消息无限重入队；需要重试上限或死信队列时，应在 Broker 上配置相应策略。

## 在 EasySwoole 自定义进程中运行

HTTP 请求不能承载常驻的消费循环。创建 `App/Process/RabbitMqConsumer.php`：

```php
<?php

namespace App\Process;

use EasySwoole\AMQP\AMQP;
use EasySwoole\AMQP\Config;
use EasySwoole\AMQP\Message;
use EasySwoole\Component\Process\AbstractProcess;
use Swoole\Coroutine;

class RabbitMqConsumer extends AbstractProcess
{
    private bool $running = true;
    private ?AMQP $client = null;

    protected function run($arg): void
    {
        while ($this->running) {
            $this->client = new AMQP(new Config(
                host: '127.0.0.1',
                user: 'guest',
                password: 'guest',
                heartbeat: 10,
            ));

            try {
                $channel = $this->client->channel();
                $channel->queueDeclare(queue: 'docs.orders', durable: true);
                $channel->qos(prefetchCount: 20);
                $channel->consume('docs.orders', function (Message $message): bool {
                    $order = json_decode($message->body, true, 512, JSON_THROW_ON_ERROR);
                    (new \App\Service\OrderHandler())->handle((int) $order['orderId']);
                    return true;
                });
            } catch (\Throwable $error) {
                if ($this->running) {
                    error_log($error->__toString());
                }
            } finally {
                $this->client->close();
                $this->client = null;
            }

            if ($this->running) {
                Coroutine::sleep(2); // 断线后退避并重新声明、订阅。
            }
        }
    }

    protected function onSigTerm(): void
    {
        $this->running = false;
        $this->client?->close();
    }
}
```

在 `App/Service/OrderHandler.php` 实现业务方法，并依据订单 ID 做幂等处理。然后在项目根目录 `EasySwooleEvent.php` 的 `mainServerCreate()` 中注册进程：

```php
use App\Process\RabbitMqConsumer;
use EasySwoole\Component\Process\Manager;
use EasySwoole\EasySwoole\Swoole\EventRegister;

public static function mainServerCreate(EventRegister $register)
{
    Manager::getInstance()->addProcess(new RabbitMqConsumer('RabbitMqConsumer'));
}
```

这里的 `OrderHandler` 是应用示例类，不属于 AMQP 组件。客户端不提供自动重连或拓扑自动恢复；重新连接后需重新创建 Channel、声明队列并订阅。更多进程生命周期说明见[自定义进程](/Advanced/process.md)。

同一 Channel 需要订阅多个队列时可以调用 `subscribe()` 创建多个订阅，再用 `wait()` 接收；不能与该 Channel 的 `consume()` 混用。并行处理建议使用不同 Channel。

下一章：[配置、TLS 与故障处理](/Client/RabbitMq/config.md)。

## 源码依据

- [Channel 消费 API](https://github.com/easy-swoole/amqp/blob/main/src/Channel.php)
- [Message](https://github.com/easy-swoole/amqp/blob/main/src/Message.php)
