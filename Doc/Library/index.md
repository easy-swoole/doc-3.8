# 组件选型与阅读路线

组件库提供可按需安装的能力，不必为了学习框架而一次装齐。先完成[安装框架](/QuickStart/install.md)与[第一个 HTTP 接口](/QuickStart/helloworld.md)；下面的 `composer require` 命令都应在**应用项目根目录**执行，而不是在本文档仓库执行。每个组件的具体版本、环境要求和安装命令以对应章节为准。

## 先选要解决的问题

| 想实现什么 | 从哪里开始 | 是否需要外部服务 |
| --- | --- | --- |
| 复用数据库、Redis 等连接 | [连接池](/Library/Pool/index.md) | 演示对象不需要；真实连接需要对应服务 |
| 异步投递并可靠消费任务 | [可信队列](/Library/Queue/index.md) | 需要 Redis 或 RabbitMQ |
| 在协程服务中调用阻塞 SDK | [同步调用](/Library/SyncInvoker/index.md) | 不需要；会启动独立同步进程 |
| 记录一次请求的调用链和耗时 | [链路追踪](/Library/Trace/index.md) | 单脚本示例不需要；持久化按需选择 |
| 按 IP 或端口限制访问 | [IpAccess](/Library/IpAccess/index.md) | 不需要 |
| 按资源路径判断权限 | [AccessPolicy](/Library/AccessPolicy/index.md) | 不需要；用户和角色数据由应用提供 |

IP 来源限制与业务权限不是一回事。IpAccess 判断“请求来自哪里”，AccessPolicy 判断“这个身份能访问什么”。连接池管理可复用对象的数量和生命周期；可信队列管理待执行任务；同步调用则把阻塞代码交给独立进程运行。

## 推荐的阅读顺序

新手可以先从不依赖外部服务的组件入手：

1. 按[IpAccess](/Library/IpAccess/index.md)或[AccessPolicy](/Library/AccessPolicy/index.md)运行独立脚本，理解“安装组件 → 加载 Composer 自动加载 → 调用 API → 查看结果”。
2. 按[连接池](/Library/Pool/index.md)使用演示对象，依次阅读对象、配置、框架注册、获取与归还；需要真实 Redis 或数据库连接时再替换演示对象。
3. 要接入 Redis/RabbitMQ 时，先确认服务已启动和扩展已安装，再阅读[可信队列](/Library/Queue/index.md)。
4. 需要处理阻塞 SDK 时阅读[同步调用](/Library/SyncInvoker/index.md)；需要排查跨层调用耗时时阅读[链路追踪](/Library/Trace/index.md)。

不必按菜单从上到下安装所有组件。每个组件都先运行自己的“安装/快速开始”示例，确认输出符合文档，再复制框架接入代码。独立脚本中的 `require __DIR__ . '/vendor/autoload.php';` 只适用于保存在**项目根目录**的脚本；放到其他目录时要相应调整路径。

## 复制示例时先检查三件事

1. 代码块是完整文件、类方法，还是要加入已有文件中的片段；不要把片段直接保存成独立 PHP 文件。
2. `App/...` 命名空间的文件需要放到对应目录；新增类后若自动加载未更新，可在项目根目录运行 `composer dump-autoload`。
3. 框架示例涉及 `EasySwooleEvent.php` 时，应把代码合并进已有事件方法，而不是用示例覆盖整个文件；改动后按相关章节的说明重启或重载服务。

开始阅读：[连接池](/Library/Pool/index.md)。
