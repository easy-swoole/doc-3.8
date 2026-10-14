# 日志与错误

EasySwoole 使用 `Logger` 记录普通运行日志，使用 `Trigger` 处理 PHP 错误和异常。两者的职责可以简单理解为：

```text
业务运行信息 ─────────────→ Logger
PHP 错误或 Throwable ─────→ Trigger ─────→ Logger
```

业务流程、订单状态和调试信息直接使用 `Logger`；需要保留错误级别、发生位置或异常文件与行号时使用 `Trigger`。

## Logger 基本用法

`Logger` 提供四个常用级别：

```php
use EasySwoole\EasySwoole\Logger;

$logger = Logger::getInstance();

$logger->info('用户登录成功');
$logger->notice('验证码即将过期');
$logger->warning('第三方接口响应较慢');
$logger->error('订单创建失败');
```

默认 Logger 会把日志写入文件，并根据配置决定是否同时输出到控制台。

日志方法的第二个参数是分类：

```php
Logger::getInstance()->info(
    '订单支付成功，orderId=10001',
    'payment'
);

Logger::getInstance()->warning(
    '数据库查询超过 500ms',
    'slow-query'
);
```

分类适合表示业务模块，例如 `payment`、`user`、`fast-db`。不要把每个订单号当作分类，否则很难配置分类过滤。

## 指定日志级别

需要动态指定级别时，调用 `log()`：

```php
use EasySwoole\EasySwoole\AbstractInterface\Log\LogLevelEnum;
use EasySwoole\EasySwoole\Logger;

Logger::getInstance()->log(
    '库存不足，productId=100',
    LogLevelEnum::WARNING,
    'inventory'
);
```

当前支持的级别是：

- `LogLevelEnum::INFO`
- `LogLevelEnum::NOTICE`
- `LogLevelEnum::WARNING`
- `LogLevelEnum::ERROR`

`Logger` 的消息参数必须是字符串。需要记录数组时，应先转换为 JSON，并检查编码失败：

```php
$context = [
    'orderId' => 10001,
    'userId' => 9527,
    'amount' => 99.90,
];

Logger::getInstance()->info(
    json_encode(
        $context,
        JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR
    ),
    'order'
);
```

## 仅输出到控制台

`console()` 只执行控制台输出，不写入日志文件：

```php
use EasySwoole\EasySwoole\AbstractInterface\Log\LogLevelEnum;
use EasySwoole\EasySwoole\Logger;

Logger::getInstance()->console(
    '数据迁移进度：50%',
    LogLevelEnum::INFO,
    'migration'
);
```

生产服务通常不应依赖控制台输出保存日志。守护模式、systemd 和容器环境的标准输出处理方式不同，重要信息应通过 `info()`、`warning()` 或 `error()` 写入正式日志。

## 日志配置

日志配置位于项目根目录的 `dev.php` 和 `produce.php`：

```php
<?php

use EasySwoole\EasySwoole\AbstractInterface\Log\LogLevelEnum;

return [
    // 其他配置……
    'LOG' => [
        'dir' => EASYSWOOLE_ROOT . '/Log',
        'handler' => null,
        'logLevels' => [
            LogLevelEnum::NOTICE,
            LogLevelEnum::WARNING,
            LogLevelEnum::ERROR,
        ],
        'displayConsole' => false,
        'ignoreCategory' => [
            'health-check',
        ],
    ],
];
```

| 配置 | 说明 |
| --- | --- |
| `dir` | 日志目录；为空时使用项目根目录下的 `Log` |
| `handler` | 自定义 `LoggerInterface` 实例；为空时使用默认文件 Logger |
| `logLevels` | 允许记录的级别；空数组表示不过滤级别 |
| `displayConsole` | 调用 `log()` 时是否同时输出到控制台 |
| `ignoreCategory` | 不记录的日志分类 |

默认 Logger 按月写入文件。例如开发模式的文件名为：

```text
Log/dev.log_YYYYMM.log
```

生产模式的前缀通常是 `produce`。修改日志配置后需要重启或重载对应 Worker 才能让新进程读取配置。

## Trigger 记录错误

主动报告一个错误时调用 `Trigger::error()`：

```php
use EasySwoole\EasySwoole\Trigger;

Trigger::getInstance()->error(
    '支付回调签名验证失败',
    E_USER_WARNING
);
```

