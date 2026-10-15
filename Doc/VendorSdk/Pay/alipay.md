# 支付宝

## 公钥模式配置

```php
use EasySwoole\Pay\Alipay;
use EasySwoole\Pay\Config\AlipayConfig;

$config = new AlipayConfig();
$config->setAppId('支付宝应用 APPID');
$config->setAppPrivateKey('去掉 PEM 头尾和换行后的应用私钥');
$config->setAlipayPublicKey('支付宝公钥正文');
$config->setNotifyUrl('https://pay.example.com/alipay/notify');
$config->setReturnUrl('https://pay.example.com/pay/result');

$alipay = new Alipay($config);
```

证书模式需要启用 `setCertMode(true)`，并传入应用公钥证书、支付宝公钥证书和支付宝根证书的文件内容。

## 手机网站支付

```php
use EasySwoole\Pay\Request\Alipay\Wap;

$request = new Wap();
$request->out_trade_no = 'ORDER_202610150010';
$request->total_amount = '1.00';
$request->subject = '会员充值';

$payUrl = $alipay->wap($request);
```

将 `$payUrl` 返回给浏览器跳转。同步返回页面只用于用户体验，不能作为修改订单状态的依据。

## 电脑网站和 APP 支付

```php
use EasySwoole\Pay\Request\Alipay\Web;
use EasySwoole\Pay\Request\Alipay\App;

$web = new Web();
$web->out_trade_no = 'ORDER_202610150011';
$web->total_amount = '1.00';
$web->subject = '网站订单';
$webUrl = $alipay->web($web);

$app = new App();
$app->out_trade_no = 'ORDER_202610150012';
$app->total_amount = '1.00';
$app->subject = 'APP 订单';
$appParams = $alipay->appPay($app);
```

## 查询、关闭和退款

```php
use EasySwoole\Pay\Request\Alipay\TradeQuery;
use EasySwoole\Pay\Request\Alipay\TradeClose;
use EasySwoole\Pay\Request\Alipay\TradeRefund;

$query = new TradeQuery();
$query->out_trade_no = 'ORDER_202610150010';
$trade = $alipay->tradeQuery($query);

$close = new TradeClose();
$close->out_trade_no = 'ORDER_202610150010';
$alipay->tradeClose($close);

$refund = new TradeRefund();
$refund->out_trade_no = 'ORDER_202610150010';
$refund->refund_amount = '1.00';
$refund->out_request_no = 'REFUND_202610150001';
$alipay->tradeRefund($refund);
```

退款请求号也必须唯一。业务应保存退款记录，避免网络重试创建重复退款请求。

## 沙箱

```php
use EasySwoole\Pay\Beans\Alipay\Gateway;

$config->setGateWay(Gateway::SANDBOX);
```

沙箱 AppID、密钥和账户不能与生产环境混用。
