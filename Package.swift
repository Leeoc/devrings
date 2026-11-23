// swift-tools-version:6.0
import PackageDescription

let cltFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

let package = Package(
    name: "DevRings",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DevRingsCore", swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))]),
        .executableTarget(name: "DevRings", dependencies: ["DevRingsCore"]),
        // `swift test` builds but never runs Swift Testing bundles under the Command Line Tools alone,
        // so the tests are an executable: `swift run DevRingsCoreTests`. The CLT also ship Swift Testing
        // outside the default framework path, without the Foundation cross-import overlay's module.
        .executableTarget(
            name: "DevRingsCoreTests",
            dependencies: ["DevRingsCore"],
            path: "Tests/DevRingsCoreTests",
            exclude: ["Fixtures"],
            swiftSettings: [.unsafeFlags(["-F", cltFrameworks, "-Xfrontend", "-disable-cross-import-overlays"])],
            linkerSettings: [.unsafeFlags(["-F", cltFrameworks, "-Xlinker", "-rpath", "-Xlinker", cltFrameworks])]
        ),
    ]
)
