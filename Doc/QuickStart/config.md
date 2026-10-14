# 配置文件

EasySwoole 默认通过运行模式选择根目录配置文件：

```text
dev.php
produce.php
```

配置文件必须返回数组。

## 默认配置结构

```php
<?php

return [
    'SERVER_NAME' => 'EasySwoole',
    'MAIN_SERVER' => [
        'LISTEN_ADDRESS' => '0.0.0.0',
        'PORT' => 9501,
        'SERVER_TYPE' => EASYSWOOLE_WEB_SERVER,
        'SOCK_TYPE' => SWOOLE_TCP,
        'RUN_MODEL' => SWOOLE_PROCESS,
        'SETTING' => [
            'worker_num' => 8,
            'reload_async' => true,
            'max_wait_time' => 3,
            'enable_deadlock_check' => false,
        ],
        'TASK' => [
            'workerNum' => 4,
            'maxRunningNum' => 128,
            'timeout' => 15,
        ],
    ],
    'LOG' => [
        'dir' => null,
        'handler' => null,
        'logLevels' => [],
        'displayConsole' => true,
        'ignoreCategory' => [],
    ],
    'TEMP_DIR' => null,
];
```

`MAIN_SERVER.SETTING` 会传给 Swoole Server。配置项是否可用取决于当前 Swoole 版本。

## 读取和修改

```php
use EasySwoole\EasySwoole\Config;

$port = Config::getInstance()->getConf('MAIN_SERVER.PORT');
$all = Config::getInstance()->getConf();

Config::getInstance()->setConf('APP.name', 'demo');
```

点语法由配置存储实现支持。运行时修改只影响当前进程内的配置对象，不会自动写回 PHP 配置文件，也不会自动同步到其他 Worker。

## 合并额外配置

```php
Config::getInstance()->loadFile(EASYSWOOLE_ROOT . '/Config/database.php');
Config::getInstance()->loadDir(EASYSWOOLE_ROOT . '/Config');
Config::getInstance()->loadEnv(EASYSWOOLE_ROOT . '/.env');
```

`loadFile()`、`loadDir()` 和 `loadEnv()` 默认递归合并；也可以传入 `false` 覆盖整个配置存储。

建议在 `EasySwooleEvent::initialize()` 中加载扩展配置，使每个进程在启动阶段得到明确配置。敏感信息不要提交到 Git。

## 源码依据

- [默认配置模板](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Resource/Config._php)
- [Config 实现](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Config.php)
