<?php

namespace App\Utility;

use League\CommonMark\Environment\Environment;
use League\CommonMark\Extension\Attributes\AttributesExtension;
use League\CommonMark\Extension\CommonMark\CommonMarkCoreExtension;
use League\CommonMark\Extension\CommonMark\Node\Block\ListBlock;
use League\CommonMark\Extension\CommonMark\Node\Block\ListItem;
use League\CommonMark\Extension\CommonMark\Node\Inline\Link;
use League\CommonMark\GithubFlavoredMarkdownConverter;
use League\CommonMark\Node\Node;
use League\CommonMark\Node\StringContainerInterface;
use League\CommonMark\Parser\MarkdownParser;
use RecursiveDirectoryIterator;
use RecursiveIteratorIterator;
use RuntimeException;

class MarkdownDoc
{
    protected string $docRoot;

    public function __construct(string $docRoot)
    {
        $this->docRoot = rtrim($docRoot, '/');
    }

    /**
     * @return array<int, array{title: string, url: ?string, children: array}>
     */
    public function parseMenu(): array
    {
        $file = $this->docRoot . '/menu.md';

        if (!is_file($file) || !is_readable($file)) {
            throw new RuntimeException("Menu file is not readable: {$file}");
        }

        $markdown = file_get_contents($file);
        if ($markdown === false) {
            throw new RuntimeException("Failed to read menu file: {$file}");
        }

        $environment = new Environment();
        $environment->addExtension(new CommonMarkCoreExtension());

        $document = (new MarkdownParser($environment))->parse($markdown);
        $menu = [];

        // Only top-level lists are menu roots. Nested lists are handled recursively.
        foreach ($document->children() as $node) {
            if ($node instanceof ListBlock) {
                array_push($menu, ...$this->parseList($node));
            }
        }

        return $menu;
    }

    public function parseDocument(string $relativePath): string
    {
        $file = $this->resolveDocumentPath($relativePath);
        $markdown = file_get_contents($file);

        if ($markdown === false) {
            throw new RuntimeException("Failed to read document: {$relativePath}");
        }

        $converter = new GithubFlavoredMarkdownConverter([
            'html_input' => 'strip',
            'allow_unsafe_links' => false,
            'attributes' => ['allow' => ['style']],
        ]);
        $converter->getEnvironment()->addExtension(new AttributesExtension());

        return $converter->convert($markdown)->getContent();
    }

    /**
     * @return array<int, array{title: string, url: string, body: string}>
     */
    public function buildSearch(): array
    {
        $root = realpath($this->docRoot);
        if ($root === false || !is_dir($root)) {
            throw new RuntimeException("Document directory not found: {$this->docRoot}");
        }

        $converter = new GithubFlavoredMarkdownConverter([
            'html_input' => 'strip',
            'allow_unsafe_links' => false,
            'attributes' => ['allow' => ['style']],
        ]);
        $converter->getEnvironment()->addExtension(new AttributesExtension());
        $documents = [];
        $files = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($root, RecursiveDirectoryIterator::SKIP_DOTS)
        );

        foreach ($files as $entry) {
            if (!$entry->isFile() || strtolower($entry->getExtension()) !== 'md') {
                continue;
            }

            $path = $entry->getRealPath();
            if ($path === false || !str_starts_with($path, $root . DIRECTORY_SEPARATOR)) {
                continue;
            }

            $relativePath = substr($path, strlen($root) + 1);
            if ($relativePath === 'menu.md') {
                continue;
            }

            $markdown = file_get_contents($path);
            if ($markdown === false) {
                throw new RuntimeException("Failed to read document: {$path}");
            }

            $html = $converter->convert($markdown)->getContent();
            $body = html_entity_decode(strip_tags(str_replace('</', ' </', $html)), ENT_QUOTES | ENT_HTML5, 'UTF-8');
            $body = trim((string) preg_replace('/\s+/u', ' ', $body));
            $title = pathinfo($path, PATHINFO_FILENAME);
            if (preg_match('/<h1(?:\s[^>]*)?>(.*?)<\/h1>/isu', $html, $match)) {
                $heading = trim(html_entity_decode(strip_tags($match[1]), ENT_QUOTES | ENT_HTML5, 'UTF-8'));
                if ($heading !== '') {
                    $title = $heading;
                }
            }

            $documents[] = [
                'title' => $title,
                'url' => '/' . str_replace(DIRECTORY_SEPARATOR, '/', $relativePath),
                'body' => $body,
            ];
        }

        usort($documents, static fn (array $a, array $b): int => strcmp($a['url'], $b['url']));
        return $documents;
    }

    /**
     * @return array<int, array{title: string, url: string, snippet: string}>
     */
    public function search(string $keyword, string $cacheFile, int $limit = 10): array
    {
        $keyword = mb_substr(trim($keyword), 0, 100, 'UTF-8');
        if ($keyword === '' || $limit < 1) {
            return [];
        }

        $json = is_file($cacheFile) ? file_get_contents($cacheFile) : false;
        if ($json === false) {
            throw new RuntimeException("Search cache is not readable: {$cacheFile}");
        }

        try {
            $documents = json_decode($json, true, 512, JSON_THROW_ON_ERROR);
        } catch (\JsonException $exception) {
            throw new RuntimeException("Search cache is invalid: {$cacheFile}", 0, $exception);
        }
        if (!is_array($documents)) {
            throw new RuntimeException("Search cache is invalid: {$cacheFile}");
        }

        $matches = [];
        $keywordLength = mb_strlen($keyword, 'UTF-8');
        $contextBefore = 50;
        $snippetLength = $contextBefore + $keywordLength + 90;

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
        $results = array_slice($matches, 0, $limit);
        foreach ($results as &$result) {
            unset($result['score']);
        }
        unset($result);

        return $results;
    }

    private function resolveDocumentPath(string $relativePath): string
    {
        $root = realpath($this->docRoot);
        $file = realpath($this->docRoot . '/' . ltrim($relativePath, '/'));

        if (
            $root === false
            || $file === false
            || !is_file($file)
            || !str_starts_with($file, $root . DIRECTORY_SEPARATOR)
            || strtolower(pathinfo($file, PATHINFO_EXTENSION)) !== 'md'
        ) {
            throw new RuntimeException("Document not found: {$relativePath}");
        }

        return $file;
    }

    /**
     * @return array<int, array{title: string, url: ?string, children: array}>
     */
    private function parseList(ListBlock $list): array
    {
        $items = [];

        foreach ($list->children() as $node) {
            if (!$node instanceof ListItem) {
                continue;
            }

            $title = '';
            $url = null;
            $children = [];

            foreach ($node->children() as $child) {
                if ($child instanceof ListBlock) {
                    array_push($children, ...$this->parseList($child));
                    continue;
                }

                if ($title === '') {
                    $title = trim($this->extractText($child));
                    $link = $this->findLink($child);
                    $url = $link?->getUrl();
                }
            }

            if ($title === '') {
                throw new RuntimeException('Menu item title cannot be empty');
            }

            $items[] = [
                'title' => $title,
                'url' => $url,
                'children' => $children,
            ];
        }

        return $items;
    }

    private function extractText(Node $node): string
    {
        $text = $node instanceof StringContainerInterface
            ? $node->getLiteral()
            : '';

        foreach ($node->children() as $child) {
            $text .= $this->extractText($child);
        }

        return $text;
    }

    private function findLink(Node $node): ?Link
    {
        if ($node instanceof Link) {
            return $node;
        }

        foreach ($node->children() as $child) {
            $link = $this->findLink($child);
            if ($link !== null) {
                return $link;
            }
        }

        return null;
    }
}
