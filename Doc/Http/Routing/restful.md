# RESTful 路由

本章把用户资源的所有路由集中定义在 `App/HttpController/Router.php`，并说明每条路由会进入哪个 Action。

## 先设计接口

| 方法 | 地址 | Handler | 含义 |
| --- | --- | --- | --- |
| GET | `/api/v1/users` | `/Api/User/index` | 用户列表 |
| GET | `/api/v1/users/{id}` | `/Api/User/detail` | 用户详情 |
| POST | `/api/v1/users` | `/Api/User/create` | 创建用户 |
| PUT | `/api/v1/users/{id}` | `/Api/User/update` | 完整更新 |
| PATCH | `/api/v1/users/{id}` | `/Api/User/patch` | 部分更新 |
| DELETE | `/api/v1/users/{id}` | `/Api/User/delete` | 删除用户 |

## 定义 Router

`App/HttpController/Router.php`：

```php
<?php

namespace App\HttpController;

use EasySwoole\Http\AbstractInterface\AbstractRouter;
use FastRoute\RouteCollector;

class Router extends AbstractRouter
{
    public function initialize(RouteCollector $routeCollector): void
    {
        $this->setGlobalMode(true);
        $this->parseParams(self::PARSE_PARAMS_IN_GET);

        $routeCollector->addGroup('/api/v1', function (RouteCollector $route): void {
            $route->get('/users', '/Api/User/index');
            $route->get('/users/{id:\\d+}', '/Api/User/detail');
            $route->post('/users', '/Api/User/create');
            $route->put('/users/{id:\\d+}', '/Api/User/update');
            $route->patch('/users/{id:\\d+}', '/Api/User/patch');
            $route->delete('/users/{id:\\d+}', '/Api/User/delete');
        });

        $this->setRouterNotFoundCallBack(function ($request, $response): bool {
            $response->withStatus(404);
            $response->withHeader('Content-Type', 'application/json; charset=utf-8');
            $response->write(json_encode([
                'code' => 404,
                'message' => '接口不存在',
            ], JSON_UNESCAPED_UNICODE));
            return false;
        });

        $this->setMethodNotAllowCallBack(function ($request, $response): bool {
            $response->withStatus(405);
            $response->withHeader('Content-Type', 'application/json; charset=utf-8');
            $response->write(json_encode([
                'code' => 405,
                'message' => '请求方法不允许',
            ], JSON_UNESCAPED_UNICODE));
            return false;
        });
    }
}
```

回调返回 `false`，表示响应已经完成，不再进入控制器自动映射。开启全局模式后，未声明的路由不会意外暴露控制器公开方法。

## 控制器放在哪里

上面所有 Handler 都以 `/Api/User` 开头，因此控制器文件是：

```text
App/HttpController/Api/User.php
```

类的命名空间必须是：

```php
namespace App\HttpController\Api;
```

完整的参数验证、响应和异常处理代码见“控制器 → REST API 实战”。

## 用 curl 验证方法约束

```bash
# 正确：列表
curl -i http://127.0.0.1:9501/api/v1/users

# 正确：创建
curl -i -X POST http://127.0.0.1:9501/api/v1/users \
  -H 'Content-Type: application/json' \
  -d '{"name":"Bob"}'

# 错误：该地址没有注册 DELETE，应返回 405
curl -i -X DELETE http://127.0.0.1:9501/api/v1/users

# 错误：地址不存在，应返回 404
curl -i http://127.0.0.1:9501/api/v1/not-found
```

路由只决定“请求交给谁”。JSON 解析、字段验证、数据库事务和权限判断仍由控制器及 Service 完成。
