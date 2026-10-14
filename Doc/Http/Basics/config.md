# 服务配置

HTTP 监听地址、端口及 Swoole 参数放在项目配置中，业务代码通过 `Config::getInstance()->getConf()` 读取。

```php
use EasySwoole\EasySwoole\Config;

$port = Config::getInstance()->getConf('MAIN_SERVER.PORT');
```

常调参数包括 `SERVER_NAME`、`LISTEN_ADDRESS`、`PORT`、`SERVER_TYPE` 和 `SETTING` 下的 `worker_num`、`max_request`、上传限制等。环境差异应拆为独立配置或环境变量，密钥不要提交到仓库。修改进程级配置后应完整重启服务。
