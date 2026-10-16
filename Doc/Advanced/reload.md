# 热重启

EasySwoole 是常驻内存框架。PHP 文件被 Worker 加载后会一直保留在进程内存中，修改源码不会像 PHP-FPM 一样在下一次请求时自动生效。热重启会替换对应的业务进程，让新进程重新加载代码，同时保留整个服务的监听能力。

热重启也常被称为平滑重载或 reload。当前框架针对不同进程提供四种重载入口：

| 命令 | 重载对象 | 典型代码 |
| --- | --- | --- |
| `server reload` | HTTP/TCP/WebSocket Worker | 控制器、Service、Worker 内初始化的对象 |
| `task reload` | `easyswoole/task` 创建的 Task Worker | Task 类及其依赖、Task Worker 内初始化的对象 |
| `crontab reload` | Crontab Scheduler 与 Worker | Job 在子进程中延迟加载的业务类 |
| `process kill --pid/--name` | 已注册的自定义进程 | 在 `run()` 中延迟加载的独立业务类 |

因此，Task Worker 使用 `task reload`，Crontab 进程使用 `crontab reload`，而不是全部依赖 `server reload`。普通自定义进程可以在满足延迟加载条件时，通过 `process kill` 退出旧进程并由 Manager 拉起新进程。以上操作都不等于停止后重新启动整个服务。

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

如果本次发布修改了异步 Task 代码，还需要重载 Task Worker：

```bash
# 同时向所有 Task Worker 发送 SIGTERM
php easyswoole.php task reload --mode=produce

# 生产环境有两个及以上 Task Worker 时，建议逐个重载
php easyswoole.php task reload \
    --mode=produce \
    --rolling \
    --timeout=30
```

只修改控制器时不需要执行 `task reload`；只修改 Task Worker 中加载的代码时也不需要额外执行 `server reload`。如果同一个 Service 类同时由 HTTP Worker 和 Task Worker 加载，则两条命令都要执行。

修改了 Crontab Worker 中延迟加载的业务类时，执行：

```bash
php easyswoole.php crontab reload --mode=produce
```

该命令会同时向当前实例的 Crontab Scheduler、普通 Worker 和特权任务 Worker 发送 `SIGTERM`，没有滚动模式。运行时暂停状态、临时修改的 Rule 和执行统计会在新 Scheduler 建表时重置。Job 类自身和注册结构已经由 Master 加载，相关变化仍需完整重启。详细说明参见[Crontab 管理](/Advanced/ManagementCommand/crontab.md)。

修改了自定义进程在 `run()` 中延迟加载的业务类时，可以先查询目标进程，再按 PID 或进程名重启：

```bash
# 先确认准确的进程名称和 PID
php easyswoole.php process show --mode=produce

# 推荐按 PID 逐个重启，便于多实例消费进程滚动切换
php easyswoole.php process kill \
    --mode=produce \
    --pid=12345

# 只有确认该名称唯一，或确实要同时重启所有同名进程时才按名称操作
php easyswoole.php process kill \
    --mode=produce \
    --name='OrderConsumer'
```

`process kill` 默认发送 `SIGTERM`。旧进程正常退出后，Swoole Manager 会拉起替代进程。该方式只更新子进程中延迟加载的业务类；如果改动了进程壳、注册参数或进程数量，仍需完整重启服务。

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
Swoole 通知 Manager 平滑替换服务 Worker
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
EasySwoole 服务
├── Swoole Master / Manager
│   ├── Worker 0
│   ├── Worker 1
│   └── Worker 2
└── EasySwoole Task 组件
    ├── TaskWorker 0
    └── TaskWorker 1
```

收到 `SIGUSR1` 后，Master 和 Manager 不会退出，监听端口也不会重新绑定。Manager 负责让旧 Worker 退出并创建新 Worker：

```text
旧 Worker 停止接收新任务
    ↓
等待当前请求或事件完成
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

## Task Worker 如何热重启

`easyswoole/task` 创建的是组件自己的 Task Worker。框架的 `task reload` 会通过 Bridge 取得这些进程的 PID，再向它们发送信号，让进程管理器创建新的 Task Worker。新进程会重新加载 Task 类及其依赖，因此修改后的 Task 业务代码可以生效。

普通重载同时通知全部 Task Worker：

```bash
php easyswoole.php task reload --mode=produce
```

输出类似：

```text
sent SIGTERM to Task worker PIDs: 18863, 18864, 18865, 18866
```

滚动重载每次只替换一个 Worker，并等待相同 index 的新进程进入 `accepting` 后再处理下一个：

```bash
php easyswoole.php task reload \
    --mode=produce \
    --rolling \
    --timeout=30
```

```text
Task Worker 0: PID 18863 -> 19201 ready
Task Worker 1: PID 18864 -> 19202 ready
```

