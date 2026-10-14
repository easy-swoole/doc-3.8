# Query 使用

`EasySwoole\FastDb\Beans\Query` 用于给一个实体设置查询条件、字段、分页、排序和锁。通过实体的 `queryLimit()` 获得：

```php
use App\Model\User;
use EasySwoole\FastDb\Beans\Query;

$entity = new User();

/** @var Query $query */
$query = $entity->queryLimit();
$query->where('status', 1)
    ->where('score', 10, '>=')
    ->orderBy('id', 'DESC')
    ->limit(20);

$result = $entity->all();
```

`Query` 负责积累查询配置，真正执行查询的仍然是实体的 `all()`、`count()`、`sum()` 等方法：

```text
new User()
  → queryLimit() 取得 Query
  → Query 设置 where/orderBy/page 等条件
  → User::all() 生成并执行 SQL
  → 返回 ListResult
```

同一个实体在查询执行前重复调用 `queryLimit()`，取得的是同一个 Query 对象，条件会继续累积。

### 常用方法

| 方法 | 作用 |
| --- | --- |
| `where()` | 添加 AND 查询条件 |
| `orWhere()` | 添加 OR 查询条件 |
| `fields()` | 指定查询或写入字段，并可切换数组结果 |
| `returnAsArray()` | 查询结果直接返回数据库行数组 |
| `hideFields()` | 从查询结果或序列化结果中隐藏字段 |
| `persistFieldLimit()` | 把字段限制传给查询返回的子实体 |
| `limit()` | 限制返回数量 |
| `page()` | 设置分页、每页数量和是否统计总数 |
| `orderBy()` | 设置排序 |
| `groupBy()` | 设置分组 |
| `join()` | 添加 JOIN |
| `func()` | 直接操作底层 QueryBuilder |
| `selectForUpdate()` | 添加 `FOR UPDATE` 行锁 |
| `returnEntity()` | 从 Query 返回所属实体，继续调用实体方法 |

### where 与 orWhere

方法签名：

```php
where(string $column, mixed $value, $operator = '=', $condition = 'AND')
orWhere(string $column, mixed $value, $operator = '=')
```

常见条件：

```php
$entity = new User();
$entity->queryLimit()
    ->where('status', 1)
    ->where('score', 60, '>=')
    ->where('id', [1, 2, 3], 'IN')
    ->where('name', 'A%', 'LIKE');

$result = $entity->all();
```

OR 条件：

```php
$entity = new User();
$entity->queryLimit()
    ->where('status', 1)
    ->orWhere('score', 100, '>=');

$result = $entity->all();
```

多个 AND、OR 混用时，括号分组语义由底层 QueryBuilder 决定。复杂条件建议使用 `func()` 明确构建，或者使用[原始查询](/FastDb/raw-query.md)中的参数化 SQL。

### fields 与数组结果

只查询需要的字段：

```php
$entity = new User();
$entity->queryLimit()->fields(['id', 'name', 'email']);
$result = $entity->all();
```

结果中的每一项仍然是 `User` 实体。如果希望获得原始数组，把 `fields()` 第二个参数设为 `true`：

```php
$entity = new User();
$entity->queryLimit()
    ->fields(['id', 'name'], true)
    ->where('status', 1);

$rows = $entity->all()->list();
```

也可以单独调用：

```php
$entity->queryLimit()->returnAsArray();
```

数组模式返回数据库行，不执行实体属性转换。JOIN 查询包含额外列或别名时，通常更适合使用数组模式，因为实体模式只接收声明了 `#[Property]` 的属性。

### hideFields 与 persistFieldLimit

`hideFields()` 不会减少 SELECT 查询的数据库列，只是在构造结果时移除指定字段：

```php
$entity = new User();
$entity->queryLimit()->hideFields(['email', 'tags']);
$result = $entity->all();
```

如果希望返回的子实体在后续 `toArray()` 或 `json_encode()` 时继续保持字段限制，需要调用 `persistFieldLimit()`：

