# 状态码和 Header

HTTP 状态码描述请求结果，业务 JSON 中的 `code` 不能代替真实状态码。

```php
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
```

注册 `$routeCollector->post('/users', '/User/create')` 后用 `curl -i -X POST` 查看状态行和 Header。

常用状态：200 查询成功，201 创建成功，204 成功且无 Body，400 请求语法错误，401 未认证，403 无权限，404 不存在，405 方法不允许，409 状态冲突，422 字段验证失败，429 请求过多，500 未知服务异常。

Header API：

```php
$response->withHeader('Cache-Control', 'no-store');       // 覆盖
$response->withAddedHeader('X-Tag', 'one');               // 追加
$response->withoutHeader('X-Debug');                      // 删除
$response->getHeaderLine('Content-Type');                 // 读取
```

Header 必须在响应真正发送前设置。名称和值不得包含换行，避免 Header 注入。认证接口通常使用 `Cache-Control: no-store`；缓存策略要根据资源是否公开、是否因用户而变化设计。

204 响应不要再写 Body：

```php
$this->response()->withStatus(204);
```
