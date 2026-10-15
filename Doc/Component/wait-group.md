# 协程等待 WaitGroup

`WaitGroup` 用于等待一组协程任务完成。调用方预先登记任务数量，任务结束时提交完成信号，等待方收到全部完成信号后继续执行。

```text
add() 登记任务
      ↓
start() 启动回调任务
      ↓
每个任务结束后 done()
      ↓
wait() 收齐全部完成信号
```

它适合“任务数量已经确定，当前协程必须等待它们全部结束”的场景。它不限制同时运行的协程数量，也不会集中保存每个任务的返回值。

## 使用回调任务

把 callable 传给 `add()`，`WaitGroup` 会在 `start()` 或 `wait()` 时为每个回调创建协程：

```php
use EasySwoole\Component\WaitGroup;
use Swoole\Coroutine;

Co\run(function (): void {
    $result = [];
    $waitGroup = new WaitGroup();

    $waitGroup->add(function () use (&$result): void {
        Coroutine::sleep(0.1);
        $result['user'] = ['id' => 1001];
    });

    $waitGroup->add(function () use (&$result): void {
        Coroutine::sleep(0.2);
        $result['orders'] = [2001, 2002];
    });

    // 未显式调用 start() 时，wait() 会自动启动一次。
    if (!$waitGroup->wait(2.0)) {
        throw new RuntimeException('tasks timeout');
    }

    var_dump($result);
});
```

`add()` 只登记任务，不会立即运行。回调内部无论正常返回还是抛出异常，组件都会在 `finally` 中调用 `done()`，避免 WaitGroup 永远少一个完成信号。

组件不会收集回调的返回值，示例通过外部 `$result` 数组保存结果。多个协程写同一数组时，应保证它们写入不同键；复杂共享写入需要额外同步。

## 显式 start 后再 wait

需要让任务先运行一段时间，再在后面等待时，可以显式调用 `start()`：

```php
$waitGroup = new WaitGroup();
$waitGroup->add($taskA);
$waitGroup->add($taskB);

$waitGroup->start();

// 当前协程可以先执行其他工作。
prepareResponse();

if (!$waitGroup->wait(3.0)) {
    throw new RuntimeException('tasks timeout');
}
```

`start()` 只能调用一次。调用后不能继续 `add()`，否则抛出 `LogicException`。

## 手动登记外部协程

不把 callable 交给 WaitGroup，而是自行创建协程时，调用无参数的 `add()` 登记数量，并确保每个任务最终调用一次 `done()`：

```php
Co\run(function (): void {
    $waitGroup = new WaitGroup();

    $waitGroup->add();
    $waitGroup->add();
    $waitGroup->start();

    go(function () use ($waitGroup): void {
        try {
            UserService::refresh();
        } finally {
            $waitGroup->done();
        }
    });

    go(function () use ($waitGroup): void {
        try {
            OrderService::refresh();
        } finally {
            $waitGroup->done();
        }
    });

    if (!$waitGroup->wait(5.0)) {
        throw new RuntimeException('refresh timeout');
    }
});
```

手动模式必须先 `start()`，再让外部协程调用 `done()`。未启动时调用 `done()` 会抛出 `LogicException`；`done()` 次数超过 `add()` 次数也会抛出异常。

## 构造参数与容量

```php
$waitGroup = new WaitGroup(128);
```

构造参数是内部 Channel 的初始容量，必须大于 0，否则抛出 `InvalidArgumentException`。启动时组件会确保实际容量至少等于任务总数，因此显式 `start()` 后，即使尚未调用 `wait()`，回调任务也不会因为提交完成信号而被一个过小的 Channel 容量阻塞。

该参数不是最大任务数量，也不限制同时运行的协程数。

## wait 的返回值和超时

```php
$completed = $waitGroup->wait(2.5);
```

- 返回 `true`：等待方已收到全部任务的完成信号。
- 返回 `false`：指定时间内没有收齐完成信号。
- 超时单位为秒，支持浮点数。
- 传入 `null`、`0` 或负数时，按近似无限等待处理。
- 没有登记任何任务时，立即返回 `true`。

超时只会让 `wait()` 返回 `false`，不会取消仍在执行的协程。任务涉及写入操作时，不能因为等待超时就认定业务没有执行；重试应保证幂等。

## count 与 successNum

```php
$remaining = $waitGroup->count();
$observed = $waitGroup->successNum();
```

- `count()` 返回尚未调用 `done()` 的任务数。
- `successNum()` 返回最近一次 `wait()` 已经从 Channel 中确认收到的完成信号数。

任务可能已经调用 `done()`，但等待方尚未消费对应信号，因此两个数值不是简单的互补关系，尤其是在等待超时之后。

## 生命周期限制

一个 `WaitGroup` 对象只用于一批任务：

- `start()` 最多调用一次。
- `wait()` 最多调用一次。
- 启动后不能继续 `add()`。
- 等待超时后不能再次调用 `wait()`。
- 没有 `reset()`，下一批任务应创建新的 `WaitGroup`。

违反这些状态约束时会抛出 `LogicException`。

## 异常处理

回调抛出异常时，内部 `finally` 仍会提交完成信号，但 `WaitGroup` 不会把异常转换为结果，也没有统一的异常回调。业务需要自行捕获并记录：

```php
$errors = [];

$waitGroup->add(function () use (&$errors): void {
    try {
        RemoteService::request();
    } catch (Throwable $throwable) {
        $errors[] = $throwable;
    }
});
```

## 常见错误

- 认为 `add($callable)` 会立即执行任务。
- 手动模式忘记先调用 `start()`。
- 某条手动任务路径没有在 `finally` 中调用 `done()`。
- 用同一个对象处理多批任务。
- 把等待超时误认为任务已经被取消。
- 把 WaitGroup 当作并发限制器；它会为所有回调任务创建协程。

## 源码依据

- [WaitGroup](https://github.com/easy-swoole/component/blob/master/src/WaitGroup.php)
