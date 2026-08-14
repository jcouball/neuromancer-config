#!/bin/bash
#
# Certify the rebuild: run the README's bootstrap procedure end to end against a
# throwaway macOS VM that has never seen this repo, then verify the outcome.
#
# A clean `chezmoi diff` proves the repo describes this machine. It says nothing
# about whether the repo can *produce* one. That is what this script tests.
#
# Runs on the host. Requires tart and a prepared base VM -- see "Certification"
# in the README for how to build one. Nothing here touches your real Mac.
#
# Usage:
#   ./certification/certify.sh                 # full run against a fresh clone
#   ./certification/certify.sh --verify-only   # re-run checks on the live cert VM
#   ./certification/certify.sh --keep          # do not delete a previous cert VM
#
# THE TWO DEVIATIONS
#
# The point of certification is to run what the README says, not a convenient
# variant, so deviations have to be named. There are exactly two, both forced by
# the platform rather than chosen:
#
#   1. --promptString  There is no human at the VM's console to answer chezmoi's
#                      one question, so the machine name is supplied up front.
#   2. SKIP_MAS=1      Apple's Virtualization framework does not support signing
#                      into the Mac App Store inside a VM, on any tool, at all.
#                      The 14 `mas` entries in .Brewfile therefore cannot be
#                      certified here and must be checked on real hardware.
#
# Everything else runs exactly as the README publishes it. There is no longer a
# third deviation for the CDN: chezmoi clones over git, which has no cache, so
# what the VM gets is always what was last pushed.

set -euo pipefail

BASE_VM="${BASE_VM:-neuromancer-base}"
CERT_VM="${CERT_VM:-neuromancer-cert}"
CERT_USER="${CERT_USER:-certuser}"
# A dedicated, passphrase-less key. Passphrase-less because certify.sh runs
# unattended over BatchMode SSH; dedicated because the alternative is handing a
# throwaway VM a key that also opens something real.
CERT_SSH_KEY="${CERT_SSH_KEY:-$HOME/.ssh/id_ed25519_neuromancer_cert}"
REPO="${NEUROMANCER_CONFIG_REPO:-jcouball/neuromancer-config}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-300}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"

VERIFY_ONLY=0
KEEP_OLD=0

while [ $# -gt 0 ]; do
  case "$1" in
    --verify-only) VERIFY_ONLY=1 ;;
    --keep) KEEP_OLD=1 ;;
    --help|-h) sed -n '2,32p' "$0" | sed 's/^#\{1,2\} \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 64 ;;
  esac
  shift
done

# All three write to stderr. log() in particular must: wait_for_ssh's result is
# captured with $(...), so anything it prints to stdout is captured as part of
# the value. It printed its progress there, and the IP became the whole
# transcript -- log line, dots and address -- which ssh rejected as
# "hostname contains invalid characters".
log()  { printf '\n\033[1m>> %s\033[0m\n' "$*" >&2; }
warn() { printf '\033[33m!! %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31m❌ %s\033[0m\n' "$*" >&2; exit 1; }

# --- Preflight -------------------------------------------------------------

command -v tart >/dev/null 2>&1 \
  || die "tart not found. It is declared in .Brewfile: brew bundle --global"

[ -f "$CERT_SSH_KEY" ] \
  || die "No certification SSH key at $CERT_SSH_KEY.
     Create one:  ssh-keygen -t ed25519 -N '' -f $CERT_SSH_KEY
     then add $CERT_SSH_KEY.pub to ~$CERT_USER/.ssh/authorized_keys in the base VM."

if [ "$VERIFY_ONLY" -eq 0 ]; then
  tart list --format json | grep -q "\"$BASE_VM\"" \
    || die "Base VM '$BASE_VM' not found. See 'Certification' in the README for how to build it."
fi

mkdir -p "$LOG_DIR"

vm_ip() { tart ip "$CERT_VM" --wait 1 2>/dev/null || true; }

wait_for_ssh() {
  local waited=0 ip=""
  log "Waiting for the VM to boot and accept SSH (up to ${BOOT_TIMEOUT}s)..."
  while [ "$waited" -lt "$BOOT_TIMEOUT" ]; do
    ip="$(vm_ip)"
    if [ -n "$ip" ] && ssh -i "$CERT_SSH_KEY" -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o IdentitiesOnly=yes -o BatchMode=yes \
        "$CERT_USER@$ip" true 2>/dev/null; then
      echo "$ip"
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
    printf "." >&2
  done
  echo >&2
  die "VM did not become reachable over SSH within ${BOOT_TIMEOUT}s.
     Check that the base image has Remote Login enabled and this host's
     public key in ~$CERT_USER/.ssh/authorized_keys."
}

# Host keys change with every clone, so they are deliberately not verified.
# This is a disposable VM on a local network, reachable only from this Mac.
guest() {
  ssh -i "$CERT_SSH_KEY" -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes \
      -o LogLevel=ERROR "$CERT_USER@$IP" "$@"
}

# --- Clone and boot --------------------------------------------------------

