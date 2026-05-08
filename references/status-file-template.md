# Status file template (full)

Append-only Markdown with a rolling `## Current state` block at the top, overwritten every iteration. The point: a manager skimming the file at hour 5 of a 6-hour run sees one block to triage, not 47 iterations to scroll.

## Template

```markdown
# Autonomous build — <task name> — started <ISO datetime>

## Current state — iteration <N> — last updated <ISO>
- Elapsed: <h:mm> / <wall_clock_budget>
- Tokens: <cumulative> / <token_budget>
- Last delta: <signed metric>      Stuck-streak: <n>
- Last move: <one sentence>
- Current hypothesis: <one sentence>
- Next planned action: <one sentence>
- Last commit: <sha>
- Forbidden-action attempts: <n>

## Inputs
- Acceptance contract: <verifying command + threshold>
- User-path verification: <command>
- Wall-clock budget: <duration>
- Token budget: <input + output cap, or USD cap>
- Status file: <this file>
- Forbidden actions: <list>
- Hard-blocker rules: <list>

## Pre-flight
- Workspace clean: <yes / acked dirty>
- Baseline commit: <sha>
- Verifier flake check: <pass: 3/3 deterministic>
- Baseline test count: <n>
- Disk free: <GB>
- Port checks: <list of ports + status>

## Initial measurement
- <metric name>: <value>  (target: <target>)

---

## Iteration 1 — elapsed <h:mm> — tokens <n>
- Move: <one-sentence concrete action>
- Files touched: <list or git diff stat>
- Measurement before: <metric=value>
- Measurement after: <metric=value>
- Delta: <signed number with unit>
- Commit: <sha or "rolled back">
- Next planned action: <one sentence>
- Now known: <one sentence — fact added to working memory>
- Still unknown: <one sentence>

## Iteration 2 — elapsed <h:mm> — tokens <n>
...

---

## Step-back analysis #1 — elapsed <h:mm>  (after 3 zero-delta iterations)
- Original attack: <description>
- Why it stalled: <hypothesis based on data>
- Lens consultation:
  - Coding discipline: <what it said>
  - TDD: <what it said>
  - Systematic debugger: <what it said>
  - Empiricist: <what it said>
  - Skeptical reviewer: <what it said>
  - Safety operator: <what it said>
- New attack: <different vector>
- Returning to iteration loop.

---

## STOP — <reason: success | escalation | timeout | token_timeout | rollback>
- Final measurement: <metric=value>
- Time elapsed: <duration>
- Tokens consumed: <n>
- Iterations: <count>
- See <status_file>.<reason>.md for the detail report.
```

## Update rules

- The `## Current state` block is **overwritten** every iteration. Use Edit, not append.
- The `## Iteration N` blocks are **append-only**. Once written, never edited.
- Step-back analyses are **append-only**, written between iteration blocks at the moment they trigger.
- When the loop stops, the `## STOP` block is appended and a separate detail file is written: `<status_file>.<reason>.md`.

## Why this format

A manager joining the run at hour 5 needs to triage in 30 seconds:
- Are we close? (delta + gap-to-target)
- Are we stuck? (stuck-streak)
- Are we burning money? (tokens / budget)
- What's the agent doing right now? (last move + next action)
- Did anything dangerous happen? (forbidden-action attempts)

All five answers are in the rolling block. The append-only history is for postmortem, not triage.
