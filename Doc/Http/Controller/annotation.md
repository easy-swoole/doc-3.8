# Attribute 参数验证

`AnnotationController` 使用 PHP 8 Attribute 声明 HTTP 方法、参数来源、类型和验证规则。适合参数较多、需要统一验证及接口文档的项目。

## 基本示例

```php
<?php

namespace App\HttpController;

use EasySwoole\HttpAnnotation\AnnotationController;
use EasySwoole\HttpAnnotation\Attributes\Api;
use EasySwoole\HttpAnnotation\Attributes\ApiGroup;
use EasySwoole\HttpAnnotation\Attributes\Param;
use EasySwoole\HttpAnnotation\Enum\HttpMethod;
use EasySwoole\HttpAnnotation\Enum\ParamFrom;
use EasySwoole\HttpAnnotation\Enum\ParamType;
use EasySwoole\HttpAnnotation\Validator\Min;
use EasySwoole\HttpAnnotation\Validator\Required;

#[ApiGroup(groupName: 'User')]
class User extends AnnotationController
{
    #[Api(
        allowMethod: HttpMethod::GET,
        requestParam: [
            new Param(
                name: 'id',
                from: ParamFrom::GET,
                type: ParamType::INT,
                validate: [new Required(), new Min(1)]
            ),
        ]
    )]
    public function detail(int $id): void
    {
        $this->writeJson(200, ['id' => $id]);
    }
}
```

方法形参名必须与 `Param(name: ...)` 一致。

## 给 `onRequest()` 声明公共参数

有些参数不是某一个 Action 独有，而是当前控制器的所有接口都要使用。例如：

- `Authorization`：登录 Token。
- `x-tenant-id`：租户编号。
- `x-request-id`：请求追踪编号。

如果在每个 `#[Api]` 中重复声明这些参数，代码会很长，也容易出现某个接口漏掉验证。`AnnotationController` 允许直接在 `onRequest()` 上使用可重复的 `#[Param]`，把它们定义为公共参数。

下面建立一个管理员控制器，要求所有 Action 携带 Token 和租户编号。

### 完整控制器示例

新建 `App/HttpController/Admin/User.php`：

```php
<?php

namespace App\HttpController\Admin;

use EasySwoole\HttpAnnotation\AnnotationController;
use EasySwoole\HttpAnnotation\Attributes\Api;
use EasySwoole\HttpAnnotation\Attributes\Param;
use EasySwoole\HttpAnnotation\Enum\HttpMethod;
use EasySwoole\HttpAnnotation\Enum\ParamFrom;
use EasySwoole\HttpAnnotation\Enum\ParamType;
use EasySwoole\HttpAnnotation\Validator\Min;
use EasySwoole\HttpAnnotation\Validator\NotEmpty;
use EasySwoole\HttpAnnotation\Validator\Required;

class User extends AnnotationController
{
    protected ?int $tenantId = null;

    #[Param(
        name: 'authorization',
        from: ParamFrom::HEADER,
        validate: [new Required(), new NotEmpty()],
        description: '管理员登录 Token'
    )]
    #[Param(
        name: 'x-tenant-id',
        from: ParamFrom::HEADER,
        type: ParamType::INT,
        validate: [new Required(), new Min(1)],
        description: '当前租户 ID'
    )]
    protected function onRequest(?string $action, ?array $data = null): ?bool
    {
        // $action 是即将执行的 Action 方法名，例如 index 或 detail。
        // $data 是组件根据上面两个 Param 解析、转换并验证后的结果。
        $token = $data['authorization'] ?? '';
        $tenantId = $data['x-tenant-id'] ?? null;

        if ($token !== 'Bearer demo-admin-token') {
            $this->writeJson(401, null, '登录状态无效');
            return false;
        }

        // Controller 每次请求都会重新创建，可以保存本次请求的数据。
        $this->tenantId = $tenantId;

        return true;
    }

    public function index(): void
    {
        $this->writeJson(200, [
            'tenantId' => $this->tenantId,
            'users' => [
                ['id' => 1, 'name' => 'Alice'],
            ],
        ]);
    }
}
```

