# URL 映射与路由

EasySwoole 提供两层路由：自动控制器映射和显式 FastRoute。建议先理解自动映射，再用显式路由设计稳定的公共 API。

## 自动控制器映射

根命名空间是 `App\\HttpController`：

| URL | 控制器 | Action |
| --- | --- | --- |
| `/` | `Index` | `index()` |
| `/user/detail` | `User` | `detail()` |
| `/admin/user/list` | `Admin\\User` | `list()` |
| `/admin/user/` | `Admin\\User` | `index()` |

控制器类名由 URL 分段首字母大写得到。Linux 文件系统区分大小写，文件名、类名和命名空间应保持一致。

## 显式路由

创建 `App/HttpController/Router.php`：

```php
<?php

namespace App\HttpController;

use EasySwoole\Http\AbstractInterface\AbstractRouter;
use FastRoute\RouteCollector;

class Router extends AbstractRouter
{
    public function initialize(RouteCollector $routeCollector): void
    {
        $this->parseParams(self::PARSE_PARAMS_IN_GET);

        $routeCollector->get('/users/{id:\\d+}', '/user/detail');
        $routeCollector->post('/users', '/user/create');
        $routeCollector->put('/users/{id:\\d+}', '/user/update');
        $routeCollector->delete('/users/{id:\\d+}', '/user/delete');
    }
}
```

Handler `/user/detail` 表示 `App\\HttpController\\User::detail()`，不是完整类名。

## 路径参数

上例使用 `PARSE_PARAMS_IN_GET`，Action 可以这样读取：

```php
$id = (int)$this->request()->getRequestParam('id');
```

默认模式是 `PARSE_PARAMS_IN_CONTEXT`：

```php
use EasySwoole\Component\Context\ContextManager;
use EasySwoole\Http\AbstractInterface\AbstractRouter;

$params = ContextManager::getInstance()
    ->get(AbstractRouter::PARSE_PARAMS_CONTEXT_KEY);
```

## 匹配带扩展名的路径

默认 pathInfo 模式会移除扩展名。要匹配 Markdown 等原始路径：

```php
$this->setPathInfoMode(false);
$routeCollector->get('/{docPath:.+\\.md}', '/parseDoc');
```

## 路由回调

```php
use EasySwoole\Http\Request;
use EasySwoole\Http\Response;

$routeCollector->get('/health', function (Request $request, Response $response) {
    $response->withHeader('Content-Type', 'application/json; charset=utf-8');
    $response->write('{"status":"ok"}');
    return false;
});
```

- 返回 `false`：已经处理完成，不再进入控制器。
- 返回 `'/user/detail'`：转发到指定 Action。
- 返回其他值：非全局模式下继续自动映射。

## 只允许显式路由

```php
$this->setGlobalMode(true);
```

开启后，未匹配 Router 的请求不会回退到自动控制器映射，适合希望严格控制公开接口的项目。

## 源码依据

- [Dispatcher](https://github.com/easy-swoole/http/blob/3.x/src/Dispatcher.php)
- [AbstractRouter](https://github.com/easy-swoole/http/blob/3.x/src/AbstractInterface/AbstractRouter.php)
