#!/usr/bin/env bash

set -euo pipefail

LOG_DIR=${STATUS_CHECK_LOG_DIR:-$(pwd)}
mkdir -p "${LOG_DIR}"

build_example()
{
    make -C examples 2>&1 | tee "${LOG_DIR}/build-n-run-build.log"
}

list_mod()
{
    local exclude_file=".ci/non-working"

    if [ ! -f "${exclude_file}" ]; then
        exclude_file="/dev/null"
    fi

    find examples -maxdepth 1 -name '*.ko' -print | sort \
        | sed 's#^examples/##; s#\.ko$##' \
        | { grep -vFxf "${exclude_file}" || test $? -eq 1; }
}

run_mod()
{
    local module=$1
    local module_log="${LOG_DIR}/${module}.log"

    {
        echo "=== insmod/rmmod pass 1: ${module} ==="
        sudo insmod "examples/${module}.ko"
        sudo rmmod "${module}"
        echo "=== insmod/rmmod pass 2: ${module} ==="
        sudo insmod "examples/${module}.ko"
        sudo rmmod "${module}"
    } 2>&1 | tee "${module_log}"
}

run_examples()
{
    local modules=()

    mapfile -t modules < <(list_mod)
    if [ ${#modules[@]} -eq 0 ]; then
        echo "No runnable modules found."
        return
    fi

    for module in "${modules[@]}"; do
        echo "Running ${module}"
        run_mod "${module}"
    done
}

build_example
run_examples
