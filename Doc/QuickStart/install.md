# 安装框架

本章从一个空目录开始，安装框架并启动安装器自带的欢迎页。请先完成[环境要求](/QuickStart/environment.md)和[安装 Swoole](/QuickStart/installSw.md)。以下命令在终端中执行，不要在本网站文档项目目录中执行。

## 创建项目

```bash
mkdir my-easyswoole-app
cd my-easyswoole-app
composer init --no-interaction --name=demo/my-easyswoole-app
composer require 'easyswoole/easyswoole:^3.8.2'
php vendor/bin/easyswoole.php install --with-examples
```

`composer init --no-interaction` 会创建 `composer.json`，这一步不需回答问题；项目名 `demo/my-easyswoole-app` 只是示例，可改为自己的 `vendor/project`。安装框架时 Composer 会创建 `vendor/` 和 `composer.lock`。若依赖安装失败，先运行 `php --ri swoole` 核对当前 CLI PHP 是否加载了扩展，再重试 Composer 命令。

## HTTP 示例文件

上面的 `--with-examples` 会生成缺失的 `App/HttpController/Index.php` 和 `App/HttpController/Router.php`，便于验证欢迎页。省略该选项时，交互终端会询问是否生成示例文件。

安装器会自动生成缺失的配置、引导和事件文件。已有文件出现替换提示时，选择保留即可继续使用项目原有配置。

本文档使用 EasySwoole `3.8.2` 起的 3.x 正式版；`^3.8.2` 允许安装兼容的后续 3.x 更新。团队部署时应提交 `composer.lock`，使各环境使用经过验证的同一组依赖。

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

安装完成后应看到 `install EasySwoole Success`。执行 `ls App/HttpController EasySwooleEvent.php easyswoole.php`，确认 `Index.php`、`Router.php` 和入口文件确实存在。缺少示例文件时，可以重新运行安装命令并加上 `--with-examples`。若服务器禁用了 `exec()`，安装器可能无法自动执行自动加载刷新，此时手动运行：

```bash
composer dump-autoload
```

## 升级后刷新项目管理脚本

升级至 EasySwoole 3.8.2 后，如果运行项目根目录的 `easyswoole.php` 报错，在项目根目录执行：

```bash
php vendor/bin/easyswoole.php install
```

安装器会用当前框架版本的模板覆盖根目录的 `easyswoole.php`。如果提示替换其他已有项目文件，选择保留即可。

## 启动并验证欢迎页

在第一个终端、项目根目录执行：

```bash
php easyswoole.php server start
```

保持这个终端运行，在第二个终端执行：

```bash
curl -i http://127.0.0.1:9501/
```

预期状态为 `HTTP/1.1 200 OK`，正文是安装器自带的欢迎页面。若提示连接失败，按[服务启动后连不上](/QuickStart/problem.md#服务启动后连不上)检查启动输出、运行模式和端口。测试结束后在第一个终端按 `Ctrl+C` 停止服务。

接下来按[第一个 HTTP 接口](/QuickStart/helloworld.md)创建自己的控制器，不必修改安装器提供的 `Index.php`。

确认前台运行正常后，才考虑后台启动：

```bash
php easyswoole.php server start -d
```

## 后续部署

```bash
composer install --no-dev --classmap-authoritative
php easyswoole.php server start -d --mode=produce
```

`--mode=produce` 会加载 `produce.php`。请确保 `Temp/`、`Log/` 或配置的自定义目录可写。生产部署建议先阅读[配置文件](/QuickStart/config.md)和[使用 systemd 管理服务](/QuickStart/systemd.md)，不要把本地调试用的前台命令直接当作发布流程。

## 源码依据

- [安装命令实现](https://github.com/easy-swoole/easyswoole/blob/3.8.2/src/Command/DefaultCommand/InstallAction.php)
- [框架 3.8.2](https://github.com/easy-swoole/easyswoole/tree/3.8.2)
