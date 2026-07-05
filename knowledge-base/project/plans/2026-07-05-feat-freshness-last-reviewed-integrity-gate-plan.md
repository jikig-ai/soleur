---
title: "feat: freshness last_reviewed integrity gate"
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
tracks_issue: 5999
epic: 6003
branch: feat-freshness-convention
pr: 6017
last_updated: 2026-07-05
review_cadence: quarterly
---

# feat: Freshness `last_reviewed` Integrity Gate

**Issue:** #5999 · **Epic:** #6003 · **PR:** #6017 · **Brainstorm:** `knowledge-base/project/brainstorms/2026-07-04-freshness-convention-brainstorm.md` · **Spec:** `knowledge-base/project/specs/feat-freshness-convention/spec.md`

## Overview

Make `last_reviewed` a **trustworthy** freshness signal. Soleur already has the convention (`last_reviewed` + `review_cadence` on 40 KB files) and the surfacing (`review-reminder.yml` + Inngest crons file overdue-review issues). What's missing — and the entire value — is the `last_updated`-vs-`last_reviewed` **integrity split**: nothing stops an automated flow from bumping `last_reviewed`, and one Soleur skill (brainstorm Phase 0.25) does exactly that on `roadmap.md`. A staleness signal computed from an unguarded `last_reviewed` is false confidence.

v1 ships: (1) a commit-time **integrity gate** blocking automated `last_reviewed` bumps across all tracked `*.md`; (2) a `last_updated`-only bump helper; (3) the Phase 0.25 self-violation fix; (4) the always-loaded rule layer (`AGENTS.core.md`) brought under the review clock — funded by teaching the budget lint to strip frontmatter (matching the loader), not by trimming a hard rule; (5) an ADR.

**Premise Validation:** All premises verified against `main`/worktree at plan time. Confirmed: convention on 40 files (`git grep last_reviewed` = 40); `review-reminder.yml:151` scans `find knowledge-base` **only** (repo-root `AGENTS.core.md` is outside its scope); the **only** automated `last_reviewed` *writer* is brainstorm `SKILL.md:121` (all three crons read-only — `cron-strategy-review.ts` has no `writeFile` on the field); precedent gate `follow-through-directive-gate.sh` is a `PreToolUse(Bash)` hook registered in `.claude/settings.json:91`; `session-rules-loader.sh:135,158` concatenates sidecars and injects `AGENTS.core.md` (strippable), while `AGENTS.md` loads via CLAUDE.md `@AGENTS.md` harness @-import (NOT strippable — so frontmatter goes on `AGENTS.core.md` only); `lint-agents-rule-budget.py:59` measures raw `read_bytes()`, B_ALWAYS = 22976/23000 (24 bytes headroom); no prior freshness ADR; highest ordinal ADR-084 → provisional **ADR-085**; gray-matter date-coercion learning at `2026-05-25-tr9-pr6-gray-matter-yaml11-date-coercion-trap.md`; `frontmatter_lib.py` provides `parse_frontmatter`/`serialize_frontmatter`/`format_field`.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| FR4: add fields to `AGENTS.md` **and** `AGENTS.core.md` | `AGENTS.md` injects raw via harness `@`-import (unstrippable → YAML would leak into every session); only `AGENTS.core.md` is loader-injected | FR4 narrowed to **`AGENTS.core.md` only**; `AGENTS.md` index stays frontmatter-free (its sidecars carry the clock) |
| Spec assumes headroom to add frontmatter | B_ALWAYS headroom = **24 bytes**; frontmatter ~110 B | Fund via **lint frontmatter-strip** (measure loaded bytes, matching loader), not a hard-rule trim (operator-authorized cost, realized cleaner) |
| FR6: reuse existing cron (implies it already scans the rule layer) | `review-reminder.yml` scans `find knowledge-base` only | Extend that `find` to also emit repo-root `AGENTS.core.md`; handle the non-`knowledge-base/` slug |

## Architecture Decision (ADR/C4)

### ADR
Create **ADR-085** `freshness-last-reviewed-integrity-gate` via `/soleur:architecture` (in-scope task, Phase 7). Records: (a) the `last_updated`-vs-`last_reviewed` boundary + why the split is load-bearing; (b) the integrity-enforcement mechanism (commit-trailer gate, default-deny on automated bumps); (c) the decision to **reuse the existing review-reminder cron + single parser** rather than build a new scanner (avoids the multi-consumer drift `cq-union-widening-grep` fights); (d) the loader/lint frontmatter-strip coupling. Provisional ordinal — re-verify against `origin/main` at ship (082/083/084 present).

