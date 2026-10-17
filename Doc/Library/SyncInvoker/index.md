# 同步调用：安装、原理与快速开始

`easyswoole/sync-invoker` 用于从协程中的 HTTP Worker 调用**没有协程支持的同步阻塞代码**，例如只能使用阻塞式 PHP 扩展的第三方 SDK。它不是把同步代码变成非阻塞代码：阻塞工作仍然发生，只是转移到独立进程，使 HTTP Worker 可以继续处理其他协程。本章以已发布的 2.2.2 代码为准。

## 先理解调用路径

```text
HTTP 请求所在的 Worker 协程
    → Unix Socket 发送方法名和参数
    → Sync Invoker 独立进程执行阻塞方法
    → 把结果返回给原协程
```

这里有三个主要对象：

| 对象 | 做什么 |
| --- | --- |
| `SyncInvoker` | 管理同步进程，并提供 `invoke()` 调用入口 |
| `AbstractDriver` 子类 | 定义允许调用的业务方法；通过 `$this->response()` 返回结果 |
| 同步 Worker | 实际执行阻塞方法的独立进程，不是 HTTP Worker |

如果已有可用的协程客户端（例如协程 MySQL/Redis/HTTP 客户端），应优先直接使用它。Sync Invoker 适合无法改造的阻塞 SDK；它会增加进程、Unix Socket 通信和序列化开销。

## 安装

在项目根目录执行：

```bash
composer require 'easyswoole/sync-invoker:^2.2'
composer show easyswoole/sync-invoker
```

2.2.2 要求 PHP 8.1+、Swoole 5.1+，还需要 `pcntl` 和 Unix 信号支持，因此应在 Linux/macOS 等环境运行。以下例子先用独立脚本认识 API，下一节再接入 EasySwoole 框架。

## 最小可运行脚本

在项目根目录新建 `sync-invoker-demo.php`：

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use EasySwoole\SyncInvoker\AbstractDriver;
use EasySwoole\SyncInvoker\SyncInvoker;
use Swoole\Http\Request;
use Swoole\Http\Response;
use Swoole\Http\Server;

class DemoDriver extends AbstractDriver
{
    public function plus(int $a, int $b): void
    {
        sleep(1); // 模拟阻塞式 SDK；实际业务换成 SDK 方法。
        $this->response($a + $b);
    }
}

$invoker = new SyncInvoker();
$invoker->getConfig()->setDriver(new DemoDriver());
$invoker->getConfig()->setWorkerNum(2);

$server = new Server('127.0.0.1', 9502);
$invoker->attachServer($server); // 必须在 start() 前添加同步进程。

$server->on('request', function (Request $request, Response $response) use ($invoker): void {
    $result = $invoker->invoke()->plus(1, 2);
    $response->end((string) $result);
});

$server->start();
```

在终端运行 `php sync-invoker-demo.php`，再用另一终端运行 `curl http://127.0.0.1:9502/`，约一秒后预期响应为 `3`。这一秒的阻塞发生在 Sync Invoker 进程中，不在处理 HTTP 请求的 Worker 中。用 Ctrl+C 停止服务。这个脚本会启动自己的 Swoole HTTP Server，**不要**与已有的 EasySwoole 服务使用同一个端口；它只是帮助理解组件调用链。

注意 `plus()` 没有通过 PHP 的 `return` 返回给调用方，而是调用 `$this->response()`。`$invoker->invoke()->plus(1, 2)` 看上去像本地方法，实际会跨进程执行，参数和结果应使用可序列化的数据，不应传递数据库连接、Socket 或其他进程内资源。

下一章：[在 EasySwoole 中接入](/Library/SyncInvoker/integration.md)。

## 源码依据

- [组件 README（2.2.2）](https://github.com/easy-swoole/sync-invoker/blob/2.2.2/README.md)
- [SyncInvoker（2.2.2）](https://github.com/easy-swoole/sync-invoker/blob/2.2.2/src/SyncInvoker.php)
