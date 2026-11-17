# 定义与发布 RPC 服务

## 定义 Service 和 Module

新建 `App/Rpc/UserService.php`：

```php
<?php

namespace App\Rpc;

use EasySwoole\Rpc\AbstractInterface\AbstractService;

final class UserService extends AbstractService
{
    public function serviceName(): string
    {
        return 'User';
    }
}
```

新建 `App/Rpc/ProfileModule.php`：

```php
<?php

namespace App\Rpc;

use EasySwoole\Rpc\AbstractInterface\AbstractServiceModule;
use EasySwoole\Rpc\Attribute\RpcAction;
use EasySwoole\Rpc\Protocol\Request;

final class ProfileModule extends AbstractServiceModule
{
    public function moduleName(): string
    {
        return 'Profile';
    }

    #[RpcAction]
    public function detail(mixed $arg, Request $request): array
    {
        return [
            'id' => (int) ($arg['id'] ?? 0),
            'name' => 'EasySwoole',
            'requestUUID' => $request->getRequestUUID(),
        ];
    }
}
```

`User.Profile.detail` 的三段分别来自 `serviceName()`、`moduleName()` 和方法名。可远程调用的方法必须是带 `#[RpcAction]` 的 public 实例方法。普通返回值将作为响应的 `result`，参数和返回值应当可以编码为 JSON。

## 在主进程注册并挂载

将下列导入和方法体合并到项目根目录的 `EasySwooleEvent.php`。示例使用本机 TCP 9601 验证调用。

```php
use App\Rpc\MyRpc;
use App\Rpc\ProfileModule;
use App\Rpc\UserService;
use EasySwoole\EasySwoole\ServerManager;
use EasySwoole\EasySwoole\Swoole\EventRegister;
use EasySwoole\Rpc\Config\RpcConfig;
use EasySwoole\Rpc\Config\SecurityConfig;
use EasySwoole\Rpc\Config\ServerConfig;

public static function mainServerCreate(EventRegister $register): void
{
    MyRpc::getInstance(new RpcConfig(
        server: new ServerConfig(
            listenAddress: '127.0.0.1',
            listenPort: 9601,
            advertiseHost: '127.0.0.1',
            nodeId: 'user-rpc-1',
        ),
        security: new SecurityConfig(apiKey: 'local-demo-key'),
    ));

    $service = new UserService();
    $service->addModule(new ProfileModule());
    MyRpc::getInstance()->server()->registerService($service);

    MyRpc::getInstance()->server()->setOnException(static function (\Throwable $error): void {
        error_log('[RPC] ' . $error->getMessage());
    });
    MyRpc::getInstance()->server()->attachServer(
        ServerManager::getInstance()->getSwooleServer()
    );
}
```

先装配 Module，再注册 Service。注册后 Service 会冻结。所有 Service 必须在 `attachServer()` 前注册，挂载应在宿主 Server 启动前完成一次。TCP 9601 由独立 RPC 进程监听，项目的 HTTP 端口继续处理 HTTP 请求。

```bash
php easyswoole.php server start
```

服务启动后，按[发起 RPC 调用](/Microservice/Rpc/client.md)从另一个终端验证。

## 服务端全局异常处理

在主进程 `attachServer()` 前注册。示例中的 `setOnException()` 集中记录没有被 Module 或 Service 接管的请求异常，以及响应序列化错误。后台节点续约和 UDP 错误使用独立的运行回调，可在同一位置追加：

```php
MyRpc::getInstance()->server()->setOnRuntimeError(static function (string $message): void {
    error_log('[RPC node/discovery] ' . $message);
});
```

| 处理位置 | 输入 | 用途 |
| --- | --- | --- |
| Module 或 Service 的 `onException()` | `Throwable`、`ResponseBuilder` | 在业务层记录异常并设置返回给调用方的响应 |
| `MyRpc::getInstance()->server()->setOnException()` | `Throwable` | 集中记录未处理的请求异常和响应序列化异常 |
| `MyRpc::getInstance()->server()->setOnRuntimeError()` | 错误消息字符串 | 记录节点上线、续约、下线以及 UDP 监听或广播失败 |

业务层未处理的请求异常在全局回调记录后返回 `SERVICE_ERROR`，节点健康标记为 `SUSPECT`。响应序列化失败则会尝试回退为精简的 `SERVICE_ERROR`，标记为 `HEALTHY`。端口冲突、非法配置和重复挂载等启动错误由挂载入口同步抛出，应在启动日志中定位。

## 在 Module 中处理预期业务异常

在 `ProfileModule` 中增加以下方法，并将三个 `use` 加到文件顶部。示例把业务校验失败转换成可读响应，其余异常继续交给上层处理。

```php
use EasySwoole\Rpc\Protocol\NodeHealthStatus;
use EasySwoole\Rpc\Protocol\ResponseBuilder;
use EasySwoole\Rpc\Protocol\ResponseStatus;

protected function onException(\Throwable $error, ResponseBuilder $response): void
{
    if (!$error instanceof \DomainException) {
        throw $error;
    }

    $response
        ->setStatus(ResponseStatus::SERVICE_ERROR)
        ->setNodeHealthStatus(NodeHealthStatus::HEALTHY)
        ->setMsg('用户查询条件无效');
}
```

例如，`detail()` 可以在用户 ID 无效时抛出 `DomainException`。客户端会进入该调用的失败回调，默认故障策略保留这个健康节点。

- [服务端请求处理源码](https://github.com/easy-swoole/rpc/tree/6.0.1/src/Server)
