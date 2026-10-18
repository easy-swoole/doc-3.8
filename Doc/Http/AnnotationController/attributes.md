# Attribute 清单与定义参数

本页是 `easyswoole/http-annotation` 4.x 的**定义速查**：先看 Attribute 写在哪里，再看构造参数、默认值和说明字段的类型。这里的“注解”指 PHP 8 原生 Attribute（`#[...]`），不是 PHPDoc 注释。初次使用可先运行[安装与继承](/Http/AnnotationController/index.md)中的控制器。

## 组件支持哪些 Attribute

| Attribute | 放在哪里 | 作用 | 用法章节 |
| --- | --- | --- | --- |
| `#[ApiGroup]` | 控制器类 | 定义接口文档的分组与说明 | [控制器组与接口定义](/Http/AnnotationController/api.md) |
| `#[Api]` | 公开 Action 方法 | 声明请求方法、参数、说明和示例 | [控制器组与接口定义](/Http/AnnotationController/api.md) |
| `new Param(...)` / `#[Param(...)]` | `Api::requestParam` 数组 / `onRequest()` 方法 | 定义参数来源、类型、默认值、校验与说明；`onRequest` 上可重复 | [接口参数](/Http/AnnotationController/params.md)、[公共参数](/Http/AnnotationController/common-params.md) |
| `#[ExtendParam]` | 覆盖父类的 `onRequest()` 方法 | 继承父类公共参数定义 | [公共参数与继承](/Http/AnnotationController/common-params.md) |
| `#[PreCall]` | 控制器类或 Action 方法 | 在解析前或 Action 前执行回调 | [前置回调与属性注入](#前置回调与属性注入) |
| `#[Di]` | 公开或受保护的属性 | 从 DI 容器注入属性 | [前置回调与属性注入](#前置回调与属性注入) |
| `#[Context]` | 公开或受保护的属性 | 从协程上下文注入属性 | [前置回调与属性注入](#前置回调与属性注入) |

前五个类位于 `EasySwoole\HttpAnnotation\Attributes`，`Di` 和 `Context` 位于 `EasySwoole\HttpAnnotation\Attributes\Property`。`Required`、`Min`、`IsEmail` 等是 `Param::validate` 中的**验证规则对象**，不属于上表的 Attribute；规则清单见[Attribute 验证规则](/Http/AnnotationController/validation-rules.md)。

## `ApiGroup`：控制器组

```php
#[ApiGroup(groupName: 'Shop.Order', description: '订单相关接口')]
class Order extends AnnotationController
{
}
```

| 构造参数 | 类型 / 默认值 | 含义 |
| --- | --- | --- |
| `groupName` | `string`，必填 | 唯一的分组名。点号建立文档层级，如 `Shop.Order` 形成 Shop → Order |
| `description` | `string\|Text\|Markdown\|null`，默认 `null` | 分组说明，显示在生成文档的分组页 |

`ApiGroup` 不会创建 URL 前缀；扫描文档时同名分组会报错。一个控制器最多定义一个组，完整示例见[控制器组与接口定义](/Http/AnnotationController/api.md)。

## `Api`：接口 Action

```php
#[Api(
    allowMethod: HttpMethod::POST,
    acceptContentType: ContentType::JSON,
    requestParam: [new Param(name: 'name', from: ParamFrom::JSON)],
    description: '创建订单'
)]
public function create(string $name): void
{
    $this->writeJson(201, ['name' => $name]);
}
```

| 构造参数 | 类型 / 默认值 | 含义 |
| --- | --- | --- |
| `allowMethod` | `HttpMethod`，默认 `GET` | 单个 HTTP 方法：`GET`、`POST`、`PUT`、`DELETE`、`HEAD`、`PATCH`、`OPTIONS` |
| `registerRouter` | `bool`，默认 `false` | 当前 4.x 尚未实现自动注册路由，设置为 `true` 也不能代替 Router |
| `requestParam` | `Param[]`，默认 `[]` | 本 Action 的请求参数声明 |
| `responseParam` | `array`，默认 `[]` | 可定义响应参数；当前 HTML 模板尚不显示响应参数表 |
| `requestExamples` | 示例对象数组，默认 `[]` | 请求样例，如 `Array2Json`、`ArrayForm`、`Raw` |
| `responseExamples` | 示例对象数组，默认 `[]` | 成功/失败响应样例 |
| `description` | `string\|Text\|Markdown\|null`，默认 `null` | 接口说明 |
| `deprecated` | `bool`，默认 `false` | 在文档中标记废弃，不会禁止访问 |
| `acceptContentType` | `ContentType\|null`，GET/HEAD 默认 `null`，其余方法默认 `FORM_DATA` | 声明允许的请求体来源；可选 `FORM_DATA`、`FORM_URLENCODED`、`JSON`、`XML`、`RAW` |

`GET`/`HEAD` 不能设置请求体 Content-Type；`ContentType::JSON` 应配 `ParamFrom::JSON`，`FORM_DATA` 可配 `POST` 或 `FILE`，`FORM_URLENCODED` 配 `POST`，`XML` 配 `XML`，`RAW` 配 `RAW_POST`。`GET`、`HEADER`、`COOKIE` 等非请求体来源可与适用的方法组合。`Api` 会检查请求方法和定义一致性，**不会自动生成自定义路由**。

## `Param`：参数定义

```php
new Param(
    name: 'page',
    from: ParamFrom::GET,
    type: ParamType::INT,
    value: 1,
    description: '页码，从 1 开始',
    validate: [new Min(1)]
)
```

| 构造参数 | 类型 / 默认值 | 含义 |
| --- | --- | --- |
| `name` | `string`，必填 | 参数名；普通形参模式下必须与 Action 形参名一致 |
| `from` | `ParamFrom\|array`，默认 `GET` | 来源；数组按顺序取第一个命中的值。可用 `GET`、`POST`、`JSON`、`XML`、`RAW_POST`、`FILE`、`HEADER`、`COOKIE`、`DI`、`CONTEXT` |
| `validate` | 验证规则对象数组，默认 `[]` | 如 `new Required()`、`new Min(1)`；详细用法见[参数验证](/Http/AnnotationController/validation.md) |
| `value` | `mixed`，默认 `null` | 未取到参数时的默认值 |
| `deprecated` | `bool`，默认 `false` | 在文档中标记该参数废弃 |
| `description` | `string\|Text\|null`，默认 `null` | 参数说明；**不接受 `Markdown`** |
| `type` | `ParamType\|null`，默认 `STRING` | 取到值后的类型转换；可用 `STRING`、`INT`、`DOUBLE`、`REAL`、`FLOAT`、`BOOLEAN`、`FILE`、`NULL_WHILE_EMPTY`；`null` 保留原值 |
| `ignoreAction` | `string[]`，默认 `[]` | 仅用于 `onRequest()` 的公共参数，列出跳过的 Action 方法名 |
| `ignorePassArgWhenNotSet` | `bool`，默认 `false` | Action 用单个 `array` 形参接收参数时，未实际取到该参数就不放进数组 |

`ParamFrom::FILE` 不能与其他来源放在同一 `from` 数组中，上传文件还应使用 `type: ParamType::FILE`。类型转换不等于数据校验，例如 `INT` 会把原始字符串强制转换为整数；需要明确合法性时增加 `Integer` 等规则。`ignoreAction` 不能写在 Action 的 `Api::requestParam` 里。

## 三种 `description` 的写法

三种位置不要混用类型：

```php
use EasySwoole\HttpAnnotation\Bean\Description\Markdown;
use EasySwoole\HttpAnnotation\Bean\Description\Text;

#[ApiGroup(groupName: 'Shop.Order', description: '订单接口')]
class Order extends AnnotationController
{
    #[Api(description: new Markdown(EASYSWOOLE_ROOT . '/Docs/order-api.md'))]
    public function index(): void {}

    #[Api(requestParam: [
        new Param(name: 'id', description: new Text('订单 ID')),
    ])]
    public function detail(string $id): void {}
}
```

上面的 `Docs/order-api.md` 只是示例，使用前需要自己创建该文件；`Markdown` 的参数是**现有 Markdown 文件路径**，不是 Markdown 正文。`Text('说明')` 表示纯文本；`new Text('/绝对路径/说明.txt', isFile: true)` 可从文件读取。`ApiGroup`、`Api` 也都可以直接传字符串；`Param` 只能传字符串或 `Text`。生成 HTML 时，文本会转义显示，Markdown 文件会被渲染；说明文件应来自可信内容。

## `onRequest` 公共参数与继承

`#[Param]` 直接标在 `onRequest()` 上时可重复，表示该控制器所有适用 Action 的公共参数。它们在进入 `onRequest()` **之前**解析、转换并验证，然后以键值数组传给第二个形参：

```php
#[Param(name: 'token', from: ParamFrom::HEADER, description: '登录令牌')]
#[Param(name: 'tenantId', from: ParamFrom::GET, type: ParamType::INT)]
protected function onRequest(?string $action, ?array $data = null): ?bool
{
    $token = $data['token'] ?? null;
    $tenantId = $data['tenantId'] ?? null;
    return true;
}
```

`$action` 是即将运行的 Action 名称。`#[Param(..., ignoreAction: ['login'])]` 可以使登录 Action 跳过某项公共参数。Action 的 `Api::requestParam` 若声明同名参数，会覆盖公共定义。当前 4.x 对带 `#[Api(allowMethod: HttpMethod::GET)]` 的 Action 还有一致性检查：适用的公共参数来源须包含 `ParamFrom::GET`、由该 Action 同名覆盖，或通过 `ignoreAction` 排除；因此上例若实际使用 GET 的 `#[Api]`，Header `token` 需要按业务重新设计，而不能简单照搬。

覆盖父控制器的 `onRequest()` 时，默认不会自动继承父方法上的 `#[Param]`。在子方法上加 `#[ExtendParam]` 可继承全部父参数；`#[ExtendParam(parentParamsName: ['token'])]` 只继承指定名称。子类同名参数优先。完整控制器及 `ignoreAction` 用法见[onRequest 公共参数与继承](/Http/AnnotationController/common-params.md)。

## 前置回调与属性注入

| Attribute | 构造参数 | 执行时机 |
| --- | --- | --- |
| `#[PreCall([Hooks::class, 'before'])]` | 一个可调用值 `callable $func` | 类上：参数解析前，回调收到 `($action, $request, $response)`；方法上：参数验证后，收到 `($request, $response)`。返回 `false` 停止后续执行 |
| `#[Di(key: 'service')]` | 必填 `string $key` | 读取 DI 容器对应键，注入公开/受保护属性 |
| `#[Context(key: 'user')]` | 必填 `string $key` | 读取协程上下文对应键，注入公开/受保护属性 |

同一属性不能同时标 `Di` 和 `Context`。属性注入发生在方法级 `PreCall` 之后。`PreCall`、`Di`、`Context` 不是文档分组或参数验证规则；只是控制器执行流程的扩展点。初学者可先掌握前三个核心 Attribute，再按需使用这些扩展。

下一章：[控制器组与接口定义](/Http/AnnotationController/api.md)。

## 源码依据

- [4.x README](https://github.com/easy-swoole/http-annotation/blob/4.x/README.md)
- [Attributes 源码目录](https://github.com/easy-swoole/http-annotation/tree/4.x/src/Attributes)
- [AttributeCache](https://github.com/easy-swoole/http-annotation/blob/4.x/src/AttributeCache.php)
