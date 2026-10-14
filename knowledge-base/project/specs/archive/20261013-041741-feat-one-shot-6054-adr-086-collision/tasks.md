---
title: "Tasks — resolve 3-way ADR-086 ordinal collision"
plan: knowledge-base/project/plans/2026-07-06-chore-resolve-adr-086-ordinal-collision-plan.md
issue: 6054
lane: single-domain
---

# Tasks — chore(arch): resolve 3-way ADR-086 ordinal collision

Decision (locked): **A `declarative-skill-context-injection` keeps ADR-086**; **B `fail-closed-redaction-engine-contract` → ADR-093**; **C `freshness-last-reviewed-source-fix-and-audit-tripwire` → ADR-094**. Next-free ordinals verified: 086–092 taken → 093/094 free.

> **Ship-time amendment:** B (redaction) actually landed at **ADR-095** — a sibling `ADR-093-sdk-plugin-source-...` claimed 093 on `main` mid-pipeline (pulled in by a Phase 7 BEHIND auto-sync), so the `/ship` ADR-Ordinal Collision Gate bumped redaction 093 → 095. C (freshness) stayed at 094. The "093/094 free" line above was true at /work-start (Task 0.1), pre-sibling.

**DO NOT** run a repo-wide `s/ADR-086/…/g`. It would corrupt Topic-D (GHCR minter, now **ADR-088**) strings and rewrite historical decision records. Use the scoped per-file lists below.

## Phase 0 — Preconditions (re-verify at /work start)

- [x] 0.1 Re-confirm next-free ordinals against `origin/main`: `git ls-files knowledge-base/engineering/architecture/decisions/ | grep -oE 'ADR-[0-9]+' | sort -u | tail`. If 093 or 094 got claimed by a sibling since plan time, bump to the new next-free pair and update every reference in this task list.
- [x] 0.2 Confirm the three colliding files still exist and `bash scripts/check-adr-ordinals.sh` currently passes ONLY because `ADR-086` is allowlisted.
- [x] 0.3 Re-confirm Topic-D carve-out: `grep -rl 'ADR-088' knowledge-base/project/specs/feat-one-shot-6031-ghcr-installation-token-minter/` returns hits (those `ADR-086` strings alias 088 — leave untouched).

## Phase 1 — Renames + ADR body edits

- [x] 1.1 `git mv knowledge-base/engineering/architecture/decisions/ADR-086-fail-closed-redaction-engine-contract.md knowledge-base/engineering/architecture/decisions/ADR-093-fail-closed-redaction-engine-contract.md`
- [x] 1.2 `git mv knowledge-base/engineering/architecture/decisions/ADR-086-freshness-last-reviewed-source-fix-and-audit-tripwire.md knowledge-base/engineering/architecture/decisions/ADR-094-freshness-last-reviewed-source-fix-and-audit-tripwire.md`
- [x] 1.3 In `ADR-093-…md`: change line 1 `# ADR-086:` → `# ADR-093:`; add a one-line **Ordinal note** after the `**Adapted from:**` line recording `renumbered 086→093 in the #6054 collision cleanup`.
- [x] 1.4 In `ADR-094-…md`: change line 1 `# ADR-086:` → `# ADR-094:`; **manually rewrite** the existing **Ordinal note** (was line 6) to the full chain: `085 (provisional) → 086 (at ship) → 094 (#6054 collision cleanup)`. Do NOT let a sed flip "re-verified to ADR-086" into a false "ADR-094".
- [x] 1.5 Verify both bodies still carry `## Status` / `## Context` / `## Decision` / `## Consequences` (renames preserve them).

## Phase 2 — Topic B (redaction) → ADR-093 (per-file blanket `s/ADR-086/ADR-093/g`)

- [x] 2.1 `plugins/soleur/skills/incident/SKILL.md` (L219 — slug becomes `ADR-093-fail-closed-redaction-engine-contract`)
- [x] 2.2 `plugins/soleur/skills/incident/scripts/redact-engine.py` (L207, L246)
- [x] 2.3 `plugins/soleur/skills/incident/scripts/redact-sentinel.sh` (L26)
- [x] 2.4 `plugins/soleur/skills/code-to-prd/scripts/code-to-prd.sh` (L468)
- [x] 2.5 `plugins/soleur/skills/legal-generate/SKILL.md` (L65)
- [x] 2.6 Verify: `for f in <the 5 B files>; do grep -c 'ADR-086' "$f"; done` all return 0.

