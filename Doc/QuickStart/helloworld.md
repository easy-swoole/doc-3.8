# HelloWorld

EasySwoole 默认从 `App\\HttpController` 命名空间查找控制器。创建 `App/HttpController/Index.php`：

```php
<?php

namespace App\HttpController;

use EasySwoole\Http\AbstractInterface\Controller;

class Index extends Controller
{
    public function index(): void
    {
        $this->response()
            ->withHeader('Content-Type', 'text/plain; charset=utf-8');
        $this->response()->write('Hello EasySwoole');
    }
}
```

启动服务：

```bash
php easyswoole.php server start
```

访问：

```bash
curl http://127.0.0.1:9501/
```

输出：

```text
Hello EasySwoole
```

## 添加一个 Action

```php
public function hello(): void
{
    $name = $this->request()->getRequestParam('name') ?? 'EasySwoole';
    $this->writeJson(200, ['message' => "Hello {$name}"]);
}
```

请求：

```bash
curl 'http://127.0.0.1:9501/index/hello?name=Swoole'
```

控制器中的 `request()` 和 `response()` 是受保护方法，只能在控制器及其子类内部调用。`writeJson()` 会同时写入 JSON、状态码和 `application/json` 响应头。

## 使用 AnnotationController

需要参数类型转换、验证或接口属性时，可以继承框架默认安装器使用的 `AnnotationController`：

```php
use EasySwoole\HttpAnnotation\AnnotationController;
use EasySwoole\HttpAnnotation\Attributes\Api;
use EasySwoole\HttpAnnotation\Attributes\Param;
use EasySwoole\HttpAnnotation\Validator\NotEmpty;

class Index extends AnnotationController
{
    #[Api(requestParam: [
        new Param(name: 'name', validate: [new NotEmpty()]),
    ])]
    public function hello(string $name): void
    {
        $this->writeJson(200, ['message' => "Hello {$name}"]);
    }
}
```

Action 必须是允许反射调用的公开实例方法，方法参数名称应与 `Param` 名称一致。

## 源码依据

- [默认 Index 控制器](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Resource/Http/Index._php)
- [Controller](https://github.com/easy-swoole/http/blob/3.x/src/AbstractInterface/Controller.php)
