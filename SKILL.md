---
name: autonomous-prototype-build
description: 'Use when the user has a binary acceptance contract and wants the agent to keep working — measure, decide, execute, verify — until the contract passes, a hard architectural blocker forces a decision only they can make, or the wall-clock + token budget runs out. Suited for prototype/POC delivery work that grinds: a failing test suite to drive green, a flaky integration to chase down, a small endpoint to ship. The skill writes status to a file the user can tail anytime; it does NOT ask for mid-loop confirmations. V2 hardens against the failure modes observed in past runs and recorded in the claude_memory database (verifier-command bugs, subagent miscounts, silent-pass tests, stream-timeout resume, MCP/permission gaps, helper-script path drift). V2.1 ships runnable scripts (preflight.sh, neg-control.sh, compute-run-id.sh) so [F7] is no longer a placeholder, plus an OPERATOR_QUICKREF.md and a codified weak-contract refusal in pre-flight. Triggers — EN: "run until green", "agentic build until done", "fire and forget", "ship until it works", "no breaks until working", "non-stop until done", "build the prototype until it works". DE: "lauf alleine durch", "ohne Pause durchziehen", "bau das durch", "ohne Rückfrage", "headless durchlaufen lassen", "prototyp ohne Unterbrechung". Do NOT use for: taste-based goals ("make this nicer"), exploratory questions, single-test debugging that takes under 10 minutes total, or anything involving irreversible production actions (deploys, destructive DB ops, sending client email).'
license: MIT
version: 2.1.0
maintainer: michael@kupermann.com
supersedes: autonomous-prototype-build@2.0.0
---

# Autonomous Prototype Build

You give the agent: a command that exits 0 when the work is done, a wall-clock budget, a token budget, and a status file path. The agent gives you back: a green build, or a diagnostic. No "want me to continue?" interruptions.

> **New here? Read `OPERATOR_QUICKREF.md` first** — 30-line version of this document, plus the runnable pre-flight invocation. Come back to this file when something in the quickref isn't enough.

This is the V2 hardening of the original skill. Every guardrail added in V2 is provenance-tagged with the database finding that motivated it (`[F#]` markers); the changelog is in `references/v2-changelog.md`. The pre-V2 version is preserved at `archive/SKILL.v0.2.2.md` for reference. V2.1 (this version) replaces the pre-flight placeholders with runnable scripts under `scripts/`.

This skill is for **delivery**, not exploration. Use brainstorming + writing-plans first to scope the work; then this skill to execute.

## What's new in V2 (failure modes V0.2.2 didn't catch)

V2 adds nine guardrails. Each one closes a hole that the V0.2.2 SimpleMD run, or a recorded failure in `claude_memory`, walked through.

