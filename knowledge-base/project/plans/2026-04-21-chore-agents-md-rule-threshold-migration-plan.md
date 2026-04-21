---
title: Raise AGENTS.md rule threshold + prove skill-migration pattern
type: chore
date: 2026-04-21
issue: 2686
branch: feat-agents-rule-threshold
pr: 2754
brainstorm: knowledge-base/project/brainstorms/2026-04-21-agents-md-rule-threshold-brainstorm.md
spec: knowledge-base/project/specs/feat-agents-rule-threshold/spec.md
---

# Raise AGENTS.md rule threshold + prove skill-migration pattern

## Overview

`AGENTS.md` is at **106 rules** / **36,566 bytes** as of 2026-04-21 — 6 over the 100-rule warn threshold in `cq-agents-md-why-single-line` (compound step 8). Every compound run fires `[WARNING] rule count (106/100) exceeded`. This PR silences the warn by raising the threshold to **115** (not 120 — preserves pressure) AND uses the opportunity to exercise the threshold rule's own guidance ("move skill-specific rules to the skills that enforce them") by migrating 3 rules tagged `[hook-enforced: ...]` / `[skill-enforced: ...]` to their owning skill/hook. The migration uses the **pointer-preservation pattern** dictated by `lint-rule-ids.py` and records the pattern so future migrations are cheaper.

