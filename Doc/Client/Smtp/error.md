# SMTP Client 响应、异常与常见问题

`Mailer` 支持返回响应和抛出异常两种错误处理方式，由构造参数或 `setEnableException()` 决定。

## 推荐：异常模式

```php
use EasySwoole\Smtp\Exception\Exception as SmtpException;
use EasySwoole\Smtp\Mailer;
use EasySwoole\EasySwoole\Logger;

$mailer = new Mailer(true);

try {
    $mailer->send($message);
} catch (SmtpException $error) {
    Logger::getInstance()->error($error->getMessage(), 'smtp');
}
```

也可以在创建后开启：

```php
$mailer = new Mailer();
$mailer->setEnableException(true);
```

异常模式适合业务代码，可以统一进入 `catch`，但异常消息只表示失败阶段，不包含 SMTP 服务端返回的完整原始文本。附件不存在、不是普通文件或不可读属于邮件内容构建错误，无论是否开启异常模式都会抛出 `EasySwoole\Smtp\Exception\Exception`。

## Response 模式

构造函数默认关闭异常。`send()` 始终返回 `Response`，必须检查状态码，不能只判断是否返回对象：

```php
use EasySwoole\Smtp\Mailer;
use EasySwoole\Smtp\Protocol\Response;
use EasySwoole\EasySwoole\Logger;

$mailer = new Mailer(false);
$response = $mailer->send($message);

if ($response->getStatus() !== Response::STATUS_OK) {
    Logger::getInstance()->error(sprintf(
        'SMTP failed, status=%d, message=%s',
        $response->getStatus(),
        $response->getMsg()
    ), 'smtp');
}
```

发送成功时 `getStatus()` 返回 `0`，`getMsg()` 返回 `ok.`。业务判断仍建议使用 `Response::STATUS_OK`，不要依赖消息文本。

## 状态码

| 状态码 | 常量 | 含义 |
| --- | --- | --- |
| `0` | `STATUS_OK` | 发送成功 |
| `101` | `STATUS_CONNECT_TIMEOUT` | 连接 SMTP 服务器失败或超时 |
| `102` | `STATUS_NOT_SMTP_PROTOCOL` | 连接后没有收到 SMTP `220` 响应 |
| `103` | `STATUS_RECEIVE_TIMEOUT` | 读取 SMTP 响应超时 |
| `201` | `STATUS_IDENTIFY_SENDER_ERROR` | `EHLO` 阶段失败 |
| `202` | `STATUS_AUTH_MODE_ERROR` | 服务端不接受 `AUTH LOGIN` |
| `203` | `STATUS_USERNAME_ERROR` | 用户名验证阶段失败 |
| `204` | `STATUS_PASSWORD_ERROR` | 密码或授权码验证失败 |
| `205` | `STATUS_FROM_MAIL_ERROR` | SMTP 信封发件人被拒绝 |
| `206` | `STATUS_RCPT_MAIL_ERROR` | 某个收件人地址被拒绝 |
| `207` | `STATUS_DATA_START_ERROR` | 服务端拒绝开始接收邮件内容 |
| `208` | `STATUS_DATA_END_ERROR` | 邮件内容提交失败 |
| `209` | `STATUS_QUIT_ERROR` | 退出 SMTP 会话失败 |

## 超时和数据包配置

```php
$mailer->setTimeout(5);
$mailer->setMaxPackage(2 * 1024 * 1024);
```

- `setTimeout()` 同时用于连接和读取响应，单位为秒。
- `setMaxPackage()` 设置 SMTP 响应的数据包上限，默认 2 MB。

生产环境应设置有限超时。邮件发送失败时，可以记录任务 ID、邮件类型、收件域名和状态码，但不要记录授权码、完整验证码或完整邮件正文。

## 常见问题

### 提示密码验证失败

确认使用的是服务商生成的 SMTP 授权码，而不是网页邮箱登录密码；同时检查 SMTP 服务是否已经在邮箱控制台开启。

### 465 可以连接，587 无法发送

465 通常使用连接即加密的隐式 SSL；587 通常要求先建立普通连接，再执行 STARTTLS。当前组件支持隐式 SSL，但没有实现 STARTTLS 升级。应选择服务商提供的隐式 SSL 端口。

### 在 CLI 中出现协程相关错误

组件内部使用 `Swoole\Coroutine\Client`。独立 PHP 脚本必须在 `Swoole\Coroutine\run()` 中调用；EasySwoole 控制器和协程 Task 中可以直接使用。

### 同一封邮件被发送给了旧收件人

`Mailer` 会保存已经添加的 To、Cc 和 Bcc 地址，并且没有公开的清空方法。不要把它注册为跨请求单例；每封邮件创建一个新实例。

### 附件发送时 Worker 内存明显上升

附件会一次性读入内存，再编码到 MIME 内容中。限制附件大小；较大的文件应使用对象存储下载链接。

### 接口响应变慢

SMTP 包含连接、登录和传输过程。对实时性要求不高的邮件，应投递到 EasySwoole Task，由 Task Worker 异步发送，并为失败任务设置有限次数的重试。

相关章节：[异步任务](/Advanced/task.md)。
