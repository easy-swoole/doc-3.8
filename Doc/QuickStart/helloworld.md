# 第一个 HTTP 接口

安装器已经创建 `App/HttpController/Index.php` 和 `Router.php`。本章新建一个独立控制器，不覆盖它们：访问 `/hello` 返回文本，再访问 `/hello/greet?name=Swoole` 返回 JSON。开始前请先完成[安装框架](/QuickStart/install.md)。

## 创建控制器文件

在**你的 EasySwoole 项目根目录**创建 `App/HttpController/Hello.php`，完整内容如下：

```php
<?php

namespace App\HttpController;

use EasySwoole\Http\AbstractInterface\Controller;

class Hello extends Controller
{
    public function index(): void
    {
        $this->response()->withHeader('Content-Type', 'text/plain; charset=utf-8');
        $this->response()->write('Hello EasySwoole');
    }

    public function greet(): void
    {
        $name = $this->request()->getRequestParam('name') ?? 'EasySwoole';
        $this->writeJson(200, ['message' => "Hello {$name}"]);
    }
}
```

文件路径、`namespace App\HttpController` 和类名 `Hello` 必须对应。安装器已经在 `composer.json` 中配置 `App\` 到 `App/` 的自动加载映射，通常不需要再编辑 Composer 配置。

## 启动并访问

在第一个终端执行：

```bash
php easyswoole.php server start
```

在第二个终端执行：

```bash
curl -i http://127.0.0.1:9501/hello
curl -i 'http://127.0.0.1:9501/hello/greet?name=Swoole'
```

第一个请求的正文应为：

```text
Hello EasySwoole
```

第二个请求的正文应为：

```json
{"code":200,"result":{"message":"Hello Swoole"},"msg":null}
```

这里没有修改 `Router.php`：默认情况下，框架会把 `/hello` 映射到 `Hello::index()`，把 `/hello/greet` 映射到 `Hello::greet()`。如果出现 404，先确认文件名和命名空间；如果服务此前已启动、修改了 PHP 文件却未生效，执行：

```bash
php easyswoole.php server reload
```

`request()` 和 `response()` 是控制器内可用的方法；`getRequestParam('name')` 读取 Query/Form 参数。`writeJson()` 会写入框架统一的 `code/result/msg` 结构、HTTP 状态码和 JSON 响应头。想看 URL 到类和方法的完整映射规则，继续阅读[URL 映射与路由](/Http/Controller/routing.md)。

## 下一步学什么

- 想改端口、Worker 数量：看[配置文件](/QuickStart/config.md)。
- 想定义 `/api/users/{id}`：看[路由基础](/Http/Routing/index.md)。
- 想做参数验证：看[Attribute 参数验证](/Http/Controller/annotation.md)。
- 想理解服务为什么要 reload：看[开发者必读](/QuickStart/notice.md)。

## 源码依据

- [安装器生成的 Index 控制器](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Resource/Http/Index._php)
- [Controller](https://github.com/easy-swoole/http/blob/3.x/src/AbstractInterface/Controller.php)
