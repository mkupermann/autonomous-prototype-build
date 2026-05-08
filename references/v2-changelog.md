# autonomous-prototype-build V2 — changelog with provenance

Every V2 change is traceable to a finding in `claude_memory` (PostgreSQL DB at `claude_memory`, table `memory_chunks`) or to a directly-observed defect from a real autonomous run. The mapping below is the source-of-truth for "why does V2 do X?"

## Provenance table

| ID | Finding (DB chunk_id or run-trace) | V2 enhancement |
|----|------------------------------------|----------------|
| F1 | SimpleMD run, status file `/tmp/simplemd_autonomous.md` (2026-05-08 00:26–00:38). Agent silently rewrote `plutil -extract` (destructive) and `spctl --assess` (false-rejects) verifier commands mid-loop. V0.2.2 had no protocol for "verifier command is buggy but contract intent is right." | **Verifier-amendment protocol** (new section). Allows command swap iff: reproducible bug, property preserved, non-destructive replacement, loud `## Verifier amendment` block in status file. Otherwise hard blocker. |
| F2 | SimpleMD run, status file. Iteration log appears as 1→3→2→4 because moves were named after kind-of-work, not order-of-completion. | **Monotonic iteration counter rule.** Iteration entries append in strict order. Out-of-order = bug. Status-file template updated. |
| F3 | DB chunk_id 503: *"Subagents dispatched via Agent tool consistently miscount passing tests. Always verify test counts directly with `xcodebuild test ... \| grep 'Test Suite.*passed'` rather than trusting subagent summaries."* | **Trust-but-verify subagents** (new decision rule #9). Parent re-runs the verifying command and parses raw output. Subagent self-reported counts = zero evidence. Codified in loop subagent-dispatch step. |
| F4 | DB chunk_id 8: *"Multi-Agent Pattern: Subagents mit bypassPermissions können trotzdem keine Dateien schreiben wenn die Permission nicht im Projekt-Settings ist."* | **Subagent write-probe in pre-flight.** Sentinel subagent writes a 1-byte file; if it fails, refuse to start. New input field `subagent_safe`. |
| F5 | DB chunk_ids 211, 192, 228, 243: *"API Stream idle timeout"* recurring across long-running skills. | **Run-ID hash + resume protocol.** Status file carries `Run-ID = SHA256(contract+budgets+forbidden+baseline_sha)`. New session resumes from last `iter-N` commit only if run-id matches. |
| F6 | DB chunk_id 455: *"Streamlit-Rewrite-Loop ... WebSocket-Disconnect mid-run löscht alles. Fix: Checkpoint nach jedem Abschnitt."* | Same as F5 — same pattern, different surface. |
| F7 | DB chunk_id 524: *"EQMOD F3b-Test hat silent-pass Bug: `if n_strong_before == 0: persistence_fractions.append(1.0)` — Test kann nie fehlschlagen wenn keine starken Strukturen gebildet wurden."* | **Negative-control check in pre-flight.** Verifier must FAIL on a deliberately-broken state. Re-confirmed at success-time so a contract that drifts to silent-pass mid-run doesn't ship green. |
| F8 | DB chunk_id 525: *"n=3 Seeds ist statistisch zu schwach ... Adversarial Reviewer fordert Validierung auf unseen seed grid (7, 100, 314, 999) ohne per-test Parameter-Retuning."* | **Seed-grid requirement for non-deterministic verifiers.** n=10 baseline (already in V0.2.2) PLUS unseen-seed grid before declaring success. |
| F9 | DB chunk_id 324: *"Architecture audit ... spot-check top claims against real code before writing the plan ... Two audit claims were wrong and caught."* | **Spot-check rule.** Before acting on a subagent's diagnosis (e.g., "the bug is in foo.py:42"), parent reads the actual file/line and confirms. Codified in subagent-dispatch step. |
| F10 | DB chunk_ids 540, 545: *"~/.claude/skills ist ein Symlink ... Skills mit internen Scripts können nicht einfach in Client-Repos verschoben werden — sie hardcoden ~/.claude/skills/<name>/scripts/ Pfade."* | **Path-resolving helpers.** `SKILL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)` rule. No hardcoded `~/.claude/skills/...` in any helper script. |
| F11 | DB chunk_id 440: *"MCP-Server werden beim Session-Start geladen. Nach dem Hinzufügen eines neuen MCP-Servers muss Claude Code neu gestartet werden."* | **MCP availability check in pre-flight.** New required input `mcp_required`. Missing MCP → refuse to start with explicit "add it and restart" instruction. Mid-loop discovery → hard blocker (cannot fix without restart). |
| F12 | DB chunk_ids 110, 125, 130, 140, 143, 192, 211, 228, 267, 299 (and others): AppleScript / external-tool timeouts hanging long-running skills. | **Per-call subprocess timeout cap.** Every external command in pre-flight + loop runs under `timeout`/`gtimeout` with a configurable per-run cap (default 300s). Killed = zero-delta. |
| F13 | DB chunk_id 317: *"Worker stuck-processing bug: `_claim_next` commits `status='processing'` BEFORE extract+embed work starts. ... Fix: stamp `claimed_at = now()` on claim, add startup reaper that resets rows stuck >N seconds."* | **Subagent claim-stamping + reaper.** Parent stamps `claimed_at` when dispatching a subagent. A subagent whose claim is >5× expected duration is killed by the reaper and counted as zero-delta. |
| F14 | DB chunk_id 506: *"Stakeholder-Review-Skill v2 nutzt 9 parallele Persona-Agenten mit binären Verdikten ... v1 hinterließ die Arbitrage beim User (Confirmation-Bias-Problem)."* | **Optional adversarial post-success.** After SUCCESS, optionally invoke `stakeholder-review` (v2) for a binary-verdict gate. Mentioned in "Composition with other skills" + flagged in success report when relevant. |
| F15 | SimpleMD run: 12 minutes used out of 3.5h budget = 5.7% utilization. Extreme undershoot can mask a too-narrow contract that is technically green but practically incomplete. | **Budget-undershoot signal.** Success report appends *"contract may be too narrow — review before relying on this as a delivery signal"* when utilization < 30%. Soft signal, not gate. |

## Behavioral changes summary (one-line each)

- Pre-flight refuses to start if the verifier passes a known-broken state. (F7)
- Pre-flight refuses to start if a needed MCP server isn't loaded. (F11)
- Pre-flight refuses to start if a subagent can't write to the workspace. (F4)
- Every external subprocess runs under a per-call timeout cap. (F12)
- Subagent self-reported counts/claims are never trusted; parent re-verifies. (F3, F9)
- Status file carries a Run-ID; resume only if it matches. (F5, F6)
- Status file iteration counter is monotonic. (F2)
- Helper scripts in this skill resolve their own dir; no `~/.claude/skills/...` hardcoding. (F10)
- Verifier commands may be amended (with logged provenance) but contract intent may not. (F1)
- Success requires negative-control re-confirmation, not just structural+user-path green. (F7)
- Success report flags budget undershoot < 30%. (F15)
- Optional binary-verdict review after success. (F14)
- Subagent dispatches stamp `claimed_at` and have a reaper for stale claims. (F13)
- Non-deterministic verifiers run on n=10 baseline + unseen-seed grid before success. (F8)

## What did NOT change

V2 is a hardening pass, not a redesign. These remain identical to V0.2.2:
- The measure→decide→execute→verify loop shape.
- Decision Rule 5 (config → code → arch → greenfield) ordering.
- Step-back panel and 3-iteration zero-delta trigger.
- Per-iteration commits (incl. zero-delta empty commits).
- Sub-agent context summarisation to ≤2 KB before re-dispatch.
- Catastrophic-regression rollback via `git reset --hard HEAD~1`.
- Concurrency lock (`.claude/autonomous-build.lock`).
- 5-stop-condition hierarchy (success / hard blocker / token timeout / wall-clock / regression).
- User-path verification gate for any UI deliverable.

## Database query that drove this (for re-running the audit)

```sql
-- All issues, blockers, defects, findings relevant to the autonomous loop.
SELECT id, category, confidence, content
FROM memory_chunks
WHERE status = 'active'
  AND (
        category = 'error_solution'
     OR (category IN ('insight','pattern','workflow')
         AND (content ILIKE '%blocker%'
           OR content ILIKE '%fail%'
           OR content ILIKE '%timeout%'
           OR content ILIKE '%verify%'
           OR content ILIKE '%silent%'
           OR content ILIKE '%subagent%'
           OR content ILIKE '%miscount%'
           OR content ILIKE '%regression%'
           OR content ILIKE '%checkpoint%'
           OR content ILIKE '%resume%'
           OR content ILIKE '%symlink%'
           OR content ILIKE '%hardcod%'
           OR content ILIKE '%MCP%'
           OR content ILIKE '%session start%'
           OR content ILIKE '%stuck%'))
       )
  AND confidence >= 0.85
ORDER BY confidence DESC, created_at DESC;
```

Re-run this query periodically; new high-confidence findings should drive a V3 hardening pass on the same provenance discipline.

## Smoke-test patches (post-V2.0.0)

### 2026-05-08 — pre-flight order-of-operations fix
**Caught by:** V2 smoke test on `/tmp/v2-smoke-test-roman/` (Roman numeral converter).
**Symptom:** Pre-flight wrote `.claude/autonomous-build.lock` BEFORE running `git status --porcelain`. If the lock path wasn't already gitignored, the freshly-written lock dirtied the workspace and pre-flight failed on its own footprint.
**Fix:** Re-ordered pre-flight in SKILL.md so workspace-clean check runs before any side effect (lock write, run-id computation, etc.). Added inline note that `.claude/` is conventionally gitignored; if not, the user must add the lock path explicitly.
**Provenance:** F-NEW1 (self-discovered during V2 acceptance test). Not yet a `claude_memory` chunk; will be ingested on next session.
