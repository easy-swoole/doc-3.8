# IpPortAccess：IP 与端口规则

`IpPortAccess` 同时检查 IP 和端口。规则中的端口是闭区间，起止端口都会被包含。

## 精确 IP 与端口

```php
<?php

use EasySwoole\IpAccess\IpPortAccess;

$access = (new IpPortAccess())
    // 单端口
    ->addIpAllowPort('127.0.0.1', 80)
    ->addIpBlockPort('192.168.0.1', 443)

    // 端口闭区间
    ->addIpAllowPort('127.0.0.1', 8000, 9000)
    ->addIpBlockPort('192.168.0.1', 1000, 2000);

$access->isAllowAccess('127.0.0.1', 80);      // true
$access->isAllowAccess('192.168.0.1', 443);   // false
$access->isAllowAccess('192.168.0.1', 1500);  // false
$access->isAllowAccess('192.168.0.1', 9500);  // true，未命中
```

端口可以传整数，也可以传只包含数字的字符串，例如 `'443'`。

## 网段与端口

```php
$access = (new IpPortAccess())
    ->addIpSegmentAllowPort('172.16.0.0/16', 80)
    ->addIpSegmentAllowPort('172.17.0.0/16', 8000, 9000)
    ->addIpSegmentBlockPort('192.168.1.0/24', 443)
    ->addIpSegmentBlockPort('192.168.2.0/24', 1000, 2000);

$access->isAllowAccess('172.17.1.20', 8080);  // true
$access->isAllowAccess('192.168.1.20', 443);  // false
$access->isAllowAccess('192.168.1.20', 80);   // true，端口未命中
```

只有 IP 范围和端口范围同时命中，规则才生效。

## 设置精确例外

精确 IP+端口规则的优先级高于网段+端口规则：

```php
$access = (new IpPortAccess())
    ->addIpSegmentBlockPort('192.168.1.0/24', 8000, 9000)
    ->addIpAllowPort('192.168.1.31', 8080);

$access->isAllowAccess('192.168.1.31', 8080); // true，精确放行
$access->isAllowAccess('192.168.1.31', 8081); // false，继续匹配网段规则
$access->isAllowAccess('192.168.1.32', 8080); // false
```

为某个 IP 配置了 8080 精确规则，不代表该 IP 的其他端口也停止匹配网段规则。

## 规则优先级

判断顺序为：

1. 精确 IP 的放行端口规则。
2. 精确 IP 的封禁端口规则。
3. IP 网段的放行端口规则。
4. IP 网段的封禁端口规则。
5. 未命中时默认放行。

## 冲突与参数校验

同一个精确 IP 的放行、封禁端口范围不能重叠。网段规则只有在“IP 范围重叠”并且“端口范围也重叠”时才冲突：

```php
use EasySwoole\IpAccess\IpPortAccess;

$access = (new IpPortAccess())
    ->addIpSegmentBlockPort('10.0.0.0/8', 80, 100);

// IP 范围和端口都重叠，抛出 LogicException。
$access->addIpSegmentAllowPort('10.1.0.0/16', 90);
```

下面的规则可以共存，因为端口不重叠：

```php
$access = (new IpPortAccess())
    ->addIpSegmentAllowPort('10.0.0.0/8', 80)
    ->addIpSegmentBlockPort('10.1.0.0/16', 443);
```

端口必须在 `1` 到 `65535` 之间，起始端口不能大于结束端口。非法 IP、CIDR 或端口会抛出 `InvalidArgumentException`，相反名单发生规则冲突时会抛出 `LogicException`。

下一章：[框架接入与代理部署](/Library/IpAccess/integration.md)。
