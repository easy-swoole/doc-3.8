# NSQ 客户端：订阅与消费

NSQ 使用 topic 表示消息类别，channel 表示消费组。同一个 topic 的不同 channel 各收到一份消息；同一 channel 内有多个消费者时，它们分担投递。

## 单脚本消费

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use EasySwoole\Nsq\Config;
use EasySwoole\Nsq\Message\Message;
use EasySwoole\Nsq\Nsq;
use Swoole\Coroutine;

Coroutine\run(function (): void {
    $consumer = new Nsq(new Config(readTimeout: -1));

    try {
        $consumer->subscribe('orders.created', 'orders.worker');
        $consumer->consume(function (Message $message, Nsq $client): bool {
            $order = json_decode($message->body, true, 512, JSON_THROW_ON_ERROR);
            echo '处理订单：' . $order['orderId'] . PHP_EOL;
            return true;
        }, requeueDelayMilliseconds: 1000);
    } finally {
        $consumer->close();
    }
});
```

`consume()` 持续运行，适合单独的消费者进程。`readTimeout: -1` 表示接收消息时无限等待；终端可用 Ctrl+C 结束示例。消息体是原始字符串，示例中的 JSON 解码属于应用逻辑。

## 确认与重投规则

| 回调结果 | 客户端行为 |
| --- | --- |
| 返回 `true`、`null`，或没有显式返回值 | 发送 FIN，确认本次消息处理成功 |
| 严格返回 `false` | 发送 REQ，按 `requeueDelayMilliseconds` 延后重投 |
| 抛出异常 | 尝试发送 REQ，然后向外抛出异常并退出消费循环 |
| 已手动 FIN 或 REQ | 不会重复确认 |

组件按 `RDY 1` 串行处理，处理完一条再请求下一条。`$message->attempts` 表示服务端投递次数，`$message->timestamp` 是 Unix 纳秒时间戳。处理可能重复投递的消息时，业务应根据消息 ID 或业务 ID 做幂等处理。

## 手动接收与确认

需要自己控制确认时机时，不调用 `consume()`，改用 `ready()`、`receive()`、`finish()` 或 `requeue()`：

```php
$consumer->subscribe('orders.created', 'orders.manual');
$consumer->ready(1);

$message = $consumer->receive();
try {
    processOrder($message->body); // 由应用实现。
    $consumer->finish($message);
} catch (\Throwable $error) {
    $consumer->requeue($message, 1000);
}
```

订阅后的初始 RDY 是 0。`ready(1)` 设置剩余可投递数为 1，不是在原值上加 1；手动循环需在处理后再次补充 RDY。处理较长任务时可以调用 `$consumer->touch($message)` 延长服务端的消息处理时限。只能确认本连接当前收到、尚未确认的原始 `Message` 对象。

## 在自定义进程中运行

HTTP 控制器不适合承载长期消费循环。新建 `App/Process/NsqOrderConsumer.php`：

```php
<?php

namespace App\Process;

use EasySwoole\Component\Process\AbstractProcess;
use EasySwoole\Nsq\Config;
use EasySwoole\Nsq\Message\Message;
use EasySwoole\Nsq\Nsq;
use Swoole\Coroutine;

class NsqOrderConsumer extends AbstractProcess
{
    private bool $running = true;
    private ?Nsq $consumer = null;

    protected function run($arg): void
    {
        while ($this->running) {
            $this->consumer = new Nsq(new Config(readTimeout: 30.0));
            try {
                $this->consumer->subscribe('orders.created', 'orders.worker');
                $this->consumer->consume(function (Message $message): bool {
                    try {
                        $order = json_decode($message->body, true, 512, JSON_THROW_ON_ERROR);
                        if (!isset($order['orderId']) || !is_int($order['orderId'])) {
                            throw new \UnexpectedValueException('消息缺少整数类型的 orderId');
                        }
                        (new \App\Service\OrderMessageHandler())->handle($order['orderId']);
                        return true;
                    } catch (\Throwable $error) {
                        error_log($error->__toString());
                        return false;
                    }
                }, requeueDelayMilliseconds: 1000);
            } catch (\Throwable $error) {
                if ($this->running) {
                    error_log($error->__toString());
                }
            } finally {
                $this->consumer->close();
                $this->consumer = null;
            }

            if ($this->running) {
                Coroutine::sleep(2); // 连接失败后退避，再重新订阅。
            }
        }
    }

    protected function onSigTerm(): void
    {
        $this->running = false;
        $this->consumer?->close();
    }
}
```

新建 `App/Service/OrderMessageHandler.php`，先用日志验证消费流程，再替换为实际的订单业务：

```php
<?php

namespace App\Service;

class OrderMessageHandler
{
    public function handle(int $orderId): void
    {
        error_log("NSQ 收到订单：{$orderId}");
        // 实际项目在此执行订单业务，并用 orderId 做幂等控制。
    }
}
```

在项目根目录的 `EasySwooleEvent.php` 中注册：

```php
use App\Process\NsqOrderConsumer;
use EasySwoole\Component\Process\Manager;

public static function mainServerCreate(\EasySwoole\EasySwoole\Swoole\EventRegister $register)
{
    Manager::getInstance()->addProcess(new NsqOrderConsumer('NsqOrderConsumer'));
}
```

`run()` 在子进程中执行，网络操作位于协程环境。示例在连接中断后重建客户端并重新订阅；`close()` 不会替尚未确认的消息发送 FIN，消息将由 nsqd 重新投递。生产环境还应按 `$message->attempts` 设置重试上限、告警或人工处理策略。自定义进程的完整注册和生命周期见[自定义进程](/Advanced/process.md)。

下一章：[配置、认证与 TLS](/Client/Nsq/config.md)。

## 源码依据

- [Nsq 消费与确认](https://github.com/easy-swoole/nsq/blob/2.x/src/Nsq.php)
- [Message](https://github.com/easy-swoole/nsq/blob/2.x/src/Message/Message.php)