未传入位置时，Trigger 会通过调用栈取得调用处的文件和行号。默认处理器会根据错误码映射日志级别：

| 错误类型 | 日志级别 |
| --- | --- |
| `E_ERROR`、`E_USER_ERROR` 等严重错误 | `ERROR` |
| `E_WARNING`、`E_USER_WARNING` 等警告 | `WARNING` |
| `E_NOTICE`、`E_USER_NOTICE`、`E_DEPRECATED` | `NOTICE` |
| 其他错误码 | `INFO` |

需要明确指定错误位置时，可以创建 `TriggerLocation`：

```php
use EasySwoole\EasySwoole\AbstractInterface\Log\TriggerLocation;
use EasySwoole\EasySwoole\Trigger;

$location = new TriggerLocation();
$location->setFile('/path/to/import.csv');
$location->setLine(128);

Trigger::getInstance()->error(
    '导入数据格式错误',
    E_USER_WARNING,
    $location
);
```

这里的文件和行号也可以表示业务数据来源，不一定必须是 PHP 源文件。

## Trigger 记录异常

捕获异常后，如果异常需要进入全局错误日志，可以调用 `throwable()`：

```php
use EasySwoole\EasySwoole\Trigger;

try {
    $orderService->create($data);
} catch (\Throwable $throwable) {
    Trigger::getInstance()->throwable($throwable);

    // 根据当前业务场景继续返回错误、回滚事务或重新抛出。
    throw $throwable;
}
```

默认 Trigger 会记录异常消息、异常文件和行号，日志分类为 `trigger`。它不会替你决定 HTTP 响应，也不会自动回滚数据库事务。

捕获异常后要避免重复记录。例如控制器捕获后调用 `Trigger::throwable()`，随后重新抛出，HTTP 全局异常处理器又记录一次，同一个异常就会出现两条日志。应明确由业务层或全局异常层中的一处负责记录。

## PHP 错误如何进入 Trigger

框架初始化时会注册 PHP error handler：

```text
PHP warning/notice/error
  → 框架 error handler
  → Trigger::error()
  → DefaultTrigger
  → Logger
```

进程关闭时，框架还会读取 `error_get_last()`，把最后一条 PHP 错误交给 Trigger。HTTP 调度器捕获到未处理的 `Throwable` 时，也会调用框架配置的 HTTP 异常处理器。

已经被业务代码 `catch` 且没有重新抛出的异常，不会自动到达全局异常处理器。如果需要记录，必须显式调用 `Trigger::throwable()` 或 `Logger::error()`。

## 监听 Trigger

可以在 Trigger 进入默认处理器之前增加回调，例如把严重错误发送到告警平台。应在 `EasySwooleEvent.php` 的 `mainServerCreate()` 中配置：

```php
<?php

namespace EasySwoole\EasySwoole;

use EasySwoole\EasySwoole\AbstractInterface\Event;
use EasySwoole\EasySwoole\AbstractInterface\Log\TriggerLocation;
use EasySwoole\EasySwoole\Swoole\EventRegister;

class EasySwooleEvent implements Event
{
    public static function initialize()
    {
    }

    public static function mainServerCreate(EventRegister $register)
    {
        Trigger::getInstance()->setOnError(
            function (
                mixed $message,
                int $errorCode,
                TriggerLocation $location
            ): void {
                // AlarmService::send(...);
            }
        );

        Trigger::getInstance()->setOnThrowable(
            function (\Throwable $throwable): void {
                // AlarmService::send(...);
            }
        );
    }
}
```

回调正常结束后，默认 Trigger 仍会继续处理。回调返回 `false` 会阻止默认处理器执行：

```php
Trigger::getInstance()->setOnThrowable(
    function (\Throwable $throwable): bool {
        // 完全由自定义逻辑处理。
        return false;
    }
);
```

只有自定义逻辑已经可靠记录异常时才返回 `false`，否则会造成错误日志丢失。告警服务本身也可能失败，回调中应捕获异常，避免错误处理过程再次抛出异常。

## 自定义 Logger

需要输出 JSON、写入集中式日志系统或更改文件拆分方式时，可以实现 `LoggerInterface`。新建 `App/Log/JsonLogger.php`：

