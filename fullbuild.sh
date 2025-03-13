#!/bin/bash
set -ex
#swiftlint --strict

# Make sure the version numbers on the podspec and CrashReporting.swift match
echo "Checking that version numbers match"
rumVer="$(grep CrashReportingVersionString SplunkRumCrashReporting/SplunkRumCrashReporting/CrashReporting.swift | grep -o '[0-9]*\.[0-9]*\.[0-9]*')"
podVer="$(grep s.version SplunkOtelCrashReporting.podspec | grep -o '[0-9]*\.[0-9]*\.[0-9]*')"
if [ $podVer != $rumVer ]; then
    echo "Error: The version numbers in SplunkOtelCrashReporting.podspec and SplunkRum.swift do not match"
    exit 1
fi

# Check the podspec is valid
pod lib lint SplunkOtelCrashReporting.podspec

xcodebuild -project SplunkRumCrashReporting/SplunkRumCrashReporting.xcodeproj -scheme SplunkRumCrashReporting -configuration Debug build
xcodebuild -project SplunkRumCrashReporting/SplunkRumCrashReporting.xcodeproj -scheme SplunkRumCrashReporting -configuration Debug test
xcodebuild -project SplunkRumCrashReporting/SplunkRumCrashReporting.xcodeproj -scheme SplunkRumCrashReporting -configuration Release build

# Now try to do a swift build to ensure that the package dependencies are properly in synch
rm -rf ./.build
SIMULATOR_SDK="$(xcode-select -p)/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
SIMULATOR_TARGET="arm64-apple-ios17-simulator"
swift build -v --sdk "$SIMULATOR_SDK" --triple "$SIMULATOR_TARGET" --scratch-path "./.build/$SIMULATOR_TARGET"

echo "========= Congratulations! ========="
