# 异步任务

异步任务适合发送通知、生成报表、处理图片等不需要阻塞当前 HTTP 请求的工作。EasySwoole 启动主服务时会创建独立的 TaskWorker，业务代码通过 `TaskManager` 投递任务。

## 配置 TaskWorker

打开项目根目录的 `dev.php`；生产环境还需要同步修改 `produce.php`。在 `MAIN_SERVER` 中配置 `TASK`：

```php
'MAIN_SERVER' => [
    // 其他主服务配置……
    'TASK' => [
        'workerNum' => 4,
        'maxRunningNum' => 128,
        'maxPackageSize' => 2 * 1024 * 1024,
        'pushTimeOut' => 5.0,
    ],
],
```

| 配置 | 默认值 | 说明 |
| --- | ---: | --- |
| `workerNum` | `3` | TaskWorker 数量，范围为 1～512 |
| `maxRunningNum` | `128` | 每个 Worker 的最大并发任务数 |
| `maxPackageSize` | `2 MiB` | 请求或响应完整数据帧的大小上限 |
| `pushTimeOut` | `5.0` | 异步投递使用的默认超时时间，单位为秒 |

修改 Worker 数量或进程配置后需要重启服务，仅热重载不会重新创建进程。

## 定义任务类

新建 `App/Task/SendWelcomeMail.php`：

```php
<?php

namespace App\Task;

use EasySwoole\Task\AbstractInterface\TaskInterface;

final class SendWelcomeMail implements TaskInterface
{
    public function __construct(
        private readonly int $userId,
        private readonly string $email
    ) {
    }

    public function run(int $taskId, int $workerIndex): bool
    {
        // 此处运行在 TaskWorker，不会阻塞原来的 HTTP 请求。
        // MailService::sendWelcome($this->userId, $this->email);

        return true;
    }

    public function onException(
        \Throwable $throwable,
        int $taskId,
        int $workerIndex
    ): bool {
        // 记录任务编号、Worker 编号和异常。
        // Logger::getInstance()->error($throwable->getMessage());

        return false;
    }
}
```

投递时必须传入实现了 `TaskInterface` 的对象实例：

```php
$task = new SendWelcomeMail($userId, $email);
TaskManager::getInstance()->async($task);
```

任务实例会使用 PHP 原生序列化跨进程传输。任务属性必须能够序列化，不要把闭包、数据库连接、文件句柄、Request 或 Response 放进任务；通常只传用户 ID、订单 ID 等必要参数，并在 `run()` 中重新查询数据。

## 异步投递

可以在控制器 Action 中直接取得框架的任务管理器：

```php
use App\Task\SendWelcomeMail;
use EasySwoole\EasySwoole\Task\TaskManager;
use EasySwoole\Task\TaskStatus;

$result = TaskManager::getInstance()->async(
    new SendWelcomeMail($userId, $email)
);

if ($result instanceof TaskStatus) {
    throw new \RuntimeException(
        "任务投递失败：{$result->message()}，错误码：{$result->value}"
    );
}

// int 类型表示任务 ID，只代表 Worker 已经接收任务。
$this->response()->write("task id: {$result}");
```

失败结果使用 `TaskStatus` 枚举。业务任务本身可以合法返回负整数，它不会与组件状态码混淆。

`async()` 成功返回任务 ID，仅表示 Worker 已接收任务，不表示 `run()` 已执行成功。异步任务的最终状态应由任务自身记录到日志或业务存储。

## 设置投递超时

`async()` 的第二个参数是本次调用的 `pushTimeOut`：

```php
$result = TaskManager::getInstance()->async(
    new SendWelcomeMail($userId, $email),
    pushTimeOut: 1.5
);
```

这个时间覆盖序列化、连接 Worker、发送任务包和等待投递响应的整个流程。未传时使用配置中的 `pushTimeOut`；小于等于 `0` 表示不设置截止时间，`NAN` 或 `INF` 会抛出 `InvalidArgumentException`。

投递超时不等于取消任务。如果 Worker 已经开始运行，即使调用方收到了超时结果，任务仍可能执行完成。因此，调用方重试可能造成重复执行，发券、扣款、通知等操作必须通过业务唯一键保证幂等。

## 同步执行

需要等待任务结果时可以使用 `sync()`：

```php
use EasySwoole\EasySwoole\Task\TaskManager;
use EasySwoole\Task\TaskStatus;

$result = TaskManager::getInstance()->sync(
    new SendWelcomeMail($userId, $email),
    pushTimeOut: 3.0
);

if ($result instanceof TaskStatus) {
    throw new \RuntimeException($result->message());
}

// $result 是任务 run() 或 onException() 返回的业务结果。
```

`sync()` 仍由 TaskWorker 执行，但当前协程会等待执行结果。同步返回值同样需要能够序列化，而且编码后的响应不能超过 `maxPackageSize`。需要快速响应客户端的耗时工作应使用 `async()`；只有当前业务确实依赖任务结果时才使用 `sync()`。

