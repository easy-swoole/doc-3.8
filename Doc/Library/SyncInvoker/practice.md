# 同步调用：超时、并发与使用边界

同步进程替 HTTP Worker 执行阻塞方法，但一次调用仍要等待结果。下面按 `sync-invoker` 2.2.3 的执行流程说明容量、失败与恢复。

## 一次调用的超时预算

```php
$result = InvokerHolder::getInstance()->invoke(2.0)->calculate(1, 2);
```

`invoke(float $timeout = 15.0)` 的单位为秒，支持小数，必须大于 0，不接受 `null`。计时从本次方法调用开始，覆盖等待空闲同步进程、Unix Socket 通信和 Driver 方法执行，不是只限制方法本身。

| 情况 | 调用方看到什么 | 同步进程如何处理 |
| --- | --- | --- |
| 所有同步进程都忙，超过预算 | `null` | 尚未分配进程，不会强杀任何进程 |
| 连接或发送失败 | 可能返回 `null`；部分底层异常会继续抛出 | 释放已抢占的进程；不把它当成执行超时 |
| Socket 接收明确报 `SOCKET_ETIMEDOUT` | `null` | 向本次调用记录的进程 PID 发送 `SIGKILL`，等待 Swoole 自动拉起替代进程 |
| Driver 正常完成并调用 `response()` | `response()` 设置的值 | 进程恢复空闲，继续接收下一次调用 |

只有明确的 Socket 接收超时才触发强杀；不要把所有 `null` 都解释为 Driver 执行超时。`null` 也可能是业务主动设置的正常结果。更危险的是 Driver 不会在每次调用前自动清空上一次的响应：如果本次漏写 `response()`，同一同步进程可能返回上一次调用的值。建议约定业务成功与业务错误都返回明确结构，例如 `['ok' => true, 'data' => ...]` 和 `['ok' => false, 'error' => ...]`，并确保每条分支都设置响应，把没有收到结果的 `null` 单独处理。

## 超时后为何会看到 `signal=9`

2.2.3 使用进程级 `SIGKILL` 终止明确超时的同步进程。日志可能出现：

```text
worker(pid=12345, id=2) abnormal exit, status=0, signal=9
```

若它与 Sync Invoker 超时同时出现，这是预期的进程重建过程：旧进程不再接收请求，Swoole 拉起新进程，新进程登记新的 PID 并重新变为可用。组件在强杀前核对记录的 PID，避免误杀已经重启的替代进程。不要无条件忽略所有 `signal=9`：手工 `kill -9`、OOM 等故障也会出现同样的信号，应结合调用超时、PID 和时间判断。

`SIGKILL` 无法被 PHP 捕获。因此被杀进程不会执行 Driver 的 `onException()`、`finally`、析构函数或 shutdown callback。进程独享的 SDK/数据库连接应在 `setOnWorkerStart()` 配置的回调中创建，以便替代进程启动后重建；不要依赖清理钩子完成重要的业务回滚。

## 业务异常与钩子

Driver 方法抛出的异常会传给该 Driver 的 `onException(\Throwable $throwable)`。默认实现会重新抛出；如果要向调用方返回结构化业务错误，在 `App/Sync/LegacyDriver.php` 中覆盖它：

```php
protected function onException(\Throwable $throwable): void
{
    error_log((string) $throwable);
    $this->response([
        'ok' => false,
        'error' => $throwable->getMessage(),
    ]);
}
```

这个回调收到的是 Driver 方法抛出的原始异常，不是“超时异常”。它自身不应再次抛出，否则异常继续传播到同步进程入口。`onRequest(Command $command): bool` 可在调用方法前拦截；返回 `false` 时应先在本次回调中调用 `response()` 设置拦截结果，否则可能返回上一次的响应。成功执行方法后会调用 `afterRequest()`。这些方法是 Driver 生命周期钩子，不是客户端可远程调用的业务方法。

## 进程数量与状态

在 `mainServerCreate()` 中、`attachServer()` 之前配置：

```php
$invoker->getConfig()->setWorkerNum(4);
$invoker->getConfig()->setMaxPackageSize(2 * 1024 * 1024);
```

`workerNum` 是同步进程数，不是 HTTP Worker 数；每个同步进程同一时刻只执行一个任务，因此最多同时运行 `workerNum` 个阻塞调用。进程数增加也会增加内存和第三方服务连接数。共享表固定创建 256 行，不要把 `workerNum` 设置得超过 256。组件固定以串行方式处理每个进程的任务，不需要开启进程内的异步并发。

服务启动后可观察进程状态：

```php
$workers = InvokerHolder::getInstance()->workerInfo();
// 示例：
// [
//     ['isAvailable' => 1, 'pId' => 12345],
//     ['isAvailable' => 0, 'pId' => 12346],
// ]
```

