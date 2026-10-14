# 静态资源路由

EasySwoole 可以返回文件，但“静态资源路由”需要区分开发环境和生产环境。生产环境优先让 Nginx/CDN 处理；下面先给出一个能运行且防止目录穿越的开发示例。

## 目录结构

在项目根目录建立公开目录：

```text
项目根目录/
├── App/HttpController/
│   ├── Router.php
│   └── StaticFile.php
└── Public/
    ├── css/app.css
    └── images/logo.png
```

只有 `Public` 内文件允许访问。

## 定义路由

在 `App/HttpController/Router.php` 的 `initialize()` 中加入：

```php
$this->setPathInfoMode(false);
$this->parseParams(self::PARSE_PARAMS_IN_GET);
$routeCollector->get('/assets/{path:.+}', '/StaticFile/read');
```

`setPathInfoMode(false)` 会保留 `.css`、`.png` 等扩展名。它是整个 Router 的行为；如果已有其他路由，应确认它们也按完整 URI 匹配。

## 创建文件控制器

新建 `App/HttpController/StaticFile.php`：

```php
<?php

namespace App\HttpController;

use EasySwoole\Http\AbstractInterface\Controller;

class StaticFile extends Controller
{
    public function read(): void
    {
        $publicRoot = realpath(EASYSWOOLE_ROOT . '/Public');
        $relativePath = (string) $this->request()->getRequestParam('path');
        $file = $publicRoot === false
            ? false
            : realpath($publicRoot . '/' . ltrim($relativePath, '/'));

        if (
            $file === false
            || !is_file($file)
            || !str_starts_with($file, $publicRoot . DIRECTORY_SEPARATOR)
        ) {
            $this->response()->withStatus(404);
            $this->response()->write('Not Found');
            return;
        }

        $mime = (new \finfo(FILEINFO_MIME_TYPE))->file($file);
        $this->response()->withHeader(
            'Content-Type',
            is_string($mime) ? $mime : 'application/octet-stream'
        );
        $this->response()->withHeader('Cache-Control', 'public, max-age=3600');
        $this->response()->sendFile($file);
    }
}
```

验证：

```bash
php easyswoole server reload
curl -i http://127.0.0.1:9501/assets/css/app.css
curl -i http://127.0.0.1:9501/assets/../composer.json
```

第二个请求不应读取到 `Public` 之外的文件。核心不是简单删除 `..`，而是对最终 `realpath()` 结果做根目录边界检查。

## 生产环境做法

Nginx 可直接映射 `/assets/`，避免占用 PHP Worker：

```nginx
location /assets/ {
    alias /var/www/example/Public/;
    try_files $uri =404;
    expires 7d;
    add_header Cache-Control "public";
}

location / {
    proxy_pass http://127.0.0.1:9501;
}
```

用户私有文件不能放在公开静态目录。应先由应用鉴权，再用 `sendFile()` 或 Nginx 的内部跳转机制返回。
