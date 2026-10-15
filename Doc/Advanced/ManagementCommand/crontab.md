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
└── setCrontabRule     临时修改任务规则
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

表格中省略了统一前缀，完整命令需加：

```text
php easyswoole.php
```

## 源码依据

- [Crontab 管理命令](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Command/DefaultCommand/Crontab.php)
- [CrontabSelector](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Command/Selector/CrontabSelector.php)
