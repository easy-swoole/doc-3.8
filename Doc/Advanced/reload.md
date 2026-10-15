# 热重启

EasySwoole 是常驻内存框架。PHP 文件被 Worker 加载后会一直保留在进程内存中，修改源码不会像 PHP-FPM 一样在下一次请求时自动生效。热重启会逐步替换 Worker，让新 Worker 重新加载业务代码，同时保留 Master 和 Manager 进程。

热重启也常被称为平滑重载或 reload。它适合更新 Worker 中运行的业务代码，不等于停止后重新启动整个服务。

## 执行热重启

在项目根目录执行：

```bash
php easyswoole.php server reload
```

生产模式必须传入和启动时相同的运行模式：

```bash
php easyswoole.php server reload --mode=produce
```

如果使用 systemd 管理服务，应让 systemd 执行预先配置的 reload 命令：

```bash
sudo systemctl reload easyswoole
```

具体 Unit 配置参见[使用 systemd 管理服务](/QuickStart/systemd.md)。

## EasySwoole 如何实现 reload

EasySwoole 的 `server reload` Action 并不重新执行 `Server::start()`，其核心流程可以简化为：

```text
执行 server reload
    ↓
根据 --mode 加载对应配置
    ↓
读取 MAIN_SERVER.SETTING.pid_file
    ↓
用 kill(pid, 0) 检查 Master 是否存在
    ↓
向 Master PID 发送 SIGUSR1
    ↓
Swoole 通知 Manager 平滑替换 Worker 和 TaskWorker
```

框架中的核心实现等价于：

```php
$pidFile = Config::getInstance()
    ->getConf('MAIN_SERVER.SETTING.pid_file');

$pid = (int) file_get_contents($pidFile);

if (!\Swoole\Process::kill($pid, 0)) {
    throw new RuntimeException("Master process {$pid} does not exist");
}

\Swoole\Process::kill($pid, SIGUSR1);
```

`kill($pid, 0)` 不会真正发送终止信号，只用于检查进程是否存在以及当前用户是否有权限向它发送信号。`SIGUSR1` 才是本次 reload 的触发信号。

命令行显示“send server reload command”只代表信号已经成功发送，不代表所有 Worker 已经完成替换。

## 进程替换原理

以进程模式为例，服务运行结构可以简化为：

```text
Master
├── Reactor 线程
└── Manager
    ├── Worker 0
    ├── Worker 1
    ├── Worker 2
    └── TaskWorker
```

收到 `SIGUSR1` 后，Master 和 Manager 不会退出，监听端口也不会重新绑定。Manager 负责让旧 Worker 退出并创建新 Worker：

```text
旧 Worker 停止接收新任务
    ↓
等待当前请求、事件或 Task 完成
    ↓
触发 Worker 退出清理
    ↓
旧 Worker 退出
    ↓
Manager 创建新 Worker
    ↓
新 Worker 执行 onWorkerStart
    ↓
新 Worker 开始处理请求
```

新旧 Worker 在切换期间可能短暂共存。新 Worker 拥有新的 PHP 内存空间，因此它在启动或首次使用类时会读取更新后的 PHP 文件。

EasySwoole 在 Worker 退出事件中会清理进程表记录、当前 Worker 的定时器和事件循环；新 Worker 启动时会重新执行 `onWorkerStart`，重新设置进程名并注册 Worker 内资源。

## 配置平滑退出时间

项目的 `dev.php` 和 `produce.php` 可以设置：

```php
return [
    'MAIN_SERVER' => [
        'SETTING' => [
            'reload_async' => true,
            'max_wait_time' => 10,
        ],
    ],
];
```

| 配置 | 作用 |
| --- | --- |
| `reload_async` | 允许旧 Worker 等待正在执行的事件和协程完成后再退出 |
| `max_wait_time` | 最长等待秒数；超过后仍未退出的 Worker 会被强制终止 |

`max_wait_time` 必须覆盖应用中合理的最长请求或任务执行时间。例如接口最大允许执行 8 秒，将它设置成 3 秒，发布时就可能强制中断正在处理的请求。

它也不能无限增大，否则被阻塞 I/O 或死循环占用的 Worker 会让发布长时间不能完成。数据库、Redis 和 HTTP 客户端仍应配置各自的连接及读写超时。

修改 `reload_async` 或 `max_wait_time` 本身属于 Server 启动配置变化，第一次启用或调整后应完整重启服务，新配置生效后，后续 reload 才会使用它。

## 哪些修改可以热重启

是否能热更新，取决于代码是在 Worker 创建前还是创建后加载。

