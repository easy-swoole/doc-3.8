# 新手路线与问题速查

## 从空目录跑通一个接口

1. [检查 PHP 和扩展](/QuickStart/environment.md)。如果 `php --ri swoole` 提示扩展未加载，先完成[安装 Swoole](/QuickStart/installSw.md)。
2. [安装框架并启动欢迎页](/QuickStart/install.md)。在项目根目录启动服务，用 `curl -i http://127.0.0.1:9501/` 验证 HTTP 200。
3. [写第一个 HTTP 接口](/QuickStart/helloworld.md)。新建 `App/HttpController/Hello.php`，访问 `/hello` 查看结果。
4. [修改端口和运行配置](/QuickStart/config.md)。本地改 `dev.php`，使用 `--mode=produce` 启动时改 `produce.php`。

## 已经遇到报错

| 看到的问题 | 去哪里检查 |
| --- | --- |
| `ext-swoole` 缺失、`Class "Swoole\..." not found` | [确认终端使用的 PHP 和扩展](/QuickStart/problem.md#swoole-扩展未加载) |
| 升级后 `php easyswoole.php` 报错 | [重新生成项目管理脚本](/QuickStart/install.md#升级后刷新项目管理脚本) |
| `Address already in use`、9501 被占用 | [查占用进程或换端口](/QuickStart/problem.md#端口已被占用) |
| `Connection refused`、浏览器连不上 | [检查启动状态和监听端口](/QuickStart/problem.md#服务启动后连不上) |
| HTTP 404、控制器没有进入 | [检查 URL、文件和路由](/QuickStart/problem.md#访问接口返回-404) |
| 改了 PHP 代码或端口，服务还是旧的 | [判断该 reload 还是完整重启](/QuickStart/problem.md#修改后没有生效) |
| 接口读不到 JSON 或注解参数 | [核对请求格式和参数来源](/QuickStart/problem.md#请求参数为空或未注入) |
| `Permission denied`、写不了日志或 PID | [检查运行用户和目录](/QuickStart/problem.md#无法写日志或-pid) |
| 经过 Nginx 后 IP 不对、上传太大失败 | [HTTP 代理与排错](/Http/problem.md) |

## 按任务找文档

| 我要做什么 | 从哪里开始 |
| --- | --- |
| 为接口加路由、参数校验或鉴权 | [路由基础](/Http/Routing/index.md)、[参数验证](/Http/AnnotationController/validation.md)、[鉴权与拦截](/Http/Middleware/global.md) |
| 读写 MySQL 或定位慢 SQL | [FastDb 安装](/FastDb/install.md)、[查询日志](/FastDb/query-log.md) |
| 加缓存、队列或后台任务 | [Fast-Cache](/Library/FastCache/index.md)、[可信队列](/Library/Queue/index.md)、[异步任务](/Advanced/task.md)、[Crontab](/Advanced/crontab.md) |
| 发布 RPC 服务或找不到节点 | [RPC 安装](/Microservice/Rpc/index.md)、[服务发现与部署](/Microservice/Rpc/discovery.md) |
| 接入 WebSocket、TCP 或 UDP | [Socket 组件与协议基础](/Socket/index.md) |
| 管理服务进程或部署上线 | [基础管理命令](/QuickStart/command.md)、[systemd 部署](/QuickStart/systemd.md)、[反向代理](/Http/Advanced/proxy.md) |
