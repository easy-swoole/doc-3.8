# 控制器组与接口定义

`#[ApiGroup]` 标记一个控制器所属的文档分组；`#[Api]` 标记公开 Action 的接口方法、说明和参数定义。前者作用于**类**，后者作用于**方法**。分组用于整理生成的文档，不是路由前缀，也不会自动注册路由。

## 按目录组织控制器

在应用项目根目录创建 `App/HttpController/Catalog/Product.php`：

```php
<?php

namespace App\HttpController\Catalog;

use EasySwoole\HttpAnnotation\AnnotationController;
use EasySwoole\HttpAnnotation\Attributes\Api;
use EasySwoole\HttpAnnotation\Attributes\ApiGroup;
use EasySwoole\HttpAnnotation\Enum\HttpMethod;

#[ApiGroup(groupName: 'Catalog.Product', description: '商品接口')]
class Product extends AnnotationController
{
    #[Api(allowMethod: HttpMethod::GET, description: '获取商品列表')]
    public function index(): void
    {
        $this->writeJson(200, [
            ['id' => 1, 'name' => '商品 A'],
        ]);
    }

    #[Api(allowMethod: HttpMethod::POST, description: '创建商品')]
    public function create(): void
    {
        $this->writeJson(201, ['id' => 2]);
    }
}
```

默认映射下可以访问：

```bash
curl -i http://127.0.0.1:9501/catalog/product
curl -i -X POST http://127.0.0.1:9501/catalog/product/create
```

`Catalog.Product` 会在生成文档时形成 Catalog → Product 的层级。每个被扫描的控制器应使用**唯一**的完整 `groupName`；例如另一个控制器可用 `Catalog.Category`。不需要一个单独的“分组类”，也无需让 `Product` 继承另一个分组控制器。

## `Api` 能声明什么

`allowMethod` 是单个 `HttpMethod` 枚举，不是方法数组；未写时默认 GET。常用值有 `GET`、`POST`、`PUT`、`DELETE`。请求参数用 `requestParam: [new Param(...)]` 声明，下一章会详细介绍。`description` 为接口说明；`deprecated: true` 只在文档中标记废弃，不会阻止调用。

```php
#[Api(
    allowMethod: HttpMethod::POST,
    description: '创建商品',
    deprecated: false
)]
public function create(): void
{
    // 业务代码
}
```

属性中的 `allowMethod` 会由注解控制器检查实际请求方法，但**不等同于路由注册**。`Api` 目前没有 `requestPath` 构造参数，`registerRouter` 也不能代替在 Router 中手动定义路由。如果需要 `/api/products` 这样的自定义 URL，应在现有 `App/HttpController/Router.php` 的 `initialize()` 中加入映射，详见[路由基础](/Http/Routing/index.md)。生成文档的扫描路径基于控制器/Action 命名，使用自定义路由时需核对两者是否一致。

只有带 `#[Api]` 的公开方法会进入自动生成的接口文档；但**未加注解的公开方法仍可能被普通 URL 映射访问**。内部辅助方法应声明为 `private` 或 `protected`，不能把 `#[Api]` 当作访问控制。

`ApiGroup::description`、`Api::description` 等完整参数类型与默认值见[Attribute 清单与定义参数](/Http/AnnotationController/attributes.md)。下一章：[接口参数与传参](/Http/AnnotationController/params.md)。

## 源码依据

- [ApiGroup.php](https://github.com/easy-swoole/http-annotation/blob/4.x/src/Attributes/ApiGroup.php)
- [Api.php](https://github.com/easy-swoole/http-annotation/blob/4.x/src/Attributes/Api.php)
- [Document.php](https://github.com/easy-swoole/http-annotation/blob/4.x/src/Document/Document.php)
