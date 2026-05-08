# autonomous-prototype-build

A Claude Code skill for the moment when you want the agent to keep working — measure, decide, execute, verify — until the contract passes or the budget runs out.

## Why this exists

I shipped a 34/34-green app with an off-screen window once. Every test was passing. The user couldn't see anything. That's the whole skill in one anecdote: structural correctness is not user correctness, and an agent that doesn't know the difference will hand you a clean test report on top of nothing.

This skill is the discipline I wish I'd had that day.

## What it does

You hand the agent seven inputs:

- A **contract** — a command that exits 0 when the work is done.
- A **user-path command** — what a real user would actually do, automated.
- A **wall-clock budget** — say, four hours.
- A **token budget** — because wall-clock alone has cost me a few thousand dollars twice.
- A **status file path** — somewhere in `/tmp` you can `tail -f`.
- **Forbidden actions** — things to escalate before doing.
- **Hard-blocker rules** — what should force an early stop.

The agent runs `measure → decide → execute → verify` in a loop until one of: success, a hard architectural blocker only you can decide, wall-clock or token budget exhaustion, or catastrophic regression. It writes a status file you can read from another terminal at any time. It does not ask for mid-loop confirmations. Unattended execution is the whole point.

## When to use it

When the contract is binary and testable, and you'd rather get "tried hard for six hours, here's the diagnostic" than "asked twelve questions over six hours and the work is half-done."

When you've got a flaky integration test that's been bugging you for a week.

When the brainstorming and planning are already done, and what's left is grinding.

## When not to use it

- The goal is taste-based ("make this nicer").
- The deliverable involves irreversible production actions — deploys to prod, destructive DB operations, sending email to real clients.
- You don't actually have a binary contract yet. In that case the right next step is brainstorming, not delivery.

## Install

Skills auto-load from `~/.claude/skills/` (or from `.claude/skills/` inside a project). To install globally:

```bash
git clone https://github.com/mkupermann/autonomous-prototype-build.git \
  ~/.claude/skills/autonomous-prototype-build
```

Or scoped to a single project:

```bash
git clone https://github.com/mkupermann/autonomous-prototype-build.git \
  .claude/skills/autonomous-prototype-build
```

To trigger, say one of: *"autonomous build"*, *"ship until it works"*, *"no breaks until working"*, *"non-stop until done"*. German triggers work too — see `SKILL.md`.

## Usage

The kickoff message looks like this:

```
Make tests/test_parser.py pass.

  contract     = "uv run pytest tests/test_parser.py -q exits 0"
  wall_clock   = "90 minutes"
  token_budget = "2M input + 500k output"
  status_file  = "/tmp/parser_build.md"
  forbidden    = ["git push", "modify pyproject.toml without ack"]
  blockers     = ["3 iterations with no progress"]
```

Two worked examples — one for a web app with a Playwright contract, one for a CLI with a pytest contract — are in `examples/`. The full detail is in `SKILL.md`.

## What's in this repo

```
.
├── SKILL.md                          ~300 lines — the agent reads this
├── README.md                         you are here
├── LICENSE                           MIT
├── references/
│   ├── decision-discipline.md        the eight rules + step-back panel
│   ├── user-path-verification.md     tooling matrix per stack
│   ├── status-file-template.md       the full status file format
│   └── loop-pseudocode.md            annotated loop with notes per step
└── examples/
    ├── invocation-web.md             web app + Playwright contract
    └── invocation-cli.md             CLI / library + pytest contract
```

## What this skill won't do

It won't redefine the contract for you mid-loop. If the contract turns out to be wrong, that's a hard architectural blocker; the agent escalates and stops. A wrong contract gives you the wrong delivery, and the skill won't paper over that.

It won't start without a token budget. Wall-clock alone is not a real cap on cost. The skill refuses to begin without a token ceiling and logs cumulative tokens every iteration so you can watch the spend.

It won't enforce `forbidden_actions` at the OS level. The agent treats the list as a soft pre-check inside the loop. If you need hard enforcement, wire it up as a hook in `.claude/settings.json` — that's a companion piece, not part of this spec.

## What's missing, honestly

**Measured success-rate data.** I don't have it yet. If you adopt this and instrument median tokens, p90 wall-clock, and success rate across runs, send me the numbers and I'll cite them here.

**A pre-tool hook for forbidden-actions enforcement.** Useful to pair with this skill; not in scope for the spec itself.

**Failure-mode case studies.** I want one annotated postmortem of a stuck-streak that the agent rode for too long, and one of a contract that turned out to be wrong. I haven't sanitised either for public yet.

## Provenance

This skill went through nine parallel stakeholder reviews before going public — a VP of AI Engineering, a FinOps lead, an engineering manager, a senior platform engineer, a skill-marketplace curator, a mid-level developer reading it cold, a skeptical OSS maintainer, an executive coach, and an Anthropic-skill-author lens. They flagged: a missing token budget (added), a persona framing that leaned on borrowed authority (cut — the rules are the rules), a single SKILL.md that was too long (split into `references/`), no 30-second pitch up front (added), and a project-specific invocation example readers couldn't follow (replaced with generic web and CLI examples). The synthesis is in the commit history.

## License

MIT. See `LICENSE`.

## Author

[Michael Kupermann](https://github.com/mkupermann). Issues and PRs welcome — particularly any that shorten the files further or add a generic example for a stack that isn't web or CLI.
