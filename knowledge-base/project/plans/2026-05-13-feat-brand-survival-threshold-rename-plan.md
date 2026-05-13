---
date: 2026-05-13
type: feat
title: brand_survival_threshold frontmatter key-rename + value-form normalization sweep
issue: 3724
parent_issue: 2725
parent_plan: knowledge-base/project/plans/2026-05-13-feat-incident-commander-skill-plan.md
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
detail_level: minimal
classification: mechanical-rename
---

# Plan: brand_survival_threshold frontmatter key-rename + value-form normalization sweep (#3724)

## Enhancement Summary

**Deepened on:** 2026-05-13
**Sections enhanced:** 4 (Research Reconciliation, FR2, Risks, Acceptance Criteria)

### Key Improvements (deepen-plan pass)
1. **Tag-array vs prose disambiguation.** Discovered that `kb-tags.txt:1288` lists `single-user-incident` (hyphenated) as a canonical KB tag, and 6 learning files use `single-user-incident` in YAML `tags:` arrays. Tag form is slugified (hyphenated by convention); prose form is the space form per `preflight/SKILL.md:473`. **Tag-array uses MUST NOT be renamed.** Updated FR2 disposition + new AC10.
2. **kb-tags.txt is auto-generated** by `scripts/generate-kb-index.sh` from frontmatter `tags:` in learning files (scoped to `knowledge-base/project/learnings/` per FR14 of that spec). If the 6 affected learning files keep their hyphenated tags, `kb-tags.txt` will continue to list the tag — no manual edit needed. Verified via `sed -n '105,135p' scripts/generate-kb-index.sh`.
3. **FR2 actual file count is 46** (not 42 from issue body, not 50). 42 of those are `.md/.yml/.yaml/.json`; the additional 4 are `.sh/.py/.txt`. The `.txt` file is `kb-tags.txt` (auto-regenerated — do not hand-edit).
4. **Preflight regex BOUNDARY tolerance verified.** `preflight/SKILL.md:472` defines `BOUNDARY='($|[[:space:]]*[.,;]|[[:space:]]+[—–-][[:space:]])'` — the plan's User-Brand Impact threshold line uses ` — inherited from parent…` trailing commentary, which is em-dash+space and matches BOUNDARY.

### New Considerations Discovered
- The 6 tag-array learning files (5 of 6 have ONLY the tag use; 1 has BOTH tag AND prose) require **per-line** judgment, not per-file. Rationale documented in §FR2 + §R7.
- `kb-tags.txt` MUST be regenerated post-rename via `bash scripts/generate-kb-index.sh` (not hand-edited) — added as AC11.

## Overview

Standalone PR1 prerequisite for #2725 incident-commander skill. **Mechanical rename only — zero behavior change.** Canonicalizes two surfaces:

1. **Frontmatter key** → `brand_survival_threshold:` (the form `AGENTS.core.md` `hr-weigh-every-decision-against-target-user-impact`, `brainstorm/SKILL.md:398`, and `preflight/SKILL.md:463` all expect).
2. **Value form** → `single-user incident` (with space, NOT hyphenated). `preflight/SKILL.md:473` regex `\`?single-user[[:space:]]+incident\`?` already pins the space form; the hyphenated value-form was effectively shadow-state.

