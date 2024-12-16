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
private var allUsedImageNames: Array <String> = []

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
    
    // Stop enable if debugger attached
    var inDebugger = false
    if isDebuggerAttached() {
        startupSpan.setAttribute(key: "error.message", value: "Debugger present. Will not construct PLCrashReporter")
        SplunkRum.debugLog("Debugger present. Will not enable PLCrashReporter")
        inDebugger = true;
    }
    if inDebugger == false {
        let success = crashReporter.enable()
        SplunkRum.debugLog("PLCrashReporter enabled: "+success.description)
        if !success {
            startupSpan.setAttribute(key: "error.message", value: "Cannot enable PLCrashReporter")
        }
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
        allUsedImageNames.removeAll()
        let path = crashReporter.crashReportPath()
        print(path as Any)
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
            span.setAttribute(key: "crash.rumSessionId", value: String(bytes: report.customData, encoding: String.Encoding.utf8) ?? "Unknown")
        }
    }
    // "marketing version" here matches up to our use of CFBundleShortVersionString
    span.setAttribute(key: "crash.app.version", value: report.applicationInfo.applicationMarketingVersion)
    span.setAttribute(key: "error", value: true)
    span.addEvent(name: "crash.timestamp", timestamp: report.systemInfo.timestamp)
    span.setAttribute(key: "exception.type", value: exceptionType ?? "unknown")
    span.setAttribute(key: "crash.address", value: report.signalInfo.address.description)

    var allThreads: Array <Any> = []
    for case let thread as PLCrashReportThreadInfo in report.threads {
        
        // Original crashed thread handler
        if (thread.crashed) {
            span.setAttribute(key: "exception.stacktrace", value: crashedThreadToStack(report: report, thread: thread))
        }
        
        // Detailed thread handler
        allThreads.append(detailedThreadToStackFrames(report: report, thread: thread))
    }
    let threadPayload = convertArrayToJSONString(allThreads) ?? "Unable to create stack frames"
    span.setAttribute(key: "exception.stackFrames", value: threadPayload)
    var images: Array <Any> = []
    images = imageList(images: report.images)
    let imagesPayload = convertArrayToJSONString(images) ?? "Unable to create images"
    span.setAttribute(key: "exception.images", value: imagesPayload)

    if report.hasExceptionInfo {
        span.setAttribute(key: "exception.type", value: report.exceptionInfo.exceptionName)
        span.setAttribute(key: "exception.message", value: report.exceptionInfo.exceptionReason)
    }
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

// Symbolication Support Code

// Extracts detail for one thread
func detailedThreadToStackFrames(report: PLCrashReport, thread: PLCrashReportThreadInfo) -> Dictionary<String, Any> {
    
    var oneThread: [String: Any] = [:]
    var allStackFrames: Array <Any> = []
    
    let threadNum = thread.threadNumber as NSNumber
    oneThread["threadNumber"] = threadNum.stringValue
    oneThread["crashed"] = thread.crashed

    var frameNum = 0
    while frameNum < thread.stackFrames.count {
        var oneFrame: [String: Any] = [:]
        
        let frame = thread.stackFrames[frameNum] as! PLCrashReportStackFrameInfo
        let instructionPointer = frame.instructionPointer
        oneFrame["instructionPointer"] = instructionPointer
        
        var baseAddress: UInt64 = 0
        var offset: UInt64 = 0
        var imageName = "???"

        let imageInfo = report.image(forAddress: instructionPointer)
        if imageInfo != nil {
            imageName = imageInfo?.imageName ?? "???"
            baseAddress = imageInfo!.imageBaseAddress
            offset = instructionPointer - baseAddress
        }
        oneFrame["imageName"] = imageName
        allUsedImageNames.append(imageName)
        
        if frame.symbolInfo != nil {
            let symbolName = frame.symbolInfo.symbolName
            let symOffset = instructionPointer - frame.symbolInfo.startAddress
            oneFrame["symbolName"] = symbolName
            oneFrame["offset"] = symOffset
        } else {
            oneFrame["baseAddress"] = baseAddress
            oneFrame["offset"] = offset
        }
        allStackFrames.append(oneFrame)
        frameNum += 1
    }
    oneThread["stackFrames"] = allStackFrames
    return oneThread
}

// Returns true if debugger is attached
private func isDebuggerAttached() -> Bool {
    var debuggerIsAttached = false

    var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    var info = kinfo_proc()
    var infoSize = MemoryLayout<kinfo_proc>.size

    _ = name.withUnsafeMutableBytes { (nameBytePtr: UnsafeMutableRawBufferPointer) -> Bool in
        guard let nameBytesBlindMemory = nameBytePtr.bindMemory(to: Int32.self).baseAddress else {
            return false
        }
        return sysctl(nameBytesBlindMemory, 4, &info, &infoSize, nil, 0) != -1
    }
    if !debuggerIsAttached && (info.kp_proc.p_flag & P_TRACED) != 0 {
        debuggerIsAttached = true
    }
    return debuggerIsAttached
}

// Returns array of code images used by app
func imageList(images: Array<Any>) -> Array<Any> {
    var outputImages: Array<Any> = []
    for image in images {
        var imageDictionary: [String:Any] = [:]
        guard let image = image as? PLCrashReportBinaryImageInfo else {
            continue
        }

        // Only add the image to the list if it was noted in the stack traces
        if(allUsedImageNames.contains(image.imageName)) {
            imageDictionary["codeType"] = cpuTypeDictionary(cpuType: image.codeType)
            imageDictionary["baseAddress"] = image.imageBaseAddress
            imageDictionary["imageSize"] = image.imageSize
            imageDictionary["imagePath"] = image.imageName
            imageDictionary["imageUUID"] = image.imageUUID
            
            outputImages.append(imageDictionary)
        }
    }
    return outputImages
}

// Returns formatted cpu data
func cpuTypeDictionary(cpuType: PLCrashReportProcessorInfo) -> Dictionary<String, String>  {
    var dictionary: [String:String] = [:]
    dictionary.updateValue(String(cpuType.type), forKey: "cType")
    dictionary.updateValue(String(cpuType.subtype), forKey: "cSubType")
    return dictionary
}

// JSON support code
func convertDictionaryToJSONString(_ dictionary: [String: Any]) -> String? {
    guard let jsonData = try? JSONSerialization.data(withJSONObject: dictionary, options: .prettyPrinted) else {
        
        return nil
    }
    guard let jsonString = String(data: jsonData, encoding: .utf8) else {
        
        return nil
    }
    return jsonString
}

func convertArrayToJSONString(_ array: [Any]) -> String? {
    guard let jsonData = try? JSONSerialization.data(withJSONObject: array, options: .prettyPrinted) else {
    
        return nil
    }
    guard let jsonString = String(data: jsonData, encoding: .utf8) else {
        
        return nil
    }
    return jsonString
}
