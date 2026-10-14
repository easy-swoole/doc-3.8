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
- `chunk()` 适合报表导出、通知发送等一般批处理；需要严格不漏数据的迁移任务，更适合自行实现基于主键游标的 `WHERE id > last_id ORDER BY id LIMIT n`。
- 批量处理仍在当前请求或任务中同步执行。耗时任务不要长期占用 HTTP 请求，应放入 TaskWorker、队列消费者或独立命令进程。

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

`fastUpdate()` 不执行实体转换、变更比较和更新钩子。空条件数组可能生成没有 WHERE 的更新，调用前必须自行保证条件安全。

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

- [AbstractEntity](https://github.com/easy-swoole/fast-db/blob/3.x/src/AbstractInterface/AbstractEntity.php)
- [Query](https://github.com/easy-swoole/fast-db/blob/3.x/src/Beans/Query.php)
- [ListResult](https://github.com/easy-swoole/fast-db/blob/3.x/src/Beans/ListResult.php)