D2+D3 (the incident-commander skill itself) ship in PR2 (#2725 / draft #3721) and DEPEND on this PR landing first.

## User-Brand Impact

**If this lands broken, the user experiences:** preflight Check 6 false-passes a sensitive-path diff because the threshold value is no longer a recognized token, OR `user-impact-reviewer` agent fails to fire on a `single-user incident`-tagged PR, OR a downstream skill's frontmatter grep silently misses a brand-critical artifact — any of which would dissolve the brand-survival gate that #2887 introduced.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — no runtime data path touched. Risk is entirely workflow-gate integrity.

**Brand-survival threshold:** single-user incident — inherited from parent #2725 brainstorm framing. D1 ships the canonical vocabulary that `user-impact-reviewer` and `preflight Check 6` already key off; any silent miscanonicalization here degrades the gate the parent feature depends on.

CPO sign-off carry-forward: covered by parent #2725 brainstorm (see `knowledge-base/project/brainstorms/2026-05-13-incident-commander-brainstorm.md` per issue body). Do NOT re-spawn CPO at this plan level — the parent's framing pre-approves D1 as the mechanical prerequisite.

## Research Reconciliation — Spec vs Codebase

| Issue body claim | Codebase reality (verified 2026-05-13) | Plan response |
|---|---|---|
| "5 files using `^brand_survival:`" | 5 files: 1 runbook, 1 brainstorm, 1 plan, 2 spec files | Confirmed — rename all 5 |
| "1 file using `^brand_threshold:`" | 1 file: `dashboard-error-postmortem.md` | Confirmed — rename |
| "~7 files using semantic `^threshold:`" | 6 files match `^threshold:`; 1 is non-brand-survival (numeric `threshold: 0.5` in test fixture); 1 uses inline `threshold: none, reason: …` form load-bearing for preflight Check 6 | Rename 4 of 6 (see disposition table §FR1c) |
| "50 files using `single-user-incident`" | 42 files (issue-body count was approximate); 59 total occurrences | Rename all 42 |

## FR1 — Frontmatter Key Rename

### FR1a — `brand_threshold:` → `brand_survival_threshold:`

**Files (1):**
- `knowledge-base/engineering/ops/runbooks/dashboard-error-postmortem.md:7`

### FR1b — `brand_survival:` → `brand_survival_threshold:`

**Files (5):**
- `knowledge-base/engineering/ops/runbooks/github-app-drift.md`
- `knowledge-base/project/brainstorms/2026-05-05-github-app-drift-guard-brainstorm.md`
- `knowledge-base/project/plans/2026-05-05-feat-github-app-drift-guard-plan.md`
- `knowledge-base/project/specs/feat-3187-gh-app-drift-guard/spec.md`
- `knowledge-base/project/specs/feat-3187-gh-app-drift-guard/tasks.md`

### FR1c — Semantic `threshold:` (brand-survival uses only) → `brand_survival_threshold:`

**Audit disposition for each `^threshold:` match (6 files):**

| File:line | Current value | Disposition | Rationale |
|---|---|---|---|
| `runbooks/codeql-bot-coverage.md:6` | `threshold: none` | **RENAME** | Frontmatter brand-survival semantic |
| `runbooks/lint-bot-statuses.md:6` | `threshold: none` | **RENAME** | Frontmatter brand-survival semantic |
| `runbooks/ruleset-bypass-drift.md:6` | `threshold: single-user-incident` | **RENAME both key + value** | Frontmatter; value also matches FR2 |
| `plans/2026-05-11-ops-ci-extend-lint-bot-synthetic-glob-plan.md:7` | `threshold: none` | **RENAME** | Frontmatter brand-survival semantic |
| `plans/2026-05-11-fix-preflight-...-plan.md:99` | `threshold: none, reason: SKILL.md operator-facing…` | **DO NOT RENAME** | Load-bearing: `preflight/SKILL.md:488,492,501` regex pins literal `threshold:[[:space:]]*none,[[:space:]]*reason:` as the scope-out sentinel inside the User-Brand Impact section. This is NOT a frontmatter key — it is a body-bullet contract that preflight Check 6 greps for. Renaming breaks the gate. |
| `plugins/soleur/skills/skill-security-scan/references/test-fixtures/clean-third-party.skill.md:21` | `threshold: 0.5` | **DO NOT RENAME** | Numeric review-confidence threshold in a test fixture — orthogonal vocabulary, not brand-survival. |

**Net FR1c renames: 4 files.**

## FR2 — Value-Form Rename: `single-user-incident` → `single-user incident`

**Scope: all non-archive matches EXCEPT tag-array occurrences.** Verified via `git grep -l "single-user-incident" | grep -v archive/ | wc -l` → **46 files** (42 `.md/.yml/.yaml/.json` + 4 other: 2 `.sh`, 1 `.py`, 1 `.txt`). Archive (`**/archive/**`) is excluded per AGENTS — historical record.

### FR2 disposition by use-site type

**Per-line judgment required, not per-file.** Two distinct vocabularies share the token `single-user-incident`:

| Use-site shape | Action | Why |
|---|---|---|
| YAML frontmatter tag array (`tags: [..., single-user-incident, ...]` or `\n  - single-user-incident`) | **DO NOT RENAME** | KB tag convention is hyphen-slugified (lowercase, no spaces). `kb-tags.txt` auto-generation enforces this. Renaming the tag would orphan the slug and `scripts/generate-kb-index.sh` would re-emit the hyphenated form on next regeneration. |
| Frontmatter brand-survival value (`brand_threshold: single-user incident`, etc. — handled in FR1) | RENAME | Already covered by FR1. |
| Prose (markdown body, error message, code comment, log string, workflow `echo`) | **RENAME** → `single-user incident` | Space form is canonical per `AGENTS.core.md:29` and `preflight/SKILL.md:473` regex. |
| Adjective-suffix form (`single-user-incident-class`, `single-user-incident-` followed by another word — `scripts/lint-rule-ids.py:212,368`) | **RENAME** → `single-user incident-class` etc. | Reads naturally as adjective ("single-user incident-class regression"); if grammatically awkward at /work, leave with `[skipped — adjective form]` note. |
| Auto-generated `knowledge-base/kb-tags.txt:1288` | **DO NOT HAND-EDIT** | Auto-regenerated by `scripts/generate-kb-index.sh` from learning frontmatter tags (which are preserved per row 1). Regenerate post-rename via AC11. |

### Files affected by tag-vs-prose disambiguation (per-line judgment)

**6 learning files have YAML tag-array uses of `single-user-incident` — preserve the tag, rename any prose:**
1. `knowledge-base/project/learnings/2026-05-03-user-impact-reviewer-catches-runtime-content-tamper-vectors.md` (line 7 tag — PRESERVE; line 14 prose — RENAME)
2. `knowledge-base/project/learnings/2026-05-10-plan-time-reviewer-orthogonality-for-security-sensitive-plans.md` (tag only)
3. `knowledge-base/project/learnings/2026-05-11-multi-agent-review-vendor-pipeline-trust-model.md`
4. `knowledge-base/project/learnings/2026-05-11-plan-review-caught-git-log-union-trap-and-cross-module-field-assumption.md`
5. `knowledge-base/project/learnings/2026-05-12-plan-review-5-agent-panel-and-architecture-only-p1s.md`
6. `knowledge-base/project/learnings/security-issues/2026-05-12-multi-agent-review-catches-load-bearing-redaction-primitive-bypasses.md`

For each: `grep -n "single-user-incident" <file>` and inspect each line. Lines matching `^[[:space:]]*tags:[[:space:]]*\[` OR `^[[:space:]]+-[[:space:]]+single-user-incident$` = preserve. All other lines = rename.

### Code-level (non-`.md/.yml/.yaml/.json`) references — 4 files

All verified as **PROSE COMMENTS or auto-generated content**, not regex/grep/pattern-match logic — safe to rename per the prose rule:

- `.claude/hooks/skill-security-scan-write.sh:87,133` — comments
- `scripts/lint-rule-ids.py:212,368` — comments using `single-user-incident-class` (adjective-suffix form per disposition table above)
- `plugins/soleur/skills/linear-fetch/scripts/persist-safe-integration.test.sh:16` — comment
- `knowledge-base/kb-tags.txt:1288` — auto-generated tag list; **do not hand-edit**; will be regenerated by `scripts/generate-kb-index.sh` post-rename (AC11) and will continue to contain `single-user-incident` (the hyphenated tag form) because the source frontmatter tags are preserved.

**Already-grep'd code references that DO NOT contain the hyphenated form** (and thus are NOT in this PR's scope): `.claude/hooks/session-rules-loader.sh:26`, `apps/web-platform/server/soleur-go-runner.ts:368`, `scripts/audit-ruleset-bypass.sh:11`, `plugins/soleur/skills/linear-fetch/scripts/redact-linear-urls.test.sh:6` already use the space form. Listed for traceability — no edit required.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — FR1a/b:** `git grep -nE "^(brand_threshold|brand_survival):" -- '*.md' '*.yml' '*.yaml' '*.json' | grep -v archive/` returns ZERO hits.
- [ ] **AC2 — FR1c:** `git grep -nE "^threshold:" -- '*.md' '*.yml' '*.yaml' '*.json' | grep -v archive/` returns ONLY the 2 protected files (`2026-05-11-fix-preflight-...-plan.md:99` and `clean-third-party.skill.md:21`). All 4 renamed entries no longer appear.
- [ ] **AC3 — FR2 (prose):** `git grep -nE "single-user-incident" 2>/dev/null | grep -v archive/ | grep -vE "^[^:]+:[[:digit:]]+:[[:space:]]*tags:[[:space:]]*\[|^[^:]+:[[:digit:]]+:[[:space:]]+-[[:space:]]+single-user-incident\$" | grep -vE "^knowledge-base/kb-tags\.txt:"` returns ZERO hits. (The filter explicitly excludes tag-array uses and the auto-generated `kb-tags.txt`; everything else MUST be renamed to the space form.)
- [ ] **AC4 — Inline scope-out sentinel preserved:** `grep -nE "^threshold:[[:space:]]*none,[[:space:]]*reason:" knowledge-base/project/plans/2026-05-11-fix-preflight-work-skills-worktree-and-test-all-gate-plan.md` returns exactly 1 hit (line 99).
- [ ] **AC5 — Numeric test fixture preserved:** `grep -nE "^threshold: 0\.5" plugins/soleur/skills/skill-security-scan/references/test-fixtures/clean-third-party.skill.md` returns exactly 1 hit (line 21).
- [ ] **AC6 — Preflight regex still matches:** Test against a canonical `- **Brand-survival threshold:** single-user incident` bullet (the form `preflight/SKILL.md:473` greps for). NOT FOR THIS PR'S DIFF (which is mechanical only) — verify the regex `\`?single-user[[:space:]]+incident\`?` continues to match unchanged.
- [ ] **AC7 — Zero-behavior-change CI check:** All pre-existing CI checks pass with same green status as `main` baseline. No new lint errors, no new test failures, no new pre-commit failures.
- [ ] **AC8 — Single commit, single PR:** One atomic commit `feat: rename brand_survival_threshold frontmatter key + canonicalize single-user incident value-form (#3724)`. PR body references parent #2725 via `Ref #2725` (NOT `Closes` — D1 is a prerequisite, D2+D3 close #2725 in PR2).
- [ ] **AC10 — Tag-array preservation:** `git grep -nE "^[[:space:]]*tags:[[:space:]]*\[.*single-user-incident\|^[[:space:]]+-[[:space:]]+single-user-incident\$" -- '*.md' 2>/dev/null | grep -v archive/` returns the SAME 6 source-line hits as on `main` baseline. The 6 hits are listed in §FR2 — each must remain hyphenated (KB tag slug convention).
- [ ] **AC11 — kb-tags.txt regeneration:** Run `bash scripts/generate-kb-index.sh` post-rename. Verify `grep -n "^single-user-incident\$" knowledge-base/kb-tags.txt` returns exactly 1 hit (the regenerated tag entry — auto-emitted from the 6 preserved tag-array uses in AC10). If the entry disappears, AC10 was violated upstream; re-audit the 6 learning files.

