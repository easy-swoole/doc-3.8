# Crontab

Crontab 用于在 EasySwoole 服务内部按照 Cron 表达式周期执行任务，例如清理过期数据、生成日报或同步业务状态。框架会在主服务启动时创建调度进程和任务 Worker，不需要另外配置 Linux `crontab`。

## 定义定时任务

新建 `App/Crontab/ClearExpiredToken.php`：

```php
<?php

namespace App\Crontab;

use EasySwoole\Crontab\JobInterface;

class ClearExpiredToken implements JobInterface
{
    public function jobName(): string
    {
        return 'ClearExpiredToken';
    }

    public function crontabRule(): string
    {
        // 每 5 分钟执行一次。
        return '*/5 * * * *';
    }

    public function run(): mixed
    {
        // return TokenModel::query()
        //     ->where('expired_at', time(), '<')
        //     ->delete();

        return 0;
    }

    public function onException(\Throwable $throwable): void
    {
        // 记录异常或发送告警。
        throw $throwable;
    }
}
```

最新版 `JobInterface::run()` 的返回类型是 `mixed`，实现类应保持相同签名：

```php
public function run(): mixed
{
    // 可以返回受影响行数、业务结果、布尔值或 null。
    return null;
}
```

返回值类型由具体任务决定；如果任务不需要返回结果，可以直接返回 `null`。任务执行失败时应抛出异常，让组件进入 `onException()`，不要只返回 `false` 后静默结束。

Cron 表达式包含五段：

```text
分钟 小时 日期 月份 星期
```

例如 `0 2 * * *` 表示每天 02:00，`*/10 * * * *` 表示每 10 分钟。调度使用服务器时区，建议在 `EasySwooleEvent::initialize()` 中明确调用 `date_default_timezone_set()`。

## 注册任务

定时任务必须在服务完成创建前注册。编辑项目根目录的 `EasySwooleEvent.php`：

```php
<?php

namespace EasySwoole\EasySwoole;

use App\Crontab\ClearExpiredToken;
use EasySwoole\EasySwoole\AbstractInterface\Event;
use EasySwoole\EasySwoole\Crontab\Crontab;
use EasySwoole\EasySwoole\Swoole\EventRegister;

class EasySwooleEvent implements Event
{
    public static function initialize()
    {
        date_default_timezone_set('Asia/Shanghai');
    }

    public static function mainServerCreate(EventRegister $register)
    {
        Crontab::getInstance()->register(new ClearExpiredToken());
    }
}
```

`jobName()` 在同一服务中必须唯一，重复注册会抛出异常。新增、删除 Job 或修改注册代码后需要完整重启服务。只修改 Job 在 `run()` 中延迟加载的独立业务类时，可以使用后文的 `crontab reload` 重建调度和执行进程。

## 普通任务与特权任务

普通任务实现 `JobInterface`，所有普通任务由同一个 `CrontabWorker` 进程接收并执行。特权任务实现 `PrivilegeJobInterface`；这个接口继承 `JobInterface`，没有增加新的方法。框架会为**每个特权任务**额外创建一个以任务名命名的独立 Worker，并将该任务的定时触发和 `runJobNow` 请求发往这个 Worker。

| 项目 | 普通任务 | 特权任务 |
| --- | --- | --- |
| 实现接口 | `JobInterface` | `PrivilegeJobInterface` |
| 执行进程 | 共用 `CrontabWorker` | 每个任务有独立的 `CrontabWorker.任务名` |
| 通信 Socket | 共用普通任务 Socket | 每个任务有专用 Socket |
| 调度规则与管理命令 | 使用相同的 Cron 规则、`show`、`stop`、`resume` 等命令 | 相同 |
| 进程资源 | 任务之间共享一个 Worker 的进程资源 | 每个任务额外占用一个进程及其资源 |

这里的“特权”表示**独立执行进程**，不是 Linux root 权限，也不会改变进程用户、提高调度优先级或自动保证任务只运行一次。两类任务都由同一个 Scheduler 调度，执行 `crontab reload` 时都会被重建。

