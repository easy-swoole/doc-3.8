# Etcd 客户端：安装与连接

`easyswoole/etcd-client` 2.x 通过 etcd v3 JSON Gateway 操作 KV、租约、用户和权限。它使用 EasySwoole HTTP Client 发送请求；使用前需要有可访问的 etcd 服务，并启用 v3 JSON Gateway。

## 安装

在 EasySwoole 项目根目录执行：

```bash
composer require 'easyswoole/etcd-client:^2.0'
composer show easyswoole/etcd-client
```

## 对象关系

```text
Config（etcd 地址、API 版本、超时、可选证书）
   ↓
Etcd
   ↓ $etcd->client
Client（put、range、grantLease、authenticate 等方法）
   ↓
etcd v3 JSON Gateway
```

这里的 `client` 是 `Etcd` 对象的**属性**，使用 `$etcd->client`，不是 `$etcd->client()`。

## 单脚本测试

在项目根目录新建临时脚本 `etcd-check.php`：

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use EasySwoole\EtcdClient\Config;
use EasySwoole\EtcdClient\Etcd;
use Swoole\Coroutine;

$etcd = new Etcd(new Config(
    endpoint: 'http://127.0.0.1:2379',
    apiVersion: 'v3',
    timeout: 5.0,
));

Coroutine\run(function () use ($etcd): void {
    $client = $etcd->client;
    $client->put('demo/message', 'hello etcd');

    $result = $client->range('demo/message');
    var_dump($result['kvs'][0]['value'] ?? null); // hello etcd
});
```

运行 `php etcd-check.php`。独立 CLI 脚本用 `Coroutine\run()` 建立协程环境；在 EasySwoole HTTP 控制器、Task 等已有协程上下文中可以直接调用。示例会向 etcd 写入 `demo/message`，测试结束后如不需要可调用 `$etcd->client->delete('demo/message')` 清理。

## 框架中读取连接配置

例如在项目根目录的 `dev.php`、`produce.php` 中添加：

```php
'ETCD' => [
    'endpoint' => 'http://127.0.0.1:2379',
    'apiVersion' => 'v3',
    'timeout' => 5.0,
    // 使用 HTTPS 和私有 CA 时：
    // 'tls' => ['caFile' => '/run/secrets/etcd-ca.crt'],
],
```

新建 `App/Utility/EtcdClientFactory.php`：

```php
<?php

namespace App\Utility;

use EasySwoole\EasySwoole\Config as FrameworkConfig;
use EasySwoole\EtcdClient\Client;
use EasySwoole\EtcdClient\Config;
use EasySwoole\EtcdClient\Etcd;
use EasySwoole\EtcdClient\TlsConfig;

final class EtcdClientFactory
{
    public static function create(): Client
    {
        $data = FrameworkConfig::getInstance()->getConf('ETCD') ?? [];
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

        return (new Etcd(new Config(
            endpoint: (string) ($data['endpoint'] ?? 'http://127.0.0.1:2379'),
            apiVersion: (string) ($data['apiVersion'] ?? 'v3'),
            timeout: (float) ($data['timeout'] ?? 5.0),
            tls: $tls,
        )))->client;
    }
}
```

控制器内使用时：

```php
$client = \App\Utility\EtcdClientFactory::create();
$value = $client->range('config/app');
```

`Config` 只保存和校验地址等参数，`Etcd` 构造时也不会立即发起请求。组件默认端点是 `http://127.0.0.1:2379`，超时为 10 秒。下一章从 KV 开始。

HTTPS、私有 CA 和双向 TLS 的完整配置见[响应、异常与 TLS](/Client/Etcd/response.md)。

## 源码依据

- [etcd-client 2.x README](https://github.com/easy-swoole/etcd-client/blob/2.x/README.md)
- [Config](https://github.com/easy-swoole/etcd-client/blob/2.x/src/Config.php)
- [Etcd 入口](https://github.com/easy-swoole/etcd-client/blob/2.x/src/Etcd.php)
- [TLS 配置](https://github.com/easy-swoole/etcd-client/blob/2.x/src/TlsConfig.php)