This is the **first attempt at AGENTS.md rule retirement since `lint-rule-ids.py` shipped** (PR #2213, 2026-04-14). No historical retirement precedent exists post-aggregator — this PR establishes one.

## Research Reconciliation — Spec vs. Codebase

The spec at `knowledge-base/project/specs/feat-agents-rule-threshold/spec.md` was written from brainstorm context before the deep research pass. Two claims need reconciliation:

| Spec claim | Codebase reality (verified 2026-04-21) | Plan response |
|---|---|---|
| **FR5:** "`gh run list --workflow rule-metrics-aggregate.yml --limit 5` is invoked. If zero successful runs, file a follow-up issue." | Aggregator **is firing**. Last scheduled run 2026-04-19 01:16 UTC succeeded (run 24617976419). Weekly PR pattern merges (#2595 on 2026-04-18). `rule-metrics.json` present on main (`generated_at: 2026-04-18T15:33:58Z`). | **FR5 satisfied by research.** Task is reduced to a verification step; no follow-up issue is filed. Plan records the last-run SHA in a comment so future audits can re-verify. |
| **FR4:** `grep -c '^- ' AGENTS.md` ≤ 103. | `lint-rule-ids.py` L65–80 hard-fails on any `[id: ...]` removed from HEAD. **Full removal blocked** until allowlist lands. Pointer-preservation is hook-compatible but count-flat. | **FR4 relaxed** to "count flat AND bytes ≥ 800 saved." Allowlist filed as single follow-up issue. |

Spec is updated with strikethrough + replacement for FR4 (not a sidecar `[Updated]` note) so future readers see one canonical version.

## Open Code-Review Overlap

Check ran against `plugins/soleur/skills/{compound,work,pencil-setup,ship}/SKILL.md`, `AGENTS.md`, `plugins/soleur/hooks/browser-cleanup-hook.sh`, `.claude/hooks/pencil-open-guard.sh`, `scripts/lint-rule-ids.py` via `gh issue list --label code-review --state open --json number,title,body --limit 200` + per-path `jq` filter.

| Match | Disposition |
|---|---|
| #2686 (this issue) | Self. |
| #2594 (chat-sidebar flake) | Only cites an AGENTS.md rule-id (`wg-when-tests-fail-and-are-confirmed-pre`) as context — not a file edit. **Not an overlap. Acknowledge only.** |

**Effective overlap: None.** No scope-out needs folding, acknowledgment, or deferral.

## Problem Statement / Motivation

1. **Compound step 8 warns every run** — `[WARNING] rule count (106/100) exceeded`. Noise desensitizes agents to real warnings (learning `2026-04-07-rule-budget-false-alarm-fix.md`).
2. **The 100-rule threshold was chosen when AGENTS.md had 58 rules** (learning `2026-04-07`, L23–25) — a ~1.7× headroom that proved too tight given each new rule cites a real incident (PRs + learning files). Every rule has a `[id: ...]` tag and most have a `**Why:** #NNNN — ...` pointer; they are not growth-for-growth's-sake.
3. **The threshold's original intent was "move skill-specific rules to the skills that enforce them"** (compound SKILL.md step 8, L205). That migration pattern has never been exercised. This PR proves it on 3 safe candidates.
4. **The aggregator + prune pipeline already exists** (PR #2213, refined in PR #2573) — it runs weekly, surfaces zero-hit-over-8w rules as GitHub issues, and is the long-term mechanism for keeping rule count accountable. Raising the threshold is *defensible* because the automated surface exists to regulate growth going forward.

## Proposed Solution

Single PR with four sequential phases executed on branch `feat-agents-rule-threshold` (worktree `.worktrees/feat-agents-rule-threshold/`, draft PR #2754):

1. **Preflight & measurement.** Capture baseline rule count, file bytes, longest rule, and aggregator status. Re-run at plan execution start (counts drift per learning `2026-04-06-rule-audit-budget-baseline-drift.md` — use variables, not absolute targets).
2. **Threshold raise** (100 → 115) in exactly two places: `AGENTS.md` line 81 and `plugins/soleur/skills/compound/SKILL.md` line 205. Both carry the same contract and must move together.
3. **Skill-migration pattern proof.** Migrate 3 candidate rules using the pointer-preservation pattern. For each: (a) move the full rule body to the owning skill/hook's own file, (b) leave a one-line pointer in AGENTS.md preserving the `[id: ...]` tag, (c) update any downstream call sites identified in the referenced-ID sweep.
4. **Verification + follow-up filing.** Re-measure; run `lefthook run pre-commit` on staged files; run `npx markdownlint-cli2 --fix` on the specific changed files (per `cq-markdownlint-fix-target-specific-paths` — not repo-wide); file follow-up issues for (i) `lint-rule-ids.py` retired-ids allowlist design, (ii) merged-id-tag pattern decision.

## Files to Edit

| Path | Edit |
|---|---|
| `AGENTS.md` | Update `cq-agents-md-why-single-line` threshold `>100` → `>115` and rewrite `**Why:**` annotation one-liner. Replace full bodies of 3 migrated rules with one-line pointers preserving `[id: ...]`. |
| `plugins/soleur/skills/compound/SKILL.md` | Step 8 (lines 196–208): change `A > 100` condition → `A > 115` and warning string `(A/100)` → `(A/115)`. Do NOT touch byte/per-rule thresholds (scope-out per spec). |
| `plugins/soleur/hooks/browser-cleanup-hook.sh` | Prepend a comment block above `set -euo pipefail` carrying full text of `cq-after-completing-a-playwright-task-call` including preserved `[id: ...]` token. Do NOT alter executable code — comment-only changes are behavior-preserving (precedent: plan `2026-04-06-chore-rule-audit-migration-plan.md` Phase 4). |
| `.claude/hooks/pencil-open-guard.sh` | Same pattern — header comment absorbs full text of `cq-before-calling-mcp-pencil-open-document`. Hook denial message already restates the rule; this migrates the prose to live with the enforcement. |
| `plugins/soleur/skills/pencil-setup/SKILL.md` | Add a section or augment existing Pencil MCP guidance with the migrated rule body referencing the hook. |
| `plugins/soleur/skills/work/SKILL.md` | Phase 2.5: absorb full text of `wg-when-a-research-sprint-produces` into the cascade-validate-loop instructions with preserved `[id: ...]` reference. |
| `knowledge-base/project/specs/feat-agents-rule-threshold/spec.md` | Strikethrough original FR4; append relaxed FR4 replacement. Mark FR5 as satisfied by research. |
| `lefthook.yml` | Wire new `lint-agents-compound-sync.sh` into pre-commit (`glob: "AGENTS.md,plugins/soleur/skills/compound/SKILL.md"`). |

## Files to Create

| Path | Purpose |
|---|---|
| `scripts/lint-agents-compound-sync.sh` | 5–8 line bash script: extract threshold literal from AGENTS.md L81 and compound SKILL.md L205; exit 1 if they disagree. Guards against future drift when someone edits one file but not the other. (Addresses architecture-review Major 1.) |
| `knowledge-base/project/learnings/2026-04-21-agents-md-rule-retirement-deprecation-pattern.md` | Deprecation breadcrumb for the 3 migrated rule IDs (required by `cq-rule-ids-are-immutable`). Documents the pointer-preservation pattern, cites `lint-rule-ids.py` constraint, records that no full-removal precedent exists post-aggregator, and notes the rejected merged-tag alternative with rationale. Also captures why 115 was chosen. |

## Technical Considerations

### Architecture impact

None. AGENTS.md and SKILL.md are agent-instruction surfaces, not runtime code. No API, schema, or data-model change. `lint-rule-ids.py` behavior is unchanged — the pointer pattern is deliberately chosen to be hook-compatible.

### Why 115 (not 120, not 110)

Per learning `2026-04-18-agents-md-byte-budget-and-why-compression.md` L39 and the per-rule-byte cap precedent (500 → 600 in PR #2544): pick a threshold above the growth tail, not a round number. Current count is 106. Monthly growth trajectory since 2026-02-25 (foundational lean-AGENTS.md learning) has been ~5–8 rules/month driven by PR citations. 115 provides ~9 rules of headroom (~1.5 months at current rate), aligns with a "modest, not blanket" signal the brainstorm agreed on, and leaves space for the 3 pointer-migrated rules to remain counted (pointers don't reduce count under the hook's current behavior). 120 was rejected as a blanket pass; 110 was rejected as too tight given the 3-rule pointer-preservation math.

### Why pointer-preservation (not merged-tag or hook amendment) in this PR

- **Merged-tag pattern** (append retiring id to an adjacent rule's line) would reduce count to 103, satisfying spec FR4 as originally written, but introduces an unprecedented pattern that visually conflates two rule texts. No review has vetted this convention.
- **`lint-rule-ids.py` amendment** to support a retired-ids allowlist is the most principled long-term fix but materially expands PR scope (script edit, test-hook coverage, allowlist file format decision). File as follow-up.
- **Pointer preservation** is the minimum-risk path that (a) exercises the migration pattern, (b) reduces AGENTS.md bytes by an estimated 800–1,200 (moving ~300–400 byte rule bodies out, replacing with ~80–120 byte pointers), (c) requires zero hook changes, (d) leaves each id string grep-able in AGENTS.md.

### Security / NFR

No user-facing surface. No NFR register entry needed. No security consideration.

### Downstream reference integrity

Per research finding E, each of the 3 migrated rule IDs has external call sites (`plans/`, `specs/`, `rule-metrics.json`, test files). All are read-only string references; the pointer preserves the `[id: ...]` tag in AGENTS.md so grep-based references remain findable. No external edits are required.

Per learning `2026-04-15-rule-utility-scoring-telemetry-patterns.md` L162–171, `.claude/hooks/lib/incidents.sh` is the place rule IDs may be emitted as telemetry strings. Run `rg -n '<id>' .claude/hooks/ tests/ scripts/ knowledge-base/project/rule-metrics.json` for each migrated id during Phase 3 — if any hook file emits the id, no change is needed (the id still resolves in AGENTS.md pointer), but document the fact in the learning file.

## Implementation Phases

### Phase 1 — Preflight & Measurement

Target environment: `.worktrees/feat-agents-rule-threshold/`, branch `feat-agents-rule-threshold`.

1.1 Capture baseline (run from worktree root):

```bash
BASELINE_COUNT=$(grep -c '^- ' AGENTS.md)
BASELINE_BYTES=$(wc -c < AGENTS.md)
BASELINE_LONGEST=$(grep '^- ' AGENTS.md | awk '{print length}' | sort -n | tail -1)
echo "baseline: rules=$BASELINE_COUNT bytes=$BASELINE_BYTES longest=$BASELINE_LONGEST"
```

Expected at plan authoring: `rules=106 bytes=36566 longest=582`. Actual at execution may differ by ±2 (count drift per learning `2026-04-06`). Record the actual values in the PR body.

1.2 Verify aggregator health (satisfies FR5):

```bash
gh run list --workflow rule-metrics-aggregate.yml --limit 5 --branch main
gh pr list --search "rule-metrics" --state all --limit 3
```

Expected: most-recent scheduled run has `status: completed, conclusion: success`. If not, follow this plan's contingency (file a tracking issue, continue).

1.3 Confirm Phase 3 migration targets are still `[hook-enforced: ...]`/`[skill-enforced: ...]` on main (no recent edit on `feat-agents-rule-threshold` has altered them):

```bash
git show main:AGENTS.md | grep -E 'cq-after-completing-a-playwright-task-call|cq-before-calling-mcp-pencil-open-document|wg-when-a-research-sprint-produces'
```

### Phase 2 — Threshold Raise (100 → 115)

2.1 Edit `AGENTS.md` line 81 (`cq-agents-md-why-single-line`):

- Change `>100 rules` → `>115 rules` in the rule body.
- Append `**Why:**` sentence: `**Why:** #2686 — empirical rule-count trajectory exceeded the original 100-rule budget; raised to 115 after confirming every rule cites a PR/learning and the rule-prune aggregator (PR #2213) is live.`

2.2 Edit `plugins/soleur/skills/compound/SKILL.md` line 205:

- Change `` If `A > 100` `` → `` If `A > 115` ``
- Change `(A/100)` → `(A/115)` in the warning string.
- Do NOT touch `B > 40000`, `L > 600`, `C > 300` — scope-out.

2.3 Read-back verification: `grep -n '115' AGENTS.md plugins/soleur/skills/compound/SKILL.md` returns exactly the two new references and no stale `100`-at-that-location.

### Phase 3 — Skill-Migration Pattern Proof (3 rules)

**Migration convention (applied to each rule):**

- Full rule body moves to the owning skill/hook file.
- In AGENTS.md, the rule is replaced with a **one-line pointer**: original lead-in verb + the destination path + the preserved `[id: ...]`. Example shape: `- Playwright tasks require browser_close; full rule in plugins/soleur/hooks/browser-cleanup-hook.sh header [id: cq-after-completing-a-playwright-task-call].`
- The pointer line stays ≤ 200 bytes (well under the 600-byte cap).
- The destination file's new comment/section includes a "Rule source: AGENTS.md (migrated 2026-04-21)" marker so the pattern is self-documenting for future readers.

**Rule 1: `cq-after-completing-a-playwright-task-call`**

- **Source (AGENTS.md L75):** `After completing a Playwright task, call \`browser_close\` [id: cq-after-completing-a-playwright-task-call] [hook-enforced: browser-cleanup-hook.sh].`
- **Destination:** `plugins/soleur/hooks/browser-cleanup-hook.sh` header comment block (lines 1–5 currently "Browser Cleanup Stop Hook"). Append a `# Rule source: AGENTS.md — migrated 2026-04-21 (PR #2754)` comment with full rule text.
- **AGENTS.md pointer:** `- Call browser_close after Playwright tasks; enforcement + full rule in plugins/soleur/hooks/browser-cleanup-hook.sh [id: cq-after-completing-a-playwright-task-call] [hook-enforced: browser-cleanup-hook.sh].`
- **Byte impact:** pointer ~150 bytes vs. current ~141 bytes — roughly neutral. Listed first for pattern-establishment value, not byte savings.

**Rule 2: `cq-before-calling-mcp-pencil-open-document`**

- **Source (AGENTS.md L73):** the full 258-byte rule body about untracked `.pen` files.
- **Destination:** two places (the hook is the blocking enforcement; the skill is where agents authoring Pencil work encounter the rule). (a) `.claude/hooks/pencil-open-guard.sh` header block — add full rule text as `# Rule source: AGENTS.md — migrated 2026-04-21 (PR #2754)`. (b) `plugins/soleur/skills/pencil-setup/SKILL.md` — add a short subsection "Untracked .pen safety" with the rule body.
- **AGENTS.md pointer:** `- Never call mcp__pencil__open_document on untracked .pen files (hook-enforced); full rule in .claude/hooks/pencil-open-guard.sh + plugins/soleur/skills/pencil-setup/SKILL.md [id: cq-before-calling-mcp-pencil-open-document] [hook-enforced: pencil-open-guard.sh].`
- **Byte impact:** ~220 bytes saved vs. source.

**Rule 3: `wg-when-a-research-sprint-produces`**

- **Source (AGENTS.md L40):** ~170 bytes. `When a research sprint produces recommendations, run the cascade-validate loop [id: wg-when-a-research-sprint-produces] [skill-enforced: work Phase 2.5]. "Findings written" is NOT done — "findings applied, validated, and all documents reflect the final state" is done.`
- **Destination:** `plugins/soleur/skills/work/SKILL.md` § Phase 2.5. Absorb the "findings written ≠ done" framing directly into the Phase 2.5 instruction body.
- **AGENTS.md pointer:** `- Research-sprint recommendations must run the cascade-validate loop; full rule in plugins/soleur/skills/work/SKILL.md §Phase 2.5 [id: wg-when-a-research-sprint-produces] [skill-enforced: work Phase 2.5].`
- **Byte impact:** ~40 bytes saved. Lowest savings of the three; included for coverage across sections (cq × 2, wg × 1).

**Sanity check after all three migrations:**

```bash
# Every [id: ...] tag from HEAD must still be present in the working copy (or lint-rule-ids.py will hard-fail)
diff <(git show HEAD:AGENTS.md | grep -oE '\[id: [a-z0-9-]+\]' | sort -u) \
     <(grep -oE '\[id: [a-z0-9-]+\]' AGENTS.md | sort -u)
# Expected: empty diff (no ids removed; 3 migrated ids remain in AGENTS.md as pointers)
```

### Phase 4 — Verification & Follow-up Filing

4.1 Measure post-migration:

```bash
echo "after: rules=$(grep -c '^- ' AGENTS.md) bytes=$(wc -c < AGENTS.md) longest=$(grep '^- ' AGENTS.md | awk '{print length}' | sort -n | tail -1)"
```

Expected: rules=106 (flat — pointer preserves count), bytes ≈ 35,300–35,800 (saving ~800–1,200 bytes), longest ≤ 582 (migrations don't touch the current-longest rule).

4.2 Lint gates (per `cq-markdownlint-fix-target-specific-paths` — specific paths only, never repo-wide):

```bash
npx markdownlint-cli2 --fix AGENTS.md \
  plugins/soleur/skills/compound/SKILL.md \
  plugins/soleur/skills/work/SKILL.md \
  plugins/soleur/skills/pencil-setup/SKILL.md \
  knowledge-base/project/specs/feat-agents-rule-threshold/spec.md \
  knowledge-base/project/learnings/2026-04-21-agents-md-rule-retirement-deprecation-pattern.md
```

4.3 Hook gate (must pass — proves pointer-preservation honored `lint-rule-ids.py`):

```bash
git add AGENTS.md && python3 scripts/lint-rule-ids.py AGENTS.md
echo "exit=$?"
```

Expected exit 0. Exit 1 indicates the pointer pattern was applied incorrectly on one of the 3 rules — re-inspect the diff.

4.4 Lefthook pre-commit end-to-end:

```bash
lefthook run pre-commit --files AGENTS.md plugins/soleur/skills/compound/SKILL.md plugins/soleur/skills/work/SKILL.md plugins/soleur/skills/pencil-setup/SKILL.md plugins/soleur/hooks/browser-cleanup-hook.sh .claude/hooks/pencil-open-guard.sh
```

4.5 **Add threshold sync guard.** Create `scripts/lint-agents-compound-sync.sh` (5–8 bash lines): extract the threshold literal from both files and exit 1 if they disagree. Wire into `lefthook.yml` pre-commit with `glob: "AGENTS.md,plugins/soleur/skills/compound/SKILL.md"`. Run once to verify it reports OK on the post-Phase-2 state.

4.6 File the single follow-up issue (via `wg-when-deferring-a-capability-create-a`):

- **Issue A: `chore(agents-md): amend lint-rule-ids.py to support retired-ids allowlist`** — milestone "Post-MVP / Later". Body: describes the pointer-preservation constraint, proposes a file-based allowlist (`scripts/retired-rule-ids.txt`), cites this PR and the deprecation learning.

The merged-id-tag alternative is NOT filed as its own issue — both reviewers flagged it as a rejected alternative that fights the rule-governance architecture. It is documented inside the deprecation learning as "considered and rejected" per `rf-when-a-reviewer-or-user-says-to-keep-a`.

4.7 Write the deprecation learning — documents the three migrated IDs, pointer-preservation pattern, rejected merged-tag alternative with rationale, threshold-raise reasoning (115 not 120), and points to Issue A.

## Alternative Approaches Considered

See brainstorm `2026-04-21-agents-md-rule-threshold-brainstorm.md` for the Option A / B / C decision rationale. Changes relative to the brainstorm decision (Option C):

- **Merged-id-tag migration** (append retiring id to adjacent rule's line): rejected inline by architecture review as fighting the rule-governance architecture. Documented in the deprecation learning.
- **`lint-rule-ids.py` allowlist amendment:** scope-appropriate for its own PR. Filed as Issue A.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `grep -c '^- ' AGENTS.md` unchanged from baseline (pointer preserves count) — 106.
- [ ] ~~`wc -c < AGENTS.md` ≤ baseline − 800~~ — **infeasible under pointer-preservation**; plan's aggregate estimate contradicted its own per-rule byte-impact table. Actual: +90 bytes. Spec FR4 updated with honest replacement; full analysis in the deprecation learning.
- [x] `grep '^- ' AGENTS.md | awk '{print length}' | sort -n | tail -1` ≤ 600 — 582.
- [x] `AGENTS.md` and `plugins/soleur/skills/compound/SKILL.md` both mention `115` in the threshold context; no stale `(A/100)` or `>100 rules` remain.
- [x] Every migrated rule's `[id: ...]` tag still appears in `AGENTS.md` (pointer-preservation invariant).
- [x] Every migrated rule's full body exists in its destination file with `Rule source: AGENTS.md — migrated 2026-04-21 (PR #2754)` marker.
- [x] `python3 scripts/lint-rule-ids.py AGENTS.md` exits 0.
- [x] `lefthook run pre-commit` exits 0 (12.6s; plugin-component-test 1135/0).
- [x] `npx markdownlint-cli2 --fix` on the specific changed Markdown files — 0 errors.
- [x] `scripts/lint-agents-compound-sync.sh` exists, executable, wired in `lefthook.yml`, exits 0 on post-Phase-2 state; fail-state simulated and reverted.
- [x] Learning file `knowledge-base/project/learnings/2026-04-21-agents-md-rule-retirement-deprecation-pattern.md` exists.
- [x] Follow-up Issue #2762 (retired-ids allowlist) filed with milestone "Post-MVP / Later", label `type/chore`.
- [x] Spec FR4 updated with strikethrough + replacement; FR5 marked satisfied.
- [x] PR body includes the 3 migrated-rule table, baseline/after counts, `Closes #2686`, link to Issue #2762.

### Post-merge (operator)

- [ ] `gh run list --workflow rule-metrics-aggregate.yml --limit 3 --branch main` — next scheduled run (Sunday 2026-04-26 00:00 UTC) succeeds AND the resulting `rule-metrics.json` PR ingests the 3 pointer lines without emitting orphan warnings.
- [ ] `gh issue view 2686 --json state --jq .state` returns `CLOSED` (via `Closes #2686` body).
- [ ] No regression in compound step 8 warning output on next compound run — expected: no `[WARNING] rule count` line (threshold now 115, count ≤ 107).
- [ ] Spot-check: authoring a new AGENTS.md rule via `/soleur:compound` → the new threshold comparator correctly fires/silent at the 115 boundary.

## Test Scenarios

Doc-only change; verification scenarios are shell assertions, not runtime tests.

- **T1 — Threshold sync.** `bash scripts/lint-agents-compound-sync.sh` exits 0 after Phase 2, and exits 1 if the literal in either file is modified without updating the other (sanity-check via temporary diff).
- **T2 — Hook immutability compatibility.** `python3 scripts/lint-rule-ids.py AGENTS.md` exits 0 after migration (confirms pointer-preservation honored the removed-id diff check).
- **T3 — Warn silenced.** `echo $((106 > 115))` returns 0 — compound step 8 would not fire the rule-count warning on the post-migration state.

## Risks & Sharp Edges

- **`lint-rule-ids.py` is stricter than the `cq-rule-ids-are-immutable` prose suggests.** The prose says removal "requires a deprecation note + tracking issue"; the hook says "any removed `[id: ...]` fails the commit." Pointer preservation is the only hook-compatible way to satisfy both until the allowlist amendment lands. The plan's learning file must call this out.
- **Count-reduction ambition (spec FR4 ≤103) is infeasible this PR.** The plan relaxes FR4 via a spec `[Updated 2026-04-21]` note. Reviewers familiar with the original spec may flag it — the reconciliation table is the canonical explanation.
- **Baseline drift between plan-write and plan-execute.** Per learning `2026-04-06-rule-audit-budget-baseline-drift.md`, count can grow 2–3 in hours if another PR lands. Use `BASELINE_COUNT` variable captured in Phase 1 throughout; do NOT hardcode 106.
- **Pointer wording sensitivity.** The pointer line is still parsed by `lint-rule-ids.py` for `[id: ...]` extraction. Malformed pointers (missing brackets, duplicated id due to typo) will hard-fail the hook. Run `diff` sanity check in Phase 3 before committing.
- **Destination file must not lose the id token.** If the id is written only inside a code block or fenced region in the destination file, grep-based `rg '<id>' .` searches may still hit it but future edits may delete it. Write the migrated body with `[id: ...]` outside any backtick fences so the token is prose-visible.
- **Comment-only hook-script changes are behavior-preserving** (precedent plan `2026-04-06-chore-rule-audit-migration-plan.md` Sharp Edges). Only touch lines ABOVE `set -euo pipefail` in `browser-cleanup-hook.sh` and `pencil-open-guard.sh`.
- **The threshold-synchronization invariant applies on every future edit.** Addressed in-PR via `scripts/lint-agents-compound-sync.sh` wired to lefthook pre-commit (Phase 4.5). Future threshold raises will hard-fail if the two files disagree.
- **Aggregator is PR-pattern** (uses `bot-pr-with-synthetic-checks`). After merge, the next Sunday 00:00 UTC run will open a PR updating `rule-metrics.json` — that PR may show count 106 (pre-this-PR) for 1 week because the aggregator snapshotted on 2026-04-18. Normal; not a regression.

## Domain Review

**Domains relevant:** Engineering (tooling/process). No Product, Marketing, Legal, Sales, Finance, Operations, or Support implications.

Per brainstorm `## Domain Assessments`: engineering-only decision. The rule governs how agents read the repo — internal tooling. No user-facing change, no commercial implication, no cross-domain surface. No domain leader spawn in the plan phase.

**Product/UX Gate:** Tier NONE — no user-facing surface. Mechanical escalation: `Files to create/edit` contains no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` paths. Gate skipped.

## References

- Threshold rule: `AGENTS.md` L81 (`cq-agents-md-why-single-line`); compound step 8 at `plugins/soleur/skills/compound/SKILL.md` L196–208
- Immutability hook: `scripts/lint-rule-ids.py` L65–80 (removed-id diff check); `AGENTS.md` L80 (`cq-rule-ids-are-immutable`)
- Aggregator: `.github/workflows/rule-metrics-aggregate.yml` + `scripts/rule-metrics-aggregate.sh`; last successful scheduled run 2026-04-19
- Precedent migration plan (pre-hook): `knowledge-base/project/plans/2026-04-06-chore-rule-audit-migration-plan.md`
- Baseline-drift caution: `knowledge-base/project/learnings/2026-04-06-rule-audit-budget-baseline-drift.md`

Brainstorm, spec, issue, and PR links are in the frontmatter above.
