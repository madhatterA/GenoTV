#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
header="$root/src/lt_shim/lt_shim.h"
artifact="${1:-$root/macos/libs/libtransport_lt_shim.dylib}"
if [[ ! -f "$artifact" ]]; then
  echo "missing native artifact: $artifact" >&2
  exit 2
fi

symbols_file="$(mktemp "${TMPDIR:-/tmp}/transport-lt-abi.XXXXXX")"
trap 'rm -f "$symbols_file"' EXIT
nm -gU "$artifact" | awk '{symbol=$NF; sub(/^_/, "", symbol); print symbol}' | sort -u >"$symbols_file"
missing=0
declared=0
while IFS= read -r symbol; do
  declared=$((declared + 1))
  if ! grep -Fxq "$symbol" "$symbols_file"; then
    echo "missing ABI symbol: $symbol" >&2
    missing=1
  fi
done < <(grep -Eo 'transport_lt_[A-Za-z0-9_]+[[:space:]]*\(' "$header" | sed 's/[[:space:]]*(//' | sort -u)
if (( declared == 0 )); then echo "no transport_lt_ symbols found in $header" >&2; exit 1; fi
if (( missing )); then exit 1; fi
echo "transport_lt ABI symbols: ok"
