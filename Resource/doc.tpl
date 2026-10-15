<?php
/** @var string $menuJson */
/** @var string $contentHtml */
/** @var string $currentPath */
?>
<!doctype html>
<html lang="zh-CN">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>EasySwoole 文档</title>
    <style>
        :root {
            color-scheme: light;
            --header-height: 72px;
            --sidebar-width: 292px;
            --toc-width: 230px;
            --background: #ffffff;
            --surface: #ffffff;
            --border: #e6e9ee;
            --text: #263445;
            --muted: #526173;
            --primary: #1687e8;
            --primary-soft: #eef7ff;
            --brand: #08b7a8;
            --code: #111827;
        }

        * { box-sizing: border-box; }

        html {
            scroll-behavior: smooth;
            scroll-padding-top: calc(var(--header-height) + 24px);
        }

        body {
            margin: 0;
            color: var(--text);
            background: var(--background);
            font: 16px/1.8 -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", sans-serif;
        }

        .header {
            position: fixed;
            z-index: 20;
            top: 0;
            right: 0;
            left: 0;
            display: flex;
            align-items: center;
            height: var(--header-height);
            padding: 0 32px;
            border-top: 2px solid #eee8f8;
            border-bottom: 1px solid var(--border);
            background: rgb(255 255 255 / 96%);
            backdrop-filter: blur(10px);
        }

        .header-brand {
            display: flex;
            align-items: center;
            width: calc(var(--sidebar-width) - 32px);
            color: #304052;
            font-size: 20px;
            font-weight: 750;
            letter-spacing: .02em;
            text-decoration: none;
        }

        .brand-mark {
            display: grid;
            width: 40px;
            height: 44px;
            margin-right: 13px;
            place-items: center;
            clip-path: polygon(50% 0, 94% 23%, 94% 76%, 50% 100%, 6% 76%, 6% 23%);
            color: white;
            background: var(--brand);
            font-size: 22px;
            font-weight: 800;
        }

        .header-tools {
            display: flex;
            flex: 1;
            align-items: center;
            justify-content: flex-end;
            gap: 32px;
        }

        .search {
            width: min(290px, 36vw);
            padding: 10px 16px 10px 40px;
            border: 1px solid #d8dde5;
            border-radius: 24px;
            outline: none;
            background: #fff no-repeat 15px center;
            font: inherit;
            line-height: 1.2;
        }

        .search:focus {
            border-color: var(--primary);
            box-shadow: 0 0 0 3px rgb(22 135 232 / 12%);
        }

        .header-title { color: var(--text); font-size: 16px; white-space: nowrap; }

        .search-wrap { position: relative; }

        .search-wrap::before {
            position: absolute;
            z-index: 1;
            top: 50%;
            left: 16px;
            width: 11px;
            height: 11px;
            border: 3px solid #aab2bd;
            border-radius: 50%;
            content: '';
            transform: translateY(-62%);
        }

        .search-wrap::after {
            position: absolute;
            top: 25px;
            left: 28px;
            width: 8px;
            height: 3px;
            border-radius: 2px;
            background: #aab2bd;
            content: '';
            transform: rotate(45deg);
        }

        .layout {
            display: grid;
            grid-template-columns: var(--sidebar-width) minmax(0, 1fr);
            min-height: 100vh;
            padding-top: var(--header-height);
        }

        .sidebar {
            position: sticky;
            top: var(--header-height);
            height: calc(100vh - var(--header-height));
            overflow-y: auto;
            padding: 32px 24px 48px;
            border-right: 1px solid var(--border);
            background: var(--surface);
        }

        .menu, .menu ul {
            margin: 0;
            padding: 0;
            list-style: none;
        }

        .menu ul {
            margin: 4px 0 10px 15px;
            padding-left: 14px;
            border-left: 1px solid #edf0f3;
        }

        .menu-row {
            display: flex;
            align-items: center;
            min-width: 0;
        }

        .menu a, .menu-label {
            display: block;
            flex: 1;
            min-width: 0;
            padding: 7px 9px;
            border-radius: 5px;
            color: var(--muted);
            text-decoration: none;
        }

        .menu-label { color: var(--text); font-weight: 600; cursor: default; }
        .menu-label.expandable { cursor: pointer; }
        .menu a:hover { color: var(--primary); background: var(--primary-soft); }
        .menu a.active { color: var(--primary); font-weight: 600; text-decoration: underline; text-underline-offset: 4px; }

        .menu-toggle {
            display: grid;
            flex: 0 0 24px;
            width: 24px;
            height: 30px;
            padding: 0;
            border: 0;
            place-items: center;
            color: #667789;
            background: transparent;
            cursor: pointer;
        }

        .menu-toggle::before {
            display: block;
            content: '›';
            font-size: 21px;
            line-height: 1;
            transition: transform .16s ease;
        }

        .menu-toggle[aria-expanded="true"]::before { transform: rotate(90deg); }
        .menu-toggle:hover { color: var(--primary); }
        .menu-toggle-placeholder { flex: 0 0 24px; width: 24px; }
        .menu ul[hidden] { display: none; }

        .main { min-width: 0; padding: 48px clamp(30px, 4vw, 72px) 90px; }

        .content-layout {
            display: grid;
            grid-template-columns: minmax(0, 1080px) var(--toc-width);
            gap: clamp(30px, 4vw, 64px);
            align-items: start;
            justify-content: center;
        }

        .document {
            max-width: 1080px;
            margin: 0;
            background: var(--surface);
        }

        .document h1, .document h2, .document h3 { line-height: 1.3; }
        .document h1[id], .document h2[id], .document h3[id] {
            scroll-margin-top: calc(var(--header-height) + 24px);
        }
        .document h1 { margin-top: 0; padding-bottom: .35em; border-bottom: 1px solid var(--border); font-size: 2.2rem; }
        .document h2 { margin-top: 2.2em; padding-bottom: .35em; border-bottom: 1px solid var(--border); }
        .document a { color: var(--primary); }
        .document img { max-width: 100%; height: auto; }
        .document table { width: 100%; border-collapse: collapse; }
        .document th, .document td { padding: 9px 12px; border: 1px solid var(--border); text-align: left; }
        .document blockquote { margin-left: 0; padding: 2px 18px; border-left: 4px solid var(--primary); color: var(--muted); }
        .document code { padding: 2px 5px; border-radius: 4px; background: #eef2f7; }
        .document pre { overflow-x: auto; padding: 18px; border-radius: 10px; color: #e5e7eb; background: var(--code); }
        .document pre code { padding: 0; color: inherit; background: transparent; }

        .toc {
            position: sticky;
            top: calc(var(--header-height) + 28px);
            max-height: calc(100vh - var(--header-height) - 56px);
            overflow-y: auto;
            padding-left: 20px;
            border-left: 1px solid var(--border);
        }

        .toc[hidden] { display: none; }

        .toc-title {
            margin-bottom: 10px;
            color: var(--text);
            font-size: 14px;
            font-weight: 700;
        }

        .toc-list { margin: 0; padding: 0; list-style: none; }

        .toc-link {
            display: block;
            padding: 4px 0;
            color: #718096;
            font-size: 14px;
            line-height: 1.55;
            text-decoration: none;
            transition: color .15s ease;
        }

        .toc-link:hover, .toc-link.active { color: var(--primary); }
        .toc-link.active { font-weight: 600; }
        .toc-link.level-3 { padding-left: 14px; font-size: 13px; }

        .menu li[hidden] { display: none; }

        @media (max-width: 1180px) {
            .content-layout { display: block; }
            .toc { display: none; }
            .document { margin: 0 auto; }
        }

        @media (max-width: 820px) {
            .header { padding: 0 18px; }
            .header-brand { width: auto; }
            .brand-mark { width: 34px; height: 38px; }
            .header-tools { gap: 12px; }
            .header-title { display: none; }
            .layout { grid-template-columns: 1fr; }
            .sidebar { position: static; height: auto; padding: 24px; border-right: 0; border-bottom: 1px solid var(--border); }
            .main { padding: 18px; }
        }
    </style>
</head>
<body>
<header class="header">
    <a class="header-brand" href="/intro.md">
        <span class="brand-mark">E</span>
        <span>EasySwoole</span>
    </a>
    <div class="header-tools">
        <label class="search-wrap">
            <span hidden>搜索文档菜单</span>
            <input class="search" id="menu-search" type="search" placeholder="搜索文档" autocomplete="off">
        </label>
        <span class="header-title">EasySwoole 文档中心</span>
    </div>
</header>
<div class="layout">
    <aside class="sidebar">
        <nav aria-label="文档菜单">
            <ul class="menu" id="doc-menu"></ul>
        </nav>
    </aside>
    <main class="main">
        <div class="content-layout">
            <article class="document" id="document-content">
                <?= $contentHtml ?>
            </article>
            <aside class="toc" id="document-toc" aria-label="本页导航" hidden>
                <div class="toc-title">本页导航</div>
                <nav>
                    <ol class="toc-list" id="document-toc-list"></ol>
                </nav>
            </aside>
        </div>
    </main>
</div>

<script>
    const menu = <?= $menuJson ?>;
    const currentPath = <?= json_encode(
        $currentPath,
        JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT
    ) ?>;

    let activeItemFound = false;

    function resetMenuState(items) {
        for (const item of items) {
            item.isActive = false;
            item.containsActive = false;
            if (Array.isArray(item.children)) {
                resetMenuState(item.children);
            }
        }
    }

    function markCurrentBranch(items) {
        for (const item of items) {
            if (!activeItemFound && item.url === currentPath) {
                item.isActive = true;
                item.containsActive = true;
                activeItemFound = true;
                return true;
            }

            if (!activeItemFound && Array.isArray(item.children) && markCurrentBranch(item.children)) {
                item.containsActive = true;
                return true;
            }
        }

        return false;
    }

    function setMenuExpanded(button, childList, expanded) {
        button.setAttribute('aria-expanded', String(expanded));
        childList.hidden = !expanded;
    }

    function renderMenu(items) {
        const list = document.createElement('ul');

        for (const item of items) {
            const listItem = document.createElement('li');
            const row = document.createElement('div');
            const hasChildren = Array.isArray(item.children) && item.children.length > 0;
            const label = item.url ? document.createElement('a') : document.createElement('span');

            row.className = 'menu-row';
            label.className = item.url ? '' : 'menu-label';
            label.textContent = item.title;
            if (item.url) {
                label.href = item.url;
                if (item.isActive) {
                    label.classList.add('active');
                    label.setAttribute('aria-current', 'page');
                }
            }

            if (hasChildren) {
                const toggle = document.createElement('button');
                const childList = renderMenu(item.children);
                const expanded = item.containsActive;

                toggle.className = 'menu-toggle';
                toggle.type = 'button';
                toggle.setAttribute('aria-label', `展开或收起 ${item.title}`);
                childList.dataset.collapsible = 'true';
                childList.dataset.defaultExpanded = String(expanded);
                setMenuExpanded(toggle, childList, expanded);
                toggle.addEventListener('click', () => {
                    setMenuExpanded(toggle, childList, toggle.getAttribute('aria-expanded') !== 'true');
                });

                row.append(toggle, label);
                listItem.append(row, childList);

                if (!item.url) {
                    label.classList.add('expandable');
                    label.addEventListener('click', () => toggle.click());
                }
            } else {
                const placeholder = document.createElement('span');
                placeholder.className = 'menu-toggle-placeholder';
                row.append(placeholder, label);
                listItem.appendChild(row);
            }

            list.appendChild(listItem);
        }

        return list;
    }

    const menuRoot = document.getElementById('doc-menu');
    resetMenuState(menu);
    markCurrentBranch(menu);
    const renderedMenu = renderMenu(menu);
    menuRoot.replaceChildren(...renderedMenu.children);

    function createHeadingId(text, index, usedIds) {
        let base = text.trim()
            .toLocaleLowerCase()
            .replace(/\s+/g, '-')
            .replace(/[^a-z0-9\u3400-\u9fff_-]/g, '')
            .replace(/^-+|-+$/g, '');

        if (base === '') {
            base = `section-${index + 1}`;
        }

        let id = base;
        let suffix = 2;
        while (usedIds.has(id) || document.getElementById(id)) {
            id = `${base}-${suffix++}`;
        }
        usedIds.add(id);
        return id;
    }

    function buildDocumentToc() {
        const documentContent = document.getElementById('document-content');
        const toc = document.getElementById('document-toc');
        const tocList = document.getElementById('document-toc-list');
        const headings = Array.from(documentContent.querySelectorAll('h2, h3'));

        if (headings.length === 0) {
            return;
        }

        const usedIds = new Set();
        const links = [];

        headings.forEach((heading, index) => {
            if (heading.id === '' || usedIds.has(heading.id)) {
                heading.id = createHeadingId(heading.textContent, index, usedIds);
            } else {
                usedIds.add(heading.id);
            }

            const item = document.createElement('li');
            const link = document.createElement('a');
            link.className = `toc-link level-${heading.tagName.substring(1)}`;
            link.href = `#${encodeURIComponent(heading.id)}`;
            link.textContent = heading.textContent.trim();
            item.appendChild(link);
            tocList.appendChild(item);
            links.push(link);
        });

        toc.hidden = false;

        let ticking = false;
        const updateActiveHeading = () => {
            const headerHeight = parseFloat(
                getComputedStyle(document.documentElement).getPropertyValue('--header-height')
            );
            const threshold = headerHeight + 32;
            let activeIndex = 0;

            headings.forEach((heading, index) => {
                if (heading.getBoundingClientRect().top <= threshold) {
                    activeIndex = index;
                }
            });

            links.forEach((link, index) => {
                const active = index === activeIndex;
                link.classList.toggle('active', active);
                if (active) {
                    link.setAttribute('aria-current', 'location');
                } else {
                    link.removeAttribute('aria-current');
                }
            });
            ticking = false;
        };

        window.addEventListener('scroll', () => {
            if (!ticking) {
                window.requestAnimationFrame(updateActiveHeading);
                ticking = true;
            }
        }, { passive: true });

        updateActiveHeading();

        if (window.location.hash !== '') {
            const initialId = decodeURIComponent(window.location.hash.substring(1));
            const initialHeading = document.getElementById(initialId);
            if (initialHeading) {
                window.requestAnimationFrame(() => initialHeading.scrollIntoView());
            }
        }
    }

    buildDocumentToc();

    document.getElementById('menu-search').addEventListener('input', (event) => {
        const keyword = event.target.value.trim().toLocaleLowerCase();

        for (const item of menuRoot.querySelectorAll('li')) {
            item.hidden = keyword !== '' && !item.textContent.toLocaleLowerCase().includes(keyword);
        }

        for (const childList of menuRoot.querySelectorAll('ul[data-collapsible]')) {
            const button = childList.previousElementSibling.querySelector('.menu-toggle');
            const expanded = keyword !== '' || childList.dataset.defaultExpanded === 'true';
            setMenuExpanded(button, childList, expanded);
        }
    });
</script>
</body>
</html>
