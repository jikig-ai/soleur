---
date: 2026-07-01
topic: sync-domain-model-register
issue: 5754
branch: feat-sync-domain-model
pr: 5869
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
---

# Brainstorm: `/soleur:sync --domain-model` — auto-fill + drift-detect the business-rules register

## What We're Building

A new `domain-model` area for the `/soleur:sync` command (`plugins/soleur/commands/sync.md`)
that analyzes a repo's data model and (re)populates + drift-checks the business-rules register
at `knowledge-base/engineering/architecture/domain-model.md`.

Full scope (operator decision, 2026-07-01 — chosen over the 5-agent "reshape to read-only"
recommendation, with the risks below on record):

1. **Auto-fill (write):** walk Supabase migrations (tables, FKs, `UNIQUE`/`CHECK`, RLS policies,
   `SECURITY DEFINER` guards), TS domain types, and named guard functions
   (`resolveCurrentWorkspaceId`, `is_workspace_member`), infer candidate business rules +
   entity relationships, and **write** them into the register — **approval-gated** (see Key Decisions).
2. **Drift report (two-way):** (a) register rows whose cited source no longer resolves = *stale*;
   (b) source-level invariants with no register row = *undocumented*.
3. **Idempotent:** re-running on an unchanged repo produces no spurious diff.
4. **Generic-repo:** accepts any connected repo (Supabase+TS is the concrete v1 engine; other
   stacks degrade gracefully, not error).

## Premise Correction (verified before design)

