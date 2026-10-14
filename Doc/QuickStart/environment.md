# 环境要求

## 必需环境

根据 EasySwoole `3.x` 最新 `composer.json`：

- PHP `8.1` 或更高版本。
- Swoole 扩展 `5.1` 或更高版本。
- JSON 扩展。
- Composer 2。
- Linux、macOS 或适合运行 Swoole 的容器环境。

生产环境建议使用 Swoole 的稳定发布版，并先核对该版本支持的 PHP 范围。Swoole `master` 当前是开发分支，不应仅因为版本号更新就直接用于生产。

## 检查环境

```bash
php -v
composer --version
php --ri swoole
php -m | grep -E 'json|mbstring|swoole'
```

也可以使用 PHP 检查关键版本：

```bash
php -r 'echo PHP_VERSION, PHP_EOL; echo swoole_version(), PHP_EOL;'
```

## 推荐扩展

HTTP Annotation 的最新版还会使用 `mbstring`、DOM、SimpleXML 和 libxml。根据业务能力，可能还需要：

- `openssl`：HTTPS、TLS 客户端。
- `curl`：HTTP 客户端及 Swoole Hook。
- `sockets`：套接字相关功能。
- `pdo`、`pdo_mysql`：数据库访问。
- `pcntl`、`posix`：CLI 进程管理环境常用扩展。

## 端口与权限

EasySwoole 默认监听 `0.0.0.0:9501`。启动前确认端口没有被占用：

```bash
lsof -iTCP:9501 -sTCP:LISTEN
```

使用 1024 以下端口通常需要额外权限，更推荐由 Nginx/Caddy 监听 80/443，再反向代理到 EasySwoole。

## 版本建议

项目必须提交 `composer.lock`。升级框架、HTTP 或 Annotation 组件后，应重新执行接口测试，尤其关注路由、请求参数来源、上传文件和常驻内存行为。

## 源码依据

- [EasySwoole 3.x composer.json](https://github.com/easy-swoole/easyswoole/blob/3.x/composer.json)
- [Swoole 源码与安装说明](https://github.com/swoole/swoole-src)
- [HTTP Annotation 4.x](https://github.com/easy-swoole/http-annotation/tree/4.x)
