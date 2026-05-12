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
| "Warns at 20,000 B" | Existing compound advisory uses **18,000** B for warn (`SKILL.md:226`) and **22,000** B for critical (`SKILL.md:227`). The cron workflow uses 22 k as the hard cap. Issue says 20 k warn — drift from existing convention. | Plan defaults to **20,000 B warn / 22,000 B critical** per the issue body (closer to the cap so warn fires before commit-rejection becomes likely), and updates compound `SKILL.md:226` warn threshold from 18 k → 20 k in the SAME PR for symmetry. The 18 k threshold was set when payload was 12 k; with payload at 21,985 B today, an 18 k warn fires every commit — useless. CPO sign-off not required (cosmetic threshold delta on advisory output; load-bearing 22 k cap is unchanged). |

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
- [ ] **AC8.** `scripts/test-all.sh` discovers and runs both new `*.test.sh` files (verify by tailing `scripts/test-all.sh` output for the test-file names; if the runner pattern is `find scripts -name '*.test.sh'`, no edit is needed — verify at plan-write time).
- [ ] **AC9.** `compound/SKILL.md:226` warn threshold updated from `> 18000` to `> 20000` to match the new lefthook warn threshold; `compound/SKILL.md:220` advisory output text updated to match (`warn > 20000 / critical > 22000`); inline `B_INDEX`/`B_CORE`/`B_ALWAYS` computation in step 8 (lines 207-209) replaced with sourcing of `scripts/agents-payload-bytes.sh`.
- [ ] **AC10.** `.github/workflows/scheduled-compound-promote.yml:148-160` and `:198-203` inline byte computations replaced with sourcing of `scripts/agents-payload-bytes.sh` (the workflow file already runs in a checkout that contains `scripts/`; the existing `wc -c` lines become `source scripts/agents-payload-bytes.sh; ...; ALWAYS_LOADED_BYTES=$(compute_b_always | cut -f3)`).
- [ ] **AC11.** Manual reproduction script (committed under `scripts/` or referenced inline in PR body) demonstrates the hook firing on a synthetic AGENTS.core.md edit that pushes payload past 22 k and rejecting the commit with a one-line `::error::` message naming the byte delta over cap.
- [ ] **AC12.** All existing AGENTS linters continue to pass (`python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt --index-file AGENTS.md AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` and `python3 scripts/lint-agents-enforcement-tags.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` without `--check-anchors` for backward-compat with the existing lefthook command). The `--check-anchors` invocation passes against the current state of `AGENTS.{md,core.md,docs.md,rest.md}` — i.e., NO existing `[skill-enforced:]` tag in the repo today is dangling. If any pre-existing tag fails the new check, EITHER fix the tag in the same PR OR add it to `scripts/agents-anchor-ignore.txt` with a one-line comment naming the rationale.

### Post-merge (operator)

- [ ] **AC13.** Open a fresh shell in a fresh checkout, `git commit --allow-empty -m "test"` succeeds (no false-fire on commits that don't touch AGENTS files — verifies lefthook glob filtering).
- [ ] **AC14.** Add a deliberate dangling segment to a `[skill-enforced: ...]` tag in a throwaway branch, attempt `git commit`, verify rejection with a precise error message; then add to `scripts/agents-anchor-ignore.txt` and verify the commit lands.

## Files to Create

- `scripts/lib/agents-payload-bytes.sh` — single source of truth for `B_ALWAYS` computation. Defines `compute_b_always()` which prints `<index>\t<core>\t<sum>` from CWD-resolved `AGENTS.md` and `AGENTS.core.md`. Honors `AGENTS_INDEX_PATH` and `AGENTS_CORE_PATH` env-var overrides for test fixtures.
- `scripts/lint-agents-rule-budget.sh` — pre-commit hook implementing AC2.
- `scripts/lint-agents-rule-budget.test.sh` — fixture-driven test for AC6.
- `scripts/lint-agents-enforcement-tags.test.sh` — fixture-driven test for AC7.
- `scripts/agents-anchor-ignore.txt` — anchor-allowlist with `# comment | blank | <skill> <anchor>` line shape per AC5. Initially populated with header comment ONLY (no allowlist entries until a real legitimate-trim case arises).

## Files to Edit

- `lefthook.yml` — add `agents-rule-budget` and `agents-skill-enforced-anchor` commands at priority 5 (AC4). Path-array glob form per `2026-03-21-lefthook-gobwas-glob-double-star.md`.
- `scripts/lint-agents-enforcement-tags.py` — add `--check-anchors` flag, multi-skill segment parser, allowlist consultation, allowlist-self-validation (AC3, AC5).
- `plugins/soleur/skills/compound/SKILL.md` — replace inline byte computation with sourced library function; update warn threshold 18 k → 20 k (AC9).
- `.github/workflows/scheduled-compound-promote.yml` — replace inline byte computation with sourced library function (AC10).

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

### Phase 3: Anchor-Parity Check (GREEN)

1. Extend `scripts/lint-agents-enforcement-tags.py` with `--check-anchors` flag, multi-skill segment parser, and allowlist consultation per AC3.
2. Add `scripts/agents-anchor-ignore.txt` with header comment.
3. Add allowlist self-validation (AC5: every `<skill>` in allowlist resolves to a real SKILL.md).
4. Run the test from Phase 0; iterate until GREEN.
5. Wire `--check-anchors` flag into the new `agents-skill-enforced-anchor` lefthook command per AC4.
6. Run `python3 scripts/lint-agents-enforcement-tags.py --check-anchors AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` against the live repo state. Expected: exit 0 (no dangling segments). If any tag fails, choose: (a) fix the anchor in the named skill, (b) update the AGENTS tag to a current anchor, or (c) add to allowlist with rationale comment. Do NOT add the existing lefthook `agents-enforcement-tag-lint` `--check-anchors` flag — keep that one in its current contract for the same backward-compat reason; the NEW `agents-skill-enforced-anchor` command is the parity check's enforcement surface.

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
