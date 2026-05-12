---
title: "chore(agents): pre-commit hook for AGENTS.md rule-budget + skill-enforced-anchor parity"
issue: 3684
branch: feat-one-shot-3684-agents-md-precommit-hook
type: chore
classification: tooling-only
lane: single-domain
priority: p3-low
created: 2026-05-12
requires_cpo_signoff: false
---

# chore(agents): pre-commit hook for AGENTS.md rule-budget + skill-enforced-anchor parity

## Enhancement Summary

**Deepened on:** 2026-05-12
**Sections enhanced:** Research Reconciliation, Acceptance Criteria (AC3, AC8, AC9, NEW AC15), Implementation Phases (Phase 3), Sharp Edges, Test Strategy, Files to Edit
**Live verifications run during deepen-pass:**

- `gh pr view 3681` → MERGED (cited correctly).
- `gh issue view 3679 / 3682 / 3683` → all exist (3679, 3682 closed; 3683 open). Citation `#3682 (just merged)` corrected to `#3682 (closed issue)` — there is no PR #3682.
- `gh label list | grep` → labels `priority/p3-low`, `type/chore` exist (frontmatter labels valid).
- `bash scripts/test-all.sh` discovery: **explicit `run_suite` list** — NOT a `find` glob. New tests must be added explicitly OR placed in `plugins/soleur/test/*.test.sh` (which IS auto-discovered at `scripts/test-all.sh:71-74`). AC8 corrected.
- Per-segment parity probe of all 4 AGENTS files using the issue body's proposed `grep -F` semantics: **10 of 21 segments are dangling** under the naive proposal. Five are anchor-notation drift (`Phase 1.4` in AGENTS, `### 1.4.` in skill body); five are descriptive-prose anchors (`step 8 (Why-line trim semantics + loader-class-fit)`, `Phase 0 Type-widening cross-consumer grep`, etc.). New AC15 ships migration in the same PR; the `--check-anchors` invocation under AC11 must pass against the migrated state.
- Threshold-update site sweep: AC9 also covers `AGENTS.docs.md:6` — the `cq-agents-md-why-single-line` rule body literally says "Targets: always-loaded payload ≤18000 warn / ≤22000 critical." This is a 4th surface that drifts on the warn-threshold change.

### Key Improvements

1. **AC15 (NEW): Live-state migration in the same PR.** The `--check-anchors` flag is meaningless if 10 of 21 existing tags fail. Two-prong migration: (a) update AGENTS tag-style convention so `Phase 1.4` becomes a literal substring of the skill body (rewrite skill headings OR rewrite tag prose), (b) bootstrap `scripts/agents-anchor-ignore.txt` for any segment whose load-bearing meaning is descriptive-prose (e.g., `step 8 (Why-line trim semantics + loader-class-fit)`).
2. **AC8 corrected.** `scripts/test-all.sh` is an explicit list, not a discovery loop. Tests go to `plugins/soleur/test/*.test.sh` (auto-discovered) OR explicit `run_suite` lines in `test-all.sh`. Plan picks the explicit-`run_suite` route to keep the new tests next to the script they exercise.
3. **AC9 expanded.** Threshold update surfaces include `AGENTS.docs.md:6` (rule body text), `compound/SKILL.md:220`, `compound/SKILL.md:226`, the new `lint-agents-rule-budget.sh` defaults. Cross-file consistency check added.
4. **Sharp Edge added: anchor-notation contract.** Explicit guidance for future tag authors — anchor segment must be a verbatim substring of the named skill's SKILL.md text. Codified as a one-line note inside the new lefthook command's comment AND inside `cq-agents-md-tier-gate`'s body trim region.
5. **`scripts/agents-payload-bytes.sh` correctly placed under `scripts/lib/`** (sibling to `rule-metrics-constants.sh`, `strip-log-injection.sh`) — matches the existing convention in the codebase. Original plan got the path right (`scripts/lib/agents-payload-bytes.sh`); confirmed in deepen-pass.

### New Considerations Discovered

- **Anchor-notation drift is the primary failure class**, not allowlist scope. The deepen-pass per-segment probe (10/21 dangling) is the load-bearing finding — without AC15, AC11 is unsatisfiable.
- **`set -euo pipefail` interaction with byte arithmetic.** New `lint-agents-rule-budget.sh` uses `$(( ))`. Confirmed `wc -c <` always emits a numeric (even for empty files: `0`). No regex guard needed for budget arithmetic. (Generalizes the `2026-04-21-cloud-task-silence-watchdog-pattern.md` learning that flagged `$(( ))` crashes on non-numeric — does not apply here.)
- **Lefthook gobwas glob `**` semantics:** new `agents-skill-enforced-anchor` command's glob `plugins/soleur/skills/**/SKILL.md` requires that all SKILL.md files sit at least one directory deep (they do — every SKILL.md is at `plugins/soleur/skills/<name>/SKILL.md`, never at `plugins/soleur/skills/SKILL.md`). Verified via `find plugins/soleur/skills -mindepth 2 -name SKILL.md | wc -l` and `find plugins/soleur/skills -maxdepth 1 -name SKILL.md`. Path-array form retained for symmetry with sibling commands.
- **Allowlist file linter wired through the existing `lint-agents-enforcement-tags.py`** so the file is ALWAYS validated when tags or skills change, even if only the allowlist is staged. AC4's lefthook glob already includes `scripts/agents-anchor-ignore.txt`.

