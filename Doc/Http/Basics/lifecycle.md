# 请求生命周期

本章描述的是一个请求从进入 Swoole 到响应发送给客户端的完整过程。控制器中的 `onRequest → Action → afterAction` 只是整个 HTTP 生命周期中“执行控制器”的一部分。

## 执行顺序

```text
客户端发起 HTTP 请求
    ↓
Swoole 触发 onRequest 事件
    ↓
框架创建 Request 和 Response 对象
    ↓
HTTP_GLOBAL_ON_REQUEST 全局请求钩子
    ├── 返回 false：跳过路由和控制器
    └── 返回其他值：继续分发请求
            ↓
Dispatcher 解析请求路径
    ↓
匹配 Router 中的显式路由
    ├── 匹配成功：执行路由 Handler
    ├── 方法不允许：执行 405 回调
    ├── 路由不存在：执行 404 回调
    └── 非全局模式且未处理：继续自动控制器映射
            ↓
创建 Controller 对象
    ↓
Controller::onRequest()
    ├── 返回 false：跳过 Action
    └── 返回其他值：执行 Action
            ↓
Controller Action
    ↓
Controller::afterAction()
    ↓
HTTP_GLOBAL_AFTER_REQUEST 全局收尾钩子
    ↓
Response 将状态码、Header、Cookie 和 Body 写回 Swoole
    ↓
客户端收到响应
```

如果任一主要阶段抛出未处理异常，会进入 HTTP 全局异常处理器。无论路由或控制器是否正常完成，框架都会尝试执行 `HTTP_GLOBAL_AFTER_REQUEST`，最后统一发送 Response。

## 第一阶段：Swoole 接收请求

EasySwoole 启动后，Swoole HTTP Server 在 Worker 进程中监听端口。当客户端访问：

```bash
curl http://127.0.0.1:9501/users/1
```

Swoole 触发 `onRequest` 事件，并提供原始的：

```php
Swoole\Http\Request
Swoole\Http\Response
```

框架随后把它们封装为：

```php
EasySwoole\Http\Request
EasySwoole\Http\Response
```

后续 Router 和 Controller 通常操作框架封装对象，不需要直接使用 Swoole 原始对象。

## 第二阶段：执行全局请求钩子

框架创建 Request 和 Response 后，会检查 `HTTP_GLOBAL_ON_REQUEST` 是否配置了回调。这个钩子发生在路由匹配之前，适合处理真正作用于全部 HTTP 请求的逻辑，例如：

- 生成 Request ID。
- 拒绝非法 Host。
- 处理服务维护状态。
- 记录请求开始时间。

如果全局请求钩子返回 `false`，Dispatcher 不会继续匹配路由，也不会创建控制器。因此在返回 `false` 之前应写入完整响应：

```php
$response->withStatus(503);
$response->write('Service Unavailable');
return false;
```

这里的全局钩子与控制器的 `onRequest()` 不同：

| 拦截点 | 执行范围 | 执行时机 |
| --- | --- | --- |
| `HTTP_GLOBAL_ON_REQUEST` | 所有 HTTP 请求 | 路由匹配之前 |
| `Controller::onRequest()` | 当前控制器或共同 Base 的子控制器 | 已匹配并创建控制器之后 |

管理员鉴权通常更适合放在管理员 Base 控制器中，而不是放到真正的全局钩子，否则登录页、公开接口和健康检查也需要额外排除。

## 第三阶段：路由分发

全局请求钩子放行后，`Dispatcher` 开始处理请求：

```text
读取 URI Path
    ↓
根据 pathInfoMode 决定是否去除扩展名
    ↓
使用 FastRoute 匹配显式路由
    ↓
得到闭包 Handler 或 /Controller/action Handler
```

例如在 `App/HttpController/Router.php` 中定义：

```php
$routeCollector->get('/users/{id:\\d+}', '/User/detail');
```

请求 `/users/1` 匹配后，Dispatcher 会把 Handler `/User/detail` 转换为：

```text
App\HttpController\User::detail()
```

如果没有显式路由匹配：

