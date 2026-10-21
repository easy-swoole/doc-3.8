# 嵌套与多级验证

普通 `Param` 校验一个顶层字段；当 JSON 请求中还有对象、列表或更深层对象时，可以递归组合两个验证器：

| 验证器 | 作用 | 适合的数据 |
| --- | --- | --- |
| `ObjectShape(params: [...])` | 定义对象内部的字段及各字段规则 | `{"name":"张三"}` |
| `Each(validate: [...])` | 对列表中每个元素执行相同规则 | `[{"id":1},{"id":2}]` |

例如包裹列表中的每个包裹都有一个危险品详情对象，结构是 `box_list[] → dangerous_detail → id`。在 `Param` 的 `validate` 中写 `Each → ObjectShape → ObjectShape`，即可逐层验证，失败时拿到 `box_list[1].dangerous_detail.id` 这样的完整字段路径。

## 完整 Example：校验运单请求

在应用项目根目录新建 `App/HttpController/ShippingValidation.php`：

```php
<?php

namespace App\HttpController;

use EasySwoole\HttpAnnotation\AnnotationController;
use EasySwoole\HttpAnnotation\Attributes\Api;
use EasySwoole\HttpAnnotation\Attributes\ApiGroup;
use EasySwoole\HttpAnnotation\Attributes\Param;
use EasySwoole\HttpAnnotation\Bean\Example\Array2Json;
use EasySwoole\HttpAnnotation\Enum\ContentType;
use EasySwoole\HttpAnnotation\Enum\HttpMethod;
use EasySwoole\HttpAnnotation\Enum\ParamFrom;
use EasySwoole\HttpAnnotation\Enum\ParamType;
use EasySwoole\HttpAnnotation\Exception\ParamValidateFail;
use EasySwoole\HttpAnnotation\Validator\Each;
use EasySwoole\HttpAnnotation\Validator\Integer;
use EasySwoole\HttpAnnotation\Validator\Min;
use EasySwoole\HttpAnnotation\Validator\NotEmpty;
use EasySwoole\HttpAnnotation\Validator\ObjectShape;
use EasySwoole\HttpAnnotation\Validator\Optional;
use EasySwoole\HttpAnnotation\Validator\Required;

#[ApiGroup(groupName: 'ShippingValidation', description: '运单请求验证示例')]
class ShippingValidation extends AnnotationController
{
    #[Api(
        allowMethod: HttpMethod::POST,
        acceptContentType: ContentType::JSON,
        description: '验证包裹列表与发件人信息，不创建真实运单',
        requestParam: [
            new Param(
                name: 'box_list',
                from: ParamFrom::JSON,
                type: null,
                description: '至少一个包裹',
                validate: [
                    new Required(),
                    new NotEmpty(),
                    new Each(validate: [
                        new ObjectShape(params: [
                            new Param(
                                name: 'box_code',
                                description: '包裹编号',
                                validate: [new Required(), new NotEmpty()]
                            ),
                            new Param(
                                name: 'quantity',
                                type: ParamType::INT,
                                description: '包裹内物品数量',
                                validate: [new Required(), new Integer(), new Min(1)]
                            ),
                            new Param(
                                name: 'dangerous_detail',
                                type: null,
                                description: '可选的危险品详情',
                                validate: [
                                    new Optional(),
                                    new ObjectShape(params: [
                                        new Param(
                                            name: 'id',
                                            description: '危险品标识',
                                            validate: [new Required(), new NotEmpty()]
                                        ),
                                        new Param(
                                            name: 'packing_instructions',
                                            description: '包装说明编号',
                                            validate: [new Required(), new NotEmpty()]
                                        ),
                                    ]),
                                ],
                                ignorePassArgWhenNotSet: true
                            ),
                        ]),
                    ]),
                ]
            ),
            new Param(
                name: 'shipper_address',
                from: ParamFrom::JSON,
                type: null,
                description: '发件人地址',
                validate: [
                    new Required(),
                    new NotEmpty(),
                    new ObjectShape(params: [
                        new Param('name', description: '发件人姓名', validate: [new Required(), new NotEmpty()]),
                        new Param('city', description: '发件城市', validate: [new Required(), new NotEmpty()]),
                    ]),
                ]
            ),
        ],
        requestExamples: [
            new Array2Json([
                'box_list' => [
                    [
                        'box_code' => 'BOX-001',
                        'quantity' => 2,
                        'dangerous_detail' => [
                            'id' => 'UN3480',
                            'packing_instructions' => '965',
                        ],
                    ],
                    ['box_code' => 'BOX-002', 'quantity' => 1],
                ],
                'shipper_address' => ['name' => '张三', 'city' => '厦门'],
            ]),
        ],
        responseExamples: [
            new Array2Json([
                'code' => 200,
                'result' => [
                    'box_list' => [
                        ['box_code' => 'BOX-001', 'quantity' => 2, 'dangerous_detail' => [
                            'id' => 'UN3480', 'packing_instructions' => '965',
                        ]],
                        ['box_code' => 'BOX-002', 'quantity' => 1],
                    ],
                    'shipper_address' => ['name' => '张三', 'city' => '厦门'],
                ],
                'msg' => '校验通过',
            ]),
        ]
    )]
    public function create(array $params): void
    {
        // $params 中已包含逐级验证及类型转换后的值。
        $this->writeJson(200, $params, '校验通过');
    }

    protected function onException(\Throwable $throwable): void
    {
        if ($throwable instanceof ParamValidateFail) {
            $this->writeJson(422, null, $throwable->getMessage());
            return;
        }

        parent::onException($throwable);
    }
}
```

