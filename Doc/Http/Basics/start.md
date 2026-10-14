# 启动 HTTP 服务

项目安装完成后，在项目根目录启动开发服务：

```bash
php easyswoole server start
```

默认入口由框架创建，控制器放在 `App/HttpController`。修改 PHP 文件后执行 `php easyswoole server reload`，生产环境可用 `start -d` 守护运行，并由进程管理器负责拉起。

先用 `curl http://127.0.0.1:9501/` 验证服务，再编写路由和控制器。不要用 PHP 内置 Web Server 代替 Swoole，它们的生命周期不同。
