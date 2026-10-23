# WebSocket 服务

WebSocket 在一次 HTTP Upgrade 握手后建立长连接，服务端和客户端都可以主动发送消息。它适合聊天、实时通知、在线协作和状态推送，不适合普通的一问一答接口。

本章实现一个可以直接测试的 WebSocket Echo 服务：

```text
客户端连接 ws://127.0.0.1:9501/ws?token=demo-token
    ↓
服务端检查路径、Origin 和 Token
    ↓
连接成功后发送欢迎消息
    ↓
客户端发送 JSON
    ↓
服务端返回 JSON
    ↓
连接关闭时清理状态
```

## 第一步：启用 WebSocket 主服务

开发环境配置位于项目根目录 `dev.php`，生产环境通常是 `produce.php`。把 `MAIN_SERVER.SERVER_TYPE` 改为 WebSocket 类型。下面只展示相关配置，项目原有的 `TASK`、`LOG` 等配置应继续保留：

```php
<?php

return [
    'SERVER_NAME' => 'EasySwoole',
    'MAIN_SERVER' => [
        'LISTEN_ADDRESS' => '0.0.0.0',
        'PORT' => 9501,
        'SERVER_TYPE' => EASYSWOOLE_WEB_SOCKET_SERVER,
        'SOCK_TYPE' => SWOOLE_TCP,
        'RUN_MODEL' => SWOOLE_PROCESS,
        'SETTING' => [
            'worker_num' => 4,
            'reload_async' => true,
            'heartbeat_check_interval' => 30,
            'heartbeat_idle_time' => 90,
            'package_max_length' => 2 * 1024 * 1024,
        ],
    ],
];
```

`EASYSWOOLE_WEB_SOCKET_SERVER` 使用 `Swoole\\WebSocket\\Server`。它同时具备 HTTP Server 能力，所以项目原有 Router 和 Controller 仍然可以继续工作。

配置含义：

- `heartbeat_check_interval`：Swoole 多久检查一次空闲连接。
- `heartbeat_idle_time`：连接多久没有数据后视为空闲并关闭。
- `package_max_length`：限制单条消息最大长度，避免超大消息耗尽内存。

修改 Server 类型后应完整重启，不能只 reload Worker：

```bash
php easyswoole.php server stop
php easyswoole.php server start
```

## 第二步：注册 WebSocket 事件

事件写在项目根目录 `EasySwooleEvent.php` 的 `mainServerCreate()` 中，不写在 HTTP Router 或 Controller 中。

下面保留文件必要结构，并注册 Open、Message、Close 三个事件：

