# Fast-Cache：注意事项

## 重启后数据丢失

Fast-Cache 将普通缓存值、哈希和队列消息全部保存在缓存进程的内存中。服务完整停止并重新启动后，这些数据都会丢失，新进程会以空缓存启动。

## 配置与部署

| 配置项 | 默认值 | 用途 |
| --- | --- | --- |
| `serverName` | `EasySwoole` | 进程和 Socket 文件名的标识 |
| `tempDir` | `sys_get_temp_dir()` | 已存在且应用可写的绝对路径 |
| `timeout` | `1.0` | 单次操作共用的连接和读写预算，单位为秒 |
| `maxMemLimit` | `512M` | 缓存进程的 PHP 内存上限，普通值、哈希和队列共用 |

Socket 文件名为 `{serverName}.fastCache.sock`。同一主机上的服务实例应使用独立路径，目录权限应限制为可信应用进程。通信失败会抛出 `RuntimeException`，缓存调用方可按业务需要回源或向上层传播错误。

## 源码依据

- [FastCache 2.1.2 README](https://github.com/easy-swoole/fast-cache/blob/2.1.2/README.md)
- [FastCache 客户端实现](https://github.com/easy-swoole/fast-cache/blob/2.1.2/src/FastCache.php)
