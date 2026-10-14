# 异常与安全

异常处理负责把失败转换成稳定的 HTTP 响应；安全控制负责让恶意或错误输入无法越过系统边界。二者应统一设计，而不是在每个 Action 中随意 `try/catch`。

## 推荐的处理层次

```text
请求进入
    ↓
全局 HTTP onRequest：Host、CORS、基础限流
    ↓
Router：404、405
    ↓
Controller onRequest：登录与权限
    ↓
参数解析与验证：400、422
    ↓
Service：业务异常、事务和并发约束
    ↓
Controller onException：当前模块的已知异常
    ↓ 未处理或重新抛出
HTTP 全局异常处理器：最终错误边界
    ↓
记录完整日志，向客户端返回安全响应
```

## HTTP 状态码和业务错误

常用约定：

| 状态码 | 含义 | 示例 |
| --- | --- | --- |
| 400 | 请求语法错误 | JSON 无法解析 |
| 401 | 未认证 | Session/Token 无效 |
| 403 | 已认证但无权限 | 普通管理员访问超级管理员接口 |
| 404 | 路由或资源不存在 | 用户 ID 不存在 |
| 405 | 路径存在但方法不允许 | 对只支持 GET 的地址发送 POST |
| 409 | 当前资源状态冲突 | 重复创建、版本冲突 |
| 422 | 字段验证失败 | 邮箱格式、长度不正确 |
| 429 | 请求频率超过限制 | 登录尝试过多 |
| 500 | 未知服务异常 | 未预料的代码错误 |

不要所有失败都返回 HTTP 200 再只看 JSON `code`，否则代理、监控和客户端无法准确理解结果。

建议统一响应格式：

```json
{
  "code": 422,
  "message": "参数验证失败",
  "errors": {
    "email": ["邮箱格式不正确"]
  },
  "requestId": "req-a1b2c3"
}
```

生产响应不要包含异常堆栈、PHP 文件路径、SQL、数据库连接信息或密钥。

## 控制器异常处理

控制器可以覆盖 `onException()`，处理本模块已知异常：

```php
use EasySwoole\EasySwoole\Trigger;
use EasySwoole\HttpAnnotation\Exception\ParamValidateFail;

protected function onException(\Throwable $throwable): void
{
    if ($throwable instanceof ParamValidateFail) {
        $this->writeJson(422, null, $throwable->getMessage());
        return;
    }

    if ($throwable instanceof BusinessException) {
        $this->writeJson(
            $throwable->getStatusCode(),
            null,
            $throwable->getMessage()
        );
        return;
    }

    // 未知异常记录后交给外层，或者在这里返回统一 500。
    Trigger::getInstance()->throwable($throwable);
    $this->writeJson(500, null, '服务器内部错误');
}
```

`ParamValidateFail` 的处理细节也可以放进所有 Annotation 控制器继承的 Base 中，避免重复。

## HTTP 全局异常处理器

全局处理器是最后一道边界。在项目根目录 `EasySwooleEvent.php` 的 `initialize()` 中配置：

```php
use EasySwoole\Component\Di;
use EasySwoole\EasySwoole\SysConst;
use EasySwoole\EasySwoole\Trigger;
use EasySwoole\Http\Request;
use EasySwoole\Http\Response;

Di::getInstance()->set(
    SysConst::HTTP_EXCEPTION_HANDLER,
    function (
        \Throwable $throwable,
        Request $request,
        Response $response
    ): void {
        Trigger::getInstance()->throwable($throwable);

        if ($response->isEndResponse()) {
            return;
        }

        $response->withStatus(500);
        $response->withHeader(
            'Content-Type',
            'application/json; charset=utf-8'
        );
        $response->write(json_encode([
            'code' => 500,
            'message' => '服务器内部错误',
        ], JSON_UNESCAPED_UNICODE));
    }
);
```

配置位于服务启动阶段，修改后应重启服务。日志记录完整异常，客户端只接收稳定文案；通过 Request ID 把两者关联起来。

## 参数错误

参数处理分两类：

```text
请求无法解析 → 400
请求可以解析，但字段不符合规则 → 422
```

严格解析 JSON：

```php
try {
    $data = json_decode(
        (string) $this->request()->getBody(),
        true,
        512,
        JSON_THROW_ON_ERROR
    );
} catch (\JsonException $exception) {
    $this->writeJson(400, null, 'JSON 格式错误');
    return;
}
```

字段验证应覆盖来源、必填性、类型、长度、格式、枚举和跨字段关系。Attribute 可以减少重复代码，但数据库唯一性、余额、库存和状态流转属于业务规则，应在 Service 和数据库约束中再次保证。

