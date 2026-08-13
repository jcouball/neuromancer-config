#!/bin/bash
#
# Verify a provisioned machine by its outcomes, not by exit codes.
#
# A provisioning script that returns zero has proved nothing. The failure that
# justified certifying sophon-config was a script that ran before its own config
# file existed, found nothing to do, and reported "all tools are installed" --
# true, and completely meaningless. Every check here looks at the machine.
#
# Runs inside the certification VM (certify.sh pipes it over SSH), but it is
# deliberately standalone: run it on the real Mac too, any time you want to know
# whether the machine still matches the repo.
#
#   ./certification/verify.sh
#   SKIP_MAS=1 ./certification/verify.sh    # tolerate missing App Store apps

# The tildes below are display text in human-readable messages, not paths.
# shellcheck disable=SC2088

set -uo pipefail   # deliberately no -e: every check must run, then report

SKIP_MAS="${SKIP_MAS:-0}"

PASS=0
FAIL=0
WARNED=0

green() { printf '\033[32m%s\033[0m' "$*"; }
red()   { printf '\033[31m%s\033[0m' "$*"; }
amber() { printf '\033[33m%s\033[0m' "$*"; }

ok()      { PASS=$((PASS + 1));   printf '  %s  %s\n' "$(green PASS)" "$1"; }
bad()     { FAIL=$((FAIL + 1));   printf '  %s  %s\n' "$(red FAIL)" "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; return 0; }
caution() { WARNED=$((WARNED + 1)); printf '  %s  %s\n' "$(amber WARN)" "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; return 0; }
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
export ASDF_DATA_DIR="${ASDF_DATA_DIR:-$HOME/.asdf}"
export PATH="$ASDF_DATA_DIR/shims:$PATH"

printf '\033[1mVerifying %s (%s)\033[0m\n' "$(scutil --get ComputerName 2>/dev/null || echo '?')" "$(sw_vers -productVersion)"

# --- Foundations -----------------------------------------------------------

section "Foundations"

if [ "$(uname -m)" = "arm64" ]; then
  ok "Apple Silicon (arm64)"
else
  bad "Not Apple Silicon" "uname -m = $(uname -m)"
fi

if /usr/bin/xcode-select -p >/dev/null 2>&1; then
  ok "Command Line Tools installed"
else
  bad "Command Line Tools missing" "xcrun, and therefore SDKROOT, will not work"
fi

if /usr/bin/pgrep -q oahd; then
  ok "Rosetta 2 running"
else
  bad "Rosetta 2 not installed" "x86_64-only casks will not run"
fi

if [ -x /opt/homebrew/bin/brew ]; then
  ok "Homebrew at /opt/homebrew"
else
  bad "Homebrew missing"
fi

# --- chezmoi ---------------------------------------------------------------

section "chezmoi"

if command -v chezmoi >/dev/null 2>&1; then
  ok "chezmoi installed ($(chezmoi --version | awk '{print $3}' | tr -d ,))"

  status_out="$(chezmoi status 2>&1)"
  if [ -z "$status_out" ]; then
    ok "chezmoi status is empty (no drift)"
  else
    bad "chezmoi reports drift" "$(printf '%s' "$status_out" | head -5 | tr '\n' ' ')"
  fi

  if [ -d "$HOME/.local/share/chezmoi/.git" ]; then
    ok "chezmoi source directory is a git checkout"
  else
    bad "chezmoi source directory missing or not a git checkout"
  fi
else
  bad "chezmoi not installed"
fi

# --- Managed files landed --------------------------------------------------

section "Managed files"

for f in .zshrc .zprofile .zshenv .Brewfile .tool-versions .gitconfig .asdfrc .p10k.zsh; do
  if [ -f "$HOME/$f" ]; then
    ok "~/$f"
  else
    bad "~/$f missing"
  fi
done

# The README used to be deployed to the home directory because it was not in
# .chezmoiignore. Anything in the source root without a leading dot becomes a
# target -- this check exists so that trap cannot come back unnoticed.
if [ -e "$HOME/README.md" ]; then
  caution "~/README.md exists" "the repo README should not be deployed; check .chezmoiignore"
else
  ok "~/README.md correctly not deployed"
fi

# --- Homebrew packages -----------------------------------------------------

section "Homebrew packages"

BREWFILE="$HOME/.Brewfile"
if [ -f "$BREWFILE" ]; then
  mas_ids=$(awk -F'id:' '/^mas /{gsub(/[^0-9]/, "", $2); if ($2 != "") print $2}' "$BREWFILE" | tr '\n' ' ')
  mas_count=$(printf '%s' "$mas_ids" | wc -w | tr -d ' ')

  # HOMEBREW_BUNDLE_NO_UPGRADE is what makes this a check for *presence* rather
  # than for freshness. Without it, every installed-but-outdated cask reports as
  # unsatisfied, which drowns the genuinely missing entries in noise. Whether
  # things are up to date is topgrade's job, not certification's.
  if [ "$SKIP_MAS" = "1" ]; then
    check_out="$(HOMEBREW_BUNDLE_NO_UPGRADE=1 HOMEBREW_BUNDLE_MAS_SKIP="$mas_ids" \
                 brew bundle check --file="$BREWFILE" --verbose 2>&1)"
  else
    check_out="$(HOMEBREW_BUNDLE_NO_UPGRADE=1 \
                 brew bundle check --file="$BREWFILE" --verbose 2>&1)"
  fi

  if printf '%s\n' "$check_out" | grep -q "dependencies are satisfied"; then
    ok "brew bundle check satisfied$([ "$SKIP_MAS" = 1 ] && echo " (excluding $mas_count App Store apps)")"
  else
    missing_list="$(printf '%s\n' "$check_out" | grep '^→' | sed 's/^→ //')"
    missing_n="$(printf '%s\n' "$missing_list" | grep -c . || true)"
    bad "brew bundle check: $missing_n entr$([ "$missing_n" = 1 ] && echo y || echo ies) unsatisfied"
    printf '%s\n' "$missing_list" | head -10 | sed 's/^/          /'
  fi

  if [ "$SKIP_MAS" = "1" ] && [ "$mas_count" -gt 0 ]; then
    caution "$mas_count App Store apps not verified" \
            "Apple Silicon VMs cannot sign into the Mac App Store; check these on real hardware"
  fi
else
  bad "~/.Brewfile missing -- cannot check packages"
fi

# --- VS Code extensions ----------------------------------------------------

section "VS Code"

if command -v code >/dev/null 2>&1; then
  declared=$(grep -c '^vscode ' "$BREWFILE" 2>/dev/null || echo 0)
  installed=$(code --list-extensions 2>/dev/null | grep -c . || echo 0)
  if [ "$installed" -ge "$declared" ]; then
    ok "$installed extensions installed ($declared declared)"
  else
    bad "$installed extensions installed, $declared declared"
  fi
else
  bad "code CLI not on PATH" "the visual-studio-code cask should provide it"
fi

# --- Runtimes --------------------------------------------------------------

section "Runtimes (asdf)"

if command -v asdf >/dev/null 2>&1; then
  ok "asdf installed ($(asdf --version 2>/dev/null | awk '{print $3}'))"

  if [ -f "$HOME/.tool-versions" ]; then
    current="$(asdf current 2>/dev/null)"
    declared=$(grep -c '^[^[:space:]#]' "$HOME/.tool-versions")

    while read -r tool want; do
      [ -n "$tool" ] || continue
      case "$tool" in \#*) continue ;; esac

      line=$(printf '%s\n' "$current" | awk -v t="$tool" '$1 == t')
      if [ -z "$line" ]; then
        bad "$tool not reported by asdf current"
        continue
      fi

      got=$(printf '%s' "$line" | awk '{print $2}')
      inst=$(printf '%s' "$line" | awk '{print $NF}')

      if [ "$inst" != "true" ]; then
        bad "$tool $want declared but not installed"
      elif [ "$got" != "$want" ]; then
        bad "$tool resolves to $got, .tool-versions declares $want"
      else
        ok "$tool $got"
      fi
    done < "$HOME/.tool-versions"

    # The shims must actually be the thing a shell reaches, not just present.
    for bin in ruby node python go; do
      resolved="$(command -v "$bin" 2>/dev/null || true)"
      case "$resolved" in
        "$ASDF_DATA_DIR"/shims/*) ok "$bin resolves through asdf shims" ;;
        "") bad "$bin not on PATH" ;;
        *)  caution "$bin resolves to $resolved" "expected an asdf shim" ;;
      esac
    done

    printf '        (%s tools declared)\n' "$declared"
  else
    bad "~/.tool-versions missing"
  fi
else
  bad "asdf not on PATH"
fi

# --- Shell environment -----------------------------------------------------

section "Shell environment"

if [ "$(basename "${SHELL:-}")" = "zsh" ]; then
  ok "login shell is zsh"
else
  caution "login shell is ${SHELL:-unset}" "expected zsh"
fi

# A fresh login shell, not this one: .zshenv and .zprofile are what a real
# terminal actually sources, and they are where the environment is set.
login_env() { zsh -lc "printf '%s' \"\${$1:-}\"" 2>/dev/null; }

java_home="$(login_env JAVA_HOME)"
if [ -z "$java_home" ]; then
  caution "JAVA_HOME not set in a login shell" "expected once a JDK is installed"
elif [ -d "$java_home" ]; then
  ok "JAVA_HOME is a real directory ($java_home)"
else
  bad "JAVA_HOME points at a nonexistent directory" "$java_home"
fi

login_path="$(login_env PATH)"
case "$login_path" in
  *"/opt/homebrew/bin"*) ok "Homebrew on PATH in a login shell" ;;
  *) bad "Homebrew not on PATH in a login shell" ;;
esac
case "$login_path" in
  *"$ASDF_DATA_DIR/shims"*) ok "asdf shims on PATH in a login shell" ;;
  *) bad "asdf shims not on PATH in a login shell" ;;
esac

# An interactive shell must start without spraying errors -- the guards added to
# .zshrc exist precisely so that a partly-provisioned machine stays usable.
#
# Run through `script` to get a pty. Without one, zsh cannot enable job control
# and powerlevel10k's gitstatus fails to start, producing six lines of alarming
# output that say nothing about the machine. That is a defect in the test, not
# in the shell, and filtering the messages by name would only paper over it.
interactive_noise() {
  script -q /dev/null zsh -ic 'exit' 2>&1 \
    | sed $'s/\x1b\\[[0-9;]*[a-zA-Z]//g' \
    | tr -d '\r' \
    | grep -v '^\^D' \
    | grep -c . || true
}

shell_noise="$(interactive_noise)"
if [ "${shell_noise:-1}" -le 1 ]; then
  ok "interactive shell starts without errors"
else
  bad "interactive shell prints $shell_noise line(s) of unexpected output" \
      "$(script -q /dev/null zsh -ic 'exit' 2>&1 | sed $'s/\x1b\\[[0-9;]*[a-zA-Z]//g' | tr -d '\r' | grep -v '^\^D' | head -3 | tr '\n' ' ')"
fi

# --- iTerm2 ----------------------------------------------------------------

section "iTerm2"

# The preferences plist is managed, but the setting that tells iTerm2 to *read*
# it lives in iTerm2's own defaults domain and is not. A rebuilt machine gets
# the plist and ignores it until this is ticked by hand, which is easy to miss
# because iTerm2 looks fine -- just not like yours.
if [ -f "$HOME/.iterm2/com.googlecode.iterm2.plist" ]; then
  ok "~/.iterm2/com.googlecode.iterm2.plist deployed"

  load_custom="$(defaults read com.googlecode.iterm2 LoadPrefsFromCustomFolder 2>/dev/null || echo 0)"
  custom_dir="$(defaults read com.googlecode.iterm2 PrefsCustomFolder 2>/dev/null || echo '')"

  if [ "$load_custom" = "1" ] && [ "$custom_dir" = "$HOME/.iterm2" ]; then
    ok "iTerm2 is reading preferences from ~/.iterm2"
  else
    caution "iTerm2 is not reading the managed preferences" \
            "set Preferences > General > Preferences > 'Load preferences from a custom folder' to ~/.iterm2"
  fi
else
  caution "~/.iterm2 preferences not deployed"
fi

# --- Identity --------------------------------------------------------------

section "Identity"

name="$(scutil --get ComputerName 2>/dev/null || echo '')"
for key in ComputerName HostName LocalHostName; do
  val="$(scutil --get "$key" 2>/dev/null || echo '')"
  if [ -n "$val" ]; then
    ok "$key = $val"
  else
    bad "$key is not set"
  fi
done
[ -n "$name" ] || bad "ComputerName is empty"

# --- Summary ---------------------------------------------------------------

printf '\n\033[1m%s\033[0m\n' "Summary"
printf '  %s passed, %s failed, %s warnings\n' \
  "$(green "$PASS")" "$([ "$FAIL" -gt 0 ] && red "$FAIL" || echo 0)" "$(amber "$WARNED")"

if [ "$FAIL" -gt 0 ]; then
  printf '\n%s\n' "$(red 'Verification failed.')"
  exit 1
fi

printf '\n%s\n' "$(green 'All checks passed.')"
exit 0
