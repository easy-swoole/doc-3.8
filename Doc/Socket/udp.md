# UDP 服务

UDP 是无连接的数据报协议。每个数据报天然保留消息边界，不存在 TCP 粘包问题，但它不保证送达、顺序或只到达一次。UDP 适合允许少量丢包的状态上报、局域网发现和低延迟通信，不适合直接承载扣款、订单创建等必须可靠完成的业务。

## 配置 UDP 主服务

编辑项目根目录的 `dev.php` 和 `produce.php`：

```php
'MAIN_SERVER' => [
    'LISTEN_ADDRESS' => '0.0.0.0',
    'PORT' => 9503,
    'SERVER_TYPE' => EASYSWOOLE_SERVER,
    'SOCK_TYPE' => SWOOLE_UDP,
    'RUN_MODEL' => SWOOLE_PROCESS,
    'SETTING' => [
        'worker_num' => 4,
        'reload_async' => true,
        'package_max_length' => 64 * 1024,
    ],
],
```

关键区别是 `SOCK_TYPE` 使用 `SWOOLE_UDP`。UDP 没有连接建立和关闭事件，主要处理 `onPacket`。

生产环境还需要在主机防火墙、云安全组和容器端口映射中开放 UDP 9503。只开放同端口的 TCP 规则不会放行 UDP 数据报。

## 注册 Packet 事件

下面使用的 `App\Socket\DispatcherFactory` 不是组件内置类，而是我们在[组件与协议基础](/Socket/index.md)中创建的项目辅助类，文件位置是 `App/Socket/DispatcherFactory.php`。UDP 示例没有单独传入 Parser，因此工厂会使用基础章节创建的 `JsonParser`。

创建上述辅助类后，编辑 `EasySwooleEvent.php`：

```php
<?php

namespace EasySwoole\EasySwoole;

use App\Socket\DispatcherFactory;
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
        $dispatcher = DispatcherFactory::create(SocketType::UDP);

        $register->add(
            EventRegister::onPacket,
            function (
                Server $server,
                string $data,
                array $clientInfo
            ) use ($dispatcher): void {
                $dispatcher->dispatchUdp(
                    $server,
                    $data,
                    $clientInfo['server_socket'],
                    $clientInfo['address'],
                    $clientInfo['port']
                );
            }
        );
    }
}
```

`dispatchUdp()` 需要四项客户端信息：

- `server_socket`：收到数据报的服务端 Socket。
- `address`：客户端 IP 地址。
- `port`：客户端源端口。
- `$data`：完整数据报内容。

Dispatcher 会创建 `EasySwoole\Socket\Client\Udp`。Parser 不需要调用 `Protocol::unpack()`，因为 UDP 数据报本身已经有边界。

## 启动服务

```bash
php easyswoole.php server stop
php easyswoole.php server start
```

查看 UDP 监听：

```bash
lsof -nP -iUDP:9503
```

## 使用 PHP 客户端测试

新建临时脚本 `udp-client.php`：

```php
<?php

$socket = stream_socket_client(
    'udp://127.0.0.1:9503',
    $errorCode,
    $errorMessage,
    3
);

if ($socket === false) {
    throw new RuntimeException(
        "connect failed: [{$errorCode}] {$errorMessage}"
    );
}

stream_set_timeout($socket, 3);

$request = json_encode([
    'action' => 'echo',
    'args' => [
        'message' => 'hello udp',
    ],
], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);

if (fwrite($socket, $request) === false) {
    throw new RuntimeException('send failed');
}

$response = fread($socket, 64 * 1024);
$metadata = stream_get_meta_data($socket);

if ($metadata['timed_out']) {
    throw new RuntimeException('receive timeout');
}

var_dump(json_decode(
    $response,
    true,
    64,
    JSON_THROW_ON_ERROR
));

fclose($socket);
```

执行：

```bash
php udp-client.php
```

也可以使用 netcat 发送一个数据报：

```bash
printf '%s' '{"action":"ping","args":{}}' \
  | nc -u -w 3 127.0.0.1 9503
```

不同系统的 `nc` 参数略有差异。如果命令立即退出或收不到响应，优先使用 PHP 示例确认协议与端口。

## UDP 响应方式

控制器完成后，Dispatcher 会调用：

```php
$server->sendto(
    $client->getAddress(),
    $client->getPort(),
    $encodedData,
    $client->getServerSocket()
);
```

这意味着响应会发送到当前数据报的源地址和源端口。客户端经过 NAT 时，服务端看到的是 NAT 映射后的地址，不能把它当作稳定身份。

控制器中也可以立即发送：

```php
$sent = $this->responseImmediately(
    json_encode(['type' => 'received'], JSON_THROW_ON_ERROR)
);
```

`responseImmediately()` 直接调用 `sendto()`，不会经过 Parser 的 `encode()`。业务需要自行保证返回格式一致。

## 无响应数据报

状态上报类消息可能不需要回复：

```php
use EasySwoole\Socket\Enum\ResponseStatus;

$this->response()->setStatus(ResponseStatus::WITHOUT_RESPONSE);
```

对于 UDP：

- `OK` 和 `RESPONSE_AND_CLOSE` 都只发送响应，不存在关闭连接。
- `WITHOUT_RESPONSE` 和 `CLOSE` 都不发送响应。

客户端如果要求确认，应在业务协议中增加消息 ID和确认消息，而不是依赖 UDP 连接状态。

## 可靠性设计

UDP 可能发生：

- 数据报丢失。
- 重复到达。
- 到达顺序变化。
- 数据报过大而被 IP 分片，其中任一分片丢失会导致整个数据报不可用。

需要应用层可靠性时，协议至少应包含：

```json
{
  "messageId": "device-10-000123",
  "timestamp": 1791993600,
  "action": "report",
  "args": {}
}
```

服务端根据 `messageId` 去重，客户端在超时后有限次数重发，并采用退避策略。即使增加确认和重试，也不要假设 UDP 能自然达到 TCP 的可靠性；复杂可靠传输通常应直接选择 TCP 或成熟的消息协议。

## 安全与来源校验

UDP 源地址可能被伪造，服务端不能仅凭 IP 和端口认定身份。公网 UDP 服务应考虑：

- 对消息增加时间戳、随机数和签名。
- 限制单个来源的频率和数据报大小。
- 避免返回远大于请求的数据，防止成为反射放大攻击入口。
- 在解析 JSON 前先限制原始数据长度。
- 不向未认证请求返回敏感信息。

## 注意事项

- UDP 没有 `onConnect` 和 `onClose`，不要维护虚假的长连接状态。
- 一个 `packet` 对应一个数据报，不要使用 TCP 长度头封包。
- 数据报应尽量小，避免 IP 分片。
- 重要写操作必须设计消息 ID、幂等和确认机制，或改用 TCP。
- 客户端超时只表示没有收到响应，不代表服务端一定没有执行。
- 多 Worker 和多实例下的去重状态需要使用共享存储。
- 防火墙、安全组和容器映射必须明确使用 UDP 协议。

## 源码依据

- [UDP 分发入口](https://github.com/easy-swoole/socket/blob/2.x/src/Dispatcher.php)
- [UDP 客户端信息](https://github.com/easy-swoole/socket/blob/2.x/src/Client/Udp.php)
- [SocketType](https://github.com/easy-swoole/socket/blob/2.x/src/Enum/SocketType.php)