```php
<?php

namespace App\Log;

use EasySwoole\EasySwoole\AbstractInterface\Log\LoggerInterface;
use EasySwoole\EasySwoole\AbstractInterface\Log\LogLevelEnum;

class JsonLogger implements LoggerInterface
{
    public function __construct(private string $file)
    {
    }

    public function log(
        string $msg,
        LogLevelEnum $logLevel = LogLevelEnum::INFO,
        ?string $category = null
    ): bool {
        $line = json_encode([
            'time' => date(DATE_ATOM),
            'level' => $logLevel->name,
            'category' => $category ?? 'debug',
            'message' => $msg,
            'pid' => getmypid(),
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);

        return file_put_contents(
            $this->file,
            $line . PHP_EOL,
            FILE_APPEND | LOCK_EX
        ) !== false;
    }

    public function console(
        string $msg,
        LogLevelEnum $logLevel = LogLevelEnum::INFO,
        ?string $category = null
    ): bool {
        return fwrite(
            STDOUT,
            "[{$logLevel->name}][{$category}] {$msg}" . PHP_EOL
        ) !== false;
    }
}
```

在 `EasySwooleEvent::initialize()` 中注册。框架会在 `initialize()` 执行结束后读取该处理器并创建 `Logger` 单例：

```php
use App\Log\JsonLogger;
use EasySwoole\Component\Di;
use EasySwoole\EasySwoole\SysConst;

public static function initialize()
{
    Di::getInstance()->set(
        SysConst::LOGGER_HANDLER,
        new JsonLogger(EASYSWOOLE_LOG_DIR . '/application.json.log')
    );
}
```

不要在 `initialize()` 中直接调用 `Logger::getInstance()->info()`。此时框架尚未完成 Logger 初始化；需要记录启动日志时，可在 `mainServerCreate()` 或后续服务事件中记录。

自定义 Logger 运行在调用日志的进程中。高并发场景直接同步写远程服务会阻塞请求，应写本地文件、使用非阻塞客户端，或把日志交给独立采集程序。

## 自定义 Trigger

需要完全改变错误和异常的处理方式时，可以实现 `TriggerInterface`。与 `setOnError()`、`setOnThrowable()` 不同，自定义 Trigger 会替换框架的 `DefaultTrigger`，因此必须自行完成日志记录，不能假设默认日志仍会执行。

新建 `App/Log/AlertTrigger.php`：

```php
<?php

namespace App\Log;

use EasySwoole\EasySwoole\AbstractInterface\Log\LogLevelEnum;
use EasySwoole\EasySwoole\AbstractInterface\Log\TriggerInterface;
use EasySwoole\EasySwoole\AbstractInterface\Log\TriggerLocation;
use EasySwoole\EasySwoole\Logger;

class AlertTrigger implements TriggerInterface
{
    public function error(
        mixed $msg,
        int $errorCode = E_USER_ERROR,
        ?TriggerLocation $location = null
    ): void {
        $message = is_scalar($msg) || $msg === null
            ? (string) $msg
            : print_r($msg, true);

        $file = $location?->getFile() ?? 'unknown';
        $line = $location?->getLine() ?? 0;
        $level = $this->errorLevel($errorCode);

        Logger::getInstance()->log(
            "{$message} at file:{$file} line:{$line}",
            $level,
            'trigger'
        );

        if ($level === LogLevelEnum::ERROR) {
            $this->sendAlert("PHP error: {$message}");
        }
    }

    public function throwable(
        \Throwable $throwable,
        ?string $category = null
    ): void {
        $message = sprintf(
            '%s at file:%s line:%d',
            $throwable->getMessage(),
            $throwable->getFile(),
            $throwable->getLine()
        );

        Logger::getInstance()->error(
            $message,
            $category ?? 'trigger'
        );

        $this->sendAlert("Unhandled throwable: {$message}");
    }

    private function errorLevel(int $errorCode): LogLevelEnum
    {
        return match ($errorCode) {
            E_PARSE,
            E_ERROR,
            E_CORE_ERROR,
            E_COMPILE_ERROR,
            E_USER_ERROR => LogLevelEnum::ERROR,

            E_WARNING,
            E_USER_WARNING,
            E_COMPILE_WARNING,
            E_RECOVERABLE_ERROR => LogLevelEnum::WARNING,

            E_NOTICE,
            E_USER_NOTICE,
            E_DEPRECATED,
            E_USER_DEPRECATED => LogLevelEnum::NOTICE,

            default => LogLevelEnum::INFO,
        };
    }

    private function sendAlert(string $message): void
    {
        try {
            // AlarmService::send($message);
        } catch (\Throwable $alertError) {
            // 不要再次调用 Trigger，否则可能形成递归。
            Logger::getInstance()->error(
                '发送错误告警失败：' . $alertError->getMessage(),
                'alert'
            );
        }
    }
}
```