这里只定义两个顶层参数。Action 使用单个 `array $params` 形参接收它们；内部的 `box_code`、`quantity`、`dangerous_detail` 等字段不会成为 Action 的独立形参。`requestExamples` 和 `responseExamples` 是接口文档中的完整 JSON 示例，不能代替验证规则。

在已有的 `App/HttpController/Router.php` 的 `initialize()` 方法中增加路由，保留原有路由及 `setPathInfoMode()` 设置：

```php
$routeCollector->post('/shipping-validation', '/ShippingValidation/create');
```

服务已启动时执行 `php easyswoole.php server reload`，然后发送与 `requestExamples` 对应的请求：

```bash
curl -i -X POST 'http://127.0.0.1:9501/shipping-validation' \
  -H 'Content-Type: application/json' \
  -d '{"box_list":[{"box_code":"BOX-001","quantity":2,"dangerous_detail":{"id":"UN3480","packing_instructions":"965"}},{"box_code":"BOX-002","quantity":1}],"shipper_address":{"name":"张三","city":"厦门"}}'
```

成功时 `result` 中保留两个包裹以及发件人信息，第二个包裹没有传 `dangerous_detail`，因此结果中也没有这个键。`quantity` 进入 Action 时是整数。

把第二个包裹的 `quantity` 改为 `0`，可验证错误路径：

```bash
curl -i -X POST 'http://127.0.0.1:9501/shipping-validation' \
  -H 'Content-Type: application/json' \
  -d '{"box_list":[{"box_code":"BOX-001","quantity":2},{"box_code":"BOX-002","quantity":0}],"shipper_address":{"name":"张三","city":"厦门"}}'
```

此时 Action 不会执行，`onException()` 返回 422；错误信息中包含 `box_list[1].quantity`。如果第二个包裹传入 `"dangerous_detail":{"id":""}`，错误路径会是 `box_list[1].dangerous_detail.id`。`ParamValidateFail::getParamName()` 也返回相同的完整路径，方便前端定位字段。

## `ObjectShape` 与 `Each` 的组合规则

- 对象使用 `new ObjectShape(params: [new Param(...), ...])`；列表使用 `new Each(validate: [规则...])`。二者可以继续递归组合，例如列表中的对象、对象中的列表，或者二维列表。**同一个 `Param` 上**不能同时放 `ObjectShape` 与 `Each`。
- 容器参数必须保留 JSON 对象或数组，通常写 `type: null`；否则默认的字符串转换会破坏结构。`Each` 只接受索引从 0 开始、没有断号的 PHP 列表，`ObjectShape` 接受关联数组。
- 子字段的 `from` 不再从 HTTP 请求单独取值，实际来源是父对象；文档中会继承根参数的来源。子字段不能设置 `ignoreAction`。
- 子字段遵循普通 `Param` 的类型、默认值、必填和可选规则。缺失的字段默认回填声明的 `value`（通常为 `null`）；设 `ignorePassArgWhenNotSet: true` 则在未传入时省略。未知字段会原样保留，不会自动过滤。
- 同一个对象的所有兄弟字段会先解析、再校验，所以 `RequiredIf`、`EqualWithColumn` 等跨字段规则能引用**当前对象内**的兄弟字段；它们不会向上查找顶层或外层对象。单纯的 `Each` 列表元素也没有对象兄弟字段上下文。
- JSON 解码后，空对象 `{}` 和空列表 `[]` 都是 PHP 的 `[]`，因此空结构无法严格区分。需要至少一个元素或字段时，配合 `NotEmpty`。嵌套最多 32 层，超出会抛出定义异常 `Annotation`。

例如在每个包裹对象内，`insured` 为 `true` 时才要求 `declared_value`：

```php
use EasySwoole\HttpAnnotation\Validator\RequiredIf;

// 以下两个 Param 放在同一个 ObjectShape(params: [...]) 中。
new Param('insured', type: ParamType::BOOLEAN, value: false),
new Param(
    'declared_value',
    type: null,
    validate: [new RequiredIf('insured', true, true)],
    ignorePassArgWhenNotSet: true
),
```

`RequiredIf` 的第三个参数开启严格比较；这里比较的是同一个包裹内已经转换为布尔值的 `insured`。是否允许负数、金额格式和货币精度是额外规则或业务逻辑，不由 `RequiredIf` 自动保证。

## 文档如何展示多级字段

生成接口文档时，参数表会把上面的结构展开为 `box_list`、`box_list[]`、`box_list[].quantity`、`box_list[].dangerous_detail.id` 等路径，并列出字段说明、类型和来源。`Array2Json` 展示完整请求或响应示例；“立即尝试”时仍需提交完整 JSON 请求体，不是分别填写每个嵌套子字段。生成方法见[生成接口文档](/Http/AnnotationController/document.md)。

下一章：[响应参数与示例](/Http/AnnotationController/response-params.md)。

## 源码依据

- [HTTP Annotation 4.2.2：嵌套请求参数](https://github.com/easy-swoole/http-annotation/blob/4.2.2/README.md#嵌套请求参数)
- [Shipping Example](https://github.com/easy-swoole/http-annotation/blob/4.2.2/tests/ControllerExample/Api/Shipping.php)
- [ObjectShape](https://github.com/easy-swoole/http-annotation/blob/4.2.2/src/Validator/ObjectShape.php)
- [Each](https://github.com/easy-swoole/http-annotation/blob/4.2.2/src/Validator/Each.php)
