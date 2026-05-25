---
title: Closed-field privacy lists must classify columns at value-shape, not column-name
date: 2026-05-25
pr: 4351
issue: 4319
category: security-issues
related_prs: [4225, 4287, 4319, 4353, 4396]
agents_concurred: [security-sentinel, data-integrity-guardian, code-quality-analyst, pattern-recognition-specialist]
defect_class: closed-list-under-redaction
---

# Closed-field privacy lists must classify columns at value-shape, not column-name

## Problem

PR #4319 (DSAR Art. 15(4) author-only redaction) defined a closed field-list `MESSAGE_REDACT_FIELDS = [content, tool_calls, usage, draft_preview, action_class]` — five columns nulled on rows authored by a non-subject in a subject-owned conversation. The plan's Research Reconciliation #2 explicitly classified the remaining columns (`tier`, `source`, `owning_domain`, `urgency`, `trust_tier`, `source_ref`, `leader_id`, `template_id`) as **structural preserve**, based on column-name intuition: most look like enum-like routing metadata.

Post-implementation multi-agent review surfaced a P1 leak class. Two **orthogonal** review agents (security-sentinel + data-integrity-guardian) independently flagged that the "structural" columns carry free-text business semantics that leak third-party content:

- `source_ref` (mig 052): pattern is `pr-<org>:<repo>:<number>` / `cve-<id>` / `secret-scan-<org>:<repo>:<alert>` — leaks third-party GitHub orgs, repos, CVE refs into the subject's bundle.
- `urgency` (mig 046): free text — "client breach Tuesday" leaks an event.
- `owning_domain` (mig 046): identifies third party's product surface (`cto`, `cfo`, `github`, `legal`).
- `leader_id` (mig 010): text — can carry email-shaped values.
- `template_id` (mig 053): constrained to `^[a-z][a-z0-9_]*$` but still signals usage pattern.
- `tier`, `source`, `trust_tier`: enum-band but still tells the subject "Bob is tier external_brand_critical" — business signal.

Plan-time review (4 agents) approved the list because each agent enumerated at the column-NAME level ("`tier` is an enum, looks structural"). Only post-implementation orthogonal review caught the leak because security-sentinel reads the migration COMMENT body for `source_ref` ("`pr-<org>:<repo>:<num>`") and data-integrity-guardian reads the column TYPE (`text` vs `uuid`/`integer`) before classifying.

## Root cause

The closed-list pattern requires a **value-shape classifier**, not a name classifier. The question to ask per column is:

1. **What CHARACTERS does this column carry?** Free text → REDACT. Constrained enum → maybe preserve. UUID/integer → preserve.
2. **Does the column NAMESPACE third-party identifiers?** (`pr-<org>:<repo>`, email-shaped IDs, slug-shaped names) → REDACT regardless of constraint.
3. **Is the value a SIGNAL ABOUT THE THIRD PARTY?** Even a closed enum like `tier='external_brand_critical'` is a business signal about Bob that leaks into Alice's bundle.

The plan's Research Reconciliation #2 stopped at #1 and even there it stopped at column-name level. None of the plan-time reviewers cracked open the migration body to verify the value shape of each "structural" column.

## Solution

1. **Expanded `MESSAGE_REDACT_FIELDS` from 5 to 13 columns** at `apps/web-platform/server/dsar-export.ts`:
   added `tier`, `source`, `owning_domain`, `urgency`, `trust_tier`, `source_ref`, `leader_id`, `template_id`. Inline JSDoc on the constant cites the column-by-column rationale (mig source + leak shape).

2. **Added `MESSAGE_NON_REDACT_ALLOWLIST`** — the explicit companion set of 9 structural columns (`id`, `conversation_id`, `workspace_id`, `user_id`, `role`, `status`, `created_at`, `cache_read_input_tokens`, `cache_creation_input_tokens`). Made the structural classification a positive assertion, not a residual.

3. **Added CI sentinel test** `apps/web-platform/test/dsar-message-redact-fields-sweep.test.ts`:
   - Parses every `supabase/migrations/*.sql` (excluding `.down.sql`) for `ALTER TABLE public.messages ADD COLUMN <name>` and initial `create table public.messages (<col> <type>, ...)`.
   - Asserts every observed column is in `MESSAGE_REDACT_FIELDS ∪ MESSAGE_NON_REDACT_ALLOWLIST`.
   - Fails CI with a clear message naming the unclassified columns when a future migration adds one without classification.
   - Anchor test asserts known columns (`content`, `tool_calls`, `workspace_id`) are observed so a parser regression can't false-pass.

4. **Updated legal disclosure prose** in 3 files (`gdpr-policy.md`, `data-protection-disclosure.md`, `article-30-register.md`):
   - Shifted from enum-list to category claim + cited `MESSAGE_REDACT_FIELDS` as source-of-truth constant.
   - Named the sentinel test as the future-proofing gate.
   - Enumerated all 13 fields explicitly for transparency.

## Key insight

**The closed-list pattern is asymmetrically dangerous:** the cost of preserving one too many columns is an Art. 15(4) leak (single-user brand-survival incident); the cost of redacting one too many columns is a structural-shell row the subject can still see. Default-fail-closed: when in doubt, REDACT, and require positive evidence (column is UUID, integer, timestamp, or known-bounded numeric) to allowlist.

A migration-sweep sentinel test is the structural fix. Without it, every future `ALTER TABLE messages ADD COLUMN <free_text>` is a silent leak until the next adversarial review catches it. The sentinel test forces classification at migration time.

## Generalizable pattern: orthogonal-agent review beats single-agent plan-time review

