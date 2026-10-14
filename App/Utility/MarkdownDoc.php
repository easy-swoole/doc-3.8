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
