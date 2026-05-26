---
date: 2026-05-22
issue: 4319
parent_brainstorm: knowledge-base/project/brainstorms/2026-05-22-dsar-workspace-member-extension-brainstorm.md
parent_issue: 4230
related_pr_merged: 4289
status: brainstormed
brand_survival_threshold: single-user incident
lane: cross-domain
user_brand_critical: true
domain_assessment_strategy: carry-forward
---

# DSAR Author-Only Message Redaction — Brainstorm (#4319)

## What We're Building

A per-row redaction predicate on the DSAR `messages` export so that messages
authored by **other** workspace members (but residing in conversations
*owned* by the data subject) are returned as structural shells —
thread-position metadata preserved, content nulled — rather than verbatim.

Concrete scope:

- Modify the messages export block at `apps/web-platform/server/dsar-export.ts:328-364`
  to post-filter rows fetched by `.in("conversation_id", conversationIds)`:
  rows where `row.user_id !== expectedUserId` keep `(id, conversation_id,
  role, created_at)` and null `content` (and any other personal-data
  columns added later).
- Apply the same rule to `message_attachments` at `:370-…` since they are
  joined via `messages.id`; an attachment authored by a non-subject within
  a subject-owned conversation must be redacted (file_name, mime_type, byte
  size preserved as thread-position metadata; storage URL nulled).
- Add a top-level `redactions: { path: string; reason: string; count: number }[]`
  field to `ManifestRoot` in the bundle manifest, bump the manifest schema
  from `1.0.0` to `1.1.0`. The exporter appends one entry per redacted
  path with reason `"art-15-4-rights-of-others"`.
- Integration test fixture: mixed-ownership conversation owned by Alice with
  one message authored by Alice + one authored by Bob. Alice's export bundle
  asserts (a) both message rows present, (b) Bob's row has nulled content +
  preserved structural fields, (c) manifest `redactions` array contains an
  entry for the redacted path with `count: 1`.

**Scope cut (explicit):**

- No retroactive sweep of already-issued DSAR bundles (acceptable — none
  issued yet at this gate; verify with `dsar_export_jobs` count at plan
  time).
- No redaction of attachments by content scanning (we redact by
  authorship — `message_attachments.user_id != requester` — not by
  inspecting attachment bodies).
- No new endpoint or UI surface; the predicate ships inside the existing
  exporter pipeline.

## Why This Approach

1. **Concrete leak vector confirmed.** Migration 059 (workspace-keyed RLS
   sweep) replaced `"Users can manage own conversations"` with
   `conversations_workspace_member_all` USING/WITH CHECK
   `public.is_workspace_member(workspace_id, auth.uid())`. Co-members can
   post in any conversation in their shared workspace. Current
   `dsar-export.ts:328-364` filters messages by `conversation_id IN
   conversationIds` only — no author filter. The leak is the verbatim Bob
   content the parent brainstorm flagged.
2. **Strict subset of the parent's FR5.** Parent spec
   `feat-dsar-workspace-member-4230/spec.md:G3 / FR5` already specified
   "thread-position metadata but redacts content" for foreign authors.
   Three plan-review reviewers (DHH, Kieran, Code-Simplicity) recommended
   split because (a) the predicate affects ALL DSARs not just departed-
   member, (b) carries Art. 13(2)(b) disclosure dependency that must
   coordinate with PR #4289. The split decision is well-grounded.
3. **PR #4289 (legal scaffolding) merged today at 08:07 UTC.** The gate
   the issue body cited is satisfied. Whether the merged copy covers
   redaction semantics is verified at plan-time research (Open Question 3).
4. **Inline post-filter > declarative allowlist type addition.** Only one
   joinVia table actually needs this predicate today (`messages` + its
   child `message_attachments`). YAGNI argues against extending
   `DsarTableSpec` with a redaction-policy object until a second table
   requires the same pattern. Inline is ~30 lines, deterministic,
   testable with one fixture.
