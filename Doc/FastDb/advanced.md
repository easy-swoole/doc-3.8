# 转换与关联

本章以 FastDb `3.0.8` 为准。先按[实体与字段映射](/FastDb/entity.md)创建 `users` 表、`App\Model\User`，并按[连接配置](/FastDb/connection.md)注册连接。下面的字段示例需要在原有 `User` 类中**替换或新增**对应属性，不是创建多个同名实体类。代码块中的 `use` 导入语句应放在 PHP 文件的 `namespace` 后、类声明前；属性和方法放在类的大括号内。

## 转换在什么时候发生

`#[Property]` 有两种字段转换方式：

| 方式 | 实体属性 | 输入时 | `toArray()`、插入、更新时 |
| --- | --- | --- | --- |
| `convertObject` | 实现 `ConvertObjectInterface` 的对象 | 调用 `toObject()` | 调用对象的 `toValue()` |
| `assignCall` + `toValue` | 数组等普通 PHP 值 | 调用输入回调 | 调用输出回调 |

同一属性不能同时设置 `convertObject` 和回调。数据库查询结果、构造函数中的数据和 `setData()` 都会经过输入转换；直接赋值属性不会调用 `assignCall`。实体的 `toArray()` 使用**输出转换值**，不等于转换对象自己的 `toArray()`。`update()` 比较转换后的数据库值，因此对象内部修改也能被识别，成功保存后不会反复更新未变化字段。

## JSON 数组：ConvertList

示例表已有 `tags JSON DEFAULT NULL`。在 `App/Model/User.php` 中，把原来的 `public ?string $tags;` **替换**成：

```php
use EasySwoole\FastDb\AbstractInterface\ConvertList;
use EasySwoole\FastDb\Attributes\Property;

// 放在 User 类内，不能与原来的 string $tags 并存。
#[Property(convertObject: ConvertList::class)]
public ?ConvertList $tags;
```

读取、修改和保存：

```php
use App\Model\User;

$user = User::findRecord(1);
if ($user === null) {
    throw new \RuntimeException('User not found');
}

// 数据库 tags = '["php"]' 时，实体里是 ConvertList 对象。
$user->tags ??= new ConvertList([]); // 数据库为 NULL 时，先创建空列表。
$user->tags->append('swoole');
var_dump($user->tags->has('php', true)); // true
var_dump($user->tags->length());          // 2
var_dump($user->tags->first());           // 'php'
var_dump($user->tags->toArray());         // ['php', 'swoole']
var_dump($user->tags->toValue());         // '["php","swoole"]'

if (!$user->update()) {
    throw new \RuntimeException('Save tags failed');
}
var_dump($user->toArray()['tags']);       // '["php","swoole"]'，不是 PHP 数组。
```

`ConvertList::toObject()` 接受 JSON 字符串或 PHP 数组；`append(null)` 不追加。普通 `ConvertList` 的 `remove($value, $strict)` 按值删除并保留原数组键；留下不连续键时，`toValue()` 可能编码成 JSON 对象。若需要列表 JSON，可以重新排列索引：

```php
$user->tags->remove('php', true);
$user->tags = new ConvertList(array_values($user->tags->toArray()));
$user->update();
```

SQL `NULL` 和 JSON 空数组是两种值：

```php
$user->setData(['tags' => null]);
$user->update(); // SQL NULL。

$user->tags = new ConvertList([]);
$user->update(); // JSON []。
```

可空属性收到 `null` 会保持 `null`；非可空 `ConvertList` 属性收到 `null` 时，转换器会生成空列表。

## JSON 对象：ConvertBean

如果 JSON 列保存一个结构化对象，可以继承 `ConvertBean`。先给示例表增加字段：

```sql
ALTER TABLE users ADD COLUMN profile JSON DEFAULT NULL;
```

新建 `App/Model/Profile.php`：

```php
<?php

namespace App\Model;

use EasySwoole\FastDb\AbstractInterface\ConvertBean;

class Profile extends ConvertBean
{
    public string $nickname = '';
    public ?string $city = null;
}
```

在 `User` 类中增加：

```php
#[Property(convertObject: Profile::class)]
public ?Profile $profile;
```

```php
$user = User::findRecord(1);
if ($user === null) {
    throw new \RuntimeException('User not found');
}

$user->setData(['profile' => ['nickname' => '小明', 'city' => '杭州']]);
$user->update();
$user->profile->city = '上海';
$user->update(); // Bean 内部变化也会写入。

var_dump($user->profile->toArray()); // ['nickname' => '小明', 'city' => '上海']
var_dump($user->toArray()['profile']); // JSON 字符串。
```

`ConvertBean::toObject()` 从 JSON 字符串或数组恢复 Bean，`toValue()` 输出供数据库存储的 JSON 字符串。

