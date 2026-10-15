# HTTP Client 安装与快速开始

`easyswoole/http-client` 封装了 `Swoole\Coroutine\Http\Client`，用于在 EasySwoole 控制器、任务或自定义进程中请求第三方 HTTP 服务。

## 环境要求

- PHP 8.1 及以上。
- 已安装 Swoole 扩展。
- 请求代码运行在协程环境中。

```bash
php -v
php --ri swoole
```

## 安装

在项目根目录执行：

```bash
composer require easyswoole/http-client
composer show easyswoole/http-client
```

组件安装后直接通过 Composer 自动加载，不需要在 `EasySwooleEvent.php` 中注册。

## 最小 GET 示例

```php
use EasySwoole\HttpClient\HttpClient;

$client = new HttpClient('https://api.example.com/users/1001');
$client->setConnectTimeout(1.0)
    ->setReadTimeout(3.0);

$response = $client->get([
    'Accept' => 'application/json',
]);

if ($response->getErrCode() !== 0) {
    throw new RuntimeException($response->getErrMsg());
}

if ($response->getStatusCode() !== 200) {
    throw new RuntimeException('HTTP ' . $response->getStatusCode());
}

$data = json_decode(
    $response->getBody(),
    true,
    512,
    JSON_THROW_ON_ERROR
);
```

完整调用顺序：

```text
new HttpClient(URL)
  → 设置 Query、Header、Cookie、Body 和超时
  → get()/post()/put()/patch() 发送请求
  → 获得 Response
  → 检查 errCode
  → 检查 HTTP statusCode
  → 解析 Body 并检查业务状态
```

## 在控制器中调用

```php
<?php

namespace App\HttpController;

use EasySwoole\Http\AbstractInterface\Controller;
use EasySwoole\HttpClient\HttpClient;

final class User extends Controller
{
    public function profile(): void
    {
        $client = new HttpClient('https://api.example.com/profile');
        $client->setConnectTimeout(1.0)->setReadTimeout(3.0);
        $response = $client->get();

        if ($response->getErrCode() !== 0) {
            $this->writeJson(502, null, 'upstream connection failed');
            return;
        }

        if ($response->getStatusCode() !== 200) {
            $this->writeJson(502, null, 'upstream response error');
            return;
        }

        $this->writeJson(200, $response->json(true));
    }
}
```

## 实例能否复用

一个 `HttpClient` 内部持有一个 Swoole 客户端，请求头、Cookie、连接和请求状态都保存在实例中。不要把同一个实例交给多个协程同时使用。

```php
go(function (): void {
    (new HttpClient('https://api.example.com/a'))->get();
});

go(function (): void {
    (new HttpClient('https://api.example.com/b'))->get();
});
```

同一协程连续访问同一个 Host 时可以开启 Keep-Alive 后复用；不同 Host 应创建不同实例。

下一章：[发送请求](/Client/Http/request.md)。
