# 鉴权与拦截

鉴权与拦截并不意味着所有网站请求都必须经过同一段代码。更常见、也更容易维护的做法是：**为一个业务模块定义公共 Base 控制器，让该模块下的所有控制器继承它**。

例如后台管理接口都必须登录，可以建立 `Admin\\Base`，在它的 `onRequest()` 中统一鉴权。鉴权失败时先写入 401 响应，再 `return false`，框架就不会继续执行目标 Action。

本章最终实现三个接口。其中登录接口也继承管理员 Base，但通过 `ignoreAction` 明确跳过鉴权：

```text
GET /admin/users       管理员用户列表，需要登录
GET /admin/dashboard   管理后台首页，需要登录
POST /admin/login      管理员登录，不需要登录
```

## 最终目录结构

需要新建四个控制器文件，并修改路由文件：

```text
项目根目录/
└── App/
    └── HttpController/
        ├── Router.php
        └── Admin/
            ├── Base.php          ← 管理员公共控制器
            ├── Auth.php          ← login 免鉴权
            ├── User.php          ← 继承 Base
            └── Dashboard.php     ← 继承 Base
```

## 第一步：定义管理员 Base 控制器

新建 `App/HttpController/Admin/Base.php`：

```php
<?php

namespace App\HttpController\Admin;

use EasySwoole\Http\AbstractInterface\Controller;

abstract class Base extends Controller
{
    /**
     * 当前控制器中不需要登录的 Action。
     * 默认没有免鉴权 Action，由具体子控制器按需声明。
     *
     * @var list<string>
     */
    protected array $ignoreAction = [];

    /**
     * 当前请求对应的管理员 ID。
     * Controller 对象按请求创建，因此这里可以保存本次请求的数据。
     */
    protected ?int $adminId = null;

    /**
     * final 可以防止子控制器覆盖 onRequest() 后绕过鉴权。
     */
    final protected function onRequest(?string $action): ?bool
    {
        // 登录、验证码等公开 Action 可以在子控制器中加入白名单。
        if ($action !== null && in_array($action, $this->ignoreAction, true)) {
            return true;
        }

        $authorization = $this->request()->getHeaderLine('Authorization');

        // 入门示例使用固定 Token，生产项目应改为 AuthService 校验。
        if (!hash_equals('Bearer demo-admin-token', $authorization)) {
            $this->writeJson(401, null, '管理员未登录或登录已过期');

            // 返回 false 后，User::index()、Dashboard::index() 等 Action
            // 都不会再执行。
            return false;
        }

        // 实际项目中，adminId 应来自 Session、JWT 或 Token 存储。
        $this->adminId = 1001;

        return true;
    }
}
```

这里有四个关键点：

1. `Base` 定义为 `abstract`，它只用于继承，本身不是可访问的业务控制器。
2. `onRequest()` 会在目标 Action 之前执行，适合做登录、权限、限流等公共检查。
3. 失败时既要写出响应，也要 `return false`。只写 401 但仍返回 `true`，目标 Action 还会继续执行并可能追加响应内容。
4. `ignoreAction` 使用严格匹配；只有子控制器明确列出的 Action 才能绕过登录检查。

## 第二步：让管理员控制器继承 Base

新建 `App/HttpController/Admin/User.php`：

```php
<?php

namespace App\HttpController\Admin;

class User extends Base
{
    public function index(): void
    {
        $this->writeJson(200, [
            'operatorId' => $this->adminId,
            'users' => [
                ['id' => 1, 'name' => 'Alice'],
                ['id' => 2, 'name' => 'Bob'],
            ],
        ]);
    }
}
```

新建 `App/HttpController/Admin/Dashboard.php`：

```php
<?php

namespace App\HttpController\Admin;

class Dashboard extends Base
{
    public function index(): void
    {
        $this->writeJson(200, [
            'operatorId' => $this->adminId,
            'onlineUsers' => 128,
        ]);
    }
}
```

