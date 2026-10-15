# 管理命令：进程管理

`process` 命令用于查看 EasySwoole 运行实例中的 Worker、自定义进程和组件进程，并可以按 PID、进程组或进程名发送终止信号。

```text
process
├── show    查看进程列表
└── kill    选择并终止进程
```

进程信息来自正在运行服务的 Bridge，因此执行命令时必须使用正确的 `--mode`。

## 查看进程列表

```bash
php easyswoole.php process show --mode=produce
```

输出按 `group` 分组，每个进程会显示：

| 字段 | 说明 |
| --- | --- |
| `name` | 进程名称 |
| `pid` | 操作系统进程 ID |
| `group` | 进程组 |
| `memoryUsage` | 当前 PHP 内存使用量 |
| `memoryPeakUsage` | PHP 内存峰值 |
| `startUpTime` | 进程启动时间 |
| `lastHeartBeat` | 框架进程表最近一次心跳时间 |
| `customProcess` | 是否为自定义进程 |

输出示例（实际会继续列出其余 Worker）：

```text
Processes (total: 13)

EasySwoole.dev.Worker (8)
  [1] EasySwoole.dev.Worker.0   PID 18851
      Memory 3.45 MB   processUpTime 2026-10-16 00:29:20
      Peak 4 MB   lastHeartBeat 2026-10-16 00:46:49   Worker process
  [2] EasySwoole.dev.Worker.1   PID 18852
      Memory 3.45 MB   processUpTime 2026-10-16 00:29:20
      Peak 4 MB   lastHeartBeat 2026-10-16 00:46:49   Worker process

EasySwoole.dev.TaskWorker (4)
  [9] EasySwoole.dev.TaskWorker.0   PID 18863
      Memory 3.46 MB   processUpTime 2026-10-16 00:29:20
      Peak 4 MB   lastHeartBeat 2026-10-16 00:46:49   Custom process

EasySwoole.dev.Bridge (1)
  [13] EasySwoole.dev.Bridge   PID 18868
      Memory 3.46 MB   processUpTime 2026-10-16 00:29:20
      Peak 4 MB   lastHeartBeat 2026-10-16 00:46:49   Custom process
```

### 持续观察

```bash
php easyswoole.php process show --mode=produce --watch=2
```

`--watch` 不带值时默认每 2 秒刷新，也可以传入大于 0 的秒数。按 `q`、`Esc` 或 `Ctrl+C` 退出。该模式要求交互式终端。

## 交互式终止进程

在终端中不传筛选条件：

```bash
php easyswoole.php process kill --mode=produce
```

框架会展示可选进程。支持的操作为：

```text
↑/↓       移动光标
空格      选择或取消当前项
a         全选或取消全选
Enter     确认选择
q/Esc     取消
```

选择完成后还会再次询问是否发送信号。原生方向键界面不可用时，会退化为输入编号，例如 `1,3,5`。在 CI、重定向或其他非交互环境中，必须显式传入筛选 Option。

确认之前，框架会重新获取进程列表并校验 PID、名称、分组和启动时间，避免用户选择期间旧进程退出、同一个 PID 被新进程复用后误杀新进程。

## 按 PID 终止

```bash
php easyswoole.php process kill \
    --mode=produce \
    --pid=12345
```

`--pid` 必须是大于 0 的整数。默认发送 `SIGTERM`，让目标进程有机会正常退出。

## 按进程组终止

先执行 `process show` 查看输出中的准确组名，然后调用：

```bash
php easyswoole.php process kill \
    --mode=produce \
    --group='MyService.produce.Worker'
```

`--group` 使用完全匹配，不是模糊查询。该命令可能命中组内多个进程，执行前必须确认目标组。

## 按进程名终止

```bash
php easyswoole.php process kill \
    --mode=produce \
    --name='MyService.produce.Worker.0'
```

`--name` 同样使用完全匹配。

可以同时传入 `--pid`、`--group` 和 `--name`，但当前实现使用“任一条件匹配”，不是“全部条件同时满足”。多个筛选条件会扩大目标集合，不会缩小范围：

```bash
# 会匹配 PID 12345，或者属于指定 group 的所有进程。
php easyswoole.php process kill \
    --mode=produce \
    --pid=12345 \
    --group='MyService.produce.Worker'
```

自动化脚本建议只传一个明确条件，并先保存 `process show` 的结果。

## 强制终止

以下两种写法都会使用 `SIGKILL`：

```bash
php easyswoole.php process kill --mode=produce --pid=12345 --force
php easyswoole.php process kill --mode=produce --pid=12345 --force=true
```

显式关闭强制模式：

```bash
php easyswoole.php process kill --mode=produce --pid=12345 --force=false
```

默认的 `SIGTERM` 允许进程执行退出清理；`SIGKILL` 会立即终止进程，无法执行清理逻辑。仅在进程失去响应并确认可以承受任务中断、锁未释放和缓冲数据丢失时使用。

`kill` 成功时，无论使用 PID、组名还是进程名筛选，都会逐行输出实际信号和目标：

```text
[SIGTERM] EasySwoole.dev.Worker.0   PID 18851: signal sent
```

按组匹配多个进程时会有多行结果。没有任何进程匹配时输出：

```text
not any process match
```

使用 `--force` 时，前缀会变成 `[SIGKILL]`。PID 会在进程重建后变化，不要把示例 PID 写入脚本。

## 进程是否会自动恢复

- 普通 Worker 通常由 Manager 重新拉起。
- 框架托管的 Task Worker 或自定义进程是否恢复，取决于对应组件的进程管理逻辑。
- Master 进程被终止会导致整个服务退出，不要用 `process kill` 随意操作 Master。

终止进程不是 reload 的替代方案。需要更新普通 Worker 代码时使用 `server reload`；只需要管理自定义 Task Worker 时使用 `task reload`。

## 源码依据

- [Process 管理命令](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Command/DefaultCommand/Process.php)
- [ProcessSelector](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Command/Selector/ProcessSelector.php)

下一章：[异步管理](/Advanced/ManagementCommand/task.md)。
