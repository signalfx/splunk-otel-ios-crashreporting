# Splunk OpenTelemetry iOS agent Crash Reporting module

This is an addon to the [Splunk RUM iOS agent](https://github.com/signalfx/splunk-otel-ios)
that adds crash reporting via [PLCrashReporter](https://github.com/microsoft/plcrashreporter).

> :construction: This project is currently in **BETA**. It is **officially supported** by Splunk. However, breaking changes **MAY** be introduced.

## Getting Started

To get started, first follow the instructions to add the SplunkOtel package
to your application, then import this optional crash reporting package into your app, 
either through the Xcode menu
`File -> Swift Packages -> Add Package Dependency` or through your `Package.swift`:

```swift
.package(url: "https://github.com/signalfx/splunk-otel-ios/", from: "0.13.0");
.package(url: "https://github.com/signalfx/splunk-otel-ios-crashreporting/", from: "0.7.0");
...
.target(name: "MyAwesomeApp", dependencies: ["SplunkOtel", "SplunkOtelCrashReporting]),
```

You'll then need to start the crash reporting **after** initializing the 
SplunkRum library:


```swift
import SplunkOtel
import SplunkOtelCrashReporting
...
// Your realm and rum-token will be provided by your friendly Splunk representative
SplunkRumBuilder(realm: "<realm>", rumAuth: "<rum-token>")
   .deploymentEnvironment(environment: "<environment>")
   .setApplicationName("<your_app_name>")
   .build()
// Initialize crash reporting module after the iOS agent
SplunkRumCrashReporting.start()
```

or

```objectivec
@import SplunkOtel;
@import SplunkOtelCrashReporting;
...
// Your realm and rum-token will be provided by your friendly Splunk representative
SplunkRumBuilder *builder = [[SplunkRumBuilder alloc] initWithRealm:@"<realm>"  rumAuth: @"<rum-token>"]];
[builder deploymentEnvironmentWithEnvironment:@"<environment-name>"];
[builder setApplicationName:@"<your_app_name>"];
[builder build];
// Initialize crash reporting module after the iOS agent
[SplunkRumCrashReporting start]
```

## Version information

- This library is compatible with iOS 15 and up (and iPadOS 15 and up)

## Building and contributing

Please read [CONTRIBUTING.md](./CONTRIBUTING.md) for instructions on building, running tests, and so forth.

## License

This library is licensed under the terms of the Apache Softare License version 2.0.
See [the license file](./LICENSE) for more details.

>ℹ️&nbsp;&nbsp;SignalFx was acquired by Splunk in October 2019. See [Splunk SignalFx](https://www.splunk.com/en_us/investor-relations/acquisitions/signalfx.html) for more information.
