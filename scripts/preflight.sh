#!/usr/bin/env bash
# preflight.sh — runnable V2 pre-flight gate for autonomous-prototype-build.
#
# This is the operator-facing version of the pre-flight block in SKILL.md.
# It runs every V2 gate in order and writes a structured pass/fail summary
# to stdout. Exit 0 = green-light the autonomous loop. Non-zero = STOP, fix
# the precondition.
#
# All inputs come from env vars so this script is harness-agnostic:
#
#   CONTRACT             required  command that exits 0 iff the work is done
#   USERPATH             optional  user-path verifying command (UI projects)
#   WALL_CLOCK           required  e.g. "4h" (free-form, hashed as-is)
#   TOKEN_BUDGET         required  e.g. "5M in + 1M out" or "$25 USD"
#   STATUS_FILE          required  where the loop will write status
#   FORBIDDEN_ACTIONS    optional  semicolon-separated list (hashed)
#   MCP_REQUIRED         optional  space-separated MCP server names         [F11]
#   SUBAGENT_SAFE        optional  "true"/"false"; default true             [F4]
#   PER_RUN_TIMEOUT      optional  seconds; default 300                     [F12]
#   DETERMINISM_RUNS     optional  how many times to re-run verifier; default 10
#   NEG_CONTROL_STRATEGY optional  auto|revert|mutate|corrupt; default auto [F7]
#
# Exit codes
#   0  all gates pass — start the loop with the printed RUN_ID
#   1  one or more gates failed — see stderr; do not start
#   2  usage / setup error

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # [F10]
PER_RUN_TIMEOUT="${PER_RUN_TIMEOUT:-300}"
DETERMINISM_RUNS="${DETERMINISM_RUNS:-10}"
SUBAGENT_SAFE="${SUBAGENT_SAFE:-true}"
NEG_CONTROL_STRATEGY="${NEG_CONTROL_STRATEGY:-auto}"

die() { echo "preflight: $*" >&2; exit 1; }
pass() { echo "  [ok]  $*"; }

# --- required inputs ---------------------------------------------------------
: "${CONTRACT:?missing required env var CONTRACT}"
: "${WALL_CLOCK:?missing required env var WALL_CLOCK}"
: "${TOKEN_BUDGET:?missing required env var TOKEN_BUDGET}"
: "${STATUS_FILE:?missing required env var STATUS_FILE}"
USERPATH="${USERPATH:-}"
FORBIDDEN_ACTIONS="${FORBIDDEN_ACTIONS:-}"
MCP_REQUIRED="${MCP_REQUIRED:-}"

echo "── autonomous-prototype-build preflight ──"

# --- timeout binary ---------------------------------------------------------
if   command -v timeout  >/dev/null 2>&1; then TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_BIN="gtimeout"
else die "neither timeout nor gtimeout found (brew install coreutils on macOS)"
fi
pass "timeout binary: $TIMEOUT_BIN"

# --- git workspace clean BEFORE any side effects ---------------------------
[ -z "$(git status --porcelain)" ] || die "workspace dirty — commit or stash first"
BASELINE_SHA="$(git rev-parse HEAD)"
pass "workspace clean at $BASELINE_SHA"

# --- weak-contract refuse (codified guard for the most common footgun) ------
# A contract that doesn't look like a runnable command is almost always a
# goal description. Refuse, point at writing-plans.
if ! printf '%s' "$CONTRACT" | grep -qE '(pytest|npm|yarn|pnpm|jest|playwright|cargo|go test|mvn|gradle|make |bash |sh |\./|swift|xcodebuild|grep |test -|exits? 0|return 0|return code)'; then
    echo "preflight: CONTRACT does not look runnable: $CONTRACT" >&2
    echo "          expected something like 'uv run pytest tests/foo.py exits 0'" >&2
    echo "          scope the work with brainstorming + writing-plans first." >&2
    exit 1
fi
pass "contract is shaped like a runnable check"

# --- concurrency lock --------------------------------------------------------
# Lock lives inside .git/ — never tracked by git, so it cannot dirty the
# workspace or interfere with the negative-control's revert strategy.
GIT_DIR="$(git rev-parse --git-dir)"
LOCK="$GIT_DIR/autonomous-build.lock"
if [ -e "$LOCK" ] && kill -0 "$(awk '{print $1}' "$LOCK" 2>/dev/null)" 2>/dev/null; then
    die "another autonomous build is running (PID $(awk '{print $1}' "$LOCK"))"
fi
echo "$$ $(date -u +%FT%TZ)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
pass "concurrency lock acquired ($LOCK)"

# --- compute Run-ID ---------------------------------------------------------
RUN_ID="$(bash "$SKILL_DIR/compute-run-id.sh" \
    "$CONTRACT" "$USERPATH" "$WALL_CLOCK" "$TOKEN_BUDGET" "$BASELINE_SHA")"
pass "RUN_ID = $RUN_ID"

# --- determinism check (under per-run cap) ----------------------------------
echo "── determinism (${DETERMINISM_RUNS} runs, ${PER_RUN_TIMEOUT}s cap) ──"
FAILS=0; HANGS=0
for i in $(seq 1 "$DETERMINISM_RUNS"); do
    set +e
    "$TIMEOUT_BIN" "$PER_RUN_TIMEOUT" bash -c "$CONTRACT" >/dev/null 2>&1
    rc=$?
    set -e
    if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then HANGS=$((HANGS+1))
    elif [ "$rc" -ne 0 ]; then FAILS=$((FAILS+1))
    fi
