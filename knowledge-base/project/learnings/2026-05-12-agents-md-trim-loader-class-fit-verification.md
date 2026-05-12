---
date: 2026-05-12
problem_type: workflow_gate_drift
component: agents_md_loader
severity: high
tags: [agents-md, loader-class-fit, skill-enforced-tag, dedup, workflow-hardening]
related_prs: [3681, 3682, 3496, 3493]
synced_to: []
---

# AGENTS.md trim — loader-class fit and `[skill-enforced:]` tag-suffix dedup

## Problem

Two adjacent failure modes surfaced when trimming AGENTS.md to fit the 22 k always-loaded budget:

1. **Loader-class fit drift.** PR #3681 demoted `wg-plan-prescribed-skills-must-run-inline` from `AGENTS.core.md` to `AGENTS.rest.md`. Pattern-recognition reviewer caught it pre-merge: the rule fires on `/work` invocations, and `/work` runs on docs-only sessions (plan-only PRs, knowledge-base edits) where `.claude/hooks/session-rules-loader.sh` does NOT load `AGENTS.rest.md`. Demoting the rule would have silently dropped its enforcement on the very session class the rule is meant to gate.
2. **Tag-body duplication.** When extending `cq-agents-md-why-single-line` (in `AGENTS.docs.md`) to also state Why-line trim semantics, the naive form added a `preserving per-issue mechanism labels (text after each `#N`)` clause to the rule body. Result: the body restated what the existing `[skill-enforced: compound step 8]` tag already pointed at, the rule grew to 594 / 600 B (6 B headroom — one keystroke from breaking the cap), and any future drift between the rule body and `compound/SKILL.md` step 8 would be silent.

## Insight A — Loader-class fit must be verified at plan time before any AGENTS.md core→rest demotion

The class table lives in `.claude/hooks/session-rules-loader.sh:88-115` (DOCS_RE / CODE_RE / INFRA_RE + the class-selection branch). The loader fires `core+docs-only` on docs-only sessions and `core+rest` on code/infra sessions; multi-class fires the fail-closed `core+docs-only+rest` branch. For each demotion candidate, classify the rule's trigger surface against the loader's class table:

- Does the rule fire on plan/learning/spec edits (docs-only)? If yes AND the demotion target (`AGENTS.rest.md`) does NOT load on docs-only, **KEEP in core**. Body-trim instead.
- Does the rule fire only on code/infra? Then the demotion is loader-class-fit-safe (`core+rest` covers it).

