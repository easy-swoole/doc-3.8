# 文件校验与保存

安全流程是：检查上传错误 → 限制大小 → 检查真实 MIME → 映射服务端扩展名 → 生成随机文件名 → 移动 → 保存文件记录。

```php
public function avatar(): void
{
    $file = $this->request()->getUploadedFile('avatar');
    if ($file === null || $file->getError() !== UPLOAD_ERR_OK) {
        $this->writeJson(422, null, '文件上传失败');
        return;
    }
    if ($file->getSize() < 1 || $file->getSize() > 2 * 1024 * 1024) {
        $this->writeJson(422, null, '文件必须小于 2MB');
        return;
    }

    $mime = (new \finfo(FILEINFO_MIME_TYPE))->file($file->getTempName());
    $extensions = ['image/jpeg' => 'jpg', 'image/png' => 'png'];
    if (!isset($extensions[$mime])) {
        $this->writeJson(422, null, '只允许 JPG 或 PNG');
        return;
    }

    $directory = EASYSWOOLE_ROOT . '/Storage/uploads/avatar';
    $name = bin2hex(random_bytes(16)) . '.' . $extensions[$mime];
    $file->moveTo($directory . '/' . $name);
    $this->writeJson(201, ['file' => $name]);
}
```

`moveTo()` 会创建目标目录并复制上传流，但目录权限、磁盘空间和异常仍需处理。上传目录应位于 Web 根目录之外；下载时根据数据库 ID 鉴权。不要保留客户端路径和文件名。图片若公开展示，建议用图像库重新解码生成，以移除伪造内容和危险元数据。

数据库和文件系统无法天然组成同一事务：可先写临时文件，业务记录提交后再改为正式状态；失败时补偿删除，并定期清理孤儿文件。