```php
$entity = new User();
$entity->queryLimit()
    ->fields(['id', 'name'])
    ->hideFields('email')
    ->persistFieldLimit();

$result = $entity->all();
echo json_encode($result, JSON_UNESCAPED_UNICODE);
```

需要从数据库层减少读取列时使用 `fields()`；只想隐藏 API 输出时使用 `hideFields()`。

### limit 与 page

只限制数量：

```php
$entity->queryLimit()->limit(20);
```

`limit()` 的第二个参数表示是否同时统计总数：

```php
$entity->queryLimit()->limit(20, true);
```

分页方法签名：

```php
page(?int $page, bool $withTotalCount = false, int $pageSize = 10)
```

示例：

```php
$entity = new User();
$entity->queryLimit()
    ->where('status', 1)
    ->orderBy('id', 'DESC')
    ->page(2, true, 20);

$result = $entity->all();
$list = $result->list();
$total = $result->totalCount();
$currentCount = count($result);
```

页码从 1 开始。`withTotalCount=true` 时，FastDb 使用 `SQL_CALC_FOUND_ROWS` 并额外执行 `SELECT FOUND_ROWS()` 获取总数；未请求统计时 `totalCount()` 返回 `null`。

页码和每页数量必须由业务限制合理范围，不能允许客户端传入无限大的 `pageSize`。

### orderBy

```php
$entity->queryLimit()->orderBy('created_at', 'DESC');
```

排序字段和方向属于 SQL 标识符，不能直接使用客户端输入。使用白名单：

```php
$allowedFields = ['id', 'score', 'created_at'];
$allowedDirections = ['ASC', 'DESC'];

$field = in_array($inputField, $allowedFields, true)
    ? $inputField
    : 'id';
$direction = in_array(strtoupper($inputDirection), $allowedDirections, true)
    ? strtoupper($inputDirection)
    : 'DESC';

$entity->queryLimit()->orderBy($field, $direction);
```

### groupBy 与聚合

```php
$entity = new User();
$entity->queryLimit()
    ->where('status', 1)
    ->groupBy('status');

$count = $entity->count();
```

实体还提供：

```php
$count = (new User())->count();
$sum = (new User())->sum('score');
$average = (new User())->avg('score');
$maximum = (new User())->max('score');
$minimum = (new User())->min('score');
```

聚合快捷方法只读取第一行。需要获得多个分组的完整结果时，使用 QueryBuilder 构建查询，不要依赖快捷聚合方法返回所有分组。

### join

```php
$entity = new User();
$entity->queryLimit()
    ->join(
        'user_profiles AS p',
        'p.user_id = users.id',
        'LEFT'
    )
    ->fields([
        'users.id',
        'users.name',
        'p.avatar',
    ], true)
    ->where('users.status', 1)
    ->orderBy('users.id', 'DESC');

$rows = $entity->all()->list();
```

JOIN 得到的 `avatar` 等额外列没有在 User 实体中声明时，实体模式会忽略这些列，因此示例使用数组模式。

### func 扩展底层查询

当 Query 没有直接提供某个方法时，可以通过 `func()` 取得底层 `EasySwoole\Mysqli\QueryBuilder`：

```php
use EasySwoole\Mysqli\QueryBuilder;

$entity = new User();
$entity->queryLimit()
    ->groupBy('status')
    ->func(function (QueryBuilder $builder): void {
        $builder->having('COUNT(*)', 10, '>');
    });

$rows = $entity->all();
```

`func()` 的回调只负责补充构建条件。最终的 SELECT 仍由实体 `all()` 完成。

### 子查询

`Query::where()` 的条件值可以接收由 `EasySwoole\Mysqli\QueryBuilder::subQuery()` 创建的子查询。

例如查询“状态正常，并且分数高于所有正常用户平均分”的用户：

