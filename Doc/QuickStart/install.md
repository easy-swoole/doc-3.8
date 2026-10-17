# 安装框架

本章从一个空目录开始，安装框架并启动安装器自带的欢迎页。请先完成[环境要求](/QuickStart/environment.md)和[安装 Swoole](/QuickStart/installSw.md)。以下命令在终端中执行，不要在本网站文档项目目录中执行。

## 创建项目

```bash
mkdir my-easyswoole-app
cd my-easyswoole-app
composer init --no-interaction --name=demo/my-easyswoole-app
composer require 'easyswoole/easyswoole:3.x-dev'
php vendor/bin/easyswoole.php install
```

`composer init --no-interaction` 会创建 `composer.json`，这一步不需回答问题；项目名 `demo/my-easyswoole-app` 只是示例，可改为自己的 `vendor/project`。安装框架时 Composer 会创建 `vendor/` 和 `composer.lock`。若依赖安装失败，先运行 `php --ri swoole` 核对当前 CLI PHP 是否加载了扩展，再重试 Composer 命令。

## 回答安装器的文件释放提示

最后一条 `php vendor/bin/easyswoole.php install` 是交互命令。它会依次询问是否释放 `Index.php` 和 `Router.php`，例如：

```text
do you want to release Index.php? [ Y / N (default) ] :
do you want to release Router.php? [ Y / N (default) ] :
```

在新项目中，两次都输入 `y` 并按回车。这样安装器才会从框架自带模板生成 `App/HttpController/Index.php`（欢迎页控制器）和 `App/HttpController/Router.php`（路由定义文件）。直接按回车相当于选择默认的 `N`，对应文件不会生成；即使最后出现 `install EasySwoole Success`，也不能据此判断这两个文件已释放。`dev.php`、`produce.php`、`bootstrap.php` 和 `EasySwooleEvent.php` 则由安装器自动释放。

如果目标文件已经存在，安装器还会先询问是否替换。已有项目不要直接输入 `y` 覆盖自己修改过的文件；先检查内容并做好备份。新建空项目一般不会遇到替换提示。

本文档针对框架 `3.x` 分支；团队部署时应提交 `composer.lock`，使各环境使用经过验证的同一组依赖。

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

安装完成后应看到 `install EasySwoole Success`。执行 `ls App/HttpController EasySwooleEvent.php easyswoole.php`，确认 `Index.php`、`Router.php` 和入口文件确实存在。如果误选了 `N`，可以重新运行安装命令，对缺失文件选择 `y`；对已经存在的文件选择默认 `N`，避免覆盖。若服务器禁用了 `exec()`，安装器可能无法自动执行自动加载刷新，此时手动运行：

```bash
composer dump-autoload
```

## 启动并验证欢迎页

在第一个终端、项目根目录执行：

```bash
php easyswoole.php server start
```

保持这个终端运行，在第二个终端执行：

```bash
curl -i http://127.0.0.1:9501/
```

预期状态为 `HTTP/1.1 200 OK`，正文是安装器自带的欢迎页面。若提示连接失败，先看第一个终端是否报错，再确认 9501 端口未被占用。测试结束后在第一个终端按 `Ctrl+C` 停止服务。

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

- [安装命令实现](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Command/DefaultCommand/Install.php)
- [框架 3.x](https://github.com/easy-swoole/easyswoole/tree/3.x)