两个控制器都没有重复编写 Token 校验，但请求它们时都会先进入 `Base::onRequest()`。

## 第三步：为登录 Action 设置免鉴权

登录接口本身用于获取 Token，如果它也要求先携带 Token，就会形成无法登录的死循环。

新建 `App/HttpController/Admin/Auth.php`：

```php
<?php

namespace App\HttpController\Admin;

class Auth extends Base
{
    /**
     * 这里只放当前 Auth 控制器中允许匿名访问的方法名。
     * 方法名必须与路由 Handler 中的 Action 完全一致。
     *
     * @var list<string>
     */
    protected array $ignoreAction = ['login'];

    public function login(): void
    {
        $username = (string) $this->request()->getRequestParam('username');
        $password = (string) $this->request()->getRequestParam('password');

        // 仅用于演示流程。生产项目应查询管理员账号，
        // 并使用 password_verify() 检查密码哈希。
        if ($username !== 'admin' || $password !== 'demo-password') {
            $this->writeJson(422, null, '账号或密码错误');
            return;
        }

        $this->writeJson(200, [
            'token' => 'demo-admin-token',
        ], '登录成功');
    }

    /**
     * logout 没有加入 ignoreAction，所以仍然要求登录。
     */
    public function logout(): void
    {
        // 实际项目应在服务端使 Session 或 Token 失效。
        $this->writeJson(200, null, '退出成功');
    }
}
```

当请求 `/admin/login` 时，框架传入的 `$action` 是 `login`：

```text
Auth::$ignoreAction 中包含 login
            ↓
Base::onRequest('login') 返回 true
            ↓
执行 Auth::login()
```

当请求 `logout` 时，`logout` 不在白名单中，因此仍会继续执行 Token 校验。

## 第四步：注册路由

编辑 `App/HttpController/Router.php`，在 `initialize()` 中注册管理员路由：

```php
<?php

namespace App\HttpController;

use EasySwoole\Http\AbstractInterface\AbstractRouter;
use FastRoute\RouteCollector;

class Router extends AbstractRouter
{
    public function initialize(RouteCollector $routeCollector): void
    {
        $routeCollector->addGroup('/admin', function (RouteCollector $route): void {
            $route->post('/login', '/Admin/Auth/login');
            $route->post('/logout', '/Admin/Auth/logout');
            $route->get('/users', '/Admin/User/index');
            $route->get('/dashboard', '/Admin/Dashboard/index');
        });
    }
}
```

路由和控制器的对应关系：

```text
GET /admin/users
    ↓ Router.php
/Admin/User/index
    ↓ 创建 App\HttpController\Admin\User
Base::onRequest()
    ├── false → 不执行 Action，直接返回鉴权失败响应
    └── true  → 执行 User::index()
```

## 第五步：验证登录与拦截效果

修改代码后 reload：

```bash
php easyswoole.php server reload
```

登录接口没有 Token 也可以访问：

```bash
curl -i -X POST http://127.0.0.1:9501/admin/login \
  -d 'username=admin&password=demo-password'
```

预期返回：

```json
{
  "code": 200,
  "result": {"token": "demo-admin-token"},
  "msg": "登录成功"
}
```

如果访问没有加入 `ignoreAction` 的退出接口，仍然会被拦截：

```bash
curl -i -X POST http://127.0.0.1:9501/admin/logout
```

预期状态码为 401。

不携带 Token：

```bash
curl -i http://127.0.0.1:9501/admin/users
```

预期状态码为 401，Action 中的用户列表不会返回：

```json
{
  "code": 401,
  "result": null,
  "msg": "管理员未登录或登录已过期"
}
```

携带正确 Token：

```bash
curl -i http://127.0.0.1:9501/admin/users \
  -H 'Authorization: Bearer demo-admin-token'
```

预期状态码为 200，并返回用户列表。另一个继承 Base 的接口也会自动受到保护：

