#!/bin/bash
set -ex

# on arm64 macOS, homebrew is custom build into /opt/homebrew
PATH=${PATH}:/opt/homebrew/bin/

if which swiftlint >/dev/null; then
   echo "Swiftlint installation found"
else
  echo "warning: SwiftLint not installed, installing via Homebrew"
  brew install swiftlint
fi

swiftlint --strict

xcodebuild -project SplunkRumCrashReporting/SplunkRumCrashReporting.xcodeproj -scheme SplunkRumCrashReporting -configuration Debug build
xcodebuild -project SplunkRumCrashReporting/SplunkRumCrashReporting.xcodeproj -scheme SplunkRumCrashReporting -configuration Debug test
xcodebuild -project SplunkRumCrashReporting/SplunkRumCrashReporting.xcodeproj -scheme SplunkRumCrashReporting -configuration Release build

# TODO Re-enable this section after the release of SPM 6.1
# Now try to do a swift build to ensure that the package dependencies are properly in synch
# rm -rf ./.build
# SIMULATOR_SDK="$(xcode-select -p)/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
# SIMULATOR_TARGET="arm64-apple-ios17-simulator"
# swift build -v --sdk "$SIMULATOR_SDK" --triple "$SIMULATOR_TARGET" --scratch-path "./.build/$SIMULATOR_TARGET"

echo "========= Congratulations! ========="
