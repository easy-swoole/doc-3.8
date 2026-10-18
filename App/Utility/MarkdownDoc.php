<?php

namespace App\Utility;

use League\CommonMark\Environment\Environment;
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
        ]);

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
        ]);
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
