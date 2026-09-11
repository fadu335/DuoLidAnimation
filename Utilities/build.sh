#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p build Diagnostics/ModuleCache
APP="$ROOT/build/DuoLidAnimation.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SDK="$(xcrun --show-sdk-path)"
FLAGS=()
# This Mac has two conflicting CLT SwiftBridging module maps. Apply a project-local VFS overlay.
# The older installed SDK avoids broken 26.0 SDK prebuilt module paths. No system files are changed.
if [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools ]] && [[ -f /Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap ]] && [[ -f /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap ]]; then
    python3 "$ROOT/Utilities/toolchain/make-overlay.py"
    FLAGS+=(-vfsoverlay "$ROOT/Utilities/toolchain/overlay.json")
    if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk ]]; then
        SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk
    fi
fi
SOURCES=(App/*.swift LidSensor/*.swift Capture/*.swift Renderer/*.swift Overlay/*.swift Utilities/*.swift Diagnostics/SelfTest.swift Diagnostics/RenderReference.swift)
swiftc -swift-version 6 -O -sdk "$SDK" -target "$(uname -m)-apple-macos14.0" \
    -module-cache-path "$ROOT/Diagnostics/ModuleCache" "${FLAGS[@]}" \
    "${SOURCES[@]}" -o "$APP/Contents/MacOS/DuoLidAnimation" \
    -framework AppKit -framework ScreenCaptureKit -framework Metal -framework MetalKit \
    -framework CoreVideo -framework CoreMedia -framework QuartzCore -framework IOKit
cp App/Info.plist "$APP/Contents/Info.plist"
cp Shaders/Shaders.metal Config/AnimationConfig.json "$APP/Contents/Resources/"
codesign --force --sign - --identifier local.duolid.animation "$APP"
echo "Built: $APP"
