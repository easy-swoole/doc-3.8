# 路由基础

本章接着[第一个 HTTP 接口](/QuickStart/helloworld.md)往下做：保留已有的 `Hello.php`，在安装器生成的 `Router.php` 中增加一条显式路由。完成后访问 `GET /api/hello?name=Swoole`，会执行 `Hello::greet()`。

## 路由写在哪里

EasySwoole 会在 HTTP 控制器命名空间中寻找名为 `Router` 的类。默认项目的控制器命名空间是 `App\\HttpController`，所以路由文件固定放在：

```text
项目根目录/
├── App/
│   └── HttpController/
│       ├── Index.php
│       ├── Hello.php       ← 上一章创建的控制器
│       └── Router.php       ← 在这里统一定义路由
├── vendor/
├── composer.json
└── easyswoole.php
```

文件名、类名和命名空间必须分别是 `Router.php`、`Router`、`App\\HttpController`。Linux 区分大小写。

安装器已经生成 `App/HttpController/Router.php`。入门练习可把这个文件**完整替换**为以下代码。它会移除安装器自带的 `/router` 和 `/closure` 演示路由，不影响 `/` 欢迎页和 `/hello` 的自动映射；如果你的项目已在 `Router.php` 中定义业务路由，就只把 `get('/api/hello', '/Hello/greet')` 那一行加进现有的 `initialize()`，不要覆盖业务路由。

```php
<?php

namespace App\HttpController;

use EasySwoole\Http\AbstractInterface\AbstractRouter;
use FastRoute\RouteCollector;

class Router extends AbstractRouter
{
    public function initialize(RouteCollector $routeCollector): void
    {
        $routeCollector->get('/api/hello', '/Hello/greet');
    }
}
```

不需要在其他配置文件中再次注册 `Router`。框架会自动查找 `App\\HttpController\\Router`，实例化它并调用 `initialize()`。

## 路由与控制器如何对应

上面的 `'/Hello/greet'` 不是文件路径，而是“控制器/Action”。它对应上一章创建的 `App/HttpController/Hello.php` 中的 `greet()`，这里不需要改动控制器。


映射关系如下：

```text
GET /api/hello?name=Swoole
    ↓ Router.php 中匹配
/Hello/greet
    ↓
App\HttpController\Hello::greet()
```

## 启动并验证

如果服务尚未运行，在第一个终端、项目根目录执行：

```bash
php easyswoole.php server start
```

如果服务已经运行并且刚修改了 `Router.php`，先执行 `php easyswoole.php server reload`，不要再次启动服务。然后在第二个终端执行：

```bash
curl -i 'http://127.0.0.1:9501/api/hello?name=Swoole'
```

预期响应包含：

```json
{"code":200,"result":{"message":"Hello Swoole"},"msg":null}
```

## 支持哪些 HTTP 方法

`RouteCollector` 提供常见方法：

```php
$routeCollector->get('/users', '/User/index');
$routeCollector->post('/users', '/User/create');
$routeCollector->put('/users/{id}', '/User/update');
$routeCollector->patch('/users/{id}', '/User/patch');
$routeCollector->delete('/users/{id}', '/User/delete');

// 同一路径允许多个方法
$routeCollector->addRoute(['GET', 'HEAD'], '/health', '/Index/health');
```

## `pathInfoMode`：路由到底拿哪一条路径匹配

`pathInfoMode` 决定的是：**FastRoute 应使用处理过的 PathInfo，还是使用浏览器传来的原始 URI Path 进行匹配**。

它在 `App/HttpController/Router.php` 的 `initialize()` 中设置：

```php
public function initialize(RouteCollector $routeCollector): void
{
    // true 是默认值，也可以不写。
    $this->setPathInfoMode(true);

    $routeCollector->get('/article/detail', '/Article/detail');
}
```

### 开启：`setPathInfoMode(true)`

这是默认模式。框架先调用 `EasySwoole\\Http\\UrlParser::pathInfo()` 处理请求路径，再交给 FastRoute 匹配。

处理规则可以简单理解为：**去掉最后一段的扩展名，并把末尾的 `index.*` 当成当前目录**。

| 浏览器请求的 URI Path | 实际用于路由匹配的路径 |
| --- | --- |
| `/article/detail` | `/article/detail` |
| `/article/detail.html` | `/article/detail` |
| `/article/detail.json` | `/article/detail` |
| `/index.php` | `/` |
| `/api/index.php` | `/api` |

因此只需注册一条不带扩展名的路由：

```php
$this->setPathInfoMode(true);
$routeCollector->get('/article/detail', '/Article/detail');
```

以下三个请求都会命中它：

```bash
curl http://127.0.0.1:9501/article/detail
curl http://127.0.0.1:9501/article/detail.html
curl http://127.0.0.1:9501/article/detail.json
```

这种模式适合传统控制器页面，或者希望兼容 `.html` 伪静态地址的项目。但请注意：`.json`、`.html` 等后缀不会再参与路由区分，不能用它们表示不同接口。

