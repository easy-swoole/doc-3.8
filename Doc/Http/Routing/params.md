# 路由参数

本章在上一章的 `App/HttpController/Router.php` 中增加用户详情路由，并在控制器里读取 `{id}`。

## 定义动态参数

完整的 `Router.php` 如下：

```php
<?php

namespace App\HttpController;

use EasySwoole\Http\AbstractInterface\AbstractRouter;
use FastRoute\RouteCollector;

class Router extends AbstractRouter
{
    public function initialize(RouteCollector $routeCollector): void
    {
        // 将 FastRoute 匹配出的路径参数合并到 GET 参数。
        $this->parseParams(self::PARSE_PARAMS_IN_GET);

        $routeCollector->get('/users/{id:\\d+}', '/User/detail');
    }
}
```

`{id:\\d+}` 表示参数名是 `id`，并且只匹配数字：

- `/users/42`：匹配，`id` 为 `42`。
- `/users/abc`：不匹配，进入 404 处理。
- `/users/42?source=search`：路径参数和查询参数都可读取。

## 在控制器中读取

新建 `App/HttpController/User.php`：

```php
<?php

namespace App\HttpController;

use EasySwoole\Http\AbstractInterface\Controller;

class User extends Controller
{
    public function detail(): void
    {
        $id = (int) $this->request()->getRequestParam('id');

        if ($id < 1) {
            $this->writeJson(422, null, 'id 必须是正整数');
            return;
        }

        $this->writeJson(200, [
            'id' => $id,
            'name' => 'User ' . $id,
        ]);
    }
}
```

验证：

```bash
php easyswoole server reload
curl http://127.0.0.1:9501/users/42
```

## 默认的 Context 模式

如果不调用 `parseParams()`，默认值是 `PARSE_PARAMS_IN_CONTEXT`。此时路径参数不会自动进入 Query，需要从协程上下文读取：

```php
use EasySwoole\Component\Context\ContextManager;
use EasySwoole\Http\AbstractInterface\AbstractRouter;

$params = ContextManager::getInstance()->get(
    AbstractRouter::PARSE_PARAMS_CONTEXT_KEY
);
$id = (int) ($params['id'] ?? 0);
```

两种方案的选择：

- `PARSE_PARAMS_IN_GET`：入门更直观，Attribute 控制器也容易把路径参数当 GET 参数验证。
- `PARSE_PARAMS_IN_CONTEXT`：严格区分路径参数与 URL Query，适合封装统一的参数读取器。
- `PARSE_PARAMS_IN_POST`：会合并到 Parsed Body，一般不建议把路径参数和请求体混在一起。
- `PARSE_PARAMS_NONE`：只匹配但不注入参数。

`parseParams()` 是 Router 的全局策略，不是只影响它后面的一条路由。一个项目应统一选定读取方式。

## 可选参数与多个参数

FastRoute 的可选段必须放在路径末尾：

```php
$routeCollector->get('/articles[/{page:\\d+}]', '/Article/index');
$routeCollector->get(
    '/teams/{teamId:\\d+}/members/{memberId:\\d+}',
    '/Team/member'
);
```

正则仅限制路径形状。资源是否存在、当前用户是否有权访问，仍要在 Service 中判断。

## 参数覆盖规则

使用 `PARSE_PARAMS_IN_GET` 时，框架以路径参数优先的方式合并 Query。比如访问 `/users/42?id=99`，最终 `id` 是 `42`。即便如此，也不要设计同名的路径参数和查询参数表达不同含义。
