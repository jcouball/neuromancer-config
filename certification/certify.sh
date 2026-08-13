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
#   1. --unattended    There is no human at the VM's console to answer prompts.
#   2. SKIP_MAS=1      Apple's Virtualization framework does not support signing
#                      into the Mac App Store inside a VM, on any tool, at all.
#                      The 14 `mas` entries in .Brewfile therefore cannot be
#                      certified here and must be checked on real hardware.
#
# Everything else -- the curl one-liner, the URL, chezmoi, every provisioning
# script -- runs exactly as written.

set -euo pipefail

BASE_VM="${BASE_VM:-neuromancer-base}"
CERT_VM="${CERT_VM:-neuromancer-cert}"
CERT_USER="${CERT_USER:-certuser}"
REPO="${NEUROMANCER_CONFIG_REPO:-jcouball/neuromancer-config}"
BRANCH="${BRANCH:-main}"
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

log()  { printf '\n\033[1m>> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m!! %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31m❌ %s\033[0m\n' "$*" >&2; exit 1; }

# --- Preflight -------------------------------------------------------------

command -v tart >/dev/null 2>&1 \
  || die "tart not found. Install it: brew install cirruslabs/cli/tart"

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
    if [ -n "$ip" ] && ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o BatchMode=yes \
        "$CERT_USER@$ip" true 2>/dev/null; then
      echo "$ip"
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
    printf "."
  done
  echo
  die "VM did not become reachable over SSH within ${BOOT_TIMEOUT}s.
     Check that the base image has Remote Login enabled and this host's
     public key in ~$CERT_USER/.ssh/authorized_keys."
}

# Host keys change with every clone, so they are deliberately not verified.
# This is a disposable VM on a local network, reachable only from this Mac.
guest() {
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
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
  tart run "$CERT_VM" --no-graphics >"$LOG_DIR/vm-console.log" 2>&1 &
  TART_PID=$!
  trap 'kill "$TART_PID" 2>/dev/null || true' EXIT
fi

IP="$(wait_for_ssh)"
echo
log "VM reachable at $IP"

# --- Run the bootstrap -----------------------------------------------------

STAMP="$(date +%Y%m%d-%H%M%S)"
BOOTSTRAP_LOG="$LOG_DIR/bootstrap-$STAMP.log"
VERIFY_LOG="$LOG_DIR/verify-$STAMP.log"

if [ "$VERIFY_ONLY" -eq 0 ]; then
  log "Running the bootstrap. Transcript: $BOOTSTRAP_LOG"
  echo "   Without a log, failures have to be inferred from wreckage."

  BOOTSTRAP_URL="https://raw.githubusercontent.com/$REPO/$BRANCH/provision.sh"

  # The command below is the README's one-liner verbatim, plus the two named
  # deviations. Do not "improve" it here -- the point is to test what the
  # README says.
  if guest "export SKIP_MAS=1 NEUROMANCER_CONFIG_REPO='$REPO'; \
            sh -c \"\$(curl -fsSL $BOOTSTRAP_URL)\" provision --unattended --name $CERT_VM" \
       2>&1 | tee "$BOOTSTRAP_LOG"; then
    log "Bootstrap exited 0."
  else
    warn "Bootstrap exited non-zero. Verifying anyway -- the exit code is not the point."
  fi
fi

# --- Verify ----------------------------------------------------------------

log "Verifying outcomes. Transcript: $VERIFY_LOG"

guest "SKIP_MAS=1 bash -s" < "$SCRIPT_DIR/verify.sh" 2>&1 | tee "$VERIFY_LOG"
VERIFY_STATUS=${PIPESTATUS[0]}

echo
if [ "$VERIFY_STATUS" -eq 0 ]; then
  printf '\033[32m✅ CERTIFIED\033[0m -- %s rebuilt from nothing and passed every check.\n' "$CERT_VM"
else
  printf '\033[31m❌ NOT CERTIFIED\033[0m -- see %s\n' "$VERIFY_LOG"
fi

cat <<EOF

The VM is still running so you can inspect it:

  ssh $CERT_USER@$IP
  tart delete $CERT_VM      # when you are done

Record anything this found in the Certification section of the README. A defect
that is fixed but not written down will be rediscovered from scratch.
EOF

exit "$VERIFY_STATUS"
