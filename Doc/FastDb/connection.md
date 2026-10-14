# 连接与连接池

FastDb 使用 `FastDb` 单例管理具名数据库配置和连接池。应用启动时注册配置，业务请求在协程中按需获取连接；不要在每个控制器 Action 中重新创建连接池。

## 添加配置

在 `dev.php` 和 `produce.php` 中增加：

```php
'FAST_DB' => [
    'host' => '127.0.0.1',
    'port' => 3306,
    'user' => 'easyswoole',
    'password' => getenv('MYSQL_PASSWORD') ?: '',
    'database' => 'easyswoole_demo',
    'charset' => 'utf8mb4',
    'timeout' => 3.0,
    'maxConnectTime' => 5.0,
    'compress' => false,
    'minObjectNum' => 0,
    'maxObjectNum' => 16,
    'getObjectTimeout' => 3.0,
],
```

环境变量可通过 systemd 注入，参见[使用 systemd 管理服务](/QuickStart/systemd.md#配置环境变量)。

## 注册默认连接

编辑项目根目录的 `EasySwooleEvent.php`：

```php
<?php

namespace EasySwoole\EasySwoole;

use EasySwoole\EasySwoole\AbstractInterface\Event;
use EasySwoole\EasySwoole\Swoole\EventRegister;
use EasySwoole\FastDb\Config as FastDbConfig;
use EasySwoole\FastDb\FastDb;

class EasySwooleEvent implements Event
{
    public static function initialize()
    {
        $config = Config::getInstance()->getConf('FAST_DB');

        FastDb::getInstance()->addDb(
            new FastDbConfig($config),
            'default'
        );
    }

    public static function mainServerCreate(EventRegister $register)
    {
    }
}
```

`initialize()` 此时只完成连接配置注册。连接池在首次使用时创建，连接按业务协程取得和归还。

## 配置项说明

| 配置 | 默认值 | 作用 |
| --- | --- | --- |
| `host` | `127.0.0.1` | MySQL 地址 |
| `port` | `3306` | MySQL 端口 |
| `charset` | `utf8mb4` | 连接字符集 |
| `timeout` | `3.0` | 查询和事务操作默认超时，秒 |
| `maxConnectTime` | `5.0` | 完整建连超时，秒 |
| `compress` | `false` | 是否请求 MySQL 协议压缩 |
| `minObjectNum` | `8` | 单个连接池维持的最小连接数 |
| `maxObjectNum` | `16` | 单个连接池最大连接数 |
| `getObjectTimeout` | `3.0` | 等待池中连接的最长时间，秒 |
| `intervalCheckTime` | `5000` | 连接池定时检查间隔，毫秒 |

示例显式把 `minObjectNum` 设置为 `0`，避免开发环境一启动就为每个 Worker 预热多条连接。生产值应通过压测决定。

连接池按进程维护。例如 8 个 Worker、每池最多 16 条连接，理论上可能产生：

```text
8 × 16 = 128 条数据库连接
```

TaskWorker 或其他使用 FastDb 的进程还需额外计算。池大小必须与 MySQL `max_connections` 和业务并发共同设计。

## 测试连接

注册完成后可以调用：

```php
FastDb::getInstance()->testDb('default');
```

连接成功返回 `true`，失败抛异常。`testDb()` 在协程外调用时会自行创建协程调度器，因此适合部署健康检查或临时诊断；不要在每个 HTTP 请求中先测试再查询。

## 多数据库连接

```php
$db = FastDb::getInstance();

$db->addDb(new FastDbConfig($primaryConfig), 'primary');
$db->addDb(new FastDbConfig($reportConfig), 'reporting');
```

FastDb 的连接选择保存在当前协程上下文中。临时切换时应恢复原连接：

```php
$previous = FastDb::getInstance()->selectConnection();

FastDb::getInstance()->selectConnection('reporting');

try {
    $users = User::findAll(['status' => 1]);
} finally {
    FastDb::getInstance()->selectConnection($previous);
}
```

FastDb 实体本身不固定连接名，实体查询使用当前协程在 FastDb 单例中选择的连接。

## 连接生命周期

同一协程、同一连接名会复用当前连接。协程结束时连接自动归还池；归还前如果仍处于事务中，组件会尝试回滚。

```php
FastDb::getInstance()->currentConnection(); // 当前选中连接的 Connection|null
FastDb::getInstance()->recycleContext();    // 提前归还当前协程的连接并清理查询栈
FastDb::getInstance()->reset();             // 重置所有已创建连接池
```

`reset()` 用于测试、进程关闭或重新初始化，不要在每个 HTTP 请求结束时调用，否则会破坏常驻连接池的意义，并可能影响其他协程。

## 配置注意

- 完整建连超时使用 `maxConnectTime` 配置。
- 数据库访问使用基于 Swoole 协程 Socket 的 mysqli 5.x 客户端。
- `Config` 的 setter 返回 `void`，逐条调用时不要写成链式配置。
- `timeout` 不包含之前等待连接池和新建连接所花的全部时间。

## 源码依据

- [FastDb](https://github.com/easy-swoole/fast-db/blob/3.x/src/FastDb.php)
- [Config](https://github.com/easy-swoole/fast-db/blob/3.x/src/Config.php)
- [MySQL Pool](https://github.com/easy-swoole/fast-db/blob/3.x/src/Mysql/Pool.php)
