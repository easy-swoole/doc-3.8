# HTTP Client 发送请求

## Query 参数和路径

```php
use EasySwoole\HttpClient\HttpClient;

$client = new HttpClient('https://api.example.com/users?page=1');
$client->setQuery(['page' => 2, 'size' => 20]);
$response = $client->get();
```

新值会覆盖同名 Query。修改路径：

```php
$client->setPath('/users/1001');
$response = $client->get();
```

## 请求方法

```php
$client->get();
$client->head();
$client->delete();
$client->trace();
$client->post($data);
$client->put($data);
$client->patch($data);
$client->options($data);
```

快捷方法的最后一个参数是本次请求 Header：

```php
$response = $client->post(
    ['name' => 'EasySwoole'],
    ['X-Request-Id' => 'request-1001']
);
```

## 表单请求

```php
$client = new HttpClient('https://api.example.com/login');
$response = $client->post([
    'username' => 'demo',
    'password' => 'secret',
]);
```

明确要求 URL Encoded 时：

```php
$client->setContentTypeFormUrlencoded();
$response = $client->post(http_build_query([
    'username' => 'demo',
    'password' => 'secret',
]));
```

## JSON 请求

`postJson()` 只接收 JSON 字符串，不会自动编码数组：

```php
$body = json_encode(
    ['name' => 'EasySwoole', 'enabled' => true],
    JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR
);

$client = new HttpClient('https://api.example.com/projects');
$response = $client->postJson($body);
```

PUT 或 PATCH JSON：

```php
$client->setContentTypeJson();
$response = $client->patch($body);
```

## XML 和原始 Body

```php
$response = $client->postXml('<request><id>1001</id></request>');
```

```php
$client->setContentType('text/plain; charset=utf-8');
$response = $client->put('raw request body');
```

## Header 与认证

```php
$client->setHeaders([
    'Accept' => 'application/json',
    'X-App-Name' => 'docs',
]);
$client->setHeader('X-Request-Id', 'request-1001');
```

当前 `setHeader()` 默认把 Header 名和值转成小写。Token、签名等区分大小写的值必须传第三个参数 `false`：

```php
$client->setHeader(
    'Authorization',
    'Bearer AbCdEf123456',
    false
);
```

Basic Auth：

```php
$client->setBasicAuth('api-user', 'api-password');
```

## Cookie

```php
$client->addCookies([
    'sessionId' => 'session-value',
    'locale' => 'zh-CN',
]);
$client->addCookie('deviceId', 'device-1001');
```

## 超时

```php
$client->setTimeout(5.0)
    ->setConnectTimeout(1.0)
    ->setReadTimeout(3.0)
    ->setWriteTimeout(2.0);
```

| 方法 | 控制范围 |
| --- | --- |
| `setTimeout()` | 默认总超时 |
| `setConnectTimeout()` | TCP/TLS 连接阶段 |
| `setReadTimeout()` | 等待响应数据 |
| `setWriteTimeout()` | 发送请求数据 |

下一章：[处理响应](/Client/Http/response.md)。
