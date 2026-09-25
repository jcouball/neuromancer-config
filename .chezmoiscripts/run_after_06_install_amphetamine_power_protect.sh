#!/bin/bash
#
# Power Protect for Amphetamine -- lets Closed-Display Mode keep a MacBook awake
# with the lid shut. https://x74353.github.io/Amphetamine-Power-Protect/
#
# The download is a DMG holding a notarized installer package, so `installer`
# can run it with no GUI. The package installs two files, which are also how
# this script tells whether it is already installed:
#
#   ~/Library/Application Scripts/com.if.Amphetamine/powerProtect.scpt
#   /private/etc/sudoers.d/amphetamine_PowerProtect
#
# run_ rather than run_once_ or run_onchange_: nothing in this repo changes when
# Power Protect goes missing, so the only reliable trigger is to check on every
# apply. The check is two file tests; the download happens only when one fails.
#
# after_ and numbered 06 so it runs once script 02 has installed Amphetamine
# from the App Store.

set -euo pipefail

# Script 02 has the same check, but it runs only when the Brewfile changes and
# this script runs on every apply.
if [ "$(id -u)" -eq 0 ]; then
  echo "❌ Do not run 'sudo chezmoi apply'." >&2
  echo "   Power Protect installs into your home directory, and running as root" >&2
  echo "   would leave root-owned files there." >&2
  echo "   Instead:  sudo -v && chezmoi apply" >&2
  exit 1
fi

SCRIPT_FILE="$HOME/Library/Application Scripts/com.if.Amphetamine/powerProtect.scpt"
SUDOERS_FILE="/private/etc/sudoers.d/amphetamine_PowerProtect"
DMG_URL="https://raw.githubusercontent.com/x74353/Amphetamine-Power-Protect/main/DMG/Power%20Protect%20for%20Amphetamine.dmg"
# The Developer ID team that signs the package. Checked instead of a checksum,
# because the DMG is served from the repo's main branch and a checksum would
# break on every legitimate update.
SIGNING_TEAM="U5SR49N3PT"
AMPHETAMINE_APP="/Applications/Amphetamine.app"
MIN_AMPHETAMINE_VERSION="5.3.1"

if [ -f "$SCRIPT_FILE" ] && [ -f "$SUDOERS_FILE" ]; then
  echo ">> Amphetamine Power Protect is already installed."
  exit 0
fi

# The package refuses to install on a Mac without a battery, or without
# Amphetamine 5.3.1 or later. Check both first and skip rather than fail: a
# desktop Mac, or a VM without an App Store login, is a normal case, not an
# error.
if ! pmset -g ps | grep -q "InternalBattery"; then
  echo ">> No internal battery; Amphetamine Power Protect is for laptops only. Skipping."
  exit 0
fi

if [ ! -d "$AMPHETAMINE_APP" ]; then
  echo ">> Amphetamine is not installed; skipping Power Protect."
  exit 0
fi

AMPHETAMINE_VERSION="$(defaults read "$AMPHETAMINE_APP/Contents/Info.plist" CFBundleShortVersionString)"
if [ "$(printf '%s\n' "$MIN_AMPHETAMINE_VERSION" "$AMPHETAMINE_VERSION" | sort -V | head -n1)" != "$MIN_AMPHETAMINE_VERSION" ]; then
  echo ">> Amphetamine $AMPHETAMINE_VERSION is older than $MIN_AMPHETAMINE_VERSION; skipping Power Protect."
  exit 0
fi

if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
  echo "❌ Installing Amphetamine Power Protect needs sudo, and there is no terminal to prompt on." >&2
  echo "   Run 'sudo -v' first, then 'chezmoi apply' -- NOT 'sudo chezmoi apply'." >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
MOUNT_POINT="$WORK_DIR/mnt"
cleanup() {
  if [ -d "$MOUNT_POINT" ]; then
    hdiutil detach -quiet "$MOUNT_POINT" 2>/dev/null || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo ">> Downloading Amphetamine Power Protect..."
curl -fsSL -o "$WORK_DIR/power-protect.dmg" "$DMG_URL"

mkdir "$MOUNT_POINT"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT_POINT" "$WORK_DIR/power-protect.dmg"

PKG="$MOUNT_POINT/Install Power Protect.pkg"
if [ ! -f "$PKG" ]; then
  echo "❌ The DMG no longer contains 'Install Power Protect.pkg'; the download has changed shape." >&2
  exit 1
fi

# This package installs a sudoers file, so do not run it on trust alone.
if ! pkgutil --check-signature "$PKG" | grep -q "Developer ID Installer: .*($SIGNING_TEAM)"; then
  echo "❌ The Power Protect package is not signed by team $SIGNING_TEAM. Not installing it." >&2
  exit 1
fi

echo ">> Installing Amphetamine Power Protect..."
sudo installer -pkg "$PKG" -target /

# The package stages the script in /Library and its postinstall moves it with
# `mv ... ~/Library/...`. Whose ~ that is depends on how the installer was
# started, so finish the move here if the postinstall put it somewhere else.
STAGED_FILE="/Library/Application Scripts/com.if.Amphetamine/powerProtect.scpt"
if [ ! -f "$SCRIPT_FILE" ] && [ -f "$STAGED_FILE" ]; then
  mkdir -p "$(dirname "$SCRIPT_FILE")"
  sudo mv -f "$STAGED_FILE" "$SCRIPT_FILE"
fi

if [ ! -f "$SCRIPT_FILE" ] || [ ! -f "$SUDOERS_FILE" ]; then
  echo "❌ Power Protect install did not produce both of its files:" >&2
  echo "   $SCRIPT_FILE" >&2
  echo "   $SUDOERS_FILE" >&2
  exit 1
fi

echo ">> Amphetamine Power Protect installed. Restart any active Closed-Display Mode session."
