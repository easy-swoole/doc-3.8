# 管理命令：服务管理

EasySwoole 在项目根目录提供 `easyswoole.php` 命令入口。`server` 命令负责启动、停止、重载和查看当前服务状态。

```text
server
├── start     启动服务
├── stop      停止服务
├── reload    平滑重载 Worker
└── status    查看服务状态
```

## 运行模式

所有服务命令都应使用和启动时相同的运行模式：

```bash
# 使用 dev.php
php easyswoole.php server status --mode=dev

# 使用 produce.php
php easyswoole.php server status --mode=produce
```

省略 `--mode` 时使用框架默认模式。运行模式决定配置文件、PID 文件、日志目录和 Bridge 通信目标。服务以 `produce` 启动，却用 `dev` 执行管理命令，通常会读取到另一份 PID 或通信配置。

## 启动服务

前台启动适合本地调试：

```bash
php easyswoole.php server start
```

终端关闭后前台服务也会结束。生产环境可以使用守护模式：

```bash
php easyswoole.php server start -d --mode=produce
```

`-d` 是无值开关，框架会在本次启动时把 `MAIN_SERVER.SETTING.daemonize` 设为 `true`。启动过程会输出运行环境、监听地址、PID 文件、日志路径等信息，然后创建并启动 Swoole Server。

输出示例（开头的 EasySwoole Logo 已省略）：

```text
Environment
  main server           : SWOOLE_WEB     listen address        : 0.0.0.0
  listen port           : 9501           worker_num            : 8
  reload_async          : true           max_wait_time         : 3
  daemonize             : true           user                  : www
  swoole version        : 6.2.2          php version           : 8.4.23
  easyswoole version    : 3.8.1-dev      run mode              : produce
  pid_file              : /var/www/project/Temp/produce.pid
  log_file              : /var/www/project/Log/produce.swoole.log
  temp dir              : /var/www/project/Temp
  log dir               : /var/www/project/Log
```

同一端口不能重复启动。启动失败时先检查：

```bash
php --ri swoole
lsof -nP -iTCP:9501 -sTCP:LISTEN
tail -f Log/produce.swoole.log
```

如果服务由 systemd 管理，应使用 `systemctl start`，不要同时再手动启动一份守护进程。

## 查看服务状态

```bash
php easyswoole.php server status --mode=produce
```

命令通过框架 Bridge 向正在运行的服务查询信息，输出分为两部分：

- `Environment`：运行模式、PHP/Swoole 环境、目录及 PID/日志路径。
- `Runtime`：启动时间、连接数、请求量、Worker 状态等 Swoole 运行数据。

服务未启动、Bridge 不可达或运行模式错误时，状态查询会失败，而不是读取一份静态缓存。

实际输出类似：

```text
Server status

Environment
  main server           : SWOOLE_WEB     listen address        : 0.0.0.0
  listen port           : 9501           worker_num            : 8
  daemonize             : true           swoole version        : 6.2.2
  php version           : 8.4.23         easyswoole version    : 3.8.1-dev
  run mode              : dev
  pid_file              : /var/www/project/Temp/dev.pid
  log_file              : /var/www/project/Log/dev.swoole.log
  temp dir              : /var/www/project/Temp
  log dir               : /var/www/project/Log

Runtime
  start_time            : 2026-10-16 00:29:20    connection_num        : 0
  accept_count          : 2                      close_count           : 2
  worker_num            : 8                      user_worker_num       : 5
  idle_worker_num       : 8                      request_count         : 8
  response_count        : 8                      coroutine_num         : 2
```

字段数量会随 Swoole 版本变化，计数也会随请求实时增长。

### 持续刷新

`status` 支持 `--watch`：

```bash
# 默认每 2 秒刷新
php easyswoole.php server status --mode=produce --watch

# 每 1.5 秒刷新
php easyswoole.php server status --mode=produce --watch=1.5
```

按 `q`、`Esc` 或 `Ctrl+C` 退出。刷新间隔必须是大于 0 的数字。`--watch` 需要交互式终端，不适合重定向、后台脚本或不支持终端控制的 Windows 环境。

## 平滑重载

```bash
php easyswoole.php server reload --mode=produce
```

命令读取当前模式的 PID 文件，确认 Master 进程存在，然后向 Master 发送 `SIGUSR1`。Swoole 会替换服务 Worker，但不会重新创建 Master、监听端口、自定义进程或整个 Server。

普通控制器和 Worker 中加载的业务代码通常可以通过 `server reload` 更新。`easyswoole/task` 创建的 Task Worker 及其加载代码应使用 `task reload` 更新；监听端口、Worker 数量、Server 类型、`mainServerCreate()` 中的子服务和普通自定义进程发生变化时必须完整重启。详细原理参见[热重启](/Advanced/reload.md)。

命令提示信号已发送，仅表示 reload 已开始。发布脚本还应通过 `server status`、进程 PID、日志和健康检查确认新 Worker 已经就绪。

输出示例：

```text
send server reload command to pid:18848 at 2026-10-16 00:50:21
```

## 停止服务

正常停止：

```bash
php easyswoole.php server stop --mode=produce
```

框架向 Master 发送正常终止信号，并最多等待约 15 秒确认进程退出。正常停止可以让进程执行退出清理，应优先使用。

只有服务无法正常退出时才强制停止：

```bash
php easyswoole.php server stop --mode=produce --force
```

`--force` 使用 `SIGKILL`，进程没有机会执行 `finally`、shutdown function、连接释放或缓冲区刷新。不要把强制停止作为日常发布方式。

正常停止成功时输出：

```text
server stop for pid 18848 at 2026-10-16 00:55:08
```

若当前模式没有 PID 文件，则会输出：

```text
pid file does not exist, please check whether to run in the daemon mode!
```

PID 和时间只是示例，应以本机输出为准。

## 命令速查

| 目的 | 命令 |
| --- | --- |
| 前台启动 | `php easyswoole.php server start --mode=dev` |
| 守护启动 | `php easyswoole.php server start -d --mode=produce` |
| 查看状态 | `php easyswoole.php server status --mode=produce` |
| 持续观察 | `php easyswoole.php server status --mode=produce --watch=2` |
| 平滑重载 | `php easyswoole.php server reload --mode=produce` |
| 正常停止 | `php easyswoole.php server stop --mode=produce` |
| 强制停止 | `php easyswoole.php server stop --mode=produce --force` |

## 源码依据

- [Server 管理命令](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Command/DefaultCommand/Server.php)
- [Watch 终端刷新](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Command/Console/Watch.php)

下一章：[进程管理](/Advanced/ManagementCommand/process.md)。
