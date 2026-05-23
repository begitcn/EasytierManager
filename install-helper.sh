#!/bin/bash
# Install the privileged helper for development
# Usage: sudo bash install-helper.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

HELPER_NAME="com.easytier.manager.helper"
DAEMON_PLIST="com.easytier.manager.helper.plist"

# Find helper binary - check build products first, then swift build
HELPER_BIN=""
for candidate in \
    "$SCRIPT_DIR/build/Release/EasyTierHelper" \
    "$SCRIPT_DIR/.build/debug/EasyTierHelper"; do
    if [ -f "$candidate" ]; then
        HELPER_BIN="$candidate"
        break
    fi
done

if [ -z "$HELPER_BIN" ]; then
    echo "Error: Helper binary not found. Build the project first."
    echo "  Run: swift build"
    exit 1
fi

INSTALL_BIN="/Library/PrivilegedHelperTools/$HELPER_NAME"
INSTALL_PLIST="/Library/LaunchDaemons/$DAEMON_PLIST"

echo "Installing privileged helper..."
echo "  Source: $HELPER_BIN"
echo "  Target: $INSTALL_BIN"

# Stop existing service if running
launchctl unload "$INSTALL_PLIST" 2>/dev/null || true

# Copy binary
mkdir -p /Library/PrivilegedHelperTools
cp "$HELPER_BIN" "$INSTALL_BIN"
chmod 755 "$INSTALL_BIN"
chown root:wheel "$INSTALL_BIN"

# Create launchd plist with Program key (for manual install, not BundleProgram)
cat > "$INSTALL_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$HELPER_NAME</string>
	<key>MachServices</key>
	<dict>
		<key>$HELPER_NAME</key>
		<true/>
	</dict>
	<key>Program</key>
	<string>$INSTALL_BIN</string>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
</dict>
</plist>
EOF
chown root:wheel "$INSTALL_PLIST"
chmod 644 "$INSTALL_PLIST"

# Load service
launchctl load "$INSTALL_PLIST"

echo "Helper installed and loaded."
echo ""
echo "Verify with: launchctl list | grep easytier"