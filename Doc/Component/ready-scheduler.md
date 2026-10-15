# 就绪调度 ReadyScheduler

`ReadyScheduler` 基于 `Swoole\Table` 保存命名项目的就绪状态，可以让一个 Worker 等待另一个 Worker 或其他相关进程完成初始化。

要实现跨进程就绪等待，必须在 Swoole 创建 Worker 之前，由主进程创建 `ReadyScheduler` 和底层 Table。EasySwoole 项目应在 `EasySwooleEvent::initialize()` 中完成初始化；不能等到 `workerStart`、控制器或其他 Worker 代码中才首次创建。

每个项目只有两种状态：

| 常量 | 值 | 含义 |
| --- | --- | --- |
| `ReadyScheduler::STATUS_UNREADY` | `0` | 尚未就绪 |
| `ReadyScheduler::STATUS_READY` | `1` | 已就绪 |

`ReadyScheduler` 不是计数器。`ready()` 和 `unready()` 会直接把状态设置为 `1` 或 `0`。

## 在主进程初始化

编辑项目根目录的 `EasySwooleEvent.php`：

```php
<?php

namespace EasySwoole\EasySwoole;

use EasySwoole\Component\ReadyScheduler;
use EasySwoole\EasySwoole\AbstractInterface\Event;
use EasySwoole\EasySwoole\Swoole\EventRegister;

class EasySwooleEvent implements Event
{
    public static function initialize(): void
    {
        // initialize 在主进程创建 Worker 之前执行。
        $scheduler = ReadyScheduler::getInstance(2048);

        // 项目也在主进程预先登记，初始状态均为 Unready。
        $scheduler->addItem('database');
        $scheduler->addItem('cache');
    }

    public static function mainServerCreate(EventRegister $register): void
    {
    }
}
```

`2048` 是底层 `Swoole\Table` 的最大项目数，只在第一次 `getInstance()` 创建实例时生效。

```text
主进程执行 initialize()
        ↓
创建 ReadyScheduler 和 Swoole Table
        ↓
注册 database、cache 等项目
        ↓
Swoole 创建 Worker/其他子进程
        ↓
各进程继承并访问同一块共享内存
        ↓
一个进程更新状态，其他进程能够等待和读取
```

如果在每个 Worker 启动后才分别首次调用 `ReadyScheduler::getInstance()`，各进程会各自创建 Table，彼此看不到状态变化，无法实现跨进程就绪等待。

## 在 Worker 中更新状态

Scheduler 已由主进程创建后，Worker 直接调用无参数的 `getInstance()` 取得继承的实例：

```php
use EasySwoole\Component\ReadyScheduler;

$scheduler = ReadyScheduler::getInstance();

if (!DatabaseService::connect()) {
    $scheduler->unready('database');
    return;
}

$scheduler->ready('database');
```

`ready()` 和 `unready()` 只会更新已经登记的项目。key 不存在时返回 `false`，不会自动创建：

```php
if (!$scheduler->ready('database')) {
    throw new RuntimeException('database item was not registered');
}
```

## 等待全部项目就绪

等待操作会调用 `Coroutine::sleep()`，必须在 Swoole 协程环境中执行：

```php
$scheduler = ReadyScheduler::getInstance();

if (!$scheduler->waitReady(['database', 'cache'], 3.0)) {
    throw new RuntimeException('dependencies are not ready');
}

ApplicationService::start();
```

`waitReady()` 只有在数组中的所有项目都达到 Ready 状态时才返回 `true`。超时前仍有任意项目未就绪，则返回 `false`。

## 等待任意项目就绪

只要多个项目中有一个可用就能继续时，使用 `waitAnyReady()`：

```php
$available = $scheduler->waitAnyReady(
    ['cache-primary', 'cache-backup'],
    2.0
);

if (!$available) {
    throw new RuntimeException('no cache node is ready');
}
```

`waitAnyReady()` 找到一个 Ready 项目后返回 `true`，但不会告诉调用方具体是哪一个。需要知道项目名称时，应在返回后分别调用 `status()` 检查。

## 状态操作

### addItem

注册一个项目，并把初始状态设置为 Unready：

```php
$created = $scheduler->addItem('database');
```

返回底层 `Swoole\Table::set()` 的结果。重复调用同一个 key 会将它重新设置为 Unready，因此不要把 `addItem()` 当成“不存在才添加”。跨进程使用时，应在主进程初始化阶段统一调用。

### ready

把已经注册的项目直接设置为 Ready：

```php
$updated = $scheduler->ready('database');
```

项目不存在时返回 `false`。

### unready 与 restore

把项目直接恢复为 Unready：

```php
$scheduler->unready('database');
$scheduler->restore('database');
```

当前版本中，`unready()` 和 `restore()` 的结果相同，都会直接写入 `STATUS_UNREADY`。二者都要求项目已经存在，不存在时返回 `false`。

### status

读取当前状态：

```php
$status = $scheduler->status('database');

if ($status === ReadyScheduler::STATUS_READY) {
    // 已就绪
}
```

项目不存在时返回 `null`。判断时应使用严格比较，避免把 `null` 和 `STATUS_UNREADY` 混为一谈。

### dropItem

删除项目：

```php
$deleted = $scheduler->dropItem('database');
```

成功删除返回 `true`；项目不存在或重复删除时返回 `false`。删除后，等待该 key 的协程会把它视为未就绪，直到等待超时或重新注册并设置为 Ready。

## 等待方法的边界

```php
$scheduler->waitReady($keys, $timeout);
$scheduler->waitAnyReady($keys, $timeout);
```

- 超时单位是秒，支持浮点数。
- 使用单调时钟计算实际经过时间，不受系统时间调整影响。
- 内部以最长约 10 毫秒的间隔轮询状态。
- 空数组会立即返回 `true`。
- `0` 或负数超时仍会先检查一次当前状态；尚未满足时立即返回 `false`。
- key 不存在时会被视为未就绪，但返回值不会区分“项目不存在”和“项目存在但尚未就绪”。需要区分时应先调用 `status()`。
- 超时只结束当前等待，不会修改任何项目状态。

## 完整生命周期示例

```php
$scheduler = ReadyScheduler::getInstance();

// report-cache 已在主进程 initialize() 中 addItem。
$scheduler->ready('report-cache');

if ($scheduler->waitReady(['report-cache'], 1.0)) {
    ReportService::start();
}

$scheduler->unready('report-cache');
$scheduler->ready('report-cache');
$scheduler->dropItem('report-cache');
```

## 使用边界

- `Swoole\Table` 只能让同一台机器上、由同一父进程派生的相关进程共享状态。
- 多台服务器之间应使用 Redis、服务注册中心或其他外部系统协调就绪状态。
- Table 数据随 Server 进程退出而消失，不是持久化存储。
- `ReadyScheduler` 只保存就绪状态，不负责执行初始化任务，也不会自动重试失败任务。

## 常见错误

- 在 Worker 中首次创建 Scheduler，却期望其他 Worker 能看到状态。
- 没有在主进程 `initialize()` 中预先登记项目。
- 没有先调用 `addItem()`，直接调用 `ready()`，然后忽略返回的 `false`。
- 重复调用 `addItem()`，意外把已经 Ready 的项目重置为 Unready。
- 在非协程代码中调用等待方法。
- 把它当成跨服务器的服务注册中心或持久化存储。

## 源码依据

- [ReadyScheduler](https://github.com/easy-swoole/component/blob/master/src/ReadyScheduler.php)
