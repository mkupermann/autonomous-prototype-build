# Loop pseudocode (annotated)

The full version of the loop summarised in `SKILL.md`. Each step has notes on why it's there and what failure mode it prevents.

```python
session_start = now()
record(session_start, all_inputs, baseline_measurements)
last_delta_sign = 0
delta_window   = []                          # rolling 5-iter window for oscillation detection

while True:

    # ----- 1. STATUS CHECK -----
    snapshot = read_state()
    gap_structural = compare(snapshot, contract)
    gap_userpath   = compare(snapshot, userpath_contract)
    # Both gates: structural correctness AND user correctness.
    # The whole skill exists because earlier versions only checked one.

    # ----- 2. STOP CHECKS (priority order) -----
    if gap_structural.passes() and gap_userpath.passes():
        if run_independent_verifier():       # fresh subprocess + cleared cache; see below
            write_success_report()
            break
        # else: a one-shot green is not enough; keep looping.

    if wall_clock_exceeded(session_start, wall_clock_budget):
        write_timeout_report(snapshot)
        break

    if tokens_exceeded(token_budget):
        write_token_timeout_report(snapshot)
        break
    # Wall-clock is necessary but not sufficient. A loop that fans out
    # five sub-agents per iteration can burn through cost in an hour. The
    # token cap is the hard cost guardrail.

    if hard_blocker_triggered(snapshot, history):
        write_escalation_report(snapshot, options)
        break
    # Examples that trigger: 3 zero-delta iterations followed by a
    # step-back that can't articulate a different attack; two
    # technical paths the agent can't choose between on engineering
    # grounds; contract turns out to be self-contradictory.

    if catastrophic_regression(snapshot, baseline_test_count):
        run("git reset --hard HEAD~1")
        # well-defined because step 7 commits per iteration
        if still_broken():
            write_rollback_report()
            break

    # ----- 3. PICK NEXT MOVE — heuristic, not vibes -----
    # Decision Rule 5 ordering (config → code → architecture → greenfield),
    # coupled to last_delta_sign:
    #   last_delta > 0  → stay on same class, same module
    #   last_delta < 0  → revert was already done; pick orthogonal attack at same class
    #   last_delta == 0 → escalate one class (config exhausted → code; etc.)
    # See references/decision-discipline.md for the full move-selection panel.
    move = pick_move(snapshot, gap, history, last_delta_sign)
    # ONE concrete action — edit a file, run a test, dispatch a sub-agent.

    # ----- 4. EXECUTE -----
    # Sub-agent transcript truncation is enforced HERE, not in anti-patterns.
    # If we re-dispatch a sub-agent that has prior history, summarise to ≤2 KB
    # of facts learned + hypotheses ruled out + last error verbatim. Raw
    # transcripts compound geometrically across re-dispatches.
    if move.is_subagent_dispatch and history.has_prior_transcript_for(move.target):
        move.context = summarise(history.transcript_for(move.target), max_kb=2)
    result = perform(move)
    # Second token check — a single fan-out can blow the budget mid-iteration.
    if tokens_exceeded(token_budget):
        write_token_timeout_report(snapshot)
        break

    # ----- 5. CLEANUP -----
    kill_orphan_subagent_processes()         # pgrep -P $$, SIGTERM, then SIGKILL after 2s
    free_claimed_ports_if_any()              # lsof -iTCP:<port>, kill if held by stale child
    # Without this, sub-agents that spawned a dev server or a long
    # test runner can leak processes and skew the next iteration's
    # measurements.

    # ----- 6. VERIFY (mandatory) -----
    new_snapshot = read_state()
    delta_structural = quantify_change(snapshot.structural, new_snapshot.structural)
    delta_userpath   = quantify_change(snapshot.userpath,   new_snapshot.userpath)
    # Composition rule: weakest gate sets progress; ANY negative gate triggers revert.
    if delta_structural < 0 or delta_userpath < 0:
        delta = min(delta_structural, delta_userpath)
        regression = True
    else:
        delta = min(delta_structural, delta_userpath)
        regression = False

    # ----- 7. COMMIT -----
    if regression:
        run("git reset --hard HEAD")
        mark_regression()
    elif delta > 0:
        run(f"git commit -am 'iter-{N}: {move_summary}'")
    else:
        pass                                 # no commit on zero-delta
    # Per-iteration commits are what make `git reset --hard HEAD~1`
    # well-defined. Without this, "rollback the last change" means
    # reverse-engineering the last 14 file edits.

    last_delta_sign = sign(delta)
    delta_window.append(delta); delta_window = delta_window[-5:]

    # ----- 8. LOG -----
    overwrite_current_state_block(snapshot, gap, next_action)
    append_iteration_entry(N, elapsed, tokens_used, move, delta)

    # ----- 9. STEP BACK — smoothed, catches oscillation as well as flatline -----
    zero_streak = count_trailing(delta_window, lambda d: d == 0)
    net_window  = sum(delta_window)
    oscillating = (len(delta_window) == 5
                   and abs(net_window) <= NOISE_THRESHOLD
                   and any(d > 0 for d in delta_window)
                   and any(d < 0 for d in delta_window))
    if zero_streak >= 3 or oscillating:
        consult_expert_lens_panel()          # see references/decision-discipline.md
        new_attack = pick_different_vector()
        if not new_attack:
            escalate_as_hard_blocker()
            break
        delta_window = []                    # reset so we don't immediately re-fire
```

