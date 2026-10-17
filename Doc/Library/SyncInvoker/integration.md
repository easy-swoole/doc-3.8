# 同步调用：在 EasySwoole 中接入

框架项目需要做三件事：定义 Driver，在服务启动前附加同步进程，然后在控制器或业务服务中调用。不要在每次 HTTP 请求中创建 `SyncInvoker` 或调用 `attachServer()`；服务启动后已经不能再添加这类自定义进程。

## 第一步：定义要执行的方法

新建 `App/Sync/LegacyDriver.php`：

```php
<?php

namespace App\Sync;

use EasySwoole\SyncInvoker\AbstractDriver;

class LegacyDriver extends AbstractDriver
{
    public function calculate(int $a, int $b): void
    {
        sleep(1); // 模拟阻塞式 SDK；实际项目中替换成 SDK 调用。
        $this->response($a + $b);
    }
}
```

客户端能调用的是 Driver 的 public 方法。将真正的阻塞代码放在这些方法中；调用完成后使用 `$this->response($value)` 指定返回数据。如果不设置响应值，调用方无法取得业务结果。

## 第二步：定义单例并在启动前挂载进程

新建 `App/Sync/InvokerHolder.php`。组件库自带的 `Singleton` trait 提供 `getInstance()`，不必再手写静态属性和 `set()/get()`：

```php
<?php

namespace App\Sync;

use EasySwoole\Component\Singleton;
use EasySwoole\SyncInvoker\SyncInvoker;

class InvokerHolder extends SyncInvoker
{
    use Singleton;
}
```

编辑项目根目录的 `EasySwooleEvent.php`，在已有的 `mainServerCreate()` 中加入下面代码；不要覆盖原有事件注册：

```php
use App\Sync\InvokerHolder;
use App\Sync\LegacyDriver;
use EasySwoole\EasySwoole\ServerManager;
use EasySwoole\EasySwoole\Swoole\EventRegister;

public static function mainServerCreate(EventRegister $register): void
{
    $invoker = InvokerHolder::getInstance();
    $invoker->getConfig()->setDriver(new LegacyDriver());
    $invoker->getConfig()->setWorkerNum(2);

    $server = ServerManager::getInstance()->getSwooleServer();
    $invoker->attachServer($server);
}
```

`mainServerCreate()` 在服务启动前执行，适合创建组件所需的共享表并把同步进程加到主 Swoole Server。这里必须首次调用 `getInstance()` 并完成 `attachServer()`；之后 HTTP Worker 继承主进程中已初始化的实例。`Singleton` 是进程内单例，不表示多个 Worker 共享同一份普通 PHP 属性；跨进程协调依靠组件的共享表和同步进程。修改同步进程数量、Driver 或这段启动代码后，应完整重启服务，不能只依赖 Worker reload。单例作用域可参考[单例模式](/Component/singleton.md)。

## 第三步：在控制器中调用

新建 `App/HttpController/SyncDemo.php`：

```php
<?php

namespace App\HttpController;

use App\Sync\InvokerHolder;
use EasySwoole\Http\AbstractInterface\Controller;

class SyncDemo extends Controller
{
    public function index(): void
    {
        // 2.0 表示本次调用的总时间预算，单位为秒。
        $result = InvokerHolder::getInstance()->invoke(2.0)->calculate(1, 2);
        $this->response()->write((string) $result);
    }
}
```

启动 EasySwoole 服务后，按项目的控制器映射规则访问该控制器，预期正文为 `3`。`invoke()` 应在 HTTP 请求所在的协程中调用；它通过 Unix Socket 等待独立进程返回结果。同步 Worker 内部执行 `calculate()`，不会把阻塞代码放回 HTTP Worker。

下一章：[超时、并发与使用边界](/Library/SyncInvoker/practice.md)。

## 源码依据

- [组件 README（2.2.2）](https://github.com/easy-swoole/sync-invoker/blob/2.2.2/README.md)
- [SyncInvoker（2.2.2）](https://github.com/easy-swoole/sync-invoker/blob/2.2.2/src/SyncInvoker.php)
