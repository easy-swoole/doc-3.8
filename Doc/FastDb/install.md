# 认识与安装 FastDb

FastDb 是面向 Swoole 协程环境的 MySQL 数据访问组件，组合了连接池、SQL 构建器和基于 PHP Attribute 的实体映射。它可以在 EasySwoole 框架中使用，也可以独立使用。

## 运行要求

FastDb 3.x 当前要求：

| 依赖 | 版本 |
| --- | --- |
| PHP | 8.1 或更高 |
| Swoole | 5.1 或更高 |
| `easyswoole/mysqli` | 5.x |
| `easyswoole/pool` | 3.x |
| 数据库 | MySQL |

先检查运行 EasySwoole 的 PHP CLI：

```bash
php -v
php --ri swoole
```

## 安装 3.x 正式版

在项目根目录执行：

```bash
composer require 'easyswoole/fast-db:^3.0'
```

`^3.0` 会安装兼容的 3.x 正式版。生产项目应提交 `composer.lock`，在测试环境验证后再部署，避免不同环境安装到不同版本。

确认版本和依赖：

```bash
composer show easyswoole/fast-db
composer show easyswoole/mysqli
composer show easyswoole/pool
```

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

- [FastDb 3.x](https://github.com/easy-swoole/fast-db/tree/3.x)
- [FastDb 3.x composer.json](https://github.com/easy-swoole/fast-db/blob/3.x/composer.json)
- [FastDb 3.x README](https://github.com/easy-swoole/fast-db/blob/3.x/README.md)
