# 运维指标：指标与返回数据

上一章已经创建 `$dash = new LinuxDash()`。本章列出 2.x 的全部采集入口。所有返回 Bean 都有公开只读属性并支持 `json_encode()`；数组方法返回 Bean 列表，而不是关联数组。单位要按字段区分，不能把累计值直接当作瞬时速率。

## 方法总览

| 方法 | 主要返回值 | Linux | macOS |
| --- | --- | --- | --- |
| `currentRam()` | 物理内存容量 | 支持 | 支持 |
| `cpu(0.1)` | CPU 使用率及每核使用率 | 支持 | 支持 |
| `network(0.1)` | 网卡流量、速率和地址 | 支持 | 支持 |
| `disks()` | 已挂载文件系统容量 | 支持 | 支持 |
| `load()` | 1/5/15 分钟平均负载 | 支持 | 支持 |
| `swap()` | Swap 容量与累计换页数 | 支持 | 支持 |
| `uptime()` | 系统运行时间 | 支持 | 支持 |
| `system()` | 主机与 CPU 基本信息 | 支持 | 支持 |
| `diskIo(0.1)` | 块设备 I/O 次数、吞吐及延迟 | 支持 | 不支持，会抛异常 |
| `tcp()` | TCP 连接状态数量 | 支持 | 不支持，会抛异常 |
| `supportsPressure()` / `pressure()` | Linux PSI 资源压力 | 视内核及 `/proc` 而定 | 不支持 |

## CPU、内存与负载

```php
$ram = $dash->currentRam();
echo $ram->total, ' / ', $ram->used, ' / ', $ram->available, PHP_EOL;

$cpu = $dash->cpu(0.5);
echo $cpu->usage, '%', PHP_EOL;
foreach ($cpu->cores as $core) {
    echo 'CPU ', $core->core, ': ', $core->usage, '%', PHP_EOL;
}

$load = $dash->load();
echo $load->one, ' / ', $load->five, ' / ', $load->fifteen, PHP_EOL;
```

`RamInfo` 的 `total`、`used`、`available` 都是**字节**。`available` 是系统估算的可用量，不能简单用空闲内存代替。`CpuInfo` 的 `usage`、`user`、`system`、`idle`、`iowait`、`steal`、`irq` 均为百分比，`cores` 是每个逻辑核心的 `CpuCoreInfo` 列表；macOS 的 Linux 专有 CPU 分类（如 `iowait`、`steal`）返回 `0`。`load()` 的 `one`、`five`、`fifteen` 是平均负载，不是 CPU 百分比；Linux 另外提供 `running`、`processes`，macOS 这两个字段为 `null`。

`cpu(0.5)` 会读取两次累计计数器，中间等待约 0.5 秒。采样时间参数单位是**秒**，默认 `0.1`，负数会抛 `InvalidArgumentException`。不要在每个高频业务请求中重复采样。

## 磁盘、Swap 与系统信息

```php
foreach ($dash->disks() as $disk) {
    echo $disk->mounted, ': ', $disk->usedPercentage, '%', PHP_EOL;
}

$swap = $dash->swap();
$uptime = $dash->uptime();
$system = $dash->system();
```

`DiskInfo` 包含 `fileSystem`、`mounted`、`size`、`used`、`avail`、`usedPercentage`。容量以字节计，使用率为百分比。`inodes`、`inodesUsed`、`inodesAvailable`、`inodesUsedPercentage` 是可空字段，平台或权限无法提供时不能当作 `0`。`disks()` 返回当前进程可见的挂载点，可能包含多个文件系统。

`SwapInfo` 的 `total`、`used`、`available` 是字节；`pagesIn`、`pagesOut` 是系统启动以来累计换页**次数**，既不是字节，也不是每秒速率。`UptimeInfo::seconds` 是运行秒数，`bootedAt` 是估算的 Unix 启动时间戳。`SystemInfo` 提供 `hostname`、`os`、`kernel`、`architecture`、`logicalCpus`；`cpuModel`、`physicalCpus`、`cpuFrequencyHz`、`performanceCpus`、`efficiencyCpus` 可能为 `null`，不要假设每台机器都能读取。

## 网络与磁盘 I/O 速率

