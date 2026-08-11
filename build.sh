#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="SleepSwitch.app"
BIN="SleepSwitch"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

echo "Compiling…"
swiftc -swift-version 5 -O Sources/main.swift -o "$APP/Contents/MacOS/$BIN" -framework AppKit

cp Info.plist "$APP/Contents/Info.plist"

echo "Built $APP"
echo "Run with: open $APP"
