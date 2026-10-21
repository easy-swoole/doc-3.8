# 模板引擎：在框架中渲染页面

本例使用 `easyswoole/template` 2.x + Plates：浏览器访问 `GET /template-demo`，控制器把名字交给独立渲染进程，最终返回 HTML。

## Plates 从哪里来

Plates 是单独安装的模板引擎，不包含在 `easyswoole/template` 中。在 EasySwoole 项目根目录执行：

```bash
composer require 'easyswoole/template:^2.0'
composer require 'league/plates:^3.6'
```

第一个包提供 `EasySwoole\Template\Render` 和 `RenderInterface`，第二个包提供本例使用的 `League\Plates\Engine`。Composer 会自动加载安装后的类，因此下文的 `App/Template/PlatesRenderer.php` 可以通过 `use League\Plates\Engine;` 引入 Plates。`Resource/views/hello.php` 则是接下来由你自己创建的页面模板，并非安装包自带。

安装完成后，按下面的**文件路径**逐个创建。

```text
项目根目录/
├── EasySwooleEvent.php              ← 服务启动前注册渲染进程
├── App/
│   ├── Template/
│   │   ├── TemplateRender.php        ← 应用自己的进程内单例
│   │   └── PlatesRenderer.php       ← 实现 RenderInterface
│   └── HttpController/
│       ├── Router.php               ← 注册 /template-demo
│       └── TemplateDemo.php         ← 请求、响应
└── Resource/
    └── views/
        └── hello.php                ← Plates 模板
```

## 1. 实现渲染器

新建 `App/Template/PlatesRenderer.php`：

```php
<?php

namespace App\Template;

use EasySwoole\Template\RenderInterface;
use League\Plates\Engine;

final class PlatesRenderer implements RenderInterface
{
    private ?Engine $engine = null;

    public function render(string $template, array $data = [], array $options = []): ?string
    {
        // 渲染进程首次收到任务时才创建引擎；每个进程保留自己的实例。
        $this->engine ??= new Engine(EASYSWOOLE_ROOT . '/Resource/views');
        return $this->engine->render($template, $data);
    }

    public function onException(
        \Throwable $throwable,
        string $template,
        array $data = [],
        array $options = []
    ): void {
        error_log('Template render failed [' . $template . ']: ' . $throwable->getMessage());
    }
}
```

`render()` 返回渲染后的字符串，或按业务约定返回 `null`。`$options` 是组件传入的扩展参数，本例不使用；若自定义模板布局、语言等，可在渲染器里自行解释。`onException()` 在渲染进程中执行，用于记录错误；它的返回类型是 `void`，**不能通过返回字符串把错误页传给客户端**。组件在异常后关闭当前连接，控制器应处理未取得 HTML 的情况。日志不要记录完整 `$data`，其中可能有个人信息或令牌。

## 2. 定义模板文件

新建 `Resource/views/hello.php`：

```php
<!doctype html>
<html lang="zh-CN">
<head><meta charset="utf-8"><title>模板示例</title></head>
<body>
    <h1>你好，<?= $this->e($name) ?></h1>
</body>
</html>
```

Plates 默认寻找 `.php` 文件，因此客户端传 `hello`，实际读取 `Resource/views/hello.php`。`$this->e()` 会对展示值做 HTML 转义；不要把用户输入直接插入 HTML。模板目录应存在并对运行用户可读。
控制器传给 `render()` 的模板名应由服务端代码固定或通过白名单选择，不要直接把 URL 参数当成模板名。

## 3. 定义应用单例

新建 `App/Template/TemplateRender.php`：

```php
<?php

namespace App\Template;

use EasySwoole\Component\Singleton;
use EasySwoole\Template\Render;

class TemplateRender extends Render
{
    use Singleton;
}
```

组件的 `Render` 不是单例；这里按框架习惯在自己的子类中 `use Singleton`，即可使用 `TemplateRender::getInstance()`。不必再写一套静态 `$instance`、`get()` 或 `set()`。

