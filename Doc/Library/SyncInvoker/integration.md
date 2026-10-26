# 同步调用：在 EasySwoole 中接入

框架项目需要做三件事：定义 Driver，在服务启动前附加同步进程，然后在控制器或业务服务中调用。不要在每次 HTTP 请求中创建 `SyncInvoker` 或调用 `attachServer()`；组件会在构造时创建共享表，调用 `attachServer()` 时把同步进程加入主服务。

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

客户端能调用的是 Driver 的 public 方法。将真正的阻塞代码放在这些方法中；调用完成后使用 `$this->response($value)` 指定返回数据。不要通过方法的 `return` 传递结果。Driver 在同一同步进程中会复用，如果某次调用没有设置响应值，可能拿到前一次调用留下的值；业务成功和失败分支都必须明确设置响应。

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
use EasySwoole\SyncInvoker\Worker;

public static function mainServerCreate(EventRegister $register): void
{
    $invoker = InvokerHolder::getInstance();
    $invoker->getConfig()->setDriver(new LegacyDriver());
    $invoker->getConfig()->setWorkerNum(2);
    $invoker->getConfig()->setTempDir(EASYSWOOLE_TEMP_DIR);
    $invoker->getConfig()->setOnWorkerStart(static function (Worker $worker): void {
        // 在同步进程启动后创建本进程独享的 SDK/数据库连接。
        // 进程因调用超时被强杀并重新拉起时，也会重新执行此回调。
    });

    $server = ServerManager::getInstance()->getSwooleServer();
    $invoker->attachServer($server);
}
```

`mainServerCreate()` 在服务启动前执行；这里首次调用 `getInstance()` 创建共享表，配置 Driver，然后只调用一次 `attachServer()`。之后 HTTP Worker 继承主进程中已初始化的实例。`Singleton` 是进程内单例，不表示多个 Worker 共享同一份普通 PHP 属性；跨进程协调依靠组件的共享表和同步进程。

`EASYSWOOLE_TEMP_DIR` 是框架初始化后的临时目录，不能写成 `EASYSWOOLE_TMP_DIR`。同步进程的 Unix Socket 会建在这个目录，部署时应保证目录可写，并避免多个服务实例使用相同的 Socket 文件名。`onWorkerStart` 是可选的；只有 SDK 需要进程独享的连接或其他资源时才配置它，不能在父进程先建立连接再依赖 fork 继承。修改同步进程数量、Driver 或这段启动代码后，应完整重启服务，不能只依赖 Worker reload。单例作用域可参考[单例模式](/Component/singleton.md)。

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
        // 2.0 表示本次调用的总时间预算，单位为秒；默认 15.0 秒。
        $result = InvokerHolder::getInstance()->invoke(2.0)->calculate(1, 2);
        if ($result === null) {
            $this->response()->withStatus(503);
            $this->response()->write('同步调用没有返回结果');
            return;
        }
        $this->response()->write((string) $result);
    }
}
```

启动 EasySwoole 服务后，按项目的控制器映射规则访问该控制器，预期正文为 `3`。`invoke()` 通过 Unix Socket 等待独立进程返回结果；同步 Worker 内部执行 `calculate()`，不会把阻塞代码放回 HTTP Worker。这里把 `null` 当作“没有结果”的失败信号，所以业务方法不要正常返回 `null`；更完整的错误处理见下一章。

下一章：[超时、并发与使用边界](/Library/SyncInvoker/practice.md)。

## 源码依据

- [组件 README（2.2.3）](https://github.com/easy-swoole/sync-invoker/blob/2.2.3/README.md)
- [SyncInvoker（2.2.3）](https://github.com/easy-swoole/sync-invoker/blob/2.2.3/src/SyncInvoker.php)