```php
use App\Model\User;
use EasySwoole\Mysqli\QueryBuilder;

// 子查询：取得状态正常用户的平均分
$averageScore = QueryBuilder::subQuery();
$averageScore
    ->where('status', 1)
    ->get('users', null, 'AVG(score)');

// 外层查询：score 大于子查询结果
$entity = new User();
$entity->queryLimit()
    ->where('status', 1)
    ->where('score', $averageScore, '>')
    ->orderBy('score', 'DESC');

$result = $entity->all();

foreach ($result as $user) {
    echo $user->name . ': ' . $user->score . PHP_EOL;
}
```

生成的 SQL 结构类似：

```sql
SELECT *
FROM users
WHERE status = ?
  AND score > (
      SELECT AVG(score)
      FROM users
      WHERE status = ?
  )
ORDER BY score DESC;
```

外层和子查询中的参数都会合并到 QueryBuilder 的绑定参数中，不需要手动拼接值。

子查询的使用步骤是：

```text
QueryBuilder::subQuery()
  → 为子查询设置 where 等条件
  → 调用 get() 或 getOne() 完成子查询构建
  → 把子查询对象作为外层 where() 的值
  → 由实体 all() 执行完整 SQL
```

例如使用 `IN` 子查询：

```php
$activeUserIds = QueryBuilder::subQuery();
$activeUserIds
    ->where('status', 1)
    ->get('users', null, 'id');

$entity = new User();
$entity->queryLimit()
    ->where('id', $activeUserIds, 'IN')
    ->orderBy('id', 'ASC');

$result = $entity->all();
```

注意：

- 必须使用 `QueryBuilder::subQuery()` 创建子查询，普通 QueryBuilder 不能直接当作子查询条件值。
- 子查询必须先调用 `get()`、`getOne()` 等方法完成 SQL 构建。
- 子查询返回多行时，外层通常使用 `IN`、`NOT IN`、`EXISTS` 等操作；返回单值时可以使用 `=`、`>` 等比较。
- 子查询中的表名、字段名仍应由应用控制，动态值继续使用参数绑定。
- 复杂子查询需要通过 `EXPLAIN` 检查执行计划，避免对外层每一行反复扫描大表。

### selectForUpdate

```php
$db = \EasySwoole\FastDb\FastDb::getInstance();
$db->begin();

try {
    $entity = new User();
    $entity->queryLimit()
        ->where('id', 1)
        ->selectForUpdate();

    $user = $entity->all()->first();

    // 修改并保存实体
    $db->commit();
} catch (\Throwable $exception) {
    $db->rollback();
    throw $exception;
}
```

`selectForUpdate()` 应在事务中使用。查询、更新和提交必须保持在同一协程和同一数据库连接中。

### returnEntity

大部分 Query 方法返回 Query 自身，便于继续设置条件。如果希望从链式调用回到原实体并立即执行实体方法，可以使用 `returnEntity()`：

```php
$result = (new User())
    ->queryLimit()
    ->where('status', 1)
    ->orderBy('id', 'DESC')
    ->limit(20)
    ->returnEntity()
    ->all();
```

### 查询状态何时重置

Query 属于当前实体，不是全局对象。执行 `all()`、`count()`、聚合、更新或删除等操作后，实体通常会清理已积累的查询状态：

```php
$entity = new User();
$entity->queryLimit()->where('status', 1);
$activeUsers = $entity->all();

// 上一次 where 已被清理，这次需要重新设置
$entity->queryLimit()->where('status', 0);
$disabledUsers = $entity->all();
```

不要假设同一个实体执行一次查询后仍保留之前的 WHERE、ORDER BY 和 LIMIT。需要执行另一条查询时应重新设置条件。

## 源码依据

- [FastDb Query](https://github.com/easy-swoole/fast-db/blob/3.x/src/Beans/Query.php)
- [AbstractEntity](https://github.com/easy-swoole/fast-db/blob/3.x/src/AbstractInterface/AbstractEntity.php)
- [ListResult](https://github.com/easy-swoole/fast-db/blob/3.x/src/Beans/ListResult.php)
- [Mysqli QueryBuilder](https://github.com/easy-swoole/mysqli/blob/5.x/src/QueryBuilder.php)
