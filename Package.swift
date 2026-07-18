// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Llamaboard",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // Backend: GGUF parsing, model library, server process manager, chat client.
        // Foundation-only so it can be reused by the app, CLI tools, and tests.
        .target(
            name: "LlamaboardKit",
            path: "Sources/LlamaboardKit"
        ),
        .executableTarget(
            name: "Llamaboard",
            dependencies: ["LlamaboardKit"],
            path: "Sources/Llamaboard",
            resources: [.copy("Resources/AppLogo.png")]
        ),
        // Headless end-to-end smoke test: parse GGUF → start server → stream chat → stop.
        .executableTarget(
            name: "llamaboard-smoke",
            dependencies: ["LlamaboardKit"],
            path: "Sources/llamaboard-smoke"
        ),
        // Assert-based unit tests (executable because swift-testing/XCTest aren't
        // available with Command Line Tools alone). Run: swift run llamaboard-tests
        .executableTarget(
            name: "llamaboard-tests",
            dependencies: ["LlamaboardKit"],
            path: "Sources/llamaboard-tests"
        )
    ]
)
