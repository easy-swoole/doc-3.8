# 注解参数验证

参数的 `validate` 接受规则对象数组。组件先从声明来源取值、按 `type` 转换，再执行规则；验证失败时不会调用目标 Action。本章用一个完整控制器演示必填、最小值和邮箱格式。

## 定义接口和规则

在应用项目根目录新建 `App/HttpController/Member.php`：

```php
<?php

namespace App\HttpController;

use EasySwoole\HttpAnnotation\AnnotationController;
use EasySwoole\HttpAnnotation\Attributes\Api;
use EasySwoole\HttpAnnotation\Attributes\ApiGroup;
use EasySwoole\HttpAnnotation\Attributes\Param;
use EasySwoole\HttpAnnotation\Enum\ContentType;
use EasySwoole\HttpAnnotation\Enum\HttpMethod;
use EasySwoole\HttpAnnotation\Enum\ParamFrom;
use EasySwoole\HttpAnnotation\Enum\ParamType;
use EasySwoole\HttpAnnotation\Exception\ParamValidateFail;
use EasySwoole\HttpAnnotation\Validator\IsEmail;
use EasySwoole\HttpAnnotation\Validator\Min;
use EasySwoole\HttpAnnotation\Validator\Required;

#[ApiGroup(groupName: 'Member', description: '会员接口')]
class Member extends AnnotationController
{
    #[Api(
        allowMethod: HttpMethod::POST,
        acceptContentType: ContentType::JSON,
        requestParam: [
            new Param(
                name: 'age',
                from: ParamFrom::JSON,
                type: ParamType::INT,
                validate: [new Required(), new Min(18)]
            ),
            new Param(
                name: 'email',
                from: ParamFrom::JSON,
                validate: [new Required(), new IsEmail()]
            ),
        ],
        description: '创建会员'
    )]
    public function create(int $age, string $email): void
    {
        $this->writeJson(201, compact('age', 'email'));
    }

    protected function onException(\Throwable $error): void
    {
        if ($error instanceof ParamValidateFail) {
            $message = $error->getFailRule()->errorMsg($error->getParamName());
            $this->writeJson(422, null, $message);
            return;
        }

        parent::onException($error);
    }
}
```

请求体中 `age` 为数字字符串或数字时会转换为整数；`create()` 的形参名必须与 `Param(name: ...)` 对应。`Required` 检查缺失，`Min(18)` 检查最小值，`IsEmail` 检查邮箱格式。JSON 来源必须配合 `ContentType::JSON`，否则注解定义会在解析时抛错。

## 实际请求

启动或 reload 服务后运行：

```bash
curl -i -X POST http://127.0.0.1:9501/member/create \
  -H 'Content-Type: application/json' \
  -d '{"age":20,"email":"a@example.com"}'

curl -i -X POST http://127.0.0.1:9501/member/create \
  -H 'Content-Type: application/json' \
  -d '{"age":15,"email":"bad"}'
```

第一条请求进入 `create()` 并返回 201；第二条至少有一条规则不通过，进入 `onException()` 返回 422。示例只处理参数验证异常；真实项目还应按[异常处理](/Http/Controller/exception.md)处理其他业务异常并记录服务端错误。

可选参数可以使用 `Optional` 与默认值，但不能把可选规则与 `Required`、`NotEmpty` 等必填规则混在同一个 `Param` 中。完整规则及用法见[Attribute 验证规则](/Http/AnnotationController/validation-rules.md)；对象和列表的递归校验见[嵌套与多级验证](/Http/AnnotationController/nested-validation.md)；在 `onRequest()` 中声明公共参数的做法见[onRequest 公共参数与继承](/Http/AnnotationController/common-params.md)。

下一章：[生成接口文档](/Http/AnnotationController/document.md)。

## 源码依据

- [4.x README：参数验证](https://github.com/easy-swoole/http-annotation/blob/4.x/README.md)
- [Param.php](https://github.com/easy-swoole/http-annotation/blob/4.x/src/Attributes/Param.php)
