#!/usr/bin/env bash

# devtools/test-modules.sh -- build modules and test them inside QEMU.
# Boots QEMU in non-interactive mode, runs insmod/rmmod for each module,
# and exits with the guest's pass/fail status.
#
# Usage:
#   devtools/test-modules.sh                # build + test all modules
#   devtools/test-modules.sh --no-build     # skip build, test existing .ko files
#   devtools/test-modules.sh --timeout 300  # QEMU timeout in seconds (default 300)

set -euo pipefail

DEVTOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$DEVTOOLS_DIR/.." && pwd)"
. "$DEVTOOLS_DIR/config.defaults"
[ -f "$DEVTOOLS_DIR/config.local" ] && . "$DEVTOOLS_DIR/config.local"

die() { echo "ERROR: $*" >&2; exit 1; }

DO_BUILD=1
TIMEOUT=300

while [ $# -gt 0 ]; do
    case "$1" in
        --no-build)  DO_BUILD=0; shift ;;
        --timeout)   shift; TIMEOUT="${1:?--timeout requires a value}"; shift ;;
        -h|--help)
            echo "Usage: $0 [--no-build] [--timeout SECS]"
            exit 0 ;;
        *)  die "Unknown option: $1" ;;
    esac
done

# Build modules first (unless --no-build)
if [ "$DO_BUILD" -eq 1 ]; then
    echo "=== Building modules ==="
    "$DEVTOOLS_DIR/build-modules.sh"
    echo ""
fi

echo "=== Booting QEMU for testing (timeout: ${TIMEOUT}s) ==="

LOGFILE=$(mktemp)
trap 'rm -f "$LOGFILE"' EXIT

# Run QEMU with a timeout so a hung guest does not block CI forever.
# The guest runs guest-test.sh and then poweroff -f.
QEMU_EXIT=0
if command -v timeout >/dev/null 2>&1; then
    timeout --signal=KILL "$TIMEOUT" \
        "$DEVTOOLS_DIR/boot.sh" --test "/mnt/lkmpg/devtools/guest-test.sh" \
        2>&1 | tee "$LOGFILE" || QEMU_EXIT=$?
else
    # macOS lacks coreutils timeout; fall back to no timeout
    "$DEVTOOLS_DIR/boot.sh" --test "/mnt/lkmpg/devtools/guest-test.sh" \
        2>&1 | tee "$LOGFILE" || QEMU_EXIT=$?
fi

# Track whether QEMU itself failed (crash, timeout, abnormal exit).
# A non-zero exit is always a hard failure even if some tests passed,
# because the run may be incomplete.
QEMU_FAILED=0
if [ "$QEMU_EXIT" -ne 0 ]; then
    QEMU_FAILED=1
    echo ""
    if [ "$QEMU_EXIT" -eq 137 ]; then
        echo "=== QEMU TIMED OUT after ${TIMEOUT}s (guest may have hung) ==="
    else
        echo "=== QEMU exited with code $QEMU_EXIT ==="
    fi
fi

# Parse structured test output (LKMPG: prefix avoids kernel log collisions).
# grep -c prints "0" and exits 1 when no matches are found, so use || true
# to prevent set -e from killing the script (not || echo 0, which would
# append a second "0" to stdout and corrupt the count).
TOTAL_PASS=$(grep -c "^LKMPG:PASS " "$LOGFILE" 2>/dev/null || true)
TOTAL_FAIL=$(grep -c "^LKMPG:FAIL " "$LOGFILE" 2>/dev/null || true)
TOTAL_SKIP=$(grep -c "^LKMPG:SKIP " "$LOGFILE" 2>/dev/null || true)
: "${TOTAL_PASS:=0}" "${TOTAL_FAIL:=0}" "${TOTAL_SKIP:=0}"

echo ""
echo "=== Results: $TOTAL_PASS passed, $TOTAL_FAIL failed, $TOTAL_SKIP skipped ==="

if [ "$TOTAL_FAIL" -gt 0 ]; then
    echo ""
    echo "Failed modules:"
    grep "^LKMPG:FAIL " "$LOGFILE" | sed 's/^LKMPG:FAIL /  /'
    exit 1
fi

if [ "$TOTAL_PASS" -eq 0 ]; then
    echo ""
    echo "No test output detected. Guest may have failed to boot."
    echo "Last 20 lines of output:"
    tail -20 "$LOGFILE"
    exit 1
fi

# QEMU crash or timeout with partial test output is still a failure --
# some modules were never tested.
if [ "$QEMU_FAILED" -ne 0 ]; then
    echo ""
    echo "QEMU exited abnormally; results above may be incomplete."
    exit 1
fi

exit 0