## JSON 对象数组：类型化 ConvertList

FastDb `3.0.8` 的 `ConvertList` 可以通过 `itemClass()` 指定列表元素的 Bean 类型。先增加列：

```sql
ALTER TABLE users ADD COLUMN contacts JSON DEFAULT NULL;
```

新建 `App/Model/Contact.php`：

```php
<?php

namespace App\Model;

use EasySwoole\FastDb\AbstractInterface\ConvertBean;

class Contact extends ConvertBean
{
    public string $name = '';
    public string $phone = '';
}
```

新建 `App/Model/ContactList.php`：

```php
<?php

namespace App\Model;

use EasySwoole\FastDb\AbstractInterface\ConvertList;

class ContactList extends ConvertList
{
    protected static function itemClass(): ?string
    {
        return Contact::class;
    }
}
```

在 `User` 类中增加：

```php
#[Property(convertObject: ContactList::class)]
public ?ContactList $contacts;
```

```php
$user = User::findRecord(1);
if ($user === null) {
    throw new \RuntimeException('User not found');
}

// setData() 接受数组或 JSON 字符串，元素自动转为 Contact。
$user->setData(['contacts' => [['name' => '张三', 'phone' => '13800000000']]]);
$user->contacts->first()->phone = '13900000000';
$user->contacts->append(['name' => '李四', 'phone' => '13700000000']);
$user->contacts->append(new Contact(['name' => '王五', 'phone' => '13600000000']));
$user->update();

var_dump($user->contacts->first() instanceof Contact); // true
var_dump($user->contacts->length());                   // 3
var_dump($user->contacts->toArray()[0]->phone);       // '13900000000'
```

数据库中的内容类似：

```json
[{"name":"张三","phone":"13900000000"},{"name":"李四","phone":"13700000000"},{"name":"王五","phone":"13600000000"}]
```

`$user->contacts->toArray()` 返回 `Contact` 对象数组，而 `toValue()` 和 `$user->toArray()['contacts']` 返回 JSON 字符串。类型化列表删除元素后会重新排列键，仍输出 JSON 数组；`append()` 只接受元素数组或 `Contact` 对象，其他类型抛出 `InvalidArgumentException`。`itemClass()` 也可指定 `SplBean` 子类。

## 列表内嵌套 Bean

联系人内部还可有结构化地址，仍使用 `contacts` JSON 列，不需要单独的 `address` 数据库列。新建 `App/Model/ContactAddress.php`：

```php
<?php

namespace App\Model;

use EasySwoole\FastDb\AbstractInterface\ConvertBean;

class ContactAddress extends ConvertBean
{
    public string $city = '';
}
```

在 `Contact` 类中保留 `name`、`phone`，增加：

```php
use EasySwoole\Spl\Attribute\ConvertBean as NestedBean;

#[NestedBean(ContactAddress::class)]
public ?ContactAddress $address;
```

这里的 `#[NestedBean]` 来自 `easyswoole/spl`，用于 Bean 的内部属性；实体的数据库字段仍使用 FastDb `#[Property]`。

```php
$user->setData(['contacts' => [
    ['name' => '张三', 'phone' => '13800000000', 'address' => ['city' => '杭州']],
]]);
$user->contacts->first()->address->city = '上海';
$user->update();

var_dump($user->contacts->first()->address instanceof ContactAddress); // true
```

数据库中保存的 JSON 形如 `[{"name":"张三","phone":"13800000000","address":{"city":"上海"}}]`。嵌套 Bean 的修改同样参与变更比较。

## 日期时间：ConvertDateTime

示例表已有 `created_at DATETIME NOT NULL`。在 `User` 类中，把原来的 `public string $created_at;` **替换**为：

```php
use EasySwoole\FastDb\AbstractInterface\ConvertDateTime;

#[Property(convertObject: ConvertDateTime::class)]
public ConvertDateTime $created_at;
```

```php
$user = User::findRecord(1);
if ($user === null) {
    throw new \RuntimeException('User not found');
}

echo $user->created_at->format('Y-m-d');
$user->created_at->modify('+1 day');
$user->update();
```

`toObject()` 接受日期字符串、`DateTimeInterface`、整数 Unix 时间戳或 `null`；已有日期对象会复制，避免共享可变实例。非可空属性初始化时以 `null` 调用转换器，会得到当前时间。`toValue()` 通常输出 `Y-m-d H:i:s`，有微秒时输出 `Y-m-d H:i:s.u`；如需保留微秒，数据库列应使用 `DATETIME(6)`。MySQL `DATETIME` 不存时区，请统一 PHP 与数据库时区；空字符串和非法 MySQL 日期（包括零日期）会抛异常。

如果数据库列允许 `NULL`，属性可声明为 `?ConvertDateTime`；此时 `setData(['created_at' => null])` 会写入 SQL `NULL`，不会转换成当前时间。

