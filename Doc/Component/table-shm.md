# 结构化共享内存 TableShm


`TableShm` 在 `Swoole\Table` 上增加序列化能力，可直接跨进程存取数组、标量等结构化数据。

```php
use EasySwoole\Component\TableShm;
use Swoole\Process;

// 必须在 fork 子进程或启动 Swoole Server 之前创建共享表。
$shm = new TableShm(
    maxRows: 1024,
    serializer: TableShm::SERIALIZER_PHP,
    columnSize: 65535
);

$process = new Process(function () use ($shm) {
    $shm->set('worker-status', [
        'pid' => getmypid(),
        'status' => 'ready',
    ]);
});

$process->start();
Process::wait();

$status = $shm->get('worker-status');
$exists = $shm->exists('worker-status');
$shm->delete('worker-status');
$shm->clear();
```

当前对外提供 `set()`、`get()`、`exists()`、`delete()` 和 `clear()`：`set()` 写入或覆盖一个键，`delete()` 删除指定键，`clear()` 清空全部键。底层 `Swoole\Table` 不对外暴露，行数统计等额外操作不属于该封装的公共 API。

构造参数说明：

- `$maxRows`：最大行数，默认 `64`，必须大于 `0`。
- `$serializer`：可选择 PHP、JSON 或 MsgPack，默认使用 PHP 序列化。
- `$columnSize`：每行 `data` 字段的字节容量，默认 `65535`。限制的是序列化后的数据长度，不是原始值长度；超过容量时 `set()` 会抛出 `LengthException`，避免被 Swoole 静默截断。

PHP 模式能保留更多 PHP 类型，但只应读取可信进程写入的数据；JSON 模式会把对象读取为关联数组，并会对资源等无法编码的值抛出 `JsonException`；MsgPack 模式要求安装 `ext-msgpack`。`maxRows` 与 `columnSize` 越大，占用的共享内存越多，应根据实际数据规模设置。

键不存在与存储值为 `null` 时，`get()` 都返回 `null`，需要区分时请先调用 `exists()`。`clear()` 会逐行删除当前数据，并不销毁底层共享内存表；并发读写期间调用时，不应把它视为原子操作。

使用 `getInstance()` 时，只有第一次调用传入的最大行数、序列化方式和列容量生效。`TableShm` 只能在同一台机器的相关进程间共享，不能替代 Redis 等跨机器存储。


## 源码依据

- [Component 仓库](https://github.com/easy-swoole/component)
