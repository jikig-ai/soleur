# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-12-feat-inngest-op-arm-no-ssh-doppler-arm-flip-plan.md
- Status: complete

### Errors
- iac-plan-write-guard.sh PreToolUse hook blocked the plan Write/Edit 3x (denies `doppler secrets set` + operator-provisioning framing). Resolved as designed via `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` opt-out (Phase 2.8 genuinely reviewed; write token is TF-provisioned; arm-flip values are out-of-band per ADR-100). No unresolved errors.
- learnings-researcher agent did not return before finalization; substituted by direct greps + four-agent deepen review. Non-blocking.

### Decisions
- op=arm is FORWARD-ONLY; rollback stays in existing `op=rollback` verb (ADR-100:231 symmetric pair).
- Pre-write FSM-state guard load-bearing: refuse re-arm over non-terminal/`done` state (re-FLUSHALL = PROD Redis data loss); positive prod-URI assertion (both backends use :5432).
- Trust reconciliation upgraded to GitHub Environment secret + required-reviewer gate (`environment: inngest-cutover`).
- New `doppler_service_token.inngest_arm_write` (read/write) in per-merge `-target` allow-list; ADR-100 amended (Decision 6b), no new ADR/C4 edit.
- Source-of-truth split: HEARTBEAT_URL read-through (TF-owned); POSTGRES_URI operator-seed-once into narrow config, consumed no-SSH by op=arm, deleted post-cutover w/ token revoke. Live prod cutover execution remains operator-gated (single-user-incident).

### Components Invoked
- Skills: soleur:plan, soleur:deepen-plan
- Agents: terraform-architect; security-sentinel + data-integrity-guardian + architecture-strategist (deepen triad); Explore x3; learnings-researcher
- Artifacts: plan .md + tasks.md (commit ba17e60a3)

## Work Phase

### Phase 0 CTO fork — POSTGRES_URI source-of-truth (RESOLVED)
Live Doppler (value-silent probes) contradicted the plan's D6/C7 assumption: `prd_terraform.INNGEST_POSTGRES_URI` is directly CI-readable, SHA-identical to canonical `prd`, uses `:5432`, and DIFFERS from the dark `soleur-inngest/prd` value. `INNGEST_POSTGRES_URI_PROD` (the plan's proposed seed) absent everywhere.

**Routed to `soleur:engineering:cto` (architecture/security fork; not operator, not unilateral). Decision: Option B — read-through from `prd_terraform` via the existing `DOPPLER_TOKEN`** (same config-scoped read `op=backup` uses for HCLOUD_TOKEN). Supersedes deepen D6/C7.
- DROP: operator seed `INNGEST_POSTGRES_URI_PROD`, narrow config `prd_inngest_arm`, narrow read token, seed-delete + seed rotation co-update, value-silent freshness assertion.
- KEEP: write token `DOPPLER_TOKEN_INNGEST_ARM` + post-cutover revoke; G3 positive prod-URI assertion (prod != dark, contains prod host, :5432 not :6543); AC-NOBODY per-value masking + stdin writes; write order (armed last); FSM-state guard; Better Stack confirm.
- Rationale: A's "narrow surface" is illusory (value already readable in prd_terraform); B removes the only human secret step + the rotation-drift trap (a stale seed could arm a dead DSN → every user's crons stall). Freshness becomes structural (live canonical source).
- Read spec: both source values read from `soleur/prd_terraform` via existing read-only `DOPPLER_TOKEN` (config-scoped, no --project/--config). Writes to `soleur-inngest/prd` via `DOPPLER_TOKEN_INNGEST_ARM`.
- FSM state pre-cutover: `INNGEST_CUTOVER_FLIP` unset in soleur-inngest/prd (confirmed).
