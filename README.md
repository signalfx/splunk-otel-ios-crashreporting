# Splunk OpenTelemetry iOS agent Crash Reporting module

This is an addon to the [Splunk RUM iOS agent](https://github.com/signalfx/splunk-otel-ios)
that adds crash reporting via [PLCrashReporter](https://github.com/microsoft/plcrashreporter).

> :construction: This project is currently in **BETA**.

## Getting Started

To get started, first follow the instructions to add the SplunkRum package
to your application, then import this optional crash reporting package into your app, 
either through the Xcode menu
`File -> Swift Packages -> Add Package Dependency` or through your `Package.swift`:

```swift
.package(url: "https://github.com/signalfx/splunk-otel-ios-crashreporting/", from: "0.1");
...
.target(name: "MyAwesomeApp", dependencies: ["SplunkRum", "SplunkRumCrashReporting]),
```

You'll then need to initialize the crash reporting **after** initializing the 
SplunkRum library:


```swift
import SplunkRum
import SplunkRumCrashReporting
...
// Your beaconUrl and rumAuth will be provided by your friendly Splunk representative
SplunkRum.initialize(beaconUrl: "https://rum-ingest.us0.signalfx.com/v1/rum", rumAuth: "ABCD...")
SplunkRumCrashReporting.initialize()
```

or

```objectivec
@import SplunkRum;
@import SplunkRumCrashReporting;
...
// Your beaconUrl and rumAuth will be provided by your friendly Splunk representative
[SplunkRum initializeWithBeaconUrl: @"https://rum-ingest.us0.signalfx.com/v1/rum" rumAuth: @"ABCD..." options: nil];
[SplunkRumCrashReporting initialize]
```

## Version information

- This library is compatible with iOS 11 and up (and iPadOS 13 and up)

## Building and contributing

Please read [CONTRIBUTING.md](./CONTRIBUTING.md) for instructions on building, running tests, and so forth.

## License

This library is released under the terms of the Apache Softare License version 2.0.
See [the license file](./LICENSE) for more details.
