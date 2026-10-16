# 管理命令：Crontab 管理

`crontab` 命令通过框架 Bridge 管理当前运行实例中已经注册的 Crontab 任务。

```text
crontab
├── show               查看任务状态
├── stop               暂停指定任务
├── stopAll            暂停全部任务
├── resume             恢复指定任务
├── resumeAll          恢复全部任务
├── runJobNow          立即执行指定任务
├── setCrontabRule     临时修改任务规则
└── reload             重载 Crontab 相关进程
```

任务类的定义和注册方式参见[Crontab](/Advanced/crontab.md)。所有命令都应传入和服务启动时相同的 `--mode`。

下面统一使用 `ClearExpiredToken` 作为演示任务。时间、执行次数和下一次运行时间会随环境变化，不需要与示例完全一致。

## 查看任务状态

```bash
php easyswoole.php crontab show --mode=produce
```

输出会汇总任务总数、运行数和停止数，并显示每个任务的：

- Task Name 和 Cron Rule。
- `running` 或 `stopped` 状态。
- 下一次计划执行时间。
- 累计执行次数和上次执行时间。
- 最近一次异常信息和异常时间。

输出示例：

```text
Crontab tasks (total: 1, running: 1, stopped: 0)

[1] ClearExpiredToken
    Rule */5 * * * *   State running   Next 2026-10-16 01:05:00
    Runs 0   Last run -
```

任务执行过后，`Runs` 会增加，`Last run` 会显示最近一次执行时间。发生异常时还会增加 `Last error` 和 `Last error time` 两行。

持续观察：

```bash
php easyswoole.php crontab show --mode=produce --watch=2
```

按 `q`、`Esc` 或 `Ctrl+C` 退出。`--watch` 只支持交互式终端。

## 暂停任务

指定任务名适合部署脚本和自动化环境：

```bash
php easyswoole.php crontab stop \
    --mode=produce \
    --taskName=ClearExpiredToken
```

省略 `--taskName` 时进入交互式多选：

```bash
php easyswoole.php crontab stop --mode=produce
```

可以用方向键、空格和 `a` 选择一个或多个任务，按 Enter 后还需要输入 `y` 确认。非交互环境必须显式提供 `--taskName`。

暂停全部任务：

```bash
php easyswoole.php crontab stopAll --mode=produce
```

`stop` 和 `stopAll` 阻止后续计划调度，不应假设它们能够中断一个已经开始执行的 `run()`。长任务仍需要自己的取消、超时和幂等机制。

输出示例：

```text
# stop --taskName=ClearExpiredToken
crontab job [ClearExpiredToken] is stop success

# stopAll
all crontab job is stop success
```

再次执行 `show` 可以看到状态变化：

```text
Crontab tasks (total: 1, running: 0, stopped: 1)

[1] ClearExpiredToken
    Rule */5 * * * *   State stopped   Next 2026-10-16 01:05:00
    Runs 0   Last run -
```

## 恢复任务

恢复一个任务：

```bash
php easyswoole.php crontab resume \
    --mode=produce \
    --taskName=ClearExpiredToken
```

交互式恢复一个或多个任务：

```bash
php easyswoole.php crontab resume --mode=produce
```

恢复全部任务：

```bash
php easyswoole.php crontab resumeAll --mode=produce
```

恢复后组件根据当前规则计算下一次执行时间，不会自动补跑暂停期间错过的每一次计划。

输出示例：

```text
# resume --taskName=ClearExpiredToken
crontab job [ClearExpiredToken] is resume success

# resumeAll
all crontab job is resume success
```

## 立即执行任务

```bash
php easyswoole.php crontab runJobNow \
    --mode=produce \
    --taskName=ClearExpiredToken
```

省略 `--taskName` 时也可以交互式多选并确认：

```bash
php easyswoole.php crontab runJobNow --mode=produce
```

`runJobNow` 是额外触发一次执行，不会改变原 Cron Rule。调用前应确认任务支持重复执行；如果同一任务的计划实例仍在运行，立即执行可能造成并发，业务层应使用分布式锁或唯一业务记录防重。

输出示例：

```text
crontab job [ClearExpiredToken] run success now
```

这里的 `success` 表示调度进程已经接受立即执行请求。任务内部是否成功仍应结合 `crontab show` 的异常字段和业务日志判断。

## 临时修改 Cron Rule

```bash
php easyswoole.php crontab setCrontabRule \
    --mode=produce \
    --taskName=ClearExpiredToken \
    --taskRule='*/10 * * * *'
```

`setCrontabRule` 的 `--taskName` 和 `--taskRule` 都是必填项，不提供交互选择。Cron 表达式包含五段：

```text
分钟 小时 日期 月份 星期
```

修改作用于当前运行实例的内存状态，不会修改任务类中的 `crontabRule()`，也不会写回 PHP 文件。服务重启后会重新使用代码中注册的规则。需要永久修改时，应修改任务类、发布代码并重启相应服务。

输出示例：

```text
crontab [ClearExpiredToken] reset rule success
```

随后执行 `show`，可以看到新规则和重新计算的下一次执行时间：

```text
Crontab tasks (total: 1, running: 1, stopped: 0)

[1] ClearExpiredToken
    Rule */10 * * * *   State running   Next 2026-10-16 01:10:00
    Runs 1   Last run 2026-10-16 01:01:12
```

## 重载 Crontab 进程

发布了 Crontab 进程在运行阶段延迟加载的业务代码，或者需要重建调度器、Worker 及其连接时，可以执行：

```bash
php easyswoole.php crontab reload --mode=produce
```

