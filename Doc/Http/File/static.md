# 静态资源

生产环境推荐由 Nginx/CDN 直接处理 `Public` 目录，EasySwoole 只处理动态请求：

```text
项目根目录/
├── Public/
│   ├── assets/app.a1b2c3.css
│   └── images/logo.png
└── App/
```

```nginx
location /assets/ {
    alias /var/www/example/Public/assets/;
    try_files $uri =404;
    expires 7d;
    add_header Cache-Control "public";
}

location / {
    proxy_pass http://127.0.0.1:9501;
}
```

带内容哈希的 CSS/JS/图片可设置长期缓存；HTML 使用短缓存或不缓存。用户私有文件不能放进公开目录。

开发期若由 EasySwoole 返回资源，在 Router 中关闭 PathInfo 模式并保留扩展名：

```php
$this->setPathInfoMode(false);
$routeCollector->get('/assets/{path:.+}', '/StaticFile/read');
```

控制器必须对 `realpath()` 后的最终路径做根目录边界检查，再设置真实 MIME、Cache-Control 并 `sendFile()`。不能只删除字符串中的 `..`，也不能把 URL 路径直接交给 `sendFile()`。完整安全控制器参见“路由 → 静态资源路由”。

Range、ETag、Last-Modified、压缩和高并发传输应交给 Nginx/CDN。应用适合做鉴权与定位文件，不适合替代成熟静态文件服务器。
