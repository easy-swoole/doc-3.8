# 获取、归还与销毁

Pool 提供三种主要使用方式。对新项目建议优先使用 `invoke()`，只有确实需要控制连接生命周期时才直接调用 `getObj()`。

## invoke：回调结束自动归还

```php
use App\Pool\DemoConnection;
use EasySwoole\Pool\Manager;

$pool = Manager::getInstance()->get('demo');
if ($pool === null) {
    throw new \RuntimeException('demo pool is not registered');
}

$result = $pool->invoke(
    function (DemoConnection $connection): string {
        return $connection->execute('select');
    },
    0.5
);
```

第二个参数是等待空闲对象的秒数。回调正常返回或抛出异常，`invoke()` 都会在 `finally` 中尝试归还对象。

不要从回调中返回 `$connection` 并在外部继续使用，也不要在回调内部手动归还它。回调结束后，这个对象可能已经被其他协程借走。

嵌套调用同一个池会再次借连接：

```php
$pool->invoke(function (DemoConnection $first) use ($pool): void {
    $pool->invoke(function (DemoConnection $second): void {
        // 这里同时占用了两个对象。
    });
});
```

池容量为 1 时，内层调用会等待并最终超时。连续操作同一资源时，应放在同一个回调中完成。

## defer：协程结束自动归还

```php
/** @var DemoConnection $connection */
$connection = $pool->defer(0.5);
$connection->execute('first');
$connection->execute('second');
```

`defer()` 会把对象保存到当前协程上下文，在协程结束时自动归还。同一协程对同一个池重复调用，会得到同一个对象：

```php
$first = $pool->defer();
$second = $pool->defer();

assert($first === $second);
```

它适合同一请求内多层代码共享同一个连接，但要注意：

- 连接会一直占用到整个协程结束。
- 长时间运行的消费协程不适合长期持有 defer 对象。
- 不要把 defer 得到的对象交给子协程使用或归还。
- 同一协程需要同时使用两个连接时，应改用 `getObj()`。

## getObj：手动控制

```php
use EasySwoole\Pool\Exception\PoolEmpty;

$connection = null;

try {
    $connection = $pool->getObj(0.5);
    if ($connection === null) {
        throw new \RuntimeException('no healthy connection');
    }

    $result = $connection->execute('query');
} catch (PoolEmpty $error) {
    // 池已达到上限，并且等待 0.5 秒后仍没有空闲对象。
    throw new \RuntimeException('service is busy', 0, $error);
} finally {
    if ($connection !== null) {
        $pool->recycleObj($connection);
    }
}
```

`getObj(?float $timeout = null, int $tryTimes = 3)` 的结果需要区分：

- 池耗尽且等待超时：抛出 `PoolEmpty`。
- `beforeUse()` 返回 `false` 且重试耗尽：可能返回 `null`。
- 创建连接失败：`createObject()` 的异常直接抛出。
- 池已经销毁：抛出 Pool 组件的 `Exception`。

`tryTimes` 用于借出前健康检查失败后的重试，不是创建连接失败后的重试次数。

## recycleObj：正常归还

```php
$pool->recycleObj($connection);
$connection = null;
```

归还时 Pool 会先执行 `objectRestore()`，然后把对象放回 Channel。归还完成后必须放弃当前引用，不能继续操作对象。

归还外部创建的对象、重复归还对象，或者归还已经在池中的对象时，通常会返回 `false`。

## unsetObj：丢弃损坏对象

当业务操作已经确认连接损坏，不应再把它放回池中：

```php
$connection = $pool->getObj();
$reusable = true;

try {
    $connection->execute('query');
} catch (BrokenConnectionException $error) {
    $reusable = false;
    $pool->unsetObj($connection);
    throw $error;
} finally {
    if ($reusable) {
        $pool->recycleObj($connection);
    }
}
```

`unsetObj()` 会从池的对象登记中删除它、调用 `gc()` 并释放一个容量名额。仅执行 PHP 的 `unset($connection)` 不会通知连接池释放容量。

## 超时范围

`getObj(0.5)` 的超时只限制从 Swoole Channel 等待对象的时间，不包含：

- `createObject()` 建立连接的时间。
- `beforeUse()` 探活时间。
- 业务查询或网络读写时间。
- `objectRestore()` 和 `gc()` 时间。

因此客户端本身还要分别设置连接超时、读写超时和探活超时。
