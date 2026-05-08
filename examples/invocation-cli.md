# Example invocation — CLI / library

A CLI tool with a failing test suite. No UI, so the user-path verification IS the structural test.

## What the user types

```
Make `tests/test_parser.py` pass.

  contract     = "uv run pytest tests/test_parser.py -q exits 0"
  wall_clock   = "90 minutes"
  token_budget = "2M input + 500k output"
  status_file  = "/tmp/parser_build.md"
  forbidden    = ["git push", "modify pyproject.toml dependencies without ack"]
  blockers     = ["3 iterations with no progress on the failing test count"]

No UI — the pytest command is both the structural and user-path gate.
```

## What the agent does

1. Reads `~/.claude/skills/autonomous-prototype-build/SKILL.md`.
2. Extracts the seven inputs (note: user-path = structural here, which is allowed for CLI deliverables).
3. Runs pre-flight:
   - `git status --porcelain` (must be empty)
   - 3-run determinism check on the verifying command
   - captures baseline pass count: `uv run pytest -q --co | wc -l`
   - skips port checks (no dev server)
4. Writes inputs + pre-flight to the status file.
5. Enters the loop.

## What the status file looks like at minute 30

```markdown
# Autonomous build — parser tests — started 2026-05-08T14:00

## Current state — iteration 8 — last updated 2026-05-08T14:30
- Elapsed: 0:30 / 1:30       Tokens: 380k / 2.5M
- Last delta: 7/12 → 9/12 tests passing (+2)
- Stuck-streak: 0
- Last move: Fixed `parse_quoted_string` to handle escaped backslash before quote
- Current hypothesis: remaining 3 failures all involve nested arrays — the array tokenizer state machine has an off-by-one on closing bracket
- Next planned action: Read `parser/array.py` lines 40-90, trace one failing case manually, then write a minimal repro before patching
- Last commit: e04d77f
- Forbidden-action attempts: 0

## Inputs
- Acceptance contract: uv run pytest tests/test_parser.py -q exits 0
- ...

## Iteration 8 — elapsed 0:28 — tokens 360k
- Move: Fixed escaped-backslash branch in parse_quoted_string
- Files touched: parser/string.py (+8 -2)
- Measurement before: 7/12 passing
- Measurement after: 9/12 passing
- Delta: +2 tests
- Commit: e04d77f
- Now known: backslash-quote escapes were the cause of test_strings_with_quotes; they were not the cause of test_nested_array (still failing)
- Still unknown: whether nested-array failures share a root cause or are independent
```

## What the agent reports back at the end

> Done. Final verdict: SUCCESS. 12/12 tests passing; independent re-run agrees.
> - Total iterations: 14
> - Wall-clock: 0:51 of 1:30
> - Tokens: 720k of 2.5M
> - Diff: 3 files, +28/-9 lines
> - Detail: `/tmp/parser_build.md.success.md`
> - Notable: two unrelated bugs (escape handling + array-bracket counter); fixing the second revealed a third (off-by-one on empty arrays), now also fixed.
