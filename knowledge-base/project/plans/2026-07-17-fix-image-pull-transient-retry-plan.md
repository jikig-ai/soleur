---
title: "fix: image-pull transient retry (widen GHCR retry beyond auth-denied)"
issue: 6525
type: bug
lane: single-domain
brand_survival_threshold: aggregate pattern
created: 2026-07-17
branch: feat-one-shot-6525-image-pull-transient-retry
---

# 🐛 fix: first-attempt `image_pull_failed` on consecutive releases — widen the GHCR retry to cover transient/network stderr (#6525)

## Overview

`pull_image_with_fallback` (`apps/web-platform/infra/ci-deploy.sh`) pulls the release image zot-primary with an atomic GHCR fallback (ADR-096 / #6122). Its GHCR leg — `_ghcr_pull_or_recover` (`ci-deploy.sh:1376-1397`) — retries a failed pull **exactly once, and only when the stderr is auth-classified** (`_pull_result_is_auth_denied` at `:530-532`, grepping `unauthorized|authentication required|denied|forbidden`). A **transient/network** first-attempt failure (timeout, connection reset, network-unreachable, EOF, no-such-host, temporary-failure) is **not** auth-classified, so it takes the `return 1` path with **zero retries**. Because `pull_image_with_fallback` returns failure only when **both** registries fail (fail-closed, old container stays live — downtime-safe), the whole deploy fails fast (~5 s) and a human `gh run rerun --failed` — hitting a warmer path minutes later — succeeds. That is exactly the observed v0.216.1 / v0.216.2 shape.

**The fix (per the #6594/PR-B handover comment on #6525):** add a transient-error classifier `_pull_result_is_transient` alongside `_pull_result_is_auth_denied`, and widen the GHCR leg so a transient failure retries with a **bounded, capped backoff** (not just the auth-denied class). The both-registries fail-closed semantics and the entire #6400 auth-recovery branch stay **byte-identical**.

**This is a code-side change to an already-provisioned script** — no new infrastructure, no operator SSH. Delivery is automatic on merge (see `## Delivery`).

**Scope discipline (do NOT over-claim):** this absorbs the **transient** first-attempt failure class. A subset of #6525's later occurrences (v0.217.0: `inngest-server`/`vector` inactive, no seccomp profile, `sandbox_canary.verdict: unknown`, rerun did NOT clear it) are **durable host-degradation** (private-NIC / IMDS first-boot race, tracked by #6400 / #6415 / #6565 / #6497), for which a bounded retry correctly **exhausts and fails-closed**. This PR closes the retry-starvation gap; it does not repair a wedged host. See `## Hypotheses` and `## Out of Scope`.

## Research Insights

**Code map (verified against `origin`/working tree at plan time):**
- `_pull_result_is_auth_denied` — `ci-deploy.sh:530-532`. Single source of truth: called by BOTH `pull_failure_event`'s classifier (`:547`) and the recovery gate `_ghcr_pull_or_recover` (`:1381`) so they agree by construction. The file explicitly warns a second regex copy would drift.
- `pull_failure_event` classifier arms — `ci-deploy.sh:545-551`. Order: `auth_denied` → `manifest_unknown` (`manifest unknown|not found|no such manifest`) → `network` (`timeout|timed out|temporary failure|no route|connection refused`) → `pull_failed`. The `network` arm's inline regex is the **narrower** sibling of the classifier we are adding.
- `_ghcr_pull_or_recover` — `ci-deploy.sh:1376-1397`. Pull once; on auth-denied → `refetch_ghcr_and_relogin` → single retry; sets global `RECOVERY_STAGE ∈ {'', recovered(implicit), pull_still_denied, refetch_unavailable, relogin_failed}`.
- `refetch_ghcr_and_relogin` — subshell-called (`stage="$(...)"`), so it CANNOT set `RECOVERY_STAGE` (subshell boundary); it `printf`s the stage string. `_ghcr_pull_or_recover` is called DIRECTLY, so it CAN set the global. This asymmetry is load-bearing — the transient loop lives in `_ghcr_pull_or_recover` (direct call) so it can set `RECOVERY_STAGE=transient_exhausted`.
- `pull_image_with_fallback` — `ci-deploy.sh:1408-1468`. Two branches (zot-active fallback `:1450`; zot-dark direct `:1461`), both route the GHCR pull through `_ghcr_pull_or_recover`, so a loop added there covers both. Caller does NOT retry — retry stays at ONE level.
- `pull_auth_recovery_event` — `ci-deploy.sh:580-597`. Fail-open, env-guarded, `op:image-pull-recovery`, `level:info`, `jq -n --arg` (never raw stderr), host_id-tagged. Reusable for a `transient_recovered` breadcrumb.

**Established retry idiom in this file** (`ci-deploy.sh:1157-1158`, `1232-1236`, and `refetch_ghcr_and_relogin`): `n=0; until <cmd>; do n=$((n+1)); [[ "$n" -ge 3 ]] && break; sleep 5; done` — hardcoded `sleep`, 3-attempt cap. The new loop mirrors the cap idiom but uses an **explicit backoff array** (see Alternatives) with a **test-only override seam**.

**Test harness** (`ci-deploy.test.sh`):
- Mock docker deny machinery — `:340-362`: `MOCK_GHCR_PULL_DENY_ALWAYS=1` (every GHCR pull denies), `MOCK_GHCR_PULL_DENY_COUNT_FILE` (integer countdown, deny while `>0` then succeed). Deny payload is `"denied: requested access to the resource is denied"` (auth-classified). **New transient tests need a transient-stderr mock arm** (a new `MOCK_GHCR_PULL_TRANSIENT_*` countdown emitting a network-class stderr).
- #6400 retry tests — `:3338-3417` (AC1 count=1→recovered; AC2 `pull_still_denied`; AC14 relogin-fail→no retry; AC4 recovery is GHCR-scoped, not zot). These MUST stay green unchanged.
- Transient stderr fixtures the fleet actually produces — `:3555-3600` (`network is unreachable`, `read: connection reset by peer`, `EOF`, `no such host`, `connection refused`). Reuse these exact strings as the classifier's positive fixtures.
- **No sleep-mock exists** — existing retry tests avoid sleeping only because the mock succeeds before the sleep is reached. A test that EXHAUSTS the transient loop would sleep for real → introduce the override seam (below).

**Institutional learnings applied:**
- `2026-06-30-adaptive-ci-poll-gate-wall-clock-ceiling-not-attempt-count.md` — **apply retry at one level only** (avoid multiplicative attempts). Loop stays in `_ghcr_pull_or_recover`, not the caller. (The wall-clock-vs-attempt-count guidance is noted but a fixed 2-element backoff array is already deterministically bounded to ≤6 s; a `date +%s` ceiling would add epoch-math complexity for no benefit — see Alternatives.)
- `2026-07-13-web-2-fsn1-fresh-boot-image-pull-auth-denied-stale-baked-cred.md` — re-fetch/retry on USE-FAILURE not just absence; the `stage`/`recovery_stage` tag makes boot-vs-deploy pull failures Sentry-queryable without SSH.
- `2026-07-15-silent-fallback-masked-a-dead-primary-for-14-days.md` — **alarm on fallback/recovery USAGE**: emit a monitored `transient_recovered` breadcrumb so retry-saves are visible (a working retry that masks a chronically flaky path is a signal, not silence).
- `2026-07-07-immutable-redeploy.md` (SE 1-3, #6400/#6415) — **over-claim guard**: a private-NIC-down host is NOT a transient timeout; retry will exhaust and fail. Do not assert this "fixes #6525" wholesale.
- `2026-06-12-octokit-wraps-undici-connect-timeout...md` — classify only genuine transients, narrowly. (bash analogue: match docker's stderr **substrings** for the fleet's real shapes, not broad tokens that would swallow `manifest unknown` / auth.)

**Premise Validation:** #6525 is OPEN (`gh issue view 6525` → `state: OPEN`, `closedByPullRequestsReferences: []`) — premise holds, this is a genuine unfixed bug. The cited functions/predicates all exist at the lines above (grepped). The #6594/PR-B handover comment is present on the issue and lays out exactly this fix direction ("widen the retry classifier to cover transient/network stderr (bounded backoff), not to touch the fail-closed both-registries semantics"). No stale premise.

## Research Reconciliation — Spec vs. Codebase

| Handover / issue claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "GHCR leg retries once, auth-only" | `_ghcr_pull_or_recover:1381` gates the single retry on `_pull_result_is_auth_denied` only | Add a transient branch with bounded backoff; auth branch untouched |
| "transient failure gets ZERO retries" | Confirmed — a non-auth stderr falls straight to `return 1` (`:1396`) with empty `RECOVERY_STAGE` | Transient stderr now enters a capped retry loop |
| "returns failure only when BOTH registries fail" | Confirmed (`pull_image_with_fallback` returns 1 only after zot AND `_ghcr_pull_or_recover` fail) | **Unchanged** — fail-closed downtime-safe semantics preserved |
| A `network` classifier "already exists" | Only inline inside `pull_failure_event:549`, narrower than the fleet's real shapes; not shared with the recovery gate | Extract `_pull_result_is_transient` as the shared predicate; `pull_failure_event` calls it (anti-drift, mirrors `_pull_result_is_auth_denied`) |

## User-Brand Impact

**If this lands broken, the user experiences:** at worst a marginally slower deploy (bounded ≤ ~6 s per GHCR leg of added backoff). A logic error in the loop still resolves to the existing fail-closed path — the prior container keeps serving prod (no new user-facing outage is introduced by this change). A regressed classifier that mis-retries a genuine auth/manifest failure would delay the (still-correct) fail-closed abort by ≤ the backoff budget, not change its outcome.

**If this leaks, the user's data is exposed via:** nothing new. The retry adds no data to any telemetry: docker stderr is already scrubbed to a coarse class BEFORE any Sentry payload (`pull_failure_event:538`), and the new `transient_recovered` breadcrumb carries only `ref` + `stage` + `host_id` via `jq -n --arg` (no raw stderr), reusing the audited `pull_auth_recovery_event` transport.

**Brand-survival threshold:** aggregate pattern — a regression in the shared pull path degrades **deploy reliability across all releases** (aggregate), not a single-user data incident. No per-PR CPO sign-off required; the section is present per preflight Check 6.

## Hypotheses

Feature keywords (`timeout`, `connection reset`, `network`, `unreachable`) trip the Network-Outage gate. This plan is a **code-side absorption fix**, not a host-outage diagnosis, so the L3→L7 host-layer checks are **opted out** with the artifact below (per the checklist's Opt-out clause), because the failure has already been root-caused and the two failure classes are separated:

1. **Transient first-attempt condition on the pull path (the class THIS PR fixes).** Verification artifact: the #6594/PR-B handover comment on #6525 traced `_ghcr_pull_or_recover` and established the retry-starvation mechanism (auth-only retry ⇒ zero retries for network stderr); both artifacts (zot mirror `MIRROR_STATUS: ok`, GHCR image present before the deploy) confirm the image existed in both registries when the host pulled fast-fail — i.e. a transport-layer blip, not a missing artifact. This is the v0.216.1/.2 shape (rerun succeeds). **[verified: handover comment + issue body registry-presence evidence]**
2. **Durable host degradation (the class THIS PR does NOT fix — L3 host layer).** v0.217.0's own state dump reports `inngest_server/vector: inactive`, `seccomp_profile_host_present: false`, and the rerun did NOT clear it. This is the private-NIC/IMDS first-boot race owned by #6415 (`soleur-private-nic-guard.sh`) / #6400 / #6565. For this class the bounded retry correctly **exhausts and fails-closed** (old container stays live) and emits `recovery_stage=transient_exhausted` so the durable case is Sentry-distinguishable from a transient one. **[opt-out artifact: this class is tracked and remediated on #6415/#6400/#6565 — L3 firewall/NIC verification is their scope, not this code change's; retrying a down NIC cannot succeed by construction.]**

**Absence-of-signal note:** if post-deploy Sentry shows `image-pull-recovery / recovery_stage=transient_recovered` events on `hetzner-150638239`, the transient class was real and is now absorbed; if it shows only `image pull failed / recovery_stage=transient_exhausted`, the occurrence was durable host-degradation (route to #6415/#6565), confirming the two-class split rather than a fix regression.

## Implementation Phases

> TDD: write the failing tests first (`cq-write-failing-tests-before`), then the source. Test path: `apps/web-platform/infra/ci-deploy.test.sh` (run offline via `bash apps/web-platform/infra/ci-deploy.test.sh`; CI runs it in `infra-validation.yml` `deploy-script-tests`, which fires on `apps/*/infra/**`).

### Phase 1 — RED: transient-classifier + transient-retry tests

Add to `ci-deploy.test.sh`:

1. **Classifier positive/negative fixtures for `_pull_result_is_transient`** — source the script and assert the predicate returns 0 for each fleet-real transient string (reuse `:3555-3600` verbatim): `network is unreachable`, `read: connection reset by peer`, `: EOF`, `no such host`, `connection refused`, `i/o timeout`, `TLS handshake timeout`, `temporary failure`. Assert it returns non-zero for an **auth** string (`denied: requested access to the resource is denied`) and a **manifest** string (`manifest unknown`) — the predicate must NOT swallow the higher-precedence classes.
2. **`pull_failure_event` still tags `network`** for a transient stderr after the refactor (proves the extracted predicate is wired into the classifier arm; grouping tag value unchanged).
3. **Transient retry recovers** — new mock arm `MOCK_GHCR_PULL_TRANSIENT_COUNT_FILE` (countdown emitting a transient stderr, then succeed). With count=1 and `PULL_TRANSIENT_RETRY_SLEEPS="0 0"`, assert: 2 GHCR pulls, a `transient_recovered` recovery event (`op:image-pull-recovery`), NO `pull_failure_event`, overall success.
4. **Transient retry exhausts → fail-closed + tagged** — transient stderr on every pull, `PULL_TRANSIENT_RETRY_SLEEPS="0 0"`: assert 3 GHCR pulls (1 + 2 retries), `pull_failure_event` fired with `pull_result=network` and `recovery_stage=transient_exhausted`, overall failure (old container stays live), NO recovery event.
5. **Non-transient, non-auth (manifest) → NO retry** — manifest stderr: assert exactly 1 GHCR pull, `pull_result=manifest_unknown`, empty `recovery_stage`, failure (regression guard: we did not widen retries to manifest-unknown).
6. **Auth path unchanged** — re-assert #6400 AC1/AC2/AC14 semantics hold byte-for-byte (these existing tests must not be edited except where the shared mock arm is added; run the full file).
7. **Single-source-of-truth wiring guard** — grep-assert `pull_failure_event`'s network arm calls `_pull_result_is_transient` (not a second inline regex), mirroring the existing `_pull_result_is_auth_denied` shared-predicate guard at `:3423-3427`.

### Phase 2 — GREEN: source changes in `ci-deploy.sh`

1. **Add `_pull_result_is_transient`** beside `_pull_result_is_auth_denied` (`~:533`), same single-source-of-truth doc comment. Regex (case-insensitive, docker-stderr substrings, non-overlapping with auth/manifest):
   `timeout|timed out|i/o timeout|temporary failure|no route|connection refused|connection reset|network is unreachable|no such host|tls handshake timeout|\bEOF\b`
2. **Rewire `pull_failure_event`'s `network` arm** (`:549`) to call `_pull_result_is_transient "$detail_raw"`. Keep precedence auth → manifest_unknown → transient → pull_failed and keep the emitted tag value `network` (Sentry grouping/alert keys unchanged).
3. **Add the transient branch to `_ghcr_pull_or_recover`** (`:1376-1397`). Structure — a bounded loop whose auth branch `return`s from inside (never loops), preserving #6400:
   - Declare the backoff schedule with a test-only override: `local -a _sleeps=( ${PULL_TRANSIENT_RETRY_SLEEPS:-2 4} )` (production `2 4`; tests set `"0 0"`). Mirrors the file's `SOLEUR_GHCR_READ_FILE` test-only-override precedent; `local max=${#_sleeps[@]}`, `attempt=0`.
   - Loop: `docker pull … 200>&- 2>"$perr"` → on success, if `attempt>0` emit `pull_auth_recovery_event "${IMAGE}:${TAG}" transient_recovered` then `return 0`.
   - On failure classify `detail="$(tail -c 400 "$perr")"`:
     - `_pull_result_is_auth_denied` → **existing #6400 recovery, verbatim** (refetch+relogin+single retry, sets `RECOVERY_STAGE`), then `return 1` — auth never enters the transient loop.
     - `_pull_result_is_transient` && `attempt < max` → `sleep "${_sleeps[$attempt]}"`; `attempt=$((attempt+1))`; continue.
     - else (transient exhausted OR manifest/unknown) → if `attempt>0` set `RECOVERY_STAGE="transient_exhausted"`; `return 1`.
4. **Comment** the one-level-retry decision (zot stays immediate-fallback = a different-registry retry; the caller does not retry) and the ≤6 s added-wall-clock bound.

### Phase 3 — Verify budget + delivery guards

1. Run `bash apps/web-platform/infra/ci-deploy.test.sh` — full suite green (including the #5145 drift guard at `:2890-2972` — it must stay green; the pull sleeps are upstream of the verify loop and are not health/cron attempts, so they do not enter `DG_RIGHT`).
2. `shellcheck apps/web-platform/infra/ci-deploy.sh` (if wired in CI) — no new findings.
3. Confirm the added worst-case wall-clock: `2` retries × `[2 s, 4 s]` = **≤6 s per GHCR leg**, ≤12 s across the web + inngest pulls — negligible vs the deploy budget; state it in the PR body.

## Delivery

`ci-deploy.sh` is pushed to the host solely by `terraform_data.deploy_pipeline_fix` (`server.tf:933-942`, whose `triggers_replace` hashes `ci-deploy.sh`). The dedicated workflow **`apply-deploy-pipeline-fix.yml`** auto-applies on `push` to `main` touching `apps/web-platform/infra/ci-deploy.sh` (path filter `:66`) and `-target`s that resource over the CF-Tunnel SSH bridge. **So merging this PR delivers the fix to the host automatically — no operator SSH, no manual `terraform apply`** (satisfies the automation-feasibility gate and `hr-all-infrastructure-provisioning-servers`). The change takes effect on the FIRST deploy after the apply completes.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `_pull_result_is_transient` exists beside `_pull_result_is_auth_denied` and matches all fixtures at `ci-deploy.test.sh:3555-3600`; returns non-zero for auth + manifest strings (test: classifier positive/negative).
- [ ] `pull_failure_event`'s network arm calls `_pull_result_is_transient` (grep guard) — single source of truth, no second inline regex.
- [ ] Transient failure retries with bounded backoff: count=1 mock recovers (2 pulls, `transient_recovered` event, no failure event); exhaust mock fails after exactly 3 pulls with `pull_result=network` + `recovery_stage=transient_exhausted`.
- [ ] Manifest/unknown stderr gets exactly 1 pull (no retry); regression guard green.
- [ ] #6400 AC1/AC2/AC14 (auth recovery) pass unchanged; `pull_image_with_fallback` still returns 1 only when BOTH registries fail (fail-closed).
- [ ] Full `bash apps/web-platform/infra/ci-deploy.test.sh` green, including the #5145 drift guard.
- [ ] Added wall-clock ≤6 s/leg documented in the PR body.
- [ ] PR body uses `Ref #6525` (NOT `Closes`) — see below.

### Post-merge (automatic — no operator action)
- [ ] `apply-deploy-pipeline-fix.yml` runs on merge and applies `terraform_data.deploy_pipeline_fix` (the fix reaches the host). Verify via the workflow run conclusion (Automation: `gh run list --workflow=apply-deploy-pipeline-fix.yml`).
- [ ] Issue closure is soak-gated, not merge-gated (the fix only exercises on real deploys). Close #6525 only after observability confirms the transient class is absorbed (see `## Observability` soak) — hence `Ref`, not `Closes`.

## Observability

```yaml
liveness_signal:
  what: registry_pull_event (zot|ghcr-fallback) fires on every successful deploy pull
  cadence: per deploy (6-12/day)
  alert_target: Sentry op:image-pull / zot_mirror_fallback_rate alert (issue-alerts.tf) — unchanged
  configured_in: apps/web-platform/infra/ci-deploy.sh registry_pull_event + infra/sentry/issue-alerts.tf
error_reporting:
  destination: Sentry (pull_failure_event, op:image-pull, level:error, host_id + recovery_stage tags) + journald IMAGE_PULL_FAIL (Better Stack via vector, SYSLOG_IDENTIFIER=ci-deploy)
  fail_loud: yes — terminal both-registries failure emits pull_failure_event before final_write_state 1 image_pull_failed
failure_modes:
  - mode: transient GHCR pull failure absorbed by retry
    detection: pull_auth_recovery_event op:image-pull-recovery, recovery_stage=transient_recovered, host_id-tagged (in-band: emitted from the deploy host itself, no SSH)
    alert_route: Sentry op:image-pull-recovery (info) — sustained volume = chronically flaky pull path signal (per 2026-07-15 learning)
  - mode: transient failure exhausts the bounded retry (durable/degraded host)
    detection: pull_failure_event pull_result=network, recovery_stage=transient_exhausted
    alert_route: Sentry op:image-pull (error) — recovery_stage discriminates transient-exhausted (this class) from durable host-degradation triage (#6415/#6565)
  - mode: auth/manifest failure (unchanged)
    detection: pull_failure_event pull_result=auth_denied|manifest_unknown, recovery_stage per #6400
    alert_route: Sentry op:image-pull (error)
logs:
  where: journald tag ci-deploy → Better Stack (vector.toml allowlist); Sentry store endpoint
  retention: Better Stack + Sentry defaults (unchanged)
discoverability_test:
  command: "gh run list --workflow=apply-deploy-pipeline-fix.yml --limit 3  # then query Sentry issues op:image-pull-recovery recovery_stage=transient_recovered on hetzner-150638239 — NO ssh"
  expected_output: "post-fix, a transient blip on hetzner-150638239 yields a transient_recovered recovery event (absorbed) instead of an image_pull_failed deploy abort; a durable host still yields recovery_stage=transient_exhausted (routes to #6415/#6565)"
```

**Soak (issue-close gate):** keep #6525 open until either (a) a post-fix deploy on `hetzner-150638239` emits `transient_recovered` (the transient class is provably absorbed), or (b) ≥7 days of releases pass with no first-attempt `image_pull_failed` of the transient class. This is a lightweight observability check, not a scripted follow-through enrollment — no new `scripts/followthroughs/` probe is warranted for a single-issue close gate (the signal is already in Sentry).

## Out of Scope

- **#6565 (zot/GHCR login failure, cred_store classifier / errno_chars).** Diagnosable, not part of this fix — recovering the host means the `cred_store` classifier + `errno_chars` field run there and pin the exact errno on the next occurrence. No change here.
- **Durable host-degradation occurrences of #6525** (v0.217.0 class: private-NIC/IMDS first-boot, inngest/vector inactive) — owned by #6400 / #6415 (`soleur-private-nic-guard.sh`) / #6497. The bounded retry correctly fails-closed for these; it does not repair a wedged host.
- **Wrapping each `docker pull` in an outer `timeout N`** to bound per-attempt latency — a separate hardening (docker has its own client timeouts); the fixed backoff array already bounds ADDED wall-clock regardless. Considered; deferred (no tracking issue — low value, docker-client timeouts already apply).
- **In-place zot-leg retry** — deliberately not added: a zot failure already falls back to GHCR (a different-registry retry), and retrying both legs would violate the one-level-retry rule (multiplicative attempts).

## Alternatives Considered

| Alternative | Decision |
|---|---|
| Wall-clock ceiling (`date +%s` epoch math) instead of a fixed backoff array | **Rejected.** The 2026-06-30 learning targets loops whose per-iteration latency is unbounded (chained API calls). Here each attempt is one `docker pull` and the backoff is a fixed 2-element array — added wall-clock is deterministically ≤6 s. Epoch math adds complexity for no bound benefit. |
| Reuse the file's `until … sleep 5 … n≥3` idiom verbatim | **Rejected** for the sleep interval (5 s×2 = 10 s is heavier than needed and hardcoded blocks fast tests). Kept the 3-attempt cap idiom; used an explicit `[2 4]` schedule with a test-only override seam (`SOLEUR_GHCR_READ_FILE` precedent). |
| Add retry in `pull_image_with_fallback` (caller) instead of `_ghcr_pull_or_recover` | **Rejected** — one-level-retry rule (2026-06-30); the caller cannot set `RECOVERY_STAGE` cleanly and would multiply attempts against the auth retry. |
| A second inline `network` regex in the recovery gate | **Rejected** — regex drift (the exact hazard the file documents for `_pull_result_is_auth_denied`). Extract one shared `_pull_result_is_transient`. |
| Broaden `_pull_result_is_transient` to also retry `manifest_unknown` | **Rejected** — a missing manifest is not transient; retrying wastes the deploy window. Regression-guarded (Phase 1 test 5). |

## Domain Review

**Domains relevant:** none

Infrastructure/CI bug fix on an already-provisioned script (`apps/web-platform/infra/ci-deploy.sh` + its test). No user-facing surface (no `components/**`, `app/**/page.tsx`, `app/**/layout.tsx` — mechanical UI-surface override does not fire), no regulated-data surface (GDPR gate 2.7 skipped), no new infrastructure/secret/vendor (IaC gate 2.8 skipped — edits an existing hashed-trigger script, delivered by the existing `apply-deploy-pipeline-fix.yml`), no architectural-decision change (ADR gate 2.10 skipped — the ADR-096 zot-primary/GHCR-fallback topology and the both-registries fail-closed contract are UNCHANGED; a bounded retry-classifier widening on an existing leg is a refinement, not a new boundary — a competent engineer reading ADR-096 would not be misled).

## Sharp Edges

- The `## User-Brand Impact` section is populated (threshold `aggregate pattern`); do not blank it — an empty/`TBD` section fails `deepen-plan` Phase 4.6 and preflight Check 6.
- The auth branch in `_ghcr_pull_or_recover` MUST `return` from inside the loop (never `continue`), or a `MOCK_GHCR_PULL_DENY_ALWAYS` auth failure would loop and burn the window — breaking #6400 AC2/AC14. Keep the transient loop strictly for the transient class.
- `_pull_result_is_transient` regex must stay non-overlapping with `_pull_result_is_auth_denied` (`unauthorized|denied|forbidden|authentication required`) and the manifest arm (`manifest unknown|not found|no such manifest`). Note `no such host` (transient) vs `no such manifest` (manifest) share `no such` — anchor on the full token (`no such host`), and keep classifier precedence auth → manifest → transient in `pull_failure_event`.
- Do NOT rename the `pull_result` tag value `network` — Sentry grouping and the `zot_mirror_fallback_rate` alert key on it. The new predicate is the source of the SAME tag value.
- Use `Ref #6525` in the PR body, not `Closes` — the fix only exercises on real deploys; auto-closing at merge before the soak confirms absorption would false-resolve it (`wg-use-closes-n-in-pr-body-not-title-to` / ops-remediation Closes-vs-Ref pattern).
