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

import Foundation
import CrashReporter
import SplunkOtel
import OpenTelemetryApi

let CrashReportingVersionString = "0.2.0"

var TheCrashReporter: PLCrashReporter?

let sessionIdKey   = "SessionID"
let screenNameKey = "ScreenName"

func initializeCrashReporting() {
    let startupSpan = buildTracer().spanBuilder(spanName: "SplunkRumCrashReporting").startSpan()
    startupSpan.setAttribute(key: "component", value: "appstart")
    defer {
        startupSpan.end()
    }
    let config = PLCrashReporterConfig(signalHandlerType: .BSD, symbolicationStrategy: PLCrashReporterSymbolicationStrategy(rawValue: 0) /* none */)
    let crashReporter_ = PLCrashReporter(configuration: config)
    if crashReporter_ == nil {
        startupSpan.setAttribute(key: "error.message", value: "Cannot construct PLCrashReporter")
        SplunkRum.debugLog("Cannot construct PLCrashReporter")
        return
    }
    let crashReporter = crashReporter_!
    let success = crashReporter.enable()
    SplunkRum.debugLog("PLCrashReporter enabled: "+success.description)
    if !success {
        startupSpan.setAttribute(key: "error.message", value: "Cannot enable PLCrashReporter")
        return
    }
    TheCrashReporter = crashReporter
    updateCrashReportSessionId()
    SplunkRum.addSessionIdChangeCallback {
        updateCrashReportSessionId()
    }
    SplunkRum.addScreenNameChangeCallback { name in
        updateCrashReportScreenName(screenname: name)
    }
    // Now for the pending report if there is one
    if !crashReporter.hasPendingCrashReport() {
        return
    }
    SplunkRum.debugLog("Had a pending crash report")
    do {
        let data = crashReporter.loadPendingCrashReportData()
        try loadPendingCrashReport(data)
    } catch {
        SplunkRum.debugLog("Error loading crash report: \(error)")
        startupSpan.setAttribute(key: "error.message", value: "Cannot load crash report")
        // yes, fall through to purge
    }
    crashReporter.purgePendingCrashReport()

}
private func buildTracer() -> Tracer {
    return OpenTelemetry.instance.tracerProvider.get(instrumentationName: "splunk-ios-crashreporting", instrumentationVersion: CrashReportingVersionString)

}

func dataToDictionary(data: Data) -> [String: String]? {
    let dicFromData = try? PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.ReadOptions.mutableContainers, format: nil)
    return dicFromData as? [String: String]
}

func dictionaryToData(dict: [String: String]) -> Data? {
    let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: PropertyListSerialization.PropertyListFormat.binary, options: 0)
    return data
}

func updateCrashReportSessionId() {
    DispatchQueue.main.async {
        saveSessionIDIntoCustomData()
    }
}

func saveSessionIDIntoCustomData() {
   if let dict = fetchFromCustomData() {
        let screenName = dict[screenNameKey] ?? ""
        saveIntoCustomData(dict: [sessionIdKey: SplunkRum.getSessionId(), screenNameKey: screenName])
    } else {
        saveIntoCustomData(dict: [sessionIdKey: SplunkRum.getSessionId()])
    }
}

func saveScreenNameIntoCustomData(screenname: String) {
    if let dict = fetchFromCustomData() {
        let oldsessionid = dict[sessionIdKey] ?? ""
        saveIntoCustomData(dict: [sessionIdKey: oldsessionid, screenNameKey: screenname])
    } else {
         saveIntoCustomData(dict: [screenNameKey: screenname])
    }
}

func saveIntoCustomData(dict: [String: String]) {
    TheCrashReporter?.customData = dictionaryToData(dict: dict)
}