## Overview

Make the always-loaded AGENTS payload byte-cap **load-bearing at commit time**, and add an anchor-parity check that catches dangling `[skill-enforced: <skill> <anchor>]` pointers before they merge.

Today both signals exist but are advisory:

- **Byte cap (22 k):** `plugins/soleur/skills/compound/SKILL.md:227` emits `[CRITICAL]` advisory; `.github/workflows/scheduled-compound-promote.yml:198-203` enforces it for the cron-promotion path only. Manual edits to `AGENTS.md` / `AGENTS.core.md` from operator commits are not gated. PR #3681 trimmed payload back to 21,985 B (15 B headroom). At the documented growth rate (~700 B/day from #3681 plan), 22 k re-trips in 1-13 days.
- **Anchor parity:** `scripts/lint-agents-enforcement-tags.py` resolves `[skill-enforced: <skill> ...]` to `plugins/soleur/skills/<skill>/SKILL.md` (file existence) but **deliberately does NOT verify the anchor text** within the skill (per the docstring at line 11-13 — phase notation is intentionally unverified to avoid coupling AGENTS.md formatting to skill heading style). The pattern-recognition F6 in PR #3681 review surfaced this gap as silent pointer drift.

This plan extends both surfaces to fail-closed at `git commit` time, wired through the existing `lefthook.yml` `pre-commit:` block.

## Research Reconciliation — Spec vs. Codebase

| Issue body claim | Codebase reality | Plan response |
|---|---|---|
| "Add a pre-commit hook (lefthook or `.claude/hooks/`)" | `lefthook.yml` already wires 3 AGENTS lints (`rule-id-lint`, `agents-compound-sync`, `agents-enforcement-tag-lint`). New hooks should add commands to this block, not duplicate the framework. | Wire 2 NEW lefthook commands (`agents-rule-budget`, `agents-skill-enforced-anchor`) alongside the existing 3. No new hook framework. |
| "Computes B_ALWAYS = wc -c AGENTS.md + wc -c AGENTS.core.md" | Existing computation lives in `plugins/soleur/skills/compound/SKILL.md:207-209` and `.github/workflows/scheduled-compound-promote.yml:148-160`. | Extract to a single shared shell library (`scripts/lib/agents-payload-bytes.sh`) and have all three callers (compound advisory, cron workflow, new pre-commit hook) source it. Single source of truth for the formula. |
| "For each `[skill-enforced: <skill> <bullet-title>]` tag, asserts `grep -F '<bullet-title>' plugins/soleur/skills/<skill>/SKILL.md` returns ≥1 match" | (a) The `<rest>` field is **not** a "bullet-title" — `lint-agents-enforcement-tags.py:11-13` documents 5 distinct notations (`Phase X`, `Check X`, `Route-Learning-to-Definition`, agent name, etc.) and intentionally skips anchor verification for this reason. (b) Many tags name **multiple skills with comma-separated anchors** in one tag (e.g., `[skill-enforced: brainstorm Phase 0.1, plan Phase 2.6, deepen-plan Phase 4.6, review user-impact-reviewer, preflight Check 6]` — 5 distinct (skill, anchor) pairs). The naive `grep -F` against the first skill would false-fail on every multi-skill tag. | Plan implements a tag-parser that splits `<rest>` on `,` into per-skill `(skill, anchor)` segments, then runs the parity grep per-segment. The grep substring is the ENTIRE anchor segment after the skill name (`Phase 1.4`, `Check 6`, `user-impact-reviewer`), which is the verbatim text the operator/reader can grep against the skill body. False-positive class (legitimate trims) is handled by an `--ignore-anchor` allowlist file (`scripts/agents-anchor-ignore.txt`) symmetrical to `scripts/retired-rule-ids.txt`. |
| "Reject if any tag is dangling" | Existing `lint-agents-enforcement-tags.py` exits 1 on missing skill dir; new check extends this with anchor-text verification but follows the same exit semantics. | Extend `lint-agents-enforcement-tags.py` with an opt-in `--check-anchors` flag (default-off so the existing single-purpose mode keeps its contract for downstream callers). Wire `--check-anchors` from the new lefthook command. |
| "Warns at 20,000 B" | Existing compound advisory uses **18,000** B for warn (`SKILL.md:226`) and **22,000** B for critical (`SKILL.md:227`). The cron workflow uses 22 k as the hard cap. Issue says 20 k warn — drift from existing convention. AGENTS.docs.md line 6 (`cq-agents-md-why-single-line` rule body) ALSO names "≤18000 warn / ≤22000 critical" verbatim. | Plan defaults to **20,000 B warn / 22,000 B critical** per the issue body (closer to the cap so warn fires before commit-rejection becomes likely), and updates ALL FOUR threshold-source surfaces in the SAME PR for symmetry: (1) compound `SKILL.md:220` advisory output text, (2) compound `SKILL.md:226` advisory branch threshold, (3) `AGENTS.docs.md:6` rule body text, (4) new `lint-agents-rule-budget.sh` defaults. The 18 k threshold was set when payload was 12 k; with payload at 21,985 B today, an 18 k warn fires every commit — useless. CPO sign-off not required (cosmetic threshold delta on advisory output; load-bearing 22 k cap is unchanged). |
| "For each `[skill-enforced: <skill> <bullet-title>]` tag, naive `grep -F '<bullet-title>'` returns ≥1 match" | **Live deepen-pass parity probe (per-segment scan of all 4 AGENTS files): 10 of 21 segments dangling under naive substring semantics.** Examples: `[skill-enforced: plan Phase 1.4]` references skill heading `### 1.4. Network-Outage Hypothesis Check` — the literal `Phase 1.4` substring is absent. `[skill-enforced: compound step 8 (Why-line trim semantics + loader-class-fit)]` is descriptive prose (refers to the 8th numbered item under `## Phase 1.5: Deviation Analyst`); no literal substring resolves. The existing `lint-agents-enforcement-tags.py:11-13` docstring documents this is intentional: "Phase notation (`Phase X`, `step X`, `Check X`, `Route-Learning-to-Definition`, agent name) is deliberately NOT verified". | New AC15 ships a same-PR migration to make the parity check meaningful. Two-prong fix: (a) **anchor-notation contract** — going forward, every tag's anchor segment MUST be a verbatim substring of the named skill's SKILL.md text. Codified inline in the new lefthook command's comment + in `cq-agents-md-tier-gate`'s body. (b) **Migrate existing 10 dangling segments**: rewrite each AGENTS tag to use a substring that exists in the named skill (preferred), OR if the skill heading is correct and the AGENTS notation is the legacy/wrong form, update the skill heading to include the AGENTS-form substring. For irreducibly-descriptive anchors (the `step 8 (...)` paren-prose form), allowlist via `scripts/agents-anchor-ignore.txt` with one-line rationale. Allowlist entries SHOULD be migrated to literal-substring form opportunistically. |

