#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

if [[ -n "${CLANG_FORMAT:-}" ]]; then
  clang_format="${CLANG_FORMAT}"
elif command -v clang-format-17 >/dev/null 2>&1; then
  clang_format="clang-format-17"
else
  clang_format="clang-format"
fi

if [[ -n "${FORMAT_CHECK_BASE:-}" ]]; then
  files="$(
    git diff --name-only "${FORMAT_CHECK_BASE}...HEAD" -- \
      '*.c' '*.cc' '*.cpp' '*.h' '*.hh' '*.hpp' \
      ':!third_party/**' ':!build/**'
  )"
else
  if command -v rg >/dev/null 2>&1; then
    files="$(
      rg --files \
        -g '*.{c,cc,cpp,h,hh,hpp}' \
        -g '!third_party/**' \
        -g '!build/**'
    )"
  else
    files="$(
      find . \
        -path ./third_party -prune -o \
        -path ./build -prune -o \
        -type f \( -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.h' -o -name '*.hh' -o -name '*.hpp' \) \
        -print
    )"
  fi
fi

if [[ -z "${files}" ]]; then
  echo "No C/C++ files found for format check."
  exit 0
fi

printf '%s\0' ${files} | xargs -0 "${clang_format}" --dry-run -Werror
