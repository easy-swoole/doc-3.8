# AccessPolicy：框架鉴权接入

下面以后台控制器为例，将身份认证和权限判断放进公共 Base 控制器。请求先验证登录状态，再把当前 Action 映射为稳定的权限路径，最后交给 `Policy` 判断。

## 建立策略管理器

新建 `App/Permission/AccessPolicyManager.php`：

```php
<?php

namespace App\Permission;

use EasySwoole\Component\Singleton;
use EasySwoole\Policy\Policy;
use EasySwoole\Policy\PolicyNode;

final class AccessPolicyManager
{
    use Singleton;

    /** @var array<string, Policy> */
    private array $policies = [];

    public function forRole(string $role): Policy
    {
        return $this->policies[$role] ??= $this->build($role);
    }

    private function build(string $role): Policy
    {
        $policy = new Policy();

        // 实际项目应从配置或数据库读取这些规则。
        $rules = match ($role) {
            'superAdmin' => [
                ['/admin/*', PolicyNode::EFFECT_ALLOW],
            ],
            'operator' => [
                ['/admin/user/read', PolicyNode::EFFECT_ALLOW],
                ['/admin/user/create', PolicyNode::EFFECT_ALLOW],
                ['/admin/user/delete', PolicyNode::EFFECT_DENY],
            ],
            default => [],
        };

        foreach ($rules as [$path, $effect]) {
            $policy->addPath($path, $effect);
        }

        return $policy;
    }
}
```

`Singleton` 让每个 Worker 拥有一个策略管理器，并在该实例中按角色缓存策略。它不是跨进程共享数据；动态更新规则时，应让各 Worker 分别重建缓存。

## 在 Base 控制器中拦截

新建 `App/HttpController/Admin/Base.php`：

```php
<?php

namespace App\HttpController\Admin;

use App\Permission\AccessPolicyManager;
use EasySwoole\Http\AbstractInterface\Controller;
use EasySwoole\Policy\PolicyNode;

abstract class Base extends Controller
{
    /** 登录接口不执行登录与权限检查。 */
    protected array $ignoreAction = ['login'];

    /** 子控制器用 Action 名声明其权限路径。 */
    protected array $actionPolicy = [];

    protected function onRequest(?string $action): ?bool
    {
        if ($action !== null && in_array($action, $this->ignoreAction, true)) {
            return true;
        }

        // 此处仅演示取值位置，实际项目应先校验 Session 或 Token。
        $session = $this->request()->getAttribute('session');
        $role = $session?->get('role');
        if (!is_string($role) || $role === '') {
            $this->writeJson(401, null, '请先登录');
            return false;
        }

        $permission = $action === null ? null : ($this->actionPolicy[$action] ?? null);
        if ($permission === null) {
            $this->writeJson(403, null, '当前操作未配置权限');
            return false;
        }

        $effect = AccessPolicyManager::getInstance()->forRole($role)->check($permission);
        if ($effect !== PolicyNode::EFFECT_ALLOW) {
            // deny 与 unknown 都拒绝，避免漏配规则时意外放行。
            $this->writeJson(403, null, '没有操作权限');
            return false;
        }

        return true;
    }
}
```

`onRequest()` 返回 `false` 后，目标 Action 不再执行。示例把 `unknown` 也视为拒绝，这是一种适合后台系统的默认拒绝策略。

项目若没有把 Session 对象写入 Request Attribute，应替换示例中的取值方式，使用项目实际的 Token、Session 或登录上下文。AccessPolicy 本身不负责认证。

## 在业务控制器声明权限

新建 `App/HttpController/Admin/User.php`：

```php
<?php

namespace App\HttpController\Admin;

class User extends Base
{
    protected array $actionPolicy = [
        'index' => '/admin/user/read',
        'create' => '/admin/user/create',
        'delete' => '/admin/user/delete',
    ];

    public function index(): void
    {
        $this->writeJson(200, [['id' => 1, 'name' => 'admin']]);
    }

    public function create(): void
    {
        $this->writeJson(200, null, '创建成功');
    }

    public function delete(): void
    {
        $this->writeJson(200, null, '删除成功');
    }
}
```

一次请求的执行过程如下：

```text
请求进入 Admin/User/delete
            ↓
Base::onRequest('delete')
            ↓
验证登录并取得角色
            ↓
映射为 /admin/user/delete
            ↓
Policy::check()
  ├── allow：返回 true，执行 delete()
  └── deny/unknown：响应 403，返回 false
```

## 登录接口与公开 Action

如果登录方法也在后台 Base 控制器下，可以像示例一样将 `login` 放入 `$ignoreAction`。忽略列表必须尽量短，只放真正公开且内部已经完成参数校验、限流等保护的 Action。

更大型的项目可以为公开控制器建立单独的基类，避免新增 Action 时误继承忽略规则。

## 一个用户有多个角色

组件不会自动合并多个 `Policy`。应用必须明确冲突策略。例如“任一角色拒绝即拒绝，否则任一角色允许即允许”：

```php
function checkRoles(array $roles, string $path): string
{
    $hasAllow = false;

    foreach ($roles as $role) {
        $effect = AccessPolicyManager::getInstance()->forRole($role)->check($path);
        if ($effect === PolicyNode::EFFECT_DENY) {
            return PolicyNode::EFFECT_DENY;
        }
        if ($effect === PolicyNode::EFFECT_ALLOW) {
            $hasAllow = true;
        }
    }

    return $hasAllow
        ? PolicyNode::EFFECT_ALLOW
        : PolicyNode::EFFECT_UNKNOWN;
}
```

这是应用层的“拒绝优先”规则，不是组件内置行为。如果业务采用“允许优先”，应在项目规范中明确说明，并为角色冲突编写测试。

## 上线检查

- 权限路径使用固定映射，不直接信任请求参数拼接权限名。
- `allow`、`deny`、`unknown` 三种结果都有测试用例。
- 未配置 Action 默认拒绝，而不是默认放行。
- 登录鉴权在权限判断之前完成。
- 多 Worker 更新策略时使用版本通知和整体替换。
- 权限拒绝记录用户、角色、权限路径和请求标识，但不要记录 Token 等敏感信息。

## 源码依据

- [Policy README](https://github.com/easy-swoole/policy/blob/master/README.md)
- [Policy 源码](https://github.com/easy-swoole/policy/blob/master/src/Policy.php)
- [PolicyNode 源码](https://github.com/easy-swoole/policy/blob/master/src/PolicyNode.php)
