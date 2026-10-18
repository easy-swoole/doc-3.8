# Attribute 验证规则

EasySwoole HTTP Annotation 4.x 当前提供 61 个内置 Validator。它们都放在：

```php
EasySwoole\HttpAnnotation\Validator
```

验证规则写在 `Param` 的 `validate` 数组中。一个参数可以组合多条规则，框架按顺序执行，遇到第一条失败规则时抛出 `ParamValidateFail`。

## 从一个完整例子开始

新建 `App/HttpController/ValidationDemo.php`，避免覆盖其他章节的控制器：

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
use EasySwoole\HttpAnnotation\Validator\BetweenMbLen;
use EasySwoole\HttpAnnotation\Validator\IsEmail;
use EasySwoole\HttpAnnotation\Validator\Min;
use EasySwoole\HttpAnnotation\Validator\NotEmpty;
use EasySwoole\HttpAnnotation\Validator\Required;

#[ApiGroup(groupName: 'ValidationDemo')]
class ValidationDemo extends AnnotationController
{
    #[Api(
        allowMethod: HttpMethod::POST,
        acceptContentType: ContentType::JSON,
        requestParam: [
            new Param(
                name: 'name',
                from: ParamFrom::JSON,
                validate: [
                    new Required(),
                    new NotEmpty(),
                    new BetweenMbLen(2, 20),
                ]
            ),
            new Param(
                name: 'email',
                from: ParamFrom::JSON,
                validate: [new Required(), new IsEmail()]
            ),
            new Param(
                name: 'age',
                from: ParamFrom::JSON,
                type: ParamType::INT,
                validate: [new Required(), new Min(18)]
            ),
        ]
    )]
    public function create(string $name, string $email, int $age): void
    {
        $this->writeJson(201, compact('name', 'email', 'age'));
    }

    protected function onException(\Throwable $throwable): void
    {
        if ($throwable instanceof ParamValidateFail) {
            $this->writeJson(422, null, $throwable->getMessage());
            return;
        }

        throw $throwable;
    }
}
```

在 `App/HttpController/Router.php` 中注册：

```php
$routeCollector->post('/validation-demo', '/ValidationDemo/create');
```

验证成功：

```bash
curl -i -X POST http://127.0.0.1:9501/validation-demo \
  -H 'Content-Type: application/json' \
  -d '{"name":"张三","email":"zhangsan@example.com","age":20}'
```

验证失败：

```bash
curl -i -X POST http://127.0.0.1:9501/validation-demo \
  -H 'Content-Type: application/json' \
  -d '{"name":"张","email":"wrong","age":16}'
