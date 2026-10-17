# 连接池

`easyswoole/pool` 是基于 Swoole 协程 Channel 实现的通用对象池。它不只可以管理数据库连接，也可以管理 Redis 客户端、HTTP 客户端以及其他创建成本较高、能够重复使用的对象。

连接池主要负责：

- 限制每个进程最多创建多少个对象。
- 在多个协程之间借出和归还对象。
- 借出前检查对象是否仍然可用。
- 定期检查空闲对象并补足最小数量。
- 在负载较低时回收一部分空闲对象。
- 在对象损坏时关闭对象并释放池容量。

## 安装

在项目根目录执行：

```bash
composer require easyswoole/pool:^3.0
```

Pool 3.x 要求 PHP 8.1 及以上，并依赖 Swoole 的协程、Channel 和 Timer 能力。安装后可以确认实际版本：

```bash
composer show easyswoole/pool
```

## 运行模型

EasySwoole 的 Worker 是独立进程，PHP 对象不会在 Worker 之间共享。因此每个 Worker 都有自己的连接池：

```text
HTTP 请求
   ↓
Worker 进程
   ↓
Manager 中的连接池
   ├── 空闲连接 A
   ├── 空闲连接 B
   └── 已借出连接 C → 当前请求协程
```

如果服务有 4 个 Worker，每个池的 `maxObjectNum` 为 20，那么下游服务最多可能收到 `4 × 20 = 80` 个连接。设置池大小时必须按所有 Worker、TaskWorker 和自定义进程的总量计算。

连接池实例应在实际使用它的进程中创建。不要在服务 fork Worker 前建立数据库或 Redis 长连接，否则多个进程可能继承同一个文件描述符，造成协议数据错乱。

## 最小可运行示例

先新建 `App/Pool/DemoConnection.php`，定义一个可以被池管理的对象：

```php
<?php

namespace App\Pool;

use EasySwoole\Pool\ObjectInterface;

final class DemoConnection implements ObjectInterface
{
    private bool $connected = true;
    private array $context = [];

    public function execute(string $command): string
    {
        if (!$this->connected) {
            throw new \RuntimeException('connection is closed');
        }

        return "executed: {$command}";
    }

    public function beforeUse(): bool
    {
        return $this->connected;
    }

    public function intervalCheck(): bool
    {
        return $this->connected;
    }

    public function objectRestore(): void
    {
        $this->context = [];
    }

    public function gc(): void
    {
        $this->connected = false;
    }
}
```

再新建 `App/Pool/DemoPool.php`：

```php
<?php

namespace App\Pool;

use EasySwoole\Pool\AbstractPool;
use EasySwoole\Pool\ObjectInterface;

final class DemoPool extends AbstractPool
{
    protected function createObject(): ObjectInterface
    {
        return new DemoConnection();
    }
}
```

最后在项目根目录新建 `pool-demo.php`。前两步的 `App/Pool/...` 文件会通过安装器配置的 `App\` 自动加载；这个脚本则需要显式加载 `vendor/autoload.php`：

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use App\Pool\DemoConnection;
use App\Pool\DemoPool;
use EasySwoole\Pool\Config;
use Swoole\Coroutine;

Coroutine\run(function (): void {
    $pool = new DemoPool(new Config([
        'minObjectNum' => 0,
        'maxObjectNum' => 10,
    ]));

    $result = $pool->invoke(
        fn (DemoConnection $connection) => $connection->execute('ping')
    );

    echo $result, PHP_EOL;
});
```

运行 `php pool-demo.php`，预期输出 `executed: ping`。这个演示对象不连接数据库或 Redis，所以不需要启动外部服务。`invoke()` 会获取一个对象，把它传给回调，并在回调结束后自动归还。控制器中的一次性操作优先使用这种方式，可以避免遗漏归还。接入框架时不要每次请求都 `new DemoPool()`；先按[Manager 与框架接入](/Library/Pool/manager.md)在全局初始化事件注册，再在控制器中获取。

## 学习顺序

建议按下面顺序阅读：

1. [连接对象与生命周期](/Library/Pool/object.md)：理解池为什么需要四个生命周期方法。
2. [连接池配置](/Library/Pool/config.md)：确定容量、等待时间和检查周期。
3. [Manager 与框架接入](/Library/Pool/manager.md)：在框架全局初始化事件中注册连接池。
4. [获取、归还与销毁](/Library/Pool/usage.md)：选择 `invoke()`、`defer()` 或 `getObj()`。
5. [预热、检查与监控](/Library/Pool/maintenance.md)：处理冷启动、健康检查和状态观测。