done
if [ "$HANGS" -gt 0 ]; then die "verifier hung $HANGS/$DETERMINISM_RUNS times (raise PER_RUN_TIMEOUT or fix flakiness)"; fi
if [ "$FAILS" -gt 0 ] && [ "$FAILS" -lt "$DETERMINISM_RUNS" ]; then
    die "verifier flaky: $FAILS/$DETERMINISM_RUNS failed; deterministic verifier required"
fi
pass "determinism: $((DETERMINISM_RUNS - FAILS))/${DETERMINISM_RUNS} consistent"

# --- negative control (the silent-pass guard) [F7] --------------------------
echo "── negative-control (must FAIL on broken state) ──"
set +e
bash "$SKILL_DIR/neg-control.sh" "$CONTRACT" --strategy "$NEG_CONTROL_STRATEGY" --timeout "$PER_RUN_TIMEOUT"
NC_RC=$?
set -e
case "$NC_RC" in
    0) pass "negative control rejected the broken state" ;;
    1) die "VERIFIER PASSED A BROKEN STATE — silent-pass contract; refuse to start" ;;
    2) die "negative-control setup error (see stderr above)" ;;
    3) die "no viable negative-control strategy (no commits, no asserts, no fixtures)" ;;
    *) die "negative-control unexpected exit $NC_RC" ;;
esac

# --- subagent write-probe [F4] ----------------------------------------------
if [ "$SUBAGENT_SAFE" = "true" ]; then
    echo "── subagent write-probe ──"
    PROBE="$(mktemp -t apb-probe.XXXXXX)"
    # The probe is a no-op in this runnable preflight: an actual harness must
    # override this section by exporting SUBAGENT_PROBE_CMD with a command
    # that dispatches a subagent which writes "$PROBE". If unset, we skip
    # with a loud warning so the operator knows the gate didn't run.
    if [ -n "${SUBAGENT_PROBE_CMD:-}" ]; then
        bash -c "PROBE='$PROBE' $SUBAGENT_PROBE_CMD" || die "subagent probe command failed"
        [ -s "$PROBE" ] || die "subagent could not write — refuse to start"
        rm -f "$PROBE"
        pass "subagent write-probe passed"
    else
        rm -f "$PROBE"
        echo "  [warn] SUBAGENT_PROBE_CMD not set; cannot verify subagent writes."
        echo "         Export SUBAGENT_PROBE_CMD='...your-dispatch... echo 1 > \$PROBE'"
        echo "         or set SUBAGENT_SAFE=false if this loop does no subagent dispatch."
    fi
else
    pass "subagent write-probe skipped (SUBAGENT_SAFE=false)"
fi

# --- MCP availability [F11] -------------------------------------------------
if [ -n "$MCP_REQUIRED" ]; then
    echo "── MCP availability ──"
    if ! command -v claude >/dev/null 2>&1; then
        echo "  [warn] 'claude' CLI not on PATH — cannot verify MCP. Skipping."
        echo "         Re-run from a Claude Code session, or unset MCP_REQUIRED."
    else
        MCP_LIST="$(claude mcp list 2>/dev/null || true)"
        for mcp in $MCP_REQUIRED; do
            if ! echo "$MCP_LIST" | grep -q "^$mcp"; then
                die "MCP '$mcp' not loaded — add it via 'claude mcp add' and restart the session"
            fi
        done
        pass "all required MCP servers loaded: $MCP_REQUIRED"
    fi
fi

# --- resource guards --------------------------------------------------------
echo "── resource guards ──"
DF_AVAIL_KB="$(df -k . | awk 'NR==2 {print $4}')"
if [ "$DF_AVAIL_KB" -lt 1048576 ]; then
    echo "  [warn] less than 1 GiB free on workspace volume"
fi
pass "disk: $((DF_AVAIL_KB / 1024)) MiB free"

# --- status file header -----------------------------------------------------
mkdir -p "$(dirname "$STATUS_FILE")"
{
    echo "# Autonomous build — started $(date -u +%FT%TZ)"
    echo "Run-ID: $RUN_ID"
    echo "Iteration counter: monotonic; out-of-order = bug"
    echo ""
    echo "## Inputs"
    echo "- contract: $CONTRACT"
    echo "- userpath: ${USERPATH:-<none>}"
    echo "- wall_clock: $WALL_CLOCK"
    echo "- token_budget: $TOKEN_BUDGET"
    echo "- forbidden: ${FORBIDDEN_ACTIONS:-<none>}"
    echo "- mcp_required: ${MCP_REQUIRED:-<none>}"
    echo "- subagent_safe: $SUBAGENT_SAFE"
    echo "- baseline_sha: $BASELINE_SHA"
    echo ""
} > "$STATUS_FILE"
pass "status file initialised at $STATUS_FILE"

echo ""
echo "── preflight PASSED — RUN_ID=$RUN_ID ──"
echo "Hand this RUN_ID to the loop. Resume only if status file's Run-ID matches."
exit 0