## User-Brand Impact

**If this lands broken, the user experiences:** every `git commit` that touches `AGENTS.md` / `AGENTS.core.md` rejects with a confusing budget-overflow error and the operator cannot land hot-fix rule edits without `--no-verify` (which silences ALL pre-commit hooks, not just this one). Loop-back is local (operator can re-trim then commit); no production user impact.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — this is a local pre-commit hook on a docs-class file. No regulated data, no auth surface, no schema change.

**Brand-survival threshold:** none, reason: tooling-only change to local pre-commit gate; failure mode is operator inconvenience (rejected commit), not user-facing data exposure or workflow loss.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1.** New file `scripts/agents-payload-bytes.sh` defines a single function `compute_b_always` that prints `<index_bytes>\t<core_bytes>\t<sum>` (tab-delimited, single line). All three callers source it: (a) new pre-commit hook, (b) compound `SKILL.md` step 8 (replacing inline computation), (c) `.github/workflows/scheduled-compound-promote.yml` (replacing inline computation). Verified via `grep -nE 'wc -c.*AGENTS\.(md|core\.md)' scripts/ .github/workflows/ plugins/soleur/skills/compound/` returning ONLY the new library file (call sites use the function instead). Allowlisted exception: the rule-audit script may keep its own arithmetic since it audits a different scope.
- [ ] **AC2.** New file `scripts/lint-agents-rule-budget.sh` (executable, `#!/usr/bin/env bash`, `set -euo pipefail`) that:
  - sources `scripts/agents-payload-bytes.sh` (no inline `wc`)
  - rejects (`exit 1` + `::error::` annotation) when `B_ALWAYS > 22000`
  - warns (`exit 0` + `::warning::` annotation) when `B_ALWAYS > 20000` AND `B_ALWAYS ≤ 22000`
  - exits 0 silently when `B_ALWAYS ≤ 20000`
  - thresholds are sourced from env-var overrides `AGENTS_BUDGET_CRITICAL_BYTES` (default 22000) and `AGENTS_BUDGET_WARN_BYTES` (default 20000) so test fixtures can drive both branches without editing the script
- [ ] **AC3.** `scripts/lint-agents-enforcement-tags.py` gains a `--check-anchors` flag (default-off). When set, for each `[skill-enforced: <segment>(, <segment>)*]` tag, the script:
  - Splits `<rest>` on `,` (whitespace-tolerant) into segments
  - For each segment, the FIRST whitespace-delimited token is the skill name; remaining tokens form the anchor substring
  - For the FIRST segment only, the skill name comes from the `[skill-enforced: <skill>` parse (existing behavior preserved)
  - For subsequent segments, the first token IS the skill name (e.g., `plan Phase 2.6` → skill=`plan`, anchor=`Phase 2.6`)
  - Asserts `plugins/soleur/skills/<skill>/SKILL.md` exists (existing check)
  - Asserts `grep -F '<anchor>' plugins/soleur/skills/<skill>/SKILL.md` returns ≥1 match
  - Allowlist: ids listed in `scripts/agents-anchor-ignore.txt` (one segment per line: `<skill> <anchor>`) skip the grep check (legitimate trims, agent-name pointers that drifted, etc.)
  - Errors are rendered with file:line + segment + suggested-fix line ("update tag, rename anchor in skill, or add to scripts/agents-anchor-ignore.txt")
