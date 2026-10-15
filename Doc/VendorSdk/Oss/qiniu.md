# 七牛云 Kodo

## 创建上传凭证

```php
use EasySwoole\Oss\QiNiu\Auth;
use EasySwoole\Oss\QiNiu\Config;

Config::setTimeout(30);
Config::setConnectTimeout(5);

$auth = new Auth(
    getenv('QINIU_ACCESS_KEY'),
    getenv('QINIU_SECRET_KEY')
);

$bucket = 'example-bucket';
$key = 'images/avatar.png';
$token = $auth->uploadToken($bucket, $key, 3600);
```

## 服务端上传文件

```php
use EasySwoole\Oss\QiNiu\Storage\UploadManager;

$manager = new UploadManager();
[$result, $error] = $manager->putFile(
    $token,
    $key,
    '/data/uploads/avatar.png',
    null,
    'image/png'
);

if ($error !== null) {
    throw new RuntimeException($error->message());
}

$hash = $result['hash'];
```

小文件使用表单上传，大文件会由组件选择分块上传。上传前仍需检查本地文件路径、大小和 MIME。

## 私有下载 URL

```php
$baseUrl = 'https://cdn.example.com/' . rawurlencode($key);
$privateUrl = $auth->privateDownloadUrl($baseUrl, 600);
```

生成 URL 前先校验业务权限。公开空间可以使用 CDN 域名直接访问，但仍建议数据库保存对象 Key 而不是完整 URL。

## 删除文件

```php
use EasySwoole\Oss\QiNiu\Storage\BucketManager;

$bucketManager = new BucketManager($auth);
$error = $bucketManager->delete($bucket, $key);

if ($error !== null) {
    throw new RuntimeException($error->message());
}
```
