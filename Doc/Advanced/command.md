# 自定义命令

EasySwoole 3.8.2 使用 `easyswoole/command` 3.x。自定义命令实现 `CommandInterface`，用 `CommandDefinition` 声明命令及操作，用 `execute()` 读取已解析的输入并返回 `CommandResult`。

## 定义命令

新建 `App/Command/GreetCommand.php`。示例提供 `run` 和 `status` 两个 Action。`run` 接收一个位置参数、一个整数选项和一个布尔开关。

```php
<?php

namespace App\Command;

use EasySwoole\Command\Console\Console;
use EasySwoole\Command\Contracts\CommandInterface;
use EasySwoole\Command\Definition\ActionDefinition;
use EasySwoole\Command\Definition\Argument;
use EasySwoole\Command\Definition\CommandDefinition;
use EasySwoole\Command\Definition\Option;
use EasySwoole\Command\Input\Input;
use EasySwoole\Command\Result\CommandResult;
use EasySwoole\Command\Validation\Rules;

final class GreetCommand implements CommandInterface
{
    public static function createDefinition(): CommandDefinition
    {
        return CommandDefinition::create('greet')
            ->description('输出问候语')
            ->action(
                ActionDefinition::create('run')
                    ->description('按指定次数输出问候语')
                    ->argument(
                        Argument::string('name', '称呼', required: true)
                            ->validate(Rules::notBlank('称呼不能为空'))
                    )
                    ->option(
                        Option::integer('times', '输出次数', default: 1)
                            ->validate(Rules::range(1, 10, '输出次数必须在 1 到 10 之间'))
                    )
                    ->option(Option::flag('numbered', '显示行号'))
            )
            ->action(ActionDefinition::create('status')->description('查看命令状态'));
    }

    public function definition(): CommandDefinition
    {
        return self::createDefinition();
    }

    public function execute(Input $input, Console $console): CommandResult
    {
        return match ($input->action()) {
            'run' => $this->greet($input),
            'status' => CommandResult::success('命令已就绪'),
            default => throw new \LogicException('未知操作'),
        };
    }

    private function greet(Input $input): CommandResult
    {
        $name = $input->argument('name');
        $times = $input->option('times');
        $numbered = $input->option('numbered');
        $lines = [];

        for ($index = 1; $index <= $times; $index++) {
            $prefix = $numbered ? "{$index}. " : '';
            $lines[] = "{$prefix}Hello {$name}";
        }

        return CommandResult::success(implode(PHP_EOL, $lines));
    }
}
```

有 Action 的命令把输入定义放在各自的 `ActionDefinition` 上。`install` 一类独立命令直接在 `CommandDefinition` 上声明输入，此时 `$input->action()` 返回 `null`。参数类型转换和校验在 `execute()` 之前完成。

## 在 bootstrap.php 中注册

在项目根目录的 `bootstrap.php` 中注册命令。管理脚本会先加载这个文件，然后才解析和执行命令。

```php
use App\Command\GreetCommand;
use EasySwoole\EasySwoole\Command\CommandRunner;

CommandRunner::getInstance()->addCommand(new GreetCommand());
```

命令名称必须唯一。注册同名命令会报错，框架内置名称包括 `install`、`server`、`process`、`task` 和 `crontab`。

## 执行与查看帮助

```bash
php easyswoole.php greet run EasySwoole --times=2 --numbered
php easyswoole.php greet status
php easyswoole.php greet run --help
```

第一条命令输出两行带行号的问候语。`EasySwoole` 是位置参数 `name`，`--times=2` 是整数选项，`--numbered` 是布尔开关。也可以写成 `--numbered=true` 或 `--numbered=false`。

执行成功使用 `CommandResult::success($message)`。业务失败可返回 `CommandResult::failure($message)`。管理脚本以退出码 `0` 表示成功，`1` 表示执行失败，`2` 表示参数错误。失败消息输出到 stderr。

## 按需加载框架配置

命令需要框架环境时，在对应的 Action 定义上添加以下设置。独立命令可以直接在 `CommandDefinition` 上设置。

```php
$action
    ->option(Option::string('mode', '运行模式，例如 --mode=produce'))
    ->metadata('runtime', true);
```

例如，将这两项加到上面 `run` 的定义末尾，即可用 `php easyswoole.php greet run EasySwoole --mode=produce` 加载 `produce.php` 后再执行。框架在输入校验通过后初始化 Core。命令在当前 CLI 进程中执行。

## 通过 Provider 注册

组件可以实现 `CommandProviderInterface`，将命令定义和实例工厂交给注册表。工厂在执行时才创建命令对象，适合有业务依赖的命令。

```php
<?php

namespace App\Command;

use EasySwoole\Command\CommandRegistry;
use EasySwoole\Command\Contracts\CommandProviderInterface;

final class AppCommandProvider implements CommandProviderInterface
{
    public function register(CommandRegistry $registry): void
    {
        $registry->register(
            GreetCommand::createDefinition(),
            static fn () => new GreetCommand()
        );
    }
}
```

将类保存为 `App/Command/AppCommandProvider.php`。在 `bootstrap.php` 中通过 `addProvider()` 注册这个 Provider。

```php
use App\Command\AppCommandProvider;
use EasySwoole\EasySwoole\Command\CommandRunner;

CommandRunner::getInstance()->addProvider(new AppCommandProvider());
```

同一个命令只注册一次。执行此 Provider 示例时，移除上面的 `addCommand(new GreetCommand())`。

## 源码依据

- [`easyswoole/easyswoole` 3.8.2 · GitHub](https://github.com/easy-swoole/easyswoole/tree/3.8.2)
- [`easyswoole/command` 3.0.1 · GitHub](https://github.com/easy-swoole/command/tree/3.0.1)

- [框架命令接入说明（3.8.2）](https://github.com/easy-swoole/easyswoole/blob/3.8.2/docs/command-3.x.md)
- [CommandRunner（3.8.2）](https://github.com/easy-swoole/easyswoole/blob/3.8.2/src/Command/CommandRunner.php)
- [Command 3.0.1](https://github.com/easy-swoole/command/tree/3.0.1)
