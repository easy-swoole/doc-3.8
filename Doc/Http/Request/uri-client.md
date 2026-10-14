# URI 与客户端信息

URI 用于获取 Scheme、Host、Port、Path 和 Query；Server Params 保存 Swoole 提供的连接与服务器信息。

## 完整示例

```php
<?php
namespace App\HttpController;

use EasySwoole\Http\AbstractInterface\Controller;

class RequestInfo extends Controller
{
    public function index(): void
    {
        $request = $this->request();
        $uri = $request->getUri();
        $server = $request->getServerParams();

        $this->writeJson(200, [
            'method' => $request->getMethod(),
            'scheme' => $uri->getScheme(),
            'host' => $uri->getHost(),
            'port' => $uri->getPort(),
            'path' => $uri->getPath(),
            'query' => $uri->getQuery(),
            'remoteIp' => $server['remote_addr'] ?? null,
            'protocol' => $request->getProtocolVersion(),
        ]);
    }
}
```

```php
$routeCollector->get('/request/info', '/RequestInfo/index');
```

```bash
curl 'http://127.0.0.1:9501/request/info?page=2'
```

URI Fragment（`#section`）不会发送到服务器。`getUri()->getQuery()` 返回原始查询字符串；读取业务参数应使用 `getQueryParams()`。

## 反向代理后的客户端 IP

直连时可读取：

```php
$remoteIp = $request->getServerParams()['remote_addr'] ?? '';
```

部署在 Nginx 后，`remote_addr` 通常是代理地址。只有请求确实来自你的可信代理时，才能解析 `X-Forwarded-For` 或 `X-Real-IP`。这些 Header 可由直连客户端伪造，不能无条件信任第一个值。

同样，Host 和 Scheme 可能受客户端或代理配置影响。生成密码重置链接、签名地址或跳转地址时，应使用应用配置的公开域名允许列表，而不是直接拼接请求 Host。

常见 Server Params 包括 `request_method`、`request_uri`、`path_info`、`query_string`、`remote_addr`、`remote_port` 和 `server_port`；具体键取决于 Swoole 版本和协议环境，使用前应提供默认值。
