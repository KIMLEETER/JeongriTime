// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "JeongriTime",
    defaultLocalization: "ko",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .executable(name: "JeongriTime", targets: ["JeongriTime"])
    ],
    targets: [
        .executableTarget(
            name: "JeongriTime",
            linkerSettings: [
                .linkedFramework("AuthenticationServices"),
                .linkedFramework("EventKit")
            ]
        ),
        .testTarget(
            name: "JeongriTimeTests",
            dependencies: ["JeongriTime"]
        )
    ]
)
