# 同步调用：超时、并发与使用边界

Sync Invoker 解决的是“阻塞式 SDK 占用 HTTP Worker”的问题，不会提升该 SDK 本身的执行速度。配置容量、超时和错误处理时，应按独立进程的模型理解。

## 调用超时

```php
$value = InvokerHolder::getInstance()->invoke(2.0)->calculate(1, 2);
```

`invoke()` 的参数单位是秒，支持小数；默认 15 秒。2.2.2 把它作为一次调用的总时间预算，包含等待空闲进程、Unix Socket 通信和方法执行。执行阶段的超时由 `SIGALRM` 实现，属于软中断：第三方扩展若长时间停留在不可中断的底层调用，可能不能及时停止。因此仍要为阻塞 SDK 自身配置超时。

调用可能因为同步进程繁忙、超时、连接失败或 Driver 抛错而失败。没有空闲进程且超过期限、或 Socket 通信失败时可能返回 `null`，所以不要把 `null` 当作正常业务值。Driver 默认的 `onException()` 会重新抛出异常；若希望调用方收到结构化错误，应覆盖该方法并通过 `$this->response(['ok' => false, 'error' => '...'])` 设置返回值。涉及扣款、发消息等有副作用的操作，超时后状态可能不明，重试前要先查询状态或使用幂等键。

例如在 `App/Sync/LegacyDriver.php` 中覆盖异常钩子：

```php
use EasySwoole\SyncInvoker\Exception\ExceptionStatus;
use EasySwoole\SyncInvoker\Exception\InvokeException;

protected function onException(\Throwable $error): void
{
    $status = $error instanceof InvokeException
        ? $error->getStatus()
        : ExceptionStatus::UNKNOWN;

    error_log($error->__toString());
    $this->response([
        'ok' => false,
        'status' => $status->value,
        'error' => $error->getMessage(),
    ]);
}
```

这段方法应放进 Driver 类中，不是独立脚本。`ExceptionStatus::TIMEOUT` 表示执行超时，`CALLBACK` 表示 Driver 方法抛错。调用方仍需单独判断 `null`：它可能是客户端未收到响应，而非 Driver 返回的错误数组。

## 进程数量与容量

```php
$invoker->getConfig()->setWorkerNum(4);
$invoker->getConfig()->setTempDir(sys_get_temp_dir());
$invoker->getConfig()->setMaxPackageSize(2 * 1024 * 1024);
```

`workerNum` 是同步执行进程数，不是 HTTP Worker 数。2.2.2 从空闲进程中选择一个执行，单个进程同一时间只执行一个阻塞调用；所有进程忙时，请求会等待直到有空闲进程或超时。不要把 HTTP 请求并发量误认为同步执行并发量。进程数越多，占用的内存和第三方服务连接也越多，应按负载逐步调整；共享表最多容纳 256 个同步进程。

参数和返回值会序列化并通过 Unix Socket 传输，避免传大文件、超大数组或不可序列化的对象。`maxPackageSize` 是通信包上限；大数据建议传文件路径或记录 ID，让同步进程自行读取。临时目录需要可写，并且多个服务实例应避免使用相同的 Socket 文件名；可通过 `setTempDir()` 为实例划分独立目录。

## 初始化阻塞客户端

如果第三方 SDK 需要长连接，可在同步进程启动后初始化，而不是在 `mainServerCreate()` 中打开连接：

```php
use EasySwoole\SyncInvoker\Worker;

$invoker->getConfig()->setOnWorkerStart(function (Worker $worker): void {
    $index = $worker->getArg()['workerIndex'];
    error_log("同步进程 {$index} 已启动");
    // 可在这里初始化当前进程独享的阻塞式客户端。
});
```

这段配置应写在 `attachServer()` 之前。多个同步进程之间不共享普通 PHP 对象的状态；若要共享任务数据，请使用数据库、Redis 或其他进程间存储。2.2.2 的 Driver 不会为每次调用克隆，因此不能把单次请求的数据留在 Driver 属性上。组件的超时使用进程级 `SIGALRM`，不要在同步进程里另行占用该信号，也不要把 `asyncAccept` 改为 `true`。

## 不适合的场景

- 已有协程友好的客户端：直接用协程客户端，减少跨进程开销。
- 很长的后台任务：优先使用异步任务或专门的队列消费者，不要让 HTTP 请求一直等待。
- 强依赖调用方内存状态的对象：跨进程不能直接共享连接、闭包状态或资源句柄。
- 无法容忍重试产生副作用的业务：先设计幂等和状态查询，再决定是否同步调用。

## 源码依据

- [组件 README（2.2.2）](https://github.com/easy-swoole/sync-invoker/blob/2.2.2/README.md)
- [Client（2.2.2）](https://github.com/easy-swoole/sync-invoker/blob/2.2.2/src/Client.php)
- [Config（2.2.2）](https://github.com/easy-swoole/sync-invoker/blob/2.2.2/src/Config.php)
