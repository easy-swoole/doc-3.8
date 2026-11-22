# 令牌桶限流器

`easyswoole/atomic-limit` 使用 Swoole 共享内存保存令牌桶，同一服务的多个 Worker 共享限流状态。每个业务 key 对应一个桶，放行一次消耗一个令牌，令牌按速率补充，余额最多达到桶容量。新桶从满桶开始。

例如每秒补充 5 个令牌、容量 10，空闲后最多可以连续放行 10 次，持续请求则受补充速率限制。

## 安装与定义入口

本章使用 **AtomicLimit 3.0.2**，运行环境为 64 位 PHP 和 Swoole 6.2.x。在应用项目根目录执行：

```bash
composer require 'easyswoole/atomic-limit:^3.0.2'
composer show easyswoole/atomic-limit
php --ri swoole
```

新建 `App/Limiter/MyLimiter.php`：

```php
<?php

namespace App\Limiter;

use EasySwoole\AtomicLimit\AtomicLimit;
use EasySwoole\Component\Singleton;

final class MyLimiter extends AtomicLimit
{
    use Singleton;
}
```

## 在主进程注册

将以下导入和方法体合并到项目根目录的 `EasySwooleEvent.php`。在 `mainServerCreate()` 中首次创建实例，Swoole 启动 Worker 后会继承这个实例及其共享内存。

```php
use App\Limiter\MyLimiter;
use EasySwoole\EasySwoole\Swoole\EventRegister;

public static function mainServerCreate(EventRegister $register): void
{
    MyLimiter::getInstance(4096);
    MyLimiter::getInstance()->setLimitQps(5);
}
```

`4096` 是活动桶及专属规则各自的总配额，按业务 key 的数量估算。`setLimitQps(5)` 把默认补充速率设为每秒 5 个，默认容量也设为 5。限流器在构造时创建共享内存，因此首次 `getInstance()` 应发生在主进程的启动阶段。

## 在控制器中限流

新建 `App/HttpController/Limited.php`：

```php
<?php

namespace App\HttpController;

use App\Limiter\MyLimiter;
use EasySwoole\Http\AbstractInterface\Controller;

final class Limited extends Controller
{
    protected function onRequest(?string $action): ?bool
    {
        $ip = (string) ($this->request()->getServerParams()['remote_addr'] ?? 'unknown');
        $key = $ip . ':/limited/' . ($action ?? 'index');

        if (!MyLimiter::getInstance()->access($key)) {
            $this->writeJson(429, null, '请求过于频繁，请稍后重试');
            return false;
        }

        return true;
    }

    public function index(): void
    {
        $this->writeJson(200, ['message' => '请求已放行']);
    }
}
```

完整重启服务以执行主进程初始化，再连续请求：

```bash
for i in 1 2 3 4 5 6 7 8 9 10; do
  curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:9501/limited
done
```

相同 IP 和 Action 共用一个桶，短时间耗尽令牌后返回 HTTP 429；等待令牌补充后可再次访问。如果通过反向代理部署，应按[URI 与客户端信息](/Http/Request/uri-client.md)获取可信的客户端 IP。也可在完成身份认证后，以用户 ID 或租户 ID 作为 key。

## 为某个 key 设置速率和突发容量

在主进程初始化时添加固定规则，也可在运行过程中设置：

```php
use App\Limiter\MyLimiter;

// 与上面控制器生成的 key 保持一致。
if (!MyLimiter::getInstance()->setRule('127.0.0.1:/limited/index', 5, 10)) {
    throw new RuntimeException('无法设置限流规则');
}
```

`setRule($key, $rate, $capacity)` 支持正小数速率，例如 `0.5` 表示平均每两秒补一个令牌；容量必须是大于等于 1 的整数。设置成功返回 `true`。修改已有桶时，先按旧规则结算，再按新容量截断余额。删除专属规则用 `removeRule($key)`，该桶随后使用默认配置。

## 手动回收桶

需要主动释放已补满桶的空间时，可以在协程中调用：

```php
use App\Limiter\MyLimiter;

$removed = MyLimiter::getInstance()->gc(); // 扫描所有分片，返回实际回收的桶数。
$removedForKey = MyLimiter::getInstance()->gc('127.0.0.1:/limited/index');
```

3.0.2 的无参数 `gc()` 会从头扫描所有分片的桶表，先在租约外筛选候选桶，再分批获取租约。每次删除前重新读取桶和规则，确认桶已补满。某个分片获取租约超时，本轮跳过该分片剩余工作，继续处理其他分片。传入 key 时只检查该桶。

若要由自定义进程统一回收，可在主进程初始化时调用 `MyLimiter::getInstance()->setAutoGc(false)`，再在继承同一实例的自定义进程中定时调用 `gc()`。关闭自动回收后，请求会跳过定期回收和插入失败时的回收重试，分片空间不足的新 key 会被拒绝，直到手动回收释放空间。需要恢复请求内回收时调用 `setAutoGc(true)`。

## 统计与使用边界

- `MyLimiter::getInstance()->qps($key)` 返回最近三个一秒时间片中，有请求时间片的平均尝试次数，包含桶内记录的拒绝请求。
- 默认启用请求内自动回收，分批回收已补满的桶以释放桶位。专属规则需要通过 `removeRule()` 删除。
- `access()` 返回 `false` 也可能是租约等待超时或桶分片容量不足。应结合 key 数量和负载检查容量配置。
- 共享范围是同一 Swoole Server 派生出的进程。独立部署的多实例各自计数，需要跨机器总额度时应使用共享后端的限流方案。
- 完整停止并重新启动服务后，内存中的桶状态、统计和动态规则会丢失。固定规则应在主进程初始化时重新设置。

## 版本与 GitHub

- [AtomicLimit 3.0.2 源码](https://github.com/easy-swoole/atomic-limit/tree/3.0.2)
- [AtomicLimit 3.0.2 使用说明](https://github.com/easy-swoole/atomic-limit/blob/3.0.2/README.md)
- [令牌桶及分片实现（3.0.2）](https://github.com/easy-swoole/atomic-limit/blob/3.0.2/src/AtomicLimitShard.php)
