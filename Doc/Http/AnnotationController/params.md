# 接口参数与传参

接口自己的参数写在 Action 的 `#[Api(requestParam: [...])]` 中，每一项是一个 `new Param(...)`。组件按 `from` 读取请求、按 `type` 转换、执行 `validate`，最后按参数名传给 Action。先看 [Attribute 清单与定义参数](/Http/AnnotationController/attributes.md)了解全部构造参数；本页专注实际调用。

## 一个可运行的例子

在应用项目根目录新建 `App/HttpController/OrderParams.php`：

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
use EasySwoole\HttpAnnotation\Validator\Min;
use EasySwoole\HttpAnnotation\Validator\Required;

#[ApiGroup(groupName: 'OrderParams', description: '订单参数示例')]
class OrderParams extends AnnotationController
{
    #[Api(
        allowMethod: HttpMethod::GET,
        description: '按 ID 查询订单',
        requestParam: [
            new Param(
                name: 'id',
                from: ParamFrom::GET,
                type: ParamType::INT,
                validate: [new Required(), new Min(1)],
                description: '订单 ID，必须大于 0'
            ),
        ]
    )]
    public function detail(int $id): void
    {
        $this->writeJson(200, ['id' => $id, 'name' => '示例订单']);
    }

    #[Api(
        allowMethod: HttpMethod::POST,
        acceptContentType: ContentType::JSON,
        description: '创建订单',
        requestParam: [
            new Param(name: 'name', from: ParamFrom::JSON, validate: [new Required()], description: '订单名称'),
            new Param(name: 'quantity', from: ParamFrom::JSON, type: ParamType::INT, value: 1, description: '数量，默认 1'),
        ]
    )]
    public function create(string $name, int $quantity): void
    {
        $this->writeJson(201, compact('name', 'quantity'));
    }
}
```

已启动服务时先运行 `php easyswoole.php server reload`，然后请求：

```bash
curl -i 'http://127.0.0.1:9501/orderParams/detail?id=12'
curl -i -X POST 'http://127.0.0.1:9501/orderParams/create' \
  -H 'Content-Type: application/json' \
  -d '{"name":"书籍","quantity":2}'
```

第一条将 `id` 以整数 `12` 传入 `detail()`；第二条从 JSON 请求体提取 `name`、`quantity`。省略 `quantity` 时使用默认值 `1`。`Param(name: ...)` 与 Action 形参名必须一致；缺少必需形参对应的注解会产生参数错误。`description` 会进入接口文档，不影响请求值。

## 来源、请求体与方法的对应关系

| `from` | 在哪里传 | 相关声明 |
| --- | --- | --- |
| `ParamFrom::GET` | URL 查询串 `?id=12` | 可用于 GET，也可用于其他方法 |
| `ParamFrom::POST` | 表单字段 | POST 等方法配 `ContentType::FORM_DATA` 或 `FORM_URLENCODED` |
| `ParamFrom::JSON` | JSON 请求体 | 配 `acceptContentType: ContentType::JSON` |
| `ParamFrom::HEADER`、`COOKIE` | 请求头、Cookie | 不属于请求体 |
| `ParamFrom::FILE` | 上传文件 | 配 `ContentType::FORM_DATA` 和 `ParamType::FILE` |
| `ParamFrom::XML`、`RAW_POST` | XML、原始请求体 | 分别配 `ContentType::XML`、`RAW` |

`GET`/`HEAD` 不能定义 `acceptContentType`。非 GET/HEAD 方法若省略该项，默认按 `FORM_DATA` 处理。`from` 也可传数组（如 `[ParamFrom::HEADER, ParamFrom::COOKIE]`），按顺序读取第一个命中的来源；`FILE` 只能单独使用。`DI`、`CONTEXT` 等来源及全部参数选项见[Attribute 清单](/Http/AnnotationController/attributes.md)。

## 用一个数组形参接收

如果 Action 只有一个 `array` 形参，声明的接口参数会合并为该数组：

```php
#[Api(requestParam: [
    new Param(name: 'page', from: ParamFrom::GET, type: ParamType::INT, value: 1, description: '页码'),
])]
public function index(array $data): void
{
    $this->writeJson(200, ['page' => $data['page']]);
}
```

若希望某个未传入的可选字段完全不进入 `$data`，可在该 `Param` 上设置 `ignorePassArgWhenNotSet: true`。普通形参模式则按名称注入；不能混用一个数组形参与其他形参。

控制器间共用的参数（例如 token）应写在 [`onRequest()` 公共参数](/Http/AnnotationController/common-params.md)，不是复制到每个 `Api::requestParam`。校验规则和失败处理见[参数验证](/Http/AnnotationController/validation.md)。
