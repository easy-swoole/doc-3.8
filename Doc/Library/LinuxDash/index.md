# 运维指标：安装与快速开始

`easyswoole/linux-dash` 2.x 是系统指标采集组件，不是自带页面的监控平台。它读取 CPU、内存、磁盘、网络等信息，返回可直接访问属性或转成 JSON 的 Bean。下面以已发布的 `2.0.1` 为准；Linux 读取 `/proc` 等系统信息，macOS 使用 PHP FFI 调用系统 API，不通过 shell 执行 `top`、`free` 等命令。

## 先明确它能做什么

```text
你的 PHP 代码
    → new LinuxDash()
    → currentRam() / cpu() / disks() / ...
    → RamInfo / CpuInfo / DiskInfo 等 Bean
    → 自行展示、记录或输出给监控系统
```

组件只负责采集，不负责存储历史曲线、告警、鉴权或前端图表。在 EasySwoole 中使用它不需要注册事件或添加自定义进程；需要 Web 接口时，由你自己的控制器调用。组件读取的是**当前进程可见**的系统视图，不提供 Docker/Kubernetes 的 cgroup 配额指标。

## 安装和环境检查

在 EasySwoole **应用项目根目录**执行，不要在本文档仓库中安装：

```bash
composer require 'easyswoole/linux-dash:^2.0'
composer show easyswoole/linux-dash
php -v
```

组件要求 PHP 8.1 及以上，本身不依赖 Swoole 扩展。Linux 主机需要让运行用户能够读取相应 `/proc` 信息；磁盘等指标还受挂载点可见性影响。macOS 需要可用的 FFI 扩展，先检查：

```bash
php --ri ffi
```

如果 macOS 的 PHP 没有 FFI，或运行环境禁用了 FFI，创建 `LinuxDash` 时会报指标读取异常。`2.x` 支持 Linux 和 macOS；其他系统会在初始化时明确报不支持。

## 单脚本测试

在应用项目根目录新建 `linux-dash-demo.php`：

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use EasySwoole\LinuxDash\LinuxDash;

$dash = new LinuxDash(); // 根据 PHP_OS_FAMILY 自动选 Linux 或 macOS 驱动。

$result = [
    'system' => $dash->system(),
    'uptime' => $dash->uptime(),
    'load' => $dash->load(),
    'memory' => $dash->currentRam(),
    'cpu' => $dash->cpu(0.5), // 两次采样相隔约 0.5 秒。
];

echo json_encode(
    $result,
    JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR
), PHP_EOL;
```

运行：

```bash
php linux-dash-demo.php
```

输出中的数值取决于运行机器。结构类似：

```json
{
    "system": {"hostname": "node-01", "os": "Linux", "kernel": "6.12.0", "architecture": "x86_64", "logicalCpus": 4, "cpuModel": "Intel Xeon", "physicalCpus": 4, "cpuFrequencyHz": 2400000000, "performanceCpus": null, "efficiencyCpus": null},
    "uptime": {"seconds": 105570.22, "bootedAt": 1792916221},
    "load": {"one": 0.34, "five": 0.18, "fifteen": 0.16, "running": 1, "processes": 233},
    "memory": {"total": 17179869184, "used": 11747164160, "available": 5432705024},
    "cpu": {"usage": 17.35, "user": 7.41, "system": 4.69, "idle": 82.65, "iowait": 5.0, "steal": 0, "irq": 0.25, "cores": [{"core": 0, "usage": 17.35, "user": 7.41, "system": 4.69, "idle": 82.65, "iowait": 5.0, "steal": 0, "irq": 0.25}]}
}
```

`cores` 实际会列出各逻辑核心；上面只展示一个核心作为结构示意。Bean 的属性是公开只读的，也实现了 `JsonSerializable`，因此可以用 `$dash->currentRam()->available` 读取字段，或直接交给 `json_encode()`。容量字段的单位通常是**字节**，不是 MB；百分比字段则是 `0` 到 `100` 的数值。

接下来阅读[指标与返回数据](/Library/LinuxDash/metrics.md)，了解每个方法的单位、平台差异和采样耗时。

## 源码依据

- [linux-dash 2.0.1 README](https://github.com/easy-swoole/linux-dash/blob/2.0.1/README.md)
- [LinuxDash.php](https://github.com/easy-swoole/linux-dash/blob/2.0.1/src/LinuxDash.php)
