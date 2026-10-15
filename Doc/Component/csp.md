# 并发调用 Csp

`Csp` 用于并发执行一组有名称的 callable，并按任务名称收集返回值。它适合聚合接口同时查询多个互不依赖的数据源：

```text
                ┌─ user 任务 ──── 用户服务
请求协程 ────────┼─ orders 任务 ── 订单服务
                └─ profile 任务 ─ 数据库
                         ↓
                 按名称合并结果
```

`Csp` 会为每个任务直接创建一个协程，不限制最大并发数。任务数量很多或需要背压时，应使用 [CoroutineRunner](/Component/runner-task.md)。

## 基本用法

```php
use EasySwoole\Component\Csp;

Co\run(function (): void {
    $csp = new Csp();

    $csp->add('user', function (): array {
        return ['id' => 1001, 'name' => 'Alice'];
    });

    $csp->add('orders', function (): array {
        return [2001, 2002];
    });

    $result = $csp->exec(3.0);

    var_dump($result['user'] ?? null);
    var_dump($result['orders'] ?? null);
    echo $csp->successNum();
});
```

正常完成后，结果结构类似：

```php
[
    'user' => ['id' => 1001, 'name' => 'Alice'],
    'orders' => [2001, 2002],
]
```

任务完成顺序不固定，但结果使用 `add()` 时提供的名称作为数组 key，因此调用方不需要依赖协程完成顺序。

## add 的行为

```php
$csp->add($itemName, $callable);
```

- `$itemName` 是结果数组的 key。
- `$callable` 的返回值会成为该 key 的值。
- `add()` 返回当前 `Csp` 对象，可以链式调用。
- 添加新名称不会清除已经登记的其他任务。
- 重复使用同一个名称时，新 callable 会覆盖旧 callable。

```php
$csp
    ->add('user', $loadFromDatabase)
    ->add('orders', $loadOrders)
    ->add('user', $loadFromCache); // 覆盖第一个 user 任务
```

任务返回 `false`、`null`、`0` 或空数组仍会被正常放入结果，因为组件传递的是包含 key 和 result 的完整消息。

## exec 和超时

```php
$result = $csp->exec(5.0);
```

- 超时单位为秒。
- 传入 `0` 或负数时按近似无限等待处理。
- 返回值只包含等待期间已经完成并被收集的任务。
- `successNum()` 返回本次执行已收集的结果数量。
- 超时不会取消仍在运行的任务协程。

内部以最长 1 秒为一次 Channel 等待周期，再检查总耗时。因此实际返回时间可能略微超过传入的超时时间。每个网络请求、数据库查询等底层 I/O 仍应设置自己的超时。

判断结果时应按 key 检查，不要只比较数量：

```php
$result = $csp->exec(2.0);

if (!array_key_exists('user', $result)) {
    // user 任务没有在等待时间内返回结果。
}
```

## 任务异常处理

`Csp` 没有统一的异常回调。任务 callable 在把结果写入 Channel 之前抛出异常时，异常会从该任务协程继续抛出，并且该任务不会提交结果。如果运行环境捕获异常后仍继续执行，`exec()` 会缺少这个完成结果并等待到整体超时。因此业务应在任务内部处理异常。

需要把失败转换成可判断结果时，应在每个任务内部捕获异常：

```php
$csp->add('user', function (): array {
    try {
        return [
            'ok' => true,
            'data' => UserService::find(1001),
        ];
    } catch (Throwable $throwable) {
        return [
            'ok' => false,
            'error' => $throwable->getMessage(),
        ];
    }
});
```

生产环境不要把敏感异常详情直接返回给外部客户端，可以在任务中记录完整异常，只在聚合结果中保存安全错误码。

## Channel 容量

构造参数用于设置内部结果 Channel 的容量：

```php
$csp = new Csp(64);
```

默认容量为 64。任务协程完成后会把结果推入 Channel；容量满时，后续任务会暂时挂起，直到 `exec()` 消费结果。该参数不会限制创建的任务协程数量，也不是并发数。

## 对象生命周期

任务定义保存在 `Csp` 对象中，执行完成后不会自动清空。再次调用 `exec()` 会重新执行已登记的全部任务。

尤其要避免在一次 `exec()` 超时后立即复用同一个对象：上一次尚未结束的协程仍可能把结果写入同一个 Channel，下一次执行可能读到上一批的延迟结果。推荐每一批并发调用创建一个新的 `Csp`：

```php
function loadDashboard(): array
{
    $csp = new Csp();
    $csp->add('user', fn () => UserService::current());
    $csp->add('orders', fn () => OrderService::recent());

    return $csp->exec(3.0);
}
```

## 与 WaitGroup 的区别

| 对比项 | `Csp` | `WaitGroup` |
| --- | --- | --- |
| 任务标识 | 每个任务有名称 | 没有任务名称 |
| 返回值 | 自动按名称收集 | 不收集返回值 |
| 完成信号 | callable 返回后自动写入结果 | 回调自动 done，或外部手动 done |
| 适合场景 | 聚合多个查询结果 | 只等待一组任务全部结束 |

## 常见错误

- 一次添加成百上千个任务，却误以为 Csp 会限制并发数。
- 任务异常没有捕获，导致结果缺失并一直等到超时。
- 超时后认为后台任务已经停止。
- 超时后复用同一个对象，混入上一批任务的延迟结果。
- 只查看 `successNum()`，不检查具体缺少了哪个 key。

## 源码依据

- [Csp](https://github.com/easy-swoole/component/blob/master/src/Csp.php)
