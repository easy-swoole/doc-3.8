# 协程锁 ChannelLock

`ChannelLock` 基于容量为 1 的 `Swoole\Coroutine\Channel` 实现命名协程锁，用于防止同一 Worker 进程中的多个协程同时进入同一个临界区。

它是进程内协程锁，不是跨进程锁，也不是分布式锁：

```text
同一 Worker 内的多个协程     可以互斥
不同 Worker 进程            不能互斥
不同服务器                  不能互斥
```

## 使用 deferLock 自动释放

业务运行在一个生命周期明确的协程中时，推荐使用 `deferLock()`：

```php
use EasySwoole\Component\ChannelLock;

Co\run(function (): void {
    go(function (): void {
        $lock = ChannelLock::getInstance();

        if (!$lock->deferLock('order:1001', 1.0)) {
            throw new RuntimeException('order lock timeout');
        }

        // 当前协程持有 order:1001 锁。
        OrderService::update(1001);

        // 当前协程退出时自动释放。
    });
});
```

`deferLock()` 先尝试获得锁，成功后通过 `Coroutine::defer()` 注册释放回调。无论协程正常结束还是因为异常退出，defer 回调都会执行。

第二个参数是等待锁的超时时间，单位为秒：

- `1.0`：最多等待 1 秒。
- `0`：不等待，无法立即获得锁就返回 `false`。
- 默认 `-1`：持续等待，不设置超时。

生产环境通常应该传入明确的超时时间，避免持锁协程异常阻塞时，其他协程永久等待。

## 使用 lock 和 unlock 手动释放

需要在临界区结束后立即释放，而不是等整个协程退出时，可以手动调用 `lock()` 和 `unlock()`：

```php
$lock = ChannelLock::getInstance();
$locked = $lock->lock('inventory:1001', 0.5);

if (!$locked) {
    throw new RuntimeException('inventory lock timeout');
}

try {
    InventoryService::decrease(1001, 1);
} finally {
    $lock->unlock('inventory:1001');
}
```

必须把 `unlock()` 放在 `finally` 中。如果临界区抛出异常却没有释放，后续等待同名锁的协程可能一直阻塞。

`unlock()` 只允许持有该锁的协程释放：

- 当前协程持有指定锁并成功释放时返回 `true`。
- 当前协程未持有该锁时返回 `false`。
- 其他协程尝试释放时返回 `false`。
- 已经释放后再次调用也返回 `false`。

## 同一协程重复加锁

同一协程已经持有某个锁时，再次调用 `lock()` 会直接返回 `true`，不会再次阻塞：

```php
$lock->lock('order:1001', 1.0); // 真正取得锁
$lock->lock('order:1001', 1.0); // 直接返回 true

$lock->unlock('order:1001');    // 一次调用就完全释放
```

组件不维护重入次数，因此它不是“加锁两次就必须解锁两次”的计数型重入锁。一次 `unlock()` 就会完全释放；第二次 `unlock()` 返回 `false`。

同一协程不要对同一个锁重复调用 `deferLock()`。每次成功调用都会注册一个 defer 回调，但第一个回调已经完成释放，后续回调只能得到 `false`。

## 锁名称设计

锁名称决定互斥范围：

```php
// 所有协程竞争同一把全局订单锁。
$lock->deferLock('order', 1.0);

// 只有操作同一订单的协程互斥，不同订单可以并发。
$lock->deferLock("order:{$orderId}", 1.0);
```

锁名应稳定且可控。组件会为首次出现的锁名创建 Channel，并在当前进程内继续保存；不要直接使用无限增长的随机值作为锁名，否则可能持续增加内存占用。

## 适用范围

适合使用 `ChannelLock`：

- 同一 Worker 内多个协程修改同一进程内对象。
- 防止同一协程服务中的重复并发操作。
- 保护无法使用原子操作完成的短临界区。

不适合使用 `ChannelLock`：

- 多个 Worker 同时修改共享数据。
- 多台服务器之间的业务锁。
- 数据库库存、余额等必须持久保证一致性的操作。

跨进程或跨服务器场景应使用数据库事务、Redis 分布式锁或其他具备正确故障处理机制的协调方案。

## 注意事项

- 只能在 Swoole 协程环境中调用。
- 临界区应尽量短，不要在持锁期间执行无法控制时长的阻塞操作。
- 超时返回 `false` 只表示没有获得锁，不能继续执行受保护的业务。
- 锁按 Worker 隔离，不能用来保护 `Swoole\Table` 中跨 Worker 的复合读写流程。

## 源码依据

- [ChannelLock](https://github.com/easy-swoole/component/blob/master/src/ChannelLock.php)
