# RabbitMQ 客户端：配置、TLS 与故障处理

连接参数由 `EasySwoole\AMQP\Config` 定义，创建客户端时传入 `new AMQP($config)`。配置对象应在使用连接的协程中传给客户端；不要在框架全局初始化阶段提前连接 Broker。

## 常用连接设置

```php
use EasySwoole\AMQP\AMQP;
use EasySwoole\AMQP\Config;

$client = new AMQP(new Config(
    host: 'rabbit.internal',
    port: 5672,
    user: 'app',
    password: getenv('AMQP_PASSWORD') ?: '',
    vhost: '/app',
    connectTimeout: 3.0,
    readTimeout: 60.0,
    writeTimeout: 3.0,
    heartbeat: 10,
));
```

| 参数 | 默认值 | 作用 |
| --- | --- | --- |
| `host`、`port` | `127.0.0.1`、`5672` | Broker 地址和 AMQP 端口 |
| `user`、`password`、`vhost` | `guest`、`guest`、`/` | 登录和虚拟主机 |
| `connectTimeout`、`readTimeout`、`writeTimeout` | `3.0`、`60.0`、`3.0` 秒 | 底层 Socket 超时 |
| `heartbeat` | `0` | 心跳周期；0 为关闭 |
| `maxMessageSize` | 64 MiB | 单条入站消息大小上限 |
| `tls` | `null` | TLS/mTLS 配置 |

`get()`、`publishConfirmed()`、批次的 `wait()` 等方法还有各自的 `timeout`：这是完整操作期限，包含排队、发送及等待 Broker 响应。传 `-1.0` 表示不设该操作期限；超时后连接可能被关闭以免继续使用响应边界不明的字节流。开启心跳也不能代替业务层的重连逻辑。

## TLS 和双向证书

```php
use EasySwoole\AMQP\TlsConfig;

$config = new Config(
    host: 'rabbit.internal',
    port: 5671,
    user: 'app',
    password: getenv('AMQP_PASSWORD') ?: '',
    tls: new TlsConfig(
        caFile: '/etc/ssl/rabbitmq-ca.pem',
        serverName: 'rabbit.internal',
    ),
);
```

若 Broker 要求客户端证书，还需在 `TlsConfig` 中同时配置 `clientCertificate` 和 `clientPrivateKey`，私钥有密码时增加 `passphrase`。证书身份认证可把 `Config` 的 `authMechanism` 改为 `Config::AUTH_EXTERNAL`，但 Broker 也必须启用该机制。生产环境应保持证书验证开启，并配置可信 CA，不建议用关闭校验来绕过证书错误。

## 常见异常与恢复

| 异常 | 排查方向 |
| --- | --- |
| `ConnectionException` | 主机、端口、账号、vhost、网络或 TLS 配置 |
| `TimeoutException` | Broker 延迟、网络阻塞或操作期限过短 |
| `ChannelClosedException` | 队列声明参数冲突、权限不足等 Broker 回复 |
| `ConnectionClosedByBrokerException` | Broker 主动关闭连接 |
| `PublisherNackException` | Publisher Confirm 收到 NACK |
| `MessageReturnedException` | `mandatory` 消息未能路由到队列 |

异常类均在 `EasySwoole\AMQP\Exception` 命名空间下。Broker 关闭 Channel/Connection 后不要复用失效对象；重建客户端和 Channel，重新声明拓扑并启动消费者。发布确认超时可能出现“Broker 已接收但客户端未收到确认”，因此补发前要依据业务 ID 做去重。`ack()`、`nack()` 的 delivery tag 只能用于原 Channel；连接断开后未确认消息可能被重新投递。

## 源码依据

- [Config](https://github.com/easy-swoole/amqp/blob/main/src/Config.php)
- [TlsConfig](https://github.com/easy-swoole/amqp/blob/main/src/TlsConfig.php)
- [AMQP README](https://github.com/easy-swoole/amqp/blob/main/README.md)
