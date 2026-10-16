# IpAccess：IP 黑白名单

`IpAccess` 只根据来源 IP 判断是否放行，支持 IPv4、IPv6、精确 IP 和 CIDR 网段。

## 添加规则并判断

```php
<?php

use EasySwoole\IpAccess\IpAccess;

$access = (new IpAccess())
    // 精确 IP
    ->addWhiteIp('127.0.0.1')
    ->addBlackIp('192.168.0.1')

    // CIDR 网段
    ->addWhiteIpSegment('172.16.0.0/16')
    ->addBlackIpSegment('192.168.1.0/24')

    // 在被封禁网段中放行一个地址
    ->addWhiteIp('192.168.1.31');

var_dump($access->isAllowAccess('127.0.0.1'));    // true
var_dump($access->isAllowAccess('192.168.0.1'));  // false
var_dump($access->isAllowAccess('192.168.1.31')); // true
var_dump($access->isAllowAccess('192.168.1.32')); // false
var_dump($access->isAllowAccess('10.0.0.1'));     // true，未命中时放行
```

所有 `add*()` 方法都返回当前对象，因此可以连续调用。

## 规则优先级

`isAllowAccess()` 按以下顺序判断，命中后立即返回：

```text
精确 IP 白名单
    ↓ 未命中
精确 IP 黑名单
    ↓ 未命中
白名单网段
    ↓ 未命中
黑名单网段
    ↓ 未命中
默认放行
```

精确 IP 比网段优先，所以可以设置例外：

```php
$access = (new IpAccess())
    ->addBlackIpSegment('10.0.0.0/8')
    ->addWhiteIp('10.0.0.10');

$access->isAllowAccess('10.0.0.10'); // true
$access->isAllowAccess('10.0.0.11'); // false
```

反过来也成立：精确 IP 黑名单可以覆盖白名单网段。

## IPv6 与 CIDR

IPv6 可以直接使用，组件会把等价写法规范化后再比较：

```php
$access = (new IpAccess())
    ->addBlackIpSegment('2001:db8::1234/64')
    ->addWhiteIp('2001:db8::1');

$access->isAllowAccess('2001:0db8:0:0:0:0:0:1'); // true
$access->isAllowAccess('2001:db8::2');             // false
```

`2001:db8::1234/64` 会按照 `/64` 网络范围参与匹配，并不要求传入字符串必须已经写成网络起始地址。

## 冲突规则与异常

以下配置会被拒绝：

- 同一个精确 IP 同时加入白名单和黑名单。
- 白名单网段与黑名单网段的地址范围发生重叠。
- IP、IPv6 或 CIDR 格式非法。

```php
use InvalidArgumentException;
use LogicException;

try {
    $access = (new IpAccess())
        ->addWhiteIpSegment('192.168.1.0/24')
        ->addBlackIpSegment('192.168.1.128/25');
} catch (LogicException $throwable) {
    // Segment "192.168.1.128/25" overlaps existing segment
    // "192.168.1.0/24" in the whitelist.
    echo $throwable->getMessage();
}

try {
    (new IpAccess())->addBlackIpSegment('192.168.1.0/33');
} catch (InvalidArgumentException $throwable) {
    echo $throwable->getMessage();
}
```

相同类型的规则允许重复或重叠；精确 IP 与相反类型的网段也允许重叠，因为这正是设置精确例外所需要的组合。

下一章：[IP 与端口规则](/Library/IpAccess/ip-port-access.md)。
