# Learning: AGENTS always-loaded byte-budget trims come from rationale bytes, not directive bytes

## Problem

Issue #4599: the always-loaded AGENTS payload `B_ALWAYS = len(AGENTS.md) + len(AGENTS.core.md)` was 26814 B, over the 22000 B reject ceiling, and the budget linter (`scripts/lint-agents-rule-budget.py`) was lefthook-pre-commit-only, never CI-wired. The deepened plan committed to **path (a)** (trim under 22000 + wire the gate) and modelled reaching core ≈ 15741 / B_ALWAYS ≈ 21212 (788 B margin) via levers L1 (over-cap trims) + L3 (demote 2 ship-phase `wg-*` gates) + **L2 "imperative tightening ≈ −2100 B (~12% of the residual core body)"**.

In execution, L1 + L3 + the safe parts of L2 (collapsing `see knowledge-base/…md` path tails and multi-clause rationale to `**Why:** #NNNN` breadcrumbs) landed at **B_ALWAYS 22782** — a real −15% reduction, but still ~782 B over 22000. The modelled "≈ −2100 B of imperative tightening" did not exist: once every directive, command, threshold, regex, `[id:]`, and enforcement tag is preserved, the always-loaded hard-rule prose has almost no safe-trim headroom left.

## Solution

Going under 22000 would have required either (a) **weakening always-loaded hard-rule directives** (forbidden — the rules are per-turn behavioral guardrails) or (b) **demoting `wg-*` gates that fire on single-class docs-only sessions** (silent-drop regression, #3681 — the loader does not inject `AGENTS.rest.md` on docs-only sessions). Both are off-limits.

The honest resolution, surfaced to the operator via `AskUserQuestion`, was **path-b hybrid** (explicitly offered by #4599: "raise/retire the advisory limit if 22k is stale"): keep the full −15% trim, raise `B_ALWAYS_REJECT` 22000 → 23000 (WARN stays 20000), and wire the linter into `scripts/test-all.sh` as a real CI gate. Net result satisfies both halves of #4599 — the payload is meaningfully smaller AND a CI gate now prevents future unbounded growth — while acknowledging that the irreducible floor (89-line pointer index + 40 `hr-*` + 1 compliance-tier body pinned to core by `lint-rule-ids.py`, CPO #3496) sits above 22000.

## Key Insight

**When planning an AGENTS always-loaded byte reduction, estimate the achievable trim budget from RATIONALE bytes (multi-clause `**Why:**` narrative, `see …/<file>.md` path tails, restated examples), NOT from imperative/directive bytes.** Directive prose (the MUST/NEVER clause + specific commands/thresholds/regexes + `[id:]` + enforcement tags) is effectively incompressible without weakening guidance. A plan lever framed as "tighten N% of imperative prose" will overshoot. If the rationale-only budget cannot reach the target, the sanctioned fallbacks are, in order: (1) demote `wg-*` gates **that never fire on single-class docs-only sessions** (ship/merge-phase only); (2) retire a rule via `retired-rule-ids.txt` if it meets the discoverability bar; (3) raise the advisory ceiling (path-b) and wire the gate at the realistic floor. Weakening a directive to hit a byte target is never on the list.

**A `wg-*` gate can be pinned to core by a COMPONENT TEST, not just by `lint-rule-ids.py`.** `lint-rule-ids.py` pins only `hr-*` and `[compliance-tier]` bodies to core. But a sibling `plugins/soleur/test/*.test.ts` can independently assert a specific `wg-*` gate lives in core (with a `→ core` pointer and a cross-reference from another rule). `wg-block-pr-ready-on-undeferred-operator-steps` is pinned this way by `ship-undeferred-operator-step-gate.test.ts` (TC-6/TC-9). The residency linter passed the demotion; the component test failed it — but only in CI, *after* auto-merge was queued. **Before demoting ANY `wg-*` gate, grep `plugins/soleur/test/` for its id** (`grep -rl '<gate-id>' plugins/soleur/test/`) and read any hit for core-residency / cross-reference assertions. A clean `lint-rule-ids.py` run is necessary but NOT sufficient.

## Session Errors

1. **Plan byte-reduction model over-estimated available trim.** The deepen-plan modelled −2100 B of "imperative tightening"; that headroom did not exist once directives were preserved, leaving the run ~782 B over the 22000 target. — Recovery: exhausted every safe lever, surfaced the wall to the operator, landed path-b (raise ceiling to 23000 + wire CI). — **Prevention:** plan/deepen-plan should size AGENTS-trim levers from rationale/Why-narrative bytes only and treat imperative prose as fixed; carry path-b (ceiling raise) as an explicit pre-approved fallback rather than assuming <target is always reachable. Routed as a Sharp Edge bullet to the plan skill.

2. **Deepen-plan first-draft byte ledger had an arithmetic error** (forwarded from session-state.md; claimed −6702 total while itemised deltas summed to −4076). — Recovery: self-caught and corrected during the deepen pass, documented in-plan as an audit trail. — **Prevention:** the aggregate-target Sharp Edge already requires per-item deltas to sum to the aggregate; this fired correctly.

3. **`gh issue create` blocked — missing `--milestone`.** — Recovery: re-ran with `--milestone "Post-MVP / Later"`. — **Prevention:** already hook-enforced (guardrails:require-milestone); one-off, no change needed.

4. **`git push` rejected after the early rebase rewrote the draft-PR init commit**, diverging local from the pushed branch. — Recovery: `git push --force-with-lease` (safe — own feature branch, deliberate rebase). — **Prevention:** rebasing a draft-PR branch (created by `worktree-manager.sh draft-pr`) always rewrites the init commit, so a force-with-lease push is expected; not an error to retry as a plain push.

5. **Enforcement-tags linter (`lint-agents-enforcement-tags.py`) showed 10 failures** when run during review. — Recovery: confirmed pre-existing via a HEAD-baseline run (identical 10, zero introduced by this PR), filed tracking issue #4622. — **Prevention:** the linter is lefthook-pre-commit-only and not CI-wired, so main drifted; #4622 tracks wiring/fixing it. When a linter fails during review, always diff against a HEAD baseline before attributing the failure to the PR.

6. **Demoting `wg-block-pr-ready-on-undeferred-operator-steps` core→rest broke `ship-undeferred-operator-step-gate.test.ts` (TC-6/TC-9), which CI surfaced only AFTER auto-merge was queued** (the `test`/`test-bun` required checks failed; the Phase 7 monitor's required-check-failure exit caught it). The plan + 6 review agents all missed it — the residency linter passed, and the component test pinning this specific gate to core wasn't on anyone's radar. — Recovery: reverted the wg-block demotion (body back to core, pointer `→ core`, restored the hr-never-label cross-ref), kept only `wg-after-marking-a-pr-ready-run-gh-pr-merge` demoted, re-trimmed ~200 B of gloss to stay under the 23000 ceiling. — **Prevention:** before demoting any `wg-*` gate, `grep -rl '<gate-id>' plugins/soleur/test/` and read hits for core-residency assertions — a clean `lint-rule-ids.py` is necessary but not sufficient. Routed to the deepen-plan checklist bullet.

## Tags
category: workflow-patterns
module: agents-md / lint-agents-rule-budget
issue: 4599
related: [[2026-05-20-rebase-before-applying-agents-md-plan-edits]]