`onRequest()` 的第二个参数必须能够接收数组：

```php
protected function onRequest(?string $action, ?array $data = null): ?bool
```

这两个形参的含义如下：

| 形参 | 内容 |
| --- | --- |
| `$action` | 即将执行的 Action 名，例如 `index`、`detail` |
| `$data` | `onRequest()` 上所有 `#[Param]` 解析并验证后的键值数组 |

本例请求成功时，`$data` 的内容是：

```php
[
    'authorization' => 'Bearer demo-admin-token',
    'x-tenant-id' => 1001,
]
```

因为 `x-tenant-id` 声明了 `type: ParamType::INT`，所以传入 `onRequest()` 的值已经转换为整数。

### 注册并测试路由

在 `App/HttpController/Router.php` 的 `initialize()` 中加入：

```php
$routeCollector->get('/admin/users', '/Admin/User/index');
```

reload 后测试：

```bash
php easyswoole server reload

curl -i http://127.0.0.1:9501/admin/users \
  -H 'Authorization: Bearer demo-admin-token' \
  -H 'x-tenant-id: 1001'
```

预期返回 200，并且响应中的 `tenantId` 为整数 `1001`。

缺少租户 Header：

```bash
curl -i http://127.0.0.1:9501/admin/users \
  -H 'Authorization: Bearer demo-admin-token'
```

此时 `Required` 验证失败，组件会在调用 `onRequest()` 之前抛出 `ParamValidateFail`，`onRequest()` 和 `index()` 都不会执行。项目应在 `onException()` 或上层异常处理器中把它转换为统一的 4xx 响应。

### 公共参数的执行顺序

组件不是先进入 `onRequest()` 再读取 Attribute。实际顺序是：

```text
读取 onRequest 上的 #[Param]
            ↓
读取当前 Action 上的 #[Api(requestParam: ...)]（如果存在）
            ↓
合并公共参数与 Action 参数
            ↓
从 Request 取值并完成类型转换
            ↓
验证 onRequest 公共参数
            ↓
验证 Action 参数
            ↓
onRequest($action, $data)
            ↓ 返回 false 时跳过 Action
执行目标 Action
```

因此 `$data` 收到的不是原始 Header 数组，而是已经按照 `Param` 定义处理过的公共参数。

### Header 参数名应使用小写

Swoole 请求头在框架内部统一为小写，组件读取 Header 时也会将 `Param` 名转换为小写。建议声明时直接使用小写名称：

```php
#[Param(name: 'authorization', from: ParamFrom::HEADER)]
#[Param(name: 'x-tenant-id', from: ParamFrom::HEADER)]
```

客户端仍可以发送常见形式的 `Authorization` 或 `X-Tenant-Id`，HTTP Header 名本身不区分大小写。

### Action 可以覆盖同名公共参数

如果当前 Action 的 `#[Api]` 又声明了同名参数，Action 定义优先。例如公共 `tenantId` 默认从 Header 获取，但某个内部接口要求从 Query 获取：

```php
#[Api(
    allowMethod: HttpMethod::POST,
    requestParam: [
        new Param(
            name: 'x-tenant-id',
            from: ParamFrom::GET,
            type: ParamType::INT,
            validate: [new Required(), new Min(1)]
        ),
    ]
)]
public function switchTenant(): void
{
}
```

组件会用 Action 中的定义覆盖 `onRequest()` 上的同名定义。覆盖后的值仍会通过 `$data['x-tenant-id']` 传给 `onRequest()`。

为了便于维护，通常不建议让同一参数在不同接口中频繁改变来源；这里主要用于说明合并规则。

