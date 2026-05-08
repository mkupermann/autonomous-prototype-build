---
name: autonomous-prototype-build
description: 'Use when the user has a binary acceptance contract and wants the agent to keep working — measure, decide, execute, verify — until the contract passes, a hard architectural blocker forces a decision only they can make, or the wall-clock + token budget runs out. The skill writes status to a file the user can tail anytime; it does NOT ask for mid-loop confirmations. Triggers — EN: "autonomous build", "headless engineer", "ship until it works", "until it''s done", "no breaks until working", "non-stop until done". DE: "fertig bis es geht", "ohne Unterbrechung", "headless modus".'
license: MIT
version: 0.2.0
maintainer: michael@kupermann.com
---

# Autonomous Prototype Build

You give the agent: a command that exits 0 when the work is done, a wall-clock budget, a token budget, and a status file path. The agent gives you back: a green build, or a diagnostic. No "want me to continue?" interruptions.

This skill is for **delivery**, not exploration. Use brainstorming + writing-plans first to scope the work; then this skill to execute.

## 30-second pitch

```
You hand over:
  contract       = "uv run pytest tests/test_thing.py exits 0"
  user_path      = "playwright test e2e/userflow.spec.ts" (if there's a UI)
  wall_clock     = "4 hours"
  token_budget   = "5M input + 1M output"  (or a USD cap)
  status_file    = "/tmp/build_status.md"
  forbidden      = ["git push", "edit src/auth/*.py without spec amendment"]

The agent runs a measure → decide → execute → verify loop until one of:
  1. SUCCESS         — both contracts green, independent re-run agrees
  2. HARD BLOCKER    — only you can decide; agent escalates with options
  3. TIMEOUT         — wall-clock OR token budget exhausted
  4. ROLLBACK        — catastrophic regression, last change reverted

You can tail the status file anytime. It has a `## Current state` block
at the top (overwritten each iteration) and an append-only history below.
```

Skip this skill if: the goal is taste-based ("make it nicer"), one test run takes under 10 minutes total, or the work involves irreversible production actions (deploys, destructive DB ops, sending client email).

## Setup

Skills auto-load when present in `~/.claude/skills/` (or in your project's `.claude/skills/`). To trigger, say one of the phrases in the description. No install step beyond placing this folder.

The skill assumes Claude Code or a comparable agent harness with: `Bash`, `Read`, `Edit`, `Write`, and the ability to dispatch sub-agents. For UI work it also assumes Playwright, `osascript`, or your platform's UI test runner is available — see `references/user-path-verification.md`.

## When to use

- The user has explicitly authorised unattended execution.
- The acceptance contract is binary and testable. "Cosine ≥ 0.5" qualifies. "Make it nicer" does not — push back and ask for a measurable contract first.
- The budget is large enough that mid-flight check-ins would dominate (typically ≥ 2 hours).
- Failure with a thorough diagnostic is acceptable to the user — they prefer "tried hard for 6 hours, here's why it didn't pass" over "asked 12 questions over 6 hours, work is half-done."

## When NOT to use

- Ambiguous or taste-driven goals.
- High-stakes irreversible actions inside the loop.
- Tasks where the right answer is "actually we shouldn't build this" — that's a brainstorming session, not a delivery loop.

## Inputs (required)

The agent MUST extract these seven fields before starting. If any is missing or vague, it pushes back and refuses to start.

| Input | Format | Example |
|---|---|---|
| **Acceptance contract** | Concrete, binary, runnable check | `uv run pytest tests/test_X.py::test_Y exits 0` |
| **User-path verification** | Concrete check that exercises the SAME entry point a real user uses | `npx playwright test e2e/checkout.spec.ts`. See `references/user-path-verification.md`. |
| **Wall-clock budget** | Hours/minutes cap | `4 hours` |
| **Token budget** | Hard cap on cumulative tokens (input + output across loop and subagents), or a USD cap | `5M input + 1M output` or `$25 USD` |
| **Status file path** | Where the loop continuously logs | `/tmp/build_status.md` |
| **Forbidden actions** | Things to escalate before doing | `[git push, modify world/physics.py without spec]` |
| **Hard-blocker rules** | What forces an early stop with escalation | `["3 iterations with no measurable progress", "main test suite drops by >2"]` |

If the contract isn't binary/testable, the agent extracts a concrete substitute or refuses: *"To run autonomously I need a measurable acceptance check. Currently the goal reads as `<X>` — what command would I run that returns 0 if the work is done?"*

The user-path verification is non-negotiable for any UI deliverable. See `references/user-path-verification.md` for the full tooling matrix and platform-specific recipes (Playwright for web, `osascript` + `screencapture` + OCR for macOS, XCUITest for iOS, `expect` / `vhs` for TUI).

## Decision discipline

Every move is decided against these rules. There is no persona; the rules are the rules. Skipping one is the failure mode this skill exists to prevent.

1. **Evidence before assertions.** No claim of progress without a measurement. "The fix probably works" is not a claim; an exit code is.
2. **You don't understand the problem if you can't articulate the test.** Refuse to act on hypotheses that aren't immediately testable.
3. **Tight feedback loops over heroic batches.** Five 5-minute experiments beat one 90-minute speculative rewrite.
4. **Empirical humility.** When two iterations don't move the metric, the hypothesis is wrong, not the implementation. Try differently, not harder.
5. **Simpler interventions first.** Config tuning before code changes. Code changes before architecture. Architecture before greenfield.
6. **Cumulative learning.** Every iteration's findings get logged as "we now know X / we ruled out Y". Don't re-run experiments whose result is in the log.
7. **Safety is non-negotiable.** Never `--no-verify`, `--force`, or skip a quality gate. Push back on contracts that lure you toward those.
8. **Push back on weak contracts.** A vague contract = a wrong delivery. Refuse to start.

The full rules, the step-back expert-lens panel, and the voice/anti-voice guidance live in `references/decision-discipline.md`.

## Pre-flight (runs once at session start)

Before entering the loop:

```bash
# Workspace sanity
git status --porcelain                  # MUST be empty (or user explicitly acks dirty baseline)
BASELINE_SHA=$(git rev-parse HEAD)

