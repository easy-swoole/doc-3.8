# HTTP 服务常见问题

## 请求连不上或返回 404

先按[安装、启动与访问排错](/QuickStart/problem.md)确认服务正在监听，再核对 URL、路由和控制器。收到 404 表示已取得 HTTP 响应，排查时可先跳过扩展安装和端口监听，直接检查[访问接口返回 404](/QuickStart/problem.md#访问接口返回-404)。

## 改了代码没有生效

根据改动属于 Worker 业务代码还是主进程配置，选择重载或完整重启。参见[修改后没有生效](/QuickStart/problem.md#修改后没有生效)。

## 注解参数校验失败时如何返回错误信息

注解控制器校验失败时会抛出 `ParamValidateFail`，目标 Action 不会执行。在控制器的 `onException()` 中捕获它，通过 `getFailRule()` 和 `getParamName()` 取得失败规则和参数名，生成提示后调用 `writeJson()` 返回客户端。

在应用项目中新建 `App/HttpController/ValidationResult.php`，也可以将下面的异常处理方法放到项目的公共注解控制器基类中，让业务控制器继承它。

```php
<?php

namespace App\HttpController;

use EasySwoole\EasySwoole\Trigger;
use EasySwoole\HttpAnnotation\AnnotationController;
use EasySwoole\HttpAnnotation\Attributes\Api;
use EasySwoole\HttpAnnotation\Attributes\Param;
use EasySwoole\HttpAnnotation\Enum\ParamFrom;
use EasySwoole\HttpAnnotation\Exception\ParamValidateFail;
use EasySwoole\HttpAnnotation\Validator\IsEmail;
use EasySwoole\HttpAnnotation\Validator\Required;

class ValidationResult extends AnnotationController
{
    #[Api(requestParam: [
        new Param(
            name: 'email',
            from: ParamFrom::GET,
            validate: [
                new Required(),
                new IsEmail(errorMsg: 'email 格式不正确'),
            ],
        ),
    ])]
    public function index(string $email): void
    {
        $this->writeJson(200, ['email' => $email]);
    }

    protected function onException(\Throwable $error): void
    {
        if ($error instanceof ParamValidateFail) {
            $message = $error->getFailRule()->errorMsg($error->getParamName());
            $this->writeJson(400, null, 'param validate fail: ' . $message);
            return;
        }

        Trigger::getInstance()->throwable($error);
        $this->writeJson(500, null, 'api error');
    }
}
```

重载 Worker 后，在另一个终端验证：

```bash
php easyswoole.php server reload
curl -i 'http://127.0.0.1:9501/validationResult?email=bad'
```

此请求返回 HTTP 400 和以下 JSON，前端可读取 `msg` 展示给用户：

```json
{"code":400,"result":null,"msg":"param validate fail: email 格式不正确"}
```

换成 `email=a%40example.com` 后返回 HTTP 200，并进入 `index()`。参数校验返回首个失败规则的结果；嵌套校验的参数名可以是 `box_list[1].id` 这样的完整路径。其它异常由示例记录到框架 Trigger，再向客户端返回 HTTP 500 和通用提示。

已有 `onException()` 时，将 `ParamValidateFail` 分支合并到现有方法中。使用自定义语言映射时，可以通过 `$error->getMessage()` 取得校验时已生成的提示，保留该次校验的语言设置。完整规则定义和错误信息配置见[注解参数验证](/Http/AnnotationController/validation.md)和[自定义错误信息](/Http/AnnotationController/validation-rules.md#自定义错误信息)。

## 请求之间串数据

检查是否把用户、请求参数或响应对象存在静态属性或单例中。将这些数据放到方法局部变量、请求对象或协程上下文，并在请求结束时清理上下文。用两个不同身份重复请求，确认响应只包含当前请求的数据。参见[会话与状态](/Http/State/index.md)和[IOC 与上下文](/Component/ioc-context.md)。

## 经过代理后 IP 或 HTTPS 判断不正确

先分别请求后端和代理入口，确认代理有没有传递协议和客户端地址。按[反向代理部署](/Http/Advanced/proxy.md)检查转发配置，再按[URI 与客户端信息](/Http/Request/uri-client.md)核对应用对代理头的读取和信任范围。

## 上传触发 413、超时或文件为空

用同一个文件分别请求后端和代理入口，定位在哪一层失败。逐层检查代理请求体限制、Swoole 大小限制和应用上传校验，修改后用同一文件重试。参见[大文件上传](/Http/File/large-upload.md)和[文件校验与保存](/Http/File/validate-save.md)。

## 版本与 GitHub

- [`easyswoole/easyswoole` 3.8.2 · GitHub](https://github.com/easy-swoole/easyswoole/tree/3.8.2)
- [`easyswoole/http` 3.2.1 · GitHub](https://github.com/easy-swoole/http/tree/3.2.1)

- [HTTP-Annotation 参数校验异常（4.2.4）](https://github.com/easy-swoole/http-annotation/blob/4.2.4/src/Exception/ParamValidateFail.php)
- [HTTP-Annotation 校验与错误生成（4.2.4）](https://github.com/easy-swoole/http-annotation/blob/4.2.4/src/Utility.php)
