# 指定颜色字符

普通模式要求识别图中全部字符；彩色模式可以指定一种目标颜色，让用户只输入这种颜色的字符。图片中会加入其他颜色的局部重叠干扰。使用这个模式时，界面必须同时展示提示语，不能只展示图片。

## 生成蓝色字符验证码

在应用项目根目录新建 `captcha-color.php`：

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use EasySwoole\VerifyCode\CaptchaColor;
use EasySwoole\VerifyCode\Config;
use EasySwoole\VerifyCode\VerifyCode;

$config = (new Config())->setComplexityLevel(3);
$result = (new VerifyCode($config))->drawCode('AbC729', CaptchaColor::BLUE);

file_put_contents(__DIR__ . '/captcha-blue.png', $result->getImageByte());
echo $result->getPrompt(), PHP_EOL; // 请输入蓝色的验证码
```

执行 `php captcha-color.php`，查看图片与终端提示。README 中固定字体和配色后的蓝色示例：

![蓝色字符验证码](/Images/verifyCodeExample/target-blue.png)

第二个参数指定目标颜色；随机生成字符时可用 `drawCode(null, CaptchaColor::BLUE)`。不传第二个参数或传 `null` 时是普通模式，不会生成彩色干扰。`getTargetColor()` 返回 `CaptchaColor` 枚举，其 `value` 为英文颜色名，`label()` 为中文颜色名；`getPrompt()` 直接给出中文提示。

## 可选目标颜色

| 枚举 | 提示语 | 示例 |
| --- | --- | --- |
| `CaptchaColor::RED` | 请输入红色的验证码 | ![红色目标](/Images/verifyCodeExample/target-red.png) |
| `CaptchaColor::BLUE` | 请输入蓝色的验证码 | ![蓝色目标](/Images/verifyCodeExample/target-blue.png) |
| `CaptchaColor::GREEN` | 请输入绿色的验证码 | ![绿色目标](/Images/verifyCodeExample/target-green.png) |
| `CaptchaColor::PURPLE` | 请输入紫色的验证码 | ![紫色目标](/Images/verifyCodeExample/target-purple.png) |
| `CaptchaColor::ORANGE` | 请输入橙色的验证码 | ![橙色目标](/Images/verifyCodeExample/target-orange.png) |
| `CaptchaColor::BLACK` | 请输入黑色的验证码 | ![黑色目标](/Images/verifyCodeExample/target-black.png) |

这些图都使用 `AbC729` 作为目标内容；用户从左到右输入**目标颜色**的字符。图像有随机性，因此目标字符的位置与重叠程度每次不同。

## 调整彩色干扰

在 `drawCode()` 前可减少干扰组数和每组字符数：

```php
$config->setDecoyCodeCount(1)       // 1～5 组，默认 2
    ->setDecoyCharacterCount(1);     // 每组 1～8 个字符，默认 2
```

![减少局部重叠干扰](/Images/verifyCodeExample/decoys.png)

每组的实际字符数不会超过目标内容的长度。彩色干扰与噪点、曲线开关独立；某些用户可能难以区分颜色，实际产品应提供普通模式或其他可访问的替代方式。

下一章：[字体与图片格式](/Library/VerifyCode/font-format.md)。

## 源码依据

- [4.x README：目标颜色与局部重叠干扰](https://github.com/easy-swoole/verify-code/blob/4.x/README.md)
- [CaptchaColor.php](https://github.com/easy-swoole/verify-code/blob/4.x/src/CaptchaColor.php)
