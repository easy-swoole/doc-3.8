# 预热、检查与监控

连接池需要在容量、冷启动速度和下游连接压力之间取得平衡。本章介绍 Pool 3.x 内置的预热、健康检查、缩容和状态接口。

## keepMin 预热

`keepMin()` **不是必选项**。不调用它时，连接池仍然可以正常工作，并会在业务第一次调用 `getObj()`、`invoke()` 或 `defer()` 时按需创建连接。

预热的作用只是提前承担建连成本，减少服务刚启动后第一批请求的等待时间。对连接建立很快、流量较低或不希望启动时立即占用下游连接的服务，可以不做预热。

确定需要预热时，在 Worker 启动后的协程中调用：

```php
$created = $pool->keepMin();
```

不传参数时补充到 `minObjectNum`，也可以临时指定目标数量：

```php
$created = $pool->keepMin(10);
```

返回值是本次新建的对象数量，不是池中的对象总数。目标仍受 `maxObjectNum` 限制。

预热需要注意：

- 每个 Worker 会分别预热自己的池。
- `createObject()` 逐个执行，建连较慢时会延长预热时间。
- 已借出的对象也计算在当前对象总数中。
- 某次创建失败后，本轮预热会停止并通过 PHP 错误机制报告。

不要在 Master 进程中先建立网络连接再 fork Worker。应在 `onWorkerStart` 后的协程中预热。

## 定时健康检查

连接池第一次初始化时，会按 `intervalCheckTime` 创建定时器。每轮最多检查 `intervalCheckBatchSize` 个空闲对象：

```php
$config = new \EasySwoole\Pool\Config([
    'intervalCheckTime' => 5_000,
    'intervalCheckBatchSize' => 8,
]);
```

检查过程：

1. 从空闲 Channel 取出对象。
2. 调用对象的 `intervalCheck()`。
3. 健康对象放回队尾。
4. 失效对象调用 `gc()` 并删除。
5. 本轮结束后调用 `keepMin()` 补足最小数量。

健康检查不会处理正在被业务协程使用的对象。借出对象时仍会通过 `beforeUse()` 再检查一次。

如果单次探活可能长时间阻塞，应在客户端上设置较短超时。批量大小只能限制每轮对象数量，不能中断某个已经卡住的探活。

将 `intervalCheckTime` 设为 `0` 或负数可以关闭定时健康检查：

```php
$config->setIntervalCheckTime(0);
```

## 自动缩容

池初始化后还会每 5 秒计算一次最近的 Channel 平均等待时间。当平均等待低于 `waitLoadAverageTime` 时，尝试回收当前对象总数的 10%，但不会低于 `minObjectNum`。

```php
$config->setWaitLoadAverageTime(0.001);
```

缩容只能取走空闲对象，不会强制关闭正在使用的连接。将阈值设置为 `0` 可以阻止当前缩容条件成立，但负载统计定时器仍然存在。

## status 状态

```php
$state = $pool->status();
```

返回格式：

```php
[
    'createdNum' => 6,
    'loadAverageTime' => 0.01,
]
```

- `createdNum`：当前登记或预占的对象总数，包含空闲、已借出和正在创建的名额。
- `loadAverageTime`：最近统计窗口内，从 Channel 获取对象的平均等待秒数，保留两位小数。

当前接口不直接提供空闲数、使用中数量或等待协程数。监控时可以同时采集：

- `status()` 的两个字段。
- `getConfig()` 中的最大、最小对象数。
- `PoolEmpty` 出现次数。
- `createObject()`、`beforeUse()` 和业务客户端异常次数。
- 真实查询或网络请求耗时。

如果 `createdNum` 经常接近最大值并伴随 `PoolEmpty`，先检查慢查询、下游延迟以及连接是否及时归还，不要只依靠扩大连接池解决。

## destroy 与 reset

`destroy()` 会停止连接池 Timer、清理空闲对象并关闭 Channel：

```php
$pool->destroy();
```

它不会等待仍在执行的业务任务，也不能安全回收所有已经借出的对象。因此应先停止接收新任务，等待借用者归还，再销毁连接池。

`reset()` 会先销毁池，再清除对象登记和 defer 上下文，使下一次获取时重新初始化：

```php
$pool->reset();
```

不要在仍有连接被借用、正在建连或健康检查运行时调用 `reset()`。常规请求处理中也不应销毁或重置整个连接池。
