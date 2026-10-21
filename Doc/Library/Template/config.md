# 模板引擎：配置、超时与排查

本章接着[在框架中渲染页面](/Library/Template/integration.md)的例子，解释 `Render` 2.x 的配置边界和常见故障。配置在 `mainServerCreate()` 中、`attachServer()` **之前**完成；修改启动期配置后要完整重启服务。

## 目前支持的配置

| 方法 | 默认值 | 作用 |
| --- | --- | --- |
| `setRender(RenderInterface $render)` | 未配置 | 指定实际模板渲染器，挂载服务前必填 |
| `setServerName(string $name)` | `EasySwoole` | 渲染进程名与 Unix Socket 文件名前缀；同机多个实例应使用不同名称 |
| `setTempDir(string $dir)` | `sys_get_temp_dir()` | Unix Socket 文件目录；应用示例使用 `EASYSWOOLE_TEMP_DIR` |
| `setWorkerNum(int $number)` | `3` | 渲染进程数量，必须大于 0 |
| `setTimeout(int $seconds)` | `3` | 单次 `render()` 客户端连接、发送、接收共用的时间预算；必须大于 0 |
| `setOnException(?callable $callback)` | `null` | 处理渲染进程自身的运行时异常 |

例如在 `mainServerCreate()` 中取得同一个应用单例后调整：

```php
$render = TemplateRender::getInstance();
$config = $render->getConfig();
$config->setWorkerNum(4);
$config->setTimeout(5);
$config->setServerName('MyAppTemplate');
$config->setTempDir(EASYSWOOLE_TEMP_DIR);
$render->attachServer(ServerManager::getInstance()->getSwooleServer());
```

这只是配置片段，仍需先按上一章调用 `setRender(new PlatesRenderer())` 并导入相关类。进程数不是“每个 HTTP Worker 四个”，而是整个 Swoole Server 注册的渲染进程数量。组件随机选一个渲染进程，单个进程按顺序处理请求；因此复杂页面并发较高时，可能需要增加进程数，但随机选择不保证绝对均衡。

## 客户端超时与渲染异常

2.x 的 `setTimeout()` 是**整数秒**，每次 `render()` 创建一个 deadline；连接、发送和接收共用剩余时间，不是三个阶段各 5 秒。超时抛 `ClientTimeoutException`，可用 `getOperation()` 看发生在 `connect`、`send` 还是 `receive`，并用 `getSocketFile()`、`getTimeout()` 记录上下文。非超时的 Socket 失败抛 `ClientException`，还可读取 `getErrorCode()`、`getErrorMessage()`。

```php
try {
    $html = TemplateRender::getInstance()->render('hello', ['name' => 'EasySwoole']);
} catch (ClientTimeoutException $error) {
    error_log(sprintf('template timeout: %s (%ds)', $error->getOperation(), $error->getTimeout()));
    // 在控制器中向客户端返回 503，避免泄露本机 Socket 路径。
} catch (ClientException $error) {
    error_log(sprintf('template socket error: %s [%d]', $error->getOperation(), $error->getErrorCode()));
    // 在控制器中向客户端返回 503。
}
```

这段是放在控制器中的处理片段；需要在文件顶部导入 `App\Template\TemplateRender` 和两个异常类。**客户端超时不等于 worker 的 PHP 渲染代码被强制终止**：它可能继续占用渲染进程，后续请求仍可能排队。避免在模板中执行长时间数据库查询、外部 HTTP 调用或循环；应在控制器/服务层准备好数据，再把简单、可序列化的数据传入 `render()`。

渲染器内部抛异常时，组件会调用 `RenderInterface::onException()` 并关闭当前连接，不会把异常 HTML 返回给 HTTP 控制器；客户端可能得到 `null`，也可能收到 `ClientException`。所以完整控制器既要捕获异常，也要处理 `null`。`setOnException()` 则负责渲染**进程自身**的异常，和单次模板渲染回调不是一回事：

```php
$config->setOnException(static function (\Throwable $error, ...$context): void {
    error_log('Template process error: ' . $error->getMessage());
});
```

## Socket、数据大小与进程状态

Socket 文件名格式为 `{serverName}.Render.Worker.{编号}.sock`，放在 `tempDir` 下。目录要存在、可写，且所有业务 Worker 和渲染进程都能访问。多套应用共用同一个临时目录时，必须设置不同 `serverName`，否则 Socket 路径会冲突。

组件使用序列化协议传递模板名、`$data` 和 `$options`，底层包长度上限为 **1 MiB**。不要把整个请求/响应对象、闭包、文件句柄、大型 ORM 实体或大量二进制内容放进模板数据；传普通标量和数组，并在业务层先完成查询与整理。`render()` 返回的是 HTML 字符串或 `null`，HTTP 状态和 Header 仍由控制器设置。

要查看当前登记的渲染进程 PID，可在管理代码中读取应用单例的共享表：

```php
foreach (TemplateRender::getInstance()->getProcessTable() as $pid => $row) {
    echo $row['pid'], PHP_EOL;
}
```

表在主进程创建，worker 启动时写入、退出时删除。它用于观察，不是进程管理命令；组件本身不提供自动重启指令。增加进程、变更 `serverName` 或 `tempDir` 后，应完整重启服务以重新注册进程和 Socket。

## 常见问题

- `RenderInterface must be configured`：`attachServer()` 之前忘记 `setRender()`。
- `Render has already been attached`：同一实例重复调用 `attachServer()`；检查 `mainServerCreate()` 是否注册两次。
- `connect` 失败或超时：确认服务已完整重启、渲染进程启动、Socket 目录存在且可写，`serverName` 和 `tempDir` 在调用侧一致。
- 请求能进入控制器但返回 503：看 `PlatesRenderer::onException()` 的日志；模板文件路径或变量有误时，渲染进程不会把异常直接显示到浏览器。
- 压力下偶发 `receive` 超时：可能是选中的渲染进程仍在处理上一个慢模板。先移走模板内的阻塞业务，再评估 `workerNum` 与超时。

## 源码依据

- [template 2.x README](https://github.com/easy-swoole/template/blob/2.x/README.md)
- [Config.php](https://github.com/easy-swoole/template/blob/2.x/src/Config.php)
- [ClientDeadline.php](https://github.com/easy-swoole/template/blob/2.x/src/ClientDeadline.php)
- [UnixClient.php](https://github.com/easy-swoole/template/blob/2.x/src/UnixClient.php)
- [RenderWorker.php](https://github.com/easy-swoole/template/blob/2.x/src/RenderWorker.php)
