# Trace 安装与快速开始

`easyswoole/trace` 2.0.2 是轻量级手动调用链追踪组件，用于记录 HTTP 请求、CLI 任务、协程任务、RPC 调用和消费任务中的调用关系、耗时、参数及异常。

组件只负责生成 Trace/Span、计算耗时和整理数据，不会自动完成以下工作：

- 不会自动拦截 EasySwoole HTTP 请求。
- 不会因为调用 `parallel()` 就启动协程。
- 不会自行决定数据库结构或直接写入数据库；应用配置自动持久化回调后，组件可以在协程结束或对象析构时执行补写兜底。
- 不会自动解析和发送 HTTP `traceparent` Header。

这些步骤需要应用在请求入口、HTTP 客户端和存储层中接入。

## 环境与安装

组件要求 PHP 8.1 及以上：

```bash
composer require easyswoole/trace:"2.0.2"
composer show easyswoole/trace
```

它本身没有强制依赖 Swoole，因此 CLI 脚本也可以使用。

## 结构设计说明

在开始写代码之前，可以先把一次链路追踪理解成一棵“调用树”。

例如用户访问个人资料接口时，程序可能依次经过控制器、业务服务和数据库：

```text
Trace：一次完整请求
└── TracePoint：UserController::profile
    └── TracePoint：UserService::profile
        └── TracePoint：query-user
```

这几个概念的职责如下：

| 概念 | 作用 | 示例 |
| --- | --- | --- |
| `Trace` | 表示一次完整的业务调用，是整棵调用树的根节点 | 一次 HTTP 请求、一次定时任务或一条消息的消费过程 |
| `TracePoint` | 表示调用过程中的一个步骤，也常被称为 Span | 控制器、Service 方法、SQL 查询或远程接口调用 |
| `traceId` | 标识整条调用链；同一棵树中的所有节点共享该值 | 根据一个 ID 查询本次请求的全部调用记录 |
| `spanId` | 标识当前节点，每个节点都有自己的值 | 精确定位某一次数据库查询 |
| `parentSpanId` | 指向当前节点的父节点，用于恢复树形关系 | 数据库节点的父节点是 Service 节点 |
| `status` | 记录节点当前执行结果 | `running`、`success`、`exception`、`timeout`、`abandoned` |
| `endedBy` | 记录节点由什么机制结束 | 手动结束、父节点收口、协程 defer 或析构兜底 |

`Trace` 继承自 `TracePoint`，因此根节点和普通节点都可以记录名称、参数、状态、开始时间和耗时，也都能继续创建子节点。

### 一次调用链如何产生

完整流程通常分为五步：

```text
请求或任务开始
    ↓
创建根 Trace
    ↓
进入新的调用步骤时创建子 TracePoint
    ↓
步骤完成、异常或超时时结束对应节点
    ↓
读取 spans() 并由应用保存或输出
```

对应到代码中的主要方法：

| 操作 | 方法 | 说明 |
| --- | --- | --- |
| 创建根节点 | `new Trace()` | 一次请求或任务通常只创建一个根 Trace |
| 创建串行子节点 | `next()` | 表示紧接着执行的下一步；一个节点只能拥有一个 `next()` 子节点 |
| 创建并列子节点 | `parallel()` | 表示同一个父节点下可以存在多个并列任务，但该方法不会自动创建协程 |
| 正常结束 | `endCall()` | 将节点标记为成功并计算耗时 |
| 异常结束 | `fail($error)` | 将节点标记为异常并记录异常信息 |
| 超时结束 | `timeout()` | 将节点标记为超时 |
| 获取全部节点 | `spans()` | 返回适合批量持久化的 `SpanBean` 列表 |

### 为什么每个节点都要结束

节点从创建时开始计时，调用 `endCall()`、`fail()` 或 `timeout()` 时停止计时。如果子节点尚未结束就先结束父节点，组件会把未结束的子节点标记为 `abandoned`，并把结束来源记录为 `parent`，表示这段调用没有被正常收尾。

2.0.2 还会为在 Swoole 协程中创建的节点注册 `Coroutine::defer()`。如果节点到协程结束时仍未收口，会以 `abandoned` 状态结束，并记录 `ended_by=coroutine_defer`。非协程环境中的对象析构也提供同类兜底并记录 `ended_by=destructor`。这些机制用于发现遗漏，不应替代正常的显式结束流程。

因此，推荐在 `try/catch/finally` 中管理调用链：正常完成时调用 `endCall()`，发生异常时调用 `fail()`，最后在 `finally` 中统一保存。组件只生成和整理链路数据，数据要写入数据库、日志或第三方平台，需要由应用自行实现。

## 第一个调用链

在项目根目录新建 `trace-demo.php`，写入下面的完整脚本：

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use EasySwoole\Trace\Trace;
use EasySwoole\Trace\Utility;

$trace = new Trace('http-request', params: [
    'method' => 'GET',
    'route' => '/users/{id}',
]);

$controller = $trace->next('UserController::profile');
$service = $controller->next('UserService::profile', [
    'user_id' => 10001,
]);

$database = $service->next('query-user');

try {
    // 执行数据库查询。
    $database->endCall();
    $service->endCall();
    $controller->endCall();
    $trace->endCall();
} catch (Throwable $error) {
    $database->fail($error);
    $service->fail($error);
    $controller->fail($error);
    $trace->fail($error);
    throw $error;
}

echo Utility::toTree($trace);
```

运行 `php trace-demo.php`，应看到从 `http-request` 到 `query-user` 的四层树。实际 Trace ID、Span ID 和耗时每次都会不同；这里没有发起真实 HTTP 请求，也不需要启动服务。接下来的[调用链与状态](/Library/Trace/span.md)会展示带分支与状态的输出。

形成的结构：

```text
http-request
└── UserController::profile
    └── UserService::profile
        └── query-user
```

## 在控制器中创建 Trace

```php
use EasySwoole\Trace\Trace;

public function profile(): void
{
    $trace = new Trace('HTTP GET /users/{id}', params: [
        'route' => '/users/{id}',
        'request_id' => $this->request()->getHeaderLine('x-request-id'),
    ]);

    $action = $trace->next('UserController::profile');

    try {
        $user = $this->userService->find(10001, $action);
        $action->endCall();
        $trace->endCall();
        $this->writeJson(200, $user);
    } catch (Throwable $error) {
        $action->fail($error);
        $trace->fail($error);
        throw $error;
    } finally {
        $this->traceRepository->save($trace->spans());
    }
}
```

示例通过参数显式把当前节点传入 Service。大型项目也可以把根 Trace 放进 `ContextManager`，让当前请求协程内的服务读取；协程结束后必须清理上下文，不能用普通全局静态变量保存当前 Trace。

示例中的 `$this->traceRepository` 是项目自行实现的存储服务，不是 Trace 组件内置对象。组件提供的是 `spans()` 和 `SpanBean`，具体写入 MySQL、日志平台或其他存储的方式由应用决定，参见[持久化与展示](/Library/Trace/storage.md)。

## 参数记录原则

```php
$point = $trace->next('query-user', [
    'user_id' => 10001,
    'status' => 'active',
]);
```

可以记录 ID、路由、方法、数据量等定位问题所需字段，但不要记录：

- 密码、Token、Cookie、Authorization 和密钥。
- 完整身份证、银行卡、手机号等敏感数据。
- 完整请求体、响应体、文件内容或大型对象。

下一章：[调用链与状态](/Library/Trace/span.md)。
