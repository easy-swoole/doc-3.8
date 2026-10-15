# TCP 服务

TCP 提供可靠、有序的字节流传输，适合设备长连接、内部网关和自定义二进制协议。TCP 没有消息边界，建立服务时必须先决定如何处理粘包和拆包。本章使用 Socket 2.x 自带的“4 字节长度头 + JSON 包体”协议。

## 协议格式

```text
+----------------------+----------------------+
| 4 字节包体长度（N）  | JSON 包体            |
+----------------------+----------------------+
```

长度字段使用网络字节序无符号整数。组件提供 `Protocol` 工具：

```php
use EasySwoole\Socket\Tools\Protocol;

$packet = Protocol::pack('{"action":"ping","args":{}}');
$json = Protocol::unpack($packet);
```

客户端和服务端必须使用完全一致的协议。不能一端添加长度头，另一端按换行符拆包。

## 创建 TCP 专用 Parser

基础章节中的 `JsonParser` 只处理 JSON。TCP 还需要负责移除请求长度头，并为响应添加长度头。新建 `App/Socket/TcpJsonParser.php`：

```php
<?php

namespace App\Socket;

use EasySwoole\Socket\AbstractInterface\ParserInterface;
use EasySwoole\Socket\Bean\Caller;
use EasySwoole\Socket\Bean\Response;
use EasySwoole\Socket\Client\Tcp;
use EasySwoole\Socket\Client\Udp;
use EasySwoole\Socket\Client\WebSocket;
use EasySwoole\Socket\Tools\Protocol;

final class TcpJsonParser implements ParserInterface
{
    private JsonParser $jsonParser;

    public function __construct()
    {
        $this->jsonParser = new JsonParser();
    }

    public function decode(string $raw, Tcp|Udp $client): ?Caller
    {
        if (!$client instanceof Tcp || $client instanceof WebSocket) {
            throw new \LogicException('TcpJsonParser only supports TCP');
        }

        return $this->jsonParser->decode(
            Protocol::unpack($raw),
            $client
        );
    }

    public function encode(Response $response, Tcp|Udp $client): ?string
    {
        if (!$client instanceof Tcp || $client instanceof WebSocket) {
            throw new \LogicException('TcpJsonParser only supports TCP');
        }

        $body = $this->jsonParser->encode($response, $client);

        return $body === null ? null : Protocol::pack($body);
    }
}
```

这里通过组合复用公共 `JsonParser`，TCP 协议细节只存在于 `TcpJsonParser`。以后 WebSocket 或 UDP 修改 JSON 结构时，不会意外套用 TCP 长度头。

## 配置 TCP 主服务

编辑项目根目录的 `dev.php` 和 `produce.php`：

```php
'MAIN_SERVER' => [
    'LISTEN_ADDRESS' => '0.0.0.0',
    'PORT' => 9502,
    'SERVER_TYPE' => EASYSWOOLE_SERVER,
    'SOCK_TYPE' => SWOOLE_TCP,
    'RUN_MODEL' => SWOOLE_PROCESS,
    'SETTING' => [
        'worker_num' => 4,
        'reload_async' => true,

        'open_length_check' => true,
        'package_length_type' => 'N',
        'package_length_offset' => 0,
        'package_body_offset' => 4,
        'package_max_length' => 4 * 1024 * 1024,

        'heartbeat_check_interval' => 30,
        'heartbeat_idle_time' => 90,
    ],
],
```

长度协议配置说明：

- `open_length_check`：让 Swoole 按长度字段组合完整数据包。
- `package_length_type`：`N` 表示读取 4 字节网络字节序整数。
- `package_length_offset`：长度字段从第 0 字节开始。
- `package_body_offset`：包体从第 4 字节开始。
- `package_max_length`：拒绝超过上限的数据包，避免异常长度耗尽内存。

启用长度检查后，`onReceive` 每次取得一个完整数据包，并且数据仍包含 4 字节长度头，所以 `TcpJsonParser` 会先调用 `Protocol::unpack()`。

## 注册 Receive 事件

下面使用的 `App\Socket\DispatcherFactory` 不是组件内置类，而是我们在[组件与协议基础](/Socket/index.md)中创建的项目辅助类，文件位置是 `App/Socket/DispatcherFactory.php`。它负责根据 Socket 类型和 Parser 创建 `Dispatcher`，并统一设置异常处理。

