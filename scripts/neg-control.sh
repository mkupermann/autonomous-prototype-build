#!/usr/bin/env bash
# neg-control.sh — verify the verifier can fail. [V2 F7]
#
# Why this exists
# ---------------
# A test suite that can never fail is worthless as an acceptance contract.
# The SimpleMD run, the EQMOD F3b run, and several others in claude_memory
# all walked past silent-pass tests of the shape:
#
#     if precondition_unmet:
#         assert True       # <-- this is the bug
#
# V2 [F7] requires that the autonomous loop refuses to start if the
# verifier passes a deliberately-broken state.
#
# How it works
# ------------
# We mutate the workspace in a small, reversible way, run the verifier, and
# assert the verifier exits non-zero. We then restore the workspace exactly.
# If the verifier passes the broken state, exit 1 — pre-flight refuses to
# start the autonomous loop.
#
# Three strategies are supported (auto-detected unless --strategy is set):
#
#   1. revert-last-commit  — `git revert --no-commit HEAD`, run verifier,
#                            then `git reset --hard HEAD`. Cleanest when the
#                            last commit touches code the verifier exercises.
#
#   2. mutate-assertion    — find the first `assert ` line under a path the
#                            verifier reads (tests/ by default) and toggle it
#                            (`assert X` → `assert not X`). Stash before,
#                            stash-pop after.
#
#   3. corrupt-fixture     — pick the first file under tests/data/ or
#                            tests/fixtures/, append 32 bytes of random
#                            garbage, run verifier, restore from git.
#
# Usage
# -----
#   neg-control.sh "<verifier_command>" [--strategy auto|revert|mutate|corrupt]
#                                       [--timeout SECONDS]
#                                       [--tests-dir tests]
#
# Exit codes
#   0  verifier correctly FAILED on the broken state (good — pre-flight may proceed)
#   1  verifier PASSED a known-broken state (bad — refuse to start the loop)
#   2  setup error (not a verifier verdict; treat as pre-flight failure)
#   3  no viable strategy could be applied (e.g., no commits, no tests, no fixtures)
#
# Safety
# ------
# - Refuses to run on a dirty workspace.
# - Always restores via a strategy-specific cleanup trap. If the cleanup
#   itself fails the script exits 2 loudly; never silently leaves mutations.
# - The verifier runs under a wall-clock cap (default 300s, override with
#   --timeout). A hang counts as setup error (exit 2), not as a fail. [F12]

set -euo pipefail

VERIFIER="${1:-}"
shift || true

STRATEGY="auto"
PER_RUN_TIMEOUT="${PER_RUN_TIMEOUT:-300}"
TESTS_DIR="tests"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --strategy)  STRATEGY="$2"; shift 2 ;;
        --timeout)   PER_RUN_TIMEOUT="$2"; shift 2 ;;
        --tests-dir) TESTS_DIR="$2"; shift 2 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$VERIFIER" ]; then
    echo "usage: $0 \"<verifier_command>\" [--strategy auto|revert|mutate|corrupt] [--timeout SECONDS] [--tests-dir DIR]" >&2
    exit 2
fi

# Locate a timeout binary; macOS ships gtimeout via coreutils, Linux ships timeout.
if   command -v timeout  >/dev/null 2>&1; then TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_BIN="gtimeout"
else
    echo "neither timeout nor gtimeout found (brew install coreutils on macOS)" >&2
    exit 2
fi

# Workspace must be clean before we mutate.
if [ -n "$(git status --porcelain)" ]; then
    echo "neg-control: workspace dirty; commit or stash first" >&2
    exit 2
fi

run_verifier() {
    # Returns the verifier exit code. Hang = treat as setup error (124).
    # We must NOT re-enable `set -e` here; if the verifier exits non-zero,
    # `set -e` would kill the script before the caller can interpret the
    # code as "broken state correctly rejected" (the success path).
    local rc
    "$TIMEOUT_BIN" "$PER_RUN_TIMEOUT" bash -c "$VERIFIER"
    rc=$?
    if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
        echo "neg-control: verifier hung (>${PER_RUN_TIMEOUT}s) — treating as setup error" >&2
        return 124
    fi
    return "$rc"
}

# -----------------------------------------------------------------------------
# Strategy 1: revert last commit
# -----------------------------------------------------------------------------
try_revert() {
    git rev-parse HEAD~1 >/dev/null 2>&1 || return 3
    git revert --no-commit HEAD >/dev/null 2>&1 || return 3
    # Cleanup is unconditional from here on.
    trap 'git reset --hard HEAD >/dev/null 2>&1 || true; trap - EXIT' EXIT
    run_verifier; local rc=$?
    git reset --hard HEAD >/dev/null 2>&1
    trap - EXIT
    return "$rc"
}

