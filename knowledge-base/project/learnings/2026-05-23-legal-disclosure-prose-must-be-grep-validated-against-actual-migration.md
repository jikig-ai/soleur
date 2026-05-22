---
title: "Legal-disclosure prose must be grep-validated against the actual migration body, not authored from plan-time conceptual descriptions"
date: 2026-05-23
related_pr: 4353
related_issue: 4333
follow_up_to_pr: 4294
related_adr: ADR-039
category: best-practices
related_learnings:
  - 2026-05-11-multi-agent-review-catches-cross-artifact-contract-drift.md
  - 2026-05-12-public-legal-doc-annotations-no-pr-numbers.md
  - 2026-05-18-plan-citation-and-ac-grep-brittleness-on-legal-doc-prs.md
detected_by_agents:
  - security-sentinel
  - code-quality-analyst
  - pattern-recognition-specialist
  - git-history-analyzer
tags: [legal-disclosure, gdpr, multi-agent-review, post-implementation-review, hallucination]
---

# Legal-disclosure prose must be grep-validated against the actual migration body

## Problem

PR #4353 added DSAR departed-member disclosure prose across three canonical legal docs (`docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md`) + three Eleventy mirrors + one counsel-attestation audit, closing the legal-doc-cross-document-gate lockstep gap left by PR #4294. The plan was deepened with live `gh` API verification + repo-grep cross-checks of byline conventions; all AC1–AC11 grep gates passed at /work Phase 4.

Post-implementation multi-agent review (`/soleur:review`) ran 4 agents + `user-impact-reviewer`. Two of them independently flagged the same P1 cluster: the new disclosures **invented columns and a WORM bypass mechanism that do not exist in the actual migration 062 / PR #4294 substrate**.

Hallucinated artifacts (verified absent by grepping `apps/web-platform/supabase/migrations/062_workspace_member_removals_and_remove_rpc_update.sql`):

| Hallucinated in prose | Actual schema |
|---|---|
| `organization_id` column | Does NOT exist on the table |
| `user_id` (FK to `auth.users`) | Actual column is `removed_user_id`, FK to `public.users` |
| `removed_user_email_hash` (SHA-256) + RPC SETs it to `'__anonymised__'` | Does NOT exist; raw email is never collected; no hash column to scrub |
| `removal_reason` (free-text from the Owner) | Does NOT exist; the row is purely structural-relational |
| WORM trigger bypass via `SET LOCAL session_replication_role='replica'` per mig 037 / mig 051 precedent | Zero matches in mig 062 — actual bypass is structural-shape detection (PII columns transition NOT NULL → NULL only; lineage unchanged) at the trigger body itself, per the post-#4294-review deliberate divergence documented in ADR-039 §Invariants |
| DSAR allowlist with "departed-user predicate OR-semantics" | Actual entry has `ownerField: "removed_user_id"` only (no `additionalOwnerFields`); single-arm `.eq("removed_user_id", expectedUserId)` at `dsar-export.ts:776` |

Plus an audit-file fabrication: `re_evaluation_triggers` field cited "ADR-039 §Re-evaluation" — ADR-039 has no such section; the closest section is `Cascade-order extension`.

Plan-time review (deepen-plan + plan-review trio) and /work Phase 4 grep gates ALL passed because none of them cross-grepped the prose against the actual migration body. The deepen-pass verified live `gh` citations for PR/issue states and verified DPD §2.3 letter sequence — both legitimate checks — but did not assert that prose-named columns exist in the schema or that named mechanisms are implemented.

## Solution

**Two independent agents** (`security-sentinel` + `code-quality-analyst`) caught the drift by grepping the actual migration body and surfacing the absent identifiers. The agent prompts explicitly asked them to cross-check disclosure claims against `apps/web-platform/supabase/migrations/*.sql` and `apps/web-platform/server/dsar-export-allowlist.ts`. Both produced concrete column-by-column drift tables that made the corrections mechanical.

Corrections were applied inline at /soleur:review (commit `ecd7c360`):

