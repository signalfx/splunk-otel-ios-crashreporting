//
/*
Copyright 2021 Splunk Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

// Why not "import SplunkOtelCrashReporting"?  Because this is linked as a local library and not as a swift package
// FIXME align the library name, file structure, etc. with the new swift package name
@testable import SplunkRumCrashReporting
import SplunkOtel
import Foundation
import XCTest
import OpenTelemetryApi
import OpenTelemetrySdk

var localSpans: [SpanData] = []

class TestSpanExporter: SpanExporter {
    var exportSucceeds = true

    func export(spans: [SpanData]) -> SpanExporterResultCode {
        if exportSucceeds {
            localSpans.append(contentsOf: spans)
            return .success
        } else {
            return .failure
        }
    }

    func flush() -> SpanExporterResultCode { return .success }
    func shutdown() { }
}

class CrashTests: XCTestCase {
    func testBasics() throws {
        let crashPath = Bundle(for: CrashTests.self).url(forResource: "sample", withExtension: "plcrash")!
        let crashData = try Data(contentsOf: crashPath)

        SplunkRum.initialize(beaconUrl: "http://127.0.0.1:8989/v1/traces", rumAuth: "FAKE", options: SplunkRumOptions(allowInsecureBeacon: true, debug: true))
        OpenTelemetrySDK.instance.tracerProvider.addSpanProcessor(SimpleSpanProcessor(spanExporter: TestSpanExporter()))
        localSpans.removeAll()

        SplunkRumCrashReporting.start()
        try loadPendingCrashReport(crashData)

        XCTAssertEqual(localSpans.count, 2)
        let crashReport = localSpans.first(where: { (span) -> Bool in
            return span.name == "SIGILL"
        })
        let startup = localSpans.first(where: { (span) -> Bool in
            return span.name == "SplunkRumCrashReporting"
        })

        XCTAssertNotNil(crashReport)
        XCTAssertNotEqual(crashReport!.attributes["splunk.rumSessionId"], crashReport!.attributes["crash.rumSessionId"])
        XCTAssertEqual(crashReport!.attributes["crash.rumSessionId"]?.description, "355ecc42c29cf0b56c411f1eab9191d0")
        XCTAssertEqual(crashReport!.attributes["crash.address"]?.description, "140733995048756")
        XCTAssertEqual(crashReport!.attributes["component"]?.description, "crash")
        XCTAssertEqual(crashReport!.attributes["error"]?.description, "true")
        XCTAssertEqual(crashReport!.attributes["exception.type"]?.description, "SIGILL")
        XCTAssertTrue(crashReport!.attributes["exception.stacktrace"]?.description.contains("UIKitCore") ?? false)

        XCTAssertNotNil(startup)
        XCTAssertEqual(startup!.attributes["component"]?.description, "appstart")
        
        XCTAssertNotNil(crashReport!.attributes["screen.name"])

    }
}