## Phase 3 — Topic C (freshness) → ADR-094 (per-file blanket `s/ADR-086/ADR-094/g`)

- [x] 3.1 `.claude/hooks/context-reviewed-gate.sh` (L4 parenthetical slug → `ADR-094-freshness-last-reviewed-source-fix-and-audit-tripwire`; L17 `§Phase 4`; L178)
- [x] 3.2 `.claude/hooks/context-reviewed-gate.test.sh` (L2)
- [x] 3.3 `.claude/hooks/session-rules-loader.sh` (L30)
- [x] 3.4 `.github/workflows/review-reminder.yml` (L49; L177 inside the `::error::` string)
- [x] 3.5 `apps/web-platform/server/inngest/functions/cron-campaign-calendar.ts` (L108 — agent-prompt text)
- [x] 3.6 `apps/web-platform/test/server/inngest/cron-campaign-calendar.test.ts` (L84 — test label)
- [x] 3.7 `plugins/soleur/skills/brainstorm/SKILL.md` (L121)
- [x] 3.8 `scripts/context-reviewed-gate-discoverability.sh` (L2)
- [x] 3.9 `scripts/lib/frontmatter-strip.test.sh` (L3)
- [x] 3.10 `scripts/lib/frontmatter-strip/SPEC.md` (L5)
- [x] 3.11 `scripts/lib/frontmatter-strip/strip.py` (L6)
- [x] 3.12 `scripts/lib/frontmatter-strip/strip.sh` (L7)
- [x] 3.13 `scripts/lint-agents-rule-budget.py` (L44)
- [x] 3.14 `scripts/lint-agents-rule-budget.test.sh` (L270)
- [x] 3.15 `scripts/review-reminder-liveness.test.sh` (L2)
- [x] 3.16 `scripts/rule-metrics-aggregate.sh` (L264)
- [x] 3.17 `tests/scripts/test-rule-metrics-aggregate.sh` (L218)
- [x] 3.18 Verify: `for f in <the 17 C files>; do grep -c 'ADR-086' "$f"; done` all return 0.

## Phase 4 — Collision guard (META)

- [x] 4.1 `scripts/check-adr-ordinals.sh`: remove `ADR-086` from `ALLOWED_COLLISIONS=( … )` (L40).
- [x] 4.2 Rewrite the comment (L34–39) to past-tense resolution narrative: the three-way ADR-086 collision was resolved in #6054 — declarative kept 086, redaction→093, freshness→094.
- [x] 4.3 `bash scripts/check-adr-ordinals.sh` exits 0 and prints `ADR ordinal + content checks passed.`

## Phase 5 — Verification (AC gate)

- [x] 5.1 `ls knowledge-base/engineering/architecture/decisions/ | grep -c '^ADR-086'` == 1 (declarative only).
- [x] 5.2 Residual-zero (scoped): `git grep -n 'ADR-086' -- '.claude/' '.github/' 'scripts/' 'tests/' 'apps/' 'plugins/' 'knowledge-base/engineering/'` returns ONLY Topic-A declarative refs + the `check-adr-ordinals.sh` resolution comment (the AC7 allowlist). Any other hit = a missed B/C ref.
- [x] 5.3 C4 untouched: `git diff --stat` shows no change to `model.c4` / `views.c4` / `spec.c4` / `model.likec4.json`; `bash plugins/soleur/test/c4-model-freshness.test.sh` passes.
- [x] 5.4 Topic-D untouched: `git diff --name-only` includes none of the GHCR-minter files.
- [x] 5.5 Historical untouched: `git diff --name-only` includes no `knowledge-base/project/{plans,specs,brainstorms,learnings}/` file except this plan + tasks.md.
- [x] 5.6 Touched suites green: `scripts/lib/frontmatter-strip.test.sh`, `scripts/lint-agents-rule-budget.test.sh`, `scripts/review-reminder-liveness.test.sh`, `tests/scripts/test-rule-metrics-aggregate.sh`, `.claude/hooks/context-reviewed-gate.test.sh`, the two `cron-campaign-calendar` vitest suites, and the repo `scripts/test-all.sh` scripts shard.
- [x] 5.7 PR body uses `Closes #6054`.
