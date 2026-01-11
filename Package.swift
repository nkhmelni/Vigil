// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "Vigil",
    platforms: [
        .iOS(.v14),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "Vigil",
            targets: ["Vigil"]
        )
    ],
    targets: [
        .target(
            name: "Vigil",
            path: "Sources/Vigil",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
                .define("VIGIL_VERSION", to: "\"1.0.0\"")
            ],
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("Foundation")
            ]
        ),
        .testTarget(
            name: "VigilTests",
            dependencies: ["Vigil"],
            path: "Tests/VigilTests"
        )
    ],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx14
)
