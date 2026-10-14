# 自定义命令

EasySwoole 的命令系统支持注册自己的 Command、Action 和 Option。例如，我们可以实现下面的调用：

```bash
php easyswoole.php myCommand run --name=EasySwoole --times=2 --force
```

这条命令可以拆成：

```text
php easyswoole.php myCommand run --name=EasySwoole --times=2 --force
                     │       │         │              │       │
                     │       │         │              │       └─ 无值 Option
                     │       │         │              └───────── 有值 Option
                     │       │         └──────────────────────── 有值 Option
                     │       └─────────────────────────────────── Action
                     └─────────────────────────────────────────── Command
```

项目入口文件如果命名为 `easyswoole`，对应命令就是：

```bash
php easyswoole myCommand run --name=EasySwoole --times=2 --force
```

## 创建命令类

新建 `App/Command/MyCommand.php`：

```php
<?php

namespace App\Command;

use EasySwoole\Command\AbstractInterface\AbstractCommand;
use EasySwoole\Command\Bean\Action;
use EasySwoole\Command\Bean\Caller;
use EasySwoole\Command\Bean\Option;
use EasySwoole\Command\Bean\Result;

class MyCommand extends AbstractCommand
{
    public function name(): string
    {
        // 调用命令中的第一个名称：myCommand
        return 'myCommand';
    }

    public function description(): string
    {
        return '项目自定义示例命令';
    }

    protected function init(): void
    {
        $action = new Action('run', '执行自定义任务');

        $action->addOption(new class('name', '要输出的名称，例如 --name=EasySwoole') extends Option {
            public static function validate(mixed $value, Caller $caller): bool|string
            {
                if (!is_string($value) || trim($value) === '') {
                    return '请使用 --name=名称 指定非空名称';
                }

                return true;
            }
        });

        $action->addOption(new class('times', '输出次数，例如 --times=2') extends Option {
            public static function validate(mixed $value, Caller $caller): bool|string
            {
                if (
                    filter_var($value, FILTER_VALIDATE_INT) === false
                    || (int) $value < 1
                    || (int) $value > 10
                ) {
                    return '--times 必须是 1 到 10 之间的整数';
                }

                return true;
            }
        });

        // force 是无值开关，使用 --force 即表示开启。
        $action->addOption(new Option('force', '是否强制执行'));

        $action->setCallback(function (Caller $caller, Result $result): void {
            $name = (string) $caller->commandLine->getOption('name');
            $times = (int) $caller->commandLine->getOption('times');
            $force = $caller->commandLine->hasOption('force');

            $lines = [];

            for ($index = 1; $index <= $times; $index++) {
                $lines[] = "{$index}. Hello {$name}";
            }

            if ($force) {
                $lines[] = 'force option enabled';
            }

            // 入口文件会在命令成功时输出 Result::$msg。
            $result->result = [
                'name' => $name,
                'times' => $times,
                'force' => $force,
            ];
            $result->msg = implode(PHP_EOL, $lines);
        });

        $this->registerAction($action);
    }
}
```

`init()` 在命令对象创建时执行，用于注册 Action、参数、Option 和最终回调。回调中的 `$result->result` 可以保存结构化结果，`$result->msg` 用于向终端输出文本。

## 注册自定义命令

项目根目录的 `easyswoole.php` 会在运行命令前自动加载 `bootstrap.php`。编辑项目根目录的 `bootstrap.php`：

```php
<?php

use App\Command\MyCommand;
use EasySwoole\EasySwoole\Command\CommandRunner;

CommandRunner::getInstance()->addCommand(new MyCommand());
```

不要在 `EasySwooleEvent::initialize()` 或 `mainServerCreate()` 中注册命令。自定义命令的解析发生在服务器启动流程之前，而 `bootstrap.php` 会在创建 `CommandRunner` 前被入口加载。

命令名称必须唯一。如果自定义命令和内置命令同名，后注册的命令会覆盖已有命令，因此不要使用 `server`、`process`、`crontab` 或 `install` 等内置名称。

## 执行命令

在项目根目录运行：

```bash
php easyswoole.php myCommand run --name=EasySwoole --times=2
```

输出示例：

```text
1. Hello EasySwoole
2. Hello EasySwoole
```

增加无值开关：

```bash
php easyswoole.php myCommand run --name=EasySwoole --times=2 --force
```

也可以按照单横线形式调用：

```bash
php easyswoole.php myCommand run -name=EasySwoole -times=2 -force
```

框架解析 Option 时会去除开头的 `-`，因此 `-force` 和 `--force` 都能被解析。为了和常见 CLI 规范保持一致，文档和脚本建议统一使用双横线：

```bash
--force
--name=EasySwoole
```

Option 的值必须写在同一个参数中：

```bash
# 正确
--name=EasySwoole

# 错误：EasySwoole 会被当成无法识别的普通参数
--name EasySwoole
```