func fetchFromCustomData() -> [String: String]? {
    guard let data = TheCrashReporter?.customData else { return nil}
    let dicFromData = dataToDictionary(data: data)
    return dicFromData
}
func updateCrashReportScreenName(screenname: String) {
    DispatchQueue.main.async {
        saveScreenNameIntoCustomData(screenname: screenname)
    }
}
func loadPendingCrashReport(_ data: Data!) throws {
    SplunkRum.debugLog("Loading crash report of size \(data?.count as Any)")
    let report = try PLCrashReport(data: data)
    var exceptionType = report.signalInfo.name
    if report.hasExceptionInfo {
        exceptionType = report.exceptionInfo.exceptionName
    }

    guard let dict = dataToDictionary(data: report.customData) else {return}
    let oldSessionId = dict[sessionIdKey] ?? ""
    let screenName = dict[screenNameKey] ?? ""
    // Turn the report into a span
    let now = Date()
    let span = buildTracer().spanBuilder(spanName: exceptionType ?? "unknown").setStartTime(time: now).setNoParent().startSpan()
    span.setAttribute(key: "component", value: "crash")
    span.setAttribute(key: "crash.rumSessionId", value: oldSessionId)
    // "marketing version" here matches up to our use of CFBundleShortVersionString
    span.setAttribute(key: "crash.app.version", value: report.applicationInfo.applicationMarketingVersion)
    span.setAttribute(key: "error", value: true)
    span.addEvent(name: "crash.timestamp", timestamp: report.systemInfo.timestamp)
    span.setAttribute(key: "exception.type", value: exceptionType ?? "unknown")
    span.setAttribute(key: "crash.address", value: report.signalInfo.address.description)
    span.setAttribute(key: "screen.name", value: screenName)
    for case let thread as PLCrashReportThreadInfo in report.threads where thread.crashed {
        span.setAttribute(key: "exception.stacktrace", value: crashedThreadToStack(report: report, thread: thread))
        break
    }
    if report.hasExceptionInfo {
        span.setAttribute(key: "exception.type", value: report.exceptionInfo.exceptionName)
        span.setAttribute(key: "exception.message", value: report.exceptionInfo.exceptionReason)
    }
    span.end(time: now)
}

// FIXME this is a messy copy+paste of select bits of PLCrashReportTextForamtter
func crashedThreadToStack(report: PLCrashReport, thread: PLCrashReportThreadInfo) -> String {
    let text = NSMutableString()
    text.appendFormat("Thread %ld", thread.threadNumber)
    var frameNum = 0
    while frameNum < thread.stackFrames.count {
        let str = formatStackFrame(
            // swiftlint:disable:next force_cast
            frame: thread.stackFrames[frameNum] as! PLCrashReportStackFrameInfo,
            frameNum: frameNum,
            report: report)
        text.append(str)
        text.append("\n")
        frameNum += 1
    }
    return String(text)
}

func formatStackFrame(frame: PLCrashReportStackFrameInfo, frameNum: Int, report: PLCrashReport) -> String {
    var baseAddress: UInt64 = 0
    var pcOffset: UInt64 = 0
    var imageName = "???"
    var symbolString: String?
    let imageInfo = report.image(forAddress: frame.instructionPointer)
    if imageInfo != nil {
        imageName = imageInfo!.imageName
        imageName = URL(fileURLWithPath: imageName).lastPathComponent
        baseAddress = imageInfo!.imageBaseAddress
        pcOffset = frame.instructionPointer - imageInfo!.imageBaseAddress
    }
    if frame.symbolInfo != nil {
        let symbolName = frame.symbolInfo.symbolName
        let symOffset = frame.instructionPointer - frame.symbolInfo.startAddress
        symbolString =  String(format: "%@ + %ld", symbolName!, symOffset)
    } else {
        symbolString = String(format: "0x%lx + %ld", baseAddress, pcOffset)
    }
    return String(format: "%-4ld%-35@ 0x%016lx %@", frameNum, imageName, frame.instructionPointer, symbolString!)
}

/**
  Call start() *after* SplunkRum.initialize()
*/
@objc public class SplunkRumCrashReporting: NSObject {
/**
  Call start() *after* SplunkRum.initialize()
*/
  @objc public class func start() {
   initializeCrashReporting()
  }
}