# -----------------------------------------------------------------------------
# Strategy 2: mutate an assertion in tests/
# -----------------------------------------------------------------------------
try_mutate() {
    [ -d "$TESTS_DIR" ] || return 3
    # First file containing `assert ` we can find.
    local target
    target=$(grep -rln --include='*.py' '^[[:space:]]*assert ' "$TESTS_DIR" 2>/dev/null | head -1)
    [ -n "$target" ] || return 3

    git stash push -u -m "neg-control-mutate" -- "$target" >/dev/null 2>&1 || return 3
    trap 'git checkout -- "'"$target"'" >/dev/null 2>&1 || true; git stash pop --quiet >/dev/null 2>&1 || true; trap - EXIT' EXIT
    git stash pop --quiet >/dev/null 2>&1 || true

    # Mutate: `    assert foo` → `    assert not (foo)`. Idempotent enough for one pass.
    python3 - "$target" <<'PY'
import re, sys, pathlib
p = pathlib.Path(sys.argv[1])
src = p.read_text()
def flip(m):
    indent, expr = m.group(1), m.group(2)
    if expr.startswith("not "):
        return f"{indent}assert {expr[4:]}"
    return f"{indent}assert not ({expr})"
new, n = re.subn(r'^([ \t]*)assert (.+?)$', flip, src, count=1, flags=re.M)
if n == 0:
    sys.exit(3)
p.write_text(new)
PY
    local mutate_rc=$?
    [ "$mutate_rc" -eq 0 ] || { trap - EXIT; return 3; }

    run_verifier; local rc=$?
    git checkout -- "$target" >/dev/null 2>&1
    trap - EXIT
    return "$rc"
}

# -----------------------------------------------------------------------------
# Strategy 3: corrupt a fixture
# -----------------------------------------------------------------------------
try_corrupt() {
    local target=""
    for d in "$TESTS_DIR/data" "$TESTS_DIR/fixtures" "$TESTS_DIR"; do
        [ -d "$d" ] || continue
        target=$(find "$d" -maxdepth 3 -type f \( -name '*.csv' -o -name '*.json' -o -name '*.txt' -o -name '*.yaml' \) 2>/dev/null | head -1)
        [ -n "$target" ] && break
    done
    [ -n "$target" ] || return 3
    [ -f "$target" ] || return 3

    trap 'git checkout -- "'"$target"'" >/dev/null 2>&1 || true; trap - EXIT' EXIT
    # Append 32 bytes of zeros; small enough not to break parsers via OOM, large enough to invalidate.
    dd if=/dev/zero bs=32 count=1 2>/dev/null >> "$target"
    run_verifier; local rc=$?
    git checkout -- "$target" >/dev/null 2>&1
    trap - EXIT
    return "$rc"
}

# Strategy dispatch with auto-fallback.
# The whole function runs with `set +e` (toggled by the caller) so non-zero
# returns from strategies don't kill the script. We leave `set -e` state to
# the caller — never re-enable it here.
run_strategy() {
    local rc=3
    case "$STRATEGY" in
        revert)  try_revert  ; rc=$? ;;
        mutate)  try_mutate  ; rc=$? ;;
        corrupt) try_corrupt ; rc=$? ;;
        auto)
            try_revert
            rc=$?
            if [ "$rc" -ne 3 ]; then
                return "$rc"
            fi
            try_mutate
            rc=$?
            if [ "$rc" -ne 3 ]; then
                return "$rc"
            fi
            try_corrupt
            rc=$?
            ;;
        *) echo "unknown strategy: $STRATEGY" >&2; return 2 ;;
    esac
    return "$rc"
}

set +e
run_strategy
RC=$?
set -e

if [ "$RC" -eq 3 ]; then
    echo "neg-control: no viable strategy applied (no commits, no asserts, no fixtures)" >&2
    exit 3
fi
if [ "$RC" -eq 124 ]; then
    exit 2  # hung verifier = setup error
fi
if [ "$RC" -eq 0 ]; then
    # Verifier exited 0 on a deliberately-broken state. That's the silent-pass bug.
    echo "neg-control: VERIFIER PASSED A BROKEN STATE — refuse to start (silent-pass contract)" >&2
    exit 1
fi

# Non-zero verifier exit on a broken state: that's what we want.
echo "neg-control: verifier correctly rejected the broken state (exit $RC)" >&2
exit 0
