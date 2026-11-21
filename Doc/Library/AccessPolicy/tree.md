# AccessPolicy：策略树与持久化

日常权限判断优先使用 `Policy`。需要直接维护树节点、导出结构或恢复结构时，可以使用 `PolicyNode`。

## 直接构建策略树

```php
use EasySwoole\Policy\AccessStatus;
use EasySwoole\Policy\PolicyNode;

$root = new PolicyNode('*');
$article = $root->addChild('article');
$article->addChild('read')->setAllow(AccessStatus::ALLOW);
$article->addChild('delete')->setAllow(AccessStatus::DENY);

$node = $root->search('/article/read');
$effect = $node?->getEffect() ?? AccessStatus::UNKNOWN;

echo $effect->value; // allow
```

`search()` 返回匹配到的节点或 `null`，因此直接使用 `PolicyNode` 时要自行把 `null` 转换为 `AccessStatus::UNKNOWN`。

## 导出策略结构

`Policy::toArray()` 和 `PolicyNode::toArray()` 都可以导出完整树结构：

```php
$data = $root->toArray();
$json = json_encode(
    $data,
    JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR
);
```

对应结构类似：

```json
{
    "name": "*",
    "leaves": {
        "article": {
            "name": "article",
            "leaves": {
                "read": {
                    "name": "read",
                    "leaves": [],
                    "allow": "allow"
                }
            },
            "allow": "unknown"
        }
    },
    "allow": "unknown"
}
```

导出数组中的 `allow` 字段使用 `allow`、`deny`、`unknown` 字符串。恢复时由组件校验并转换为枚举。

## 从数组恢复 PolicyNode

```php
$data = json_decode($json, true, 512, JSON_THROW_ON_ERROR);
$root = new PolicyNode($data);

$node = $root->search('/article/read');
$effect = $node?->getEffect() ?? AccessStatus::UNKNOWN;
```

也可以在节点名称不变时调用 `restore()` 更新节点内容：

```php
$root = new PolicyNode('*');
$root->restore($data);
```

`Policy` 没有接收导出数组的构造参数。业务如果希望继续调用 `Policy::check()`，更适合持久化下面这样的平面规则，然后重新构建对象。加载时通过 `AccessStatus::from()` 将保存的字符串转换成枚举；非法字符串会抛出 `ValueError`：

```php
use EasySwoole\Policy\Policy;

$rules = [
    ['/article/read', 'allow'],
    ['/article/delete', 'deny'],
];

$policy = new Policy();
foreach ($rules as [$path, $effect]) {
    $policy->addPath($path, AccessStatus::from($effect));
}
```

## 动态更新与多 Worker

策略对象保存在当前进程内存中，不会自动同步给其他 Worker。生产环境推荐保存规则版本，并在每个 Worker 中用完整规则构建一个新对象，再整体替换旧对象：

```text
数据库修改规则并递增版本
          ↓
各 Worker 收到通知或定期检查版本
          ↓
读取完整规则并构建新的 Policy
          ↓
校验成功后整体替换旧对象
```

组件没有删除单条路径的公开方法。需要撤销规则时，不要继续修改旧树，应从当前有效规则重新构建 `Policy`。

下一章：[框架鉴权接入](/Library/AccessPolicy/integration.md)。

## 版本与 GitHub

- [`easyswoole/policy` 1.2.2 · GitHub](https://github.com/easy-swoole/policy/tree/1.2.2)
