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

    public function run(): int
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

`jobName()` 在同一服务中必须唯一，重复注册会抛出异常。注册代码修改后需要重启服务。

## 管理定时任务

服务启动后可以在项目根目录执行：

```bash
php easyswoole crontab show
php easyswoole crontab runJobNow --taskName=ClearExpiredToken
php easyswoole crontab stop --taskName=ClearExpiredToken
php easyswoole crontab resume --taskName=ClearExpiredToken
php easyswoole crontab setCrontabRule --taskName=ClearExpiredToken --taskRule='*/10 * * * *'
```

非默认运行模式需要追加 `--mode=produce`。`stop`、`resume` 和 `setCrontabRule` 修改的是当前运行实例中的状态，服务重启后仍以代码中的 `crontabRule()` 为准。

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
