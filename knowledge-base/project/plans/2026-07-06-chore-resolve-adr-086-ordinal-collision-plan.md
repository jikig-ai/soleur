---
title: "chore(arch): resolve 3-way ADR-086 ordinal collision on main (adr-ordinals red)"
type: chore
date: 2026-07-06
lane: single-domain
issue: 6054
branch: feat-one-shot-6054-adr-086-collision
---

# chore(arch): resolve 3-way ADR-086 ordinal collision on main

## Enhancement Summary

**Deepened on:** 2026-07-06

**Deepen-plan halt gates (all pass):**
- **4.6 User-Brand Impact** — present; threshold `none` with a sensitive-path scope-out reason (Files-to-Edit include `apps/web-platform/server/inngest/functions/cron-campaign-calendar.ts`, which matches the sensitive-path regex, so the scope-out bullet is required and present). PASS.
- **4.7 Observability** — all 5 schema fields present with non-placeholder values; `discoverability_test.command` is `bash scripts/check-adr-ordinals.sh …` (no `ssh`). PASS.
- **4.8 PAT-shaped variable** — no `var.*_token`/`TF_VAR_*`/literal-token forms in the plan. PASS (no infra auth touched).
- **4.9 UI-wireframe** — no UI-surface file in Files-to-Edit (only `.md`, `.sh`, `.py`, `.ts` comment/test edits + a workflow YAML). SKIP.
- **4.5 network-outage / 4.55 downtime-cutover** — no trigger (no SSH/handshake/timeout keywords; no infra-reboot / DB-lock / deploy-router class). SKIP.

**Verify-the-negative passes (load-bearing carve-outs confirmed against the tree):**
- **Topic-D (GHCR minter) aliases ADR-088, not 086.** Confirmed: `…/feat-one-shot-6031-ghcr-installation-token-minter/` specs contain `ADR-088`; the minter plan carries 29 `ADR-086` hits that are stale references to what shipped as ADR-088. These MUST NOT be swept — a blanket `s/ADR-086/…/g` would corrupt ADR-088 citations. AC9 + the Sharp Edge guard this.
- **No live B/C file mixes both topics.** `git grep` confirms zero freshness markers in the Topic-B live files and zero redaction markers in the Topic-C live files → the per-file blanket substitution (`s/ADR-086/ADR-093/g` in B-files, `…094…` in C-files) is safe. (Multi-topic discussion exists only in Topic-A keep-086 files and the historical/META files, which are edited by hand or not at all.)
- **C4 untouched holds.** Both `model.c4` ADR-086 lines and all 11 `ADR-086` tokens in `model.likec4.json` are Topic A (declarative), which keeps 086 → no `.c4` edit, no regeneration, `c4-model-freshness.test.sh` stays green (AC8).

