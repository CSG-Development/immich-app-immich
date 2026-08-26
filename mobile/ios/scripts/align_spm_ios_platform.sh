#!/bin/bash
# Flutter always generates FlutterGeneratedPluginSwiftPackage at iOS 13.0
# (the SDK default). Plugins such as background_downloader and home_widget
# require 14.0+, and the app's deployment target is 15.0.
#
# `updateMinimumDeployment` only runs when the Flutter CLI drives the iOS
# build (`flutter build ios` / `flutter run`). Fastlane/xcodebuild never
# calls it, so the generated package must be aligned before gym.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
package_swift="${script_dir}/../Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"

if [[ ! -f "$package_swift" ]]; then
  echo "SPM package manifest not found, skipping: $package_swift"
  exit 0
fi

if grep -q '.iOS("15.0")' "$package_swift"; then
  echo "FlutterGeneratedPluginSwiftPackage already targets iOS 15.0"
  exit 0
fi

if [[ "$(uname)" == "Darwin" ]]; then
  sed -i '' 's/\.iOS("13\.0")/.iOS("15.0")/' "$package_swift"
else
  sed -i 's/\.iOS("13\.0")/.iOS("15.0")/' "$package_swift"
fi

if ! grep -q '.iOS("15.0")' "$package_swift"; then
  echo "Failed to set FlutterGeneratedPluginSwiftPackage platform to iOS 15.0" >&2
  exit 1
fi

echo "Set FlutterGeneratedPluginSwiftPackage platform to iOS 15.0"
