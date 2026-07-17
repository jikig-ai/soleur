---
title: "Tasks — fix #6512 seccomp remediation pull-robustness + unenforced alarm"
plan: knowledge-base/project/plans/2026-07-17-fix-seccomp-remediation-pull-robustness-and-unenforced-alarm-plan.md
issue: 6512
lane: cross-domain
---

# Tasks — #6512 seccomp remediation redeploy

Derived from the finalized (post 5-signal review) plan. Threshold: `aggregate pattern`.
Fix 1 = `local-cache` reload tier. Fix 2a = item-4 actionable alert (always). Fix 2b = standing
enforcement probe (Phase-0-gated → **DEFERRED**, #6628). Test-first per `cq-write-failing-tests-before`.

## Phase 0 — In-session diagnosis + Fix-2b gate (no code)

- [x] 0.1 Sentry ISSUES / live signal — GHCR manifest of `v0.214.7` returns **HTTP 200** (image
      retained); the pull failure was a transient/auth leg failure, not a missing artifact. Precise
      leg (zot-prune vs GHCR-auth) is immaterial to Fix 1, which removes the registry dependency for
      a reload regardless.
- [x] 0.2 GHCR manifest HEAD/GET of `v0.214.7` (Doppler `soleur/prd` `GHCR_READ_TOKEN`) → HTTP 200.
- [x] 0.3 zot keep-set confirmed = 5 `v*` (`variables.tf:176` comment) — a several-releases-old
      running version is GC-eligible from zot.
- [x] 0.4 **Fix-2b gate → DEFER.** `terraform_data.docker_seccomp_config` (`server.tf:1024-1056`) is
      keyed on BOTH the profile hash AND `server_id` → host replacement re-runs the provisioner;
      reboot preserves the durable file + `--security-opt`. No non-merge unenforcement path
      confirmable in-session that Fix 2a would miss → defer Fix 2b (task 5.1, #6628).
- [x] 0.5 Phase-0 findings + gate decision written into the ADR-079 `(#6512, 2026-07-17)` amendment.
      Deep delivery-leg RCA → deferred issue #6629 (task 5.2).

## Phase 1 — Fix 1: local-cache reload tier (test-first)

- [x] 1.1 RED: `ci-deploy.test.sh` cases (a)-(d) added; (a)+(b) RED without the tier (171/173).
- [x] 1.2 GREEN: `_try_local_cache_reload` at both both-failed exits (ZOT_ACTIVE + zot-dark, P2-5);
      keys on `docker inspect --format '{{.Image}}' soleur-web-platform` (literal, not `$CONTAINER_NAME`);
      guards `image_kind==web` + `^v[0-9]+\.[0-9]+\.[0-9]+$`; sets `LOCAL_CACHE_VERIFIED_REF`.
- [x] 1.3 GREEN: caller (`:2140`) uses `LOCAL_CACHE_VERIFIED_REF` as `VERIFIED_REF` and SKIPS
      `verify_image_signature`, with `cosign_reused_local_reload` (explicit reuse, not warn fail-open).
- [x] 1.4 GREEN: `registry_pull_event` level ternary extended → `local-cache` = `warning`.
- [x] 1.5 GREEN: `issue-alerts.tf` — dedicated `local_cache_reload_rate` alert (registry==local-cache).
      `zot_mirror_fallback_rate` NOT touched.
- [x] 1.6 GREEN: `scheduled-zot-restart-loop.yml:229` runbook grep extended to also match `local-cache`.
- [x] 1.7 `zot-soak-6122.sh` NOT edited (architecture P2 — `!=5` guard + semantic misdirection).
- [x] 1.8 Non-vacuity: negative-space cases (c) presence-probe, (c2) web-guard, (d) both-failed-gate
      each gate the rescue out; tier-absent RED confirmed (a)/(b). Serves the mutation-test intent.

## Phase 2 — Fix 2a (always) + Fix 2b (gated → deferred)

- [x] 2.1 RED: `scripts/seccomp-unenforced-alert.test.sh` (4 cases: create-when-absent + Sentry,
      comment-when-present dedupe, Sentry-absent fail-open, gh-error fail-open) — RED without the script.
- [x] 2.2 GREEN (Fix 2a): `scripts/seccomp-unenforced-alert.sh` sourced by `apply-deploy-pipeline-fix.yml`
      item-4; called at `diagnose_and_fail` + the redeploy-terminal `*)` failure before `exit 1`.
      Files/updates a deduped plain-language `ci/seccomp-unenforced` issue (label created) + Sentry
      `op:seccomp-remediation-failed` event. `issues: write` already granted. NOT a cron check-in.
- [x] 2.3 GREEN (Fix 2a): `issue-alerts.tf` — dedicated `seccomp_remediation_failed` alert.
- [~] 2.4 **DEFERRED** (task 0.4 gated Fix 2b OUT) → #6628. Not built.
- [~] 2.5 DEFERRED (Fix 2b) → #6628.
- [~] 2.6 DEFERRED (Fix 2b) → #6628.
- [~] 2.7 DEFERRED (Fix 2b) → #6628.

## Phase 3 — ADR + tests-green

- [x] 3.1 ADR-079 `(#6512, 2026-07-17)` amendment: Q1 supersession; local-cache tier + cosign-reuse
      posture (ADR-087 cross-ref) + pull-chain third tier (ADR-096 cross-ref); Fix 2a + Fix-2b gate
      (deferred #6628) + loop-vs-watchdog reconciliation; Phase-0 findings; stale-but-enforcing
      residual. Status stays `adopting`.
- [x] 3.2 No C4 impact — no `.c4` files touched.
- [x] 3.3 Full suite green: `ci-deploy.test.sh` (173/173 after relaxing (b) to its rescue-fired
      discriminator; MOCK_ZOT_CONFIGURED canary-health is a harness artifact), `seccomp-unenforced-alert.test.sh`
      (4/4), `actionlint` (apply-deploy-pipeline-fix rc=0), `terraform validate` (sentry root: valid).

## Phase 4 — Ship + post-merge re-enforce (in /soleur:ship)

- [ ] 4.1 `Ref #6512` in PR body (NOT `Closes` — closure follows Phase-4 live re-enforcement).
- [ ] 4.2 Post-merge: confirm `apply-web-platform-infra.yml` provisioned the new on-host `ci-deploy.sh`
      BEFORE re-enforcing (P1-6).
- [ ] 4.3 `gh workflow run apply-deploy-pipeline-fix.yml`; verify `host_present=true && host_sha==committed
      && loaded_matches=true` via one `/hooks/deploy-status` read.
- [~] 4.4 Fix 2b NOT built → no Sentry monitor to confirm.
- [ ] 4.5 `gh issue close 6512` after live re-enforcement verifies enforced.

## Phase 5 — Deferred follow-ups (filed)

- [x] 5.1 Fix 2b (standing probe) → **#6628** (consolidated with residual).
- [x] 5.2 Deep delivery-leg RCA (`host_present=false` provisioner/host-replacement cause) → **#6629**.
- [x] 5.3 Stale-but-enforcing residual (page on `host_sha!=committed` persisting ≥2 probes) → **#6628**.
- [~] 5.4 zot retention keep-set widening — NOT filed: Phase 0 showed GHCR retains the image (keep-set
      is not the sole cause) and Fix 1 covers the reload; widening would not have prevented #6512.
