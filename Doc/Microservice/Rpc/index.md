# RPC 安装与接入

EasySwoole RPC 通过 Swoole 协程和 TCP 短连接调用远程服务。调用路径由服务名、模块名和 Action 组成，例如 `User.Profile.detail`。提供方注册这条路径，调用方通过节点管理器取得服务的 TCP 地址。

## 设计原理

### 服务启动与节点发现

提供方的 RPC TCP 进程开始监听后，辅助进程才登记节点，并在启用 UDP 时向网关通告。网关把收到的节点写入本机共享表，供 HTTP Worker 查询。

```mermaid
flowchart TD
    Register["提供方：注册 User 服务及 Profile 模块"] --> Attach["attachServer 挂载自定义进程"]
    Attach --> Tcp["默认 3 个 TCP 进程共用一个监听端口"]
    Tcp --> Ready["进程成功监听后，按 index 刷新共享进程心跳"]
    Ready --> Health{"AssistWorker 检查：至少一个 TCP 进程存活？"}
    Health -->|是| Online["登记并续约本机节点"]
    Online --> Heartbeat["发送 UDP 心跳，通告服务名与 TCP 地址"]
    Health -->|全部失活| Offline["停止续约，摘除已发布节点并发送 UDP 下线通知"]
    Offline -->|TCP 进程恢复监听| Ready
    Shutdown["提供方正常关停"] --> Offline

    Heartbeat --> Receive["网关：AssistWorker 接收 UDP 通告"]
    Offline --> Receive
    Receive --> Verify{"发现包是否合法？"}
    Verify -->|否| Discard["丢弃，继续接收"]
    Verify -->|是| Update["心跳写入或续约，下线通知删除节点"]
    Update --> Table["网关 NodeManager 节点表，供 HTTP worker 查询"]
    Table --> Expiry["查询时过滤并清理已超过 TTL 的记录"]
```

### 单次调用

调用方按服务名查询节点，选出目标后通过 TCP 发送请求。服务端按服务、模块和 Action 分发，客户端校验响应，再按失败策略决定是否重试。

```mermaid
flowchart TD
    Http["收到 HTTP 请求"] --> Batch["buildRequest 后添加 User.Profile.detail"]
    Batch --> Lookup["exec 并发执行批次，按 User 查询节点"]
    Lookup -->|查询失败| LookupFailed["NODE_LOOKUP_FAILED"]
    Lookup -->|无节点| NoNode["NOT_AVAILABLE_NODE"]
    Lookup -->|有节点| Select["按权重选择节点"]
    Select --> Send["TCP 短连接：发送固定包头和 JSON 包体"]

    Send --> Header{"服务端先收齐固定包头，检查长度、时间戳和签名"}
    Header -->|校验失败或超时| Close["直接关闭连接"]
    Header -->|通过| Body["用剩余时间读取包体"]
    Body -->|超时或提前断开| Close
    Body -->|收齐| Check{"校验包体哈希、JSON 结构和内层签名"}
    Check -->|失败| Illegal["返回 ILLEGAL_PACKAGE 和具体原因"]
    Check -->|通过| Action["按 Service、Module、Action 分发"]
    Action --> Response["构建并编码只读 Response"]

    Close --> Evaluate["客户端得到传输失败或超时状态"]
    Illegal --> Decode["客户端解码响应并检查签名和请求 UUID"]
    Response --> Decode
    Evaluate --> Retry{"失败策略和重试预算允许再次尝试？"}
    Decode --> Retry
    Retry -->|是，仍有时间| Lookup
    Retry -->|否| Result["按完整调用路径返回最终 Response"]
    LookupFailed --> Fallback["重试选节点失败时保留上一次调用的响应"]
    NoNode --> Fallback
    Fallback --> Result
```

两张流程图来自 [RPC 6.0.1 上游 README](https://github.com/easy-swoole/rpc/blob/6.0.1/README.md#设计与调用流程)。

## 安装

本文以 `easyswoole/rpc` **6.0.1** 为准，需要 PHP 8.1+、Swoole 5.1+ 和 `easyswoole/component:^2.5`。在 EasySwoole 应用项目根目录执行：

```bash
composer require 'easyswoole/rpc:^6.0.1'
composer show easyswoole/rpc
```

## 定义项目的 RPC 入口

新建 `App/Rpc/MyRpc.php`：

```php
<?php

namespace App\Rpc;

use EasySwoole\Component\Singleton;
use EasySwoole\Rpc\Rpc;

final class MyRpc extends Rpc
{
    use Singleton;
}
```

每个应用通过 `MyRpc::getInstance()` 访问 RPC。首次调用传入该应用的配置和依赖。需要挂载 RPC 或 UDP 发现进程的 EasySwoole 应用，在主进程的 `EasySwooleEvent::mainServerCreate()` 中完成初始化和挂载，Worker 启动后即可使用已配置的实例。

接下来创建[服务提供方](/Microservice/Rpc/server.md)，再用[客户端](/Microservice/Rpc/client.md)验证调用。

## 源码依据

- [RPC 6.0.1 源码](https://github.com/easy-swoole/rpc/tree/6.0.1)
- [Composer 包](https://packagist.org/packages/easyswoole/rpc)