# Determinism check on the verifying command
for i in 1 2 3; do <verifying_command> || FLAKE=1; done
# If FLAKE: refuse to start. A non-deterministic verifier means we can't tell progress from noise.

# Baseline counts
BASELINE_TEST_COUNT=$(<test_collect_command> | wc -l)

# Resource guards
df -h .                                  # disk free?
lsof -iTCP:<dev_server_port> || true     # any port we'll need already taken?
```

If any check fails, the agent writes the failure into the status file and asks the user to fix the precondition. Do not start the loop on a dirty workspace or a flaky verifier.

## The loop

```
session_start = now()
record session_start, all inputs, baseline measurements in status file

while True:
    # 1. STATUS CHECK
    snapshot = read_state()                 # git diff, last test result, last metric
    gap_structural = compare(snapshot, contract)
    gap_userpath   = compare(snapshot, userpath_contract)

    # 2. STOP CHECKS (priority order)
    if gap_structural.passes() and gap_userpath.passes():
        run_independent_verifier()          # one re-run; must agree
        if agrees: write_success_report(); break
    if wall_clock_exceeded(): write_timeout_report(); break
    if tokens_exceeded(): write_token_timeout_report(); break
    if hard_blocker_triggered(): write_escalation_report(); break
    if catastrophic_regression():
        git_reset_hard("HEAD~1")            # well-defined because we commit per iteration
        if still_broken(): write_rollback_report(); break

    # 3. PICK NEXT MOVE
    # exactly one concrete action — edit a file, run a test, dispatch a sub-agent
    move = highest_leverage_action(snapshot, gap, history)

    # 4. EXECUTE
    result = perform(move)

    # 5. CLEANUP (mandatory before verify)
    kill_orphan_subagent_processes()        # pgrep -P $$ then kill stale children
    free_claimed_ports_if_any()

    # 6. VERIFY (mandatory — no skipping)
    new_snapshot = read_state()
    delta = quantify_change(snapshot, new_snapshot)

    # 7. COMMIT (so rollback is well-defined)
    if delta is positive: git commit -am "iter-N: <move summary>"
    if delta is negative: git reset --hard HEAD; mark regression
    if delta is zero: stuck_streak += 1; do not commit

    # 8. LOG
    overwrite_current_state_block(snapshot, gap, next_action)
    append_iteration_entry(iteration_number, elapsed, tokens_used, move, delta)

    # 9. STEP BACK
    if stuck_streak >= 3: trigger step-back analysis (force a different attack vector)