### Post-merge (operator)

- [ ] **AC9 — Parent PR rebase:** After this PR lands on `main`, rebase #3721 (PR2 for #2725) onto updated `main`. The spec body for #2725 will receive `[Updated 2026-05-13]` markers in PR2 once the rename is on disk.

## Files to Edit

**Total: ~47 files** (42 value-form + 4 frontmatter-key FR1c + 1 FR1a + ~5 FR1b minus overlap; some files appear in both lists).

Frontmatter (10 unique files):
1. `knowledge-base/engineering/ops/runbooks/dashboard-error-postmortem.md` (FR1a)
2. `knowledge-base/engineering/ops/runbooks/github-app-drift.md` (FR1b)
3. `knowledge-base/project/brainstorms/2026-05-05-github-app-drift-guard-brainstorm.md` (FR1b)
4. `knowledge-base/project/plans/2026-05-05-feat-github-app-drift-guard-plan.md` (FR1b)
5. `knowledge-base/project/specs/feat-3187-gh-app-drift-guard/spec.md` (FR1b)
6. `knowledge-base/project/specs/feat-3187-gh-app-drift-guard/tasks.md` (FR1b)
7. `knowledge-base/engineering/ops/runbooks/codeql-bot-coverage.md` (FR1c)
8. `knowledge-base/engineering/ops/runbooks/lint-bot-statuses.md` (FR1c)
9. `knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md` (FR1c — both key + value)
10. `knowledge-base/project/plans/2026-05-11-ops-ci-extend-lint-bot-synthetic-glob-plan.md` (FR1c)

