# Consul 客户端：服务注册与发现

服务提供方把实例注册到 Consul Agent，调用方查询健康实例，再连接实例地址。`ConsulClient` 只封装 HTTP API；业务如何选择实例、重试和负载均衡，仍由应用决定。

## 注册服务

以下代码应在服务已经监听 `8080` 端口后执行，例如 Worker 启动后的业务初始化代码。示例假设 `$client` 已由[客户端工厂](/Client/Consul/index.md)创建，且当前处于协程环境。

```php
use EasySwoole\Consul\Request\Agent\Service\Register;

$client->agent()->serviceRegister(new Register([
    'name' => 'orders',
    'id' => 'orders-10-0-0-8-8080',
    'address' => '10.0.0.8',
    'port' => 8080,
    'meta' => ['version' => 'v2'],
    'checks' => [[
        'HTTP' => 'http://10.0.0.8:8080/health',
        'Interval' => '10s',
        'Timeout' => '2s',
    ]],
]));
```

`name` 是服务名；`id` 用于唯一标识一个实例，后续注销也使用这个 ID。`address` 应是调用方可以连接的地址，不能机械地填写 `127.0.0.1`。请求对象会把这些属性映射成 Consul API 需要的 `Name`、`ID`、`Address`、`Port` 等 JSON 字段。

示例的 `checks` 配置要求应用提供能返回成功状态的 `/health` 接口；这个 URL 要能从 Consul Agent 所在环境访问。健康检查未通过时，后文的 `passing: true` 查询不会返回该实例。服务端口和路径都应替换成实际值。

建议只由一个明确的服务生命周期入口负责注册和注销，避免每个 HTTP Worker 都重复执行同一段注册代码。服务注册是写入 Consul 的外部操作；部署时应同时设计健康检查和异常退出后的清理方式，不能只依赖正常退出时的注销。

## 查看本机 Agent 已注册的服务

```php
use EasySwoole\Consul\Request\Agent\Services;

$services = $client->agent()->services(new Services());
var_dump($services);
```

`agent()->services()` 查询的是当前连接的 Agent。需要在集群内发现服务实例时，应使用 Catalog 或 Health 端点。

## 查询可用实例

```php
use EasySwoole\Consul\Request\Health\Service as HealthService;

$nodes = $client->health()->service(new HealthService([
    'service' => 'orders',
    'passing' => true,
]));

foreach ($nodes as $node) {
    $service = $node['Service'];
    $address = $service['Address'] ?: $node['Node']['Address'];
    $port = (int) $service['Port'];

    // 将 $address 和 $port 交给应用自己的负载均衡或 HTTP 客户端。
}
```

`passing: true` 只返回通过健康检查的实例。若没有为服务配置健康检查，Consul 对“可用”的判断可能无法反映应用是否真正能处理请求。应配置符合业务的 HTTP、TCP 或 TTL 健康检查，并让检查地址在 Consul Agent 所在环境可访问。

`catalog()->service()` 可查看登记的服务节点，但它不等同于健康过滤：

```php
use EasySwoole\Consul\Request\Catalog\Service as CatalogService;

$registered = $client->catalog()->service(new CatalogService([
    'service' => 'orders',
]));
```

## 注销实例

```php
use EasySwoole\Consul\Request\Agent\Service\DeRegister;

$client->agent()->serviceDeregister(new DeRegister([
    'service_id' => 'orders-10-0-0-8-8080',
]));
```

注销请求应发往管理该实例的 Agent。实例 ID 与注册时的 `id` 保持一致。服务发现调用方应只使用健康实例，并能处理查询为空、节点下线或连接失败。

下一章：[Session 与其他端点](/Client/Consul/session.md)。

## 源码依据

- [Agent 端点](https://github.com/easy-swoole/consul/blob/2.x/src/Agent.php)
- [Health 端点](https://github.com/easy-swoole/consul/blob/2.x/src/Health.php)
- [服务注册请求](https://github.com/easy-swoole/consul/blob/2.x/src/Request/Agent/Service/Register.php)
