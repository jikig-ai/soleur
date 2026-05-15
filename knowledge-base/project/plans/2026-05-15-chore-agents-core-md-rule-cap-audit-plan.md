---
title: chore(AGENTS) — core.md per-rule cap audit + B_ALWAYS shrink to clear active REJECT
date: 2026-05-15
issue: 3834
branch: feat-one-shot-3834
lane: procedural
type: agents-md-maintenance
requires_cpo_signoff: false
deepened_on: 2026-05-15
related_prs: [3808, 3833, 3837, 3839, 3681, 2754, 3496]
---

# chore(AGENTS): audit core.md for additional per-rule cap violations beyond hr-no-dashboard-eyeball-pull-data-yourself

## Enhancement Summary

**Deepened on:** 2026-05-15
**Sections enhanced:** 4 (Overview, Implementation Phases, Acceptance Criteria, Risks)
**Verification passes added:**
1. Live `gh` verification of every cited PR/issue (#3808, #3833, #3837, #3839, #3681, #2754, #3496, #3356, #2618, #2880, #2857, #2887, #2954) — all exist; states cited.
2. Live `grep -E "\[id: <id>\]"` verification of every cited rule ID against `AGENTS.{md,core.md,docs.md,rest.md}` — all 18 distinct citations resolve to ACTIVE rules; cross-checked against `scripts/retired-rule-ids.txt` (zero hits).
3. Live `gh label list` verification of DEF-1 follow-up labels (`type/chore`, `domain/engineering`, `priority/p3-low`) — all 3 exist.
4. Verified canonical test paths: `.claude/hooks/session-rules-loader.test.sh` + `.claude/hooks/session-rules-loader-headless.test.sh` + `scripts/lint-agents-rule-budget.test.sh` (corrected from a fabricated `plugins/soleur/test/session-rules-loader-test.sh` in plan v1).
5. Cited `sed -n '88,115p' .claude/hooks/session-rules-loader.sh` output verbatim in Loader Class Fit section below.

### Key Improvements (deepen-pass corrections)

1. **Test paths corrected.** Plan v1's AC3 cited `plugins/soleur/test/session-rules-loader-test.sh` — a fabricated path. Canonical loader tests are at `.claude/hooks/session-rules-loader.test.sh` and `.claude/hooks/session-rules-loader-headless.test.sh`. Linter smoke test is at `scripts/lint-agents-rule-budget.test.sh`. All three now cited in AC3.
2. **Normalized colloquial rule-ID truncations.** Plan v1 referenced `hr-no-dashboard-eyeball` (short form) in 3 places where the full ID `hr-no-dashboard-eyeball-pull-data-yourself` is the active rule. Full IDs now used in citation contexts; short forms retained only as quoted text from prior PR bodies.
3. **Loader-class-fit pre-cited.** The `sed -n '88,115p' .claude/hooks/session-rules-loader.sh` output is reproduced inline (per the deepen-plan checklist's loader-class-fit mirror bullet) so the demotion-candidate gate at Phase 2.1 has its evidence locked in at plan time.
4. **B_ALWAYS post-trim math grounded.** Required reduction is now stated as **≥ 533 B** (22,499 → 21,966 = 533 B reduction to match #3837's 34 B headroom).
5. **Phase 2.1.5 deferred-demotion-decision-tree added.** If the 6-rule Why-trim hits the 533 B target, demotion is skipped entirely — the loader-class-fit gate only fires if the planner reaches it.

### New Considerations Discovered

- **#3839 was scope-out, not regression.** PR #3839's body explicitly named B_ALWAYS as a pre-existing CRITICAL condition deferred to follow-up. This plan IS that follow-up; the bundling with #3834 is justified by the shared linter-script touchpoint, not by accidental scope-creep.
- **Brainstorm Approach D structural shrink is now overdue.** The 2026-04-23 brainstorm framed structural shrink (`Approach D` — discoverability-litmus + retired-rule-ids allowlist) as a separate effort. With this PR being the second Why-trim pass within 30 days, DEF-1 is no longer a "nice-to-have" follow-up; the growth rate has caught up. DEF-1 promoted from advisory to actively-tracked.

---

Closes #3834.

## Overview

Issue #3834 asks for an audit pass on the per-rule body cap (600 B, enforced by `scripts/lint-agents-rule-budget.py`) across `AGENTS.{core,docs,rest}.md` to catch any silent violations beyond `hr-no-dashboard-eyeball-pull-data-yourself` (which PR #3808 trimmed from 1,150 B → 582 B).

**Per-rule audit result (run at plan time, single canonical command from the issue body):**

```bash
$ awk '/^- / { if (length($0) > 600) print FILENAME ":" NR ": " length($0) " B" }' \
    AGENTS.core.md AGENTS.docs.md AGENTS.rest.md
# (zero output — no per-rule violations)
```

The literal close-criterion in #3834 is already met. The longest rule per sidecar:

| Sidecar | Longest rule | Bytes |
|---|---|---|
| `AGENTS.core.md` | `hr-menu-option-ack-not-prod-write-auth` (line 26) | 582 |
| `AGENTS.docs.md` | `cq-agents-md-why-single-line` (line 6) | 586 |
| `AGENTS.rest.md` | `wg-use-closes-n-in-pr-body-not-title-to` (line 18) | 571 |

All 77 rule bodies across the three sidecars are under the 600 B per-rule cap.

**However, while running the audit linter as a whole, the OTHER axis enforced by the same script — `B_ALWAYS` — is now in REJECT state:**

```bash
$ python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md
[REJECT] B_ALWAYS=22499 > 22000 (AGENTS.md=4785 + AGENTS.core.md=17714). exit=1
```

PR #3839 (merged ~30 min before this plan was drafted) added `hr-autonomous-loop-skill-api-budget-disclosure` to core (+439 B vs the post-#3837 baseline of 22,687 → 22,499 net after a partial `hr-no-dashboard-eyeball` trim). #3839's PR body explicitly scoped-out the resulting CRITICAL state as a "pre-existing condition" deferred to a follow-up. **Every subsequent AGENTS-touching commit will be blocked by lefthook** until B_ALWAYS drops back under 22,000.

The plan therefore packages two deliverables under #3834:

1. **AC1 — Per-rule audit closure (the issue's literal scope).** Codify the audit command, record the zero-violation finding in a learning file, close #3834.
2. **AC2 — B_ALWAYS shrink to clear the active REJECT and restore the 34 B headroom buffer #3837 established.** Same byte-trim playbook as #3837 (Why-tail trims on non-compliance-tier rules; optional `wg-*` core→rest demotion if a clean trigger-class fit exists).

Bundling is justified because the audit (#3834) and the shrink are operating on the same script's output (`scripts/lint-agents-rule-budget.py`) — running the linter is the audit action AND surfaces the live REJECT. Splitting would force every AGENTS commit between now and the follow-up to use `LEFTHOOK=0`, which AGENTS.md forbids (`wg-before-every-commit-run-compound-skill` workflow + general no-bypass posture).

## Research Reconciliation — Spec vs. Codebase

| Claim in issue body | Codebase reality (verified at plan time) | Plan response |
|---|---|---|
| "PR #3808 trimmed `hr-no-dashboard-eyeball` 1,150 B → 582 B" | PR #3839 further trimmed it to **488 B** at line 35 of core.md as part of the autonomous-loop-disclosure backport. | Cite the correct current size (488 B) in AC1's record. |
| "Compound's `[WARNING] longest rule is L bytes`" | Current longest in core is `hr-menu-option-ack-not-prod-write-auth` at 582 B — not 488 B (post-trim hr-no-dashboard). | Record longest-rule-per-sidecar table (above). |
| "B_ALWAYS=21,966 with 34 B headroom" (parent-agent CONTEXT NOTE) | B_ALWAYS=**22,499** (REJECT). Parent context is stale by one merge cycle (#3839 landed after #3837). | Plan must shrink B_ALWAYS, not assume it's clean. |
| 5 compliance-tier rules listed in CONTEXT NOTE | Verified via `grep -n "compliance-tier" AGENTS.{core,docs,rest}.md`: exactly 5 hits, all in core.md, IDs match the CONTEXT NOTE list. | Use the verified list verbatim — Why-tails on these 5 rules are off-limits. |

## User-Brand Impact

**If this lands broken, the user experiences:** AGENTS.md sidecar load-class regression — a demoted/trimmed rule fails to fire on its trigger surface, causing a previously-caught defect class (e.g., a workflow-gate skip, a silent-fallback) to ship undetected. Operator's PR-time gates degrade silently. The directly-affected user is the Soleur founder operator running `/work` against guidance they expect to be enforced.

**If this leaks, the user's data is exposed via:** N/A — this PR touches no PII, secrets, or data surfaces. Pure documentation/governance edit on agent-internal guidance.

**Brand-survival threshold:** `none` — reason: AGENTS.md governance edits are agent-internal API surface; failure mode is reduced PR-time defense, not a user-facing failure. The shrink mechanism (Why-tail trim + optional wg-* demote) is byte-only; rule semantics are preserved. The 5 compliance-tier rules (`hr-exhaust-all-automated-options-before`, `hr-menu-option-ack-not-prod-write-auth`, `hr-never-git-add-a-in-user-repo-agents`, `hr-never-paste-secrets-via-bang-prefix`, `cq-pg-security-definer-search-path-pin-pg-temp`) are off-limits — these are the ones whose Whys map to brand-survival incidents (#2618/#2880/#2857/#2887/#2954 + PR-B prd-JWT leak).

## Files to Edit

- `AGENTS.core.md` — Why-tail trims on 6-8 non-compliance-tier rules (see §Implementation Phases).
- `AGENTS.md` — if any `wg-*` rule is demoted core→rest, flip the pointer-index entry.
- `AGENTS.rest.md` — if any `wg-*` rule is demoted core→rest, append the body to `## Workflow Gates`.
- `knowledge-base/project/learnings/2026-05-15-agents-md-per-rule-audit-zero-violations.md` — **CREATE.** Records the audit command, the zero-violation result, the top-rule table per sidecar, and the deferred follow-ups (e.g., "next-longest rule is `hr-menu-option-ack-not-prod-write-auth` at 582 B with 18 B headroom — flagged for monitoring but not actioned, compliance-tier"). This is the artifact a future audit pass reads to know the cap is currently green.

## Files to Create

- `knowledge-base/project/learnings/2026-05-15-agents-md-per-rule-audit-zero-violations.md` (per above).

## Open Code-Review Overlap

```bash
$ gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
$ for f in AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md; do
    jq -r --arg path "$f" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
  done
```

None at plan-write time.

## Implementation Phases

### Phase 0 — Preconditions (must pass before Phase 1)

0.1. **Verify per-rule cap is clean.**
```bash
awk '/^- / && length($0) > 600' AGENTS.core.md AGENTS.docs.md AGENTS.rest.md
# Expected: zero output.
```

0.2. **Verify B_ALWAYS is in REJECT.**
```bash
python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md
echo "exit=$?"
# Expected: [REJECT] B_ALWAYS=22499 > 22000. exit=1.
```

0.3. **Confirm compliance-tier rule list.** Exactly 5, all in core.md:
```bash
grep -n "\[compliance-tier\]" AGENTS.core.md AGENTS.docs.md AGENTS.rest.md
# Expected: 5 lines, all in AGENTS.core.md (lines 12, 26, 28, 31, 57).
```

0.4. **Capture baseline byte sizes** for the post-trim delta math:
```bash
wc -c AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md
# Expected: AGENTS.md=4785, AGENTS.core.md=17714.
```

### Phase 1 — Per-rule audit codification (closes #3834 literal scope)

1.1. Create `knowledge-base/project/learnings/2026-05-15-agents-md-per-rule-audit-zero-violations.md` with:
   - YAML frontmatter (`category`, `tags`, `related: [3833, 3834, 3808, 3837, 3839]`).
   - The audit command (single-line `awk`).
   - The zero-violation finding + date.
   - Top-rule-per-sidecar table (582 / 586 / 571 B).
   - Footnote: "Next-longest rule is `hr-menu-option-ack-not-prod-write-auth` at 582 B (18 B headroom). Compliance-tier — off-limits for Why-tail trim. Monitor only."

1.2. **No edit to AGENTS.* files for Phase 1.** The audit is purely observational; the learning file is the artifact.

### Phase 2 — B_ALWAYS shrink (clears active REJECT, restores 34 B headroom)

**Target:** `B_ALWAYS ≤ 21,966 B` (the same headroom #3837 established). Required reduction: ≥ 533 B from current 22,499 B.

**Per-rule trim budget table** (target ~70 B/rule average, all on non-compliance-tier rules in `AGENTS.core.md` since core is the sidecar pulling B_ALWAYS over budget):

| Rule ID | Line | Current B | Trim target | Method |
|---|---|---|---|---|
| `hr-write-boundary-sentinel-sweep-all-write-sites` | 28 | 524 | ~80 B | Collapse "Full grep pattern + call-site example: …" pointer line; the work skill SKILL.md §Phase 0 already documents the pattern. |
| `hr-gdpr-gate-on-regulated-data-surfaces` | 32 | 504 | ~80 B | Compress enforcement-tag list; the canonical regex pointer in the rule already routes to gdpr-gate/SKILL.md. |
| `hr-no-dashboard-eyeball-pull-data-yourself` | 35 | 488 | ~50 B | Trim "Subjective calls stay human; technical interpretation does not." (redundant given the Per-rule body already names the criterion); keep the `**Why:** #3356` citation. |
| `hr-type-widening-cross-consumer-grep` | 30 | 484 | ~70 B | Compress "Full grep pattern + Message.usage example: `plugins/soleur/skills/work/SKILL.md` §Phase 0." pointer — same anti-duplication pattern as the write-boundary trim. |
| `hr-ssh-diagnosis-verify-firewall` | 27 | 469 | ~60 B | Compress runbook path mention (the rule already names the file; keep the file path, drop the redundant "Runbook:" label). |
| `hr-autonomous-loop-skill-api-budget-disclosure` | 16 | 468 | ~50 B | Compress the `[skill-enforced: …]` tag (use shorter file pointer) + `**Why:**` tail. New rule from #3839; over-allocated tag prose. |
| `pdr-when-a-user-message-contains-a-clear` | 61 | 441 | ~50 B | Compress prose; this is a routing-heuristic rule, not a brand-survival incident. |
| `hr-when-a-plan-specifies-relative-paths-e-g` | 9 | 419 | ~30 B | Compress `**Why:**` tail (already trimmed in #3837; one more pass possible). |

**Total trim target:** ~470 B from Why-tails + tag compression. **Buffer:** if Why-trim alone falls short of 533 B, demote one `wg-*` rule core→rest. **Candidate:** `wg-zero-agents-until-user-confirms` (line 45 of `AGENTS.core.md`, 359 B) — verify loader-class fit before proposing.

2.1. **Loader-class-fit evidence (reproduced inline at plan time so the demotion-candidate gate doesn't drift).** Per the AGENTS.md "core→rest demotion" Sharp Edge:

```
# .claude/hooks/session-rules-loader.sh lines 88-115 (verbatim at plan time):
DOCS_RE='\.(md|markdown|txt|njk|html)$|^\.github/.*\.md$'
CODE_RE='\.(ts|tsx|js|jsx|py|go|rs|swift|kt|java|c|cpp|cs|php|sh|bash|zsh|rb)$'
INFRA_RE='\.tf$|^apps/[^/]+/infra/|\.github/workflows/|/?Dockerfile|/migrations/.*\.sql$'

# Class selection. Multi-class / empty / explicit override → load everything (fail-closed).
CLASSES="core"
if [[ "${LOADER_FAIL_CLOSED:-}" == "1" ]]; then
  CLASSES="core docs-only rest"
elif [[ -z "$CHANGES" ]]; then
  CLASSES="core docs-only rest"
elif (( HAS_CODE + HAS_INFRA + HAS_DOCS > 1 )); then
  CLASSES="core docs-only rest"
elif (( HAS_DOCS == 1 )); then
  CLASSES="core docs-only"
elif (( HAS_CODE == 1 || HAS_INFRA == 1 )); then
  CLASSES="core rest"
fi
```

For each demotion candidate, classify trigger surface against the three regexes. Required outcome: rule MUST load on every class its trigger surface fires on. `AGENTS.rest.md` is NOT loaded on `docs-only` class (only `core + docs-only` are). If the demotion candidate's trigger is or includes docs-only, KEEP in core and find another trim avenue. **CPO sign-off PR #3496 condition 3:** only `wg-*` rules may be demoted; `hr-*` may not be demoted regardless of loader-class fit.

2.1.5. **Demotion decision tree.** If Phase 2.2 Why-trims reach the ≥533 B reduction target on `AGENTS.core.md` alone, **demotion is skipped entirely** — DO NOT demote a rule "just because we can". The byte-trim path preserves the always-loaded behavior of every existing rule on its trigger class. Demotion is only invoked if Why-trims fall short.

2.2. **Apply Phase 2 trims.** Edit `AGENTS.core.md` in a single commit; preserve all `[id: ...]` tags, all `[compliance-tier]` markers, all canonical incident-citation `**Why:** #NNNN` references. Compliance-tier rules' Whys are off-limits.

2.3. **Verify B_ALWAYS post-trim.**
```bash
python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md
echo "exit=$?"
# Expected: [OK] B_ALWAYS<=21,966. exit=0.
```

2.4. **Verify rule-IDs lint.**
```bash
python3 scripts/lint-rule-ids.py
echo "exit=$?"
# Expected: exit=0 (no IDs removed; all 77 rule IDs preserved).
```

2.5. **Smoke-test the loader + linter test suites.**
```bash
bash .claude/hooks/session-rules-loader.test.sh           # 14/14 expected
bash .claude/hooks/session-rules-loader-headless.test.sh  # 4/4 expected
bash scripts/lint-agents-rule-budget.test.sh              # 15/15 expected
```

### Phase 3 — Commit + PR

3.1. Single atomic commit: `chore(AGENTS): close #3834 per-rule audit + clear B_ALWAYS REJECT`.
3.2. PR body: cite #3834 (`Closes #3834`) AND name the B_ALWAYS shrink as the bundled deliverable. Reference #3837 / #3839 / #3808 as the pattern lineage.
3.3. AC checklist from §Acceptance Criteria below.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Per-rule audit recorded.** `knowledge-base/project/learnings/2026-05-15-agents-md-per-rule-audit-zero-violations.md` exists, contains the audit command verbatim, the zero-violation finding, and the per-sidecar top-rule table.
- [ ] **AC1.1 — Audit command verification.**
  ```bash
  awk '/^- / && length($0) > 600' AGENTS.core.md AGENTS.docs.md AGENTS.rest.md
  # Expected: zero output.
  ```
- [ ] **AC2 — B_ALWAYS in OK state.**
  ```bash
  python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md
  # Expected: exit=0, B_ALWAYS ≤ 21,966 (~34 B headroom under reject cap).
  ```
- [ ] **AC2.1 — Rule-ID immutability preserved.** `python3 scripts/lint-rule-ids.py` exits 0; `git diff` shows zero `[id: …]` tag removals.
- [ ] **AC2.2 — Compliance-tier Whys preserved.** `git diff -U0 AGENTS.core.md | grep '^-' | grep -c '\[compliance-tier\]'` returns 0 (no deletion of compliance-tier rule lines); the 5 compliance-tier rule Whys (`hr-exhaust-all-automated-options-before`, `hr-menu-option-ack-not-prod-write-auth`, `hr-never-git-add-a-in-user-repo-agents`, `hr-never-paste-secrets-via-bang-prefix`, `cq-pg-security-definer-search-path-pin-pg-temp`) are byte-identical pre/post.
- [ ] **AC2.3 — Canonical incident citations preserved.** Every `**Why:** #NNNN` reference in `AGENTS.core.md` pre-edit is still present post-edit. Verify via:
  ```bash
  diff <(git show HEAD~1:AGENTS.core.md | grep -oE '\*\*Why:\*\*[^.]*#[0-9]+' | sort) \
       <(grep -oE '\*\*Why:\*\*[^.]*#[0-9]+' AGENTS.core.md | sort)
  # Expected: zero diff.
  ```
- [ ] **AC2.4 — If any demotion happened, AGENTS.md index pointer flipped + AGENTS.rest.md body appended.** Verified by `grep -c '<id> → rest' AGENTS.md` returning 1 and `grep -c '\[id: <id>\]' AGENTS.rest.md` returning 1.
- [ ] **AC2.5 — Loader-class fit verified for any demotion.** PR body cites the `sed -n '88,115p' .claude/hooks/session-rules-loader.sh` output + the class-fit determination per the AGENTS.md Sharp Edge rule.
- [ ] **AC3 — Loader + linter test suites pass.** All three of:
  - `bash .claude/hooks/session-rules-loader.test.sh` exits 0 (14/14 tests, per #3837 baseline).
  - `bash .claude/hooks/session-rules-loader-headless.test.sh` exits 0 (4/4 tests, per #3837 baseline).
  - `bash scripts/lint-agents-rule-budget.test.sh` exits 0 (15/15 tests, per #3837 baseline).
- [ ] **AC4 — Atomic commit.** `git log feat-one-shot-3834 --not main --oneline` returns exactly one commit modifying `AGENTS.*md` files.
- [ ] **AC5 — `Closes #3834` in PR body** (not title), per `wg-use-closes-n-in-pr-body-not-title-to`.
- [ ] **AC6 — Lefthook passes on the PR commit** without `LEFTHOOK=0` bypass.

### Post-merge (operator)

None. The shrink is self-applying via the merged commit; subsequent AGENTS-touching commits will simply succeed at lefthook without bypass.

## Test Scenarios

1. **Audit command in isolation.** Run `awk '/^- / && length($0) > 600' AGENTS.{core,docs,rest}.md` against the post-merge state — must return zero. Repeat against `HEAD~1` to confirm the pre-PR state was also clean (this anchors the audit's framing: per-rule cap was clean, the bundled shrink targeted B_ALWAYS).
2. **Linter end-to-end.** Run `python3 scripts/lint-agents-rule-budget.py` and confirm `exit=0` with the `[OK] B_ALWAYS=...` line.
3. **Demotion negative test (only if applied).** If a `wg-*` was demoted core→rest, simulate a `docs-only` session (touch only an `.md` file) and verify the loader does NOT load `AGENTS.rest.md` — then verify the demoted rule's trigger surface does NOT include docs-only file classes (otherwise the demotion is a regression). Loader behavior: `LOADER_FAIL_CLOSED=1 bash .claude/hooks/session-rules-loader.sh` for fail-closed mode.

## Risks

- **Why-tail trims accumulate ambiguity over generations.** Each shrink iteration trims the same Why-tails further. PR #3837 already did a Why-tail pass; #3834 is the second. At some point Whys lose semantic distinguishability between rules. **Mitigation:** the 8-rule trim budget keeps individual trims to ~30-80 B (not aggressive); the 5 compliance-tier rules are off-limits forever; canonical `#NNNN` citations are preserved as the load-bearing audit-trail.
- **B_ALWAYS growth rate.** PR #3839 added one rule and consumed all 34 B of headroom from #3837 in <24 hours. The 34 B buffer this plan restores will likely be consumed by the next AGENTS-touching PR. Structural fix (Approach D from the 2026-04-23 brainstorm — discoverability litmus + retired-rule-ids allowlist) is deferred to a separate effort.  **Mitigation:** file a follow-up to track structural shrink — see §Deferrals.
- **`hr-autonomous-loop-skill-api-budget-disclosure` was just added (#3839).** Trimming it within 24h of its merge risks losing the operator-facing context the rule was designed to convey. **Mitigation:** trim only the `[skill-enforced: …]` tag and the `**Why:** #3819 closes #3809` tail prose (citation kept as `#3819`); the rule body + sentinel reference stay intact.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is populated; threshold = `none`.
- **Re-running the audit command MUST be a pre-merge gate.** If a subsequent commit on this branch adds prose to AGENTS that pushes a rule over 600 B, AC1.1 fails. The audit is anchored at PR-merge time, not at plan time.
- **The 5 compliance-tier rule Whys are off-limits.** Carried forward from #3837's CPO sign-off (PR #3496 condition 3 + the trim playbook the brainstorm encodes). Touching them in this PR would be a workflow violation regardless of byte impact.
- **Loader-class-fit gate fires on any demotion.** Per the AGENTS.md "core→rest demotion" Sharp Edge: `wg-*` demotions only; never `hr-*`; loader-class fit verified against `.claude/hooks/session-rules-loader.sh` lines 88-115. The Phase 2 trim plan defaults to Why-trims only and avoids demotion; demotion is a fallback if Why-trims fall short of 533 B.

## Deferrals (tracked separately)

- **DEF-1: Structural B_ALWAYS shrink (Approach D from `knowledge-base/project/brainstorms/2026-04-23-agents-md-budget-revisit-brainstorm.md`).** Discoverability-litmus + retired-rule-ids allowlist to actually shrink the rule count, not just trim Why-tails. Without this, every 1-2 new rules require a follow-up Why-trim pass. **Re-evaluate when:** the third Why-trim pass lands (this plan is the second after #3837); OR B_ALWAYS hits 22,000 a third time within 7 days. File: `gh issue create --title "chore(AGENTS): structural B_ALWAYS shrink via Approach D (discoverability litmus + retired-rule-ids allowlist)" --milestone "Post-MVP / Later" --label "type/chore,domain/engineering,priority/p3-low"` — to be done by the planner at PR-creation time if not already filed.
- **DEF-2: Lefthook B_ALWAYS WARN-tier escalation.** Currently `B_ALWAYS_WARN=20000` is a stderr-only warn; agents routinely run past it without escalation until REJECT at 22,000. Consider raising the warn floor and making it actionable (e.g., block on a label, or surface in compound). Re-evaluate after DEF-1 lands.

## Research Insights

**PR / Issue citation verification (live `gh` calls, deepen-plan checklist):**

| Ref | State | Title | Used in plan as |
|---|---|---|---|
| #3808 | MERGED | feat(workflow): brainstorm Phase 1.0.5/2.5 + SKILL.md description budget rule | Lineage: original `hr-no-dashboard-eyeball-pull-data-yourself` trim 1,150→582 B. |
| #3833 | CLOSED | chore(AGENTS): shrink B_ALWAYS below 22,000 byte critical threshold | Sibling issue (parallel worktree). Plan v1 context note. |
| #3834 | OPEN | chore(AGENTS): audit core.md for additional per-rule cap violations beyond hr-no-dashboard-eyeball | This plan's parent issue. |
| #3837 | MERGED | chore(AGENTS): shrink B_ALWAYS below 22,000-byte critical threshold | Canonical playbook (Why-trim + 1 demote, 22,687 → 21,966 B). |
| #3839 | MERGED | feat: backport API-budget operator preamble to autonomous-loop skills | Pushed B_ALWAYS back over reject (22,499); declared scope-out. |
| #3681 | MERGED | chore(agents): trim always-loaded payload 24,622 → 21,985 B | Initial structural trim pass. |
| #2754 | MERGED | feat-agents-rule-threshold | Pointer-migration measured +21 B net; abandoned-pattern reference. |
| #3496 | MERGED | feat-agents-md-change-class-loader | CPO sign-off + condition 3 (no hr-* demotions). |

**Rule-ID citation verification (active vs retired):**

All 18 distinct rule IDs cited in this plan resolve to ACTIVE rules in `AGENTS.{md,core.md,docs.md,rest.md}`. Zero retired-ID citations against `scripts/retired-rule-ids.txt`. Two substring artifacts (`hr-no-dashboard`, `hr-no-dashboard-eyeball`) were colloquial truncations in narrative prose; normalized to the full active ID `hr-no-dashboard-eyeball-pull-data-yourself` in citation contexts.

**Label verification (DEF-1 follow-up issue):**

```bash
$ for l in type/chore domain/engineering priority/p3-low; do
    gh label list --limit 200 | grep -E "^$l\b" && echo OK || echo MISSING
  done
# All three: OK
```

**Test-path verification (corrected from plan v1):**

```bash
$ find . -path ./node_modules -prune -o -name "*session-rules-loader*" -print
.claude/hooks/session-rules-loader.sh                 # the loader
.claude/hooks/session-rules-loader.test.sh            # 14-test suite
.claude/hooks/session-rules-loader-headless.test.sh   # 4-test headless suite

$ find . -name "lint-agents-rule-budget*"
scripts/lint-agents-rule-budget.py                    # the linter
scripts/lint-agents-rule-budget.test.sh               # 15-test smoke suite
```

Plan v1's reference to `plugins/soleur/test/session-rules-loader-test.sh` was a fabrication — corrected throughout.

**Linter contract (verbatim from `scripts/lint-agents-rule-budget.py`):**

```python
B_ALWAYS_WARN   = 20000   # stderr warn, exit 0
B_ALWAYS_REJECT = 22000   # reject, exit 1
PER_RULE_CAP    = 600     # per-rule body cap, applied to ^- lines under SECTIONS headings
```

**Pre-pass linter state (run at plan write time):**

```bash
$ python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md
[REJECT] B_ALWAYS=22499 > 22000 (AGENTS.md=4785 + AGENTS.core.md=17714).
exit=1
```

**Per-rule cap state (verbatim audit command from #3834 issue body):**

```bash
$ awk '/^- / { if (length($0) > 600) print FILENAME ":" NR ": " length($0) " B" }' \
    AGENTS.core.md AGENTS.docs.md AGENTS.rest.md
# zero output — #3834's literal close criterion already met.
```

**Top-15 longest rules in `AGENTS.core.md` (informational, for trim-target selection):**

| Bytes | Line | Rule ID | Trim-eligible? |
|---|---|---|---|
| 582 | 26 | `hr-menu-option-ack-not-prod-write-auth` | NO (compliance-tier) |
| 557 | 31 | `hr-never-paste-secrets-via-bang-prefix` | NO (compliance-tier) |
| 535 | 57 | `cq-pg-security-definer-search-path-pin-pg-temp` | NO (compliance-tier) |
| 524 | 28 | `hr-write-boundary-sentinel-sweep-all-write-sites` | YES |
| 504 | 32 | `hr-gdpr-gate-on-regulated-data-surfaces` | YES |
| 502 | 12 | `hr-exhaust-all-automated-options-before` | NO (compliance-tier) |
| 488 | 35 | `hr-no-dashboard-eyeball-pull-data-yourself` | YES |
| 484 | 30 | `hr-type-widening-cross-consumer-grep` | YES |
| 469 | 27 | `hr-ssh-diagnosis-verify-firewall` | YES (already trimmed in #3837 — secondary pass possible) |
| 468 | 16 | `hr-autonomous-loop-skill-api-budget-disclosure` | CAUTION (newly added #3839; trim tag/why only) |
| 441 | 61 | `pdr-when-a-user-message-contains-a-clear` | YES |
| 419 | 9 | `hr-when-a-plan-specifies-relative-paths-e-g` | YES (already trimmed in #3837) |
| 419 | 40 | `wg-every-feature-listed-in-a-roadmap-phase` | YES |
| 413 | 53 | `wg-plan-prescribed-skills-must-run-inline` | YES |
| 408 | 13 | `hr-never-label-any-step-as-manual-without` | YES |

8 rule slots projected for ~530 B aggregate trim, with 6 fallback alternates if any single trim is rejected during /work.

**Edge cases / sharp edges discovered in deepen:**

- **Why-tail trim ambiguity over generations.** This is the second Why-trim pass within 30 days. #3837 trimmed the same families. The pattern is structurally byte-neutral over the long run (PR #2754 measured +21 B net on pointer-migration); each pass extracts diminishing returns. **Mitigation:** the brainstorm-prescribed Approach D (DEF-1) is the only structural exit; this PR is a tactical buffer, not a strategy.
- **Trimming the newly-added rule (#3839) within 24h.** Risks signaling that prose added at PR time is "extra". **Mitigation:** trim only the `[skill-enforced: ...]` tag literal (which is mechanical metadata, not Why-prose) and tighten the `**Why:** #3819 closes #3809 disclosure asymmetry` tail to `**Why:** #3819`. Sentinel reference (`disclaims warranty for runtime cost`) MUST stay byte-identical — it's the rule's load-bearing assertion target.
- **`hr-no-dashboard-eyeball-pull-data-yourself` was just trimmed in #3839.** Hitting it again risks compounding loss of context. **Mitigation:** keep the line at-or-near 480 B (current 488 B); the proposed ~50 B trim drops it to ~440 B, still above the bottom-quartile of sibling rules.

**B_ALWAYS post-trim math (target: 21,966 B, matching #3837's headroom):**

```
Current B_ALWAYS:  22,499 B
Target B_ALWAYS:   21,966 B
Required reduction:   533 B from AGENTS.core.md (AGENTS.md is index-only, no edits planned)

Sum of trim-budget cells in Phase 2 table:
  80 + 80 + 50 + 70 + 60 + 50 + 50 + 30 = 470 B
  
Gap: 533 - 470 = 63 B shortfall on the prose-only path.

Resolution path:
- (A) Take one extra ~60 B trim from a 9th rule (e.g., `wg-every-feature-listed-in-a-roadmap-phase` at 419 B → ~360 B).
- (B) Demote one wg-* (loader-class-fit verified per Phase 2.1) — only if (A) is rejected.

Default to (A); demotion only if (A)'s 9th trim is rejected by /work or review.
```

## References

- **Issue:** #3834 (this plan's parent)
- **Sibling PR (just merged):** #3837 — established the Why-trim + demote playbook this plan inherits. Cited as canonical pattern in Phase 2.
- **Sibling PR (just merged):** #3839 — added `hr-autonomous-loop-skill-api-budget-disclosure`, scoped-out the B_ALWAYS REJECT, declared the pre-existing-condition framing.
- **Lineage:** #3808 (original `hr-no-dashboard-eyeball` trim 1,150 B → 582 B), #3681 (initial trim pass 24.6 KB → 22.0 KB), #2754 (pointer-migration measured +21 B net — established that pointer-migration is not the byte path).
- **Brainstorm (structural shrink):** `knowledge-base/project/brainstorms/2026-04-23-agents-md-budget-revisit-brainstorm.md` — the Approach D direction, deferred to DEF-1.
- **Lint script:** `scripts/lint-agents-rule-budget.py` — the canonical enforcer; thresholds: `B_ALWAYS_WARN=20000`, `B_ALWAYS_REJECT=22000`, `PER_RULE_CAP=600`.
- **Sidecar loader:** `.claude/hooks/session-rules-loader.sh` lines 88-115 — class-selection branch consulted for loader-class fit.
- **Foundational learning:** `knowledge-base/project/learnings/2026-05-15-multi-stage-premise-validation-compounds-and-agents-sidecar-loader-class-fit.md` (loader-class-fit canonical reference).
