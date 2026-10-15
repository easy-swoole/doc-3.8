# Redis Pool 安装

`easyswoole/redis-pool` 4.x 基于 `easyswoole/pool` 3.x 和 `phpredis`，支持 Redis 单机和 Redis Cluster。

单机客户端继承 `Redis`，集群客户端继承 `RedisCluster`，数据命令使用 phpredis API。

## 环境要求

- PHP 8.1 及以上。
- Swoole 5.1 及以上。
- PHP `redis` 扩展。

```bash
php -v
php --ri swoole
php --ri redis
```

## 安装

```bash
composer require easyswoole/redis-pool:^4.0
composer show easyswoole/redis-pool
composer show easyswoole/pool
```

如果 `php --ri redis` 找不到扩展，需要先安装并启用 phpredis，仅安装 Composer 包不能代替 PHP 扩展。

## 完整接入流程

```text
安装 redis-pool 和 phpredis
  → 创建 Config
  → 在框架 initialize() 中 register()
  → 可选 keepMin() 预热
  → invoke()/defer() 获取连接
  → 执行 Redis 命令
  → 回调或协程结束后自动归还
```

下一章：[配置与注册](/Client/Redis/config.md)。
