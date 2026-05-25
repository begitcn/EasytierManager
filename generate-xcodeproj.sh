#!/bin/bash
# Generate Xcode project using XcodeGen
# Install XcodeGen: brew install xcodegen

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Generate version constants from VERSION
bash scripts/generate-version.sh

if ! command -v xcodegen &> /dev/null; then
    echo "XcodeGen not found. Install it with: brew install xcodegen"
    echo "Then run this script again."
    exit 1
fi

# Pass MARKETING_VERSION to xcodegen so project.yml can use it
export MARKETING_VERSION
MARKETING_VERSION=$(cat VERSION)

rm -rf EasyTierManager.xcodeproj
xcodegen generate
echo "✅ Xcode project generated: EasyTierManager.xcodeproj"
