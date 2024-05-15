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

// Make sure the version numbers on the podspec and CrashReporting.swift match
let CrashReportingVersionString = "0.6.0"

var TheCrashReporter: PLCrashReporter?
private var customDataDictionary: [String: String] = [String: String]()

func initializeCrashReporting() {
    let startupSpan = buildTracer().spanBuilder(spanName: "SplunkRumCrashReporting").startSpan()
    startupSpan.setAttribute(key: "component", value: "appstart")
    defer {
        startupSpan.end()
    }
    let config = PLCrashReporterConfig(signalHandlerType: .BSD, symbolicationStrategy: .all /* all */)
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
    updateDeviceStats()
    startPollingForDeviceStats()
    SplunkRum.addSessionIdChangeCallback {
        updateCrashReportSessionId()
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

func updateCrashReportSessionId() {
   do {
       customDataDictionary["sessionId"] = SplunkRum.getSessionId()
       let customData = try NSKeyedArchiver.archivedData(withRootObject: customDataDictionary, requiringSecureCoding: false)
       TheCrashReporter?.customData = customData
   } catch {
        // We have failed to archive the custom data dictionary.
        SplunkRum.debugLog("Failed to add the sessionId to the crash reports custom data.")
   }
}

private func updateDeviceStats() {
    do {
        customDataDictionary["batteryLevel"] = DeviceStats.batteryLevel
        customDataDictionary["freeDiskSpace"] = DeviceStats.freeDiskSpace
        customDataDictionary["freeMemory"] = DeviceStats.freeMemory
        let customData = try NSKeyedArchiver.archivedData(withRootObject: customDataDictionary, requiringSecureCoding: false)
        TheCrashReporter?.customData = customData
    } catch {
        // We have failed to archive the custom data dictionary.
        SplunkRum.debugLog("Failed to add the device stats to the crash reports custom data.")
    }
}

/*
 Will poll every 5 seconds to update the device stats.
 */
private func startPollingForDeviceStats() {
    let repeatSeconds: Double = 5
    DispatchQueue.global(qos: .background).async {
        let timer = Timer.scheduledTimer(withTimeInterval: repeatSeconds, repeats: true) { _ in
            updateDeviceStats()
        }
        timer.fire()
    }
}

func loadPendingCrashReport(_ data: Data!) throws {
    SplunkRum.debugLog("Loading crash report of size \(data?.count as Any)")
    let report = try PLCrashReport(data: data)
    var exceptionType = report.signalInfo.name
    if report.hasExceptionInfo {
        exceptionType = report.exceptionInfo.exceptionName
    }
    // Turn the report into a span
    let now = Date()
    let span = buildTracer().spanBuilder(spanName: exceptionType ?? "unknown").setStartTime(time: now).setNoParent().startSpan()
    span.setAttribute(key: "component", value: "crash")
    if report.customData != nil {
        let customData = NSKeyedUnarchiver.unarchiveObject(with: report.customData) as? [String: String]
        if customData != nil {
            span.setAttribute(key: "crash.rumSessionId", value: customData!["sessionId"]!)
            span.setAttribute(key: "crash.batteryLevel", value: customData!["batteryLevel"]!)
            span.setAttribute(key: "crash.freeDiskSpace", value: customData!["freeDiskSpace"]!)
            span.setAttribute(key: "crash.freeMemory", value: customData!["freeMemory"]!)
        } else {
            span.setAttribute(key: "crash.rumSessionId", value: String(decoding: report.customData, as: UTF8.self))
        }
    }
    // "marketing version" here matches up to our use of CFBundleShortVersionString
    span.setAttribute(key: "crash.app.version", value: report.applicationInfo.applicationMarketingVersion)
    span.setAttribute(key: "error", value: true)
    span.addEvent(name: "crash.timestamp", timestamp: report.systemInfo.timestamp)
    span.setAttribute(key: "exception.type", value: exceptionType ?? "unknown")
    span.setAttribute(key: "crash.address", value: report.signalInfo.address.description)
    for case let thread as PLCrashReportThreadInfo in report.threads where thread.crashed {
        span.setAttribute(key: "exception.stacktrace", value: crashedThreadToStack(report: report, thread: thread))
        break
    }
    if report.hasExceptionInfo {
        span.setAttribute(key: "exception.type", value: report.exceptionInfo.exceptionName)
        span.setAttribute(key: "exception.message", value: report.exceptionInfo.exceptionReason)
    }
    // binary images
    let text = NSMutableString()
    for case let binaryImage as PLCrashReportBinaryImageInfo in report.images {
        text.append(binaryImageToStack(report: report, binaryImage: binaryImage))
        text.append("\n")
    }
    span.setAttribute(key: "binaryImages", value: String(text))
    span.end(time: now)
}

// FIXME this is a messy copy+paste of select bits of PLCrashReportTextFormatter
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
// Add binary image as attribute of crash span
func binaryImageToStack(report: PLCrashReport, binaryImage: PLCrashReportBinaryImageInfo) -> String {
    var baseAddress: UInt64 = 0
    var imageSize: UInt64 = 0
    var imageName = "???"
    var imageUUID = "XXX"
    var shortname = imageName
    let imageInfo = binaryImage
    var binaryArchi = "Unknown"
    if imageInfo != nil {
        imageName = imageInfo.imageName
        shortname = URL(fileURLWithPath: imageName).lastPathComponent
        baseAddress = imageInfo.imageBaseAddress
        imageSize = imageInfo.imageSize
        imageUUID = imageInfo.imageUUID
        // PLCrashReportSystemInfo PLCrashReportArchitecture
        binaryArchi = convertBinaryArchitectueIntoString(archi: report.systemInfo.architecture)
    }
    return String(format: "0x%lx 0x%lx %@ %@ <%@> %-35@ ", baseAddress, imageSize, shortname, binaryArchi, imageUUID, imageName)
}
func convertBinaryArchitectueIntoString(archi: PLCrashReportArchitecture) -> String {
    var architecture = ""
    switch archi {
    case PLCrashReportArchitectureX86_32:
        architecture = "x86-32"
    case PLCrashReportArchitectureX86_64:
        architecture = "x86-64"
    case  PLCrashReportArchitectureARMv6:
        architecture = "ARMv6"
    case PLCrashReportArchitecturePPC:
        architecture = "PPC"
    case PLCrashReportArchitecturePPC64:
        architecture = "PPC64"
    case PLCrashReportArchitectureARMv7:
        architecture = "ARMv7"
    default:
        architecture = "Unknown"
    }
    return architecture
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
