# 安装框架

## 创建项目

```bash
mkdir my-easyswoole-app
cd my-easyswoole-app
composer init
composer require easyswoole/easyswoole:3.x-dev
php vendor/bin/easyswoole.php install
```

如果项目固定在已发布版本，请把 `3.x-dev` 替换成团队验证过的明确版本约束，并提交生成的 `composer.lock`。

## 安装命令生成的文件

```text
App/HttpController/Index.php
App/HttpController/Router.php
EasySwooleEvent.php
bootstrap.php
dev.php
produce.php
easyswoole.php
```

同时会在 `composer.json` 中补充：

```json
{
  "autoload": {
    "psr-4": {
      "App\\": "App/"
    }
  }
}
```

如果服务器禁用了 `exec()`，安装器可能无法自动执行自动加载刷新，此时手动运行：

```bash
composer dump-autoload
```

## 启动服务

```bash
php easyswoole.php server start
```

默认访问地址：

```text
http://127.0.0.1:9501/
```

后台启动：

```bash
php easyswoole.php server start -d
```

## 生产环境

```bash
composer install --no-dev --classmap-authoritative
php easyswoole.php server start -d --mode=produce
```

请确保 `Temp/`、`Log/` 或配置的自定义目录可写。生产部署应配合进程守护工具，并将服务停止、重载和健康检查纳入发布流程。

## 源码依据

- [安装命令实现](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Command/DefaultCommand/Install.php)
- [框架 3.x](https://github.com/easy-swoole/easyswoole/tree/3.x)
