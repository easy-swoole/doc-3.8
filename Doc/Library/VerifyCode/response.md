# 在控制器中输出验证码

生成图片后，可以直接返回图片二进制，让 `<img src="...">` 请求该 URL；也可以返回包含 Base64 data URI 的 JSON，由前端赋给 `<img>` 的 `src`。两种方式使用同一组件，不需要额外的图像处理库。

## 创建控制器

在**你的 EasySwoole 应用项目根目录**新建 `App/HttpController/Captcha.php`，完整内容如下：

```php
<?php

namespace App\HttpController;

use EasySwoole\Http\AbstractInterface\Controller;
use EasySwoole\VerifyCode\Config;
use EasySwoole\VerifyCode\VerifyCode;

class Captcha extends Controller
{
    public function image(): void
    {
        $config = (new Config())
            ->setCharset('23456789ABCDEFGHJKLMNPQRSTUVWXYZ')
            ->setLength(5);
        $result = (new VerifyCode($config))->drawCode();

        $this->response()->withHeader('Content-Type', $result->getImageMime());
        $this->response()->withHeader('Cache-Control', 'no-store');
        $this->response()->write($result->getImageByte());
    }

    public function base64(): void
    {
        $result = (new VerifyCode())->drawCode();

        $this->response()->withHeader('Cache-Control', 'no-store');
        $this->writeJson(200, ['image' => $result->getImageBase64()]);
    }
}
```

`getImageByte()` 返回图片二进制，`getImageMime()` 返回当前图片格式的 MIME；Base64 方法返回的是完整的 `data:image/...;base64,...` URI，无需前端再拼接前缀。组件还有 `getImageCode()`，但**不要把它放进图片或 JSON 响应**。

## 访问接口

默认控制器映射下，`/captcha/image` 和 `/captcha/base64` 分别对应上面的两个 Action。先启动框架服务：

```bash
php easyswoole.php server start
```

服务已启动、但新增控制器尚未生效时执行 `php easyswoole.php server reload`。随后在浏览器打开 `http://127.0.0.1:9501/captcha/image`，应直接看到图片。也可从终端保存并查看：

```bash
curl -s http://127.0.0.1:9501/captcha/image -o captcha.png
curl -s http://127.0.0.1:9501/captcha/base64
```

前端用图片 URL 时：

```html
<img src="/captcha/image" alt="图片验证码">
```

用 JSON 返回的 Base64 时，把响应里的 `result.image` 赋给图片元素的 `src`。如果项目改用了显式路由，请在现有 `App/HttpController/Router.php` 中把这两个 URL 映射到 `Captcha` 的对应 Action；路由文件位置与写法见[路由基础](/Http/Routing/index.md)。

## 源码依据

- [4.x README：结果与输出](https://github.com/easy-swoole/verify-code/blob/4.x/README.md)
- [Result.php](https://github.com/easy-swoole/verify-code/blob/4.x/src/Result.php)
