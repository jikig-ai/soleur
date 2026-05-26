---
issue: 3679
lane: procedural
type: chore
classification: tooling-cleanup
requires_cpo_signoff: false
---

# chore: AGENTS always-loaded payload over 22k — placement-gate trim + wg-* demotion

Closes #3679 (PR body, on its own line).

## Enhancement Summary

**Deepened on:** 2026-05-12
**Sections enhanced:** 6 (Overview, Trim Targets, Files to Edit, AC, Implementation Phases, Risks)
**Sources consulted:** institutional learnings (3), `scripts/lint-rule-ids.py` source, `plugins/soleur/skills/work/SKILL.md`, `plugins/soleur/skills/compound/SKILL.md`, `.claude/hooks/session-rules-loader.sh`/`.test.sh`, live `gh` issue/PR state, live `gh label list`.

### Key Improvements

1. **Linter-enforced residency invariant verified live.** `scripts/lint-rule-ids.py:358-387` mechanically asserts `hr-*` AND `[compliance-tier]` rules MUST live in `AGENTS.core.md`. The plan's 3 wg-* demotions and 2 hr-* body-trims (no demotion) both pass this gate by construction — confirmed by reading the linter implementation, not by paraphrasing CPO sign-off prose. AC now references the linter call site so a future refactor of `collect_residency_metadata` doesn't silently weaken the gate.
2. **Baseline pinned to live measurement.** Issue body asserts 24,622 B; `wc -c AGENTS.md AGENTS.core.md` confirms 4,602 + 20,020 = 24,622 B at deepen-plan time (worktree commit `a29d5436`). Per learning `2026-05-11-agents-md-sidecar-byte-budget-adaptation-at-work-phase-0.md`, plan-quoted byte budgets are preconditions — /work Phase 0 MUST re-measure (now folded into the implementation phases as an explicit step).
3. **Growth-rate math made explicit.** PR #3496 merge-time was 21,848 B (2026-05-11); current is 24,622 B (2026-05-12). Net +2,774 B in ~24 hours. Rate matches the 4.7-rules/day / ~700 B/day estimate from `wg-every-session-error-must-produce-either`. Post-trim target 21,045 B re-trips 22 k after ~7 days at that rate — Risks section now flags a follow-up issue for a pre-commit budget gate.
4. **Skill edit prerequisite for hr-type-widening trim flagged.** Body-trim of `hr-type-widening-cross-consumer-grep` requires the grep-three-patterns instruction to FIRST land in `plugins/soleur/skills/work/SKILL.md` §Phase 0. Phase ordering reworked so the skill edit (Phase 2) precedes the body-trim (Phase 3) — per learning `2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md`, contract-changing phases MUST precede consumer phases even in a single atomic PR.
5. **Fallback path quantified.** If the skill edit at Phase 2 fails to land, fallback (Why-only trim on hr-type-widening) saves ~100 B less. Net post-trim total in fallback: 21,545 B (still under 22 k critical, but only 455 B of headroom — equals ~0.6 rules of new growth before re-breach).
6. **Reviewer-discoverability of body-trimmed pointers explicit.** Each body-trimmed hr-* pointer line now contains an absolute file-path + section anchor to the enforcing artifact. `cq-agents-md-tier-gate` explicitly endorses this pattern (already-enforced branch). Verified the work/SKILL.md §Phase 0 anchor exists at line 122 at deepen-plan time; AC re-verifies the anchor name still resolves after the Phase 2 edit (the bullet text is reordered, not the section name).

### New Considerations Discovered

- **`AGENTS.md` (the index/pointer file) is loaded every turn via `CLAUDE.md`'s `@AGENTS.md` reference**, while `AGENTS.core.md` is loaded once per session via the SessionStart hook. Per-turn cost is bounded by `AGENTS.md` (4,602 B) — `AGENTS.core.md` is only a first-turn cost (offset by prompt cache after ~3 turns per learning `2026-05-11-agents-md-change-class-loader-measured-savings.md`). The 22 k threshold is therefore a SessionStart-budget, not a per-turn budget. Trimming the body of hr-* rules in `AGENTS.core.md` reduces SessionStart cost only; demoting wg-* from core → rest reduces SessionStart cost for docs-only sessions (where rest is NOT loaded) AND code/infra sessions (because rest is loaded separately, the wg-* bytes move out of the "always-loaded" payload measurement).
- **Compound skill rule-budget step 8 emits the WARN message that already prescribes the exact strategy in this plan** (`plugins/soleur/skills/compound/SKILL.md:227`): "demote wg-* class-specific rules from AGENTS.core.md to AGENTS.rest.md (per CPO sign-off PR #3496, only wg-* may be demoted — never hr-*)". This plan is the implementation of that pre-written guidance.
- **Telemetry retirement gate is currently non-viable.** `knowledge-base/project/rule-metrics.json` was bootstrapped 2026-05-10; all 69 tagged rules show `applied_count=0` because the 8-week zero-hit window has not opened (earliest viable retirement-by-metrics: ~2026-07-04). The issue body's suggestion #4 ("Retire unused rules via `scripts/retired-rule-ids.txt` if 8w zero hits") is captured as deferred scope-out, not in-scope work.

