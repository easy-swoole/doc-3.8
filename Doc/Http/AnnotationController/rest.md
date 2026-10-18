# 实战：用户 REST API

本章用 Router、AnnotationController、JSON 参数和统一异常处理实现一组用户接口。示例使用内存数组演示流程，实际项目应替换为 Repository 和数据库连接池。

## API 设计

| 方法 | 路径 | 功能 |
| --- | --- | --- |
| GET | `/api/users/{id}` | 查询用户 |
| POST | `/api/users` | 创建用户 |
| PUT | `/api/users/{id}` | 更新用户 |
| DELETE | `/api/users/{id}` | 删除用户 |

## Router

`App/HttpController/Router.php`：

```php
<?php

namespace App\HttpController;

use EasySwoole\Http\AbstractInterface\AbstractRouter;
use FastRoute\RouteCollector;

class Router extends AbstractRouter
{
    public function initialize(RouteCollector $routeCollector): void
    {
        $this->parseParams(self::PARSE_PARAMS_IN_GET);

        $routeCollector->get('/api/users/{id:\\d+}', '/UserApi/detail');
        $routeCollector->post('/api/users', '/UserApi/create');
        $routeCollector->put('/api/users/{id:\\d+}', '/UserApi/update');
        $routeCollector->delete('/api/users/{id:\\d+}', '/UserApi/delete');
    }
}
```

## UserApi 控制器

`App/HttpController/UserApi.php`：

```php
<?php

namespace App\HttpController;

use EasySwoole\EasySwoole\Trigger;
use EasySwoole\HttpAnnotation\AnnotationController;
use EasySwoole\HttpAnnotation\Attributes\Api;
use EasySwoole\HttpAnnotation\Attributes\ApiGroup;
use EasySwoole\HttpAnnotation\Attributes\Param;
use EasySwoole\HttpAnnotation\Enum\ContentType;
use EasySwoole\HttpAnnotation\Enum\HttpMethod;
use EasySwoole\HttpAnnotation\Enum\ParamFrom;
use EasySwoole\HttpAnnotation\Enum\ParamType;
use EasySwoole\HttpAnnotation\Exception\ParamValidateFail;
use EasySwoole\HttpAnnotation\Validator\IsEmail;
use EasySwoole\HttpAnnotation\Validator\Min;
use EasySwoole\HttpAnnotation\Validator\NotEmpty;
use EasySwoole\HttpAnnotation\Validator\Required;

#[ApiGroup(groupName: 'UserApi')]
class UserApi extends AnnotationController
{
    private const USERS = [
        1 => ['id' => 1, 'name' => 'Alice', 'email' => 'alice@example.com'],
    ];

    #[Api(
        allowMethod: HttpMethod::GET,
        requestParam: [
            new Param(
                name: 'id',
                from: ParamFrom::GET,
                type: ParamType::INT,
                validate: [new Required(), new Min(1)]
            ),
        ]
    )]
    public function detail(int $id): void
    {
        $user = self::USERS[$id] ?? null;
        if ($user === null) {
            $this->writeJson(404, null, '用户不存在');
            return;
        }

        $this->writeJson(200, $user);
    }

    #[Api(
        allowMethod: HttpMethod::POST,
        acceptContentType: ContentType::JSON,
        requestParam: [
            new Param(
                name: 'name',
                from: ParamFrom::JSON,
                validate: [new Required(), new NotEmpty()]
            ),
            new Param(
                name: 'email',
                from: ParamFrom::JSON,
                validate: [new Required(), new IsEmail()]
            ),
        ]
    )]
    public function create(string $name, string $email): void
    {
        // 实际项目：调用 Service/Repository 持久化。
        $this->writeJson(201, [
            'id' => 2,
            'name' => $name,
            'email' => $email,
        ]);
    }

    #[Api(
        allowMethod: HttpMethod::PUT,
        acceptContentType: ContentType::JSON,
        requestParam: [
            new Param(name: 'id', from: ParamFrom::GET, type: ParamType::INT),
            new Param(name: 'name', from: ParamFrom::JSON, validate: [new NotEmpty()]),
            new Param(name: 'email', from: ParamFrom::JSON, validate: [new IsEmail()]),
        ]
    )]
    public function update(int $id, string $name, string $email): void
    {
        $this->writeJson(200, compact('id', 'name', 'email'));
    }

    #[Api(
        allowMethod: HttpMethod::DELETE,
        requestParam: [
            new Param(name: 'id', from: ParamFrom::GET, type: ParamType::INT),
        ]
    )]
    public function delete(int $id): void
    {
        // 实际项目：删除资源后返回 204，且不写 Body。
        $this->response()->withStatus(204);
    }

    protected function onException(\Throwable $throwable): void
    {
        if ($throwable instanceof ParamValidateFail) {
            $message = $throwable->getFailRule()
                ->errorMsg($throwable->getParamName());
            $this->writeJson(422, null, $message);
            return;
        }

        Trigger::getInstance()->throwable($throwable);
        $this->writeJson(500, null, '服务器内部错误');
    }
}
```

## 请求测试

```bash
curl http://127.0.0.1:9501/api/users/1

curl -X POST http://127.0.0.1:9501/api/users \
  -H 'Content-Type: application/json' \
  -d '{"name":"Bob","email":"bob@example.com"}'

curl -X PUT http://127.0.0.1:9501/api/users/1 \
  -H 'Content-Type: application/json' \
  -d '{"name":"Alice Chen","email":"alice@example.com"}'

curl -i -X DELETE http://127.0.0.1:9501/api/users/1
```

## 生产项目如何拆分

控制器只负责 HTTP 协议层：读取参数、调用 Service、转换响应。业务规则放进 Service，数据访问放进 Repository。不要把数据库 SQL、事务和复杂业务全部堆在 Action 中。

```text
Controller → Service → Repository → Database/Cache
```

这样可以独立测试业务逻辑，也能让 CLI、Task Worker 或 RPC 复用同一 Service。
