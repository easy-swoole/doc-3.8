# 定时器

EasySwoole Component 的 `Timer` 对 Swoole 定时器进行了简单封装，适合执行延迟任务和固定间隔的轻量任务。定时器属于创建它的进程，不会自动在不同 Worker 之间共享。

## 两种定时器

| 方法 | 执行方式 | 常见用途 |
| --- | --- | --- |
| `after($ms, $callback)` | 延迟指定毫秒后执行一次 | 延迟检查、短时间后的资源清理 |
| `loop($ms, $callback)` | 每隔指定毫秒重复执行 | 心跳、轻量指标采集、定期刷新内存缓存 |

两个方法的时间单位都是毫秒。`1_000` 表示 1 秒，`60_000` 表示 1 分钟。

## 单次延迟定时器

```php
use EasySwoole\Component\Timer;

$timerId = Timer::getInstance()->after(3_000, function (): void {
    // 3 秒后执行一次。
    echo "delay task executed\n";
});
```

`after()` 返回定时器 ID。回调执行完成后，该定时器自动失效，不需要手动清理。

定时器只适合进程仍在运行时的短期延迟工作。它不会持久化，服务重启后也不会恢复；需要可靠执行的业务任务应写入任务表或消息队列。

## 循环定时器

```php
use EasySwoole\Component\Timer;

$timerId = Timer::getInstance()->loop(5_000, function (): void {
    try {
        // 每 5 秒执行一次轻量任务。
        // MetricsService::flush();
    } catch (\Throwable $throwable) {
        // 定时器回调不会自动替业务记录异常。
        error_log($throwable->__toString());
    }
});
```

`loop()` 返回定时器 ID。只要所在进程继续运行并且定时器没有被清除，回调就会按照间隔持续触发。

循环间隔表示两次触发之间的时间，并不是“上一轮完成后再等待一段时间”。如果回调包含协程 I/O，或者回调中又创建了协程，上一轮尚未完成时下一轮可能已经到达。可以使用运行标记防止同一进程内重复执行：

```php
use EasySwoole\Component\Timer;

$running = false;

Timer::getInstance()->loop(5_000, function () use (&$running): void {
    if ($running) {
        return;
    }

    $running = true;

    try {
        // 执行业务逻辑。
    } catch (\Throwable $throwable) {
        error_log($throwable->__toString());
    } finally {
        $running = false;
    }
});
```

运行标记只对当前进程有效。如果服务部署了多个实例，或者多个 Worker 都注册了相同定时器，需要使用 Redis 锁、数据库锁等方式避免跨进程重复执行。

## 使用名称管理定时器

`loop()` 的第三个参数可以设置定时器名称：

```php
use EasySwoole\Component\Timer;

Timer::getInstance()->loop(
    10_000,
    function (): void {
        // 定期上报服务状态。
    },
    'report-service-status'
);
```

之后可以使用定时器 ID或名称清除循环定时器：

```php
$timer = Timer::getInstance();

$timer->clear($timerId);
$timer->clear('report-service-status');
```

`clear()` 成功清除时返回 `true`，定时器不存在时返回 `false`。名称只保存在当前进程的 `Timer` 实例中，不会跨进程共享。

查看当前进程中的 Swoole 定时器 ID：

```php
$timerIds = Timer::getInstance()->list();
```

`clearAll()` 会清除当前进程中的所有 Swoole 定时器，可能同时影响框架或其他组件创建的定时器，业务代码通常不应调用它。

## 在 Worker 启动时注册

不要在控制器 Action 中创建循环定时器。每次请求都会再次注册，最终会产生大量重复定时器。需要随 HTTP 服务启动的定时器，可以在项目根目录的 `EasySwooleEvent.php` 中监听 `onWorkerStart`。

下面的示例只在编号为 `0` 的 Worker 中注册一次：

```php
<?php

namespace EasySwoole\EasySwoole;

use EasySwoole\Component\Timer;
use EasySwoole\EasySwoole\AbstractInterface\Event;
use EasySwoole\EasySwoole\Swoole\EventHelper;
use EasySwoole\EasySwoole\Swoole\EventRegister;
use Swoole\Server;

class EasySwooleEvent implements Event
{
    public static function initialize()
    {
    }

    public static function mainServerCreate(EventRegister $register)
    {
        EventHelper::registerWithAdd(
            $register,
            EventRegister::onWorkerStart,
            function (Server $server, int $workerId): void {
                if ($workerId !== 0) {
                    return;
                }

                Timer::getInstance()->loop(
                    10_000,
                    function (): void {
                        // 仅在 Worker 0 中执行。
                    },
                    'worker-health-check'
                );
            }
        );
    }
}
```

`onWorkerStart` 会在每个 Worker 启动时触发。如果去掉 `$workerId !== 0` 的判断，每个 Worker 都会创建一份相同的定时器。例如配置了 8 个 Worker，一次间隔到达时就可能执行 8 次。

Worker 热重载时，旧 Worker 中的定时器随旧进程退出，新 Worker 会重新执行 `onWorkerStart` 并创建自己的定时器。内存中的执行次数和临时状态不会继承。

## 长时间循环任务放入自定义进程

HTTP Worker 的主要职责是处理请求。循环定时器回调执行时间较长、调用容易阻塞的第三方服务，或者需要长期稳定运行时，不应占用 HTTP Worker。建议创建专用的[自定义进程](/Advanced/process.md#自定义定时器进程)，在自定义进程的 `run()` 中注册定时器。

适合放到自定义进程的场景包括：

- 每轮需要处理大量数据。
- 回调可能执行数秒甚至更久。
- 需要维护独立的数据库、Redis 或消息队列连接。
- 需要单独查看、停止和监控后台进程。
- 定时任务不能影响 HTTP 请求的响应延迟。

如果任务按具体日期或自然时间执行，例如每天 02:00、每周一或每月最后一天，应使用 [Crontab](/Advanced/crontab.md)，不要用循环定时器自行计算时间。

## 使用注意事项

- 定时器依赖当前进程的事件循环，进程停止后定时器立即失效。
- 定时器没有持久化、失败重试和补偿机制，重要任务需要业务层记录执行状态。
- 循环回调应主动捕获异常并记录日志，避免故障没有任何线索。
- 回调耗时应明显短于循环间隔；否则应防止任务重叠或改用自定义进程。
- 不要在请求、循环回调或其他高频路径中重复注册循环定时器。
- 多 Worker、多进程和多服务器部署都会放大执行次数，需要明确任务应该执行一份还是多份。
- 网络请求、数据库查询和队列操作必须配置超时，不能永久阻塞事件循环。
- 修改定时器注册逻辑后，应按部署流程重载或重启对应进程。

## 源码依据

- [Timer](https://github.com/easy-swoole/component/blob/master/src/Timer.php)
- [EventRegister](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Swoole/EventRegister.php)
