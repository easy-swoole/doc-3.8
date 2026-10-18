# 字符、尺寸与颜色

本章设置普通验证码的字符集、长度、宽高和配色。下面的示例均使用 4.x 的 `Config`；每次生成仍调用 `VerifyCode::drawCode()`。

## 字符集和长度

在应用项目根目录新建 `captcha-appearance.php`：

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use EasySwoole\VerifyCode\Config;
use EasySwoole\VerifyCode\VerifyCode;

$config = (new Config())
    ->setCharset('0123456789')
    ->setLength(6);

$result = (new VerifyCode($config))->drawCode();
file_put_contents(__DIR__ . '/captcha-digits.png', $result->getImageByte());
```

执行 `php captcha-appearance.php` 后会得到 6 位纯数字图片：

![纯数字验证码](/Images/verifyCodeExample/digits.png)

为避开容易看错的 `0/O`、`1/I`，可以换成：

```php
$config->setCharset('23456789ABCDEFGHJKLMNPQRSTUVWXYZ')->setLength(6);
```

![排除易混字符的验证码](/Images/verifyCodeExample/charset.png)

`setLength()` 只控制随机生成的长度；如果调用 `drawCode('AbC729')`，会绘制传入的 6 个字符，而不受 `setLength()` 限制。内置字体只适合数字与英文字母。

## 背景色与文字颜色

在上面的 `$config` 创建后、`drawCode()` 前，增加：

```php
$config->setFontColor('#7A2E8E')
    ->setBackColor([255, 249, 240]);
```

![自定义配色验证码](/Images/verifyCodeExample/colors.png)

两种颜色都可传三位/六位十六进制字符串（可带 `#`），也可传 `[红, 绿, 蓝]` 三个 0～255 的整数，例如 `'#abc'`、`'2457A6'` 或 `[36, 87, 166]`。上图使用了固定字体、固定内容，所以它只展示配色差异，不要求与上面纯数字脚本的形状完全一致。

## 图片尺寸和字号

在 `drawCode()` 前设置：

```php
$config->setImageWidth(420)
    ->setImageHeight(120)
    ->setFontSize(38);
```

![放大尺寸与字号的验证码](/Images/verifyCodeExample/size.png)

不设置宽高时组件会根据字符数量与字号计算。显式宽高不会自动扩大；字体越大、字符越多或旋转越明显，越需要留出边距，否则字符可能被裁切。

下一章：[噪点、曲线与复杂度](/Library/VerifyCode/complexity.md)。

## 源码依据

- [4.x README：字符集、配色与尺寸](https://github.com/easy-swoole/verify-code/blob/4.x/README.md)
- [Config.php](https://github.com/easy-swoole/verify-code/blob/4.x/src/Config.php)
