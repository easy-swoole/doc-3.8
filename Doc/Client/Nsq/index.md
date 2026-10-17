# NSQ 客户端：安装与连接

`easyswoole/nsq` 2.x 是基于 Swoole 协程 Socket 的 NSQ TCP V2 客户端，用来向 nsqd 发布消息、按 topic/channel 订阅消息，也可以通过 nsqlookupd 查询 nsqd 节点。它使用的接口是 `EasySwoole\Nsq\Nsq` 和 `EasySwoole\Nsq\Config`。

## 安装

在项目根目录执行：

```bash
composer require 'easyswoole/nsq:^2.0'
composer show easyswoole/nsq
```

运行环境需要 64 位 PHP 8.1 及以上、Swoole 5.1 及以上。网络操作需要在 Swoole 协程中执行。测试前准备一个可访问的 nsqd TCP 监听端口，默认示例使用 `127.0.0.1:4150`；nsqlookupd 的 HTTP 端口通常是 `4161`，两者不能混用。

## 先理解三个对象

```text
Config：连接地址、超时、认证和 TLS 参数
   ↓
Nsq：一条 nsqd TCP 连接，负责发布或订阅
   ↓
Message：消费时收到的消息及 ID、重试次数等信息
```

一个 `Nsq` 对象由一个协程独占，不要在多个协程中共享同一对象。发布者和订阅者也要分别创建实例；客户端订阅后不能在同一连接上发布。

## 单脚本测试

在项目根目录新建 `nsq-check.php`：

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use EasySwoole\Nsq\Config;
use EasySwoole\Nsq\Nsq;
use Swoole\Coroutine;

Coroutine\run(function (): void {
    $producer = new Nsq(new Config(host: '127.0.0.1', port: 4150));

    try {
        $producer->publish('demo.events', 'hello nsq');
        echo "发布成功\n";
    } finally {
        $producer->close();
    }
});
```

运行 `php nsq-check.php`。`new Nsq(...)` 不会立即连接，第一次发布时会自动连接、完成 IDENTIFY，再等待 nsqd 返回 `OK`。连接失败或服务端拒绝时会抛异常，不会输出“发布成功”。

普通 EasySwoole 控制器或 Task 的协程代码中可直接调用 `publish()`；不要在 `EasySwooleEvent::initialize()` 里提前建立网络连接。消费者通常是长期运行的循环，应放在[自定义进程](/Advanced/process.md)中，后文给出完整示例。

下一章：[发布消息](/Client/Nsq/publish.md)。

## 源码依据

- [NSQ 2.x README](https://github.com/easy-swoole/nsq/blob/2.x/README.md)
- [Nsq 客户端](https://github.com/easy-swoole/nsq/blob/2.x/src/Nsq.php)
- [连接配置](https://github.com/easy-swoole/nsq/blob/2.x/src/Config.php)
