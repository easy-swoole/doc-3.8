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
