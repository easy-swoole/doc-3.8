# 性能优化

性能优化应从数据开始，而不是直接复制一组“高并发参数”。完整链路是：

```text
客户端
  → 网络和 Linux 内核
  → Nginx / 负载均衡
  → Swoole Reactor 与 Worker
  → EasySwoole 控制器
  → MySQL、Redis、第三方接口
```

任何一层饱和，继续增大另一层并发都可能让排队时间、内存和超时更加严重。

## 优化前先确定指标

至少记录：

- 吞吐量：RPS/QPS。
- 延迟：P50、P95、P99，而不只是平均值。
- 错误率：4xx、5xx、超时和连接失败。
- 并发连接数、活跃协程数、请求排队情况。
- Worker CPU、RSS 内存和进程重启次数。
- MySQL/Redis 连接池等待时间与慢查询。
- 外部 HTTP、DNS、磁盘和日志耗时。

优化目标应该类似“在 8 核 16GB 实例上，500 并发时 P99 小于 200ms、错误率低于 0.1%”，而不是笼统地追求“最大并发”。

## Linux 文件描述符与 `ulimit`

每个客户端 Socket、Nginx 到 EasySwoole 的上游连接、MySQL/Redis 连接、日志文件和普通文件都会消耗文件描述符。文件描述符不足时，程序通常会出现 `Too many open files`、无法接受新连接或无法打开日志等问题。

### 先理解软限制和硬限制

查看当前 Shell 的限制：

```bash
ulimit -Sn  # soft nofile：当前实际采用的限制
ulimit -Hn  # hard nofile：普通用户可设置的上限
```

软限制可以在不超过硬限制的前提下调整；普通用户不能把硬限制提高到系统允许值以上。`ulimit` 不是全局配置，它只影响当前 Shell 以及从该 Shell 启动的子进程：

```text
当前 Shell 的 ulimit
        ↓ 继承
php easyswoole server start
        ↓ 继承
EasySwoole Master → Manager → Worker/TaskWorker
```

因此，在终端 A 执行 `ulimit -n 200000`，不会改变终端 B、已经运行的 EasySwoole，或由 systemd 启动的服务。

### 临时调整并启动服务

适合开发环境或临时压测：

```bash
ulimit -n 200000
ulimit -Sn
php easyswoole server start
```

如果出现 `ulimit: open files: cannot modify limit: Operation not permitted`，通常表示目标值超过当前硬限制。此时不要反复执行命令，应配置 PAM limits、systemd 或容器运行参数。

也可以在启动脚本中设置，但必须确保该脚本就是 EasySwoole 进程的父进程：

```bash
#!/usr/bin/env bash
set -e

ulimit -n 200000
exec php /var/www/app/easyswoole server start
```

`exec` 会让 PHP 进程替换当前脚本进程，便于服务管理器正确跟踪 PID 和退出状态。

### 使用 systemd 永久配置

生产环境如果由 systemd 启动，Shell 的 `ulimit` 和 `/etc/security/limits.conf` 通常不会决定服务限制，应直接为 Unit 设置 `LimitNOFILE`。推荐用 override，避免升级服务文件时覆盖自定义配置：

```bash
sudo systemctl edit easyswoole
```

填写：

```ini
[Service]
LimitNOFILE=200000
```

应用并重启服务：

```bash
sudo systemctl daemon-reload
sudo systemctl restart easyswoole
```

查看 systemd 已加载的配置以及运行进程真正获得的限制：

```bash
systemctl show easyswoole -p LimitNOFILE -p MainPID

MAIN_PID=$(systemctl show easyswoole -p MainPID --value)
cat "/proc/${MAIN_PID}/limits" | grep 'Max open files'
```

不要只在 SSH 终端执行 `ulimit -n` 后就认为 systemd 服务也已生效。

### 配置登录用户的 PAM limits

如果通过 SSH 登录后手动启动 EasySwoole，可新建：

```ini
# /etc/security/limits.d/99-easyswoole.conf
www-data soft nofile 200000
www-data hard nofile 200000
```

