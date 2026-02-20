#!/bin/bash

# DevDash - Clean Build and Run Script

set -e  # Exit on error

# Kill running app if open
if pgrep -x "DevDash" > /dev/null; then
    echo "🛑 Stopping running DevDash instance..."
    pkill -x "DevDash"
    sleep 0.5
fi

echo "🧹 Cleaning and building DevDash..."
xcodebuild -project DevDash.xcodeproj -scheme ServiceManager -configuration Debug clean build

echo "🚀 Launching DevDash..."
open ~/Library/Developer/Xcode/DerivedData/DevDash-*/Build/Products/Debug/DevDash.app

echo "✅ Done!"
