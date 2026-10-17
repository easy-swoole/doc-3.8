# EasySwoole 3.x

EasySwoole 是运行在 Swoole 之上的常驻内存 PHP 框架，可以开发 HTTP API、WebSocket、TCP/UDP 服务和长期运行的任务。本教程先带你启动一个 HTTP 服务并写出第一个接口；其他组件可以等接口跑通后再学。

与传统 PHP-FPM 的“每次请求重新加载应用”不同，EasySwoole 会启动主进程、Manager 进程、Worker 进程和可选的 Task Worker。应用代码在 Worker 生命周期内持续驻留，因此能够减少重复加载开销，同时也要求开发者正确处理全局状态、连接资源和热重载。

## 第一次使用，按这个顺序读

1. [环境要求](/QuickStart/environment.md)：确认命令行 PHP 和 Swoole 可用。
2. [安装框架](/QuickStart/install.md)：创建项目，启动安装器自带的欢迎页。
3. [第一个 HTTP 接口](/QuickStart/helloworld.md)：创建 `Hello.php`，用 `curl` 验证文本和 JSON 响应。
4. [配置文件](/QuickStart/config.md)：知道端口在哪里改，为什么改完要重启。
5. [路由基础](/Http/Routing/index.md)：需要自定义 URL 时再学习显式路由。

准备发布到服务器时，再看[开发者必读](/QuickStart/notice.md)、[管理命令](/QuickStart/command.md)和[systemd 管理服务](/QuickStart/systemd.md)。[框架设计](/FrameworkDesign/index.md)解释内部启动流程，初学时可先跳过，不影响完成上面的练习。

本项目文档以 EasySwoole `3.x` 为主线，要求 PHP 8.1+、Swoole 5.1+。各组件章节会说明自己的安装与接口。生产环境应提交 `composer.lock`，并固定已验证的 PHP、Swoole 与组件组合。

## 核心能力

- 基于 Swoole 的常驻内存、多进程与协程运行模型。
- HTTP、WebSocket、TCP 和 UDP 服务。
- PSR-7 风格请求、响应、URI、Stream 与上传文件对象。
- FastRoute 路由和按控制器目录自动映射。
- PHP 8 原生 Attribute 参数解析、验证和接口文档生成。
- Task Worker、自定义进程、定时任务、日志和依赖注入。

## 三条命令看全局

```bash
composer require 'easyswoole/easyswoole:3.x-dev'
php vendor/bin/easyswoole.php install
php easyswoole.php server start
```

这三条命令要在**已创建 `composer.json` 的新项目根目录**执行；从零建项目、检查环境、验证 HTTP 输出的完整步骤在[安装框架](/QuickStart/install.md)。安装器会生成 `easyswoole.php`、`EasySwooleEvent.php`、`dev.php`、`produce.php`、`bootstrap.php`、示例控制器和路由文件，并为 `App\` 写入 PSR-4 自动加载配置。

## 源码参考

- [EasySwoole 框架](https://github.com/easy-swoole/easyswoole/tree/3.x)
- [EasySwoole HTTP](https://github.com/easy-swoole/http/tree/3.x)
- [HTTP Annotation](https://github.com/easy-swoole/http-annotation/tree/4.x)
- [Swoole](https://github.com/swoole/swoole-src)

> 本文档描述的是 EasySwoole 3.x 当前代码。复制旧版 3.5/3.6/3.7 文档示例前，请先确认类名、PHP 版本和组件版本是否仍然一致。
