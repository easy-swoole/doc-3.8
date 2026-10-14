# 反向代理部署

生产环境通常不让 EasySwoole 直接暴露在公网。推荐由 Nginx 负责 TLS、域名、静态文件和连接限制，再把动态请求转发给监听内网地址的 EasySwoole。

```text
浏览器 / App
    ↓ HTTPS :443
Nginx
    ├── /assets/ → 直接读取静态文件
    ├── /ws      → WebSocket Upgrade
    └── 其他请求 → EasySwoole 127.0.0.1:9501
```

## EasySwoole 监听地址

Nginx 和 EasySwoole 在同一台服务器时，生产配置 `produce.php` 建议只监听回环地址：

```php
'MAIN_SERVER' => [
    'LISTEN_ADDRESS' => '127.0.0.1',
    'PORT' => 9501,
    'SERVER_TYPE' => EASYSWOOLE_WEB_SERVER,
    // 保留项目其他配置……
],
```

这样外部无法绕过 Nginx 直接访问 9501。若 Nginx 与应用分属不同服务器，则监听内网地址，并通过安全组或防火墙只允许代理节点访问。

WebSocket 项目将 `SERVER_TYPE` 改为 `EASYSWOOLE_WEB_SOCKET_SERVER`，同一个端口仍可处理普通 HTTP 请求。

## 最小 HTTP 代理配置

先确认 EasySwoole 本身可访问：

```bash
curl -i http://127.0.0.1:9501/
```

然后创建 Nginx 站点配置，例如 `/etc/nginx/conf.d/example.conf`：

```nginx
upstream easyswoole_backend {
    server 127.0.0.1:9501 max_fails=3 fail_timeout=10s;
    keepalive 32;
}

server {
    listen 80;
    server_name api.example.com;

    location / {
        proxy_pass http://easyswoole_backend;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        proxy_set_header X-Request-ID $request_id;

        # 普通 HTTP 使用 upstream keepalive，不发送 Connection: close。
        proxy_set_header Connection "";

        proxy_connect_timeout 3s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
```

检查并重载：

```bash
sudo nginx -t
sudo nginx -s reload
curl -i http://api.example.com/
```

`proxy_pass` 没有附加 URI，因此原始路径会完整传给 EasySwoole。若写成带路径的 `proxy_pass http://backend/api/;`，Nginx 会按照 location 规则重写 URI，新手应避免在没有明确需求时这样配置。

## HTTPS 配置

TLS 通常在 Nginx 终止，EasySwoole 后端仍使用本机 HTTP：

```nginx
server {
    listen 80;
    server_name api.example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    http2 on;
    server_name api.example.com;

    ssl_certificate     /etc/letsencrypt/live/api.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.example.com/privkey.pem;

    location / {
        proxy_pass http://easyswoole_backend;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Request-ID $request_id;
    }
}
```

证书路径和 TLS 策略应由证书工具及当前安全规范生成，不要直接复制过时的协议或 Cipher 列表。

EasySwoole 与 Nginx 之间是 HTTP，所以框架 URI 的 Scheme 未必能直接反映用户访问的 HTTPS。应用只有在请求确实来自可信代理时，才能使用 `X-Forwarded-Proto` 判断外部协议。生成重置密码链接等绝对 URL 时，更稳妥的做法是使用配置中的公开站点地址。

## Header 分别表示什么

| Header | 含义 |
| --- | --- |
| `Host` | 用户访问的域名 |
| `X-Real-IP` | Nginx 看到的直接客户端 IP |
| `X-Forwarded-For` | 经过的客户端与代理地址链 |
| `X-Forwarded-Proto` | 外部请求使用 HTTP 还是 HTTPS |
| `X-Forwarded-Host` | 外部 Host |
| `X-Forwarded-Port` | 外部端口 |
| `X-Request-ID` | Nginx 生成的请求追踪 ID |

这些 Header 不是天然可信的。安全边界必须满足至少一项：

- EasySwoole 只监听 `127.0.0.1`，外部无法直连。
- 防火墙只允许可信代理访问应用端口。
- 应用确认请求来源是可信代理后才解析 Forwarded Header。

如果 Nginx 前面还有云负载均衡，应先让 Nginx 正确恢复真实地址：

```nginx
# 这里只能填写负载均衡器的真实内网 CIDR，不能写 0.0.0.0/0。
set_real_ip_from 10.20.0.0/16;
real_ip_header X-Forwarded-For;
real_ip_recursive on;
```

配置正确后，`$remote_addr` 才是经过可信链解析的客户端地址。错误地信任任意来源会让攻击者伪造 IP，绕过限流和审计。

## WebSocket 代理

在 Nginx `http` 配置块定义 Connection 映射：

```nginx
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
```

站点中单独配置 WebSocket 路径：

```nginx
location /ws {
    proxy_pass http://easyswoole_backend;
    proxy_http_version 1.1;

    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Request-ID $request_id;

    proxy_read_timeout 120s;
    proxy_send_timeout 120s;
    proxy_buffering off;
}
```

HTTPS 页面必须连接 `wss://api.example.com/ws`。代理读超时应大于应用心跳间隔，否则连接虽然正常，仍可能被 Nginx 当作长时间无数据而关闭。

