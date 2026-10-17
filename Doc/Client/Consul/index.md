# Consul 客户端：安装与连接

`easyswoole/consul` 2.x 是 Consul HTTP API 的协程客户端。应用通过 `ConsulClient` 访问 KV、服务注册、健康检查、Session 等端点；它连接的是已运行的 Consul Agent，不会替你安装或启动 Consul 服务。

## 安装 2.x

在 EasySwoole 项目根目录执行：

```bash
composer require 'easyswoole/consul:^2.0'
composer show easyswoole/consul
```

Consul Agent 的 HTTP 地址必须能从应用所在机器访问。以下示例使用 `127.0.0.1:8500`；如果 Agent 部署在其他机器，请换成实际地址。

## 客户端结构

```text
ClientConfig（Agent 地址、端口、协议、API 版本）
      ↓
ConsulClient
      ├── status()、kv()、agent()、health() 等端点
      ↓
请求对象（例如 Request\Status\Leader）
      ↓
HTTP Transport → Consul Agent → 解码后的 PHP 值
```

`ConsulClient` 会按需创建并复用端点对象。每次 HTTP 调用由默认 Transport 创建独立的 HTTP 客户端；不需要为 `ConsulClient` 注册连接池。

## 单脚本测试

在项目根目录新建临时脚本 `consul-check.php`：

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use EasySwoole\Consul\ClientConfig;
use EasySwoole\Consul\ConsulClient;
use EasySwoole\Consul\Request\Status\Leader;
use Swoole\Coroutine;

$client = new ConsulClient(new ClientConfig(
    host: '127.0.0.1',
    port: 8500,
    apiVersion: 'v1',
    scheme: 'http',
));

Coroutine\run(function () use ($client): void {
    $leader = $client->status()->leader(new Leader());
    var_dump($leader); // 例如 "127.0.0.1:8300"；具体值取决于 Consul 集群。
});
```

运行 `php consul-check.php`。单独的 CLI 脚本需要 `Coroutine\run()`；EasySwoole 的 HTTP 控制器和 Task 回调本身处于协程环境，直接调用端点方法即可。`ClientConfig` 默认值是 `http://127.0.0.1:8500/v1/`，所以本地默认配置也可以写成 `new ConsulClient()`。

## 在项目配置中保存地址

可以在项目根目录的 `dev.php`、`produce.php` 中增加：

```php
'CONSUL' => [
    'host' => '127.0.0.1',
    'port' => 8500,
    'scheme' => 'http',
    'apiVersion' => 'v1',
    // 使用 HTTPS 时改为 scheme=https、port=8501，并按需添加 tls。
    // 'tls' => ['caFile' => '/run/secrets/consul-ca.crt'],
],
```

再建 `App/Utility/ConsulClientFactory.php`，集中读取配置：

```php
<?php

namespace App\Utility;

use EasySwoole\Consul\ClientConfig;
use EasySwoole\Consul\ConsulClient;
use EasySwoole\Consul\TlsConfig;
use EasySwoole\EasySwoole\Config;

final class ConsulClientFactory
{
    public static function create(): ConsulClient
    {
        $data = Config::getInstance()->getConf('CONSUL') ?? [];
        $tlsData = $data['tls'] ?? null;
        $tls = is_array($tlsData) ? new TlsConfig(
            verifyPeer: (bool) ($tlsData['verifyPeer'] ?? true),
            allowSelfSigned: (bool) ($tlsData['allowSelfSigned'] ?? false),
            caFile: $tlsData['caFile'] ?? null,
            caPath: $tlsData['caPath'] ?? null,
            clientCertificate: $tlsData['clientCertificate'] ?? null,
            clientPrivateKey: $tlsData['clientPrivateKey'] ?? null,
            passphrase: $tlsData['passphrase'] ?? null,
            serverName: $tlsData['serverName'] ?? null,
        ) : null;

        return new ConsulClient(new ClientConfig(
            host: (string) ($data['host'] ?? '127.0.0.1'),
            port: (int) ($data['port'] ?? 8500),
            apiVersion: (string) ($data['apiVersion'] ?? 'v1'),
            scheme: (string) ($data['scheme'] ?? 'http'),
            tls: $tls,
        ));
    }
}
```

