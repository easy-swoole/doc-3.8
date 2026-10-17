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

## 三种控制器选择

### Controller

最基础、依赖最少，适合简单接口或希望完全手动处理参数的场景。

```php
use EasySwoole\Http\AbstractInterface\Controller;
```

### AnnotationController

支持 PHP 8 Attribute、参数来源、类型转换、验证以及接口文档，是当前框架安装模板的默认选择。

```php
use EasySwoole\HttpAnnotation\AnnotationController;
```

### REST

根据 HTTP Method 自动给 Action 加前缀。例如 `/user/info` 的 GET 请求调用 `getInfo()`，POST 请求调用 `postInfo()`。

```php
use EasySwoole\Http\AbstractInterface\REST;
```

新项目通常选择 `AnnotationController`；需要传统 REST 方法前缀映射时再选择 `REST`。

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
- [REST](https://github.com/easy-swoole/http/blob/3.x/src/AbstractInterface/REST.php)
- [AnnotationController](https://github.com/easy-swoole/http-annotation/blob/4.x/src/AnnotationController.php)
