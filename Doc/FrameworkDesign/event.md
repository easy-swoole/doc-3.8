# 事件注册

EasySwoole 没有要求项目直接调用 `$server->on()`，而是把 `EventRegister` 交给 `EasySwooleEvent::mainServerCreate()`。项目先把回调保存到注册器中，服务启动前再由 `ServerManager` 统一绑定到 Swoole Server。

## 两个项目级生命周期方法

安装框架后，项目根目录会生成 `EasySwooleEvent.php`：

```php
<?php

namespace EasySwoole\EasySwoole;

use EasySwoole\EasySwoole\AbstractInterface\Event;
use EasySwoole\EasySwoole\Swoole\EventRegister;

class EasySwooleEvent implements Event
{
    public static function initialize()
    {
        // Server 尚未创建
    }

    public static function mainServerCreate(EventRegister $register)
    {
        // Server 已创建，但尚未 start
    }
}
```

执行顺序是：

```text
加载 produce.php/dev.php
  → EasySwooleEvent::initialize()
  → 创建 Swoole Server
  → EasySwooleEvent::mainServerCreate($register)
  → 框架注册默认回调和组件
  → ServerManager 将回调绑定到 Swoole
  → Swoole Server start
```

## `initialize()` 适合做什么

调用 `initialize()` 时配置已经加载，`Temp` 和 `Log` 目录已经初始化，但 Swoole Server 尚不存在。适合：

- 设置时区和协程全局参数。
- 向 DI 注册业务对象或框架钩子。
- 替换日志、异常等全局处理器。
- 加载只需要定义、不需要建立网络连接的配置。

不建议在这里创建仅供 Worker 使用的数据库长连接。Swoole 后续创建多进程时，跨进程复用启动前连接容易造成协议数据错乱。进程私有资源通常应在 `onWorkerStart` 中建立。

## `mainServerCreate()` 如何注册事件

例如注册 Worker 启动和关闭事件：

```php
use EasySwoole\EasySwoole\Swoole\EventRegister;
use Swoole\Server;

public static function mainServerCreate(EventRegister $register)
{
    $register->add(
        EventRegister::onWorkerStart,
        function (Server $server, int $workerId): void {
            if ($server->taskworker) {
                echo "TaskWorker {$workerId} started\n";
                return;
            }

            echo "Worker {$workerId} started\n";
        }
    );

    $register->add(
        EventRegister::onWorkerStop,
        function (Server $server, int $workerId): void {
            echo "Worker {$workerId} stopped\n";
        }
    );
}
```

常用事件常量包括：

| 常量 | Swoole 事件 | 典型用途 |
| --- | --- | --- |
| `onStart` | `start` | Master 启动后记录状态 |
| `onShutdown` | `shutdown` | 服务整体关闭后的清理 |
| `onManagerStart` | `managerStart` | Manager 初始化 |
| `onWorkerStart` | `workerStart` | 初始化 Worker 私有资源 |
| `onWorkerStop` | `workerStop` | Worker 停止清理 |
| `onWorkerExit` | `workerExit` | 异步重载时清理事件循环资源 |
| `onConnect` | `connect` | TCP 客户端建立连接 |
| `onReceive` | `receive` | TCP 数据到达 |
| `onClose` | `close` | 连接关闭 |
| `onRequest` | `request` | HTTP 请求到达 |
| `onOpen` | `open` | WebSocket 连接建立 |
| `onMessage` | `message` | WebSocket 消息到达 |
| `onTask`、`onFinish` | `task`、`finish` | Swoole Task 任务处理 |

不同 Server 类型支持的事件不同。例如普通 HTTP 服务主要使用 `request`，WebSocket 服务才会使用 `open` 和 `message`。

## `add()` 与 `set()` 的区别

一个 Swoole 事件通常只能向原生 Server 注册一次，但框架和业务可能都需要监听同一事件。`EventRegister` 使用多回调容器解决这个问题：

```php
// 在该事件已有回调的基础上追加
$register->add(EventRegister::onWorkerStart, $callback);

// 设置该事件的回调集合；可能影响此前保存的内容
$register->set(EventRegister::onWorkerStart, $callback);
```

业务通常应使用 `add()`，避免意外覆盖同一事件的已有回调。

在 `ServerManager::start()` 中，框架会为每个事件执行一次原生 `on()`，再在包装函数里依次调用注册器保存的多个回调：

```php
$server->on($event, function (...$args) use ($callbacks) {
    foreach ($callbacks as $callback) {
        $callback(...$args);
    }
});
```

因此同一事件中的某个回调如果执行阻塞操作，也会延迟后续回调。

## 框架默认事件何时加入

`Core::createServer()` 的相关顺序是：

```text
1. 创建原生 Swoole Server
2. EasySwooleEvent::mainServerCreate($register)
3. Core::registerDefaultCallBack()
4. Core::extraHandler()
```

默认回调包括：

- HTTP/HTTP-WebSocket Server 的 `request` 分发。
- `workerStart` 中的进程命名、进程表和内存心跳。
- `workerStop`、`workerExit` 的 Timer 与事件循环清理。
- `managerStart` 的进程命名。

`extraHandler()` 还会把 Task、Process Manager、Bridge 和 Crontab 挂载到 Server，这些组件也可能继续注册服务事件。

## HTTP 请求事件为什么一般不用自己注册

对于 HTTP Server，框架默认注册的 `request` 回调会：

```text
Swoole Request/Response
  → EasySwoole Request/Response 封装
  → HTTP_GLOBAL_ON_REQUEST
  → Dispatcher 路由与控制器
  → HTTP_GLOBAL_AFTER_REQUEST
  → 发送响应
```

业务需要全局 HTTP 前后置逻辑时，优先使用框架提供的全局 HTTP 事件；需要控制器鉴权时使用控制器 `onRequest()`。直接追加底层 `onRequest` 容易与框架的请求分发职责重叠。参见[HTTP 事件](/Http/Basics/events.md)和[鉴权与拦截](/Http/Middleware/global.md)。

## 注册子服务事件

通过 `ServerManager::addServer()` 增加监听端口时，会为子服务单独创建 `EventRegister`：

```php
$subRegister = ServerManager::getInstance()->addServer(
    'tcp-service',
    9502,
    SWOOLE_TCP,
    '0.0.0.0'
);

$subRegister->add(EventRegister::onReceive, function (
    Server $server,
    int $fd,
    int $reactorId,
    string $data
): void {
    $server->send($fd, "received: {$data}");
});
```

主服务和子服务的注册器彼此独立。服务启动时，`ServerManager` 会先绑定主服务事件，再逐个绑定子服务事件。

## 源码依据

- [EasySwooleEvent 模板](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Resource/EasySwooleEvent._php)
- [EventRegister](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Swoole/EventRegister.php)
- [EventHelper](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Swoole/EventHelper.php)
- [Core 默认回调](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Core.php)
