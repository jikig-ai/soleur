---
title: "Tasks — security(inngest): secrets via env not argv + rotate"
ref: 5560
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-18-security-inngest-secrets-env-not-argv-plan.md
---

# Tasks — #5560 inngest secrets argv→env + rotate

Derived from the finalized (post-5-agent-review) plan. RED→GREEN where tests apply.

## Phase 0 — Preconditions
- [ ] 0.1 Confirm inngest reads `INNGEST_POSTGRES_URI`/`INNGEST_REDIS_URI`/`INNGEST_SIGNING_KEY`/`INNGEST_EVENT_KEY` from env (docs verified; pin `<!-- verified: 2026-06-18 -->`).
- [ ] 0.2 Confirm inngest reads Postgres from NO env alias other than `INNGEST_POSTGRES_URI` (makes the fail-safe `unset` sufficient).
- [ ] 0.3 Confirm `--postgres-max-open-conns 10` is accepted when Postgres is env-configured.
- [ ] 0.4 Record `random_password.inngest_redis_password_prd` `special = false` (`inngest.tf:147`) → URL-safe on rotation.
- [ ] 0.5 Read inngest pin/build precedent plans (image-build→pin-bump→deploy chain).

## Phase 1 — Rewrite ExecStart (RED→GREEN)
- [ ] 1.1 Write/extend `inngest.test.sh` regression block FIRST → RED: negative (no secret flags, only `$${…}` refs) + positive (`exec`, `export INNGEST_REDIS_URI`, stripped `INNGEST_SIGNING_KEY`, `$${INNGEST_POSTGRES_URI}`/`$${INNGEST_EVENT_KEY}` refs, `--postgres-max-open-conns` present) + fail-safe `unset INNGEST_POSTGRES_URI`.
- [ ] 1.2 Rewrite `inngest-bootstrap.sh:320` ExecStart: drop `--signing-key`/`--event-key` flags; add `export INNGEST_SIGNING_KEY="$${INNGEST_SIGNING_KEY#signkey-prod-}";` + `@@BACKEND_ENV@@` before `exec` inngest. Preserve the `signkey-prod-` rationale comment.
- [ ] 1.3 Branch `BACKEND_ENV` + `BACKEND_FLAGS` (`:353-359`): durable → `export INNGEST_REDIS_URI=…;` + `--postgres-max-open-conns 10`; fail-safe → `unset INNGEST_POSTGRES_URI;` + empty flags.
- [ ] 1.4 Add the parallel `@@BACKEND_ENV@@` substitution (`:360-362`, bash param-expansion, not sed).
- [ ] 1.5 Add the "DETECTION SENTINEL — do not remove/move to env" note at `:300-302`.
- [ ] 1.6 Update bootstrap comments (`:293-310`, `:342-352`) for env-delivery + unset invariant. Run `inngest.test.sh` → GREEN.

## Phase 2 — Cross-consumer sentinel sweep
- [ ] 2.1 `ci-deploy.sh:269-289` (`verify_inngest_health`): substring `--postgres-uri`→`--postgres-max-open-conns`; DROP dead `*'--redis-uri'*` sub-check (`:279`); re-express invariant (sentinel ⇒ inngest-redis active + /health 200); update comment + log strings.
- [ ] 2.2 `ci-deploy.sh:1000-1001` (ExecStart re-derivation): `*'--postgres-uri'*`→`*'--postgres-max-open-conns'*`.
- [ ] 2.3 `inngest-wiped-volume-verify.sh:98` (data-safety guard — HIGHEST RISK): swap substring.
- [ ] 2.4 `inngest-wiped-volume-verify.test.sh`: update ALL fixtures/assertions to the new sentinel.
- [ ] 2.5 `ci-deploy.test.sh:2214`: update FAIL-message grep to the renamed log string.
- [ ] 2.6 AC4 verification grep over the FULL file list → zero detection-logic hits of old substrings. Run `inngest-wiped-volume-verify.test.sh`, `ci-deploy.test.sh`, `cat-inngest-verify-state.test.sh`.

## Phase 3 — Docs + ADR
- [ ] 3.1 Amend ADR-030: add load-bearing invariant (secrets via env, never argv — #5560) + amendment-log entry, `status: adopting`.
- [ ] 3.2 Runbook `inngest-server.md`: replace `--postgres-uri`/`--redis-uri` detection prose with `--postgres-max-open-conns` sentinel + a `## Secret delivery` (env, not argv) note + deploy-then-rotate ordering. (No `.c4` edit.)

## Phase 4 — Full infra suite
- [ ] 4.1 Run `apps/web-platform/infra/*.test.sh` (inngest + ci-deploy + wiped-volume + cat-verify-state) → green. Typecheck N/A.

## Phase 5 — Ship (pre-merge)
- [ ] 5.1 PR body: `Ref #5560` (NOT `Closes`); enumerate `### Post-merge (operator)` rotation steps + rollback hazard.

## Post-merge (operator/automatable) — sequenced
- [ ] PM.1 (AC7.5) Pin-bump `cloud-init.yml` after the tagged image builds + deploy (explicit gated handoff).
- [ ] PM.2 (AC8) Verify deployed: cmdline secret-free (negative) + `/proc/<pid>/environ` has all 4 secrets (positive); `verify_inngest_health` ok.
- [ ] PM.3 (AC8.5) Capture armed-reminder baseline BEFORE rotation.
- [ ] PM.4 (AC9) Rotate `INNGEST_REDIS_PASSWORD` via `terraform apply -replace` (canonical tf triplet) — secret mutation only, no redeploy.
- [ ] PM.5 (AC10) Rotate Supabase Postgres password → re-set `INNGEST_POSTGRES_URI` in Doppler (stdin) → validate new URI connects (read-only probe) BEFORE redeploy. (`automation-status: UNVERIFIED` — attempt via Supabase Management API / MCP.)
- [ ] PM.6 (AC11) Single redeploy loads both rotated creds → `verify_inngest_health` ok + reminder count == baseline → `gh issue close 5560`.
- [ ] PM.7 File `tech-debt` follow-up: consolidate the ≥3 cmdline-grep durable detectors into one `inngest-durable?` helper.

**Rollback:** revert `cloud-init.yml` pin + redeploy. Post-rotation: NEVER roll back to a pre-fix (argv-form) image — it re-leaks rotated creds. Fix forward if no env-form image is healthy.
