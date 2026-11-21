# 命令解析

EasySwoole 3.8.2 使用 `easyswoole/command` 3.x 处理命令定义、输入绑定、帮助和执行。以 `php easyswoole.php server start -d --mode=produce` 为例，`server` 是 Command，`start` 是 Action，`-d` 和 `--mode=produce` 是这个 Action 的选项。

## 入口脚本与命令注册

项目根目录的 `easyswoole.php` 加载 Composer 自动加载文件，定义 `IN_PHAR`、`RUNNING_ROOT` 和 `EASYSWOOLE_ROOT`，再加载项目的 `bootstrap.php`。脚本最后将命令行参数交给 Runner，并以返回值作为进程退出码。

```php
exit(CommandRunner::getInstance()->run(array_slice($argv, 1)));
```

`CommandRunner` 继承 `EasySwoole\Command\Application`，构造时通过 `DefaultCommandProvider` 注册 `install`、`server`、`process`、`task` 和 `crontab` 的定义与工厂。项目可在 `bootstrap.php` 中注册[自定义命令](/Advanced/command.md)。

## 从输入到 Action

1. 根据注册表定位命令和 Action，再绑定并校验输入。`-d` 绑定为布尔值，`--mode=produce` 绑定为字符串。只查看帮助或输入有误时，流程在此结束。
2. 执行中间件读取 Action 的 `runtime` 元数据，必要时回退到命令定义。启用后，以解析后的 `mode` 调用 `Core::initialize()`。支持 `--watch` 的 Action 也在这一层接入终端刷新。
3. `ServerCommand` 根据 `Input::action()` 分发给 `ServerStartAction`。执行结果以 `CommandResult` 表达，由应用输出消息并返回退出码。

## 运行模式如何传递

命令中的：

```bash
--mode=produce
```

会传给 `Core::initialize('produce')`，随后 `Core::loadEnv()` 加载：

```text
项目根目录/produce.php
```

未指定时通常使用 `dev`，并加载 `dev.php`。不同模式默认还对应不同 PID 文件：

```text
Temp/dev.pid
Temp/produce.pid
```

因此对生产服务执行管理命令时应保持模式一致：

```bash
php easyswoole.php server start -d --mode=produce
php easyswoole.php server reload --mode=produce
php easyswoole.php server stop --mode=produce
```

如果启动使用 `produce`，停止却没有指定模式，命令可能去读取 `dev` 的 PID 文件。

## start Action 做了什么

输入校验和运行环境初始化完成后，`ServerStartAction` 主要执行：

```php
defined('EASYSWOOLE_RUNNING') or define('EASYSWOOLE_RUNNING', true);

// -d 会写入 MAIN_SERVER.SETTING.daemonize
// MAIN_SERVER.SETTING.user 为空时填入当前用户
// 然后输出启动环境信息

Core::getInstance()->createServer()->start();
```

这里的链式调用可以拆开理解：

```php
$core = Core::getInstance();
$core->createServer(); // 创建 Server 并完成事件注册
$core->start();        // 真正进入 Swoole 事件循环
```

`createServer()` 返回的是 `Core` 自身，并不是 Swoole Server。

## `-d` 在哪里生效

`-d` 不由入口脚本直接处理。`start` Action 检测该 option 后，将：

```php
MAIN_SERVER.SETTING.daemonize = true
```

后续 `ServerManager::createSwooleServer()` 会把整个 `SETTING` 数组传给 Swoole 的 `set()`，最终由 Swoole 在启动时进入守护模式。

如果服务由 systemd 管理，不应使用 `-d`，具体参见[使用 systemd 管理服务](/QuickStart/systemd.md)。

## 排查命令问题

当服务尚未进入 Swoole 启动阶段就退出时，可以依次检查：

```bash
# 查看框架支持的命令
php easyswoole.php

# 查看 server 的 Action 和 option
php easyswoole.php server

# 确认生产配置文件存在且语法正确
php -l produce.php

# 确认入口文件和 Composer 自动加载可用
php easyswoole.php server start --mode=produce
```

如果连启动信息都没有输出，重点排查入口、自动加载、`bootstrap.php`、配置加载和 `initialize()`；如果启动信息已经输出，再排查服务器创建与事件注册阶段。

## 源码依据

- [`easyswoole/easyswoole` 3.8.2 · GitHub](https://github.com/easy-swoole/easyswoole/tree/3.8.2)

- [CLI 入口模板（3.8.2）](https://github.com/easy-swoole/easyswoole/blob/3.8.2/src/Resource/easyswoole)
- [CommandRunner（3.8.2）](https://github.com/easy-swoole/easyswoole/blob/3.8.2/src/Command/CommandRunner.php)
- [Server 命令（3.8.2）](https://github.com/easy-swoole/easyswoole/blob/3.8.2/src/Command/DefaultCommand/ServerCommand.php)
