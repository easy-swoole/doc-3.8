# 配置文件

EasySwoole 默认通过运行模式选择根目录配置文件：

```text
dev.php
produce.php
```

配置文件必须返回数组。

刚安装完先只改 `dev.php`，因为 `php easyswoole.php server start` 默认以开发模式启动。`produce.php` 用于 `--mode=produce`，不要为了调试把两份配置同时改乱。

## 第一次改配置：换一个端口

打开项目根目录的 `dev.php`，找到 `MAIN_SERVER` 下的 `PORT`，把 `9501` 改为 `9502`。仅改这一处即可。保存后在项目根目录完整停止并重新启动服务：

```bash
php easyswoole.php server stop
php easyswoole.php server start
```

在另一个终端验证：

```bash
curl -i http://127.0.0.1:9502/hello
```

预期仍能看到 `Hello EasySwoole`。修改监听端口属于启动期变更，`server reload` 不会重新创建主 Server，因此这里必须完整重启。完成实验后可把端口改回 9501，同样需要重启。

## 默认配置结构

安装器生成的配置大致如下。下面是**对照说明**，不要将整段代码直接粘贴到已有 `dev.php` 后面；修改时只编辑现有数组中需要变化的键。

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
            'pushTimeOut' => 15,
            'maxPackageSize' => 2 * 1024 * 1024,
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

`MAIN_SERVER.PORT` 是 HTTP 监听端口；`MAIN_SERVER.SETTING.worker_num` 是 HTTP Worker 数量；`MAIN_SERVER.TASK` 配置框架 Task 组件。对于首次运行，先保留安装器默认值，确认服务可访问后再逐项调整。

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
