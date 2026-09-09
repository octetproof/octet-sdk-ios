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
            url: "https://github.com/octetproof/octet-sdk-ios/releases/download/2.0.0/OctetSDK.xcframework.zip",
            checksum: "8ef981b97f5566a83e4f03cf01cddd83e7bca078b7f7b503d1377198fc04c551"
        ),
    ]
)
