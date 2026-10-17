# IpAccess：安装与组件选择

`easyswoole/ip-access` 用于在应用内判断某个 IPv4 或 IPv6 地址是否允许访问。它支持精确 IP、CIDR 网段以及 IP 与端口组合规则，适合后台入口限制、内网接口保护、回调来源过滤和多端口服务访问控制。

## 环境要求与安装

组件要求 PHP 8.1 或更高版本。在项目根目录执行：

```bash
composer require easyswoole/ip-access
```

安装后不需要注册服务提供者，Composer 会自动加载组件类：

```php
use EasySwoole\IpAccess\IpAccess;
use EasySwoole\IpAccess\IpPortAccess;
```

## 应该使用哪个类

组件提供两个入口类：

| 类 | 判断依据 | 常见场景 |
| --- | --- | --- |
| `IpAccess` | 只判断 IP | HTTP 后台、Webhook、内部 API |
| `IpPortAccess` | 同时判断 IP 和端口 | 多端口 TCP/UDP 服务、同一 IP 在不同端口使用不同策略 |

只限制访问来源时使用 `IpAccess` 即可。只有业务确实需要区分端口时，才使用 `IpPortAccess`。

## 最小示例

在项目根目录新建 `ip-access-demo.php`，写入完整内容：

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use EasySwoole\IpAccess\IpAccess;

$access = (new IpAccess())
    ->addBlackIpSegment('192.168.1.0/24')
    ->addWhiteIp('192.168.1.31');

var_dump($access->isAllowAccess('192.168.1.31')); // true
var_dump($access->isAllowAccess('192.168.1.32')); // false
var_dump($access->isAllowAccess('10.0.0.1'));     // true
```

运行 `php ip-access-demo.php`，三行结果依次应为 `bool(true)`、`bool(false)`、`bool(true)`。这个例子只检查内存规则，不需要启动 EasySwoole HTTP 服务。

这里最后一个结果是 `true`，因为两个类采用相同的默认策略：**没有命中任何规则时放行**。因此只配置白名单并不等于“除白名单外全部拒绝”。如果业务需要严格的仅白名单模式，应在应用层明确实现默认拒绝策略，不能误以为添加一条白名单后组件会自动拒绝其他地址。

## 规则保存在哪里

规则保存在当前 PHP 对象的内存中，组件不会读取配置文件，也不会自动同步 Redis、数据库或其他 Worker：

```text
配置文件或数据库
      ↓ 应用启动/Worker 初始化时读取
IpAccess 对象（当前进程内存）
      ↓
isAllowAccess() 判断
```

不要在每次请求中重新读取数据库并构建大量规则。规则固定时，可以在每个 Worker 中初始化一次并复用对象；需要动态更新时，应由应用监听配置变化，再为每个 Worker 重建完整规则对象。

下一章：[IP 黑白名单](/Library/IpAccess/ip-access.md)。

## 源码依据

- [IpAccess 仓库](https://github.com/easy-swoole/ip-access)
- [IpAccess 源码](https://github.com/easy-swoole/ip-access/blob/main/src/IpAccess.php)
