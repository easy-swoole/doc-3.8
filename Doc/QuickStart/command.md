# 基础管理命令

EasySwoole 的项目命令入口是根目录下的 `easyswoole.php`。

## 服务管理

```bash
# 前台启动，适合本地调试
php easyswoole.php server start

# 守护进程启动
php easyswoole.php server start -d

# 使用生产配置启动
php easyswoole.php server start -d --mode=produce

# 平滑重载 Worker
php easyswoole.php server reload

# 查看服务状态
php easyswoole.php server status

# 停止服务
php easyswoole.php server stop

# 强制停止
php easyswoole.php server stop --force
```

`reload` 向主进程发送 `SIGUSR1`，主要用于更新 Worker 中加载的业务代码。主进程级配置、监听端口和部分启动期资源发生变化时，应完整重启服务。

## 运行模式

`--mode=dev` 加载 `dev.php`，`--mode=produce` 加载 `produce.php`。PID 文件默认位于：

```text
Temp/dev.pid
Temp/produce.pid
```

日志文件也会按运行模式区分。停止命令依赖 PID 文件，因此前台进程异常退出后可能需要检查残留 PID。

## 查看帮助

```bash
php easyswoole.php
php easyswoole.php server
```

框架还注册了 `install`、`process`、`task` 和 `crontab` 等命令。服务、进程、异步任务和 Crontab 的完整管理方法参见[管理命令](/Advanced/ManagementCommand/server.md)。具体可用 Action 和 Option 应以当前命令输出为准。

## 部署注意

- 不要并行启动两套使用相同端口和 PID 文件的实例。
- 守护模式下路径必须使用绝对路径；框架默认将临时目录和日志目录转换为项目根目录下的绝对路径。
- 发布脚本应先检查 `server stop/reload` 的退出结果，而不是只判断命令是否执行。

## 源码依据

- [Server 命令](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Command/DefaultCommand/Server.php)
- [命令入口模板](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Resource/easyswoole)
