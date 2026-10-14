# 路由分组

当接口增多后，可以用路由分组统一 `/api/v1` 等前缀。分组仍然写在 `App/HttpController/Router.php` 的 `initialize()` 中。

## 完整示例

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

        $routeCollector->addGroup('/api/v1', function (RouteCollector $group): void {
            $group->get('/users', '/Api/User/index');
            $group->get('/users/{id:\\d+}', '/Api/User/detail');
            $group->post('/users', '/Api/User/create');
        });
    }
}
```

注意方法名是 `addGroup()`，不是 `group()`。回调参数仍是 FastRoute 的 `RouteCollector`。

对应控制器建议放到子目录：

```text
App/HttpController/
├── Router.php
└── Api/
    └── User.php
```

`App/HttpController/Api/User.php`：

```php
<?php

namespace App\HttpController\Api;

use EasySwoole\Http\AbstractInterface\Controller;

class User extends Controller
{
    public function index(): void
    {
        $this->writeJson(200, [['id' => 1, 'name' => 'Alice']]);
    }

    public function detail(): void
    {
        $id = (int) $this->request()->getRequestParam('id');
        $this->writeJson(200, ['id' => $id, 'name' => 'Alice']);
    }

    public function create(): void
    {
        $name = (string) $this->request()->getRequestParam('name');
        $this->writeJson(201, ['id' => 2, 'name' => $name]);
    }
}
```

验证三条路由：

```bash
curl http://127.0.0.1:9501/api/v1/users
curl http://127.0.0.1:9501/api/v1/users/1
curl -X POST http://127.0.0.1:9501/api/v1/users -d 'name=Bob'
```

## 嵌套分组

`addGroup()` 可以嵌套，前缀会依次拼接：

```php
$routeCollector->addGroup('/api', function (RouteCollector $api): void {
    $api->addGroup('/v1', function (RouteCollector $v1): void {
        $v1->get('/users', '/Api/User/index');
    });
});
```

分组本身只负责路径前缀，并不会自动增加鉴权中间件。当前版本中，可让 `/Api` 下的控制器继承同一个 `BaseController`，在 `onRequest()` 中集中认证。