## Command、Action 和 Option

一个 Command 可以注册多个 Action：

```text
myCommand
├── run
│   ├── --name=EasySwoole
│   ├── --times=2
│   └── --force
├── status
└── clear
```

例如，在同一个 `init()` 中继续注册 `status`：

```php
$status = new Action('status', '查看执行状态');

$status->setCallback(function (Caller $caller, Result $result): void {
    $result->msg = 'command is ready';
});

$this->registerAction($status);
```

对应调用为：

```bash
php easyswoole.php myCommand status
```

直接运行 Command 而不指定有效 Action 时，框架会列出它支持的 Action 和 Option：

```bash
php easyswoole.php myCommand
```

## 有值 Option 和无值 Option

有值 Option 使用 `getOption()` 读取：

```php
$name = $caller->commandLine->getOption('name');
```

无值开关使用 `hasOption()` 判断是否出现：

```php
$force = $caller->commandLine->hasOption('force');
```

未提供 `--force` 时，`getOption('force')` 和 `hasOption('force')` 的结果分别是 `null` 和 `false`；提供 `--force` 后，结果分别是 `null` 和 `true`。因此无值开关不能只依靠 `getOption()` 判断。

同一个 Option 重复出现时，后面的值会覆盖前面的值：

```bash
php easyswoole.php myCommand run --name=first --name=second --times=1
```

最终读取到的 `name` 是 `second`。

## 普通命名参数

除了以 `-` 开头的 Option，命令系统还支持 `参数名=值` 形式的 Param。先在 Action 中注册：

```php
use EasySwoole\Command\Bean\Param;

$action->addParam(new class('target', '处理目标，例如 target=users') extends Param {
    public static function validate(mixed $value, Caller $caller): bool|string
    {
        return in_array($value, ['users', 'orders'], true)
            ? true
            : 'target 只允许 users 或 orders';
    }
});
```

在回调中读取：

```php
$target = $caller->commandLine->getParam('target');
```

调用方式：

```bash
php easyswoole.php myCommand run target=users --name=EasySwoole --times=1
```

`target=users` 是 Param，`--name=EasySwoole` 是 Option，两者不要混淆。

## 返回执行失败

参数校验失败时，Option 或 Param 的 `validate()` 返回错误文本即可。如果回调已经开始执行，但业务处理失败，应设置失败状态：

```php
use EasySwoole\Command\Bean\ExecStatusEnum;

$action->setCallback(function (Caller $caller, Result $result): void {
    try {
        // 执行业务操作。
    } catch (\Throwable $throwable) {
        $result->status = ExecStatusEnum::COMMAND_ACTION_EXEC_FAIL;
        $result->msg = $throwable->getMessage();
    }
});
```

入口会根据执行状态生成失败提示。命令会直接操作数据库、文件或远程服务时，应该把异常转换为明确的错误状态，部署脚本也应检查进程退出结果和业务输出。

## 在命令中加载框架配置

普通自定义命令不会自动加载 `dev.php` 或 `produce.php`。命令需要读取 EasySwoole 配置时，可以注册 `--mode`，并在 `beforeExecute()` 中初始化框架：

```php
use EasySwoole\Command\Bean\Caller;
use EasySwoole\Command\Bean\Result;
use EasySwoole\EasySwoole\Core;

public function beforeExecute(Caller $caller, Result $result): bool
{
    $mode = $caller->commandLine->getOption('mode');
    Core::getInstance()->initialize($mode);

    return true;
}
```

还要为每个需要运行模式的 Action 添加 Option：

```php
$action->addOption(new Option('mode', '运行模式，例如 --mode=produce'));
```

然后执行：

```bash
php easyswoole.php myCommand run \
    --name=EasySwoole \
    --times=1 \
    --mode=produce
```

如果命令不需要框架配置、日志目录或运行模式，不要为了一个简单脚本初始化整个 EasySwoole Core。

## 使用注意事项

- 自定义命令在 CLI 进程中执行，不是在 HTTP Worker 中执行。
- 命令执行结束后进程退出，内存状态不会保留到下一次调用。
- 长时间运行的命令应输出进度并处理 `SIGTERM`，不要让部署脚本无限等待。
- 破坏性操作应增加明确的 `--force` 或确认参数，并在执行前再次校验目标。
- 密码、Token 等敏感信息不应直接放在命令行中，因为它们可能出现在 Shell 历史和系统进程列表中。
- 需要周期执行命令时，可以由 systemd timer、Linux crontab 或 CI 调度；需要跟随 EasySwoole 服务运行的任务可使用框架 [Crontab](/Advanced/crontab.md)。

## 源码依据

- [EasySwoole Command](https://github.com/easy-swoole/command)
- [CommandRunner](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Command/CommandRunner.php)
- [命令入口](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Resource/easyswoole)
