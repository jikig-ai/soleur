---
date: 2026-05-15
topic: bundle-workflow-fixes-2733-2741
issues: ["#2733", "#2741"]
branch: feat-bundle-workflow-fixes
pr: "#3808"
lane: cross-domain
brand_survival_threshold: none
status: complete
updated: 2026-05-15
---

# Bundle: Workflow Improvements (#2733, #2741)

> **[Updated 2026-05-15 — scope reduction]** Plan-phase Phase 1 verification dissolved #2732's premise. The named hook (`.claude/hooks/security_reminder_hook.py`, not `plugins/soleur/hooks/` as the issue body said) only scans `.github/workflows/*.yml` for GitHub Actions injection sinks — it never scanned markdown for literal Python tokens. PR #2528 narrowed it to that scope on 2026-04-18, three days before #2732 was filed. Whatever blocked the 2026-04-21 audit-session writes was not this hook. #2732 closed as fixed-by-#2528. USER_BRAND_CRITICAL dropped to false. The reduced bundle (#2733 + #2741) has no user-data surface. Original brainstorm body preserved below for the historical record; only Key Decisions table and User-Brand Impact section retain operative authority post-reduction.
>
> **Meta-irony:** the dissolved premise on #2732 is exactly the workflow defect that #2733's Phase 1.0.5 (premise validation before research) is designed to catch. Two of the three bundled issues had load-bearing premise errors in their issue bodies, both caught by Phase 1.1 (research) checks — first at brainstorm time (#2741 AGENTS.md byte cap), second at plan time (#2732 hook scope). Strong real-world evidence that #2733's addition pays for itself.

## What We're Building

A single PR bundling three workflow-improvement issues left over from the 2026-04-21 peer-plugin-audit session:

1. **#2732** — `security_reminder_hook.py` should skip literal-token detection inside markdown fenced-code blocks tagged ```` ```text ````, ```` ```prose ````, or ```` ```diff ````. Documentation that *describes* a scanner pattern (specs, learnings) is currently treated as a credential leak.
2. **#2733** — Brainstorm skill gains **Phase 1.0.5 (premise validation)** before research and **Phase 2.5 (productize checkpoint)** after approach selection. Both have exact body text in the issue.
3. **#2741** — Skill-description word-budget enforcement: a new `cq-skill-description-budget-headroom` rule in AGENTS.md, plus a Phase 1 measurement step in the plan skill and a Phase 2 checkpoint in the brainstorm skill.

## Why This Approach

