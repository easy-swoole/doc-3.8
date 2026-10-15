# 跨进程共享

Swoole 的多个 Worker 是相互独立的 PHP 进程。普通数组、静态属性、`Singleton` 和 IOC 容器在每个 Worker 中各有一份，不能直接看到其他 Worker 的修改。

Component 提供三个基于 Swoole 共享内存的管理工具：

| 组件 | 底层结构 | 适合保存 |
| --- | --- | --- |
| `AtomicManager` | `Swoole\Atomic`、`Swoole\Atomic\Long` | 计数器、序号和简单状态值 |
| `TableManager` | `Swoole\Table` | 具有固定字段结构的多行数据 |
| `TableShm` | 封装后的 `Swoole\Table` | 数组、标量等可序列化数据 |

这些组件只能在同一台机器、由同一父进程创建的相关进程之间共享，不能代替 Redis 或数据库完成跨服务器共享。

## 必须在创建 Worker 前初始化

共享内存对象必须在 Swoole Server 创建 Worker 或 fork 子进程之前建立，子进程才能继承同一块共享内存。

EasySwoole 项目可以在根目录 `EasySwooleEvent.php` 的 `initialize()` 中创建：

```php
<?php

namespace EasySwoole\EasySwoole;

use EasySwoole\Component\AtomicManager;
use EasySwoole\Component\TableManager;
use EasySwoole\EasySwoole\AbstractInterface\Event;
use EasySwoole\EasySwoole\Swoole\EventRegister;
use Swoole\Table;

class EasySwooleEvent implements Event
{
    public static function initialize(): void
    {
        AtomicManager::getInstance()->add('request-count', 0);

        TableManager::getInstance()->add(
            'worker-status',
            [
                'pid' => [
                    'type' => Table::TYPE_INT,
                    'size' => 8,
                ],
                'status' => [
                    'type' => Table::TYPE_STRING,
                    'size' => 16,
                ],
            ],
            128
        );
    }

    public static function mainServerCreate(EventRegister $register): void
    {
    }
}
```

不要等到 `workerStart`、HTTP 请求或控制器 Action 中才首次创建跨进程共享对象。此时每个 Worker 可能创建出彼此独立的内存结构，无法达到跨进程共享目的。

## AtomicManager：共享数值

只需要原子增加、减少或读取一个整数时，优先使用 `AtomicManager`：

```php
$atomic = AtomicManager::getInstance()->get('request-count');
$atomic?->add(1);

$count = $atomic?->get();
```

原子操作不需要再加普通协程锁，适合高频计数。它只能保存整数，无法保存用户资料、数组或字符串。详细用法参见 [AtomicManager](/Component/atomic-manager.md)。

## TableManager：固定字段表格

需要按 key 保存多行记录，并且每行字段固定时，使用 `TableManager`：

```php
$table = TableManager::getInstance()->get('worker-status');

$table?->set('worker-1', [
    'pid' => getmypid(),
    'status' => 'running',
]);

$row = $table?->get('worker-1');
```

字段类型和字符串容量必须在建表时确定。它适合连接状态、Worker 心跳和小型共享索引，不适合保存大小无法预估的内容。详细用法参见 [TableManager](/Component/table-manager.md)。

## TableShm：序列化结构化数据

需要直接保存数组或标量，不想为每个字段定义列时，可以使用 `TableShm`：

```php
use EasySwoole\Component\TableShm;

$shm = TableShm::getInstance(
    maxRows: 1024,
    serializer: TableShm::SERIALIZER_JSON,
    columnSize: 65535
);

$shm->set('worker-1', [
    'pid' => getmypid(),
    'status' => 'running',
]);

$data = $shm->get('worker-1');
```

数据会先序列化再写入底层 `Swoole\Table`，使用方便但会增加序列化成本。序列化后的内容不能超过 `columnSize`。详细用法参见 [TableShm](/Component/table-shm.md)。

## 如何选择

- 单个整数计数或状态：`AtomicManager`。
- 数据字段固定、需要按列读取：`TableManager`。
- 数据结构灵活、接受整体序列化读写：`TableShm`。
- 多台服务器共享、需要持久化或数据量较大：Redis、数据库等外部存储。

## 共享不代表业务操作原子

`Swoole\Table` 的单次 `get()`、`set()` 等操作可以安全地被多个进程调用，但由多次调用组成的“先读取、计算、再写入”并不会自动成为一个整体原子操作：

```php
$row = $table->get('stock');
$row['amount']--;
$table->set('stock', $row);
```

两个 Worker 同时执行上面代码时仍可能覆盖结果。计数优先使用 Atomic 或 Table 自带的原子增减能力；复杂业务一致性应使用适合的锁、数据库事务或外部协调服务。

## 容量与生命周期

- 共享内存容量在创建时确定，运行中不能无限扩展。
- 字符串列和 `TableShm` 的 `columnSize` 按字节计算，中文和序列化数据可能占用更多字节。
- 不要保存数据库连接、文件资源、闭包或 Socket 对象。
- Server 完全停止后，共享内存数据随进程退出而消失，不具备持久化能力。
- reload Worker 时共享结构通常仍由 Master 持有，但业务不应把它当作永久数据源。

## 源码依据

- [AtomicManager](https://github.com/easy-swoole/component/blob/master/src/AtomicManager.php)
- [TableManager](https://github.com/easy-swoole/component/blob/master/src/TableManager.php)
- [TableShm](https://github.com/easy-swoole/component/blob/master/src/TableShm.php)
