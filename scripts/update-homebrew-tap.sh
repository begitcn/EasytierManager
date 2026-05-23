#!/bin/bash
set -euo pipefail

usage() {
  echo "Usage: $0 --version V --aarch64-sha SHA [--x86_64-sha SHA]"
  exit 1
}

VERSION=""
AARCH64_SHA=""
X86_64_SHA="0000000000000000000000000000000000000000000000000000000000000000"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --aarch64-sha) AARCH64_SHA="$2"; shift 2 ;;
    --x86_64-sha) X86_64_SHA="$2"; shift 2 ;;
    *) usage ;;
  esac
done

if [ -z "$VERSION" ] || [ -z "$AARCH64_SHA" ]; then
  usage
fi

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

git clone --depth 1 https://github.com/begitcn/homebrew-tap.git "$TEMP_DIR"
cd "$TEMP_DIR"
git remote set-url origin "https://x-access-token:${GH_PAT}@github.com/begitcn/homebrew-tap.git"

CASK_DIR="$TEMP_DIR/Casks"
mkdir -p "$CASK_DIR"
CASK_FILE="$CASK_DIR/easytiermanager.rb"

cat > "$CASK_FILE" << CASK_EOF
cask "easytiermanager" do
  version "${VERSION}"
  arch arm: "aarch64", intel: "x86_64"

  on_arm do
    sha256 "${AARCH64_SHA}"
    url "https://github.com/begitcn/EasyTierManager/releases/download/v#{version}/EasyTierManager-#{arch}-v#{version}.dmg"
  end
  on_intel do
    sha256 "${X86_64_SHA}"
    url "https://github.com/begitcn/EasyTierManager/releases/download/v#{version}/EasyTierManager-#{arch}-v#{version}.dmg"
  end

  name "EasyTierManager"
  desc "Native macOS GUI for EasyTier mesh VPN"
  homepage "https://github.com/begitcn/EasyTierManager"

  app "EasyTierManager.app"

  uninstall launchctl: "EasyTierHelper",
            delete:    [
              "/Library/PrivilegedHelperTools/EasyTierHelper",
              "/Library/LaunchDaemons/EasyTierHelper.plist",
            ]

  zap trash: [
    "~/Library/Application Support/EasyTierManager",
    "~/Library/Caches/com.easytier.manager",
    "~/Library/Preferences/com.easytier.manager.plist",
  ]
end
CASK_EOF

git add -A
git config user.name "EasyTierManager Bot"
git config user.email "bot@easytier.manager"
git commit -m "easytiermanager: update to v${VERSION}"
git push
