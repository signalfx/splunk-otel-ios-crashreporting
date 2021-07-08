#!/bin/bash
set -e
swiftlint --strict
xcodebuild -project SplunkRumCrashReporting/SplunkRumCrashReporting.xcodeproj -scheme SplunkRumCrashReporting -configuration Debug build
xcodebuild -project SplunkRumCrashReporting/SplunkRumCrashReporting.xcodeproj -scheme SplunkRumCrashReporting -configuration Debug test
xcodebuild -project SplunkRumCrashReporting/SplunkRumCrashReporting.xcodeproj -scheme SplunkRumCrashReporting -configuration Release build

# Now try to do a swift build to ensure that the package dependencies are properly in synch
swift build -v -Xswiftc "-sdk" -Xswiftc "`xcrun --sdk iphonesimulator --show-sdk-path`" -Xswiftc "-target" -Xswiftc "x86_64-apple-ios11.0-simulator"

echo "========= Congratulations! ========="