```

由于规则按声明顺序执行，第二次请求首先报告 `name` 长度错误；修正后才会继续遇到邮箱或年龄错误。

## 必填与可选规则

| 规则 | 用法 | 说明 |
| --- | --- | --- |
| `Required` | `new Required()` | 参数必须实际传入，但不检查内容是否为空 |
| `NotEmpty` | `new NotEmpty()` | 值不能为空；整数 `0` 和字符串 `'0'`允许 |
| `RequiredIf` | `new RequiredIf('type', 'company')` | 关联字段等于指定值时必填 |
| `RequiredWith` | `new RequiredWith(['password'])` | 列表中任一字段已传且非空时必填 |
| `RequiredWithout` | `new RequiredWithout(['email'])` | 列表中任一字段未传或为空时必填 |
| `Optional` | `new Optional()` | 未传且值严格为 `null` 时跳过该参数的全部规则 |
| `IgnoreValidatorWhenEmpty` | `new IgnoreValidatorWhenEmpty()` | 未传或 PHP `empty()` 时跳过规则，包括 `0`、`false` |
| `OptionalIfParamMiss` | `new OptionalIfParamMiss('account')` | 当前字段与目标字段都未传时跳过 |
| `OptionalIfParamSet` | `new OptionalIfParamSet('account')` | 当前字段未传、目标字段已传时跳过 |
| `OptionalIfParamValInArray` | `new OptionalIfParamValInArray('mode', ['guest'])` | 目标值在列表中时，允许当前字段不传 |
| `OptionalIfParamValNoInArray` | `new OptionalIfParamValNoInArray('mode', ['member'])` | 目标值不在列表中时，允许当前字段不传 |

### `Required` 和 `NotEmpty` 的区别

```php
new Param('nickname', validate: [new Required()]);
```

客户端传入 `nickname=` 时，参数存在，所以 `Required` 可以通过。如果字段还不能是空字符串，需要组合：

```php
new Param('nickname', validate: [
    new Required(),
    new NotEmpty(),
]);
```

### 可选字段的正确写法

```php
new Param(
    name: 'age',
    from: ParamFrom::JSON,
    type: null,
    validate: [
        new Optional(),
        new Integer(),
        new Min(18),
    ]
)
```

`type: null` 保留未传入时的 `null`，使 `Optional` 可以准确跳过后续规则。`Optional*`、`IgnoreValidatorWhenEmpty` 不能与 `Required*`、`NotEmpty` 用在同一个 Param 中；当前版本会把这种配置直接判为冲突。

### 条件必填示例

```php
new Param(name: 'type', from: ParamFrom::JSON),
new Param(
    name: 'companyName',
    from: ParamFrom::JSON,
    validate: [
        new RequiredIf('type', 'company'),
        new MaxMbLength(100),
    ]
)
```

当 `type=company` 时必须传 `companyName`。

## 数字与金额规则

| 规则 | 用法 | 说明 |
| --- | --- | --- |
| `Integer` | `new Integer()` | 整数或合法整数字符串 |
| `IsFloat` | `new IsFloat()` | 合法浮点表示，整数也可能通过 |
| `IsNumeric` | `new IsNumeric()` | 使用 `is_numeric()` 判断 |
| `IsBool` | `new IsBool()` | 允许 `true`、`false`、`1`、`0`、`'1'`、`'0'` |
| `AllDigital` | `new AllDigital()` | 全部是数字字符，允许前导零 |
| `Min` | `new Min(1)` | 数值大于或等于下限 |
| `Max` | `new Max(100)` | 数值小于或等于上限 |
| `Between` | `new Between(1, 100)` | 数值位于闭区间，建议配合 `IsNumeric` |
| `MultipleOf` | `new MultipleOf(0.25)` | 必须是给定数值的整数倍 |
| `Decimal` | `new Decimal(2)` | 小数精度最多为 2 位 |
| `Money` | `new Money(2)` | 金额文本，小数最多为 2 位 |

不要只依赖 `ParamType::INT` 判断输入是否合法，因为类型转换发生在验证之前，字符串 `abc` 转成整数后会变成 `0`。需要验证原始格式时使用 `type: null`：

```php
new Param(
    name: 'quantity',
    from: ParamFrom::JSON,
    type: null,
    validate: [new Required(), new Integer(), new Min(1)]
)
```

金额建议作为字符串验证，进入金额计算时再转换成最小货币单位，避免浮点误差：

```php
new Param('amount', from: ParamFrom::JSON, type: null, validate: [
    new Required(),
    new Money(2),
]);
```

## 字符串与格式规则

| 规则 | 用法 | 说明 |
| --- | --- | --- |
| `Alpha` | `new Alpha()` | 仅英文字母 |
| `AlphaNum` | `new AlphaNum()` | 仅英文字母和数字 |
| `AlphaDash` | `new AlphaDash()` | 英文字母、连字符、下划线；当前实现不允许数字 |
| `Regex` | `new Regex('/^[A-Z]{2}[0-9]{4}$/')` | 使用自定义正则，必须包含分隔符 |
| `IsEmail` | `new IsEmail()` | 邮箱格式 |
| `IsUrl` | `new IsUrl(['https'])` | URL 格式，并可限制协议 |
| `IsIp` | `new IsIp('IPV4')` | IP；模式为 `ANY`、`IPV4` 或 `IPV6` |
| `IsDomain` | `new IsDomain()` | 域名格式，不接收完整 URL，不查询 DNS |
| `IsPhoneNumber` | `new IsPhoneNumber()` | 中国大陆 11 位手机号 |

URL 示例：

```php
new Param('callbackUrl', from: ParamFrom::JSON, validate: [
    new Required(),
    new IsUrl(['https'], '回调地址必须使用 HTTPS'),
]);
```

格式验证只说明字符串长得像合法 URL。若服务器随后访问这个地址，还必须增加域名/IP 允许列表以防 SSRF。

## 长度规则

| 规则 | 用法 | 说明 |
| --- | --- | --- |
| `Length` | `new Length(10)` | 字节长度等于 10；数组则比较元素数 |
| `MinLength` | `new MinLength(2)` | 最小字节长度；数组则比较元素数 |
| `MaxLength` | `new MaxLength(20)` | 最大字节长度；数组则比较元素数 |
| `BetweenLen` | `new BetweenLen(2, 20)` | 字节长度区间，不接受数组 |
| `MbLength` | `new MbLength(10)` | 多字节字符数等于 10 |
| `MinMbLength` | `new MinMbLength(2)` | 最小多字节字符数 |
| `MaxMbLength` | `new MaxMbLength(20)` | 最大多字节字符数 |
| `BetweenMbLen` | `new BetweenMbLen(2, 20)` | 多字节字符数区间，不接受数组 |

中文名称应使用 `Mb` 系列：

```php
new Param('name', from: ParamFrom::JSON, validate: [
    new Required(),
    new BetweenMbLen(2, 20),
]);
```

`Length` 使用字节数，一个 UTF-8 中文通常占多个字节；`MbLength` 才更接近用户理解的字符数量。

## 固定值、枚举与去重规则

| 规则 | 用法 | 说明 |
| --- | --- | --- |
| `Equal` | `new Equal('active', true)` | 与固定值相等，第二个参数控制严格比较 |
| `Different` | `new Different('blocked', true)` | 与固定值不同 |
| `InArray` | `new InArray(['draft', 'published'], true)` | 值在允许列表中 |
| `NotInArray` | `new NotInArray(['admin'], true)` | 值不在禁止列表中 |
| `Enum` | `new Enum(Status::class, true)` | 验证 PHP 原生枚举名称或 BackedEnum 值 |
| `DistinctInString` | `new DistinctInString(',')` | 分隔字符串内不能出现重复值 |
| `DistinctInArray` | `new DistinctInArray(true)` | 数组元素不能重复 |

原生枚举示例：

```php
enum Status: string
{
    case Draft = 'draft';
    case Published = 'published';
}

