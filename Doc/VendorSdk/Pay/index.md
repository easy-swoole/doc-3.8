# Pay 安装与配置

`easyswoole/pay` 2.x 提供微信支付 API v3 和支付宝开放平台接口。它负责请求签名、响应验签和支付参数构造，业务仍需自行保存订单、校验金额并处理回调幂等。

## 环境要求

- PHP 8.1 及以上。
- Swoole 扩展。
- OpenSSL、JSON、BCMath、Mbstring 扩展。
- 微信支付网络请求在协程中执行。

```bash
php --ri swoole
php --ri openssl
php --ri bcmath
php --ri mbstring
```

## 安装

```bash
composer require easyswoole/pay:"2.x"
composer show easyswoole/pay
```

## 凭据保存

支付私钥、APIv3 密钥和生产证书不能提交到 Git。建议使用：

- 部署系统挂载的只读密钥文件。
- 环境变量或专用密钥管理服务。
- 仅服务进程用户可读取的文件权限。

项目配置只保存密钥文件路径，不直接保存密钥正文：

```php
'PAY' => [
    'WECHAT' => [
        'appId' => 'wx0000000000000000',
        'merchantCert' => '/run/secrets/wechat/apiclient_cert.pem',
        'merchantKey' => '/run/secrets/wechat/apiclient_key.pem',
        'publicKey' => '/run/secrets/wechat/pub_key.pem',
        'publicKeyId' => 'PUB_KEY_ID_xxx',
        'apiV3Key' => getenv('WECHAT_PAY_API_V3_KEY'),
    ],
],
```

## 金额和订单号

- 微信支付金额单位是“分”，例如 1 元传 `100`。
- 支付宝金额通常使用两位小数字符串，例如 `'1.00'`。
- 商户订单号必须持久化并保持全局唯一。
- 创建支付前先在本地数据库保存待支付订单，不能只依赖前端返回结果。

后续按使用平台阅读[微信支付](/VendorSdk/Pay/wechat.md)或[支付宝](/VendorSdk/Pay/alipay.md)。
