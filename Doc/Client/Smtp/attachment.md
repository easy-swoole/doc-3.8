# SMTP Client 收件人、抄送与附件

## 多个收件人

重复调用 `addAddress()` 可以增加多个主收件人：

```php
$mailer->addAddress('alice@example.com', 'Alice');
$mailer->addAddress('bob@example.com', 'Bob');
```

第二个参数是显示名称，可以省略。

## 抄送和密送

```php
$mailer->addCc('manager@example.com', '部门主管');
$mailer->addBcc('audit@example.com', '审计邮箱');
```

- `addCc()` 添加抄送人，其他收件人可以在邮件头中看到该地址。
- `addBcc()` 添加密送人，组件会将该地址加入 SMTP 投递列表，但不会写进邮件头。

可以同时使用主收件人、抄送和密送：

```php
use App\Utility\SmtpMailerFactory;
use EasySwoole\Smtp\Request\Html;

$mailer = SmtpMailerFactory::create();
$mailer->setFrom('notice@example.com', '财务系统');
$mailer->setReplyTo('finance@example.com', '财务部');
$mailer->addAddress('alice@example.com', 'Alice');
$mailer->addCc('manager@example.com', '部门主管');
$mailer->addBcc('audit@example.com');

$message = new Html();
$message->setSubject('月度账单');
$message->setBody('<h1>月度账单</h1><p>账单文件请查看附件。</p>');

$mailer->send($message);
```

## 添加附件

`Text` 和 `Html` 都支持附件：

```php
$message->addAttachment(
    EASYSWOOLE_ROOT . '/Temp/invoice-202610.pdf',
    '2026年10月账单.pdf'
);
```

第一个参数是服务器上的实际文件路径，第二个参数是收件人看到的附件名。省略第二个参数时使用原文件名：

```php
$message->addAttachment(EASYSWOOLE_ROOT . '/Temp/report.csv');
```

3.x 支持发送内容为空的文件；只要路径指向可读取的普通文件，空文件不会被误判为读取失败。无法识别的文件扩展名会使用 `application/octet-stream`。

重复调用可以添加多个附件：

```php
$message->addAttachment(EASYSWOOLE_ROOT . '/Temp/report.pdf');
$message->addAttachment(EASYSWOOLE_ROOT . '/Temp/detail.csv');
```

## 附件发送前检查

不要把用户传入的任意路径直接交给 `addAttachment()`。应由业务代码确定允许访问的目录，并在发送前检查文件：

```php
$file = EASYSWOOLE_ROOT . '/Temp/invoice-202610.pdf';

if (!is_file($file) || !is_readable($file)) {
    throw new RuntimeException('附件不存在或不可读');
}

if (filesize($file) > 10 * 1024 * 1024) {
    throw new RuntimeException('附件不能超过 10 MB');
}

$message->addAttachment($file, '账单.pdf');
```

组件发送附件时会读取整个文件并构造 MIME 内容，二进制附件会使用 Base64 编码。大附件会占用较多 Worker 内存，而且编码后体积还会增加。大文件更适合上传到对象存储后在邮件中提供带过期时间的下载链接。

`Mailer::setMaxPackage()` 设置的是 Swoole 客户端接收 SMTP 响应时允许的数据包上限，不等同于附件大小限制；附件上限应由应用和邮件服务商共同约束。

## 常驻内存下不要复用收件人状态

下面的写法不适合 EasySwoole Worker：

```php
// 错误示意：全局对象中的收件人会不断累积。
$sharedMailer->addAddress('alice@example.com');
$sharedMailer->send($message);

$sharedMailer->addAddress('bob@example.com');
$sharedMailer->send($message); // 此时对象中仍然保留 Alice。
```

每封邮件都创建新的 `Mailer` 和消息对象：

```php
$mailer = SmtpMailerFactory::create();
$mailer->addAddress('bob@example.com');

$message = new Html();
$message->setSubject('独立邮件');
$message->setBody('<p>本邮件只发送给 Bob。</p>');

$mailer->send($message);
```

下一章：[响应、异常与常见问题](/Client/Smtp/error.md)。