### 关闭：`setPathInfoMode(false)`

关闭后，FastRoute 直接使用原始 URI Path，扩展名会被保留：

```php
public function initialize(RouteCollector $routeCollector): void
{
    $this->setPathInfoMode(false);

    $routeCollector->get('/article/detail', '/Article/detail');
    $routeCollector->get('/article/detail.json', '/Article/detailJson');
    $routeCollector->get('/docs/{path:.+\\.md}', '/Document/read');
}
```

匹配结果变为：

| 请求 | 匹配的路由 |
| --- | --- |
| `/article/detail` | `/article/detail` |
| `/article/detail.json` | `/article/detail.json` |
| `/article/detail.html` | 未注册，返回 404 |
| `/docs/quick-start.md` | `/docs/{path:.+\\.md}` |

关闭模式适合以下情况：

- 路由本身需要匹配 `.md`、`.json`、`.css` 等扩展名。
- 同一个基础路径需要根据后缀进入不同处理器。
- 文档系统、静态资源代理或兼容已有的带后缀 URL。

### 两种模式的完整对比

| 对比项 | `true`（默认） | `false` |
| --- | --- | --- |
| FastRoute 匹配输入 | 处理后的 PathInfo | 原始 URI Path |
| 是否去掉最后一段扩展名 | 是 | 否 |
| `/index.php` | 作为 `/` 匹配 | 按 `/index.php` 匹配 |
| `/api/index.php` | 作为 `/api` 匹配 | 按 `/api/index.php` 匹配 |
| 适用场景 | 控制器路由、伪静态页面 | 文件后缀路由、文档与资源地址 |

### 它不影响 Query String

无论开启还是关闭，路由匹配的都只是 URI Path。查询参数不会参与匹配：

```text
/users?page=2&size=20
```

用于匹配的仍是 `/users`，`page` 和 `size` 应通过 Request 读取。

### 它是 Router 级配置

`setPathInfoMode()` 不是只控制紧随其后的一条路由，而是影响当前 `Router` 中所有显式路由。不能在同一个 Router 中让一部分路由使用 `true`、另一部分使用 `false`。

如果项目既有普通 API，又要匹配 Markdown 文件，可以统一关闭并把所有路由写成实际需要的完整路径：

```php
public function initialize(RouteCollector $routeCollector): void
{
    $this->setPathInfoMode(false);

    $routeCollector->get('/api/users', '/Api/User/index');
    $routeCollector->get('/docs/{path:.+\\.md}', '/Document/read');
}
```

### 它只改变显式路由的匹配路径

从组件的 `Dispatcher` 流程看，`pathInfoMode` 用于选择 FastRoute 的匹配输入；控制器自动映射和字符串 Handler 最终仍会经过 `UrlParser::pathInfo()`。

例如关闭模式后注册：

```php
$routeCollector->get('/docs/{path:.+\\.md}', '/Document/read');
```

`/docs/start.md` 可以按完整后缀命中这条路由，然后 Handler `/Document/read` 再被解析为 `Document::read()`。不要把 Handler 写成带 `.php` 的文件名。

### 如何确认自己的设置

可以临时注册两条测试路由：

```php
$this->setPathInfoMode(false);
$routeCollector->get('/mode/test', '/Hello/index');
$routeCollector->get('/mode/test.html', '/Hello/greet');
```

reload 后分别请求：

```bash
php easyswoole.php server reload
curl -i http://127.0.0.1:9501/mode/test
curl -i http://127.0.0.1:9501/mode/test.html
```

第一条应返回文本 `Hello EasySwoole`，第二条应返回 JSON。两个 Action 都在快速开始创建的 `Hello.php` 中。如果切换为 `true`，它们会被规范化到同一个 `/mode/test`，FastRoute 会把它们视为重复路由，因此不能同时注册。

## 自动映射和显式路由的区别

即使没有 `Router.php`，框架也能把 `/user/detail` 自动映射到 `App\\HttpController\\User::detail()`。显式路由的价值在于约束请求方法、隐藏内部类结构，并为公共 API 提供稳定地址。

默认情况下，显式路由没有匹配时仍会尝试自动映射。如果项目只允许声明过的路由，在 `initialize()` 开头开启全局模式：

```php
$this->setGlobalMode(true);
```

开启后应同时配置 404 和 405 回调，否则未匹配请求可能只得到空响应。相关处理参见“异常与安全”中的“404 与 405”小节。

## 常见错误

- 修改路由后没有 reload，常驻 Worker 仍运行旧代码。
- 把文件放到 `App/Router.php`，框架默认不会找到它。
- Handler 写成 PHP 文件路径；它应写成 `/控制器/Action`。
- Router 没有继承 `AbstractRouter`，框架会抛出路由类型错误。
- 请求方法不一致，例如只注册 POST，却直接在浏览器地址栏用 GET 访问。

下一章将给 `/users/{id}` 加上动态参数并演示两种读取方式。
