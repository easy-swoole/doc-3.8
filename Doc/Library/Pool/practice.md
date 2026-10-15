# 实践建议与常见问题

## 推荐的选择顺序

根据业务场景选择接口：

| 场景 | 推荐接口 | 原因 |
| --- | --- | --- |
| 一次回调完成查询 | `invoke()` | 异常时也会尝试自动归还 |
| 同一请求的多层代码共享连接 | `defer()` | 当前协程重复获取同一对象 |
| 需要同时借多个对象 | `getObj()` | 可以分别控制每个对象的生命周期 |
| 连接已经损坏 | `unsetObj()` | 关闭对象并释放容量，不再复用 |

无论选择哪种方式，都不要在对象归还后继续使用旧引用，也不要把同一个连接交给多个协程并发操作。

## 完整的业务调用封装

可以用服务类统一处理池不存在、池耗尽和连接归还：

```php
<?php

namespace App\Service;

use App\Pool\DemoConnection;
use EasySwoole\Pool\Exception\PoolEmpty;
use EasySwoole\Pool\Manager;

final class RemoteService
{
    public function execute(string $command): string
    {
        $pool = Manager::getInstance()->get('demo');
        if ($pool === null) {
            throw new \RuntimeException('demo pool is not registered');
        }

        try {
            return $pool->invoke(
                fn (DemoConnection $connection) => $connection->execute($command),
                0.5
            );
        } catch (PoolEmpty $error) {
            throw new \RuntimeException('connection pool is busy', 0, $error);
        }
    }
}
```

控制器只依赖 `RemoteService`，不需要重复编写池获取逻辑。

## 事务应该怎样使用

事务必须在一次借用期间完成：

```php
$pool->invoke(function (DatabaseConnection $connection): void {
    $connection->beginTransaction();

    try {
        $connection->insertOrder();
        $connection->insertOrderItems();
        $connection->commit();
    } catch (\Throwable $error) {
        $connection->rollBack();
        throw $error;
    }
});
```

不要分别调用两次 `invoke()` 完成同一事务，因为两次可能取得不同连接。连接对象的 `objectRestore()` 也应检查未结束事务并回滚，防止状态泄漏。

## PoolEmpty 应该怎样处理

`PoolEmpty` 表示在等待时间内没有取得对象，常见原因包括：

- 并发超过池容量。
- 某些路径忘记归还对象。
- 下游操作太慢，连接长时间被占用。
- `defer()` 所在协程运行时间过长。
- 健康检查或新建连接本身很慢。

HTTP 服务通常返回 503，并记录池名称、等待时间和 `status()`。是否重试取决于业务是否幂等；写操作不能在不确定执行结果时盲目重试。

## 为什么 createdNum 一直增长

Pool 会按需创建对象，直到达到最大数量。请依次检查：

1. 每次 `getObj()` 是否都在 `finally` 中归还或销毁。
2. 是否有长时间不结束的协程使用 `defer()`。
3. 查询、网络请求或锁等待是否过慢。
4. `objectRestore()` 是否抛出异常，导致对象被销毁并重建。

达到高水位不一定是泄漏；持续出现 `PoolEmpty` 才说明容量或使用方式需要重点排查。

## 为什么设置了 minObjectNum 却没有连接

`minObjectNum` 是补充目标，不会在构造池时立即创建。需要在 Worker 启动后的协程中执行：

```php
$pool->keepMin();
```

连接池首次初始化后，周期健康检查也会在每轮结束时补充最小数量。

## 为什么 getObj 超时比配置更久

连接池超时只控制 Channel 等待，不控制建连、探活和客户端读写。应该同时配置：

- Pool 的 `getObjectTimeout`。
- 客户端连接超时。
- 客户端读写超时。
- `beforeUse()` 和 `intervalCheck()` 使用的探活超时。
- 整个业务调用的总时间预算。

## 错误处理注意事项

对象创建异常会直接交给调用方。恢复、清理和后台检查中的异常，组件部分路径会通过 `trigger_error()` 报告。

如果项目把 `E_USER_NOTICE` 转换为异常，后台回调也可能受到影响。因此：

- 生命周期方法要尽量可靠，并自行控制网络超时。
- 请求入口、定时任务和消费循环应设置最终的 `Throwable` 边界。
- 记录池耗尽、创建失败、探活失败和归还失败日志。
- 不要认为返回类型为 `bool` 就代表内部绝不会抛异常。

## 多进程连接预算

假设有：

- 8 个 HTTP Worker，每个池上限 20。
- 4 个 TaskWorker，每个池上限 10。
- 发布期间新旧两组 Worker 短暂共存。

稳定状态连接上限为：

```text
8 × 20 + 4 × 10 = 200
```

热重载或平滑发布时还要预留重叠空间。数据库最大连接数必须高于应用连接预算，并为管理连接、迁移脚本和其他服务保留余量。