将 `www-data` 替换为实际启动服务的用户。修改后需要退出并重新登录，再执行：

```bash
ulimit -Sn
ulimit -Hn
```

该方式依赖登录会话经过 PAM limits 模块，不会自动修改已经存在的会话，也不应拿来替代 systemd Unit 的 `LimitNOFILE`。

### 系统级上限

除了单个进程的 `nofile`，Linux 还有系统级约束：

```bash
sysctl fs.file-max   # 整个系统可分配的文件句柄数量
sysctl fs.nr_open    # 单进程 nofile 可设置的内核上限
cat /proc/sys/fs/file-nr
```

只有系统级文件句柄确实接近耗尽时，才需要提高 `fs.file-max`。如果 `LimitNOFILE` 超过 `fs.nr_open`，还需要评估并调整 `fs.nr_open`。示例配置：

```ini
# /etc/sysctl.d/99-easyswoole.conf
fs.file-max = 1000000
fs.nr_open = 1000000
```

```bash
sudo sysctl --system
```

这些值不是固定推荐值，应根据实例内存、服务数量和连接预算决定。

### 如何估算和验证

`nofile` 不能只等于 Swoole 的 `max_conn`，因为程序还需要访问上游和文件。可以先按下面的思路做容量预算：

```text
nofile 下限
≈ 客户端最大连接数
 + MySQL/Redis/HTTP 客户端连接数
 + 日志、静态文件和监听 Socket
 + 20%～30% 安全余量
```

例如计划承载 50,000 个长连接，并预留 10,000 个上游连接和其他句柄，可把 80,000 作为压测起点，而不是不加分析地设置为 1,000,000。

服务启动后，找到实际 Master/Worker PID 并验证：

```bash
pgrep -af 'easyswoole|EasySwoole'
cat /proc/<PID>/limits | grep 'Max open files'
ls "/proc/<PID>/fd" | wc -l
lsof -p <PID> | wc -l
```

`/proc/<PID>/fd` 反映该进程当前打开的描述符数量。Swoole 使用多进程模型，应同时观察 Master、Manager、Worker 和 TaskWorker，而不是随意取第一个 PHP 进程。最终还要确认：

- `max_conn` 小于进程实际的软限制，并留出上游连接和文件余量。
- Nginx 自身的 `worker_rlimit_nofile`、systemd 限制和 `worker_connections` 相互匹配。
- 容器部署时同时检查宿主机和容器的 `nofile`；例如 Docker/Compose 需要单独传入 `--ulimit` 或 `ulimits`。
- 调高限制只增加容量上限，不会直接提高 RPS；内存、带宽和下游服务仍可能先达到瓶颈。

## Linux TCP 队列

两个容易混淆的队列：

```text
tcp_max_syn_backlog
    半连接队列：收到 SYN、尚未完成三次握手

somaxconn
    listen() 已完成握手、等待应用 accept 的队列上限
```

查看当前值：

```bash
sysctl net.core.somaxconn
sysctl net.ipv4.tcp_max_syn_backlog
ss -s
netstat -s | grep -i listen
```

只有监控显示突发连接导致队列溢出时才提高。示例起点：

```ini
# /etc/sysctl.d/99-easyswoole.conf
net.core.somaxconn = 8192
net.ipv4.tcp_max_syn_backlog = 8192
```

应用：

```bash
sudo sysctl --system
```

Swoole 的 `backlog` 最终还会受到 `net.core.somaxconn` 截断，所以两边需要配套。Linux 新旧版本的默认值不同，不能假设所有服务器都是 128 或 4096。

## 临时端口与 TIME_WAIT

EasySwoole 大量主动连接 MySQL、Redis 或 HTTP 上游时，会消耗本机临时端口：

```bash
sysctl net.ipv4.ip_local_port_range
ss -ant state time-wait | wc -l
```

可以在确认端口确实不足后扩大范围：

```ini
net.ipv4.ip_local_port_range = 10240 65535
```