Value-form (42 files): enumerate at /work time via `git grep -l "single-user-incident" -- '*.md' '*.yml' '*.yaml' '*.json' '*.sh' '*.ts' '*.js' '*.py' | grep -v archive/`. Includes:
- `.github/workflows/pr-quality-guards.yml` (prose + error message strings)
- `.claude/hooks/session-rules-loader.sh`, `.claude/hooks/skill-security-scan-write.sh` (comments)
- `apps/web-platform/server/soleur-go-runner.ts` (comment)
- `scripts/audit-ruleset-bypass.sh`, `scripts/lint-rule-ids.py` (comments — see Risks §R3 for `-incident-class` suffix)
- `plugins/soleur/skills/linear-fetch/scripts/*.test.sh` (comments)
- ~33 `knowledge-base/**/*.md` files (brainstorms, plans, specs, learnings, runbooks)

## Files to Create

None.

## Risks

| ID | Risk | Mitigation |
|---|---|---|
| **R1** | `threshold:` semantic-vs-review-threshold disambiguation: blindly renaming all `^threshold:` matches breaks (a) preflight Check 6 scope-out sentinel at `2026-05-11-fix-preflight-...-plan.md:99`, and (b) numeric review-threshold in `clean-third-party.skill.md:21`. | Disposition table in §FR1c enumerates each of the 6 files explicitly. /work phase MUST follow the table — no blanket `sed -i` over `^threshold:`. AC2 + AC4 + AC5 gate this at PR time. |
| **R2** | preflight regex regression: `preflight/SKILL.md:473` already pins `single-user[[:space:]]+incident` (space form). If `pr-quality-guards.yml` or `audit-ruleset-bypass.sh` did regex-match against the hyphenated form, renaming would break their workflow logic. | Verified manually — all 7 code-level references are PROSE COMMENTS (see FR2 disposition). No regex/grep depends on the hyphenated form. AC7 (zero-behavior-change CI) catches any residual surface. |
| **R3** | `scripts/lint-rule-ids.py:212,368` uses adjective-suffixed forms `single-user-incident-class` and `single-user-incident-` (hyphen-suffix is grammatical, not the value-form). | Rename to `single-user incident-class` reads naturally as an adjective ("single-user incident-class regression"). Code is a comment; no semantic impact. Verify visually at /work — if grammatically awkward, leave with `[skipped — adjective form]` note in PR body. |
| **R4** | Archive paths (`**/archive/**`) should NOT be touched (historical record). | All `git grep` enumeration commands in ACs include `| grep -v archive/`. /work phase MUST apply the same filter. |
| **R5** | Drift between PR1 land and PR2 (#3721) rebase: another contributor lands a new file with the old value-form between PR1 merge and PR2 rebase. | Out of scope for this PR. `pr-quality-guards.yml` already has language guarding the brand-survival vocabulary; if it does NOT yet block the hyphenated form, file a follow-up `wg-*` gate after PR1 lands (deferred to #2725 D2/D3 scope). |
| **R6** | One file is the `feat-3187-gh-app-drift-guard/spec.md` and `tasks.md` — touching closed-feature spec files. | Acceptable — spec frontmatter is a forward-reference contract for any future tooling that reads spec frontmatter. Renaming is mechanical and non-destructive (preserves all spec body content). |
| **R7** | **Tag-array vs prose disambiguation (deepen-plan finding).** `single-user-incident` is both (a) a slugified KB tag in `kb-tags.txt` + 6 learning files' YAML `tags:` arrays AND (b) a prose value-form. Blanket rename orphans the tag slug and silently breaks `kb-search` faceting. | §FR2 disposition table enumerates per-line judgment rules. AC10 verifies tag-array preservation. AC11 verifies `kb-tags.txt` regenerates cleanly. /work phase MUST inspect each of the 6 listed learning files line-by-line — never blanket `sed` over learning frontmatter. |

## Test Strategy

**No new tests.** This is a mechanical rename with zero behavior change. Verification is entirely grep-based at the AC level.

**Manual verification** at /work:
1. Apply rename via per-file `Edit` (not blanket `sed -i` — disposition table requires per-file judgment).
2. Run ACs 1-5 as `git grep` commands and confirm expected counts.
3. Run `bun test` / `pnpm test` (whatever the package.json scripts.test resolves to) and confirm pre-existing green status holds.
4. Open PR; let CI run; confirm AC7 (no new red checks vs `main`).

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open --json number,title,body --limit 200`. None of the 47 planned files appear in any open code-review issue body. Disposition: **None.**

## Domain Review

**Domains relevant:** Engineering (mechanical refactor), Product (brand-survival vocabulary is product-owned).

**Carry-forward from parent #2725 brainstorm.** CPO + CLO + CTO sign-offs landed at the brainstorm framing of #2725 (per issue body's reference to `knowledge-base/project/brainstorms/2026-05-13-incident-commander-brainstorm.md`). D1 (this PR) is the canonical-vocabulary prerequisite that the brainstorm framing already presumed; no fresh domain spawn needed at this plan level.

### Product/UX Gate

**Tier:** none — no user-facing surface touched. All edits are operator-facing markdown/YAML/code comments.

## GDPR / Compliance Gate

**Skip.** No regulated-data surface touched. No schemas, migrations, auth flows, API routes, or `.sql` files in the diff. No new processing activity. The rename does not introduce any cross-controller data movement.

## Sharp Edges

- **Do NOT use blanket `sed -i 's/single-user-incident/single-user incident/g'`** — TWO disambiguations require per-line judgment: (a) 6 learning files have tag-array uses that MUST stay hyphenated (R7); (b) `scripts/lint-rule-ids.py:212,368` uses adjective-suffixed forms (R3). Per-file `Edit` is required.
- **Do NOT rename `^threshold:` matches blindly** — 2 of the 6 matches are LOAD-BEARING for unrelated gates (R1). Follow the §FR1c disposition table.
- **Do NOT hand-edit `knowledge-base/kb-tags.txt`** — it is auto-generated by `scripts/generate-kb-index.sh`. The hyphenated `single-user-incident` entry will regenerate from preserved tag-array uses (AC11).
- **Do NOT touch `**/archive/**`** — historical record (R4). All AC greps and /work edits must filter via `grep -v archive/`.
- **PR body MUST use `Ref #2725`, NOT `Closes #2725`** — D1 is a prerequisite; D2+D3 close #2725 in PR2. Premature `Closes` would auto-close #2725 at this PR's merge and lose the parent's tracking state. Same class as the `Closes` rule for ops-remediation PRs in the Sharp Edges list of the plan skill.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Already filled — carry-forward from #2725.)

## Implementation Phases

**Single phase — mechanical rename.**

1. Apply FR1a (1 file, 1 line edit).
2. Apply FR1b (5 files, 1 line edit each).
3. Apply FR1c per disposition table (4 of 6 `^threshold:` files — skip the 2 protected).
4. Apply FR2 — split into two passes:
   - **4a.** For the 6 learning files in §FR2 with YAML tag-array uses: `grep -n "single-user-incident" <file>` per file; rename PROSE lines only; preserve tag-array lines (R7).
   - **4b.** For all other 40 files (46 total − 6 tag-array files): per-file `Edit` rename (avoids mangling adjective-suffix forms in `lint-rule-ids.py` per R3). Skip `knowledge-base/kb-tags.txt` — auto-regenerated in step 5.
5. Run `bash scripts/generate-kb-index.sh` to regenerate `kb-tags.txt`. Confirm AC11 grep passes.
6. Run AC verification greps (AC1-AC5, AC10) locally.
7. Commit as one atomic commit; push; open PR with `Ref #2725` (not `Closes`).
8. Wait for CI; verify AC7 (zero new red checks vs `main`).

## Parent Linkage

- **Parent feature:** #2725 (incident-commander skill)
- **Parent plan:** `knowledge-base/project/plans/2026-05-13-feat-incident-commander-skill-plan.md` §FR1
- **Parent brainstorm:** `knowledge-base/project/brainstorms/2026-05-13-incident-commander-brainstorm.md`
- **Parent spec:** `knowledge-base/project/specs/feat-incident-commander-2725/spec.md` §FR1, AC1-AC3
- **Parent PR (draft):** #3721 (D2+D3 — depends on this landing first)
