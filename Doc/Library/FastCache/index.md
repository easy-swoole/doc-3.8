# 轻量缓存

`easyswoole/fast-cache` 在 Swoole Server 中启动独立的缓存进程。应用 Worker 通过 Unix Socket 读写该进程的内存，同一服务实例下的多个 Worker 可以共享普通值、哈希和 FIFO 队列。适合缓存可重新计算的结果，例如短期配置快照。缓存进程重启后会从空状态开始。

## 安装

本文基于 `2.x` 分支的 `ec48da8`，需要 PHP 8.1+、Swoole 5.0+、`easyswoole/component:^2.5.7` 和 `easyswoole/spl:^2.0`。截至本章编写时，查到的 Packagist 正式版为 `2.0.1`，使用旧入口 `Cache::getInstance()`。下面的示例使用分支中的 `FastCache` 类和 TTL 接口。 [分支依赖](https://github.com/easy-swoole/fast-cache/blob/ec48da8a0b4386a2b9c843c0c1a802cf897ece5e/composer.json) · [Packagist 正式版](https://root.packagist.org/packages/easyswoole/fast-cache)

在应用项目根目录安装开发分支，并保留 `composer.lock` 以复现已安装的提交。

```bash
composer require 'easyswoole/fast-cache:2.x-dev'
composer show easyswoole/fast-cache
```

## 在 EasySwoole 中接入

当前示例所用的 `FastCache` 声明为 `final`，直接写 `class MyCache extends FastCache` 会在 PHP 加载类时出错。新建 `App/Cache/MyCache.php`，用 `MyCache::getInstance()` 提供单例式入口。

```php
<?php

namespace App\Cache;

use EasySwoole\FastCache\FastCache;

final class MyCache
{
    private static FastCache $cache;

    public static function register(FastCache $cache): void
    {
        self::$cache = $cache;
    }

    public static function getInstance(): FastCache
    {
        return self::$cache;
    }
}
```

将以下代码合并到 `EasySwooleEvent.php`。在主进程的 `mainServerCreate()` 中创建并注册客户端，使用框架的 `EASYSWOOLE_TEMP_DIR` 存放 Unix Socket。此时 Swoole Server 尚未启动，缓存子进程只需挂载一次。应用 Worker 继承主进程注册的客户端，通过同一个 Socket 访问缓存。

```php
use App\Cache\MyCache;
use EasySwoole\EasySwoole\ServerManager;
use EasySwoole\EasySwoole\Swoole\EventRegister;
use EasySwoole\FastCache\Config as FastCacheConfig;
use EasySwoole\FastCache\FastCache;

public static function mainServerCreate(EventRegister $register): void
{
    $cache = new FastCache(new FastCacheConfig([
        'serverName' => 'myapp',
        'tempDir' => EASYSWOOLE_TEMP_DIR,
    ]));
    $cache->attachToServer(ServerManager::getInstance()->getSwooleServer());
    MyCache::register($cache);
}
```

服务启动且 Socket 就绪后，在控制器或 Service 的 Swoole 协程中调用。

```php
use App\Cache\MyCache;

$cache = MyCache::getInstance();
$cache->set('home:title', '首页', ttl: 60);
$title = $cache->get('home:title'); // '首页'
$cache->del('home:title');
```

TTL 从写入时起按秒计算，必须是正整数。值过期或不存在时，`get()` 返回 `null`。覆盖写入时省略 `ttl` 或传 `null`，会清除原有过期时间。业务通过 `=== null` 判断缓存缺失时，应避免把 `null` 存作有效缓存值。

## 哈希

用 `hset($key, $field, $value)` 写入字段，`hget()` 读取字段，`hdel()` 删除字段。需要遍历时，按插入顺序分页，使用上次返回的游标继续。

```php
$cache->hset('app:labels', 'home', '首页');
$cache->hset('app:labels', 'help', '帮助');

$cursor = null;
do {
    $page = $cache->hscan('app:labels', $cursor, count: 100);
    foreach ($page['items'] as $item) {
        // $item 包含 field 和 value。
    }
    $cursor = $page['cursor'];
} while ($cursor !== null);
```

扫描过程中删除任一字段会使已有游标失效。普通值、哈希和队列各自存储，同名键可以共存。TTL 适用于普通值。

## 内存队列

先用 `initQueue()` 设置容量，再用 `push()` 入队和 `pop()` 出队。初始化同名队列会清空原有消息，因此应由应用在缓存进程就绪后统一初始化。未初始化时，首次入队或出队会创建容量为 `PHP_INT_MAX` 的队列。

```php
$cache->initQueue('preview-jobs', 128); // 统一初始化时调用。
$sent = $cache->push('preview-jobs', ['id' => 42], timeout: 0.5);
$job = $cache->pop('preview-jobs', timeout: 0.5);
```

队列满时入队等待空位，超时或队列关闭时返回 `false`。队列空时出队等待消息，超时或队列关闭时返回 `null`。消息在回包前就已出队，连接中断时可能丢失。需可靠消费的业务可使用[可信队列](/Library/Queue/index.md)。

## 配置与部署

| 配置项 | 默认值 | 用途 |
| --- | --- | --- |
| `serverName` | `EasySwoole` | 进程和 Socket 文件名的标识 |
| `tempDir` | `sys_get_temp_dir()` | 已存在且应用可写的绝对路径 |
| `timeout` | `1.0` | 单次操作共用的连接和读写预算，单位为秒 |
| `maxMemLimit` | `512M` | 缓存进程的 PHP 内存上限，普通值、哈希和队列共用 |

Socket 文件名为 `{serverName}.fastCache.sock`。同一主机上的服务实例应使用独立路径，目录权限应限制为可信应用进程。通信失败会抛出 `RuntimeException`，缓存调用方可按业务需要回源或向上层传播错误。

## 源码依据

- [FastCache 2.x README](https://github.com/easy-swoole/fast-cache/blob/ec48da8a0b4386a2b9c843c0c1a802cf897ece5e/README.md)
- [FastCache 客户端实现](https://github.com/easy-swoole/fast-cache/blob/ec48da8a0b4386a2b9c843c0c1a802cf897ece5e/src/FastCache.php)
