# Loop pseudocode (annotated)

The full version of the loop summarised in `SKILL.md`. Each step has notes on why it's there and what failure mode it prevents.

```python
session_start = now()
record(session_start, all_inputs, baseline_measurements)

while True:

    # ----- 1. STATUS CHECK -----
    snapshot = read_state()
    gap_structural = compare(snapshot, contract)
    gap_userpath   = compare(snapshot, userpath_contract)
    # Both gates: structural correctness AND user correctness.
    # The whole skill exists because earlier versions only checked one.

    # ----- 2. STOP CHECKS (priority order) -----
    if gap_structural.passes() and gap_userpath.passes():
        if independent_re_run_agrees():
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
    # five sub-agents per iteration can burn $3-5k in an hour. The token
    # cap is the hard cost guardrail.

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

    # ----- 3. PICK NEXT MOVE -----
    move = highest_leverage_action(snapshot, gap, history)
    # ONE concrete action — edit a file, run a test, dispatch a
    # sub-agent, profile a hotspot. NOT "continue trying" or
    # "iterate". If you can't name a single move, step back.

    # ----- 4. EXECUTE -----
    result = perform(move)

    # ----- 5. CLEANUP -----
    kill_orphan_subagent_processes()  # pgrep -P $$ then kill stale children
    free_claimed_ports_if_any()       # lsof + kill if needed
    # Without this, sub-agents that spawned a dev server or a long
    # test runner can leak processes and skew the next iteration's
    # measurements.

    # ----- 6. VERIFY (mandatory) -----
    new_snapshot = read_state()
    delta = quantify_change(snapshot, new_snapshot)
    # No skipping. The verifying command runs every iteration even
    # when "obviously" nothing changed.

    # ----- 7. COMMIT -----
    if delta is positive:
        run(f"git commit -am 'iter-{N}: {move_summary}'")
    elif delta is negative:
        run("git reset --hard HEAD")
        mark_regression()
    elif delta is zero:
        stuck_streak += 1
        # do NOT commit zero-delta moves; keeps the rollback target
        # to the last green state.

    # ----- 8. LOG -----
    overwrite_current_state_block(snapshot, gap, next_action)
    append_iteration_entry(N, elapsed, tokens_used, move, delta)

    # ----- 9. STEP BACK -----
    if stuck_streak >= 3:
        consult_expert_lens_panel()  # see references/decision-discipline.md
        new_attack = pick_different_vector()
        if not new_attack:
            escalate_as_hard_blocker()
            break
        stuck_streak = 0
```

## Notes per step

### 1. Status check
The two-gap split (structural + user-path) is non-optional for UI deliverables. See `user-path-verification.md`.

### 2. Stop checks
Order matters. Check success first (cheap, terminates the loop). Wall-clock and token budgets next (both are hard caps). Hard blocker before regression (a blocker should escalate cleanly, not get masked by a botched fix). Regression last (and only after the others, because it's the most aggressive — full reset).

### 3. Pick next move
This is where most loops drift. The rule "exactly one concrete action" is enforced by the self-review gates: if the agent can't write a one-sentence "next planned action", the loop is broken.

### 4. Execute
Sub-agent dispatch happens here. See `SKILL.md` "Subagent dispatch within the loop" for the rules. Headline: one sub-agent per move; declare a token ceiling; kill at 2× the ceiling.

### 5. Cleanup
Often skipped, often the cause of "why did the next iteration fail mysteriously". Process leaks, port collisions, file locks, leftover `node_modules` mutations.

### 6. Verify
Even "trivial" iterations get verified. The cost of one extra verify is small; the cost of declaring success on a non-green build is the whole run.

### 7. Commit
Per-iteration commits are what make `git reset --hard HEAD~1` a well-defined rollback. Without this, "rollback the last change" means "re-implement reverse-engineering the last 14 file edits."

### 8. Log
Two writes per iteration: overwrite the rolling block, append the immutable history entry. Both go to the same file.

### 9. Step back
3 zero-delta iterations is the trigger. The expert lens panel (in `decision-discipline.md`) forces structured reflection rather than "let me try one more thing."
