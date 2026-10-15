# 容器与事件

Component 提供两类容器和两类事件对象：

| 类 | 一个键保存的内容 | 典型用途 |
| --- | --- | --- |
| `Container` | 一个值 | 配置项、服务对象和命名资源 |
| `MultiContainer` | 多个值 | 中间件列表、处理器列表 |
| `Event` | 一个 callable | 一个事件只有一个处理器 |
| `MultiEvent` | 多个 callable | 一个事件依次通知多个监听器 |

`Event` 继承自 `Container`，`MultiEvent` 继承自 `MultiContainer`。事件类在容器能力之上限制保存内容必须可以调用，并增加了 `hook()` 触发方法。

这些对象都是当前 PHP 进程中的普通内存对象，不会自动跨 Worker 共享。

## Container 键值容器

`Container` 的一个键只保存一个值。重复设置同一个键时，新值会覆盖旧值：

```php
use EasySwoole\Component\Container;

$container = new Container();
$container->set('appName', 'demo');
$container->set('debug', true);

echo $container->get('appName');
var_dump($container->all());
```

常用方法：

| 方法 | 说明 |
| --- | --- |
| `set($key, $item)` | 保存或覆盖一个值，成功返回容器自身 |
| `get($key)` | 读取值；键不存在时返回 `null` |
| `delete($key)` | 删除指定键并返回容器自身 |
| `all()` | 返回当前全部键值 |
| `clear()` | 清空整个容器 |

可以在构造函数中限制允许使用的键：

```php
$container = new Container(['config', 'logger']);

$container->set('config', ['debug' => true]);
$result = $container->set('database', $database);

if ($result === false) {
    throw new RuntimeException('database is not an allowed key');
}
```

传入允许键列表后，设置未声明的键会返回 `false`，不会写入数据。不传或传入 `null` 表示不限制键名。

需要注意，`get()` 使用 `isset()` 判断键是否存在，因此“键不存在”和“该键保存了 `null`”都会得到 `null`。业务需要区分这两种情况时，不应把 `null` 作为有效值保存。

## MultiContainer 多值容器

`MultiContainer` 允许一个键保存多个值：

```php
use EasySwoole\Component\MultiContainer;

$container = new MultiContainer();
$container->add('middleware', 'auth');
$container->add('middleware', 'trace');

var_dump($container->get('middleware'));
// ['auth', 'trace']
```

`add()` 与 `set()` 的区别：

```php
$container->add('middleware', 'cors');
// ['auth', 'trace', 'cors']

$container->set('middleware', 'rate-limit');
// ['rate-limit']
```

- `add()` 在该键的数组末尾追加一个值。
- `set()` 清除该键已有的值，再保存一个只包含新值的数组。
- `get()` 始终返回数组或 `null`，即使这个键只有一个值。

`MultiContainer` 同样支持构造函数允许键列表，以及 `delete()`、`all()` 和 `clear()`。

## Event 单监听器事件

`Event` 的一个事件名称只能保存一个 callable：

```php
use EasySwoole\Component\Event;

$events = new Event();

$events->set(
    'user.created',
    function (int $userId): string {
        return "created:{$userId}";
    }
);

$result = $events->hook('user.created', 1001);
echo $result;
```

`hook()` 后面的参数会原样传给监听器。重复调用 `set()` 会覆盖原监听器：

```php
$events->set('user.created', $firstListener);
$events->set('user.created', $secondListener);

// 只会执行 $secondListener。
$events->hook('user.created', 1001);
```

传入不可调用的值时，`set()` 返回 `false`；触发不存在的事件时，`hook()` 返回 `null`。

## MultiEvent 多监听器事件

`MultiEvent` 允许同一事件注册多个监听器，并按照添加顺序逐个执行：

```php
use EasySwoole\Component\MultiEvent;

$events = new MultiEvent();

$events->add(
    'order.paid',
    fn (int $orderId): string => "log:{$orderId}"
);

$events->add(
    'order.paid',
    fn (int $orderId): string => "notify:{$orderId}"
);

$results = $events->hook('order.paid', 1001);

var_dump($results);
// ['log:1001', 'notify:1001']
```

`hook()` 返回由所有监听器返回值组成的数组。事件不存在时返回空数组。

`add()` 与 `set()` 的行为不同：

```php
$events->add('saved', $listenerA);
$events->add('saved', $listenerB);
// saved 包含 A 和 B

$events->set('saved', $listenerC);
// saved 现在只包含 C
```

监听器是同步、按顺序执行的。某个监听器抛出异常时，异常会继续向上传递，后面的监听器不会继续执行；组件不会自动记录异常，也不会自动重试。

需要保证其他监听器仍然执行时，应在每个监听器内部捕获并记录自己的异常：

```php
$events->add('order.paid', function (int $orderId): void {
    try {
        NotificationService::send($orderId);
    } catch (Throwable $throwable) {
        error_log((string) $throwable);
    }
});
```

## 如何选择

- 一个名称只保存一个普通值：使用 `Container`。
- 一个名称保存有顺序的多个普通值：使用 `MultiContainer`。
- 一个事件只允许一个处理器：使用 `Event`。
- 一个事件需要通知日志、缓存、消息等多个监听器：使用 `MultiEvent`。

容器只负责保存和读取数据，不负责自动创建对象。需要类名解析、别名和构造函数依赖注入时，请使用 [IOC 与上下文](/Component/ioc-context.md)中的 `Di`。

## 源码依据

- [Container](https://github.com/easy-swoole/component/blob/master/src/Container.php)
- [MultiContainer](https://github.com/easy-swoole/component/blob/master/src/MultiContainer.php)
- [Event](https://github.com/easy-swoole/component/blob/master/src/Event.php)
- [MultiEvent](https://github.com/easy-swoole/component/blob/master/src/MultiEvent.php)
