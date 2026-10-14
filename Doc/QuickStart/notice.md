# 开发者必读

## 常驻内存不是 PHP-FPM

Worker 启动后，已加载的类、静态属性、单例和全局变量会持续存在。不要假设一次请求结束后所有状态都会自动清空。

```php
// 错误示例：不同请求会共享并累加
private static array $currentUser = [];
```

请求级数据应放在局部变量、请求对象或协程上下文中，并在生命周期结束时释放。

## 多进程之间不共享普通内存

每个 Worker 都有自己的 PHP 内存空间。修改某个 Worker 的数组、单例或配置，不会自动传播到其他 Worker。跨进程共享应使用数据库、Redis、Swoole Table、消息队列或明确的 IPC 机制。

## 注意协程安全

同一 Worker 可以交错执行多个协程。以下对象不应被并发请求随意复用：

- 保存“当前用户”等请求状态的单例。
- 没有连接池保护的数据库连接。
- 可变的全局 Request/Response 引用。
- 非协程安全的第三方客户端。

框架默认模板调用：

```php
Coroutine::set(['hook_flags' => SWOOLE_HOOK_TCP]);
```

Hook 能力取决于 Swoole 版本和编译选项。启用 Hook 不代表任意扩展或 SDK 都自动变得协程安全。

## 阻塞操作

Worker 中执行长时间 CPU 计算或未被 Hook 的阻塞 I/O 会影响同一 Worker 处理其他请求。CPU 密集任务应考虑 Task Worker、独立进程或外部队列。

## 代码更新

PHP 文件修改后，已运行 Worker 不会像 PHP-FPM 一样在下一请求自动重新加载。开发或发布时执行：

```bash
php easyswoole.php server reload
```

主服务监听配置等启动期变更需要完整重启。

## 异常与日志

不要在生产接口中直接输出完整堆栈。控制器可以覆盖 `onException()`，将详细信息写入日志，对客户端返回稳定错误结构。

## 源码依据

- [EasySwoole Core](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Core.php)
- [EasySwooleEvent 模板](https://github.com/easy-swoole/easyswoole/blob/3.x/src/Resource/EasySwooleEvent._php)