滚动重载适合配置了两个及以上 Task Worker 的生产服务，可以避免同时终止全部接收进程。只有一个 Task Worker 时仍会存在短暂的接收空窗。完整参数与状态检查参见[异步管理](/Advanced/ManagementCommand/task.md)。

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
| Task 类及其依赖 | 可以，但使用 `task reload` | 新 Task Worker 会重新加载对应代码 |
| Task Worker 内创建的连接和对象 | 可以，但使用 `task reload` 重建 | 连接不能跨进程沿用，应在新进程中重新创建 |
| 监听地址、端口、Server 类型 | 不可以 | Master 不会退出，也不会重新创建监听服务 |
| `worker_num`、Reactor 等 Server Setting | 不可以 | `Server::set()` 只在服务启动前执行 |
| `mainServerCreate()` 中增加监听端口或自定义进程 | 通常不可以 | reload 不会重新创建整个 Server |
| 已注册自定义进程调用的独立业务类 | 有条件可以 | 杀掉该进程，由 Manager 拉起新进程后延迟加载新版业务类 |
| `EasySwooleEvent::initialize()` 的初始化结构 | 不应依赖 reload | reload 命令中的初始化发生在独立 CLI 进程，不会修改正在运行的 Master 内存 |
| Composer 依赖、扩展和启动入口 | 建议完整重启 | 可能已经在 Worker 创建前由 Master 加载 |

判断原则是：只替换对应 Worker 就能重新创建的内容可以 reload。HTTP 等服务 Worker 使用 `server reload`，组件 Task Worker 使用 `task reload`；需要重新执行 CLI 启动、创建 Server、绑定端口或改变 Master/Manager 状态的内容必须完整重启。

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

启用 `reload_async` 后，`server reload` 中普通进行中的请求会获得一段收尾时间；超过 `max_wait_time` 仍未结束时可能被强制终止。因此写操作、支付回调和消息消费必须具备幂等性，不能把 reload 当成事务保障机制。

`task reload` 默认发送 `SIGTERM`。Task Worker 会停止接收新任务并等待当前任务退出；滚动模式还会等待替代进程进入 `accepting`。如果任务长时间不结束，滚动重载会受到 `--timeout` 限制并停止后续操作。不要在日常发布中使用 `--force`，因为 `SIGKILL` 不会给当前 Task 执行清理和收尾的机会。

在进程模式下，监听 Socket 仍由 Master 持有，所以 reload 不需要重新绑定端口。但 WebSocket、TCP 等长连接的业务状态如果只保存在某个 Worker 的普通 PHP 变量中，会随该 Worker 退出而丢失。需要跨 reload 保留的状态应放在 Redis、数据库、Swoole Table 或其他共享存储中。

普通自定义进程并不等同于服务 Worker 或 Task 组件 Worker。`server reload` 和 `task reload` 都不会替换 `addProcess()` 注册的普通自定义进程。不过，对于已经注册好的自定义进程，可以通过“进程壳固定、业务类延迟加载”的方式，终止旧进程并让 Manager 拉起新进程，从而更新业务代码。

## 自定义进程的热重启

自定义进程在 `mainServerCreate()` 中被实例化并传给 `addProcess()`。此时自定义进程类文件已经被主进程加载，类中的 `run()` 方法体也已经被 PHP 编译为 Opcode。因此，不能把它理解为“`run()` 的代码尚未加载”。

可以热更新的关键在于：**让 `run()` 只负责进程生命周期，并在子进程启动后首次引用另一个独立业务类**。如果这个业务类从未在 Master/Manager 中加载，新拉起的子进程会通过 Composer 自动加载器从磁盘读取它的最新版本。

推荐目录结构：

```text
App/
├── Process/
│   └── OrderConsumerProcess.php   固定的进程壳，修改后需要完整重启
└── ProcessLogic/
    └── OrderConsumerRunner.php    实际业务，可以按进程重启更新
```

### 定义稳定的进程壳

新建 `App/Process/OrderConsumerProcess.php`：

```php
<?php

namespace App\Process;

use EasySwoole\Component\Process\AbstractProcess;

class OrderConsumerProcess extends AbstractProcess
{
    private bool $running = true;

    protected function run($arg): void
    {
        // OrderConsumerRunner 不要在构造方法或 mainServerCreate() 中实例化。
        // 这一行实际在子进程执行，触发业务类的首次自动加载。
        $runnerClass = 'App\\ProcessLogic\\OrderConsumerRunner';
        $runner = new $runnerClass();
        $runner->run(fn (): bool => $this->running);
    }

    protected function onSigTerm(): void
    {
        // 让业务循环自然退出，完成当前任务的收尾。
        $this->running = false;
    }

    protected function onException(\Throwable $throwable, ...$args): void
    {
        error_log($throwable->__toString());
    }
}
```

使用类名字符串不是绝对要求，但它能清楚表达这里需要延迟到子进程才解析业务类。不要在进程壳的属性默认值、构造方法、`mainServerCreate()`、静态初始化逻辑或配置构建阶段提前实例化 `OrderConsumerRunner`。

### 把业务循环放到独立类

新建 `App/ProcessLogic/OrderConsumerRunner.php`：

```php
<?php

namespace App\ProcessLogic;

use Swoole\Coroutine;

class OrderConsumerRunner
{
    public function run(callable $isRunning): void
    {
        while ($isRunning()) {
            try {
                // 从队列获取并处理一条任务。
                $this->consumeOne();
            } catch (\Throwable $throwable) {
                error_log($throwable->__toString());
            }

            Coroutine::sleep(0.1);
        }
    }

    private function consumeOne(): void
    {
        // 实际消费逻辑。
    }
}
```