## 自定义转换：枚举

数据库保存数字、业务代码使用枚举时，可以实现 `ConvertObjectInterface`。先增加示例列：

```sql
ALTER TABLE users
    ADD COLUMN sex TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0未知 1男性 2女性';
```

新建 `App/Model/SexEnum.php`：

```php
<?php

namespace App\Model;

use EasySwoole\FastDb\AbstractInterface\ConvertObjectInterface;

enum SexEnum: int implements ConvertObjectInterface
{
    case UNKNOWN = 0;
    case MALE = 1;
    case FEMALE = 2;

    public static function toObject(mixed $data): object
    {
        return self::tryFrom((int) $data) ?? self::UNKNOWN;
    }

    public function toValue(): int
    {
        return $this->value;
    }
}
```

在 `User` 类中增加：

```php
#[Property(convertObject: SexEnum::class)]
public SexEnum $sex = SexEnum::UNKNOWN;
```

```php
$user = User::findRecord(1);
if ($user === null) {
    throw new \RuntimeException('User not found');
}

// 数据库 sex=1，驱动也可能返回字符串 '1'。
var_dump($user->sex === SexEnum::MALE); // true
$user->sex = SexEnum::FEMALE;
$user->update();                       // 数据库写入 2。
var_dump($user->toArray()['sex']);     // 2

$user->setData(['sex' => 1]);
var_dump($user->sex === SexEnum::MALE); // true
```

`toObject()` 必须返回对象，通常与属性声明类型一致；`toValue()` 返回可写入数据库的值。非可空转换属性初始化时可能把默认值或 `null` 传给转换器，应明确处理。上例把未知值转成 `UNKNOWN`；若需严格拒绝非法数据库值，可抛异常。`setData()` 收到已是目标类型的对象时不重复转换。

## 不创建对象：assignCall 与 toValue

如果希望 JSON 列在 PHP 中直接使用数组，可配对两个回调。上面的 `tags` 已用于 `ConvertList`，这里另加 `meta` 列，避免在同一属性上混用方式：

```sql
ALTER TABLE users ADD COLUMN meta JSON DEFAULT NULL;
```

在 `User` 类中增加属性和方法：

```php
use EasySwoole\FastDb\Attributes\Hook\Call;

#[Property(
    assignCall: new Call([User::class, 'decodeMeta']),
    toValue: new Call([User::class, 'encodeMeta'])
)]
public ?array $meta;

public static function decodeMeta(string|array|null $value): ?array
{
    if ($value === null || is_array($value)) {
        return $value;
    }
    return json_decode($value, true, 512, JSON_THROW_ON_ERROR);
}

public static function encodeMeta(?array $value): ?string
{
    return $value === null ? null : json_encode($value, JSON_THROW_ON_ERROR);
}
```

```php
$user = User::findRecord(1);
if ($user === null) {
    throw new \RuntimeException('User not found');
}

$user->setData(['meta' => '{"theme":"dark"}']);
var_dump($user->meta);              // ['theme' => 'dark']
$user->meta['theme'] = 'light';
$user->update();
var_dump($user->toArray()['meta']);  // '{"theme":"light"}'

$user->meta = ['theme' => 'blue'];   // 已是数组时可直接赋值。
$user->update();                    // 输出回调仍会编码成 JSON。
```

默认情况下，属性回调只收到当前字段值。若还需要当前实体，可显式传参：

```php
toValue: new Call(
    [User::class, 'encodeMetaWithContext'],
    [Call::PARAM_PROPERTY_VALUE, Call::PARAM_CURRENT_ENTITY]
)
```

相应方法签名可写成 `encodeMetaWithContext(?array $value, User $entity): ?string`。`PARAM_PROPERTY_VALUE` 替换为当前值，`PARAM_CURRENT_ENTITY` 替换为当前实体，其他参数按字面传入。直接赋值不执行 `assignCall`，因此需确保赋入值符合属性声明类型。

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

- [FastDb 3.0.8 README：属性转换](https://github.com/easy-swoole/fast-db/blob/3.0.8/README.md#属性转换)
- [ConvertList](https://github.com/easy-swoole/fast-db/blob/3.0.8/src/AbstractInterface/ConvertList.php)
- [ConvertDateTime](https://github.com/easy-swoole/fast-db/blob/3.0.8/src/AbstractInterface/ConvertDateTime.php)
- [ConvertBean](https://github.com/easy-swoole/fast-db/blob/3.0.8/src/AbstractInterface/ConvertBean.php)
- [FieldCodec](https://github.com/easy-swoole/fast-db/blob/3.0.8/src/Internal/FieldCodec.php)
- [Property](https://github.com/easy-swoole/fast-db/blob/3.0.8/src/Attributes/Property.php)
