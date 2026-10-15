# 连接对象与生命周期

连接池只负责调度对象，不知道如何连接数据库、如何判断 Redis 是否断线，也不知道业务使用后需要重置哪些状态。这些行为由连接对象通过 `ObjectInterface` 告诉连接池。

## ObjectInterface

所有放入 Pool 3.x 的对象都必须实现：

```php
namespace EasySwoole\Pool;

interface ObjectInterface
{
    public function gc();

    public function objectRestore();

    public function beforeUse(): bool;

    public function intervalCheck(): bool;
}
```

四个方法的调用时机如下：

```text
createObject()
      ↓
对象进入空闲队列
      ↓
beforeUse() ── false/异常 ──→ gc()
      ↓ true
业务协程使用对象
      ↓
objectRestore() ── 异常 ──→ gc()
      ↓
对象回到空闲队列
      ↓
intervalCheck() ─ false/异常 → gc()
```

## createObject：创建对象

继承 `AbstractPool` 后必须实现 `createObject()`。这里负责建立真实连接，失败时直接抛出异常：

```php
use EasySwoole\Pool\AbstractPool;
use EasySwoole\Pool\ObjectInterface;

final class ApiClientPool extends AbstractPool
{
    protected function createObject(): ObjectInterface
    {
        $client = new ApiClient('https://api.example.com');
        $client->connect();

        return $client;
    }
}
```

不要捕获异常后返回一个未连接的对象，也不要返回 `null`。组件会在创建失败时释放预占的容量，然后把异常交给调用方处理。

## beforeUse：借出前探活

对象从空闲队列取出后，Pool 会先调用 `beforeUse()`：

```php
public function beforeUse(): bool
{
    return $this->client->ping();
}
```

- 返回 `true`：把对象交给调用方。
- 返回 `false`：执行 `gc()` 丢弃对象，然后尝试获取其他对象。
- 抛出异常：丢弃当前对象；重试次数耗尽后向调用方抛出异常。

探活应有较短的客户端超时。`getObj(1.0)` 的 1 秒只限制等待 Channel 的时间，不限制 `ping()` 自身耗时。

## objectRestore：归还前恢复状态

归还对象时会调用 `objectRestore()`。这里用于清除上一次业务留下的状态：

```php
public function objectRestore(): void
{
    if ($this->client->inTransaction()) {
        $this->client->rollBack();
    }

    $this->client->clearRequestContext();
}
```

数据库事务、Redis 事务或订阅状态、HTTP 客户端请求头等都不能泄漏给下一个协程。如果无法恢复到安全状态，应抛出异常，让 Pool 丢弃该对象。

## intervalCheck：空闲时健康检查

Pool 会定时从空闲队列中取出一批对象并调用：

```php
public function intervalCheck(): bool
{
    return $this->client->ping();
}
```

返回 `false` 或抛出异常时，对象会执行 `gc()` 并从池中移除。这个方法只检查空闲对象；已借出的对象不会被后台检查。

## gc：关闭底层资源

对象失效、连接池缩容或连接池销毁时会调用：

```php
public function gc(): void
{
    $this->client->close();
}
```

`gc()` 是连接池定义的资源清理回调，不是 PHP 的析构函数。调用后 PHP 变量可能仍然引用这个对象，但底层连接已经不可再使用。

清理方法应尽量满足两个条件：

- 即使连接已经断开，再次清理也不会产生严重错误。
- 不执行长时间阻塞操作，避免拖慢回收和健康检查。

## 为第三方客户端编写适配器

第三方客户端通常没有实现 `ObjectInterface`，可以用适配器包装：

```php
final class ClientConnection implements \EasySwoole\Pool\ObjectInterface
{
    public function __construct(
        private ThirdPartyClient $client
    ) {
    }

    public function client(): ThirdPartyClient
    {
        return $this->client;
    }

    public function beforeUse(): bool
    {
        return $this->client->ping();
    }

    public function intervalCheck(): bool
    {
        return $this->client->ping();
    }

    public function objectRestore(): void
    {
        $this->client->reset();
    }

    public function gc(): void
    {
        $this->client->close();
    }
}
```

业务代码通过 `$connection->client()` 取得客户端。这样连接的建立、探活、恢复和关闭规则都集中在一个类中。
