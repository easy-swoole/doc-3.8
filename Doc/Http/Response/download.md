# 文件下载

`sendFile()` 可以把服务器文件作为响应发送，但传入的是服务器绝对路径，不能直接接受用户提交的任意路径。

## 固定文件下载

```php
public function manual(): void
{
    $file = EASYSWOOLE_ROOT . '/Storage/manual.pdf';
    if (!is_file($file) || !is_readable($file)) {
        $this->writeJson(404, null, '文件不存在');
        return;
    }

    $response = $this->response();
    $response->withHeader('Content-Type', 'application/pdf');
    $response->withHeader(
        'Content-Disposition',
        'attachment; filename="manual.pdf"'
    );
    $response->withHeader('Content-Length', (string) filesize($file));
    $response->sendFile($file);
}
```

```php
$routeCollector->get('/downloads/manual', '/Download/manual');
```

```bash
curl -i http://127.0.0.1:9501/downloads/manual
curl -o manual.pdf http://127.0.0.1:9501/downloads/manual
```

## 根据 ID 下载私有文件

URL 应传业务 ID，而不是磁盘路径：

```text
GET /downloads/42
```

控制器流程应为：验证登录 → 查询 ID 42 的文件记录 → 检查访问权限 → 从可信记录取得存储路径 → 确认文件位于存储根目录 → `sendFile()`。

若确实拼接相对路径，必须用 `realpath()` 检查最终路径仍在允许根目录内：

```php
$root = realpath(EASYSWOOLE_ROOT . '/Storage/downloads');
$file = $root === false ? false : realpath($root . '/' . $relativePath);
if ($file === false || !str_starts_with($file, $root . DIRECTORY_SEPARATOR)) {
    $this->writeJson(404, null, '文件不存在');
    return;
}
```

下载名来自数据库或用户输入时要过滤 CR/LF、引号和路径分隔符，防止 Header 注入。非 ASCII 文件名可按 RFC 5987 增加 `filename*`。

公开大文件更适合由 Nginx/CDN 或对象存储处理；私有大文件可在应用鉴权后使用 Nginx 内部跳转或短期签名 URL，避免长期占用 PHP Worker。
