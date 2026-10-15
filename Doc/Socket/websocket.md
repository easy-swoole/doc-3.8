# WebSocket 服务

WebSocket 在 HTTP Upgrade 握手后建立双向长连接，适合浏览器聊天、实时通知、在线协作和状态推送。本章把 [Socket 组件基础](/Socket/index.md)中创建的 Dispatcher 接入 EasySwoole WebSocket 主服务。

## 配置 WebSocket 主服务

编辑项目根目录的 `dev.php`；生产环境还需要同步修改 `produce.php`。下面只展示 `MAIN_SERVER`，原有 `TASK`、`LOG` 等配置应继续保留：

```php
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
```

`EASYSWOOLE_WEB_SOCKET_SERVER` 创建 `Swoole\WebSocket\Server`。它仍然具备 HTTP 服务能力，因此原有 HTTP 路由和控制器可以继续使用。

配置说明：

- `heartbeat_check_interval`：Swoole 检查空闲连接的间隔。
- `heartbeat_idle_time`：连接超过该时间没有收到数据时关闭。
- `package_max_length`：单个请求允许的最大数据长度。

修改 Server 类型或监听配置后必须完整重启服务，不能只 reload Worker。

## 创建 WebSocket Parser

Parser 决定客户端消息如何转换为控制器和 Action，也决定控制器响应如何编码后推送给客户端。下面约定每条 WebSocket 文本消息都是一个 JSON 对象：

```json
{
  "action": "echo",
  "args": {
    "message": "hello websocket"
  }
}
```

新建 `App/Socket/WebSocketParser.php`：

```php
<?php

namespace App\Socket;

use EasySwoole\Socket\AbstractInterface\ParserInterface;
use EasySwoole\Socket\Bean\Caller;
use EasySwoole\Socket\Bean\Response;
use EasySwoole\Socket\Client\Tcp;
use EasySwoole\Socket\Client\Udp;
use EasySwoole\Socket\Client\WebSocket;

final class WebSocketParser implements ParserInterface
{
    public function decode(string $raw, Tcp|Udp $client): ?Caller
    {
        if (!$client instanceof WebSocket) {
            throw new \LogicException('WebSocketParser only supports WebSocket clients');
        }

        if ($client->getOpCode() !== WEBSOCKET_OPCODE_TEXT) {
            throw new \UnexpectedValueException('only text frames are supported');
        }

        $payload = json_decode(
            $raw,
            true,
            64,
            JSON_THROW_ON_ERROR
        );

        if (!is_array($payload)) {
            throw new \UnexpectedValueException('request must be a JSON object');
        }

        $action = $payload['action'] ?? null;
        $args = $payload['args'] ?? [];

        if (!is_string($action) || $action === '') {
            throw new \UnexpectedValueException('action is required');
        }

        if (!is_array($args)) {
            throw new \UnexpectedValueException('args must be an object');
        }

        $caller = new Caller();
        $caller->setControllerClass(EchoController::class);
        $caller->setAction($action);
        $caller->setArgs($args);

        return $caller;
    }

    public function encode(Response $response, Tcp|Udp $client): ?string
    {
        if (!$client instanceof WebSocket) {
            throw new \LogicException('WebSocketParser only supports WebSocket clients');
        }

        return json_encode([
            'status' => $response->getStatus()->value,
            'data' => $response->getMessage(),
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
    }
}
```

### WebSocket Client 与 TCP Client 的关系

组件中的客户端类分别是：

```php
EasySwoole\Socket\Client\Tcp
EasySwoole\Socket\Client\WebSocket
```

这里通常所说的 WebSocketClient，实际类名是 `EasySwoole\Socket\Client\WebSocket`；TcpClient 的实际类名是 `EasySwoole\Socket\Client\Tcp`。`WebSocket` 继承自 `Tcp`：

```php
class WebSocket extends Tcp
{
    // WebSocket Frame 相关属性和方法
}
```

因此，WebSocket Client 首先是一个 TCP Client，能够使用从 `Tcp` 继承的连接信息，例如：

```php
$fd = $client->getFd();
```

同时它还增加了 WebSocket Frame 专属信息：

```php
$data = $client->getData();       // Frame 数据
$opcode = $client->getOpCode();   // 文本、二进制等消息类型
$finish = $client->getIsFinish(); // Frame 是否结束
```

这也是 WebSocket 专用 Parser 的方法参数仍然写成 `Tcp|Udp` 的原因：它必须完整实现 `ParserInterface`，而 `WebSocket` 本身属于 `Tcp` 的子类。进入方法后，可以使用 `instanceof WebSocket` 缩小类型：