- 全局路由模式开启时，不再尝试自动控制器映射。
- 全局路由模式关闭时，继续根据 URL 查找控制器。
- 设置了 404 或 405 回调时，执行对应回调；回调返回 `false` 表示响应已经处理完成。

关于 `pathInfoMode`、动态参数和全局路由模式，参见“HTTP 服务 → 路由 → 路由基础”。

## 第四阶段：执行控制器

找到控制器后，框架使用当前 Request、Response 和 Action 名创建 Controller 对象。控制器内部再执行一段更细的生命周期：

```text
创建 Controller
    ↓
onRequest($action)
    ├── false：不执行 Action
    └── true：继续
            ↓
Action
    ↓
afterAction($action)
```

例如管理员 Base 控制器可以在 `onRequest()` 中鉴权：

```php
protected function onRequest(?string $action): ?bool
{
    $token = $this->request()->getHeaderLine('Authorization');

    if ($token === '') {
        $this->writeJson(401, null, '请先登录');
        return false;
    }

    return true;
}
```

返回 `false` 只会跳过 Action，`afterAction()` 仍位于 `finally` 中并会继续执行。详细说明参见“控制器 → 控制器生命周期”。

## 第五阶段：全局收尾

路由和控制器处理完成后，框架在 `finally` 中调用 `HTTP_GLOBAL_AFTER_REQUEST`。因此以下情况发生时，它仍会被尝试执行：

- 全局请求钩子返回 `false`。
- Router 回调提前结束请求。
- 控制器 `onRequest()` 返回 `false`。
- Action 正常完成。
- 前面的处理过程抛出异常。

适合放在这里的逻辑包括：

- 记录最终状态码和请求耗时。
- 提交请求指标。
- 清理请求级上下文。

不要只依赖这个钩子归还数据库连接等关键资源。获取资源的代码仍应使用就近的 `try/finally`，连接池也应提供可靠的回收机制。

## 第六阶段：发送响应

收尾钩子结束后，框架统一把 Response 写回 Swoole，顺序包括：

```text
HTTP 状态码
    ↓
Headers
    ↓
Cookies
    ↓
Body 或 sendFile
    ↓
结束 Swoole Response
```

这也是为什么业务代码通常只需要操作：

```php
$this->response()->withStatus(201);
$this->response()->withHeader('X-Request-Id', $requestId);
$this->response()->write('created');
```

控制器不需要主动调用底层 Swoole Response 的 `end()`。提前直接结束底层响应后再修改 Header 或 Body，可能导致内容无法发送或重复响应。

## 异常从哪里处理

异常处理具有由内向外的层次：

```text
Controller 内部异常
    ↓
Controller::onException()
    ↓ 未处理或再次抛出
Dispatcher 的 HTTP 异常处理器
    ↓
HTTP_GLOBAL_AFTER_REQUEST
    ↓
发送错误 Response
```

生产环境的异常处理器应记录完整异常，但只向客户端返回稳定的错误码、简短消息和 Request ID，不能返回堆栈、绝对路径、SQL 或密钥。

## 常驻进程需要特别注意

请求处理完成后，Worker 进程不会退出。类静态属性和单例也不会自动恢复初始值：

```php
// 错误：下一个请求可能读到上一个用户。
class CurrentUser
{
    public static ?int $id = null;
}
```

当前用户、Token、临时数组等请求态数据应放在：

- Controller 实例属性。
- 方法局部变量。
- Request 对象。
- 能够在请求结束时正确清理的协程上下文。

数据库连接、HTTP Client 等可复用资源可以放入连接池，但一次请求的业务状态不能放入常驻全局对象。

## 源码执行关系

完整流程主要对应以下组件：

```text
EasySwoole\EasySwoole\Core
    └── 注册 Swoole onRequest，执行全局前后钩子并发送响应

EasySwoole\Http\Dispatcher
    └── 路由匹配、自动控制器映射和全局异常处理

EasySwoole\Http\AbstractInterface\Controller
    └── onRequest、Action、afterAction 和 onException

EasySwoole\Http\Response
    └── 将状态码、Header、Cookie、Body 或文件写回 Swoole
```