**Precedent (4.4):** the renumber follows the documented pattern in `workflow-patterns/2026-07-05-adr-ordinal-collision-on-rebase-renumber-mine-not-mains.md` (renumber-yours / discriminate-by-issue / regenerate-don't-hand-merge / verify-with-the-real-gate). No SQL/atomic-write/lock precedent applies (mechanical doc renumber).

**No new considerations changed the plan** — deepen-plan corroborated the keep-086 decision, the 093/094 assignment, the sweep scope, and the Files-to-Edit list. No decisions were revised.

## Overview

Three PRs authored **ADR-086** and merged into `main` in the same window (2026-07-05), so
`main` now carries three files claiming ordinal `ADR-086` and its own `adr-ordinals` CI check
(`scripts/check-adr-ordinals.sh`) is RED. PR #6011 papered over the breakage by adding `ADR-086`
to `ALLOWED_COLLISIONS` (the script's documented tech-debt mechanism) so unrelated PRs are not
blocked. This plan performs the cleanup: **keep one file at 086, renumber the other two to the
next-free ordinals, sweep every live cross-reference, then shrink `ALLOWED_COLLISIONS`** so the
gate goes green on its own.

The three colliding files:

| ID | File | Topic | Discriminating issue(s) |
|----|------|-------|-------------------------|
| **A** | `ADR-086-declarative-skill-context-injection.md` | declarative skill context-injection (PostToolUse:Skill, `context_queries`) | #5989 / #6035 / #6046 |
| **B** | `ADR-086-fail-closed-redaction-engine-contract.md` | fail-closed redaction engine (`redact-sentinel.sh`, NFKC) | #5987 / #6032 / #6045 |
| **C** | `ADR-086-freshness-last-reviewed-source-fix-and-audit-tripwire.md` | `last_reviewed` freshness + commit-time audit tripwire | #5999 / #6003 |

**Decision (locked, see Proposed Solution):** **A keeps ADR-086**; **B → ADR-093**; **C → ADR-094**.

## Problem Statement / Motivation

`adr-ordinals` is a **non-required** CI check, so the concurrent merges landed on `main` and the
check turned RED post-squash without blocking any auto-merge (this is exactly the failure class
`/ship`'s ADR-Ordinal Collision Gate and learning
`workflow-patterns/2026-07-05-adr-ordinal-collision-on-rebase-renumber-mine-not-mains.md` describe).
The allowlist entry is intentional, temporary tech debt; the comment at
`scripts/check-adr-ordinals.sh:28` says "When the cleanup issue lands, shrink this allowlist
accordingly." Until then, `main` ships a permanently-red ordinal gate and three docs lie about
their ordinal, which corrupts any future ADR cross-reference or `/soleur:architecture` lookup.

## Research Reconciliation — Spec vs. Codebase

| Issue-body claim | Reality (verified on branch @ origin/main state) | Plan response |
|------------------|--------------------------------------------------|---------------|
| "Renumber two of the three to the next free ordinals (**089/090**; 087 and 088 are taken by #6011)" | **STALE.** `ADR-089`, `ADR-090`, `ADR-091`, `ADR-092` all now exist on `main` (merged after the issue was filed). `git ls-files` confirms the highest ordinal is 092. | **Next-free ordinals are 093 and 094.** B → 093, C → 094. (Premise-drift caught at Phase 0.6 — a plan/issue ordinal is stale the moment a sibling ADR lands; re-verify against `origin/main` at ship, per `/ship` ADR-Ordinal gate.) |
| "regenerate `model.likec4.json`" | `model.c4` references ADR-086 on **only two lines (41, 62)**, and **both are Topic A (declarative)**, which keeps 086. `views.c4` / `spec.c4` have zero ADR-086 refs. | **No `.c4` edit and no regeneration needed.** `model.c4` / `model.likec4.json` stay byte-identical; `c4-model-freshness.test.sh` stays green. A verification step confirms this rather than a blind regen. |
| "update … principles-register, any citing code/docs" | `principles-register.md` has **zero** ADR-086 references (verified). | Drop principles-register from the sweep. |
| (implicit) "every `ADR-086` string is one of the three" | **FALSE.** A **fourth** cluster of `ADR-086` strings exists — the **GHCR installation-token minter** — which was *provisionally* ADR-086 but shipped as **`ADR-088`**. `feat-one-shot-6031-.../phase0-evidence.md:9-10` states "NOT ADR-086 … retarget ADR-088." | **Topic D (7 files) is explicitly carved OUT of the sweep** — its `ADR-086` strings are stale references to what is now ADR-088, not to B or C. A blanket `s/ADR-086/…/g` over the repo would corrupt these. |

## Proposed Solution

### Which file keeps 086

Three signals converge on **A (declarative) keeping ADR-086**:

1. **Merge/author order** (the conventional tiebreaker — first holder keeps the ordinal): A authored first (`a1018a640`, 18:45:39) < B (`b20a0d67c`, 18:47:55) < C (`74e772594`, 18:48:20).
2. **C4-model minimization:** `model.c4` references ADR-086 only for Topic A. Keeping A at 086 means **zero C4 edits and zero regeneration** — the smallest, safest blast radius.
3. **Issue framing:** the issue lists A (#6035) first and offers "merge order / cross-reference density" as the criterion.

Renumber assignment follows merge order onto the next-free ordinals: **B (2nd) → 093**, **C (3rd) → 094**.

### Sweep scope decision (live surfaces only)

The `ADR-086` string appears in **55 files**. The sweep is deliberately scoped to **live/authoritative
surfaces** (ADR bodies, code, hooks, scripts, skills, workflows) and **excludes**:

- **Historical migration artifacts** under `knowledge-base/project/{plans,specs,brainstorms,learnings}/`
  (~25 files) — point-in-time records that legitimately narrate `ADR-086` as it was at authoring
  time (e.g. `adr: ADR-086 (provisional)`). Rewriting them falsifies the record. (Mirrors the
  Step-2 own-migration-artifact carve-out convention.)
- **Topic D** (7 GHCR-minter files) — already stale → ADR-088; out of scope for this issue.
- **Topic A** live files — keep ADR-086, no edit.

Rationale over a full-repo sweep: a full sweep would (a) rewrite point-in-time decision records and
(b) risk Topic-D contamination (globs like `ADR-086-*.md` in minter docs). Live-surface-only is the
correct, defensible scope; the residual-zero AC is scoped to match.

### Sweep mechanics

**Every live citing file is single-topic** (verified line-by-line): each file's `ADR-086` token(s)
map to exactly one of B or C — no live file mixes B and C. So a **per-file blanket substitution** is
safe: `s/ADR-086/ADR-093/g` inside each B-file, `s/ADR-086/ADR-094/g` inside each C-file. This
correctly updates both bare ordinals **and** filename/slug forms (e.g. `incident/SKILL.md:219`'s
`ADR-086-fail-closed-redaction-engine-contract` → `ADR-093-fail-closed-redaction-engine-contract`).

**Two exceptions requiring manual (non-blanket) edits:**

1. **The C (freshness) ADR body's Ordinal note** (line 6): it narrates history ("Planned
   provisionally as ADR-085 … re-verified to **ADR-086** at implementation time"). A blanket sed
   would rewrite that history to "ADR-094" and lie. Instead, **rewrite** the note to record the full
   chain: 085 (provisional) → 086 (at ship) → **094** (this collision cleanup, #6054).
2. **`scripts/check-adr-ordinals.sh`** (META): remove `ADR-086` from the `ALLOWED_COLLISIONS` array
   and rewrite the comment (lines 34-39) from present-tense "is a three-way collision" to past-tense
   resolution ("was a three-way collision, resolved in #6054: A kept 086, B→093, C→094").

## Technical Considerations

- **CI drift-guard risk:** several C-topic files are *test* files (`frontmatter-strip.test.sh`,
  `lint-agents-rule-budget.test.sh`, `review-reminder-liveness.test.sh`,
  `test-rule-metrics-aggregate.sh`, `context-reviewed-gate.test.sh`, `cron-campaign-calendar.test.ts`).
  All current `ADR-086` occurrences are **comments**, not assertions on the literal string — but the
  Sharp Edge "CI sentinel substring match against canonical prose" applies. **Verification:** run each
  touched test suite after the sweep and confirm green; no test may assert the literal `ADR-086` as
  expected output for a renumbered topic.
- **`.ts` edits are comment-only** (`cron-campaign-calendar.ts:108` prompt text,
  `cron-campaign-calendar.test.ts:84` label) — no runtime behavior changes; `tsc` unaffected.
- **Renumber order** (`git mv`): both targets (093, 094) are free and distinct from 086, so there is
  no transient collision — order is immaterial. (Contrast the learning's "rename the later one first"
  which applied when targets overlapped source ordinals.)
- **No new architectural decision** is made (see Architecture Decision section) — this is a mechanical
  ordinal renumber; ADR *content* is unchanged.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. The failure surface is the
  `adr-ordinals` CI check staying RED on `main`, or an internal contributor / `/soleur:architecture`
  lookup following a stale `ADR-086` reference to the wrong decision doc.
- **If this leaks, the user's data / workflow / money is exposed via:** N/A — no user data, no
  secrets, no runtime code path touched (comment/identifier-string edits only).
- **Brand-survival threshold:** `none`
- *Scope-out override:* `threshold: none, reason: the diff only renames ADR docs and updates comment/identifier references — it touches no schema, migration, auth flow, API route, or .sql, and changes no runtime behavior.`

## Observability

```yaml
liveness_signal:
  what: "adr-ordinals CI check (scripts/check-adr-ordinals.sh) transitions RED -> GREEN on main"
  cadence: "per-push (ci.yml test-scripts shard)"
  alert_target: "PR checks + main CI status"
  configured_in: ".github/workflows/ci.yml + scripts/check-adr-ordinals.sh"

error_reporting:
  destination: "GitHub Actions CI job output (test-scripts shard)"
  fail_loud: "check-adr-ordinals.sh exits 1 with a named failing condition (e.g. 'NEW ADR ordinal collision'); c4-model-freshness.test.sh byte-diff fails loudly if a .c4 desync is introduced"

failure_modes:
  - mode: "a renumbered ADR still shares an ordinal (residual duplicate file)"
    detection: "scripts/check-adr-ordinals.sh (ls | grep -oE '^ADR-[0-9]{3}' | sort | uniq -d) after ALLOWED_COLLISIONS shrink"
    alert_route: "CI red on the PR and on main"
  - mode: "a live cross-reference left pointing at the wrong topic's ordinal"
    detection: "residual-grep AC (bare/slug ADR-086 remaining in a B/C live file returns >0)"
    alert_route: "PR CI / plan-review / QA"
  - mode: "unintended .c4 desync (should not happen — Topic A keeps 086)"
    detection: "plugins/soleur/test/c4-model-freshness.test.sh byte-diff"
    alert_route: "test-scripts CI shard"

logs:
  where: "GitHub Actions CI logs (test-scripts + test shards)"
  retention: "90 days (GitHub default)"

discoverability_test:
  command: "bash scripts/check-adr-ordinals.sh && bash plugins/soleur/test/c4-model-freshness.test.sh"
  expected_output: "'ADR ordinal + content checks passed.' AND 'PASS: committed model.likec4.json is in sync with the .c4 sources'"
```

## Architecture Decision (ADR/C4)

**No new architectural decision is created or changed** — this is a mechanical ordinal renumber of
two existing, already-Accepted ADRs; their `## Decision` bodies are unchanged. The ADR/C4 gate fires
because ADRs are touched, so its checks are recorded here:

### ADR
- No new ADR. Two existing ADRs are renamed (ordinal only): B `086→093`, C `086→094`, each with a
  provenance "Ordinal note" recording the `#6054` collision cleanup. `check-adr-ordinals.sh` required
  headings (`## Status`/`## Context`/`## Decision`/`## Consequences`) are preserved (renames, not
  rewrites).

### C4 views
- **No C4 impact — verified against all three `.c4` files.** Read `model.c4`, `views.c4`, `spec.c4`.
  Only `model.c4` references ADR-086 (lines 41, 62), and **both refs are Topic A (declarative
  context-injection, #6046)** which keeps ordinal 086. `views.c4` and `spec.c4` have zero ADR-086
  refs. No external actor, external system, container/data-store, or access-relationship changes:
  the renumber alters no element, edge, or `#external` boundary — it renames doc files whose ordinals
  the C4 model does not (for B/C) reference. Therefore `model.c4` is untouched and
  `model.likec4.json` needs no regeneration; a verification step asserts the freshness test stays green.

### Sequencing
- Single-PR atomic; no soak or staged status flip.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Renames:** `git mv` applied so exactly these files exist and the old names are gone:
      `ADR-093-fail-closed-redaction-engine-contract.md`,
      `ADR-094-freshness-last-reviewed-source-fix-and-audit-tripwire.md`; and
      `ADR-086-declarative-skill-context-injection.md` remains.
- [ ] **AC2 — ADR body titles:** line 1 of the renamed files reads `# ADR-093: …` and `# ADR-094: …`
      respectively.
- [ ] **AC3 — Ordinal notes:** the B body has a new "Ordinal note" recording `086→093 (#6054)`; the C
      body's existing Ordinal note is rewritten to `085 (provisional) → 086 (ship) → 094 (#6054)`.
- [ ] **AC4 — Gate green:** `ADR-086` removed from `ALLOWED_COLLISIONS` in `check-adr-ordinals.sh`,
      its comment rewritten to past-tense resolution, and `bash scripts/check-adr-ordinals.sh` exits 0
      printing `ADR ordinal + content checks passed.`
- [ ] **AC5 — B sweep complete:** for every Topic-B live file (see Files to Edit),
      `grep -c 'ADR-086' <file>` returns 0 and the topic now reads `ADR-093` (bare + slug forms).
- [ ] **AC6 — C sweep complete:** for every Topic-C live file, `grep -c 'ADR-086' <file>` returns 0
      and the topic now reads `ADR-094`.
- [ ] **AC7 — Residual-zero (scoped):** `git grep -n 'ADR-086' -- '.claude/' '.github/' 'scripts/'
      'tests/' 'apps/' 'plugins/' 'knowledge-base/engineering/'` returns **only** Topic-A
      (declarative) references + the `check-adr-ordinals.sh` resolution-narrative comment — i.e. the
      allowlist: `skill-context-queries.sh/.test.sh`, `agent-runner-query-options.ts`,
      `cc-dispatcher.ts`, `context-queries-hook.ts`, `context-queries-hook.test.ts`,
      `context-queries-shell-parity.test.ts`, `context-queries-fixture.ts`, `taste-profile-update.sh`,
      `ADR-090-*.md`, `model.c4`, `model.likec4.json`, and `check-adr-ordinals.sh`. Any other hit = a
      missed B/C ref = FAIL.
- [ ] **AC8 — C4 untouched:** `git diff --stat` shows no change to `model.c4`, `views.c4`, `spec.c4`,
      or `model.likec4.json`; `bash plugins/soleur/test/c4-model-freshness.test.sh` passes.
- [ ] **AC9 — Topic-D untouched:** `git diff --name-only` includes **none** of the 7 GHCR-minter
      files (their `ADR-086`→ADR-088 strings are out of scope).
- [ ] **AC10 — Historical artifacts untouched:** `git diff --name-only` includes no file under
      `knowledge-base/project/{plans,specs,brainstorms,learnings}/` except this plan + `tasks.md`.
- [ ] **AC11 — Touched suites green:** the affected test suites pass, confirming no drift-guard
      asserts on the `ADR-086` literal — at minimum:
      `scripts/lib/frontmatter-strip.test.sh`, `scripts/lint-agents-rule-budget.test.sh`,
      `scripts/review-reminder-liveness.test.sh`, `tests/scripts/test-rule-metrics-aggregate.sh`,
      `.claude/hooks/context-reviewed-gate.test.sh`, and the vitest suites for the two
      `cron-campaign-calendar` files.
- [ ] **AC12 — PR body uses `Closes #6054`** (this is a code-merge cleanup, not a post-merge
      ops-remediation — the fix ships in the diff, so auto-close on merge is correct).

## Test Scenarios

- Given the three ADR-086 files on `main`, when the two renames + sweep + allowlist-shrink land,
  then `bash scripts/check-adr-ordinals.sh` exits 0 (no allowlisted or new collision remains).
- Given Topic-D minter docs referencing `ADR-086` (now ADR-088), when the sweep runs, then those 7
  files are unchanged (carve-out honored).
- Given `model.c4` references only Topic A, when the renumber lands, then `model.c4` /
  `model.likec4.json` are byte-identical and `c4-model-freshness.test.sh` passes with no regen.
- Given the C-topic test files carry `ADR-086` only in comments, when they are renumbered to 094,
  then each touched suite still passes (no literal-string assertion breaks).

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned zero issues whose bodies reference
`check-adr-ordinals`, `ADR-086`, `model.c4`, `ALLOWED_COLLISIONS`, `redaction-engine`, or
`freshness-last-reviewed`.

## Domain Review

**Domains relevant:** none

CI/docs tech-debt cleanup (label `domain/engineering`). No cross-domain implications: no UI surface
(no `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx` in Files to Edit → Product NONE), no
regulated-data surface (GDPR gate skipped), no new infrastructure (IaC gate skipped). Mechanical
ordinal renumber owned entirely by engineering.

## Files to Edit

### ADR renames + body edits (`git mv` + manual)
- `knowledge-base/engineering/architecture/decisions/ADR-086-fail-closed-redaction-engine-contract.md` → `ADR-093-…` (title line 1 → `# ADR-093:`; add Ordinal note after "Adapted from" line)
- `knowledge-base/engineering/architecture/decisions/ADR-086-freshness-last-reviewed-source-fix-and-audit-tripwire.md` → `ADR-094-…` (title line 1 → `# ADR-094:`; **manually rewrite** the existing Ordinal note at line 6)

### Topic B (redaction) → ADR-093 (per-file blanket `s/ADR-086/ADR-093/g`)
- `plugins/soleur/skills/incident/SKILL.md` (L219 — slug/path form)
- `plugins/soleur/skills/incident/scripts/redact-engine.py` (L207, L246)
- `plugins/soleur/skills/incident/scripts/redact-sentinel.sh` (L26)
- `plugins/soleur/skills/code-to-prd/scripts/code-to-prd.sh` (L468)
- `plugins/soleur/skills/legal-generate/SKILL.md` (L65)

### Topic C (freshness) → ADR-094 (per-file blanket `s/ADR-086/ADR-094/g`)
- `.claude/hooks/context-reviewed-gate.sh` (L4 — parenthetical slug; L17 `§Phase 4`; L178)
- `.claude/hooks/context-reviewed-gate.test.sh` (L2)
- `.claude/hooks/session-rules-loader.sh` (L30)
- `.github/workflows/review-reminder.yml` (L49, L177)
- `apps/web-platform/server/inngest/functions/cron-campaign-calendar.ts` (L108 — comment/prompt text)
- `apps/web-platform/test/server/inngest/cron-campaign-calendar.test.ts` (L84 — test label)
- `plugins/soleur/skills/brainstorm/SKILL.md` (L121)
- `scripts/context-reviewed-gate-discoverability.sh` (L2)
- `scripts/lib/frontmatter-strip.test.sh` (L3)
- `scripts/lib/frontmatter-strip/SPEC.md` (L5)
- `scripts/lib/frontmatter-strip/strip.py` (L6)
- `scripts/lib/frontmatter-strip/strip.sh` (L7)
- `scripts/lint-agents-rule-budget.py` (L44)
- `scripts/lint-agents-rule-budget.test.sh` (L270)
- `scripts/review-reminder-liveness.test.sh` (L2)
- `scripts/rule-metrics-aggregate.sh` (L264)
- `tests/scripts/test-rule-metrics-aggregate.sh` (L218)

### Special (META)
- `scripts/check-adr-ordinals.sh` — remove `ADR-086` from `ALLOWED_COLLISIONS` (L40); rewrite comment L34-39 to past-tense resolution narrative.

### Explicitly NOT edited
- **Topic A (keep 086):** `skill-context-queries.sh`/`.test.sh`, `agent-runner-query-options.ts`, `cc-dispatcher.ts`, `context-queries-hook.ts`(+`.test.ts`), `context-queries-shell-parity.test.ts`, `context-queries-fixture.ts`, `taste-profile-update.sh`, `ADR-090-*.md`, `model.c4`, `model.likec4.json`.
- **Topic D (now ADR-088):** the 7 files under `…/feat-one-shot-6031-ghcr-installation-token-minter/`, `…/feat-ghcr-installation-token-minter-plan.md`, and the two `2026-07-05-ghcr…`/`…-adr-ordinal-collision…` learnings.
- **Historical artifacts:** all other `knowledge-base/project/{plans,specs,brainstorms,learnings}/` files.

## Files to Create

- `knowledge-base/project/plans/2026-07-06-chore-resolve-adr-086-ordinal-collision-plan.md` (this file)
- `knowledge-base/project/specs/feat-one-shot-6054-adr-086-collision/tasks.md`

## Dependencies & Risks

- **Risk — stale ordinal drifts again before merge:** a sibling ADR could take 093/094 during the
  pipeline. Mitigation: `/ship`'s ADR-Ordinal Collision Gate re-verifies next-free against
  `origin/main` before merge and after every Phase 7 sync; treat 093/094 as provisional until then.
- **Risk — Topic-D contamination via blanket sed:** mitigated by the scoped, per-file B/C edit lists
  (never a repo-wide `s/ADR-086/…/g`) + AC9.
- **Risk — a test drift-guard asserts the `ADR-086` literal:** mitigated by AC11 (run all touched
  suites). All current occurrences are comments; verify.
- **Dependency:** none blocking. PR #6011's `ALLOWED_COLLISIONS` entry is the thing this PR removes.

## References & Research

- Issue: #6054
- Interim allowlist PR: #6011 (added `ADR-086` to `ALLOWED_COLLISIONS`; took 087/088)
- Renumber pattern: `knowledge-base/project/learnings/workflow-patterns/2026-07-05-adr-ordinal-collision-on-rebase-renumber-mine-not-mains.md`
- Ship-time gate: `plugins/soleur/skills/ship/SKILL.md` §"ADR-Ordinal Collision Gate" (L1067)
- Collision guard + allowlist comment: `scripts/check-adr-ordinals.sh:28,34-40`
- C4 freshness gate: `plugins/soleur/test/c4-model-freshness.test.sh`; regen: `scripts/regenerate-c4-model.sh`
- Colliding ADRs: A `ADR-086-declarative-skill-context-injection.md` (#6035), B `ADR-086-fail-closed-redaction-engine-contract.md`, C `ADR-086-freshness-last-reviewed-source-fix-and-audit-tripwire.md`

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's threshold is `none` with a
  sensitive-path scope-out reason — filled.
- **Do not run a repo-wide `s/ADR-086/…/g`** — it would corrupt Topic-D (GHCR minter, now ADR-088)
  strings and rewrite historical decision records. Use the scoped per-file B/C edit lists only.
- The C (freshness) ADR body's Ordinal note is a **history record** — rewrite it manually to append
  the `→094 (#6054)` step; do not let the blanket sed flip "re-verified to ADR-086" into a false
  "re-verified to ADR-094".
