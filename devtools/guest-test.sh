#!/bin/sh

# devtools/guest-test.sh -- runs inside QEMU guest.
# Iterates all .ko modules in /mnt/lkmpg/examples/, performs insmod/rmmod
# twice, and reports pass/fail. Respects .ci/non-working exclusion list.
#
# Output uses "LKMPG:" prefix to distinguish test results from kernel log noise.

set -e

MODULE_DIR="/mnt/lkmpg/examples"
NON_WORKING="/mnt/lkmpg/.ci/non-working"
NON_WORKING_QEMU="/mnt/lkmpg/devtools/non-working"
FAIL=0
PASS=0
SKIP=0

for ko in "$MODULE_DIR"/*.ko; do
    [ -f "$ko" ] || continue
    mod=$(basename "$ko" .ko)

    # Skip modules listed in .ci/non-working or devtools/non-working
    skip=0
    for nw in "$NON_WORKING" "$NON_WORKING_QEMU"; do
        if [ -f "$nw" ] && grep -qFx "$mod" "$nw" 2>/dev/null; then
            skip=1
            break
        fi
    done
    if [ "$skip" -eq 1 ]; then
        echo "LKMPG:SKIP $mod"
        SKIP=$((SKIP + 1))
        continue
    fi

    # insmod/rmmod twice (same logic as .ci/build-n-run.sh)
    if insmod "$ko" 2>&1 && rmmod "$mod" 2>&1 && \
       insmod "$ko" 2>&1 && rmmod "$mod" 2>&1; then
        echo "LKMPG:PASS $mod"
        PASS=$((PASS + 1))
    else
        echo "LKMPG:FAIL $mod"
        # Try to clean up
        rmmod "$mod" 2>/dev/null || true
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "LKMPG:RESULTS $PASS passed, $FAIL failed, $SKIP skipped"

if [ "$FAIL" -eq 0 ]; then
    echo "LKMPG:EXIT 0"
    exit 0
else
    echo "LKMPG:EXIT 1"
    exit 1
fi
