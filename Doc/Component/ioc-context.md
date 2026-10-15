# IOC 与上下文

Component 提供 `Di` 和 `ContextManager` 两种用途不同的数据管理工具：

| 组件 | 作用域 | 主要用途 |
| --- | --- | --- |
| `Di` | 当前 PHP 进程 | 注册配置、服务对象、类名和服务别名 |
| `ContextManager` | 当前协程 | 保存当前请求的用户、请求 ID 和链路信息 |

IOC 容器负责“业务类需要哪些服务以及如何取得”，协程上下文负责“本次请求携带哪些临时数据”。服务对象通常放入 `Di`，请求状态放入 `ContextManager`，不要把当前登录用户等请求数据写入进程级 IOC 容器。

## IOC 与依赖注入

IOC（控制反转）是把对象创建和依赖管理从业务代码中抽离。业务代码不再到处手动 `new` 依赖对象，而是先把服务注册到容器，需要时再按名称取得。

Component 中对应的实现是 `EasySwoole\Component\Di`。`Di` 使用 `Singleton`，因此每个 Worker 进程都有自己的容器实例。

```php
use EasySwoole\Component\Di;

$di = Di::getInstance();
```

## 注册和读取普通值

配置数组、字符串等普通值可以直接保存：

```php
$di->set('config', [
    'debug' => true,
    'timezone' => 'Asia/Shanghai',
]);

$config = $di->get('config');
```

`set()` 只负责登记，不会在注册时检查或转换类型。读取不存在的键时，默认返回 `null`。

## 注册已创建的对象

```php
$logger = new AppLogger('/tmp/app.log');
$di->set('logger', $logger);

$sameLogger = $di->get('logger');
var_dump($logger === $sameLogger); // true
```

保存对象后，`get()` 会原样返回该对象。由于 `Di` 是进程级单例，同一个 Worker 中后续读取会获得同一个对象。

不要在父进程提前注册数据库连接或客户端 Socket，再让多个 Worker 继承使用。网络资源应在对应 Worker 创建后初始化。

## 按类名延迟创建对象

把类名字符串注册到 `Di` 时，对象不会立即创建。第一次 `get()` 才会通过反射实例化，并把实例缓存回容器：

```php
class Mailer
{
    public function __construct(
        private string $host,
        private int $port
    ) {
    }
}

$di->set(
    'mailer',
    Mailer::class,
    'smtp.example.com',
    25
);

$mailer = $di->get('mailer');
```

`set()` 中类名之后的参数会原样传给构造函数。构造函数含有内置类型、联合类型或没有默认值的参数时，建议像上例一样显式提供参数。

## 自动解析构造函数依赖

没有显式提供构造参数时，`Di` 会检查构造函数参数：

- 参数具有类类型时，按照完整类名从容器继续读取。
- 参数没有类类型时，按照参数名从容器读取。
- 容器没有对应参数时，尝试使用构造函数默认值。

```php
class UserRepository
{
}

class UserService
{
    public function __construct(
        private UserRepository $repository
    ) {
    }
}

$di->set(UserRepository::class, UserRepository::class);
$di->set(UserService::class, UserService::class);

$service = $di->get(UserService::class);
```

自动解析适合简单、明确的构造函数。复杂依赖、联合类型或同一接口存在多个实现时，应显式注册构造参数，避免解析结果不明确。

## 服务别名

可以给已经注册的键增加更容易阅读的别名：

```php
$di->set('userService', UserService::class);
$di->alias('user.service', 'userService');

$service = $di->get('user.service');
```

别名自身不能与已经存在的真实键重名，否则 `alias()` 会抛出 `InvalidArgumentException`。

删除别名和实际服务使用不同方法：

```php
$di->deleteAlias('user.service');
$di->delete('userService');
```

`clear()` 只清空实际注册项，不会清空别名。调用 `clear()` 后如果还保留别名，读取别名最终可能得到 `null`，因此需要完整重置时还应删除对应别名。

## 未注册服务的处理

可以通过 `setOnKeyMiss()` 设置键未命中时的统一处理：

```php
$di->setOnKeyMiss(function (string $key): mixed {
    error_log("service not found: {$key}");
    return null;
});

$service = $di->get('not-exists');
```

回调的返回值会直接成为 `get()` 的结果。不要在未命中回调中无条件再次读取同一个键，否则会形成递归调用。

## callable 不会自动执行

闭包和其他 callable 会被当作普通值保存，`get()` 不会把它当成服务工厂执行：

```php
$di->set('factory', fn () => new UserService());

$factory = $di->get('factory');
$service = $factory();
```

如果需要每次读取都创建新对象，应由业务代码显式调用工厂，或自行封装服务提供者。

## 协程上下文 ContextManager

`ContextManager` 按协程 ID 保存数据，适合记录只属于当前请求的信息：

```php
use EasySwoole\Component\Context\ContextManager;

Co\run(function (): void {
    $context = ContextManager::getInstance();

    $context->set('requestId', 'req-1001');
    $context->set('userId', 1001);

    echo $context->get('requestId');
    var_dump($context->getContextArray());

    $context->unset('userId');
});
```

同一协程内的不同方法不需要层层传递参数，只要取得同一个 `ContextManager`，就能读取当前协程的数据。

## 上下文的自动清理

第一次访问当前协程上下文时，`ContextManager` 会使用 `Coroutine::defer()` 注册清理回调。协程结束后，该协程的整个上下文会被删除：

```php
Co\run(function (): void {
    go(function (): void {
        $context = ContextManager::getInstance();
        $context->set('requestId', 'req-1001');

        // 当前子协程结束时，req-1001 对应的上下文自动清理。
    });
});
```

因此，`ContextManager` 应在 Swoole 协程环境中使用。不要把上下文对象保存到静态变量后跨协程复用。

## 手动删除上下文

删除一个键：

```php
$removed = ContextManager::getInstance()->unset('requestId');
```

删除当前协程的全部上下文：

```php
ContextManager::getInstance()->destroy();
```

清空管理器中保存的所有协程上下文：

```php
ContextManager::getInstance()->destroyAll();
```

`destroyAll()` 会影响当前进程内其他仍在运行的协程，普通请求代码不应调用；它更适合明确的进程清理或测试场景。

## 指定协程 ID

`set()`、`get()`、`unset()`、`destroy()` 和 `getContextArray()` 都可以传入指定协程 ID：

```php
$context->set('requestId', 'req-1001', $cid);
$requestId = $context->get('requestId', $cid);
```

常规业务应省略 `$cid`，让组件使用当前协程。手动操作其他协程的上下文容易造成数据串用，并且目标协程可能已经结束。

新创建的子协程拥有新的协程 ID，不会自动继承父协程上下文。需要把 request ID 等信息传入子协程时，应显式通过闭包 `use` 传递并在子协程中重新设置。

## 配合使用示例

IOC 容器保存进程级服务，上下文保存请求级数据：

```php
use EasySwoole\Component\Context\ContextManager;
use EasySwoole\Component\Di;

$logger = Di::getInstance()->get('logger');
$requestId = ContextManager::getInstance()->get('requestId');

$logger->info('request completed', [
    'requestId' => $requestId,
]);
```

不要反过来把当前请求的 `requestId` 写到 `Di`。同一 Worker 会连续或并发处理多个请求，进程级容器中的请求数据会相互覆盖。

## 源码依据

- [Di](https://github.com/easy-swoole/component/blob/master/src/Di.php)
- [ContextManager](https://github.com/easy-swoole/component/blob/master/src/Context/ContextManager.php)
