# IpAccess：框架接入与代理部署

本章以“只允许办公网和本机访问后台接口”为例，把 `IpAccess` 接入 EasySwoole 控制器。IP 检查应尽早执行，拒绝后写入响应并返回 `false`，避免目标 Action 继续运行。

## 建立后台 Base 控制器

新建 `App/HttpController/Admin/Base.php`：

```php
<?php

namespace App\HttpController\Admin;

use EasySwoole\Http\AbstractInterface\Controller;
use EasySwoole\IpAccess\IpAccess;

abstract class Base extends Controller
{
    /** 每个 Worker 只构建一次规则，后续请求复用。 */
    private static ?IpAccess $ipAccess = null;

    final protected function onRequest(?string $action): ?bool
    {
        $clientIp = $this->request()->getServerParams()['remote_addr'] ?? '';

        if ($clientIp === '' || !self::ipAccess()->isAllowAccess($clientIp)) {
            $this->writeJson(403, null, '当前 IP 不允许访问');
            return false;
        }

        return true;
    }

    private static function ipAccess(): IpAccess
    {
        if (self::$ipAccess === null) {
            self::$ipAccess = (new IpAccess())
                // 示例采用黑名单策略：封禁整个网段，再放行办公出口。
                ->addBlackIpSegment('203.0.113.0/24')
                ->addWhiteIp('203.0.113.10');
        }

        return self::$ipAccess;
    }
}
```

后台控制器继承这个 Base 后，请求会先进入 `onRequest()`：

```php
<?php

namespace App\HttpController\Admin;

class Dashboard extends Base
{
    public function index(): void
    {
        $this->writeJson(200, ['status' => 'ok']);
    }
}
```

```text
请求进入 Dashboard
        ↓
Base::onRequest()
  ├── 不允许：写入 403，返回 false，Action 不执行
  └── 允许：返回 true，继续执行 Dashboard::index()
```

示例中的 `203.0.113.0/24` 是文档保留网段，部署时必须替换为真实规则。

## 仅白名单模式需要额外设计

组件未命中规则时默认放行，所以不能只调用 `addWhiteIp()` 就认为其他来源会被拒绝。严格白名单可以先在应用配置中维护允许的精确 IP/CIDR，再由应用自身决定默认拒绝；如果规则可以表达为一个大黑名单加少数精确例外，也可以利用组件的优先级实现。

不要为了实现“拒绝所有 IPv4”随意加入 `0.0.0.0/0`，再同时添加白名单网段；相反类型的重叠网段会被组件判定为冲突。精确白名单 IP 可以作为黑名单网段的例外，但白名单网段不可以和黑名单网段重叠。

## Nginx 反向代理后的客户端 IP

服务直连时，`remote_addr` 是客户端地址；经过 Nginx 后，它通常是 Nginx 的地址。如果直接相信任意请求携带的 `X-Forwarded-For`，攻击者就可以伪造 IP 绕过限制。

正确流程是：

1. 防火墙只允许可信代理访问 EasySwoole 监听端口。
2. Nginx 覆盖客户端 IP Header，不要原样透传客户端提供的值。
3. 应用只在 `remote_addr` 属于可信代理时解析 `X-Real-IP` 或 `X-Forwarded-For`。
4. 把解析后的单个合法 IP 传给 `isAllowAccess()`。

Nginx 示例：

```nginx
location / {
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_pass http://127.0.0.1:9501;
}
```

反向代理信任链的完整配置参见[反向代理部署](/Http/Advanced/proxy.md)。

## 动态规则与多 Worker

每个 Worker 都有独立内存，修改某个 Worker 中的对象不会自动传播到其他 Worker。动态规则建议采用以下流程：

```text
后台修改规则并持久化到数据库/Redis
              ↓
发布规则版本变更通知
              ↓
每个 Worker 拉取完整规则
              ↓
构建新的 IpAccess 对象并整体替换旧对象
```

整体替换比在旧对象上逐条追加更容易保证一致性。当前公开 API 用于添加和判断，没有删除单条规则的方法；需要撤销规则时应重新构建对象。

## 使用 IpPortAccess

同一个进程监听多个端口时，可以把当前服务端口一起传入：

```php
use EasySwoole\IpAccess\IpPortAccess;

$server = $this->request()->getServerParams();
$clientIp = (string) ($server['remote_addr'] ?? '');
$serverPort = (int) ($server['server_port'] ?? 0);

$access = (new IpPortAccess())
    ->addIpSegmentBlockPort('192.168.0.0/16', 9502);

if ($clientIp === '' || $serverPort === 0 || !$access->isAllowAccess($clientIp, $serverPort)) {
    $this->writeJson(403, null, '当前 IP 或端口不允许访问');
    return false;
}
```

这里应传本地监听端口 `server_port`，而不是客户端临时端口 `remote_port`。

## 使用注意事项

- IP 规则不能替代登录鉴权、权限检查和接口签名。
- 客户端 IP 可能受代理、NAT 和 IPv4/IPv6 双栈影响，上线前要用真实链路验证。
- 规则来自配置文件或数据库时，应捕获 `InvalidArgumentException` 和 `LogicException`，启动阶段发现错误应直接阻止服务就绪。
- 规则对象没有跨进程共享能力，不要把一次请求中的临时修改当成全局配置。
- `IpPortAccess` 的端口范围是闭区间，`8000, 9000` 会同时包含 8000 和 9000。

## 源码依据

- [IpAccess README](https://github.com/easy-swoole/ip-access/blob/main/README.md)
- [IpPortAccess 源码](https://github.com/easy-swoole/ip-access/blob/main/src/IpPortAccess.php)
