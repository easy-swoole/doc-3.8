# AccessPolicy：路径规则与通配符

一条策略由“资源路径”和“判断结果”组成。建议先按业务含义设计路径，不要直接把用户提交的任意 URL 当作权限名称。

```text
/admin/user/read
   │      │    └── 操作
   │      └─────── 资源
   └────────────── 业务区域
```

## 添加精确规则

```php
use EasySwoole\Policy\Policy;
use EasySwoole\Policy\PolicyNode;

$policy = new Policy();
$policy->addPath('/admin/user/read', PolicyNode::EFFECT_ALLOW);
$policy->addPath('/admin/user/delete', PolicyNode::EFFECT_DENY);

echo $policy->check('/admin/user/read');   // allow
echo $policy->check('/admin/user/delete'); // deny
echo $policy->check('/admin/user/update'); // unknown
```

重复添加同一路径会更新该节点的结果：

```php
$policy->addPath('/admin/user/read', PolicyNode::EFFECT_DENY);
echo $policy->check('/admin/user/read'); // deny
```

## 使用通配符

路径段 `*` 表示通配节点。末尾通配符可以匹配后续路径：

```php
$policy = new Policy();
$policy->addPath('/article/*', PolicyNode::EFFECT_ALLOW);

echo $policy->check('/article/read');          // allow
echo $policy->check('/article/comment/read');  // allow
echo $policy->check('/member/read');           // unknown
```

通配符位于中间且后面还有子节点时，只消费当前位置的一个路径段：

```php
$policy = new Policy();
$policy->addPath('/tenant/*/report/read', PolicyNode::EFFECT_ALLOW);

echo $policy->check('/tenant/acme/report/read');       // allow
echo $policy->check('/tenant/acme/2026/report/read');  // unknown
```

## 精确规则优先

可以先用通配符设置一类资源的默认策略，再用精确路径设置例外：

```php
$policy = new Policy();
$policy->addPath('/admin/*', PolicyNode::EFFECT_DENY);
$policy->addPath('/admin/profile/read', PolicyNode::EFFECT_ALLOW);

echo $policy->check('/admin/profile/read'); // allow，精确规则优先
echo $policy->check('/admin/user/read');    // deny，回退到 /admin/*
```

匹配时会先查找精确分支；精确分支没有有效结果时，再尝试同级通配分支。设计规则时应避免堆叠过多互相覆盖的规则，以免维护者难以判断最终结果。

## 路径合法性

`addPath()` 不接受空路径或连续的 `/`：

```php
$policy->addPath('');                  // 抛出 Policy Exception
$policy->addPath('/admin//user/read'); // 抛出 Policy Exception
```

调用 `check('/admin//user/read')` 时不会抛出上述异常，而是返回 `unknown`。配置规则来自数据库或后台表单时，应在加载阶段捕获异常并拒绝启用错误配置。

```php
use EasySwoole\Policy\Exception\Exception as PolicyException;

try {
    $policy->addPath($path, $effect);
} catch (PolicyException $throwable) {
    // 记录错误并阻止这份权限配置生效
}
```

下一章：[策略树与持久化](/Library/AccessPolicy/tree.md)。
