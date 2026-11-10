// swift-tools-version:5.9
import PackageDescription

// The URL and checksum on the binaryTarget below are rewritten by the
// release workflow (release-ios.yml in octetproof/octet-sdk) on every
// tagged release. Pin to a tagged version in your consumer Package.swift;
// do not track `main`.

let package = Package(
    name: "OctetSDK",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "OctetSDK", targets: ["OctetSDK"])
    ],
    targets: [
        .binaryTarget(
            name: "OctetSDK",
            url: "https://github.com/octetproof/octet-sdk-ios/releases/download/3.1.1/OctetSDK.xcframework.zip",
            checksum: "bdb1e246baa253eb4f43e6b50bead407665e26d7fa08a2a9b1f6ba94b6d96105"
        ),
    ]
)
