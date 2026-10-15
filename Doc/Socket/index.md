# 组件与协议基础

`easyswoole/socket` 2.x 是建立在 Swoole Server 之上的请求分发组件。它不会替代 Swoole 创建监听端口，而是负责把 WebSocket、TCP 或 UDP 收到的原始数据转换为控制器调用，再把控制器响应编码并发送给客户端。

```text
Swoole 事件收到原始数据
        ↓
Dispatcher 创建客户端信息对象
        ↓
Parser::decode() 解析请求
        ↓
Caller 指向 Controller 和 Action
        ↓
Controller 执行业务逻辑
        ↓
Parser::encode() 编码响应
        ↓
Dispatcher 发送或关闭连接
```

本节后续三个章节共用这里创建的 Parser、Controller 和 Dispatcher 工厂。

## 安装组件

Socket 2.x 当前通过 `2.x` 开发分支提供：

```bash
composer require easyswoole/socket:2.x-dev
```

它要求 PHP 8.1+ 和 Swoole 扩展。安装后可以确认版本：

```bash
composer show easyswoole/socket
```

如果现有 EasySwoole 项目的 Composer 依赖仍将 Socket 限制为 `^1.3`，Composer 会拒绝同时安装 2.x。这说明项目依赖约束尚未统一升级；应先让框架及其他依赖共同支持 2.x，不要直接覆盖 `vendor` 中的旧组件。

## 请求格式

下面统一使用 JSON 请求：

```json
{
  "action": "echo",
  "args": {
    "message": "hello"
  }
}
```

- `action` 决定执行控制器中的哪个公开 Action。
- `args` 是传给业务逻辑的参数。
- 客户端不能直接指定 PHP 控制器类，服务端 Parser 应自行决定允许调用的控制器。

## 创建 JSON Parser

新建 `App/Socket/JsonParser.php`：

```php
<?php

namespace App\Socket;

use EasySwoole\Socket\AbstractInterface\ParserInterface;
use EasySwoole\Socket\Bean\Caller;
use EasySwoole\Socket\Bean\Response;
use EasySwoole\Socket\Client\Tcp;
use EasySwoole\Socket\Client\Udp;

final class JsonParser implements ParserInterface
{
    public function decode(string $raw, Tcp|Udp $client): ?Caller
    {
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
        return json_encode([
            'status' => $response->getStatus()->value,
            'data' => $response->getMessage(),
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
    }
}
```

`decode()` 返回 `null` 时，Dispatcher 不会执行控制器。`encode()` 返回 `null` 时，Dispatcher 不发送响应。

公共 Parser 只负责 JSON 与 `Caller`/`Response` 之间的转换，不处理任何传输层封包。TCP 的长度头、粘包和拆包规则放在 [TCP 服务](/Socket/tcp.md)中单独实现。

## 创建 Socket 控制器

新建 `App/Socket/EchoController.php`：

```php
<?php

namespace App\Socket;

use EasySwoole\Socket\AbstractInterface\Controller;
use EasySwoole\Socket\Enum\ResponseStatus;

final class EchoController extends Controller
{
    protected function onRequest(?string $actionName): bool
    {
        // 可以在这里完成鉴权、限流和公共参数检查。
        return true;
    }

    public function echo(): void
    {
        $this->response()->setMessage([
            'action' => 'echo',
            'args' => $this->caller()->getArgs(),
        ]);
    }

    public function ping(): void
    {
        $this->response()->setMessage([
            'action' => 'pong',
            'time' => time(),
        ]);
    }

    public function close(): void
    {
        $this->response()->setMessage([
            'message' => 'connection closed by server',
        ]);
        $this->response()->setStatus(ResponseStatus::RESPONSE_AND_CLOSE);
    }

    protected function actionNotFound(?string $actionName): void
    {
        $this->response()->setMessage([
            'error' => 'action not found',
            'action' => $actionName,
        ]);
    }

    protected function onException(\Throwable $throwable): void
    {
        throw $throwable;
    }

    protected function afterAction(?string $actionName): void
    {
        // 成功、拦截或异常后都会执行，适合记录耗时和清理资源。
    }
}
```

