# 阿里云 OSS

## 创建客户端

```php
use EasySwoole\Oss\AliYun\Config;
use EasySwoole\Oss\AliYun\OssClient;

$config = new Config([
    'accessKeyId' => getenv('ALIYUN_ACCESS_KEY_ID'),
    'accessKeySecret' => getenv('ALIYUN_ACCESS_KEY_SECRET'),
    'endpoint' => 'oss-cn-hangzhou.aliyuncs.com',
    'timeout' => 30,
    'connectionTimeout' => 5,
]);

$client = new OssClient($config);
```

Endpoint 使用 Bucket 所在地域对应的地址。绑定自定义域名时还需设置 `isCName`。

## 上传字符串和文件

```php
$bucket = 'example-bucket';

$client->putObject(
    $bucket,
    'documents/readme.txt',
    'Hello EasySwoole'
);

$client->uploadFile(
    $bucket,
    'images/avatar.png',
    '/data/uploads/avatar.png'
);
```

## 下载和删除

读取到内存：

```php
$content = $client->getObject($bucket, 'documents/readme.txt');
```

下载到文件：

```php
use EasySwoole\Oss\AliYun\OssConst;

$client->getObject($bucket, 'images/avatar.png', [
    OssConst::OSS_FILE_DOWNLOAD => '/data/downloads/avatar.png',
]);
```

删除：

```php
$client->deleteObject($bucket, 'images/avatar.png');
```

## 临时签名 URL

```php
use EasySwoole\Oss\AliYun\OssConst;

$url = $client->generatePresignedUrl(
    $bucket,
    'private/report.pdf',
    600,
    OssConst::OSS_HTTP_GET
);
```

过期时间使用较短值，并在授权接口中先检查当前用户是否有权访问该对象。

所有网络操作都可能抛出 `OssException`，应记录 Request ID、Bucket 和 Key，但不要记录访问密钥。
