<?php

namespace App\Process;

use App\Utility\MarkdownDoc;
use EasySwoole\Component\Process\AbstractProcess;
use Swoole\Coroutine;
use Swoole\Event;
use Swoole\Timer;
use Throwable;

class DocSearchIndex extends AbstractProcess
{
    private bool $running = true;

    protected function run($arg): void
    {
        $doc = new MarkdownDoc(EASYSWOOLE_ROOT . '/Doc');
        $cacheFile = EASYSWOOLE_TEMP_DIR . '/doc-search.json';

        while ($this->running) {
            try {
                $json = json_encode(
                    $doc->buildSearch(),
                    JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR
                );
                $temporaryFile = tempnam(EASYSWOOLE_TEMP_DIR, 'doc-search-');
                if ($temporaryFile === false) {
                    throw new \RuntimeException('Cannot create document search cache');
                }
                try {
                    if (file_put_contents($temporaryFile, $json) !== strlen($json)
                        || !rename($temporaryFile, $cacheFile)) {
                        throw new \RuntimeException('Cannot write document search cache');
                    }
                } finally {
                    if (is_file($temporaryFile)) {
                        unlink($temporaryFile);
                    }
                }
            } catch (Throwable $throwable) {
                error_log('Document search indexing failed: ' . $throwable);
            }

            if ($this->running) {
                Coroutine::sleep(15);
            }
        }
    }

    protected function onSigTerm(): void
    {
        Timer::clearAll();
        Event::exit();
        $this->running = false;
    }
}