- [ ] **AC4.** `lefthook.yml` `pre-commit:` block gains 2 new commands at priority 5 (alongside `agents-enforcement-tag-lint`):
  - `agents-rule-budget`: glob `["AGENTS.md", "AGENTS.core.md"]`, runs `bash scripts/lint-agents-rule-budget.sh`
  - `agents-skill-enforced-anchor`: glob `["AGENTS.md", "AGENTS.core.md", "AGENTS.docs.md", "AGENTS.rest.md", "scripts/lint-agents-enforcement-tags.py", "plugins/soleur/skills/**/SKILL.md", "scripts/agents-anchor-ignore.txt"]`, runs `python3 scripts/lint-agents-enforcement-tags.py --check-anchors AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md`
- [ ] **AC5.** `scripts/agents-anchor-ignore.txt` exists (initially empty except for header comment matching the `scripts/retired-rule-ids.txt` format style). The file MUST be linted by `lint-agents-enforcement-tags.py` to enforce: each line is `<skill> <anchor>` OR `# comment` OR blank; skill name MUST resolve to a real `plugins/soleur/skills/<skill>/SKILL.md` (otherwise the allowlist itself becomes a silent rot surface).
- [ ] **AC6.** Test file `scripts/lint-agents-rule-budget.test.sh` (bash, follows `scripts/compound-promote.test.sh` test-runner style) covers 3 fixture branches: (a) payload at 19,500 B → exit 0 silent, (b) payload at 21,000 B → exit 0 + warn annotation on stderr, (c) payload at 22,500 B → exit 1 + error annotation on stderr. Fixtures use synthetic AGENTS.md / AGENTS.core.md files in a tempdir with env-var overrides on the threshold to drive each branch.
- [ ] **AC7.** Test file `scripts/lint-agents-enforcement-tags.test.sh` (bash) covers 4 fixture branches for the `--check-anchors` flag: (a) tag with single-skill resolved anchor → pass, (b) tag with multi-skill comma-separated anchors all resolved → pass, (c) tag with one dangling segment → fail with descriptive error naming the segment, (d) dangling segment listed in `scripts/agents-anchor-ignore.txt` → pass.
- [ ] **AC8.** `scripts/test-all.sh` runs both new `*.test.sh` files. **Deepen-pass correction:** `test-all.sh` is an EXPLICIT `run_suite "<label>" <cmd>` list (lines 52-68) — it does NOT auto-discover from a glob. Add explicit `run_suite "scripts/lint-agents-rule-budget" bash scripts/lint-agents-rule-budget.test.sh` and `run_suite "scripts/lint-agents-enforcement-tags" bash scripts/lint-agents-enforcement-tags.test.sh` lines next to the other `tests/scripts/...` entries (line range 57-62). Note: line 71-74 of `test-all.sh` DOES auto-discover `plugins/soleur/test/*.test.sh` — placing the new tests there is an alternative, but they would be physically distant from the scripts they exercise; explicit lines are clearer.
- [ ] **AC9.** Warn-threshold update propagates across **all four surfaces** (deepen-pass found AGENTS.docs.md as a fourth threshold-source not in the original plan):
  - `plugins/soleur/skills/compound/SKILL.md:220` advisory output text → `(warn > 20000 / critical > 22000)`
  - `plugins/soleur/skills/compound/SKILL.md:226` advisory branch threshold → `if (( B_ALWAYS > 20000 ))`
  - `AGENTS.docs.md:6` rule body text → `Targets: always-loaded payload ≤20000 warn / ≤22000 critical.`
  - `scripts/lint-agents-rule-budget.sh` defaults → `AGENTS_BUDGET_WARN_BYTES=20000`
  - Cross-file consistency check at /work Phase 4: `grep -nE '18000|22000|20000' AGENTS.docs.md plugins/soleur/skills/compound/SKILL.md scripts/lint-agents-rule-budget.sh scripts/lib/agents-payload-bytes.sh .github/workflows/scheduled-compound-promote.yml` MUST show `20000` warn at all warn sites and `22000` critical at all critical sites; no stray `18000` left behind.

  Also: inline `B_INDEX`/`B_CORE`/`B_ALWAYS` computation in compound `SKILL.md:207-209` (and the same expressions inline in step 8 prose) replaced with sourcing of `scripts/lib/agents-payload-bytes.sh`.
