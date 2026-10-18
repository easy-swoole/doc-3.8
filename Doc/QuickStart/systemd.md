# 使用 systemd 管理服务

开发环境可以在终端中启动 EasySwoole，但生产环境通常需要解决下面的问题：

- 服务器重启后自动启动。
- 进程异常退出后自动恢复。
- 用统一的命令启动、停止、重启和查看状态。
- 明确运行用户、工作目录、文件描述符限制和日志位置。

Linux 上可以使用 systemd 管理 EasySwoole。本章以以下部署信息为例：

| 项目 | 示例值 |
| --- | --- |
| 项目目录 | `/var/www/easyswoole` |
| PHP 路径 | `/usr/bin/php` |
| 运行用户和用户组 | `www-data:www-data` |
| EasySwoole 模式 | `produce` |
| Unit 名称 | `easyswoole.service` |

请将这些值替换为服务器上的真实信息。

systemd 示例使用前台模式（不带 `-d`），不会因为守护化改变工作目录。但业务代码仍建议用 `EASYSWOOLE_ROOT`、`EASYSWOOLE_TEMP_DIR` 构造路径，不依赖 Unit 的 `WorkingDirectory`；原因和常量初始化时机见[开发者必读](/QuickStart/notice.md#文件路径不要依赖当前工作目录)。

## 部署前检查

首先进入项目目录，确认应用可以由目标用户正常启动：

```bash
cd /var/www/easyswoole
command -v php
sudo -u www-data /usr/bin/php easyswoole.php server start --mode=produce
```

看到服务成功启动后，按 `Ctrl+C` 结束测试。不要跳过这一步，否则 PHP 路径、扩展、配置文件或目录权限等问题会混进 systemd 配置问题中。

确保运行用户至少能够读取项目，并能写入应用实际使用的临时目录和日志目录。默认情况下通常需要检查：

```bash
sudo chown -R www-data:www-data /var/www/easyswoole/Temp
sudo chown -R www-data:www-data /var/www/easyswoole/Log
```

如果项目修改了 `TEMP_DIR`、`LOG.dir` 或日志组件配置，应以实际目录为准。不要为了省事把整个项目设置成 `777`。

## 创建 Unit 文件

创建 `/etc/systemd/system/easyswoole.service`：

```ini
[Unit]
Description=EasySwoole HTTP Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/var/www/easyswoole

ExecStart=/usr/bin/php /var/www/easyswoole/easyswoole.php server start --mode=produce
ExecReload=/bin/kill -USR1 $MAINPID

Restart=on-failure
RestartSec=3
TimeoutStopSec=30
KillSignal=SIGTERM

LimitNOFILE=200000

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

这里最重要的是：`ExecStart` 不要增加 `-d`。

```text
systemd
  └── EasySwoole/Swoole 主进程（前台运行，由 systemd 直接监控）
      ├── Manager
      ├── Worker
      └── TaskWorker
```

如果使用 `server start -d`，Swoole 会转入后台，启动命令很快退出，`Type=simple` 就无法准确表示服务是否仍在运行。既然已经交给 systemd 管理，就不再需要 EasySwoole 自己守护化。

### 配置项说明

- `WorkingDirectory`：保证相对路径从项目根目录解析。
- `User`、`Group`：避免服务以 root 身份长期运行。
- `--mode=produce`：加载项目的 `produce.php` 配置。
- `Restart=on-failure`：进程异常退出时重启，管理员正常停止时不会反复拉起。
- `ExecReload`：向 systemd 追踪的 Swoole 主进程发送 `SIGUSR1`，平滑重载 Worker。
- `TimeoutStopSec`：停止时给正在处理的请求一定退出时间。
- `LimitNOFILE`：设置服务进程的文件描述符限制，Worker 会继承该值。

`200000` 只是示例，不是所有服务器的固定推荐值。应结合 Swoole `max_conn`、Nginx 连接数、上游连接池和机器容量设置。更完整的估算与验证方式参见[性能优化](/Http/Advanced/performance.md#linux-文件描述符与-ulimit)。

## 加载并启动服务

Unit 文件创建或修改后，执行：

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now easyswoole
```

`enable` 设置开机启动，`--now` 表示立即启动。随后检查状态：

```bash
systemctl status easyswoole --no-pager
```

如果看到 `active (running)`，再验证 HTTP 服务：

```bash
curl -i http://127.0.0.1:9501/
```

服务显示正在运行不等于业务一定正常，因此需要同时执行一次真实 HTTP 请求。

## 日常管理命令

```bash
# 启动
sudo systemctl start easyswoole

# 停止
sudo systemctl stop easyswoole

# 完整重启，适用于主进程配置、端口等发生变化
sudo systemctl restart easyswoole

# 平滑重载 Worker，适用于多数业务代码更新
sudo systemctl reload easyswoole

# 查看状态
systemctl status easyswoole --no-pager

# 取消开机启动
sudo systemctl disable easyswoole
```

服务改由 systemd 管理后，日常运维应统一使用 `systemctl`。不要同时执行 `php easyswoole.php server start -d`，否则可能启动第二套进程，造成端口占用或 PID 文件混乱。

## 查看日志

查看当前启动以来的输出：

```bash
journalctl -u easyswoole -b
```

持续跟踪：

```bash
journalctl -u easyswoole -f
```

查看最近 100 行：

```bash
journalctl -u easyswoole -n 100 --no-pager
```

systemd Journal 主要保存进程的标准输出和标准错误。EasySwoole 或业务日志组件写入文件的日志仍应到项目配置的日志目录查看。

## 发布代码后的处理

只修改控制器、服务类等 Worker 中加载的 PHP 代码时，可以发布完成后执行：

```bash
sudo systemctl reload easyswoole
```

修改以下内容时更适合完整重启：

- 监听地址或端口。
- `worker_num`、`task_worker_num` 等进程配置。
- systemd Unit、环境变量或 PHP 配置。
- 在主进程启动阶段加载的资源和代码。

```bash
sudo systemctl restart easyswoole
```

修改 Unit 后还必须先执行 `sudo systemctl daemon-reload`。

## 配置环境变量

少量非敏感环境变量可以写在 Unit 中：

```ini
[Service]
Environment="APP_ENV=produce"
Environment="TZ=Asia/Shanghai"
```

变量较多时，可使用独立文件：

```ini
[Service]
EnvironmentFile=/etc/easyswoole/easyswoole.env
```

例如 `/etc/easyswoole/easyswoole.env`：

```text
APP_ENV=produce
TZ=Asia/Shanghai
```

限制该文件的读取权限，尤其不要让数据库密码、Token 等敏感值对所有系统用户可读：

```bash
sudo chown root:www-data /etc/easyswoole/easyswoole.env
sudo chmod 640 /etc/easyswoole/easyswoole.env
```

项目是否读取这些变量取决于应用自身的配置实现；systemd 只负责把它们传给 PHP 进程。

## 常见启动失败问题

### PHP 路径不正确

systemd 不会自动加载用户 Shell 中的 alias、`.bashrc`、`.zshrc` 或某些版本管理工具环境。先运行：

```bash
command -v php
/usr/bin/php -v
/usr/bin/php --ri swoole
```

然后在 `ExecStart` 中使用验证过的绝对路径。

### 目录没有写权限

日志中出现 `Permission denied` 时，检查 systemd 实际运行用户和目录权限：

```bash
systemctl show easyswoole -p User -p Group -p WorkingDirectory
namei -l /var/www/easyswoole/Temp
namei -l /var/www/easyswoole/Log
```

父目录也必须具有允许目标用户进入的执行权限。

### 端口已经被占用

```bash
sudo ss -lntp | grep ':9501'
pgrep -af 'easyswoole|EasySwoole'
```

确认是否曾经通过 `server start -d` 启动过另一套实例。停止旧进程后再交给 systemd，不要直接删除正在使用的 PID 文件。

### 服务不断重启

```bash
systemctl status easyswoole --no-pager
journalctl -u easyswoole -n 100 --no-pager
systemctl show easyswoole -p NRestarts -p ExecMainStatus
```

先看第一次启动失败的错误，而不是持续执行 `restart`。常见原因包括 PHP/Swoole 扩展缺失、生产配置语法错误、目录无权限和监听端口冲突。

### 修改 Unit 没有生效

```bash
sudo systemctl daemon-reload
sudo systemctl restart easyswoole
systemctl cat easyswoole
```

`systemctl cat` 可以显示 systemd 最终加载的主 Unit 和 override，便于排查编辑错文件的问题。

## 完整验证清单

部署完成后建议逐项确认：

```bash
# systemd 认为服务正常
systemctl is-active easyswoole
systemctl is-enabled easyswoole

# 主进程和子进程存在
systemctl status easyswoole --no-pager

# 监听端口正确
sudo ss -lntp | grep ':9501'

# HTTP 请求成功
curl -i http://127.0.0.1:9501/

# 文件描述符限制已经传给主进程
MAIN_PID=$(systemctl show easyswoole -p MainPID --value)
grep 'Max open files' "/proc/${MAIN_PID}/limits"
```

最后可以在维护窗口执行一次服务器重启，确认服务能够自动启动，并再次进行 HTTP 健康检查。
