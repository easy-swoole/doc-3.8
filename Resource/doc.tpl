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
            text-decoration: none;
        }

        .header-brand img {
            display: block;
            width: 220px;
            max-width: 100%;
            height: auto;
            max-height: 52px;
            object-fit: contain;
            object-position: left center;
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

        .search-results {
            position: absolute;
            z-index: 30;
            top: calc(100% + 10px);
            right: 0;
            width: min(420px, calc(100vw - 36px));
            max-height: min(65vh, 560px);
            overflow-y: auto;
            padding: 6px;
            border: 1px solid var(--border);
            border-radius: 10px;
            background: var(--surface);
            box-shadow: 0 12px 30px rgb(38 52 69 / 15%);
        }

        .search-results[hidden] { display: none; }
        .search-result { display: block; padding: 9px 11px; border-radius: 6px; color: var(--text); text-decoration: none; }
        .search-result:hover, .search-result:focus { background: var(--primary-soft); }
        .search-result-title { display: block; color: var(--primary); font-weight: 600; }
        .search-result-snippet { display: block; overflow: hidden; color: var(--muted); font-size: 13px; line-height: 1.5; }
        .search-result mark { color: #d92d20; background: transparent; font-weight: 700; }
        .search-message { padding: 10px 12px; color: var(--muted); font-size: 14px; }

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
            min-width: 0;
            max-width: 1080px;
            margin: 0;
            background: var(--surface);
            overflow-wrap: anywhere;
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
        .table-scroll table { width: max-content; min-width: 100%; }
        .document th, .document td { padding: 9px 12px; border: 1px solid var(--border); text-align: left; }
        .document blockquote { margin-left: 0; padding: 2px 18px; border-left: 4px solid var(--primary); color: var(--muted); }
        .document code { padding: 2px 5px; border-radius: 4px; background: #eef2f7; }
        .document pre { max-width: 100%; overflow-x: auto; padding: 18px; border-radius: 10px; color: #e5e7eb; background: var(--code); }
        .document pre code { padding: 0; color: inherit; background: transparent; }
        .table-scroll { max-width: 100%; overflow-x: auto; }

        .mobile-menu-toggle, .menu-backdrop { display: none; }

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
            :root { --header-height: 112px; }
            .header {
                display: grid;
                grid-template-columns: 40px minmax(0, 1fr);
                grid-template-rows: 48px 44px;
                column-gap: 10px;
                height: var(--header-height);
                padding: 8px 16px 10px;
            }
            .mobile-menu-toggle {
                display: grid;
                width: 40px;
                height: 40px;
                padding: 0;
                border: 1px solid var(--border);
                border-radius: 8px;
                place-items: center;
                color: var(--text);
                background: #fff;
                font-size: 24px;
                line-height: 1;
                cursor: pointer;
            }
            .header-brand { width: auto; min-width: 0; }
            .header-brand img { width: 170px; }
            .header-tools { grid-column: 1 / -1; min-width: 0; }
            .search-wrap, .search { width: 100%; }
            .search { height: 42px; padding-top: 8px; padding-bottom: 8px; font-size: 16px; }
            .search-wrap::after { top: 23px; }
            .search-results { right: 0; width: 100%; max-height: min(55vh, 420px); }
            .layout { grid-template-columns: 1fr; }
            .sidebar {
                position: fixed;
                z-index: 18;
                top: var(--header-height);
                bottom: 0;
                left: 0;
                width: min(320px, 85vw);
                height: auto;
                padding: 20px 18px calc(32px + env(safe-area-inset-bottom));
                border-right: 1px solid var(--border);
                box-shadow: 8px 0 24px rgb(38 52 69 / 10%);
                transform: translateX(-105%);
                transition: transform .2s ease;
            }
            .menu-backdrop {
                position: fixed;
                z-index: 17;
                inset: var(--header-height) 0 0;
                background: rgb(17 24 39 / 38%);
            }
            body.menu-open { overflow: hidden; }
            body.menu-open .sidebar { transform: translateX(0); }
            body.menu-open .menu-backdrop { display: block; }
            .main { padding: 24px 16px 64px; }
            .document h1 { font-size: 1.8rem; }
            .document h2 { font-size: 1.4rem; }
            .document pre { padding: 14px; }
        }
    </style>
</head>
<body>
<header class="header">
    <button class="mobile-menu-toggle" id="mobile-menu-toggle" type="button" aria-label="打开文档菜单" aria-controls="document-sidebar" aria-expanded="false">☰</button>
    <a class="header-brand" href="/">
        <img src="/Images/docNavLogo.png" alt="EasySwoole" width="220" height="49">
    </a>
    <div class="header-tools">
        <div class="search-wrap">
            <input class="search" id="menu-search" type="search" placeholder="搜索文档" aria-label="搜索文档标题和正文" autocomplete="off">
            <div class="search-results" id="search-results" role="status" aria-live="polite" hidden></div>
        </div>
    </div>
</header>
<div class="menu-backdrop" id="menu-backdrop" aria-hidden="true"></div>
<div class="layout">
    <aside class="sidebar" id="document-sidebar">
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

    const mobileMenuToggle = document.getElementById('mobile-menu-toggle');
    const menuBackdrop = document.getElementById('menu-backdrop');
    const documentSidebar = document.getElementById('document-sidebar');
    const mobileViewport = window.matchMedia('(max-width: 820px)');

    function setMobileMenuOpen(open) {
        const isOpen = mobileViewport.matches && open;
        document.body.classList.toggle('menu-open', isOpen);
        mobileMenuToggle.setAttribute('aria-expanded', String(isOpen));
        mobileMenuToggle.setAttribute('aria-label', isOpen ? '关闭文档菜单' : '打开文档菜单');
        documentSidebar.inert = mobileViewport.matches && !isOpen;
    }

    mobileMenuToggle.addEventListener('click', () => {
        setMobileMenuOpen(mobileMenuToggle.getAttribute('aria-expanded') !== 'true');
    });
    menuBackdrop.addEventListener('click', () => setMobileMenuOpen(false));
    menuRoot.addEventListener('click', event => {
        if (event.target.closest('a')) setMobileMenuOpen(false);
    });
    document.addEventListener('keydown', event => {
        if (event.key === 'Escape' && document.body.classList.contains('menu-open')) {
            setMobileMenuOpen(false);
            mobileMenuToggle.focus();
        }
    });
    mobileViewport.addEventListener('change', () => setMobileMenuOpen(false));
    setMobileMenuOpen(false);

    document.querySelectorAll('.document table').forEach(table => {
        const wrapper = document.createElement('div');
        wrapper.className = 'table-scroll';
        table.parentNode.insertBefore(wrapper, table);
        wrapper.appendChild(table);
    });

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

    const searchInput = document.getElementById('menu-search');
    const searchResults = document.getElementById('search-results');
    let searchTimer;
    let searchRequest;

    function showSearchMessage(message) {
        const item = document.createElement('div');
        item.className = 'search-message';
        item.textContent = message;
        searchResults.replaceChildren(item);
        searchResults.hidden = false;
    }

    function appendHighlightedText(element, value, keyword) {
        const text = String(value ?? '');
        const needle = keyword.toLocaleLowerCase();
        const lowerText = text.toLocaleLowerCase();
        let cursor = 0;
        let position;

        while ((position = lowerText.indexOf(needle, cursor)) !== -1) {
            element.append(document.createTextNode(text.slice(cursor, position)));
            const mark = document.createElement('mark');
            mark.textContent = text.slice(position, position + keyword.length);
            element.append(mark);
            cursor = position + keyword.length;
        }
        element.append(document.createTextNode(text.slice(cursor)));
    }

    searchInput.addEventListener('input', () => {
        const keyword = searchInput.value.trim();
        clearTimeout(searchTimer);
        searchRequest?.abort();

        if (keyword === '') {
            searchResults.replaceChildren();
            searchResults.hidden = true;
            return;
        }

        searchTimer = setTimeout(async () => {
            const request = new AbortController();
            searchRequest = request;
            try {
                const response = await fetch(`/search?q=${encodeURIComponent(keyword)}`, {
                    signal: request.signal,
                    headers: { Accept: 'application/json' }
                });
                const payload = await response.json();
                if (!response.ok) {
                    throw new Error(payload.msg || '搜索暂不可用');
                }
                if (searchInput.value.trim() !== keyword) return;

                const results = Array.isArray(payload.result) ? payload.result : [];
                if (results.length === 0) {
                    showSearchMessage('没有找到匹配的文档');
                    return;
                }

                const links = results.filter(item =>
                    typeof item.url === 'string' && /^\/[A-Za-z0-9_./-]+\.md$/.test(item.url)
                ).map(item => {
                    const link = document.createElement('a');
                    const title = document.createElement('span');
                    const snippet = document.createElement('span');
                    link.className = 'search-result';
                    link.href = item.url;
                    title.className = 'search-result-title';
                    appendHighlightedText(title, item.title, keyword);
                    snippet.className = 'search-result-snippet';
                    appendHighlightedText(snippet, item.snippet, keyword);
                    link.append(title, snippet);
                    return link;
                });
                searchResults.replaceChildren(...links);
                searchResults.hidden = false;
            } catch (error) {
                if (error.name !== 'AbortError' && searchInput.value.trim() === keyword) {
                    showSearchMessage(error.message || '搜索暂不可用');
                }
            }
        }, 250);
    });

    searchInput.addEventListener('keydown', (event) => {
        if (event.key === 'Escape') searchResults.hidden = true;
    });
    document.addEventListener('click', (event) => {
        if (!event.target.closest('.search-wrap')) searchResults.hidden = true;
    });
</script>
</body>
</html>
