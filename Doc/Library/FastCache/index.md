# Fast-Cache：安装

`easyswoole/fast-cache` 在 Swoole Server 中启动独立的缓存进程。应用 Worker 通过 Unix Socket 读写该进程的内存，同一服务实例下的多个 Worker 可以共享普通值、哈希和 FIFO 队列。适合缓存可重新计算的结果，例如短期配置快照。缓存进程重启后会从空状态开始。

## 安装

本文以 FastCache `2.1.2` 为准，需要 PHP 8.1+、Swoole 5.0+、`easyswoole/component:^2.5.7` 和 `easyswoole/spl:^2.0`。

在应用项目根目录执行。

```bash
composer require 'easyswoole/fast-cache:^2.1.2'
composer show easyswoole/fast-cache
```

## 在 EasySwoole 中接入

新建 `App/Cache/MyCache.php`，继承 `FastCache` 并使用 EasySwoole 的 `Singleton` trait。

```php
<?php

namespace App\Cache;

use EasySwoole\Component\Singleton;
use EasySwoole\FastCache\FastCache;

final class MyCache extends FastCache
{
    use Singleton;
}
```

将以下代码合并到 `EasySwooleEvent.php`。在主进程的 `mainServerCreate()` 中创建并注册客户端，使用框架的 `EASYSWOOLE_TEMP_DIR` 存放 Unix Socket。此时 Swoole Server 尚未启动，缓存子进程只需挂载一次。应用 Worker 继承主进程注册的客户端，通过同一个 Socket 访问缓存。

```php
use App\Cache\MyCache;
use EasySwoole\EasySwoole\ServerManager;
use EasySwoole\EasySwoole\Swoole\EventRegister;
use EasySwoole\FastCache\Config as FastCacheConfig;

public static function mainServerCreate(EventRegister $register): void
{
    $cache = MyCache::getInstance(new FastCacheConfig([
        'serverName' => 'myapp',
        'tempDir' => EASYSWOOLE_TEMP_DIR,
    ]));
    $cache->attachToServer(ServerManager::getInstance()->getSwooleServer());
}
```

下一章：[基础使用](/Library/FastCache/usage.md)。