5. **Manifest `redactions` array makes the Art. 15 completeness signal
   explicit.** Without it, a reviewer of the bundle cannot distinguish
   "no redactions occurred" from "redactions occurred but were silent."
   The bundle schema version bump 1.0.0 → 1.1.0 is essentially free —
   no consumers exist outside the exporter itself today.

## User-Brand Impact

`USER_BRAND_CRITICAL=true`. Brand-survival threshold: **single-user
incident**.

Vectors and the surface that gates each:

1. **Cross-tenant author leak via mixed-ownership conversation export.**
   Concrete: Alice owns conversation C, Bob (co-member of same
   workspace) posts message M in C, Alice exercises DSAR, Alice receives
   M's verbatim content. Predicate at `dsar-export.ts:328-364` is the
   only load-bearing gate; if absent or buggy, leak ships. Mitigated
   by: integration test fixture for the mixed-ownership path; predicate
   review in `user-impact-reviewer` agent at PR review.
2. **Silent over-redaction (Art. 15 incompleteness).** If the predicate
   accidentally nulls structural fields (e.g., `created_at`), Alice's
   bundle becomes Art. 15-incomplete and the requester cannot reconstruct
   thread context. Mitigated by: explicit preserved-fields list in the
   helper; fixture assertion that all four structural fields survive.