命令会根据当前运行模式自动计算 Crontab 进程组。例如服务名为 `EasySwoole`、模式为 `produce` 时，目标组为：

```text
EasySwoole.produce.Crontab
```

该组通常包含：

```text
EasySwoole.produce.Crontab
├── EasySwoole.produce.CrontabScheduler       调度进程
├── EasySwoole.produce.CrontabWorker          普通任务 Worker
└── EasySwoole.produce.CrontabWorker.任务名   特权任务独立 Worker
```

`reload` 内部复用 `process kill` 的筛选与信号逻辑，默认向组内全部进程发送 `SIGTERM`。Swoole Manager 会在旧进程退出后重新创建替代进程。

输出示例：

```text
[SIGTERM] EasySwoole.produce.CrontabScheduler   PID 20101: signal sent
[SIGTERM] EasySwoole.produce.CrontabWorker   PID 20102: signal sent
```

如果还注册了特权任务，输出中会继续列出对应的独立 Worker。PID 会随每次重载变化。

当前实例没有注册任何 Crontab Job 时，不会创建 Crontab 进程，命令输出：

```text
not any process match
```

这不表示框架重载失败，而是当前运行模式下没有匹配 `SERVER_NAME.mode.Crontab` 进程组的目标。若预期已经注册任务，应检查 `--mode`、`SERVER_NAME`、注册代码和当前进程列表。

### 重载后的状态

新的 Scheduler 会根据服务启动时已经注册的 Job 重新建立调度表，因此以下运行时数据会重置：

- `stop`、`stopAll` 设置的暂停状态。
- `setCrontabRule` 临时修改的表达式。
- `Runs`、`Last run`、`Last error` 等运行统计。
- 下一次执行时间会按照 Job 的 `crontabRule()` 重新计算。

如果某个任务在发布期间必须保持暂停，不要只依赖进程内的 `stop` 状态。应把开关持久化到配置中心、Redis 或数据库，并让任务执行前检查该开关；也可以在 reload 后重新执行 `stop`。

### 哪些代码能够更新

Job 在 `mainServerCreate()` 中通过 `new ClearExpiredToken()` 注册时，Job 类本身已经由主进程加载。`crontab reload` 只替换现有 Crontab 子进程，不会重新执行 `mainServerCreate()`，因此：

- Job 的 `run()` 中首次自动加载的 Service、Repository 等独立业务类，可以随新 Worker 加载新版代码。
- 已在 Master 中加载的 Job 类本身不能依赖此次 reload 更新。
- 新增或删除 Job、修改注册方式、修改 Job 类中的 `jobName()` 或 `crontabRule()`，应完整重启服务。

推荐让 Job 保持为稳定的调度壳，把实际业务放到独立类中：

```php
public function run(): mixed
{
    // CleanupExpiredTokenService 在 Crontab Worker 中首次使用时自动加载。
    return (new \App\Service\CleanupExpiredTokenService())->run();
}
```

详细的延迟加载原理参见[热重启：自定义进程的热重启](/Advanced/reload.md)。

### 强制重载

仅当 Crontab 进程失去响应且确认可以中断当前任务时使用：

```bash
php easyswoole.php crontab reload \
    --mode=produce \
    --force
```

也可以显式传入 `--force=true`；`--force=false` 仍使用 `SIGTERM`。强制模式会向所有 Crontab 进程发送 `SIGKILL`，不会执行正常清理，正在运行的任务可能只完成一部分。

强制模式输出中的信号名会变为：

```text
[SIGKILL] EasySwoole.produce.CrontabScheduler   PID 20101: signal sent
[SIGKILL] EasySwoole.produce.CrontabWorker   PID 20102: signal sent
```

`crontab reload` 当前没有滚动重载参数，会同时操作整个 Crontab 进程组。重载期间可能短暂没有调度器或可用 Worker，所以任务必须具备幂等性；严格依赖单次准点执行的业务还应增加持久化调度记录和补偿扫描。

## 交互操作的并发保护

进入交互选择后，任务状态可能在用户确认前发生变化。框架会在真正执行前重新读取任务列表，并比较任务名、Rule 和停止状态；如果任务已经消失或变化，本次命令会终止，要求重新选择。

这只能避免管理命令操作过期快照，不能代替业务锁。多实例部署时，每个实例通常拥有各自的 Crontab 调度器，命令只连接当前配置对应的实例。只允许全局执行一次的任务仍要使用 Redis 锁或数据库唯一约束。

## 命令速查

| 目的 | 命令 |
| --- | --- |
| 查看 | `crontab show --mode=produce` |
| 监控 | `crontab show --mode=produce --watch=2` |
| 暂停一个 | `crontab stop --mode=produce --taskName=任务名` |
| 暂停全部 | `crontab stopAll --mode=produce` |
| 恢复一个 | `crontab resume --mode=produce --taskName=任务名` |
| 恢复全部 | `crontab resumeAll --mode=produce` |
| 立即运行 | `crontab runJobNow --mode=produce --taskName=任务名` |
| 修改规则 | `crontab setCrontabRule --mode=produce --taskName=任务名 --taskRule='*/10 * * * *'` |
| 重载进程 | `crontab reload --mode=produce` |
| 强制重载 | `crontab reload --mode=produce --force` |

表格中省略了统一前缀，完整命令需加：

```text
php easyswoole.php
```

## 源码依据

- [Crontab 管理命令](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Command/DefaultCommand/Crontab.php)
- [CrontabSelector](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Command/Selector/CrontabSelector.php)
- [Process 管理命令](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Command/DefaultCommand/Process.php)
