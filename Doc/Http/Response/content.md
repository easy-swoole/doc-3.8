# 文本、HTML 与 JSON

控制器通过 `$this->response()` 获得当前 Response。业务代码只负责设置状态、Header 和 Body，框架会在请求结束时统一发送，不必直接调用 Swoole 的 `end()`。

## 完整示例

新建 `App/HttpController/ResponseDemo.php`：

```php
<?php
namespace App\HttpController;

use EasySwoole\Http\AbstractInterface\Controller;

class ResponseDemo extends Controller
{
    public function text(): void
    {
        $this->response()->withHeader('Content-Type', 'text/plain; charset=utf-8');
        $this->response()->write('Hello EasySwoole');
    }

    public function html(): void
    {
        $name = htmlspecialchars(
            (string) ($this->request()->getQueryParam('name') ?? '访客'),
            ENT_QUOTES | ENT_SUBSTITUTE,
            'UTF-8'
        );
        $this->response()->withHeader('Content-Type', 'text/html; charset=utf-8');
        $this->response()->write("<h1>Hello {$name}</h1>");
    }

    public function jsonData(): void
    {
        $this->writeJson(200, [
            'id' => 1,
            'name' => 'Alice',
        ], 'success');
    }
}
```

然后打开已有的 `App/HttpController/Router.php`，将下面三行加入 `initialize(RouteCollector $routeCollector)` 内，保留已有路由：

```php
$routeCollector->get('/response/text', '/ResponseDemo/text');
$routeCollector->get('/response/html', '/ResponseDemo/html');
$routeCollector->get('/response/json', '/ResponseDemo/jsonData');
```

```bash
php easyswoole.php server reload
curl -i http://127.0.0.1:9501/response/text
curl -i 'http://127.0.0.1:9501/response/html?name=Alice'
curl -i http://127.0.0.1:9501/response/json
```

三次请求应分别得到纯文本 `Hello EasySwoole`、HTML `<h1>Hello Alice</h1>`，以及包含 `"result":{"id":1,"name":"Alice"}` 的 JSON。`-i` 会同时显示 HTTP 状态行和 Content-Type；如果服务尚未启动，先按[启动 HTTP 服务](/Http/Basics/start.md)启动。

`write()` 可以多次调用，非分块模式下内容会追加到 Body。`writeJson()` 会设置 JSON Content-Type、HTTP 状态码，并生成 `code/result/msg` 结构。若项目需要另一种统一格式，可在公共 Base Controller 中封装自己的响应方法。

输出 HTML 时必须按上下文转义动态值；不要直接把 Query、异常消息或数据库内容拼进 HTML。JSON 编码失败、循环引用或无效 UTF-8 也应在统一响应层处理。
