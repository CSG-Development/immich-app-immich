#!/usr/bin/env bash
# Makes Flutter not incorrectly append `-sdk` arguments to simulator builds
# This breaks macros that must build for the host's platform
#
# Flutter was informed of this (https://github.com/flutter/flutter/issues/146122) but has not fixed it in 2 years
#
# Upstream: mobile/ios/scripts/xcode_flutter_patch.sh (immich-app/immich#30821).
# Fork: also resolve FVM's `.fvm/flutter_sdk` when not running under mise postinstall.

set -eu

if [[ -n "${MISE_TOOL_INSTALL_PATH:-}" ]]; then
  sdk="${MISE_TOOL_INSTALL_PATH}/flutter"
elif [[ -n "${FLUTTER_ROOT:-}" ]]; then
  sdk="$FLUTTER_ROOT"
else
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  fvm_sdk="$(cd "$script_dir/../.." && pwd)/.fvm/flutter_sdk"
  if [[ -e "$fvm_sdk" ]]; then
    sdk="$(cd "$fvm_sdk" && pwd -P)"
  else
    sdk="$(mise where aqua:flutter/flutter)/flutter"
  fi
fi

mac_dart="$sdk/packages/flutter_tools/lib/src/ios/mac.dart"

pattern="buildCommands.addAll(<String>['-sdk', XcodeSdk.IPhoneSimulator.platformName]);"

# Filter out the sdk arg pattern
if awk -v pat="$pattern" 'index($0, pat) { found=1; next } { print } END { exit !found }' "$mac_dart" > "$mac_dart.tmp"; then
  # If it was filtered out, apply it
  mv "$mac_dart.tmp" "$mac_dart"

  # Force flutter itself to rebuild
  rm -f "$sdk/bin/cache/flutter_tools.snapshot" "$sdk/bin/cache/flutter_tools.stamp"

  echo "flutter postinstall: removed simulator -sdk flag from xcodebuild invocation ($sdk)"
else
  rm -f "$mac_dart.tmp"
fi
