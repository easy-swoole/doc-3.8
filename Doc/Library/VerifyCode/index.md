# 图片验证码：安装与生成

`easyswoole/verifycode` 4.x 基于 PHP GD 生成图片验证码，支持自带字体、字符集、尺寸、噪点、曲线、复杂度和指定颜色字符。先用一个独立 PHP 脚本生成图片，确认组件可以工作，再阅读后面的控制器输出章节。

## 安装

在**你的 EasySwoole 应用项目根目录**运行：

```bash
php -v
php --ri gd
composer require 'easyswoole/verifycode:^4.0'
```

需要 PHP 8.1 及以上、GD 扩展及 FreeType 支持。`php --ri gd` 应显示 GD 扩展信息，其中 FreeType Support 为 enabled。Composer 包名是 `easyswoole/verifycode`，GitHub 仓库名是 `verify-code`。

## 生成第一张图片

在项目根目录新建 `captcha-test.php`，完整内容如下：

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use EasySwoole\VerifyCode\VerifyCode;

$result = (new VerifyCode())->drawCode();
file_put_contents(__DIR__ . '/captcha.png', $result->getImageByte());
echo "已生成 captcha.png\n";
```

执行 `php captcha-test.php`，然后打开项目根目录中的 `captcha.png`。图片每次都会变化，下面只是其中一次的效果：

![默认验证码示例](/Images/verifyCodeExample/default.png)

默认随机生成 4 位数字与英文字母，背景为白色，随机选字体和文字颜色；噪点开启、曲线关闭、复杂度为 1。`drawCode()` 返回 `Result` 对象；`getImageByte()` 是图片二进制。直接输出 HTTP 图片、返回 Base64 的方法见[控制器输出](/Library/VerifyCode/response.md)。

## 指定内容

`drawCode()` 不传参数时随机生成；也可以传入要绘制的字符串：

```php
use EasySwoole\VerifyCode\VerifyCode;

$result = (new VerifyCode())->drawCode('AbC729');
```

![指定内容且无干扰的示例](/Images/verifyCodeExample/clean.png)

这张示例图在 README 中还固定了字体、配色并关闭了干扰，因此与仅指定内容的代码不会完全同色同形。内置字体只包含数字和英文字母，当前绘制按单字节字符处理，不要传入中文作为验证码内容。后续章节会分别说明这些配置。

## 按什么顺序阅读

1. [字符、尺寸与颜色](/Library/VerifyCode/appearance.md)：设置内容与基本外观。
2. [噪点、曲线与复杂度](/Library/VerifyCode/complexity.md)：调节干扰程度。
3. [指定颜色字符](/Library/VerifyCode/color.md)：让用户只输入某种颜色的字符。
4. [字体与图片格式](/Library/VerifyCode/font-format.md)：选择字体及 PNG/GIF/JPG。
5. [控制器输出](/Library/VerifyCode/response.md)：在 EasySwoole 中返回图片或 Base64。

本文示例图来自组件 4.x 仓库，已经复制到本站 `Static/Images/verifyCodeExample`；字符位置与干扰内容有随机性，实际运行不要求和截图完全一致。

## 源码依据

- [verify-code 4.x README](https://github.com/easy-swoole/verify-code/blob/4.x/README.md)
- [4.x composer.json](https://github.com/easy-swoole/verify-code/blob/4.x/composer.json)
