# 噪点、曲线与复杂度

`setUseNoise()` 控制噪点，`setUseCurve()` 控制单像素细曲线，`setComplexityLevel()` 控制 1～9 级复杂度。三个设置可以独立组合：提高等级**不会自动打开**噪点或曲线。

## 完整示例

在应用项目根目录新建 `captcha-complexity.php`：

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use EasySwoole\VerifyCode\Config;
use EasySwoole\VerifyCode\VerifyCode;

$config = (new Config())
    ->setUseNoise(true)
    ->setUseCurve(true)
    ->setComplexityLevel(5);

$result = (new VerifyCode($config))->drawCode('AbC729');
file_put_contents(__DIR__ . '/captcha-complexity.png', $result->getImageByte());
```

执行 `php captcha-complexity.php` 查看图片。下图同样开启两种干扰，但 README 示例使用了固定字体和配色，并设置为 4 级，所以不会和脚本生成结果完全相同：

![噪点与曲线同时开启](/Images/verifyCodeExample/combined.png)

## 分别观察噪点和曲线

只开启噪点：

```php
$config->setUseNoise(true)->setUseCurve(false);
```

![仅开启噪点](/Images/verifyCodeExample/noise.png)

只开启曲线：

```php
$config->setUseNoise(false)->setUseCurve(true)->setComplexityLevel(4);
```

![仅开启曲线](/Images/verifyCodeExample/curves.png)

4.x 的曲线均为 1 像素宽。默认配置已经开启噪点，因此需要显式写 `setUseNoise(false)` 才能只看曲线效果。

## 选择复杂度

复杂度影响字符旋转、字号抖动、水平/垂直位置，以及**已开启**的噪点与曲线数量。范围为 1～9；超出范围会抛出参数异常。以下是 README 中同一内容、不同等级的示例：

| 等级 | 示例 |
| --- | --- |
| 1 | ![1 级验证码](/Images/verifyCodeExample/level-1.png) |
| 2 | ![2 级验证码](/Images/verifyCodeExample/level-2.png) |
| 3 | ![3 级验证码](/Images/verifyCodeExample/level-3.png) |
| 4 | ![4 级验证码](/Images/verifyCodeExample/level-4.png) |
| 5 | ![5 级验证码](/Images/verifyCodeExample/level-5.png) |
| 6 | ![6 级验证码](/Images/verifyCodeExample/level-6.png) |
| 7 | ![7 级验证码](/Images/verifyCodeExample/level-7.png) |
| 8 | ![8 级验证码](/Images/verifyCodeExample/level-8.png) |
| 9 | ![9 级验证码](/Images/verifyCodeExample/level-9.png) |

即使设为 7 级，也可关闭两种干扰：

```php
$config->setComplexityLevel(7)->setUseNoise(false)->setUseCurve(false);
```

![7 级但关闭噪点和曲线](/Images/verifyCodeExample/level-7-clean.png)

等级越高不一定越适合用户。组件 README 也指出，这些等级未经过 OCR 成功率基准验证；应以实际可读性选择，不要把复杂度数字当作安全保证。

下一章：[指定颜色字符](/Library/VerifyCode/color.md)。

## 源码依据

- [4.x README：噪点、曲线与复杂度](https://github.com/easy-swoole/verify-code/blob/4.x/README.md)
- [Config.php](https://github.com/easy-swoole/verify-code/blob/4.x/src/Config.php)