3. **Disclosure drift (Art. 13(2)(b)).** If the merged PR #4289 copy does
   not already describe the redaction semantics ("messages authored by
   other workspace members are returned with content redacted but thread-
   position preserved"), the runtime behavior outpaces the documented
   processing. Mitigated by: plan-time research-phase verification (Open
   Question 3); if delta needed, ride a coordinated text update in this
   PR through the legal-doc cross-document gate.

The `user-impact-reviewer` agent at PR review is the load-bearing gate;
plan must inherit this section verbatim and the integration test for the
mixed-ownership redaction path must be present.

## Key Decisions

| Decision | Choice | Why |
|---|---|---|
| Predicate location | Inline in `dsar-export.ts:328-364` (messages) + analogous for `message_attachments` | YAGNI vs declarative type extension; one joinVia table needs it today |
| Redacted columns (messages) | `content` (and any future personal-data columns) | Preserve `id, conversation_id, role, created_at` for Art. 15 thread-context completeness |
| Redacted columns (message_attachments) | Storage URL / encrypted blob ref | Preserve `id, message_id, mime_type, byte_size, created_at` for completeness |
| Manifest shape | New top-level `redactions: { path, reason, count }[]` | Explicit Art. 15 completeness signal; consumer-auditable |
| Manifest schema bump | 1.0.0 → 1.1.0 | No external consumers; bump is essentially free; aligns with semver minor |
| Redaction reason value | `"art-15-4-rights-of-others"` (single string) | Single trigger today; no enum needed |
| Domain assessment strategy | Carry-forward parent triad (CTO/CPO/CLO from #4230) | Strict subset of parent scope; no code drift since today; user-impact-reviewer at PR review remains load-bearing |
| Disclosure copy delta | Plan-time research verifies against merged PR #4289 | Open question — answer determines whether docs/legal text update rides this PR |
| Retroactive bundle sweep | Out of scope | No bundles issued at this gate (verify at plan time via `dsar_export_jobs` count) |
| Attachments by content scan | Out of scope | Author-based redaction only; we don't inspect blob bodies |

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support.
**Spawned:** none this brainstorm — domain assessment strategy is
**carry-forward** from parent #4230 brainstorm (per in-flight feature
refresh rule).

### Engineering (CTO) — carried forward

**Summary (from parent #4230):** Mixed-ownership predicate at
`dsar-export-allowlist.ts` / `dsar-export.ts:328-364` is load-bearing;
integration test for the foreign-author path is required. **Delta for
#4319:** parent scope was a single FR5 line; this brainstorm pins the
implementation site to the inline post-filter in `dsar-export.ts`
(rejecting the declarative-type extension as YAGNI) and specifies the
preserved-field list explicitly.

### Product (CPO) — carried forward

**Summary (from parent #4230):** Author-only redaction with thread-
position metadata is correct for case-(a) ex-members. **Delta for
#4319:** the same predicate now applies to ALL DSARs (any subject's
co-author messages get redacted, not just departed-member-adjacent
content). User impact is identical: single co-member's content leaking
to a requester is a single-user incident regardless of workspace
membership state.

### Legal (CLO) — carried forward

**Summary (from parent #4230):** Predicate satisfies Art. 15 (subject's
own data) and Art. 17(3)(b)/(e) carve-outs (don't leak surviving
members' data when they appear adjacent in threads). **Delta for
#4319:** PR #4289 (legal scaffolding) merged today at 08:07 UTC.
Whether the merged copy already describes the Art. 15(4) redaction
semantics requires a research-phase grep at plan time (Open Question 3);
if delta needed, this PR coordinates docs/legal text update through the
legal-doc cross-document gate.

## Capability Gaps

- **Engineering:** Inline predicate in `dsar-export.ts:328-364` messages
  block + analogous block in `message_attachments`. Evidence:
  `grep -nE 'redact|author_only|art-15-4' apps/web-platform/server/dsar-export.ts`
  → zero hits.
- **Engineering:** Manifest schema bump 1.0.0 → 1.1.0 + new `redactions`
  field on `ManifestRoot`. Evidence:
  `grep -nE 'redactions\s*:|"1\.1\.0"' apps/web-platform/server/dsar-export.ts`
  → zero hits.
- **Engineering:** Integration test for mixed-ownership redaction.
  Evidence: `grep -lE 'mixed.ownership|foreign.author|art-15-4' apps/web-platform/test/dsar-*.test.ts`
  → zero hits.
- **Legal (conditional):** Art. 15(4) disclosure delta in
  privacy-policy.md / gdpr-policy.md / DPD §2.3 if merged PR #4289 does
  not already cover redaction semantics. Evidence: deferred to plan-time
  research (grep merged docs for `Art.\s*15\s*\(4\)|rights of others|recital 63|redact` post-#4289 merge).

## Open Questions

1. Should the redaction also nullify the foreign author's `user_id`
   column on returned rows, or preserve `user_id` so the requester knows
   *that* someone else contributed (without seeing *what*)? Tentative:
   preserve `user_id` — completeness signal that another author exists
   in the thread; the personal-data lens applies to content not
   authorship-identifier-in-shared-context. Resolve at plan time with
   CLO confirmation.
2. Should the `redactions` manifest array include row-level granularity
   (one entry per redacted row) or per-table aggregation (one entry per
   table with summed count)? Tentative: per-path aggregation
   `{ path: "messages.jsonl", reason: "...", count: N }`. Lower
   manifest size; sufficient for completeness audit. Resolve at plan
   time.
3. Does merged PR #4289 already cover the Art. 15(4) redaction semantics
   in privacy-policy / gdpr-policy / DPD? Plan-time research-phase grep
   against current `main` after rebase. If covered, no delta in this
   PR; if not, ride a coordinated text update through the legal-doc
   cross-document gate.
4. Are there other joinVia tables (now or planned) where the same
   author-redaction predicate should apply? Plan-time grep:
   `grep -nE 'joinVia' apps/web-platform/server/dsar-export-allowlist.ts`
   — only `messages` and `message_attachments` today; confirm no
   pending PR adds another joinVia.

## Productize Candidates

None this brainstorm — predicate is project-specific, not a recurring
pattern.

## Deferred Follow-ups (to file as separate issues)

None this brainstorm — the parent #4230 brainstorm already filed the
known follow-ups (Art. 17 cascade RESTRICT, runtime_cost_state RLS,
public DSAR intake form, roadmap.md update). The scope cut on this
issue (no retroactive sweep, no attachment content scanning) is
inherent to the predicate design, not a deferred capability.

## Session Errors

None significant. Premise probe at Phase 0 caught the pre-condition
satisfaction: all three referenced dependencies (#4230 CLOSED, #4229
CLOSED, PR #4289 MERGED 2026-05-22T08:07Z) confirmed before worktree
creation, reframing the issue from "deferred pending #4289" to "ready
to plan now." The issue body's "Re-evaluation criteria" gate is
satisfied.