## TaskStatus 状态码

```php
use EasySwoole\Task\TaskStatus;

$status = TaskStatus::ERROR_PROCESS_BUSY;

echo $status->value;     // -2
echo $status->message(); // task process busy
```

| 状态 | 说明 |
| --- | --- |
| `ERROR_PROCESS_BUSY` | 没有可接收任务的 Worker |
| `ERROR_PROTOCOL_ERROR` | 投递协议解析失败 |
| `ERROR_ILLEGAL_PACKAGE` | 任务包不合法或任务未通过白名单 |
| `ERROR_TASK_ERROR` | 同步任务执行异常 |
| `ERROR_PACKAGE_EXPIRE` | 任务开始执行前已经过期 |
| `ERROR_SOCK_TIMEOUT` | Socket 连接、发送或接收超时 |
| `ERROR_PACKAGE_TOO_LARGE` | 投递包超过 `maxPackageSize` |
| `ERROR_RESPONSE_TOO_LARGE` | 同步任务返回数据超过限制 |

## Worker 选择与繁忙处理

投递前，组件会从共享状态表中排除尚未启动、正在退出和已达到 `maxRunningNum` 的 Worker，再选择当前 `running` 最小的 Worker；负载相同时随机选择。

Task 组件不使用内置任务队列。一次调用只向一个 Worker 投递一次，遇到 Worker 繁忙、连接失败或超时不会自动改投另一个 Worker，避免调用方不确定任务是否送达时发生隐式重复执行。是否重试应由业务根据任务幂等性决定。

## 可选任务白名单

默认允许投递所有 `TaskInterface` 实现类。需要限制允许执行的任务类型时，在项目根目录的 `EasySwooleEvent.php` 中注册白名单：

```php
use App\Task\SendWelcomeMail;
use EasySwoole\EasySwoole\Task\TaskManager;

public static function mainServerCreate(EventRegister $register)
{
    TaskManager::getInstance()
        ->getConfig()
        ->addRegistryTask(SendWelcomeMail::class);
}
```

白名单为空表示不限制；一旦添加了任务类，就只能投递明确登记的类。未登记的任务返回 `TaskStatus::ERROR_ILLEGAL_PACKAGE`。

## 查看 Worker 状态

```php
use EasySwoole\EasySwoole\Task\TaskManager;

$status = TaskManager::getInstance()->status();
```

返回结果按 Worker 编号包含：

- `accepting`：是否还接受新任务，退出中的 Worker 为 `0`。
- `running`：正在执行的任务数。
- `success`：成功任务数。
- `fail`：失败或被丢弃的任务数。
- `pid`：Worker 进程 ID。
- `startUpTime`：Worker 启动时间戳。

这些数据适合监控进程状态，不应替代业务任务表。

## Worker 退出

Worker 收到 `SIGTERM` 后会停止接收新任务，等待已经开始的任务执行完成，再清理状态记录和 Unix Socket 后退出。为了能够正常重启：

- 不要在任务中编写没有退出条件的 `while (true)`。
- 所有网络、文件和子进程调用都应设置超时。
- CPU 密集循环应拆分批次并适当让出协程调度。
- 单纯在无限循环中加入 `Coroutine::sleep()` 并不能让任务正常结束，任务本身仍需有明确的退出条件。

组件不会强制中断已经运行的 PHP 任务。永久阻塞的任务会导致 Worker 无法完成优雅退出。

## 数据包与 Socket 路径

`maxPackageSize` 同时限制异步任务包、同步任务包和同步响应，完整大小包含 4 字节长度头。传输大文件时只应传文件路径或对象存储标识，不要把文件内容直接放入任务对象。

TaskWorker 使用 Unix Domain Socket。完整路径格式为：

```text
{tempDir}/{serverName}.TaskWorker.{workerId}.sock
```

完整路径限制为 100 字节。框架会使用 EasySwoole 临时目录和服务名设置这两个参数；部署目录过深时，应缩短项目临时目录配置，否则服务会在创建 Worker 时抛出异常。

## 使用建议

- 重要任务应记录业务状态、失败原因和重试次数。
- 所有可能重试的写操作都应保证幂等。
- 不要无限增加 `workerNum` 和 `maxRunningNum`，数据库连接数与下游服务容量需要一起评估。
- 任务代码更新后应按部署流程重启或重载进程。
- 异步任务适合有限时间内能够完成的工作，长期循环消费者应使用[自定义进程](/Advanced/process.md)。

## 源码依据

- [EasySwoole Task](https://github.com/easy-swoole/task)
- [TaskStatus](https://github.com/easy-swoole/task/blob/2.2.1/src/TaskStatus.php)
- [框架 TaskManager](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Task/TaskManager.php)
