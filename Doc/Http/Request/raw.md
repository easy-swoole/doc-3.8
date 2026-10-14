# 原始请求体

Webhook 签名、非 JSON 协议或需要区分 JSON 语法错误时，应读取未经业务解析的原始 Body。

## Webhook 签名完整示例

新建 `App/HttpController/Webhook.php`：

```php
<?php
namespace App\HttpController;

use EasySwoole\Http\AbstractInterface\Controller;

class Webhook extends Controller
{
    public function receive(): void
    {
        $raw = (string) $this->request()->getBody();
        $signature = $this->request()->getHeaderLine('x-signature');
        $expected = hash_hmac('sha256', $raw, 'demo-secret');

        if ($signature === '' || !hash_equals($expected, $signature)) {
            $this->writeJson(401, null, '签名错误');
            return;
        }

        try {
            $payload = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
        } catch (\JsonException $exception) {
            $this->writeJson(400, null, 'JSON 格式错误');
            return;
        }

        $this->writeJson(200, ['event' => $payload['event'] ?? null]);
    }
}
```

```php
$routeCollector->post('/webhook', '/Webhook/receive');
```

测试时对完全相同的字节计算签名：

```bash
body='{"event":"order.paid"}'
signature=$(printf '%s' "$body" | openssl dgst -sha256 -hmac 'demo-secret' -hex | sed 's/^.* //')
curl -X POST http://127.0.0.1:9501/webhook \
  -H 'Content-Type: application/json' \
  -H "X-Signature: $signature" \
  --data-binary "$body"
```

签名必须针对原始字节验证，不能先解码 JSON 再重新编码；空格、换行和键顺序变化都会改变签名。密钥应来自环境变量或密钥服务，不能像示例一样写死。

可先检查 `Content-Length` 并在 Nginx/Swoole 层限制 Body 大小，但 Header 也可能伪造，最终仍以实际接收数据为准。大文件不要用原始 Body 一次性读入内存，应使用上传机制或对象存储直传。
