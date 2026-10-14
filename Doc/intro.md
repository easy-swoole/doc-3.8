# EasySwoole 3.x

EasySwoole 是运行在 Swoole 之上的常驻内存 PHP 框架，面向 HTTP API、WebSocket、TCP/UDP 服务以及需要协程并发能力的长期运行程序。

与传统 PHP-FPM 的“每次请求重新加载应用”不同，EasySwoole 会启动主进程、Manager 进程、Worker 进程和可选的 Task Worker。应用代码在 Worker 生命周期内持续驻留，因此能够减少重复加载开销，同时也要求开发者正确处理全局状态、连接资源和热重载。

## 当前文档基线

本文档于 **2026-10-14** 根据以下 GitHub 最新分支核对：

| 组件 | 分支/版本 | 核对提交 |
| --- | --- | --- |
| `easy-swoole/easyswoole` | `3.x` | `db711009` |
| `easy-swoole/http` | `3.x` | `25570eb8` |
| `easy-swoole/http-annotation` | `4.x` | `6008e72a` |
| `swoole/swoole-src` | `master`（开发分支） | `f0796270` |

当前 EasySwoole 3.x 源码要求 PHP `^8.1`、Swoole `>=5.1` 和 JSON 扩展。生产环境应固定 Composer 锁文件和已验证的 Swoole 发布版本，不建议直接追踪 Swoole 的开发分支。

## 核心能力

- 基于 Swoole 的常驻内存、多进程与协程运行模型。
- HTTP、WebSocket、TCP 和 UDP 服务。
- PSR-7 风格请求、响应、URI、Stream 与上传文件对象。
- FastRoute 路由和按控制器目录自动映射。
- PHP 8 原生 Attribute 参数解析、验证和接口文档生成。
- Task Worker、自定义进程、定时任务、日志和依赖注入。

## 最小启动流程

```bash
composer require easyswoole/easyswoole:3.x-dev
php vendor/bin/easyswoole.php install
php easyswoole.php server start
```

安装命令会生成 `easyswoole.php`、`EasySwooleEvent.php`、`dev.php`、`produce.php`、`bootstrap.php`、示例控制器和路由文件，并为 `App\\` 写入 PSR-4 自动加载配置。

## 源码参考

- [EasySwoole 框架](https://github.com/easy-swoole/easyswoole/tree/3.x)
- [EasySwoole HTTP](https://github.com/easy-swoole/http/tree/3.x)
- [HTTP Annotation](https://github.com/easy-swoole/http-annotation/tree/4.x)
- [Swoole](https://github.com/swoole/swoole-src)

> 本文档描述的是 EasySwoole 3.x 当前代码。复制旧版 3.5/3.6/3.7 文档示例前，请先确认类名、PHP 版本和组件版本是否仍然一致。
