{style="display:block;font-size:clamp(10.5px,.85vw,14px);line-height:1.35"}
```
  ______                          _____                              _
 |  ____|                        / ____|                            | |
 | |__      __ _   ___   _   _  | (___   __      __   ___     ___   | |   ___
 |  __|    / _` | / __| | | | |  \___ \  \ \ /\ / /  / _ \   / _ \  | |  / _ \
 | |____  | (_| | \__ \ | |_| |  ____) |  \ V  V /  | (_) | | (_) | | | |  __/
 |______|  \__,_| |___/  \__, | |_____/    \_/\_/    \___/   \___/  |_|  \___|
                          __/ |
                         |___/
```

# EasySwoole
[![Latest Stable Version](https://poser.pugx.org/easyswoole/easyswoole/v/stable)](https://packagist.org/packages/easyswoole/easyswoole)
[![Total Downloads](https://poser.pugx.org/easyswoole/easyswoole/downloads)](https://packagist.org/packages/easyswoole/easyswoole)
[![Latest Unstable Version](https://poser.pugx.org/easyswoole/easyswoole/v/unstable)](https://packagist.org/packages/easyswoole/easyswoole)
[![License](https://poser.pugx.org/easyswoole/easyswoole/license)](https://packagist.org/packages/easyswoole/easyswoole)
[![Monthly Downloads](https://poser.pugx.org/easyswoole/easyswoole/d/monthly)](https://packagist.org/packages/easyswoole/easyswoole)

EasySwoole 是一款基于 Swoole Server 开发的常驻内存型的分布式 PHP 框架，专为 API 而生，摆脱传统 PHP 运行模式在进程唤起和文件加载上带来的性能损失。
EasySwoole 高度封装了 Swoole Server 而依旧维持 Swoole Server 原有特性，支持同时混合监听 HTTP、自定义 TCP、UDP 协议，让开发者以最低的学习成本和精力编写出多进程、可异步、高可用的应用服务。


## 生产可用
EasySwoole 从最早的前身 EasyPHP-Swoole，到更名为 EasySwoole，再到现如今的 EasySwoole 3.x 版本，多年时间在众多社区小伙伴的共同努力下，EasySwoole 的稳定与可靠已经经历了非常多的大企业检验。

例如：

- 腾讯公司的 IEG 部门
- WEGAME 部门
- 网宿科技（国内 CDN 厂家）
- 360 金融
- 360 小游戏（Actor）
- 9377 小游戏
- 厦门美图网
- 蝉大师
- 宝宝巴士
- 瑞祥科技集团

等公司都在使用 EasySwoole。

## 特性

- 强大的 TCP/UDP Server 框架，多线程，EventLoop，事件驱动，异步，Worker 进程组，Task 异步任务，毫秒定时器，SSL/TLS 隧道加密
- EventLoop API，让用户可以直接操作底层的事件循环，将 Socket、Stream、管道等 Linux 文件加入到事件循环中
- 定时器、协程对象池、HTTP/SOCKET 控制器、分布式微服务、RPC 支持

## 优势

- 简单易用开发效率高
- 并发百万 TCP 连接
- TCP/UDP/UnixSocket
- 支持异步/同步/协程
- 支持多进程/多线程
- CPU 亲和性/守护进程

## 主要能力

### HTTP 服务

框架提供控制器、路由、请求与响应对象，以及服务事件等能力，可用于构建网站接口和 REST API。控制器负责处理具体请求；路由负责将 URL 映射到处理逻辑；事件允许在请求进入或服务启动等时机加入应用行为。详见 [HTTP 服务](/Http/Basics/start.md)。

### Socket 服务

依托 Swoole 的网络服务能力，并结合 `easyswoole/socket` 组件，可以构建 WebSocket、TCP 和 UDP 服务，处理长连接、双向通信或自定义协议。详见 [Socket 服务](/Socket/index.md)。

### 后台任务与进程

对于不适合在 HTTP 请求中完成的工作，可以使用异步任务；对于周期性工作，可以使用定时器或 Crontab；需要独立运行的业务逻辑，则可以放入自定义进程。相关用法从 [异步任务](/Advanced/task.md) 开始阅读。

### 可组合的组件

EasySwoole 的框架核心与独立组件可以按需组合。数据库访问可使用 [FastDb](/FastDb/install.md)，资源复用可使用[连接池](/Library/Pool/index.md)；客户端、队列、链路追踪等功能也有各自的组件文档。它们并非创建框架项目后全部自动安装，使用时应按照对应章节引入和配置。

## 适合的应用

EasySwoole 可用于 HTTP API 服务、需要实时推送的 WebSocket 应用、使用 TCP/UDP 自定义协议的服务，以及包含定时任务或后台处理流程的系统。选择具体能力时，可以先实现一个最小的 HTTP 服务，再根据业务需求增加 Socket 服务、持久化和其他组件。

## 联系作者

- 作者：如果的如果
- 邮箱：[admin@fosuss.com](mailto:admin@fosuss.com)
- QQ：291323003
- 微信：扫描下方二维码

![EasySwoole 作者微信二维码](/Images/authWx.jpg){style="display:block;width:220px;margin:0 auto"}


## 从哪里开始

初次使用建议依次阅读[环境要求](/QuickStart/environment.md)、[安装框架](/QuickStart/install.md)和[第一个 HTTP 接口](/QuickStart/helloworld.md)。如果希望理解命令解析、事件注册到服务启动的内部过程，可以继续阅读[框架设计](/FrameworkDesign/index.md)。

项目源码：[EasySwoole 3.x](https://github.com/easy-swoole/easyswoole/tree/3.x)。

