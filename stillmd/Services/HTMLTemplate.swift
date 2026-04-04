import Foundation

enum HTMLTemplate {
    static func build(
        markdownContent: String,
        markedJS: String,
        highlightJS: String,
        css: String,
        initialScrollPosition: Double = 0,
        themePreference: String = ThemePreference.system.rawValue,
        textScale: Double = AppPreferences.defaultTextScale,
        documentLineNumbersVisible: Bool = false,
        documentBaseURL: URL? = nil
    ) -> String {
        // Base64 keeps `${…}`, backticks, quotes, and `</script>` from breaking out of the HTML `<script>` block
        // or being interpreted as JS (template literals / unterminated strings → blank WebView).
        let markdownBase64 = Data(markdownContent.utf8).base64EncodedString()
        let escapedThemePreference = themePreference
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let baseTag = documentBaseURL.map { url in
            let href = url.absoluteString
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
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
        </head>
        <body>
            <div id="document-line-number-overlay" aria-hidden="true">
                <div id="document-line-number-column"></div>
            </div>
            <div id="content"></div>
            <script>
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
                const documentLineNumberOverlay = document.getElementById('document-line-number-overlay');
                const documentLineNumberColumn = document.getElementById('document-line-number-column');
                const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
                const messageHandlers = window.webkit?.messageHandlers ?? {};
                const scrollHandler = messageHandlers.scrollPosition ?? null;
                const findResultsHandler = messageHandlers.findResults ?? null;
                const linkClickedHandler = messageHandlers.linkClicked ?? null;
                const initialScrollY = \(initialScrollPosition);
                const initialThemePreference = "\(escapedThemePreference)";
                const initialTextScale = \(textScale);
                const initialDocumentLineNumbersVisible = \(documentLineNumbersVisible ? "true" : "false");
                const viewerState = {
                    themePreference: initialThemePreference,
                    findQuery: '',
                    documentLineNumbersVisible: initialDocumentLineNumbersVisible,
                };
                let findMatches = [];
                let findState = { currentIndex: -1 };
                let documentLineNumberLayoutPending = false;
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

                function renderCodeBlock(codeElement) {
                    const pre = codeElement.parentElement;
                    if (!pre || pre.dataset.stillmdCodeDecorated === 'true') {
                        return;
                    }

                    pre.dataset.stillmdCodeDecorated = 'true';

                    const language = getCodeLanguage(codeElement);
                    const rawText = codeElement.textContent || '';
                    const lines = rawText.split(/\\r?\\n/);

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

                function clearDocumentLineNumbers() {
                    documentLineNumberColumn.replaceChildren();
                    document.documentElement.style.setProperty('--document-line-number-gutter-width', '0px');
                }

                function scheduleDocumentLineNumberLayout() {
                    if (!viewerState.documentLineNumbersVisible) {
                        clearDocumentLineNumbers();
                        return;
                    }

                    if (documentLineNumberLayoutPending) {
                        return;
                    }

                    documentLineNumberLayoutPending = true;
                    requestAnimationFrame(() => {
                        documentLineNumberLayoutPending = false;
                        layoutDocumentLineNumbers();
                    });
                }

                function layoutDocumentLineNumbers() {
                    if (!viewerState.documentLineNumbersVisible) {
                        clearDocumentLineNumbers();
                        return;
                    }

                    const bodyRect = document.body.getBoundingClientRect();
                    const candidates = contentElement.querySelectorAll(
                        'h1, h2, h3, h4, h5, h6, p, li, tr, hr, .stillmd-code-line'
                    );
                    const rows = [];
                    let lineNumber = 1;

                    for (const candidate of candidates) {
                        if (candidate.tagName === 'P' && candidate.closest('li')) {
                            continue;
                        }

                        if (candidate.tagName === 'LI' && candidate.querySelector('p, .stillmd-code-line')) {
                            continue;
                        }

                        const range = document.createRange();
                        range.selectNodeContents(candidate);
                        let rects = Array.from(range.getClientRects()).filter((rect) => {
                            return rect.width > 0 && rect.height > 0;
                        });

                        if (!rects.length) {
                            const fallbackRect = candidate.getBoundingClientRect();
                            if (fallbackRect.width > 0 || fallbackRect.height > 0) {
                                rects = [fallbackRect];
                            }
                        }

                        for (const rect of rects) {
                            const row = document.createElement('div');
                            row.className = 'document-line-number';
                            row.textContent = String(lineNumber++);
                            row.style.top = `${rect.top - bodyRect.top}px`;
                            row.style.height = `${Math.max(rect.height, 1)}px`;
                            rows.push(row);
                        }
                    }

                    documentLineNumberColumn.replaceChildren(...rows);
                    const digits = String(Math.max(1, lineNumber - 1)).length;
                    document.documentElement.style.setProperty(
                        '--document-line-number-gutter-width',
                        `${Math.max(2, digits + 1)}ch`
                    );
                }

                function renderMarkdown(source) {
                    contentElement.innerHTML = marked.parse(source);
                    decorateCodeBlocks();
                    if (viewerState.findQuery) {
                        highlightMatches(viewerState.findQuery, true);
                    } else {
                        publishFindResults();
                    }
                    scheduleDocumentLineNumberLayout();
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
                                if (parent.closest('script, style, mark[data-stillmd-find="true"]')) {
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
                    scheduleDocumentLineNumberLayout();
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
                    scheduleDocumentLineNumberLayout();
                }

                function applyTheme() {
                    const resolvedTheme = viewerState.themePreference === 'system'
                        ? (mediaQuery.matches ? 'dark' : 'light')
                        : viewerState.themePreference;
                    document.documentElement.setAttribute('data-theme', resolvedTheme);
                    document.documentElement.setAttribute(
                        'data-theme-preference',
                        viewerState.themePreference
                    );
                }

                function setThemePreference(nextThemePreference) {
                    viewerState.themePreference = nextThemePreference || 'system';
                    applyTheme();
                    scheduleDocumentLineNumberLayout();
                }

                function setTextScale(nextTextScale) {
                    const clampedScale = Math.min(Math.max(nextTextScale, 0.85), 1.30);
                    document.documentElement.style.setProperty('--text-scale', clampedScale);
                    scheduleDocumentLineNumberLayout();
                }

                function setDocumentLineNumbersVisible(nextVisible) {
                    viewerState.documentLineNumbersVisible = !!nextVisible;
                    if (!viewerState.documentLineNumbersVisible) {
                        clearDocumentLineNumbers();
                        return;
                    }
                    scheduleDocumentLineNumberLayout();
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

                // Dark mode detection
                function updateTheme(e) {
                    applyTheme();
                }
                mediaQuery.addEventListener('change', updateTheme);
                window.__stillmdBootPhase = 'theme-ready';
                setThemePreference(initialThemePreference);
                setTextScale(initialTextScale);
                setDocumentLineNumbersVisible(initialDocumentLineNumbersVisible);

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
                window.addEventListener('scroll', scheduleScrollReport, { passive: true });

                // Global updateContent function for live reload
                function updateContent(md, targetScrollY) {
                    renderMarkdown(md);
                    restoreScrollPosition(targetScrollY);
                }

                const resizeObserver = new ResizeObserver(() => {
                    scheduleDocumentLineNumberLayout();
                });
                resizeObserver.observe(contentElement);
                resizeObserver.observe(document.body);
                window.addEventListener('resize', scheduleDocumentLineNumberLayout);
                window.__stillmdBootPhase = 'before-render';

                renderMarkdown(md);
                window.__stillmdBootPhase = 'after-render';
                restoreScrollPosition(initialScrollY);
                window.__stillmdBootPhase = 'ready';
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
