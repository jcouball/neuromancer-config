#!/bin/bash
#
# Bootstrap a freshly installed Apple Silicon Mac.
#
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/jcouball/neuromancer-config/main/provision.sh)"
#
# Runs under `sh` when invoked through the one-liner above, which is why this
# sticks to what bash 3.2 in POSIX mode provides. To pass flags through the
# one-liner, a $0 placeholder is required:
#
#   sh -c "$(curl -fsSL ...)" provision --unattended
#
# This script is intentionally the *only* thing that has to be run by hand. It
# installs Homebrew and chezmoi, then hands over to chezmoi, which owns
# everything else via .chezmoiscripts/.

set -euo pipefail

REPO="${NEUROMANCER_CONFIG_REPO:-jcouball/neuromancer-config}"
UNATTENDED="${UNATTENDED:-0}"
COMPUTER_NAME="${COMPUTER_NAME:-}"
ICLOUD_WAIT_SECONDS="${ICLOUD_WAIT_SECONDS:-300}"

usage() {
  cat <<'EOF'
Usage: provision.sh [--unattended] [--name NAME] [--help]

  --unattended   Never prompt. Skips the Apple ID wait, and only renames the
                 computer if --name or $COMPUTER_NAME is set. This is the mode
                 certification runs in.
  --name NAME    Set the computer name without prompting.
  --help         Show this message.

Environment:
  NEUROMANCER_CONFIG_REPO   chezmoi source repo (default: jcouball/neuromancer-config)
  ICLOUD_WAIT_SECONDS       How long to wait for Apple ID sign-in (default: 300)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --unattended) UNATTENDED=1 ;;
    --name) COMPUTER_NAME="${2:-}"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 64 ;;
  esac
  shift
done

log()  { echo ">> $*"; }
warn() { echo "!! $*" >&2; }
die()  { echo "❌ $*" >&2; exit 1; }

# --- Functions ---

# Validate sudo up front and hold the timestamp open for the whole run.
#
# Without this the Command Line Tools and Homebrew installs -- which together
# can take longer than sudo's five minute default -- hit a second password
# prompt partway through, from a subprocess that may not be able to display it.
ensure_sudo_credentials() {
  log "Validating sudo credentials..."

  if [ "$UNATTENDED" = "1" ]; then
    sudo -n -v 2>/dev/null || die "Unattended mode needs a cached or passwordless sudo credential."
  else
    sudo -v || die "You must enter valid sudo credentials to run this script."
  fi

  # Refresh the timestamp until this script exits.
  while true; do
    sudo -n -v 2>/dev/null || exit
    sleep 60
    kill -0 "$$" 2>/dev/null || exit
  done &
  SUDO_KEEPALIVE_PID=$!
  trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
}

# Homebrew installs the Command Line Tools itself, but doing it here first keeps
# that work inside the sudo window opened above, and makes a failure legible
# rather than surfacing as a confusing Homebrew error.
install_command_line_tools() {
  if /usr/bin/xcode-select -p >/dev/null 2>&1; then
    log "Command Line Tools already installed."
    return
  fi

  log "Installing Command Line Tools..."

  # softwareupdate only offers the CLT package while this sentinel exists.
  local sentinel="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
  sudo touch "$sentinel"

  local product
  product=$(softwareupdate -l 2>/dev/null \
    | grep -B 1 -E 'Command Line Tools' \
    | awk -F'Label: ' '/Label: /{print $2}' \
    | sort -V \
    | tail -n 1)

  if [ -n "$product" ]; then
    sudo softwareupdate -i "$product" --verbose
  else
    warn "Could not find a Command Line Tools package via softwareupdate."
    if [ "$UNATTENDED" = "1" ]; then
      sudo rm -f "$sentinel"
      die "Cannot install Command Line Tools unattended."
    fi
    log "Falling back to the graphical installer. Complete it, then return here."
    /usr/bin/xcode-select --install || true
    while ! /usr/bin/xcode-select -p >/dev/null 2>&1; do
      sleep 5
      printf "."
    done
    echo
  fi

  sudo rm -f "$sentinel"
  /usr/bin/xcode-select -p >/dev/null 2>&1 || die "Command Line Tools install did not complete."
}