Plan-time review with 4 agents (DHH, Kieran, Code-Simplicity, agent-finder) approved the 5-field list because each agent enumerates from a similar lens. Post-implementation review's value came from **orthogonality**:

- `security-sentinel` reads migration COMMENT bodies for namespace patterns.
- `data-integrity-guardian` reads migration COLUMN TYPES + ROPA prose.
- `code-quality-analyst` reads for closed-list/sweep-gate anti-patterns.
- `pattern-recognition-specialist` reads for stamp coupling + duplication.

Two-of-three orthogonal agents concurring on the SAME P1 (security + data-integrity both flagged the field list) is a much stronger signal than 4 agents concurring on "looks fine" at plan time. Cross-reconciliation rule applies: when two orthogonal agents independently surface the same harm, treat as P1 even if a third agent (user-impact-reviewer) silently approves.

## Session Errors

1. **archiver@8 ESM-only default-import was silently broken in production** — `import archiver from "archiver"` returns `undefined` under Node's `require(esm)` interop; `archiver("zip", ...)` would throw `(0, default) is not a function`. Worked only because no test exercised `buildArchiveToDisk` since the dep was bumped. Surfaced when this PR added the first test that calls it. **Recovery:** switched to named `ZipArchive` constructor with a v7→v8 type cast (matches `scripts/spike/dsar-streaming-upload.ts` pattern). **Prevention:** when bumping the major version of a runtime dep that ships dual ESM/CJS, add a smoke test that exercises the new import shape at least once. Consider a hard rule: **"After bumping a runtime dep to a major version that changes its ESM/CJS surface, grep for every `import X from \"<pkg>\"` site and run the smoke test covering that entry."**

2. **Observability test spied on `logger.default.child` while SUT calls `createChildLogger`** — fresh-module dynamic import hit a different logger module than the spy targeted; RED test ran red for the wrong reason. **Recovery:** `vi.doMock("../server/logger", async () => ({ ...actual, default: stub, createChildLogger: () => stub }))` + `vi.resetModules()` + dynamic import. **Prevention:** when SUT does module-init `const log = createChildLogger(x)`, the spy must intercept the named export at the module BEFORE the SUT imports it; `vi.doMock` (not hoisted) is the canonical shape.

3. **Pre-existing cross-tenant integration test broken by mig 059** — `conversations.workspace_id NOT NULL` made fixture INSERT fail. PR #4225 / #4287 landed mig 059 without updating the test's fixture inserts. **Recovery:** added `workspace_id: u.id` + `user_id: u.id` (per ADR-038 N2 the user's solo workspace has id=users.id). **Prevention:** when a migration adds a NOT NULL column to a table any test inserts into, the migration PR must update all fixture INSERT sites in the same commit (extend the data-migration-expert gate to enumerate fixture-test seed sites).

4. **Pre-existing `enqueueExport.workspace_id` production bug** — production self-serve DSAR enqueue has been broken since #4287 merged 2026-05-21. The route at `app/api/account/export/route.ts` and the `enqueueExport` function omit `workspace_id` from the `dsar_export_jobs` insert. Surfaced here when the cross-tenant test exercised the path. Filed #4396, scope-out from this PR. **Prevention:** for any column added as NOT NULL on a table with existing insert sites, run `git grep -nE '\.from\("<table>"\)\.insert\('` and fail-loud if any caller doesn't pass the new column.

5. **Branch was 10 commits behind main at start of work, including #4353 (legal-doc lockstep)** that touched the same 4 files this PR edited. Code-quality-analyst caught it at review time, not /work Phase 0.5 entry. **Recovery:** rebased onto origin/main; conflict-free since #4353's edits were in non-overlapping locations. **Prevention:** extend work skill Phase 0.5 check 6 escalation (FAIL HARD vs WARN) to `docs/legal/` and `knowledge-base/legal/` surfaces — currently scoped to AGENTS.* and `plugins/soleur/skills/ship/SKILL.md` only. Legal-doc surfaces have the same multi-PR-collision dynamic (multiple compliance PRs land in the same week, each touching `article-30-register.md` / `gdpr-policy.md`).

6. **Plan classified namespace-leaking columns as "structural preserve" at column-NAME level** — the main learning above. **Recovery:** post-implementation orthogonal-agent review caught it; expanded REDACT 5→13 + sentinel test. **Prevention:** plan skill must enumerate column-VALUE-SHAPE (free-text? namespace identifier? enum?) not just column name, AND the plan-time review prompt must instruct at least one reviewer to crack open the migration COMMENT body for each column being classified.

7. **AC4 grep path drift in plan** — plan cited `data-processing-description.md` (4 occurrences); actual on-disk file renamed long ago to `data-protection-disclosure.md`. user-impact-reviewer flagged it. **Recovery:** updated tasks.md AC4 grep target. **Prevention:** extend the `hr-always-read-a-file-before-editing-it` rule to plan-time path NAMING — plan must verify each path it cites by reading the file before prescribing it.

8. **tier="external_low_stakes" violated mig 046 `messages_external_tier_status_check`** in test seed — external_* tiers require `status IN ('draft','archived')`. Test default status is `'complete'`. **Recovery:** changed to `tier="internal_routing"`. One-off, but a comment in the test now warns future fixture authors.

9. **My initial sed for tasks.md checkbox-ticking malformed Phase 0 boxes** with `**0.&` capture bug. **Recovery:** `git checkout` + cleaner sed with character classes. **Prevention:** verify after regex-based bulk edits with `grep -E "^- \["` before proceeding.

## Tags

category: security-issues
module: dsar-export
defect-class: closed-list-under-redaction
review-class: orthogonal-agent-concurrence
