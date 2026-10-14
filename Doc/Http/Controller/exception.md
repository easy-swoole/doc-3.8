# 异常与错误处理

控制器内抛出的异常会进入 `onException()`。建议把参数错误、业务错误和系统错误转换成一致的响应格式。

## 定义业务异常

```php
<?php

namespace App\Exception;

use RuntimeException;

class BusinessException extends RuntimeException
{
    public function __construct(
        string $message,
        public readonly int $httpStatus = 400,
        public readonly string $errorCode = 'BUSINESS_ERROR'
    ) {
        parent::__construct($message);
    }
}
```

## 控制器统一处理

```php
use App\Exception\BusinessException;
use EasySwoole\EasySwoole\Trigger;
use EasySwoole\HttpAnnotation\Exception\ParamValidateFail;
use EasySwoole\HttpAnnotation\Exception\RequestMethodNotAllow;

protected function onException(\Throwable $throwable): void
{
    if ($throwable instanceof ParamValidateFail) {
        $message = $throwable->getFailRule()
            ->errorMsg($throwable->getParamName());
        $this->writeJson(422, null, $message);
        return;
    }

    if ($throwable instanceof RequestMethodNotAllow) {
        $this->writeJson(405, null, 'Method Not Allowed');
        return;
    }

    if ($throwable instanceof BusinessException) {
        $this->writeJson(
            $throwable->httpStatus,
            ['errorCode' => $throwable->errorCode],
            $throwable->getMessage()
        );
        return;
    }

    Trigger::getInstance()->throwable($throwable);
    $this->writeJson(500, null, '服务器内部错误');
}
```

不要把堆栈、数据库信息或磁盘路径直接返回给生产客户端。

## 404 Action

```php
protected function actionNotFound(?string $action)
{
    $this->writeJson(404, null, "Action {$action} not found");
}
```

Router 没有命中与控制器 Action 不存在是两个阶段。全局路由模式下，还可以通过 `setRouterNotFoundCallBack()` 设置路由级 404。

## 全局 HTTP 异常

Dispatcher 支持 `setHttpExceptionHandler()`。它适合处理控制器构造前、路由回调或 Dispatcher 层异常；控制器的 `onException()` 负责控制器生命周期内部异常。

## 状态码建议

| 场景 | 状态码 |
| --- | --- |
| 参数格式或 JSON 错误 | 400 |
| 未认证 | 401 |
| 无权限 | 403 |
| 资源或 Action 不存在 | 404 |
| HTTP 方法错误 | 405 |
| 业务校验不通过 | 422 |
| 未预期服务端异常 | 500 |

状态码与业务 `errorCode` 分开：HTTP 状态表达协议结果，业务码用于客户端精确处理。

## 源码依据

- [Controller 异常流程](https://github.com/easy-swoole/http/blob/3.x/src/AbstractInterface/Controller.php)
- [Dispatcher 异常处理](https://github.com/easy-swoole/http/blob/3.x/src/Dispatcher.php)
- [ParamValidateFail](https://github.com/easy-swoole/http-annotation/blob/4.x/src/Exception/ParamValidateFail.php)
