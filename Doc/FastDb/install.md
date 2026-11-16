# 认识与安装 FastDb

FastDb 是面向 Swoole 协程环境的 MySQL 数据访问组件，组合了连接池、SQL 构建器和基于 PHP Attribute 的实体映射。它可以在 EasySwoole 框架中使用，也可以独立使用。

## 运行要求

本文档以 FastDb 3.1.1 为准，运行要求如下：

| 依赖 | 版本 |
| --- | --- |
| PHP | 8.1 或更高 |
| Swoole | 5.1 或更高 |
| `easyswoole/mysqli` | ^5.1，实体查询使用 5.1.6 起提供的接口 |
| `easyswoole/pool` | 3.x |
| `easyswoole/spl` | ^2.2 |
| 数据库 | MySQL |

先检查运行 EasySwoole 的 PHP CLI：

```bash
php -v
php --ri swoole
```

## 安装 FastDb

在项目根目录执行：

```bash
composer require 'easyswoole/fast-db:^3.1.1'
```

`^3.1.1` 会安装 3.1.1 或兼容的后续 3.x 正式版。生产项目应提交 `composer.lock`，在测试环境验证后再部署，避免不同环境安装到不同版本。

确认版本和依赖：

```bash
composer show easyswoole/fast-db
composer show easyswoole/mysqli
composer show easyswoole/pool
```

## 从旧版本迁移

升级到 FastDb 3.1.1 时，需要在实体中单独指定主键。将旧的 `#[Property(isPrimaryKey: true)]` 拆成 `#[Property]` 和 `#[PrimaryKey]`。如果数据库列使用 `AUTO_INCREMENT`，再加上 `#[AutoIncrement]`，以便插入后回填生成的值。每个实体最多声明一个主键，属性名应与数据库主键列名一致。

```php
use EasySwoole\FastDb\Attributes\AutoIncrement;
use EasySwoole\FastDb\Attributes\PrimaryKey;
use EasySwoole\FastDb\Attributes\Property;

// 在实体类中声明，示例对应自增主键 id。
#[Property]
#[PrimaryKey]
#[AutoIncrement]
public int $id;
```

完成主键映射后，`findRecord($id)`、实体 `update()` 和 `delete()` 会按指定的主键定位记录。迁移时保留原有数据库主键，并按[实体与字段映射](/FastDb/entity.md)检查其他模型的声明。

## 推荐目录

```text
项目根目录
├── App
│   ├── HttpController
│   └── Model
│       └── User.php
├── EasySwooleEvent.php
├── dev.php
├── produce.php
└── easyswoole.php
```

后续步骤为：

```text
安装组件
  → 在运行模式配置中增加 FAST_DB
  → EasySwooleEvent::initialize() 注册连接
  → 定义 Attribute 实体
  → 在控制器或 Service 中查询
```

## 源码依据

- [FastDb 3.1.1](https://github.com/easy-swoole/fast-db/tree/3.1.1)
- [FastDb 3.1.1 composer.json](https://github.com/easy-swoole/fast-db/blob/3.1.1/composer.json)
- [FastDb 3.1.1 README](https://github.com/easy-swoole/fast-db/blob/3.1.1/README.md)
