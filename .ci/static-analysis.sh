#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel)
LOG_DIR=${STATUS_CHECK_LOG_DIR:-"${ROOT_DIR}/.status-check-logs"}
TOOL_CACHE_DIR=${STATUS_CHECK_TOOL_CACHE_DIR:-"${ROOT_DIR}/.status-check-tools"}
mkdir -p "${LOG_DIR}" "${TOOL_CACHE_DIR}"

mapfile -t SOURCES < <(git -C "${ROOT_DIR}" ls-files '*.c' '*.cc' '*.cpp' '*.h')

count_matches()
{
    local pattern=$1
    local file=$2

    grep -E -c "${pattern}" "${file}" 2>/dev/null || true
}

update_repo()
{
    local repo_url=$1
    local repo_dir=$2

    if [ -d "${repo_dir}/.git" ]; then
        git -C "${repo_dir}" fetch --depth=1 origin
        git -C "${repo_dir}" reset --hard FETCH_HEAD
        return
    fi

    rm -rf "${repo_dir}"
    git clone --depth=1 "${repo_url}" "${repo_dir}"
}

do_cppcheck()
{
    local cppcheck_log="${LOG_DIR}/cppcheck.xml"
    local cppcheck_bin

    cppcheck_bin=$(command -v cppcheck || true)
    if [ -z "${cppcheck_bin}" ]; then
        echo "[!] cppcheck not installed. Failed to run static analysis the source code." >&2
        exit 1
    fi

    "${cppcheck_bin}" \
        --enable=warning,performance,information \
        --suppress=unusedFunction:hello-1.c \
        --suppress=missingIncludeSystem \
        --std=c89 \
        --xml \
        "${SOURCES[@]}" \
        2> "${cppcheck_log}"

    local error_count
    error_count=$(count_matches "</error>" "${cppcheck_log}")
    if [ "${error_count}" -gt 0 ]; then
        echo "Cppcheck failed: ${error_count} error(s)"
        cat "${cppcheck_log}"
        exit 1
    fi
}

do_sparse()
{
    local sparse_dir="${TOOL_CACHE_DIR}/sparse"
    local sparse_log="${LOG_DIR}/sparse.log"
    local sparse_bin
    local warning_count
    local error_count
    local count

    update_repo "https://git.kernel.org/pub/scm/devel/sparse/sparse.git" "${sparse_dir}"
    make -C "${sparse_dir}" sparse
    sparse_bin="${sparse_dir}/sparse"

    make -C examples clean >/dev/null 2>&1 || true
    if ! make -C examples C=2 CHECK="${sparse_bin}" 2> "${sparse_log}"; then
        cat "${sparse_log}"
        exit 1
    fi

    warning_count=$(count_matches " warning:" "${sparse_log}")
    error_count=$(count_matches " error:" "${sparse_log}")
    count=$((warning_count + error_count))
    if [ "${count}" -gt 0 ]; then
        echo "Sparse failed: ${warning_count} warning(s), ${error_count} error(s)"
        cat "${sparse_log}"
        exit 1
    fi
    make -C examples clean >/dev/null 2>&1 || true
}

do_gcc()
{
    local gcc_log="${LOG_DIR}/gcc.log"
    local gcc_bin
    local warning_count
    local error_count
    local count

    gcc_bin=$(command -v gcc || true)
    if [ -z "${gcc_bin}" ]; then
        echo "[!] gcc is not installed. Failed to run static analysis with GCC." >&2
        exit 1
    fi

    make -C examples clean >/dev/null 2>&1 || true
    if ! make -C examples CONFIG_STATUS_CHECK_GCC=y STATUS_CHECK_GCC="${gcc_bin}" \
        2> "${gcc_log}"; then
        cat "${gcc_log}"
        exit 1
    fi

    warning_count=$(count_matches " warning:" "${gcc_log}")
    error_count=$(count_matches " error:" "${gcc_log}")
    count=$((warning_count + error_count))
    if [ "${count}" -gt 0 ]; then
        echo "gcc failed: ${warning_count} warning(s), ${error_count} error(s)"
        cat "${gcc_log}"
        exit 1
    fi
    make -C examples CONFIG_STATUS_CHECK_GCC=y STATUS_CHECK_GCC="${gcc_bin}" clean \
        >/dev/null 2>&1 || true
}

do_smatch()
{
    local smatch_dir="${TOOL_CACHE_DIR}/smatch"
    local smatch_log="${LOG_DIR}/smatch.log"
    local smatch_bin
    local warning_count
    local error_count
    local count

    update_repo "https://github.com/error27/smatch.git" "${smatch_dir}"
    make -C "${smatch_dir}" smatch
    smatch_bin="${smatch_dir}/smatch"

    make -C examples clean >/dev/null 2>&1 || true
    if ! make -C examples C=2 CHECK="${smatch_bin} -p=kernel" > "${smatch_log}" \
        2>&1; then
        cat "${smatch_log}"
        exit 1
    fi

    warning_count=$(count_matches " warn:" "${smatch_log}")
    error_count=$(count_matches " error:" "${smatch_log}")
    count=$((warning_count + error_count))
    if [ "${count}" -gt 0 ]; then
        echo "Smatch failed: ${warning_count} warning(s), ${error_count} error(s)"
        grep -E "warn:|error:" "${smatch_log}" || true
        exit 1
    fi
    make -C examples clean >/dev/null 2>&1 || true
}

do_cppcheck
do_sparse
do_gcc
do_smatch
