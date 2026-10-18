# 认识控制器

控制器是 HTTP 请求进入业务代码的入口。Dispatcher 根据 URL 找到控制器和 Action，构造控制器对象，并把当前请求、响应对象交给它处理。

## 第一个控制器

沿用[第一个 HTTP 接口](/QuickStart/helloworld.md)中创建的 `App/HttpController/Hello.php`，不要覆盖安装模板自带的 `Index.php`。如果跳过了快速开始，可新建这个文件：

```php
<?php

namespace App\HttpController;

use EasySwoole\Http\AbstractInterface\Controller;

class Hello extends Controller
{
    public function index(): void
    {
        $this->response()->write('Hello EasySwoole');
    }
}
```

请求：

```bash
php easyswoole.php server reload
curl http://127.0.0.1:9501/Hello/index
```

预期输出是 `Hello EasySwoole`。这里的 `/Hello/index` 分别对应类名 `Hello` 和公开方法 `index()`；如果你已按快速开始注册 `/api/hello`，也可访问 `http://127.0.0.1:9501/api/hello`。修改控制器文件后先执行 reload；如果服务尚未启动，请先按[启动 HTTP 服务](/Http/Basics/start.md)启动。

## 控制器里有什么

基础 `Controller` 提供这些核心能力：

```php
$request = $this->request();       // 当前请求
$response = $this->response();     // 当前响应
$action = $this->getActionName();  // 当前 Action 名称

$this->writeJson(200, ['ok' => true]);
$json = $this->json();
$xml = $this->xml();
```

其中 `request()`、`response()` 和 `getActionName()` 是 `protected`，用于控制器内部及子类。

## 本章使用的控制器基类

本章只使用 `EasySwoole\Http\AbstractInterface\Controller`。它不要求为类或 Action 写 Attribute；参数可通过 `$this->request()` 手动读取，响应通过 `$this->response()` 或 `writeJson()` 写入。想声明参数来源、自动校验并生成接口文档，读完普通控制器后再看[注解控制器](/Http/AnnotationController/index.md)。

## 可访问的 Action

Dispatcher 只调用公开、非静态、且未被框架禁止的实例方法。不要把内部辅助方法声明为 `public`，否则它可能被 URL 当作 Action 访问。

```php
private function findUser(int $id): ?array
{
    // 内部方法使用 private/protected
}
```

## 建议目录

```text
App/HttpController/
├── Router.php
├── Index.php
├── User.php
└── Admin/
    └── User.php
```

下一章将说明这些文件如何映射到 URL。

## 源码依据

- [Controller](https://github.com/easy-swoole/http/blob/3.x/src/AbstractInterface/Controller.php)
