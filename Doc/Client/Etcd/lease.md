# Etcd 客户端：租约与临时键

租约为键提供有效期。把键写入时绑定租约，租约过期或被撤销后，绑定的键会被 etcd 删除。适合临时服务节点、短期会话标记等场景。

## 创建并绑定租约

以下示例假设 `$client` 已按[安装与连接](/Client/Etcd/index.md)创建：

```php
$lease = $client->grantLease(30); // TTL 30 秒
$leaseId = (int) $lease['ID'];

$client->put('sessions/user-123', 'online', [
    'lease' => $leaseId,
]);
```

`grantLease()` 的返回结构保留 etcd 原始字段，例如 `ID` 和 `TTL`。租约 ID 需要传回 `put()` 的 `lease` 选项；只调用 `grantLease()` 并不会让已有键自动过期。

## 查询、续期、撤销

```php
// 查询剩余 TTL，并让响应包含绑定的键。
$status = $client->leaseTimeToLive($leaseId, includeKeys: true);
var_dump($status['TTL'] ?? null, $status['keys'] ?? []);

// 单次续期请求。
$renewed = $client->keepLeaseAlive($leaseId);

// 主动撤销；绑定的键将被删除。
$client->revokeLease($leaseId);
```

`leaseTimeToLive()` 返回的 `keys` 已由组件做 Base64 解码。`keepLeaseAlive()` 是一次请求，**不会自动启动后台循环续期**。需要长期保留租约时，应在自己的循环中定期调用，并处理续期失败、进程退出和网络中断。循环定时器的使用可参见[基础进阶：定时器](/Advanced/timer.md)；长时间驻留的续期逻辑更适合放在[自定义进程](/Advanced/process.md)。

租约用于限时有效的键，不等于完整的分布式锁。多个实例竞争同一资源时，还需要使用 etcd 事务或其他原子协调机制；本组件 2.x 的公开 `Client` API 没有封装事务方法。

下一章：[认证与权限](/Client/Etcd/auth.md)。

## 源码依据

- [Client 租约方法](https://github.com/easy-swoole/etcd-client/blob/2.x/src/Client.php)