```php
if (!$client instanceof WebSocket) {
    throw new \LogicException('WebSocketParser only supports WebSocket clients');
}

// 判断完成后，可以安全调用 WebSocket 独有的方法。
$opcode = $client->getOpCode();
```

需要注意，这里的继承关系只是组件对客户端信息对象的代码复用，并不表示 WebSocket 消息可以按照普通 TCP 流进行拆包。WebSocket 已经由协议 Frame 提供消息边界，而普通 TCP 服务仍需自行解决粘包和拆包问题。

`decode()` 的职责是：

1. 检查消息类型并解析 JSON。
2. 校验 `action` 和 `args` 的基本结构。
3. 创建 `Caller`，由服务端指定 `EchoController`，再设置要执行的 Action 和参数。

不要允许客户端通过 JSON 直接传入任意 PHP 类名。控制器类应该由 Parser 根据服务端定义的协议决定，否则可能调用到不应公开的类。

`encode()` 接收控制器产生的 `Response`，并返回最终推送给客户端的字符串。返回 `null` 表示本次不发送数据；`decode()` 返回 `null` 则表示本次消息不进入控制器。

## 注册 WebSocket 事件

下面使用的 `App\Socket\DispatcherFactory` 不是组件内置类，而是我们在[组件与协议基础](/Socket/index.md)中创建的项目辅助类，文件位置是 `App/Socket/DispatcherFactory.php`。请先完成该类，再编辑项目根目录的 `EasySwooleEvent.php`，在 `mainServerCreate()` 中创建 WebSocket Dispatcher，并把 Frame 交给 `dispatchWebSocket()`：

```php
<?php

namespace EasySwoole\EasySwoole;

use App\Socket\DispatcherFactory;
use App\Socket\WebSocketParser;
use EasySwoole\EasySwoole\AbstractInterface\Event;
use EasySwoole\EasySwoole\Swoole\EventRegister;
use EasySwoole\Socket\Enum\SocketType;
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
        $dispatcher = DispatcherFactory::create(
            SocketType::WEB_SOCKET,
            new WebSocketParser()
        );

        $register->add(
            EventRegister::onOpen,
            function (Server $server, Request $request): void {
                // Open 发生在握手完成后，可建立用户与 fd 的映射。
                $server->push($request->fd, json_encode([
                    'status' => 'OK',
                    'data' => [
                        'message' => 'connected',
                        'fd' => $request->fd,
                    ],
                ], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR));
            }
        );

        $register->add(
            EventRegister::onMessage,
            function (Server $server, Frame $frame) use ($dispatcher): void {
                $dispatcher->dispatchWebSocket($server, $frame);
            }
        );

        $register->add(
            EventRegister::onClose,
            function (Server $server, int $fd, int $reactorId): void {
                // 清理 fd 对应的登录状态、房间订阅和在线记录。
            }
        );
    }
}
```

这里使用 `$register->add()`，不会覆盖框架或其他组件已经注册的同类事件。Dispatcher 的类型必须是 `SocketType::WEB_SOCKET`，类型不一致时组件会抛出 `LogicException`。

## 消息处理流程

客户端发送：

```json
{
  "action": "echo",
  "args": {
    "message": "hello websocket"
  }
}
```

执行过程是：

```text
onMessage
  → Dispatcher::dispatchWebSocket()
  → JsonParser::decode()
  → EchoController::echo()
  → JsonParser::encode()
  → WebSocket Server::push()
```

`EasySwoole\Socket\Client\WebSocket` 保存了当前 Frame 的：

- `fd`
- `data`
- `opcode`
- `finish`

控制器可以通过 `$this->caller()->getClient()` 取得这些信息。

## 启动和测试

完整重启服务：

```bash
php easyswoole.php server stop
php easyswoole.php server start
```

浏览器控制台测试：

```javascript
const socket = new WebSocket("ws://127.0.0.1:9501");

socket.addEventListener("open", () => {
  socket.send(JSON.stringify({
    action: "echo",
    args: { message: "hello websocket" }
  }));
});

socket.addEventListener("message", (event) => {
  console.log(JSON.parse(event.data));
});

socket.addEventListener("close", (event) => {
  console.log("closed", event.code, event.reason);
});
```

也可以使用 `wscat`：

```bash
wscat -c ws://127.0.0.1:9501
```

连接后输入：

```json
{"action":"ping","args":{}}
```

## 连接认证

`Dispatcher` 只负责业务消息分发，不会自动验证 WebSocket 握手。身份认证可以选择：

- 在握手或 `onOpen` 阶段校验一次性连接票据。
- 连接建立后要求客户端先发送登录消息，在认证完成前拒绝其他 Action。
- 在服务端保存 `userId` 与 `fd` 的映射，不能信任消息体中的用户 ID。

