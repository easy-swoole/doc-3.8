# onRequest 公共参数与继承

`#[Param]` 可以直接标在控制器的 `onRequest()` 上，而且可以重复。与 `Api::requestParam` 不同，这些参数适用于该控制器的多个 Action；组件在调用 `onRequest()` **之前**完成读取、转换和验证，把结果作为第二个参数 `$data` 传入。第一个参数 `$action` 是当前 Action 名称。

## 登录跳过 token，其他接口鉴权

新建 `App/HttpController/Admin/Profile.php`：

```php
<?php

namespace App\HttpController\Admin;

use EasySwoole\HttpAnnotation\AnnotationController;
use EasySwoole\HttpAnnotation\Attributes\Api;
use EasySwoole\HttpAnnotation\Attributes\ApiGroup;
use EasySwoole\HttpAnnotation\Attributes\Param;
use EasySwoole\HttpAnnotation\Enum\HttpMethod;
use EasySwoole\HttpAnnotation\Enum\ParamFrom;
use EasySwoole\HttpAnnotation\Validator\Required;

#[ApiGroup(groupName: 'Admin.Profile', description: '管理员示例')]
class Profile extends AnnotationController
{
    #[Param(
        name: 'token',
        from: ParamFrom::HEADER,
        validate: [new Required()],
        description: '请求头中的管理员令牌',
        ignoreAction: ['login']
    )]
    protected function onRequest(?string $action, ?array $data = null): ?bool
    {
        if ($action === 'login') {
            return true;
        }

        // 演示用固定值；正式项目应在这里查询或校验实际令牌。
        if (($data['token'] ?? null) !== 'demo-token') {
            $this->writeJson(401, null, 'unauthorized');
            return false;
        }

        return true;
    }

    #[Api(allowMethod: HttpMethod::POST, description: '登录，无需 token')]
    public function login(): void
    {
        $this->writeJson(200, ['token' => 'demo-token']);
    }

    #[Api(allowMethod: HttpMethod::POST, description: '查询管理员资料')]
    public function show(): void
    {
        $this->writeJson(200, ['name' => 'admin']);
    }
}
```

服务 reload 后测试：

```bash
curl -i -X POST 'http://127.0.0.1:9501/admin/profile/login'
curl -i -X POST 'http://127.0.0.1:9501/admin/profile/show' -H 'token: demo-token'
curl -i -X POST 'http://127.0.0.1:9501/admin/profile/show' -H 'token: wrong'
```

`login` 在参数解析时就跳过 `token`，并在 `onRequest()` 中放行。`show` 会先读取请求头 `token`，再将 `['token' => '...']` 传入 `onRequest()`；令牌错误时响应并返回 `false`，Action 不再执行。缺少令牌时 `Required` 会先报参数验证失败，**不会进入 `onRequest()`**；若需统一返回 401，可按[参数验证](/Http/AnnotationController/validation.md)中的 `onException()` 处理。这里的 `token` 仅用于示例，请求头名称和鉴权方案由应用自行决定。

## 定义多个公共参数

重复写 `#[Param]`，通过 `$data` 的键名读取：

```php
#[Param(name: 'token', from: ParamFrom::HEADER, ignoreAction: ['login'])]
#[Param(name: 'tenantId', from: ParamFrom::POST, description: '租户 ID')]
protected function onRequest(?string $action, ?array $data = null): ?bool
{
    $token = $data['token'] ?? null;
    $tenantId = $data['tenantId'] ?? null;
    return true;
}
```

此例只适合有表单字段 `tenantId` 的请求；JSON 请求体应改为 `ParamFrom::JSON` 并在对应 `#[Api]` 上声明 `acceptContentType: ContentType::JSON`。`onRequest` 参数不只用于鉴权，也可承载每个 Action 都要读取的租户 ID、客户端标识等。Action 的 `Api::requestParam` 若声明同名参数，会覆盖公共定义。`ignoreAction` 的值是 Action **方法名**，不是 URL；它只允许写在 `onRequest()` 的 `#[Param]` 中。

注意：当前组件对 GET 的 `#[Api]` 会检查适用的 `onRequest` 公共参数来源。仅声明 `HEADER` 的公共参数不能直接用于这类 GET Action；需让来源包含 `ParamFrom::GET`、由 Action 的同名参数覆盖，或者对该 GET Action 设置 `ignoreAction`。上面的完整鉴权示例因此使用 POST。

## 继承父控制器的公共参数

如果子控制器覆盖了 `onRequest()`，父方法上的 `#[Param]` 不会自动继承；需要在子方法添加 `#[ExtendParam]`。例如先新建 `App/HttpController/Admin/Base.php`：

```php
<?php

namespace App\HttpController\Admin;

use EasySwoole\HttpAnnotation\AnnotationController;
use EasySwoole\HttpAnnotation\Attributes\Param;
use EasySwoole\HttpAnnotation\Enum\ParamFrom;

abstract class Base extends AnnotationController
{
    #[Param(name: 'token', from: ParamFrom::HEADER, description: '管理员令牌')]
    protected function onRequest(?string $action, ?array $data = null): ?bool
    {
        if (($data['token'] ?? null) !== 'demo-token') {
            $this->writeJson(401, null, 'unauthorized');
            return false;
        }
        return true;
    }
}
```

再新建 `App/HttpController/Admin/Report.php`：

```php
<?php

namespace App\HttpController\Admin;

use EasySwoole\HttpAnnotation\Attributes\Api;
use EasySwoole\HttpAnnotation\Attributes\ApiGroup;
use EasySwoole\HttpAnnotation\Attributes\ExtendParam;
use EasySwoole\HttpAnnotation\Attributes\Param;
use EasySwoole\HttpAnnotation\Enum\HttpMethod;
use EasySwoole\HttpAnnotation\Enum\ParamFrom;
use EasySwoole\HttpAnnotation\Enum\ParamType;

#[ApiGroup(groupName: 'Admin.Report', description: '管理员报表')]
class Report extends Base
{
    #[ExtendParam]
    #[Param(name: 'tenantId', from: ParamFrom::POST, type: ParamType::INT, description: '租户 ID')]
    protected function onRequest(?string $action, ?array $data = null): ?bool
    {
        if (parent::onRequest($action, $data) === false) {
            return false;
        }
        // 这里能同时读取继承的 token 和本类的 tenantId。
        $tenantId = $data['tenantId'] ?? null;
        return true;
    }

    #[Api(allowMethod: HttpMethod::POST, description: '查看报表')]
    public function index(): void
    {
        $this->writeJson(200, ['report' => 'ok']);
    }
}
```

测试：

```bash
curl -i -X POST 'http://127.0.0.1:9501/admin/report' \
  -H 'token: demo-token' -F 'tenantId=7'
```

`#[ExtendParam]` 只负责继承**参数定义**；想复用父类鉴权逻辑，仍要显式调用 `parent::onRequest($action, $data)`。不传参数时继承父类全部公共参数；`#[ExtendParam(parentParamsName: ['token'])]` 只继承列出的名称。子类声明同名 `#[Param]` 时以子类定义为准。完整选项见[Attribute 清单与定义参数](/Http/AnnotationController/attributes.md)。
