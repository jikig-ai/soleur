---
title: Harden agent-sandbox against SDK-bump breakage (canary + observability + SDK guard + redeploy)
type: feat
date: 2026-07-01
lane: cross-domain
closes: 5875
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
adr: ADR-079
---

# Harden agent-sandbox against SDK-bump breakage 🛡️

Prevention follow-ups for the 2026-07-01 P0 (#5873 / fixed by #5874), tracked in **#5875**. #5849 bumped `@anthropic-ai/claude-agent-sdk` 0.2.85→0.3.197, which **split** bwrap setup into `unshare(CLONE_NEWUSER)` then `unshare(CLONE_NEWPID|CLONE_NEWNS)`. The container seccomp profile only allowed `unshare` when `CLONE_NEWUSER` was set, so the second call EPERM'd → the Concierge Bash sandbox was down for **all tenants** until #5874 added two allow-rules. The outage produced **zero server-side signal** (visible only in the agent transcript). This plan makes that class of failure impossible to ship silently again.

PIR: `knowledge-base/engineering/operations/post-mortems/2026-07-01-concierge-bwrap-seccomp-sdk-0-3-outage-postmortem.md`.

## Overview

The incident class is fully closed by **two** load-bearing preventions: a **tagged sandbox-startup-failure event** (signal/MTTR) and a **CI gate that drives the real SDK codepath against the committed profile on any SDK bump** (catches the bad bump pre-merge). The other two items are load-bearing **amplifier** fixes: a faithful canary (the gate's engine) and profile-apply→redeploy ordering (so a *recovery* fix like #5874 actually loads promptly). Sequenced as **3 PRs**, preceded by a blocking spike:

| Step | #5875 item(s) | Ships |
|------|---------------|-------|
| **Phase 0 spike** (blocking, pre-PR) | — | Determine the SDK error-shape + whether the sandbox can be probed without a model round-trip. Both decide PR1's classifier and PR2/PR3's canary shape. |
| **PR1** | Item 2 — sandbox-start observability | Tag + stderr + `sdkVersion`, signature-gated (`sandboxKind !== "other"`) on both catch paths. First (fastest safety win, no dependency). |
| **PR2** | Item 1 — faithful canary | SDK-driven payload, wired **non-blocking** (dark-launch). |
| **PR3** | Items 3 + 4 — SDK-bump guard + profile→redeploy | Both consume the canary; promote it to blocking here. |

(Observability ships first — it is the change that would have given signal for #5873, and it is independent. This is a preference, not a hard constraint; PR1 and PR2 could merge since the canary is non-blocking.)

## Pre-PR Spike (Phase 0 — blocking) — RESOLVED 2026-07-01 (#5875 comment)

Both unknowns resolved against the installed `@anthropic-ai/claude-agent-sdk@0.3.197`:

1. **Error shape — resolved favorably.** The bwrap/seccomp stderr (incl. `Operation not permitted`) is merged into the thrown `Error`'s **`.message`** (plain `Error`, no separate `.stderr`/`.cause`/`.data`); `agent-runner.ts:2648` already reads `err.message`, and `agent-runner-sandbox-config.test.ts:161-167` confirms the SDK writes sandbox failures to stderr→message (#2634). **→ PR1's classifier keyed on `.message` is correct**; it broadens the substring set beyond `"sandbox required but unavailable"` to also match the bwrap/unshare/seccomp/`Operation not permitted` signatures.
2. **No-model-round-trip — resolved NO.** Sandbox init is gated behind `query()` (an Anthropic API call); `startup()` only pre-warms the subprocess (not sandbox validation); the internal Bash tool is always model-driven. **→ a faithful canary needs ANTHROPIC creds + network AND must handle model non-determinism.** This turns PR2's canary into a **mechanism fork routed to the CTO agent at PR2 kickoff** (work-skill architectural-fork gate): (a) *model-turn-driven* (faithful; creds+network; scope to SDK-bump PRs; handle non-determinism) vs (b) *capture-the-SDK-bwrap-argv-once-then-replay* creds-free (decouples faithfulness from the model turn; re-capture on each SDK bump). The chosen mechanism is recorded in ADR-079. PR1 (observability) is unaffected.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (verified on `origin/main`) | Plan response |
|---|---|---|
| Canary at `ci-deploy.sh:~784` probes only `bwrap --unshare-pid` | Confirmed (`:782–794`). Comment L768–781 records the #4932 faithful-probe was reverted (#4941) and a faithful check "must not gate deploys until proven to pass on a healthy host." | PR2 replaces the *content* (faithful split-unshare) but keeps *non-blocking* until PR3 promotes it. |
| SDK-bump detection should watch `bun.lock` | **`package-lock.json` is deploy-authoritative** — the prod image builds via `npm ci` (`Dockerfile:4-5,127-128`); `bun.lock` feeds only CI bun test/typecheck (`ci.yml:293`). There is **no** cross-parity check between the two lockfiles, so they can drift. | PR3 keys the gate on **`package-lock.json`** (both SDK packages) **and** adds a `bun.lock`↔`package-lock.json` version-parity assertion so a future single-lockfile bump can't evade or false-fire. |
| Item 4: "sequence the redeploy after the apply" | The two workflows are in **different** concurrency groups (`terraform-apply-web-platform-host` `apply-deploy-pipeline-fix.yml:128` vs `deploy-web-platform` `web-platform-release.yml:422`) — a shared group serializes but does **not** order. `docker restart` can't reload a `docker run`-time `--security-opt`. | PR3 makes the **apply workflow itself** redeploy (sequenced after the apply) and assert `loaded==committed`, fail loud. `flock` in `ci-deploy.sh` dedupes the concurrent release deploy (idempotent, ADR-068-drained). No self-healing control loop. |
| Item 4 is seccomp-only | `terraform_data.apparmor_bwrap_profile` (`server.tf:747`, sha256-triggered) is **absent from the auto-apply coupling** — not in the `apply-deploy-pipeline-fix.yml` `-target=` set (`:239-256`) nor the #5505 paths-union / #5873 co-target assertions. (It *is* in the #5515 `depends_on` describe.) So an apparmor-only edit doesn't auto-apply at all. | **Fold apparmor apply-parity into PR3** (add to `-target=` set + `on.push.paths` + co-target/paths assertions): identical bug, ~3 lines, same incident class. |

**Premise Validation (Phase 0.6).** All cited references hold: #5875 OPEN (work target), #5874 MERGED, #5873 CLOSED, #5849 MERGED, #4932/#4941 MERGED (the false-rollback lesson — confirmed). All cited files exist. The PIR's four prevention items map 1:1 to #5875's four items — no uncovered item.

## Problem Statement / Motivation

Three independent amplifiers, each closed here:

1. **The deploy canary validated a code path the SDK no longer uses.** `bwrap --unshare-pid` never exercises the split `unshare(CLONE_NEWUSER)` → `unshare(CLONE_NEWPID|CLONE_NEWNS)`, so #5849 shipped **green**. A prior fix (#4932) hand-rolled `--unshare-user --proc /proc`, which *also* mismatched the real SDK argv, false-rolled-back **every** deploy, and was reverted (#4941). Faithfulness is the crux.
2. **Zero server-side signal.** The catch sites tag only the substring `"sandbox required but unavailable"` (the SDK's *missing-binary* preflight, `agent-runner.ts:2649`, `cc-dispatcher.ts:2722`). A seccomp **EPERM** has a different stderr (`bwrap: … Operation not permitted`) → it fell through to a bare untagged `captureException` (`agent-runner.ts:2662`), invisible to on-call filters.
3. **"Applied" ≠ "loaded".** A profile edit auto-applies to the host but the container only loads a new profile at `docker run`; the redeploy that loads it fires **concurrently and unordered** on the same merge. The fix deploy can run the *stale* profile and go green while every tenant stays broken — and this bites hardest during *recovery* (a #5874-style fix must actually load).

## Proposed Solution

### PR1 — Sandbox-start observability (item 2) · ships first

Emit a **structured, `agent-sandbox`-tagged, Sentry-alertable event** for *any* sandbox-startup failure.

- **Minimal, faithful event.** A small `classifySandboxStartupError()` (mirroring the existing `abort-classifier.ts` precedent) returns `{ sandboxKind, errorCode, sdkVersion }` and the event carries **raw stderr** too. `sandboxKind` is a single category enum (`missing_binary` | `seccomp_or_userns_denial` | `other`) keyed off the Phase-0 error shape — not a fan-out of per-hypothesis booleans (a human reads the stderr; add a boolean only when a specific alert route must branch on it).
- **Tag on error SIGNATURE, not stream phase (CTO ruling, ADR-079 — supersedes the plan's original `streamStartSent` guard).** Tag `feature:"agent-sandbox"` iff `classifySandboxStartupError(err).sandboxKind !== "other"` at both catch sites. The `streamStartSent === false` gate the plan originally prescribed was **rejected**: `streamStartSent` is set unconditionally at `agent-runner.ts:2111` *before* the SDK iterator loop, so it is always true at the `:2476` catch; and the #5873 seccomp denial surfaces *after* `stream_start` (the sandbox wraps the model-driven Bash tool, Phase-0 §0.2) — the gate produced a silent no-op on the exact incident shape (0 emits, proven against `agent-runner-sandbox-config.test.ts`). The classifier's namespace/preflight-token requirement is what excludes a mid-conversation model/API error (no token → `"other"`). `cc-dispatcher.ts:2694` is factory-scoped (inherently startup) and already shipped the correct ungated form.
- **Both paths.** Broaden `cc-dispatcher.ts` and `agent-runner.ts`.
- **Don't collapse a fleet outage.** `agent-runner.ts:2650` already emits **undebounced** (`reportSilentFallback`); `cc-dispatcher.ts:2723` uses `mirrorWithDebounce` keyed per-`(userId, class)` → one event per user per TTL, not a global collapse. Keep emit **per-user** (do not introduce a global-key debounce). The `issue-alerts.tf` alert uses Sentry's **native frequency / affected-users threshold** (≥K users in T) — no custom distinct-tenant primitive. **`event_unique_user_frequency` counts distinct Sentry *users*, not `extra` keys** → `reportSilentFallback` must promote `userIdHash` to the event `user.id` (`observability.ts` `userScopeFromExtra`), else the count stays 0 and the alert never fires (found at PR1 review).
- **Pseudonymized attribution.** Pass raw `userId`; the existing helper auto-hashes to `userIdHash` at `observability.ts:217`. Omit/hash `workspacePath`.
- **Alert as IaC (ADR-031):** `apps/web-platform/infra/sentry/issue-alerts.tf`.

### PR2 — Faithful sandbox canary (item 1) · dark-launch, non-blocking

- **Faithfulness = drive the real SDK codepath.** Hand-rolled bwrap argv is **disqualified** (caused #5849's false-green *and* #4932's false-rollback). The payload (`apps/web-platform/scripts/sandbox-canary.mjs`, baked into the image) **imports `agent-runner-sandbox-config.ts`**, feeds that exact options object into the SDK, starts a Bash sandbox, runs a no-op — so its argv *is* the SDK's argv, version-locked to the tree. Per the Phase-0 spike, no model round-trip (or scope to SDK-bump PRs with creds).
- **Two contexts, one payload** — already provided across items: item 1's deploy-time `docker exec` into the running canary container tests the *loaded* profile; item 3's CI `docker run` with the *committed* profile tests pre-merge. No third harness.
- **Non-blocking first.** Wire alongside the legacy `:784` probe. The legacy probe **stays the gate** during dark-launch; the faithful probe only records its verdict. A **"faithful FAIL + legacy PASS"** disagreement is the alertable promote-readiness signal.
- **No-SSH failure surface.** Verdict → deploy-state JSON (surfaced on `/hooks/deploy-status`) **and** a Sentry event — never journald-only (`hr-no-ssh-fallback-in-runbooks`).
- **Exit-code classification (false-rollback prevention).** `docker exec`/binary/OOM failures (125/126/127, ENOENT) = `canary_infra_error` → do **not** roll back; only `bwrap … Operation not permitted` = `sandbox_broken` → (once blocking) hook the existing `ci-deploy.sh:784` rollback path.
- **Bash traps:** `set +o pipefail` around any `cmd | logger`; dedupe with `awk '!seen[$0]++'`.

### PR3 — SDK-bump guard (item 3) + profile→redeploy (item 4)

- **SDK-bump CI gate (item 3).** A `pull_request` job in `ci.yml` that detects a **resolved-version** change of `@anthropic-ai/claude-agent-sdk` or `@anthropic-ai/claude-code` in **`package-lock.json`** (deploy-authoritative), plus a `bun.lock`↔`package-lock.json` parity assertion, and runs the faithful canary via `docker run` on the **committed** profile. Blocking at PR-time (a false-fail blocks a merge, not prod). Scope claim explicitly: "the *committed* profile is valid" — host-load is item 4's job (runner ≠ host: userns sysctl, no `soleur-bwrap` apparmor on the runner).
- **Profile→redeploy ordering (item 4).** In `apply-deploy-pipeline-fix.yml`, after the apply of `docker_seccomp_config` (+ `apparmor_bwrap_profile`), a **sequenced** step POSTs `/hooks/deploy` (reuses `ci-deploy.sh`'s health-gated, ADR-068-drained swap; `flock` dedupes the concurrent release deploy — idempotent), then asserts the running container's `seccomp_profile_sha256` (surfaced on `/hooks/deploy-status`) **equals** `sha256(committed profile)` and the canary passes; if not → `::error::` + `exit 1` + Sentry (fail-loud). No drift-poll/conditional-retrigger loop — the redeploy is unconditional after a profile-changing apply (which only fires when the profile actually changed).
- **Promote the canary to blocking** (soak-gated — see Follow-Through Enrollment).
- **AppArmor apply-parity:** add `apparmor_bwrap_profile` to the workflow's `-target=` set + `on.push.paths` + the co-target/paths coupling assertions.

## Technical Approach

### Implementation Phases

- **Phase 0 (spike, pre-PR):** the two determinations above.
- **PR1 (small):** `classifySandboxStartupError` (+ unit test with a **synthesized** seccomp-EPERM signal in the shape Phase-0 confirmed — deterministic, no LLM in the assertion path); broaden both catch sites (signature-gated on `sandboxKind !== "other"` — no `streamStartSent` gate per the CTO ruling); `issue-alerts.tf` frequency/affected-users alert; author **ADR-079** (status `adopting`).
- **PR2 (medium):** `sandbox-canary.mjs`; wire non-blocking into `ci-deploy.sh`; emit verdict to deploy-state; `cat-deploy-state.sh` surfaces it; follow-through enrollment.
- **PR3 (medium):** `ci.yml` SDK-bump job (package-lock detection + parity assertion + docker-run canary); `apply-deploy-pipeline-fix.yml` sequenced redeploy + `loaded==committed` assert + fail-loud + apparmor apply-parity; `cat-deploy-state.sh`/`ci-deploy.sh` `seccomp_profile_sha256` surface; new loaded-verification guard in the coupling test; promote canary to blocking; flip ADR-079 → `accepted`.

### Files to Edit / Create

**PR1:** create `apps/web-platform/server/sandbox-startup-classifier.ts`, `apps/web-platform/test/sandbox-startup-classifier.test.ts`, `knowledge-base/engineering/architecture/decisions/ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md`; edit `apps/web-platform/server/agent-runner.ts`, `apps/web-platform/server/cc-dispatcher.ts`, `apps/web-platform/server/observability.ts` (`userScopeFromExtra` — promote `userIdHash` → event `user.id` so the affected-users alert can count tenants), `apps/web-platform/infra/sentry/issue-alerts.tf`, `.github/workflows/apply-sentry-infra.yml` (add `sentry_issue_alert.sandbox_startup_failure` to the plan-step `-target=` set — an alert not in the target list ships in code but never applies; see learning 2026-06-12-detector-cron-must-route-its-own-self-failure-ops-and-register-new-sentry-alert-in-apply-target).

**PR2:** create `apps/web-platform/scripts/sandbox-canary.mjs`, `apps/web-platform/test/sandbox-canary.test.ts` (vitest, under `test/` so the config globs collect it — **not** `scripts/`), `scripts/followthroughs/canary-promotion-5875.sh`; edit `apps/web-platform/infra/ci-deploy.sh`, `apps/web-platform/infra/cat-deploy-state.sh`.

**PR3:** edit `.github/workflows/ci.yml`, `.github/workflows/apply-deploy-pipeline-fix.yml`, `apps/web-platform/infra/ci-deploy.sh`, `apps/web-platform/infra/cat-deploy-state.sh`, `apps/web-platform/infra/server.tf` (apparmor apply-parity), `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`, `ADR-079` (status flip).

### Attack Surface Enumeration (security boundary: seccomp + apparmor)

- **Sandbox-startup failure modes:** missing binary; seccomp `unshare` denial (the incident); apparmor mount-in-userns denial; kernel `apparmor_restrict_unprivileged_userns` sysctl drift (already guarded by `bwrap-userns-sysctl.service`, `server.tf:735` — out of scope, noted); resource exhaustion. The classifier's `sandboxKind` + raw stderr covers all.
- **Boundaries the faithful canary exercises:** it drives *real* bwrap, so it covers **both** `--security-opt seccomp=…` and `--security-opt apparmor=soleur-bwrap` — item-4 load-verification catches an apparmor regression for free; the apply-parity fold-in closes the auto-apply gap.
- **No relaxation:** this plan adds gates/observability; #5874's hardened rules are untouched.

## Alternative Approaches Considered

| Alternative | Verdict | Why |
|---|---|---|
| Hand-rolled `bwrap` argv canary | **Rejected** | Can't track the SDK; caused #5849 (false-green) and #4932 (false-rollback). |
| Item 4 self-healing verify (poll→detect-drift→conditional-retrigger→re-probe) | **Rejected as overbuilt** | A bespoke control loop to avoid one graceful, idempotent, ADR-068-drained redeploy. Straight sequenced apply→redeploy→assert is simpler and closes the same race. |
| Item 4 via shared GHA `concurrency:` group | **Rejected** | Serializes but doesn't *order*; different groups; folding in the deploy lock couples unrelated scopes. |
| Item 4 via `docker restart` | **Rejected** | Can't reload a `docker run`-time `--security-opt`; a raw stop/rm/run bypasses the canary swap + cron drain. |
| Custom distinct-tenant aggregate alert | **Rejected (YAGNI)** | Sentry's native frequency/affected-users threshold suffices; the only real requirement is not to add a global-key debounce. |
| 5-way boolean classifier taxonomy | **Rejected (YAGNI)** | `sandboxKind` enum + raw stderr discriminates the known shape; add booleans when an alert route needs one. |
| Detect SDK bump via `bun.lock` | **Rejected** | `package-lock.json` is deploy-authoritative (`npm ci`); key on it + parity-assert `bun.lock`. |
| AppArmor apply-parity as a deferred tracking issue | **Rejected** | Identical bug, ~3 lines, same incident class — fold into PR3. |
| Bundle observability with SDK-guard (issue's literal suggestion) | Adjusted | Observability ships first/alone; SDK-guard bundles with redeploy (both canary consumers). |

## User-Brand Impact

- **If this lands broken, the user experiences:** the prevention *failing* — a future SDK bump silently EPERMs the sandbox and every tenant's Concierge Bash tool fails with **no server-side signal** (the #5873 recurrence); **or** a flaky canary false-rolls-back every deploy (#4941); **or** the broadened classifier false-tags mid-conversation errors → alert fatigue masks real signal.
- **If this leaks, the user's workflow/identity is exposed via:** the sandbox-failure Sentry event carries tenant/workspace attribution (`userId`, `workspaceId`, `workspacePath`). Mitigation: reuse `userId → userIdHash` (auto at `observability.ts:217`); never emit raw `workspacePath`.
- **Brand-survival threshold:** `aggregate pattern` — a systemic **availability** failure across all tenants, no single-user data specificity (CTO concurred). No per-PR CPO sign-off; `user-impact-reviewer` does not fire.

## Observability

```yaml
liveness_signal:
  what: "faithful sandbox canary verdict per deploy (deploy-state JSON) + agent-sandbox:sdk-startup Sentry event stream"
  cadence: "per deploy (canary) + per sandbox-start attempt (runtime event)"
  alert_target: "Sentry issue alert (infra/sentry/issue-alerts.tf), native frequency/affected-users threshold → operator"
  configured_in: "apps/web-platform/infra/sentry/issue-alerts.tf ; ci-deploy.sh (canary verdict) ; cat-deploy-state.sh (/hooks/deploy-status)"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN"
  fail_loud: "agent-sandbox-tagged event on any sandbox-startup failure; apply-deploy-pipeline-fix.yml ::error:: + exit 1 if loaded profile != committed after redeploy"

failure_modes:
  - mode: "seccomp EPERM on split-unshare (the #5873 shape)"
    detection: "in-surface: classifySandboxStartupError emits agent-sandbox event with sandboxKind, errorCode, raw stderr, sdkVersion — from the failing runtime path"
    alert_route: "Sentry alert → operator; native affected-users threshold if ≥K tenants"
  - mode: "profile applied to host but not loaded by running container"
    detection: "post-apply assert seccomp_profile_sha256 (on /hooks/deploy-status) == sha256(committed) + canary pass — no SSH"
    alert_route: "apply-deploy-pipeline-fix.yml fail-loud + Sentry"
  - mode: "canary false-rollback / infra-vs-sandbox conflation"
    detection: "exit-code classification (125/126/127+ENOENT ⇒ canary_infra_error, non-blocking) vs bwrap Operation-not-permitted ⇒ sandbox_broken"
    alert_route: "deploy-state reason field + Sentry; faithful-FAIL+legacy-PASS disagreement paged"
  - mode: "unguarded SDK bump ships (lockfile drift)"
    detection: "ci.yml gate diffs package-lock.json resolved version (both packages) + bun.lock parity assert; runs faithful canary on committed profile"
    alert_route: "PR check red (blocking)"

logs:
  where: "Sentry (runtime events) ; /hooks/deploy-status JSON (canary verdict + loaded profile hash) ; GH Actions run logs"
  retention: "Sentry 90d ; deploy-state current-run ; GH Actions 90d"

discoverability_test:
  command: "curl -s https://deploy.soleur.ai/hooks/deploy-status | jq '{tag, seccomp_profile_sha256, sandbox_canary}'"
  expected_output: "sandbox_canary: \"pass\", seccomp_profile_sha256 == sha256(apps/web-platform/infra/seccomp-bwrap.json @ HEAD)"
```

**Affected-surface (2.9.2).** The bwrap sandbox is a blind surface. Each `detection` names an **in-surface** probe (the classifier emits *from* the failing runtime path; the canary runs *inside* the container via `docker exec`), and the event's structured fields (`sandboxKind` + `errorCode` + raw `stderr` + `sdkVersion`) discriminate the competing root-cause hypotheses in one event — satisfying `hr-observability-as-plan-quality-gate` and `observability-coverage-reviewer` §Step 4.6 (that reviewer runs at PR1 review — see Review agents).

## Infrastructure (IaC)

### Terraform changes
- **`server.tf` — no change** to `terraform_data.docker_seccomp_config` (684–741); the redeploy is a workflow step, not a TF resource.
- **AppArmor fold-in:** add `terraform_data.apparmor_bwrap_profile` to `apply-deploy-pipeline-fix.yml`'s `-target=` set + `on.push.paths` (+ `apparmor-soleur-bwrap.profile`).
- **No new `TF_VAR_*`.** The redeploy + assert step reuses `WEBHOOK_DEPLOY_SECRET`, `CF_ACCESS_CLIENT_ID/SECRET` from Doppler `prd_terraform`/`prd` — no no-default var, so no `hr-tf-variable-no-operator-mint-default` merge-abort risk.
- Host-script edits (`ci-deploy.sh`, `cat-deploy-state.sh`) ride the **existing** `deploy_pipeline_fix` delivery (both already in `TRIGGER_FILES`).

### Apply path
**Workflow-sequencing.** `terraform apply -target=…docker_seccomp_config,…apparmor_bwrap_profile` lands the files; a sequenced `if: success()` step POSTs `/hooks/deploy` and asserts `loaded==committed`, fail loud. **Downtime:** one graceful, canary-validated, ADR-068-drained, single-replica swap (ADR-027) — fires only when a profile actually changed (rare); `flock` makes the concurrent release deploy a no-op.

### Distinctness / drift safeguards
Fresh-host trap intact (`{ sha256, server_id }` untouched). No `lifecycle.ignore_changes`. The three existing coupling describes (#5505 paths, #5515 `depends_on`, #5873 co-target) stay green; the redeploy/apparmor changes update the #5505/#5873 assertions in lockstep and add a **new** loaded-verification guard (below).

### Vendor-tier reality check
**N/A** — Hetzner self-hosted single host via CF-Tunnel webhook; no managed-service tier gates any field.

## Architecture Decision (ADR / C4)

### ADR
Author **ADR-079 — "Faithful SDK sandbox canary + profile-apply→redeploy verification contract"** in PR1 (status `adopting`), flip to `accepted` in PR3. Records: (1) the canary drives the *real* SDK codepath (faithfulness invariant); (2) dark-launch-before-blocking (`wg-dark-launch-deploy-gates`); (3) the "applied ≠ loaded" coupling and the sequenced-redeploy-then-assert contract. Cross-refs ADR-031 (Sentry-as-IaC), ADR-068 (cron-drain), ADR-075 (sandbox config the canary imports), ADR-072 (adaptive deploy gate).

### C4 views
Enumeration checked against all three `.c4` files: no new external human actor, no new container/data-store (`hetzner = container "Compute"` already models the host), no changed access relationship. The **one** candidate is Sentry, absent from the external-systems block (`model.c4` ~L204–237) — but Sentry has been the error sink all along; this change does not *introduce* it, so its C4 absence is a **pre-existing doc gap**, not an impact of this plan. **Optional cleanup (not a PR1 merge gate):** add `sentry` (`#external`) + a `hetzner -> sentry` edge + view include; if done, run `c4-code-syntax.test.ts` + `c4-render.test.ts`. The architectural decision itself is recorded in ADR-079, satisfying `wg-architecture-decision-is-a-plan-deliverable`.

## Acceptance Criteria

### Phase 0 spike
- [ ] Recorded in #5875: the exact field a seccomp-EPERM surfaces in (`err.message` vs subprocess `.stderr`), and whether the sandbox can be probed without a model round-trip (or the scope-down decision).

### PR1 — observability
#### Pre-merge (PR)
- [ ] Given the real seccomp-EPERM signal shape (from Phase 0), `classifySandboxStartupError` returns `sandboxKind="seccomp_or_userns_denial"` with `errorCode`/`sdkVersion`; the emitted event carries `feature:"agent-sandbox"` + raw stderr. Test uses a **synthesized** signal in that shape (no LLM in the assertion path).
- [x] Both `cc-dispatcher.ts` and `agent-runner.ts` emit the tagged event on sandbox-startup failure. Tagging is by SIGNATURE (`sandboxKind !== "other"`), not stream phase (CTO ruling): a model/API error carrying no sandbox token is **not** tagged **even though `streamStartSent===true` at the catch**; a sandbox-shaped error IS tagged despite `streamStartSent===true` (regression pair: `agent-runner-sandbox-config.test.ts` positive+negative, `cc-dispatcher-real-factory.test.ts` T16).
- [x] `issue-alerts.tf` alert fires on the tagged event via a native affected-users threshold (`event_unique_user_frequency`, ≥3 tenants/1h); `reportSilentFallback` promotes `userIdHash`→`user.id` so the count is non-zero (unit-pinned in `observability.test.ts`); `terraform validate` passes; no global-key debounce is introduced on the sandbox-startup emit.
- [ ] Raw `userId`/`workspacePath` never reach Sentry (test asserts `userIdHash` present, raw absent).
- [ ] ADR-079 committed (`adopting`).

### PR2 — faithful canary
#### Pre-merge (PR)
- [x] `sandbox-canary.mjs` imports `agent-runner-sandbox-config.ts` (lazy, capture mode; does not re-specify options); test lives under `apps/web-platform/test/` and is collected by vitest (14 tests). **Mechanism = ADR-079 hybrid (capture-in-CI / replay-at-deploy); deploy-time runs in-container (host has no node).**
- [x] `ci-deploy.sh`: faithful canary runs **non-blocking** (`run_faithful_sandbox_canary`), legacy probe remains the gate; verdict written to deploy-state and surfaced on `/hooks/deploy-status` (`sandbox_canary`); Sentry event on faithful-FAIL; exit-code classification distinguishes `canary_infra_error` (125/126/127/ENOENT, non-blocking) from `sandbox_broken`.
- [x] Follow-through enrollment committed (script + sweeper secrets + soak accumulator). Directive/label enrolled on a **dedicated soak issue** Ref #5875 (not #5875 itself — sweeper closes-on-pass would prematurely close the umbrella before PR3).
#### Post-merge (automation)
- [ ] Follow-through sweeper promotes canary → blocking after **5 green non-blocking verdicts across ≥3 days of real deploys** (automated; see Enrollment).

### PR3 — SDK-bump guard + redeploy
#### Pre-merge (PR)
- [x] `ci.yml` (required `lockfile-sync` job) fires when the resolved version of `@anthropic-ai/claude-agent-sdk` or `@anthropic-ai/claude-code` changes in **`package-lock.json`**; a `bun.lock`↔`package-lock.json` parity mismatch for either package also fails the job (`apps/web-platform/scripts/sdk-bump-sandbox-gate.sh` + `.test.sh`, 7/7). (CTO ruling ADR-079 option (b): the merge-blocking gate is the DETERMINISTIC bump-detection + parity + `sdk-bump-verified:` ack — NOT a paid/non-deterministic model-turn `docker run --replay` on the uncaptured fixture. The creds-gated real-argv capture is **deferred** to a tracked follow-up; until then the bump gate's ack is the required maintainer attestation.)
- [x] Regression: `apps/web-platform/scripts/sandbox-canary-regression.test.sh` (+ synthesized `test-fixtures/sandbox-canary/seccomp-pre-5874.json` + a **distinct** `split-unshare-argv.json`) proves would-have-caught — a deterministic **structural** layer (always-on, blocking via the `test` shard: pre-5874 == committed minus the 2 #5874 rules) + a self-validating **docker-run bwrap** layer (opt-in from `infra-validation.yml`: EPERM under pre-5874, pass under committed; sysctl=0 on the ephemeral runner only).
- [x] `apply-deploy-pipeline-fix.yml`: sequenced (after the apply, `if: success()`) redeploy POST to `/hooks/deploy`, then assert `/hooks/deploy-status` `seccomp_profile_sha256 == sha256(committed)` + canary **not `sandbox_broken`**; `::error::`+`exit 1` if not. (CTO ruling ADR-079: dropped literal "canary pass" — the canary is still non-blocking dark-launch/`fixture_uncaptured`, so `pass`/`canary_infra_error`/`fixture_uncaptured` all pass-through; only a faithful `sandbox_broken` is fatal.)
- [x] `cat-deploy-state.sh` emits `seccomp_profile_sha256`; `ci-deploy.sh` records the loaded hash (`write_seccomp_profile_hash` at prod container start).
- [x] AppArmor apply-parity: `apparmor_bwrap_profile` added to the `-target=` set (plan+apply) + `on.push.paths`; the #5505 paths-union and #5873 co-target assertions updated accordingly (new `apparmor profile auto-apply parity (#5875)` describe); all three existing describes stay green. (AppArmor needs no redeploy — `apparmor_parser -r` at apply reloads the kernel profile for the running container; only seccomp is bound at `docker run`.)
- [x] **New** loaded-verification guard in `ship-deploy-pipeline-fix-gate.test.ts` asserts: a redeploy step ordered after the `terraform apply` step, and a `loaded==committed` assertion that fails loud.
- [ ] ~~Canary promoted to blocking~~ **DEFERRED (CTO ruling ADR-079).** The soak precondition (5 green verdicts / ≥3 days) is mechanically impossible until the deferred real-argv capture lands (see #5889 — the soak counter holds at 0 on `fixture_uncaptured`). Promotion stays owned by **#5889**; not in PR3.
- [ ] ~~ADR-079 flipped to `accepted`~~ **STAYS `adopting` (CTO ruling).** Flip only when BOTH deferrals land: real-capture wiring AND canary blocking-promotion (#5889). ADR-079 amended with an "Interim mechanism (PR3)" note + "Adopting→Accepted criteria".

### Non-Functional
- [x] CI SDK-bump gate runtime bounded — the blocking gate is deterministic bash (jq lockfile parse + `git` bump-detect + ack scan); NO model turn in the merge path (ADR-079 option (b)). The creds-gated model-turn capture is deferred (deferral B).
- [x] Extra redeploy fires only on an actual profile change — the redeploy step is conditional-by-construction (`loaded_seccomp == committed` → no-op skip), so a routine script/server.tf/apparmor-only apply does not swap prod.

### Review agents (run at review time — not ACs)
`observability-coverage-reviewer` at PR1; `security-sentinel` at PR3 (seccomp/apparmor boundary). `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` per PR; tests via the package runner (`vitest` for `apps/web-platform/test/**`; `bun test` for `plugins/soleur/test/*`).

## Test Scenarios

### Acceptance (RED targets)
- Given a synthesized seccomp-EPERM signal (Phase-0 shape), when the classifier runs, then `sandboxKind="seccomp_or_userns_denial"` and the emit carries `feature:"agent-sandbox"` + stderr + `sdkVersion`.
- Given a mid-conversation model/API error carrying no sandbox token (`sandboxKind="other"`), when caught in `agent-runner.ts` (with `streamStartSent=true`), then it is **not** tagged sandbox-startup; given a sandbox-shaped error at the same catch, it **is** tagged (tagging is by signature, not stream phase — CTO ruling).
- Given a `package-lock.json`-only bump of `@anthropic-ai/claude-agent-sdk`, when CI runs, then the SDK-bump gate fires and runs the canary; given a `bun.lock`/`package-lock.json` version mismatch, the gate fails.
- Given the seccomp profile applied but the container running the old profile, when the sequenced post-apply assert runs, then `loaded != committed` fails the run loud.

### Regression
- Given the #5849 split-unshare change against the synthesized pre-#5874 profile fixture, when the CI canary runs, then it FAILS (would-have-caught).
- Given a `docker exec` infra error (exit 125), when the host canary runs, then it records `canary_infra_error` and does **not** roll back (won't repeat #4941).

### Integration verification (`/soleur:qa`, no SSH)
- **API verify:** `curl -s https://deploy.soleur.ai/hooks/deploy-status | jq '.seccomp_profile_sha256'` expects `sha256(apps/web-platform/infra/seccomp-bwrap.json @ HEAD)`.
- **Sentry:** issues search `feature:agent-sandbox` returns the structured event on a forced dev failure.

## Hypotheses (network-outage gate — SSH apply path)

Item 4's auto-apply reaches the host via the existing CF-Tunnel SSH bridge; the redeploy is `/hooks/deploy` over CF-Access HTTPS. Per `hr-ssh-diagnosis-verify-firewall` (this is prevention, not live-outage diagnosis — opt-outs cite the reused, already-green path):

1. **L3 — CF-Tunnel reachability.** Apply uses the existing `cf-tunnel-ssh-bridge`, not a raw port-22 operator allowlist, so operator-egress-IP drift does not gate it. *Opt-out: verified — the same bridge already carries every `apply-deploy-pipeline-fix.yml` run green; no new ingress path.*
2. **L3 — DNS/routing.** `deploy.soleur.ai` via Cloudflare (unchanged). *Opt-out: reused surface.*
3. **L7 — webhook auth.** `/hooks/deploy` + `/hooks/deploy-status` are CF-Access + HMAC gated (unchanged). *Opt-out: reused.*
4. **L7 — application.** Redeploy observable via GH Actions logs + `/hooks/deploy-status` (no journald-only signal); verified by the discoverability_test.

## Domain Review

**Domains relevant:** Engineering.

### Engineering (CTO)
**Status:** reviewed.
**Assessment:** Full advisory obtained and incorporated. Confirmed: one payload / two contexts (docker-run committed vs docker-exec loaded); hand-rolled argv disqualified → SDK-driven probe with a no-model-turn AC; classify by error signature, not substring/timing (the plan's original `streamStartSent` phase gate was later **rejected at PR1 kickoff by a second CTO ruling** — ADR-079 — because `streamStartSent` is always true at the catch and the seccomp denial surfaces mid-stream; signature alone is the guard); emit per-user + native alert (not a global-key debounce); ordered apply→redeploy over a concurrency group; threshold `aggregate pattern`. New considerations folded in: AppArmor parity, lockfile-vs-manifest detection, blocking-canary reuses the existing rollback path, synthesized-stderr classifier test. **Capability gaps:** none.

**Product/UX Gate:** NONE — no UI surface (no `components/**`/`app/**/page.tsx`/`layout.tsx` in Files); mechanical override does not fire. **Operations:** assessed not-relevant (Soleur Operations = expense/vendor/provisioning, not SRE). **Legal:** event is pseudonymized; no regulated-data surface touched; threshold aggregate → `gdpr-gate` (2.7) skips; pseudonymization captured as an AC.

## Open Code-Review Overlap

5 open scope-outs touch planned files:
- **#3739** (extract `reportSilentFallbackWithUser` — collapse 11-site duplication) — touches `observability.ts`. **Fold-in candidate**: if PR1 adds a `withIsolationScope+setUser` site, extend/adopt the helper and `Closes #3739`; else **acknowledge** (the sandbox emit routes through `reportSilentFallback`/`mirrorWithDebounce`, which already hash userId — likely no 12th duplication).
- **#3243** (decompose `cc-dispatcher.ts`) — **acknowledge**: keep PR1's catch-site addition minimal so it doesn't worsen the decompose debt.
- **#3242** (tool_use WS raw-name), **#2197** (billing/`server.tf`) — **acknowledge**: unrelated.
- **#3216** (resolved inline) — **no action**.

## Follow-Through Enrollment (canary dark→blocking soak)

The canary promotion is a soak-gated close criterion. Enrolled so it's automated, not memory:
- **Script:** `scripts/followthroughs/canary-promotion-5875.sh` — exit 0 when the last **5** `/hooks/deploy-status` canary verdicts (over ≥3 days) are `pass` with `start=` pinned strictly after PR2's deploy; mirrors `reconcile-ff-only-sentry-4977.sh`.
- **Tracker directive:** `<!-- soleur:followthrough script=scripts/followthroughs/canary-promotion-5875.sh earliest=<PR2-deploy+3d> secrets=WEBHOOK_DEPLOY_SECRET,CF_ACCESS_CLIENT_ID,CF_ACCESS_CLIENT_SECRET -->` + `follow-through` label on #5875.
- **Sweeper wiring:** add any new `secrets=` to `.github/workflows/scheduled-followthrough-sweeper.yml`.

## Success Metrics
- A synthetic replay of the #5849 change fails the CI SDK-bump gate (would-have-caught).
- The next real SDK bump runs the canary; any regression is red pre-merge.
- A forced sandbox-startup failure produces a filterable `feature:agent-sandbox` Sentry event within seconds (MTTR "invisible" → "one event").
- Zero false-rollbacks attributable to the canary during/after dark-launch.

## Dependencies & Risks
1. **[HIGH] Canary faithfulness drift** — import `agent-runner-sandbox-config.ts` + no-model-turn AC.
2. **[HIGH] Phase-0 error-shape unknown** — the classifier is false-green-prone if built against the wrong field; the spike resolves it before PR1 freezes the design.
3. **[MED] Observability false-tag** — signature-based classifier (`sandboxKind !== "other"`) is the sole mis-tag guard; a bare EPERM with no namespace token must stay `"other"` (unit-pinned). The `streamStartSent` gate was rejected (CTO ruling, ADR-079) as a silent-no-op false-NEGATIVE.
4. **[MED] Lockfile source-of-truth** — key on `package-lock.json` (deploy-authoritative) + `bun.lock` parity assertion.
5. **[MED] Ordering illusion** — sequenced apply→redeploy (not a concurrency group); `flock` dedupes the concurrent release.
6. **[LOW] CI-vs-host faithfulness divergence** — CI gate claims only "committed profile valid"; host-load is item 4.

## References & Research
- Incident/PIR: `knowledge-base/engineering/operations/post-mortems/2026-07-01-concierge-bwrap-seccomp-sdk-0-3-outage-postmortem.md`; #5873/#5874/#5849/#5875.
- Dark-launch / false-rollback: `knowledge-base/project/learnings/2026-06-04-cron-silence-was-bwrap-userns-drift-not-turn-budget.md` (#4932→#4941); `wg-dark-launch-deploy-gates`.
- Blind-surface probe: `knowledge-base/project/learnings/best-practices/2026-07-01-blind-surface-needs-structured-probe-before-nth-fix.md`; `hr-observability-as-plan-quality-gate`.
- Canary bash traps: `knowledge-base/project/learnings/2026-04-29-canary-layer3-mount-and-pipefail-traps.md`.
- Seccomp/bwrap prior art: `knowledge-base/project/learnings/security-issues/docker-seccomp-blocks-bwrap-sandbox-20260405.md`; `.../bwrap-sandbox-three-layer-docker-fix-20260405.md`.
- Lockfile trap: #5866; `knowledge-base/project/learnings/workflow-patterns/2026-06-11-model-launch-review-skill-build-premise-corrections.md`.
- Deterministic LLM-SDK tests: `knowledge-base/project/learnings/best-practices/2026-04-19-llm-sdk-security-tests-need-deterministic-invocation.md`.
- Code anchors: `ci-deploy.sh:647,782-794,865-884`; `server.tf:684,747,735`; `Dockerfile:4-5,127-128`; `apply-deploy-pipeline-fix.yml:128,239-256`; `web-platform-release.yml:422`; `cc-dispatcher.ts:2694,2722`; `agent-runner.ts:2476,2649,2662,980,2107`; `agent-runner-sandbox-config.ts:172-223`; `observability.ts:37-39,217,489,574`; `abort-classifier.ts:54-88`; `vitest.config.ts:44,64`; `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts:345,413,511`.
- ADRs: ADR-031, ADR-068, ADR-072, ADR-075, ADR-027.

## Sharp Edges
- The `## User-Brand Impact` threshold is set (`aggregate pattern`) — do not leave it empty or it fails `deepen-plan` Phase 4.6.
- Do **not** wire the faithful canary to gate/rollback until it has dark-launched to proven-green (the #4932→#4941 lesson).
- The redeploy MUST route through `/hooks/deploy` (ci-deploy.sh swap) to inherit the ADR-068 cron drain; a raw `docker restart` can't reload a `docker run`-time `--security-opt` anyway.
- The SDK-bump gate keys on **`package-lock.json`** (deploy-authoritative via `npm ci`), not `bun.lock`; assert the two lockfiles agree so neither can drift the gate.
- Build the classifier against the **real** error field (Phase-0 spike), not an assumed one — a synthesized fixture in the wrong shape passes green while missing the production signal.
