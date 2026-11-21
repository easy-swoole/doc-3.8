# HTTP 服务常见问题

## 请求连不上或返回 404

先按[安装、启动与访问排错](/QuickStart/problem.md)确认服务正在监听，再核对 URL、路由和控制器。收到 404 表示已取得 HTTP 响应，排查时可先跳过扩展安装和端口监听，直接检查[访问接口返回 404](/QuickStart/problem.md#访问接口返回-404)。

## 改了代码没有生效

根据改动属于 Worker 业务代码还是主进程配置，选择重载或完整重启。参见[修改后没有生效](/QuickStart/problem.md#修改后没有生效)。

## 请求之间串数据

检查是否把用户、请求参数或响应对象存在静态属性或单例中。将这些数据放到方法局部变量、请求对象或协程上下文，并在请求结束时清理上下文。用两个不同身份重复请求，确认响应只包含当前请求的数据。参见[会话与状态](/Http/State/index.md)和[IOC 与上下文](/Component/ioc-context.md)。

## 经过代理后 IP 或 HTTPS 判断不正确

先分别请求后端和代理入口，确认代理有没有传递协议和客户端地址。按[反向代理部署](/Http/Advanced/proxy.md)检查转发配置，再按[URI 与客户端信息](/Http/Request/uri-client.md)核对应用对代理头的读取和信任范围。

## 上传触发 413、超时或文件为空

用同一个文件分别请求后端和代理入口，定位在哪一层失败。逐层检查代理请求体限制、Swoole 大小限制和应用上传校验，修改后用同一文件重试。参见[大文件上传](/Http/File/large-upload.md)和[文件校验与保存](/Http/File/validate-save.md)。

## 版本与 GitHub

- [`easyswoole/easyswoole` 3.8.2 · GitHub](https://github.com/easy-swoole/easyswoole/tree/3.8.2)
- [`easyswoole/http` 3.2.1 · GitHub](https://github.com/easy-swoole/http/tree/3.2.1)
