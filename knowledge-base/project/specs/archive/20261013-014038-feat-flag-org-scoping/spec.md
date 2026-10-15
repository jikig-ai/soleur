---
feature: flag-org-scoping
issue: 4581
branch: feat-flag-org-scoping
pr: 4582
date: 2026-05-29
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
brainstorm: knowledge-base/project/brainstorms/2026-05-29-flag-org-scoping-brainstorm.md
---

# Spec: Org-Targetable Runtime Flag Provisioning + Per-Org Scoping

## Problem Statement

The sanctioned flag tooling (`flag-create/scripts/create.sh`, `flag-set-role/scripts/flip.sh`)
cannot provision or per-org-scope an org-targetable runtime flag. Enabling
`byok-delegations` (owner-funded BYOK, per-grantee opt-in) for one org (jikigai
`70a70ab0`) is impossible through approved tooling, blocking #4232. Five verified gaps:

1. `create.sh:43` aborts (`exit 1`) when a flag name already appears in `server.ts`
   RUNTIME_FLAGS — no path to create only the missing Flagsmith feature for a code-wired flag.
2. `flip.sh --org` edits only the `org-targeted` segment **rule** (membership); it never
   creates a per-feature **feature-state override** (`flip_segment_in_env` runs only in the
   role branch). A fresh org-targetable feature has no override → evaluates `default_enabled=false`.
3. `org-targeted` (segment 1130454) is a single **shared** segment; a feature override on it
   is all-or-nothing across every org in the segment. No per-(feature,org) granularity —
   `byok-delegations` cannot be scoped to jikigai alone. (Reverses ADR-043.)
4. Both scripts `exit 4` when `OPERATOR_EMAIL` is absent from Doppler `soleur/cli_ops`.
5. Both scripts invoke `audit_flag_flip(...)` via the `psql` binary — hard dependency that
   fails on a machine without `psql`/`sudo`.

## Goals

- One sanctioned command enables an org-targetable flag for **one** org, with the WORM audit
  row written, no `psql`/`OPERATOR_EMAIL` precondition failure, and **no** collateral enable
  for unrelated orgs (satisfies #4581 acceptance).
- Per-(feature,org) scoping via **per-feature segments** (Option A), bounding segment count
  on the feature axis.
- Audit append remains **mandatory** and tamper-evident through the transport change.

## Non-Goals

- Per-org-segment model (Option B — rejected: relocates ADR-043's explosion to the customer axis).
- Per-user/per-identity flag overrides (org is the correct boundary; ADR-043 unchanged on this).
- A targeting-matrix UI (YAGNI — ~2-5 org-targetable features, not n×m).
- Promoting `byok-delegations` on the roadmap (advisory open question, not in scope).
- Deriving the audit actor from `git config` as a normal path (spoofable).

## Functional Requirements

**PR-1 (portability, ship first):**
- **FR1** — Replace the `psql` audit append in both scripts with a PostgREST RPC
  (`POST /rest/v1/rpc/audit_flag_flip`) using the `service_role` key; curl-only, no psql/sudo.
- **FR2** — Audit append stays mandatory: RPC non-2xx / empty body / missing id → `exit 4`,
  before any Flagsmith mutation (append-before-flip ordering).
- **FR3** — Actor resolution order: Doppler `OPERATOR_EMAIL` → (optional) authenticated
  `gh api user` with loud warning + Sentry mirror → hard fail. Record provenance tier.
- **FR4** — Seed `OPERATOR_EMAIL`, `SUPABASE_URL`, and the service-role key in `soleur/cli_ops`
  in-session (operator action automated, not deferred).

**PR-2 (per-feature-segment model, ADR-043-gated):**
- **FR5** — `create.sh --flagsmith-only`: provision the Flagsmith feature for an
  already-code-wired flag (skip server.ts/.env.example/Doppler steps).
- **FR6** — Provision a per-feature segment `<flag>-orgs` and one ON-override for the feature
  on that segment (idempotent).
- **FR7** — `flag-set-role ... --org <uuid>` resolves/edits the **flag's own** segment
  membership (not the shared `org-targeted`), idempotently.
- **FR8** — Post-write **re-verify read**: assert the target flag is in scope for exactly the
  intended org set (count==1 for a single-org enable) before reporting success.
- **FR9** — State-migration dry-run enumerating every existing (feature, segment-override)
  pair; migrate `team-workspace-invite` + current `org-targeted` membership into per-feature
  segments without a collateral flip.

## Technical Requirements

- **TR1** — Audit RPC routes through the SECURITY DEFINER `public.audit_flag_flip` (migration
  071), granted to `service_role` only; never a raw table insert (would bypass the
  no-update/no-delete trigger + actor CHECK).
- **TR2** — Amend ADR-043 via `/soleur:architecture create` before PR-2, recording the
  per-feature-segment model, blast-radius rationale, and the fallback-fidelity property
  (per-org overrides invisible to the Doppler `FLAG_*` mirror → OFF on Flagsmith outage).
- **TR3** — Confirm the live Flagsmith subscription segment-count cap via API before PR-2 merge.
- **TR4** — Silent-fallback mirror: any `gh api user` actor fallback emits a warning + Sentry
  event (`cq-silent-fallback-must-mirror-to-sentry`).
- **TR5** — `cq-pg-security-definer-search-path-pin-pg-temp`: if migration 071's function is
  touched, verify `search_path` pinning is retained.

## Acceptance Criteria

- `flag-set-role byok-delegations prd on --org <jikigai-uuid>` enables byok for jikigai
  **only**, writes the WORM row, and the re-verify read confirms count==1.
- The second org (`1a8045bf`) is unaffected for `byok-delegations`; `team-workspace-invite`
  remains ON for both orgs across the migration.
- Both scripts run end-to-end on a machine **without** `psql`.
- PR gated on `user-impact-reviewer` pass.
