# 服务发现与部署

默认的节点管理器使用 Swoole Table，同一个宿主 Server 的进程可以共享节点记录。独立运行的服务与网关可以通过 UDP 通告交换节点，或通过 `RpcDependencies` 注入使用外部注册中心的节点管理器。

## 在可信内网中启用 UDP 发现

本机验证时，在[服务提供方](/Microservice/Rpc/server.md)首次配置 `MyRpc` 的 `RpcConfig` 中加入以下配置。记得导入 `EasySwoole\Rpc\Config\DiscoveryConfig`。

```php
discovery: new DiscoveryConfig(
    broadcast: true,
    broadcastAddresses: ['127.0.0.1:9600'],
    broadcastIntervalMs: 1000,
),
```

在单独的网关应用中定义相同的 `MyRpc` 子类。在网关的 `mainServerCreate()` 中加入以下导入和方法体。网关的 HTTP 监听端口要与提供方的 HTTP 端口区分开。

```php
use App\Rpc\MyRpc;
use EasySwoole\EasySwoole\ServerManager;
use EasySwoole\EasySwoole\Swoole\EventRegister;
use EasySwoole\Rpc\Config\DiscoveryConfig;
use EasySwoole\Rpc\Config\RpcConfig;
use EasySwoole\Rpc\Config\SecurityConfig;

public static function mainServerCreate(EventRegister $register): void
{
    MyRpc::getInstance(new RpcConfig(
        discovery: new DiscoveryConfig(
            listen: true,
            listenAddress: '127.0.0.1',
            listenPort: 9600,
        ),
        security: new SecurityConfig(apiKey: 'local-demo-key'),
    ));

    MyRpc::getInstance()->server()->setOnRuntimeError(static function (string $message): void {
        error_log('[RPC discovery] ' . $message);
    });
    MyRpc::getInstance()->server()->attachServer(
        ServerManager::getInstance()->getSwooleServer()
    );
}
```

网关的发现进程收到提供方心跳后，会把 `User` 节点写入其 Worker 共享的节点表。网关的控制器可以直接用 `MyRpc::getInstance()->client()->buildRequest()` 创建批次，无需手动登记固定节点。第一条通告到达前，调用可能返回 `NOT_AVAILABLE_NODE`。提供方异常退出时，陈旧记录最终由节点 TTL 清理。

## 跨机器部署

- `ServerConfig::listenAddress` 是提供方的 TCP 绑定地址。`advertiseHost` 必须能被调用方访问，存在端口映射时用 `advertisePort` 指定对外端口。
- `broadcastAddresses` 填写网关实际可达的 UDP 地址和端口。`nodeId` 应在同一服务下保持唯一，节点 TTL 应长于心跳和广播间隔。
- 通信方使用相同的 `apiKey` 并保持时钟同步。签名校验保护消息完整性，业务数据仍以明文传输。
- 超时后服务端可能已执行 Action。给写操作启用重试前，使用业务单号或幂等键防止重复写入。

具体配置、节点接口与异常类型见 [RPC 6.0.1 文档](https://github.com/easy-swoole/rpc/blob/6.0.1/README.md)。

## 节点上线与下线

UDP 模式由各实例直接向配置的收件地址发送心跳，没有中心注册服务。网关的 UDP 监听可以独立启用，提供方的通告也可以独立启用。每个网关维护自己的节点视图。提供方正常停止时会发送下线通知；如果通知丢失，网关会按节点 TTL 淘汰记录。

默认的 Swoole Table 同时支持同一宿主内的共享节点表，即使 UDP 关闭也可以使用。可以在调用方的协程中查看当前列表：

```php
use App\Rpc\MyRpc;

$nodes = MyRpc::getInstance()->getNodeManager()->getNodes('User');
```

空数组表示查询成功、当前没有可用节点。返回 `false` 表示查询失败。排查时先检查路径第一段与节点的服务名是否一致，再核对 UDP 端口、密钥和 TCP 通告地址。

多个服务和网关需要共享一个注册中心时，参考[集中式注册与自定义节点管理器](/Microservice/Rpc/node-manager.md)。
