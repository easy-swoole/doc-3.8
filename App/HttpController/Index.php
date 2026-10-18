<?php


namespace App\HttpController;


use App\Utility\MarkdownDoc;
use EasySwoole\Component\Context\ContextManager;
use EasySwoole\EasySwoole\Trigger;
use EasySwoole\Http\AbstractInterface\AbstractRouter;
use EasySwoole\HttpAnnotation\AnnotationController;
use EasySwoole\HttpAnnotation\Attributes\ApiGroup;
use EasySwoole\HttpAnnotation\Exception\ParamValidateFail;
use RuntimeException;

#[ApiGroup(
    groupName: 'Index'
)]
class Index extends AnnotationController
{

    public function search(): void
    {
        $this->response()->withHeader('Cache-Control', 'no-store');
        $query = $this->request()->getQueryParam('q');
        if ($query !== null && !is_string($query)) {
            $this->writeJson(400, [], '搜索关键词格式错误');
            return;
        }
        $keyword = trim($query ?? '');
        if ($keyword === '') {
            $this->writeJson(200, []);
            return;
        }

        $keyword = mb_substr($keyword, 0, 100, 'UTF-8');
        $cacheFile = EASYSWOOLE_TEMP_DIR . '/doc-search.json';
        $json = is_file($cacheFile) ? file_get_contents($cacheFile) : false;
        if ($json === false) {
            $this->writeJson(503, [], '搜索索引正在构建，请稍后重试');
            return;
        }

        try {
            $documents = json_decode($json, true, 512, JSON_THROW_ON_ERROR);
        } catch (\JsonException $exception) {
            $this->writeJson(503, [], '搜索索引暂不可用');
            return;
        }

        if (!is_array($documents)) {
            $this->writeJson(503, [], '搜索索引暂不可用');
            return;
        }

        $matches = [];
        foreach ($documents as $document) {
            if (!is_array($document)) {
                continue;
            }
            $title = $document['title'] ?? null;
            $url = $document['url'] ?? null;
            $body = $document['body'] ?? null;
            if (!is_string($title) || !is_string($url) || !is_string($body)) {
                continue;
            }

            $titlePosition = mb_stripos($title, $keyword, 0, 'UTF-8');
            $bodyPosition = mb_stripos($body, $keyword, 0, 'UTF-8');
            if ($titlePosition === false && $bodyPosition === false) {
                continue;
            }

            $contextBefore = 50;
            $contextAfter = 90;
            $snippetLength = $contextBefore + mb_strlen($keyword, 'UTF-8') + $contextAfter;
            $start = $bodyPosition === false ? 0 : max(0, $bodyPosition - $contextBefore);
            $snippet = mb_substr($body, $start, $snippetLength, 'UTF-8');
            if ($start > 0) {
                $snippet = '…' . $snippet;
            }
            if ($start + $snippetLength < mb_strlen($body, 'UTF-8')) {
                $snippet .= '…';
            }

            $matches[] = [
                'title' => $title,
                'url' => $url,
                'snippet' => $snippet,
                'score' => $titlePosition === false ? 1 : 2,
            ];
        }

        usort($matches, static fn (array $a, array $b): int =>
            ($b['score'] <=> $a['score']) ?: strcmp($a['url'], $b['url'])
        );
        $results = array_slice($matches, 0, 10);
        foreach ($results as &$result) {
            unset($result['score']);
        }
        unset($result);

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
            $this->renderNotFound();
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

    private function renderNotFound(): void
    {
        $this->response()->withStatus(404);
        $this->response()->withHeader('Content-Type', 'text/html; charset=utf-8');
        $this->response()->write(
            $this->renderTemplate(EASYSWOOLE_ROOT . '/Resource/404.tpl')
        );
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

    protected function actionNotFound(?string $action)
    {
        $this->response()->withStatus(404);
        $file = EASYSWOOLE_ROOT.'/vendor/easyswoole/easyswoole/src/Resource/Http/404.html';
        if(!is_file($file)){
            $file = EASYSWOOLE_ROOT.'/src/Resource/Http/404.html';
        }
        $this->response()->write(file_get_contents($file));
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
