// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Prisma",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Prisma", targets: ["Prisma"])
    ],
    targets: [
        .target(
            name: "UpdateCore",
            path: "Sources/UpdateCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "Prisma",
            dependencies: ["UpdateCore"],
            path: "Sources/Prisma",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "UpdateSigner",
            dependencies: ["UpdateCore"],
            path: "Sources/UpdateSigner",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "UpdateCoreTests",
            dependencies: ["UpdateCore"],
            path: "Tests/UpdateCoreTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
