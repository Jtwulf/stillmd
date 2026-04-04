// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "stillmd",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "stillmd",
            path: "stillmd",
            exclude: ["Info.plist"],
            resources: [
                .copy("Resources/marked.min.js"),
                .copy("Resources/highlight.min.js"),
                .copy("Resources/preview.css")
            ]
        ),
        .testTarget(
            name: "stillmdTests",
            dependencies: ["stillmd"],
            path: "stillmdTests"
        ),
    ]
)