The issue is written as "establish the register + add auto-fill," but **scope #1 is already done**:
- **PR #5773 (merged 2026-06-30)** created `domain-model.md` (5 entities + 9 business rules,
  hand-curated with ADR/migration/guard citations) + ADR-maintenance wiring (the `architecture`
  skill's `create` step, SKILL.md Step 8.5, updates the register when an ADR records a rule).
- The register's own maintenance contract names **#5754** as the tracker for the auto-fill +
  the fast-follow enforcement gates (plan-flag / review drift-check / ship block).

So this brainstorm is the **analyzer/drift-detector**, not the register format. Live proof the
feature is needed: the register cites a guard `resolveActiveWorkspace`, but the real symbol is
`resolveCurrentWorkspaceId` — exactly the citation drift a drift-check would catch.

## Why This Approach

`/soleur:sync` is already a 4-phase area-dispatch command (analyze → dedup-review → write →
definition-sync) with confidence scoring and Jaccard dedup. A new `domain-model` area reuses that
machinery instead of building a parallel tool. Deterministic-first extraction (SQL/grep for
structural facts, LLM only for phrasing) keeps false positives low; content-anchored citations
(migration# + object name, not line numbers) make re-runs diff-free. Approval-gated writes preserve
the register's curation trust while still delivering auto-fill.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | **Full scope** (auto-write + drift + generic-repo) | Operator decision 2026-07-01, overriding the unanimous leader recommendation to ship read-only first. Risks (register corruption, write-mostly artifact, speculative tenant scope) are recorded below and mitigated by decisions 2–8. |
| 2 | **Approval-gated auto-write** | Reuse sync's accept/skip/edit review. Inferred rows land in a clearly-marked **"Auto-inferred (unreviewed)"** section; promoted to curated `BR-*` only on operator approval. Never mix with or overwrite hand-curated rows unprompted. |
| 3 | **Never mint/reassign `BR-*` IDs mechanically** | Mirrors `cq-rule-ids-are-immutable`. Unmatched candidates surface as "proposed, needs human ID," never auto-numbered. |
| 4 | **Deterministic-first extraction** | Parse SQL for structural facts (tables/FKs/`UNIQUE`/`CHECK`/RLS/`SECURITY DEFINER`/guard symbols). LLM only translates a structural fact → a rule *statement*, gated to structures the deterministic layer already flagged as invariant-bearing, marked `low` confidence. No free-form "infer rules from code." |
| 5 | **Content-anchored citations** | Cite `migration 053 › workspace_members_pkey` / `workspace-resolver.ts › resolveCurrentWorkspaceId()` — migration# + object name, or symbol + file. **No line numbers** (they churn). Migrations are append-only/immutable, so the anchor never drifts. |
| 6 | **Keyed reconciliation before text match** | Match candidate → existing row by **cited-source identity** first (same migration object / same guard symbol), fall back to sync's Jaccard >0.8 on statement text. |
| 7 | **Idempotency self-check** | Deterministic sort before diff + a `--verify-idempotency` mode (extract twice, diff, non-zero exit on divergence) so CI can gate diff-free re-runs. Pin the report template (columns, sort key, severity enum). |
| 8 | **Completeness disclaimer** | CLO guardrail: register header + every drift report carry "Best-effort extraction from migrations/RLS/types; NOT a security audit or access-control attestation. Absence ≠ unenforced; presence ≠ correctly enforced." Travels with any copy. |
| 9 | **Generic-repo = capability tiers** | The analyzer accepts any connected repo; the Supabase+TS extractor is v1's concrete engine. Unknown stacks emit "domain-model extraction unsupported for this stack" (empty + disclaimered report), never garbage or errors. |
| 10 | Visual design: **N/A** | Pure CLI + markdown-report feature; no UI surface (Phase 3.55 legitimately skipped). |

## Deferred (follow-up issues)

- **Enforcement gates** (plan-time flagging, review drift-check, ship block): distinct CI/workflow-gate
  concern the register already calls "fast-follow." The drift report IS the drift-check primitive;
  wiring it into plan/review/ship is separable. → **#5871**.
- **Scheduled drift-check cron** (Productize Candidate): run `--domain-model` drift weekly, file an
  issue when register/source diverge. → **#5872**.

## Open Questions (for the plan skill)

- **ADR needed?** The deterministic-vs-LLM boundary + content-anchor citation scheme are architectural
  (CTO flagged). Plan should decide whether to run `/soleur:architecture create` for
  "Content-anchored domain-model drift extraction (deterministic-first)" (`wg-architecture-decision-is-a-plan-deliverable`).
- **Extraction implementation surface:** a deterministic SQL parser is real work (no existing migration
  parser in-repo). Shell/awk grep vs a proper SQL grammar — plan-time HOW decision. The C4 pipeline
  (`model.c4` → `model.likec4.json`) is the closest existing model-walk but is architecture-level, not
  schema-derived; likely not reusable for extraction.
- **Where does the "Auto-inferred (unreviewed)" section live** — inline in `domain-model.md` under a
  fenced heading, or a sibling include? Trade-off: single-register goal vs. keeping curated rows pristine.

## User-Brand Impact

- **Artifact:** the `/soleur:sync --domain-model` area + the drift report it emits.
- **Vector:** a drift-detector that gives *false confidence* — reporting "no drift" while an
  undocumented RLS/ownership invariant exists, or auto-writing a wrong inferred rule that corrupts a
  canonical row — could let a real access/tenancy invariant go unrecorded and be mis-cited as a
  governance control.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO), Legal (CLO). Marketing, Operations, Sales, Finance,
Support: not relevant (internal developer tooling, no user-facing/commercial/ops surface).

### Engineering (CTO)

**Summary:** Top risk is auto-writing fuzzy-inferred rows into a hand-curated authoritative register.
Recommends deterministic-first hybrid extraction, content-anchored citations for idempotency, keyed
reconciliation, generic-repo deferred, enforcement gates as a separate issue. No capability gaps
(`soleur:sync` + architecture skill + Supabase MCP cover the surface).

### Product (CPO)

**Summary:** Reshape verdict — the drift report is the product, auto-write is the liability; recommends
shipping read-only first behind a soak gate and deferring speculative tenant-repo scope. Operator chose
full scope; the write-mostly-artifact risk is mitigated by the approval-gate + unreviewed-section design.

### Legal (CLO)

**Summary:** Governance surface immaterial (read-only internal tooling, no personal data). One guardrail
worth keeping: a completeness disclaimer so the register isn't mis-cited as an access-control attestation
under GDPR Art. 5(2) / SOC2 CC6.

## Session Errors

None. Premise-drift (register already exists via #5773) was caught pre-worktree via existence grep +
`gh pr list`, and the design was reframed to the analyzer before any leader spawn.
