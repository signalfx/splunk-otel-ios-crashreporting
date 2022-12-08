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

@testable import SplunkRumCrashReporting
import Foundation
import XCTest

class DeviceStatsTests: XCTestCase {
    func testBattery() throws {
        let batteryLevel = DeviceStats.batteryLevel
        XCTAssertEqual(batteryLevel, "100.0%")
    }
    func testFreeDiskSpace() throws {
        let diskSpace = DeviceStats.freeDiskSpace
        let space = Int(diskSpace.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 0
        XCTAssertTrue(space > 0)
    }
    func testFreeMemory() throws {
        let freeMemory = DeviceStats.freeMemory
        let space = Int(freeMemory.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 0
        XCTAssertTrue(space > 0)
    }
}
