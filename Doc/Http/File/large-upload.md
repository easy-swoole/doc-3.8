# 大文件上传

单次上传会同时受到反向代理、Swoole 和应用限制。先检查 Nginx `client_max_body_size`、Swoole 请求大小配置、超时、磁盘空间和临时目录；不要只修改其中一层。

更大的文件建议分片：

```text
1. POST /uploads/init       → 返回 uploadId、chunkSize
2. PUT  /uploads/{id}/parts/{number} → 保存分片并校验哈希
3. POST /uploads/{id}/complete       → 校验清单、合并、核对整文件哈希
4. DELETE /uploads/{id}              → 取消并清理
```

每个分片使用 `uploadId + number` 作为幂等键，重复上传应覆盖或直接返回成功。服务端必须限制文件总大小、分片大小/数量、并发数、用户配额和 uploadId 所有权；不能相信客户端声明的总大小或哈希。

合并时使用流式复制，不要把所有分片读入一个 PHP 字符串。完成后验证 SHA-256、原子移动到正式目录并写入数据库。定时任务清理超时分片；多实例部署时使用共享对象存储或确保同一 uploadId 固定到同一存储节点。

能使用对象存储时，推荐由应用鉴权后签发短期上传 URL，让客户端直传，再通过回调或完成接口确认结果，减少 HTTP Worker 和本机磁盘压力。