`OrderConsumerRunner` 以及只由它继续加载的 Service、Repository 等业务类，都可以随新自定义进程重新加载。已经由 Master 提前加载的公共类仍然会继承旧定义。

### 注册和重启进程

进程仍然只在 `mainServerCreate()` 中注册一次：

```php
use App\Process\OrderConsumerProcess;
use EasySwoole\Component\Process\Manager;

public static function mainServerCreate(EventRegister $register)
{
    Manager::getInstance()->addProcess(
        new OrderConsumerProcess('OrderConsumer')
    );
}
```

部署新版 `OrderConsumerRunner.php` 后，先找出准确 PID：

```bash
php easyswoole.php process show --mode=produce
```

再向目标进程发送默认的 `SIGTERM`：

```bash
php easyswoole.php process kill \
    --mode=produce \
    --name='OrderConsumer'
```

该自定义进程附加在 Swoole Server 上，由 Manager 管理。旧进程退出后，Manager 会重新创建替代进程；替代进程进入 `run()` 时再从磁盘加载新版 `OrderConsumerRunner`。随后再次检查 PID 和日志：

```bash
php easyswoole.php process show --mode=produce
```

```text
旧 PID 退出
    ↓
Manager 使用启动时已经注册的进程壳创建新进程
    ↓
新进程执行旧进程壳中的 run()
    ↓
首次自动加载磁盘上的新版 OrderConsumerRunner
    ↓
开始执行新版业务逻辑
```

### 生产环境注意事项

- 进程壳类本身、构造参数、进程数量、进程名称、管道类型和 `mainServerCreate()` 注册逻辑已经在主进程内存中；这些内容变化后仍要完整重启。
- 业务类不能在 Master/Manager 阶段提前加载。可以在子进程中用 `get_included_files()` 检查加载文件，但更重要的是审查启动代码的引用位置。
- 应使用 `SIGTERM`，并在 `onSigTerm()` 中停止接单、结束循环、等待当前任务完成和释放资源。`--force` 使用 `SIGKILL`，不属于软重启。
- 自定义进程没有 `task reload --rolling` 那样的专用就绪协议。多个同组消费者应逐个按 PID 重启，并在每次操作后确认新 PID、心跳和业务健康，再处理下一个。
- 单个消费进程退出到替代进程就绪之间可能存在空窗。重要任务应依赖可信队列、确认重投和幂等处理，而不是假设进程切换绝对无缝。
- CLI OPcache 必须允许新进程读取更新后的脚本；若关闭时间戳校验，应在发布流程中重置 OPcache，或者选择完整重启。
- 进程收到 `SIGTERM` 后是否能及时退出，取决于业务循环是否响应停止标记，以及网络、数据库和队列调用是否配置了合理超时。

因此，这是一种**有边界的自定义进程业务代码热重启**：可以更新延迟加载的业务层，但不能更新主进程已经加载的进程定义和服务结构。

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
  → 判断代码由服务 Worker、Task Worker、Crontab、自定义进程，还是多类进程共同加载
  → 检查依赖和配置
  → 按需执行 server reload
  → 按需执行 task reload --rolling --timeout=30
  → 按需执行 crontab reload
  → 按需执行 process kill --pid=...，逐个替换自定义进程
  → 观察对应 Worker PID 是否变化
  → 检查错误日志和超时日志
  → 请求健康检查接口
  → 验证关键业务接口
```

可以使用以下命令辅助确认：

```bash
php easyswoole.php server status --mode=produce
php easyswoole.php process show --mode=produce
php easyswoole.php task show --mode=produce
php easyswoole.php crontab show --mode=produce
pgrep -af 'EasySwoole|easyswoole'
tail -f Log/produce.log_$(date +%Y%m).log
```

不要在极短时间内反复执行 reload。应等待上一轮 Worker 替换完成，并结合应用日志、进程 PID 和健康检查判断发布结果。

四类命令的完整参数分别参见[服务管理](/Advanced/ManagementCommand/server.md)、[异步管理](/Advanced/ManagementCommand/task.md)、[Crontab 管理](/Advanced/ManagementCommand/crontab.md)和[进程管理](/Advanced/ManagementCommand/process.md)。

## 源码依据

- [EasySwoole Server 命令](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Command/DefaultCommand/Server.php)
- [EasySwoole Task 命令](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Command/DefaultCommand/Task.php)
- [TaskReloader](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Command/TaskReloader.php)
- [EasySwoole Core Worker 事件](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Core.php)
- [Component AbstractProcess](https://github.com/easy-swoole/component/blob/master/src/Process/AbstractProcess.php)
- [Swoole Server addProcess](https://openswoole.com/docs/modules/swoole-server-addProcess)
- [Swoole Server reload](https://openswoole.com/docs/modules/swoole-server-reload)
- [reload_async 与 max_wait_time](https://openswoole.com/docs/modules/swoole-server/configuration)