这样控制器或 Task 可以调用 `ConsulClientFactory::create()` 后使用 `kv()` 等端点。这里仅创建配置和客户端对象，不会立即连接 Consul。`ClientConfig` 会检查空主机名、端口范围、空 API 版本，以及协议是否为 `http` 或 `https`。

## HTTPS 与双向 TLS

Consul Agent 开启 HTTPS 后，连接地址要改为实际的 HTTPS 监听地址。使用受系统信任 CA 签发的证书时，只需设置 `scheme: 'https'` 和对应端口；客户端默认验证服务端证书。使用私有 CA 时，传入 `TlsConfig`：

```php
use EasySwoole\Consul\ClientConfig;
use EasySwoole\Consul\ConsulClient;
use EasySwoole\Consul\TlsConfig;

$client = new ConsulClient(new ClientConfig(
    host: 'consul.internal',
    port: 8501,
    scheme: 'https',
    tls: new TlsConfig(
        caFile: '/run/secrets/consul-ca.crt',
    ),
));
```

如果 Agent 同时要求客户端证书，在上述配置中增加证书和私钥：

```php
$tls = new TlsConfig(
    caFile: '/run/secrets/consul-ca.crt',
    clientCertificate: '/run/secrets/consul-client.crt',
    clientPrivateKey: '/run/secrets/consul-client.key',
    // 私钥加密时才需要：passphrase: getenv('CONSUL_TLS_KEY_PASSPHRASE') ?: null,
);

$client = new ConsulClient(new ClientConfig(
    host: 'consul.internal',
    port: 8501,
    scheme: 'https',
    tls: $tls,
));
```

使用前面的工厂时，项目配置可以这样写：

```php
'CONSUL' => [
    'host' => 'consul.internal',
    'port' => 8501,
    'scheme' => 'https',
    'apiVersion' => 'v1',
    'tls' => [
        'caFile' => '/run/secrets/consul-ca.crt',
        'clientCertificate' => '/run/secrets/consul-client.crt',
        'clientPrivateKey' => '/run/secrets/consul-client.key',
    ],
],
```

只用 HTTPS 和私有 CA 时，删去两个客户端证书字段即可。如果通过 IP 连接而证书签发给域名，可以设置 `tls.serverName` 为证书域名。证书和私钥要成对配置，`TlsConfig` 只能用于 HTTPS；私钥口令从环境变量等安全位置读取。`caPath`、`verifyPeer` 和 `allowSelfSigned` 也是可选参数，通常保持默认的证书校验，并用 `caFile` 信任私有 CA。

## 请求对象的写法

每个端点方法接收对应的请求对象。构造函数数组和 setter 都可以设置参数：

```php
use EasySwoole\Consul\Request\Status\Leader;

$byArray = new Leader(['dc' => 'dc1']);

$bySetter = new Leader();
$bySetter->setDc('dc1');

$client->status()->leader($byArray);
$client->status()->leader($bySetter);
```

请求对象可能在执行时把 key、服务名等字段移入 URL，并修改自身状态；同一操作再次发送时应创建**新的请求对象**。下一章从 KV 的读写开始。

## 源码依据

- [Consul 2.x README](https://github.com/easy-swoole/consul/blob/2.x/README.md)
- [客户端配置](https://github.com/easy-swoole/consul/blob/2.x/src/ClientConfig.php)
- [客户端入口](https://github.com/easy-swoole/consul/blob/2.x/src/ConsulClient.php)
- [TLS 配置](https://github.com/easy-swoole/consul/blob/2.x/src/TlsConfig.php)
