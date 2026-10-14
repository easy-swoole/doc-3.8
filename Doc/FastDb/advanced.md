# 转换与关联

本章介绍 FastDb 3.x 的 JSON、日期时间、自定义对象转换与实体关联查询。

## JSON 列转换

示例表的 `tags` 是 JSON 字段。使用 `ConvertList` 可以在 PHP 中以对象操作：

```php
use EasySwoole\FastDb\AbstractInterface\ConvertList;
use EasySwoole\FastDb\Attributes\Property;

#[Property(convertObject: ConvertList::class)]
public ?ConvertList $tags;
```

```php
$user = User::findRecord(1);

if ($user !== null) {
    $user->tags->append('swoole');
    $user->tags->remove('php', true);
    $user->update();
}
```

`ConvertList::toValue()` 写入 JSON 字符串。若希望 API 输出嵌套数组，需要在响应层自行转换；实体默认序列化会使用转换对象的 `toValue()`。

## 日期时间转换

数据库 `DATETIME` 可以映射为 `ConvertDateTime`：

```php
use EasySwoole\FastDb\AbstractInterface\ConvertDateTime;

#[Property(convertObject: ConvertDateTime::class)]
public ?ConvertDateTime $created_at;
```

```php
$user->created_at->modify('+1 day');
$user->update();
```

MySQL `DATETIME` 不保存时区。应用、PHP 默认时区和数据库连接应使用统一约定，跨地区系统通常在业务层统一使用 UTC。

## 自定义转换

当数据库保存的是整数、字符串等基础类型，而业务代码希望使用枚举或值对象时，可以实现 `ConvertObjectInterface` 自定义转换规则。

例如，`users.sex` 使用 `0`、`1`、`2` 分别表示未知、男性和女性：

```sql
ALTER TABLE `users`
    ADD COLUMN `sex` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0未知 1男性 2女性';
```

在 `App/Model/SexEnum.php` 中定义枚举：

```php
<?php

namespace App\Model;

use EasySwoole\FastDb\AbstractInterface\ConvertObjectInterface;

enum SexEnum implements ConvertObjectInterface
{
    case UNKNOWN;
    case MALE;
    case FEMALE;

    /**
     * 将数据库中的原始值转换为业务对象。
     */
    public static function toObject(mixed $data): object
    {
        return match ((int) $data) {
            1 => self::MALE,
            2 => self::FEMALE,
            default => self::UNKNOWN,
        };
    }

    /**
     * 将业务对象转换为可以写入数据库的值。
     */
    public function toValue(): int
    {
        return match ($this) {
            self::MALE => 1,
            self::FEMALE => 2,
            self::UNKNOWN => 0,
        };
    }
}
```

然后在实体属性上通过 `convertObject` 指定转换类：

```php
<?php

namespace App\Model;

use EasySwoole\FastDb\AbstractInterface\AbstractEntity;
use EasySwoole\FastDb\Attributes\Property;

class User extends AbstractEntity
{
    #[Property(isPrimaryKey: true)]
    public int $id;

    #[Property(convertObject: SexEnum::class)]
    public SexEnum $sex = SexEnum::UNKNOWN;
}
```

完成映射后，业务代码不再需要记忆数据库中的数字含义：

```php
$user = User::findRecord(1);

if ($user !== null) {
    // 从数据库读取 sex=1 时，toObject() 会将它转换为 SexEnum::MALE。
    if ($user->sex === SexEnum::MALE) {
        echo '男性';
    }

    // update() 时会调用 toValue()，最终向数据库写入数字 2。
    $user->sex = SexEnum::FEMALE;
    $user->update();
}
```

通过数组构造实体或调用 `setData()` 时也会执行相同的转换：

```php
$user = new User(['sex' => 1]);

var_dump($user->sex === SexEnum::MALE); // true

$user->setData(['sex' => SexEnum::FEMALE]);
$user->insert(); // 数据库保存为 2
```

整个转换过程可以理解为：

```text
数据库值 / setData() 原始值
        ↓ SexEnum::toObject()
实体中的 SexEnum 对象
        ↓ $sex->toValue()
插入、更新和实体序列化使用的数据库值
```

编写自定义转换类时应注意：

- `toObject()` 必须返回对象，并且通常应返回与实体属性类型一致的对象。
- `toObject()` 可能收到数据库驱动返回的数字字符串，例如 `'1'`，也可能收到属性初始化阶段的 `null`，转换器应明确处理这些值。
- `toValue()` 应返回数据库驱动能够保存的标量或 `null`，不要返回枚举对象本身。
- 向 `setData()` 传入已经是目标类型的对象时，FastDb 会直接使用该对象，不会重复转换。
- 对于 `?SexEnum` 这样的 nullable 属性，传入 `null` 时会保留 `null`；非 nullable 属性收到 `null` 时，转换器需要提供合理的默认结果或主动抛出异常。
- 同一个 `Property` 不要同时配置 `convertObject`、`assignCall` 和 `toValue`，这些是不同的字段转换方式。

上例遇到未知值时统一返回 `SexEnum::UNKNOWN`。如果业务要求数据库出现非法值就立即失败，也可以在 `default` 分支抛出 `UnexpectedValueException`。

## 关联查询

FastDb 的关联是按需执行的独立查询，不是自动 JOIN 或 eager loading。假设 `orders.userId` 指向用户：

```php
use EasySwoole\FastDb\Attributes\Relate;

class User extends AbstractEntity
{
    #[Relate(
        targetEntity: Order::class,
        targetProperty: 'userId',
        selfProperty: 'id'
    )]
    public function orders()
    {
        return $this->relateMany();
    }
}
```

```php
$user = User::findRecord(1);
$orders = $user?->orders();
```

遍历大量用户后逐个调用 `orders()` 会产生 N+1 查询。列表接口应收集用户 ID 后用 `IN` 批量查询，再由业务代码分组。

## 源码依据

- [转换接口](https://github.com/easy-swoole/fast-db/tree/3.x/src/AbstractInterface)
- [SexEnum 自定义转换示例](https://github.com/easy-swoole/fast-db/blob/3.x/tests/Model/SexEnum.php)
- [Relate](https://github.com/easy-swoole/fast-db/blob/3.x/src/Attributes/Relate.php)
