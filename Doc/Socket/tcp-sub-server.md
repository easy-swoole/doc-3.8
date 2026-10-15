# TCP 子服务

一个 EasySwoole 进程可以同时监听多个端口。例如，主服务继续在 `9501` 提供 HTTP 或 WebSocket 服务，再增加一个监听 `9502` 的 TCP 子服务。两个端口共用同一个 Swoole Server 和 Worker 进程，但可以分别注册事件和设置通信协议。

```text
同一个 EasySwoole 进程
├── 主服务  0.0.0.0:9501  HTTP/WebSocket
└── 子服务  0.0.0.0:9502  TCP
```

TCP 子服务不是再启动一个独立进程，而是在主 Swoole Server 上通过 `addListener()` 多监听一个端口。

## 使用场景

TCP 子服务适合以下场景：

- HTTP API 与设备 TCP 长连接由同一套业务代码处理。
- WebSocket 服务之外，再为内部系统提供 TCP 协议入口。
- 同一个服务需要监听多个 TCP 端口，并为每个端口使用不同协议配置。

如果两个服务需要独立扩容、独立重启、使用不同 Worker 数量或相互隔离阻塞风险，更适合拆成两个独立服务，而不是使用子服务。

## 前置代码

本章继续使用[组件与协议基础](/Socket/index.md)和 [TCP 服务](/Socket/tcp.md)中的代码：

- `App\Socket\TcpJsonParser`：处理 4 字节长度头和 JSON 包体。
- `App\Socket\DispatcherFactory`：在 `App/Socket/DispatcherFactory.php` 中自定义的项目辅助类，用于创建 Socket Dispatcher；它不是组件内置类。
- `App\Socket\EchoController`：处理 `echo`、`ping` 等 Action。

客户端协议仍是“4 字节网络字节序长度 + JSON 包体”。如果尚未创建这些类，请先完成 TCP 服务章节中的 Parser 和控制器示例。

## 在 mainServerCreate 中增加监听端口

编辑项目根目录的 `EasySwooleEvent.php`，在 `mainServerCreate()` 中调用 `ServerManager::addServer()`：

```php
<?php

namespace EasySwoole\EasySwoole;

use App\Socket\DispatcherFactory;
use App\Socket\TcpJsonParser;
use EasySwoole\EasySwoole\AbstractInterface\Event;
use EasySwoole\EasySwoole\Swoole\EventRegister;
use EasySwoole\Socket\Enum\SocketType;
use Swoole\Server;

class EasySwooleEvent implements Event
{
    public static function initialize(): void
    {
        date_default_timezone_set('Asia/Shanghai');
    }

    public static function mainServerCreate(EventRegister $register): void
    {
        $tcpRegister = ServerManager::getInstance()->addServer(
            serverName: 'tcp-device',
            port: 9502,
            type: SWOOLE_TCP,
            listenAddress: '0.0.0.0',
            setting: [
                'open_length_check' => true,
                'package_length_type' => 'N',
                'package_length_offset' => 0,
                'package_body_offset' => 4,
                'package_max_length' => 4 * 1024 * 1024,
            ]
        );

        $dispatcher = DispatcherFactory::create(
            SocketType::TCP,
            new TcpJsonParser()
        );

        $tcpRegister->add(
            EventRegister::onConnect,
            function (Server $server, int $fd, int $reactorId): void {
                // 此处只表示 TCP 已连接，通常还需要等待设备登录包。
            }
        );

        $tcpRegister->add(
            EventRegister::onReceive,
            function (
                Server $server,
                int $fd,
                int $reactorId,
                string $data
            ) use ($dispatcher): void {
                $dispatcher->dispatchTcp(
                    $server,
                    $data,
                    $fd,
                    $reactorId
                );
            }
        );

        $tcpRegister->add(
            EventRegister::onClose,
            function (Server $server, int $fd, int $reactorId): void {
                // 清理该 fd 对应的设备登录状态和订阅关系。
            }
        );

        // $register 仍是主服务的事件注册器。
        // 原有 HTTP/WebSocket 主服务逻辑继续注册到 $register。
    }
}
```

`addServer()` 的参数含义如下：

| 参数 | 说明 |
| --- | --- |
| `serverName` | 子服务唯一名称，后续可以通过名称取得监听端口对象 |
| `port` | 新增的监听端口，这里是 `9502` |
| `type` | Socket 类型，TCP 使用 `SWOOLE_TCP` |
| `listenAddress` | 监听地址；`0.0.0.0` 表示监听所有 IPv4 网卡 |
| `setting` | 只应用于该监听端口的协议配置 |

