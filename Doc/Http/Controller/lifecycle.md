# Action 与生命周期

一个请求进入控制器后，并不是直接调用 Action。基础控制器通过 `__hook()` 依次执行请求前置逻辑、Action、收尾逻辑和异常处理。

## 执行顺序

```text
构造 Controller
    ↓
onRequest()
    ↓ 返回 false 时停止
Action
    ↓
afterAction()
    ↓
响应发送
```

任意阶段抛出的异常会进入 `onException()`。

## onRequest：鉴权和公共前置检查

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

返回 `false` 会跳过 Action，但框架仍会进入 `finally` 执行 `afterAction()`。不要在这里保存跨请求的可变静态状态。

## Action：处理业务

```php
public function detail(): void
{
    $id = (int)$this->request()->getRequestParam('id');
    $this->writeJson(200, ['id' => $id]);
}
```

如果 Action 返回一个不同于当前路径的非空字符串，Dispatcher 会把它当作新的控制器路径继续分发：

```php
public function legacy(): string
{
    return '/user/detail';
}
```

内部辅助方法应使用 `private` 或 `protected`，避免成为可路由 Action。

## afterAction：统一收尾

```php
protected function afterAction(?string $actionName): void
{
    // 记录指标、释放请求级业务资源等
}
```

数据库连接通常应由连接池和 `finally` 管理，不要只依赖 `afterAction()` 才归还关键资源。

本章只描述普通 `Controller` 的执行顺序。注解控制器还会在进入 Action 前提取并验证参数，详见[注解控制器：参数来源与传参](/Http/AnnotationController/params.md)。

## 源码依据

- [Controller::__hook](https://github.com/easy-swoole/http/blob/3.x/src/AbstractInterface/Controller.php)