**Mitigation shipped in this PR (#3682):** plan/SKILL.md and deepen-plan/SKILL.md each gained a checklist item that pins the grep target: `sed -n '88,115p' .claude/hooks/session-rules-loader.sh`. Pinning the grep (rather than paraphrasing the regex into the plan body) means the planner reads the canonical source every time — when the loader's regex eventually changes (e.g., adds `.yaml` to DOCS_RE), the gate self-updates. Both bullets carry mirror comments (`<!-- mirror: ... — keep in sync; trim both together -->`) so future trims sweep both.

The same insight got mirrored into `compound/SKILL.md` step 8's `[CRITICAL]` warning string: when the always-loaded payload exceeds 22 k and the operator is actively trimming, the warning now also says `Before demoting any wg-*, verify loader-class fit: sed -n '88,115p' ...`. Three reinforcement points (plan, deepen-plan, compound-at-trim-time) so the gate fires whatever entry path the operator takes.

## Insight B — Push semantic detail into the `[skill-enforced:]` tag suffix, not the rule body

When an AGENTS.md rule already carries `[skill-enforced: <skill> <step>]`, that tag IS a typed pointer to the enforcer. If the enforcer's behavior gains a new dimension (e.g., compound step 8 now enforces both "Why-line trim semantics" AND "loader-class-fit"), the cheapest, drift-safe form is to extend the tag suffix:

```
[skill-enforced: compound step 8]                                      ← before
[skill-enforced: compound step 8 (Why-line trim semantics + loader-class-fit)]  ← after
```

The tag suffix gives a future reader a one-line cue about WHAT the enforcer covers, without restating the verbatim directive in the rule body. The verbatim directive belongs in the enforcer (compound step 8), which is the single source of truth.

Naive failure mode: state the same directive in BOTH the rule body AND the enforcer. The two will drift independently — rule body is read at session-start (docs-only sidecar), enforcer text is read at compound-fire time (any session that runs compound). Any future edit to one without the other leaves the operator with two non-aligned policies.

**Cap headroom recovered in this PR:** 594 → 578 B (6 B → 22 B). Cheap because the dedup is a refactor, not a deletion.

## Generalization

Both insights are forms of the same underlying principle: **`AGENTS.md` is the index, not the spec — let the enforcer own the semantics.** The class-aware loader (`AGENTS.{core,docs,rest}.md` sidecars) and the `[skill-enforced:]` / `[hook-enforced:]` tag system both push the policy text out of the always-loaded path into the artifact that actually fires the gate. When extending an enforced rule, the question to ask first is "where does the enforcer live?" — and the answer is almost never "in the AGENTS.md body."

## Session Errors

1. **`git add -A` instead of explicit file list** — touches `hr-never-git-add-a-in-user-repo-agents`. Recovery: confirmed only the 5 expected modified files were staged (no surprise additions). **Prevention:** stage with `git add <file1> <file2>...` enumerating each file; reserve `-A` for fully-clean worktree commits where every untracked path is intentional.
2. **Plan body cited wrong loader line ranges** (`84-115` and `84-86` in 9 places across the plan; reality is `88-115` for the regex+class-selection block, `88-90` for the three `_RE` literals, `103-115` for the class-selection if/elif). The wrong ranges sit on blank/comment lines. Caught only by code-quality reviewer post-implementation. Recovery: bulk `sed -i` fix in the review-fixes commit. **Prevention:** plan/deepen-plan should `sed -n '<range>p' <file>` and assert the printed range contains the cited regex literals before freezing the citation. (Captured as the new loader-class-fit checklist item in this very PR — #3682 fixes its own root cause.)
3. **Duplicate concept across artifacts** — added the trim-semantics clause to BOTH `cq-agents-md-why-single-line` body AND `compound/SKILL.md` step 8. Pattern-recognition flagged it as P1 with 6 B cap headroom. Recovery: dedup into the `[skill-enforced:]` tag suffix; rule body recovered 22 B headroom. **Prevention:** insight B above. When extending a rule that already names an enforcer, push the new dimension into the tag suffix.
4. **Stale byte-budget math in plan** — the plan claimed `pre-edit 572 B + 28 B headroom` against a `+60 B` insertion, prescribing a `−32 B` trim path. The shipped form took a different math path (dedup into tag suffix instead of rule-body insertion). Code-quality reviewer caught the stale assertion. Recovery: rewrote plan §Phase 3 §1 + §Enhancement Summary item 2 to reflect the actual shipped form. **Prevention:** when the work skill picks a different trim mechanism than the plan prescribed, update the plan's byte-budget assertions in the same edit cycle so the artifact stays self-consistent.
5. **`File has been modified since read` Edit error** after `sed -i` mutated the plan file mid-edit cycle. Recovery: re-grep'd the offending substring, re-applied via second Edit. **Prevention:** after any `sed -i` on a file the conversation has cached, re-read the affected ranges before any subsequent Edit on the same file.

## Related

- PR #3682 (this PR) — the workflow-hardening implementation.
- PR #3681 — the source PR whose review surfaced the loader-class-fit gap.
- PR #3496 — CPO sign-off establishing the `wg-*`-only demotion taxonomy.
- PR #3493 — the SessionStart class-aware loader split that created this defect class.
- `AGENTS.docs.md:6` — the `cq-agents-md-why-single-line` rule body.
- `compound/SKILL.md:227` — the `[CRITICAL]` warning where trim happens.
- `.claude/hooks/session-rules-loader.sh:88-115` — the canonical class table.
- `plugins/soleur/skills/plan/SKILL.md` — loader-class-fit checklist (mirror).
- `plugins/soleur/skills/deepen-plan/SKILL.md` — loader-class-fit checklist (mirror).
- `plugins/soleur/skills/work/SKILL.md` Phase 4 — entry-guard with distinct exit codes (2 = pause-and-commit, 1 = halt-and-investigate).
