// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FloatingTodoTimer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FloatingTodoTimer", targets: ["FloatingTodoTimer"])
    ],
    targets: [
        .executableTarget(
            name: "FloatingTodoTimer",
            path: "Sources/FloatingTodoTimer"
        ),
        .testTarget(
            name: "FloatingTodoTimerTests",
            dependencies: ["FloatingTodoTimer"],
            path: "Tests/FloatingTodoTimerTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
