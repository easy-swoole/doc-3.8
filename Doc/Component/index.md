# 基础组件

`easyswoole/component` 是 EasySwoole 的通用基础组件包。本章主要介绍单例、容器、依赖注入、事件、协程上下文、协程任务调度和跨进程共享等常用能力。

EasySwoole 主框架已经默认依赖该组件，因此正常安装框架后无需再次执行 Composer 安装命令，可以直接使用。组件使用 PSR-4 自动加载，命名空间前缀为：

```php
EasySwoole\Component\
```

这些类不依赖 HTTP 控制器，可以在框架事件、控制器和其他业务类中使用。

## 组件能力总览

| 分类 | 主要类 | 用途 |
| --- | --- | --- |
| 单例 | `Singleton` | 在当前进程中保存一个类实例 |
| 协程单例 | `CoroutineSingleTon` | 每个协程保存各自的实例 |
| 容器 | `Container`、`MultiContainer` | 按名称保存一个或多个值 |
| 依赖注入 | `Di` | 保存服务、别名并按需创建对象 |
| 事件 | `Event`、`MultiEvent` | 注册并调用一个或多个事件处理器 |
| 协程上下文 | `ContextManager` | 保存当前协程的请求级数据 |
| 协程同步 | `ChannelLock`、`WaitGroup` | 协程互斥和等待并发任务 |
| 并发调用 | `Csp` | 并发执行多个命名任务并收集结果 |
| 任务调度 | `Runner`、`Task`、`ParallelJob` | 限制并发数并持续消费任务 |
| 共享数据 | `AtomicManager`、`TableManager`、`TableShm` | 在相关进程之间共享计数或结构化数据 |
| 就绪协调 | `ReadyScheduler` | 等待一个或多个服务进入就绪状态 |

## 先理解进程与协程

使用基础组件前，需要先分清进程内状态、协程内状态和跨进程共享状态。

```text
Swoole Server
├── Worker 进程 1
│   ├── 协程 A
│   └── 协程 B
└── Worker 进程 2
    ├── 协程 C
    └── 协程 D
```

- `Singleton`、`Container`、`Di` 和普通 PHP 数组只属于当前进程。不同 Worker 中各有一份，修改不会自动同步。
- `CoroutineSingleTon` 和 `ContextManager` 按协程隔离。同一个 Worker 中的两个协程也不会共享同一份上下文。
- `Swoole\Atomic` 和 `Swoole\Table` 可以在由同一父进程派生的进程之间共享，但不能跨服务器共享。
- 多台服务器之间共享状态，应使用 Redis、数据库或其他外部存储。

不要把数据库连接、Redis 客户端或 Socket 对象放入共享内存。这些资源与创建它们的进程或协程有关，应在实际使用它们的进程中建立。

## 进程内单例

业务类使用 `Singleton` trait 后，可以通过 `getInstance()` 取得当前进程内的同一个实例：

```php
<?php

namespace App\Service;

use EasySwoole\Component\Singleton;

final class ConfigCenter
{
    use Singleton;

    public function __construct(
        private array $config = []
    ) {
    }

    public function get(string $key, mixed $default = null): mixed
    {
        return $this->config[$key] ?? $default;
    }
}
```

第一次调用时传入构造参数：

```php
$config = ConfigCenter::getInstance([
    'appName' => 'demo',
    'debug' => true,
]);

echo $config->get('appName');
```

后续调用 `ConfigCenter::getInstance()` 会返回同一个对象，不会重新执行构造函数。这里的“同一个”只限当前 PHP 进程；四个 Worker 会各自创建一个实例。

## 协程内单例

需要为每个请求协程保存独立对象时，可以使用 `CoroutineSingleTon`：

```php
use EasySwoole\Component\CoroutineSingleTon;

final class RequestScope
{
    use CoroutineSingleTon;

    public array $data = [];
}

Co\run(function (): void {
    go(function (): void {
        RequestScope::getInstance()->data['requestId'] = 'request-1';
        echo RequestScope::getInstance()->data['requestId'];
    });

    go(function (): void {
        RequestScope::getInstance()->data['requestId'] = 'request-2';
        echo RequestScope::getInstance()->data['requestId'];
    });
});
```

两个协程获得的是不同实例。协程结束时组件会自动清理当前协程的实例。