new Param(
    name: 'status',
    from: ParamFrom::JSON,
    type: null,
    validate: [new Enum(Status::class, strict: true)]
)
```

JSON 数组去重时必须使用 `type: null`，否则默认字符串转换会破坏数组：

```php
new Param('ids', from: ParamFrom::JSON, type: null, validate: [
    new Required(),
    new DistinctInArray(strict: true),
]);
```

## 字段比较规则

| 规则 | 用法 | 说明 |
| --- | --- | --- |
| `EqualWithColumn` | `new EqualWithColumn('password', true)` | 当前值等于另一个参数 |
| `DifferentWithColumn` | `new DifferentWithColumn('oldPassword', true)` | 当前值不同于另一个参数 |
| `BigThanColumn` | `new BigThanColumn('min')` | 当前值严格大于另一个参数 |
| `SmallThanColumn` | `new SmallThanColumn('max')` | 当前值严格小于另一个参数 |

确认密码示例：

```php
new Param('password', from: ParamFrom::JSON, type: null, validate: [
    new Required(),
    new MinLength(8),
]),
new Param('passwordConfirmation', from: ParamFrom::JSON, type: null, validate: [
    new Required(),
    new EqualWithColumn('password', strict: true),
])
```

关联字段必须也定义为 `Param`。比较使用的是双方解析及类型转换之后的值，严格比较时尤其要注意两边的 `type` 是否一致。

## 日期与时间规则

| 规则 | 用法 | 说明 |
| --- | --- | --- |
| `Date` | `new Date('2026-01-01')` | 与指定日期比较 `Y-m-d`，忽略时间 |
| `DateFormat` | `new DateFormat('Y-m-d')` | 严格检查指定日期格式和溢出日期 |
| `DateAfter` | `new DateAfter('2026-01-01')` | 日期严格晚于固定日期 |
| `DateBefore` | `new DateBefore('2027-01-01')` | 日期严格早于固定日期 |
| `DateAfterColumn` | `new DateAfterColumn('startDate')` | 日期严格晚于另一个参数 |
| `DateBeforeColumn` | `new DateBeforeColumn('endDate')` | 日期严格早于另一个参数 |
| `Timestamp` | `new Timestamp()` | 秒级整数时间戳 |
| `TimestampAfter` | `new TimestampAfter('2026-01-01')` | 时间戳严格晚于固定时间 |
| `TimestampBefore` | `new TimestampBefore('2027-01-01')` | 时间戳严格早于固定时间 |

日期区间示例：

```php
new Param('startDate', from: ParamFrom::JSON, validate: [
    new Required(),
    new DateFormat('Y-m-d'),
]),
new Param('endDate', from: ParamFrom::JSON, validate: [
    new Required(),
    new DateFormat('Y-m-d'),
    new DateAfterColumn('startDate'),
])
```

日期和时间戳规则使用服务器时区。生产项目应统一配置时区，并在 API 文档中说明时间格式和时区。

## 文件规则

`IsFile` 用于上传文件：

```php
new Param(
    name: 'avatar',
    from: ParamFrom::FILE,
    type: ParamType::FILE,
    validate: [
        new Required(),
        new IsFile(
            maxSize: 2 * 1024 * 1024,
            allowExt: ['jpg', 'png'],
            errorMsg: '头像必须是 2MB 以内的 JPG 或 PNG 文件'
        ),
    ]
)
```

`maxSize` 单位是字节，`allowExt` 使用小写扩展名。它根据上传对象和客户端文件名扩展名验证，不检查真实 MIME 或文件内容。图片上传仍应使用 `finfo` 检查 MIME，必要时重新解码生成。

`ParamFrom::FILE` 必须是唯一参数来源，不能与 GET、POST 等来源组合。

## 自定义错误信息

所有内置规则最后一个构造参数都是 `errorMsg`：

```php
new Min(
    min: 18,
    errorMsg: '{#validateParam} 不能小于 {#min}'
)
```

常用占位符：

- `{#validateParam}`：当前参数名。
- `{#min}`、`{#max}`：数值边界。
- `{#minLen}`、`{#maxLen}`：长度边界。
- `{#compare}` 或 `{#paramName}`：比较目标。
- `DateFormat` 使用 `{#format}`。

不同规则支持的占位符取决于规则本身的属性。简单项目也可以直接写固定中文文案。

## 自定义验证函数 `Func`

内置规则无法表达业务规则时，可以使用 `Func`。由于 PHP Attribute 参数必须是常量表达式，Attribute 中不要直接写闭包，应传静态方法：

新建 `App/Validator/TicketValidator.php`：

```php
<?php

namespace App\Validator;

use EasySwoole\HttpAnnotation\Validator\Bean\ValidateRequest;

class TicketValidator
{
    public static function check(ValidateRequest $context): bool
    {
        $value = $context->validateParam->parsedValue();

        return is_string($value)
            && str_starts_with($value, 'ticket-');
    }
}
```

控制器中使用：

```php
use App\Validator\TicketValidator;
use EasySwoole\HttpAnnotation\Validator\Func;

new Param(
    name: 'ticket',
    from: ParamFrom::JSON,
    validate: [
        new Required(),
        new Func(
            func: [TicketValidator::class, 'check'],
            errorMsg: 'ticket 格式不正确'
        ),
    ]
)
```

也可以让验证器实现 `ValidateFuncInterface`，再将对象传给 `Func`。仅在普通 PHP 代码动态创建规则时才适合使用闭包。

## 常用组合

用户名：

```php
new Param('username', from: ParamFrom::JSON, validate: [
    new Required(),
    new NotEmpty(),
    new AlphaNum(),
    new BetweenLen(4, 20),
]);
```

分页页码：

```php
new Param('page', from: ParamFrom::GET, type: null, value: 1, validate: [
    new Integer(),
    new Min(1),
]);
```

可选邮箱：

```php
new Param('email', from: ParamFrom::JSON, type: null, validate: [
    new Optional(),
    new IsEmail(),
]);
```

价格：

```php
new Param('price', from: ParamFrom::JSON, type: null, validate: [
    new Required(),
    new Money(2),
]);
```

## 常见错误

- 忘记导入 Validator 类，PHP 会在当前控制器命名空间中寻找同名类。
- 只写 `ParamType::INT`，却没有使用 `Integer` 验证原始输入。
- 中文长度使用 `Length`，导致一个汉字被计算为多个字节。
- `Optional` 与 `Required`、`NotEmpty` 同时使用，产生互斥配置。
- JSON 数组没有设置 `type: null`，被默认 STRING 转换破坏。
- 字段比较规则引用了未定义的参数。
- 文件扩展名验证通过后就直接信任文件内容。
- 把数据库唯一性、库存等业务规则全部写成参数 Validator；这类规则仍应由 Service 和数据库约束完成。

下一章：[生成接口文档](/Http/AnnotationController/document.md)。
