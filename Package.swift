// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Iles",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(name: "Iles", targets: ["Iles"]),
        .executable(name: "IlesTests", targets: ["IlesTests"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.19.0"),
    ],
    targets: [
        .target(
            name: "Domain",
            path: "Sources/Domain",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .target(
            name: "Infrastructure",
            dependencies: [
                "Domain",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/Infrastructure",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .target(
            name: "IslandGeometry",
            path: "Sources/IslandGeometry",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .target(
            name: "IlesCore",
            dependencies: [
                "Domain",
                "Infrastructure",
                "IslandGeometry",
            ],
            path: "Sources/Iles",
            exclude: [
                "Info.plist",
                "Iles.entitlements",
                "Resources/PrivacyInfo.xcprivacy",
                "Resources/Iles.icns",
                "Resources/IlesAppIcon.png",
            ],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .unsafeFlags(["-enable-testing"], .when(configuration: .debug)),
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "Iles",
            dependencies: [
                "IlesCore",
            ],
            path: "Sources/IlesApp",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "IlesTests",
            dependencies: [
                "IlesCore",
                "Domain",
                "Infrastructure",
                "IslandGeometry",
            ],
            path: "Tests/IlesTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
