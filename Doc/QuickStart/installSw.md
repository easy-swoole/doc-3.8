# 安装 Swoole

Swoole 是 PHP 扩展，必须安装到运行 EasySwoole 的 CLI PHP 环境中。Web Server 使用的 PHP 配置与终端 PHP 可能不同，请以 `php --ini` 的结果为准。

## 使用 PECL

安装稳定发布版的常见方式：

```bash
pecl install swoole
```

然后在 CLI 使用的 `php.ini` 中启用：

```ini
extension=swoole.so
```

验证：

```bash
php --ri swoole
```

## 从源码编译

需要 PHP 开发工具、C/C++ 编译器和 `phpize`：

```bash
git clone https://github.com/swoole/swoole-src.git
cd swoole-src
git checkout <稳定版本标签>
phpize
./configure
make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)"
sudo make install
```

需要额外能力时先执行 `./configure --help`。常用选项包括：

```bash
./configure \
  --enable-sockets \
  --enable-swoole-curl \
  --enable-mysqlnd
```

TLS、PostgreSQL、c-ares、Brotli、io_uring 等能力需要对应系统开发库。不要复制与当前版本不匹配的旧编译参数。

## 容器方式

希望减少宿主机环境差异时，可以使用官方 Swoole Docker 镜像，或以官方 PHP 镜像自行构建 Swoole 扩展。务必固定镜像标签，避免 `latest` 带来不可预期升级。

## 常见检查

```bash
# 检查 CLI 加载的配置文件
php --ini

# 检查扩展是否加载并查看编译信息
php --ri swoole
```

出现 `Class "Swoole\\..." not found` 时，通常是执行命令的 PHP 没有加载扩展，而不是 Composer 自动加载问题。

## 源码依据

- [swoole/swoole-src](https://github.com/swoole/swoole-src)
- [Swoole Releases](https://github.com/swoole/swoole-src/releases)
- [Swoole 官方 Docker 镜像](https://github.com/swoole/docker-swoole)
