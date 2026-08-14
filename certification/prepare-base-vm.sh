#!/bin/bash
#
# Prepare a freshly-installed macOS VM to be a certification base image.
#
# Runs INSIDE the guest, once, right after Setup Assistant. Everything it does
# is host-side plumbing -- SSH access and passwordless sudo -- so that
# certify.sh can drive the VM unattended. None of it is part of the rebuild
# being certified.
#
# Reach it through tart's directory sharing, which works from first boot and
# needs no networking, no clipboard agent, and no retyping:
#
#   # on the host
#   tart run --dir=cert:$PWD/certification:ro neuromancer-base
#
#   # in the VM's Terminal
#   "/Volumes/My Shared Files/cert/prepare-base-vm.sh"
#
# Afterwards: shut the VM down and never boot the base image again. certify.sh
# clones it, and a base image that gets booted is no longer a clean machine.

set -euo pipefail

PUBKEY_NAME="${PUBKEY_NAME:-id_ed25519_neuromancer_cert.pub}"
SHARE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\n\033[1m>> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m!! %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31m❌ %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "This runs inside the macOS guest, not on the host."

if [ "$USER" = "james" ]; then
  warn "This account is named 'james'."
  warn "Several defects only surface for a user who is not you -- .gitconfig was"
  warn "broken for every other account and nobody noticed for years. Consider"
  warn "rebuilding this VM with the account named 'certuser'."
  printf '   Continue anyway? [y/N] '
  read -r reply
  case "$reply" in [yY]*) ;; *) exit 1 ;; esac
fi

# --- Disk ------------------------------------------------------------------

log "Checking the disk is big enough..."

# Disk size has to be set when the VM is CREATED. `tart set --disk-size` grows
# the virtual disk but not the APFS container inside it, and the container
# cannot be grown afterwards either: macOS lays the Recovery partition down
# *after* the data container, so the free space is on the far side of it and
# `diskutil apfs resizeContainer` fails with -69519.
#
# The failure mode is nasty. A 50 GB VM gets ~41 GiB usable, ~29 GiB of it free
# after macOS, and `brew bundle` runs out somewhere in the middle of 121
# packages -- reporting 113 failed installs rather than "the disk is full".
#
# The only fix is at creation:
#   tart create --from-ipsw=latest --disk-size 100 neuromancer-base
AVAIL_GB="$(df -g / | awk 'NR==2{print $4}')"
echo "   ${AVAIL_GB} GB available."

if [ "${AVAIL_GB:-0}" -lt 45 ]; then
  warn "Only ${AVAIL_GB} GB free. The Brewfile needs roughly 35-40 GB for 84"
  warn "formulae and 37 casks, and this VM will run out partway through."
  warn "Recreate it with a bigger disk -- the size cannot be changed later:"
  warn "  tart delete $(scutil --get LocalHostName 2>/dev/null || echo neuromancer-base)"
  warn "  tart create --from-ipsw=latest --disk-size 100 neuromancer-base"
  printf '   Continue anyway? [y/N] '
  read -r reply
  case "$reply" in [yY]*) ;; *) exit 1 ;; esac
fi

# --- Public key ------------------------------------------------------------

log "Installing the certification public key..."

PUBKEY_PATH="$SHARE_DIR/$PUBKEY_NAME"
if [ ! -f "$PUBKEY_PATH" ]; then
  die "No public key at $PUBKEY_PATH.
     On the host, copy it into the shared directory first:
       cp ~/.ssh/$PUBKEY_NAME <repo>/certification/"
fi

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if grep -qxFf "$PUBKEY_PATH" "$HOME/.ssh/authorized_keys" 2>/dev/null; then
  echo "   Already authorized."
else
  cat "$PUBKEY_PATH" >> "$HOME/.ssh/authorized_keys"
  echo "   Added to ~/.ssh/authorized_keys."
fi
chmod 600 "$HOME/.ssh/authorized_keys"

# --- Passwordless sudo -----------------------------------------------------

log "Granting passwordless sudo to $USER..."
echo "   Unattended provisioning requires it, and three chezmoi scripts need root."

if sudo -n true 2>/dev/null && [ -f "/etc/sudoers.d/$USER" ]; then
  echo "   Already configured."
else
  echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/$USER" >/dev/null
  sudo chmod 440 "/etc/sudoers.d/$USER"
  sudo -n true 2>/dev/null || die "Passwordless sudo did not take effect."
  echo "   Done."
fi

# --- Remote Login ----------------------------------------------------------

log "Enabling Remote Login..."

if sudo systemsetup -getremotelogin 2>/dev/null | grep -qi 'On'; then
  echo "   Already enabled."
elif sudo systemsetup -setremotelogin on 2>/dev/null; then
  echo "   Enabled."
else
  # systemsetup needs Full Disk Access on recent macOS, which Terminal.app does
  # not have in a fresh install. This is the one step that may need the GUI.
  warn "Could not enable Remote Login from the command line."
  warn "macOS requires Full Disk Access for systemsetup, which a fresh"
  warn "Terminal.app does not have. Enable it by hand:"
  warn "  System Settings > General > Sharing > Remote Login"
  printf '   Press return once Remote Login is on... '
  read -r _
fi

sudo systemsetup -getremotelogin 2>/dev/null | grep -qi 'On' \
  || die "Remote Login is still off; certify.sh cannot reach this VM without it."

# --- Report ----------------------------------------------------------------

cat <<EOF

$(printf '\033[32m✅ Base VM prepared\033[0m')

  user           $USER
  authorized     $(wc -l < "$HOME/.ssh/authorized_keys" | tr -d ' ') key(s)
  sudo           passwordless
  Remote Login   on
  address        $(ipconfig getifaddr en0 2>/dev/null || echo '(no en0 address yet)')

Next, on the host:

  1. Shut this VM down.       sudo shutdown -h now
  2. Never boot the base image again -- certify.sh clones it.
  3. ./certification/certify.sh

EOF
