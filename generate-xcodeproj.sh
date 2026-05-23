#!/bin/bash
# Generate Xcode project using XcodeGen
# Install XcodeGen: brew install xcodegen

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v xcodegen &> /dev/null; then
    echo "XcodeGen not found. Install it with: brew install xcodegen"
    echo "Then run this script again."
    exit 1
fi

xcodegen generate --project EasyTierManager.xcodeproj
echo "✅ Xcode project generated: EasyTierManager.xcodeproj"