```

The full pseudocode with notes on each step lives in `references/loop-pseudocode.md`.

## Self-review gates (the discipline that prevents drift)

After every iteration the agent MUST be able to write three sentences to the status file:

1. **What measurable change did this iteration produce?** Number with a unit, not "things look better."
2. **Are acceptance criteria closer or farther? By how much?** Quantitative gap.
3. **What's the single concrete next action?** A specific file edit, test run, or dispatch — not "keep iterating."

If the agent cannot answer #1 with a number for **3 consecutive iterations**, it MUST step back: stop the current attack vector, re-read the contract, re-profile the system, and pick a different attack — perhaps one that contradicts an earlier assumption. If no different attack is articulable, escalate as a hard blocker.

## Stop conditions, hierarchical

In priority order. Check in this order each iteration.

### 1. Success
Both `gap_structural` and `gap_userpath` pass + independent re-run agrees. Write `<status_file>.success.md` with: final measurements, total iterations, total wall time, total tokens consumed, `git diff` from session_start, notable findings.

### 2. Hard architectural blocker
A concrete decision only the user can make. Examples that qualify:
- Two equally valid technical paths with different downstream commitments.
- Compliance/legal/security implication beyond engineering.
- Adding an external dependency with a different licence.
- A discovery during the loop invalidates the contract itself.

Examples that do NOT qualify (do not escalate for these):
- "Should I commit this?" / "Want me to keep going?" / "This is taking longer than expected."

When escalating, write `<status_file>.escalation.md` with: the exact decision the user must make, 2-3 concrete options with measurable downstream cost, the agent's recommendation if any, and what the agent will do once they answer.

### 3. Token budget exceeded
Cumulative tokens (main loop + all subagents) hits 80% of cap → write `<status_file>.cost_warning.md`, downshift to a smaller model for non-decision moves. At 100% → stop with `<status_file>.token_timeout.md`. Tokens are logged every iteration alongside `elapsed`.

### 4. Wall-clock budget exceeded
Stop, attempt one final commit of in-progress work (if it doesn't break tests), write `<status_file>.timeout.md` with: how close to the contract (quantitative), 2-3 highest-priority next actions, partial wins worth preserving.

### 5. Catastrophic regression
Main test suite drops below baseline by more than the user-specified threshold (default 2 tests). Try `git reset --hard HEAD~1`. If still broken, write `<status_file>.rollback.md` and stop.

## Anti-patterns

Three rules. Everything else is restating the loop.

- **No claim of progress without an exit code.** If the verifying command didn't run and exit 0, you have not succeeded — regardless of how things "look."
- **No same-fix-twice.** If a hypothesis didn't move the metric, don't re-try the same thing. Pick a different attack.
- **No skipped verification gate.** After every fix, run the verifying command and capture the measurement. No exceptions.

Cost-blowup variants worth naming explicitly because they look productive:
- **Re-dispatching a failed sub-agent with the full prior transcript appended.** Costs compound geometrically. Summarise to ≤2 KB of facts before re-dispatch.
- **Step-back analysis that re-reads the entire repo every time.** Cache the relevant slice; revisit only the parts the new hypothesis touches.
- **Yak-shaving** (reformatting, refactoring, polishing irrelevant code). Every iteration must trace to the contract. If the highest-leverage action isn't on the contract path, something's wrong.

## User-path verification — the missing gate

Structural correctness ≠ user correctness. A contract that only verifies internal state can be 100% green while the user sees nothing. I shipped a 34/34-green app with an off-screen window once. This section exists because of that.

The rule: structural green is not done. The user-path verification command must also be green. Both gates must trip in the same iteration before the agent writes a success report.

If the proposed contract has no user-path command and the deliverable has a UI of any kind, the agent refuses to start and says: *"The contract you've given me is structural — it verifies that internal pieces work. It does not verify that the user can complete their flow. Before I run, I need a user-path verification command. For this stack I'd suggest `<X>`. Lock that or propose an alternative, and I'll start."*

Pure libraries / CLI-with-stdout-only / backend services with programmatic clients can skip this gate — the structural test IS the user test. If unsure, default to including it.

The full tooling matrix (Playwright, XCUITest, Espresso, `osascript`, `screencapture` + OCR, `vhs`, perceptualdiff), the macOS Screen-Recording-permission workaround, and the `--user-path-test` injection pattern live in `references/user-path-verification.md`.

## Status file format

Append-only Markdown with a rolling `## Current state` block at the top, overwritten every iteration. The point: a manager skimming the file at hour 5 of a 6-hour run sees one block to triage, not 47 iterations to scroll.