客户端验证只改善交互，不能代替服务端验证。

## 404 与 405

使用显式路由时，在 `App/HttpController/Router.php` 设置回调：

```php
use EasySwoole\Http\Request;
use EasySwoole\Http\Response;

$this->setGlobalMode(true);

$this->setRouterNotFoundCallBack(
    function (Request $request, Response $response): bool {
        $response->withStatus(404);
        $response->withHeader('Content-Type', 'application/json; charset=utf-8');
        $response->write(json_encode([
            'code' => 404,
            'message' => '接口不存在',
        ], JSON_UNESCAPED_UNICODE));
        return false;
    }
);

$this->setMethodNotAllowCallBack(
    function (Request $request, Response $response): bool {
        $response->withStatus(405);
        $response->withHeader('Content-Type', 'application/json; charset=utf-8');
        $response->write(json_encode([
            'code' => 405,
            'message' => '请求方法不允许',
        ], JSON_UNESCAPED_UNICODE));
        return false;
    }
);
```

回调返回 `false` 表示响应已完成，不再进入自动控制器映射。

测试：

```bash
curl -i http://127.0.0.1:9501/not-found
curl -i -X DELETE http://127.0.0.1:9501/users
```

404 页面不要列出全部路由、控制器类名或本地文件路径。405 可按需要增加 `Allow` Header，但当前回调没有直接提供允许方法列表，项目需要自行维护或封装路由元数据。

## 限流

限流至少要考虑四个问题：

1. 限制谁：用户、API Key、可信客户端 IP 或组合键。
2. 限制哪个接口：登录、短信、上传、查询的成本不同。
3. 使用什么算法：固定窗口、滑动窗口、令牌桶。
4. 状态存在哪里：多 Worker、多实例必须使用 Redis 等共享原子存储。

超过限制时返回：

```php
$this->response()->withStatus(429);
$this->response()->withHeader('Retry-After', '60');
$this->writeJson(429, null, '请求过于频繁，请稍后重试');
return false;
```

登录接口可使用类似的键：

```text
rate:login:{accountHash}:{trustedClientIp}
```

不要直接把邮箱、手机号等隐私数据写进 Redis Key 或日志，可以先做不可逆摘要。计数与过期设置必须原子执行，可使用 Redis Lua；只执行 `INCR` 后再单独设置过期，进程异常时可能留下永不过期的键。

限流不能只存在某个 Worker 的静态数组中，否则不同 Worker 的计数互相不可见。还应限制限流 Key 的数量，避免攻击者制造无限随机 Key 消耗内存。

## 常见 Web 安全边界

### SQL 注入

使用数据库驱动的参数绑定，不把输入拼进 SQL。字段名、排序方向无法作为普通值绑定时，必须映射到服务端允许列表。

### XSS

HTML 输出按所在上下文转义。正文、HTML Attribute、JavaScript 和 URL 的转义方式不同；不要把用户内容直接拼入模板。

### CSRF

使用 Cookie 自动认证的状态修改接口需要 CSRF 防护。`SameSite` 可以降低风险，但复杂场景还应使用 CSRF Token，并验证 Origin/Referer。

### 文件与目录穿越

上传文件不信任客户端文件名、扩展名和 MIME。读取文件时通过 `realpath()` 验证最终路径仍位于允许根目录。

### 开放重定向与 SSRF

跳转目标、Webhook 地址、图片抓取地址和代理目标使用允许列表。不能只判断字符串是否包含自己的域名。

### Host Header

不要直接使用请求 Host 生成密码重置链接或签名地址。使用配置中的公开域名，并在全局 HTTP 事件中限制允许 Host。

### 密钥与日志

密钥通过环境变量或密钥服务提供并定期轮换。密码、Cookie、Authorization、身份证号等不能原样写入日志。

### 依赖与生产配置

及时更新框架和依赖，检查安全公告。生产环境关闭详细错误输出，使用 HTTPS，设置合理的请求大小、超时和并发限制。

## 上线前检查

- 未知异常是否统一返回 500，而不是堆栈？
- 400、401、403、404、405、409、422、429 是否含义清楚？
- 所有入口是否进行服务端参数验证？
- 登录、短信、上传等接口是否单独限流？
- Cookie、Session、JWT 是否具有过期、轮换和撤销策略？
- SQL、HTML、文件路径、跳转和外部 URL 是否采用安全 API 或允许列表？
- 日志是否脱敏，并可通过 Request ID 关联？
- 多 Worker、多实例下的状态是否使用共享、原子的存储？
