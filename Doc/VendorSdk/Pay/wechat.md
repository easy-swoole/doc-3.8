# 微信支付

## 创建 Wechat 实例

```php
use EasySwoole\Pay\Config\WechatConfig;
use EasySwoole\Pay\Wechat;

$config = new WechatConfig();
$config->setMchApiClientCert('/run/secrets/wechat/apiclient_cert.pem');
$config->setMchApiClientKey('/run/secrets/wechat/apiclient_key.pem');
$config->setWechatPayPublicKey('/run/secrets/wechat/pub_key.pem');
$config->setWechatPayPublicKeyId('PUB_KEY_ID_xxxxxxxxx');
$config->setAppId('wx0000000000000000');
$config->setEncryptKey('32位APIv3密钥');

$wechat = new Wechat($config);
```

商户号和商户证书序列号会从 `apiclient_cert.pem` 解析。商户私钥用于请求签名；微信支付公钥和公钥 ID 用于响应及回调验签；APIv3 密钥用于解密通知资源。

## Native 扫码支付

```php
use EasySwoole\Pay\Request\Wechat\Native;

$request = new Native();
$request->description = '订单商品说明';
$request->out_trade_no = 'ORDER_202610150001';
$request->notify_url = 'https://pay.example.com/wechat/notify';
$request->amount->total = 100; // 1 元，单位为分。

$result = $wechat->native($request);
$codeUrl = $result->getCodeUrl();
```

把 `$codeUrl` 生成二维码交给用户扫码。客户端扫码完成不代表订单一定支付成功，最终状态应以已验签回调或主动查询为准。

## JSAPI 和小程序支付

```php
use EasySwoole\Pay\Request\Wechat\JsApi;

$request = new JsApi();
$request->description = '会员充值';
$request->out_trade_no = 'ORDER_202610150002';
$request->notify_url = 'https://pay.example.com/wechat/notify';
$request->amount->total = 100;
$request->payer->openid = '当前 AppID 下的用户 openid';

$result = $wechat->jsApi($request);

$frontendParams = [
    'appId' => $result->appId,
    'timeStamp' => $result->timeStamp,
    'nonceStr' => $result->nonceStr,
    'package' => $result->package,
    'signType' => $result->signType,
    'paySign' => $result->paySign,
];
```

`openid` 必须属于配置的 AppID。

## H5 支付

```php
use EasySwoole\Pay\Request\Wechat\H5;

$request = new H5();
$request->description = 'H5 商品订单';
$request->out_trade_no = 'ORDER_202610150003';
$request->notify_url = 'https://pay.example.com/wechat/notify';
$request->amount->total = 100;
$request->scene_info->payer_client_ip = '用户真实公网 IP';
$request->scene_info->h5_info->type = 'Wap';
$request->scene_info->h5_info->app_url = 'https://pay.example.com/checkout';

$result = $wechat->h5($request);
$h5Url = $result->h5_url;
```

跳转页面域名必须在商户平台配置，且 `payer_client_ip` 应是实际付款用户公网 IP。

## 查询与关闭订单

```php
$order = $wechat->queryByOutTradeNo('ORDER_202610150001');
$state = $order->trade_state;

if ($state === 'NOTPAY') {
    $wechat->close('ORDER_202610150001');
}
```

获得微信订单号后也可以调用 `$wechat->query($transactionId)`。

## 异常处理

```php
use EasySwoole\Pay\Exception\WechatApiError;

try {
    $result = $wechat->native($request);
} catch (WechatApiError $error) {
    $apiCode = $error->apiCode;
    $message = $error->getMessage();
    $detail = $error->detail;
}
```

日志可以记录商户订单号和错误码，不能记录私钥、APIv3 密钥或完整敏感支付数据。
