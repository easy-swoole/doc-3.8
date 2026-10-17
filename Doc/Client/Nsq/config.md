# NSQ 客户端：配置、认证与 TLS

`Config` 是只读连接配置，创建时会校验参数，但不会立即连接 nsqd。第一次发布、订阅或显式调用 `connect()` 时，客户端才建立 TCP 连接并完成握手。

## 常用连接参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `host` / `port` | `127.0.0.1:4150` | nsqd TCP 地址 |
| `connectTimeout` | `3.0` | 连接和 TLS 握手超时，单位秒 |
| `readTimeout` | `60.0` | 接收超时，单位秒；`-1` 表示持续等待 |
| `writeTimeout` | `3.0` | 写入超时，单位秒 |
| `identify` | `[]` | NSQ IDENTIFY 参数，例如客户端名、心跳间隔 |
| `authSecret` | `null` | nsqd 启用 AUTH 时使用的密钥 |
| `tls` | `null` | 传入 `TlsConfig` 后启用 TLS |

```php
use EasySwoole\Nsq\Config;

$config = new Config(
    host: 'nsqd.internal',
    port: 4150,
    readTimeout: 30.0,
    identify: [
        'client_id' => 'order-consumer-1',
        'heartbeat_interval' => 30_000, // 毫秒
    ],
    authSecret: getenv('NSQ_AUTH_SECRET') ?: null,
);
```

`authSecret` 只在服务端声明需要认证时发送。密钥不要写入代码或日志。当前 2.x 不支持 Snappy、Deflate；不要在 `identify` 中启用。`readTimeout: -1` 仅表示等待数据时不超时，不会关闭服务端心跳。

## TLS 连接

nsqd 的 TLS 是在同一条 TCP 连接上协商升级的：先发送 MAGIC 和 IDENTIFY，收到服务端支持 TLS 的确认后才进行握手。客户端会根据 `tls` 自动设置 IDENTIFY 中的 `tls_v1`，不需要手动设置。

使用私有 CA 的示例：

```php
use EasySwoole\Nsq\Config;
use EasySwoole\Nsq\Nsq;
use EasySwoole\Nsq\TlsConfig;

$client = new Nsq(new Config(
    host: 'nsqd.internal',
    port: 4150,
    tls: new TlsConfig(
        caFile: '/run/secrets/nsq-ca.pem',
        serverName: 'nsqd.internal',
    ),
));
```

如果 nsqd 要求双向 TLS，再提供客户端证书和私钥：

```php
$tls = new TlsConfig(
    caFile: '/run/secrets/nsq-ca.pem',
    clientCertificate: '/run/secrets/nsq-client.pem',
    clientPrivateKey: '/run/secrets/nsq-client-key.pem',
    serverName: 'nsqd.internal',
);

$client = new Nsq(new Config(host: 'nsqd.internal', tls: $tls));
```

证书和私钥必须成对设置；加密私钥还可设置 `passphrase`。`serverName` 用于 SNI 和证书名称校验，按证书中的域名填写。默认会验证服务端证书；私有 CA 推荐使用 `caFile` 或 `caPath`，而不是关闭 `verifyPeer`。如果服务端未协商 TLS，客户端会拒绝连接，不会自动退回明文。

## 心跳和耗时任务

客户端在等待帧时会回复 NSQ 心跳；执行消费回调期间不会另开协程读取心跳。单条业务处理时间较长时，应在处理步骤之间调用 `$client->touch($message)`，并检查服务端消息超时与心跳设置。`touch()` 延长消息处理时限，但不能替代回复心跳；特别耗时的工作可拆分成异步任务。

下一章：[服务发现与故障处理](/Client/Nsq/discovery.md)。

## 源码依据

- [Config](https://github.com/easy-swoole/nsq/blob/2.x/src/Config.php)
- [TlsConfig](https://github.com/easy-swoole/nsq/blob/2.x/src/TlsConfig.php)
- [连接握手](https://github.com/easy-swoole/nsq/blob/2.x/src/Connection/Connection.php)
