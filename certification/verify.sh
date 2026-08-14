#!/bin/bash
#
# Verify a provisioned machine by its outcomes, not by exit codes.
#
# A provisioning script that returns zero has proved nothing. The failure that
# justified certifying sophon-config was a script that ran before its own config
# file existed, found nothing to do, and reported "all tools are installed" --
# true, and completely meaningless. Every check here looks at the machine.
#
# Runs inside the certification VM (certify.sh copies it there and runs it as a
# file -- never piped to `bash -s`, because the first check that reads stdin
# would then swallow the rest of the script), but it is
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

# Tested by running something x86_64, not by looking for the daemon. `pgrep
# oahd` reports whether Rosetta is *currently translating*, not whether it is
# installed -- on a machine that has not run an Intel binary since boot, the
# daemon is simply not there, and certification called a working install
# "not installed" because of it.
if arch -x86_64 /usr/bin/true 2>/dev/null; then
  ok "Rosetta 2 works (ran an x86_64 binary)"
else
  bad "Rosetta 2 not working" "x86_64-only casks will not run"
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

  # Entries an Apple Silicon VM structurally cannot satisfy. Named individually,
  # with the reason, rather than hidden behind a blanket "VM mode" -- an
  # exception you cannot enumerate is indistinguishable from a bug you have
  # stopped noticing.
  #
  #   zoom            its installer package's postinstall scripts fail in a VM
  #   postgresql@17   `restart_service` needs a GUI launchd domain (gui/501),
  #                   which does not exist over SSH: launchctl exits 125 with
  #                   "Domain does not support specified action"
  #
  # Both install and work on real hardware; neither can be proven here.
  vm_exceptions='zoom postgresql@17'

  if printf '%s\n' "$check_out" | grep -q "dependencies are satisfied"; then
    ok "brew bundle check satisfied$([ "$SKIP_MAS" = 1 ] && echo " (excluding $mas_count App Store apps)")"
  else
    missing_list="$(printf '%s\n' "$check_out" | grep '^→' | sed 's/^→ //')"

    if [ "$SKIP_MAS" = "1" ]; then
      excepted=""
      remaining=""
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        hit=0
        for e in $vm_exceptions; do
          case "$line" in *"$e"*) hit=1 ;; esac
        done
        if [ "$hit" = 1 ]; then
          excepted="$excepted$line
"
        else
          remaining="$remaining$line
"
        fi
      done <<EOF
$missing_list
EOF
      missing_list="$(printf '%s' "$remaining")"
      excepted_n="$(printf '%s' "$excepted" | grep -c . || true)"
      if [ "${excepted_n:-0}" -gt 0 ]; then
        caution "$excepted_n entr$([ "$excepted_n" = 1 ] && echo y || echo ies) cannot work in a VM" \
                "verify these on real hardware"
        printf '%s' "$excepted" | sed 's/^/          /'
      fi
    fi

    missing_n="$(printf '%s' "$missing_list" | grep -c . || true)"
    if [ "${missing_n:-0}" -eq 0 ]; then
      ok "brew bundle check satisfied$([ "$SKIP_MAS" = 1 ] && echo " (excluding App Store apps and VM-incompatible entries)")"
    else
      bad "brew bundle check: $missing_n entr$([ "$missing_n" = 1 ] && echo y || echo ies) unsatisfied"
      printf '%s' "$missing_list" | head -10 | sed 's/^/          /'
    fi
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
  script -q /dev/null zsh -ic 'exit' </dev/null 2>&1 \
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
      "$(script -q /dev/null zsh -ic 'exit' </dev/null 2>&1 | sed $'s/\x1b\\[[0-9;]*[a-zA-Z]//g' | tr -d '\r' | grep -v '^\^D' | head -3 | tr '\n' ' ')"
fi

# --- Java ------------------------------------------------------------------

section "Java"

# Checked by running it, not by looking at variables. openjdk is keg-only, so a
# machine can have a perfectly good JDK on disk, a JAVA_HOME that points into a
# real directory, and still fail every `java` invocation -- which is exactly the
# state this machine was in. Presence proves nothing; execution does.
if brew list --versions openjdk >/dev/null 2>&1; then
  ok "openjdk installed ($(brew list --versions openjdk | awk '{print $2}'))"

  if /usr/libexec/java_home >/dev/null 2>&1; then
    ok "java_home resolves ($(/usr/libexec/java_home))"
  else
    bad "java_home cannot find a JDK" \
        "openjdk is keg-only; script 05 links it into /Library/Java/JavaVirtualMachines"
  fi

  if java -version >/dev/null 2>&1; then
    ok "java runs ($(java -version 2>&1 | head -1))"
  else
    bad "java does not run" "$(java -version 2>&1 | head -1)"
  fi

  java_home="$(login_env JAVA_HOME)"
  if [ -n "$java_home" ] && [ -x "$java_home/bin/java" ]; then
    ok "JAVA_HOME usable in a login shell ($java_home)"
  elif [ -n "$java_home" ]; then
    bad "JAVA_HOME set but has no bin/java" "$java_home"
  else
    bad "JAVA_HOME not set in a login shell"
  fi
else
  caution "openjdk not installed" "declared in .Brewfile"
fi

# --- Terminal --------------------------------------------------------------

section "Terminal"

if [ -d "/Applications/Warp.app" ]; then
  ok "Warp installed"
else
  bad "Warp not installed" "declared as a cask in .Brewfile"
fi

# Warp keeps its settings in a binary SQLite database, so there is nothing to
# verify beyond the app being present -- see "Deliberately not managed".

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

# The sentinel below is the last thing this script does, and certify.sh requires
# it. A verification that dies partway through must never be mistaken for one
# that passed -- exactly the "reported success, did nothing" failure that this
# whole exercise exists to catch.
printf 'VERIFY-COMPLETE %s passed %s failed %s warnings\n' "$PASS" "$FAIL" "$WARNED"

if [ "$FAIL" -gt 0 ]; then
  printf '%s\n' "$(red 'Verification failed.')"
  exit 1
fi

printf '%s\n' "$(green 'All checks passed.')"
exit 0