set_computer_name() {
  local current_name
  current_name=$(scutil --get ComputerName 2>/dev/null || echo "")

  if [ -z "$COMPUTER_NAME" ]; then
    if [ "$UNATTENDED" = "1" ]; then
      log "Unattended: leaving computer name as '$current_name'."
      return
    fi
    read -r -p ">> Enter the name for this computer [$current_name]: " COMPUTER_NAME
    COMPUTER_NAME=${COMPUTER_NAME:-$current_name}
  fi

  [ -n "$COMPUTER_NAME" ] || { log "No computer name given; skipping."; return; }

  log "Setting computer name to '$COMPUTER_NAME'..."
  sudo scutil --set ComputerName "$COMPUTER_NAME"
  sudo scutil --set HostName "$COMPUTER_NAME"
  sudo scutil --set LocalHostName "$COMPUTER_NAME"
}

# Reads the Apple ID out of the iCloud account plist.
#
# Uses plutil rather than jq: this runs before Homebrew exists, and while
# macOS 15+ does ship /usr/bin/jq, depending on that is depending on an accident
# of the OS version. plutil has been in the base system forever.
is_signed_in() {
  local plist_file="$HOME/Library/Preferences/MobileMeAccounts.plist"
  [ -f "$plist_file" ] || return 1

  local account_id
  account_id=$(plutil -extract 'Accounts.0.AccountID' raw -o - "$plist_file" 2>/dev/null || echo "")
  [ -n "$account_id" ]
}

# Waiting is bounded. An unbounded loop cannot be certified, and cannot be run
# from anything but an attended terminal.
wait_for_icloud_login() {
  if [ "$UNATTENDED" = "1" ]; then
    log "Unattended: skipping the Apple ID check."
    log "Note: the Mac App Store cannot be signed into inside a VM, so the"
    log "      'mas' entries in .Brewfile will be skipped. This is expected."
    return
  fi

  log "Checking Apple ID sign-in status..."

  if is_signed_in; then
    echo "✅ Apple ID is signed in."
    return
  fi

  echo "❌ Not signed in to Apple ID. Sign in via System Settings > Apple ID."
  echo "   Also open the App Store and sign in, or the 'mas' entries in"
  echo "   .Brewfile will fail. Waiting up to ${ICLOUD_WAIT_SECONDS}s (Ctrl-C to skip)..."

  local waited=0
  while ! is_signed_in; do
    if [ "$waited" -ge "$ICLOUD_WAIT_SECONDS" ]; then
      echo
      warn "Timed out waiting for Apple ID sign-in. Continuing anyway."
      warn "The 'mas' entries in .Brewfile will not install until you sign in"
      warn "and re-run: brew bundle --file=\"\$HOME/.Brewfile\""
      return
    fi
    sleep 3
    waited=$((waited + 3))
    printf "."
  done

  echo
  echo "✅ Apple ID is signed in."
}

install_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    log "Homebrew already installed."
  elif [ -x /opt/homebrew/bin/brew ]; then
    log "Homebrew already installed (not yet on PATH)."
  else
    log "Homebrew not found. Installing..."
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  # Put brew on PATH for the rest of *this* script only.
  #
  # Deliberately not appended to ~/.zprofile: chezmoi owns that file, its
  # dot_zprofile already runs `brew shellenv`, and an append here would be
  # silently overwritten by the apply a few lines below.
  [ -x /opt/homebrew/bin/brew ] || die "Homebrew install did not produce /opt/homebrew/bin/brew."
  eval "$(/opt/homebrew/bin/brew shellenv)"
}

install_chezmoi() {
  if command -v chezmoi >/dev/null 2>&1; then
    log "chezmoi already installed."
  else
    log "Installing chezmoi..."
    brew install chezmoi
  fi
}

# Re-runnable by design. The previous version skipped entirely when the source
# directory existed, which made a second run a silent no-op -- exactly the
# behaviour you don't want when you are re-running because something failed.
apply_dotfiles() {
  if [ -d "$HOME/.local/share/chezmoi/.git" ]; then
    log "chezmoi already initialized; applying..."
    chezmoi apply
  else
    log "Initializing chezmoi from $REPO..."
    chezmoi init --apply "$REPO"
  fi
}

# --- Main ---

log "Starting system bootstrap..."

ensure_sudo_credentials
install_command_line_tools
set_computer_name
wait_for_icloud_login
install_homebrew
install_chezmoi
apply_dotfiles

echo "✅ Bootstrap complete."
echo
echo "Next: open a new terminal so the shell picks up the new environment,"
echo "then run 'chezmoi status' -- it should be empty."
