# Plan citation provenance + AC grep brittleness on legal-doc PRs

**Date:** 2026-05-18
**PR:** #3988 (AUP §4.7/§4.8 amendment closing #3921)
**Branch:** feat-one-shot-issue-3921-aup-art9-ccpa-spi-warning

## Problem

Three classes of plan-time precondition errors surfaced during a `/soleur:one-shot` run for a 3-file markdown-only legal-doc PR:

1. **PR/commit provenance error** — the plan's Research Reconciliation cited PR #3940 as the source of the Article 30 PA2 Art. 9 / chat-attachments cell. The actual source was PR #3883 (PR-D itself). #3940 added a *different* row (PA-13 CFO autonomous-draft). The error rode through the plan, the commit message, and the PR body before git-history-analyzer caught it during multi-agent review.

2. **AC grep style mismatch** — plan AC11 expected literal `Last Updated: May 18, 2026` but the target file's existing convention (since 2026-02-20) is `**Last Updated:** May 18, 2026` (bold-wrapped). The implementation correctly preserved the file's style; the AC grep was written without consulting the file's convention and would have spuriously failed verification even on correct output.

3. **Markdown soft-wrap breaking single-line `grep -F`** — the §4.7 prose was wrapped at ~80 chars per markdown convention, putting `under` at end of one line and `§6.2 of this Policy.` at start of the next. Markdown renders correctly (soft-wrap joins with space) but plan AC2's `grep -F 'under §6.2 of this Policy'` returned 0 matches. Required a source-line re-flow to satisfy the grep.

Additionally, multi-agent post-impl review surfaced a P1 the plan-time CLO assess phase missed: §4.8 omitted CPRA SPI Cat-(1)(D) "citizenship or immigration status" (added by AB 947 in 2023, not covered by GDPR Art. 9). The CLO did the SPI-vs-Art.9 overlay analysis but didn't enumerate every CPRA SPI sub-category against the draft.

## Solution

**For provenance (#1 + #6):** before a plan finalizes a "this content landed via PR #N" claim, verify with `git log -S '<distinctive-substring-from-the-content>' -- <file>`. This is the cheap, deterministic check. The plan-time research subagent had access to git and didn't run it. Required a post-review correction commit (`d1788d56`) to fix the plan + reflect the correction in audit trail.

**For AC grep style (#2):** plan AC greps that target a specific file format must inspect the file's existing convention first. The plan's `grep -cF 'Last Updated: May 18, 2026'` would have been correct for a fresh file but was wrong for this AUP (which uses bold-wrapped date lines). Fix: AC grep should be `grep -E '^\*\*Last Updated:\*\* May 18, 2026$'` OR drop the brittle "exact form" gate and verify with `grep -F 'May 18, 2026'` (looser match against the file's actual content).

**For markdown soft-wrap (#3):** when an AC grep targets a multi-word phrase containing inline cross-references (`under §X.Y`), keep the lead-in word + reference together on a single source line so `grep -F` matches. Fix applied: re-flowed the prose so `under §6.2 of this Policy.` sits on a single line.

**For multi-agent review coverage (#7):** CLO assess phase should not be the final regulatory-completeness gate — the plan-time analysis biased toward "Art. 9 vs CCPA SPI overlap" rather than "enumerate every CCPA SPI sub-category and check coverage." Multi-agent review caught it because security-sentinel was prompted to "verify against the official statutory text" rather than "compare against GDPR Art. 9." Different framing → different gap detection.

## Key Insight

Plan-time text claims (PR numbers, AC grep literals, cross-reference forms) are **preconditions to verify, not facts**. The work-phase rule "Plan-quoted numbers are preconditions to verify, not facts" already covers measurement claims (test counts, byte budgets, headroom estimates). This learning extends the same rule to three sibling shapes that surfaced in a docs-only PR:

- PR/commit provenance citations (`landed via PR #N`)
- AC grep literals (must match file's existing style/wrap)
- Markdown source-line layout (must align with grep's single-line scope)

The cost of each is small — `git log -S`, `head <file>`, a re-flow — but compounds: an unverified citation rides into a commit message + PR body + audit trail, and an unverified AC grep produces false-fail verification cycles. Cheapest gate: at plan deepen-pass, add a "verify citations + AC greps against file conventions" step before finalizing.

## Cross-references

- Existing related rule: work-phase precondition note in `plugins/soleur/skills/work/SKILL.md` Phase 1 step 1 ("Plan-quoted numbers are preconditions to verify, not facts")
- Existing related learning: `knowledge-base/project/learnings/2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md`
- This PR (#3988) is the closure of issue #3921 (PR-D PA2 line-62 follow-up); PA2 amendment source is PR #3883 (PR-D itself, 2026-05-16).

## Session Errors

1. **`gh pr view 3921` returned error — #3921 is an issue not a PR.** — Recovery: pivoted to `gh issue view 3921`. — Prevention: when fetching a `#N` reference of unknown type, try `gh issue view` first (issues outnumber PRs as inbound work items) or run both in parallel.

2. **AC verification bash chain broke at first 0-match grep.** A long `echo ... && grep -F ... | wc -l && echo ...` chain exited prematurely because `grep -F` returns exit 1 on 0 matches; `&&` short-circuited the rest of the report. — Recovery: re-ran chain with `;` separators wrapped in `{ ... } 2>&1`. — Prevention: use `;` not `&&` for verification chains where each step prints diagnostic output; or wrap each grep with `|| true`. (Self-evident bash hygiene; not worth a hook.)

3. **`under §6.2 of this Policy` grep returned 0 due to source-line wrap.** Source had `under\n§6.2 of this Policy.`; `grep -F` matches per line. — Recovery: re-flowed the line. — Prevention: when writing legal/docs prose with inline `§X.Y of this Policy` cross-references, keep the cross-reference + lead-in word on a single source line so single-line grep gates match.

4. **AC11 grep expected unbolded `Last Updated: May 18, 2026`; file convention is bolded `**Last Updated:** May 18, 2026`.** — Recovery: verified file's bold convention is the correct style precedent; AC11 grep was the bug, content was correct. — Prevention: plan-deepen pass should inspect each AC grep target file's style conventions BEFORE writing the grep literal; `head <file>` is the cheap check.

5. **Plan provenance cited PR #3940 as PA2 amendment source; actual is PR #3883.** Caught by git-history-analyzer during multi-agent review. — Recovery: corrected plan + commit body in review-fix commit (`d1788d56`). — Prevention: plan-deepen subagent should verify each `landed via PR #N` claim with `git log -S '<distinctive-substring>' -- <file>` before citing.

6. **One-shot orchestrator inherited the #3940 provenance error from args into the initial commit message** without independent verification. — Recovery: same as #5. — Prevention: when args contain a `landed via PR #N` claim, orchestrator should pre-verify before passing through to subagents OR rely on git-history-analyzer to catch in review (current safety net worked).

7. **CLO assess phase missed CPRA SPI Cat-(1)(D) "citizenship or immigration status" coverage gap.** Plan-time analysis focused on Art. 9 vs CCPA SPI overlap but didn't enumerate every CPRA SPI sub-category against the draft. Caught by security-sentinel in post-impl multi-agent review. — Recovery: added §4.8 bullet (e) + catch-all paragraph anchoring to operative statutory text. — Prevention: CLO assess agent prompt should add explicit "enumerate every CCPA SPI sub-category in §1798.140(ae)(1) and (ae)(2) and check coverage" framing — overlay-vs-enumeration is the gap-detection mode here.

## Tags

category: process
module: plan / deepen-plan / one-shot