```php
foreach ($dash->network(1.0) as $nic) {
    echo $nic->interface, ': ', $nic->rxPerSecond, ' B/s ↓, ',
        $nic->txPerSecond, ' B/s ↑', PHP_EOL;
}
```

每个 `NetworkInfo` 的 `rx`、`tx` 是累计字节数；`rxPerSecond`、`txPerSecond` 才是采样区间的平均速率（B/s）。还包括累计包数 `rxPackets`、`txPackets`，错误数、丢包数，以及可空的 `mtu`、`mac`、`state` 和 `addresses`。后几项可能暴露内网地址或网卡信息，公开 HTTP 接口不宜无筛选输出。

Linux 可进一步采集块设备 I/O：

```php
foreach ($dash->diskIo(1.0) as $device) {
    if ($device->partition) {
        continue; // 只展示整盘，避免和分区数据重复计数。
    }
    echo $device->device, ': ', $device->readsPerSecond, ' read ops/s, ',
        $device->writeBytesPerSecond, ' write B/s', PHP_EOL;
}
```

`DiskIoInfo` 的 `reads`、`writes`、`readBytes`、`writeBytes` 为累计值；`readsPerSecond`、`writesPerSecond` 为 IOPS，`readBytesPerSecond`、`writeBytesPerSecond` 为 B/s，`busyPercentage` 为区间繁忙率。`readLatencyMs`、`writeLatencyMs` 是平均毫秒延迟，`queueDepth` 是估算的平均队列深度，`inProgress` 是采样结束时的 I/O 数量。macOS 调用 `diskIo()` 会抛 `UnsupportedMetricException`。

`network()` 与 `diskIo()` 和 `cpu()` 一样都需要两次采样。若顺序调用 `cpu(0.5)`、`network(1.0)`、`diskIo(1.0)`，请求光是采样等待就约需 2.5 秒。需要频繁展示时宜由后台定时采集并缓存结果，而不是让每个浏览器请求各自采样。

## TCP 连接与 PSI 压力

Linux 的 `$dash->tcp()` 返回 `TcpInfo`：`total` 是连接数量总和，`states` 仅包含数量大于零的状态，例如 `ESTABLISHED`、`TIME_WAIT`、`LISTEN`。macOS 不支持该方法，会抛 `UnsupportedMetricException`。

PSI（Pressure Stall Information）依赖 Linux 内核及可读的 `/proc/pressure`，应先检测：

```php
if ($dash->supportsPressure()) {
    $pressure = $dash->pressure();
    echo json_encode($pressure, JSON_THROW_ON_ERROR), PHP_EOL;
}
```

`PressureInfo` 有 `cpu`、`memory`、`io` 三组；每组包含系统实际提供的 `some` 和/或 `full`。其中 `avg10`、`avg60`、`avg300` 是相应窗口内的受阻时间百分比，`total` 是累计受阻**微秒**。不能假设每组都有 `full`。macOS 或没有相应 `/proc/pressure` 文件时，`supportsPressure()` 为 `false`；直接调用 `pressure()` 会抛 `UnsupportedMetricException`。

## 各方法的返回样例

以下按组件 README 的示例展示 `json_encode()` 后的数据结构。数值只用于认识字段，不代表你的机器的实际状态；`network()`、`disks()`、`diskIo()` 返回数组，其余指标方法返回一个 Bean。

### `currentRam()`：物理内存

```json
{"total":17179869184,"used":11747164160,"available":5432705024}
```

### `cpu(0.5)`：CPU 总体与每核

```json
{
  "usage":12.35,"user":7.41,"system":4.69,"idle":82.65,
  "iowait":5.0,"steal":0.0,"irq":0.25,
  "cores":[
    {"core":0,"usage":15.0,"user":9.0,"system":6.0,"idle":80.0,
     "iowait":5.0,"steal":0.0,"irq":0.0}
  ]
}
```

`cores` 在真实输出中会按逻辑核心列出多项，示例只展示一项。

### `network(1.0)`：每张网卡

