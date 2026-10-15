# 单例模式

Component 提供两种单例 trait：

| Trait | 实例作用域 | 适合保存 |
| --- | --- | --- |
| `Singleton` | 当前 PHP 进程 | 配置对象、无状态服务、进程级管理器 |
| `CoroutineSingleTon` | 当前协程 | 请求上下文、当前用户和链路追踪信息 |

二者都通过 `getInstance()` 取得实例，但隔离范围完全不同。选择时应先判断数据是希望由整个 Worker 共用，还是只能属于当前请求协程。

## 进程内单例 Singleton

`Singleton` 为类提供进程内单例。第一次调用 `getInstance()` 时传入的参数用于构造实例，后续调用只返回已经创建的对象，不会重新执行构造函数。

```php
use EasySwoole\Component\Singleton;

class ConfigCenter
{
    use Singleton;

    public function __construct(public array $config = [])
    {
    }
}

$config = ConfigCenter::getInstance(['debug' => true]);
$sameConfig = ConfigCenter::getInstance(['debug' => false]);

var_dump($config === $sameConfig);       // true
var_dump($sameConfig->config['debug']);  // true
```

第二次传入的构造参数不会生效，因为实例已经在第一次调用时创建。

进程内单例只在当前 PHP 进程有效。假设 Swoole 启动了四个 Worker，每个 Worker 都会分别拥有一个 `ConfigCenter` 实例，它们之间不会自动共享属性修改。

不要在 Server 启动前创建包含数据库连接、Redis 连接或客户端 Socket 的单例，再期望子进程安全共用这些连接。与进程绑定的资源应在对应 Worker 创建完成后初始化。

## 协程单例 CoroutineSingleTon

`CoroutineSingleTon` 按协程 ID 保存实例：同一个协程内多次调用返回同一个对象，不同协程得到相互隔离的对象。协程结束时，组件会自动清理该协程对应的实例。

```php
use EasySwoole\Component\CoroutineSingleTon;

class RequestScope
{
    use CoroutineSingleTon;

    public array $data = [];
}

Co\run(function (): void {
    go(function (): void {
        RequestScope::getInstance()->data['requestId'] = 'req-1';
        echo RequestScope::getInstance()->data['requestId'];
    });

    go(function (): void {
        RequestScope::getInstance()->data['requestId'] = 'req-2';
        echo RequestScope::getInstance()->data['requestId'];
    });
});
```

两个子协程中的 `RequestScope` 不是同一个实例，因此不会互相覆盖 `requestId`。

在非协程环境中，当前协程 ID 通常为 `-1`，此时无法依靠协程结束自动清理。确实需要在这种环境使用时，应在业务结束后调用：

```php
RequestScope::destroy();
```

## 如何选择

使用 `Singleton` 的典型场景：

- 当前 Worker 内共用的配置访问器。
- 无请求状态的格式转换器或服务对象。
- 组件自身的 Manager 类。

使用 `CoroutineSingleTon` 的典型场景：

- 当前 HTTP 请求的用户信息。
- 当前请求的 trace ID、日志上下文。
- 只允许在一个协程调用链中传递的临时数据。

如果数据需要跨 Worker 共享，这两种单例都不适合。单机相关进程间共享可以使用 `Swoole\Atomic` 或 `Swoole\Table`；跨机器共享应使用 Redis、数据库等外部存储。

## 常见错误

- 把 `Singleton` 当成整个服务器唯一实例。它实际上是每个进程一份。
- 使用 `Singleton` 保存当前登录用户，导致同一 Worker 中的多个请求相互污染。
- 在父进程提前创建网络连接单例，然后让多个子进程继承连接。
- 在非协程环境使用 `CoroutineSingleTon`，却从不调用 `destroy()`。

## 源码依据

- [Singleton](https://github.com/easy-swoole/component/blob/master/src/Singleton.php)
- [CoroutineSingleTon](https://github.com/easy-swoole/component/blob/master/src/CoroutineSingleTon.php)
