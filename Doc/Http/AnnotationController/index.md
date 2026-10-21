# 注解控制器：安装与继承

普通控制器从 URL 找到 Action 后，由方法自己读取请求参数；`AnnotationController` 在此基础上读取 PHP 8 Attribute，按声明的来源提取参数、转换类型、执行校验，并可扫描生成接口文档。先读完[普通控制器](/Http/Controller/index.md)，再学习本章会更容易理解它增加了什么。

## 环境与组件

在**应用项目根目录**执行：

```bash
php -v
php --ri swoole
php --ri json
php --ri mbstring
php --ri dom
php --ri simplexml
php --ri libxml
composer show easyswoole/http-annotation
```

组件需要 PHP 8.1 及以上、JSON、mbstring、DOM、SimpleXML、libxml；如果当前项目没有安装，在项目根目录运行：

```bash
composer require 'easyswoole/http-annotation:^4.0'
```

EasySwoole 3.8 项目通常已通过框架依赖安装该组件，先用 `composer show` 确认，已有就不必重复安装。检查其他扩展时同样使用 `php --ri 扩展名`。

## 创建第一个注解控制器

新建 `App/HttpController/HelloAnnotation.php`：

```php
<?php

namespace App\HttpController;

use EasySwoole\HttpAnnotation\AnnotationController;
use EasySwoole\HttpAnnotation\Attributes\Api;
use EasySwoole\HttpAnnotation\Attributes\ApiGroup;
use EasySwoole\HttpAnnotation\Enum\HttpMethod;

#[ApiGroup(groupName: 'Hello', description: '第一个注解接口')]
class HelloAnnotation extends AnnotationController
{
    #[Api(allowMethod: HttpMethod::GET, description: '返回问候语')]
    public function index(): void
    {
        $this->writeJson(200, ['message' => 'Hello Annotation']);
    }
}
```

文件路径、`namespace App\HttpController` 和类名要一致。服务尚未启动时执行 `php easyswoole.php server start`；已启动则执行 `php easyswoole.php server reload`。然后测试：

```bash
curl -i http://127.0.0.1:9501/helloAnnotation
```

默认控制器映射会进入 `HelloAnnotation::index()`。这里的 `#[ApiGroup]` 为文档定义分组，`#[Api]` 声明该接口只接受 GET。注解**不会自动创建 URL 路由**；显式路由仍需在 `App/HttpController/Router.php` 定义。现有 `Controller` 子类不能同时 `extends Controller, AnnotationController`；要启用 Attribute 处理，只需把基类改为 `AnnotationController`，它本身继承普通 `Controller`。

后续按[Attribute 清单与定义参数](/Http/AnnotationController/attributes.md) → [控制器组与接口定义](/Http/AnnotationController/api.md) → [接口参数与传参](/Http/AnnotationController/params.md) → [onRequest 公共参数与继承](/Http/AnnotationController/common-params.md) → [参数验证](/Http/AnnotationController/validation.md) → [嵌套与多级验证](/Http/AnnotationController/nested-validation.md) → [响应参数与示例](/Http/AnnotationController/response-params.md) → [生成接口文档](/Http/AnnotationController/document.md)阅读。

## 源码依据

- [HTTP Annotation 4.x README](https://github.com/easy-swoole/http-annotation/blob/4.x/README.md)
- [AnnotationController](https://github.com/easy-swoole/http-annotation/blob/4.x/src/AnnotationController.php)