### 在 onOpen 中读取 Token

`onOpen` 的 `$request` 是 `Swoole\Http\Request`，WebSocket 升级请求携带的 Query 参数、Header 和 Cookie 都可以从这里取得。实际项目中，请用下面的注册代码替换前文仅发送欢迎消息的 `onOpen` 示例，不要同时保留两个回调。下面按 `Authorization` Header、Cookie、Query 参数的顺序寻找 Token：

```php
use App\Auth\TokenService;
use App\Socket\ConnectionRegistry;
use Swoole\Http\Request;
use Swoole\WebSocket\Server;

$register->add(
    EventRegister::onOpen,
    function (Server $server, Request $request): void {
        $authorization = $request->header['authorization'] ?? '';
        $headerToken = null;

        if (is_string($authorization)
            && preg_match('/^Bearer\s+(.+)$/i', $authorization, $matches)
        ) {
            $headerToken = trim($matches[1]);
        }

        $cookieToken = $request->cookie['access_token'] ?? null;
        $queryToken = $request->get['token'] ?? null;

        $token = $headerToken ?: $cookieToken ?: $queryToken;
        $userId = is_string($token)
            ? TokenService::verify($token)
            : null;

        if ($userId === null) {
            // onOpen 执行时升级已经完成，因此这里直接关闭连接。
            $server->disconnect($request->fd, 1008, 'unauthorized');
            return;
        }

        // 保存服务端可信的 userId 与 fd 关系，供后续消息鉴权使用。
        ConnectionRegistry::bind($request->fd, $userId);

        $server->push($request->fd, json_encode([
            'status' => 'OK',
            'data' => [
                'message' => 'connected',
                'userId' => $userId,
            ],
        ], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR));
    }
);
```

### WebSocket 关闭状态码

`disconnect()` 的第二个参数不是 HTTP 状态码，而是 WebSocket Close Frame 的关闭状态码：

```php
$server->disconnect($request->fd, 1008, 'unauthorized');
```

这里使用 `1008`（Policy Violation，违反策略），表示客户端没有满足服务端制定的连接策略。未登录、Token 无效或无权建立连接都可以使用它，而且无需向客户端暴露具体鉴权规则。

服务端常用的标准状态码如下：

| 状态码 | 含义 | 适用场景 |
| --- | --- | --- |
| `1000` | 正常关闭 | 业务已完成，服务端正常结束连接 |
| `1001` | 端点离开 | 服务停机、重启或页面离开 |
| `1002` | 协议错误 | 收到不符合 WebSocket 协议的数据 |
| `1003` | 不支持的数据类型 | 服务只接受文本，却收到二进制数据等 |
| `1007` | 消息内容无效 | 文本消息不是合法 UTF-8 等 |
| `1008` | 违反策略 | 鉴权失败、权限不足或违反服务规则 |
| `1009` | 消息过大 | 消息超过服务端允许的大小 |
| `1011` | 服务端内部错误 | 服务端遇到意外错误，无法完成请求 |
| `1012` | 服务重启 | 服务端即将重启，客户端可以稍后重连 |
| `1013` | 稍后重试 | 服务繁忙或临时不可用 |
| `1014` | 上游响应无效 | 网关或代理收到无效的上游响应 |

`1010` 表示客户端要求的 WebSocket 扩展没有协商成功，通常由客户端发送，服务端不应把它当作普通业务关闭码。

以下状态码不能由服务端写入 Close Frame：

| 状态码 | 原因 |
| --- | --- |
| `1004` | 协议保留，尚未定义具体含义 |
| `1005` | 只用于本地表示“没有收到关闭状态码” |
| `1006` | 只用于本地表示连接异常中断，未收到关闭帧 |
| `1015` | 只用于本地表示 TLS 握手失败 |

Socket 2.x 的 `Response::setCode()` 接受 `1000`～`4999`，但会拒绝上面四个保留值。范围合法并不代表可以随意占用：

- `1000`～`2999` 用于协议、标准或已登记的公共含义，不应自定义。
- `3000`～`3999` 用于已向 IANA 登记的库、框架和应用代码，使用前应查询是否已有定义。
- `4000`～`4999` 是 Private Use，项目需要自定义业务关闭码时优先使用这个范围，并在客户端和服务端统一约定含义。例如约定 `4001` 表示登录过期。

关闭原因字符串适合提供简短、可公开的信息，例如 `unauthorized` 或 `server restart`；不要写入 Token、内部异常堆栈或敏感鉴权细节。

示例中的 `TokenService::verify()` 代表项目自己的 Token 校验逻辑：校验签名、有效期和用户状态，成功后返回用户 ID，失败返回 `null`。`ConnectionRegistry::bind()` 代表连接状态存储；多 Worker 环境不能只用普通 PHP 数组保存完整连接关系。

