---
title: "fix: seccomp remediation redeploy — reuse the already-running image on registry-prune, and make an unenforced profile a standing alarm"
type: fix
date: 2026-07-17
issue: 6512
lane: cross-domain
brand_survival_threshold: aggregate pattern
adr: ADR-079 (amend — governing decision for the profile-apply→redeploy verification contract)
---

# fix: seccomp remediation redeploy fails (image_pull_failed on an already-running tag) — profile left unenforced and invisible

## Overview

The `apply-deploy-pipeline-fix.yml` "item 4" step (ADR-079 / #5875) exists to close the "applied ≠
loaded" gap: after a seccomp-profile change is delivered to the host, the *running* container only
picks up a new `--security-opt seccomp=<file>` at `docker run`, so the step sequences a graceful
redeploy and asserts the running container is enforcing the committed profile. On 2026-07-16 (issue
#6512) that redeploy terminated `image_pull_failed` on tag `v0.214.7`, leaving `seccomp_profile_host_present=false`
— **the security control is not in force, and the only signal was one red job among a page of green.**

This plan does **two** deterministic, in-repo things and **one** in-session diagnosis:

1. **Fix 1 — Robustness (root-cause for the reload-pull leg).** The seccomp redeploy targets
   `v<running_version>` — the image the container is *already running*, cosign-verified at its original
   deploy and always present in the host's local docker store. Yet `ci-deploy.sh` re-pulls it through the
   registry chain (zot-primary → GHCR-fallback), whose zot keep-set is now **5 `v*` tags**
   (`variables.tf:176`, #6246). A several-releases-old running version is GC-eligible from zot; if the GHCR
   leg then also fails, the reload dies `image_pull_failed` **for an image that needs no new bits**. Add a
   `local-cache` last-resort tier to `pull_image_with_fallback` that, on both-registries-fail for a `web`
   same-version reload, **reuses the running container's image ID as `VERIFIED_REF` (skipping re-verify with
   an explicit cosign-reuse decision — NOT the warn-mode fail-open)** and emits a monitored, separately-alerted
   `registry=local-cache` event.

2. **Fix 2 — Visibility, made ACTIONABLE (the issue's core ask #3 — the #6454 shape).** Split by plan-review:
   **2a (ship):** the item-4 step, on a redeploy terminal failure, emits a Sentry event (dedicated
   issue-alert) AND files a plain-language `ci/seccomp-unenforced` GitHub issue before `exit 1` — the
   operator-visible, actionable signal for the observed failure. **2b (Phase-0-gated):** a standing 6h
   enforcement probe that, on unenforcement, age-gated-**auto-dispatches** the idempotent re-enforcement +
   files the same plain-language issue (mirroring the accepted `scheduled-inngest-health.yml` watchdog) —
   built only if Phase 0 confirms a non-merge unenforcement path, else deferred. Non-technical-founder
   actionability (CTO) and not-building-speculative-apparatus (simplicity) are both honored.

3. **Diagnosis (in-session, no SSH).** Confirm the zot-prune hypothesis (validates Fix 1's target leg) and
   make the light "does a non-merge unenforcement path exist?" determination that gates Fix 2b. The DEEP
   delivery-leg root cause (`host_present=false`) is a separate bug filed as a tracked follow-up —
   the issue itself sanctioned "filed rather than fixed inline" for the
   live-state-dependent parts.

## Problem Statement

### What the issue reports (verbatim log)

```
Baseline: host_present=false host_sha256='<none>' loaded_matches_host=false (committed='7654ef…', tag='latest').
STATE invariant not satisfied — a seccomp change is applied but the running container is not enforcing it. Redeploying to load it.
Redeploying running version as v0.214.7 (state-file .tag was 'latest').
Redeploy FAILED: web-platform v0.214.7 terminal reason='image_pull_failed' exit_code=1. The applied seccomp profile was NOT loaded.
```

### The two questions the issue separates — and where each actually lands

- **Q1 "Why is the state-file `.tag='latest'`?"** — **Superseded / not the resolution source.** ADR-079
  amendment **#5955** already changed the redeploy to resolve its target version from the public
  `/health` `.version` (`apply-deploy-pipeline-fix.yml:631-633`), *not* from the state-file `.tag`. The
  `.tag='latest'` string appears **only in the diagnostic log** (`:640`, `:643`); `CURRENT_TAG` is read
  at `:589` and used nowhere in the resolution path. `v0.214.7` was the genuinely-running version at
  21:03 (v0.215.x released *after*, 21:13/21:23), correctly resolved from `/health`. **Chasing "fix the
  state-file tag" would fix a non-bug.** See §Research Reconciliation.

- **Q2 "Why did pulling `v0.214.7` fail when GHCR demonstrably has it?"** — **This is the real bug**, and
  it is fixable at the reload layer without pinning the exact registry-leg failure. The seccomp reload
  targets the already-running image; a registry pull is unnecessary for a reload and is the single point
  of failure. The tightened zot keep-set (5 `v*`, #6246) makes a several-releases-old running version
  GC-eligible from the zot-primary path; the GHCR fallback leg then failing (the #6090 stale-baked-cred
  class, or GHCR degradation) yields `image_pull_failed`.

### The damage that makes this a filed P1: invisibility

`host_present=false` = the container's seccomp layer of the tenant-agent sandbox boundary (ADR-079 §context;
the profile governs the SDK's `unshare()` calls) is **off**, and prod health hides it completely — the exact
"gate reporting nothing wrong while checking nothing" shape of #6454. This is the highest-value, lowest-risk,
fully-deterministic part of the fix.

## Research Reconciliation — Issue premise vs. codebase reality

| Issue claim | Reality (verified) | Plan response |
|---|---|---|
| "state-file `.tag='latest'` … aims the remediation at a stale image" (ask #1) | Redeploy resolves target from `/health` `.version` (`apply-deploy-pipeline-fix.yml:631-633`, ADR-079 #5955). `.tag` is read at `:589` and used only in log strings `:640/:643`. `v0.214.7` was the *correct* running version. | Do **not** touch state-file tag resolution. Document the supersession in the ADR amendment + PR body so no future reader re-opens it. |
| "the fallback ('redeploy the running version') resolved to a version several releases stale" | The running version genuinely *was* v0.214.7 at redeploy time; v0.215.x released later. Not stale-resolution — the running image simply couldn't be re-pulled. | Fix the *pull* of the running image (Fix 2), not the resolution. |
| "zot retention/GC pruning older tags … unverified — do not treat as the diagnosis" | zot keep-set is **5 `v*`** (`variables.tf:176`, #6246 tightening); GHCR retains more (image present in GHCR per issue). Consistent with zot-prune + GHCR-leg failure. Still **unverified for this specific run** → Phase 0 confirms. | Fix 2 removes zot-prune as a failure mode for a *reload* regardless of the precise leg; Phase 0 captures the evidence. |
| `host_present=false` framed as the redeploy's fault | Distinct **delivery-leg** failure (the profile file was not on the host *before* the redeploy). "Apply web-platform infra succeeded on the same commit" but the file was absent — a delivery/host-replacement question, live-state-dependent. | Diagnose in Phase 0; fold if it is a repo defect, else tracked follow-up (§Deferred). |

## Proposed Solution

### Architecture

Two independent, composable fixes plus a diagnosis gate. Neither fix depends on the other; Fix 1
(visibility) ships standalone value even if Fix 2 is descoped, and vice-versa.

**Fix 1 — `local-cache` fallback tier in the deploy executor's pull chain.**
`apps/web-platform/infra/ci-deploy.sh` `pull_image_with_fallback()` (line ~1399) currently degrades
zot-primary → GHCR-fallback (ADR-096), and on both-fail sets `final_write_state 1 "image_pull_failed"`
(web path `:2132-2133`). Add a THIRD tier evaluated only after both registries fail:

**This is NOT a `return 0` — it must produce a runnable `VERIFIED_REF` and make an EXPLICIT cosign decision
(architecture-strategist P1-A, the finding that would otherwise ship a no-op + a silently fail-opened cosign
gate).** The pulled image is never run directly: `pull_image_with_fallback` → `VERIFIED_REF="$(verify_image_signature
"$IMAGE:$TAG")"` (`ci-deploy.sh:2142`) → every `docker create`/`run` consumes `$VERIFIED_REF`
(`:2166/:2259/:2493`), never `$IMAGE:$TAG`. In the #6512 topology the running image is tagged under the
**zot** ref, so a naive `return 0` leaves `IMAGE=ghcr.io/…` (un-reassigned; reassign is `:1414` on zot
*success*), `verify_image_signature "ghcr.io/…:$TAG"` finds no local RepoDigest → in default `warn` mode
(`:54`) it **fail-opens cosign** and `docker run` attempts a fresh network pull (both down) → deploy fails
anyway; in `enforce` mode it dies `cosign_verify_failed`. Either way the fix does not fix the bug.

```sh
# Both registries failed. Rescue ONLY a genuine same-bits reload of the RUNNING
# container's image (the item-4 seccomp path targets v<running_version> by
# construction — #5955). The running container's image is cosign-verified-at-
# original-deploy, immutable @sha256, and always local. Reuse it by IMAGE ID and
# make an EXPLICIT cosign-reuse decision — never fall through the warn-mode
# fail-open. Container literal is `soleur-web-platform` (:2474) — there is NO
# $CONTAINER_NAME variable in ci-deploy.sh (P1-B; a bare $CONTAINER_NAME aborts
# under set -u). Component-guarded: this rescue is web-platform-only.
running_img_id="$(docker inspect --format '{{.Image}}' soleur-web-platform 2>/dev/null || true)"
if [[ "$image_kind" == "web" && "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ \
      && -n "$running_img_id" ]] && docker image inspect "$running_img_id" >/dev/null 2>&1; then
  registry_pull_event "local-cache" "$image_kind" "$TAG"          # 3-arg (:608); level ternary extended
  cosign_verify_event "reused_local_reload" "$running_img_id" \
    "both registries down; reusing the already-verified running image for a same-version seccomp reload"
  LOCAL_CACHE_VERIFIED_REF="$running_img_id"   # caller threads this into VERIFIED_REF, skipping re-verify
  return 0
fi
```

- **Threading (P1-A, must be specified — not deferred to /work):** on this branch the caller
  (`ci-deploy.sh:2140-2143`) uses `LOCAL_CACHE_VERIFIED_REF` as `VERIFIED_REF` and **skips
  `verify_image_signature`** — the running image was cosign-verified at its original deploy (identical
  immutable @sha256 bits), so re-verification is a no-op, and skipping it explicitly (with a
  `cosign_reused_local_reload` event) is the honest posture vs. silently fail-opening the `warn` path. This
  is a deliberate amendment to the ADR-087 cosign contract → recorded in the ADR amendment.
- **Safety (P0-1 + P1-2 + P1-B):** rescues only a `web` deploy of an immutable semver tag whose target is
  the running container's own image ID (always local). A re-pushed tag, a stale leftover, or a genuine
  new-version deploy (never the running image ID) all fall through to the existing hard `image_pull_failed`.
  Blast radius for any genuine version change is zero.
- **Both failure exits (P2-5):** placed at the shared both-failed point covering the `ZOT_ACTIVE==1` and
  zot-dark `return 1` sites, so a `ZOT_ACTIVE=0` reload is also rescued.
- **Runnability backstop (P2-3):** `docker image inspect` proves presence, not that `docker run` succeeds on
  a partially-GC'd layer; the existing post-run health gate is the final backstop.
- **Not silent — a `local-cache` event must PAGE, via a DEDICATED alert (P1-1 + architecture P2s).**
  `registry_pull_event` is `(registry, image_kind, tag)` (`ci-deploy.sh:608`); making `local-cache` a
  watched paging signal requires:
  1. **`ci-deploy.sh:614`** — extend the `level` ternary to
     `if $reg == "ghcr-fallback" or $reg == "local-cache" then "warning" else "info"` (else it emits `info`
     and hides like the 14-day dead primary).
  2. **`apps/web-platform/infra/sentry/issue-alerts.tf`** — add a **SEPARATE** issue-alert
     (`local_cache_reload_rate`) on `registry == "local-cache"`. Do **NOT** add `local-cache` to
     `zot_mirror_fallback_rate` (`:1408`): that alert's non-zero rate is the single no-SSH page gating the
     IRREVERSIBLE ADR-096 §5.5 GHCR retirement — `local-cache` means *neither* registry served, a different
     meaning; overloading it corrupts the retirement gate. `filters_v2` uses `filter_match="any"` so a
     dedicated `tagged_event {registry EQUAL local-cache}` alert is clean.
  3. **`scripts/followthroughs/zot-soak-6122.sh`** — do **NOT** fold `local-cache` into `FAIL_QUERIES[rolling]`
     (architecture P2): a single facet query can't match two registry values, the hardcoded `!= 5` count
     guard (`:232`) + enumerated echo strings (`:270/:421`) would break, and semantically `local-cache` is
     NOT a GHCR-served event (it would produce a false GHCR-retirement signal). Leave the soak untouched;
     the dedicated issue-alert (2) is the local-cache signal.
  4. **`.github/workflows/scheduled-zot-restart-loop.yml:229`** (architecture P2, missed consumer) — its
     remediation runbook greps `betterstack-query.sh --grep ghcr-fallback` for pull-path health BEFORE
     firing a registry-host ForceNew-replace; a host silently on `local-cache` (both registries dead) reads
     CLEAN there → the operator fires the replace blind, the exact #6400 total-outage the runbook guards
     against. Extend that grep to also match `local-cache`.
- **Blast radius:** `pull_image_with_fallback` is the single pull path for every deploy; the tier is
  additive and guarded, so a normal deploy that pulls cleanly never reaches it.

Fix 2 splits into an **always-ship** active-failure alert and a **Phase-0-gated** standing drift probe. This
split is the joint resolution of two plan-review findings: (i) code-simplicity — the OBSERVED incident was an
*active* failure (a redeploy ran and failed loud), fully covered by an actionable alert on that failure; a
standing 6h drift probe watches an *unconfirmed* non-merge unenforcement class, so it must be gated, not built
speculatively; (ii) CTO — whatever alert fires must be **actionable by a non-technical founder**, who cannot
run `gh workflow run`; so every alert files a plain-language GitHub issue AND (for the standing probe)
auto-dispatches the bounded, idempotent re-enforcement, mirroring the accepted `scheduled-inngest-health.yml`
watchdog.

**Fix 2a — active-failure actionable alert (SHIP; maps 1:1 to the #6512 incident).** The item-4 step already
knows the instant a redeploy terminates in `image_pull_failed` / `diagnose_and_fail`. Before `exit 1`, it:
- emits a **Sentry event** (`feature:"agent-sandbox"`, `op:"seccomp-remediation-failed"`, level=error) with a
  **dedicated `issue-alerts.tf` rule** — NOT a cron-monitor check-in (code-simplicity MEDIUM: an event-driven
  check-in to a cadence monitor's slug resets its missed-check-in clock and masks a genuinely-missed
  scheduled beat; keep the event-driven and cadence signals on separate Sentry surfaces);
- files/updates a **plain-language GitHub tracking issue** (`gh issue`, label `ci/seccomp-unenforced`,
  age-gated dedupe like `scheduled-inngest-health.yml:330/363`): *"The seccomp security profile is not
  enforced on the running server and automatic remediation failed."* — the operator-readable surface
  (`operator-digest` harvests `action-required` issues, never PR bodies / red CI jobs).
This is the whole visibility fix for the observed failure, and it is HEAD-independent and cheap.

**Fix 2b — standing seccomp-enforcement drift probe (`scheduled-seccomp-enforcement.yml` + Sentry cron
monitor). BUILD ONLY IF Phase 0 confirms a non-merge unenforcement path exists** (a host replacement / reboot
that leaves the container unenforced WITHOUT an item-4 run — the `host_present=false` delivery-leg class). If
Phase 0 cannot confirm such a path, **defer 2b to a tracked follow-up** (§Deferred) — Fix 2a covers every
unenforcement that an item-4 run produces. If built, it mirrors `scheduled-inngest-health.yml`:
- Every 6h (`cron`) + `workflow_dispatch`, GET `/hooks/deploy-status` (HMAC + CF-Access as item-4
  `:533-542`), read the **LIVE** `seccomp_profile_host_present` / `seccomp_profile_loaded_matches_host`.
  These are runtime ground truth (ADR-079 #5960, `cat-deploy-state.sh:seccomp_live_json` ~:300-363:
  `loaded_matches_host` = live `docker inspect HostConfig.SecurityOpt` vs the host file) — the monitor MUST
  consume these live fields, NEVER the deprecated recorded `.seccomp_profile_sha256` (tmpfs, reboot-cleared).
- **Paging condition = `host_present != true || loaded_matches_host != true`, HEAD-independent (P1-5)** — never
  false-pages during the benign window between a seccomp merge and the host redeploy. The HEAD-hash match is
  the item-4 step's job, not the standing probe's.
- **On unenforcement (mirrors the accepted watchdog, resolving CTO's actionability HIGH):** (1) **age-gated
  auto-dispatch** `apply-deploy-pipeline-fix.yml` (`github.token` `actions:write`, idempotent, no SSH) to
  re-enforce; (2) file/update the same plain-language `ci/seccomp-unenforced` issue; (3) `error` cron
  check-in. *ADR-079 reconciliation:* ADR-079 rejected an **item-4** self-healing verify-LOOP; a SEPARATE
  standing watchdog firing ONE bounded, age-gated, idempotent re-dispatch is the distinct, accepted pattern
  (`inngest-watchdog`), not that loop — recorded in the amendment.
- **Fail-safe on its own instrument — EXPLICIT `error`, never omit (P1-3/P1-4):** endpoint unreachable /
  non-200 / missing field / unset `WEBHOOK_DEPLOY_SECRET`/`CF_ACCESS_*` / HMAC failure → explicit `error`
  check-in with `detail=probe_unavailable` (P2-4, distinguishes "probe broken" from "genuinely unenforced").
  `set -uo pipefail` (not `-e`), `record_failure()` first-structure, initial in-progress check-in, untrusted
  response stripped (`strip_log_injection`). Mutation-test **each conjunct independently** (P2-2), including
  `loaded_matches` (the #6512 reload leg).

**Diagnosis (Phase 0, in-session, no SSH — `hr-no-dashboard-eyeball-pull-data-yourself`).** Deterministically:
(a) Sentry ISSUES surface (not events — #6090 Lesson 2) for the ci-deploy terminal on run 29450562340, its
`registry`/`pull_result` classification (zot-prune vs GHCR leg); (b) a live authenticated GHCR manifest fetch
of `v0.214.7` with the current Doppler `GHCR_READ_TOKEN` (the #6090 GHCR-leg test); (c) the running version's
position vs the zot 5-`v*` keep-set horizon. **This confirms Fix 1 targets the actual failing leg.** A
**light** determination — *does a non-merge unenforcement path exist?* — gates Fix 2b. The **deep**
delivery-leg root cause (why the provisioner left `host_present=false`) is a SEPARATE bug the plan defers
regardless of outcome (code-simplicity MEDIUM), so its RCA moves to the §Deferred follow-up, not this plan.

### Implementation Phases

#### Phase 0 — In-session deterministic diagnosis (no code) + the Fix-2b gate decision

- Query Sentry ISSUES surface (not events — #6090 Lesson 2) for the `image_pull_failed` ci-deploy terminal
  on run 29450562340's host; read `registry` + `pull_result` classification (zot-prune vs GHCR leg).
- Live authenticated GHCR manifest HEAD/GET of `ghcr.io/jikig-ai/soleur-web-platform:v0.214.7` with the
  current Doppler `GHCR_READ_TOKEN` (basic→bearer, #6090). Record HTTP status.
- Confirm the zot keep-set horizon: count `v*` releases between v0.214.7 and the incident-time head. **These
  three validate Fix 1 targets the actual failing leg.**
- **Fix-2b gate:** determine whether a non-merge unenforcement path exists (a host replacement / reboot that
  leaves `host_present=false` WITHOUT an item-4 run) — from `/hooks/deploy-status` history + whether the
  `terraform_data.docker_seccomp_config` provisioner (`server.tf:1024-1056`, keyed on hash AND host id)
  re-runs on a host replacement. If YES → build Fix 2b. If NO/unconfirmed → defer Fix 2b (§Deferred); Fix 2a
  covers item-4-produced unenforcement.
- **Output:** a §Research Reconciliation addendum in the ADR amendment; the Fix-2b build/defer decision. The
  DEEP delivery-leg RCA (why the file was absent) → §Deferred follow-up regardless.

#### Phase 1 — Fix 1: `local-cache` reload tier (RED → GREEN)

- Files: `apps/web-platform/infra/ci-deploy.sh` (`pull_image_with_fallback` tier producing
  `LOCAL_CACHE_VERIFIED_REF` + the caller's skip-reverify branch `:2140-2143` + `registry_pull_event` level
  ternary `:614`), `apps/web-platform/infra/sentry/issue-alerts.tf` (**new dedicated** `local_cache_reload_rate`
  alert — P1-1, NOT overloading `zot_mirror_fallback_rate`), `.github/workflows/scheduled-zot-restart-loop.yml`
  (extend the `:229` health grep to `local-cache` — architecture P2), `apps/web-platform/infra/ci-deploy.test.sh`.
  Do NOT touch `zot-soak-6122.sh` (architecture P2 — `!=5` guard + semantic misdirection).
- RED tests first (`cq-write-failing-tests-before`): (a) both registries fail + `web` + immutable semver +
  running image present → `VERIFIED_REF` resolves to the **running image ID** and the container is run
  end-to-end from it (NOT just `return 0` + event — architecture P1-A test-design gap), emits
  `registry=local-cache level=warning` + `cosign_reused_local_reload`; (b) reproduce #6512's zot-served
  topology (running image tagged under the zot ref, `IMAGE` un-reassigned) → still rescued via running image
  ID (a tier keyed on `ghcr.io/…:$TAG` would MISS — assert it keys on the running ID); (c) running image ID
  absent / TAG≠running / `latest` / non-web → hard `image_pull_failed` (unchanged); (d) zot serves → tier
  never reached, no `local-cache` event.

#### Phase 2 — Fix 2a (SHIP) + Fix 2b (Phase-0-gated) (RED → GREEN)

- **Fix 2a (always):** `apply-deploy-pipeline-fix.yml` item-4 step — on redeploy terminal failure, emit a
  Sentry event (`op:seccomp-remediation-failed`) + file/update a plain-language `ci/seccomp-unenforced`
  GitHub issue (age-gated dedupe) before `exit 1`. Files: `apply-deploy-pipeline-fix.yml`,
  `apps/web-platform/infra/sentry/issue-alerts.tf` (dedicated `seccomp_remediation_failed` alert). `gh` needs
  `issues: write`.
- **Fix 2b (only if Phase 0 gates it in):** `.github/workflows/scheduled-seccomp-enforcement.yml` (new; 6h
  `cron` + `workflow_dispatch`; `actions: write` for the auto-dispatch, `issues: write`),
  `apps/web-platform/infra/sentry/cron-monitors.tf` (one `sentry_monitor`; slug = filename per
  `cron-monitors.tf:8-10`). NOT a required check.
- RED tests (whichever pieces are built): enforced-frame → `ok`; `host_present=false` OR
  `loaded_matches=false` → `error` + auto-dispatch (age-gated) + issue; benign deploy-lag frame
  (`host_sha != HEAD`, still enforcing) → `ok` NOT `error` (P1-5); endpoint non-200 / missing field /
  `secret_unset` → explicit `error` + `probe_unavailable`, never omit (P1-3/P1-4); untrusted body stripped;
  mutation-test each conjunct incl. `loaded_matches` (P2-2).

#### Phase 3 — ADR-079 amendment (+ ADR-096/087 cross-refs) + C4 + tests-green

- Amend `ADR-079` with a new dated `(#6512, 2026-07-17)` amendment: (a) Q1 supersession (state-file `.tag`
  not a source; #5955); (b) the `local-cache` reload tier + its `VERIFIED_REF`/**cosign-reuse posture**
  (explicit skip-reverify for a verified running image — an amendment to the **ADR-087** cosign contract,
  cross-referenced) + the **ADR-096** pull-chain third tier (cross-referenced so a future §5.3 retirement
  editor sees it); (c) Fix 2a + the Fix-2b gate + the self-healing-**loop**-vs-standing-**watchdog**
  reconciliation (ADR-079 rejected an item-4 loop; a separate age-gated single-dispatch watchdog is the
  distinct accepted pattern); (d) Phase-0 findings; (e) the stale-but-enforcing residual (arch P2) as a named
  tracked deferral. ADR-079 stays `adopting`. Threshold `aggregate pattern` unchanged.
- C4: **no new element** (§Architecture Decision) — one-line "no `.c4` files touched".
- Full-suite green: `ci-deploy.test.sh`, the Fix-2 test(s), `terraform validate` (sentry root),
  `actionlint` on any new/edited workflow.

#### Phase 4 — Re-enforce live (automatable post-merge, not manual)

- **Sequencing prerequisite (P1-6): the new `ci-deploy.sh` must be ON THE HOST before re-enforcing.**
  `ci-deploy.sh` runs on the host and is pushed there only by the Terraform provisioner in `server.tf`
  (hashed triggers), NOT by merging the PR. The `ci-deploy.sh` change fires `apply-web-platform-infra.yml`
  on merge, which provisions the new script. Phase 4 MUST wait for that infra apply to complete (verify via
  its workflow run status) — otherwise the `local-cache` tier is not live during the very re-enforcement it
  protects.
- Then re-enforce the profile via `gh workflow run apply-deploy-pipeline-fix.yml` (`workflow_dispatch`) —
  with Fix 1 now on the host, the redeploy's pull can no longer die on a pruned running tag. Confirm
  `host_present=true && loaded_matches_host=true` via one `/hooks/deploy-status` read. `gh`/curl-automatable
  (no SSH); place it in `/soleur:ship` post-merge verification, not `### Post-merge (operator)`.
- The new standing monitor's first check-in will read `error` until this re-enforcement completes (the host
  is unenforced at merge); the honest expectation is an `error → ok` transition, not a first `ok` (P2-1).

## Alternative Approaches Considered

| Alternative | Verdict |
|---|---|
| Widen the zot retention keep-set so the running version is never GC'd | Rejected as the primary fix: a band-aid that (a) doesn't fix the GHCR-leg failure, (b) grows the store, (c) still round-trips a registry for a reload that needs no bits. Fix 1 removes the registry dependency for a reload entirely. May still be a Phase-0-gated follow-up if diagnosis shows the keep-set is the sole cause. |
| Blanket "use local image whenever the registry pull fails" / naive `return 0` on tag-present | Rejected: (a) would serve stale bits for a genuine version change; (b) as `return 0` it leaves `IMAGE` un-reassigned → cosign fail-open + a fresh network pull that dies anyway (arch P1-A). Fix 1 reuses the *running container's image ID* as `VERIFIED_REF` with an explicit cosign-reuse decision — safe by construction. |
| Fix the state-file `.tag='latest'` (issue ask #1) | Rejected: fixing a non-bug — the tag is not the resolution source (#5955). |
| A single standing 6h monitor as the primary visibility fix (original plan) | Restructured, not kept: the OBSERVED incident is an *active* failure fully covered by Fix 2a (item-4 emits an actionable alert). A standing probe watches an *unconfirmed* non-merge drift class → Phase-0-gated (Fix 2b), not built speculatively (code-simplicity). |
| `gh workflow run` as the operator's remediation action | Rejected: a non-technical founder cannot run it (CTO). Every alert files a plain-language GitHub issue; Fix 2b auto-dispatches the bounded re-enforcement itself (mirrors `scheduled-inngest-health`). |
| A self-healing control **loop** at item-4 (poll→detect→retrigger) | Rejected (ADR-079 already rejected it as overbuilt). Fix 2b is a SEPARATE standing watchdog firing ONE age-gated idempotent dispatch — the distinct accepted pattern, not that loop (recorded in the amendment). |

## User-Brand Impact

- **If this lands broken, the user experiences:** no *direct* user-facing artifact — prod stays healthy;
  the failure mode is a *latent* security-hardening gap (the container seccomp layer of the tenant-agent
  sandbox is unenforced) plus a *false-green* monitor if Fix 2 is built wrong (an inert seccomp monitor
  reporting `ok` over an unenforced host — the exact #6537/#6454 recurrence this plan must not rebuild).
- **If this leaks, the user's workflow/data is exposed via:** a compromised tenant agent session escaping
  the bwrap sandbox with a wider syscall surface than the committed seccomp profile intends (defense-in-depth
  degradation, not a direct exfiltration path).
- **Brand-survival threshold:** `aggregate pattern` — aligned with ADR-079's own declared threshold (the
  seccomp gate this plan amends). The failure class is systemic ("a green gate checking nothing"), not a
  single per-PR user incident; no per-PR CPO sign-off is added, but the section and the
  `user-impact-reviewer` cross-check apply at review time.

## Observability

```yaml
liveness_signal:
  what:            "Fix 2a (always): item-4 files a plain-language ci/seccomp-unenforced GitHub issue + op:seccomp-remediation-failed Sentry issue on a redeploy terminal failure. Fix 2b (Phase-0-gated): 6h standing enforcement probe → Sentry cron monitor"
  cadence:         "Fix 2a: event-driven (per item-4 failure). Fix 2b: every 6h cron + workflow_dispatch"
  alert_target:    "Plain-language GitHub issue (operator-digest harvests action-required issues) + Sentry issue (the LARGER alerting plane, model.c4:273)"
  configured_in:   "apply-deploy-pipeline-fix.yml (Fix 2a) + issue-alerts.tf (dedicated alerts); if built: scheduled-seccomp-enforcement.yml + cron-monitors.tf (Fix 2b)"

error_reporting:
  destination:     "Sentry web-platform (Sentry-as-IaC, ADR-031) + GitHub issues. Fix-1 local-cache usage → registry_pull_event level=warning → dedicated local_cache_reload_rate issue-alert"
  fail_loud:       "item-4 failure → plain-language GitHub issue + Sentry event + ::error::+exit 1; local-cache reuse emits level=warning + cosign_reused_local_reload"

failure_modes:
  - mode:          "Redeploy terminal failure (image_pull_failed / diagnose_and_fail) leaves profile unenforced — the #6512 active failure"
    detection:     "Fix 2a: item-4 emits op:seccomp-remediation-failed Sentry event + files ci/seccomp-unenforced GitHub issue before exit 1"
    alert_route:   "GitHub issue (operator-readable) + Sentry issue"
  - mode:          "Non-merge unenforcement (host replacement/reboot → host_present=false, no item-4 run)"
    detection:     "Fix 2b (if Phase-0-gated in): 6h probe reads live discriminators; error iff host_present!=true || loaded_matches!=true (HEAD-independent, P1-5)"
    alert_route:   "Age-gated auto-dispatch of re-enforcement + GitHub issue + Sentry cron issue"
  - mode:          "Fix 2b probe cannot measure (endpoint down / non-200 / missing field / secret unset / HMAC fail)"
    detection:     "fails safe → EXPLICIT check-in=error with detail=probe_unavailable (never ok, never omit) (P1-3/P2-4)"
    alert_route:   "Sentry cron issue; probe_unavailable disambiguates from genuine unenforcement"
  - mode:          "Stale-but-enforcing host (host_present=true, loaded_matches=true, host_sha!=HEAD) between merges"
    detection:     "NOT paged by Fix 2b (HEAD-independent, avoids deploy-lag false-page); item-4 asserts host_sha==committed post-apply. Residual window = tracked deferral (arch P2)"
    alert_route:   "item-4 ::error::+exit 1 on the next seccomp apply; §Deferred residual"
  - mode:          "Seccomp reload re-pull fails at both registries but running image is local"
    detection:     "Fix 1 registry_pull_event registry=local-cache level=warning (fallback usage)"
    alert_route:   "dedicated local_cache_reload_rate issue-alert"
  - mode:          "Seccomp reload re-pull fails at both registries AND running image absent"
    detection:     "final_write_state 1 image_pull_failed (unchanged) → triggers Fix 2a"
    alert_route:   "GitHub issue + Sentry (Fix 2a)"

logs:
  where:           "journald LOG_TAG on the host (registry_pull_event); GitHub Actions run logs for the monitor; Sentry issues"
  retention:       "Sentry issue retention (90d); journald per host rotation; GH Actions log retention (90d)"

discoverability_test:
  command:         "APP_DOMAIN_BASE=$(doppler secrets get APP_DOMAIN_BASE --plain); WEBHOOK_SECRET=$(doppler secrets get WEBHOOK_DEPLOY_SECRET --plain); sig=$(printf '' | openssl dgst -sha256 -hmac \"$WEBHOOK_SECRET\" | sed 's/.*= //'); curl -s --max-time 15 -H \"X-Signature-256: sha256=$sig\" -H \"CF-Access-Client-Id: $(doppler secrets get CF_ACCESS_CLIENT_ID --plain)\" -H \"CF-Access-Client-Secret: $(doppler secrets get CF_ACCESS_CLIENT_SECRET --plain)\" \"https://deploy.$APP_DOMAIN_BASE/hooks/deploy-status\" | jq '{host_present:.seccomp_profile_host_present, host_sha:.seccomp_profile_host_sha256, loaded_matches:.seccomp_profile_loaded_matches_host}'"
  expected_output: '{"host_present": true, "host_sha": "<sha256 of committed seccomp-bwrap.json>", "loaded_matches": true}'
```

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/sentry/issue-alerts.tf` — add TWO **dedicated** issue-alerts (always ships):
  `local_cache_reload_rate` (`registry==local-cache`, Fix 1) and `seccomp_remediation_failed`
  (`op:seccomp-remediation-failed`, Fix 2a). Do NOT extend `zot_mirror_fallback_rate` (it gates the
  irreversible ADR-096 GHCR retirement — architecture P2).
- `apps/web-platform/infra/sentry/cron-monitors.tf` — **only if Fix 2b is Phase-0-gated in**: add ONE
  `sentry_monitor` for `scheduled-seccomp-enforcement` (slug = filename per `cron-monitors.tf:8-10`;
  `failure_issue_threshold` default 1). Provider: existing `jianyuan/sentry` (`main.tf`). No new `TF_VAR_*`.
- Applied by the existing auto-apply root `apply-sentry-infra.yml` (`paths: infra/sentry/**`, FULL-ROOT
  since #6589) — declaring a resource applies it on merge. No new secret, host, or vendor.

### Apply path
- Sentry-API resources applied by the existing sentry root on merge. **Chosen: auto-apply via
  `apply-sentry-infra.yml`.** Blast radius: 2-3 new alert/monitor resources; no destroy. Verify created
  alerts/monitor via the sentry API read post-merge (`/soleur:ship`).

### Distinctness / drift safeguards
- No `dev != prd` split (monitors are prd-only, matching sibling cron-monitors). No
  `lifecycle.ignore_changes` needed. State lands in the sentry root's R2 backend (existing).

### Vendor-tier reality check
- `sentry_monitor` (cron) is available on the current Sentry plan (8+ siblings already declared in
  `cron-monitors.tf`). NOT a `betteruptime_policy`-class paid-tier gate. No `count = var.*_paid_tier`
  guard required.

## Architecture Decision (ADR/C4)

### ADR
- **Amend ADR-079** (`knowledge-base/engineering/architecture/decisions/ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md`)
  — the governing decision for the profile-apply→redeploy verification contract (#5875 item 4). New dated
  amendment `(#6512, 2026-07-17)` recording: (a) Q1 supersession (state-file `.tag` is not a tag source;
  #5955); (b) the `local-cache` reload tier + its running-image-ID safety scoping AND its **cosign-reuse
  posture** — explicit skip-reverify for the already-verified running image, an amendment to the **ADR-087**
  cosign contract (**cross-referenced**), and a **third tier on ADR-096's** zot→GHCR pull chain
  (**cross-referenced** so a future §5.3 GHCR-retirement editor sees it); (c) Fix 2a + the Fix-2b gate + the
  **self-healing-LOOP-vs-standing-WATCHDOG reconciliation** (ADR-079 rejected an *item-4* verify loop; a
  SEPARATE age-gated single-dispatch watchdog, à la `inngest-watchdog`, is the distinct accepted pattern);
  (d) Phase-0 findings; (e) the **stale-but-enforcing residual** (arch P2) as a named tracked deferral.
  Status stays `adopting` (Deferral A / #5889 open). No new ordinal (amendment).

### C4 views
- **No C4 impact.** Enumeration checked against all three model files
  (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`):
  - **External human actors:** none new (operator/founder already modeled).
  - **External systems/vendors:** the alarm rides the already-modeled `sentry` system (model.c4:273, "the
    LARGER of two alerting planes … issue-alerts.tf, cron-monitors.tf") and the already-modeled `zot`/`ghcr`
    pull edges (model.c4:406-407). No new vendor.
  - **Containers / data-stores:** the deploy pipeline (web-platform container, ci-deploy, deploy-status
    endpoint) is modeled under `hetzner`; the `local-cache` tier is internal to the existing pull edge.
  - **Access relationships:** the new monitor emits to Sentry via the already-modeled alerting edge
    (github → sentry cron check-ins, sibling of the existing `cron-monitors.tf` monitors); no new edge
    class. The standing monitor is a sibling of the existing `#6396 Sentry terminal-stage issue-alert`
    (model.c4:408) — same shape, new subject.
  - Confirm at /work by reading all three `.c4` files; run the C4 validation tests
    (`apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`) — a "no impact" conclusion
    that is wrong fails there, not at `tsc`.

### Sequencing
- The ADR amendment is authored in Phase 3 of this plan (in-scope), not deferred.

## Domain Review

**Domains relevant:** Engineering (CTO) only.

No business-domain (Marketing/Sales/Finance/Legal/Support/Operations) implications — this is an
infra/observability change to the deploy pipeline. Product: **NONE** (Files-to-Edit touch
`.github/workflows/`, `apps/web-platform/infra/**`, `apps/web-platform/infra/sentry/*.tf`, ADR docs, and
`*.test.sh` — no UI-surface file per the ui-surface term list). GDPR (Phase 2.7): **skip** — no
schema/migration/auth/API-route surface; the Sentry emit carries only the already-pseudonymized
discriminators (no raw userId; ADR-079 Recital-26 handling unchanged). Engineering/CTO lens is covered by
this plan body + the always-on plan-review CTO panel + deepen-plan's architecture/security/data-integrity
triad.

### Product/UX Gate
Not applicable — Product NONE, no UI-surface file in Files-to-Edit.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open` (61 open) returned zero matches for any of
`apply-deploy-pipeline-fix.yml`, `ci-deploy.sh`, `cat-deploy-state.sh`, `issue-alerts.tf`,
`seccomp-bwrap.json` in the issue bodies.

## Acceptance Criteria

### Pre-merge (PR)

#### Functional Requirements — Fix 1 (local-cache reload tier)
- [ ] The tier fires **only** when both registries fail AND `image_kind==web` AND `TAG` is immutable semver
      AND the running container's image (`docker inspect --format '{{.Image}}' soleur-web-platform` — the
      literal container name, NOT `$CONTAINER_NAME`, P1-B) is present locally. It sets
      `LOCAL_CACHE_VERIFIED_REF` to that image ID and the caller (`:2140-2143`) uses it as `VERIFIED_REF`
      and **skips `verify_image_signature`**, emitting `cosign_reused_local_reload` (explicit reuse, NOT the
      warn-mode fail-open — P1-A).
- [ ] A regression test reproducing #6512's zot-served topology (running image tagged under the zot ref,
      `IMAGE` un-reassigned) proves the container runs **end-to-end from the running image ID** — a tier
      keyed on `${IMAGE}:${TAG}` (= `ghcr.io/…`) would MISS and is RED (P1-A test-design gap).
- [ ] `registry_pull_event "local-cache" "$image_kind" "$TAG"` (3-arg, `:608`); the `level` ternary (`:614`)
      is extended so `local-cache` emits `level=warning`.
- [ ] A **dedicated** `local_cache_reload_rate` issue-alert on `registry==local-cache` exists in
      `issue-alerts.tf`; `zot_mirror_fallback_rate` (the GHCR-retirement gate) is NOT touched, and
      `zot-soak-6122.sh` is NOT touched (architecture P2).
- [ ] `scheduled-zot-restart-loop.yml:229`'s pull-health grep also matches `local-cache` (a host on
      local-cache must not read CLEAN and trigger a blind registry-replace — architecture P2).
- [ ] Both-registries-fail with running-image absent / TAG≠running / `latest` / non-web still terminates
      `final_write_state 1 image_pull_failed` (unchanged); zot-serves never reaches the tier (assert absence).

#### Functional Requirements — Fix 2a (active-failure alert, always ships)
- [ ] The item-4 step, on a redeploy terminal failure, emits a Sentry event
      (`op:seccomp-remediation-failed`, dedicated `issue-alerts.tf` rule) AND files/updates a plain-language
      `ci/seccomp-unenforced` GitHub issue (age-gated dedupe) before `exit 1`. It does NOT check in to a
      cron-monitor slug (event-driven ≠ cadence — code-simplicity MEDIUM). `issues: write` granted.

#### Functional Requirements — Fix 2b (standing probe, ONLY if Phase 0 gates it in)
- [ ] Built iff Phase 0 confirmed a non-merge unenforcement path (else deferred, §Deferred). If built:
      `scheduled-seccomp-enforcement.yml` (6h `cron` + `workflow_dispatch`; `actions: write` + `issues: write`)
      reads LIVE `host_present`/`loaded_matches_host` from `/hooks/deploy-status` (never the recorded
      `.seccomp_profile_sha256`); pages `error` iff `host_present!=true || loaded_matches!=true`
      (HEAD-independent, P1-5); on unenforcement age-gated-auto-dispatches `apply-deploy-pipeline-fix.yml` +
      files the `ci/seccomp-unenforced` issue; a `sentry_monitor` in `cron-monitors.tf` (slug=filename).
- [ ] If built: fails safe with an EXPLICIT `error` + `probe_unavailable` (never omit) on unreadable/secret-unset
      (`set -uo pipefail`, `record_failure()`, initial in-progress check-in — P1-3/P1-4/P2-4); benign
      deploy-lag frame → `ok` not `error` (P1-5); untrusted body stripped; each conjunct mutation-tested incl.
      `loaded_matches` (P2-2).

#### Cross-cutting
- [ ] ADR-079 carries the `(#6512, 2026-07-17)` amendment (Q1 supersession; local-cache tier + cosign-reuse
      posture cross-ref ADR-087; pull-chain third tier cross-ref ADR-096; Fix 2a + Fix-2b gate +
      loop-vs-watchdog reconciliation; stale-but-enforcing tracked residual); status stays `adopting`.
- [ ] `Ref #6512` in the PR body (NOT `Closes` — closure follows Phase-4 live re-enforcement, ops-remediation
      class).

#### Quality Gates
- [ ] `ci-deploy.test.sh`, any Fix-2 test, `actionlint` on new/edited workflows, and the sentry-root
      `terraform validate` all green. Each new safety gate mutation-tested (mutant asserted RED first).
- [ ] No C4 impact — no `.c4` files touched (one-line confirmation; no mandated `c4-render` run for a
      zero-`.c4`-file change).

### Post-merge (operator — all automatable, run in `/soleur:ship`)
- [ ] Confirm `apply-web-platform-infra.yml` (fired by the `ci-deploy.sh` change) completed and provisioned
      the new on-host `ci-deploy.sh` BEFORE re-enforcing (P1-6).
- [ ] `gh workflow run apply-deploy-pipeline-fix.yml` (workflow_dispatch) re-enforces the profile; then one
      `/hooks/deploy-status` read shows `host_present=true && host_sha==committed && loaded_matches=true`.
      Automation: `gh` + curl (no SSH).
- [ ] If Fix 2b was built: the `scheduled-seccomp-enforcement` monitor exists in Sentry; expect an
      `error → ok` transition (host is unenforced until re-enforcement completes — a first `ok` is NOT the
      honest expectation) (P2-1).
- [ ] `gh issue close 6512` after live re-enforcement verifies `host_present=true && loaded_matches=true`.

### Non-Functional Requirements
- [ ] No new `TF_VAR_*`, no new secret, host, or vendor (reuses existing Doppler `prd_terraform` +
      `soleur/prd` secrets and the existing sentry root). Reliability/observability NFR axes only.

## Test Scenarios

### Acceptance Tests (RED targets)
- Given zot fails AND GHCR fails AND an immutable `v<semver>` TAG whose image == the running container's
  image ID, when `pull_image_with_fallback web` runs, then it returns 0, emits `registry=local-cache
  level=warning`, and the deploy proceeds (reuses the running image).
- Given zot fails AND GHCR fails AND the running-container image is absent / TAG image-ID ≠ running / TAG is
  `latest`, when the pull runs, then `final_write_state 1 image_pull_failed` (unchanged).
- Given zot serves the image, when the pull runs, then NO `registry=local-cache` event is emitted.
- Given a `registry=local-cache` event, when the dedicated `local_cache_reload_rate` issue-alert evaluates,
  then it opens a Sentry issue (P1-1 wiring proven, not just emitted); `zot_mirror_fallback_rate` and the
  zot soak are unaffected.
- Given an item-4 redeploy terminal failure, when Fix 2a runs, then a `ci/seccomp-unenforced` GitHub issue is
  filed/updated AND a `op:seccomp-remediation-failed` Sentry issue opens (before `exit 1`).
- Given `/hooks/deploy-status` returns `host_present=false` (or `loaded_matches_host=false`), when the
  standing probe runs (Fix 2b, if built), then it checks in `error` AND age-gated-auto-dispatches the
  re-enforcement.
- Given a benign deploy-lag frame (host on the prior profile but enforcing it: `host_present=true,
  loaded_matches=true, host_sha != HEAD-committed`), when the probe runs, then it checks in `ok` — NOT
  `error` (P1-5, no deploy-lag false-page).
- Given `/hooks/deploy-status` returns HTTP 502 / a body missing `seccomp_profile_host_present` / an unset
  `WEBHOOK_DEPLOY_SECRET`, when the probe runs, then it sends an EXPLICIT `error` check-in with
  `detail=probe_unavailable` — NOT `ok`, NOT an omitted check-in (P1-3/P1-4/P2-4).
- Given an enforced frame (`host_present=true, loaded_matches=true`), when the probe runs, then `ok`.

### Regression Tests (prove the fix)
- Reproduce #6512's exact topology: a zot-SERVED running image (so the local tag is the zot ref, NOT
  `ghcr.io/...` — P0-1), zot prunes it, GHCR leg fails → the tier keyed on the running container's image ID
  still rescues (deploy proceeds, profile loads) instead of `image_pull_failed`. A tier keyed on
  `docker image inspect ghcr.io/...:${TAG}` (the un-reassigned `IMAGE`) would MISS this — assert the fix
  keys on the running image ID.
- The #6537/#6454 anti-recurrence: the standing monitor does NOT report `ok` when it cannot read the
  endpoint (mutation-tested).

### Edge Cases
- Local `${IMAGE}:${TAG}` present but its image ID ≠ the running container's image ID (a tag re-pushed to
  new bits between deploys, or a stale leftover): the `local-cache` tier does NOT fire (image-ID gate) →
  falls through to the existing hard `image_pull_failed`. This is the intended conservative behavior —
  the tier rescues only a true same-bits reload.
- Sentry cron monitor "missed check-in" false-positive on a slow GH runner: set the monitor's schedule +
  `checkin_margin` with headroom (per the `cron-monitors.tf:44-47` false-page note) — 6h cadence gives ample margin.

## Dependencies & Risks

- **Risk: building an inert/false-green monitor (Fix 2).** The dominant failure mode across the cited
  learnings (#6537, #6400). Mitigation: fail-safe-on-own-instrument invariant + assert-discriminator +
  mandatory mutation-testing of every gate + a stub that models the real `/hooks/deploy-status` contract
  (the discriminator fields, not a convenient exit code).
- **Risk: `local-cache` tier weakening a genuine version change / serving stale bits / silently
  fail-opening cosign (architecture P1-A).** Mitigation: it reuses the **running container's image ID** (not
  a possibly-wrong-ref tag) as `VERIFIED_REF` for a `web` immutable-semver reload only, and makes the cosign
  reuse **explicit** (`cosign_reused_local_reload`, skip-reverify of an already-verified image) rather than
  falling through the warn-mode fail-open. A re-pushed tag / stale leftover / new version all fall through to
  hard `image_pull_failed`. Blast radius for any genuine change is zero; the cosign contract change is
  recorded in the ADR-087 cross-ref.
- **Root cause NOT treated by Fix 1: zot's 5-`v*` keep-set can GC the *currently running* version.** Fix 1
  is a backstop, and its local cache is itself prunable (`docker image prune`) — if the running version is
  GC'd from zot AND GHCR's leg fails AND the local image was pruned, the reload still hard-fails
  `image_pull_failed` (now loudly alarmed by Fix 2, not silent). The durable complement — pin the running
  version out of zot GC-eligibility (or resolve the reload via the always-kept `:latest` digest without
  widening the semver-only deploy contract, #5955) — is **tracked** (§Deferred), recorded in the ADR
  amendment. Not built here because Fix 2 makes the residual failure loud and Fix 1 covers the common case.
- **Risk: Phase-0 diagnosis inconclusive on the delivery leg (`host_present=false`).** Then the delivery-leg
  root cause is filed as a tracked follow-up (§Deferred); Fixes 1 & 2 ship regardless (both stand alone).
- **Dependency:** the Sentry `sentry_monitor` resource + `apply-sentry-infra.yml` auto-apply (existing).

## Deferred (tracked)

- **Delivery-leg root cause** (`host_present=false` — why the profile file was absent from the host before
  the redeploy) — the DEEP RCA (provisioner keying / host replacement), separate from this plan's fixes. File
  a GitHub issue (`domain/engineering`, `type/bug`, `priority/p2-high`) with the Phase-0 evidence and a
  re-evaluation trigger. Milestone from `knowledge-base/product/roadmap.md`.
- **Fix 2b (standing enforcement probe), if Phase 0 does NOT confirm a non-merge unenforcement path.** File
  a tracked issue so the drift-catcher is built if/when a non-merge unenforcement path is later observed
  (trigger: a `ci/seccomp-unenforced` issue with `host_present=false` outside a known item-4 run).
- **Stale-but-enforcing residual (arch P2):** a host that reboots/replaces onto a stale-but-enforcing profile
  (`host_present=true, loaded_matches=true, host_sha!=committed`) between seccomp merges is not paged by
  Fix 2b (HEAD-independent) until the next item-4 run. File a tracked issue to close the window (e.g., page on
  a `host_sha!=committed` mismatch that persists across ≥2 consecutive probes — drift, not deploy-lag).
- **zot retention keep-set widening** — only if Phase 0 shows the keep-set is the sole cause AND Fix 1 is
  judged insufficient (it should not be). Tracked, not built here.
- **Re-check the 3 intermittent `Apply deploy-pipeline-fix` failures** (issue ask #4) against the pull-path
  root cause — folded into Phase 0's Sentry query; if a distinct cause, file separately.

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or
  omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section is filled with a concrete
  threshold (`aggregate pattern`).
- **Do not re-open Q1.** The state-file `.tag` is not the redeploy tag source (#5955). Any "fix the tag"
  suggestion is a non-bug (§Research Reconciliation) — the `local-cache` fallback is the fix.
- **Fix 2 must fail safe on its own instrument.** "Could not read `/hooks/deploy-status`" is `error`, never
  `ok`. Mutation-test it before trusting green (the inert-monitor / self-healing-guard learnings).
- **`registry=local-cache` must be a MONITORED emit,** not a bare log line — alarm on fallback usage, or a
  dead registry hides behind a working local cache (the silent-fallback-14-days learning).

## References & Research

### Internal References
- ADR-079 (governing) — `knowledge-base/engineering/architecture/decisions/ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md`; amendments #5955 (tag from /health), #5960 (live loaded proof), #6147/#6353 (reader inventory).
- Item-4 step — `.github/workflows/apply-deploy-pipeline-fix.yml:490-720` (tag resolution :620-643; pull-fail poll :713-717).
- Pull chain — `apps/web-platform/infra/ci-deploy.sh` `pull_image_with_fallback` (~:1399), `registry_pull_event` (:600-614), web `image_pull_failed` (:2132-2133), semver guard (:1919-1925).
- Live discriminators — `apps/web-platform/infra/cat-deploy-state.sh` (`seccomp_live_json` ~:300-363; `.tag` passthrough :436-470).
- zot keep-set (5 v*) — `apps/web-platform/infra/variables.tf:176` (#6246 tightening).
- Monitor precedent — `.github/workflows/scheduled-inngest-health.yml`; `apps/web-platform/infra/sentry/cron-monitors.tf`.
- C4 — `knowledge-base/engineering/architecture/diagrams/model.c4:262/273/406-408` (zot/sentry/pull edges).

### Learnings applied
- `2026-07-15-self-healing-guard-on-a-blind-host-must-fail-safe-on-its-own-instrument.md` — fail-safe on own instrument; mutation-test safety gates.
- `2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire.md` — model the response contract in fixtures; assert discriminator not count; a file-scoped assert can't certify a line property.
- `2026-07-15-silent-fallback-masked-a-dead-primary-for-14-days.md` — alarm on fallback USAGE (`registry=local-cache`), not only total failure.
- `2026-07-13-web-2-fsn1-fresh-boot-image-pull-auth-denied-stale-baked-cred.md` — GHCR `image_pull_failed` classes; query Sentry ISSUES not events; re-fetch-on-failure.
- `2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface.md` — Phase 0 pins the executing path/leg from observability before committing the fix layer.

### Related Work
- Issue: #6512. Superseding amendment: #5955. Related registry/observability: #6122/ADR-096, #6246 (retention), #6090 (GHCR stale cred), #6537/#6454 (inert-monitor / invisible-gate class), #5875/#5960 (item-4).