1. **Rewrite "Data processed" enumeration** against the actual schema. Drop `organization_id`, `removed_user_email_hash`, `removal_reason`; rename `user_id → removed_user_id`; add ON DELETE SET NULL carve-out note for `workspace_id`.
2. **Replace WORM bypass claim** with the structural-shape detection prose verified at ADR-039 §Invariants and the PA-19 entry in `knowledge-base/legal/article-30-register.md` §(g)(1).
3. **Correct anonymise RPC behavior**: NULLs BOTH PII columns (`removed_user_id` AND `removed_by_user_id`), not just one and an imaginary email-hash.
4. **Correct DSAR fulfilment**: single-arm on `removed_user_id` (owner-of-record), not OR-semantics. Workspace Owner's own DSAR returns rows where they were removed, not rows where they performed removals.
5. **Add cascade step 3.91** to Privacy Policy §8.1 (omitted vs DPD/GDPR Policy which named it).
6. **Drop ADR-039 §Re-evaluation** reference; document the triggers as the audit's own canonical set mirroring the prior team-workspace audit at `2026-05-counsel-review-4289.md`.
7. **Drop false-precedent citations** to PR #4081 / #4213 audit files (do not exist).
8. **Add PA-19 ⊥ PA-20 deliberate-duplication rationale** to DPD §2.3(v).

All AC1–AC11 still passed post-fix. §2.3(v) canonical/mirror diff: byte-identical.

## Key Insight

**Legal-disclosure prose for a database-substrate change must be derived from (or grep-validated against) the migration body, not from plan-time conceptual descriptions.** The plan-time loop optimizes for legal accuracy of the rights framework (Art. 5/6/9/13/17/20/30), regulator-facing surface coverage, and inter-doc lockstep — none of which require the author to actually open the migration file. The disclosure prose's load-bearing technical claims (column names, RPC signatures, cascade steps, trigger bypass mechanisms) live in the migration body, and a writer working from the plan + prior knowledge will hallucinate plausible-sounding identifiers that **fail a regulator's spot-check against the live schema**.

The pattern generalizes beyond legal docs: any disclosure surface that names an implementation detail (privacy policies, security disclosures, API documentation, vendor DPAs, transparency reports) must have that detail grep-validated against the implementing module. The cheapest gate is to require **at least one review agent prompt that explicitly cross-checks disclosure claims against the implementing file paths**.

This is distinct from the `self-claimed cross-artifact contract drift` pattern in `2026-05-11-multi-agent-review-catches-cross-artifact-contract-drift.md` — there's no `// mirrors X` comment to grep for; the drift is purely from author-side hallucination of schema details. The detection signal lives in cross-file grep, not in self-claim regex.

## Prevention

### At plan time

When the plan declares a docs-only PR that discloses a substrate landed by a prior PR, the plan **must include a precondition** that requires `/work` to:
1. Open the prior PR's primary migration file and copy the `CREATE TABLE` block into a scratch fenced code block in `tasks.md` (or a sibling artifact).
2. Open the SECURITY DEFINER RPC body and copy the UPDATE/SET clauses into the scratch.
3. Open the consuming DSAR allowlist entry and copy the entire literal.
4. Open the WORM trigger body and copy the bypass condition.

The prose is then written from the scratch, not from the plan's conceptual narrative. The plan's deepen-pass should verify the scratch exists, not the prose.

### At review time

When the diff includes ANY file under `docs/legal/`, `plugins/soleur/docs/pages/legal/`, or `knowledge-base/legal/`, the review's spawn prompt for `security-sentinel` AND `code-quality-analyst` MUST include:

> Cross-check every implementation-detail claim in the new prose (column names, RPC signatures, trigger bypass mechanism, cascade step numbers, DSAR allowlist entry, ON DELETE behavior) against the migration body, the RPC body, and the consuming TypeScript file. Produce a column-by-column drift table if anything diverges.

This was the exact prompt that surfaced the drift here. It must become the default for legal-disclosure PRs going forward — codified in `plugins/soleur/skills/review/SKILL.md` Step 1 (Conditional Agents → legal-disclosure trigger).

### At /soleur:plan deepen-pass

Add a Phase 4.9 (or equivalent slot) that runs `grep -F <prose-named-column> apps/web-platform/supabase/migrations/<cited-migration>` for every column name that appears in the new disclosure prose. Empty greps abort the deepen-pass with a P1 rejection. The check is cheap (≤30 greps per plan) and catches hallucination at the latest possible plan-time gate.

