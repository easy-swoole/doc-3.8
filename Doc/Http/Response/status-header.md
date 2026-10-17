# 状态码和 Header

HTTP 状态码描述请求结果，业务 JSON 中的 `code` 不能代替真实状态码。本节接着[文本、HTML 与 JSON](/Http/Response/content.md)的项目操作。

## 创建接口返回 201

新建 `App/HttpController/StatusDemo.php`：

```php
<?php

namespace App\HttpController;

use EasySwoole\Http\AbstractInterface\Controller;

class StatusDemo extends Controller
{
    public function create(): void
    {
        $response = $this->response();
        $response->withStatus(201);
        $response->withHeader('Content-Type', 'application/json; charset=utf-8');
        $response->withHeader('Location', '/users/1001');
        $response->withHeader('X-Request-Id', 'req-1001');
        $response->write(json_encode([
            'id' => 1001,
            'name' => 'Alice',
        ], JSON_UNESCAPED_UNICODE));
    }

    public function noContent(): void
    {
        $this->response()->withStatus(204);
    }
}
```

在已有 `App/HttpController/Router.php` 的 `initialize(RouteCollector $routeCollector)` 中加入两行，保留原有路由：

```php
$routeCollector->post('/status/users', '/StatusDemo/create');
$routeCollector->delete('/status/users/{id:\d+}', '/StatusDemo/noContent');
```

```bash
php easyswoole.php server reload
curl -i -X POST http://127.0.0.1:9501/status/users
curl -i -X DELETE http://127.0.0.1:9501/status/users/1001
```

第一条请求应看到 `201 Created`、`Location: /users/1001`、`X-Request-Id: req-1001` 和 JSON Body。第二条应看到 `204 No Content`，且没有 Body。此处只是演示状态码，不会真的写数据库。

## 常用状态码

常用状态：200 查询成功，201 创建成功，204 成功且无 Body，400 请求语法错误，401 未认证，403 无权限，404 不存在，405 方法不允许，409 状态冲突，422 字段验证失败，429 请求过多，500 未知服务异常。

## 操作 Header

在控制器方法中，可以通过 `$this->response()` 调用以下方法：

```php
$response = $this->response();
$response->withHeader('Cache-Control', 'no-store');       // 覆盖
$response->withAddedHeader('X-Tag', 'one');               // 追加
$response->withoutHeader('X-Debug');                      // 删除
$response->getHeaderLine('Content-Type');                 // 读取
```

Header 必须在响应真正发送前设置。名称和值不得包含换行，避免 Header 注入。认证接口通常使用 `Cache-Control: no-store`；缓存策略要根据资源是否公开、是否因用户而变化设计。

204 响应不要再写 Body。
