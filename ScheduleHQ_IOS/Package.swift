// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScheduleHQ",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "ScheduleHQ",
            targets: ["ScheduleHQ"]),
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "11.0.0"),
    ],
    targets: [
        .target(
            name: "ScheduleHQ",
            dependencies: [
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseMessaging", package: "firebase-ios-sdk"),
            ],
            path: "ScheduleHQ"),
    ]
)