Socket 2.x 会自动把业务控制器中 `public`、非静态的方法识别为可访问 Action。上例中的 `echo`、`ping` 和 `close` 都可以由客户端调用。

因此，控制器中的辅助方法、鉴权方法和任何不允许客户端直接调用的方法，都必须声明为 `protected` 或 `private`：

```php
private function currentUserId(): int
{
    // 该方法不会成为客户端可访问的 Action。
    return 1001;
}
```

`Controller` 基类的方法和 PHP 魔术方法不会成为 Action。即便如此，也不要为了复用方便而把业务辅助方法声明为 `public`；`public` 应只用于明确对外开放的 Action。

## 创建 Dispatcher 工厂

`DispatcherFactory` 不是 EasySwoole 或 Socket 组件提供的类，而是本套文档为了统一创建不同协议的 `Dispatcher` 而定义的项目辅助类。后续 WebSocket、TCP 和 UDP 章节都会复用它。

新建 `App/Socket/DispatcherFactory.php`：

```php
<?php

namespace App\Socket;

use EasySwoole\EasySwoole\Trigger;
use EasySwoole\Socket\AbstractInterface\ParserInterface;
use EasySwoole\Socket\Bean\Response;
use EasySwoole\Socket\Client\Tcp;
use EasySwoole\Socket\Client\Udp;
use EasySwoole\Socket\Config;
use EasySwoole\Socket\Dispatcher;
use EasySwoole\Socket\Enum\ResponseStatus;
use EasySwoole\Socket\Enum\SocketType;
use Swoole\Server;

final class DispatcherFactory
{
    public static function create(
        SocketType $type,
        ?ParserInterface $parser = null
    ): Dispatcher {
        $config = new Config($type, $parser ?? new JsonParser());

        $config->setOnExceptionHandler(
            function (
                Server $server,
                \Throwable $throwable,
                string $raw,
                Tcp|Udp $client,
                Response $response
            ): void {
                Trigger::getInstance()->throwable($throwable);

                $response->setMessage([
                    'error' => 'invalid request',
                ]);
                $response->setStatus(ResponseStatus::RESPONSE_AND_CLOSE);
            }
        );

        return new Dispatcher($config);
    }
}
```

没有配置异常处理器时，Dispatcher 对 TCP/WebSocket 会关闭连接并重新抛出异常；UDP 没有连接可关闭。示例统一返回错误消息。生产环境不要把异常堆栈和内部路径直接发送给客户端。

## ResponseStatus

控制器通过 `ResponseStatus` 决定响应行为：

| 状态 | 发送响应 | TCP/WebSocket | UDP |
| --- | --- | --- | --- |
| `OK` | 是 | 保持连接 | 发送一个数据报 |
| `WITHOUT_RESPONSE` | 否 | 保持连接 | 不发送 |
| `RESPONSE_AND_CLOSE` | 是 | 发送后关闭 | 只发送响应 |
| `CLOSE` | 否 | 直接关闭 | 不发送 |

UDP 是无连接协议，因此 `CLOSE` 对 UDP 只表示不响应，不存在关闭客户端连接的动作。

## 三种服务如何选择

| 服务 | 消息边界 | 连接 | 适用场景 |
| --- | --- | --- | --- |
| WebSocket | Frame 自带边界 | 长连接 | 浏览器实时通信、聊天、推送 |
| TCP | 需要业务协议拆包 | 长连接 | 网关、设备连接、自定义可靠协议 |
| UDP | 每个数据报自带边界 | 无连接 | 状态上报、局域网发现、允许丢包的低延迟场景 |

后续章节分别说明如何把同一套分发逻辑接入三种 Swoole 事件。

## 源码依据

- [Socket 2.x](https://github.com/easy-swoole/socket/tree/2.x)
- [Dispatcher](https://github.com/easy-swoole/socket/blob/2.x/src/Dispatcher.php)
- [ParserInterface](https://github.com/easy-swoole/socket/blob/2.x/src/AbstractInterface/ParserInterface.php)
- [Controller](https://github.com/easy-swoole/socket/blob/2.x/src/AbstractInterface/Controller.php)