```bash
curl -i http://127.0.0.1:9501/admin/dashboard \
  -H 'Authorization: Bearer demo-admin-token'
```

## `return false` 后还会执行什么

Controller 的实际执行顺序是：

```text
onRequest()
    ├── 返回 false：跳过 Action
    └── 返回其他值：继续执行 Action
            ↓
afterAction() 始终会在 finally 中执行
```

因此，`return false` 会阻止业务 Action，但不会阻止 `afterAction()`。如果 Base 中实现了请求日志或耗时统计，它在鉴权失败时仍然会执行：

```php
protected function afterAction(?string $actionName): void
{
    // 无论 onRequest 是否通过，这里都会执行。
    // 可用于记录状态码、Action 名称和请求耗时。
}
```

## 生产项目不要使用固定 Token

固定 Token 只是为了让示例可以独立运行。实际项目应把解析和校验封装到 Service：

```php
final protected function onRequest(?string $action): ?bool
{
    if ($action !== null && in_array($action, $this->ignoreAction, true)) {
        return true;
    }

    $token = $this->request()->getHeaderLine('Authorization');
    $admin = AdminAuthService::getInstance()->authenticate($token);

    if ($admin === null) {
        $this->writeJson(401, null, '请先登录');
        return false;
    }

    if (!$admin->canAccess($action)) {
        $this->writeJson(403, null, '没有操作权限');
        return false;
    }

    $this->adminId = $admin->getId();
    return true;
}
```

- 401 表示没有有效身份。
- 403 表示已经识别身份，但没有当前操作权限。
- 当前管理员信息只能保存为本次请求的数据，不要写入静态属性或全局单例的可变属性，否则常驻 Worker 中可能发生请求串数据。

## `ignoreAction` 应该定义在哪里

建议让 Base 提供空数组，然后由具体控制器声明自己的白名单：

```php
// Admin/Base.php
protected array $ignoreAction = [];

// Admin/Auth.php
protected array $ignoreAction = ['login', 'captcha'];
```

不要直接在 Base 中写一个覆盖所有管理员控制器的巨大列表：

```php
// 不推荐
protected array $ignoreAction = ['login', 'captcha', 'callback', 'index'];
```

因为白名单只保存 Action 名，不包含控制器名。如果 Base 全局放行 `index`，那么所有继承它的 `index()` 都可能绕过鉴权。让白名单跟着具体控制器，可以清楚看出哪个接口被公开。

对于更加严格的项目，也可以用“控制器类名 + Action 名”组成白名单，或创建单独的公开登录控制器。但无论采用哪种方案，都应默认要求鉴权，只显式放行少量入口。

## 哪些控制器不会被拦截

只有继承 `App\\HttpController\\Admin\\Base` 的控制器才会执行这里的鉴权。前台公开控制器可直接继承框架的 `Controller`，不会受到管理员规则影响：

```php
use EasySwoole\Http\AbstractInterface\Controller;

class PublicArticle extends Controller
{
    // 公开接口
}
```

这正是按业务模块建立 Base 控制器的意义：管理员、商户端、开放 API 可以分别拥有自己的公共拦截规则，而不是把全部逻辑堆到一个巨大的全局判断中。

## 常见错误

- 子控制器仍然直接继承 `Controller`，所以不会进入管理员 Base。
- 鉴权失败后忘记 `return false`，Action 继续执行。
- 只 `return false` 却没有写响应，客户端收到空内容。
- 子类覆盖 `onRequest()` 却没有调用父类，导致绕过鉴权；可像示例一样声明为 `final`。
- 把 `login` 错写为路由地址 `/admin/login`；白名单匹配的是 Action 方法名，不是 URL。
- 在 Base 中放行过于常见的 `index`，意外让多个管理员控制器绕过鉴权。
- 把当前管理员保存在 `static` 属性或常驻单例中，造成不同请求之间串用户。
