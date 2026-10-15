# 连接池配置

`EasySwoole\Pool\Config` 可以接收数组，也可以通过 setter 链式设置。

## 完整配置项

| 配置项 | 默认值 | 单位 | 作用 |
| --- | ---: | --- | --- |
| `maxObjectNum` | `16` | 个 | 当前池最多创建的对象总数 |
| `minObjectNum` | `8` | 个 | 预热及周期补充时希望保持的对象总数 |
| `getObjectTimeout` | `3.0` | 秒 | 从 Channel 等待对象的默认时间 |
| `intervalCheckTime` | `5000` | 毫秒 | 空闲对象健康检查周期，`<= 0` 表示关闭 |
| `intervalCheckBatchSize` | `8` | 个 | 每轮最多检查多少个空闲对象 |
| `waitLoadAverageTime` | `0.001` | 秒 | 平均等待时间低于该值时允许缩容 |
| `extraConf` | `null` | — | 交给自定义连接池使用的额外配置 |

## 使用数组配置

```php
use EasySwoole\Pool\Config;

$config = new Config([
    'minObjectNum' => 2,
    'maxObjectNum' => 20,
    'getObjectTimeout' => 1.5,
    'intervalCheckTime' => 10_000,
    'intervalCheckBatchSize' => 5,
    'waitLoadAverageTime' => 0.001,
    'extraConf' => [
        'host' => '127.0.0.1',
        'port' => 6379,
    ],
]);
```

读取配置：

```php
$max = $config->getMaxObjectNum();
$timeout = $config->getGetObjectTimeout();
$connectionConfig = $config->getExtraConf();
```

## 使用 setter

```php
$config = (new Config())
    ->setMinObjectNum(2)
    ->setMaxObjectNum(20)
    ->setGetObjectTimeout(1.5)
    ->setIntervalCheckTime(10_000)
    ->setIntervalCheckBatchSize(5)
    ->setWaitLoadAverageTime(0.001)
    ->setExtraConf(['host' => '127.0.0.1']);
```

数量必须满足：

```text
0 <= minObjectNum <= maxObjectNum
maxObjectNum >= 1
intervalCheckBatchSize >= 1
```

使用 setter 从默认值向下调整最大数量时，要先降低最小数量：

```php
$config = (new Config())
    ->setMinObjectNum(1)
    ->setMaxObjectNum(4);
```

用构造数组时不存在调用顺序问题。

## 如何确定 maxObjectNum

不要简单地把值设得很大。连接上限要同时考虑：

- 数据库或 Redis 能接受的最大连接数。
- EasySwoole Worker、TaskWorker 和自定义进程数量。
- 同一进程中有多少个命名连接池。
- 单次请求是否可能同时借用多个连接。

例如数据库允许应用使用 200 个连接，服务有 8 个 Worker，并保留 40 个连接给发布重叠和后台任务，则 HTTP Worker 中每个池可以先按下面估算：

```text
(200 - 40) / 8 = 20
```

这只是上限预算。实际还要根据下游吞吐、请求耗时和监控数据调整。

## minObjectNum 与冷启动

`minObjectNum` 不会在 `new Pool()` 时立即创建连接。它是 `keepMin()` 和周期补充使用的目标数量。

如果希望 Worker 启动后立即准备连接，需要主动调用：

```php
$pool->keepMin();
```

最小数量是“已创建对象总数”的目标，不是必须保持的空闲对象数；已借出的对象也计算在内。

## 运行中不要随意修改配置

Pool 保存的是同一个可变 `Config` 对象，但并非所有选项都适合运行时动态调整：

- 修改 `maxObjectNum` 不会重建已经创建的 Channel。
- 修改 `intervalCheckTime` 不会重新注册现有 Timer。
- `intervalCheckBatchSize` 会在下一轮检查时读取新值。

需要修改容量或检查周期时，更安全的方式是停止新请求、等待连接归还，然后重建连接池。
