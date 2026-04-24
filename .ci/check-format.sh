#!/usr/bin/env bash

set -euo pipefail

mapfile -t SOURCES < <(git ls-files '*.c' '*.cc' '*.cpp' '*.h')
if [ ${#SOURCES[@]} -eq 0 ]; then
    exit 0
fi

CLANG_FORMAT=$(command -v clang-format-20 || command -v clang-format || true)
if [ -z "${CLANG_FORMAT}" ]; then
    echo "[!] clang-format not installed. Install clang-format-20 or clang-format." >&2
    exit 1
fi

LOG_DIR=${STATUS_CHECK_LOG_DIR:-$(pwd)}
mkdir -p "${LOG_DIR}"
DIFF_LOG="${LOG_DIR}/check-format.diff"
TMP_FILE=$(mktemp)
trap 'rm -f "${TMP_FILE}"' EXIT

: > "${DIFF_LOG}"

for file in "${SOURCES[@]}"; do
    "${CLANG_FORMAT}" "${file}" > "${TMP_FILE}"
    if ! diff -u -p --label="${file}" --label="expected coding style" \
        "${file}" "${TMP_FILE}" >> "${DIFF_LOG}"; then
        cat "${DIFF_LOG}"
        exit 1
    fi
done

if "${CLANG_FORMAT}" --output-replacements-xml "${SOURCES[@]}" | grep -Eq "</replacement>"; then
    exit 1
fi