```php
<?php

namespace EasySwoole\EasySwoole;

use EasySwoole\EasySwoole\AbstractInterface\Event;
use EasySwoole\EasySwoole\Swoole\EventRegister;
use Swoole\Http\Request;
use Swoole\WebSocket\Frame;
use Swoole\WebSocket\Server;

class EasySwooleEvent implements Event
{
    public static function initialize(): void
    {
        date_default_timezone_set('Asia/Shanghai');
    }

    public static function mainServerCreate(EventRegister $register): void
    {
        $register->add(
            EventRegister::onOpen,
            function (Server $server, Request $request): void {
                $fd = $request->fd;
                $path = $request->server['request_uri'] ?? '/';
                $origin = $request->header['origin'] ?? '';
                $token = $request->get['token'] ?? '';

                // 只允许 /ws 建立 WebSocket 业务连接。
                if ($path !== '/ws') {
                    $server->disconnect($fd, 1008, 'invalid path');
                    return;
                }

                $allowedOrigins = [
                    'http://localhost:3000',
                    'https://admin.example.com',
                ];
                if ($origin !== '' && !in_array($origin, $allowedOrigins, true)) {
                    $server->disconnect($fd, 1008, 'origin denied');
                    return;
                }

                // 演示用固定 Token；生产项目应调用认证服务。
                if (!hash_equals('demo-token', (string) $token)) {
                    $server->disconnect($fd, 1008, 'unauthorized');
                    return;
                }

                // 握手已由 Swoole 完成（HTTP 101）；这里发送的是 WebSocket 消息帧。
                $server->push($fd, json_encode([
                    'type' => 'connected',
                    'fd' => $fd,
                ], JSON_UNESCAPED_UNICODE));
            }
        );

        $register->add(
            EventRegister::onMessage,
            function (Server $server, Frame $frame): void {
                if (strlen($frame->data) > 64 * 1024) {
                    $server->disconnect($frame->fd, 1009, 'message too large');
                    return;
                }

                try {
                    $message = json_decode(
                        $frame->data,
                        true,
                        64,
                        JSON_THROW_ON_ERROR
                    );
                } catch (\JsonException $exception) {
                    $server->push($frame->fd, json_encode([
                        'type' => 'error',
                        'message' => '消息必须是 JSON',
                    ], JSON_UNESCAPED_UNICODE));
                    return;
                }

                $server->push($frame->fd, json_encode([
                    'type' => 'echo',
                    'data' => $message,
                    'time' => time(),
                ], JSON_UNESCAPED_UNICODE));
            }
        );

        $register->add(
            EventRegister::onClose,
            function (Server $server, int $fd, int $reactorId): void {
                // 清理 fd 对应的订阅、房间和在线状态。
                // Close 也可能由普通 TCP/HTTP 连接触发，清理逻辑应具备幂等性。
            }
        );
    }
}
```

这里使用 `$register->add()`，允许框架或其他组件继续追加同类事件。`set()` 会替换该事件已有回调，除非明确需要覆盖，否则优先使用 `add()`。

## WebSocket 事件分别做什么

### `onOpen`

WebSocket 握手成功后才触发。默认握手由 Swoole 完成，客户端已经收到 HTTP `101 Switching Protocols`；`onOpen` 不需要、也不能再返回一次 101。上例的 `$server->push()` 发送的是连接建立后的第一条 WebSocket 消息，不是握手响应，因此可以在这里直接调用。若不需要欢迎消息，删掉这次 `push()` 即可，不影响连接建立。

执行顺序为：客户端发送 HTTP Upgrade 请求 → Swoole 完成握手并返回 101 → 触发 `onOpen` → 可调用 `push()` 发送消息。`onOpen` 回调的 `void` 返回值也不决定握手是否通过。

`onOpen` 适合读取连接路径、Origin、Token，并建立用户与 fd 的映射；但此时检查失败只能通过 `disconnect()` 关闭已经升级的连接，不能再把握手响应改成 401 或 403。要在升级前拒绝请求，应在握手阶段处理。

示例为了便于测试，从 Query 读取 Token。生产环境需要避免 Token 长期出现在 URL 和代理日志中，可使用：

- 短期、一次性的连接票据。
- 安全 Cookie，并配合严格 Origin 检查。
- 客户端连接后发送认证消息，在认证完成前禁止业务操作。

在 `onOpen` 中拒绝连接意味着握手已经完成后再断开。若必须在 HTTP Upgrade 阶段直接拒绝，使用下面的 `onHandShake`。

### `onHandShake`：升级前拒绝连接

只有需要在握手阶段返回 HTTP 错误状态（例如无效 Token 返回 403）时，才需要自定义握手。`onHandShake` 的回调参数是 `Swoole\Http\Request` 和 `Swoole\Http\Response`，与 `onOpen` 的 `Server`、`Request` 不同。

在 `EasySwooleEvent.php` 的 `mainServerCreate()` 中，用下面的注册代码**替换**前文整个 `onOpen` 注册块；保留 `onMessage` 和 `onClose`。文件顶部另加 `use Swoole\Http\Response;`：

