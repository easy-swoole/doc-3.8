# 服务创建与启动

命令完成初始化后，`server start` Action 执行：

```php
Core::getInstance()->createServer()->start();
```

这一行包含两个阶段：`createServer()` 负责创建对象和收集事件，`start()` 才真正启动进程与事件循环。

## `Core::createServer()`

首先读取运行模式配置中的 `MAIN_SERVER`：

```php
$conf = Config::getInstance()->getConf('MAIN_SERVER');

ServerManager::getInstance()->createSwooleServer(
    $conf['PORT'],
    $conf['SERVER_TYPE'],
    $conf['LISTEN_ADDRESS'],
    $conf['SETTING'],
    $conf['RUN_MODEL'],
    $conf['SOCK_TYPE']
);
```

配置与构造参数的对应关系是：

| 配置 | 用途 |
| --- | --- |
| `LISTEN_ADDRESS` | 监听地址，例如 `0.0.0.0` |
| `PORT` | 监听端口，例如 `9501` |
| `SERVER_TYPE` | TCP、HTTP 或 WebSocket Server 类型 |
| `RUN_MODEL` | Swoole 运行模式，通常是 `SWOOLE_PROCESS` |
| `SOCK_TYPE` | Socket 类型，通常是 `SWOOLE_TCP` |
| `SETTING` | 传给 Swoole Server `set()` 的配置 |

## Server 类型如何决定实例

`ServerManager::createSwooleServer()` 根据 `SERVER_TYPE` 创建不同的原生对象：

```text
EASYSWOOLE_SERVER
  → Swoole\Server

EASYSWOOLE_WEB_SERVER
  → Swoole\Http\Server

EASYSWOOLE_WEB_SOCKET_SERVER
  → Swoole\WebSocket\Server
```

创建成功后立即调用：

```php
$server->set($setting);
```

所以 `worker_num`、`max_conn`、`daemonize`、`pid_file` 等 `MAIN_SERVER.SETTING` 配置在事件注册之前就交给了 Swoole。

## createServer 后续步骤

原生 Server 创建完成后，`Core::createServer()` 继续执行：

```php
EasySwooleEvent::mainServerCreate(
    ServerManager::getInstance()->getEventRegister()
);

$this->registerDefaultCallBack($server, $serverType);
$this->extraHandler();
```

对应职责是：

1. 让项目注册自己的服务事件或增加子服务。
2. 注册框架的 HTTP 分发和 Worker 生命周期回调。
3. 把 Task、Process Manager、Bridge、Crontab 挂载到 Server。

这个阶段只是保存和组织回调，还没有开始监听端口，也不会处理请求。

## HTTP 默认回调如何建立

当类型是 HTTP 或 WebSocket Server 时，框架会初始化 `Dispatcher`，并为原生 `request` 事件注册默认逻辑：

```text
收到 Swoole HTTP 请求
  → 封装成 EasySwoole Request/Response
  → 执行 HTTP_GLOBAL_ON_REQUEST
  → Dispatcher::dispatch()
  → 路由与控制器 Action
  → 执行 HTTP_GLOBAL_AFTER_REQUEST
  → Response::__response() 发送结果
```

如果请求处理抛出异常，会进入 `HTTP_EXCEPTION_HANDLER`。如果没有配置自定义处理器，框架创建默认异常回调，写入 500 状态和错误信息，并交给 Trigger 记录。

这也是控制器只有在服务创建完成并接收到请求后才会被实例化的原因；控制器不参与 CLI 命令解析和主服务创建。

## `Core::start()`

服务器和事件准备完成后，`Core::start()` 做两件事：

```php
$serverName = Config::getInstance()->getConf('SERVER_NAME');
$this->setProcessName($serverName);

ServerManager::getInstance()->start();
```

先设置主进程名称，再交给 `ServerManager`。

## `ServerManager::start()`

`ServerManager` 将暂存在注册器里的回调真正绑定到 Swoole：

```text
读取主服务 EventRegister::all()
  → 对每种事件调用主 Server::on()
  → 包装器依次执行该事件的所有回调

读取每个子服务的 EventRegister::all()
  → 对子监听端口调用 Port::on()

标记 isStart = true
记录是否为 daemonize
调用 Swoole Server::start()
```

最后一行：

```php
$this->getSwooleServer()->start();
```

会进入 Swoole 自身的启动流程。在前台模式下，该调用会持续运行，直到服务收到退出信号或发生不可恢复的错误。

## 调用 `start()` 后创建哪些进程

以 `SWOOLE_PROCESS` 为例，可以概括为：

```text
Master
├─ Reactor 线程：接收连接、网络收发
└─ Manager
   ├─ Worker 0
   ├─ Worker 1
   ├─ ...
   └─ TaskWorker（配置后存在）
```

实际进程数量由 `worker_num`、`task_worker_num` 以及 EasySwoole Task 配置等共同决定。框架在默认 `workerStart` 回调中区分 Worker 与 TaskWorker，为其设置进程名，并记录进程信息和内存心跳。

## 启动后事件顺序

从应用观察角度，常见启动事件可简化为：

```text
Swoole Server::start()
  → onStart（Master）
  → onManagerStart（Manager，进程模式）
  → onWorkerStart（每个 Worker/TaskWorker）
  → 开始处理 onRequest/onReceive/onMessage 等业务事件
```

多个 Worker 的启动先后不应被业务代码当作严格顺序依赖。每个 Worker 都有独立的 PHP 内存空间，不能用普通全局变量在 Worker 之间共享状态。

## 平滑重载为什么不重新执行全部启动流程

执行：

```bash
php easyswoole.php server reload --mode=produce
```

`reload` 命令读取 PID 文件并向主进程发送 `SIGUSR1`。Swoole 会更新 Worker，但不会重新运行外部 CLI 入口来重建 Master。因此通常会重新执行新 Worker 中的 `onWorkerStart`，但不会重新执行用于创建主服务的完整 `createServer()` 链路。

以下修改通常需要完整重启：

- 监听地址和端口。
- `worker_num`、Server 类型等主服务配置。
- `mainServerCreate()` 中注册的主进程级事件或子监听端口。
- 只在 `initialize()` 或 Server 创建前读取的设置。

普通控制器和 Worker 内加载的业务代码通常可以通过平滑重载更新。

## 启动问题如何定位到阶段

```text
没有任何命令输出
  → 检查 PHP、Composer autoload、bootstrap.php、命令解析

提示配置文件或目录错误
  → 检查 Core::initialize()、运行模式、目录权限

显示启动环境后立即报错
  → 检查 createServer()、Swoole SETTING、mainServerCreate()

端口监听成功但 HTTP 500
  → 检查 request 默认回调、路由、控制器和异常日志

reload 后配置没有变化
  → 判断该配置是否需要完整 restart
```

可以配合下面的命令确认运行状态：

```bash
php easyswoole.php server status --mode=produce
sudo ss -lntp | grep ':9501'
pgrep -af 'EasySwoole|easyswoole'
tail -f Log/produce.swoole.log
```

使用 systemd 时，改用 `systemctl status` 和 `journalctl` 查看父进程退出原因，参见[使用 systemd 管理服务](/QuickStart/systemd.md)。

## 源码依据

- [Core](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Core.php)
- [ServerManager](https://github.com/easy-swoole/easyswoole/blob/3.x/src/ServerManager.php)
- [EventRegister](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Swoole/EventRegister.php)
- [Server 命令](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Command/DefaultCommand/Server.php)