## Overview

Compound rule-budget step 8 flagged a `[CRITICAL]` breach of the always-loaded payload threshold:

```
always-loaded total:    24,622 bytes (warn > 18000 / critical > 22000)
```

The always-loaded total is `AGENTS.md` (4,602 bytes — pointer index) + `AGENTS.core.md` (20,020 bytes) = 24,622 bytes. That's 2,622 bytes (12 %) over the 22 k harness ceiling that `cq-agents-md-why-single-line` declares load-bearing for per-session-first-turn cost.

This plan applies the placement gate (`cq-agents-md-tier-gate`) to the top-N longest rules: demote class-specific `wg-*` from core to rest (CPO sign-off PR #3496 condition 3 — wg-only), and trim already-enforced `hr-*` bodies to one-line pointers per the gate's "already-enforced" branch. No `hr-*` is demoted; no rule retired.

Target: trim the always-loaded payload from 24,622 B to ≤ 21,000 B (≥ 1,000 B under critical, ≥ 3,000 B under warn — leaves headroom for `cq-agents-md-why-single-line`'s registry-growth rate of 4.7 rules/day documented in #2865).

## User-Brand Impact

**If this lands broken, the user experiences:** `AGENTS.core.md` parse failure on SessionStart (e.g., malformed pointer line in `AGENTS.md` after demotion, or missing `[id:]` slug after body-trim) — the rules loader fails closed (per `[session-rules-loader]` LOADER_FAIL_CLOSED test) and the operator sees the loader stamp `[rules-loader] FAILED — fail-closed` at session start. No agent runs without rules loaded.

**If this leaks, the user's [data / workflow / money] is exposed via:** trimming a rule body too aggressively could drop a load-bearing constraint that the enforcing skill does NOT fully encode in its SKILL.md. The constraint then disappears from agent context entirely. Mitigation: every body-trimmed rule MUST cite the file path where the full constraint lives (skill/learning/runbook), and `scripts/lint-rule-ids.py` keeps the `[id:]` slug uniqueness invariant intact.

**Brand-survival threshold:** none — tooling refactor on AGENTS.md surface; no operator data, credentials, or workflow gating changes. Threshold `none, reason: AGENTS.md refactor — no regulated-data surface, no auth/payments touched, no schema change.`

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Reality | Plan response |
|---|---|---|
| Issue: "[CRITICAL] always-loaded payload 24,622 bytes" | Verified: `wc -c AGENTS.md AGENTS.core.md` = 4,602 + 20,020 = 24,622 B | Use as baseline; AC asserts post-trim ≤ 22,000 B (target ≤ 21,000 B). |
| Issue: "longest rule 1004 bytes" | Verified: `wg-plan-prescribed-skills-must-run-inline` body via `grep -h '^- ' AGENTS.core.md \| awk '{print length}' \| sort -rn` | Demote to AGENTS.rest.md (wg-* is demotable per #3496). |
| Issue: "148 rules" | `grep -c '^- ' AGENTS.md AGENTS.core.md AGENTS.rest.md AGENTS.docs.md` = 74 + 53 + 17 + 4 = 148 (index duplicates body — actual unique = 74) | Advisory only, no count change in this PR. |
| Compound: "shrink required before next rule" | Confirmed in `plugins/soleur/skills/compound/SKILL.md:227` | Plan acts before next rule lands. |
| Issue suggestion: "Retire unused rules via `scripts/retired-rule-ids.txt` if 8w zero hits" | `knowledge-base/project/rule-metrics.json` shows ALL 69 tagged rules at `applied_count=0` because telemetry was bootstrapped 2026-05-10 (2 days ago) | Retirement-by-metrics is NOT yet viable — telemetry baseline is too fresh. Plan uses placement-gate trim + demotion instead. |
| Issue: "no `hr-*` rule demoted from core" | PR #3496 CPO sign-off condition 3: only `wg-*` may be demoted | Plan respects: 0 `hr-*` demotions. 2 `hr-*` body-trims (already-enforced pointer pattern) — body-trim is NOT demotion. |
| Open code-review overlap | `gh issue list --label code-review --state open` returns issues but none touch `AGENTS.md`/`AGENTS.core.md`/`AGENTS.rest.md`/`AGENTS.docs.md` | No overlap; no fold-in. |

## Open Code-Review Overlap

None — `jq` search across `gh issue list --label code-review --state open --json number,title,body --limit 200` against each planned-edit file path returned zero matches.

## Trim Targets

Sorted by byte impact. All measurements via `grep -h '^- ' AGENTS.core.md | awk '{print length, $0}' | sort -rn`.

### Demote core → rest (wg-* only — per PR #3496 CPO condition 3)

| Rule id | Current bytes | Action | Index update |
|---|---|---|---|
| `wg-plan-prescribed-skills-must-run-inline` | 1004 | Move full body verbatim from `AGENTS.core.md` § Workflow Gates → `AGENTS.rest.md` § Workflow Gates | `AGENTS.md` line: change `→ core` to `→ rest` |
| `wg-use-closes-n-in-pr-body-not-title-to` | 571 | Move full body verbatim (already `[scanner-enforced]`); `AGENTS.rest.md` § Workflow Gates | `AGENTS.md` line: change `→ core` to `→ rest` |
| `wg-every-session-error-must-produce-either` | 552 | Move full body verbatim; `AGENTS.rest.md` § Workflow Gates | `AGENTS.md` line: change `→ core` to `→ rest` |

Subtotal: ~2,127 B removed from `AGENTS.core.md`.

**Why these three:** All three apply at PR/work time on code/infra-class changes, not on docs-only or session-start. AGENTS.rest.md is loaded for `code` and `infra` change-classes (per session-rules-loader). Demoting to rest preserves the rule for the sessions that actually trigger it; docs-only sessions don't need them.

**`wg-after-a-pr-merges-to-main-verify-all`** (430 B) is `[skill-enforced: ship Phase 7]` — eligible to demote too but the rule MUST be visible at session start for the "verify before ending the session" semantics (it gates session-end behavior, not just work-time behavior). Keep in core; do not demote.

### Body-trim hr-* to one-line pointer (placement-gate "already-enforced" branch)

`cq-agents-md-tier-gate` (`AGENTS.docs.md`) prescribes: "Already-enforced (`[hook-enforced:]` / `[skill-enforced:]` / `[scanner-enforced:]` for fail-soft CI): keep `[id]` + tag + one-line pointer; full rule in the enforcing artifact." Both candidates already have the full body encoded in the named enforcing artifact.

| Rule id | Current bytes | Verified enforcing-artifact location | Action |
|---|---|---|---|
| `hr-write-boundary-sentinel-sweep-all-write-sites` | 715 | `plugins/soleur/skills/work/SKILL.md:122` carries the verbatim grep pattern and example call site | Replace body with one-line pointer: `[skill-enforced: work Phase 0 Write-boundary sentinel sweep]. Enumerate ALL write sites where the sentinel applies, not just diff sites — see `plugins/soleur/skills/work/SKILL.md` §Phase 0.` |
| `hr-type-widening-cross-consumer-grep` | 729 | Currently NOT in a skill SKILL.md. Body is the load-bearing instructions. | **Conditional trim:** add the grep-three-patterns instruction to `plugins/soleur/skills/work/SKILL.md` §Phase 0 in the same PR, then trim the AGENTS.core.md body to a pointer. If the skill edit is not made, do NOT trim — fall back to a `**Why:**` trim only (~100 B). |

Subtotal (best-case): ~1,200 B removed.
Subtotal (fallback if hr-type-widening skill edit deferred): ~600 B removed (write-boundary only) + ~100 B Why-trim on hr-type-widening = ~700 B.

### Why-line trim (already-enforced rules with verbose Why-clauses)

Per `cq-agents-md-why-single-line`: "AGENTS registry rules cap at ~600 bytes; `**Why:**` is one sentence → PR/learning." The rules below are over-cap because their `**Why:**` lines either duplicate the body or carry multiple incidents.

| Rule id | Current bytes | Target bytes | Action |
|---|---|---|---|
| `hr-menu-option-ack-not-prod-write-auth` | 602 | ≤ 550 | Trim `**Why:**` from `#2618 per-command-ack; #2880 operationalized for non-interactive exec.` to `#2618; #2880.` |
| `hr-never-paste-secrets-via-bang-prefix` | 589 | ≤ 500 | Trim `**Why:**` and the long learning-path reference — keep the learning-path, drop the prose sentence. |
| `pdr-when-a-user-message-contains-a-clear` | 572 | ≤ 500 | Trim the `Note:` clause about Command Center web app routing to a one-token annotation; keep the routing-policy core. |
| `cq-pg-security-definer-search-path-pin-pg-temp` | 569 | ≤ 500 | Trim `**Why:**` to issue ref only. |

Subtotal: ~250 B removed.

### Total expected savings

- Demotion: 2,127 B
- Body-trim (best case): 1,200 B
- Why-trim: 250 B
- **Total: ~3,577 B**

### Research Insights — Trim Targets

**Linter contract for body-trimmed rules.** `scripts/lint-rule-ids.py` (read at deepen-plan time, lines 358-387) enforces two residency invariants:

```python
# Residency invariants (CPO sign-off PR #3496, condition #3):
# 1. Every `[compliance-tier]`-tagged rule MUST live in AGENTS.core.md.
# 2. Every `hr-*` rule MUST live in AGENTS.core.md.
```

The linter treats "lives in core" as "has a body line in `AGENTS.core.md`" — a body-trim that keeps the rule's line in core (even reduced to a one-line pointer) passes. A demotion (removing the body line from core and adding it to rest) would fail for any `hr-*` or `[compliance-tier]` rule. Verified by reading `collect_residency_metadata()` at `scripts/lint-rule-ids.py:200` — it parses each file's body lines for `[id: ...]` plus enforcement tags, then asserts set-difference.

**Why-line cap precedent.** The retired-rule registry's grandfather entries (e.g., `hr-before-running-git-commands-on-a` retired 2026-04-23 in PR #2865) demonstrate that ~600 B is the operational ceiling. Five of the 7 retired entries from PR #2865 were retired on "discoverability litmus" grounds (the constraint surfaced via a clear error, so the rule was redundant) — not on size. The plan's body-trim approach (keep the constraint, shrink the documentation) is a strictly weaker action than retirement; existing precedent for size reductions is `wg-after-marking-a-pr-ready-run-gh-pr-merge` which had its `**Why:**` trimmed in-place during PR #2865.

**Demotion blast radius.** `.claude/hooks/session-rules-loader.sh` classifies sessions into `docs-only`, `code`, `infra`, or `mixed` based on file extensions and paths in the change-set. `AGENTS.rest.md` is loaded for `code`, `infra`, and `mixed` sessions; `AGENTS.docs.md` is loaded for `docs-only`, and `mixed`. Per the measured-savings learning: "Mixed-frequency = 40 % [in the PR #3496 5-PR spot-check]; for those sessions the loader provides no savings (fail-closed loads everything), but operates as a safety floor." Net implication: the 3 demoted wg-* rules will be loaded on ~60 % of sessions instead of 100 %. Acceptable per the rules' semantics (all 3 apply at /work or PR time, not at session start).

**Anti-pattern: trimming a rule whose body is the source-of-truth.** Some `hr-*` rules carry constraints that exist NOWHERE else in the codebase (e.g., `hr-never-write-to-claude-code-memory-claude` — the constraint is purely policy, not enforced by code). Trimming those rules to a pointer would break the discoverability litmus from `wg-every-session-error-must-produce-either`. The two hr-* rules selected for body-trim in this plan (`hr-write-boundary-sentinel-sweep-all-write-sites`, `hr-type-widening-cross-consumer-grep`) both have load-bearing bodies in `plugins/soleur/skills/work/SKILL.md` (verified at deepen-plan time for write-boundary; conditional on Phase 2 for type-widening) — body-trim is safe by construction.

Post-trim always-loaded total: 24,622 − 3,577 = **21,045 B** (1,000 B under 22 k critical, 3,000 B under 18 k warn — *just over* warn, but in the explicit acceptance band per `cq-agents-md-why-single-line`).

Fallback (hr-type-widening skill edit deferred): 24,622 − (2,127 + 700 + 250) = **21,545 B** (455 B under 22 k, but headroom for only ~1 new rule before next breach).

**Decision:** Pursue best-case (skill edit included). The skill edit is ~5 lines of bash + 3 sentences of prose — same-PR cost is low; deferring just punts the same edit to a follow-up PR.

## Files to Edit

- `AGENTS.md` — update 3 wg-* pointer lines from `→ core` to `→ rest`.
- `AGENTS.core.md` — remove 3 wg-* rules (full body); trim 2 hr-* rules to pointer; trim 4 Why-lines.
- `AGENTS.rest.md` — add 3 wg-* rules under § Workflow Gates (verbatim from core, no edit to body).
- `plugins/soleur/skills/work/SKILL.md` — add `hr-type-widening-cross-consumer-grep` grep-three-patterns instruction to §Phase 0 (under existing Write-boundary sentinel sweep block).

## Files to Create

None.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `wc -c AGENTS.md AGENTS.core.md` total ≤ 22,000 bytes (current 24,622). **Actual:** 21,534 B (466 B headroom).
- [ ] `wc -c AGENTS.md AGENTS.core.md` total ≤ 21,500 bytes (target headroom). **Actual:** 21,534 B (34 B over aspirational; 22 k critical AC passes).
- [x] `grep -h '^- ' AGENTS.core.md | awk '{print length}' | sort -rn | head -1` returns a value ≤ 600 (longest core rule respects the cap). **Actual:** 558.
- [x] `python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt --index-file AGENTS.md AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` exits 0.
- [x] `bash scripts/lint-agents-compound-sync.sh` exits 0.
- [x] `python3 scripts/lint-agents-enforcement-tags.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` exits 0.
- [x] `bash .claude/hooks/session-rules-loader.test.sh` exits 0 (14/14 passed; up from 11 at PR #3496 merge — additional cases added in subsequent hardening).
- [x] For every demoted `wg-*` rule, `git grep -nE '\[id: <rule-id>\]'` returns exactly 2 results: the index pointer in `AGENTS.md` (pointing to `rest`) and the body in `AGENTS.rest.md`. Zero results in `AGENTS.core.md`.
- [x] For every body-trimmed `hr-*` rule, the pointer line cites a file path containing the verbatim constraint. Verify: `grep -nE '<pointer-path>' AGENTS.core.md` returns the pointer; opening the cited file finds the load-bearing body within ±5 lines of the named anchor.
- [x] No `hr-*` rule moved out of `AGENTS.core.md` (CPO sign-off PR #3496 condition 3).
- [x] No new entry added to `scripts/retired-rule-ids.txt` (this PR is trim-not-retire).
- [x] PR body uses `Closes #3679` on its own line (per `wg-use-closes-n-in-pr-body-not-title-to`).

### Post-merge (operator)

- [ ] Open a fresh Claude Code session against any feature branch; confirm the `[rules-loader] loaded:` stamp appears in tool output and lists `AGENTS.core.md` with the trimmed body (no truncation, no parse-error).
- [ ] Confirm a docs-only session does NOT load the 3 demoted wg-* rules (loader stamp shows `AGENTS.docs.md` only, not `rest`).
- [ ] Confirm a code/infra session DOES load the 3 demoted wg-* rules (loader stamp shows `AGENTS.rest.md` present).

## Implementation Phases

### Phase 0 — Baseline + repo-edits-only sweep

1. Read `AGENTS.md`, `AGENTS.core.md`, `AGENTS.rest.md`, `AGENTS.docs.md` in full.
2. Record current byte sizes: `wc -c AGENTS*.md > /tmp/baseline-bytes.txt`.
3. Record current longest-rule size: `grep -h '^- ' AGENTS.core.md | awk '{print length}' | sort -rn | head -5 > /tmp/baseline-longest.txt`.
4. Confirm `plugins/soleur/skills/work/SKILL.md` §Phase 0 currently contains the write-boundary sentinel sweep block verbatim (already verified at plan time, line 122). Re-verify post-Phase-0 in case the file changed.

### Phase 1 — Demote wg-* trio core → rest (no body edits)

1. Copy the three wg-* rules verbatim from `AGENTS.core.md` § Workflow Gates to `AGENTS.rest.md` § Workflow Gates (append, keep section ordering deterministic — alphabetical by id-suffix within the section).
2. Remove the same three lines from `AGENTS.core.md`.
3. Update `AGENTS.md` pointer index: change `[id: wg-plan-prescribed-skills-must-run-inline] → core` to `→ rest`; same for the other two.
4. Run `python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt --index-file AGENTS.md AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` — expect exit 0. The cross-file linter (per PR #3496) checks pointer↔body consistency.
5. Run `wc -c AGENTS.md AGENTS.core.md` — expect ~22,500 B at this point.

### Phase 2 — Add hr-type-widening grep instruction to work skill

1. Read `plugins/soleur/skills/work/SKILL.md` lines 100-150 (the Phase 0 section).
2. After the existing "Write-boundary sentinel sweep" bullet, add a sibling bullet: **Type-widening cross-consumer grep (when applicable).** When the PR widens a producer-side shared type whose payload crosses an `unknown`/`any`/jsonb boundary, `git grep -nE '<field-name-pattern>' apps/` across every consumer and verify each respects the new optionality. For `Message`-class fields the canonical grep is `git grep -nE '\bmessage\.usage\.(input_tokens|output_tokens|completed_actions)\b' apps/` (adapt per field family). See learning `2026-05-12-type-widening-cascades-and-write-boundary-sentinels.md`; hard rule `hr-type-widening-cross-consumer-grep`. **Why:** PR-A2 #3603.
3. Verify the bullet is 1-3 sentences and includes the grep example verbatim.

### Phase 3 — Body-trim 2 hr-* rules to pointer

1. In `AGENTS.core.md`, replace the body of `hr-write-boundary-sentinel-sweep-all-write-sites` with:
   `When a plan introduces a guard/sentinel that asserts a property at write sites, enumerate ALL write sites where the property applies — not just diff sites [id: hr-write-boundary-sentinel-sweep-all-write-sites] [skill-enforced: work Phase 0 Write-boundary sentinel sweep]. Full grep pattern + call-site example: plugins/soleur/skills/work/SKILL.md §Phase 0.`
2. Replace the body of `hr-type-widening-cross-consumer-grep` with:
   `When widening a producer-side shared type whose payload crosses an unknown/any/jsonb boundary, grep every consumer and verify each respects the new optionality BEFORE merging [id: hr-type-widening-cross-consumer-grep] [skill-enforced: work Phase 0 Type-widening cross-consumer grep]. Full grep pattern + Message.usage example: plugins/soleur/skills/work/SKILL.md §Phase 0.`
3. Verify each trimmed line is ≤ 350 bytes.

### Phase 4 — Why-line trims on 4 rules

For each rule, edit in place; do NOT touch the `[id: ...]` slug; preserve `[hook-enforced:]` / `[skill-enforced:]` / `[scanner-enforced:]` / `[compliance-tier]` tags exactly.

1. `hr-menu-option-ack-not-prod-write-auth`: replace `**Why:** #2618 per-command-ack; #2880 operationalized for non-interactive exec.` with `**Why:** #2618; #2880.`
2. `hr-never-paste-secrets-via-bang-prefix`: drop the trailing learning-path narration sentence; keep the `See knowledge-base/...md.` reference. Trim `**Why:** 2026-05-06 PR-B — prd JWT secret entered transcript verbatim.` to `**Why:** PR-B prd-JWT leak (2026-05-06).`
3. `pdr-when-a-user-message-contains-a-clear`: keep the orthogonality core (`spawn multiple leaders ONLY when ... distinct asks ... different domains`); drop the parenthetical example duplication and the Command-Center routing note. Keep the spawn-via-run_in_background reference.
4. `cq-pg-security-definer-search-path-pin-pg-temp`: trim `**Why:** PR #2954 — migration 033 + precedent 027 both had the gap; reviewer caught pre-merge.` to `**Why:** PR #2954 — migration 033/027 gap, caught pre-merge.`

### Phase 5 — Verify post-trim totals

1. `wc -c AGENTS.md AGENTS.core.md` → assert total ≤ 21,500 B.
2. `grep -h '^- ' AGENTS.core.md | awk '{print length}' | sort -rn | head -1` → assert ≤ 600 B.
3. `python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt --index-file AGENTS.md AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` → exit 0.
4. `bash scripts/lint-agents-compound-sync.sh` → exit 0.
5. `python3 scripts/lint-agents-enforcement-tags.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` → exit 0.
6. `bash .claude/hooks/session-rules-loader.test.sh` → 11/11.

### Phase 6 — Session-loader smoke test

1. Stage all edits but do NOT commit yet.
2. Open a fresh terminal, `cd` into the worktree, run `.claude/hooks/session-rules-loader.sh` against a synthetic `docs-only` change-class input. Confirm `AGENTS.docs.md` loads, `AGENTS.rest.md` does NOT.
3. Repeat with a `code` class. Confirm `AGENTS.rest.md` loads and contains the 3 newly demoted wg-* rules.
4. Confirm the loader's `[rules-loader] loaded:` stamp shows the trimmed `AGENTS.core.md` without truncation or parse error.

### Phase 7 — Compound + commit

1. Run `skill: soleur:compound` (per `wg-before-every-commit-run-compound-skill`).
2. Stage: `git add AGENTS.md AGENTS.core.md AGENTS.rest.md plugins/soleur/skills/work/SKILL.md`.
3. Commit + push.

### Research Insights — Implementation Phases

**Phase-order load-bearing.** Per learning `2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md` (Kieran-rails-reviewer catch on PR #3509): when a plan prescribes BOTH a contract-changing edit AND a contract-consumer edit, the contract phase MUST come before the consumer phase even when the entire PR is single-merge atomic. Phase 2 (skill edit — adds the new `Type-widening cross-consumer grep` bullet) is the contract change; Phase 3 (body-trim of `hr-type-widening-cross-consumer-grep` to a pointer that references the new bullet) is the consumer. Reordering would produce a body-trim that points at a section anchor not yet present in the skill file — `grep` would return zero matches, and an over-cautious reader (human or agent) would conclude the constraint is lost.

**Plan-quoted measurement is a precondition.** Phase 0 step 2 (`wc -c AGENTS*.md > /tmp/baseline-bytes.txt`) is folded in to honor the rule from learning `2026-05-11-agents-md-sidecar-byte-budget-adaptation-at-work-phase-0.md`: "Plan-quoted measurements are preconditions to verify, not facts." If the work session runs more than a few hours after this plan lands, fresh growth (4.7 rules/day = ~700 B/day) may have pushed the baseline higher — the AC still enforces ≤22 k, but the savings math may need re-derivation.

**Idempotent file edits.** Each of Phase 1's three demotion edits is a verbatim copy + delete + index-line-update. Edits to `AGENTS.rest.md` are appended in alphabetical order within § Workflow Gates (the file currently has 3 wg-* bodies in that section; adding 3 more keeps it sortable). The Edit tool's idempotency contract is satisfied because each `old_string` is unique (matched on the `[id: ...]` slug); re-running the same edit on a partially-applied state will fail with "old_string not found" rather than silently double-writing.

**Verifier wiring.** Phase 5 runs three linters whose call sites and exit codes are verified at deepen-plan time:

- `scripts/lint-rule-ids.py` — supports `--retired-file` and `--index-file` flags (docstring at line 14). Cross-file mode (5 file args) checks pointer↔body consistency AND residency invariants.
- `scripts/lint-agents-compound-sync.sh` — exists at the expected path; called by lefthook on every AGENTS.md edit.
- `scripts/lint-agents-enforcement-tags.py` — same call site as PR #3496; runs against all 4 AGENTS files.

**`.claude/hooks/session-rules-loader.test.sh` — 11 cases.** Verified file exists, executable. Cases per PR #3496 test plan: 4 classifier, 1 LOADER_FAIL_CLOSED, 1 idempotency, 1 bare-repo path, 1 manifest schema, 1 fail-closed, 1 stamp ≤ 200 B, plus 1 additional case (likely the `docs` vs `docs-only` slug parity test added in session-error recovery). Phase 5 step 6 asserts 11/11 — any new test added since #3496 would push this higher; the AC tolerates "≥ all-pass" by checking exit 0 rather than a fixed pass count. Updated below.

## Test Strategy

No new tests — this PR is a content refactor against an existing test surface. The load-bearing test suite is:

1. `scripts/lint-rule-ids.py` — cross-file mode (verifies pointer↔body consistency); cross-checked manually post-edit at Phase 5.
2. `.claude/hooks/session-rules-loader.test.sh` — 11 cases including LOADER_FAIL_CLOSED, classifier accuracy, idempotency, fail-closed, manifest schema. Asserts the loader still parses `AGENTS.core.md` and `AGENTS.rest.md` after the demotion.
3. Manual smoke test at Phase 6 — confirms the SessionStart hook produces the expected loader stamp on a fresh session.

## Risks

- **Risk: a demoted wg-* rule fires on a session class that doesn't load `AGENTS.rest.md`.** The 3 demoted rules:
  - `wg-plan-prescribed-skills-must-run-inline` — fires at `/work` Phase 4 entry; `/work` runs on code/infra sessions exclusively. Safe.
  - `wg-use-closes-n-in-pr-body-not-title-to` — scanner-enforced via `.github/workflows/pr-auto-close-scanner.yml`; the scanner is the load-bearing enforcement, the rule is documentation. Safe.
  - `wg-every-session-error-must-produce-either` — applies session-end on error. Docs-only sessions can produce errors too (e.g., editing a `.md` file with a broken link). **Risk surface:** an operator on a docs-only session hits an error, the rule is not loaded, the learning-file step is skipped. Mitigation: `cq-agents-md-tier-gate` (in AGENTS.docs.md, always loaded for docs-class) already mandates the placement gate, and `wg-when-a-workflow-gap-causes-a-mistake-fix` (still in core) covers the fix-first invariant. Net: the constraint is documented adjacent to the docs-class context.

- **Risk: body-trim of hr-write-boundary leaves the rule too thin for the agent to act on.** Mitigation: pointer line includes the exact file path of the load-bearing body. `cq-agents-md-tier-gate` explicitly endorses this pattern. The full body is in `plugins/soleur/skills/work/SKILL.md` which IS loaded by every code/infra session that would trigger the rule.

- **Risk: hr-type-widening skill edit at Phase 2 not landing cleanly.** Mitigation: Phase 2 is a single bullet addition to an existing `Phase 0` section that already follows the same pattern (write-boundary sentinel sweep). The Phase 2 task is < 10 lines of diff. If the skill edit fails to land, fall back to a Why-only trim on hr-type-widening (loses ~600 B but still hits 22 k).

- **Risk: linter detects a stale `[id:]` slug after copy-paste from core to rest.** Mitigation: Phase 1 step 4 runs the cross-file linter explicitly before Phase 2 begins. Any pointer↔body drift is a hard fail (exit 1 with named line).

- **Risk: a future PR re-adds bytes to `AGENTS.core.md`, re-tripping the budget.** Mitigation: out of scope for this PR. The 4.7-rules/day growth-rate problem (`wg-every-session-error-must-produce-either` documents it via #2865) is the load-bearing constraint that this trim only buys headroom for; rule-budget telemetry hardening is a separate follow-up.

### Research Insights — Risks

**Empirical growth-rate.** Comparing PR #3496 merge state (21,848 B, 2026-05-11) to current (24,622 B, 2026-05-12) yields +2,774 B in ~24 hours — concentrated on a single-day window (worktree HEAD commit `a29d5436`). That's ~3.9× the 700 B/day estimate from PR #2865 telemetry. The spike likely correlates with the cc-soleur-go #3603 hardening PR landing two new long hr-* rules (`hr-type-widening-cross-consumer-grep` and `hr-write-boundary-sentinel-sweep-all-write-sites` — both 700+ B). Sustained spike rate is unknown; the 4.7-rules/day average remains the load-bearing estimate. Post-trim 21,045 B will re-trip 22 k after ~1.4 days at spike rate, ~13 days at average rate. The Out-of-Scope deferral for a pre-commit rule-budget gate is therefore time-sensitive (file the tracking issue at PR merge per `wg-when-deferring-a-capability-create-a`).

**Linter coverage gaps acknowledged.** `scripts/lint-rule-ids.py` enforces:

1. Slug uniqueness across all 4 AGENTS files (pointer ↔ body).
2. `hr-*` residency in `AGENTS.core.md`.
3. `[compliance-tier]` residency in `AGENTS.core.md`.
4. Retired-id reintroduction rejection.
5. Removed-id diff (HEAD↔current).

It does NOT enforce:

- Per-rule byte cap (no rule exceeds ~600 B). Out of scope for this PR.
- Always-loaded payload total ≤ 22 k. Out of scope; compound step 8 surfaces it advisorily at commit time, but doesn't block commit.

The lint gap is the load-bearing reason the Out-of-Scope tracking issue is filed.

**Risk: linter not run before commit.** `wg-before-every-commit-run-compound-skill` is the gate; compound step 8 surfaces the budget breach as `[CRITICAL]` advisory. The skill does NOT block commit on `[CRITICAL]` today — operator discretion. Mitigation in this PR: Phase 5 (verify post-trim totals) runs the linters manually and asserts the budget; commit only proceeds if Phase 5 succeeds. Phase 5 results are recorded in the PR body.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — tooling refactor on the `AGENTS.md` surface; no operator data, credentials, schema, payments, UI, or workflow gating change. The trim respects the CPO sign-off in PR #3496 (only `wg-*` demotion, no `hr-*`) — that condition is encoded as an AC, not a separate CPO re-sign-off.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's threshold is `none` with a non-empty reason — preflight Check 6 sensitive-path regex does NOT match `AGENTS*.md`, so the `none` threshold passes.
- Re-running the trim later (next rule-budget breach) MUST verify `cq-agents-md-tier-gate`'s "already-enforced" claim against the named skill file at the time of the next trim. Skills move; pointers go stale. The next planner should grep `plugins/soleur/skills/work/SKILL.md` for both `Write-boundary sentinel sweep` and `Type-widening cross-consumer grep` headers before trusting the pointer.
- The 4.7-rules/day growth rate documented in `wg-every-session-error-must-produce-either` (PR #2865 reference) means the 21,045 B post-trim payload re-trips 22 k after ~13 days of rule growth (assuming ~150 B average per new rule × 4.7/day = ~700 B/day). This plan does NOT address the growth-rate root cause; only the current breach. A follow-up rule-retirement-via-telemetry PR is appropriate once `knowledge-base/project/rule-metrics.json` accumulates ≥ 8 weeks of post-bootstrap data (current bootstrap was 2026-05-10; earliest viable telemetry-based retirement: ~2026-07-04).

## Browser / Manual Steps

None. All edits are file-content changes verified by existing CI lints and the SessionStart hook test suite.

## CLI-Verification

All CLI invocations cited in this plan are verified against the worktree:

- `wc -c AGENTS.md AGENTS.core.md` — POSIX standard, verified locally.
- `grep -h '^- ' AGENTS.core.md | awk '{print length}' | sort -rn | head -1` — used at plan time, returned `1004`.
- `python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt --index-file AGENTS.md AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` — argument shape verified at `scripts/lint-rule-ids.py:14` (Usage docstring).
- `bash scripts/lint-agents-compound-sync.sh` — file exists at `scripts/lint-agents-compound-sync.sh`.
- `python3 scripts/lint-agents-enforcement-tags.py` — file exists at `scripts/lint-agents-enforcement-tags.py`.
- `bash .claude/hooks/session-rules-loader.test.sh` — file exists per PR #3496 commit history (`.claude/hooks/session-rules-loader.test.sh` named in test plan).

## Out of Scope (deferred)

- **Rule retirement via 8-week telemetry zero-hit signal.** `knowledge-base/project/rule-metrics.json` was bootstrapped 2026-05-10; earliest 8-week window completes ~2026-07-04. Tracking: file a follow-up issue at PR merge time titled "AGENTS.md rule retirement via 8w telemetry (post 2026-07-04)" labeled `type/chore`, `priority/p3-low`, milestone `Post-MVP / Later`. (Plan/work-skill creates the tracking issue per `wg-when-deferring-a-capability-create-a`.)
- **Rule-budget hooks at commit time.** A pre-commit hook that re-runs the rule-budget computation and rejects commits that push always-loaded payload past 22 k would prevent recurrence; out of scope for this PR. Tracking: file a follow-up issue "Pre-commit hook for AGENTS.md rule-budget gate" labeled `type/chore`, `priority/p3-low`.
- **Splitting `AGENTS.core.md` further (e.g., a security-tier sidecar).** PR #3496 already chose the docs/rest/core split; further splitting is a follow-up architectural decision, not a same-PR trim.

## Verified Citations (deepen-plan live checks)

All external references in this plan were resolved live at deepen-plan time (2026-05-12). Recorded here for plan-review audit per `Quality Checks`:

```text
$ gh pr view 3496 --json state,title --jq '"#3496: \(.state) - \(.title)"'
#3496: MERGED - WIP: feat-agents-md-change-class-loader

$ for n in 3679 2887 2865 2618 2880 2954 2681 3603; do gh issue view $n ...; done
#3679: OPEN - chore: AGENTS always-loaded payload over 22k critical threshold
#2887: CLOSED - SECURITY P0: dev and prd Doppler configs target the same Supabase project
#2865: CLOSED - chore: shrink AGENTS.md to ≤32k bytes via retired-ids allowlist + discoverability litmus
#2618: CLOSED - infra: drift detected in web-platform
#2880: MERGED - docs(infra): plan + learning for recurring deploy_pipeline_fix drift
#2954: MERGED - fix(cc-soleur-go): drain code-review backlog #2918-#2923 cleanup bundle
#2681: CLOSED - ops: admin-IP drift caused prod SSH lockout
#3603: CLOSED - hardening: cc-soleur-go transcript persistence — cross-tenant invariants

$ gh label list --limit 200 | grep -E "^(type/chore|priority/p3-low)"
priority/p3-low — Nice-to-have, no time pressure
type/chore     — Maintenance, refactoring, tech debt

$ wc -c AGENTS.md AGENTS.core.md   # baseline
 4602 AGENTS.md
20020 AGENTS.core.md
24622 total

$ grep -h '^- ' AGENTS.core.md | awk '{print length}' | sort -rn | head -5
1004 729 715 602 589

# All 11 rule IDs cited in plan body verified active:
active: hr-write-boundary-sentinel-sweep-all-write-sites
active: hr-type-widening-cross-consumer-grep
active: wg-plan-prescribed-skills-must-run-inline
active: wg-use-closes-n-in-pr-body-not-title-to
active: wg-every-session-error-must-produce-either
active: hr-menu-option-ack-not-prod-write-auth
active: hr-never-paste-secrets-via-bang-prefix
active: pdr-when-a-user-message-contains-a-clear
active: cq-pg-security-definer-search-path-pin-pg-temp
active: cq-agents-md-tier-gate
active: cq-agents-md-why-single-line
```

No fabricated or retired rule IDs cited — verified per learning `2026-05-09-llm-authored-plans-cite-fabricated-and-retired-rule-ids.md`.
