---
title: gdpr-gate v2 layers + repo-scan mode
issue: 3518
v1_pr: 3501
adr: ADR-026
brand_survival_threshold: single-user incident
status: draft
date: 2026-05-10
---

# Spec: gdpr-gate v2 layers + repo-scan mode

## Problem Statement

v1 (PR #3501) shipped the `gdpr-gate` skill with three separately-active layer files (api-layer, data-in-transit, data-lifecycle), a prose-shaped `legal-consent.md` (no `check_id` markers), and `--diff`/`--plan` modes only. Three Sprinto-upstream layer files (`auth-sessions`, `frontend`, `testing-seeding`) were deferred to v2 to avoid carrying stale lifts; `--repo-scan` was deferred for credential-leak risk (ADR-026 NFR-014). v1 plan AC-PM-2 named issue #3518 as the v2 follow-up.

## Goals

1. Lift `auth-sessions.md`, `frontend.md`, `testing-seeding.md` from `gosprinto/compliance-skills` against current upstream SHAs as **separately-active layers** with EU-extension footers (Art. 32(1)(b), ePrivacy/TTDSG, Art. 32 pseudonymization).
2. Promote `legal-consent.md` from prose to layer-shaped (LC-01..LC-05) — archive v1 prose to `references/legacy/` for one release cycle.
3. Add `/soleur:gdpr-gate --repo-scan` for whole-repo audits, gated by:
   - Sole-arg sentinel detection (no substring matches).
   - `git ls-files -c -o --exclude-standard` source.
   - 7-pattern path deny-list at `scripts/path-denylist.txt`.
   - Two-clause `GDPR_GATE_REPO_SCAN_ALLOW_PATHS` env var (must match deny pattern AND exist in `git ls-files`).
   - CI-environment refusal (structural).
   - Inline-only output (no persistence).
   - Canonical-regex single-source via SKILL.md (sourced, not redefined).
4. Maintain v1 architectural invariants: advisory-only, mandatory disclaimer, schema-only prompt invariant, ADR-026 ≤4k token budget per scan iteration (now per 25-file batch).

## Non-Goals

- Modify AGENTS.md `hr-gdpr-gate-on-regulated-data-surfaces` rule body (rule already delegates trigger surface to SKILL.md).
- Modify `lefthook.yml` or `.gitleaks.toml` (canonical regex unchanged; deny-list is gate-internal).
- Auto-trigger `--repo-scan` from plan / work / ship phases (operator-initiated only).
- Per-check_id severity fixtures across all 7 layers (anchor coverage deferred to follow-up).
- Submodule support for `--repo-scan` (deferred).
- `--repo-scan-path=<glob>` scoped variant (deferred).
- Automated `path-denylist.txt` ↔ `.gitleaks.toml` parity sync (deferred).

## Functional Requirements

- **FR1** — Three new layer files exist under `references/layers/` with attribution headers (verbatim text from v1 NOTICE convention) and EU-extension footers.
- **FR2** — `legal-consent.md` is layer-shaped with check_ids LC-01..LC-05; v1 prose archived at `references/legacy/legal-consent-v1-prose.md`.
- **FR3** — `/soleur:gdpr-gate --repo-scan` executes the full repo scan, applies the deny-list before any read, and emits findings inline.
- **FR4** — Three new layer files lift content verbatim from upstream commit `7b58d68461cb1fc033a063e34cc9de63d0b4144b` with per-blob SHAs recorded in NOTICE.
- **FR5** — `repo-scan.sh` extracts the canonical regex from SKILL.md (single source of truth) and refuses to run if extraction fails.
- **FR6** — Two-clause env-var defense: every entry in `GDPR_GATE_REPO_SCAN_ALLOW_PATHS` must match a deny pattern AND exist in `git ls-files`. CI-environment usage is refused.

## Technical Requirements

- **TR1** — `repo-scan.sh` ≤300 lines, pure bash, `set -euo pipefail`, `LC_ALL=POSIX`.
- **TR2** — Token budget: ≤4k per 25-file Haiku batch (matches ADR-026 TR3 floor).
- **TR3** — Canonical regex appears verbatim in 4 places (SKILL.md, scripts/gdpr-gate.sh, gdpr-gate.test.ts, ship/SKILL.md). `repo-scan.sh` does NOT add a 5th surface — sourced from SKILL.md.
- **TR4** — Test surface: extends `gdpr-gate.test.ts` for layer/NOTICE/legacy assertions; new `gdpr-gate-repo-scan.test.ts` for the 7 D1-D4 + sentinel + canonical-regex test cases.
- **TR5** — No new AGENTS.md rule. Discoverability via `repo-scan.sh` clear-error stderr.

## Acceptance Criteria

See plan: `knowledge-base/project/plans/2026-05-10-feat-gdpr-gate-v2-layers-and-repo-scan-plan.md` §"Acceptance Criteria" (Pre-merge + Post-merge subsections).

## Domain Considerations

- **Engineering:** CTO assessment (re-run for v2) GREEN once 5 ship-blocking design fixes addressed (all in plan).
- **Legal:** Carry-forward from v1 brainstorm; advisory-only output preserved for `--repo-scan`. CLO sign-off at /review time on historical-migration tracked-not-amended posture.
- **Product:** No user-facing UI surface; `--repo-scan` is operator CLI. CPO sign-off at plan time per `requires_cpo_signoff: true`.

## Open Questions

None remaining after plan-review consensus. All Kieran P1/P2/P3 items addressed in the plan.