1. **Negative-control verifier check** in pre-flight — refuses to start if the verifier passes a *deliberately broken* state. [F7: silent-pass tests can never fail.]
2. **Verifier-amendment protocol** — explicit handling for "the contract intent is right but the verification *command* is broken/destructive/non-portable." [F1: the SimpleMD run silently rewrote two verifier commands; that gray-area decision now has a written rule.]
3. **Run-ID hash + status-file resume** — `SHA256(contract + budgets + forbidden + baseline_sha)` written into the status file. New sessions resume only if the run-id matches. [F5/F6: stream-timeouts and websocket disconnects shouldn't lose 6 hours of work.]
4. **Trust-but-verify subagents** — parent NEVER trusts subagent self-reported counts; always re-runs the verifying command and parses raw output. Spot-check any subagent diagnosis before acting on it. [F3, F9.]
5. **Subagent write-probe** in pre-flight — dispatches a sentinel subagent that writes a 1-byte file. If it can't, refuse to start. [F4: bypassPermissions ≠ project-settings permission.]
6. **MCP availability check** in pre-flight — declares all required MCP tools up front; missing = refuse to start (MCP load happens at session boot, can't be added mid-loop). [F11.]
7. **Per-call subprocess timeout cap** — every external command in pre-flight and the loop runs under `timeout`/`gtimeout` or an in-shell trap. Killed = zero-delta, not unbounded hang. [F12: AppleScript and similar tools have hung whole sessions repeatedly.]
8. **Path-resolving helpers** — every script in this skill folder resolves its own dir via `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)`. No hardcoded `~/.claude/skills/...`. [F10: the skill folder is reachable through a symlink and may be relocated.]
9. **Monotonic iteration counter + ordered status file** — iteration entries append in strict order; out-of-order entries are a regression bug. [F2: the SimpleMD run's status file logged 1→3→2→4 because moves were named after the *kind* of work, not the *order* they completed.]

Two more soft signals (advisory, not gate):

- **Budget-undershoot flag.** If the run reports SUCCESS using <30% of budget, the success report calls it out with: *"contract may be too narrow — consider tightening before relying on this as a delivery signal."* [F15.]
- **Optional adversarial post-success.** After SUCCESS, optionally invoke `stakeholder-review` (v2) for a binary verdict gate before the user accepts delivery. [F14.]

## 30-second pitch

```
You hand over:
  contract       = "uv run pytest tests/test_thing.py exits 0"
  user_path      = "playwright test e2e/userflow.spec.ts" (if there's a UI)
  wall_clock     = "4 hours"
  token_budget   = "5M input + 1M output"  (or a USD cap)
  status_file    = "/tmp/build_status.md"
  forbidden      = ["git push", "edit src/auth/*.py without spec amendment"]
  mcp_required   = ["postgres", "browse"]            # NEW in V2 [F11]
  subagent_safe  = true                              # NEW in V2 [F4] — pre-flight verifies

The agent runs a measure → decide → execute → verify loop until one of:
  1. SUCCESS         — both contracts green, independent re-run agrees,
                       and the verifier provably FAILS on a known-broken state
                       (negative control, V2 [F7])
  2. HARD BLOCKER    — only you can decide; agent escalates with options
  3. TIMEOUT         — wall-clock OR token budget exhausted
  4. ROLLBACK        — catastrophic regression, last change reverted
  5. RESUME          — prior session's status file is found with a matching run-id;
                       agent picks up from last-good commit (V2 [F5])

You can tail the status file anytime. It has a `## Current state` block
at the top (overwritten each iteration) and an append-only history below.
```

Skip this skill if: the goal is taste-based ("make it nicer"), one test run takes under 10 minutes total, or the work involves irreversible production actions (deploys, destructive DB ops, sending client email).

## Setup

Skills auto-load when present in `~/.claude/skills/` (or in your project's `.claude/skills/`). To trigger, say one of the phrases in the description. No install step beyond placing this folder.

The skill assumes Claude Code or a comparable agent harness with: `Bash`, `Read`, `Edit`, `Write`, and the ability to dispatch sub-agents. For UI work it also assumes Playwright, `osascript`, or your platform's UI test runner is available — see `references/user-path-verification.md` (carried over from V0.2.2).

## When to use

- The user has explicitly authorised unattended execution.
- The acceptance contract is binary and testable. "Cosine ≥ 0.5" qualifies. "Make it nicer" does not — push back and ask for a measurable contract first.
- The budget is large enough that mid-flight check-ins would dominate (typically ≥ 2 hours).
- Failure with a thorough diagnostic is acceptable — the user prefers "tried hard for 6 hours, here's why it didn't pass" over "asked 12 questions over 6 hours, work is half-done."

## When NOT to use

- Ambiguous or taste-driven goals.
- High-stakes irreversible actions inside the loop.
- Tasks where the right answer is "actually we shouldn't build this" — that's a brainstorming session, not a delivery loop.

## Inputs (required)

The agent MUST extract these nine fields before starting. If any is missing or vague, it pushes back and refuses to start. Two are new in V2 (`mcp_required`, `subagent_safe`).

| Input | Format | Example |
|---|---|---|
| **Acceptance contract** | Concrete, binary, runnable check | `uv run pytest tests/test_X.py::test_Y exits 0` |
| **User-path verification** | Concrete check that exercises the SAME entry point a real user uses | `npx playwright test e2e/checkout.spec.ts`. See `references/user-path-verification.md`. |
| **Wall-clock budget** | Hours/minutes cap | `4 hours` |
| **Token budget** | Hard cap on cumulative tokens (input + output across loop and subagents), or a USD cap | `5M input + 1M output` or `$25 USD` |
| **Status file path** | Where the loop continuously logs | `/tmp/build_status.md` |
| **Forbidden actions** | Things to escalate before doing | `[git push, modify world/physics.py without spec]` |
| **Hard-blocker rules** | What forces an early stop with escalation | `["3 iterations with no measurable progress", "main test suite drops by >2"]` |
| **mcp_required** *(V2)* | List of MCP servers/tools the loop will need | `["postgres", "github", "browse"]` — pre-flight verifies they're loaded; missing → refuse to start (MCP loads at session boot only). [F11] |
| **subagent_safe** *(V2)* | Boolean — does the loop dispatch sub-agents? | If `true`, pre-flight runs a write-probe to confirm subagents can actually write to the workspace. [F4] |

If the contract isn't binary/testable, the agent extracts a concrete substitute or refuses: *"To run autonomously I need a measurable acceptance check. Currently the goal reads as `<X>` — what command would I run that returns 0 if the work is done?"*

The user-path verification is non-negotiable for any UI deliverable. See `references/user-path-verification.md` for the full tooling matrix and platform-specific recipes.

## Decision discipline

Every move is decided against these rules. There is no persona; the rules are the rules.

1. **Evidence before assertions.** No claim of progress without a measurement.
2. **You don't understand the problem if you can't articulate the test.**
3. **Tight feedback loops over heroic batches.** Five 5-minute experiments beat one 90-minute speculative rewrite.
4. **Hypothesis-first.** When two iterations don't move the metric, the hypothesis is wrong, not the implementation.
5. **Simpler interventions first.** Config tuning before code changes. Code changes before architecture. Architecture before greenfield.
6. **Cumulative learning.** Every iteration's findings get logged as "we now know X / we ruled out Y."
7. **Safety is non-negotiable.** Never `--no-verify`, `--force`, or skip a quality gate.
8. **Push back on weak contracts.** A vague contract = a wrong delivery. Refuse to start.
9. **Trust-but-verify subagents.** *(V2)* Subagent self-reports — especially counts ("12 tests passed") — are not evidence. Parent re-runs the verifying command on the same workspace and parses raw output. [F3, F9]
10. **The verifier is part of the contract.** *(V2)* If the verifier command itself is buggy/destructive/non-portable, that's a bounded amendment, not a free hand to redefine the goal. See "Verifier-amendment protocol" below. [F1]

The full rules live in `references/decision-discipline.md` (carried over from V0.2.2).

## Pre-flight (runs once at session start)

Pre-flight is the gate: if any check fails, write the failure into the status file and stop. **Five new V2 checks** marked `[V2]`.

```bash
# ─── Skill self-locate (V2 [F10]) ─────────────────────────────────────
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# All helper scripts under $SKILL_DIR; never hardcode ~/.claude/skills.

# ─── Workspace sanity FIRST (before any side effects) ────────────────
# Check workspace clean BEFORE writing the lock file. If we wrote the lock
# first, an unignored lock path would itself dirty the workspace and the
# clean-check would fail on our own footprint. (Caught in v2 smoke test.)
[ -z "$(git status --porcelain)" ] || { echo "dirty workspace — commit or stash first"; exit 1; }
BASELINE_SHA=$(git rev-parse HEAD)

# ─── Concurrency lock — one autonomous build per repo ────────────────
LOCK=.claude/autonomous-build.lock
mkdir -p .claude 2>/dev/null
if [ -e "$LOCK" ] && kill -0 "$(awk '{print $1}' "$LOCK")" 2>/dev/null; then
    echo "Another autonomous build is running (PID $(awk '{print $1}' "$LOCK") since $(awk '{print $2}' "$LOCK"))"; exit 1
fi
echo "$$ $(date -u +%FT%TZ)" > "$LOCK"
# Lock is under .claude/ which is conventionally gitignored. If not, ensure
# this exact path is in .gitignore so it doesn't dirty subsequent runs.
trap 'rm -f "$LOCK"' EXIT

# ─── Run-ID for resume (V2 [F5/F6/F8]) ───────────────────────────────
RUN_ID=$(printf '%s|%s|%s|%s|%s' \
    "$CONTRACT" "$USERPATH" "$WALL_CLOCK" "$TOKEN_BUDGET" "$BASELINE_SHA" \
    | shasum -a 256 | awk '{print $1}')
# Write into the status file as `Run-ID: <hex>`. On resume, refuse if mismatch.

# ─── Determinism check (10-run minimum, with timeout cap) [V0.2.2 + V2] ──
# Per-run timeout cap (V2 [F12]) prevents hung verifiers eating the entire budget.
PER_RUN_TIMEOUT=${PER_RUN_TIMEOUT:-300}      # default 5min/run; user-override
FLAKE=0
for i in $(seq 1 10); do
    timeout "$PER_RUN_TIMEOUT" bash -c "$VERIFYING_COMMAND" || FLAKE=1
done
# If FLAKE: refuse to start. A non-deterministic verifier means we can't tell progress from noise.

# ─── Negative-control: verifier MUST fail on a broken state (V2 [F7]) ──
# A test suite that can never fail is worthless as a contract.
# V2.1: ship a runnable strategy library instead of pseudocode.
# scripts/neg-control.sh tries three reversible mutations (revert last
# commit, flip an assertion in tests/, corrupt a fixture) and asserts the
# verifier exits non-zero on the broken state. Exit 0 = good. Exit 1 =
# silent-pass contract; refuse to start.
bash "$SKILL_DIR/scripts/neg-control.sh" "$VERIFYING_COMMAND" \
    --strategy "${NEG_CONTROL_STRATEGY:-auto}" \
    --timeout "$PER_RUN_TIMEOUT"

# ─── Subagent write-probe (V2 [F4]) ──────────────────────────────────
# Dispatch a sentinel subagent that writes a 1-byte file. Confirms permission stack.
if [ "$SUBAGENT_SAFE" = "true" ]; then
    PROBE=/tmp/probe_$$.txt
    dispatch_subagent "echo 1 > $PROBE" || { echo "subagent dispatch failed"; exit 1; }
    [ -s "$PROBE" ] || { echo "subagent could not write — refuse to start"; exit 1; }
    rm -f "$PROBE"
fi

# ─── MCP availability check (V2 [F11]) ───────────────────────────────
# MCP servers load only at session boot. If a needed one is missing, refuse —
# the user must add it and restart Claude Code; doing so mid-loop is impossible.
for mcp in $MCP_REQUIRED; do
    claude mcp list 2>/dev/null | grep -q "^$mcp" \
        || { echo "MCP '$mcp' not loaded — restart session after adding"; exit 1; }
done

# ─── Baseline test count — robust parse, not line-count ──────────────
BASELINE_TEST_COUNT=$(<test_collect_command> | tail -1 | grep -oE '^[0-9]+')

# ─── Resource guards ─────────────────────────────────────────────────
df -h .                                  # disk free?
lsof -iTCP:<dev_server_port> || true     # any port we'll need already taken?
```

If any check fails, the agent writes the failure into the status file and asks the user to fix the precondition. **No exceptions** — silent-pass verifiers, blocked subagent writes, and missing MCP tools are not "we'll work around it" problems; they're "stop and tell the user" problems.

## The loop

The loop is unchanged from V0.2.2 except for the trust-but-verify subagent steps and the per-iteration run-id check. See `references/loop-pseudocode.md` for the full annotated pseudocode. The core skeleton:

```
while True:
    snapshot = read_state()
    gap_structural, gap_userpath = compare(snapshot, contract), compare(snapshot, userpath_contract)

    # STOP CHECKS (priority order)
    if gap_structural.passes() and gap_userpath.passes():
        # V2: independent re-run + negative-control re-check both required.
        # See "What 'success' actually means in V2" below.
        if run_independent_verifier() and reconfirm_negative_control(): break
    if wall_clock_exceeded(): break
    if tokens_exceeded(): break
    if hard_blocker_triggered(): break
    if catastrophic_regression():
        git_reset_hard("HEAD~1"); if still_broken(): break

    move = pick_move(snapshot, gap, history, last_delta_sign, exhausted_classes)

    # SUBAGENT DISPATCH (V2 hardened)
    if move.is_subagent_dispatch:
        if history.has_prior_transcript_for(move.target):
            move.context = summarise(history.transcript_for(move.target), max_kb=2)
        result = perform(move)                 # subagent returns its summary
        # V2 [F3, F9]: parent does NOT trust the summary's counts or claims.
        # Parent re-runs the verifying command itself.
        result = parent_reverify(move.target)
        if result.makes_a_claim_about_a_file:
            spot_check_against_real_file(result)   # V2 [F9]

    if tokens_exceeded(): break

    kill_orphan_subagent_processes()
    free_claimed_ports_if_any()

    # VERIFY (mandatory — no skipping)
    new_snapshot = read_state()
    delta_structural = quantify_change(snapshot.structural, new_snapshot.structural)
    delta_userpath   = quantify_change(snapshot.userpath,   new_snapshot.userpath)
    delta = min(delta_structural, delta_userpath)
    regression = (delta_structural < 0 or delta_userpath < 0)

    # COMMIT — every iteration, including zero-delta
    if regression:        git reset --hard HEAD; mark_regression()
    elif delta > 0:       git commit -am "iter-N: <move summary>"
    else:                 git commit -a --allow-empty -m "iter-N: zero-delta — <move summary>"

    last_delta_sign = sign(delta)
    delta_window.append(delta); delta_window = delta_window[-5:]

    overwrite_current_state_block(snapshot, gap, next_action)
    append_iteration_entry(monotonic_iter_n, elapsed, tokens_used, move, delta)
    # V2 [F2]: monotonic_iter_n is a single counter; never log out of order.

    # STEP-BACK (zero-streak / oscillation / slow-bleed) — unchanged from V0.2.2
    ...
```

## What "success" actually means in V2

V0.2.2 declared success when both `gap_structural` and `gap_userpath` passed and a fresh-subprocess re-run agreed. V2 adds one more gate:

- **Re-confirm negative control.** Before declaring success, run the verifier against a deliberately-broken state once more and confirm it FAILS. If it doesn't, the contract regressed mid-loop into something silent-pass — that's not success, it's hidden breakage. Escalate. [F7]

So V2 success requires: structural green + user-path green + fresh-subprocess agreement + negative-control still rejects + (if non-deterministic) seed-grid agreement (n≥10 plus an unseen-seed grid). [F8: n=3 is too few.]

## Verifier-amendment protocol (V2)

This is the rule for the gray-area moment in the SimpleMD run: the *contract intent* was right, but two *verification commands* were buggy on macOS 26 (`plutil -extract` mutated the source plist; `spctl --assess` rejected ad-hoc signatures even when the app launched fine). The agent silently rewrote both. That worked, but it was an undocumented decision the user couldn't audit until the success report.

V2 codifies it. The agent MAY amend a verifier command WITHOUT escalating IFF **all** of the following hold:

1. **Reproducible bug.** The agent has a 1-line shell repro showing the verifier behaves wrong (destructive output, false-rejects, non-portable, etc.).
2. **Property preserved.** The replacement command checks the *same property*, just by a different mechanism. Examples: `plutil -extract` → `PlistBuddy -c "Print :<key>"`. `spctl --assess` → `xattr -p com.apple.quarantine` + `pgrep -x AppName`.
3. **Non-destructive.** The replacement does not mutate the workspace or anything outside `/tmp`.
4. **Logged loudly.** A `## Verifier amendment` block in the status file with: original command, replacement, evidence-of-bug repro, property the new command actually checks. Not a footnote — a top-level block.

If any of those don't hold, this is a HARD BLOCKER — escalate to the user with the evidence and the proposed substitute. The agent does NOT redefine *what counts as done*; it only swaps the *instrument* used to measure.

Anti-rule: "the verifier is wrong because the bar is too high" is NOT an amendment, it's a contract change. Escalate.

## Resume protocol (V2)

If the session terminates mid-loop (stream timeout, harness crash, websocket disconnect, user kill), the next session can resume from the status file. [F5/F6.]

```bash
# Resume entry point — runs BEFORE pre-flight if a prior status file exists.
if [ -f "$STATUS_FILE" ]; then
    PRIOR_RUN_ID=$(awk '/^Run-ID:/ {print $2}' "$STATUS_FILE")
    EXPECTED_RUN_ID=$(compute_run_id)         # same hash as in pre-flight
    if [ "$PRIOR_RUN_ID" = "$EXPECTED_RUN_ID" ]; then
        # Same contract, same baseline — safe to resume.
        LAST_GOOD_SHA=$(git log --grep='^iter-' -1 --format=%H)
        git checkout "$LAST_GOOD_SHA"
        echo "RESUMED at iter-$(grep -c '^## Iteration' $STATUS_FILE) from $LAST_GOOD_SHA"
    else
        echo "Status file run-id mismatch — refusing to resume; archive and start fresh."
        mv "$STATUS_FILE" "$STATUS_FILE.archived-$(date +%s)"
    fi
fi
```

The status file's `Run-ID` is computed from `SHA256(contract|user_path|wall_clock|token_budget|baseline_sha)`. Any contract/budget change → new run-id → forced fresh start (no silent resume on a different goal). Pattern lifted from `claude_memory` chunk 461 (Streamlit checkpoint cache-key).

## Self-review gates (the discipline that prevents drift)

After every iteration the agent MUST be able to write three sentences to the status file:

1. **What measurable change did this iteration produce?** Number with a unit.
2. **Are acceptance criteria closer or farther? By how much?** Quantitative gap.
3. **What's the single concrete next action?** A specific file edit, test run, or dispatch.

If the agent cannot answer #1 with a number for **3 consecutive iterations**, it MUST step back: stop the current attack vector, re-read the contract, re-profile the system, pick a different attack. If no different attack is articulable, escalate as a hard blocker.

## Stop conditions, hierarchical

In priority order. Check in this order each iteration.

### 1. Success
Both gates pass + independent re-run agrees + negative control still rejects (V2). Write `<status_file>.success.md` with: final measurements, total iterations, total wall time, total tokens, `git diff` from session_start, notable findings, **and a budget-utilization line** (V2): if utilization < 30%, append *"contract may be too narrow — review before relying on this as a delivery signal."* [F15]

### 2. Hard architectural blocker
A concrete decision only the user can make. Examples:
- Two equally valid technical paths with different downstream commitments.
- Compliance/legal/security implication beyond engineering.
- Adding an external dependency with a different licence.
- A discovery during the loop invalidates the contract itself.
- A verifier-amendment criterion is NOT met (see "Verifier-amendment protocol").
- A required MCP tool is missing and adding it requires a session restart.

NOT hard blockers (do not escalate for these): "Should I commit this?" / "Want me to keep going?" / "This is taking longer than expected."

When escalating, write `<status_file>.escalation.md` with: the exact decision the user must make, 2-3 concrete options with measurable downstream cost, the agent's recommendation, and what the agent will do once they answer.

### 3. Token budget exceeded
Cumulative tokens hit 80% of cap → write `.cost_warning.md`, downshift to a smaller model for non-decision moves. At 100% → stop with `.token_timeout.md`.

### 4. Wall-clock budget exceeded
Stop, attempt one final commit of in-progress work (if it doesn't break tests), write `.timeout.md` with: how close to the contract (quantitative), 2-3 highest-priority next actions, partial wins worth preserving.

### 5. Catastrophic regression
Main test suite drops below baseline by more than the user-specified threshold (default 2 tests). Try `git reset --hard HEAD~1`. If still broken, write `.rollback.md` and stop.

## Anti-patterns

V0.2.2 had three. V2 keeps those and adds five.

- **No claim of progress without an exit code.** If the verifying command didn't run and exit 0, you have not succeeded.
- **No same-fix-twice.** If a hypothesis didn't move the metric, don't re-try the same thing. Pick a different attack.
- **No skipped verification gate.** After every fix, run the verifying command and capture the measurement.
- *(V2)* **No trusting subagent counts.** Subagents reliably miscount. Parent re-runs the verifier and parses raw output. "12 tests passed" from a subagent = 0 evidence. [F3]
- *(V2)* **No silent contract drift.** If the verifier command needs replacing, log a `## Verifier amendment` block. If the contract *intent* changes, escalate.
- *(V2)* **No silent-pass tests in the contract.** Pre-flight catches the obvious cases (verifier passes a known-broken state); the agent must also call out any test it touches that has the shape `if precondition_unmet: assert True`. [F7]
- *(V2)* **No hardcoded skill paths.** Helper scripts in this folder MUST self-resolve via `$(dirname "${BASH_SOURCE[0]}")`. The skill folder may be reached through a symlink. [F10]
- *(V2)* **No unbounded subprocesses.** Every external call gets a `timeout`/`gtimeout` cap. AppleScript, Playwright, custom CLIs — all of them. Killed = zero-delta, not unbounded hang. [F12]

Cost-blowup variants worth naming explicitly because they look productive:
- **Re-dispatching a failed sub-agent with the full prior transcript appended.** Costs compound geometrically. Summarise to ≤2 KB of facts before re-dispatch.
- **Step-back analysis that re-reads the entire repo every time.** Cache the relevant slice; revisit only the parts the new hypothesis touches.
- **Yak-shaving** (reformatting, refactoring, polishing irrelevant code). Every iteration must trace to the contract.

## User-path verification — the missing gate

Structural correctness ≠ user correctness. A contract that only verifies internal state can be 100% green while the user sees nothing. The story behind this section: a 34/34-green app with an off-screen window once shipped from this loop. This section exists because of that.

The rule: structural green is not done. The user-path verification command must also be green. Both gates must trip in the same iteration before the agent writes a success report.

If the proposed contract has no user-path command and the deliverable has a UI of any kind, the agent refuses to start: *"The contract you've given me is structural — it verifies that internal pieces work. It does not verify that the user can complete their flow. For this stack I'd suggest `<X>`. Lock that or propose an alternative, and I'll start."*

Pure libraries / CLI-with-stdout-only / backend services with programmatic clients can skip this gate — the structural test IS the user test. If unsure, default to including it.

The full tooling matrix lives in `references/user-path-verification.md`.

## Status file format

Append-only Markdown with a rolling `## Current state` block at the top, overwritten every iteration.

V2 adds two required header fields: **Run-ID** and **Iteration counter monotonicity warning**.

```markdown
# Autonomous build — <task name> — started <ISO datetime>
Run-ID: <sha256>                                  # NEW in V2
Iteration counter: monotonic; out-of-order = bug  # NEW in V2

## Current state — iteration N — last updated <ISO>
- Elapsed: <h:mm> / <budget>      Tokens: <n> / <cap>
- Last delta: <signed metric>     Stuck-streak: <n>
- Last move: <one sentence>
- Current hypothesis: <one sentence>
- Next planned action: <one sentence>
- Last commit: <sha>              Forbidden-action attempts: <n>
- Verifier amendments: <n>        # NEW in V2 — count of approved amendments

## Inputs
<contract, user_path, budgets, forbidden, blockers, mcp_required, subagent_safe>

## Initial measurement
<metric=value, target=value, negative_control=fails-as-expected>

---

## Iteration 1 — <elapsed> — <tokens>
<measure-before, move, measure-after, delta, next>

## Verifier amendment — iteration N           # NEW in V2; appears only when used
- Original: <command>
- Replacement: <command>
- Evidence (1-line repro): <output>
- Property preserved: <which property the new command checks>

## Iteration 2 — ...
```

When the loop stops, the agent writes a separate report: `<status_file>.success.md` / `.escalation.md` / `.timeout.md` / `.token_timeout.md` / `.rollback.md`.

## Subagent dispatch within the loop (V2 hardened)

The loop frequently dispatches sub-agents for individual moves. V2 hardens four points:

- Sub-agents return a result; their output FEEDS the verification step. **Parent re-runs the verifying command** (V0.2.2 said this; V2 makes it a discipline rule, not a recommendation). [F3]
- **Parent spot-checks any specific claim.** If a subagent says "the bug is in `foo.py:42`", the parent reads `foo.py` line 42 before acting. [F9]
- **Counts are never trusted.** "All 12 tests pass" from a subagent ≠ 12 tests pass. The parent runs the test command itself and parses output (e.g., for pytest: `tail -1` → `grep -oE '[0-9]+ passed'`). [F3]
- Sub-agents that fail or report BLOCKED do not escalate to the user — they trigger a different attack in the parent loop. A BLOCKED return counts as zero-delta toward the stuck-streak unless parent's re-verification finds new evidence.
- One sub-agent per move; never spawn five sub-agents in parallel and merge guesses.
- Each dispatch declares an expected token ceiling. A sub-agent that exceeds 2× its ceiling is killed and counted as a zero-delta iteration.
- **Parent stamps each subagent dispatch with `claimed_at`; reaper kills any subagent whose claim is >5× expected duration.** Pattern lifted from `claude_memory` chunk 317 (worker stuck-processing bug). [F13]

## MCP and session-restart awareness (V2)

MCP servers load at session start only. If the loop discovers it needs a server that isn't loaded, the answer is NEVER "add it and continue" — adding requires a Claude Code session restart, which kills the loop. [F11]

The pre-flight `mcp_required` check is the gate. If something becomes obviously needed mid-loop, the loop escalates as a hard blocker: *"This run needs MCP server `<X>` which isn't loaded. Add it via `claude mcp add --scope user <X> ...`, restart the session, and re-invoke the skill — your status file's run-id will let it resume from the last commit."*

## Concrete invocation examples

Two generic examples are in `examples/` (carried over from V0.2.2):
- `examples/invocation-web.md` — web app where the contract is `npm test` + `npx playwright test e2e/`.
- `examples/invocation-cli.md` — CLI/library where the contract is `uv run pytest`.

The pattern is the same: the user states the nine inputs (V2), the agent reads SKILL.md, extracts them, runs pre-flight, and enters the loop.

## Caveats

- **Token-expensive.** Sub-agent dispatches and repeated test runs accumulate. The token budget is a real cap.
- **Drift risk.** Mitigated by `forbidden_actions`, the status file the user can tail mid-flight, the wall-clock + token caps, per-iteration commits that make rollback well-defined, and (V2) the verifier-amendment protocol that makes any contract-instrument change loud.
- **The quality bar is the contract.** A loose contract = something that passes the contract but isn't useful. V2's negative-control check catches the *silent-pass* class but not the *too-narrow* class — the budget-undershoot signal helps flag the latter.
- **No measured success-rate data ships with this skill yet.** Instrumentation (median tokens, p90 wall-clock, success rate) belongs in your team's adoption checklist.
- **Concurrency is not modelled.** Two engineers running this against the same repo will collide. Run on a dedicated branch or worktree.

## Composition with other skills

- **brainstorming + writing-plans first** — define the contract and the high-level approach. THEN this skill executes.
- **subagent-driven-development** — this skill internally uses sub-agent dispatch as one of its move types. The differences are autonomy + budget.
- **systematic-debugging** — for root-cause work *inside* an iteration, not as the loop driver.
- **stakeholder-review (v2) / research-stakeholder-review** — for high-stakes deliveries, run a binary-verdict review after success but before merge. V2 of this skill flags this in the success report when the binary verdict matters (high-stakes domains, irreversible follow-on actions).

## A note on contracts

The skill removes user supervision; that's the point, and that's the risk. A wrong contract gives a wrong delivery, no matter how cleanly the loop runs. Push back on weak contracts at the start. If the agent discovers mid-loop that the contract itself is wrong (not just the verifier command), that is a hard architectural blocker — escalate, do not redefine the contract autonomously.

V2 adds explicit machinery (negative control, verifier-amendment protocol, run-id resume) so that the *instruments* of measurement can be improved during a run without the *goal* drifting. The discipline is the same as V0.2.2: measure honestly, log loudly, escalate when only the user can decide.

## See also

- `OPERATOR_QUICKREF.md` — 30-line cheatsheet for fast invocation.
- `scripts/preflight.sh` — runnable pre-flight (V2.1) covering every gate below.
- `scripts/neg-control.sh` — silent-pass guard with three reversible mutation strategies.
- `scripts/compute-run-id.sh` — the resume hash.
- `references/v2-changelog.md` — full provenance of V2 changes against `claude_memory` findings.
- `references/loop-pseudocode.md` — annotated loop pseudocode (carried from V0.2.2).
- `references/decision-discipline.md` — full rule set (carried from V0.2.2).
- `references/status-file-template.md` — full status file template (carried from V0.2.2).
- `references/user-path-verification.md` — UI-verification tooling matrix (carried from V0.2.2).