更重要的是复用连接池和 HTTP Keep-Alive，避免每个请求重新建立上游连接。不要为了减少 TIME_WAIT 盲目修改 `tcp_tw_reuse`、`tcp_fin_timeout` 或关闭协议保护；TIME_WAIT 是 TCP 正确性的一部分，异常数量通常意味着连接没有复用或上游设计存在问题。

## TCP Keepalive

长连接或 WebSocket 可结合 Swoole 应用心跳与 TCP Keepalive。Linux 参数包括：

```bash
sysctl net.ipv4.tcp_keepalive_time
sysctl net.ipv4.tcp_keepalive_intvl
sysctl net.ipv4.tcp_keepalive_probes
```

TCP Keepalive 用于发现死连接，不等同于业务心跳。参数过小会制造大量探测包；还要与 Nginx、云负载均衡和防火墙的空闲超时共同设计。

## 一个保守的内核配置示例

下面只是中等规模服务的起点，不是通用最优值：

```ini
# /etc/sysctl.d/99-easyswoole.conf
fs.file-max = 1000000
net.core.somaxconn = 8192
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.ip_local_port_range = 10240 65535
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
```

变更前保存旧值，先在一台测试或灰度实例验证，并观察连接失败、内存和网络指标。容器环境还要确认参数属于宿主机、Pod 还是 Network Namespace，以及平台是否允许修改。

## Swoole 配置放在哪里

EasySwoole 把 `MAIN_SERVER.SETTING` 原样传给 Swoole Server。开发环境通常修改根目录 `dev.php`，生产修改 `produce.php`：

```php
'MAIN_SERVER' => [
    'LISTEN_ADDRESS' => '127.0.0.1',
    'PORT' => 9501,
    'SERVER_TYPE' => EASYSWOOLE_WEB_SERVER,
    'SETTING' => [
        'reactor_num' => 4,
        'worker_num' => 8,
        'backlog' => 8192,
        'max_conn' => 50000,
        'max_request' => 100000,
        'max_request_grace' => 10000,
        'max_request_execution_time' => 30,
        'reload_async' => true,
        'max_wait_time' => 10,
        'package_max_length' => 2 * 1024 * 1024,
        'buffer_output_size' => 2 * 1024 * 1024,
    ],
],
```

这些数值仅用于展示字段位置，不能原样用于所有服务器。修改底层 Setting 后应完整重启，并检查启动日志中是否有不支持或非法配置警告。

## `reactor_num`

Reactor 线程负责监听 Socket 和投递网络事件，不执行 PHP 业务。通常从 CPU 核数附近开始测试：

```php
'reactor_num' => swoole_cpu_num(),
```

Reactor 并非越多越快，数量过大会增加线程调度开销。官方文档建议不要超过 CPU 核数的约两倍，并指出它受到 Worker 数量关系的约束。HTTP 业务慢时，瓶颈更常在 Worker 或下游，而不是 Reactor。

## `worker_num`

Worker 执行 PHP Controller 和业务代码。

- CPU 密集：通常从 CPU 核数开始，过多会产生上下文切换。
- 协程化 I/O：可从 CPU 核数的 1–4 倍压测，但仍受内存和下游容量限制。
- 同步阻塞 I/O：增加 Worker 能暂时提高并发，但优先修复阻塞调用或迁移到合适的 Task/独立服务。

查看 CPU：

```bash
nproc
lscpu
```

调优方法是逐级测试 1×、2× 等配置，比较吞吐、P99、CPU 和上下文切换，而不是直接设置几十倍 CPU。

## `max_conn`

`max_conn` 是 Swoole 同时接受的最大连接数，应同时满足：

```text
max_conn < Worker 进程实际 LimitNOFILE
max_conn × 每连接内存 < 可用内存预算
```

HTTP Keep-Alive 和 WebSocket 都占连接。把它设置成几十万并不会创造内存、带宽或下游容量；超出业务承载能力时，较早拒绝通常比服务器 OOM 更安全。

## `backlog`

