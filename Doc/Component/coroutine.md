# 协程任务调度

Component 在 Swoole 协程基础上提供了 `ChannelLock`、`WaitGroup`、`Csp`、`CoroutineRunner`、`ParallelJob` 和 `ReadyScheduler` 等常用并发封装。它们分别负责协程互斥、等待任务完成、并发收集结果、限制任务并发数和协调就绪状态。

| 组件 | 任务来源 | 并发控制 | 结果形式 | 适用场景 |
| --- | --- | --- | --- | --- |
| `ChannelLock` | 当前协程主动加锁 | 同一锁名串行执行 | 是否成功取得锁 | 防止多个协程同时修改同一资源 |
| `WaitGroup` | 预先登记，或由外部协程手动完成 | 不限制 | 完成数量 | 等待一组已知任务全部结束 |
| `Csp` | 预先按名称登记 | 每个任务一个协程 | 按名称保存结果 | 同时查询用户、订单、配置等多个数据源 |
| `CoroutineRunner` | 提前或在循环中加入 `Task` | 固定并发数 | 每个 Task 保存结果 | 有限任务队列、批量处理 |
| `ParallelJob` | 通过回调持续拉取任务 | 指定消费者协程数 | 是否结束 | 持续取任务并并行消费 |
| `ReadyScheduler` | 预先登记就绪项 | 等待全部或任意项目就绪 | 布尔值 | 等待数据库、缓存等依赖准备完成 |

## 运行环境

这些封装依赖 Swoole 协程，应在协程环境中使用。独立脚本需要先创建协程容器：

```php
<?php

require __DIR__ . '/vendor/autoload.php';

Co\run(function (): void {
    // 在这里使用本章介绍的协程调度组件。
});
```

在 EasySwoole Worker 中使用时，也应确认当前代码路径允许创建协程，并避免调用没有协程化的阻塞 I/O。

## ChannelLock：保护协程临界区

多个协程可能同时修改同一份进程内资源时，可以使用相同的锁名称保证临界区串行执行：

```php
$lock = ChannelLock::getInstance();

if ($lock->deferLock('order:1001', 1.0)) {
    // 当前协程结束时自动释放锁。
}
```

`ChannelLock` 是当前进程内的协程锁，不能用于跨 Worker 或跨服务器互斥。完整用法参见 [ChannelLock](/Component/channel-lock.md)。

## WaitGroup：只关心是否全部完成

当任务数量已经确定，并且只需要等待全部任务结束时，使用 `WaitGroup`：

```php
$waitGroup->add($loadUser);
$waitGroup->add($loadOrders);
$waitGroup->start();
$completed = $waitGroup->wait(3.0);
```

它不负责限制并发数，也不按任务名称整理返回值。完整用法参见 [WaitGroup](/Component/wait-group.md)。

## Csp：按名称并发收集结果

当多个任务互相独立，并且调用方需要按名称取得结果时，使用 `Csp`：

```php
$csp->add('user', $loadUser);
$csp->add('orders', $loadOrders);
$results = $csp->exec(3.0);
```

结果仍能通过 `user`、`orders` 区分，适合聚合接口。完整用法参见 [Csp](/Component/csp.md)。

## CoroutineRunner：限制任务队列并发数

`EasySwoole\Component\CoroutineRunner` 是命名空间，主要类是：

```php
EasySwoole\Component\CoroutineRunner\Runner
EasySwoole\Component\CoroutineRunner\Task
```

`Runner` 用固定数量的消费者协程处理 `Task` 队列，适合批量任务但不能一次性创建过多协程的情况：

```php
$runner = new Runner(concurrency: 4, taskChannelSize: 128);
$runner->addTask(new Task($callable));
$runner->start(30);
```

完整用法参见 [CoroutineRunner](/Component/runner-task.md)。

## ParallelJob：持续拉取并消费任务

任务不是一次性全部提供，而是需要不断从队列或其他来源拉取时，使用 `ParallelJob`：

```php
$parallel->setTaskProducer($fetchNextJob); // 返回 null 表示本次没有任务。
$parallel->setTaskHandler($handleJob);      // 非 null 值（包括 0、false）均会传入。
$parallel->sync(coroutineNum: 8, maxJobTry: 3, timeOut: 30);
```

完整用法参见 [ParallelJob](/Component/parallel-job.md)。

## ReadyScheduler：等待依赖就绪

当业务协程必须等待数据库、缓存或其他命名依赖进入就绪状态时，可以使用 `ReadyScheduler`：

```php
// Scheduler 和项目应已在主进程 initialize() 中创建。
$scheduler = ReadyScheduler::getInstance();

$allReady = $scheduler->waitReady(
    ['database', 'cache'],
    3.0
);
```

它协调的是命名状态，不负责执行任务本身。等待方法运行在协程中；如果要让不同 Worker 共享就绪状态，底层 `Swoole\Table` 必须在创建 Worker 前由主进程初始化。完整用法参见 [ReadyScheduler](/Component/ready-scheduler.md)。

## 超时不等于取消

这几个组件的等待超时，通常只表示调用方停止等待，不代表已经启动的协程会被强制终止。业务任务仍应为数据库、HTTP、Redis、Channel 等 I/O 操作设置各自的超时。

```text
整体等待超时
    ≠
自动取消所有业务协程
```

如果任务包含写入操作，调用方超时后不能直接假设任务没有执行。重试时应使用业务唯一键或幂等设计，避免重复写入。

## 选择建议

- 只等待一组任务完成：`WaitGroup`。
- 防止同一进程内的多个协程同时进入临界区：`ChannelLock`。
- 并发执行少量命名任务并聚合结果：`Csp`。
- 已有一批任务，需要限制最大并发数：`CoroutineRunner`。
- 持续从任务源拉取并由多个协程消费：`ParallelJob`。
- 等待一个或多个命名依赖进入就绪状态：`ReadyScheduler`。

## 源码依据

- [WaitGroup](https://github.com/easy-swoole/component/blob/master/src/WaitGroup.php)
- [ChannelLock](https://github.com/easy-swoole/component/blob/master/src/ChannelLock.php)
- [Csp](https://github.com/easy-swoole/component/blob/master/src/Csp.php)
- [CoroutineRunner](https://github.com/easy-swoole/component/tree/master/src/CoroutineRunner)
- [ReadyScheduler](https://github.com/easy-swoole/component/blob/master/src/ReadyScheduler.php)