自定义 Trigger 中可以调用 `Logger`，但不要再次调用 `Trigger::error()` 或 `Trigger::throwable()`，否则会重新进入当前 Trigger，形成无限递归。

### 注册自定义 Trigger

在 `EasySwooleEvent.php` 的 `initialize()` 中通过 DI 注册：

```php
use App\Log\AlertTrigger;
use EasySwoole\Component\Di;
use EasySwoole\EasySwoole\SysConst;

public static function initialize()
{
    Di::getInstance()->set(
        SysConst::TRIGGER_HANDLER,
        new AlertTrigger()
    );
}
```

框架会在 `EasySwooleEvent::initialize()` 返回后读取 `TRIGGER_HANDLER`，然后创建全局 `Trigger` 单例。不要在 `initialize()` 中提前调用 `Trigger::getInstance()`，否则自定义处理器可能尚未完成初始化。

如果同时使用自定义 Logger 和自定义 Trigger，可以在同一个 `initialize()` 中注册：

```php
public static function initialize()
{
    $di = Di::getInstance();

    $di->set(
        SysConst::LOGGER_HANDLER,
        new JsonLogger(EASYSWOOLE_LOG_DIR . '/application.json.log')
    );

    $di->set(
        SysConst::TRIGGER_HANDLER,
        new AlertTrigger()
    );
}
```

Logger 和 Trigger 会在 `initialize()` 结束后按框架流程完成创建，因此 `AlertTrigger` 真正处理错误时可以正常调用 `Logger::getInstance()`。

### 自定义 Trigger 还是监听回调

| 需求 | 推荐方式 |
| --- | --- |
| 保留默认日志，只额外发送告警 | `setOnError()` / `setOnThrowable()` |
| 完全改变错误格式、级别映射或输出目标 | 实现 `TriggerInterface` |
| 只更改日志文件格式或保存位置 | 实现 `LoggerInterface` |
| 同时改变异常处理和日志存储 | 同时注册自定义 Trigger 与 Logger |

自定义 Trigger 是全局错误入口。实现中应保证稳定、快速，并捕获告警服务自身的异常；否则错误处理器再次失败，会让原始问题更难排查。

## Logger 与 Trigger 怎么选

| 场景 | 推荐方式 |
| --- | --- |
| 记录正常业务步骤 | `Logger::info()` |
| 记录需要关注但不影响流程的问题 | `Logger::notice()` 或 `warning()` |
| 记录明确的业务失败 | `Logger::error()` |
| 报告 PHP 风格错误并保留位置 | `Trigger::error()` |
| 报告捕获到的异常 | `Trigger::throwable()` |
| 改变日志保存格式或目标 | 实现 `LoggerInterface` |
| 接入异常告警但保留默认日志 | `setOnError()` / `setOnThrowable()` |

## 使用注意事项

- 不要记录密码、Token、Cookie、身份证号或完整银行卡号。
- 日志应包含可检索的业务标识，如 request ID、order ID，但不要把高基数字段作为 category。
- `ignoreCategory` 会直接丢弃匹配分类的日志，修改前确认不会屏蔽故障信息。
- `logLevels` 是允许列表，生产配置只保留高等级时，INFO 日志不会写入文件。
- 捕获并重新抛出的异常要避免在多层重复记录。
- 日志目录必须存在且运行用户可写；磁盘写满时默认 Logger 无法保证日志成功保存。
- 高频日志会增加文件 I/O，应控制循环、心跳和成功请求日志的数量。

## 源码依据

- [Logger](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Logger.php)
- [Trigger](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Trigger.php)
- [DefaultLogger](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Utility/DefaultLogger.php)
- [DefaultTrigger](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Utility/DefaultTrigger.php)
- [TriggerInterface](https://github.com/easy-swoole/easyswoole/blob/3.x/src/AbstractInterface/Log/TriggerInterface.php)
