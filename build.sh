#!/bin/zsh
set -eu
cd "${0:A:h}"
destination="${1:-build/Earphone Silencer.app}"
mkdir -p "$destination/Contents/MacOS"
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
    DeviceControl.swift main.swift -framework AppKit -framework IOKit \
    -o "$destination/Contents/MacOS/EarphoneSilencer"
cp Info.plist "$destination/Contents/Info.plist"
codesign --force --sign - "$destination"
"$destination/Contents/MacOS/EarphoneSilencer" --self-test
