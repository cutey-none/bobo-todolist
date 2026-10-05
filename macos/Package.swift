// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QuadrantTodo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "QuadrantTodo",
            path: "Sources/QuadrantTodo"
        ),
        .testTarget(
            name: "QuadrantTodoTests",
            dependencies: ["QuadrantTodo"],
            path: "Tests/QuadrantTodoTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
