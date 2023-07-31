#!/bin/bash
set -e
swiftlint --strict

# Make sure the version numbers on the podspec and CrashReporting.swift match
echo "Checking that version numbers match"
rumVer="$(grep SplunkRumVersionString SplunkRumCrashReporting/SplunkRumCrashReporting/CrashReporting.swift | grep -o '[0-9]*\.[0-9]*\.[0-9]*')"
podVer="$(grep s.version SplunkOtel.podspec | grep -o '[0-9]*\.[0-9]*\.[0-9]*')"
if [ $podVer != $rumVer ]; then
    echo "Error: The version numbers in SplunkOtel.podspec and SplunkRum.swift do not match"
    exit 1
fi

xcodebuild -project SplunkRumCrashReporting/SplunkRumCrashReporting.xcodeproj -scheme SplunkRumCrashReporting -configuration Debug build
xcodebuild -project SplunkRumCrashReporting/SplunkRumCrashReporting.xcodeproj -scheme SplunkRumCrashReporting -configuration Debug test
xcodebuild -project SplunkRumCrashReporting/SplunkRumCrashReporting.xcodeproj -scheme SplunkRumCrashReporting -configuration Release build

# Now try to do a swift build to ensure that the package dependencies are properly in synch
swift build -v -Xswiftc "-sdk" -Xswiftc "`xcrun --sdk iphonesimulator --show-sdk-path`" -Xswiftc "-target" -Xswiftc "x86_64-apple-ios11.0-simulator"

echo "========= Congratulations! ========="
