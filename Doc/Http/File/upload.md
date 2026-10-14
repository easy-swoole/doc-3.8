# 文件上传

上传文件来自 `multipart/form-data`，普通字段进入 Parsed Body，文件进入 UploadedFiles。

新建 `App/HttpController/Upload.php`：

```php
<?php
namespace App\HttpController;

use EasySwoole\Http\AbstractInterface\Controller;

class Upload extends Controller
{
    public function avatar(): void
    {
        $file = $this->request()->getUploadedFile('avatar');
        if ($file === null) {
            $this->writeJson(422, null, '请选择 avatar 文件');
            return;
        }
        if ($file->getError() !== UPLOAD_ERR_OK) {
            $this->writeJson(422, null, '上传失败，错误码：' . $file->getError());
            return;
        }
        $this->writeJson(200, [
            'clientName' => $file->getClientFilename(),
            'clientType' => $file->getClientMediaType(),
            'size' => $file->getSize(),
        ]);
    }
}
```

```php
$routeCollector->post('/upload/avatar', '/Upload/avatar');
```

```bash
curl -X POST http://127.0.0.1:9501/upload/avatar \
  -F 'avatar=@/absolute/path/avatar.jpg' \
  -F 'description=my avatar'
```

读取单个文件用 `getUploadedFile('avatar')`，读取全部用 `getUploadedFiles()`；同名多文件可能得到数组，应逐项检查。`getClientFilename()` 和 `getClientMediaType()` 都由客户端提供，不能作为安全依据。错误码、大小、真实 MIME 和业务权限必须在保存前验证。

常见错误：表单字段名和代码不一致、客户端未使用 multipart、只检查扩展名、直接使用原文件名保存，以及先移动后验证。
