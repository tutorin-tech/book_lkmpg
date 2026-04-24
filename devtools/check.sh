#!/usr/bin/env bash

# devtools/check.sh -- fast offline validation of devtools scripts.
# No QEMU, no kernel build, no network. Runs in <5 seconds.
#
# Usage:
#   devtools/check.sh              # run all checks
#   devtools/check.sh shellcheck   # run only shellcheck
#   devtools/check.sh syntax       # run only bash/sh syntax checks
#   devtools/check.sh config       # run only config consistency checks

set -euo pipefail

DEVTOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$DEVTOOLS_DIR/.." && pwd)"

PASS=0
FAIL=0
ERRORS=""

pass() { PASS=$((PASS + 1)); echo "  PASS  $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS="${ERRORS}  FAIL  $1\n"; echo "  FAIL  $1"; }

# --- Shell syntax validation ---
check_syntax() {
    echo "=== Shell syntax ==="

    for f in "$DEVTOOLS_DIR"/*.sh; do
        # Detect interpreter from shebang
        local shebang
        shebang=$(head -1 "$f")
        case "$shebang" in
            *bash*) bash -n "$f" 2>/dev/null && pass "bash -n $(basename "$f")" \
                                              || fail "bash -n $(basename "$f")" ;;
            *sh*)   sh -n "$f" 2>/dev/null && pass "sh -n $(basename "$f")" \
                                            || fail "sh -n $(basename "$f")" ;;
            *)      bash -n "$f" 2>/dev/null && pass "bash -n $(basename "$f")" \
                                              || fail "bash -n $(basename "$f")" ;;
        esac
    done

    # init uses /bin/sh
    sh -n "$DEVTOOLS_DIR/initramfs/init" 2>/dev/null \
        && pass "sh -n initramfs/init" \
        || fail "sh -n initramfs/init"
}

# --- shellcheck ---
check_shellcheck() {
    echo "=== shellcheck ==="

    if ! command -v shellcheck >/dev/null 2>&1; then
        echo "  SKIP  shellcheck not installed"
        return
    fi

    local sc_opts=(
        --severity=warning
        --exclude=SC1091   # "Not following sourced file" (config.defaults uses dynamic paths)
        --exclude=SC2034   # "Variable appears unused" (config vars consumed by sourcing scripts)
    )

    for f in "$DEVTOOLS_DIR"/*.sh; do
        if shellcheck "${sc_opts[@]}" "$f" 2>/dev/null; then
            pass "shellcheck $(basename "$f")"
        else
            fail "shellcheck $(basename "$f")"
        fi
    done

    if shellcheck "${sc_opts[@]}" --shell=sh "$DEVTOOLS_DIR/initramfs/init" 2>/dev/null; then
        pass "shellcheck initramfs/init"
    else
        fail "shellcheck initramfs/init"
    fi
}

# --- Config consistency ---
check_config() {
    echo "=== Config consistency ==="

    # config.defaults must be sourceable without error
    (
        DEVTOOLS_DIR="$DEVTOOLS_DIR"
        PROJECT_ROOT="$PROJECT_ROOT"
        . "$DEVTOOLS_DIR/config.defaults"
    ) 2>/dev/null && pass "config.defaults sources cleanly" \
                  || fail "config.defaults sources cleanly"

    # config.defaults must define all required variables
    local required_vars="KERNEL_VERSION BUSYBOX_VERSION QEMU_BIN KERNEL_SRC KERNEL_BUILD INITRAMFS_CPIO EXAMPLES_DIR"
    local missing=""
    for var in $required_vars; do
        val=$(
            DEVTOOLS_DIR="$DEVTOOLS_DIR"
            PROJECT_ROOT="$PROJECT_ROOT"
            . "$DEVTOOLS_DIR/config.defaults"
            eval "echo \${$var:-}"
        )
        if [ -z "$val" ]; then
            missing="$missing $var"
        fi
    done
    if [ -z "$missing" ]; then
        pass "config.defaults defines all required variables"
    else
        fail "config.defaults missing:$missing"
    fi

    # kernel.config must use valid Kconfig syntax (CONFIG_*=y or # CONFIG_* is not set)
    local bad_lines
    bad_lines=$(grep -vnE '^\s*$|^\s*#|^CONFIG_[A-Z0-9_]+=[ymns0-9"]+' \
                "$DEVTOOLS_DIR/kernel.config" || true)
    if [ -z "$bad_lines" ]; then
        pass "kernel.config syntax"
    else
        fail "kernel.config invalid lines: $bad_lines"
    fi

    # Every script must source config.defaults
    for f in setup.sh boot.sh build-modules.sh test-modules.sh; do
        if grep -q 'config\.defaults' "$DEVTOOLS_DIR/$f"; then
            pass "$f sources config.defaults"
        else
            fail "$f does not source config.defaults"
        fi
    done
}

# --- Script interface contracts ---
check_interfaces() {
    echo "=== Interface contracts ==="

    # --help must exit 0 for scripts that support it
    for f in boot.sh test-modules.sh; do
        if "$DEVTOOLS_DIR/$f" --help >/dev/null 2>&1; then
            pass "$f --help exits 0"
        else
            fail "$f --help exits non-zero"
        fi
    done

    # boot.sh without setup must fail with a clear message
    (
        DEVTOOLS_DIR="$DEVTOOLS_DIR"
        # Point to a non-existent cache so it thinks setup hasn't run
        export CACHE_DIR="$DEVTOOLS_DIR/.cache-nonexistent-$$"
        output=$("$DEVTOOLS_DIR/boot.sh" 2>&1 || true)
        if echo "$output" | grep -qi "setup.sh"; then
            exit 0
        else
            exit 1
        fi
    ) && pass "boot.sh without setup suggests setup.sh" \
      || fail "boot.sh without setup suggests setup.sh"

    # build-modules.sh without kernel build must fail with a clear message
    (
        export CACHE_DIR="$DEVTOOLS_DIR/.cache-nonexistent-$$"
        output=$("$DEVTOOLS_DIR/build-modules.sh" 2>&1 || true)
        if echo "$output" | grep -qi "setup.sh"; then
            exit 0
        else
            exit 1
        fi
    ) && pass "build-modules.sh without setup suggests setup.sh" \
      || fail "build-modules.sh without setup suggests setup.sh"

    # guest-test.sh must be executable
    if [ -x "$DEVTOOLS_DIR/guest-test.sh" ]; then
        pass "guest-test.sh is executable"
    else
        fail "guest-test.sh is not executable"
    fi

    # initramfs/init must be executable
    if [ -x "$DEVTOOLS_DIR/initramfs/init" ]; then
        pass "initramfs/init is executable"
    else
        fail "initramfs/init is not executable"
    fi
}

# --- Non-working list consistency ---
check_non_working() {
    echo "=== non-working list ==="

    # Validate both .ci/non-working (bare-metal) and devtools/non-working (QEMU)
    local lists=("$PROJECT_ROOT/.ci/non-working" "$DEVTOOLS_DIR/non-working")

    for nw in "${lists[@]}"; do
        local label
        label=$(basename "$(dirname "$nw")")/$(basename "$nw")

        if [ ! -f "$nw" ]; then
            echo "  SKIP  $label not found"
            continue
        fi

        # Every entry must correspond to an actual module source
        while IFS= read -r mod; do
            [ -z "$mod" ] && continue
            # Module might be built from multiple objects (e.g., startstop-objs)
            if [ -f "$PROJECT_ROOT/examples/${mod}.c" ] || \
               grep -q "^${mod}-objs" "$PROJECT_ROOT/examples/Makefile" 2>/dev/null; then
                pass "$label entry '$mod' has source"
            else
                fail "$label entry '$mod' has no matching source"
            fi
        done < "$nw"

        # No trailing whitespace
        if grep -qP '[ \t]+$' "$nw" 2>/dev/null; then
            fail "$label has trailing whitespace"
        else
            pass "$label has no trailing whitespace"
        fi
    done
}

# --- Dispatch ---
run_all() {
    check_syntax
    check_shellcheck
    check_config
    check_interfaces
    check_non_working
}

case "${1:-all}" in
    syntax)     check_syntax ;;
    shellcheck) check_shellcheck ;;
    config)     check_config ;;
    interfaces) check_interfaces ;;
    non-working) check_non_working ;;
    all)        run_all ;;
    *)          echo "Usage: $0 [syntax|shellcheck|config|interfaces|non-working|all]"; exit 1 ;;
esac

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    echo ""
    printf "%b" "$ERRORS"
    exit 1
fi