- [ ] **AC10.** `.github/workflows/scheduled-compound-promote.yml:148-160` and `:198-203` inline byte computations replaced with sourcing of `scripts/agents-payload-bytes.sh` (the workflow file already runs in a checkout that contains `scripts/`; the existing `wc -c` lines become `source scripts/agents-payload-bytes.sh; ...; ALWAYS_LOADED_BYTES=$(compute_b_always | cut -f3)`).
- [ ] **AC11.** Manual reproduction script (committed under `scripts/` or referenced inline in PR body) demonstrates the hook firing on a synthetic AGENTS.core.md edit that pushes payload past 22 k and rejecting the commit with a one-line `::error::` message naming the byte delta over cap.
- [ ] **AC12.** All existing AGENTS linters continue to pass (`python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt --index-file AGENTS.md AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` and `python3 scripts/lint-agents-enforcement-tags.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` without `--check-anchors` for backward-compat with the existing lefthook command). The `--check-anchors` invocation passes against the post-AC15-migration state of `AGENTS.{md,core.md,docs.md,rest.md}`. See AC15 for the migration that makes this satisfiable.

- [ ] **AC15 (NEW from deepen-pass).** Live-state anchor migration in the same PR. Deepen-pass per-segment scan found 10 of 21 existing `[skill-enforced:]` segments dangling under naive substring semantics. The `--check-anchors` flag is meaningless until those 10 are resolved. For each of the 10 dangling segments documented in the table below, choose ONE remediation:

  | # | File:Line | Skill | Anchor | Default remediation (override only with rationale comment) |
  |---|---|---|---|---|
  | 1 | `AGENTS.core.md:26` | plan | `Phase 1.4` | Update tag to `1.4 Network-Outage Hypothesis Check` (verbatim substring of skill heading `### 1.4. Network-Outage Hypothesis Check`). |
  | 2 | `AGENTS.core.md:29` | plan | `Phase 2.6` | Update tag to `2.6 User-Brand Impact` (verbatim substring of skill heading). |
  | 3 | `AGENTS.core.md:29` | deepen-plan | `Phase 4.6` | Update tag to `4.6 User-Brand Impact Halt` (verbatim substring of skill heading `### 4.6. User-Brand Impact Halt (Always)`). |
  | 4 | `AGENTS.core.md:32` | work | `Phase 0 Type-widening cross-consumer grep` | Verify whether work/SKILL.md §Phase 0 contains the substring `Type-widening cross-consumer grep` (per #3681 it should — the bullet was added in the same PR). If not, allowlist with rationale. |
  | 5 | `AGENTS.core.md:33` | work | `Phase 0 Write-boundary sentinel sweep` | Same as above — verify substring presence; allowlist if descriptive prose. |
  | 6 | `AGENTS.core.md:40` | ship | `Phase 5.5 Retroactive Gate Application` | Verify substring presence in ship/SKILL.md. |
  | 7 | `AGENTS.docs.md:6` | compound | `step 8 (Why-line trim semantics + loader-class-fit)` | Allowlist (descriptive prose pointing to the 8th numbered item under `## Phase 1.5`; the `(Why-line trim semantics + loader-class-fit)` is parenthetical commentary). One-line rationale: `# step 8 is the 8th numbered item under compound §Phase 1.5; parens are descriptive commentary not a substring`. |
  | 8 | `AGENTS.docs.md:7` | compound | `Route-Learning-to-Definition` | Update compound/SKILL.md to add a heading or sub-bullet text containing the literal `Route-Learning-to-Definition` (the route IS in compound but uses different prose), OR allowlist. Prefer the skill-side fix — this anchor is the placement-gate router and the literal name should be discoverable. |
  | 9 | `AGENTS.rest.md:5` | work | `Phase 2 TDD Gate` | Verify work/SKILL.md §Phase 2 names a "TDD Gate" subsection. If not, update tag to verbatim heading. |
  | 10 | `AGENTS.rest.md:29` | ship | `Phase 5.5 Review-Findings Exit Gate` | Verify ship/SKILL.md §Phase 5.5 has a "Review-Findings Exit Gate" subsection. |

  **Migration order at /work time:** First, for each row, run `grep -F '<anchor>' plugins/soleur/skills/<skill>/SKILL.md`. If it returns ≥1 match, no action needed (deepen-pass probe was wrong on that segment — possible if grep -F semantics differ from Python's `in` for unicode/whitespace edge cases). If 0 matches, apply the default remediation. Document each decision in a one-line PR-body table so reviewers can audit.

  **Allowlist policy:** The allowlist is a last resort — every entry MUST cite the load-bearing reason the anchor cannot be made literal. Future allowlist additions go through the same gate.

### Post-merge (operator)

- [ ] **AC13.** Open a fresh shell in a fresh checkout, `git commit --allow-empty -m "test"` succeeds (no false-fire on commits that don't touch AGENTS files — verifies lefthook glob filtering).
- [ ] **AC14.** Add a deliberate dangling segment to a `[skill-enforced: ...]` tag in a throwaway branch, attempt `git commit`, verify rejection with a precise error message; then add to `scripts/agents-anchor-ignore.txt` and verify the commit lands.

## Files to Create

- `scripts/lib/agents-payload-bytes.sh` — single source of truth for `B_ALWAYS` computation. Defines `compute_b_always()` which prints `<index>\t<core>\t<sum>` from CWD-resolved `AGENTS.md` and `AGENTS.core.md`. Honors `AGENTS_INDEX_PATH` and `AGENTS_CORE_PATH` env-var overrides for test fixtures. **Pure-source library (no `+x`)** — sourced via `source "$(dirname "${BASH_SOURCE[0]}")/lib/agents-payload-bytes.sh"` from callers; matches existing `scripts/lib/rule-metrics-constants.sh` and `scripts/lib/strip-log-injection.sh` convention. Uses `# shellcheck shell=bash` directive at top (no shebang).
- `scripts/lint-agents-rule-budget.sh` — pre-commit hook implementing AC2.
- `scripts/lint-agents-rule-budget.test.sh` — fixture-driven test for AC6.
- `scripts/lint-agents-enforcement-tags.test.sh` — fixture-driven test for AC7.
- `scripts/agents-anchor-ignore.txt` — anchor-allowlist with `# comment | blank | <skill> <anchor>` line shape per AC5. Initially populated with header comment ONLY (no allowlist entries until a real legitimate-trim case arises).

## Files to Edit

- `lefthook.yml` — add `agents-rule-budget` and `agents-skill-enforced-anchor` commands at priority 5 (AC4). Path-array glob form per `2026-03-21-lefthook-gobwas-glob-double-star.md`.
- `scripts/lint-agents-enforcement-tags.py` — add `--check-anchors` flag, multi-skill segment parser, allowlist consultation, allowlist-self-validation (AC3, AC5).
- `scripts/test-all.sh` — explicit `run_suite` lines for the two new bash tests (per AC8 deepen-pass correction; the runner is an explicit list, not a glob discovery).
- `plugins/soleur/skills/compound/SKILL.md` — replace inline byte computation with sourced library function; update warn threshold 18 k → 20 k at lines 220 and 226 (AC9).
- `AGENTS.docs.md` — line 6 (`cq-agents-md-why-single-line` rule body): update threshold prose `≤18000 warn` → `≤20000 warn` to keep this 4th threshold-source surface in sync (AC9). Also: line 6 anchor-tag (`step 8 (Why-line trim semantics + loader-class-fit)`) and line 7 anchor-tag (`Route-Learning-to-Definition`) per AC15 row 7 + 8 — allowlist OR migrate to literal substrings.
- `AGENTS.core.md` — anchor-tag rewrites per AC15 rows 1-6 (lines 26, 29, 32, 33, 40). Body-byte cost: each rewrite is byte-neutral (replaces same-length anchor strings); confirm via `wc -c AGENTS.core.md` after edits to ensure always-loaded payload stays ≤22,000 B.
- `AGENTS.rest.md` — anchor-tag rewrites per AC15 rows 9-10 (lines 5, 29). No always-loaded byte impact (rest sidecar is class-loaded only).
- `.github/workflows/scheduled-compound-promote.yml` — replace inline byte computation with sourced library function (AC10). Note: workflow may need a `chmod +x scripts/lib/agents-payload-bytes.sh` step OR the library should be pure-source (no executable bit required when `source`d). Plan picks pure-source (matches the existing `scripts/lib/rule-metrics-constants.sh` and `scripts/lib/strip-log-injection.sh` convention — neither is `+x`).

## Implementation Phases

### Phase 0: Preflight + Test Scaffold (TDD RED)

1. Read every line of `scripts/lint-rule-ids.py`, `scripts/lint-agents-enforcement-tags.py`, `lefthook.yml` (already done in plan-research; re-read at /work time per `hr-always-read-a-file-before-editing-it`).
2. Run `bash scripts/test-all.sh` to confirm baseline-green and to verify the test runner's discovery pattern (`find` glob shape).
3. Write `scripts/lint-agents-rule-budget.test.sh` (RED — fails because the script doesn't exist yet).
4. Write `scripts/lint-agents-enforcement-tags.test.sh` (RED — fails because `--check-anchors` doesn't exist yet).
5. Confirm both new tests fail with the expected RED reason.

### Phase 1: Shared Library Extraction

1. Write `scripts/lib/agents-payload-bytes.sh` (single function, env-var-overridable paths).
2. Update `plugins/soleur/skills/compound/SKILL.md` step 8 to source the library (NOT inline `wc -c`); update warn threshold 18 k → 20 k.
3. Update `.github/workflows/scheduled-compound-promote.yml` two byte-computation sites to source the library.
4. Verify all three callers produce identical output for a fixed AGENTS payload.

### Phase 2: Rule-Budget Hook (GREEN)

1. Implement `scripts/lint-agents-rule-budget.sh` per AC2.
2. Run the test from Phase 0; iterate until GREEN.
3. Wire into `lefthook.yml` per AC4.
4. Manual repro: `git commit --allow-empty` on a clean tree → exit 0 silent (no AGENTS file staged).
5. Manual repro: stage a 600 B addition to `AGENTS.core.md`, commit → expect exit 0 + warn annotation (payload now ~22.6 k? — depends on current); iterate threshold env-vars to drive both branches deterministically.

### Phase 3: Anchor-Parity Check + Live-State Migration (GREEN)

1. Extend `scripts/lint-agents-enforcement-tags.py` with `--check-anchors` flag, multi-skill segment parser, and allowlist consultation per AC3.
2. Add `scripts/agents-anchor-ignore.txt` with header comment matching `scripts/retired-rule-ids.txt` style.
3. Add allowlist self-validation (AC5: every `<skill>` in allowlist resolves to a real SKILL.md).
4. Run the test from Phase 0; iterate until GREEN.
5. Wire `--check-anchors` flag into the new `agents-skill-enforced-anchor` lefthook command per AC4.
6. **Live-state migration (AC15).** Run `python3 scripts/lint-agents-enforcement-tags.py --check-anchors AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` against the live repo. Expected at this point: ~10 dangling segments per the deepen-pass probe. For each dangling segment, apply the default remediation from AC15's table. Re-run after each batch. Iterate until exit 0.
7. Capture the per-segment migration decisions in a PR-body table for reviewer audit.
8. Do NOT add `--check-anchors` to the existing `agents-enforcement-tag-lint` lefthook command — keep that one in its current contract for backward-compat. The NEW `agents-skill-enforced-anchor` command is the parity check's enforcement surface.

### Phase 4: Verification Sweep + AC11 Reproduction

1. Run `bash scripts/test-all.sh` end-to-end; assert all 3 AGENTS-related linters + both new tests + the existing 38 plugin test suites are green.
2. Stage a `[skill-enforced: nonexistent-skill Phase 99]` edit to `AGENTS.core.md`, attempt `git commit`, verify rejection with a precise error message naming the dangling segment. Revert the staged edit.
3. Stage an AGENTS.core.md addition that pushes B_ALWAYS past 22 k, attempt commit, verify rejection with byte-delta error. Revert.
4. Capture both reproductions in the PR body for reviewer verification.

### Phase 5: Multi-Agent Plan Review + Ship

1. Plan-review (DHH + Kieran + code-simplicity) — see "Plan Review" output.
2. /work executes Phases 0-4 above.
3. /review on the PR diff.
4. /ship.

## Sharp Edges

- **Threshold drift across surfaces.** This plan introduces a shared library specifically to prevent the `B_ALWAYS` formula from re-drifting across compound, the cron workflow, and the new pre-commit hook. The 20 k / 22 k thresholds are NOT in the shared library — they are owned by each caller's policy (compound is advisory, the hook is load-bearing). Future authors must keep all four threshold call-sites (compound `SKILL.md:226`/`:227`, the new `lint-agents-rule-budget.sh` defaults, the cron workflow's `MAX_ALWAYS_LOADED_BYTES`) in sync OR migrate the threshold itself to a config file — but moving the formula was the higher-ROI fix per the rule-budget incident class.
- **`--no-verify` still bypasses.** Per `lefthook.yml` precedent for `gitleaks-staged` ("Bypass with `git commit --no-verify` is intentionally possible — CI re-scans on every PR"), this hook is a fast-feedback gate, not a load-bearing CI floor. The existing CI gate at `.github/workflows/rule-audit.yml` (bi-weekly) and `.github/workflows/scheduled-compound-promote.yml` (post-apply revert) remain the load-bearing floors. The plan does NOT add a `pull_request`-triggered CI workflow because the cron post-apply revert already covers the LLM-generated rule-edit class, and the only remaining surface is direct operator commits — for which `--no-verify` is the operator's explicit ack.
- **Allowlist-as-rot-surface.** The `scripts/agents-anchor-ignore.txt` allowlist will accumulate entries over time as legitimate trims happen. Without periodic review, dead entries (allowlisted segment that has since been re-anchored or whose tag has been removed) become silent rot. AC5's allowlist-self-validation catches the simplest class (skill no longer exists), but does NOT catch "anchor was re-added to skill, allowlist no longer needed." Defer this scrubbing to a future cron / quarterly-review job — out of scope for this PR.
- **Multi-skill tag parser fragility.** The segment parser splits on `,` — a future tag containing a `,` inside an anchor string (e.g., `Phase 5.5, Step 3`) would mis-parse. Today no such tag exists (verified at plan-write time via `grep -F ',' AGENTS*.md | grep -F 'skill-enforced'`). Add a Sharp Edges entry to `scripts/lint-agents-enforcement-tags.py`'s docstring noting the parse contract: anchor segments MUST NOT contain `,`. If a future anchor needs a comma, switch the segment delimiter to `;` (and update both the parser and the AGENTS tag-style guidance in `cq-agents-md-tier-gate`'s body).
- **Empty-payload edge case.** `wc -c` on a missing file errors; the shared library uses the existing `2>/dev/null || echo 0` pattern from compound. If `AGENTS.core.md` is renamed/removed in the future, the hook silently treats core as 0 bytes — the rule-id residency linter would catch the actual rename, so the silent-zero is not a load-bearing failure.
- **Plan whose `## User-Brand Impact` is empty/TBD will fail `deepen-plan` Phase 4.6 (per the framework convention).** This plan declares `Brand-survival threshold: none, reason: ...` per the convention.
- **Anchor-notation contract for `[skill-enforced: <skill> <anchor>]` tags going forward.** The `<anchor>` segment MUST be a verbatim substring of the named skill's SKILL.md file. Rationale: that is the literal contract `--check-anchors` verifies via `grep -F`. Examples: `[skill-enforced: plan 1.4 Network-Outage]` (substring of `### 1.4. Network-Outage Hypothesis Check`) ✓; `[skill-enforced: plan Phase 1.4]` (no `Phase` prefix in skill body) ✗ unless the skill heading is updated to `### Phase 1.4.`. For irreducibly-descriptive references (e.g., "the 8th numbered item under §Phase 1.5"), allowlist via `scripts/agents-anchor-ignore.txt` with one-line rationale — but every allowlist entry is a future-rot surface, so prefer literal substrings.
- **Threshold-source drift across four surfaces.** AC9 enumerates four sites that name the warn threshold (compound `SKILL.md:220`, compound `SKILL.md:226`, AGENTS.docs.md:6, new `lint-agents-rule-budget.sh`). A future tweak that changes the threshold MUST update all four. Out-of-scope to consolidate today (would require a 5th file `scripts/lib/agents-budget-constants.sh` with `WARN_BYTES`/`CRITICAL_BYTES` exports, and an AGENTS.docs.md rewrite to reference the constant by name not value — both add complexity beyond this PR's scope). Track as Sharp Edge for future authors.

## Test Strategy

- **bash fixture tests** (`scripts/lint-agents-rule-budget.test.sh`, `scripts/lint-agents-enforcement-tags.test.sh`) follow the `scripts/compound-promote.test.sh` runner style: `set -euo pipefail`, `make_fixture()` builds a tempdir with synthetic AGENTS files, env-var overrides drive each test branch, `pass`/`fail` counters with summary line, EXIT trap cleans up.
- **No new test framework dependency.** The repo already runs `bash *.test.sh` files via `scripts/test-all.sh`; verified at plan-write time by inspection.
- **Manual reproductions captured in PR body** per AC11 + AC13 + AC14 — these double as the operator-runbook for "how do I demonstrate the hook works."

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — tooling-only change to local pre-commit gate. No Product/UX surface (no user-facing artifact). No CLO concern (no regulated-data surface; no terms-of-use change). No CTO architecture concern beyond the established AGENTS-byte-budget pattern. No CFO/CMO/CRO/COO concern.

## Open Code-Review Overlap

Run at plan-write time:

```bash
gh issue list --label code-review --state open \
  --json number,title,body --limit 200 > /tmp/open-review-issues.json
for f in scripts/lint-agents-enforcement-tags.py scripts/lint-rule-ids.py lefthook.yml \
         plugins/soleur/skills/compound/SKILL.md \
         .github/workflows/scheduled-compound-promote.yml; do
  jq -r --arg path "$f" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' \
    /tmp/open-review-issues.json
done
```

Result: None matching at plan-write time. Will re-run at /work Phase 0.

## Compliance Tier Gate

`/soleur:gdpr-gate` not invoked: this plan does not touch regulated-data surfaces per the canonical regex (no `*.sql`, no `lib/auth/`, no `app/api/`, no migration). None of the (a)-(d) extension triggers fire (no LLM-bound processing on operator data, threshold `none`, no new cron, no new artifact distribution surface beyond local hook scripts). Skipping silently per `hr-gdpr-gate-on-regulated-data-surfaces`.

## Why Now

PR #3681 trimmed the always-loaded payload from 24,622 B to 21,985 B with **15 B of headroom** under the 22 k harness performance ceiling. At the documented growth rate (~700 B/day per the #3681 plan §Out of Scope item 2), the cap re-trips between 1 and 13 days post-merge of #3681. Waiting for the next breach to land on the cron post-apply revert path leaks the pattern: operator commits to AGENTS that push past the cap will land on `main` first and revert later (or worse — the cron is gated by promotion-config opt-in, so operator-direct commits NEVER hit the revert path). The pre-commit hook is the gate this load-bearing budget needs.

## Out of Scope

- **Constitution.md byte cap.** Out of scope. The 300-rule advisory in compound `SKILL.md:230` is informational; constitution.md does not load every turn.
- **Per-rule byte cap (`> 600 B`) enforcement at commit time.** Out of scope per the issue body (it lists "per-rule byte cap" and "always-loaded total" both, but the primary rejection is the always-loaded total — the per-rule cap is enforced advisorily by `cq-agents-md-why-single-line` itself which is human-followed at edit time). Defer to a future iteration if rule-bloat re-emerges as a class.
- **Anchor parity for `[hook-enforced:]` tags.** Out of scope. The existing `lint-agents-enforcement-tags.py` already resolves hook-enforced tags via path/lefthook lookup; no parity gap was named in the PR #3681 review.
- **Migrating the 22 k threshold itself to a config file.** Out of scope; threshold ownership lives at each caller per the Sharp Edges note.
- **Periodic scrubbing of `scripts/agents-anchor-ignore.txt`.** Out of scope; defer to future cron / quarterly-review job. Will file a tracking issue if the file accumulates ≥3 entries in the first 30 days post-merge.

## Deferral Tracking

No deferred items requiring tracking issues — the four "Out of Scope" items above are either (a) advisory-only existing surfaces, (b) covered by adjacent existing gates, or (c) anticipated-rare future-iteration triggers with clear re-evaluation criteria stated inline.