```json
[
  {
    "interface":"eth0","rx":267561846,"tx":174725169,
    "rxPerSecond":1197.39,"txPerSecond":5787.4,
    "rxPackets":4162112,"txPackets":2197013,
    "rxErrors":0,"txErrors":0,"rxDropped":3,"txDropped":0,
    "collisions":0,"mtu":1500,"mac":"00:11:22:33:44:55",
    "state":"up","addresses":["10.0.0.10","fe80::1"]
  }
]
```

### `disks()`：每个挂载点

```json
[
  {
    "fileSystem":"/dev/vda3","size":42670731264,
    "used":8629985280,"avail":34040745984,"usedPercentage":20.22,
    "mounted":"/","inodes":2621440,"inodesUsed":134000,
    "inodesAvailable":2487440,"inodesUsedPercentage":5.11
  }
]
```

### `load()`：平均负载

```json
{"one":0.34,"five":0.18,"fifteen":0.16,"running":1,"processes":233}
```

macOS 的 `running` 和 `processes` 为 `null`。

### `swap()`：交换空间

```json
{"total":4294963200,"used":49152,"available":4294914048,"pagesIn":0,"pagesOut":13}
```

`pagesIn`、`pagesOut` 是累计页数，不能按字节理解。

### `uptime()`：运行时间

```json
{"seconds":105570.22,"bootedAt":1792916221}
```

### `system()`：主机信息

README 用 macOS 主机展示了可空的频率字段及 Apple Silicon 核心类型：

```json
{
  "hostname":"apple-silicon-node","os":"macOS","kernel":"24.6.0",
  "architecture":"arm64","logicalCpus":8,"cpuModel":"Apple M1",
  "physicalCpus":8,"cpuFrequencyHz":null,
  "performanceCpus":4,"efficiencyCpus":4
}
```

Linux 上 `performanceCpus`、`efficiencyCpus` 通常为 `null`。

### `diskIo(1.0)`：块设备 I/O（仅 Linux）

```json
[
  {
    "device":"vda","reads":27312,"writes":101154,
    "readBytes":880077824,"writeBytes":1646177792,
    "readsPerSecond":12.5,"writesPerSecond":8.2,
    "readBytesPerSecond":1048576,"writeBytesPerSecond":524288,
    "busyPercentage":3.5,"readLatencyMs":3.2,"writeLatencyMs":4.1,
    "queueDepth":0.15,"inProgress":1,"partition":false
  }
]
```

### `tcp()`：TCP 状态（仅 Linux）

```json
{"states":{"ESTABLISHED":2,"TIME_WAIT":4,"LISTEN":3},"total":9}
```

`states` 只列出数量大于零的状态，因此键会随当前连接变化。

### `supportsPressure()` 与 `pressure()`：PSI 压力

`supportsPressure()` 返回布尔值：Linux 内核暴露并允许读取三类 PSI 文件时为 `true`，否则为 `false`。检查为 `true` 后，`pressure()` 的 README 样例为：

```json
{
  "cpu":{"some":{"avg10":1.0,"avg60":2.0,"avg300":3.0,"total":4000}},
  "memory":{
    "some":{"avg10":0.1,"avg60":0.2,"avg300":0.3,"total":400},
    "full":{"avg10":0.01,"avg60":0.02,"avg300":0.03,"total":40}
  },
  "io":{
    "some":{"avg10":0.5,"avg60":0.6,"avg300":0.7,"total":800},
    "full":{"avg10":0.05,"avg60":0.06,"avg300":0.07,"total":80}
  }
}
```

某些内核不提供 `cpu.full` 等字段，按实际返回的键读取，不要假设所有分组都有 `some` 和 `full`。

## 错误处理

```php
use EasySwoole\LinuxDash\Exception\MetricReadException;
use EasySwoole\LinuxDash\Exception\UnsupportedMetricException;

try {
    $diskIo = $dash->diskIo(0.5);
} catch (UnsupportedMetricException $error) {
    // 当前平台没有这个指标；不要把它误报为“0 IOPS”。
} catch (MetricReadException $error) {
    // 平台支持，但本次采集失败；记录日志并稍后再试。
}
```

## 源码依据

- [linux-dash 2.0.1 README](https://github.com/easy-swoole/linux-dash/blob/2.0.1/README.md)
- [DriverInterface.php](https://github.com/easy-swoole/linux-dash/blob/2.0.1/src/AbstractInterface/DriverInterface.php)
