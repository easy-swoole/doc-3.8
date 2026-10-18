<?php


namespace App\HttpController;


use App\Utility\MarkdownDoc;
use EasySwoole\Component\Context\ContextManager;
use EasySwoole\EasySwoole\Trigger;
use EasySwoole\Http\AbstractInterface\AbstractRouter;
use EasySwoole\HttpAnnotation\AnnotationController;
use EasySwoole\HttpAnnotation\Attributes\Api;
use EasySwoole\HttpAnnotation\Attributes\ApiGroup;
use EasySwoole\HttpAnnotation\Attributes\Param;
use EasySwoole\HttpAnnotation\Exception\ParamValidateFail;
use EasySwoole\HttpAnnotation\Validator\NotEmpty;
use RuntimeException;

#[ApiGroup(
    groupName: 'Index'
)]
class Index extends AnnotationController
{

    public function index(): void
    {
        $this->response()->withHeader('Content-Type', 'text/html; charset=utf-8');
        $this->response()->write(
            $this->renderTemplate(EASYSWOOLE_ROOT . '/Resource/index.tpl')
        );
    }

    #[Api(
        requestParam: [
            new Param(
                name: 'q',
                validate: [
                    new NotEmpty()
                ]
            )
        ]
    )]
    public function search(string $q): void
    {
        $keyword = $q;

        try {
            $results = (new MarkdownDoc(EASYSWOOLE_ROOT . '/Doc'))->search(
                $keyword,
                EASYSWOOLE_TEMP_DIR . '/doc-search.json'
            );
        } catch (RuntimeException $exception) {
            $this->writeJson(503, [], '搜索索引暂不可用');
            return;
        }

        $this->writeJson(200, $results);
    }

    public function parseDoc(): void
    {
        $routeParams = ContextManager::getInstance()
            ->get(AbstractRouter::PARSE_PARAMS_CONTEXT_KEY);
        $docPath = is_array($routeParams) ? ($routeParams['docPath'] ?? '') : '';

        $doc = new MarkdownDoc(EASYSWOOLE_ROOT . '/Doc');

        try {
            $contentHtml = $doc->parseDocument($docPath);
        } catch (RuntimeException) {
            $this->actionNotFound($docPath);
            return;
        }

        $menuJson = json_encode(
            $doc->parseMenu(),
            JSON_UNESCAPED_UNICODE
            | JSON_UNESCAPED_SLASHES
            | JSON_HEX_TAG
            | JSON_HEX_AMP
            | JSON_HEX_APOS
            | JSON_HEX_QUOT
            | JSON_THROW_ON_ERROR
        );

        $html = $this->renderTemplate(
            EASYSWOOLE_ROOT . '/Resource/doc.tpl',
            [
                'menuJson' => $menuJson,
                'contentHtml' => $contentHtml,
                'currentPath' => '/' . ltrim($docPath, '/'),
            ]
        );

        $this->response()->withHeader('Content-Type', 'text/html; charset=utf-8');
        $this->response()->write($html);
    }

    private function renderTemplate(string $file, array $variables = []): string
    {
        if (!is_file($file) || !is_readable($file)) {
            throw new RuntimeException("Template file is not readable: {$file}");
        }

        extract($variables, EXTR_SKIP);
        ob_start();

        try {
            include $file;
            return (string)ob_get_clean();
        } catch (\Throwable $throwable) {
            ob_end_clean();
            throw $throwable;
        }
    }

    protected function actionNotFound(?string $action): void
    {
        $this->response()->withStatus(404);
        $this->response()->withHeader('Content-Type', 'text/html; charset=utf-8');
        $this->response()->write(
            $this->renderTemplate(EASYSWOOLE_ROOT . '/Resource/404.tpl')
        );
    }

    function onException(\Throwable $throwable): void
    {
        if($throwable instanceof ParamValidateFail){
            $msg = $throwable->getFailRule()->errorMsg($throwable->getParamName());
            $this->response()->write("param validate fail: $msg");
        }else{
            Trigger::getInstance()->throwable($throwable);
            $this->response()->write("系统出现异常，请联系管理员");
        }
    }
}
