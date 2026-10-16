# AccessPolicy：安装与基本概念

`easyswoole/policy` 是一个轻量的路径策略组件。它把权限资源组织成树，再判断指定路径的结果是允许、拒绝还是未知。它适合表达后台菜单、控制器 Action、API 资源等分层权限。

## 环境要求与安装

组件要求 PHP 8.1 或更高版本。在项目根目录执行：

```bash
composer require easyswoole/policy
```

安装后无需注册服务提供者，Composer 会自动加载组件类：

```php
use EasySwoole\Policy\Policy;
use EasySwoole\Policy\PolicyNode;
```

## 三种判断结果

`check()` 返回字符串，而不是布尔值：

| 常量 | 字符串 | 含义 |
| --- | --- | --- |
| `PolicyNode::EFFECT_ALLOW` | `allow` | 明确允许 |
| `PolicyNode::EFFECT_DENY` | `deny` | 明确拒绝 |
| `PolicyNode::EFFECT_UNKNOWN` | `unknown` | 没有匹配到有效策略 |

`unknown` 不等于允许。后台权限、管理接口等安全场景应采用默认拒绝：只有结果严格等于 `EFFECT_ALLOW` 才继续执行。

## 最小示例

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use EasySwoole\Policy\Policy;
use EasySwoole\Policy\PolicyNode;

$policy = new Policy();
$policy->addPath('/article/read', PolicyNode::EFFECT_ALLOW);
$policy->addPath('/article/delete', PolicyNode::EFFECT_DENY);

var_dump($policy->check('/article/read'));   // allow
var_dump($policy->check('/article/delete')); // deny
var_dump($policy->check('/article/create')); // unknown
```

路径开头和结尾的 `/` 会被忽略，因此 `article/read`、`/article/read` 与 `/article/read/` 表示同一条路径。路径大小写敏感，建议项目统一使用小写名称。

## 组件负责什么

AccessPolicy 只负责“路径规则的建立与匹配”，不负责以下工作：

- 用户登录、Token 校验和 Session 管理；
- 用户、角色和权限数据表；
- 从数据库自动加载或同步规则；
- 自动接管控制器或路由。

应用需要先完成身份认证，取得用户或角色，再选择对应的 `Policy` 对象进行判断。完整接入示例见[框架鉴权接入](/Library/AccessPolicy/integration.md)。

下一章：[路径规则与通配符](/Library/AccessPolicy/rules.md)。

## 源码依据

- [Policy 仓库](https://github.com/easy-swoole/policy)
- [Policy 源码](https://github.com/easy-swoole/policy/blob/master/src/Policy.php)
- [PolicyNode 源码](https://github.com/easy-swoole/policy/blob/master/src/PolicyNode.php)
