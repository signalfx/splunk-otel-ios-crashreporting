// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "SplunkOtelCrashReporting",
    platforms: [
        .iOS(.v11),
	.macOS(.v10_13)
    ],
    products: [
        .library(name: "SplunkOtelCrashReporting", targets: ["SplunkOtelCrashReporting"])
    ],
    dependencies: [
        .package(name: "SplunkOtel", url:"https://github.com/signalfx/splunk-otel-ios", from: "0.4.0"),
        .package(name: "PLCrashReporter", url:"https://github.com/microsoft/plcrashreporter", from: "1.8.0")
    ],
    targets: [
        .target(
            name: "SplunkOtelCrashReporting",
            dependencies: [
                .product(name: "CrashReporter", package: "PLCrashReporter"),
		.product(name: "SplunkOtel", package: "SplunkOtel")
            ],
	    path: "SplunkRumCrashReporting",
	    exclude: [ 
		"SplunkRumCrashReportingTests", 
		"SplunkRumCrashReporting/SplunkRumCrashReporting.h",
		"SplunkRumCrashReporting/Info.plist"
	    ],
	    sources: [ "SplunkRumCrashReporting" ]
        )
    ]
)
