# Query、Form 与 JSON 参数

控制器通过 `$this->request()` 获得当前请求。参数来源不同，读取方法也不同。

| 类型 | 客户端形式 | 读取方法 |
| --- | --- | --- |
| Query | `/products?page=2` | `getQueryParams()`、`getQueryParam()` |
| Form | `name=Alice` | `getParsedBody()` |
| JSON | `{"name":"Alice"}` | Controller 的 `json()` 或 `getBody()` |

## 完整示例

新建 `App/HttpController/RequestDemo.php`：

```php
<?php
namespace App\HttpController;

use EasySwoole\Http\AbstractInterface\Controller;

class RequestDemo extends Controller
{
    public function query(): void
    {
        $page = filter_var(
            $this->request()->getQueryParam('page') ?? 1,
            FILTER_VALIDATE_INT
        );
        if ($page === false || $page < 1) {
            $this->writeJson(422, null, 'page 必须是正整数');
            return;
        }
        $this->writeJson(200, ['page' => $page]);
    }

    public function form(): void
    {
        $name = trim((string) $this->request()->getParsedBody('name'));
        if ($name === '') {
            $this->writeJson(422, null, 'name 不能为空');
            return;
        }
        $this->writeJson(200, ['name' => $name]);
    }

    public function jsonBody(): void
    {
        $data = $this->json();
        $name = trim((string) ($data['name'] ?? ''));
        $age = filter_var($data['age'] ?? null, FILTER_VALIDATE_INT);
        if ($name === '' || $age === false || $age < 1) {
            $this->writeJson(422, null, 'name 或 age 不合法');
            return;
        }
        $this->writeJson(200, compact('name', 'age'));
    }
}
```

在 `App/HttpController/Router.php` 注册：

```php
$routeCollector->get('/request/query', '/RequestDemo/query');
$routeCollector->post('/request/form', '/RequestDemo/form');
$routeCollector->post('/request/json', '/RequestDemo/jsonBody');
```

测试三种来源：

```bash
curl 'http://127.0.0.1:9501/request/query?page=2'
curl -X POST http://127.0.0.1:9501/request/form -d 'name=Alice'
curl -X POST http://127.0.0.1:9501/request/json \
  -H 'Content-Type: application/json' \
  -d '{"name":"Alice","age":20}'
```

## JSON 语法错误

`$this->json()` 在无效 JSON 时返回空数组。需要明确返回 400 时，严格解析原始 Body：

```php
try {
    $data = json_decode((string) $this->request()->getBody(), true, 512, JSON_THROW_ON_ERROR);
} catch (\JsonException $exception) {
    $this->writeJson(400, null, 'JSON 格式错误');
    return;
}
```

## `getRequestParam()` 的合并规则

```php
$name = $this->request()->getRequestParam('name');
```

它合并 Form Parsed Body 和 Query，同名时 Form 优先，不会解析 JSON。公共 API 建议使用明确的读取方法，让参数来源一目了然。

未传、空字符串、字符串 `'0'`、整数 `0` 和 JSON `null` 含义不同，不要一律用 `empty()`。常见错误还包括用 `getParsedBody()` 读取 JSON、只做 `(int)` 强转而不验证，以及把密码或 Token 放进 Query。