All three are small, well-scoped, and originate from the same audit session. Bundling avoids three round-trips of CI + review for changes that touch overlapping surface (`plugins/soleur/skills/brainstorm/SKILL.md` is edited by #2733 and #2741).

## User-Brand Impact

- **Artifact:** `plugins/soleur/hooks/security_reminder_hook.py` literal-token guard
- **Vector:** An operator pastes a real credential into a fenced ```` ```text ```` block inside docs (mistaking it for a sample); the docs-allowance skips the block; the credential lands on `main` and the public repo.
- **Threshold:** `single-user incident` — one leaked credential = one operator's brand-survival event.
- **Mitigation in this bundle:** The fence-tag allowance is narrow (only `text`/`prose`/`diff`), not a path whitelist. Tests must include a regression case where a high-entropy literal token inside a fence-tagged block IS flagged when it matches a credential pattern beyond the literal-token-name signal.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | **Bundle into one PR (single worktree, single review).** | Three small, related changes from one audit session; #2733 and #2741 touch the same skill file. Splitting would create three round-trips of CI for ~400 LOC total. |
| 2 | **#2732 approach: Option 1 (fenced-code skip).** | Decided upfront by user. Smallest surface area. Documented in the bundle so authors know to tag scanner-pattern fences with `text`/`prose`/`diff`. |
| 3 | **#2741 rule lands in `AGENTS.docs.md`, not `AGENTS.core.md` or `AGENTS.rest.md`.** | Trigger fires on PRs editing `plugins/soleur/skills/*/SKILL.md` `description:` lines. SKILL.md is markdown → `.md` → `docs-only` class per `.claude/hooks/session-rules-loader.sh` lines 102-126. (**[Updated 2026-05-15 — plan-review correction]** Initial brainstorm claim said `AGENTS.rest.md` / "code-class"; architecture-strategist caught the loader-class misfit at plan-review. `AGENTS.rest.md` does NOT load on docs-only sessions, which would have made the rule silent-no-op for its own trigger. Third real-time demonstration that #2733's Phase 1.0.5 pays for itself.) |
| 4 | **No AGENTS.md rule retirement required.** | #2741's issue body cited a 100-rule / 40,000-byte cap on a single AGENTS.md file. Verification (Phase 1.1) found AGENTS.md was refactored into sidecars: 75 rules across `AGENTS.{core,docs,rest}.md`, 32,470 bytes total. The budget premise is obsolete. |
| 5 | **Ordering inside brainstorm SKILL.md: #2733 first, then #2741.** | #2733 inserts new structural phases (1.0.5, 2.5). #2741 adds an inline checkpoint inside Phase 2. Applying #2733 first means #2741's checkpoint anchors to a stable section. |
| 6 | **Skip Phase 0.5 domain triad (CPO/CLO/CTO) despite `USER_BRAND_CRITICAL=true`.** | Sole user-brand vector (hook docs allowance) has Option 1 already decided. Triad spawn would be ceremonial. The user-impact-reviewer agent at PR review time remains the load-bearing gate per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`. |

## Meta-Finding: This Brainstorm Validated #2733's Phase 1.0.5

The most load-bearing moment in this brainstorm was Phase 1.1's premise check on AGENTS.md state — which is *exactly* the workflow #2733 proposes to encode as Phase 1.0.5 (Premise Validation). Had we not verified, the entire brainstorm would have designed a rule-retirement procedure for a constraint that doesn't exist. This is a real-time data point that the Phase 1.0.5 addition is worth the budget.

## Open Questions

- **Test coverage for #2732:** How aggressive should the regression test be? Minimum: a fenced ```` ```text ```` block with a real `sk_test_*` literal still triggers via a fall-back high-entropy check. Decide during plan phase.
- **AGENTS.docs.md rule placement:** Append at the end of the existing `cq-*` cluster (after `cq-eleventy-critical-css-screenshot-gate`). [Resolved at plan-review.]

## Non-Goals

- **No backfill audit** of existing SKILL.md descriptions. The new budget rule fires on future PRs only. Existing over-cap descriptions stay as-is.
- **No expansion of #2732's allowance** beyond `text`/`prose`/`diff` fences. Path whitelists and `<!-- security-hook-allow -->` markers are explicitly rejected as broader-surface alternatives.
- **No retirement of any existing AGENTS.md rule** (premise dissolved).

## Domain Assessments

**Assessed:** Engineering (implicit via the bundle scope — all three issues are engineering-domain workflow tooling). CPO/CLO/CTO triad considered (USER_BRAND_CRITICAL=true) but skipped per Key Decision #6.

## Acceptance Criteria (for spec.md)

- AC1: `security_reminder_hook.py` skips literal-token detection inside markdown fenced-code blocks tagged ```` ```text ````, ```` ```prose ````, or ```` ```diff ```` — with a regression test that a high-entropy credential pattern inside the fence is still flagged via a secondary check.
- AC2: `plugins/soleur/skills/brainstorm/SKILL.md` gains Phase 1.0.5 (Premise Validation) and Phase 2.5 (Productize Checkpoint) with text matching #2733's issue body.
- AC3: `plugins/soleur/skills/plan/SKILL.md` Phase 1 gains the SKILL.md description budget measurement step with text matching #2741's issue body.
- AC4: `plugins/soleur/skills/brainstorm/SKILL.md` Phase 2 gains the budget-measurement checkpoint per #2741.
- AC5: `AGENTS.docs.md` gains `[id: cq-skill-description-budget-headroom]` rule with the body text from #2741's issue.
- AC6: `AGENTS.md` index gains a pointer line `- [id: cq-skill-description-budget-headroom] → docs-only`.
