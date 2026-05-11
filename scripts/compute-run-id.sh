#!/usr/bin/env bash
# compute-run-id.sh — emit the V2 run-id hash on stdout.
#
# The run-id is the resume key: SHA256(contract|user_path|wall_clock|
# token_budget|baseline_sha). Identical inputs → identical hash → safe to
# resume from the last iter-N commit. Any input change → new hash →
# refuse to resume on a different goal. [F5, F6]
#
# Usage (positional, in this exact order):
#   compute-run-id.sh \
#       "$CONTRACT" \
#       "$USERPATH" \
#       "$WALL_CLOCK" \
#       "$TOKEN_BUDGET" \
#       "$BASELINE_SHA"
#
# Empty arguments are allowed (e.g., USERPATH for pure-CLI deliverables).
# The hash is stable across machines as long as the inputs match byte-for-byte.

set -euo pipefail

if [ "$#" -ne 5 ]; then
    echo "usage: $0 CONTRACT USERPATH WALL_CLOCK TOKEN_BUDGET BASELINE_SHA" >&2
    exit 2
fi

CONTRACT="$1"
USERPATH="$2"
WALL_CLOCK="$3"
TOKEN_BUDGET="$4"
BASELINE_SHA="$5"

# Use printf so trailing newlines from heredoc/cmd-substitution don't shift the hash.
# Pipe-separated; no shell expansion of any field contents.
if command -v shasum >/dev/null 2>&1; then
    printf '%s|%s|%s|%s|%s' \
        "$CONTRACT" "$USERPATH" "$WALL_CLOCK" "$TOKEN_BUDGET" "$BASELINE_SHA" \
        | shasum -a 256 \
        | awk '{print $1}'
elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s|%s|%s|%s|%s' \
        "$CONTRACT" "$USERPATH" "$WALL_CLOCK" "$TOKEN_BUDGET" "$BASELINE_SHA" \
        | sha256sum \
        | awk '{print $1}'
else
    echo "neither shasum nor sha256sum found" >&2
    exit 3
fi
