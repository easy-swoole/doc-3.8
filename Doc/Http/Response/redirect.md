# 重定向

重定向由状态码和 `Location` Header 组成。EasySwoole 提供 `redirect()`：

```php
public function oldPage(): void
{
    $this->response()->redirect('/new-page', 302);
}
```

```php
$routeCollector->get('/old-page', '/Page/oldPage');
$routeCollector->get('/new-page', '/Page/newPage');
```

```bash
curl -i http://127.0.0.1:9501/old-page
curl -i -L http://127.0.0.1:9501/old-page
```

不加 `-L` 可看到 302 和 Location，加 `-L` 会跟随跳转。

常用状态：301 永久跳转且可能被长期缓存；302 临时跳转；303 常用于 POST 成功后转到 GET 页面；307/308 保留原请求方法和 Body。登录提交后通常使用 303，避免刷新页面重复 POST：

```php
$this->response()->redirect('/dashboard', 303);
```

禁止直接重定向到用户提供的任意 URL：

```php
// 危险：形成开放重定向
$this->response()->redirect($this->request()->getQueryParam('next'));
```

可只允许以单个 `/` 开头的站内路径，并拒绝 `//evil.example`，或者把目标映射为服务端预定义名称。重定向设置后应立即 `return`，避免后续代码继续修改响应或执行敏感操作。
