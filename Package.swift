// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "SplunkRumCrashReporting",
    platforms: [
        .iOS(.v11),
	.macOS(.v10_13)
    ],
    products: [
        .library(name: "SplunkRumCrashReporting", targets: ["SplunkRumCrashReporting"])
    ],
    dependencies: [
        .package(name: "SplunkRum", url:"https://github.com/signalfx/splunk-otel-ios", from: "0.2.0"),
        .package(name: "PLCrashReporter", url:"https://github.com/microsoft/plcrashreporter", from: "1.8.0")
    ],
    targets: [
        .target(
            name: "SplunkRumCrashReporting",
            dependencies: [
                .product(name: "CrashReporter", package: "PLCrashReporter"),
		.product(name: "SplunkRum", package: "SplunkRum")
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
