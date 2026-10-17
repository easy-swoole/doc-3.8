# RabbitMQ 客户端：安装与连接

本节先完成一件事：从 PHP 发出一条消息，再用 PHP 把它取回来。跑通之后，再学习交换机、持久化和长期运行的消费者。

RabbitMQ 是消息服务器；`easyswoole/amqp` 是 PHP 连接 RabbitMQ 的客户端。AMQP 是两者通信的协议，并不是另一个需要安装的服务。

## 先认识四个名字

| 名称 | 可以先理解为 | 本节对应代码 |
| --- | --- | --- |
| RabbitMQ / Broker | 保存并转发消息的服务器 | `127.0.0.1:5672` |
| `AMQP` 客户端 | PHP 与服务器之间的一条连接 | `new AMQP(new Config(...))` |
| `Channel` | 连接内执行命令的通道 | `$client->channel()` |
| Queue（队列） | 暂存待处理消息的地方 | `docs.hello` |

一条消息的大致路径是：发布者 → RabbitMQ → 队列 → 消费者。后面会介绍 Exchange（交换机）；第一次运行时先用 RabbitMQ 自带的默认交换机，不必手动创建它。

## 安装与准备

在项目根目录执行：

```bash
composer require 'easyswoole/amqp:^1.0'
composer show easyswoole/amqp
```

需要 64 位 PHP 8.1+、Swoole 5.1+。还要先启动 RabbitMQ，并确认 PHP 所在机器能访问它的 AMQP 端口（默认 5672）。如果本机已安装 RabbitMQ，可运行 `rabbitmq-diagnostics ping` 检查服务；尚未安装时，请先按 RabbitMQ 官方安装文档准备服务。管理界面常用 15672 端口，不能把它填成这里的 AMQP 端口。

示例使用本机的 `guest/guest` 和默认 vhost `/`。RabbitMQ 的 `guest` 通常仅允许从服务器本机登录；如果 PHP 与 RabbitMQ 分处两台机器，先在 RabbitMQ 创建自己的账号和 vhost，再替换下面的配置。

## 第一步：发布一条消息

在项目根目录（能看到 `vendor/autoload.php` 的目录）创建 `amqp-send.php`：

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use EasySwoole\AMQP\AMQP;
use EasySwoole\AMQP\Config;
use Swoole\Coroutine;

Coroutine\run(function (): void {
    $client = new AMQP(new Config(
        host: '127.0.0.1',
        port: 5672,
        user: 'guest',
        password: 'guest',
        vhost: '/',
    ));

    try {
        $channel = $client->channel();
        $channel->queueDeclare(queue: 'docs.hello', durable: true);
        $channel->publish(body: 'hello rabbitmq', routingKey: 'docs.hello');
        echo "已发送：hello rabbitmq\n";
    } finally {
        $client->close();
    }
});
```

执行 `php amqp-send.php`，预期输出 `已发送：hello rabbitmq`。`queueDeclare()` 确保队列存在；`routingKey` 填队列名，是因为这里使用默认交换机。`publish()` 返回只说明客户端已经写出消息，并不等于 RabbitMQ 已确认保存；可靠发布稍后再讲。

## 第二步：把消息取回来

在同一目录创建 `amqp-receive.php`：

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use EasySwoole\AMQP\AMQP;
use EasySwoole\AMQP\Config;
use Swoole\Coroutine;

Coroutine\run(function (): void {
    $client = new AMQP(new Config(
        host: '127.0.0.1',
        port: 5672,
        user: 'guest',
        password: 'guest',
        vhost: '/',
    ));

    try {
        $channel = $client->channel();
        $message = $channel->get('docs.hello');
        if ($message === null) {
            echo "队列为空，请先运行 php amqp-send.php\n";
            return;
        }

        echo '收到：' . $message->body . PHP_EOL;
        $channel->ack($message->deliveryTag);
    } finally {
        $client->close();
    }
});
```

执行 `php amqp-receive.php`，预期输出 `收到：hello rabbitmq`。再运行一次会显示队列为空，因为上一条消息已经确认。`get()` 是“取一条”；`ack()` 是告诉 RabbitMQ“这条处理成功，可以移除”。实际业务应在处理成功后才 ACK，处理失败则 NACK 并决定是否重新入队。

## 在 EasySwoole 项目里放哪里

上面两个 PHP 文件只是最小可运行实验，不需要修改框架文件。实际项目中，短时间的发布操作可以放在控制器或 Task 的业务代码里；连接应在使用它的协程中创建，完成后在 `finally` 里 `close()`。不要在 `EasySwooleEvent::initialize()` 中提前建立网络连接。需要一直等待消息的消费者应放到[自定义进程](/Advanced/process.md)，完整例子见[消费、确认与进程部署](/Client/RabbitMq/consume.md)。

`channel()` 会按需建立连接，不必先调用 `connect()`。一个 `AMQP` 对象对应一条连接，不是连接池。

下一章：[交换机、队列与绑定](/Client/RabbitMq/topology.md)。

## 源码依据

- [AMQP README](https://github.com/easy-swoole/amqp/blob/main/README.md)
- [AMQP 客户端](https://github.com/easy-swoole/amqp/blob/main/src/AMQP.php)
