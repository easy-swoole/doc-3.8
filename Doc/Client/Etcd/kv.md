# Etcd 客户端：KV 读写与范围查询

以下示例假设已经按[安装与连接](/Client/Etcd/index.md)创建 `$client`，且调用处于协程环境。

## 写入与读取单个键

```php
$client->put('config/database/host', '127.0.0.1');

$result = $client->range('config/database/host');
if ((int) ($result['count'] ?? 0) > 0) {
    $value = $result['kvs'][0]['value'];
    echo $value; // 127.0.0.1
}
```

`range()` 返回 etcd 的响应数组，`count` 为零时不要直接访问 `kvs[0]`。2.x 客户端会自动对请求的 key/value 做 Base64 编码，也会自动解码返回的 `kvs`，调用方直接使用原始字符串。

## 读取写入前的值

```php
$result = $client->put(
    'config/database/host',
    '10.0.0.10',
    ['prev_kv' => true],
);

$oldValue = $result['prev_kv']['value'] ?? null;
```

`prev_kv` 只有在请求该选项且此前确实存在旧值时才会出现，返回的 `value` 同样由客户端解码。

## 前缀、范围与全部键

```php
// 查询以 config/ 开头的键。
$configs = $client->rangePrefix('config/');

// 按 etcd 的半开区间查询：[config/a, config/z)。
$part = $client->range('config/a', 'config/z');

// 查询全部键。生产环境应留意结果规模。
$all = $client->rangeAll();

// 可以把 etcd Range API 的选项放在第二个参数。
$firstTenKeys = $client->rangePrefix('config/', [
    'limit' => 10,
    'keys_only' => true,
]);
```

`rangePrefix()` 会计算范围终点；不需要自己拼接 `range_end`。前缀不能为空。大范围扫描可能返回大量数据，建议通过前缀、`limit` 等选项收窄范围。

## 删除

```php
// 删除单个键。
$deleted = $client->delete('config/database/host');
echo $deleted['deleted'] ?? 0;

// 同时返回删除前的键值。
$deletedWithPrevious = $client->delete(
    'config/database/host',
    previous: true,
);

// 删除前缀下的全部键，范围应先确认。
$deletedPrefix = $client->deletePrefix('config/old/');
```

`prev_kvs` 中的 key/value 会自动解码。也可调用 `$client->delete('config/a', 'config/z')` 删除指定范围。

## 历史版本压缩

```php
$client->compact(revision: 1000);
$client->compact(revision: 1000, physical: true);
```

压缩针对 etcd 的历史修订版本，和删除当前键不是一回事。先从业务响应的 `header.revision` 等字段确定需要压缩的修订版本；不要随意使用示例数字。

下一章：[租约与临时键](/Client/Etcd/lease.md)。

## 源码依据

- [Client KV 方法](https://github.com/easy-swoole/etcd-client/blob/2.x/src/Client.php)
