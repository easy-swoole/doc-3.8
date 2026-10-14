# PSR 与 Swoole 原始对象

EasySwoole Request 实现了 PSR ServerRequest 接口的大部分常用能力，同时包装了 `Swoole\\Http\\Request`。业务代码优先使用框架/PSR API，只有需要 Swoole 特有字段时再访问原始对象。

## 框架 Request 从哪里获得

```php
protected function action(): void
{
    $request = $this->request();
}
```

常用接口：

```php
$request->getMethod();
$request->getUri();
$request->getHeaders();
$request->getBody();
$request->getQueryParams();
$request->getParsedBody();
$request->getCookieParams();
$request->getUploadedFiles();
$request->getServerParams();
```

请求 Attribute 可在同一次请求中传递应用数据：

```php
$request->withAttribute('currentUserId', 1001);
$userId = $request->getAttribute('currentUserId');
```

当前实现的 `with*()` 方法会修改并返回同一个对象。即便如此，业务代码也应按照接口使用，不要依赖私有属性。

## 访问 Swoole 原始对象

```php
$swooleRequest = $this->request()->getSwooleRequest();
$fd = $swooleRequest?->fd;
$server = $swooleRequest?->server ?? [];
```

新建调试控制器：

```php
class NativeRequest extends \EasySwoole\Http\AbstractInterface\Controller
{
    public function index(): void
    {
        $native = $this->request()->getSwooleRequest();
        $this->writeJson(200, [
            'fd' => $native?->fd,
            'requestTime' => $native?->server['request_time'] ?? null,
        ]);
    }
}
```

原始对象与 Swoole 版本及运行方式耦合，单元测试中也可能为 `null`。访问时应集中封装并处理空值。不要把原始 Request 保存到静态属性、异步任务或请求结束后继续使用；框架析构时会关闭 Body 并释放底层引用。

## 什么时候不需要原始对象

- 读取 Header、Cookie、Query、Form、上传文件：使用框架 Request。
- 获取 URI、方法和协议版本：使用 PSR 风格接口。
- 在中间层传当前用户：使用请求 Attribute 或协程上下文。
- 读取连接 fd、Swoole 特有 server 字段：才考虑原始对象。

直接访问 `$swooleRequest->get`、`post`、`header` 会让控制器和 Swoole 紧密耦合，也绕开框架已经完成的规范化处理。