`ServerManager::addServer()` 内部会调用主 Swoole Server 的 `addListener()`，并返回这个子服务专用的 `EventRegister`。因此，TCP 子服务的 `connect`、`receive` 和 `close` 事件应注册到 `$tcpRegister`，不能注册到代表主服务的 `$register`。

## 为什么不直接调用 addListener

直接取得 Swoole Server 后也能调用底层 API：

```php
$server = ServerManager::getInstance()->getSwooleServer();
$port = $server->addListener('0.0.0.0', 9502, SWOOLE_TCP);
```

但是在 EasySwoole 项目中，推荐使用 `ServerManager::addServer()`。它除了调用 `addListener()`，还会保存子服务名称、监听端口和独立的事件注册器。框架启动时会自动把 `$tcpRegister` 中的回调绑定到对应的 `Swoole\Server\Port`。

如果绕过 `addServer()`，就需要自行调用 `$port->set()` 和 `$port->on()` 完成所有配置与事件绑定，也无法通过 EasySwoole 的服务名称取得该端口。

## 获取子服务端口对象

需要读取或操作子服务端口对象时，可以使用注册时的名称：

```php
use EasySwoole\EasySwoole\ServerManager;
use Swoole\Server\Port;

$tcpPort = ServerManager::getInstance()
    ->getSwooleServer('tcp-device');

if ($tcpPort instanceof Port) {
    // $tcpPort 是 9502 对应的 Swoole\Server\Port。
}
```

发送数据时仍使用事件回调传入的主 `Server` 对象：

```php
$server->send($fd, $packet);
```

不要把 `Swoole\Server\Port` 当作一个独立 Server；连接管理、发送数据和 Worker 生命周期仍由主 Server 负责。

## 同时增加多个 TCP 子服务

每个端口调用一次 `addServer()`，并使用不同的服务名称：

```php
$deviceRegister = ServerManager::getInstance()->addServer(
    'tcp-device',
    9502,
    SWOOLE_TCP,
    '0.0.0.0',
    $deviceSettings
);

$internalRegister = ServerManager::getInstance()->addServer(
    'tcp-internal',
    9503,
    SWOOLE_TCP,
    '127.0.0.1',
    $internalSettings
);
```

两个端口可以使用不同的拆包设置和不同的 Parser。不要复用协议不一致的 Dispatcher，例如一个端口使用长度头、另一个端口使用换行符时，应分别创建对应的 Parser 和 Dispatcher。

## 启动和测试

新增监听端口后需要完整重启，不能只 reload Worker：

```bash
php easyswoole.php server stop
php easyswoole.php server start
```

确认主端口和 TCP 子服务端口都在监听：

```bash
lsof -nP -iTCP:9501 -sTCP:LISTEN
lsof -nP -iTCP:9502 -sTCP:LISTEN
```

随后可以直接使用 [TCP 服务](/Socket/tcp.md)中的组件客户端，把连接端口改为 `9502`：

```php
$client = new \EasySwoole\Socket\Tools\Client(
    unixSock: '127.0.0.1',
    port: 9502,
    timeout: 3.0,
    maxPackageLength: 4 * 1024 * 1024
);
```

## 配置与部署注意事项

- 子服务必须在 Server 启动前添加，因此应放在 `mainServerCreate()` 中，不能等到 Worker 启动后再动态增加端口。
- `worker_num`、`task_worker_num`、进程模式等属于主 Server 配置，不能为每个子端口单独设置。
- `open_length_check`、`package_length_type` 和 `package_max_length` 等协议配置可以设置在子端口上。
- 主服务与子服务共享 Worker。TCP 回调中的阻塞操作同样会影响同一批 Worker 处理其他端口的请求。
- `serverName` 必须保持唯一；重复名称会导致后注册的子服务覆盖框架保存的名称映射。
- 对外开放新端口时，还需要同步配置防火墙、安全组、容器端口映射和反向代理或四层负载均衡。
- 多端口共用同一套 fd 空间，连接关闭后 fd 仍可能被复用；业务身份不能只保存一个永久 fd。

## 源码依据

- [EasySwoole ServerManager](https://github.com/easy-swoole/easyswoole/blob/3.x/src/ServerManager.php)
- [Socket TCP Dispatcher](https://github.com/easy-swoole/socket/blob/2.x/src/Dispatcher.php)
- [Socket TCP 客户端信息](https://github.com/easy-swoole/socket/blob/2.x/src/Client/Tcp.php)
