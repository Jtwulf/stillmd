// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MarkdownPreviewer",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "MarkdownPreviewer",
            path: "MarkdownPreviewer",
            exclude: ["Info.plist"],
            resources: [
                .copy("Resources/marked.min.js"),
                .copy("Resources/highlight.min.js"),
                .copy("Resources/preview.css")
            ]
        ),
        .testTarget(
            name: "MarkdownPreviewerTests",
            dependencies: ["MarkdownPreviewer"],
            path: "MarkdownPreviewerTests"
        ),
    ]
)
