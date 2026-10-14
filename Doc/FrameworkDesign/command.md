# 命令解析

EasySwoole 的启动不是直接在入口脚本中创建 HTTP Server，而是先进入通用命令系统。下面以命令为例逐项追踪：

```bash
php easyswoole.php server start -d --mode=produce
```

## 入口脚本做了什么

项目根目录的 `easyswoole.php` 依次执行：

1. 在几个候选位置查找 `vendor/autoload.php`。
2. 定义 `IN_PHAR`、`RUNNING_ROOT`、`EASYSWOOLE_ROOT`。
3. 如果项目根目录存在 `bootstrap.php`，则加载它。
4. 使用 `Utility::parseArgv($argv)` 解析命令行。
5. 取出命令名和 Action，构造 `Caller`。
6. 交给 `CommandRunner::exec()` 执行。
7. 输出成功消息，或把错误结果转换成帮助文本。

命令参数可以理解为：

```text
php easyswoole.php server start -d --mode=produce
                     │      │    │       │
                     │      │    │       └─ option: mode=produce
                     │      │    └───────── option: d
                     │      └────────────── action: start
                     └───────────────────── command: server
```

最终形成的调用信息近似于：

```php
$caller = new Caller('server', 'start', $commandLine);
$result = CommandRunner::getInstance()->exec($caller);
```

## CommandRunner 如何找到命令

`CommandRunner` 构造时注册框架内置命令：

```php
$this->addCommand(new Install());
$this->addCommand(new Server());
$this->addCommand(new Process());
$this->addCommand(new Crontab());
```

实例化每个 Command 时，其父类构造方法会调用 `init()`。以 `Server` 为例，`init()` 创建 `start`、`stop`、`reload`、`status` 等 Action，并为每个 Action 注册 option 和回调。

因此命令系统内部是三层结构：

```text
CommandRunner
└─ server                         Command
   ├─ start                      Action
   │  ├─ -d                     Option
   │  └─ --mode=produce         Option
   ├─ stop
   ├─ reload
   └─ status
```

如果命令或 Action 不存在，命令管理器不会进入服务器启动流程，而是返回对应错误状态，并由入口脚本显示帮助信息。

## `server start` 的执行顺序

命令管理器找到 Action 后，不会立刻执行启动回调。顺序是：

```text
CommandRunner::exec()
  → Command Manager 查找 command/action
  → Server::beforeExecute()
  → Action 参数和 option 校验
  → start Action callback
```

`Server::beforeExecute()` 会先执行：

```php
$mode = $caller->commandLine->getOption('mode');
Core::getInstance()->initialize($mode);
```

这意味着配置加载、目录初始化和 `EasySwooleEvent::initialize()` 都发生在 `start` Action 回调之前。`server stop`、`reload` 和 `status` 也会经过这个初始化步骤，因为它们需要得到对应运行模式的 PID、临时目录等配置。

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

通过前置初始化和参数校验后，`start` 回调主要执行：

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

- [CLI 入口模板](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Resource/easyswoole)
- [CommandRunner](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Command/CommandRunner.php)
- [Server 命令](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Command/DefaultCommand/Server.php)
