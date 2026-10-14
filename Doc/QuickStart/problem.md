# 快速开始常见问题

## Swoole 扩展未加载

```text
Class "Swoole\\..." not found
```

检查命令实际使用的 PHP：

```bash
which php
php --ini
php --ri swoole
```

Composer 安装成功不代表 PHP 已加载 Swoole 扩展。

## 端口已被占用

```bash
lsof -iTCP:9501 -sTCP:LISTEN
```

停止旧进程或修改 `MAIN_SERVER.PORT`。不要直接删除 PID 文件来代替停止仍在运行的服务。

## 修改代码没有生效

EasySwoole 是常驻内存服务，需要重载 Worker：

```bash
php easyswoole.php server reload
```

如果变更涉及启动期配置或主服务，执行完整停止和启动。

## 控制器返回 404

依次检查：

1. 文件路径和命名空间是否匹配 `App\\HttpController`。
2. 类名与文件名大小写是否一致。
3. Action 是否为公开实例方法。
4. 执行 `composer dump-autoload`。
5. 自定义 Router 是否开启了全局模式。

## 无法写日志或 PID

确认运行用户对 `Log/`、`Temp/` 或自定义目录有权限。守护模式尤其要避免相对路径。

## Annotation 参数没有注入

- 控制器必须继承 `AnnotationController`。
- Action 参数名必须与 `Param(name: ...)` 一致。
- HTTP 方法必须符合 `Api::allowMethod`。
- 参数来源 `ParamFrom` 必须与请求体类型一致。

## 如何确认真实依赖版本

```bash
composer show easyswoole/easyswoole
composer show easyswoole/http
composer show easyswoole/http-annotation
```

排查问题时应提供 PHP、Swoole、框架和组件版本，以及最小复现代码。

## 参考

- [EasySwoole Issues](https://github.com/easy-swoole/easyswoole/issues)
- [Swoole Issues](https://github.com/swoole/swoole-src/issues)