当前 4.x 组件还会在扫描阶段检查：声明为 `GET` 的 `#[Api]`，其适用的公共参数来源必须包含 `ParamFrom::GET`，或者由 Action 同名覆盖、通过 `ignoreAction` 排除。因此上面的完整示例由 Router 限制 GET 方法，没有在 `index()` 上重复声明 `#[Api(allowMethod: HttpMethod::GET)]`。如果项目要同时使用 GET 的 `#[Api]` 和 Header 公共参数，需要针对该 Action 同名覆盖 Header 参数；不要为了绕过检查而允许 Token 从 Query String 传入。

### 为登录 Action 忽略 Token 参数

登录接口本身还没有 Token，可以在公共参数的 `ignoreAction` 中将它排除：

```php
#[Param(
    name: 'authorization',
    from: ParamFrom::HEADER,
    validate: [new Required(), new NotEmpty()],
    ignoreAction: ['login']
)]
protected function onRequest(?string $action, ?array $data = null): ?bool
{
    if ($action === 'login') {
        return true;
    }

    $token = $data['authorization'] ?? '';
    if ($token !== 'Bearer demo-admin-token') {
        $this->writeJson(401, null, '登录状态无效');
        return false;
    }

    return true;
}
```

访问 `login` 时，`authorization` 不会进入 `$data`，也不会执行它的 `Required` 验证。因此读取时应使用 `$data['authorization'] ?? ''`，不能假设键一定存在。

`ignoreAction` 填写的是 Action 方法名 `login`，不是 URL `/admin/login`。只应豁免确实允许匿名访问的少量接口。

## 参数来源

`ParamFrom` 支持：

| 来源 | 说明 |
| --- | --- |
| `GET` | Query 参数 |
| `POST` | 表单字段 |
| `JSON` | JSON 请求体字段 |
| `XML` | XML 请求体字段 |
| `RAW_POST` | 完整原始请求体 |
| `FILE` | 上传文件对象 |
| `HEADER` | Header，key 按小写处理 |
| `COOKIE` | Cookie |
| `DI` | 依赖注入容器 |
| `CONTEXT` | 协程上下文 |

`from` 可传单个来源或数组，数组按声明顺序取第一个命中值。FILE 必须是唯一来源。

## 请求方法和 Content-Type

- GET、HEAD 不允许请求体来源，`acceptContentType` 必须为 `null`。
- POST 等方法默认使用 `FORM_DATA`。
- JSON 参数必须配合 `ContentType::JSON`。
- XML、RAW、FILE 同样需要对应 Content-Type。

```php
#[Api(
    allowMethod: HttpMethod::POST,
    acceptContentType: ContentType::JSON,
    requestParam: [
        new Param(name: 'name', from: ParamFrom::JSON),
    ]
)]
public function create(string $name): void
{
}
```

当前运行时会检查 HTTP Method，但不会单独校验请求头中的实际 Content-Type。对 Content-Type 有严格要求时，应在前置逻辑中再检查。

## 数组接收参数

Action 只有一个 `array` 形参时，所有接口参数会被打包：

```php
public function create(array $data): void
{
    $name = $data['name'];
}
```

`ignorePassArgWhenNotSet: true` 只在这种数组模式中生效。

## 可选参数

```php
new Param(
    name: 'keyword',
    from: ParamFrom::GET,
    validate: [new Optional()],
    value: '',
    ignorePassArgWhenNotSet: true
)
```

可选类规则不能和 `Required`、`NotEmpty` 等必填规则混用，最新版组件会在解析 Attribute 时直接报错。

## 验证失败

验证失败会抛出 `ParamValidateFail`，应在控制器的 `onException()` 中转换为 422 或项目统一错误格式，详见“异常与错误处理”。

## 源码依据

- [HTTP Annotation 4.x README](https://github.com/easy-swoole/http-annotation/tree/4.x)
- [Param](https://github.com/easy-swoole/http-annotation/blob/4.x/src/Attributes/Param.php)
- [Api](https://github.com/easy-swoole/http-annotation/blob/4.x/src/Attributes/Api.php)