### C4 views
**No C4 impact.** Checked all three model files (`model.c4`, `views.c4`, `spec.c4`). The change adds no external human actor (the reviewing operator is the already-modeled user), no external system, no container/datastore (`platform.plugin.kb`, `platform.plugin.skills` already modeled at `model.c4:67-89`), and no access-relationship change. A dev-workflow metadata convention on repo files is not a system-topology element. "None" is cited against the enumeration, per the completeness mandate.

## Implementation Phases

Phase order is **contract-before-consumer**: the frontmatter-strip (Phase 3) MUST land before `AGENTS.core.md` frontmatter (Phase 4), else the budget lint goes RED in CI; the bump helper (Phase 1) is the contract the reconcile fix (Phase 5) consumes.

### Phase 0 — Preconditions (re-verify at /work start)
- Re-run B_ALWAYS: `a=$(wc -c<AGENTS.md); c=$(wc -c<AGENTS.core.md); echo $((a+c))` (expect ~22976; sibling PRs may shift it).
- Confirm `follow-through-directive-gate.sh` shape + `.claude/hooks/lib/incidents.sh` `emit_incident`/`strip_command_bodies` API (mirror target).
- Re-grep automated `last_reviewed` writers: `grep -rnE "last_reviewed" scripts/ plugins/soleur/skills/*/scripts/ apps/web-platform/server/inngest/` — confirm Phase 0.25 is still the sole writer.

### Phase 1 — `last_updated`-only bump helper (the contract)
- **Create** `scripts/bump-frontmatter-updated.py` reusing `scripts/frontmatter_lib.py` (`parse_frontmatter` → set `last_updated` to today (ISO date) → `serialize_frontmatter`). It exposes **no** `last_reviewed` setter — structurally incapable (FR2). CLI: `python3 scripts/bump-frontmatter-updated.py <file>...`.
- **Create** `scripts/test_bump_frontmatter_updated.py`: asserts `last_updated` written, `last_reviewed` untouched, missing-frontmatter handled.

### Phase 2 — Reviewed-integrity gate
- **Create** `.claude/hooks/context-reviewed-gate.sh` — `PreToolUse(Bash)` hook mirroring `follow-through-directive-gate.sh`:
  - Fire only when the command is a `git commit` (word-boundary match on `$SCAN` via `strip_command_bodies`).
  - Compute the staged delta of `last_reviewed:` lines: `git -C "$WORK_DIR" diff --cached -U0 -- '*.md' | grep -E '^\+.*last_reviewed:'` (added/changed reviewed lines).
  - If any exist, require a `Context-Reviewed: <path|all>` trailer in the commit message (`-m`/`-F`/heredoc body). Present → allow. Absent → **deny + `emit_incident`** (FR1).
  - **Fail-open (exit 0):** not a `git commit`; no staged `*.md`; no `last_reviewed:` delta; unparseable input; missing `.cwd`.
- **Create** `.claude/hooks/context-reviewed-gate.test.sh` (TR1) covering: automated bump (no trailer) → deny; `Context-Reviewed:` trailer → allow; `last_updated`-only change → allow; non-commit command → fail-open; malformed input → fail-open.
- **Edit** `.claude/settings.json` — register the hook under `PreToolUse`→`Bash` (mirror `:91`).