创建该类后，编辑 `EasySwooleEvent.php`：

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
        $dispatcher = DispatcherFactory::create(
            SocketType::TCP,
            new TcpJsonParser()
        );

        $register->add(
            EventRegister::onConnect,
            function (Server $server, int $fd, int $reactorId): void {
                // 建立连接后可以初始化连接状态，但此时通常尚未认证。
            }
        );

        $register->add(
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

        $register->add(
            EventRegister::onClose,
            function (Server $server, int $fd, int $reactorId): void {
                // 清理连接认证、订阅和设备在线状态。
            }
        );
    }
}
```

Dispatcher 会创建 `EasySwoole\Socket\Client\Tcp`，控制器可以读取当前连接的 fd 和 reactorId：

```php
$client = $this->caller()->getClient();
$fd = $client->getFd();
$reactorId = $client->getReactorId();
```

fd 只在当前 Server 生命周期中有效，连接关闭后可能被重新使用。

## 启动服务

监听类型发生变化时需要完整重启：

```bash
php easyswoole.php server stop
php easyswoole.php server start
```

确认端口：

```bash
lsof -nP -iTCP:9502 -sTCP:LISTEN
```

## 使用组件客户端测试

Socket 2.x 的 `Tools\Client` 会自动添加和移除 4 字节长度头。新建临时测试脚本 `tcp-client.php`：

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use EasySwoole\Socket\Tools\Client;
use Swoole\Coroutine;

Coroutine\run(function (): void {
    $client = new Client(
        unixSock: '127.0.0.1',
        port: 9502,
        timeout: 3.0,
        maxPackageLength: 4 * 1024 * 1024
    );

    $request = json_encode([
        'action' => 'echo',
        'args' => [
            'message' => 'hello tcp',
        ],
    ], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);

    $sentBytes = $client->send(
        $request,
        safeSend: true,
        timeout: 3.0
    );

    if ($sentBytes === false) {
        throw new RuntimeException('send failed');
    }

    $rawResponse = $client->recv(timeout: 3.0);

    if ($rawResponse === null) {
        throw new RuntimeException('receive timeout');
    }

    var_dump(json_decode(
        $rawResponse,
        true,
        64,
        JSON_THROW_ON_ERROR
    ));

    $client->close();
});
```

执行：

```bash
php tcp-client.php
```

`safeSend: true` 会循环发送，直到完整数据包写入、发送失败或超过整体超时。部分数据已发送后发生超时时，不能不加判断地重新发送整个业务请求，否则服务端可能重复处理。

## 使用其他语言客户端

非 PHP 客户端也必须先把 JSON 编码成字节，再在前面添加 4 字节大端序长度。伪代码：

```text
body = utf8(json)
packet = uint32_big_endian(length(body)) + body
socket.write_all(packet)
```

读取时先精确读取 4 字节，解析长度，再精确读取对应数量的包体字节。一次普通 `read()` 不保证返回完整数据。

## 主动响应和关闭

普通控制器响应由 Dispatcher 自动调用 `Server::send()`。需要提前发送时：

```php
$sent = $this->responseImmediately(
    \EasySwoole\Socket\Tools\Protocol::pack('immediate message')
);
```

`responseImmediately()` 不会经过 Parser 的 `encode()`，因此使用长度协议时必须自行封包。

需要发送最终响应后关闭连接：

```php
use EasySwoole\Socket\Enum\ResponseStatus;

$this->response()->setMessage(['message' => 'bye']);
$this->response()->setStatus(ResponseStatus::RESPONSE_AND_CLOSE);
```

需要直接重置 TCP 连接：

```php
$this->response()->setReset(true);
$this->response()->setStatus(ResponseStatus::CLOSE);
```

## 连接认证

TCP 建立连接不等于完成业务认证。常见做法是要求第一条数据包为登录请求，认证成功后把用户或设备信息与 fd 绑定。后续 Action 在 `onRequest()` 中检查连接状态。

多 Worker 环境不能只使用普通静态数组保存所有连接。单机可以使用 Swoole Table，多实例使用 Redis 或其他共享存储，并保存节点 ID 与连接版本。

## 注意事项

- TCP 是字节流，任何业务协议都必须明确消息边界。
- 服务端、客户端、Parser 的封包方式必须一致。
- 限制 `package_max_length`，并同时限制 JSON 深度和业务字段大小。
- 所有连接都应配置认证超时、空闲超时和心跳策略。
- 不要在 `onReceive` 中执行阻塞 I/O 或无限循环。
- 写操作可能只发送部分数据，客户端应使用完整写入逻辑。
- 请求超时不代表服务端没有处理，重试型写操作必须保证幂等。
- 修改端口、Socket 类型或拆包配置后需要完整重启服务。

## 源码依据

- [TCP 分发入口](https://github.com/easy-swoole/socket/blob/2.x/src/Dispatcher.php)
- [Protocol](https://github.com/easy-swoole/socket/blob/2.x/src/Tools/Protocol.php)
- [协程客户端](https://github.com/easy-swoole/socket/blob/2.x/src/Tools/Client.php)
