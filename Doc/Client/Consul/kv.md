# Consul 客户端：KV 配置读写

Consul KV 可以保存少量运行配置、服务开关或协调数据。本章示例假设已经按[安装与连接](/Client/Consul/index.md)创建 `$client`，并且调用位置处于 Swoole 协程中。

## 写入

```php
use EasySwoole\Consul\Request\Kv;

$result = $client->kv()->put(
    new Kv(['key' => 'app/payment/enabled']),
    'true',
);

var_dump($result); // Consul 返回的布尔结果；失败时也可能抛出异常。
```

第二个参数是原始字符串请求体，不会自动转成 JSON。若希望保存数组，先由应用编码：

```php
$value = json_encode(['enabled' => true], JSON_THROW_ON_ERROR);
$client->kv()->put(new Kv(['key' => 'app/payment/options']), $value);
```

## 读取并解码

```php
$records = $client->kv()->read(new Kv([
    'key' => 'app/payment/options',
]));

if (!is_array($records) || !isset($records[0]['Value'])) {
    throw new \RuntimeException('Consul 中没有找到配置');
}

$raw = base64_decode((string) $records[0]['Value'], true);
if ($raw === false) {
    throw new \RuntimeException('Consul KV Value 不是有效的 Base64');
}

$options = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
var_dump($options); // ['enabled' => true]
```

普通 KV 查询的响应是记录数组，其中 `Value` 为 Base64 编码；它不是直接可用的配置值。也可以传 `new Kv(['key' => '...', 'raw' => true])` 请求原始文本，此时返回类型可能是字符串，应按业务需要处理。不存在的 key 通常得到 HTTP 404，组件会抛出 `ConsulException`。

## 删除与递归查询

```php
$deleted = $client->kv()->delete(new Kv([
    'key' => 'app/payment/options',
]));

$all = $client->kv()->read(new Kv([
    'key' => 'app/payment/',
    'recurse' => true,
]));
```

`recurse` 用来查询前缀下的多个 key。删除时也可以设置 `recurse`，但它会删除整个前缀下的记录，务必先确认前缀范围。

## CAS 更新

需要避免覆盖其他进程刚写入的值时，可以把上次读取到的 `ModifyIndex` 放入 `cas`：

```php
$records = $client->kv()->read(new Kv(['key' => 'app/counter']));
$index = (int) $records[0]['ModifyIndex'];

$updated = $client->kv()->put(
    new Kv(['key' => 'app/counter', 'cas' => $index]),
    '2',
);

if ($updated !== true) {
    // 写入前已有其他进程修改该 key，重新读取后再决定是否重试。
}
```

组件会保留 `cas: 0` 这样的值，不会因其为零而从请求中删除。请求对象会被端点方法更新 URL，所以每次读写都应新建一个 `Kv` 对象。

下一章：[服务注册与发现](/Client/Consul/service.md)。

## 源码依据

- [KVStore](https://github.com/easy-swoole/consul/blob/2.x/src/KVStore.php)
- [KV 请求对象](https://github.com/easy-swoole/consul/blob/2.x/src/Request/Kv.php)