`backlog` 控制应用 listen 队列请求值，实际值受 Linux `somaxconn` 上限约束：

```php
'backlog' => 8192,
```

它主要吸收短时连接突发，不能解决 Worker 长时间处理不过来的问题。如果队列持续增长，应降低上游流量、扩容或优化业务。

## `max_request` 与内存增长

`max_request` 让 Worker 处理一定请求数后重启，可释放扩展或业务代码缓慢泄漏的内存：

```php
'max_request' => 100000,
'max_request_grace' => 10000,
```

Grace 随机区间避免全部 Worker 同时重启。它是兜底手段，不是修复内存泄漏的方法。先用监控确认 RSS 随请求数持续增长，再设置合理值并继续定位泄漏；持有长连接或复杂异步状态的服务更要谨慎轮换 Worker。

## 请求执行时间

支持该 Setting 的 Swoole 版本可以设置：

```php
'max_request_execution_time' => 30,
```

它防止单个 HTTP 请求无限占用执行资源，但不能代替 MySQL、Redis、HTTP Client 自身的连接与读写超时。每个外部依赖都应设置更短、分层的超时。

## 优雅 reload

```php
'reload_async' => true,
'max_wait_time' => 10,
```

异步 reload 允许 Worker 完成正在处理的事件，`max_wait_time` 限制最长等待。时间太短会中断慢请求，太长会拖慢发布。Server 类型、端口及部分底层配置变化仍需要完整重启。

## 请求与响应大小

```php
'package_max_length' => 2 * 1024 * 1024,
'buffer_output_size' => 2 * 1024 * 1024,
```

限制必须根据真实 API 设置，并与 Nginx `client_max_body_size` 配套。不要为了“大文件”把所有接口上限放到数百 MB；上传应独立限流，超大文件使用分片或对象存储直传。

过大的输出缓存会增加每连接内存风险。列表接口要分页，文件使用 `sendFile()` 或代理/对象存储，不要把整文件读进 PHP 字符串。

## 协程与阻塞 I/O

协程只有在等待可协程化的 I/O 时才能让出执行权。以下调用需要重点检查：

- 未启用 Hook 的阻塞网络库。
- 本地大文件同步读写。
- CPU 密集的压缩、图像和加密计算。
- `sleep()`、外部命令和未知扩展调用。

项目通常在 `EasySwooleEvent::initialize()` 配置协程 Hook：

```php
use Swoole\Coroutine;

Coroutine::set([
    'hook_flags' => SWOOLE_HOOK_ALL,
    'max_concurrency' => 1000,
]);
```

Hook 范围应按依赖兼容性测试，不要未经验证直接在生产从少量 Hook 切换到 ALL。`max_concurrency` 是保护上限，不代表应用和数据库真的能承载同等并发。

## Task Worker

发送邮件、生成报表等不要求在 HTTP 响应内完成的工作可以投递 Task 或外部消息队列。CPU 密集任务放入 Task 只能隔离 HTTP Worker，并不会降低总 CPU 消耗。

Task Worker 是独立进程，也要设置并发、超时、重试、幂等和积压监控。需要可靠投递的业务不能只依赖内存 Task 队列，应使用持久化消息系统。

## 连接池容量

连接池总量按实例和 Worker 放大：

```text
总 MySQL 连接
= 应用实例数 × worker_num × 每 Worker 池上限
```

例如 4 个实例、8 个 Worker、每 Worker 10 条连接，理论最大为 320。必须确认 MySQL `max_connections`、Redis、代理和其他服务都能承受，并预留管理连接。

连接池太小会排队，太大会压垮数据库。应同时观察池等待时间、连接使用率、SQL P99 和数据库 CPU。连接必须在 `finally` 中归还，并设置获取超时，不能无限等待。

## 应用层收益通常更大

在调整内核之前，优先检查：

