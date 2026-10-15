# 支付回调与安全

支付回调必须遵循“读取原始请求 → 验签 → 解密或解析 → 校验订单 → 幂等更新 → 返回成功”的顺序。

## 微信支付回调

```php
use EasySwoole\Pay\Request\Wechat\Callback;
use EasySwoole\Pay\Wechat;

$headers = array_change_key_case($this->request()->getHeaders(), CASE_LOWER);
$rawBody = $this->request()->getBody()->__toString();

$callback = new Callback([
    'signature' => $headers['wechatpay-signature'][0] ?? '',
    'timestamp' => (int)($headers['wechatpay-timestamp'][0] ?? 0),
    'nonce' => $headers['wechatpay-nonce'][0] ?? '',
    'certSerial' => $headers['wechatpay-serial'][0] ?? '',
    'body' => $rawBody,
]);

if (!$wechat->verify($callback)) {
    throw new RuntimeException('微信支付回调验签失败');
}

$payload = json_decode($rawBody, true, 512, JSON_THROW_ON_ERROR);
$resource = $payload['resource'];
$plainText = $wechat->decrypt(
    $resource['ciphertext'],
    $resource['nonce'],
    $resource['associated_data'] ?? ''
);
$payment = json_decode($plainText, true, 512, JSON_THROW_ON_ERROR);
```

校验商户号、AppID、商户订单号和金额后，在数据库事务中幂等更新订单。微信支付 API v3 通知处理成功后可以返回 HTTP 204，不需要响应 XML：

```php
$this->response()->withStatus(204);
```

验签、解密或业务处理失败时返回 4xx/5xx，使微信支付平台按通知规则重试。组件中的 `Wechat::success()`/`fail()` 是 XML 响应辅助方法，不应用于这里的 API v3 通知响应。

## 支付宝回调

```php
use EasySwoole\Pay\Alipay;

$data = $this->request()->getRequestParam();

if (!$alipay->verifyResponse($data)) {
    $this->response()->write(Alipay::fail());
    return;
}

// 校验 app_id、out_trade_no、total_amount、seller_id 和 trade_status。
// 使用 out_trade_no 幂等更新本地订单。

$this->response()->write(Alipay::success());
```

## 必须校验的业务字段

- 回调所属应用和商户是否是自己的配置。
- `out_trade_no` 是否存在且属于当前商户。
- 支付金额、币种是否和本地订单完全一致。
- 支付状态是否属于可接受的成功状态。
- 已成功订单再次收到通知时只返回成功，不重复发货。

不要信任前端提交的“支付成功”，也不要在验签前写入数据库。回调处理成功后再返回成功字符串；处理失败应返回失败，让支付平台按规则重试。
