# 模板引擎：安装与工作原理

`easyswoole/template` 2.x 不是一种新的模板语法，而是**渲染进程与协程请求之间的桥梁**。应用实现 `RenderInterface`，在独立进程中调用自己选择的模板引擎；HTTP 控制器通过 Unix Socket 取得渲染后的 HTML 字符串。这让不适合在多个协程中共享状态的 PHP 模板引擎不必直接在 HTTP Worker 中执行。

## 安装前确认

在 EasySwoole **应用项目根目录**执行：

```bash
php -v
php --ri swoole
composer require 'easyswoole/template:^2.0'
composer show easyswoole/template
```

组件需要 PHP 8.1 及以上、Swoole，以及项目中的 `easyswoole/component` 2.x。安装组件**不会自动安装 Plates、Smarty 或 Blade**；实际模板引擎要另装。下一章用 Plates 演示，再执行：

```bash
composer require 'league/plates:^3.6'
```

`composer require` 只在自己的应用项目中运行，不需要在本文档站点项目中安装。新增类和模板文件的具体位置见[在框架中渲染页面](/Library/Template/integration.md)。

## 一次渲染如何完成

```text
浏览器请求 /template-demo
  → HTTP 控制器调用 TemplateRender::getInstance()->render('hello', $data)
  → 组件选中一个 RenderWorker，经 Unix Socket 发送模板名、数据和选项
  → RenderWorker 调用应用实现的 RenderInterface::render()
  → 模板引擎生成 HTML，组件把字符串传回控制器
  → 控制器设置 Content-Type 并写入 HTTP 响应
```

`Render` 在服务启动前通过 `attachServer()` 注册渲染进程。每个渲染进程有独立的 Socket，进程内部按顺序处理渲染请求；`workerNum` 增加的是**渲染进程数**，不是 HTTP Worker 数。渲染器对象在渲染进程中使用，切勿把持有请求、响应或协程上下文的对象传入模板数据。

## 三个核心对象

| 对象 | 由谁创建 | 负责什么 |
| --- | --- | --- |
| `RenderInterface` 实现类 | 应用 | 根据模板名和数据生成 `string\|null`；处理本次渲染异常 |
| `Render` | 应用 | 保存配置、注册渲染进程、提供 `render()` 客户端入口 |
| `RenderWorker` | 组件 | 监听 Unix Socket，在独立进程中执行渲染器 |

2.x 的 `Render` 本身**不提供** `getInstance()`。在框架项目中需要一个固定入口时，可以定义子类并 `use EasySwoole\Component\Singleton`，而不是自行写静态属性；下一章给出完整代码。`Singleton` 只保证**当前进程内**的实例，跨进程通信仍依靠组件的 Unix Socket。

下一章：[在框架中渲染页面](/Library/Template/integration.md)。

## 源码依据

- [template 2.x README](https://github.com/easy-swoole/template/blob/2.x/README.md)
- [Render.php](https://github.com/easy-swoole/template/blob/2.x/src/Render.php)
- [RenderInterface.php](https://github.com/easy-swoole/template/blob/2.x/src/RenderInterface.php)
