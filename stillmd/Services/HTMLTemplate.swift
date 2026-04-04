import Foundation

enum HTMLTemplate {
    static func build(
        markdownContent: String,
        markedJS: String,
        highlightJS: String,
        css: String,
        initialScrollPosition: Double = 0,
        themePreference: String = ThemePreference.system.rawValue,
        textScale: Double = AppPreferences.defaultTextScale
    ) -> String {
        let escapedMarkdown = markdownContent
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "</script>", with: "<\\/script>")
        let escapedThemePreference = themePreference
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src file: data: https: http:;">
            <style>\(css)</style>
            <script>\(markedJS)</script>
            <script>\(highlightJS)</script>
        </head>
        <body>
            <div id="content"></div>
            <script>
                // Strip raw HTML blocks from markdown output for security.
                // This prevents injected <img onerror=...>, <script>, javascript: links, etc.
                marked.use({
                    renderer: {
                        html(token) { return ''; }
                    }
                });

                // marked.js configuration: GFM enabled
                marked.setOptions({
                    gfm: true,
                    breaks: false,
                    highlight: function(code, lang) {
                        if (lang && hljs.getLanguage(lang)) {
                            return hljs.highlight(code, { language: lang }).value;
                        }
                        return code;
                    }
                });

                // Initial render
                const md = `\(escapedMarkdown)`;
                const contentElement = document.getElementById('content');
                const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
                const scrollHandler = window.webkit.messageHandlers.scrollPosition;
                const findResultsHandler = window.webkit.messageHandlers.findResults;
                const initialScrollY = \(initialScrollPosition);
                const initialThemePreference = "\(escapedThemePreference)";
                const initialTextScale = \(textScale);
                const viewerState = {
                    themePreference: initialThemePreference,
                    findQuery: '',
                };
                let findMatches = [];
                let findState = { currentIndex: -1 };

                function renderMarkdown(source) {
                    contentElement.innerHTML = marked.parse(source);
                    hljs.highlightAll();
                    if (viewerState.findQuery) {
                        highlightMatches(viewerState.findQuery, true);
                    } else {
                        publishFindResults();
                    }
                }

                function publishFindResults() {
                    findResultsHandler.postMessage({
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
                            window.webkit.messageHandlers.linkClicked.postMessage(link.href);
                        }
                    }
                });

                // Dark mode detection
                function updateTheme(e) {
                    applyTheme();
                }
                mediaQuery.addEventListener('change', updateTheme);
                setThemePreference(initialThemePreference);
                setTextScale(initialTextScale);

                let scrollState = { pending: false };
                function reportScroll() {
                    scrollHandler.postMessage(window.scrollY);
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

                renderMarkdown(md);
                restoreScrollPosition(initialScrollY);
            </script>
        </body>
        </html>
        """
    }
}