`1` 表示空闲，`0` 表示正在执行；超时强杀后、替代进程启动前可能短暂看到 `-1`。`pId` 是同步进程 PID，重建后会变化。尚未启动的进程不会出现在返回列表中。列表下标不是稳定的进程编号，不要用它作为业务 ID。

## 重试、事务与幂等

收到 `null` 并不能证明同步方法没有执行。可能已经向外部服务发起请求，或数据库事务已经提交，只是返回结果时超时或通信中断。立即重试扣款、发消息、创建订单等操作可能产生重复副作用。

- 为有副作用的调用传入业务唯一键，并在 Driver 或下游服务做幂等校验。
- 超时后先查业务状态，再决定是否重试；不要把 `null` 直接当成“操作失败”。
- 尽量缩短事务范围，不要在数据库事务中等待耗时外部接口。
- 被强杀的进程不会执行 PHP 清理代码；未提交事务及其锁何时释放，要看 MySQL 何时确认对应会话已经断开。

### 强杀时 MySQL 事务何时释放

假设同步进程已开启普通 InnoDB 事务，执行了 `UPDATE`，却在 `COMMIT` 前被 `SIGKILL`：

```text
同步进程被强杀
    → PHP 的 finally / rollback() 不执行
    → 进程持有的 MySQL Socket 由操作系统关闭
    → MySQL 检测到该连接断开
    → 回滚未提交事务，并在事务终止后释放其锁
```

本章的接入方式是在同步 Worker 中创建并独占 MySQL 连接。Worker 被强杀后，操作系统会关闭它持有的 Socket；直接连接 MySQL 时，服务端检测到断线后会结束会话、回滚普通未提交事务，事务终止时释放锁，**通常不需要等到 `wait_timeout`**。不过“Worker 已退出”不等于“MySQL 已完成回滚”：MySQL 可能仍在执行语句、检测断线或回滚大量修改，期间其他事务仍可能等锁。若中间还有数据库代理，实际释放时机也取决于代理如何处理它到 MySQL 的后端连接；`wait_timeout` 只是在连接一直未被识别为断开时才可能涉及的兜底机制，不应当成正常回滚流程。

因此，连接应在 `setOnWorkerStart()` 中为每个同步 Worker 分别建立，并在 Worker 重建后重新建立。不要把它提前放在父进程创建；这既不符合进程隔离，也会让连接所有权和断线行为难以判断。

排查锁迟迟未释放时，可在 MySQL 侧查看仍在运行或回滚的事务及其会话 ID：

```sql
SELECT trx_id, trx_state, trx_started, trx_mysql_thread_id, trx_query
FROM information_schema.innodb_trx;

SHOW PROCESSLIST;
SHOW GLOBAL VARIABLES LIKE 'wait_timeout';
```

把 `trx_mysql_thread_id` 与 `SHOW PROCESSLIST` 的 `Id` 对照，并结合强杀时间和数据库日志判断会话是否仍存在。不要仅凭 Sync Invoker 已拉起新进程就断定旧事务及锁已经释放。已经 `COMMIT` 的事务不会因断线而撤销；`XA PREPARE` 等特殊事务也不适用普通“断线即回滚”的判断。

MySQL 的[异常断线说明](https://dev.mysql.com/doc/refman/8.4/en/communication-errors.html)、[InnoDB 锁释放规则](https://dev.mysql.com/doc/refman/8.4/en/innodb-locks-set.html)和 [`wait_timeout` 定义](https://dev.mysql.com/doc/refman/8.4/en/server-system-variables.html)可用于核对线上实际行为。

## 参数、状态与部署边界

参数和结果经过序列化与 Unix Socket 传输，不要传数据库连接、Socket、闭包或超大文件；大数据可传记录 ID 或文件路径，让同步进程自行读取。`setMaxPackageSize()` 限制通信包大小。

Driver 实例不会为每次调用克隆，而且调用可能落到任意空闲进程。不要把当前请求的数据、调用次数或跨请求共享状态保存在 Driver 的普通属性中；跨进程状态应放在数据库、Redis 或其他共享介质。同步进程需要的连接应在进程启动后建立。

在同一机器部署多个服务实例时，为每个实例配置独立且可写的 `tempDir`，避免它们争用 `SyncInvoker.Worker.*.sock`。修改进程数量或目录后需要完整重启服务。

Sync Invoker 不适合很长的后台任务：它仍会占用一个同步进程，并让请求等待。长任务应使用异步任务或队列消费者。

## 源码依据

- [组件 README（2.2.3）](https://github.com/easy-swoole/sync-invoker/blob/2.2.3/README.md)
- [Client（2.2.3）](https://github.com/easy-swoole/sync-invoker/blob/2.2.3/src/Client.php)
- [Worker（2.2.3）](https://github.com/easy-swoole/sync-invoker/blob/2.2.3/src/Worker.php)