## Defined functions

### `run_independent_verifier()`

Re-runs the verifying command in a **fresh subprocess** with cleared transient state. Same-shell re-runs miss test pollution.

```bash
# Clear common per-language caches
find . -type d -name __pycache__ -prune -exec rm -rf {} +
rm -rf .pytest_cache .ruff_cache 2>/dev/null
rm -rf node_modules/.cache 2>/dev/null

# Run in a fresh subprocess (note bash -c, not eval in parent shell)
bash -c "$verifying_command"
```

Returns true only if the fresh run agrees with the in-process run that triggered the success check. If the fresh run fails, the loop continues — the structural-and-userpath green from step 1 was test pollution, not real progress.

### `kill_orphan_subagent_processes()`

```bash
# Enumerate descendants of the current process tree
PIDS=$(pgrep -P $$)
[ -z "$PIDS" ] && return 0
# Graceful kill first
kill -TERM $PIDS 2>/dev/null
sleep 2
# Force any stragglers
kill -KILL $PIDS 2>/dev/null
```

### `summarise(transcript, max_kb)`

Not raw truncation — extraction. Output structure:

```
## Facts learned this attempt (5-10 bullets)
## Hypotheses ruled out (3-5 bullets)
## Last error verbatim
<exact stderr / failing assertion / trace>
```

Drop: tool-call dumps, intermediate reasoning, successful-but-irrelevant sub-results. Truncating raw transcripts to N KB without extraction loses the load-bearing facts.

### `pick_move()`

Walks the move-selection panel (see `references/decision-discipline.md`) top-down, filtered by what history has already ruled out:

```python
def pick_move(snapshot, gap, history, last_delta_sign):
    if last_delta_sign > 0:
        return same_class_same_module(snapshot, history)
    elif last_delta_sign < 0:
        return same_class_orthogonal(snapshot, history)
    else:
        return escalate_one_class(snapshot, history)
```

## Notes per step

### 1. Status check
The two-gap split (structural + user-path) is non-optional for UI deliverables. See `user-path-verification.md`.

### 2. Stop checks
Order matters. Check success first (cheap, terminates the loop). Wall-clock and token budgets next (both are hard caps). Hard blocker before regression (a blocker should escalate cleanly, not get masked by a botched fix). Regression last (and only after the others, because it's the most aggressive — full reset).

### 3. Pick next move
This is where most loops drift. The rule "exactly one concrete action" is enforced by the self-review gates: if the agent can't write a one-sentence "next planned action", the loop is broken. Coupling the move to `last_delta_sign` plus Decision Rule 5 takes this from vibes to mechanics.

### 4. Execute
Sub-agent dispatch happens here. Headline: one sub-agent per move; declare a token ceiling; kill at 2× the ceiling. Re-dispatch summarises (not truncates) prior transcripts. The second token-budget check after EXECUTE is the critical guardrail against a single fan-out blowing the cap mid-iteration.

### 5. Cleanup
Often skipped, often the cause of "why did the next iteration fail mysteriously". Process leaks, port collisions, file locks, leftover `node_modules` mutations.

### 6. Verify
Even "trivial" iterations get verified. The two-gate composition (`min(delta_structural, delta_userpath)`) ensures the weakest gate paces progress. Improving structural while user-path regresses is NOT progress; it's a regression that the simple "did the metric go up?" check would have rewarded.

### 7. Commit
Per-iteration commits are what make `git reset --hard HEAD~1` a well-defined rollback. Without this, "rollback the last change" means re-implementing reverse-engineering the last 14 file edits.

### 8. Log
Two writes per iteration: overwrite the rolling block, append the immutable history entry. Both go to the same file.

### 9. Step back
Two triggers: trailing 3 zero-deltas (flatline), or a 5-iter window that nets near zero with at least one positive and one negative (oscillation). The second catches the case where +1/-1/+1/-1/+1 keeps the zero-streak at zero while the loop produces nothing. The expert lens panel in `decision-discipline.md` forces structured reflection rather than "let me try one more thing."