- 是否存在 N+1 查询。
- 列表是否分页，字段是否只查询所需列。
- 索引是否匹配真实过滤和排序条件。
- Redis 缓存是否有命中率、TTL、防击穿和防雪崩设计。
- 外部调用能否并发，但是否有限制最大并发。
- JSON 和响应体是否过大。
- 日志是否同步写大量内容或记录完整 Body。
- 热路径是否重复读取配置、解析注解或创建连接。

缓存不是越多越好。缓存键数量、序列化成本、一致性和穿透同样需要监控。

## Nginx 配合

Nginx 侧重点包括：

```nginx
worker_processes auto;

events {
    worker_connections 16384;
    multi_accept on;
}

http {
    keepalive_timeout 30s;
    keepalive_requests 1000;

    upstream easyswoole_backend {
        server 127.0.0.1:9501;
        keepalive 64;
    }
}
```

理论连接容量还受 Nginx Worker 的文件描述符限制。上游 Keepalive 减少 Nginx 与 EasySwoole 反复握手；客户端 Keepalive 太长则会占用更多空闲连接。具体代理 Header、上传和 WebSocket 配置参见“反向代理部署”。

## 如何压测

先建立可重复基线：固定机器、数据集、PHP/Swoole 配置和压测机。压测机不能与服务共用 CPU。

简单示例：

```bash
wrk -t4 -c100 -d60s --latency http://127.0.0.1:9501/health/live
wrk -t8 -c500 -d120s --latency http://127.0.0.1:9501/api/users
```

健康接口只能测框架和网络上限，不能代表真实业务。还要测试带数据库、JSON Body、鉴权、缓存未命中和典型响应大小的接口。

逐次只改变一个变量，记录：

```text
配置版本、RPS、P50/P95/P99、错误率、CPU、内存、连接数、下游指标
```

压测结束后继续低流量运行一段时间，观察常驻进程内存是否持续增长。只看 30 秒峰值会漏掉泄漏、连接池耗尽和缓存过期抖动。

## 运行时观察

常用系统命令：

```bash
pidstat -p ALL 1
vmstat 1
ss -s
sar -n TCP,ETCP 1
top -H -p <pid>
```

Swoole Server 的 `stats()` 可以提供连接、请求、Worker/Task 等运行指标。可以把必要字段接入内部监控，但不要把完整调试端点公开到互联网。

设置告警时关注趋势和饱和度：P99 上升、连接池等待、队列积压、Worker RSS 单调增长、连接拒绝和下游超时，比单独的 CPU 百分比更有价值。

## 推荐调优顺序

```text
1. 建立真实业务压测与监控基线
2. 修复慢 SQL、阻塞 I/O、N+1 和超大响应
3. 设置依赖超时、连接池和并发上限
4. 调整 worker_num / reactor_num 并重复压测
5. 根据连接量设置 nofile、max_conn、backlog
6. 只有观察到队列或端口瓶颈时再调整 sysctl
7. 灰度发布并持续观察 P99、错误率和内存
```

## 常见误区

- `worker_num` 设置越大性能越好。
- 把 `max_request` 当作内存泄漏的永久解决方案。
- 盲目复制 `sysctl.conf`，不知道每个值解决什么指标。
- 只提高连接上限，不核算每连接内存和数据库容量。
- 压测只访问空的 HelloWorld，然后推断业务接口性能。
- 只看平均延迟，忽略 P99 和错误率。
- 所有超时都设得很长，导致故障时请求堆积。
- 在 Worker 内运行阻塞命令或 CPU 重任务。
- 用本机静态数组保存跨 Worker 状态。

## 参考依据

- [Linux 内核 IP sysctl 文档](https://kernel.org/doc/html/latest/networking/ip-sysctl.html)
- [OpenSwoole Server 配置参考](https://openswoole.com/docs/25.x/modules/swoole-server/configuration)
- [OpenSwoole HTTP Server 配置](https://openswoole.com/docs/modules/swoole-http-server/configuration)

项目使用的是 Swoole 扩展时，应以实际安装版本的配置文档和启动警告为准；OpenSwoole 文档用于解释同源配置概念，不代表每个版本都支持完全相同的 Setting。