## 4. 在服务启动前挂载渲染进程

编辑项目根目录**现有** `EasySwooleEvent.php`，在已有的 `mainServerCreate()` 中加入下面代码；不要覆盖方法内原有的进程和事件注册：

```php
use App\Template\PlatesRenderer;
use App\Template\TemplateRender;
use EasySwoole\EasySwoole\ServerManager;
use EasySwoole\EasySwoole\Swoole\EventRegister;

public static function mainServerCreate(EventRegister $register): void
{
    $render = TemplateRender::getInstance();
    $config = $render->getConfig();
    $config->setRender(new PlatesRenderer());
    $config->setServerName('MyAppTemplate');
    $config->setTempDir(EASYSWOOLE_TEMP_DIR);
    $config->setWorkerNum(2);
    $config->setTimeout(3);

    $render->attachServer(ServerManager::getInstance()->getSwooleServer());
}
```

这里的代码是**方法片段**，其中 `use` 语句应放在 `EasySwooleEvent.php` 文件顶部、类声明之前；方法体应合并进现有类。`mainServerCreate()` 在 Server 启动前执行，适合注册自定义进程。必须先 `setRender()` 再 `attachServer()`，而且同一实例只能挂载一次。`EASYSWOOLE_TEMP_DIR` 避免写死 Socket 文件目录；目录须存在、可写，且服务器各进程都能访问。

## 5. 控制器取得 HTML 并响应

新建 `App/HttpController/TemplateDemo.php`：

```php
<?php

namespace App\HttpController;

use App\Template\TemplateRender;
use EasySwoole\Http\AbstractInterface\Controller;
use EasySwoole\Template\Exception\ClientException;
use EasySwoole\Template\Exception\ClientTimeoutException;

class TemplateDemo extends Controller
{
    public function index(): void
    {
        try {
            $html = TemplateRender::getInstance()->render('hello', [
                'name' => 'EasySwoole',
            ]);
        } catch (ClientTimeoutException | ClientException $error) {
            error_log($error->getMessage());
            $this->response()->withStatus(503);
            $this->response()->write('模板服务暂不可用');
            return;
        }

        if ($html === null) {
            $this->response()->withStatus(503);
            $this->response()->write('模板渲染没有返回内容');
            return;
        }

        $this->response()->withHeader('Content-Type', 'text/html; charset=utf-8');
        $this->response()->write($html);
    }
}
```

在现有 `App/HttpController/Router.php` 的 `initialize()` 中**增加**路由，不要替换其他路由：

```php
$routeCollector->get('/template-demo', '/TemplateDemo/index');
```

因为增加了渲染进程，首次接入后执行完整的服务启动；已运行的服务应先停止，再启动，**不能只做 Worker reload**。按项目现有模式执行 `php easyswoole.php server stop`、`php easyswoole.php server start`，再测试：

```bash
curl -i http://127.0.0.1:9501/template-demo
```

预期 HTTP 200、`Content-Type: text/html`，正文包含“你好，EasySwoole”。如果返回 503，查看服务日志与渲染进程日志，按[配置、超时与排查](/Library/Template/config.md)定位。

## 修改代码后如何生效

`PlatesRenderer`、`TemplateRender` 和渲染进程是在服务启动前加载的。修改渲染器实现、进程数、Socket 目录、模板引擎配置或 `mainServerCreate()` 后，完整重启服务。模板文件本身由本例中的 Plates 在渲染时读取；普通模板内容变化通常下次请求即可看到，若所选引擎启用了自己的缓存，则按该引擎规则清理缓存。

下一章：[配置、超时与排查](/Library/Template/config.md)。

## 源码依据

- [template 2.x README](https://github.com/easy-swoole/template/blob/2.x/README.md)
- [Render.php](https://github.com/easy-swoole/template/blob/2.x/src/Render.php)
- [RenderWorker.php](https://github.com/easy-swoole/template/blob/2.x/src/RenderWorker.php)
- [Plates 模板渲染](https://platesphp.com/templates/overview/)
