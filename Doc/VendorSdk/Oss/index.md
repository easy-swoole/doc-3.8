# OSS 安装与接入说明

`easyswoole/oss` 2.x 提供阿里云 OSS、七牛云 Kodo 和腾讯云 COS 的协程客户端实现。

## 环境与安装

组件要求 PHP 8.1+、Swoole 和 cURL 扩展：

```bash
php --ri swoole
php --ri curl
composer require easyswoole/oss:"2.x"
composer show easyswoole/oss
```

## 选择厂商客户端

| 厂商 | 配置和客户端 |
| --- | --- |
| 阿里云 | `EasySwoole\Oss\AliYun\Config`、`OssClient` |
| 七牛云 | `EasySwoole\Oss\QiNiu\Auth`、`UploadManager`、`BucketManager` |
| 腾讯云 | `EasySwoole\Oss\Tencent\Config`、`OssClient` |

## 凭据与对象 Key

- AccessKey/SecretKey 不得写进仓库或返回给前端。
- 服务端尽量使用最小权限 RAM/CAM 子账号。
- 上传对象 Key 应由服务端生成，不能直接使用未经清理的用户文件名。
- 私有文件通过短期签名 URL 下载，不要把 Bucket 改成公共读。
- 数据库保存 Bucket、Key、大小、MIME、哈希和业务归属，不要只保存临时 URL。

后续选择[阿里云 OSS](/VendorSdk/Oss/aliyun.md)、[七牛云 Kodo](/VendorSdk/Oss/qiniu.md)或[腾讯云 COS](/VendorSdk/Oss/tencent.md)。
