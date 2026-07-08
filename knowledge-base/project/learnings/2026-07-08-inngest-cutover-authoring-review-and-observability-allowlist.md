# Learning: authoring a boot-critical cutover — the no-SSH marker that never ships, and the FSM transient that conflates two windows

**Date:** 2026-07-08
**Feature:** Phase-2 Inngest dedicated-host cutover (`op=execute`/`verify`/`rollback` workflow + flip FSM). PR #6218, Ref #6178, ADR-100.
**Context:** one-shot pipeline; six phase-batched implementation subagents + a 5-agent boot-critical/destructive review.

## Problem

A boot-critical, destructive cutover (Redis `FLUSHALL`, prod-Postgres arm, whole-fleet quiesce) was authored against a written plan. Green deterministic gates (`.test.sh`) passed at every phase, yet multi-agent review found one **P0** and several **P1** defects that all-green CI could not see. The three highest-value ones generalize.

## Key Insights

### 1. A new `logger -t <tag>` on a host script is invisible off-box unless the tag is in the Vector allowlist (recurring)
The flip emitted `logger -t inngest-cutover-flip` and the plan asserted it "rides the already-shipped Vector→Better Stack journald shipper" as the sole **no-SSH operator gate** (ADR-100 P0-2). But `apps/web-platform/infra/vector.toml` Source 4 (`host_scripts_journald`) forwards journald lines **only by exact-match `SYSLOG_IDENTIFIER`** against a closed allowlist — and the new tag wasn't in it. The marker never left the box; the entire no-SSH channel was **inert**. The cited "already-shipped shipper" commit shipped the *shipper*, not the *allowlist entry*.
- **Prevention:** when adding ANY `logger -t <tag>` on a host script whose output must reach Better Stack, add `<tag>` to `vector.toml` Source 4 `include_matches.SYSLOG_IDENTIFIER` **and** its drift-guard fixture (`apps/web-platform/test/infra/vector-pii-scrub.test.sh`) in the same change. "Rides the shipper" is a claim to verify against the allowlist, never a fact. The `observability-coverage-reviewer` now catches this when its spawn prompt names the allowlist check — but the cheapest gate is adding the tag at author time.

### 2. An FSM transient state that conflates a pre-side-effect and a post-side-effect window is a resume hazard (generalizable)
The flip set the flag to `flipping` **before** `stop → FLUSHALL → assert DBSIZE==0 → start`, and the `flipping`-resume branch did `start → done` with **no** FLUSHALL. A reboot/crash in the `[set-flipping … start]` window resumed via `flipping` and started a **prod** scheduler against an **un-flushed** dark Redis — the exact stale-cron/double-fire the FLUSHALL exists to prevent. Three independent review agents (security, architecture, data-integrity) converged on it.
- **Fix / Prevention:** split the transient by side-effect boundary. Keep `flipping` = *pre*-flush (its resume safely re-runs the full stop→FLUSHALL→assert while still dark), add a distinct `flushed`/`starting` checkpoint written *after* the assert passes and *before* start (its resume only ensures start→done, never re-flushing live prod state). Ask of every transient: "does resuming from this state re-run the side effect, and is that safe in BOTH the pre- and post-side-effect case?" Pair with an `ERR` trap that emits a marker AND drives the flag to a terminal `aborted` so a `set -e` failure halts loudly instead of silently.

### 3. A no-op loop that *looks like* per-host fan-out is worse than honest single-host coverage (generalizable)
The quiesce gate looped `$CUTOVER_HOSTS` sending an `X-Cutover-Host: $h` header — but no hook consumed it and the inventory script read `127.0.0.1` (whatever the LB routed to). Every iteration probed the same host, yet the gate printed "zero inngest running across [all hosts]" → **false confidence**; weight-0 web-2 was never verified. Real per-host web→web inventory needs new infra (firewall + host-targeting hook) that the plan deferred.
- **Prevention:** a fan-out stub that projects coverage it doesn't deliver is a data-integrity trap. Either implement real per-host addressing or state the residual honestly (scope the claim to what was actually probed) + file a tracking issue (#6227) + persist an operator decision-challenge. Don't let a cosmetic loop launder a deferred capability into apparent completeness.

## Process notes (Session Errors)
- **Weekly API-limit interrupted the planning subagent.** Recovery: the plan body + one completed deepen reviewer's findings were on disk; a follow-up subagent folded them and wrote `tasks.md` after the cap reset. **Prevention:** on a cap-interrupted planning subagent, check for on-disk plan artifacts before re-running (one-shot's partial-artifact recovery step already prescribes this) — do not re-spawn the full plan+deepen.
- **IaC-routing SessionStart hook blocks each infra-prose edit independently.** The `<!-- iac-routing-ack: … -->` marker must be inlined **per-edit**, not just at file level (the hook scans each edit in isolation). **Prevention:** already hook-enforced; inline the ack in each edit that carries `systemctl`/`doppler secrets set` prose.
- **Plan-path drift:** C.3d named `inngest.tf` but the OCI image-tag pin lives in `cloud-init-inngest.yml`; `infra-config-apply.test.sh` needed count-bumps the plan said weren't required. **Prevention:** covered by `hr-when-a-plan-specifies-relative-paths` — plan is authoritative for intent, never for paths/counts; re-derive both at work time.
- **`vector-pii-scrub` re-run failed on missing `SENTRY_USERID_PEPPER` + no vector binary** — an environment-precondition artifact, not a regression (the implementing subagent ran it 30/0 with both present; CI provides both). **Prevention:** confirm a test's own env/binary preconditions before reading its non-zero exit as a defect.

## Tags
category: integration-issues
module: apps/web-platform/infra (inngest cutover, vector observability)
related: ADR-100, #6178, #6218, #6227
