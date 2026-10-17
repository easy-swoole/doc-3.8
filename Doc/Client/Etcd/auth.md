# Etcd 客户端：认证与权限

etcd 开启认证后，应用先用用户名、密码换取 Token，再用携带 Token 的客户端访问受保护的 KV。下面的管理操作需要有相应管理权限，不应在每次业务请求中重复执行。

## 登录并获取认证客户端

```php
$token = $client->authenticate('app-user', '从安全配置读取的密码');
$authenticated = $client->withToken($token);

$result = $authenticated->range('config/app');
```

`withToken()` 返回新的 `Client` 对象，原来的 `$client` 保持不变。Token 会放入请求头 `Grpc-Metadata-Token`。不同身份需要各自的客户端对象；Token 不要写入源码或输出到日志。要回到匿名客户端，可调用 `$authenticated->withToken(null)`。

## 创建角色与用户

例如创建只读 `config/` 前缀的角色：

```php
use EasySwoole\EtcdClient\Permission;

$admin = $client->withToken($adminToken);

$admin->addRole('config-reader');
$admin->grantRolePermission(
    role: 'config-reader',
    permission: Permission::Read,
    key: 'config/',
    rangeEnd: 'config0',
);

$admin->addUser('app-reader', '从安全配置读取的初始密码');
$admin->grantUserRole('app-reader', 'config-reader');
```

`config/` 到 `config0` 是用于覆盖 `config/` 前缀的半开范围示例，业务前缀改变时应重新计算或核对范围边界。`Permission` 枚举提供 `Read`、`Write`、`ReadWrite` 三种权限。

查询和维护角色、用户还有这些方法：

```php
$role = $admin->role('config-reader');
$roles = $admin->roles();
$user = $admin->user('app-reader');
$users = $admin->users();

$admin->changePassword('app-reader', '新的安全密码');
$admin->revokeUserRole('app-reader', 'config-reader');
$admin->revokeRolePermission('config-reader', 'config/', 'config0');

// 确认不再被业务使用后再删除。
$admin->deleteUser('app-reader');
$admin->deleteRole('config-reader');
```

## 启用认证

客户端提供 `$client->enableAuthentication()` 和 `$authenticated->disableAuthentication()`。启用前应先按 etcd 的要求准备 root 用户和 root 角色，并验证管理 Token 可用；否则可能把管理操作一起锁在服务之外。此类操作属于集群初始化或维护流程，不建议放进普通 HTTP 控制器。

下一章：[响应、异常与 TLS](/Client/Etcd/response.md)。

## 源码依据

- [Client 认证与权限方法](https://github.com/easy-swoole/etcd-client/blob/2.x/src/Client.php)
- [Permission 枚举](https://github.com/easy-swoole/etcd-client/blob/2.x/src/Permission.php)
