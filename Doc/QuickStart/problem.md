# 安装、启动与访问排错

按终端或浏览器里的症状查找。下列框架管理命令在应用项目根目录执行。

## Swoole 扩展未加载

适用于 Composer 提示缺少 `ext-swoole`，或 PHP 提示找不到 `Swoole\Server` 等类。

```bash
command -v php
php --ini
php --ri swoole
```

如果最后一条显示扩展未加载，按[安装 Swoole](/QuickStart/installSw.md)为这套 CLI PHP 安装扩展，并在 `php --ini` 指出的配置目录启用它。再次运行 `php --ri swoole`，确认输出版本信息后再重试。

## 端口已被占用

看到 `Address already in use` 时，先确认哪个进程正在监听：

```bash
lsof -nP -iTCP:9501 -sTCP:LISTEN
```

如果是已启动的同一个项目，在原终端按 `Ctrl+C`，或使用[管理命令](/QuickStart/command.md)按原运行模式停止。如果该端口由其他服务使用，修改本项目 `dev.php` 中的 `MAIN_SERVER.PORT`，并用新端口验证。生产模式对应 `produce.php`。参见[修改监听端口](/QuickStart/config.md#第一次改配置换一个端口)。

## 服务启动后连不上

先以前台模式运行 `php easyswoole.php server start`，查看第一个报错。另开终端，用 `curl -i http://127.0.0.1:9501/` 验证。若已修改端口，把 9501 换成实际监听端口。若从其他机器访问，先在部署机器上验证本地请求，再检查监听地址、端口映射和反向代理。

升级框架后如果根目录管理脚本本身报错，见[刷新项目管理脚本](/QuickStart/install.md#升级后刷新项目管理脚本)。

## 访问接口返回 404

1. 确认访问的是启动输出中的端口，再用 `curl -i http://127.0.0.1:9501/hello` 查看实际状态码。
2. 对照[第一个 HTTP 接口](/QuickStart/helloworld.md)，核对 `App/HttpController/Hello.php`、`App\HttpController`、类名 `Hello` 和公开方法 `index()` 的拼写与大小写。
3. 使用自定义 Router 时，核对请求方法及路径。如果启用了全局路由模式，显式注册对应路由。参见[路由基础](/Http/Routing/index.md)和[URL 到控制器的映射](/Http/Controller/routing.md)。
4. 如果报的是类加载错误，检查 `composer.json` 中的 `App\\` 映射并执行 `composer dump-autoload`。文件调整后重载 Worker，再请求同一个 URL 验证。

## 修改后没有生效

只改控制器等 Worker 加载的业务代码时，运行 `php easyswoole.php server reload`。改监听端口、Worker 数量或主进程启动配置时，完整停止并重新启动。服务以 `--mode=produce` 启动时，管理命令也要带 `--mode=produce`。重载后用相同请求验证变更，详见[热重启](/Advanced/reload.md)。

## 请求参数为空或未注入

- 普通控制器先确认数据来自 URL Query、表单还是 JSON，按[请求参数](/Http/Request/input.md)使用对应方法。发送 JSON 时设置 `Content-Type: application/json`。
- 注解控制器核对基类、Action 参数名、`Param(name: ...)`、HTTP 方法和 `ParamFrom`。对照[参数来源与传参示例](/Http/AnnotationController/params.md)重发请求。

## 无法写日志或 PID

从报错里找到实际目录。核对启动用户和目录权限，确认该用户能写入 `Log/`、`Temp/` 或配置中的自定义目录。后台运行和 systemd 下优先使用以项目根目录为基准的绝对路径。参见[文件路径](/QuickStart/notice.md#文件路径不要依赖当前工作目录)和[日志与错误](/Advanced/log-error.md)。

## 确认实际依赖版本

```bash
php -v
php --ri swoole
composer show easyswoole/easyswoole
composer show easyswoole/http
composer show easyswoole/http-annotation
```

反馈问题时提供出错命令、第一条完整报错、这些版本和最小复现代码。 [EasySwoole Issues](https://github.com/easy-swoole/easyswoole/issues)