在非协程环境中，协程 ID 通常为 `-1`，实例不会随协程自动销毁；此时应根据实际生命周期调用 `destroy()`。

## Container 与 MultiContainer

`Container` 适合一个名称保存一个值：

```php
use EasySwoole\Component\Container;

$container = new Container(['config', 'logger']);
$container->set('config', ['debug' => true]);

$config = $container->get('config');
$all = $container->all();

$container->delete('config');
$container->clear();
```

构造函数传入的数组用于限制允许的键名。设置未允许的键时，`set()` 返回 `false`：

```php
$ok = $container->set('database', $database);

if ($ok === false) {
    throw new RuntimeException('database is not an allowed key');
}
```

如果一个名称需要保存多个值，使用 `MultiContainer`：

```php
use EasySwoole\Component\MultiContainer;

$container = new MultiContainer();
$container->add('middleware', 'auth');
$container->add('middleware', 'trace');

var_dump($container->get('middleware'));
// ['auth', 'trace']

$container->set('middleware', 'cors');
// 覆盖为 ['cors']
```

## 依赖注入容器

`Di` 是进程内的轻量级依赖注入容器：

```php
use EasySwoole\Component\Di;

$di = Di::getInstance();

$di->set('config', [
    'debug' => true,
]);

$di->set('userService', UserService::class);
$di->alias('user.service', 'userService');

$service = $di->get('user.service');
```

保存类名时，`Di` 会在第一次 `get()` 时创建对象并缓存。保存已经创建好的对象或 callable 时，`get()` 会直接返回原值，不会自动执行 callable。

构造函数包含内置类型、联合类型或无法自动判断的参数时，应显式传入构造参数，不要依赖自动解析：

```php
$di->set(
    'mailer',
    Mailer::class,
    'smtp.example.com',
    25
);
```

## 单事件与多事件

`Event` 的一个事件名称只能保存一个处理器：

```php
use EasySwoole\Component\Event;

$events = new Event();
$events->set('user.created', function (int $userId): string {
    return "created:{$userId}";
});

$result = $events->hook('user.created', 1001);
```

需要让多个监听器依次响应同一个事件时，使用 `MultiEvent`：

```php
use EasySwoole\Component\MultiEvent;

$events = new MultiEvent();
$events->add('order.paid', fn (int $id) => "log:{$id}");
$events->add('order.paid', fn (int $id) => "notify:{$id}");

$results = $events->hook('order.paid', 1001);
```

`add()` 追加监听器，`set()` 覆盖该事件已有的监听器。监听器抛出的异常会继续向上传递，生产环境应在事件触发入口统一记录异常。

## 协程组件必须在协程环境使用

Channel、协程锁、WaitGroup、Csp 和协程任务调度依赖 Swoole 协程。独立脚本可以使用 `Co\run()` 创建协程环境：

```php
<?php

require __DIR__ . '/vendor/autoload.php';

Co\run(function (): void {
    // 在这里使用 Channel、WaitGroup、Csp 等协程组件。
});
```

EasySwoole 的请求回调通常已经运行在 Server Worker 环境中，但仍要避免在协程中调用未完成协程化的阻塞 I/O，否则会阻塞整个 Worker。

## 与其他章节的关系

各项能力已经拆分为独立二级菜单。阅读时可以先通过本页理解进程与协程边界，再进入对应功能章节查看 API、示例和注意事项。

## 常见误区

- 不要把 `Singleton` 当成跨 Worker 的全局单例。
- 不要使用普通静态数组保存所有 Worker 的在线连接或登录状态。
- 不要在协程结束后继续持有它的上下文对象。
- 不要无超时地等待 Channel、锁或外部 I/O。
- 不要把 `Swoole\Table` 当成跨机器数据库；它是单机共享内存结构。
- WaitGroup、Csp 和 Runner 的等待超时通常使用秒，使用前仍应查看对应方法说明。

## 源码依据

- [Component 仓库](https://github.com/easy-swoole/component)
- [Singleton](https://github.com/easy-swoole/component/blob/master/src/Singleton.php)
- [CoroutineSingleTon](https://github.com/easy-swoole/component/blob/master/src/CoroutineSingleTon.php)
- [Container](https://github.com/easy-swoole/component/blob/master/src/Container.php)
- [Di](https://github.com/easy-swoole/component/blob/master/src/Di.php)
- [Event](https://github.com/easy-swoole/component/blob/master/src/Event.php)
