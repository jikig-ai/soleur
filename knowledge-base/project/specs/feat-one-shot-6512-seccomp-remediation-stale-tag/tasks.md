---
title: "Tasks — fix #6512 seccomp remediation pull-robustness + unenforced alarm"
plan: knowledge-base/project/plans/2026-07-17-fix-seccomp-remediation-pull-robustness-and-unenforced-alarm-plan.md
issue: 6512
lane: cross-domain
---

# Tasks — #6512 seccomp remediation redeploy

Derived from the finalized (post 5-signal review) plan. Threshold: `aggregate pattern`.
Fix 1 = `local-cache` reload tier. Fix 2a = item-4 actionable alert (always). Fix 2b = standing
enforcement probe (Phase-0-gated). Test-first per `cq-write-failing-tests-before`.

## Phase 0 — In-session diagnosis + Fix-2b gate (no code)

- [ ] 0.1 Sentry ISSUES surface (not events, #6090 L2) for the ci-deploy `image_pull_failed` terminal on
      run 29450562340 — read `registry` + `pull_result` (zot-prune vs GHCR leg).
- [ ] 0.2 Live authenticated GHCR manifest HEAD/GET of `ghcr.io/jikig-ai/soleur-web-platform:v0.214.7` with
      current Doppler `GHCR_READ_TOKEN` (#6090 basic→bearer); record HTTP status.
- [ ] 0.3 Count `v*` releases between v0.214.7 and incident-time head (zot 5-`v*` keep-set horizon).
- [ ] 0.4 **Fix-2b gate decision:** does a non-merge unenforcement path exist (host replacement/reboot →
      `host_present=false` with no item-4 run)? From `/hooks/deploy-status` history +
      `terraform_data.docker_seccomp_config` keying (`server.tf:1024-1056`). YES → build Fix 2b; NO/unsure →
      defer Fix 2b (tasks 3.x), record in §Deferred.
- [ ] 0.5 Write the Phase-0 findings + gate decision into the ADR-079 amendment draft. Deep delivery-leg RCA
      → deferred issue (task 5.2), not this plan.

## Phase 1 — Fix 1: local-cache reload tier (test-first)

- [ ] 1.1 RED: `ci-deploy.test.sh` cases — (a) both registries fail + `web` + immutable semver + running
      image present → container runs end-to-end from the running image ID, emits `registry=local-cache`
      `level=warning` + `cosign_reused_local_reload`; (b) #6512 zot-served topology (running image tagged
      under zot ref, `IMAGE` un-reassigned) → still rescued via running image ID (a `${IMAGE}:${TAG}`-keyed
      tier MISSES → RED); (c) running-image absent / TAG≠running / `latest` / non-web → hard
      `image_pull_failed`; (d) zot serves → tier never reached, no event.
- [ ] 1.2 GREEN: add the `local-cache` tier at `pull_image_with_fallback`'s shared both-failed point
      (covers `ZOT_ACTIVE==1` and zot-dark exits). Key on
      `docker inspect --format '{{.Image}}' soleur-web-platform` (literal, NOT `$CONTAINER_NAME`); guard
      `image_kind==web` + `^v[0-9]+\.[0-9]+\.[0-9]+$`; set `LOCAL_CACHE_VERIFIED_REF`.
- [ ] 1.3 GREEN: caller (`:2140-2143`) uses `LOCAL_CACHE_VERIFIED_REF` as `VERIFIED_REF` and SKIPS
      `verify_image_signature`, emitting `cosign_reused_local_reload` (explicit reuse — NOT warn-mode
      fail-open).
- [ ] 1.4 GREEN: extend `registry_pull_event` `level` ternary (`:614`) so `local-cache` → `warning`.
- [ ] 1.5 GREEN: `issue-alerts.tf` — add dedicated `local_cache_reload_rate` alert on
      `registry==local-cache`. Do NOT touch `zot_mirror_fallback_rate`.
- [ ] 1.6 GREEN: `scheduled-zot-restart-loop.yml:229` — extend the pull-health grep to also match
      `local-cache` (a host on local-cache must not read CLEAN and trigger a blind registry-replace).
- [ ] 1.7 Do NOT edit `zot-soak-6122.sh` (`!=5` count guard + semantic misdirection — architecture P2).
- [ ] 1.8 Mutation-test the local-cache guard (mutant RED first).

## Phase 2 — Fix 2a (always) + Fix 2b (gated)

- [ ] 2.1 RED: item-4 failure test — on redeploy terminal failure, a `ci/seccomp-unenforced` GitHub issue is
      filed/updated AND an `op:seccomp-remediation-failed` Sentry event opens before `exit 1`.
- [ ] 2.2 GREEN (Fix 2a): `apply-deploy-pipeline-fix.yml` item-4 — on `image_pull_failed`/`diagnose_and_fail`,
      emit the Sentry event + file the plain-language GitHub issue (age-gated dedupe like
      `scheduled-inngest-health.yml:330/363`) before `exit 1`. Grant `issues: write`. Do NOT check in to a
      cron-monitor slug (event-driven ≠ cadence).
- [ ] 2.3 GREEN (Fix 2a): `issue-alerts.tf` — add dedicated `seccomp_remediation_failed` alert.
- [ ] 2.4 **Only if task 0.4 gated Fix 2b in:** `scheduled-seccomp-enforcement.yml` (6h `cron` +
      `workflow_dispatch`; `actions: write` + `issues: write`; carry the
      `<!-- gate-override: new-scheduled-cron-prefer-inngest -->` comment with the external-watchdog
      justification — the PreToolUse hook requires it) — reads LIVE `host_present`/`loaded_matches`
      from `/hooks/deploy-status` (NEVER recorded `.seccomp_profile_sha256`); pages `error` iff
      `host_present!=true || loaded_matches!=true` (HEAD-independent); on unenforcement age-gated-dispatch
      `apply-deploy-pipeline-fix.yml` + file `ci/seccomp-unenforced` issue.
- [ ] 2.5 (Fix 2b) fail-safe: `set -uo pipefail`, `record_failure()`, initial in-progress check-in, explicit
      `error` + `probe_unavailable` on unreadable/secret-unset (never omit); untrusted body stripped.
- [ ] 2.6 (Fix 2b) `cron-monitors.tf` — one `sentry_cron_monitor` (slug = workflow filename).
- [ ] 2.7 (Fix 2b) RED/mutation: benign deploy-lag frame → `ok` not `error` (P1-5); each conjunct mutated
      independently incl. `loaded_matches` (P2-2); fail-safe mutant (`ok` on unreadable) RED.

## Phase 3 — ADR + tests-green

- [ ] 3.1 Amend ADR-079 `(#6512, 2026-07-17)`: Q1 supersession; local-cache tier + cosign-reuse posture
      (cross-ref ADR-087) + pull-chain third tier (cross-ref ADR-096); Fix 2a + Fix-2b gate +
      loop-vs-watchdog reconciliation; Phase-0 findings; stale-but-enforcing residual. Status stays `adopting`.
- [ ] 3.2 Confirm no C4 impact — no `.c4` files touched (one-line note; no mandated render run).
- [ ] 3.3 Full suite green: `ci-deploy.test.sh`, Fix-2 test(s), `actionlint` on new/edited workflows,
      `terraform validate` (sentry root).

## Phase 4 — Ship + post-merge re-enforce (in /soleur:ship)

- [ ] 4.1 `Ref #6512` in PR body (NOT `Closes`).
- [ ] 4.2 Post-merge: confirm `apply-web-platform-infra.yml` provisioned the new on-host `ci-deploy.sh`
      BEFORE re-enforcing (P1-6).
- [ ] 4.3 `gh workflow run apply-deploy-pipeline-fix.yml`; verify `host_present=true && host_sha==committed
      && loaded_matches=true` via one `/hooks/deploy-status` read.
- [ ] 4.4 If Fix 2b built: confirm the Sentry monitor exists; expect `error → ok` transition.
- [ ] 4.5 `gh issue close 6512` after live re-enforcement verifies enforced.

## Phase 5 — Deferred follow-ups (file as tracked issues)

- [ ] 5.1 Fix 2b (if task 0.4 deferred it) — tracked issue with build trigger.
- [ ] 5.2 Deep delivery-leg RCA (`host_present=false` provisioner/host-replacement cause).
- [ ] 5.3 Stale-but-enforcing residual (page on `host_sha!=committed` persisting ≥2 probes).
- [ ] 5.4 zot retention keep-set widening (only if Phase 0 shows it is the sole cause).
