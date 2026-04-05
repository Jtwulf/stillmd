import Foundation

enum HTMLTemplate {
    static func containsMermaidFence(in markdownContent: String) -> Bool {
        markdownContent.range(
            of: #"(?m)^[ \t]{0,3}(?:```|~~~)[ \t]*mermaid(?:[ \t].*)?$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    static func build(
        markdownContent: String,
        markedJS: String,
        highlightJS: String,
        css: String,
        initialScrollPosition: Double = 0,
        themePreference: String = ThemePreference.defaultPreference.rawValue,
        textScale: Double = AppPreferences.defaultTextScale,
        documentBaseURL: URL? = nil,
        initialFindQuery: String = "",
        mermaidJS: String? = nil
    ) -> String {
        // Base64 keeps `${…}`, backticks, quotes, and `</script>` from breaking out of the HTML `<script>` block
        // or being interpreted as JS (template literals / unterminated strings → blank WebView).
        let markdownBase64 = Data(markdownContent.utf8).base64EncodedString()
        let escapedThemePreference = themePreference
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedInitialFindQuery = initialFindQuery
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        let mermaidScriptTag = mermaidJS.map { "<script>\($0)</script>" } ?? ""
        let baseTag = documentBaseURL.map { url in
            let href = url.absoluteString
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return "<base href=\"\(href)\">"
        } ?? ""

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            \(baseTag)
            <style>\(css)</style>
            <script>\(markedJS)</script>
            <script>\(highlightJS)</script>
            \(mermaidScriptTag)
        </head>
        <body>
            <div id="content"></div>
            <script>
                // MARK: Embedded preview runtime (marked.js, highlight.js, Mermaid, stillmd bridge)
                // Kept inline for a single `loadHTMLString` document; Swift splits would fragment bundle/tests.
                try {
                window.__stillmdBootPhase = 'script-start';
                // Strip raw HTML blocks from markdown output for security.
                // This prevents injected <img onerror=...>, <script>, javascript: links, etc.
                marked.use({
                    renderer: {
                        html() {
                            return '';
                        }
                    }
                });

                // marked.js configuration: GFM enabled
                marked.setOptions({
                    gfm: true,
                    breaks: false,
                    highlight: function(code, lang) {
                        try {
                            if (lang && hljs.getLanguage(lang)) {
                                return hljs.highlight(code, { language: lang }).value;
                            }
                        } catch (e) {}
                        return code;
                    }
                });

                function stillmdMarkdownFromBase64(b64) {
                    const binary = atob(b64);
                    const bytes = new Uint8Array(binary.length);
                    for (let i = 0; i < binary.length; i++) {
                        bytes[i] = binary.charCodeAt(i);
                    }
                    return new TextDecoder('utf-8').decode(bytes);
                }

                // Initial render (see Swift: markdownBase64)
                window.__stillmdBootPhase = 'before-initial-render';
                const md = stillmdMarkdownFromBase64('\(markdownBase64)');
                const contentElement = document.getElementById('content');
                const messageHandlers = window.webkit?.messageHandlers ?? {};
                const scrollHandler = messageHandlers.scrollPosition ?? null;
                const findResultsHandler = messageHandlers.findResults ?? null;
                const linkClickedHandler = messageHandlers.linkClicked ?? null;
                const initialScrollY = \(initialScrollPosition);
                const initialThemePreference = "\(escapedThemePreference)";
                const initialTextScale = \(textScale);
                const initialFindQuery = "\(escapedInitialFindQuery)";
                const viewerState = {
                    themePreference: initialThemePreference,
                    findQuery: initialFindQuery,
                };
                let findMatches = [];
                let findState = { currentIndex: -1 };
                let mermaidRenderGeneration = 0;
                let mermaidRenderSequence = 0;
                window.__stillmdBootPhase = 'state-ready';

                function postMessageIfAvailable(handler, payload) {
                    if (handler && typeof handler.postMessage === 'function') {
                        handler.postMessage(payload);
                    }
                }

                function escapeHTML(value) {
                    return value
                        .replace(/&/g, '&amp;')
                        .replace(/</g, '&lt;')
                        .replace(/>/g, '&gt;')
                        .replace(/"/g, '&quot;')
                        .replace(/'/g, '&#39;');
                }

                function getCodeLanguage(codeElement) {
                    for (const className of codeElement.classList) {
                        if (className.startsWith('language-')) {
                            return className.slice('language-'.length);
                        }
                    }
                    return '';
                }

                function isMermaidBlock(codeElement) {
                    return getCodeLanguage(codeElement) === 'mermaid';
                }

                function renderCodeBlock(codeElement) {
                    const pre = codeElement.parentElement;
                    if (!pre || pre.dataset.stillmdCodeDecorated === 'true' || isMermaidBlock(codeElement)) {
                        return;
                    }

                    pre.dataset.stillmdCodeDecorated = 'true';

                    const language = getCodeLanguage(codeElement);
                    const rawText = codeElement.textContent || '';
                    const normalizedText = rawText.replace(/\\r?\\n$/, '');
                    const lines = normalizedText.split(/\\r?\\n/);

                    const block = document.createElement('div');
                    block.className = 'stillmd-code-block';

                    const gutter = document.createElement('div');
                    gutter.className = 'stillmd-code-gutter';

                    const linesContainer = document.createElement('div');
                    linesContainer.className = 'stillmd-code-lines';

                    lines.forEach((line, index) => {
                        const lineNumber = document.createElement('span');
                        lineNumber.className = 'stillmd-code-line-number';
                        lineNumber.textContent = String(index + 1);
                        gutter.appendChild(lineNumber);

                        const lineRow = document.createElement('div');
                        lineRow.className = 'stillmd-code-line';
                        lineRow.dataset.stillmdCodeLine = 'true';

                        const lineContent = document.createElement('span');
                        lineContent.className = 'stillmd-code-line-content';
                        if (!line) {
                            lineContent.innerHTML = '&nbsp;';
                        } else if (language && hljs.getLanguage(language)) {
                            try {
                                lineContent.innerHTML = hljs.highlight(line, { language: language }).value;
                            } catch (e) {
                                lineContent.innerHTML = escapeHTML(line);
                            }
                        } else {
                            lineContent.innerHTML = escapeHTML(line);
                        }

                        lineRow.appendChild(lineContent);
                        linesContainer.appendChild(lineRow);
                    });

                    block.appendChild(gutter);
                    block.appendChild(linesContainer);
                    pre.replaceWith(block);
                }

                function decorateCodeBlocks() {
                    const codeBlocks = contentElement.querySelectorAll('pre > code');
                    for (const codeElement of codeBlocks) {
                        renderCodeBlock(codeElement);
                    }
                }

                function decorateMermaidBlocks() {
                    const mermaidCodeBlocks = contentElement.querySelectorAll('pre > code');
                    for (const codeElement of mermaidCodeBlocks) {
                        if (!isMermaidBlock(codeElement)) {
                            continue;
                        }

                        const pre = codeElement.parentElement;
                        if (!pre || pre.dataset.stillmdMermaidDecorated === 'true') {
                            continue;
                        }

                        pre.dataset.stillmdMermaidDecorated = 'true';
                        pre.dataset.stillmdMermaidSource = codeElement.textContent || '';
                        pre.dataset.stillmdMermaidState = 'fallback';
                        pre.classList.add('stillmd-mermaid-block');
                    }
                }

                function getResolvedMermaidTheme() {
                    return viewerState.themePreference === 'dark' ? 'dark' : 'default';
                }

                function configureMermaid() {
                    if (typeof mermaid === 'undefined' || typeof mermaid.initialize !== 'function') {
                        return false;
                    }

                    try {
                        mermaid.initialize({
                            startOnLoad: false,
                            securityLevel: 'strict',
                            theme: getResolvedMermaidTheme(),
                            fontFamily: getComputedStyle(document.body).fontFamily,
                        });
                        return true;
                    } catch (error) {
                        return false;
                    }
                }

                function setMermaidFallback(pre, source) {
                    pre.dataset.stillmdMermaidState = 'fallback';
                    pre.innerHTML = `<code class="language-mermaid">${escapeHTML(source)}</code>`;
                }

                function setMermaidRendered(pre, svg, bindFunctions) {
                    pre.dataset.stillmdMermaidState = 'rendered';
                    pre.innerHTML = svg;
                    if (typeof bindFunctions === 'function') {
                        try {
                            bindFunctions(pre);
                        } catch (error) {}
                    }
                }

                async function renderMermaidBlock(pre, generation) {
                    const source = pre.dataset.stillmdMermaidSource || '';
                    if (generation !== mermaidRenderGeneration) {
                        return;
                    }

                    if (!source) {
                        setMermaidFallback(pre, source);
                        return;
                    }

                    if (!configureMermaid()) {
                        setMermaidFallback(pre, source);
                        return;
                    }

                    try {
                        const diagramId = `stillmd-mermaid-${generation}-${++mermaidRenderSequence}`;
                        const result = await mermaid.render(diagramId, source);
                        if (generation !== mermaidRenderGeneration) {
                            return;
                        }

                        const svg = typeof result === 'string' ? result : result?.svg;
                        const bindFunctions =
                            result && typeof result === 'object' && typeof result.bindFunctions === 'function'
                                ? result.bindFunctions
                                : null;

                        if (typeof svg !== 'string' || !svg) {
                            throw new Error('Mermaid render returned no SVG');
                        }

                        setMermaidRendered(pre, svg, bindFunctions);
                    } catch (error) {
                        if (generation !== mermaidRenderGeneration) {
                            return;
                        }
                        setMermaidFallback(pre, source);
                    }
                }

                async function renderMermaidBlocks() {
                    const mermaidBlocks = Array.from(
                        contentElement.querySelectorAll('pre.stillmd-mermaid-block')
                    );

                    if (!mermaidBlocks.length) {
                        return;
                    }

                    if (typeof mermaid === 'undefined') {
                        for (const pre of mermaidBlocks) {
                            setMermaidFallback(pre, pre.dataset.stillmdMermaidSource || '');
                        }
                        return;
                    }

                    mermaidRenderGeneration += 1;
                    const generation = mermaidRenderGeneration;

                    await Promise.all(
                        mermaidBlocks.map((pre) => renderMermaidBlock(pre, generation))
                    );
                }

                async function renderMarkdown(source) {
                    contentElement.innerHTML = marked.parse(source);
                    decorateCodeBlocks();
                    decorateMermaidBlocks();
                    if (viewerState.findQuery) {
                        highlightMatches(viewerState.findQuery, true);
                    } else {
                        publishFindResults();
                    }
                    await renderMermaidBlocks();
                }

                function publishFindResults() {
                    postMessageIfAvailable(findResultsHandler, {
                        matchCount: findMatches.length,
                        currentIndex: findState.currentIndex,
                    });
                }

                function clearFindHighlights() {
                    const marks = contentElement.querySelectorAll('mark[data-stillmd-find="true"]');
                    for (const mark of marks) {
                        mark.replaceWith(document.createTextNode(mark.textContent || ''));
                    }
                    contentElement.normalize();
                    findMatches.length = 0;
                    findState.currentIndex = -1;
                }

                function updateActiveFindMatch(shouldScroll) {
                    findMatches.forEach((mark, index) => {
                        if (index === findState.currentIndex) {
                            mark.setAttribute('data-find-active', 'true');
                        } else {
                            mark.removeAttribute('data-find-active');
                        }
                    });
                    publishFindResults();
                    if (shouldScroll && findState.currentIndex >= 0) {
                        findMatches[findState.currentIndex].scrollIntoView({
                            block: 'center',
                            inline: 'nearest',
                            behavior: 'auto',
                        });
                    }
                }

                function highlightMatches(query, preserveIndex) {
                    const previousIndex = findState.currentIndex;
                    viewerState.findQuery = query;
                    clearFindHighlights();

                    if (!query) {
                        publishFindResults();
                        return;
                    }

                    const queryLower = query.toLocaleLowerCase();
                    const textNodes = [];
                    const walker = document.createTreeWalker(
                        contentElement,
                        NodeFilter.SHOW_TEXT,
                        {
                            acceptNode(node) {
                                if (!node.textContent || !node.textContent.trim()) {
                                    return NodeFilter.FILTER_REJECT;
                                }
                                const parent = node.parentElement;
                                if (!parent) {
                                    return NodeFilter.FILTER_REJECT;
                                }
                                if (
                                    parent.closest(
                                        'script, style, mark[data-stillmd-find="true"], pre.stillmd-mermaid-block'
                                    )
                                ) {
                                    return NodeFilter.FILTER_REJECT;
                                }
                                return NodeFilter.FILTER_ACCEPT;
                            },
                        }
                    );

                    while (walker.nextNode()) {
                        textNodes.push(walker.currentNode);
                    }

                    for (const node of textNodes) {
                        const originalText = node.textContent || '';
                        const lowerText = originalText.toLocaleLowerCase();
                        let matchIndex = lowerText.indexOf(queryLower);

                        if (matchIndex === -1) {
                            continue;
                        }

                        const fragment = document.createDocumentFragment();
                        let cursor = 0;

                        while (matchIndex !== -1) {
                            if (matchIndex > cursor) {
                                fragment.appendChild(
                                    document.createTextNode(originalText.slice(cursor, matchIndex))
                                );
                            }

                            const matchText = originalText.slice(matchIndex, matchIndex + query.length);
                            const mark = document.createElement('mark');
                            mark.className = 'stillmd-find-match';
                            mark.dataset.stillmdFind = 'true';
                            mark.textContent = matchText;
                            fragment.appendChild(mark);
                            findMatches.push(mark);

                            cursor = matchIndex + query.length;
                            matchIndex = lowerText.indexOf(queryLower, cursor);
                        }

                        if (cursor < originalText.length) {
                            fragment.appendChild(document.createTextNode(originalText.slice(cursor)));
                        }

                        node.parentNode.replaceChild(fragment, node);
                    }

                    if (!findMatches.length) {
                        publishFindResults();
                        return;
                    }

                    findState.currentIndex = preserveIndex && previousIndex >= 0
                        ? Math.min(previousIndex, findMatches.length - 1)
                        : 0;

                    updateActiveFindMatch(true);
                }

                function updateFindQuery(query) {
                    highlightMatches(query, false);
                }

                function navigateFind(direction) {
                    if (!findMatches.length) {
                        publishFindResults();
                        return;
                    }

                    if (direction === 'previous') {
                        findState.currentIndex =
                            (findState.currentIndex - 1 + findMatches.length) % findMatches.length;
                    } else {
                        findState.currentIndex = (findState.currentIndex + 1) % findMatches.length;
                    }

                    updateActiveFindMatch(true);
                }

                function applyTheme() {
                    document.documentElement.setAttribute('data-theme', viewerState.themePreference);
                    document.documentElement.setAttribute(
                        'data-theme-preference',
                        viewerState.themePreference
                    );
                }

                function setThemePreference(nextThemePreference) {
                    viewerState.themePreference = nextThemePreference === 'dark' ? 'dark' : 'light';
                    applyTheme();
                    void renderMermaidBlocks();
                }

                function setTextScale(nextTextScale) {
                    const clampedScale = Math.min(Math.max(nextTextScale, 0.85), 1.30);
                    document.documentElement.style.setProperty('--text-scale', clampedScale);
                }

                // Intercept external link clicks
                document.addEventListener('click', function(e) {
                    const link = e.target.closest('a');
                    if (link && link.href) {
                        const url = new URL(link.href);
                        if (url.protocol === 'javascript:') {
                            e.preventDefault();
                            return;
                        }
                        if (url.protocol === 'http:' || url.protocol === 'https:') {
                            e.preventDefault();
                            postMessageIfAvailable(linkClickedHandler, link.href);
                        }
                    }
                });

                window.__stillmdBootPhase = 'theme-ready';
                setThemePreference(initialThemePreference);
                setTextScale(initialTextScale);

                let scrollState = { pending: false };
                function reportScroll() {
                    postMessageIfAvailable(scrollHandler, window.scrollY);
                }
                function scheduleScrollReport() {
                    if (scrollState.pending) {
                        return;
                    }
                    scrollState.pending = true;
                    requestAnimationFrame(() => {
                        scrollState.pending = false;
                        reportScroll();
                    });
                }
                function restoreScrollPosition(targetY) {
                    requestAnimationFrame(() => {
                        const maxY = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
                        window.scrollTo(0, Math.min(targetY, maxY));
                        scheduleScrollReport();
                    });
                }
                window.addEventListener('scroll', function() {
                    scheduleScrollReport();
                }, { passive: true });

                // Global updateContent function for live reload
                function updateContent(md, targetScrollY) {
                    renderMarkdown(md)
                        .then(() => {
                            restoreScrollPosition(targetScrollY);
                        })
                        .catch(error => {
                            window.__stillmdLastError = error && error.stack ? String(error.stack) : String(error);
                            restoreScrollPosition(targetScrollY);
                        });
                }

                window.__stillmdBootPhase = 'before-render';

                renderMarkdown(md)
                    .then(() => {
                        window.__stillmdBootPhase = 'after-render';
                        restoreScrollPosition(initialScrollY);
                        window.__stillmdBootPhase = 'ready';
                    })
                    .catch(error => {
                        window.__stillmdBootPhase = 'caught-error';
                        window.__stillmdLastError = error && error.stack ? String(error.stack) : String(error);
                        const contentElement = document.getElementById('content');
                        if (contentElement && !contentElement.innerHTML) {
                            contentElement.innerHTML = '<pre class="stillmd-render-error"></pre>';
                            contentElement.firstChild.textContent = window.__stillmdLastError;
                        }
                    });
                } catch (error) {
                    window.__stillmdBootPhase = 'caught-error';
                    window.__stillmdLastError = error && error.stack ? String(error.stack) : String(error);
                    const contentElement = document.getElementById('content');
                    if (contentElement && !contentElement.innerHTML) {
                        contentElement.innerHTML = '<pre class="stillmd-render-error"></pre>';
                        contentElement.firstChild.textContent = window.__stillmdLastError;
                    }
                }
            </script>
        </body>
        </html>
        """
    }
}
