// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "LibWally",
    platforms: [
        .iOS(.v11)
    ],
    products: [
        .library(
            name: "LibWally",
            targets: ["LibWally", "LibWallyCore"]
        )
    ],
    targets: [
        .target(
            name: "LibWally",
            path: "LibWally"
        ),
        .target(
            name: "LibWallyCore",
            path: "CLibWally/libwally-core",
            sources: [
                "src"
            ]
        )
    ]
)
