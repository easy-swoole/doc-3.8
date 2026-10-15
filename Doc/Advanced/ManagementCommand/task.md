# 管理命令：异步管理

`task` 命令管理 `easyswoole/task` 2.2.1 创建的自定义 Task Worker。它可以查看每个 Task Worker 的运行状态，也可以同时或逐个重载 Task Worker。

```text
task
├── show      查看 Task Worker 状态
└── reload    重载 Task Worker
```

这里管理的是 EasySwoole Task 组件创建的 Worker，不是执行某一个 Task 业务对象的命令。异步任务的定义和投递方式参见[异步任务](/Advanced/task.md)。

## 查看 Task Worker

```bash
php easyswoole.php task show --mode=produce
```

每个 Worker 会显示：

| 字段 | 说明 |
| --- | --- |
| `index` | Task Worker 编号 |
| `pid` | 当前进程 PID |
| `State` | `accepting` 表示接收新任务，`draining` 表示停止接收并等待现有任务结束 |
| `Running` | 当前正在执行的任务数 |
| `Success` | 已成功完成的任务数 |
| `Fail` | 已失败的任务数 |
| `processUpTime` | 当前 Worker 启动时间 |

没有配置 Task Worker 时会显示 `No Task workers available.`。

本项目配置 4 个 Task Worker 时的实际输出如下：

```text
Task workers (total: 4)

[0] PID 18863   State accepting
    Running 0   Success 0   Fail 0
    processUpTime 2026-10-16 00:29:20

[1] PID 18864   State accepting
    Running 0   Success 0   Fail 0
    processUpTime 2026-10-16 00:29:20

[2] PID 18865   State accepting
    Running 0   Success 0   Fail 0
    processUpTime 2026-10-16 00:29:20

[3] PID 18866   State accepting
    Running 0   Success 0   Fail 0
    processUpTime 2026-10-16 00:29:20
```

### 持续观察

```bash
php easyswoole.php task show --mode=produce --watch=1
```

`--watch` 不带值时默认 2 秒刷新一次，也可以指定大于 0 的秒数。按 `q`、`Esc` 或 `Ctrl+C` 退出；非交互终端不能使用。

## 同时重载全部 Task Worker

```bash
php easyswoole.php task reload --mode=produce
```

默认流程为：

```text
通过 Bridge 查询全部 Task Worker PID
    ↓
向每个 PID 发送 SIGTERM
    ↓
组件停止接收新任务并退出
    ↓
进程管理器创建替代 Worker
```

命令输出“sent SIGTERM”表示信号已发送，不代表替代 Worker 已经全部就绪。因为所有 Worker 会在同一轮收到信号，Worker 数量较少或任务执行较长时，可能出现短暂没有 Worker 接收任务的窗口。

输出示例：

```text
sent SIGTERM to Task worker PIDs: 18863, 18864, 18865, 18866
```

## 滚动重载

生产环境有两个及以上 Task Worker 时，优先使用滚动重载：

```bash
php easyswoole.php task reload \
    --mode=produce \
    --rolling \
    --timeout=30
```

滚动重载每次只处理一个 Worker：

```text
取得初始 Worker 列表并按 index 排序
    ↓
确认目标 PID 未变化且仍在 accepting
    ↓
确认还有其他 Worker 可以接收任务
    ↓
向当前 Worker 发送 SIGTERM
    ↓
等待旧 PID 消失
    ↓
等待相同 index 的新 PID 进入 accepting
    ↓
继续处理下一个 Worker
```

`--timeout` 是每个 Worker 的等待上限，默认 30 秒，必须是大于 0 的数字。某个 Worker 超时、PID 被外部替换、没有其他可用 Worker 或发送信号失败时，滚动流程会停止，并保留已经完成的重载结果。

只有一个 Task Worker 时，滚动重载无法提供真正的无空窗切换。高可用异步处理至少应配置两个 Worker，并确保任务投递方能够处理暂时繁忙或连接失败。

滚动重载会等待每个替代 Worker 就绪，因此输出中会同时显示旧、新 PID：

```text
Task Worker 0: PID 18863 -> 19201 ready
Task Worker 1: PID 18864 -> 19202 ready
Task Worker 2: PID 18865 -> 19203 ready
Task Worker 3: PID 18866 -> 19204 ready
```

若当前没有 Task Worker，则输出：

```text
no Task workers available to reload
```

## 强制重载

```bash
# 同时向全部 Task Worker 发送 SIGKILL
php easyswoole.php task reload --mode=produce --force

# 逐个使用 SIGKILL
php easyswoole.php task reload \
    --mode=produce \
    --rolling \
    --force=true \
    --timeout=10
```

`--force` 不带值或设置为 `true` 时使用 `SIGKILL`；`--force=false` 仍使用 `SIGTERM`。

`SIGKILL` 不允许 Worker 等待当前任务完成。正在执行的邮件发送、写库或远程调用可能只完成一部分，因此 Task 必须设计为幂等，并通过业务状态、唯一键或重试记录避免重复副作用。日常发布应使用默认的 `SIGTERM`。

强制重载的输出格式相同，但信号名为 `SIGKILL`：

```text
sent SIGKILL to Task worker PIDs: 18863, 18864, 18865, 18866
```

## 重载前后的检查

```bash
# 1. 观察运行任务数量
php easyswoole.php task show --mode=produce --watch=1

# 2. 另一个终端执行滚动重载
php easyswoole.php task reload --mode=produce --rolling --timeout=30

# 3. 再次查看状态
php easyswoole.php task show --mode=produce
```

确认每个 index 的 PID 已更新、状态为 `accepting`，并检查 `Fail` 计数和应用错误日志。`Success`、`Fail` 等计数属于当前 Worker 的运行状态，新进程启动后可能重新计数，不能代替持久化业务监控。

## 源码依据

- [Task 管理命令](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Command/DefaultCommand/Task.php)
- [TaskReloader](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Command/TaskReloader.php)
- [Task 2.2.1](https://github.com/easy-swoole/task)

下一章：[Crontab 管理](/Advanced/ManagementCommand/crontab.md)。