```php
$register->add(
    EventRegister::onHandShake,
    function (Request $request, Response $response): void {
        $path = $request->server['request_uri'] ?? '/';
        $origin = $request->header['origin'] ?? '';
        $token = $request->get['token'] ?? '';

        if ($path !== '/ws') {
            $response->status(404);
            $response->end('Not Found');
            return;
        }

        $allowedOrigins = [
            'http://localhost:3000',
            'https://admin.example.com',
        ];
        if ($origin !== '' && !in_array($origin, $allowedOrigins, true)) {
            $response->status(403);
            $response->end('Forbidden');
            return;
        }

        // 演示用固定 Token；生产项目应验证短期连接票据。
        if (!is_string($token) || !hash_equals('demo-token', $token)) {
            $response->status(403);
            $response->end('Forbidden');
            return;
        }

        // 接管默认握手后，必须自行检查请求并生成协议要求的响应头。
        $key = $request->header['sec-websocket-key'] ?? '';
        $version = $request->header['sec-websocket-version'] ?? '';
        $upgrade = $request->header['upgrade'] ?? '';
        $connection = $request->header['connection'] ?? '';
        $decodedKey = is_string($key) ? base64_decode($key, true) : false;

        if ($version !== '13'
            || !is_string($upgrade) || strcasecmp($upgrade, 'websocket') !== 0
            || !is_string($connection)
            || !preg_match('/(?:^|,)\s*upgrade\s*(?:,|$)/i', $connection)
            || $decodedKey === false || strlen($decodedKey) !== 16
            || base64_encode($decodedKey) !== $key
        ) {
            $response->status(400);
            $response->end('Bad WebSocket handshake');
            return;
        }

        $accept = base64_encode(sha1(
            $key . '258EAFA5-E914-47DA-95CA-C5AB0DC85B11',
            true
        ));
        $response->header('Upgrade', 'websocket');
        $response->header('Connection', 'Upgrade');
        $response->header('Sec-WebSocket-Accept', $accept);
        $response->status(101);
        $response->end();
    }
);
```

失败分支以 4xx 响应结束 HTTP 请求，连接不会升级；成功分支发送握手头及 `101 Switching Protocols`，随后才能收发 WebSocket 消息。这里不要调用 `push()`：此时握手尚未结束。自定义 `onHandShake` 后，Swoole 不会自动触发 `onOpen`，所以前文的欢迎消息也不会发送；如需欢迎消息，应在成功握手后另行安排发送，而不是继续依赖原来的 `onOpen`。框架的 `EventRegister` 会依次调用同名事件回调并忽略其返回值，因此务必通过 `$response->status()` 和 `$response->end()` 完成响应，不要仅靠回调 `return true/false` 决定握手结果。一个握手事件也应只注册一个实际负责响应的处理器，避免重复输出。

此示例未协商 WebSocket 子协议或扩展。如果业务需要 `Sec-WebSocket-Protocol` 等能力，必须按客户端请求和协议规则补齐协商，不能直接回显任意请求头。浏览器 WebSocket API 无法随意设置 `Authorization` 请求头；示例用 Query Token 仅为便于测试，生产中宜使用短期票据或结合 Origin 检查的安全 Cookie。

### `onMessage`

客户端每发送一个 WebSocket Frame 都会触发。`$frame->fd` 是连接标识，`$frame->data` 是消息内容。

生产消息建议使用固定信封：

```json
{
  "id": "msg-1001",
  "type": "chat.send",
  "data": {
    "roomId": 10,
    "content": "hello"
  }
}
```

服务端应验证 JSON、消息类型、字段、权限、大小和频率。不要根据客户端传入的 userId 判断身份，应使用连接认证阶段建立的服务端身份映射。

发送前可判断连接状态：

```php
if ($server->isEstablished($fd)) {
    $server->push($fd, $json);
}
```

### `onClose`

连接关闭时清理用户-fd 映射、房间订阅和在线状态。网络断开、心跳超时、服务端主动断开都会进入清理流程，所以逻辑必须可重复执行。