### Phase 3 — Frontmatter-strip (loader + lint) — enables Phase 4
- **Edit** `.claude/hooks/session-rules-loader.sh` — in the sidecar concatenation (≈`128-158`), strip a leading `---\n…\n---\n` block from each sidecar before appending. Preserve the fail-closed missing-file path and the ≤200-byte header contract (TR3). Do NOT alter `TOTAL_RULES` (`:177` greps `^- .*[id:` — frontmatter lines don't match, unaffected).
- **Edit** `scripts/lint-agents-rule-budget.py` — strip a leading frontmatter block from **`AGENTS.core.md`** before the byte count (`:59-60`), so B_ALWAYS measures *loaded* bytes (matches the loader). Leave `AGENTS.md` counted whole (it injects raw). Document the coupling in a comment.
- **Edit** `scripts/lint-agents-rule-budget.test.sh` — assert frontmatter on `AGENTS.core.md` does not count toward B_ALWAYS; assert `AGENTS.md` frontmatter (if ever present) still would.
- **Add** a loader test (in the loader's existing `.test.sh` if present, else a new assertion): injected sidecar context must NOT contain `last_reviewed:` / `review_cadence:` (FR5 / AC3).

### Phase 4 — Bring `AGENTS.core.md` under the clock
- **Edit** `AGENTS.core.md` — add frontmatter: `last_reviewed: 2026-07-05`, `review_cadence: monthly` (hard rules churn faster than quarterly), `owner: <operator>`. (Now budget-safe: Phase 3 lint-strip excludes it from B_ALWAYS.)

### Phase 5 — Fix the Phase 0.25 self-violation
- **Edit** `plugins/soleur/skills/brainstorm/SKILL.md:121` — change "Update `last_updated` **and `last_reviewed`**" → "Update `last_updated` **only** (a reconcile is an automated write; never bump `last_reviewed` — see ADR-085). Use `scripts/bump-frontmatter-updated.py`." (FR3)
- Grep the roadmap-reconcile module + any sibling skill prose for other `last_reviewed` auto-bump instructions; fix in kind.

### Phase 6 — Extend the overdue-review scan
- **Edit** `.github/workflows/review-reminder.yml` — extend the `find knowledge-base` feed (`:151`) to also emit repo-root `AGENTS.core.md`; fix the slug builder (`:97` `slug="${file#knowledge-base/}"`) to produce a sensible title for the non-`knowledge-base/` path. Do NOT add a second scanner (reuse — CTO/`cq-union-widening-grep`).

### Phase 7 — ADR + C4 note
- **Create** `knowledge-base/engineering/architecture/decisions/ADR-085-freshness-last-reviewed-integrity-gate.md` via `/soleur:architecture` (content per §Architecture Decision). Add the "no C4 impact" enumeration note to the ADR body.

### Phase 8 — Verify
- Run `bun test`/`vitest` per `package.json scripts.test`; run each new `.test.sh`; run the two lints (`lint-agents-rule-budget.py`, rule-ids) to confirm B_ALWAYS OK; run through the Acceptance Criteria below.

## Files to Create
- `.claude/hooks/context-reviewed-gate.sh`
- `.claude/hooks/context-reviewed-gate.test.sh`
- `scripts/bump-frontmatter-updated.py`
- `scripts/test_bump_frontmatter_updated.py`
- `knowledge-base/engineering/architecture/decisions/ADR-085-freshness-last-reviewed-integrity-gate.md`

## Files to Edit
- `.claude/settings.json` — register the gate hook
- `.claude/hooks/session-rules-loader.sh` — strip sidecar frontmatter before injection
- `scripts/lint-agents-rule-budget.py` + `.test.sh` — strip `AGENTS.core.md` frontmatter before byte count
- `AGENTS.core.md` — add freshness frontmatter
- `plugins/soleur/skills/brainstorm/SKILL.md` — Phase 0.25 step 4 (`:121`): `last_updated`-only
- `.github/workflows/review-reminder.yml` — extend scan to repo-root `AGENTS.core.md`

## Open Code-Review Overlap
None. (`gh issue list --label code-review --state open` cross-checked against the Files lists — no open scope-out names these paths.)

## User-Brand Impact
- **If this lands broken, the user experiences:** the reviewed-clock signal keeps reading "fresh" while a hard rule silently ages, so an agent trusts a stale rule and makes a wrong high-blast-radius decision.
- **If this leaks / mis-fires:** a false-`last_reviewed` (automated bump slipping past the gate) exposes the operator to acting on stale governance — a single-user trust breach.
- **Brand-survival threshold:** single-user incident (auto, per #5175).

CPO sign-off: satisfied by operator-in-loop — this is internal dev-tooling with no user-facing surface; the operator drove every scope decision in the brainstorm + this plan. `user-impact-reviewer` will run at PR review per the review skill's conditional-agent block.

## Observability
```yaml
liveness_signal:
  what: review-reminder cron files an overdue-review issue when a constitutional file passes its cadence
  cadence: existing review-reminder.yml schedule
  alert_target: GitHub issue (existing channel)
  configured_in: .github/workflows/review-reminder.yml
error_reporting:
  destination: emit_incident (.claude/hooks/lib/incidents.sh) on gate deny + on fail-open error path
  fail_loud: true (deny prints reason to stderr; incident row recorded)
failure_modes:
  - mode: gate false-blocks a legitimate human review bump lacking the trailer
    detection: deny message names the required Context-Reviewed trailer
    alert_route: stderr (operator sees it at commit time)
  - mode: gate fails open on parse error (never bricks commits)
    detection: emit_incident on the error branch
    alert_route: incidents ledger
logs:
  where: incidents ledger (.claude/hooks/lib/incidents.sh) + commit-time stderr
  retention: per existing incidents convention
discoverability_test:
  command: printf '{"tool_input":{"command":"git commit -m x"},"cwd":"'"$PWD"'"}' | .claude/hooks/context-reviewed-gate.sh; echo $?
  expected_output: exit 0 fail-open with no staged last_reviewed delta; deny (non-zero) when a staged last_reviewed change lacks the trailer
```

## Acceptance Criteria

### Pre-merge (PR)
- **AC1.** With a `last_reviewed:` change staged and no trailer, `context-reviewed-gate.sh` denies (test proves it).
- **AC2.** `python3 scripts/bump-frontmatter-updated.py <fixture>` changes `last_updated` and leaves `last_reviewed` byte-identical (test proves it).
- **AC3.** Post-loader injected context for a frontmatter-bearing `AGENTS.core.md` contains the rule text but NOT `last_reviewed:`/`review_cadence:` (loader test).
- **AC4.** `lint-agents-rule-budget.py` passes with `AGENTS.core.md` frontmatter present (B_ALWAYS excludes it); `.test.sh` asserts the exclusion.
- **AC5.** `brainstorm/SKILL.md:121` no longer instructs bumping `last_reviewed`; `grep -n 'last_reviewed' plugins/soleur/skills/brainstorm/SKILL.md` shows no auto-bump instruction.
- **AC6.** `review-reminder.yml` scan feed includes `AGENTS.core.md` (grep the workflow for the added path; dry-run the `find`+append produces it).
- **AC7.** ADR-085 exists with the mechanism + boundary + reuse rationale + C4-none enumeration.
- **AC8.** Full test suite + `lint-agents-rule-budget.py` + rule-ids lint green.

### Post-merge (operator)
- None. No infra apply, no external state. (Automation-feasibility gate: all steps are code + CI; nothing operator-only.)

## Risks & Sharp Edges
- A plan whose `## User-Brand Impact` is empty/placeholder fails `deepen-plan` Phase 4.6 — this section is filled.
- **Budget coupling:** Phase 3 (lint frontmatter-strip) MUST merge in the same PR as / before Phase 4 (frontmatter). They are one atomic change; never split. The loader-strip and lint-strip enforce the *same* invariant at two layers — keep their frontmatter-detection regex identical.
- **Gate scope:** the gate protects `last_reviewed:` on ALL tracked `*.md`, strengthening the whole 40-file convention — not just the rule layer. Confirm the trailer requirement doesn't trip legitimate multi-file review commits (support `Context-Reviewed: all`).
- **Slug builder:** `review-reminder.yml:97` strips the `knowledge-base/` prefix; the repo-root `AGENTS.core.md` path needs its own slug branch or the issue title degrades.
- Keep the loader frontmatter-strip aligned with the ≤200-byte header contract test (loader `.test.sh` #11) — the strip happens in the sidecar body, not the header.

## Alternative Approaches Considered
| Approach | Verdict | Rationale |
|---|---|---|
| A–F GPA grade surfaced every session | Rejected (NG1/NG2) | Duplicates the working overdue-issue channel; ambient noise operators ignore; wrong surface (statusline is user-global). |
| Separate threshold/registry file | Rejected | Second source of truth that drifts (CTO); reuse in-file `review_cadence` + the one existing scanner. |
| Fund frontmatter via hard-rule body trim | Superseded | Trims real always-loaded rule content for bytes that aren't even loaded (loader strips them); the lint-strip measures loaded bytes correctly instead. |
| Frontmatter on `AGENTS.md` index too | Rejected | Injects raw YAML via harness `@`-import every session (unstrippable). |
