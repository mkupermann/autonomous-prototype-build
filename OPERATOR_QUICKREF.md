# Operator quickref — autonomous-prototype-build

The 30-line version of `SKILL.md`. Read this first; read the full SKILL only
when something below is unclear.

## When to invoke this skill

Say one of: *"run until green"*, *"build the prototype until it works"*,
*"lauf alleine durch"*. The skill takes over and reports back at one of five
stop conditions.

## Required inputs (nine fields)

```
CONTRACT          uv run pytest tests/test_X.py exits 0
USERPATH          npx playwright test e2e/ ; <none> for pure-CLI work
WALL_CLOCK        4h
TOKEN_BUDGET      5M in + 1M out   (or $25 USD)
STATUS_FILE       /tmp/build_status.md
FORBIDDEN         git push; edit src/auth/*.py
HARD_BLOCKERS     3 zero-delta iters; main suite drops > 2
MCP_REQUIRED      postgres github                 # space-separated
SUBAGENT_SAFE     true | false
```

A weak or goal-shaped CONTRACT is rejected at pre-flight. Use
`brainstorming` + `writing-plans` to lock the contract first.

## Pre-flight cheat sheet

```bash
export CONTRACT='uv run pytest tests/foo.py exits 0'
export WALL_CLOCK='4h' TOKEN_BUDGET='5M in + 1M out'
export STATUS_FILE='/tmp/build_status.md'
export MCP_REQUIRED='postgres' SUBAGENT_SAFE='true'

bash scripts/preflight.sh
# → emits RUN_ID and writes the status file header on success
# → exits non-zero with a clear reason on any gate failure
```

The pre-flight runs every V2 gate: workspace-clean, weak-contract refuse,
concurrency lock, run-id hash, determinism (10 runs under per-run timeout),
negative control (`scripts/neg-control.sh`), subagent write-probe, MCP
availability, disk free.

## Five stop conditions

```
1. SUCCESS         contracts green + independent re-run + neg-control still rejects
2. HARD BLOCKER    only you can decide; agent escalates with options
3. TIMEOUT         wall-clock OR token budget exhausted
4. ROLLBACK        catastrophic regression, last change reverted
5. RESUME          prior status file with matching RUN_ID found; pick up at last iter-N commit
```

## Iron rules (the rest are in `references/decision-discipline.md`)

1. No claim of progress without an exit code.
2. Never trust a subagent's counts. Parent re-runs the verifier.
3. The verifier may be *amended* (logged loudly) but the goal may not drift.
4. Same fix twice = wrong hypothesis. Pick a different attack.
5. After SUCCESS at < 30% of budget, flag the contract as possibly too narrow.

## Files in this skill

```
SKILL.md                          full procedure (reference)
OPERATOR_QUICKREF.md              you are here
scripts/preflight.sh              runnable pre-flight gate
scripts/neg-control.sh            silent-pass guard ([F7])
scripts/compute-run-id.sh         resume hash
references/v2-changelog.md        provenance: every V2 guardrail
references/loop-pseudocode.md     annotated loop
references/decision-discipline.md full rule set
references/status-file-template.md status-file template
references/user-path-verification.md UI verification tooling matrix
examples/invocation-cli.md        CLI/library example
examples/invocation-web.md        web-app example
archive/SKILL.v0.2.2.md           pre-V2 version, preserved
```

## If something looks off

- Pre-flight fails on "VERIFIER PASSED A BROKEN STATE" → your test suite has
  a silent-pass path. Find it before starting (look for `if precondition_unmet:
  assert True` or any test that exits 0 without running its real assertion).
- Pre-flight skips the subagent write-probe with a `[warn]` → export
  `SUBAGENT_PROBE_CMD='<dispatcher> echo 1 > $PROBE'` for your harness, or
  set `SUBAGENT_SAFE=false` if the loop will not dispatch subagents.
- MCP check is skipped because `claude` is not on PATH → you're running
  pre-flight outside a Claude Code session; either accept the skip and verify
  MCP manually, or unset `MCP_REQUIRED`.
