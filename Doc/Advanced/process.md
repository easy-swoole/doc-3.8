# 自定义进程

自定义进程适合运行需要与 HTTP Worker 同时启动、长期驻留的消费者或后台循环，例如消息队列消费、设备连接维护和指标采集。普通的一次性耗时工作优先使用[异步任务](/Advanced/task.md)，周期任务优先使用[Crontab](/Advanced/crontab.md)。

## 创建进程类

新建 `App/Process/OrderConsumer.php`：

```php
<?php

namespace App\Process;

use EasySwoole\Component\Process\AbstractProcess;
use Swoole\Coroutine;

class OrderConsumer extends AbstractProcess
{
    private bool $running = true;

    protected function run($arg): void
    {
        while ($this->running) {
            try {
                // 从消息队列获取一条消息并处理。
                // $message = QueueClient::pop(timeout: 1);
                // if ($message !== null) {
                //     OrderService::consume($message);
                // }
            } catch (\Throwable $throwable) {
                $this->onException($throwable);
            }

            // 没有消息时必须让出协程，避免空循环占满 CPU。
            Coroutine::sleep(0.1);
        }
    }

    protected function onSigTerm(): void
    {
        // 收到停止信号后，让 run() 的循环自然退出。
        $this->running = false;
    }

    protected function onShutDown(): void
    {
        // 关闭连接、刷新缓冲区等。
    }

    protected function onException(\Throwable $throwable, ...$args): void
    {
        // 生产环境应接入项目日志和告警。
        error_log($throwable->__toString());
    }
}
```

`run()` 是进程入口。默认开启协程支持，可以在其中使用 Swoole 协程客户端。常驻循环必须设置等待时间，并为网络和队列操作设置超时。

## 注册到主服务

编辑项目根目录的 `EasySwooleEvent.php`，在 `mainServerCreate()` 中注册：

```php
<?php

namespace EasySwoole\EasySwoole;

use App\Process\OrderConsumer;
use EasySwoole\Component\Process\Manager;
use EasySwoole\EasySwoole\AbstractInterface\Event;
use EasySwoole\EasySwoole\Swoole\EventRegister;

class EasySwooleEvent implements Event
{
    public static function initialize()
    {
    }

    public static function mainServerCreate(EventRegister $register)
    {
        Manager::getInstance()->addProcess(
            new OrderConsumer('OrderConsumer')
        );
    }
}
```

框架会在完成事件注册后把 `Manager` 中的进程附加到主服务。不要在控制器请求中调用 `addProcess()`；Swoole 服务启动后不能再动态添加这类进程。

## 使用进程配置

需要设置分组、启动参数或管道类型时，可以显式创建配置：

```php
use App\Process\OrderConsumer;
use EasySwoole\Component\Process\Config;
use EasySwoole\Component\Process\Manager;

$config = new Config();
$config->setProcessName('OrderConsumer-1');
$config->setProcessGroup('OrderConsumer');
$config->setArg(['queue' => 'orders']);
$config->setEnableCoroutine(true);
$config->setPipeType(Config::PIPE_TYPE_NONE);

Manager::getInstance()->addProcess(new OrderConsumer($config));
```

示例进程不使用进程管道，因此选择 `PIPE_TYPE_NONE`。如果需要父子进程通信，可选择 `PIPE_TYPE_SOCK_DGRAM` 或 `PIPE_TYPE_SOCK_STREAM`，并重写 `onPipeReadable()`；回调中必须读取管道数据，否则事件会持续触发。

## 自定义定时器进程

`AbstractProcess` 提供了三个定时器方法：

| 方法 | 说明 |
| --- | --- |
| `addTick($ms, $callback)` | 每隔指定毫秒重复执行，返回定时器 ID |
| `delay($ms, $callback)` | 延迟指定毫秒后执行一次，返回定时器 ID |
| `clearTick($timerIdOrName)` | 根据定时器 ID 或名称清除定时器 |

例如，每 10 秒采集一次业务指标，并在进程启动 3 秒后执行一次初始化检查。新建 `App/Process/MetricsTimerProcess.php`：