三种传递方式对应的客户端用法如下。

Query 参数适用于浏览器原生 WebSocket：

```javascript
const ticket = "一次性短期票据";
const socket = new WebSocket(
  `wss://example.com/ws?token=${encodeURIComponent(ticket)}`
);
```

浏览器地址、代理访问日志和监控系统可能记录 URL，因此 Query 参数中应使用短期、一次性票据，不应放长期访问令牌。

Cookie 会随符合域名、路径和 `SameSite` 规则的升级请求自动发送：

```http
Cookie: access_token=your-token
```

生产环境应使用 `Secure`、`HttpOnly` 和合适的 `SameSite` 属性，并在服务端校验 `Origin`，避免跨站建立 WebSocket。浏览器原生 `WebSocket` 构造函数不能自行设置 `Authorization` Header。

非浏览器客户端通常可以发送 Header，例如：

```http
Authorization: Bearer your-token
```

```bash
wscat -c wss://example.com/ws \
  -H "Authorization: Bearer your-token"
```

如果希望在升级前直接拒绝请求，而不是先建立连接再由 `onOpen` 关闭，应改为自定义 WebSocket 握手事件并在握手阶段完成认证。

如果在 `EchoController::onRequest()` 中做认证，可以根据 WebSocket 的 fd 查询服务端登录状态：

```php
protected function onRequest(?string $actionName): bool
{
    $client = $this->caller()->getClient();

    if (!$client instanceof \EasySwoole\Socket\Client\WebSocket) {
        return false;
    }

    // return ConnectionAuth::check($client->getFd());
    return true;
}
```

认证失败时应设置响应消息和状态，不能只返回 `false` 后让客户端永久等待。

## 主动推送

控制器内需要提前发送一条消息时，可以使用：

```php
$sent = $this->responseImmediately(
    json_encode(['type' => 'notice'], JSON_THROW_ON_ERROR)
);
```

`responseImmediately()` 直接调用 WebSocket `push()` 并返回布尔结果，不会替业务检查连接是否仍然存在。控制器外主动推送时应先判断：

```php
if ($server->isEstablished($fd)) {
    $server->push($fd, $payload);
}
```

二进制消息可以设置 Response：

```php
$this->response()->setMessage($binaryData);
$this->response()->setOpCode(WEBSOCKET_OPCODE_BINARY);
$this->response()->setFlags(SWOOLE_WEBSOCKET_FLAG_FIN);
```

## 关闭连接

`ResponseStatus::RESPONSE_AND_CLOSE` 会先推送响应，再调用 WebSocket `disconnect()`。可以指定关闭码和原因：

```php
use EasySwoole\Socket\Enum\ResponseStatus;

$response = $this->response();
$response->setMessage(['error' => 'unauthorized']);
$response->setCode(1008);
$response->setReason('unauthorized');
$response->setStatus(ResponseStatus::RESPONSE_AND_CLOSE);
```

关闭码必须处于 1000～4999，且不能使用 1004、1005、1006、1015 等保留值。

## 多 Worker 与多实例

普通 PHP 数组只属于当前 Worker，不能作为完整在线连接表。单机多 Worker 可以使用 Swoole Table，多服务器部署通常使用 Redis 保存用户、fd、节点和连接版本。

不同服务器上的 fd 没有全局意义。向另一台服务器持有的连接推送时，需要先通过消息队列或 Pub/Sub 把消息发送到对应节点，再由该节点调用 `push()`。

## 注意事项

- 限制消息大小、JSON 深度和发送频率；只把确实需要对外提供的 Action 声明为 `public`。
- 配置心跳并让客户端使用指数退避重连，避免服务恢复时出现重连风暴。
- fd 会被复用，不能作为永久用户 ID。
- `onClose` 可能由 HTTP 或未认证连接触发，清理逻辑必须幂等。
- 不要把异常详情、Token 或完整聊天内容写入普通日志。
- WebSocket 在线推送不等于可靠消息；重要消息应落库并支持重连补拉。

## 源码依据

- [WebSocket 分发入口](https://github.com/easy-swoole/socket/blob/2.x/src/Dispatcher.php)
- [WebSocket 客户端信息](https://github.com/easy-swoole/socket/blob/2.x/src/Client/WebSocket.php)
- [Response](https://github.com/easy-swoole/socket/blob/2.x/src/Bean/Response.php)
- [IANA WebSocket Close Code 注册表](https://www.iana.org/assignments/websocket/websocket.xhtml#close-code-number)
- [RFC 6455 状态码定义](https://www.rfc-editor.org/rfc/rfc6455.html#section-7.4)
