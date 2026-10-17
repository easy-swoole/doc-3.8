# Consul 客户端：Session 与其他端点

Session 是 Consul 中有有效期的对象，常用于与 KV 的 `acquire`、`release` 配合实现协作锁。客户端只提供这些 API 的请求入口；续期、锁失败重试和业务幂等需要应用自己处理。

## 创建、查看和销毁 Session

以下示例处于 Swoole 协程中，`$client` 已按[安装与连接](/Client/Consul/index.md)创建：

```php
use EasySwoole\Consul\Request\Session\Create;
use EasySwoole\Consul\Request\Session\Destroy;
use EasySwoole\Consul\Request\Session\Info;

$created = $client->sessions()->create(new Create([
    'name' => 'report-lock',
    'behavior' => 'delete',
    'TTL' => '30s',
]));

$sessionId = $created['ID'];
$info = $client->sessions()->info(new Info(['uuid' => $sessionId]));

// 工作结束后释放 Session。
$client->sessions()->destroy(new Destroy(['uuid' => $sessionId]));
```

`TTL` 到期后 Session 会失效；长任务应定期调用 `sessions()->renew()`。如果要用 KV 锁，`acquire` 的返回结果必须检查，不能因为请求没有抛异常就认为拿到了锁。Session 失效、进程退出和多实例部署都需要纳入锁方案设计。

## 一次加锁操作的入口

```php
use EasySwoole\Consul\Request\Kv;
use EasySwoole\Consul\Request\Session\Renew;

$acquired = $client->kv()->put(
    new Kv(['key' => 'locks/daily-report', 'acquire' => $sessionId]),
    'worker-1',
);

if ($acquired !== true) {
    throw new \RuntimeException('锁已被其他实例持有');
}

// 长时间持锁时，按 TTL 提前续期；续期失败应停止受锁保护的操作。
$client->sessions()->renew(new Renew(['uuid' => $sessionId]));

// 释放时也应检查 Consul 返回值，并在 finally 中销毁 Session。
$released = $client->kv()->put(
    new Kv(['key' => 'locks/daily-report', 'release' => $sessionId]),
    'worker-1',
);
```

以上是 API 入口演示，不是完整分布式锁实现。尤其是业务执行时间超过 TTL 时，原持有者即使尚未完成工作，也可能失去锁；关键业务应增加持久化幂等标识或 fencing token。

## 其他端点入口

2.x 还通过 `ConsulClient` 暴露以下端点。它们采用相同模式：先调用端点方法，再传入对应 `EasySwoole\Consul\Request\...` 请求对象。

| 客户端方法 | 主要用途 |
| --- | --- |
| `status()` | Leader、Raft Peers |
| `catalog()` | 数据中心、节点、服务目录 |
| `acl()` | ACL Token、Policy、Role 等 |
| `configuration()` | Config Entries |
| `connect()` | Connect 与 Intentions |
| `events()` | 事件触发与查询 |
| `queries()` | Prepared Queries |
| `snapshots()` | 集群快照 |
| `transactions()` | Consul Transactions |
| `operator()` | 集群运维接口 |

例如读取当前 Leader：

```php
use EasySwoole\Consul\Request\Status\Leader;

$leader = $client->status()->leader(new Leader(['dc' => 'dc1']));
```

不同端点返回的值不统一，调用前要查对应 Consul API 的响应结构；尤其是 Snapshot 返回原始二进制内容，不应当按普通 JSON 处理。

下一章：[认证、响应与异常](/Client/Consul/response.md)。

## 源码依据

- [Session 端点](https://github.com/easy-swoole/consul/blob/2.x/src/Session.php)
- [ConsulClient 端点列表](https://github.com/easy-swoole/consul/blob/2.x/src/ConsulClient.php)