```php
<?php

namespace App\Process;

use EasySwoole\Component\Process\AbstractProcess;

class MetricsTimerProcess extends AbstractProcess
{
    private ?int $collectTimerId = null;
    private bool $collecting = false;

    protected function run($arg): void
    {
        // 周期定时器：每 10 秒执行一次。
        $this->collectTimerId = $this->addTick(10_000, function (): void {
            // 上一次采集尚未完成时跳过，避免任务不断重叠。
            if ($this->collecting) {
                return;
            }

            $this->collecting = true;

            try {
                $this->collectMetrics();
            } catch (\Throwable $throwable) {
                $this->onException($throwable, 'collect_metrics');
            } finally {
                $this->collecting = false;
            }
        });

        // 单次定时器：进程启动 3 秒后执行一次。
        $this->delay(3_000, function (): void {
            try {
                $this->checkDependencies();
            } catch (\Throwable $throwable) {
                $this->onException($throwable, 'check_dependencies');
            }
        });
    }

    private function collectMetrics(): void
    {
        // 查询并上报指标。
    }

    private function checkDependencies(): void
    {
        // 检查数据库、Redis 或其他依赖。
    }

    protected function onSigTerm(): void
    {
        if ($this->collectTimerId !== null) {
            $this->clearTick($this->collectTimerId);
            $this->collectTimerId = null;
        }
    }

    protected function onException(\Throwable $throwable, ...$args): void
    {
        error_log($throwable->__toString());
    }
}
```

然后在 `EasySwooleEvent.php` 的 `mainServerCreate()` 中注册该进程：

```php
use App\Process\MetricsTimerProcess;
use EasySwoole\Component\Process\Config;
use EasySwoole\Component\Process\Manager;

public static function mainServerCreate(EventRegister $register)
{
    $config = new Config();
    $config->setProcessName('MetricsTimerProcess');
    $config->setProcessGroup('TimerProcess');
    $config->setEnableCoroutine(true);
    $config->setPipeType(Config::PIPE_TYPE_NONE);

    Manager::getInstance()->addProcess(
        new MetricsTimerProcess($config)
    );
}
```

`addTick()` 和 `delay()` 的时间单位都是毫秒。周期定时器从进程启动后开始计时，并不对应具体的自然时间；需要“每天 02:00”或“每周一执行”这类日历调度时，应使用 [Crontab](/Advanced/crontab.md)。

### 使用有名称的定时器

需要按名称管理定时器时，可以直接使用 `Timer`：

```php
use EasySwoole\Component\Timer;

protected function run($arg): void
{
    Timer::getInstance()->loop(
        5_000,
        function (): void {
            $this->collectMetrics();
        },
        'collect-metrics'
    );
}

protected function onSigTerm(): void
{
    $this->clearTick('collect-metrics');
}
```

定时器名称在当前进程的 `Timer` 实例中管理，不会跨进程共享。两个不同的自定义进程可以使用相同名称，彼此不会覆盖。

### 定时器使用注意事项

- 定时器回调中的异常应主动捕获并交给 `onException()`，避免异常中断后续逻辑。
- 回调可能执行协程 I/O。执行时间可能超过定时间隔时，应增加运行状态或分布式锁，防止同一任务重叠。
- 不要在每次回调中继续注册新的周期定时器，否则定时器数量会持续增长。
- 数据库和 Redis 连接应在自定义进程中初始化，不要复用父进程创建的连接。
- 进程收到 `SIGTERM` 时应停止业务定时器，并让正在运行的回调尽快结束。
- 多台服务器都会启动自己的定时器进程。只允许全局执行一次的任务需要分布式锁，或者改用集中式调度。

## 查看和停止进程

服务启动后执行：

```bash
php easyswoole process show
php easyswoole process kill --pid=进程PID
php easyswoole process kill --group=OrderConsumer
```

默认使用 `SIGTERM`，组件会依次触发 `onSigTerm()` 和 `onShutDown()`。只有进程无法正常退出时才考虑 `--force`；强制终止不会给业务清理资源的机会。

## 生命周期和注意事项

```text
主服务创建
  → mainServerCreate() 注册进程
  → 框架把进程附加到 Swoole Server
  → 子进程启动并执行 run()
  → 收到 SIGTERM 时执行 onSigTerm()
  → 执行 onShutDown() 并退出
```

- 自定义进程拥有独立内存，不能直接读取 HTTP Worker 后来修改的普通 PHP 变量。
- 数据库、Redis 等连接应在子进程启动后创建，不要把父进程中创建的连接作为 `$arg` 传入。
- 业务消费需要设计确认、重试和幂等，进程存活不代表每条消息都处理成功。
- 进程异常不能只输出到终端，生产环境应写入日志并配置监控告警。
- 修改进程数量、名称或注册逻辑后需要重启服务。

## 源码依据

- [AbstractProcess](https://github.com/easy-swoole/component/blob/master/src/Process/AbstractProcess.php)
- [Process Manager](https://github.com/easy-swoole/component/blob/master/src/Process/Manager.php)
- [Timer](https://github.com/easy-swoole/component/blob/master/src/Timer.php)