The full template lives in `references/status-file-template.md`. The minimum required fields:

```markdown
# Autonomous build — <task name> — started <ISO datetime>

## Current state — iteration N — last updated <ISO>
- Elapsed: <h:mm> / <budget>      Tokens: <n> / <cap>
- Last delta: <signed metric>     Stuck-streak: <n>
- Last move: <one sentence>
- Current hypothesis: <one sentence>
- Next planned action: <one sentence>
- Last commit: <sha>              Forbidden-action attempts: <n>

## Inputs
<contract, user_path, budgets, forbidden, blockers>

## Initial measurement
<metric=value, target=value>

---

## Iteration 1 — <elapsed> — <tokens>
<measure-before, move, measure-after, delta, next>

## Iteration 2 — ...
```

When the loop stops, the agent writes a separate report: `<status_file>.success.md` / `.escalation.md` / `.timeout.md` / `.token_timeout.md` / `.rollback.md`.

## Subagent dispatch within the loop

The loop frequently dispatches sub-agents for individual moves (the way you would in subagent-driven-development). Differences:

- Sub-agents return a result; their output FEEDS the verification step. The parent re-runs the verifying command; it does not trust sub-agent self-reports.
- Sub-agents that fail or report BLOCKED do not escalate to the user — they trigger a different attack in the parent loop.
- One sub-agent per move; never spawn five sub-agents in parallel and merge guesses.
- Each dispatch declares an expected token ceiling. A sub-agent that exceeds 2× its ceiling is killed and counted as a zero-delta iteration.

## Concrete invocation examples

Two generic examples are in `examples/`:
- `examples/invocation-web.md` — a web app where the contract is `npm test` + `npx playwright test e2e/`.
- `examples/invocation-cli.md` — a CLI/library where the contract is `uv run pytest`.

The pattern is the same: the user states the seven inputs, the agent reads SKILL.md, extracts them, runs pre-flight, and enters the loop.

## Caveats

- **Token-expensive.** Sub-agent dispatches and repeated test runs accumulate. The token budget is a real cap; treat it like a wall-clock cap.
- **Drift risk.** Occasional unwanted commits or wrong directions. Mitigated by `forbidden_actions`, the status file the user can tail mid-flight, the wall-clock + token caps, and per-iteration commits that make rollback well-defined.
- **The quality bar is the contract.** A loose contract = something that passes the contract but isn't useful. Design the contract carefully.
- **No measured success-rate data ships with this skill yet.** If you adopt it across a team, instrument: median tokens, p90 wall-clock, success rate. Without that, "autonomous" is faith-based.
- **Concurrency is not modelled.** Two engineers running this against the same repo will collide. Run on a dedicated branch or worktree.

## Composition with other skills

- **brainstorming + writing-plans first** — define the contract and the high-level approach. THEN this skill executes.
- **subagent-driven-development** — this skill internally uses sub-agent dispatch as one of its move types. The differences are autonomy + budget.
- **systematic-debugging** — for root-cause work *inside* an iteration, not as the loop driver.
- **stakeholder-review / research-stakeholder-review** — for high-stakes deliveries, run a review after the loop reports success but before merge.

## A note on contracts

The skill removes user supervision; that's the point, and that's the risk. A wrong contract gives a wrong delivery, no matter how cleanly the loop runs. Push back on weak contracts at the start. If the agent discovers mid-loop that the contract itself is wrong, that is a hard architectural blocker — escalate, do not redefine the contract autonomously.