例如，报表任务使用独立进程可以避免它与普通清理任务共用 Worker 的内存和进程级状态。新建 `App/Crontab/GenerateDailyReport.php`：

```php
<?php

namespace App\Crontab;

use EasySwoole\Crontab\PrivilegeJobInterface;

class GenerateDailyReport implements PrivilegeJobInterface
{
    public function jobName(): string
    {
        return 'GenerateDailyReport';
    }

    public function crontabRule(): string
    {
        return '0 2 * * *';
    }

    public function run(): mixed
    {
        // 将业务类留到执行进程中首次加载，便于发布后重载 Crontab 进程。
        return (new \App\Service\DailyReportService())->generate();
    }

    public function onException(\Throwable $throwable): void
    {
        throw $throwable;
    }
}
```

`DailyReportService` 是示例业务类，需要在项目中自行实现。然后在前面的 `EasySwooleEvent::mainServerCreate()` 中同时注册两个任务：

```php
use App\Crontab\GenerateDailyReport;

Crontab::getInstance()->register(new ClearExpiredToken());
Crontab::getInstance()->register(new GenerateDailyReport());
```

服务重启后，进程结构类似：

```text
EasySwoole.<mode>.CrontabScheduler                  调度全部任务
EasySwoole.<mode>.CrontabWorker                     执行普通任务
EasySwoole.<mode>.CrontabWorker.GenerateDailyReport  执行该特权任务
```

普通任务数量较多但资源消耗较轻时，先使用普通任务。只有某个任务需要独立的进程资源或与其他任务隔离时，再使用特权任务。专用 Worker 仍可能因任务自身执行过久、重复触发或多实例部署而产生并发与重复执行问题；需要业务锁、超时或幂等处理时仍须自行实现。

## 管理定时任务

服务启动后可以在项目根目录执行：

```bash
php easyswoole crontab show
php easyswoole crontab runJobNow --taskName=ClearExpiredToken
php easyswoole crontab stop --taskName=ClearExpiredToken
php easyswoole crontab resume --taskName=ClearExpiredToken
php easyswoole crontab setCrontabRule --taskName=ClearExpiredToken --taskRule='*/10 * * * *'
php easyswoole crontab reload
```

`show` 支持 `--watch=2` 持续刷新。`stop`、`resume` 和 `runJobNow` 省略 `--taskName` 时，会在交互式终端中打开多选界面；自动化脚本必须显式指定任务名。

非默认运行模式需要追加 `--mode=produce`。`stop`、`resume` 和 `setCrontabRule` 修改的是当前运行实例中的状态，服务重启或执行 `crontab reload` 后仍以启动时注册的 Job 配置为准。

`crontab reload` 会同时重建 Scheduler、普通 Worker 和特权任务 Worker。Job 类在 `mainServerCreate()` 注册时已经由 Master 加载，因此推荐让 `run()` 只作为稳定入口，把实际业务放在子进程中首次加载的 Service 中：

```php
public function run(): mixed
{
    return (new \App\Service\CleanupExpiredTokenService())->run();
}
```

这样部署新的 Service 代码后，可以执行：

```bash
php easyswoole crontab reload --mode=produce
```

如果修改的是 Job 类自身、新增或删除 Job、调整 `jobName()`、`crontabRule()` 或注册逻辑，仍然需要完整重启。完整参数、进程范围、状态重置和强制重载风险参见[Crontab 管理命令](/Advanced/ManagementCommand/crontab.md)。

## 避免重复和堆积

普通 Crontab 任务共用 Worker。一次任务的执行时间超过调度间隔时，可能出现任务堆积或并发执行。建议：

- 使用 Redis 锁或数据库唯一记录保证同一业务周期只执行一次。
- 为外部请求和数据库查询设置超时。
- 大批量工作拆成小任务，再投递到异步任务系统。
- 在多实例部署中确认任务是否会在每个实例各执行一次；只允许单实例执行的任务必须增加分布式锁。
- `onException()` 中记录任务名、计划时间和异常堆栈，避免任务静默失败。

## 源码依据

- [EasySwoole Crontab 组件](https://github.com/easy-swoole/crontab)
- [框架 Crontab 单例](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Crontab/Crontab.php)
