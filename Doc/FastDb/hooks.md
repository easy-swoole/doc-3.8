# 实体生命周期钩子

FastDb 可以在实体初始化、插入、更新和删除之前执行自定义方法。钩子通过类级 PHP Attribute 声明，适合设置时间字段、规范化数据或执行实体自身的轻量校验。

## 支持的钩子

| Attribute | 触发时机 | 返回 `false` 是否中止操作 |
| --- | --- | --- |
| `OnInitialize` | 每次构造实体时 | 否 |
| `OnInsert` | `insert()` 生成写入数据前 | 是 |
| `OnUpdate` | `update()`计算变更字段前 | 是 |
| `OnDelete` | `delete()` 生成删除条件前 | 是 |

当前提供的是操作前钩子，没有 after-insert、after-update 或 after-delete 钩子。

## 完整实体示例

```php
<?php

namespace App\Model;

use EasySwoole\FastDb\AbstractInterface\AbstractEntity;
use EasySwoole\FastDb\Attributes\Hook\OnDelete;
use EasySwoole\FastDb\Attributes\Hook\OnInitialize;
use EasySwoole\FastDb\Attributes\Hook\OnInsert;
use EasySwoole\FastDb\Attributes\Hook\OnUpdate;
use EasySwoole\FastDb\Attributes\Property;

#[OnInitialize('initializeEntity')]
#[OnInsert('beforeInsert')]
#[OnUpdate('beforeUpdate')]
#[OnDelete('beforeDelete')]
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

    #[Property]
    public string $created_at;

    #[Property]
    public string $updated_at;

    public function tableName(): string
    {
        return 'users';
    }

    protected function initializeEntity(): void
    {
        // 每次 new User() 以及查询结果创建 User 实体时都会执行
    }

    protected function beforeInsert(): bool
    {
        $this->name = trim($this->name);

        if ($this->name === '' || !filter_var($this->email, FILTER_VALIDATE_EMAIL)) {
            return false;
        }

        $now = date('Y-m-d H:i:s');
        $this->created_at = $now;
        $this->updated_at = $now;
        return true;
    }

    protected function beforeUpdate(): bool
    {
        if (isset($this->name)) {
            $this->name = trim($this->name);
        }

        $this->updated_at = date('Y-m-d H:i:s');
        return true;
    }

    protected function beforeDelete(): bool
    {
        // 示例：系统账号不允许通过实体删除
        return isset($this->id) && $this->id !== 1;
    }
}
```

Attribute 中传入字符串时，FastDb 会在当前实体上查找并调用同名方法，因此钩子方法可以声明为 `protected`。

## OnInitialize 的执行顺序

构造实体时的顺序是：

```text
new User($data)
  → 根据 #[Property] 初始化默认值和 nullable 字段
  → 执行 OnInitialize
  → 将构造参数 $data 交给 setData($data, true)
```

这意味着 `OnInitialize` 发生在构造参数赋值之前。不要在该钩子中假设 `$data` 中的 `id`、`name` 等值已经写入实体。

`OnInitialize` 在所有实体构造场景中都会运行，包括：

- 业务代码执行 `new User()`。
- `findRecord()` 把一行数据库记录转换为实体。
- `findAll()` 或 `all()` 创建列表实体。

因此不要在 `OnInitialize` 中发送消息、写数据库或执行昂贵查询，否则一次列表查询可能产生大量额外操作。

## 插入钩子

```php
$user = new User([
    'name' => ' Alice ',
    'email' => 'alice@example.com',
]);

$ok = $user->insert();
```

执行顺序：

```text
insert()
  → OnInsert
  → 返回值严格等于 false 时停止
  → 属性转换与 toArray(true)
  → 生成并执行 INSERT
  → 成功后回填自增主键
```

`OnInsert` 对属性的修改会进入本次 INSERT，因此适合生成创建时间或规范化字段。

## 更新钩子

```php
$user = User::findRecord(10);
$user->name = 'New name';
$ok = $user->update();
```

`OnUpdate` 在 FastDb 计算变更字段之前执行，所以钩子中设置的 `updated_at` 会进入本次 UPDATE。即使业务代码没有修改其他字段，钩子修改了映射属性后也可能产生更新 SQL。

不要在钩子中调用当前实体的 `update()`，否则会递归再次触发 `OnUpdate`。

## 删除钩子

```php
$user = User::findRecord(10);

if ($user !== null && !$user->delete()) {
    // 可能被 OnDelete 拒绝，或者数据库没有删除对应记录
}
```

`OnDelete` 返回 `false` 可以阻止实体删除。但它不是完整的权限系统：调用者仍可能使用 `fastDelete()`、原始 SQL 或其他数据库工具绕过实体钩子。鉴权和关键数据保护还应在 Service、控制器权限以及数据库账号权限层实现。

## 使用 callable

除了实体方法名，还可以传入 callable。未显式配置参数时，callable 默认接收当前实体：

```php
use EasySwoole\FastDb\Attributes\Hook\OnInsert;

#[OnInsert([UserHook::class, 'beforeInsert'])]
class User extends AbstractEntity
{
    // ...
}

final class UserHook
{
    public static function beforeInsert(User $user): bool
    {
        $user->name = trim($user->name);
        return $user->name !== '';
    }
}
```

需要自定义参数时，可以使用 `Call::PARAM_CURRENT_ENTITY` 占位：

```php
use EasySwoole\FastDb\Attributes\Hook\Call;
use EasySwoole\FastDb\Attributes\Hook\OnInsert;

#[OnInsert(
    [UserHook::class, 'validate'],
    [Call::PARAM_CURRENT_ENTITY, 'create']
)]
class User extends AbstractEntity
{
    // ...
}
```

```php
final class UserHook
{
    public static function validate(User $user, string $scene): bool
    {
        return $scene === 'create' && isset($user->email);
    }
}
```

## 钩子继承

子实体没有声明某种钩子时，会沿父类向上查找该钩子；如果子类声明了同类型钩子，则使用距离子类最近的声明，不会自动同时执行父类和子类两个钩子。

如果确实需要复用父类逻辑，可以让子类钩子方法显式调用父类方法，再执行自己的逻辑。

## 不会触发钩子的操作

以下入口绕过实体生命周期钩子：

- `User::fastUpdate()`。
- `User::fastDelete()`。
- `FastDb::query()` 执行底层 `QueryBuilder`。
- `FastDb::rawQuery()`。
- 在其他工具或数据库客户端中直接执行 SQL。

这些入口适合批量或底层操作，但校验、时间字段和审计信息必须由调用方自行处理。

## 使用边界

- 钩子是同步执行的，耗时会直接增加当前数据库操作的延迟。
- 钩子内抛出的异常会向调用方传播，写操作不会继续执行。
- 只有严格的布尔值 `false` 会中止插入、更新或删除；`null`、`0` 等其他返回值不会按 `false` 处理。
- 钩子适合实体自身规则，不适合包含多个聚合、外部接口和复杂事务的完整业务流程。
- 涉及多表一致性的业务应放在 Service 中，并由 Service 明确管理事务。

## 源码依据

- [AbstractEntity 钩子调用](https://github.com/easy-swoole/fast-db/blob/3.x/src/AbstractInterface/AbstractEntity.php)
- [Hook Attributes](https://github.com/easy-swoole/fast-db/tree/3.x/src/Attributes/Hook)
- [ReflectionCache](https://github.com/easy-swoole/fast-db/blob/3.x/src/Utility/ReflectionCache.php)