| 修改内容 | reload 是否足够 | 原因 |
| --- | --- | --- |
| 控制器、Service、普通业务类 | 通常可以 | 新 Worker 会重新加载业务类 |
| Worker 内创建的连接和对象 | 可以，但需要重建 | 旧 Worker 内存会随进程退出，新 Worker 应在 `onWorkerStart` 或首次使用时创建 |
| Worker 内定时器 | 可以，但需要重新注册 | EasySwoole 会在 Worker 退出时清理定时器 |
| `onWorkerStart` 中的逻辑 | 可以 | 新 Worker 会再次执行 `onWorkerStart` |
| 监听地址、端口、Server 类型 | 不可以 | Master 不会退出，也不会重新创建监听服务 |
| `worker_num`、Reactor 等 Server Setting | 不可以 | `Server::set()` 只在服务启动前执行 |
| `mainServerCreate()` 中增加监听端口或自定义进程 | 通常不可以 | reload 不会重新创建整个 Server |
| `EasySwooleEvent::initialize()` 的初始化结构 | 不应依赖 reload | reload 命令中的初始化发生在独立 CLI 进程，不会修改正在运行的 Master 内存 |
| Composer 依赖、扩展和启动入口 | 建议完整重启 | 可能已经在 Worker 创建前由 Master 加载 |

判断原则是：只替换 Worker 就能重新创建的内容可以 reload；需要重新执行 CLI 启动、创建 Server、绑定端口或改变 Master/Manager 状态的内容必须完整重启。

## 为什么有时修改 PHP 后仍不生效

Swoole 只能让新 Worker 重新加载 Worker 生命周期内包含的文件。如果文件在 `Server::start()` 前已经由 Master 加载，新 Worker 会继承 Master 中原有的类定义，reload 不能重新定义它。

可以按下面顺序排查：

1. 确认 reload 使用的 `--mode` 与 start 一致。
2. 检查命令读取的 PID 文件是否属于当前服务实例。
3. 确认修改的是实际部署目录，而不是另一份代码副本。
4. 判断文件是否在 `initialize()`、`mainServerCreate()` 或 Server 启动前已经加载。
5. 使用 OPcache 时确认 CLI 的时间戳检查策略允许读取新文件，必要时采用完整重启。
6. 检查是否连续发送 reload；前一次尚未完成时，后续 reload 请求可能不会被重复执行。

如果不能确定文件加载阶段，生产发布应选择完整重启或滚动重启，不要假设所有 PHP 文件都能通过 reload 更新。

## 请求、Task 和长连接会怎样

启用 `reload_async` 后，普通进行中的请求和 Task 会获得一段收尾时间；超过 `max_wait_time` 仍未结束时可能被强制终止。因此写操作、支付回调和消息消费必须具备幂等性，不能把 reload 当成事务保障机制。

在进程模式下，监听 Socket 仍由 Master 持有，所以 reload 不需要重新绑定端口。但 WebSocket、TCP 等长连接的业务状态如果只保存在某个 Worker 的普通 PHP 变量中，会随该 Worker 退出而丢失。需要跨 reload 保留的状态应放在 Redis、数据库、Swoole Table 或其他共享存储中。

自定义进程并不等同于 Worker。`SIGUSR1` 的目标是 Worker/TaskWorker 重载，不能依赖它重新创建 `addProcess()` 注册的自定义进程；相关进程结构发生变化时应完整重启。

## 完整重启

出现以下情况时应执行完整重启：

- 修改监听地址、端口或 Server 类型。
- 修改 Worker 数量、TaskWorker 数量或底层 Swoole Setting。
- 修改 `mainServerCreate()` 中的子服务、自定义进程或主进程事件。
- 更新 PHP 扩展、Composer 自动加载结构或启动阶段依赖。
- 发布后 reload 无法加载目标代码。

直接使用命令管理时：

```bash
php easyswoole.php server stop --mode=produce
php easyswoole.php server start -d --mode=produce
```

使用 systemd 时：

```bash
sudo systemctl restart easyswoole
```

单实例完整重启可能产生短暂不可用。生产环境需要无中断发布时，应在负载均衡器后部署多个实例，逐个摘流、重启、健康检查并恢复流量。

## 发布检查建议

一次较安全的热更新流程如下：

```text
完成代码部署
  → 检查依赖和配置
  → 执行 server reload
  → 观察 Worker PID 是否逐步变化
  → 检查错误日志和超时日志
  → 请求健康检查接口
  → 验证关键业务接口
```

可以使用以下命令辅助确认：

```bash
php easyswoole.php server status --mode=produce
pgrep -af 'EasySwoole|easyswoole'
tail -f Log/produce.log_$(date +%Y%m).log
```

不要在极短时间内反复执行 reload。应等待上一轮 Worker 替换完成，并结合应用日志、进程 PID 和健康检查判断发布结果。

## 源码依据

- [EasySwoole Server 命令](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Command/DefaultCommand/Server.php)
- [EasySwoole Core Worker 事件](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Core.php)
- [Swoole Server reload](https://openswoole.com/docs/modules/swoole-server-reload)
- [reload_async 与 max_wait_time](https://openswoole.com/docs/modules/swoole-server/configuration)
