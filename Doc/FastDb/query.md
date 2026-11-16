# 查询与数据写入

以下示例假设已经注册 `default` 连接，并定义了 `App\Model\User` 实体。数据库操作应在 Swoole 协程内执行；EasySwoole HTTP 控制器本身运行于服务的协程环境中。

## 查询一条记录

按主键查询：

```php
$user = User::findRecord(1);

if ($user === null) {
    // 没有找到
}
```

按字段查询：

```php
$user = User::findRecord([
    'email' => 'alice@example.com',
    'status' => 1,
]);
```

带运算符：

```php
$user = User::findRecord([
    'score' => [100, '>='],
]);
```

复杂条件使用 `QueryBuilder` 回调：

```php
use EasySwoole\Mysqli\QueryBuilder;

$user = User::findRecord(function (QueryBuilder $query): void {
    $query->where('status', 1)
        ->orderBy('id', 'ASC');
});
```

## 查询多条记录

```php
$users = User::findAll();
$users = User::findAll('1,2,3');
$users = User::findAll(['status' => 1]);
$rows = User::findAll(['status' => 1], returnAsArray: true);
```

`findAll()` 返回普通数组；`returnAsArray: true` 返回数据库行数组，否则数组元素为 `User` 实体。

字符串或 UUID 主键列表不要使用逗号简写，因为逗号列表会转换成整数。应显式写 `IN`：

```php
$users = User::findAll([
    'id' => [['uuid-a', 'uuid-b'], 'IN'],
]);
```

复杂链式查询、字段限制、分页、JOIN 和底层构建器扩展参见[Query 使用](/FastDb/query-object.md)。


## 使用 chunk 分批处理

当数据量较大时，不要使用 `findAll()` 一次性把全部记录加载到内存。可以先设置查询条件，再使用 `chunk()` 分批读取：

```php
$entity = new User();
$entity->queryLimit()
    ->where('status', 1)
    ->orderBy('id', 'ASC');

$entity->chunk(function (User $user): void {
    // 每次回调接收一条 User 实体，而不是一整个批次数组
    echo $user->id . ':' . $user->name . PHP_EOL;
}, 100);
```

方法签名为：

```php
chunk(callable $callback, int $chunkSize = 10)
```

FastDb 每次查询 `$chunkSize` 条记录，但会逐条调用回调。所有批次处理完成后方法返回；回调抛出异常时，异常会继续向外抛出并终止后续处理。

例如分批导出用户：

```php
$handle = fopen('/tmp/users.csv', 'wb');

if ($handle === false) {
    throw new \RuntimeException('Cannot open export file');
}

try {
    $entity = new User();
    $entity->queryLimit()
        ->fields(['id', 'name', 'email'])
        ->where('status', 1)
        ->orderBy('id', 'ASC');

    $entity->chunk(function (User $user) use ($handle): void {
        fputcsv($handle, [
            $user->id,
            $user->name,
            $user->email,
        ]);
    }, 500);
} finally {
    fclose($handle);
}
```

使用 `chunk()` 时需要注意：

- 当前实现使用 OFFSET 分页，应设置稳定且尽量唯一的排序，例如按主键 `id ASC`。
- 回调每次接收单条实体；`chunkSize` 控制每次数据库读取数量，不控制回调参数数量。
- 遍历期间如果删除记录，或者修改了查询所依赖的 `status` 等字段，后续 OFFSET 可能发生偏移，导致跳过或重复处理。
- 处理过程中会删除记录或修改筛选字段时，可以使用 `chunkById()` 按稳定唯一列分批。
- 批量处理仍在当前请求或任务中同步执行。耗时任务不要长期占用 HTTP 请求，应放入 TaskWorker、队列消费者或独立命令进程。

## 按主键分批

```php
$entity = new User();
$entity->queryLimit()->where('status', 1)->orderBy('id', 'ASC');
$entity->chunk(function (User $user): void {
    // 逐条处理。
    echo $user->id;
}, 100);
```

`chunk($callback, $chunkSize = 10)` 按 OFFSET 分页读取，每次回调接收一条记录，不是一个数组块。各页沿用入口处从发起实体取得的查询配置，并使用首个查询的表和连接。回调可以另选连接执行自己的查询，之后的分页仍使用首个查询的数据源。请提供稳定排序；遍历中删除记录或修改筛选条件可能改变后续页的偏移，不适合需要稳定游标的迁移任务。 `chunk()` 不主动请求总数统计，按原始页条数判断是否继续；调用前显式开启的总数统计选项仍保留。

`$chunkSize` 必须大于 0。回调返回严格的 `false` 时立即停止，不再交付本批剩余记录或查询后续批次；没有返回值或返回其他值时继续。`chunk()` 本身不返回累计处理条数。

## 插入

```php
$now = date('Y-m-d H:i:s');

$user = new User([
    'name' => 'Alice',
    'email' => 'alice@example.com',
    'status' => 1,
    'score' => 0,
    'created_at' => $now,
    'updated_at' => $now,
]);

if (!$user->insert()) {
    throw new \RuntimeException('Insert user failed');
}

$id = $user->id;
```

自增主键会在成功插入后回填到实体属性。

## 更新

推荐先查询再修改：

```php
$user = User::findRecord(1);

if ($user === null) {
    throw new \RuntimeException('User not found');
}

$user->name = 'Alice New';
$user->updated_at = date('Y-m-d H:i:s');

if (!$user->update()) {
    throw new \RuntimeException('No row updated');
}
```

`update()` 只写入相对初始基准发生变化的字段。没有字段变化时会跳过 SQL 并返回 `true`；执行了 SQL但影响行数为 0 时返回 `false`。

无需实体转换和生命周期钩子时，可以直接更新：

```php
$affected = User::fastUpdate(1, [
    'status' => 0,
    'updated_at' => date('Y-m-d H:i:s'),
]);
```

复杂条件使用回调：

```php
$affected = User::fastUpdate(
    function (QueryBuilder $query): void {
        $query->where('score', 10, '<');
    },
    ['status' => 0]
);
```

`fastUpdate()` 不执行实体转换、变更比较和更新钩子。快捷更新和删除都要求提供有效的 WHERE 条件，空条件会抛出异常。

## 删除

实体删除：

```php
$user = User::findRecord(1);

if ($user !== null) {
    $user->delete();
}
```

快捷删除：

```php
$affected = User::fastDelete(['status' => 0]);
```

复杂条件仍推荐 QueryBuilder 回调。回调如果没有添加条件，可能删除全部记录。生产业务通常应使用软删除字段，避免物理删除后无法恢复。

## 在控制器中使用

```php
<?php

namespace App\HttpController;

use App\Model\User;
use EasySwoole\Http\AbstractInterface\Controller;

class Users extends Controller
{
    public function detail()
    {
        $id = (int) $this->request()->getRequestParam('id');
        $user = User::findRecord($id);

        if ($user === null) {
            $this->response()->withStatus(404);
            $this->writeJson(404, null, 'User not found');
            return;
        }

        $this->writeJson(200, $user->toArray(), 'OK');
    }
}
```

## 源码依据

- [AbstractEntity](https://github.com/easy-swoole/fast-db/blob/3.1.1/src/AbstractInterface/AbstractEntity.php)
- [Query](https://github.com/easy-swoole/fast-db/blob/3.1.1/src/Beans/Query.php)
- [ListResult](https://github.com/easy-swoole/fast-db/blob/3.1.1/src/Beans/ListResult.php)
