# 生成接口文档

`easyswoole/http-annotation` 4.x 可以扫描带 `#[ApiGroup]` 的注解控制器和带 `#[Api]` 的公开方法，生成完整 HTML。可以用脚本生成静态文件，也可以在控制器里直接响应，例如访问 `/doc`。两种方式都使用 `Document::scan2html()`，区别是生成时机。

## 先准备可扫描的控制器

至少完成[安装与继承](/Http/AnnotationController/index.md)或[控制器组与接口定义](/Http/AnnotationController/api.md)中的示例。扫描时控制器文件必须能被应用的 Composer 自动加载：类名、命名空间、文件路径要一致。组件只把有 `#[ApiGroup]` 的注解控制器放进文档；只有带 `#[Api]` 的公开方法会显示为接口。

## 创建生成脚本

在**应用项目根目录**新建 `build-api-doc.php`：

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use EasySwoole\HttpAnnotation\Document\Document;

$document = new Document(
    __DIR__ . '/App/HttpController',
    'App\\HttpController'
);
$document->getConfig()->setProjectName('我的 API');
$document->getConfig()->setHost('http://127.0.0.1:9501');

$html = $document->scan2html();
$output = __DIR__ . '/Static/api.html';
if (file_put_contents($output, $html) === false) {
    throw new RuntimeException("无法写入 {$output}");
}
echo "已生成 {$output}\n";
```

`Document` 的第一个参数是控制器**实际目录**，第二个参数是该目录对应的**根命名空间**。`scan2html()` 返回 HTML 字符串，不会自动保存文件；脚本把它写入 `Static/api.html`。先确保应用项目中有 `Static` 目录，然后运行：

```bash
mkdir -p Static
php build-api-doc.php
php -S 127.0.0.1:8080 -t Static
```

另开浏览器访问 `http://127.0.0.1:8080/api.html`。这里的 `php -S` 只用来本地预览静态文档；业务 API 仍由 9501 端口的 EasySwoole 服务处理。若项目已经开启 `document_root => EASYSWOOLE_ROOT . '/Static'` 和 `enable_static_handler => true`，也可按项目静态资源规则直接由框架提供该文件。

## 在控制器中直接响应 `/doc`

如果希望打开一个固定地址就看到最新接口文档，可在应用项目根目录新建 `App/HttpController/ApiDoc.php`：

```php
<?php

namespace App\HttpController;

use EasySwoole\Http\AbstractInterface\Controller;
use EasySwoole\HttpAnnotation\Document\Document;

class ApiDoc extends Controller
{
    public function index(): void
    {
        $document = new Document(
            EASYSWOOLE_ROOT . '/App/HttpController',
            'App\\HttpController'
        );
        $document->getConfig()->setProjectName('我的 API');
        $document->getConfig()->setHost('http://127.0.0.1:9501');

        $this->response()->withHeader('Content-Type', 'text/html; charset=utf-8');
        $this->response()->write($document->scan2html());
    }
}
```

这里使用普通 `Controller`，因为文档页面本身不是需要加入接口文档的 API。`EASYSWOOLE_ROOT` 指向项目根目录，避免服务部署后依赖当前工作目录。

然后在现有 `App/HttpController/Router.php` 的 `initialize()` 中**增加**一条路由，保留文件里原有路由和 `setPathInfoMode()` 设置：

```php
$routeCollector->get('/doc', '/ApiDoc/index');
```

重载服务后打开 `http://127.0.0.1:9501/doc`。也可以执行：

```bash
php easyswoole.php server reload
curl -i http://127.0.0.1:9501/doc
```

此方案每次请求 `/doc` 都会扫描控制器并生成 HTML，适合开发环境或接口数量较少的项目。接口较多或访问频繁时，优先使用上面的脚本生成静态文件，或自行加入缓存并在代码变更后刷新。接口文档可能包含内部地址、参数和请求示例；生产环境开放 `/doc` 前应增加鉴权或仅允许内网访问。

## 分组、路径与说明如何出现在文档中

例如 `#[ApiGroup(groupName: 'Catalog.Product')]` 会形成 Catalog → Product 导航；其 `Product::index()` 和 `Product::create()` 只有在方法上写了 `#[Api]` 才会被扫描。分组名不能重复。组件按控制器类和 Action 名构建默认文档路径，不会读取你在 Router 中自定义的所有 URL；若实际项目用 `/api/products` 等别名，需要核对文档展示路径，不能误以为注解会自动注册路由。

`Api` 支持 `description`、`requestParam`、请求/响应示例及 `deprecated` 标记。可在接口上增加响应样例：

```php
use EasySwoole\HttpAnnotation\Bean\Example\Array2Json;

#[Api(
    allowMethod: HttpMethod::GET,
    description: '列出商品',
    responseExamples: [
        new Array2Json(['code' => 200, 'result' => [['id' => 1]]]),
    ]
)]
public function index(): void
{
    $this->writeJson(200, [['id' => 1]]);
}
```

这段是对上一章 `Product::index()` 的替换片段，不是可单独运行的文件。接口文档还提供“立即尝试”，会按声明的请求方法和参数构造浏览器请求。浏览器跨域、Cookie、CORS 仍受普通 Web 安全规则约束；公开生成文件前检查其中的示例数据和说明，不要把密钥或内部地址发布出去。

## 常见问题

- 扫描结果为空：检查控制器是否继承 `AnnotationController`、类上是否有 `#[ApiGroup]`、方法上是否有 `#[Api]`、Composer 自动加载是否正确。
- 分组报重复：不同控制器不能使用同一个完整 `groupName`。
- 修改接口后页面没变化：重新执行 `php build-api-doc.php` 并刷新浏览器；运行服务中的 Attribute 缓存需要重载时再执行 `php easyswoole.php server reload`。
- `/doc` 返回 404：确认 `Router.php` 增加了 `get('/doc', '/ApiDoc/index')`，并已重载服务；若生成时出错，再检查扫描路径和注解控制器是否能正常加载。
- 在线试运行失败：先用 curl 确认接口可用，再检查文档 host、实际路由和浏览器 CORS；生成 HTML 不会自动启动 API 服务。

## 源码依据

- [4.x README：生成接口文档](https://github.com/easy-swoole/http-annotation/blob/4.x/README.md)
- [Document.php](https://github.com/easy-swoole/http-annotation/blob/4.x/src/Document/Document.php)
