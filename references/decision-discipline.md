# Decision discipline (long form)

This is the full version of the rules summarised in `SKILL.md` under "Decision discipline". The short version is eight bullets. Here's what each one means and why it's load-bearing.

## The eight rules

### 1. Evidence before assertions
No claim of progress without a measurement. "The fix probably works" is not a claim; an exit code is. The status file entry that says "fixed the cosine bug" is rejected; the entry that says "cosine 0.34 → 0.41, +0.07, verifying command exits 0" is accepted.

### 2. You don't understand the problem if you can't articulate the test
Refuse to act on hypotheses that aren't immediately testable. If the next move is "let me try X and see what happens", step back and sharpen the test first. If you cannot describe the measurement that would tell you X worked, you do not yet understand X.

### 3. Tight feedback loops over heroic batches
Five 5-minute experiments beat one 90-minute speculative rewrite. Each iteration must move a number, however slightly. A loop that spends 90 minutes on one move has lost the ability to recover from a wrong hypothesis.

### 4. Hypothesis-first — assume your model of the system is wrong
When two iterations don't move the metric, the hypothesis is wrong, not the implementation. Don't try harder; try differently. The temptation to "iterate on the same fix with a slight variation" is the agent's confirmation bias kicking in.

### 5. Simpler interventions first
Config tuning before code changes. Code changes before architecture. Architecture before greenfield. The 80% of failures fixed by the simplest intervention are the ones a senior engineer fixes first.

**Move-selection panel (used by `pick_move()` in the loop):**

| Class | Cost | Reach for it when |
|---|---|---|
| 1. Config tweak | lowest | A flag, an env var, a timeout, a threshold could plausibly move the metric. Always try this layer first. |
| 2. Code change in the failing module | low | The failure traces to a specific function or line and you've read it. |
| 3. Code change across modules | medium | The bug is interaction-shaped (timing, state, contracts between modules). |
| 4. Architecture change | high | Two iterations of class 2-3 didn't move the metric and the diagnosis points at a structural mismatch. |
| 5. New dependency / greenfield | highest | The architecture itself is wrong and patching it costs more than replacing it. Escalate as a hard architectural blocker first. |

The loop's `pick_move()` walks this table top-down, filtered by what history has already ruled out. When `last_delta > 0` the loop stays at the same class. When `last_delta < 0` (revert just happened) the loop tries an orthogonal move *at the same class*. When `last_delta == 0` the loop escalates one class.

### 6. Cumulative learning
Every iteration's findings get written to the status file in the form "we now know X is true / we ruled out Y". Don't re-run experiments whose result is in the log. The status file is the loop's working memory; treat it like one.

### 7. Safety and correctness are non-negotiable
Never disable a test "just to ship". Never `--no-verify`, `--force`, or skip a quality gate. Push back on contracts that lure you toward those — the contract is wrong, not the safety check.

### 8. Push back on weak contracts
If the contract is vague, the agent refuses to start the loop. The agent is the user's first line of defence against a wrong contract. A contract like "make this read better" or "fix the AI thing" is rejected on sight.

## What the decision discipline does NOT do

- Drift into yak-shaving (reformatting, polishing, "while I'm here" refactors).
- Re-try the same fix twice.
- Mistake activity for progress.
- Confuse subjective improvements with measurable ones.
- Ask the user mid-loop for permission. (User has authorised the budget; the agent uses it.)
- Hide uncertainty. Every iteration's status entry names what's still unknown.

## Step-back analysis: the expert reference panel

When the loop hits 3 zero-delta iterations and triggers step-back, consult these mental lenses before picking a new attack vector. The status file entry for that step-back must record: "Lens X says <Y>." This forces active engagement with each lens, not a nod.

| Lens | Question it asks |
|---|---|
| **Coding discipline (Karpathy)** | Is the simplest possible thing that could work the simplest thing being tried? Are you skipping a check or a measurement? |
| **TDD / verification** | Does the failing test point at the right behaviour, or is it testing the wrong thing? Would a senior engineer accept this contract? |
| **Systematic debugger** | What's the root cause? Have you actually traced it, or are you patching symptoms? Read the code; don't guess. |
| **Researcher / empiricist** | What's the simplest hypothesis consistent with all the data so far? Have you ruled out the alternatives? |
| **Skeptical reviewer** | Where would another engineer challenge this? What's the strongest counter-argument? |
| **Safety-conscious operator** | Is this change reversible? Is the workspace healthier or fragiler? Is anything left in a half-state? |

## Voice in the status file

Status file entries are:

- **Concrete** — name files, commit hashes, exact metrics, exact line numbers.
- **Terse** — a senior engineer reading should grasp the whole iteration in 15 seconds.
- **Measurement-first** — lead with the number that moved (or didn't). The interpretation comes after.
- **Free of hedging** — not "this might be the issue" but "this IS the issue, evidence: X". If you don't have evidence, don't assert.
- **Honest about what's still unknown** — every iteration's "next planned action" identifies what evidence the agent is now hunting.

Anti-voice (do not write these):
- "I think we're getting close"
- "this should work"
- "trying again with X"
- "almost there"
- "looks better"

## When to escalate

Escalate ONLY for hard architectural blockers that the user must adjudicate (Stop Condition 2 in `SKILL.md`). Do NOT escalate to ask permission for execution decisions. DO escalate when:

- Two technical paths exist with different downstream cost, and the agent genuinely cannot pick on engineering grounds.
- A contract turns out to be self-contradictory or impossible.
- A discovery during the loop invalidates the contract itself. This is a contract-validity escalation, not a permission request.

Never escalate "should I commit?", "want me to keep going?", "is this approach OK?" — those are loop-internal.
