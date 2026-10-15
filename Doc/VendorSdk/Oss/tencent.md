# 腾讯云 COS

## 创建客户端

```php
use EasySwoole\Oss\Tencent\Config;
use EasySwoole\Oss\Tencent\OssClient;

$config = new Config([
    'appId' => getenv('TENCENT_COS_APP_ID'),
    'secretId' => getenv('TENCENT_COS_SECRET_ID'),
    'secretKey' => getenv('TENCENT_COS_SECRET_KEY'),
    'region' => 'ap-guangzhou',
    'bucket' => 'example-1250000000',
    'schema' => 'https',
    'timeout' => 30,
    'connectTimeout' => 5,
]);

$client = new OssClient($config);
```

Bucket 通常包含 AppID 后缀，Region 必须与 Bucket 所在地域一致。

## 上传文件或内容

```php
$bucket = 'example-1250000000';
$key = 'documents/readme.txt';

$client->upload($bucket, $key, 'Hello EasySwoole');

$stream = fopen('/data/uploads/video.mp4', 'rb');
try {
    $client->upload($bucket, 'videos/video.mp4', $stream, [
        'PartSize' => 5 * 1024 * 1024,
    ]);
} finally {
    fclose($stream);
}
```

内容超过 `PartSize` 时会走分片上传。

## 下载对象

```php
$result = $client->getObject([
    'Bucket' => $bucket,
    'Key' => $key,
]);

$content = $result['Body']->__toString();
```

`Body` 是流对象。大文件不要全部转成字符串，应按流读取并写入目标文件。

## 删除和签名 URL

```php
$client->deleteObject([
    'Bucket' => $bucket,
    'Key' => $key,
]);

$url = $client->getObjectUrl(
    $bucket,
    'private/report.pdf',
    600
);
```

签名 URL 的有效期应尽量短，生成前检查当前用户对对象的业务权限。异常日志可记录 Request ID、Region、Bucket 和 Key，不能记录 SecretKey。
