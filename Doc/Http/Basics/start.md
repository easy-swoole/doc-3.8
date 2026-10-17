# 启动 HTTP 服务

如果尚未创建项目，先完成[安装框架](/QuickStart/install.md)和[第一个 HTTP 接口](/QuickStart/helloworld.md)。本章只梳理“服务已经装好后，如何启动和验证 HTTP”的步骤。

在有 `easyswoole.php` 的项目根目录，用第一个终端启动开发服务：

```bash
php easyswoole.php server start
```

在第二个终端验证安装器首页和自己的接口：

```bash
curl -i http://127.0.0.1:9501/
curl -i http://127.0.0.1:9501/hello
```

两个请求都应返回 200；`/hello` 正文应为 `Hello EasySwoole`。如果连不上，先检查启动终端里的报错、`dev.php` 中的端口及端口占用。修改控制器文件后运行 `php easyswoole.php server reload`；修改监听端口、Worker 数量等启动期配置后要完整停止并重启。测试结束时，在第一个终端按 `Ctrl+C`。

HTTP 控制器放在 `App/HttpController`。不要用 PHP 内置 Web Server 代替 Swoole，它们的进程与生命周期不同。生产环境建议使用[systemd](/QuickStart/systemd.md)等进程管理器。
