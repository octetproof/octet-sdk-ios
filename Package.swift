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
            url: "https://github.com/octetproof/octet-sdk-ios/releases/download/0.0.4-alpha/OctetSDK.xcframework.zip",
            checksum: "d3e02a96d136293069f6344e128ba6399ab42fc6ee9f215988fe570d48abc90d"
        ),
    ]
)
