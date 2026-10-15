# SMTP Client 安装与配置

`easyswoole/smtp` 3.x 是基于 `Swoole\Coroutine\Client` 实现的 SMTP 客户端，可用于发送验证码、注册通知、订单通知和告警邮件。

## 运行结构

发送一封邮件需要准备两类对象：

```text
Mailer：负责连接 SMTP 服务器、登录和指定收发件人
   +
Text/Html：负责主题、正文、字符集和附件
   ↓
Mailer::send()
   ↓
Response 或 Smtp Exception
```

`Mailer` 保存服务器配置和收件人信息，`Text`、`Html` 保存具体邮件内容。调用 `send()` 时组件会创建一个 SMTP 连接，完成登录、发送和退出流程。

## 环境要求

- PHP 8.1 及以上。
- Swoole 5.1 及以上。
- PHP `mbstring` 扩展。
- 发送代码必须运行在 Swoole 协程环境中。

```bash
php -v
php --ri swoole
php --ri mbstring
```

## 安装

在项目根目录执行：

```bash
composer require easyswoole/smtp:"3.x"
composer show easyswoole/smtp
```

组件通过 Composer 自动加载，不需要在 `EasySwooleEvent.php` 中注册。

## 准备 SMTP 账号

不同邮件服务商的地址和端口不同。以服务商控制台显示的配置为准，常见配置如下：

| 配置 | 示例 | 说明 |
| --- | --- | --- |
| Host | `smtp.qq.com` | SMTP 服务器地址 |
| Port | `465` | 常用于隐式 SSL |
| SSL | `true` | 连接建立时立即启用 TLS |
| Username | `notice@example.com` | 通常是完整邮箱地址 |
| Password | 邮箱授权码 | 通常不是网页登录密码 |

组件的 `setSsl(true)` 使用的是隐式 SSL，适合服务商明确提供的 SSL 端口。当前版本没有实现 STARTTLS 升级，因此只提供 587/STARTTLS 的服务不能直接使用该模式。非加密 SMTP 端口应设置 `setSsl(false)`，但生产环境不建议通过公网发送明文凭据。

## 写入项目配置

在项目根目录的 `dev.php`、`produce.php` 中增加：

```php
return [
    // 其他配置……
    'SMTP' => [
        'host' => 'smtp.qq.com',
        'port' => 465,
        'ssl' => true,
        'username' => 'notice@example.com',
        'password' => getenv('SMTP_PASSWORD'),
        'timeout' => 5,
    ],
];
```

密码和授权码不要提交到 Git 仓库，生产环境应从环境变量或密钥管理服务读取。

## 创建 Mailer 工厂

新建 `App/Utility/SmtpMailerFactory.php`，集中读取配置：

```php
<?php

namespace App\Utility;

use EasySwoole\EasySwoole\Config;
use EasySwoole\Smtp\Mailer;
use RuntimeException;

final class SmtpMailerFactory
{
    public static function create(): Mailer
    {
        $config = Config::getInstance()->getConf('SMTP');

        if (!is_array($config) || empty($config['host'])) {
            throw new RuntimeException('SMTP 配置不存在');
        }

        // true 表示发送失败时抛出 Smtp Exception。
        $mailer = new Mailer(true);
        $mailer->setHost((string) $config['host']);
        $mailer->setPort((int) ($config['port'] ?? 465));
        $mailer->setSsl((bool) ($config['ssl'] ?? true));
        $mailer->setUsername((string) $config['username']);
        $mailer->setPassword((string) $config['password']);
        $mailer->setTimeout((int) ($config['timeout'] ?? 5));

        return $mailer;
    }
}
```

每次发送都通过工厂创建一个新的 `Mailer`。组件会把 `addAddress()`、`addCc()` 和 `addBcc()` 添加的地址保存在对象中，却没有清空地址的方法。在常驻内存的 Worker 中把一个 `Mailer` 单例反复复用，后续邮件可能带上前一次的收件人。

## 非 EasySwoole 脚本中运行

EasySwoole 控制器、Task 和协程回调本身处于协程环境。单独编写 CLI 测试脚本时，需要主动创建协程容器：

```php
use Swoole\Coroutine;

Coroutine\run(function (): void {
    // 在这里创建 Mailer 并发送邮件。
});
```

下一章：[发送文本与 HTML 邮件](/Client/Smtp/send.md)。
