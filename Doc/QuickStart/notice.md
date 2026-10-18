# 开发者必读

## 文件路径不要依赖当前工作目录

本地前台启动时，相对路径可能碰巧从项目根目录解析；使用 `php easyswoole.php server start -d` 后，Swoole 守护进程的当前工作目录可能变化，代码中的 `./Config`、`Temp/cache.json` 就可能指向错误位置。**这是工作目录变化，不是 `-d` 自动启用了 `chroot`。**

在控制器、事件或任务中，用框架常量构造绝对路径：

```php
$projectFile = EASYSWOOLE_ROOT . '/Config/business.php';
$temporaryFile = EASYSWOOLE_TEMP_DIR . '/business-cache.json';
```

`EASYSWOOLE_ROOT` 是项目根目录；`EASYSWOOLE_TEMP_DIR` 是已初始化的临时目录，默认对应项目下的 `Temp`，也可能由 `TEMP_DIR` 配置改到其他绝对路径。框架定义的是 **`EASYSWOOLE_TEMP_DIR`**，不是 `EASYSWOOLE_TMP_DIR`。配置文件加载发生在临时目录初始化之前，因此在 `dev.php`、`produce.php` 中设置目录时使用 `EASYSWOOLE_ROOT`，不要提前使用 `EASYSWOOLE_TEMP_DIR`。详情见[基础管理命令](/QuickStart/command.md)与[配置文件](/QuickStart/config.md)。

如果另外显式配置了 Swoole 的 `chroot`，那是真正的文件系统根目录隔离；还需确认这些绝对路径在隔离后的进程中可见，不能只靠改用常量解决。

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