fd 只是当前 Swoole Server 进程生命周期中的连接编号，断开后可能被复用，不能作为永久用户 ID 或数据库业务主键。

## 第三步：使用客户端测试

浏览器控制台：

```javascript
const socket = new WebSocket(
  "ws://127.0.0.1:9501/ws?token=demo-token"
);

socket.addEventListener("open", () => {
  console.log("connected");
  socket.send(JSON.stringify({ type: "ping", data: "hello" }));
});

socket.addEventListener("message", (event) => {
  console.log("message", JSON.parse(event.data));
});

socket.addEventListener("close", (event) => {
  console.log("closed", event.code, event.reason);
});

socket.addEventListener("error", (event) => {
  console.error("websocket error", event);
});
```

也可以安装 `wscat` 测试：

```bash
wscat -c 'ws://127.0.0.1:9501/ws?token=demo-token' \
  -H 'Origin: http://localhost:3000'
```

连接后输入：

```json
{"type":"ping","data":"hello"}
```

应收到 `type=echo` 的 JSON 响应。

## 心跳与保活

Swoole 的 `heartbeat_idle_time` 根据连接最近一次收到数据的时间清理空闲连接。应用层还可以约定 ping/pong 消息：

```php
if (($message['type'] ?? '') === 'ping') {
    $server->push($frame->fd, json_encode(['type' => 'pong']));
    return;
}
```

客户端应在合理间隔发送心跳，并在断线后采用指数退避重连。不要让所有客户端在同一秒无限重连，否则服务恢复时会形成重连风暴。

## 用户与 fd 的映射

单个 Worker 的普通数组不能作为完整在线用户表，因为同一服务器有多个 Worker：

```php
// 不适合作为多 Worker 的全局在线状态
private static array $connections = [];
```

可根据规模选择：

- Swoole Table：单机 Worker 间共享连接元数据。
- Redis：多进程、多实例共享用户与节点信息。
- Redis Pub/Sub、NATS、Kafka：把广播消息传递到持有目标连接的实例。

映射至少应包含 `userId`、`fd`、服务器实例 ID、连接时间和最后活跃时间。断开时只删除与当前连接版本匹配的记录，避免旧连接的 Close 事件误删用户的新连接。

## 广播和多实例

同一 Server 内发送前遍历连接并检查 `isEstablished()`；大量广播要分批，注意慢客户端和发送缓冲区。

多实例时，一个实例不能直接 `push()` 另一个实例的 fd。典型流程：

```text
业务产生通知
    ↓
消息总线按 userId/roomId 发布
    ↓
各 WebSocket 实例消费
    ↓
实例查找本机 fd
    ↓
server->push()
```

消息需要定义唯一 ID、顺序要求、重试和幂等策略。WebSocket 在线推送不能替代可靠存储；重要通知应先落库，客户端重连后按游标补拉。

## Nginx 反向代理

生产环境通常使用 `wss://`，由 Nginx 终止 TLS：

```nginx
location /ws {
    proxy_pass http://127.0.0.1:9501;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_read_timeout 120s;
    proxy_send_timeout 120s;
}
```

代理超时应大于应用心跳周期。HTTPS 页面只能连接 `wss://`，否则浏览器会阻止混合内容。

## 上线前检查

- 是否校验连接路径、Origin 和身份？
- 是否限制单条消息大小和发送频率？
- 是否处理无效 JSON、未知消息类型和权限失败？
- 是否配置心跳、空闲超时和退避重连？
- 是否在 Close 中幂等清理连接状态？
- 是否避免把 fd 当作永久用户 ID？
- 多 Worker、多实例的连接映射和广播是否使用共享机制？
- 重要消息是否支持落库、确认、重试或重连补拉？
- Nginx 是否转发 Upgrade/Connection Header，超时是否合理？
- 日志是否避免记录完整 Token 和敏感消息内容？
