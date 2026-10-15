# 共享表 TableManager


管理命名的 `Swoole\Table`。

```php
use EasySwoole\Component\TableManager;
use Swoole\Table;

$manager = TableManager::getInstance();
$manager->add('users', [
    'name' => ['type' => Table::TYPE_STRING, 'size' => 64],
    'score' => ['type' => Table::TYPE_INT, 'size' => 8],
], 1024);

$table = $manager->get('users');
$table?->set('1001', ['name' => 'Alice', 'score' => 10]);
$manager->del('users');
```

跨进程使用的 Table 应在创建子进程前完成 `add()`。`del()` 会销毁底层 Table，请确保其他代码不再持有或使用它。


## 源码依据

- [Component 仓库](https://github.com/easy-swoole/component)
