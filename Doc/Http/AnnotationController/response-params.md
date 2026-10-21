# 响应参数与示例

请求参数说明“客户端要传什么”；响应参数说明“接口会返回什么”。当前 `easyswoole/http-annotation` 4.x 在 `#[Api]` 中通过 `responseParam` 定义响应字段，并在生成的 HTML 中显示响应参数表。完整 JSON 可另用 `responseExamples` 展示；两者是独立配置。

## 从实际响应开始定义

假设查询商品成功时，控制器响应为：

```json
{
  "code": 200,
  "result": {"id": 19, "name": "示例商品"},
  "msg": "ok"
}
```

在应用项目根目录新建 `App/HttpController/Catalog/ProductResponse.php`。这段代码可直接放入已有 EasySwoole 项目，不需要另建注解配置文件：

```php
<?php

namespace App\HttpController\Catalog;

use EasySwoole\HttpAnnotation\AnnotationController;
use EasySwoole\HttpAnnotation\Attributes\Api;
use EasySwoole\HttpAnnotation\Attributes\ApiGroup;
use EasySwoole\HttpAnnotation\Attributes\Param;
use EasySwoole\HttpAnnotation\Bean\Example\Array2Json;
use EasySwoole\HttpAnnotation\Bean\Example\ResParam;
use EasySwoole\HttpAnnotation\Bean\Example\ResParamType;
use EasySwoole\HttpAnnotation\Enum\HttpMethod;
use EasySwoole\HttpAnnotation\Enum\ParamFrom;
use EasySwoole\HttpAnnotation\Enum\ParamType;
use EasySwoole\HttpAnnotation\Validator\Required;

#[ApiGroup(groupName: 'Catalog.ProductResponse', description: '商品响应文档示例')]
class ProductResponse extends AnnotationController
{
    #[Api(
        allowMethod: HttpMethod::GET,
        description: '按 ID 获取商品',
        requestParam: [
            new Param(name: 'id', from: ParamFrom::GET, type: ParamType::INT, validate: [new Required()], description: '商品 ID'),
        ],
        responseParam: [
            new ResParam('code', 200, ResParamType::int, '业务响应码'),
            new ResParam('result', ['id' => 19, 'name' => '示例商品'], ResParamType::object, '商品数据'),
            new ResParam('result.id', 19, ResParamType::int, '商品 ID'),
            new ResParam('result.name', '示例商品', ResParamType::string, '商品名称'),
            new ResParam('msg', 'ok', ResParamType::string, '响应说明'),
        ],
        responseExamples: [
            new Array2Json([
                'code' => 200,
                'result' => ['id' => 19, 'name' => '示例商品'],
                'msg' => 'ok',
            ]),
            new Array2Json([
                'code' => 404,
                'result' => null,
                'msg' => '商品不存在',
            ], isSuccessResponse: false),
        ]
    )]
    public function detail(int $id): void
    {
        if ($id !== 19) {
            $this->writeJson(404, null, '商品不存在');
            return;
        }

        $this->writeJson(200, ['id' => $id, 'name' => '示例商品'], 'ok');
    }
}
```

示例里的商品和 ID 是演示数据，实际项目应改为查询数据库。`#[Api]` 不自动注册路由；若希望通过固定地址访问，在现有 `App/HttpController/Router.php` 的 `initialize()` 中**增加**这一行，保留原有路由：

```php
$routeCollector->get('/products/detail', '/Catalog/ProductResponse/detail');
```

重载服务后测试 `curl -i 'http://127.0.0.1:9501/products/detail?id=19'`；改成其他 ID 会得到失败响应。路由参数的传递规则见[路由基础](/Http/Routing/index.md)。接口可否访问与文档能否展示是两件事。

## `ResParam` 的四个参数

```php
new ResParam(
    name: 'result.id',
    exampleValue: 19,
    paramType: ResParamType::int,
    description: '商品 ID'
);
```

| 参数 | 类型 / 默认值 | 作用 |
| --- | --- | --- |
| `name` | `string`，必填 | 字段名。嵌套字段使用点分写法，如 `result.id` |
| `exampleValue` | `mixed`，必填 | 表格“参数值”列中的示例值；`null` 会显示为 `-` |
| `paramType` | `ResParamType`，默认 `string` | `object`、`string`、`int`、`bool`、`float`，枚举名称为小写 |
| `description` | `string\|Text\|null`，默认 `null` | 表格“描述说明”列；`Text` 位于 `Bean\Description` 命名空间 |

这些定义会按数组顺序逐行显示。`result.id` 只是表格中的字段路径，不会自动构造嵌套 JSON；真实响应仍由 Action 自己写出。`responseParam` 只做文档展示，不负责校验响应、转换数据类型或设置 HTTP 状态。想说明数组字段时，可用 `ResParamType::object` 描述容器，并在 `description` 中写清“商品列表”等含义；当前枚举没有独立的 `array` 类型。

## 生成后会看到什么

运行[生成接口文档](/Http/AnnotationController/document.md)中的 `build-api-doc.php` 或访问项目配置的 `/doc`。打开 `Catalog.ProductResponse → detail`，在“请求参数”之后可看到“响应参数”表，大致如下：

| 参数名 | 参数值 | 参数类型 | 描述说明 |
| --- | --- | --- | --- |
| `code` | `200` | `int` | 业务响应码 |
| `result` | `{"id":19,"name":"示例商品"}` | `object` | 商品数据 |
| `result.id` | `19` | `int` | 商品 ID |
| `result.name` | `示例商品` | `string` | 商品名称 |
| `msg` | `ok` | `string` | 响应说明 |

之后会分别显示成功、失败响应示例。`Array2Json(..., isSuccessResponse: false)` 放在失败示例区域；默认 `true` 放在成功区域。`responseParam` 空数组时该区域显示“暂无示例”。**不要把 `code` 与 HTTP 状态码混为一谈**：本例使用 `writeJson(200, ...)` 时两者恰好相同，但 `ResParam('code', ...)` 只描述响应体字段。

下一章：[生成接口文档](/Http/AnnotationController/document.md)。

## 源码依据

- [4.x README：响应参数与完整响应示例](https://github.com/easy-swoole/http-annotation/blob/4.x/README.md)
- [ResParam.php](https://github.com/easy-swoole/http-annotation/blob/4.x/src/Bean/Example/ResParam.php)
- [ResParamType.php](https://github.com/easy-swoole/http-annotation/blob/4.x/src/Bean/Example/ResParamType.php)
- [Document.php](https://github.com/easy-swoole/http-annotation/blob/4.x/src/Document/Document.php)
