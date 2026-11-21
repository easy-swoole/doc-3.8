# Fast-Cache：基础使用

按[安装](/Library/FastCache/index.md)完成主进程注册后，等服务启动且 Socket 就绪，再在控制器或 Service 的 Swoole 协程中调用。各示例均使用 `App\Cache\MyCache`。

## 普通值与 TTL

```php
use App\Cache\MyCache;

MyCache::getInstance()->set('home:title', '首页', ttl: 60);
$title = MyCache::getInstance()->get('home:title'); // '首页'
MyCache::getInstance()->del('home:title');
```

TTL 从写入时起按秒计算，必须是正整数。值过期或不存在时，`get()` 返回 `null`。覆盖写入时省略 `ttl` 或传 `null`，会清除原有过期时间。业务通过 `=== null` 判断缓存缺失时，应避免把 `null` 存作有效缓存值。

## 哈希

用 `hset($key, $field, $value)` 写入字段，`hget()` 读取字段，`hdel()` 删除字段。需要遍历时，按插入顺序分页，使用上次返回的游标继续。

```php
MyCache::getInstance()->hset('app:labels', 'home', '首页');
MyCache::getInstance()->hset('app:labels', 'help', '帮助');

$cursor = null;
do {
    $page = MyCache::getInstance()->hscan('app:labels', $cursor, count: 100);
    foreach ($page['items'] as $item) {
        // $item 包含 field 和 value。
    }
    $cursor = $page['cursor'];
} while ($cursor !== null);
```

扫描过程中删除任一字段会使已有游标失效。普通值、哈希和队列各自存储，同名键可以共存。TTL 适用于普通值。

## 内存队列

先用 `initQueue()` 设置容量，再用 `push()` 入队和 `pop()` 出队。初始化同名队列会清空原有消息，因此应由应用在缓存进程就绪后统一初始化。未初始化时，首次入队或出队会创建容量为 `PHP_INT_MAX` 的队列。

```php
MyCache::getInstance()->initQueue('preview-jobs', 128); // 统一初始化时调用。
$sent = MyCache::getInstance()->push('preview-jobs', ['id' => 42], timeout: 0.5);
$job = MyCache::getInstance()->pop('preview-jobs', timeout: 0.5);
```

队列满时入队等待空位，超时或队列关闭时返回 `false`。队列空时出队等待消息，超时或队列关闭时返回 `null`。消息在回包前就已出队，连接中断时可能丢失。需可靠消费的业务可使用[可信队列](/Library/Queue/index.md)。

下一章：[注意事项](/Library/FastCache/notes.md)。

## 版本与 GitHub

- [`easyswoole/fast-cache` 2.1.2 · GitHub](https://github.com/easy-swoole/fast-cache/tree/2.1.2)
