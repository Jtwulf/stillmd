import Foundation

enum HTMLTemplate {
    static func build(
        markdownContent: String,
        markedJS: String,
        highlightJS: String,
        css: String
    ) -> String {
        let escapedMarkdown = markdownContent
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>\(css)</style>
            <script>\(markedJS)</script>
            <script>\(highlightJS)</script>
        </head>
        <body>
            <div id="content"></div>
            <script>
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
                document.getElementById('content').innerHTML = marked.parse(md);
                hljs.highlightAll();

                // Intercept external link clicks
                document.addEventListener('click', function(e) {
                    const link = e.target.closest('a');
                    if (link && link.href) {
                        const url = new URL(link.href);
                        if (url.protocol === 'http:' || url.protocol === 'https:') {
                            e.preventDefault();
                            window.webkit.messageHandlers.linkClicked.postMessage(link.href);
                        }
                    }
                });

                // Dark mode detection
                const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
                function updateTheme(e) {
                    document.documentElement.setAttribute('data-theme',
                        e.matches ? 'dark' : 'light');
                }
                mediaQuery.addEventListener('change', updateTheme);
                updateTheme(mediaQuery);

                // Scroll position reporting
                function reportScroll() {
                    window.webkit.messageHandlers.scrollPosition.postMessage(window.scrollY);
                }

                // Global updateContent function for live reload
                function updateContent(md) {
                    const scrollY = window.scrollY;
                    document.getElementById('content').innerHTML = marked.parse(md);
                    hljs.highlightAll();
                    window.scrollTo(0, Math.min(scrollY, document.body.scrollHeight));
                }
            </script>
        </body>
        </html>
        """
    }
}
