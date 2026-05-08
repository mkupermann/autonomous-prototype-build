# Example invocation — web app

A typical kickoff for a web deliverable. The user has a failing Playwright test for a checkout flow and wants the agent to keep working until both the unit tests and the user-path test pass.

## What the user types

```
Make the checkout flow pass.

  contract     = "npm test -- checkout exits 0 AND npx playwright test e2e/checkout.spec.ts exits 0"
  wall_clock   = "4 hours"
  token_budget = "5M input + 1M output"
  status_file  = "/tmp/checkout_build.md"
  forbidden    = ["git push", "rm -rf node_modules", "modify src/payments/* without explicit ack"]
  blockers     = ["3 iterations with no progress on either test", "main test suite drops by >2"]

Don't ask me anything mid-loop unless the contract turns out to be wrong.
Status to /tmp/checkout_build.md. I'll tail it.
```

## What the agent does

1. Reads `~/.claude/skills/autonomous-prototype-build/SKILL.md`.
2. Extracts the seven inputs above.
3. Runs **pre-flight**:
   - `git status --porcelain` (must be empty)
   - 3-run determinism check on both verifying commands
   - captures baseline test count: `npm test -- --listTests | wc -l`
   - `lsof -iTCP:3000` (the dev server port the e2e test will use)
   - `df -h .`
4. Writes the inputs + pre-flight results to the status file.
5. Enters the loop.

## What the status file looks like at hour 2

```markdown
# Autonomous build — checkout flow — started 2026-05-08T10:14

## Current state — iteration 17 — last updated 2026-05-08T12:09
- Elapsed: 1:55 / 4:00       Tokens: 1.8M / 6.0M
- Last delta: +1 unit test passing (3/4 → 4/4); e2e still red on "Place order" button
- Stuck-streak: 0
- Last move: Updated `src/cart/total.ts` to handle empty discount code branch
- Current hypothesis: e2e button-click handler is firing before the form validation finishes — race condition on disabled state
- Next planned action: Add `await expect(page.getByRole('button', { name: 'Place order' })).toBeEnabled()` before the click in the spec, then trace where the button gets disabled
- Last commit: a7f3b21
- Forbidden-action attempts: 0

## Inputs
- Acceptance contract: npm test -- checkout exits 0 AND npx playwright test e2e/checkout.spec.ts exits 0
- ...
```

## What the agent reports back at the end

One message:

> Done. Final verdict: SUCCESS. Both contracts green; independent re-run agrees.
> - Total iterations: 23
> - Wall-clock: 2:41 of 4:00
> - Tokens: 2.4M of 6.0M
> - Diff: 4 files, +47/-12 lines
> - Detail: `/tmp/checkout_build.md.success.md`
> - Notable: the bug was a race in `src/cart/validate.ts` where async validation completed after the disabled state was lifted. Fix is at commit a91c3d7.

If it had hit the wall-clock or token budget, the report would be the same shape but `TIMEOUT` with the closest measurements + the next 2-3 actions to take with more budget.
