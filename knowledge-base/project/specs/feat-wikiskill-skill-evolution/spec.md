---
feature: wikiskill-skill-evolution
date: 2026-09-18
lane: cross-domain
brand_survival_threshold: single-user incident
closes: '#8281'
brainstorm: knowledge-base/project/brainstorms/2026-09-18-wikiskill-skill-evolution-brainstorm.md
source: https://arxiv.org/abs/2608.27454 (CC BY 4.0)
status: draft
---

# Spec: WikiSkill-style Skill Evolution

## Problem Statement

Soleur's compounding loop captures experience but does not compound it, and its only machine
writer produces nothing that can be observed.

- `cron-compound-promote` has been `enabled: true` since 2026-07-06. `promotion-log.md` has zero
  rows; no `self-healing/auto` PR or issue has ever existed. The 2026-09-13 run spent 516,512
  input tokens on one Sonnet call and opened nothing. Its zero-output return paths emit only a
  Sentry heartbeat with `ok: true`, so the cause is unknowable from telemetry.
- Every session writes a new learning file (2,309 total). The 2026-09-13 weakness digest shows 15
  learnings in one week for a single failure class.
- Rejected proposals are retained nowhere a machine reads, so the loop can re-propose what was
  already refused.
- 0 of 98 skills record why they exist; skill descriptions are at 2,442/2,442 words.

## Goals

- G1 — Every proposer run reports a machine-readable outcome; zero-output causes are diagnosable
  from telemetry without SSH.
- G2 — One pattern page per failure/success pattern, with new evidence appended rather than a new
  file created.
- G3 — The proposer reads a compact index plus a ledger of past outcomes (including rejections)
  instead of the whole corpus.
- G4 — The loop can create a new skill when a mature pattern has no skill that owns it, within a
  budget and security envelope.
- G5 — Skills get shorter; their evidence moves to provenance files.
- G6 — Effectiveness is measured by recurrence of a failure class after a fix targets it.

## Non-Goals

- NG1 — No auto-merge. Every phase keeps the human-reviewed draft PR.
- NG2 — No committed raw trace layer; no tenant or alpha-tester data (CLO P1).
- NG3 — No founder-facing changelog (stays deferred, #6102).
- NG4 — No per-tenant skill evolution; improvement is global-plugin.
- NG5 — No auto-authored executable code: created skills are markdown-only.
- NG6 — No change to ADR-092 hard-rule protections.

## Functional Requirements

**Phase 1 — working, visible loop**

- FR1 — `cron-compound-promote` emits `SOLEUR_COMPOUND_PROMOTE_OUTCOME` on every terminal path
  (`disabled`, `deduped`, `week-cap-reached`, `no-qualifying-clusters`, `anthropic-truncated`,
  `completed`), carrying cluster count and each per-cluster refusal reason.
- FR2 — A Sentry alert fires after 4 consecutive zero-output weeks.
- FR3 — #8274: diff paths are derived as `git apply` resolves them (e.g. `git apply --numstat -z`),
  and every reported path is checked against the allowlist. A diff with no parsable path is refused.
- FR4 — A `patterns/` layer: one page per pattern with description, root cause, fix, and links to
  the learnings that evidence it. Pages are updated by patch (append / replace / insert-after).
- FR5 — An index with one line per pattern in the form problem + root cause + fix, specific enough
  to judge relevance without opening the page.
- FR6 — Backfill: all 2,309 learnings are clustered into pattern pages in reviewed, chunked
  batches. Learnings are never deleted or rewritten; a wrong merge is repaired by editing a
  pattern page.
- FR7 — `/compound` upserts the matching pattern page after writing its learning; it creates a new
  page only when no existing pattern matches.
- FR8 — The proposer reads the index first and fetches individual pages on demand, replacing the
  whole-corpus prompt.
- FR9 — An append-only proposal ledger, written by the harness (not the model), recording proposal
  metadata, target, unified diff, gate result and outcome, including full rejected proposals.
- FR10 — The proposer must read the ledger before proposing and may not re-propose a rejected
  change; `no_action` is a valid outcome.

**Phase 2 — gated skill creation** (blocked until Phase 1 produces observable proposals)

- FR11 — Description-budget headroom is freed before any create proposal is allowed.
- FR12 — The proposer may open a draft PR creating a skill: markdown-only, no `scripts/`,
  `PURPOSE.md` required (origin, patterns addressed, evolution history).
- FR13 — A create proposal names the nearest existing skill and justifies not patching it, and
  emits merge/retire candidates.
- FR14 — A create proposal is net ≤ 0 description words, with the compensating trim in the same PR.
- FR15 — `skill-security-scan` runs on any proposed skill; the PII pre-pass covers pattern pages.

**Phase 3 — concise skills**

- FR16 — `**Why:**` rationale and learning citations move from SKILL.md into `PURPOSE.md`, one
  skill per PR, leaving instruction lines in place.

**Measurement**

- FR17 — After a fix merges, if its targeted pattern page gains new evidence within ~4 weeks, the
  ledger marks the change ineffective and the next proposal must address that.

## Technical Requirements

- TR1 — Classifier-skill edits keep the strict eval gate (ADR-069). Procedural skills use the
  human-merged draft PR + deterministic lints + FR17's lagging gate.
- TR2 — ADR-092 WORM acks and `diffRemovesHardRule` stay in force; created skills may not restate
  or relax `hr-*` rules.
- TR3 — Any raw trace layer is local, gitignored and expiring, sourced only from the operator's
  own repo (PA-31 §(g)(8), PA-34 control C1). Retaining or transmitting traces triggers
  `/soleur:gdpr-gate` at plan time and a PA-31 §(c)/(g) amendment.
- TR4 — Adapted WikiSkill prompt text carries CC BY 4.0 attribution in the ADR and each
  `PURPOSE.md`.
- TR5 — An ADR records the pattern-wiki layer and the phase gates before Phase 1 implementation
  (`/soleur:architecture create`).
- TR6 — The ledger keeps `promotion-log.md`'s non-repudiation property: append-only, rows never
  mutated.
- TR7 — Pattern pages and the index respect INDEX.md's exclusion rules (ADR-174) and the
  always-loaded byte budget; neither is injected into the always-loaded corpus.

## Open Questions

- Location of `patterns/` (`knowledge-base/project/patterns/` vs. inside `learnings/`).
- Maintainer split: `/compound` inline upsert, a weekly reconciling cron, or both.
- Backfill batch size and what the human reviewer checks.
- Pattern maturity threshold and how "no skill owns this" is decided.
- Source of description-budget headroom (one-time pass vs. per-proposal trims).