if [ "$VERIFY_ONLY" -eq 0 ]; then
  if tart list --format json | grep -q "\"$CERT_VM\""; then
    if [ "$KEEP_OLD" -eq 1 ]; then
      die "Cert VM '$CERT_VM' already exists and --keep was given."
    fi
    log "Removing the previous cert VM..."
    tart stop "$CERT_VM" 2>/dev/null || true
    tart delete "$CERT_VM"
  fi

  # An APFS clone: seconds, and almost no additional disk. This is the
  # equivalent of reverting to a checkpoint -- the base image is never booted
  # again, so it cannot drift.
  log "Cloning $BASE_VM -> $CERT_VM..."
  tart clone "$BASE_VM" "$CERT_VM"

  log "Starting $CERT_VM..."
  # nohup, and deliberately no EXIT trap to kill it. A trap here stopped the VM
  # the moment the script finished, which contradicted the closing message,
  # made --verify-only impossible, and threw away the failed machine that is
  # the most useful thing a failed run produces.
  nohup tart run "$CERT_VM" --no-graphics >"$LOG_DIR/vm-console.log" 2>&1 &
fi

IP="$(wait_for_ssh)"
echo
log "VM reachable at $IP"

# Fail fast on a disk that cannot finish the job. Run 3 spent twenty minutes
# downloading before Homebrew ran out of space and reported it as 113 failed
# package installs -- a diagnosis that took longer than the run. The number was
# knowable in the first second.
# shellcheck disable=SC2016  # awk's $4 must reach the guest unexpanded.
AVAIL_GB="$(guest 'df -g / | awk "NR==2{print \$4}"' 2>/dev/null || echo 0)"
log "Guest has ${AVAIL_GB} GB free."
if [ "${AVAIL_GB:-0}" -lt 45 ]; then
  die "Only ${AVAIL_GB} GB free in the guest; the Brewfile needs roughly 35-40.
     Disk size can only be set when the VM is created:
       tart delete $BASE_VM
       tart create --from-ipsw=latest --disk-size 100 $BASE_VM"
fi

# --- Run the bootstrap -----------------------------------------------------

STAMP="$(date +%Y%m%d-%H%M%S)"
BOOTSTRAP_LOG="$LOG_DIR/bootstrap-$STAMP.log"
VERIFY_LOG="$LOG_DIR/verify-$STAMP.log"

if [ "$VERIFY_ONLY" -eq 0 ]; then
  log "Running the bootstrap. Transcript: $BOOTSTRAP_LOG"
  echo "   Certifying $REPO" >&2
  echo "   Without a log, failures have to be inferred from wreckage." >&2

  # The three commands from "Rebuild from nothing", verbatim, plus the two
  # deviations named above. Do not "improve" them here -- the point is to test
  # what the README says.
  #
  # NONINTERACTIVE=1 is Homebrew's own documented flag for unattended installs,
  # not a deviation: without a terminal its installer waits for a RETURN that
  # will never come.
  # shellcheck disable=SC2016  # $(...) must stay unexpanded: it runs in the guest.
  BOOTSTRAP='set -e
export SKIP_MAS=1 NONINTERACTIVE=1
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"
brew install chezmoi
chezmoi init --apply --promptString "Computer name='"$CERT_VM"'" '"$REPO"

  if guest "$BOOTSTRAP" 2>&1 | tee "$BOOTSTRAP_LOG"; then
    log "Bootstrap exited 0."
  else
    warn "Bootstrap exited non-zero. Verifying anyway -- the exit code is not the point."
  fi
fi

# --- Verify ----------------------------------------------------------------

log "Verifying outcomes. Transcript: $VERIFY_LOG"

# Copy the script over and run it as a file, rather than piping it to `bash -s`.
#
# Piping made stdin the script itself, so the first command inside it that read
# stdin -- `script`, used to get a pty for the interactive-shell check -- ate the
# remainder. bash hit EOF partway through, exited 0 because the last command it
# managed to run had succeeded, and ssh reported success. certify.sh believed it
# and printed CERTIFIED over a machine with no Homebrew, no chezmoi and no
# managed files at all.
scp -q -i "$CERT_SSH_KEY" -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes \
    "$SCRIPT_DIR/verify.sh" "$CERT_USER@$IP:/tmp/verify.sh" \
  || die "Could not copy verify.sh to the VM."

# set +e: the pipeline is expected to fail when verification fails, and with
# `set -e` plus pipefail that would abort the script here -- silently, before it
# could report anything.
set +e
guest "SKIP_MAS=1 bash /tmp/verify.sh" 2>&1 | tee "$VERIFY_LOG"
VERIFY_STATUS=${PIPESTATUS[0]}
set -e

# Never trust a zero exit on its own. verify.sh prints a sentinel as its final
# act, so a run that died partway through cannot be mistaken for a clean one --
# which is the entire lesson of the defect this harness exists to catch, and
# which this harness itself fell for.
if ! grep -q '^VERIFY-COMPLETE' "$VERIFY_LOG"; then
  warn "verify.sh did not run to completion -- its result cannot be trusted."
  VERIFY_STATUS=1
fi

echo
if [ "$VERIFY_STATUS" -eq 0 ]; then
  printf '\033[32m✅ CERTIFIED\033[0m -- %s rebuilt from nothing and passed every check.\n' "$CERT_VM"
else
  printf '\033[31m❌ NOT CERTIFIED\033[0m -- see %s\n' "$VERIFY_LOG"
fi

cat <<EOF

The VM is left running so you can inspect it:

  ssh -i $CERT_SSH_KEY $CERT_USER@$IP
  ./certification/certify.sh --verify-only   # re-check without rebuilding
  tart stop $CERT_VM && tart delete $CERT_VM # when you are done

Record anything this found in the Certification section of the README. A defect
that is fixed but not written down will be rediscovered from scratch.
EOF

exit "$VERIFY_STATUS"