## Session Errors

1. **Prose invented columns + bypass mechanism that don't exist in mig 062.** — Recovery: multi-agent review at /soleur:review surfaced the drift, corrections applied inline in commit `ecd7c360`. — Prevention: add the legal-disclosure cross-grep prompt to /soleur:review's spawn template (per Prevention §At review time above); add Phase 4.9 grep-validate to /soleur:plan deepen-pass (per Prevention §At /soleur:plan above).

2. **Privacy Policy §8.1 omitted cascade step 3.91 while DPD/GDPR Policy named it.** — Recovery: added step 3.91 to PP §8.1 (canonical + mirror) in same commit as the schema fixes. — Prevention: the cross-doc consistency check at /soleur:review (pattern-recognition-specialist's task #3 "cascade-step numbers must agree across all docs") caught this — already covered by the existing review template; no new enforcement needed.

3. **Audit cited non-existent ADR-039 §Re-evaluation section.** — Recovery: replaced with reference to the prior `2026-05-counsel-review-4289.md` audit's re_evaluation_triggers as the canonical source. — Prevention: when copy-paste-extending a prior audit file's `re_evaluation_triggers` frontmatter, verify the cited ADR section actually exists via `grep '^##' <adr-path>` before sign-off.

4. **Audit cited non-existent precedent audits (PR #4081, #4213).** — Recovery: replaced with citations to the actual audit files (`#4051, #4066, #4289`) verified via `ls knowledge-base/legal/audits/`. — Prevention: every audit-file precedent citation MUST be `ls`-verified before sign-off; the verification is a single command and the cost of fabricating a precedent is non-trivial (counsel-attestation defensibility collapses on the first audit row).

5. **Propagated pre-existing `#4231 = PR` framing from PR #4287's byline.** #4231 is an issue (closed by PR #4287); the prose says "migration 063 / PR #4231". — Recovery: out-of-scope for this PR (the error is on `main`). — Prevention: when extending a `#NNNN — ...` byline from a prior PR, treat the cited PR/issue numbers as suspicious; run `gh issue view <N>` + `gh pr view <N>` to disambiguate before copy-extending.

6. **Plan deepen-pass sub-agent Task tool fan-out unavailable** → degraded to inline verification. — Recovery: inline verification still completed against the documented quality gates; no actual gap. — Prevention: the spec's documented fallback path worked as designed; no enforcement change needed.

7. **Initial mirror edit failed because the Eleventy mirror has pre-existing drift from canonical** (mirror is missing the LinkedIn carve-out paragraph in §8.1). — Recovery: re-anchored at end of §8.1 instead of before the LinkedIn carve-out. — Prevention: when editing an Eleventy mirror, do NOT assume the mirror's section bodies are byte-identical to canonical; the mirror has known drift (mirror's `previous:` byline chain skips the `#4287` segment that canonical preserves). For NEW section additions, anchor by structural landmark (end of §, beginning of next §), not by sibling-content match.

## Verification

- Commit `ecd7c360` applies all corrections.
- All AC1–AC11 still pass post-fix (verified inline at /soleur:review).
- §2.3(v) canonical/mirror diff: byte-identical.
- `git grep -nE 'removed_user_email_hash|removal_reason' docs/legal/ plugins/soleur/docs/pages/legal/` returns only the audit's corrective-audit-trail prose (which intentionally names the corrected fabricated terms as audit trail).

## Cross-references

- Plan: `knowledge-base/project/plans/2026-05-22-feat-dsar-departed-member-legal-doc-lockstep-plan.md`
- ADR: `knowledge-base/engineering/architecture/decisions/ADR-039-departed-member-removal-ledger.md`
- PA-19 register: `knowledge-base/legal/article-30-register.md` §"Processing Activity 19"
- Counsel audit: `knowledge-base/legal/audits/2026-05-counsel-review-4353.md`
- Implementing migration: `apps/web-platform/supabase/migrations/062_workspace_member_removals_and_remove_rpc_update.sql`
- DSAR consumer: `apps/web-platform/server/dsar-export-allowlist.ts`, `apps/web-platform/server/dsar-export.ts`
