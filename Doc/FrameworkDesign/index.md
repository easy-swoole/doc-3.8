# 启动流程总览

本章从源码角度解释执行下面这条命令后，EasySwoole 如何解析命令、初始化框架、注册事件并最终启动 Swoole 服务：

```bash
php easyswoole.php server start --mode=produce
```

理解这条链路后，就能判断代码应该放在 `bootstrap.php`、`EasySwooleEvent::initialize()`、`mainServerCreate()` 还是 Worker 启动事件中，也更容易定位“配置为什么没有生效”“事件为什么没有触发”等问题。

## 核心文件

| 文件或类 | 作用 |
| --- | --- |
| 项目根目录 `easyswoole.php` | CLI 入口，加载 Composer、解析参数并执行命令 |
| `CommandRunner` | 注册框架内置命令并分发到对应 Command |
| `DefaultCommand\Server` | 定义 `server start/stop/reload/status` |
| `Core` | 加载配置、执行项目初始化、创建服务器和注册默认能力 |
| 项目根目录 `EasySwooleEvent.php` | 项目级初始化和服务事件注册入口 |
| `ServerManager` | 保存 Swoole Server、汇总事件并调用 `start()` |
| `EventRegister` | 暂存项目注册的 Swoole 事件回调 |

## 完整调用顺序

```text
easyswoole.php
│
├─ 查找并加载 vendor/autoload.php
├─ 定义 EASYSWOOLE_ROOT 等常量
├─ 加载 bootstrap.php（如果存在）
├─ Utility::parseArgv($argv)
├─ 构造 Caller(command=server, action=start)
└─ CommandRunner::exec($caller)
   │
   ├─ 找到 Server 命令和 start Action
   ├─ Server::beforeExecute()
   │  └─ Core::initialize('produce')
   │     ├─ 加载 produce.php
   │     ├─ 初始化 Temp、Log 和 PID 文件路径
   │     ├─ EasySwooleEvent::initialize()
   │     └─ 注册错误和 shutdown 处理器
   │
   └─ 执行 start Action
      ├─ 处理 -d 和运行用户配置
      ├─ Core::createServer()
      │  ├─ 创建 Swoole Server 并调用 set($setting)
      │  ├─ EasySwooleEvent::mainServerCreate($register)
      │  ├─ 注册框架默认 HTTP、Worker 等回调
      │  └─ 挂载 Task、Process、Bridge、Crontab
      │
      └─ Core::start()
         ├─ 设置主进程名称
         └─ ServerManager::start()
            ├─ 将 EventRegister 中的回调绑定到 Swoole
            └─ Swoole\Server::start()
```

## 三个最容易混淆的扩展位置

### `bootstrap.php`

入口脚本加载 Composer 后、解析命令前执行。它不仅会影响 `server start`，也会影响 `install`、`server stop` 等其他 CLI 命令。

适合放置非常早期且所有命令都需要的引导逻辑。不要在这里连接数据库、启动定时器或执行耗时业务。

### `EasySwooleEvent::initialize()`

`Core::initialize()` 加载运行模式配置并初始化目录后调用。此时还没有创建 Swoole Server。

适合设置时区、协程全局选项、依赖注入、日志处理器等不依赖 Server 对象的内容：

```php
public static function initialize()
{
    date_default_timezone_set('Asia/Shanghai');
    \Swoole\Coroutine::set([
        'hook_flags' => SWOOLE_HOOK_TCP,
    ]);
}
```

### `EasySwooleEvent::mainServerCreate()`

Swoole Server 已创建且已应用 `MAIN_SERVER.SETTING`，但尚未调用 `start()`。框架把 `EventRegister` 传给项目代码，用它注册 Worker、连接和 WebSocket 等服务事件。

```php
public static function mainServerCreate(EventRegister $register)
{
    $register->add(EventRegister::onWorkerStart, function ($server, int $workerId) {
        // 每个 Worker 启动后执行
    });
}
```

## 主进程与 Worker 的区别

启动阶段的代码不一定只执行一次：

| 位置 | 主要执行进程 | 典型用途 |
| --- | --- | --- |
| `bootstrap.php` | 启动命令的 PHP 进程 | 早期引导 |
| `initialize()` | Swoole 启动前 | 全局配置和依赖注册 |
| `mainServerCreate()` | Swoole 启动前 | 向 Server 注册事件 |
| `onStart` | Master | 主进程启动后的操作 |
| `onManagerStart` | Manager | Manager 进程初始化 |
| `onWorkerStart` | 每个 Worker/TaskWorker | 创建进程内连接池、加载 Worker 资源 |
| `onRequest` | Worker | 处理每个 HTTP 请求 |

例如在 `onWorkerStart` 中创建连接池，会为每个 Worker 分别创建一份；在 `onRequest` 中创建则会按请求重复创建。设计资源初始化位置时，必须先确认所处进程和触发次数。

接下来的章节会分别展开命令解析、事件注册和服务启动内部流程。

## 源码依据

- [CLI 入口模板](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Resource/easyswoole)
- [Core](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Core.php)
- [Server 命令](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Command/DefaultCommand/Server.php)
- [ServerManager](https://github.com/easy-swoole/easyswoole/blob/3.x/src/ServerManager.php)
