# 原子计数 AtomicManager


管理命名的 `Swoole\Atomic` 和 `Swoole\Atomic\Long`。

```php
use EasySwoole\Component\AtomicManager;

$manager = AtomicManager::getInstance();
$manager->add('request-count', 0);
$manager->get('request-count')?->add(1);

$manager->addLong('bytes', 0);
$manager->getLong('bytes')?->add(1024);
```

应在创建 Worker/子进程之前初始化，使底层共享内存能被派生进程继承。重复添加同名项不会覆盖原对象。


## 源码依据

- [Component 仓库](https://github.com/easy-swoole/component)
