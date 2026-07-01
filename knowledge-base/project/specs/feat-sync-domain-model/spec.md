---
feature: sync-domain-model
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
issue: 5754
date: 2026-07-01
branch: feat-sync-domain-model
pr: 5869
brainstorm: knowledge-base/project/brainstorms/2026-07-01-sync-domain-model-register-brainstorm.md
related:
  - knowledge-base/engineering/architecture/domain-model.md
  - plugins/soleur/commands/sync.md
---

# Spec — `/soleur:sync --domain-model`: auto-fill + drift-detect the business-rules register

## Problem Statement

Soleur's business rules (workspace ownership = N co-owners, `(installation_id, repo_url)` repo
binding, membership-gated access, guaranteed solo workspace) are encoded across migrations, RLS
policies, guard functions, and ADRs. The **register** that catalogues them
(`knowledge-base/engineering/architecture/domain-model.md`) already exists (PR #5773), but it is
maintained only manually + via the ADR-create hook. Nothing derives rules **from source** or detects
when the register and the code have diverged. Live proof: the register cites a guard
`resolveActiveWorkspace` that no longer exists (real symbol: `resolveCurrentWorkspaceId`).

## Goals

1. A new **`domain-model` area** in `/soleur:sync` that walks a repo's data model (migrations,
   RLS, CHECK/UNIQUE/FK constraints, `SECURITY DEFINER` guards, TS domain types, named guard
   functions) and reconciles inferred business rules against the register.
2. **Two-way drift report:** register rows whose cited source no longer resolves (*stale*), and
   source-level invariants with no register row (*undocumented*).
3. **Approval-gated auto-fill:** write inferred rows into the register via sync's accept/skip/edit
   review, into a clearly-marked "Auto-inferred (unreviewed)" section.
4. **Idempotent:** re-running on an unchanged repo produces no spurious diff (content-anchored
   citations + stable sort + a `--verify-idempotency` self-check).
5. **Generic-repo:** accepts any connected repo; Supabase+TS is the concrete engine, other stacks
   degrade gracefully.

## Non-Goals

- **No mechanical enforcement gates** (plan-time flagging, review drift-check, ship block) — separate
  follow-up issue; the drift report is the reusable primitive they will consume.
- **No scheduled/cron drift-check** — separate follow-up (Productize Candidate).
- **No autonomous overwrite of hand-curated `BR-*` rows** — writes are approval-gated and never
  mint/reassign IDs.
- **No full multi-stack extraction engine** beyond graceful degradation — deep support for
  non-Supabase stacks is out of scope.

## Functional Requirements

- **FR1** — `/soleur:sync domain-model` runs the analyzer as a standalone area (excluded from `all`,
  like `rule-prune`, since it targets a specific register).
- **FR2** — Deterministic extraction of structural facts: tables, FKs, `UNIQUE`/`CHECK`/`NOT NULL`,
  `CREATE POLICY` name + `USING`/`WITH CHECK` predicate, `SECURITY DEFINER` RPC signatures, named
  guard symbols. LLM used only to phrase a flagged structural fact as a rule statement (confidence
  `low`).
- **FR3** — Every emitted candidate/row carries a **content-anchored** source citation
  (migration# + object name, or symbol + file — no line numbers) and a confidence tag.
- **FR4** — Reconciliation matches candidate → existing register row by cited-source identity first,
  Jaccard >0.8 on statement text as fallback; unmatched candidates are surfaced as
  "proposed, needs human ID," never auto-numbered.
- **FR5** — Two-way drift report with a pinned template (fixed columns, stable sort, `stale` /
  `undocumented` severity enum) and a completeness disclaimer.
- **FR6** — Approval-gated writes: inferred rows proposed via `AskUserQuestion` accept/skip/edit;
  accepted rows land in the "Auto-inferred (unreviewed)" section; hand-curated `BR-*` rows are never
  overwritten unprompted.
- **FR7** — `--verify-idempotency` mode: extract twice, diff, non-zero exit on divergence.
- **FR8** — Unknown/unsupported stack emits "domain-model extraction unsupported for this stack"
  (empty + disclaimered report), never an error or garbage rows.

## Technical Requirements

- **TR1** — Reuse `sync.md`'s existing Phase 2 dedup/review + Phase 3 write machinery; add the
  `domain-model` branch to area dispatch.
- **TR2** — Content-anchored citations only; migrations are append-only so migration# + object name
  is a stable key.
- **TR3** — Deterministic sort of candidates before any diff/write to guarantee diff-free re-runs.
- **TR4** — Completeness disclaimer emitted in both the register header and every drift report.
- **TR5** — Extraction must not depend on a hardcoded file whitelist (walk the migrations tree +
  guard-symbol grep so new migrations/policies are picked up automatically).

## Acceptance Criteria

- [ ] `/soleur:sync domain-model` populates/updates `domain-model.md` from a repo's migrations +
      domain types + guard functions (approval-gated).
- [ ] Each generated row cites a concrete content-anchored source.
- [ ] Drift report lists register-rows-without-source + source-invariants-without-register-row.
- [ ] Re-running on an unchanged repo produces no spurious diff (`--verify-idempotency` green).
- [ ] The live `resolveActiveWorkspace` → `resolveCurrentWorkspaceId` citation drift is flagged as
      stale by the report.
- [ ] Unsupported stack degrades gracefully (disclaimered empty report).
- [ ] Register header + every report carry the completeness disclaimer.

## Open Questions

- ADR for the deterministic-vs-LLM boundary + content-anchor scheme (plan deliverable).
- SQL extraction implementation: shell/awk grep vs a real SQL grammar (no existing migration parser
  in-repo; C4 pipeline is architecture-level, not schema-derived).
- Placement of the "Auto-inferred (unreviewed)" section (inline fenced heading vs sibling include).
