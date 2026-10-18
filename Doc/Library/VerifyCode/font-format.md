# 字体与图片格式

组件自带六种字体，默认会为每个 `VerifyCode` 实例随机选择一种。无需下载字体，也不依赖系统已安装的字体。若需统一视觉风格，可以指定自有 TTF 文件的绝对路径。

## 内置字体效果

| 字体 | 示例 |
| --- | --- |
| Black Ops One | ![Black Ops One](/Images/verifyCodeExample/font-1.png) |
| Bungee | ![Bungee](/Images/verifyCodeExample/font-2.png) |
| Monoton | ![Monoton](/Images/verifyCodeExample/font-3.png) |
| Wallpoet | ![Wallpoet](/Images/verifyCodeExample/font-4.png) |
| Jolly Lodger | ![Jolly Lodger](/Images/verifyCodeExample/font-5.png) |
| Play Bold | ![Play Bold](/Images/verifyCodeExample/font-6.png) |

内置字体经过数字和英文字母字符集裁剪；部分字体大小写看起来相同。其许可证说明在[组件仓库的字体目录](https://github.com/easy-swoole/verify-code/blob/4.x/src/assets/ttf/FONT-LICENSES.md)。

## 使用自有字体

在应用项目根目录新建 `captcha-font.php`。先将你有权使用的 `my-font.ttf` 放到项目的 `assets/fonts/` 目录，再运行：

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use EasySwoole\VerifyCode\Config;
use EasySwoole\VerifyCode\VerifyCode;

$font = __DIR__ . '/assets/fonts/my-font.ttf';
$config = (new Config())->setUseFont($font);
$result = (new VerifyCode($config))->drawCode('AbC729');
file_put_contents(__DIR__ . '/captcha-font.png', $result->getImageByte());
```

`setUseFont()` 指定一个字体文件；路径必须是可读的绝对路径。若希望自有字体与内置字体一起参与随机选择，改用 `$config->addFonts($font)`；也可传多个路径组成的数组。不要把仓库 README 中的 `__DIR__ . '/src/assets/ttf/1.ttf'` 原样复制到你的应用：那是组件仓库的相对路径，不是应用项目的路径。

## PNG、GIF、JPG

在调用 `drawCode()` 前设置图片格式：

```php
use EasySwoole\VerifyCode\MIME;

$config->setMimeType(MIME::JPG); // MIME::PNG、MIME::GIF 或 MIME::JPG
```

| 格式 | 示例 |
| --- | --- |
| PNG（默认） | ![PNG 格式](/Images/verifyCodeExample/format.png) |
| GIF（静态） | ![GIF 格式](/Images/verifyCodeExample/format.gif) |
| JPG | ![JPG 格式](/Images/verifyCodeExample/format.jpg) |

响应图片时不要写死 `Content-Type: image/png`，应使用当前结果的 `getImageMime()`；不同格式的二进制通过同一个 `getImageByte()` 取得。

下一章：[控制器输出](/Library/VerifyCode/response.md)。

## 源码依据

- [4.x README：字体与格式](https://github.com/easy-swoole/verify-code/blob/4.x/README.md)
- [MIME.php](https://github.com/easy-swoole/verify-code/blob/4.x/src/MIME.php)
