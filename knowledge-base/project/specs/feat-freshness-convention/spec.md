---
lane: cross-domain
brand_survival_threshold: single-user incident
tracks_issue: 5999
epic: 6003
status: draft
last_updated: 2026-07-04
review_cadence: quarterly
---

# Spec: Freshness Convention — `last_reviewed` Integrity Gate

**Issue:** #5999 · **Epic:** #6003 · **Brainstorm:** `knowledge-base/project/brainstorms/2026-07-04-freshness-convention-brainstorm.md` · **PR:** #6017

## Problem Statement

Soleur's largest recurring failure class is **stale premises** — agents acting confidently on silently-aged context. A `last_reviewed` + `review_cadence` convention already exists on 40 KB files and is consumed by live crons that file overdue-review issues. But the signal is **not trustworthy**: nothing prevents an *automated* write from bumping `last_reviewed`, and the brainstorm skill's own Phase 0.25 roadmap reconcile (`SKILL.md:121`) does exactly that on the most-consulted file. Meanwhile the highest-pain population — the always-loaded rule layer (`AGENTS.md` + sidecars) — carries no freshness metadata at all. A staleness signal computed from an unguarded `last_reviewed` is false confidence: worse than no signal.

## Goals

- G1. Make `last_reviewed` a **trustworthy** signal: only a deliberate human review may bump it; automated writes bump `last_updated` only.
- G2. Eliminate the existing self-violation (Phase 0.25 auto-bumping `last_reviewed`).
- G3. Bring the always-loaded rule layer (`AGENTS.md`, `AGENTS.core.md`) under the existing convention without leaking frontmatter into agent context.
- G4. Reuse the existing overdue-review surfacing (no new parser/scanner).

## Non-Goals

- NG1. A–F GPA freshness grade (duplicates the working overdue-issue channel; hides the actionable file).
- NG2. A session-start / statusline freshness line (noise; statusline is user-global, not repo-shippable).
- NG3. Per-section (per-H2) freshness markers (no consumer, high parse cost).
- NG4. `derived_from`/`generator` inheritance (no generator emits a constitutional file — YAGNI).
- NG5. Touching MEMORY.md (CC-local, write-forbidden by `no-memory-write.sh`).
- NG6. A new review skill/agent in v1 (default to a lightweight marker; revisit if the plan chooses the active-checkin UX).

## Functional Requirements

- **FR1.** A commit/Edit gate blocks any change that modifies a `last_reviewed:` line **unless** an explicit human-review marker is present for the session/commit. Fail-safe-open on gate error (never brick commits); mirror precedent gate ergonomics.
- **FR2.** A shared bump helper writes `last_updated` (any actor) and is *structurally incapable* of writing `last_reviewed`. Automated flows (migrations, generators, reconcile) use only this helper.
- **FR3.** Phase 0.25 roadmap reconcile (`plugins/soleur/skills/brainstorm/SKILL.md:121` + `roadmap-reconcile.sh` module) bumps `last_updated` only; never `last_reviewed`.
- **FR4.** `AGENTS.md` and `AGENTS.core.md` gain `last_reviewed` + `review_cadence` (+ optional `owner`) frontmatter.
- **FR5.** `.claude/hooks/session-rules-loader.sh` strips leading YAML frontmatter from each sidecar before concatenating it into `additionalContext`. (Test: the injected rule text must not contain `last_reviewed:`.)
- **FR6.** The existing overdue consumers (`review-reminder.yml`, `cron-review-reminder.ts`, `cron-strategy-review.ts`) include the rule-layer files in their scan, using the *same* strict date parser (no fourth parser).

## Technical Requirements

- **TR1.** The gate ships with a `.test.sh` sibling (repo precedent: every `*-gate.sh` has one). Cover: automated bump blocked, human-marked bump allowed, `last_updated`-only write allowed, gate-error fail-open.
- **TR2.** Frontmatter parsing reuses the existing shared module; respect the gray-matter YAML-1.1 date-coercion trap (learning `2026-05-25-tr9-pr6-gray-matter-yaml11-date-coercion-trap.md`) — match `cron-strategy-review.ts`'s strict regex, not `date -d`.
- **TR3.** Loader change must not violate the ≤200-byte header contract or the fail-closed sidecar-load path (session-rules-loader test 11).
- **TR4.** An ADR captures: (a) reuse-existing-cron vs new registry, (b) the `last_reviewed` integrity-enforcement mechanism.

## Acceptance Criteria

- AC1. An automated flow attempting to bump `last_reviewed` is blocked by the gate (test proves it).
- AC2. Running the roadmap reconcile no longer changes `last_reviewed` on `roadmap.md`.
- AC3. `AGENTS.md`/`AGENTS.core.md` carry the fields; agent context (post-loader) contains the rule text but **not** the YAML.
- AC4. An overdue rule-layer file produces a review-reminder GitHub issue via the existing cron (no new scanner added).

## Open Questions

See brainstorm §Open Questions — top: passive marker vs active `/soleur:review-context` checkin skill (resolve at plan/ADR).
