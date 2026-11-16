// swift-tools-version: 5.9
// Phần riêng iOS của Xử lý PDF ảnh: nhận dạng chữ bằng Tesseract 4.1.1 (gói libtesseract dựng sẵn của SwiftyTesseract,
// giấy phép MIT; Tesseract Apache 2.0, Leptonica BSD) và rung báo.

import PackageDescription

let package = Package(
    name: "xlpdf_ios",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "xlpdf-ios", targets: ["xlpdf_ios"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(url: "https://github.com/SwiftyTesseract/libtesseract.git", exact: "0.2.0"),
    ],
    targets: [
        .target(
            name: "xlpdf_ios",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "libtesseract", package: "libtesseract"),
            ],
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedLibrary("c++"),
            ]
        )
    ]
)