## 静态资源

静态文件应尽量绕过 PHP Worker：

```nginx
location /assets/ {
    alias /var/www/example/Public/assets/;
    try_files $uri =404;
    expires 7d;
    add_header Cache-Control "public";
    access_log off;
}
```

带内容哈希的资源可以设置更长缓存。用户私有文件不能放在公开目录，应先由应用鉴权，再使用内部跳转、对象存储签名 URL 等方式下载。

## 上传大小和超时

上传限制至少存在 Nginx、Swoole、应用三层。Nginx 示例：

```nginx
server {
    client_max_body_size 20m;
    client_body_timeout 30s;

    location / {
        proxy_connect_timeout 3s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        proxy_pass http://easyswoole_backend;
    }
}
```

Nginx 限制更小时会直接返回 413，请求不会到达 EasySwoole。超时不能无限放大：长时间业务应改成提交任务后查询状态，而不是让 HTTP 请求一直等待。

默认请求缓冲能让 Nginx 先接收请求体，避免慢速客户端长期占用后端连接。关闭 `proxy_request_buffering` 可以流式转发，但会把慢上传压力直接传给 EasySwoole，应明确评估后再使用。

## 健康检查

添加一个不依赖数据库和第三方服务的存活检查：

```php
$routeCollector->get('/health/live', function ($request, $response) {
    $response->withHeader('Content-Type', 'application/json');
    $response->write('{"status":"ok"}');
    return false;
});
```

再按需要增加就绪检查 `/health/ready`，验证实例是否已经完成初始化、连接池是否可用。两者作用不同：

- Liveness 失败：进程可能需要重启。
- Readiness 失败：暂时从负载均衡摘除，但不一定重启。

健康检查不要执行昂贵查询，也不要记录大量访问日志。Nginx 开源版 upstream 可使用 `max_fails` 和 `fail_timeout` 做被动失败判断；云负载均衡或编排平台通常提供主动健康检查。

## 多实例负载均衡

```nginx
upstream easyswoole_backend {
    least_conn;
    server 10.0.1.11:9501 max_fails=3 fail_timeout=10s;
    server 10.0.1.12:9501 max_fails=3 fail_timeout=10s;
    keepalive 64;
}
```

应用实例必须尽量无状态：Session、限流计数和任务状态放在 Redis/数据库等共享存储；上传文件放共享对象存储。WebSocket 连接本身有状态，需要消息总线把通知发送到持有目标连接的实例。

普通 HTTP 通常不需要粘性会话。依赖 IP Hash 隐藏本地 Session 问题，会让扩缩容和故障切换更加困难。

## 优雅发布

推荐流程：

```text
启动新实例
    ↓
等待 /health/ready 成功
    ↓
加入负载均衡
    ↓
旧实例停止接收新请求
    ↓
等待进行中的请求完成
    ↓
停止旧实例
```

EasySwoole 代码更新可使用 reload，但 Server 类型、监听端口、底层 Swoole Setting 等进程级配置变化应完整重启。WebSocket 发布还要考虑现有长连接的断开通知和客户端退避重连。

## 常见故障排查

| 现象 | 常见原因 | 检查方法 |
| --- | --- | --- |
| 502 Bad Gateway | EasySwoole 未启动、端口错误、连接被拒绝 | `curl 127.0.0.1:9501`、Nginx error log |
| 504 Gateway Timeout | Action 阻塞、下游超时、`proxy_read_timeout` 太短 | 请求耗时日志、慢查询、依赖监控 |
| 413 Request Entity Too Large | `client_max_body_size` 太小 | Nginx 配置和 error log |
| 客户端 IP 都是 127.0.0.1 | 读取了 `remote_addr`，未处理可信代理 Header | 检查转发 Header 和信任链 |
| HTTPS 页面生成 HTTP 链接 | 应用不知道外部 Scheme | 检查 `X-Forwarded-Proto`，优先使用站点配置 |
| WebSocket 立即断开 | Upgrade Header 缺失、代理超时、Origin/Token 被拒绝 | 浏览器 Network、Nginx 和应用日志 |
| 静态资源 404 | `alias` 路径或 `try_files` 使用错误 | `nginx -T`、检查文件权限和实际路径 |

排查顺序应从内到外：先直连 EasySwoole，再检查 Nginx upstream，最后检查域名、TLS、CDN和外部负载均衡。每一层都使用同一个 Request ID 能显著降低定位难度。

## 上线前检查

- EasySwoole 端口是否只允许可信代理访问？
- 是否先执行 `nginx -t` 再 reload？
- Host、真实 IP、外部 Scheme 和 Request ID 是否正确传递？
- 应用是否只信任已知代理写入的 Forwarded Header？
- TLS 证书是否自动续期并有到期监控？
- 上传大小、连接/读取/发送超时是否三层一致？
- WebSocket 是否正确转发 Upgrade，代理超时是否大于心跳周期？
- 静态文件是否由 Nginx/CDN 处理，私有文件是否经过鉴权？
- 健康检查是否区分存活与就绪？
- 多实例是否移除了进程本地 Session 和上传文件依赖？
