# SMTP Client 发送文本与 HTML 邮件

## 发送流程

一封邮件的基本发送顺序如下：

```text
创建新的 Mailer
  → 设置发件人和收件人
  → 创建 Text 或 Html
  → 设置主题和正文
  → 调用 send()
  → 处理 Response 或异常
```

## 发送纯文本邮件

```php
use App\Utility\SmtpMailerFactory;
use EasySwoole\Smtp\Request\Text;

$mailer = SmtpMailerFactory::create();
$mailer->setFrom('notice@example.com', '示例商城');
$mailer->addAddress('alice@example.com', 'Alice');

$message = new Text();
$message->setSubject('验证码通知');
$message->setBody("您的验证码是 538921，5 分钟内有效。\n如非本人操作，请忽略本邮件。");

$mailer->send($message);
```

`Text` 默认使用 `text/plain`，适合验证码、告警和不需要排版的通知。

## 发送 HTML 邮件

```php
use App\Utility\SmtpMailerFactory;
use EasySwoole\Smtp\Request\Html;

$mailer = SmtpMailerFactory::create();
$mailer->setFrom('notice@example.com', '示例商城');
$mailer->setReplyTo('support@example.com', '客户支持');
$mailer->addAddress('alice@example.com', 'Alice');

$message = new Html();
$message->setSubject('订单支付成功');
$message->setBody(<<<'HTML'
<!doctype html>
<html lang="zh-CN">
<body>
    <h1>支付成功</h1>
    <p>订单 <strong>NO202610150001</strong> 已支付成功。</p>
    <p>感谢您的购买。</p>
</body>
</html>
HTML);

$mailer->send($message);
```

`Html` 默认使用 `text/html`。邮件客户端通常会过滤 JavaScript、表单和部分 CSS，重要样式建议使用简单的行内 CSS，不要依赖前端框架。

## 在控制器中发送

```php
<?php

namespace App\HttpController;

use App\Utility\SmtpMailerFactory;
use EasySwoole\EasySwoole\Logger;
use EasySwoole\Http\AbstractInterface\Controller;
use EasySwoole\Smtp\Exception\Exception as SmtpException;
use EasySwoole\Smtp\Request\Text;
use Throwable;

final class VerificationCode extends Controller
{
    public function send(): void
    {
        $email = (string) $this->request()->getRequestParam('email');

        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
            $this->writeJson(400, null, '邮箱格式不正确');
            return;
        }

        $message = new Text();
        $message->setSubject('登录验证码');
        $message->setBody('您的验证码是 538921，5 分钟内有效。');

        try {
            $mailer = SmtpMailerFactory::create();
            $mailer->setFrom('notice@example.com', '示例应用');
            $mailer->addAddress($email);
            $mailer->send($message);

            $this->writeJson(200, null, '邮件已发送');
        } catch (SmtpException $error) {
            // 记录内部错误，不要把账号、授权码或完整异常直接返回给客户端。
            Logger::getInstance()->error($error->getMessage(), 'smtp');
            $this->writeJson(502, null, '邮件发送失败，请稍后重试');
        } catch (Throwable $error) {
            Logger::getInstance()->error($error->getMessage(), 'smtp');
            $this->writeJson(500, null, '服务暂时不可用');
        }
    }
}
```

SMTP 是网络操作，不建议让用户请求无限等待。应设置超时，并根据业务需求把邮件发送放入异步任务；接口只负责生成任务，Task Worker 完成实际发送。异步任务的定义方式参见[异步任务](/Advanced/task.md)。

## 发件地址的含义

```php
$mailer->setUsername('notice@example.com');
$mailer->setFrom('service@example.com', '客户服务');
```

在 3.x 中，`setFrom()` 同时设置 SMTP 信封发件人和邮件头中的展示地址；没有调用 `setFrom()` 时，两者才默认使用 `username`。

邮件服务商可能要求发件地址与登录账号相同，或者要求发件地址属于已验证域名。即使组件允许设置不同地址，服务端仍可能拒绝投递或把邮件归类为垃圾邮件。

下一章：[收件人、抄送与附件](/Client/Smtp/attachment.md)。
