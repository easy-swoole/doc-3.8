# Etcd 客户端：响应、异常与 TLS

2.x 客户端返回 etcd JSON Gateway 的响应数组，保留 `header`、`revision`、`count` 等原始字段，并自动处理常用键值字段的 Base64 编解码。

## 读取响应

```php
$result = $client->range('config/app');

$revision = $result['header']['revision'] ?? null;
$count = (int) ($result['count'] ?? 0);
$value = $result['kvs'][0]['value'] ?? null;
```

调用方不需要再对 `kvs`、`prev_kv`、`prev_kvs` 的 `key` 和 `value` 执行 `base64_decode()`；租约详情中的 `keys` 和角色权限字段也会按组件实现解码。没有查到键时，应根据 `count` 或 `kvs` 判断，不要直接访问第一个元素。

## 捕获异常

```php
use EasySwoole\EtcdClient\Exception\EtcdException;
use EasySwoole\EtcdClient\Exception\TransportException;

try {
    $result = $client->range('config/app');
} catch (TransportException $exception) {
    // 请求发送或编码失败；可根据业务情况重试。
    throw $exception;
} catch (EtcdException $exception) {
    // etcd 返回非 2xx，或者响应 JSON 无法解析。
    throw $exception;
}
```

`TransportException` 继承 `EtcdException`，所以需要分别处理时应先捕获子类。`Config` 的 URL、API 版本、超时和证书组合无效时会抛 `InvalidArgumentException`，这是配置错误，不宜靠重试解决。

## HTTPS 与双向 TLS

etcd 启用 HTTPS 后，将 `endpoint` 改为 `https://` 地址。客户端会在非 443 端口（例如 2379）显式启用 TLS，并默认验证服务端证书。证书由系统信任的 CA 签发时，无须额外 TLS 参数：

```php
$client = (new \EasySwoole\EtcdClient\Etcd(
    new \EasySwoole\EtcdClient\Config(endpoint: 'https://etcd.internal:2379')
))->client;
```

使用私有 CA 时，通过 `TlsConfig` 指定 CA 文件。如果服务端还要求客户端证书，再同时提供证书和私钥：

```php
use EasySwoole\EtcdClient\Config;
use EasySwoole\EtcdClient\Etcd;
use EasySwoole\EtcdClient\TlsConfig;

$tls = new TlsConfig(
    caFile: '/run/secrets/etcd-ca.crt',
    clientCertificate: '/run/secrets/etcd-client.crt',
    clientPrivateKey: '/run/secrets/etcd-client.key',
    // 私钥加密时才需要：passphrase: getenv('ETCD_TLS_KEY_PASSPHRASE') ?: null,
);

$etcd = new Etcd(new Config(
    endpoint: 'https://etcd.internal:2379',
    timeout: 5.0,
    tls: $tls,
));

$client = $etcd->client;
```

如果只需要验证私有 CA 签发的服务端证书，`new TlsConfig(caFile: '/run/secrets/etcd-ca.crt')` 即可，无需客户端证书。证书和私钥路径必须同时提供，并确保服务进程有读取权限。证书文件与私钥文件不应提交到仓库。

如果通过 IP 地址连接，而证书签发给域名，可在 `TlsConfig` 中设置 `serverName: 'etcd.internal'`。使用[安装与连接](/Client/Etcd/index.md)中的工厂时，项目配置写法如下：

```php
'ETCD' => [
    'endpoint' => 'https://etcd.internal:2379',
    'apiVersion' => 'v3',
    'timeout' => 5.0,
    'tls' => [
        'caFile' => '/run/secrets/etcd-ca.crt',
        'clientCertificate' => '/run/secrets/etcd-client.crt',
        'clientPrivateKey' => '/run/secrets/etcd-client.key',
    ],
],
```

只用 HTTPS 和私有 CA 时，删去两个客户端证书字段即可。`TlsConfig` 只能用于 HTTPS；`caPath`、`verifyPeer` 和 `allowSelfSigned` 也是可选项，通常保持默认的证书校验，并通过 `caFile` 信任私有 CA。

## 当前接口范围

该组件 2.x 的公开 `Client` 方法覆盖 KV、租约、认证、用户和角色权限。它没有封装 watch 流或事务 API；若业务需要它们，应使用适合的客户端或按 etcd API 单独实现。不要把 `rangePrefix()` 轮询误当作实时 watch。

## 源码依据

- [Client](https://github.com/easy-swoole/etcd-client/blob/2.x/src/Client.php)
- [EasySwooleTransport](https://github.com/easy-swoole/etcd-client/blob/2.x/src/Transport/EasySwooleTransport.php)
- [Config](https://github.com/easy-swoole/etcd-client/blob/2.x/src/Config.php)
- [TlsConfig](https://github.com/easy-swoole/etcd-client/blob/2.x/src/TlsConfig.php)
