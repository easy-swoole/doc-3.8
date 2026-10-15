# CoroutineRunner

`CoroutineRunner` 是组件中的命名空间，其中两个核心类分别负责队列调度和单个任务描述：

```php
EasySwoole\Component\CoroutineRunner\Runner
EasySwoole\Component\CoroutineRunner\Task
```

- `Runner`：维护任务 Channel，并用固定最大并发数启动任务协程。
- `Task`：保存 callable、执行结果、开始时间及成功和失败回调。

它适合已有一批任务、但不希望一次创建过多协程的场景，例如批量同步数据、处理文件或调用有并发限制的外部 API。

## 完整示例

```php
use EasySwoole\Component\CoroutineRunner\Runner;
use EasySwoole\Component\CoroutineRunner\Task;

Co\run(function (): void {
    $runner = new Runner(
        concurrency: 4,
        taskChannelSize: 128
    );

    $runner->setOnException(
        function (Throwable $throwable, Task $task): void {
            error_log(sprintf(
                'task failed after %.3f seconds: %s',
                microtime(true) - $task->getStartTime(),
                $throwable->getMessage()
            ));
        }
    );

    for ($i = 1; $i <= 10; $i++) {
        $taskId = $i;

        $task = new Task(function () use ($taskId): int|false {
            $result = RemoteService::handle($taskId);
            return $result ? $taskId * 2 : false;
        });

        $task->setOnSuccess(function (Task $task) use ($taskId): void {
            echo "task {$taskId}: {$task->getResult()}\n";
        });

        $task->setOnFail(function (Task $task) use ($taskId): void {
            echo "task {$taskId} returned false\n";
        });

        $runner->addTask($task);
    }

    $runner->start(30);
});
```

## Runner 构造参数

```php
$runner = new Runner(
    concurrency: 4,
    taskChannelSize: 128
);
```

| 参数 | 说明 |
| --- | --- |
| `concurrency` | 同时运行的任务协程上限，默认 `64` |
| `taskChannelSize` | 等待队列的 Channel 容量，默认 `1024` |

两个值都应设置为大于 0 的整数。组件当前没有主动校验 `concurrency`；设置为 0 时不会消费任务，只会等待到 Runner 超时。Channel 容量满时，`addTask()` 会挂起等待可写空间，因此应在协程环境中添加任务，并根据生产速度设置容量。

## 创建 Task

```php
$task = new Task(function (): mixed {
    return doSomething();
});
```

Task 提供以下数据：

| 方法 | 说明 |
| --- | --- |
| `getCall()` / `setCall()` | 读取或替换任务 callable |
| `getResult()` / `setResult()` | 读取或设置执行结果 |
| `getStartTime()` / `setStartTime()` | 任务开始执行时的 Unix 微秒时间 |
| `getOnSuccess()` / `setOnSuccess()` | 成功回调 |
| `getOnFail()` / `setOnFail()` | 返回 `false` 时的失败回调 |
| `getTimeout()` / `setTimeout()` | 保存任务超时配置 |

通常由 Runner 自动设置 `startTime` 和 `result`，业务代码主要设置 callable、`onSuccess` 和 `onFail`。

## 成功和失败如何判断

Runner 使用严格比较判断任务结果：

```php
$result !== false // 成功
$result === false // 失败
```

因此，以下返回值都会视为成功：

```php
null
0
''
[]
```

只有严格的布尔值 `false` 会触发 `onFail`。成功时先把返回值写入 `Task::result`，再调用 `onSuccess($task)`；失败时同样保存 `false`，再调用 `onFail($task)`。

## 异常处理

任务 callable、`onSuccess` 或 `onFail` 抛出的 `Throwable` 都会进入 Runner 的异常处理：

```php
$runner->setOnException(
    function (Throwable $throwable, Task $task): void {
        error_log($throwable->getMessage());
    }
);
```

如果没有设置 `onException`，异常会从任务协程继续抛出。生产环境建议始终设置异常回调，并通过传入的 `Task` 记录任务标识、开始时间和上下文。

异常任务不会自动重试。需要重试时，应在任务 callable 内实现有限次数重试，或创建新的 Task 重新入队，并确保写操作幂等。

## Task timeout 的实际行为

```php
$task->setTimeout(3);
```

当前 `Task::timeout` 只是一个可读写属性，Runner 不会读取它，也不会根据它中断任务。设置该值不能产生实际超时控制。

真正的超时应在业务 I/O 层实现，例如为 HTTP、Redis 或数据库请求设置超时；也可以在 callable 中使用适合当前业务的协程超时机制。

## 启动和结束条件

```php
$runner->start(30);
```

`start()` 会在以下任一条件满足时返回：

- 等待队列为空，并且当前运行任务数为 0。
- 运行时间超过 `$waitTime`。

`$waitTime` 单位为秒。传入 0 或负数时会转换为近似无限等待。

`start()` 没有完成状态返回值。返回后可以检查队列中是否仍有未启动任务：

```php
$status = $runner->status();

if ($status['queueSize'] > 0) {
    // Runner 可能因等待超时而提前返回，队列仍有任务。
}
```

需要特别注意：Runner 超时只会停止调度循环，不会取消已经启动的任务协程。未启动的任务仍留在队列中，并且 `start()` 返回时会把内部 `runningNum` 重置为 0，即使此前启动的协程仍可能在执行。因此，返回后的 `status()['runningNum']` 不能用于确认超时任务已经结束。

不要在超时后立刻复用同一个 Runner 或依赖状态计数完成资源释放；应让业务任务拥有自己的 I/O 超时，并为超时后的任务结果做好处理。

## 动态加入任务

`setOnLoop()` 会在 Runner 调度循环的每一轮调用，可以按需继续加入任务：

```php
$jobs = new SplQueue();
$jobs->enqueue(1001);
$jobs->enqueue(1002);

$runner->setOnLoop(function (Runner $runner) use ($jobs): void {
    if ($jobs->isEmpty()) {
        return;
    }

    $id = $jobs->dequeue();
    $runner->addTask(new Task(
        fn () => OrderService::sync($id)
    ));
});
```

`onLoop` 会被频繁调用，逻辑必须轻量，并且不能无上限持续生产任务，否则 Runner 无法满足队列为空的结束条件。

## 查看运行状态

```php
$status = $runner->status();
```

返回结构：

```php
[
    'queueSize' => 10,   // 等待执行的任务数，不包含运行中的任务
    'concurrency' => 4,  // 最大并发数
    'runningNum' => 4,   // 当前运行任务数
    'isRunning' => true, // 调度循环是否运行
]
```

`queueSize()` 只返回等待队列长度，不包含已经被取出、正在执行的任务。

## 生命周期与复用

一次正常执行完成后，可以继续 `addTask()` 并再次调用 `start()` 处理下一批任务。但不要并发调用同一个 Runner 的 `start()`，也不要在前一次因超时返回、任务仍在运行时立刻启动下一批。

如果不同批次的并发数、异常策略或生命周期不同，直接为每一批创建新的 Runner 更清晰。

## 常见错误

- 把 `taskChannelSize` 当成并发数。
- 把 `setTimeout()` 当成真正的任务超时。
- 认为返回 `null`、`0` 或空数组会触发 `onFail`。
- 不设置 `onException`，导致任务协程异常无人处理。
- Runner 超时返回后，认为运行中的任务已被取消。
- 在非协程环境调用 `addTask()` 或 `start()`。

## 源码依据

- [Runner](https://github.com/easy-swoole/component/blob/master/src/CoroutineRunner/Runner.php)
- [Task](https://github.com/easy-swoole/component/blob/master/src/CoroutineRunner/Task.php)
