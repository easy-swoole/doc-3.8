# Manager 与框架接入

`EasySwoole\Pool\Manager` 是当前进程内的连接池注册表。业务代码可以用名称取得连接池，不需要到处传递池实例。

## 注册与获取

```php
use App\Pool\DemoPool;
use EasySwoole\Pool\Config;
use EasySwoole\Pool\Manager;

$pool = new DemoPool(new Config([
    'minObjectNum' => 2,
    'maxObjectNum' => 10,
]));

Manager::getInstance()->register($pool, 'demo');

$registeredPool = Manager::getInstance()->get('demo');
if ($registeredPool === null) {
    throw new \RuntimeException('demo pool is not registered');
}
```

不传名称时，Manager 使用连接池类名作为键：

```php
Manager::getInstance()->register($pool);
$pool = Manager::getInstance()->get(DemoPool::class);
```

明确使用短名称通常更方便切换多套配置，例如 `redis.default`、`redis.cache` 和 `database.reporting`。

## 在全局初始化事件中注册

编辑项目根目录的 `EasySwooleEvent.php`，在框架全局 `initialize()` 事件中创建并注册连接池：

```php
<?php

use App\Pool\DemoPool;
use EasySwoole\EasySwoole\AbstractInterface\Event;
use EasySwoole\EasySwoole\Swoole\EventRegister;
use EasySwoole\Pool\Config;
use EasySwoole\Pool\Manager;

class EasySwooleEvent implements Event
{
    public static function initialize(): void
    {
        $config = new Config([
            'minObjectNum' => 2,
            'maxObjectNum' => 10,
            'getObjectTimeout' => 1.0,
        ]);

        Manager::getInstance()->register(
            new DemoPool($config),
            'demo'
        );
    }

    public static function mainServerCreate(EventRegister $register): void
    {
        $register->add(
            EventRegister::onWorkerStart,
            function (\Swoole\Server $server, int $workerId): void {
                if ($server->taskworker) {
                    return;
                }

                // 注册已经在 initialize() 完成；这里只做 Worker 预热。
                $pool = Manager::getInstance()->get('demo');
                if ($pool !== null) {
                    go(static function () use ($pool): void {
                        $pool->keepMin();
                    });
                }
            }
        );
    }
}
```

`initialize()` 在框架全局初始化阶段执行。这里的 `new DemoPool()` 和 `register()` 只建立 PHP 配置对象与注册关系，不会立即建立数据库、Redis 或其他网络连接，因此可以在全局初始化事件中完成。

Swoole 创建 Worker 后，每个进程会拥有自己的一份 Manager 和 Pool。真正的连接会在该进程第一次 `getObj()`、`invoke()`、`defer()` 或 `keepMin()` 时建立，不会跨进程共用同一个连接。

## 可选的 Worker 预热

注册放在 `initialize()`；预热则是可选项。完全删除下面的 `onWorkerStart` 代码，连接池依然可以正常使用，只会在首次业务调用时按需创建连接。

只有希望减少第一批请求的建连延迟时，才在 `onWorkerStart` 后的协程中调用 `keepMin()`。TaskWorker 不使用该池时可以跳过预热：

```php
if ($server->taskworker) {
    return;
}
```

即使跳过预热，TaskWorker 仍然继承了注册信息。如果它后来调用连接池，连接会按需创建。HTTP Worker 和 TaskWorker 都使用连接时，要把两类进程的连接数一起计入下游连接预算。

## 在控制器中使用

```php
<?php

namespace App\HttpController;

use App\Pool\DemoConnection;
use EasySwoole\Http\AbstractInterface\Controller;
use EasySwoole\Pool\Manager;

final class PoolDemo extends Controller
{
    public function index(): void
    {
        $pool = Manager::getInstance()->get('demo');
        if ($pool === null) {
            $this->response()->withStatus(503);
            $this->writeJson(503, null, 'connection pool is unavailable');
            return;
        }

        $result = $pool->invoke(
            fn (DemoConnection $connection) => $connection->execute('ping')
        );

        $this->writeJson(200, ['result' => $result]);
    }
}
```

线上代码还应捕获 `PoolEmpty` 和客户端异常，把池繁忙与下游故障转换成合适的 HTTP 响应，并记录日志和监控指标。

## 同名注册的注意事项

再次注册同名池会直接替换 Manager 中的引用，不会自动销毁旧池：

```php
Manager::getInstance()->register($newPool, 'demo');
```

运行中直接替换可能遗留旧 Timer 和连接。需要更换连接池时，应先停止新请求、等待旧连接归还，再销毁旧池并注册新实例。

`Manager::resetAll()` 会对已注册的池执行 `destroy()`，不会删除注册名称，也不会把这些池恢复为可用状态。若要继续使用某个实例，需要对该池调用 `reset()`，但常驻服务更建议在安全的进程生命周期中重建池。
