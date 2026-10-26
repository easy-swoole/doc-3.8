# 同步调用：安装、原理与快速开始

`easyswoole/sync-invoker` 适合在 Swoole 协程服务中调用没有协程支持的阻塞式 SDK。阻塞代码并没有消失，而是在独立的同步进程中运行；发起调用的协程通过 Unix Socket 等待结果，HTTP Worker 可以继续调度其他协程。以下用法以组件 `2.2.3` 为准。

## 先理解结构

```text
HTTP Worker 中的协程
    → invoke(超时秒数)->方法名(参数)
    → 抢占一个空闲同步进程，通过 Unix Socket 发送命令
    → 该进程调用 AbstractDriver 子类中的 public 方法
    → Driver 使用 response(结果) 设置返回值
    → 结果通过 Unix Socket 返回原协程
```

`workerNum` 决定最多同时执行多少个阻塞调用；每个同步进程一次只执行一个调用。共享的 `Swoole\Table` 记录各进程的 PID 和是否空闲。如果已经有协程版客户端，优先直接使用它，避免额外的进程与序列化开销。

## 安装与环境

在项目根目录执行：

```bash
composer require 'easyswoole/sync-invoker:^2.2'
composer show easyswoole/sync-invoker
php --ri swoole
```

组件要求 PHP 8.1+、Swoole 5.1+，以及可使用 Unix Socket 和进程信号的系统。调用参数与结果要能序列化，不能直接跨进程传递数据库连接或 Socket 资源。

## 单脚本测试

先用独立脚本认识 API。新建项目根目录的 `sync-invoker-demo.php`：

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use EasySwoole\SyncInvoker\AbstractDriver;
use EasySwoole\SyncInvoker\Config;
use EasySwoole\SyncInvoker\SyncInvoker;
use Swoole\Http\Request;
use Swoole\Http\Response;
use Swoole\Http\Server;

final class DemoDriver extends AbstractDriver
{
    public function plus(int $a, int $b): void
    {
        sleep(1); // 模拟阻塞式 SDK；这段代码在同步进程中执行。
        $this->response($a + $b);
    }
}

$config = new Config();
$config->setWorkerNum(2);
$config->setDriver(new DemoDriver());

$invoker = new SyncInvoker($config); // 构造时创建共享 Swoole\Table。
$server = new Server('127.0.0.1', 9502);
$invoker->attachServer($server); // 必须在 Server::start() 前执行，且只执行一次。

$server->on('request', static function (
    Request $request,
    Response $response
) use ($invoker): void {
    $result = $invoker->invoke(3.0)->plus(1, 2);
    $response->end((string) $result);
});

$server->start();
```

打开两个终端，分别执行：

```bash
php sync-invoker-demo.php
```

```bash
curl http://127.0.0.1:9502/
# 约一秒后输出：3
```

用 Ctrl+C 停止脚本。它会启动自己的 Swoole HTTP Server，不能与已有服务占用同一端口。`plus()` 的 PHP 返回类型是 `void`：跨进程返回值要通过 `$this->response()` 设置，而不是 `return $a + $b`。每次调用都要显式设置响应，包括业务失败分支；Driver 会在同一同步进程中复用，漏设响应可能返回前一次调用留下的值。`invoke(3.0)` 的超时单位是秒，指这一次调用从等待空闲进程到接收结果的总预算；默认是 15 秒。

接下来把相同结构放进框架项目：[在 EasySwoole 中接入](/Library/SyncInvoker/integration.md)。

## 源码依据

- [组件 README（2.2.3）](https://github.com/easy-swoole/sync-invoker/blob/2.2.3/README.md)
- [SyncInvoker（2.2.3）](https://github.com/easy-swoole/sync-invoker/blob/2.2.3/src/SyncInvoker.php)
