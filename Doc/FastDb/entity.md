# 实体与字段映射

FastDb 使用继承自 `AbstractEntity` 的实体表示一张表，并通过 PHP 8 Attribute `#[Property]` 明确声明参与数据库映射的字段。

## 准备示例表

本章和后续查询示例使用 `easyswoole_demo` 数据库中的 `users` 表：

```sql
CREATE DATABASE easyswoole_demo
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE easyswoole_demo;

CREATE TABLE users (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(191) NOT NULL,
    status INT NOT NULL DEFAULT 1,
    score INT NOT NULL DEFAULT 0,
    tags JSON DEFAULT NULL,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_users_email (email),
    KEY idx_users_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

表结构与下面的实体属性一一对应。示例使用 InnoDB，以便后续章节演示事务和行锁。

## 定义 User 实体

新建 `App/Model/User.php`：

```php
<?php

namespace App\Model;

use EasySwoole\FastDb\AbstractInterface\AbstractEntity;
use EasySwoole\FastDb\Attributes\Property;

class User extends AbstractEntity
{
    #[Property(isPrimaryKey: true)]
    public int $id;

    #[Property]
    public string $name;

    #[Property]
    public string $email;

    #[Property(defaultValue: 1)]
    public int $status;

    #[Property(defaultValue: 0)]
    public int $score;

    #[Property]
    public ?string $tags;

    #[Property]
    public string $created_at;

    #[Property]
    public string $updated_at;

    public function tableName(): string
    {
        return 'users';
    }
}
```

只有带 `#[Property]` 的 public、非 static 属性参与输入、查询结果映射、写入和序列化。属性名就是数据库字段名，FastDb 3.x 的 `Property` 没有单独的列名映射参数。

## Property 常用参数

| 参数 | 作用 |
| --- | --- |
| `isPrimaryKey: true` | 声明主键，每个实体最多一个 |
| `defaultValue` | 实体初始化默认值 |
| `convertObject` | 指定实现 `ConvertObjectInterface` 的转换类型 |
| `assignCall` | 数据赋给属性时执行的转换回调 |
| `toValue` | 序列化、插入和更新前执行的转换回调 |

主键用于 `findRecord(1)`、实体 `update()` 和 `delete()` 等操作。没有主键的实体仍可使用条件查询，但不能使用依赖主键的快捷行为。

## nullable 和默认值

```php
#[Property]
public ?string $tags;

#[Property(defaultValue: 1)]
public int $status;
```

- nullable 属性未提供数据时初始化为 `null`。
- `defaultValue` 为实体提供默认值。
- 非 nullable 且无默认值的属性可能保持未初始化，读取前必须确保已赋值或从数据库加载。

实体默认值不等于数据库默认值。插入时实体实际生成的字段值可能覆盖数据库默认值，应根据业务决定默认值放在哪一层。

## 构造和 setData

```php
$user = new User([
    'name' => 'Alice',
    'email' => 'alice@example.com',
]);
```

构造数据会成为实体的初始比较基准。FastDb 更新时只写入相对基准发生变化的字段：

```php
$user = User::findRecord(1);
$user->name = 'Alice New';
$user->update();
```

手动构造一个用于更新的实体时，先把主键作为基准，再修改字段：

```php
$user = new User(['id' => 1]);
$user->status = 0;
$user->update();
```

下面的代码不会产生更新，因为构造时 `status=0` 已经被视为初始状态：

```php
$user = new User(['id' => 1, 'status' => 0]);
$user->update();
```

`setData()` 的第二个参数也控制是否接受为比较基准：

```php
$user->setData(['name' => 'Bob']);       // 形成待更新变更
$user->setData(['name' => 'Bob'], true); // 同时接受为新基准
```

## 序列化

```php
$user = User::findRecord(1);

if ($user !== null) {
    $array = $user->toArray();
    $json = json_encode($user, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
}
```

限制返回字段：

```php
$user->queryLimit()
    ->fields(['id', 'name', 'email'])
    ->hideFields('email');

$data = $user->toArray();
```

查询列表并希望限制传递给结果实体时使用 `persistFieldLimit()`：

```php
$entity = new User();
$entity->queryLimit()
    ->fields(['id', 'name'])
    ->persistFieldLimit();

$result = $entity->all();
```

## 输入安全

未知键会被 `setData()` 忽略，但仍不建议把未经验证的请求体整体传给实体。应显式挑选允许字段：

```php
$user = new User([
    'name' => $input['name'],
    'email' => $input['email'],
]);
```

这样可以避免客户端控制 `id`、`status`、`score` 等内部字段。

## 源码依据

- [AbstractEntity](https://github.com/easy-swoole/fast-db/blob/3.x/src/AbstractInterface/AbstractEntity.php)
- [Property](https://github.com/easy-swoole/fast-db/blob/3.x/src/Attributes/Property.php)
- [EntityReflection](https://github.com/easy-swoole/fast-db/blob/3.x/src/Beans/EntityReflection.php)
