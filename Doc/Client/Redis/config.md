# Redis Pool 配置与注册

## 单机配置

```php
use EasySwoole\RedisPool\Config;

$config = new Config([
    'host' => '127.0.0.1',
    'port' => 6379,
    'username' => null,
    'password' => null,
    'database' => 0,
    'connectTimeout' => 1.5,
    'readTimeout' => 2.0,
    'retryInterval' => 100,
    'persistent' => false,
    'minObjectNum' => 2,
    'maxObjectNum' => 20,
    'getObjectTimeout' => 1.0,
]);
```

Redis ACL 可以同时设置 `username` 和 `password`。密码不要提交到代码仓库。

## Cluster 配置

```php
$config = new Config([
    'mode' => Config::MODE_CLUSTER,
    'seeds' => [
        '10.0.0.11:7001',
        '10.0.0.12:7002',
        '10.0.0.13:7003',
    ],
    'username' => 'app-user',
    'password' => 'app-password',
    'connectTimeout' => 1.5,
    'readTimeout' => 2.0,
    'minObjectNum' => 2,
    'maxObjectNum' => 20,
]);
```

Cluster 必须配置种子节点，而且只支持数据库 0。

## 配置项

| 配置项 | 默认值 | 说明 |
| --- | --- | --- |
| `mode` | `standalone` | 单机或 `cluster` |
| `host` / `port` | `127.0.0.1:6379` | 单机地址 |
| `seeds` | `[]` | Cluster 种子节点 |
| `username` / `password` | `null` | ACL 认证 |
| `database` | `0` | 单机数据库编号 |
| `connectTimeout` | `3.0` | 连接超时，秒 |
| `readTimeout` | `3.0` | 读取超时，秒 |
| `retryInterval` | `0` | 单机重试间隔，毫秒 |
| `persistent` | `false` | 是否使用持久连接 |
| `minObjectNum` | `8` | 最小对象数 |
| `maxObjectNum` | `20` | 最大对象数 |

## EasySwoole 配置文件

```php
'REDIS' => [
    'host' => '127.0.0.1',
    'port' => 6379,
    'password' => null,
    'database' => 0,
    'minObjectNum' => 2,
    'maxObjectNum' => 20,
    'getObjectTimeout' => 1.0,
],
```

## 在全局初始化事件中注册

编辑项目根目录的 `EasySwooleEvent.php`：

```php
use EasySwoole\EasySwoole\Config as EasySwooleConfig;
use EasySwoole\RedisPool\Config;
use EasySwoole\RedisPool\RedisPool;

public static function initialize(): void
{
    $data = EasySwooleConfig::getInstance()->getConf('REDIS');

    RedisPool::getInstance()->register(
        new Config($data),
        'default'
    );
}
```

`register()` 只创建 Pool 和配置对象，不会在 `initialize()` 中立即连接 Redis。Worker 创建后会各自继承注册信息，第一次调用 `invoke()`、`defer()` 或 `keepMin()` 时，才在当前进程中建立 Redis 连接。

不要在 `initialize()` 中调用 `keepMin()`，否则会在 Worker 创建前建立实际网络连接。

## 可选的 Worker 预热

`keepMin()` **不是 Redis Pool 的必选步骤**。如果省略整个 `onWorkerStart` 监听，第一次 `invoke()` 或 `defer()` 会在当前 Worker 中按需建立连接，连接池仍能正常工作。

只有希望减少服务启动后第一批请求的建连延迟时，才在 `mainServerCreate()` 中增加 `onWorkerStart` 监听并预热：

```php
use EasySwoole\EasySwoole\Swoole\EventRegister;
use EasySwoole\RedisPool\RedisPool;

public static function mainServerCreate(EventRegister $register): void
{
    $register->add(
        EventRegister::onWorkerStart,
        function (\Swoole\Server $server, int $workerId): void {
            if ($server->taskworker) {
                return;
            }

            $pool = RedisPool::getInstance()->getPool('default');
            if ($pool !== null) {
                go(static function () use ($pool): void {
                    $pool->keepMin();
                });
            }
        }
    );
}
```

注册属于全局初始化，是使用命名池的必要步骤；预热属于进程启动后的可选优化，两者不要混在一起。每个 Worker 最终拥有独立连接；8 个 Worker、每池上限 20，最多可能建立 160 个连接。

## 多个连接池

```php
RedisPool::getInstance()->register($cacheConfig, 'cache');
RedisPool::getInstance()->register($sessionConfig, 'session');
```

同名池不能重复注册。下一章：[获取与归还](/Client/Redis/connection.md)。
