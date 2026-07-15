---
title: "fix(infra): zot gate login_failed — the boot-baked htpasswd cannot survive a credential rotation"
date: 2026-07-15
type: bug
lane: single-domain
branch: feat-one-shot-zot-gate-login-failed
sentry_issue: WEB-PLATFORM-5B
related_issues: [6122, 6416, 6421, 6424, 6452]
related_adrs: [ADR-096, ADR-115]
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# fix(infra): zot gate `login_failed` — the boot-baked htpasswd cannot survive a credential rotation

## Enhancement Summary

**Deepened on:** 2026-07-15
**Gates run:** 4.5 (network-outage, fired), 4.55 (downtime/cutover, **fired — HALT resolved**), 4.6 (user-brand,
pass), 4.7 (observability, pass), 4.8 (PAT-shaped, pass), 4.9 (UI wireframe, N/A)
**Passes run:** verify-the-negative (6 claims), precedent-diff §4.4 (4 patterns)

### Key improvements from the deepen pass

1. **Added `## Downtime & Cutover`** (Phase 4.55 halt — the plan replaces `hcloud_server.registry` and had no
   zero-downtime evaluation). Two zero-downtime paths evaluated and explicitly rejected with reasons; residual
   window accepted on the evidence that **no serving surface is affected** (E2).
2. **Mechanical proof of the root cause found.** The `templatefile()` call at `zot-registry.tf:248-279` passes
   only the two non-secret usernames and zero references to `random_password.*.result` — so Terraform has **no
   data edge** from the password to the host and cannot know the bake is stale. This upgrades the root cause
   from "strongly inferred" to "structurally proven".
3. **Caught a self-inflicted trap in the fix itself.** The precedent classifier the plan tells the implementer
   to mirror (`_pull_result_is_auth_denied`) buckets `unauthorized|denied|forbidden` together — copying it
   verbatim would collapse H3 (401) and H4 (403) into one bucket, reintroducing the exact ambiguity being
   fixed. Added task 1.2b + a Phase 3 test case.
4. **`replace_triggered_by` confirmed safe.** `random_password` has no `keepers` (zero grep hits) → it will not
   fire on a routine apply.
5. **`htpasswd -vb` semantics verified live** (exit 0/3, token never printed) rather than asserted from memory.

### What post-implementation review changed (2026-07-15, PR #6484)

Multi-agent review found **three P1s the plan, the deepen pass, and a green suite all missed** — two of them
defects the implementation introduced, one a latent data-loss hazard the ADR amendment would have *mandated*.
Recorded here because each is a reusable lesson, not a one-off:

1. **The probe killed the telemetry line it rode on.** `zot-disk-heartbeat.sh` runs `set -u`; the first draft
   expanded `"$ZOT_PULL_TOKEN"` bare, so an unset token raised `unbound variable` and **exited the script
   before `$LINE` was built** — taking the entire `SOLEUR_ZOT_DISK` self-report dark (disk, OOM, boot_id,
   everything) and bypassing the trailing `exit 0` that exists so the cron can never wedge. `|| HTP_PULL=false`
   does not rescue an expansion error. The `unknown` guards written for exactly that case sat eight lines too
   late — dead code. Since heartbeat *absence* is itself an alarm, it would have paged "host down" when only
   the probe broke. **Lesson:** a guard against a fail-mode must be a *precondition*, never a post-hoc
   correction; and an observability probe must fail safe on its own instrument.
2. **H4 was never a live hypothesis, and the classifier arm defending it was net-harmful.** Running the pinned
   zot digest with this repo's exact `accessControl` showed `docker login` (`GET /v2/`) answers 200-or-401 and
   **never 403** — a policy-less user still gets `Login Succeeded`; authz lives at the manifest endpoint. So
   the plan's whole H3-vs-H4 apparatus was a false dichotomy derived from *reading zot's config* instead of
   *measuring zot*. Worse, the `authz_denied` arm's bare `denied` had zero true positives here and stole
   `connect: permission denied` (a SOCKET error) from `transport` — while the arm that will actually fire most
   on this fleet (private-NIC → `network is unreachable`; zot OOM → `connection reset`) fell through to
   `unclassified`, the very bucket #6483 exists to drain. **Lesson:** a hypothesis about a vendored service's
   response codes is a claim to measure against the pinned image; one `docker run` settled it.
3. **The ADR amendment mandated a landmine on git-data.** Written as a class-wide MUST inside an ADR whose
   Status says "registry host only", it would have required `replace_triggered_by = [random_password.
   git_data_luks]` — replacing the host on a passphrase rotation and `luksOpen`-ing the NEW key against volumes
   encrypted with the OLD one, permanently bricking the fleet's most irreplaceable data. The first draft's own
   comment ("Mirrors `random_password.git_data_luks`") pointed straight at it, and the existing first blocker
   does not reach the replace primitive. Fixed by scoping the MUST + adding a SECOND normative blocker.
   **Lesson:** when generalizing a rule, the blast radius generalizes too — and the sibling the code already
   names as analogous is the first place to check.

4. **The drift guards did not pin what their names claimed — and only mutation testing found it.** The suite was
   green; three of the guards were vacuous:
   - **Block-scoped, not attribute-scoped.** Each assertion grepped the whole ~90-line `hcloud_server.registry`
     block, so it only proved a token appeared *somewhere in the resource*. Moving `random_password.zot_pull`
     from `replace_triggered_by` into `depends_on` — a plausible tidy-up — left the suite **22/22 green** while
     the assertion literally named *"replace_triggered_by names random_password.zot_pull"* was **false**, and
     rotating the pull token (the exact WEB-PLATFORM-5B credential) no longer replaced the host. **The bug this
     file exists to guard, fully reintroduced, under a green guard.** Fixed by extracting each attribute's list
     body and matching within it.
   - **The comment strip was full-line only.** Its own comment claimed "the guard can never pass on explanatory
     prose". With zero `lifecycle`/`depends_on` and the tokens named in *trailing* comments, the suite was
     **22/22 green**. `zot-registry.tf` uses trailing comments, so the idiom is live in the guarded file. Fixed
     with `sed 's/[[:space:]]#.*$//'`; the mutation now yields 8 failures.
   - **A key-presence grep standing in for a value assertion.** `grep '"host_id":'` matches `"host_id":""`
     because jq always emits the key — attribution could be gutted entirely and the test stayed green. The
     #6396 precedent it claimed to reuse asserts a non-empty value *and carries a comment warning about this
     exact vacuity*. The lesson was cited and not applied.
   **Lesson:** a green guard proves nothing about the guard. Mutate the defect back in and watch it go RED —
   for the drift class specifically, mutate a SIBLING attribute in, not just the anchor out.

Also corrected: a stale `>/dev/null 2>&1 so no trace/secret leaks` comment this PR falsified (the same
false-comment class the PR exists to fix), the probe collapsing `rc=6` (user renamed) into a confident "credential
diverged", an `alert_route` citing a Sentry poller for a Better Stack field, and the line citations this PR's own
insertions staled.

**The through-line across all four:** every one was a *claim* that a green signal appeared to support — a
comment claiming an edge, a hypothesis claiming a response code, an ADR claiming a scope, a test claiming an
invariant. The plan's own thesis ("a comment that documents a guarantee the code does not provide is what let
this ship") turned out to describe the plan, the implementation, and the tests as much as the original bug.

### New considerations discovered

- The `depends_on` gap is a literal single-element list at `:289` — confirmed, not a strawman.
- `hcloud_server.registry` has **no** `provisioner`/`connection` block, so this apply carries no hard SSH
  dependency (the network-outage resource-shape trigger does not fire for this change set).

## Overview

Sentry `WEB-PLATFORM-5B` — `zot gate degraded (login_failed) — configured but inactive, using GHCR` — fires on
every deploy. The emitter is `zot_gate_and_login()` at `apps/web-platform/infra/ci-deploy.sh:808`: it resolves
`ZOT_PULL_USER`/`ZOT_PULL_TOKEN` from Doppler `soleur/prd`, runs `docker login "$ZOT_REGISTRY_URL"`, and on
failure calls `zot_gate_degraded_event login_failed` and falls through to the unchanged GHCR path.

**This is not a credential regression and not Doppler drift. It is a credential-lifecycle defect: the registry
host's `/etc/zot/htpasswd` is baked once at boot and no Terraform edge or convergence loop ever rebuilds it.**
When `random_password.zot_pull` is rotated, both Doppler copies update and the host's htpasswd does not — so
every client that presents the new token is rejected forever, with no signal that says why.

The telemetry below was self-pulled (`hr-no-dashboard-eyeball-pull-data-yourself`); no step in this plan asks a
human to fetch a log, open a dashboard, or run a probe.

### Evidence (self-pulled 2026-07-15)

| # | Fact | Layer / how pulled |
|---|------|--------------------|
| E1 | `WEB-PLATFORM-5B`, 14 events, first `2026-07-14T21:11:28Z`, last `2026-07-15T15:10:07Z`, **100% `zot_gate_reason=login_failed`** | Sentry EU `GET /api/0/organizations/jikigai-eu/issues/?query=registry:zot-gate-degraded` |
| E2 | **zot has NEVER served a successful pull in 90d** — zero `registry:zot` AND zero `registry:ghcr-fallback` issues | Sentry, 90d query |
| E3 | zot is **running and reachable and receives the login**: `zot_last_err` carries a zot `session.go:137` HTTP-API access log with `User-Agent: docker/29.6.1` at `2026-07-15T14:31:01.559Z` — the exact second of an E1 event | Better Stack `SOLEUR_ZOT_DISK` self-report |
| E4 | `crane/0.20.2` (14:59:48Z) and `cosign/v3.1.1` (15:00:46Z) authenticate to zot in the same window, `Authorization:[******]` present | Better Stack `SOLEUR_ZOT_DISK` `zot_last_err` |
| E5 | **All three credential planes agree**: tfstate `random_password.zot_pull.result` == Doppler `soleur/prd` == Doppler `soleur-registry/prd` (sha256 `922cf93d…`, len 40). Push tokens likewise agree (`46edcc9f…`) | R2 tfstate + `doppler secrets get` (hashes only, values never printed) |
| E6 | Registry host `soleur-registry` **created `2026-07-14T16:42:24Z`**, `status=running`, `private_net 10.0.1.30` — 4.5 h before the first `login_failed` | Hetzner API `GET /v1/servers?name=soleur-registry` |
| E7 | `zot_restarts=0`, `state_status=running`, `pcent=16`, `oom_kills_5m=0` — the host is healthy; this is not the #6288 restart-loop or the #6284 disk-full class | Better Stack `SOLEUR_ZOT_DISK` |
| E8 | Both web hosts DO have `insecure-registries: ["10.0.1.30:5000"]` — fresh hosts via `cloud-init.yml:438-445`, `web-1` via `terraform_data.registry_insecure_config` | code read; corroborated by E3 (a well-formed HTTP request reached zot) |

### Root cause

`E4` is the discriminator. The **push** credential (`zot-push`) authenticates against the same
`/etc/zot/htpasswd` in the same window that the **pull** credential (`zot-pull`) is rejected. A wholesale-stale
or missing htpasswd would break both. One entry is current and the other is not — which is exactly the shape
produced by rotating **one** of the two passwords.

`zot-registry.tf:78-80` claims:

> `NO ignore_changes anywhere downstream (TF owns the values) → rotation via `terraform apply -replace=random_password.zot_pull` re-propagates htpasswd + Doppler in ONE apply.`

**That claim is false, and it is the bug.** Verified by `grep -n "replace_triggered_by" apps/web-platform/infra/zot-registry.tf` → **zero hits**, and `hcloud_server.registry`'s `user_data` never references `random_password.zot_pull` (it passes only `doppler_token`, `zot_pull_user`, `zot_push_user`, `zot_image`, `doppler_arch`, `doppler_sha256`, `betterstack_logs_ingest_url` — the token *values* are deliberately kept out of user_data). So:

- Replacing `random_password.zot_pull` updates `doppler_secret.zot_pull_token` + `doppler_secret.zot_pull_token_registry` (consistent with E5).
- It does **not** replace `hcloud_server.registry`, and nothing else rebuilds `/etc/zot/htpasswd` — the file is written exactly once, in the `runcmd` heredoc at `cloud-init-registry.yml:583-585`.
- The htpasswd `zot-pull` entry therefore pins the pre-rotation value while every client presents the post-rotation one → permanent `login_failed`, and `ZOT_ACTIVE` never becomes 1 (E2).

The same missing-edge class has a second live instance: `hcloud_server.registry` declares
`depends_on = [doppler_secret.registry_betterstack_logs_token]` (`zot-registry.tf:290`) — added by #6244 for
exactly this reason — but **omits `doppler_secret.zot_pull_token_registry` and `doppler_secret.zot_push_token_registry`**.
The host reads those two at boot through the Doppler CLI, so Terraform sees no implicit dependency and is free to
create/boot the server concurrently with (or before) the secret writes. On a fresh stand-up that races the
htpasswd bake against the token write. The `depends_on` fix was made once and never generalized to the two
secrets that actually gate the bake.

### Why this hid for so long

The one datum that decides this — zot's HTTP status and auth reason for the pull login — is destroyed at the
source: `ci-deploy.sh:808` runs `docker login … >/dev/null 2>&1`, so `login_failed` is a single undifferentiated
bucket for *bad credential*, *authz denial*, *transport*, and *timeout*. The beacon carries no `host_id`, and the
registry host is deny-all/no-SSH so zot's own auth log is not shipped. #6452, #6424 and #6421 are already three
consecutive fixes in this area; a fourth blind fix would repeat the exact pattern named in
`knowledge-base/project/learnings/best-practices/2026-07-01-blind-surface-needs-structured-probe-before-nth-fix.md`.
Phase 1 therefore ships the discriminating probe **first**, in the same PR as the fix, so the fix is confirmed by
telemetry rather than asserted.

## Research Reconciliation — Spec vs. Codebase

| Claim (from the issue framing) | Reality (verified) | Plan response |
|---|---|---|
| "credential/auth regression" | No regression — zot never served a single pull in 90d (E2). Nothing degraded; it never worked. | Reframe as a first-activation + rotation-lifecycle defect. |
| "configuration drift" | The Doppler↔tfstate planes are **not** drifted (E5). The drift is host-state (htpasswd) vs control-plane, which no drift detector covers. | Fix the missing convergence edge; add the htpasswd-match probe as the drift detector. |
| "gap in the gate's activation logic" | Closest to correct, but the gate's *logic* is sound — it correctly declines to activate. The gap is that the failure is **undiagnosable** and the credential can silently diverge. | Phases 1-3. |
| Related PR #6452 (fallback-signal counting) | Merged; counts the four fallback signals in the soak gate. Unrelated to the login itself. | No change. |
| Related PR #6424 (alarm threshold) | Merged; the alarm can now fire. It fires correctly today — 5B is the proof. | No change. |
| Related PR #6421 / ADR-114 (silently-skipped mirror) | Merged; un-masks the mirror skip. `#6416` (web-2 private-net) still OPEN — the mirror is only now backfilling (E4 crane push). | Note the interaction: even with login fixed, zot must hold the image to serve a pull. AC covers both. |

## Hypotheses (ordered L3 → L7, per the network-outage checklist)

Reachability was established **before** any auth hypothesis, per `hr-ssh-diagnosis-verify-firewall`:

| # | Hypothesis | Status |
|---|---|---|
| H0 | Firewall / private-net route to `10.0.1.30:5000` | **Excluded** — E3: zot logs a well-formed HTTP request from the deploying host's docker at the exact failing second. The `/v2/` probe also passes (the gate reached the login branch at all). |
| H1 | `insecure-registries` missing → docker attempts HTTPS | **Excluded** — E8 + E3 (an HTTPS ClientHello to an HTTP port does not produce a clean access log with a `docker/29.6.1` User-Agent). |
| H2 | Doppler / tfstate credential drift | **Excluded** — E5, all three planes agree. |
| H3 | **htpasswd `zot-pull` entry stale vs the rotated token** | **THE hypothesis** — uniquely explains E2+E4+E5 together. Confirmed structurally by the absent `replace_triggered_by`. Now the ONLY hypothesis this call site can discriminate (H4 is falsified below). |
| H4 | zot `accessControl` denies `zot-pull` at `/v2/` (403 authz, not 401 authn) | **FALSIFIED at /work — not observable here at all.** ~~Live, lower.~~ |

**H4 is dead, and the plan's "H3 vs H4" framing was a false dichotomy.** Measured at /work against the pinned
zot (v2.1.2, the `zot-registry.tf:55` digest) with this repo's exact `accessControl`: `docker login` issues
exactly one request — `GET /v2/` — and zot answers it **200 or 401, never 403**. A user with **zero**
accessControl policies still gets `Login Succeeded`; zot enforces authz at `/v2/<repo>/manifests/<tag>`
(measured: 403), which the login path never touches. So a broken accessControl does not produce `login_failed`
at all — login SUCCEEDS, `ZOT_ACTIVE=1`, and the failure surfaces later at pull time under a different signal.

Two things follow, both applied:

- **Phase 2b is struck** (see below) — it was gated on a verdict (`zot_login_http=403`) the probe cannot emit.
- **The classifier's `authz_denied` arm was net-harmful as originally written.** Matching bare
  `denied`/`forbidden` gave it zero true positives here and one real false positive:
  `connect: permission denied` is a SOCKET error (EACCES), which it stole from `transport`. It now matches a
  literal `403` only, as a defensive tripwire.

**Why this matters beyond H4:** the plan reasoned about zot's authz from its config file rather than from zot's
behavior. `accessControl` *looks* like it gates `/v2/` — the config says `"**": { policies: [...],
defaultPolicy: [] }` — and it does not. A hypothesis about a vendored service's response codes is a claim to
measure against the pinned image, not to derive from its config. One `docker run` of the pinned digest settled
what the whole H3/H4 apparatus was built to decide.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — the GHCR fallback is atomic and hosts keep
booting the correct signed digest. The harm is latent and identical to the #6421 postmortem's: the redundancy
ADR-096 exists to provide **does not exist**, and the fleet reports green. If GHCR degraded — the exact scenario
zot was built to survive — every host would fail to pull and the platform would not deploy or recover.

**If this leaks, the user's data/workflow is exposed via:** no new exposure. The probe added in Phase 1 emits a
**boolean** match result and an HTTP status code — never a token, never a hash of a token. `docker login` stderr
is classified to a fixed enum before it reaches Sentry, so a credential can never ride out in an error string.

- **Brand-survival threshold:** `aggregate pattern` — no single-user incident is reachable from this path (the
  fallback holds); the risk is fleet-wide loss of registry redundancy. Operator-confirmed at /go routing time.

## Implementation Phases

### Phase 1 — Make the failure discriminating (ships FIRST, same PR)

Per `plan` §2.9.2, the probe must discriminate **all** competing hypotheses in **one** event.

1. **`apps/web-platform/infra/ci-deploy.sh` — capture and classify the login failure.**
   Replace the discard at `:808`. Capture stderr to a temp file, and classify the **content** into a fixed enum
   (mirroring the existing `_pull_result_is_auth_denied` precedent at `:838`, which already classifies stderr
   content rather than a path):
   - `authn_rejected` — `401` / `unauthorized` / `incorrect username or password`
   - `authz_denied` — `403` / `denied` / `access to the resource is denied`
   - `tls_mismatch` — `server gave HTTP response to HTTPS client` (proves an `insecure-registries` gap)
   - `transport` — `connection refused` / `no route to host` / `context deadline exceeded` / `i/o timeout`
   - `unclassified` — anything else
   Add `zot_login_class` + `zot_login_http` (the status code, scraped from stderr when present) to
   `zot_gate_degraded_event`'s `tags`. **Never** put raw stderr in the payload — classify first (a registry error
   string can echo a username; the enum is the only thing that crosses the boundary).
2. **`ci-deploy.sh` — add `host_id` to `zot_gate_degraded_event`.** The beacon currently has no host attribution
   (verified: the 14 events carry only `feature`/`op`/`registry`/`zot_gate_reason`/`level`/`logger`), so
   "which host" is unanswerable. Reuse the `host_id` tag precedent added to `pull_failure_event` by #6396/#6401.
3. **`apps/web-platform/infra/cloud-init-registry.yml` — the in-surface htpasswd-match probe.** This is the
   decisive, no-SSH discriminator for H3 on a deny-all host. In `zot-disk-heartbeat.sh` (already running under
   `doppler run --project soleur-registry --config prd`, so both tokens are already in scope), add:

   ```sh
   # htpasswd_pull_matches / htpasswd_push_matches: does the BOOT-BAKED htpasswd still match the
   # CURRENT Doppler token? `htpasswd -vb` verifies a password against a file and NEVER prints the
   # token — it emits only a fixed status line ("Password for user X correct." / "password
   # verification failed"), which we discard. exit 0 = match, exit 3 = mismatch (verified live
   # 2026-07-15 against httpd:alpine; see Research Insights). Emits a BOOLEAN only.
   htpasswd -vb /etc/zot/htpasswd "${zot_pull_user}" "$ZOT_PULL_TOKEN" >/dev/null 2>&1 \
     && HTP_PULL=true || HTP_PULL=false
   htpasswd -vb /etc/zot/htpasswd "${zot_push_user}" "$ZOT_PUSH_TOKEN" >/dev/null 2>&1 \
     && HTP_PUSH=true || HTP_PUSH=false
   ```

   Append `htpasswd_pull_matches=$HTP_PULL htpasswd_push_matches=$HTP_PUSH` to the existing `SOLEUR_ZOT_DISK`
   line. Expected verdict if H3 holds: `htpasswd_pull_matches=false htpasswd_push_matches=true` — which is the
   E4 asymmetry, proven from inside the host.
   *Precondition (verified at plan time):* `apache2-utils` is already in `packages:`
   (`cloud-init-registry.yml:18`), so `htpasswd` is on the host. `-v` semantics confirmed live (exit 0 match /
   exit 3 mismatch, token never printed) — re-confirm against the shipped Ubuntu 24.04 build at /work, since the
   live check ran against `httpd:alpine`, not the host image.

### Phase 2 — Close the credential-convergence gap (the H3 fix)

1. **`apps/web-platform/infra/zot-registry.tf` — force the bake to follow the token.** Add to
   `hcloud_server.registry`:

   ```hcl
   lifecycle {
     replace_triggered_by = [
       random_password.zot_pull,
       random_password.zot_push,
     ]
   }
   ```

   This makes the comment at `:78-80` true: rotating either password now replaces the host, which rebuilds the
   htpasswd from the new value in the same apply. Per `hr-prod-host-config-change-immutable-redeploy`, immutable
   redeploy is the sanctioned path for a prod host config change.
2. **`zot-registry.tf` — complete the `depends_on`.** Extend `:290` to:

   ```hcl
   depends_on = [
     doppler_secret.registry_betterstack_logs_token,
     doppler_secret.zot_pull_token_registry,
     doppler_secret.zot_push_token_registry,
   ]
   ```

   Same reasoning the betterstack entry already documents at `:60-64`; the two secrets that gate the htpasswd
   bake were simply never added. Without this, a fresh stand-up races the bake against the token write.
3. **`zot-registry.tf:78-80` — correct the false comment.** State what is actually true: the values live only in
   Doppler and are baked into the htpasswd at boot, so rotation is only safe because `replace_triggered_by`
   forces the redeploy. A comment that documents a guarantee the code does not provide is what let this ship.

### Phase 2b — H4 arm — **STRUCK at /work (the hypothesis is falsified, not merely unlikely)**

This phase said: if the probe returns `zot_login_http=403` + `zot_login_class=authz_denied` while
`htpasswd_pull_matches=true`, then H3 is refuted and the defect is zot's `accessControl`
(`cloud-init-registry.yml:116-126`) rejecting `zot-pull` at the `/v2/` base route.

**That verdict can never arrive.** Measured at /work against the pinned zot image (v2.1.2, the digest at
`zot-registry.tf:55`) running this repo's exact `accessControl` block:

| request | credential | status |
|---|---|---|
| `GET /v2/` (**the only request `docker login` makes**) | anonymous | 401 |
| `GET /v2/` | valid, `read` policy | 200 |
| `GET /v2/` | valid, **zero accessControl policy** | **200** |
| `GET /v2/` | valid user, wrong password | 401 |
| `/v2/<repo>/manifests/<tag>` | valid, zero policy | **403** |

zot does **not** apply `accessControl` to the `/v2/` base route — it enforces at the manifest endpoint. So the
login path answers 200-or-401 and 403 is unreachable there. Two consequences the plan had backwards:

1. **H4 was never a live hypothesis for this defect.** A broken `accessControl` does not produce
   `login_failed` at all: the login SUCCEEDS, `ZOT_ACTIVE=1`, and the failure appears later at pull time as a
   different signal. The probe was at the wrong layer to see it, so "H3 vs H4, decided by the probe" was a false
   dichotomy — H3 was the only hypothesis the login path can discriminate.
2. **The classifier's `authz_denied` arm was net-harmful as written.** Matching bare `denied`/`forbidden` gave
   it zero true positives on this path and a real false positive: `connect: permission denied` is a SOCKET error
   (ICMP admin-prohibited → EACCES), which it stole from `transport` — pointing the operator at an accessControl
   bug that cannot exist. The arm now matches a literal `403` only, purely as a tripwire.

If a zot accessControl defect is ever suspected, the observable is `zot-entry-gate.sh`'s manifest probe (which
currently folds a 403 into "tag does not resolve"), not this gate. Phase 2's `replace_triggered_by` +
`depends_on` ship regardless, exactly as the plan said — they are proven latent defects, and their justification
never depended on the H3/H4 outcome.

### Phase 3 — Regression tests

`apps/web-platform/infra/ci-deploy.test.sh` (the existing harness; it already asserts the `relogin_failed` /
`zot_gate_degraded` shapes at `:3341-3345`):

1. Each stderr fixture maps to its `zot_login_class` (5 cases, one per enum member).
2. A `tls_mismatch` stderr does **not** classify as `authn_rejected` — the enum's discriminating power is the
   whole point; a collapse to one bucket is the bug being fixed.
3. `zot_gate_degraded_event` payload carries `host_id`, `zot_login_class`, `zot_login_http`.
4. **Stderr never reaches the payload** — assert the raw fixture string is absent from the captured POST body.
5. `apps/web-platform/infra/registry-insecure-config.test.sh` (existing): assert `replace_triggered_by` names
   both `random_password.zot_pull` and `random_password.zot_push`, and that `depends_on` names all three secrets.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** `grep -c 'replace_triggered_by' apps/web-platform/infra/zot-registry.tf` ≥ 1, and the block names both
  `random_password.zot_pull` and `random_password.zot_push`.
- **AC2** `hcloud_server.registry`'s `depends_on` names all three of
  `doppler_secret.{registry_betterstack_logs_token,zot_pull_token_registry,zot_push_token_registry}`.
- **AC3** `grep -c 're-propagates htpasswd + Doppler in ONE apply' apps/web-platform/infra/zot-registry.tf` == 0
  (the false claim is gone). *Absence-grep is safe here: verified 2026-07-15 that this phrase occurs exactly once
  in the repo, at `zot-registry.tf:79`, and the replacement prose must not restate it.*
- **AC4** The `docker login` invocation in `zot_gate_and_login` no longer discards stderr — stderr is redirected
  to a capture file, not to `/dev/null`.
- **AC5** `bash apps/web-platform/infra/ci-deploy.test.sh` passes, including the 5 new classification cases and
  the "stderr never reaches the payload" assertion.
- **AC6** `bash apps/web-platform/infra/registry-insecure-config.test.sh` passes.
- **AC7** `terraform validate` passes in `apps/web-platform/infra/` (the `lifecycle` block is config-phase
  validated — see Sharp Edges).
- **AC8** `terraform plan` shows **exactly one** resource to replace (`hcloud_server.registry`) and **no**
  create/destroy of any other `-target`-excluded resource. Run with the canonical triplet (see §Infrastructure).
- **AC9** ADR-115 amended (see §Architecture Decision); `knowledge-base/engineering/architecture/decisions/ADR-115-dedicated-host-private-nic-boot-convergence.md` contains the credential-convergence extension.

### Post-apply (fully automated — no human step)

> **Renamed from "Post-merge" at /work.** Merging applies nothing here (see §Infrastructure → Apply path);
> these gates bind after the `registry-host-replace` dispatch, which this pipeline fires itself.

- **AC10 (probe-wiring / liveness — NOT fix-confirmation)** After the dispatch replaces the registry host, the
  next `SOLEUR_ZOT_DISK` self-report carries `htpasswd_pull_matches` and `htpasswd_push_matches` as
  well-formed booleans. Verified without SSH:
  ```
  doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 30m --grep SOLEUR_ZOT_DISK --limit 1
  ```
  > **CORRECTED AT /work.** This AC originally required `=true` and was treated as the post-apply proof.
  > It is **near-vacuous as fix-confirmation**: the replace re-bakes htpasswd from the CURRENT Doppler values,
  > so `htpasswd_pull_matches=true` is the expected reading under **both** H3 and H4 — it cannot discriminate.
  > The plan's §Observability likewise claimed *"Pre-fix the same command returns `htpasswd_pull_matches=false`
  > — which IS the confirmation of H3."* **There is no such pre-fix window:** the probe lives in
  > `cloud-init-registry.yml`, so shipping it IS the `user_data` change that forces the replace that repairs the
  > divergence. The probe's own deployment destroys the datum it was written to capture. AC10 is therefore
  > demoted to "the probe is wired and reporting"; **AC11 is the real fix gate.** The probe's enduring value is
  > as the ongoing rotation-divergence detector — a *future* rotation without the Phase-2 edge would show
  > `false`, which is the job it actually has.
- **AC11 (THE fix gate)** The next deploy emits **zero** new `WEB-PLATFORM-5B` events and **at least one**
  `registry:zot` / "image pulled from zot" event — the first successful zot pull in the system's history (E2).
  Verified via the Sentry EU org-scoped issues API (see §Observability).
- **AC11b (H3/H4 verdict — post-replace, stated honestly)** The hypotheses are discriminated *after* the
  replace, not before it:
  - login succeeds + AC11 green ⇒ **H3 confirmed** (the stale boot-baked htpasswd was causal).
  - login still fails with `zot_login_class=authz_denied` + `zot_login_http=403` + `htpasswd_pull_matches=true`
    ⇒ **H3 refuted, H4 holds** ⇒ execute Phase 2b (zot `accessControl`, `cloud-init-registry.yml:116-126`).
  - `zot_login_class=tls_mismatch` ⇒ neither; an `insecure-registries` gap on the deploying host.
  Phase 2's Terraform edges ship regardless of the verdict — they are proven latent defects.
- **AC12** `#6416` interaction: AC11 requires the mirror to hold the image. If the pull 404s rather than 401s,
  that is #6416 (mirror backfill), not this defect — assert the discriminator (`zot_login_class` absent, a
  `registry:ghcr-fallback` event present instead of `zot-gate-degraded`) and link #6416 rather than reopening.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_ZOT_DISK self-report from the deny-all registry host, now carrying
        htpasswd_pull_matches / htpasswd_push_matches
  cadence: every 5 min (existing root cron, cloud-init-registry.yml:241)
  alert_target: Better Stack Logs source 2457081 (eu-fsn-3); polled by the in-repo GH-cron
        recurrence alarm per ADR-096 (log-content alarms are pollers, not native alerts)
  configured_in: apps/web-platform/infra/cloud-init-registry.yml (zot-disk-heartbeat.sh)

error_reporting:
  destination: Sentry EU (jikigai-eu/web-platform) via the ci-deploy store transport
        (zot_gate_degraded_event, ci-deploy.sh:636)
  fail_loud: true — level=warning, and the beacon fires on EVERY gate miss when
        ZOT_REGISTRY_URL is set. Fail-open on the POST itself (a Sentry outage must never
        abort a deploy); a POST failure breadcrumbs to journald and is shipped by Vector.

failure_modes:
  - mode: htpasswd diverged from the rotated Doppler token (H3 — this defect)
    detection: SOLEUR_ZOT_DISK htpasswd_pull_matches=false  [layer: Better Stack Logs]
    alert_route: |
      NONE TODAY — on-demand query only (betterstack-query.sh --grep SOLEUR_ZOT_DISK).
      CORRECTED AT /work: this field originally cited scripts/followthroughs/zot-soak-6122.sh
      as its alert route. That script polls SENTRY (API="https://sentry.io/api/0"), so it
      cannot see a Better Stack field, contains no htpasswd query, and is not enrolled. The
      citation was fiction, and `git grep htpasswd_pull_matches` returns zero consumers.
      Saying so plainly beats naming a route that does not exist — an unread probe that CLAIMS
      an alert route is the same defect class as the false comment this whole PR exists to fix.
      Wiring a standing poller is tracked separately (see §Follow-ups): the natural host is
      scripts/zot-restart-loop-alarm.sh, which already polls Better Stack for SOLEUR_ZOT_DISK
      and is enrolled via .github/workflows/scheduled-zot-restart-loop.yml — but it is a
      418-line fail-safe alarm ("NEVER FIRE on zero valid evidence") whose new leg needs its
      own false-positive profile, an `unknown`-vs-`false` policy, and RED tests. That is a
      design task, not a line to bolt on inside this PR.
  - mode: zot rejects zot-pull at /v2/ on authz, not authn (H4)
    detection: |
      FALSIFIED AT /work — NOT OBSERVABLE ON THE LOGIN PATH, and no longer a live hypothesis.
      Measured against the pinned zot (v2.1.2, the digest at zot-registry.tf:55) running this
      repo's exact accessControl: `docker login` issues exactly ONE request, GET /v2/, and zot
      answers 200 or 401 there — never 403. A user with ZERO accessControl policies still gets
      `Login Succeeded`; zot enforces authz at /v2/<repo>/manifests/<tag> (measured: 403),
      which the login path never touches. So a broken accessControl does not degrade the gate
      at all — login SUCCEEDS, ZOT_ACTIVE=1, and the failure surfaces later at PULL time under
      a different signal. The login probe is the wrong layer for H4; zot-entry-gate.sh
      (manifest endpoint) is where zot's real 403 lives.
    alert_route: n/a — see the pull-time modes; Phase 2b is struck (below).
  - mode: insecure-registries missing on a host → docker login attempts HTTPS
    detection: Sentry tag zot_login_class=tls_mismatch + host_id  [layer: Sentry]
    alert_route: WEB-PLATFORM-5B
  - mode: private-net route lost (the #6416 / ADR-114 class)
    detection: Sentry zot_gate_reason=probe_unreachable (WEB-PLATFORM-57)  [layer: Sentry]
    alert_route: WEB-PLATFORM-57
  - mode: registry host down / OOM / disk-full
    detection: absence of SOLEUR_ZOT_DISK + zot_restarts / oom_kills_5m  [layer: Better Stack]
    alert_route: soleur-registry-disk-prd + the #6291 restart-loop alarm

logs:
  where: web hosts → journald → Vector → Better Stack (source 2457081), tag ci-deploy.
         Registry host → SOLEUR_ZOT_DISK self-report only (deny-all, no SSH, no cloudflared).
  retention: Better Stack Logs source retention (ClickHouse warehouse, queryable via
         scripts/betterstack-query.sh)

discoverability_test:
  # Single-line on purpose. A `command: |` block scalar is mis-parsed by preflight Check 10:
  # its continuation regex (`^[[:space:]]+[^[:space:]]`) matches ANY indented line, so it
  # swallows the following `expected_output:` key into the command — which then trips the
  # shell-active-token reject on that key's own `|`. One line parses cleanly and, more to the
  # point, is a command an operator can actually paste.
  command: doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 30m --grep SOLEUR_ZOT_DISK --limit 1
  # Concrete + matchable on purpose: preflight Check 10 RUNS this command and substring-matches
  # stdout against this value. A prose paragraph here would never match and would fail the
  # check for a non-defect. `SOLEUR_ZOT_DISK` is the field-independent invariant — the host is
  # self-reporting at all. Verified live at /ship: exit 0, a real line returned.
  expected_output: SOLEUR_ZOT_DISK
  # Post-replace, that line additionally carries htpasswd_pull_matches / htpasswd_push_matches
  # as `true` / `false` / `unknown` (`unknown` = cannot tell — file or token absent, or a
  # non-mismatch htpasswd exit; deliberately distinct from `false` = read it, and it diverged).
  interpretation: |
    There is NO pre-fix reading of `false` to be had. The probe ships inside cloud-init
    user_data, so deploying it forces the host replace that re-bakes htpasswd — `true` is the
    expected post-replace value under BOTH H3 and H4 and proves only that the probe is wired.
    AC11 (zero new WEB-PLATFORM-5B + a registry:zot pull) is the fix gate. This probe's real
    job is ONGOING: it is what makes a FUTURE credential rotation's divergence visible within
    5 min instead of never — but only once something polls it (see the H3 alert_route above).
```

Secondary, also SSH-free (Sentry side, EU host — note `sentry.io` 404s for this org and
`SENTRY_AUTH_TOKEN` 403s; use `SENTRY_IAC_AUTH_TOKEN` against `jikigai-eu.sentry.io`):

```bash
TOK=$(doppler secrets get SENTRY_IAC_AUTH_TOKEN --plain -p soleur -c prd_terraform)
curl -s -G -H "Authorization: Bearer $TOK" \
  --data-urlencode 'query=registry:zot-gate-degraded' --data-urlencode 'statsPeriod=24h' \
  "https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/issues/" \
  | jq -r '.[] | "\(.shortId) count=\(.count) last=\(.lastSeen) \(.title)"'
# expected post-fix: no WEB-PLATFORM-5B rows in the 24h after the apply
```

## Downtime & Cutover

*(Required by deepen-plan Phase 4.55 — the plan replaces `hcloud_server.registry`, which is the infra
reboot/replace trigger class. Zero-downtime is the default and must be evaluated first, not assumed away.)*

**Offline-inducing operation:** `replace_triggered_by` forces a `-/+` replace of `hcloud_server.registry`. The
zot registry at `10.0.1.30:5000` is absent for the ~3-5 min boot+bake window.

**Serving surface affected: none.** This is the load-bearing fact, and it is evidence-backed, not asserted:

- The **pull path is dark**. `ZOT_ACTIVE=0` on every host today and zot has served **zero** pulls in 90 days
  (E2). Every web host pulls from GHCR and will continue to. app.soleur.ai, the Concierge, and the deploy
  webhook do not touch the registry host at all (model.c4:178 — no cloudflared on zot).
- The **store volume is disposable by design** — model.c4:260 documents it as a GHCR mirror that re-fills from
  CI's dual-push. Losing it costs a re-mirror, not data.
- The only affected consumer is the **CI mirror push** (crane), if a release lands inside the window. That path
  is already **non-blocking by design** (`fix(infra): zot mirror nonblocking release`, #6421 un-masks it as
  degraded rather than green) — a release during the window degrades its mirror step and still ships.

**Zero-downtime paths evaluated:**

| Path | Verdict |
|---|---|
| **Cron-converging htpasswd** (rebuild from Doppler on a timer, mirroring the ADR-115 private-NIC guard) — genuinely zero-downtime, no replace at all | **Rejected.** It would *silently repair* a rotation, destroying the immutable-redeploy audit trail and masking exactly the divergence this plan exists to make visible. It also diverges from `hr-prod-host-config-change-immutable-redeploy`. Recorded in the ADR-115 amendment's `## Alternatives Considered`. |
| **Blue-green** — stand up a second registry host, flip `ZOT_REGISTRY_URL`, retire the old | **Rejected as disproportionate.** `ZOT_REGISTRY_URL` is a fixed private IP; blue-green needs a second host + a Doppler flip + a cutover step, to protect a surface currently serving zero traffic. Revisit **after** the Phase-5 cutover, when the calculus inverts. |
| **In-place SSH rewrite of htpasswd** | **Rejected** — `hr-no-ssh-fallback-in-runbooks` + the host's deny-all firewall. |

**Decision: accept the bounded residual window** (gate clause 3). Justification: no serving surface is affected
(E2), the hard rule prefers immutable redeploy, and the only zero-downtime alternative actively defeats the
observability this plan is built to add. **No maintenance window or sign-off is required precisely because the
affected surface serves nothing today** — that is what makes now the cheapest possible moment to make this
change. Once the Phase-5 cutover puts zot on the live pull path, this same change would require a real window
and a blue-green path; the plan should land before then.

**Per-stage verification / rollback:** AC10 (`htpasswd_pull_matches=true` within 5 min, no SSH) is the
post-replace gate. Rollback is `terraform apply` against the prior state — and because the pull path is dark,
even a failed replace leaves every host booting correctly from GHCR. Blast radius on failure is the same as
today's steady state.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/zot-registry.tf` — `lifecycle.replace_triggered_by` + completed `depends_on` on
  `hcloud_server.registry`; corrected rotation comment.
- `apps/web-platform/infra/cloud-init-registry.yml` — htpasswd-match probe in `zot-disk-heartbeat.sh`
  (user_data change → contributes to the host replace).
- No new providers, no new variables, no new secrets. No `TF_VAR_*` to provision — nothing to mint, so the
  `hr-tf-variable-no-operator-mint-default` sequencing trap does not apply.

### Apply path

**(c) Immutable redeploy of `hcloud_server.registry` via the `registry-host-replace` dispatch.** The htpasswd
cannot be patched in place without an SSH provisioner, which `hr-no-ssh-fallback-in-runbooks` and the host's
deny-all firewall both forbid — so the host is replaced, per `hr-prod-host-config-change-immutable-redeploy`.

> **CORRECTED AT /work (2026-07-15) — the plan was wrong about the trigger.** This section originally read
> *"The apply is executed by the merge-triggered `apply-web-platform-infra.yml` workflow; no human runs a
> command."* **That is false, and believing it would have shipped a fix that never applied.** Every resource in
> `zot-registry.tf` is an `OPERATOR_APPLIED_EXCLUSION` under the CTO apply-path ruling of 2026-07-06
> (`zot-registry.tf:15-21`): they are deliberately **NOT** in the per-PR CI `-target=` list, because the per-PR
> path bridges over SSH to the existing web host and cannot provision a dedicated host. Merging this PR
> therefore lands the code and changes **nothing** on the registry host — AC10/AC11 would have been "verifying"
> a fix that had not been applied, and the `htpasswd_pull_matches` probe would never even ship.
>
> The `-target='hcloud_server.registry'` entries that a naive `git grep -n 'target='` surfaces (workflow
> `:1758`, `:1951`) belong to **`workflow_dispatch`** jobs, not the merge path — which is exactly why the
> plan's prescribed grep passed while its conclusion was wrong. The grep answered "is the address named
> anywhere?", not "does the merge path apply it?".

**The real path** (ADR-096 amendment 2026-07-08, `zot-registry.tf:24-30`): a sanctioned dispatch-only
`registry-host-replace` `workflow_dispatch` that runs a scoped, destroy-guarded
`terraform apply -replace='hcloud_server.registry'` preserving `hcloud_volume.registry`. It is fired with
`gh workflow run` — a CLI call this pipeline makes itself; it is **not** an operator handoff
(`hr-exhaust-all-automated-options-before`). Post-merge sequence: merge → `gh workflow run
apply-web-platform-infra.yml -f apply_target=registry-host-replace -f reason='#6483 …'` → AC10/AC11 verify.

**Verified at /work against real prod state** (read-only `terraform plan`, mirroring the dispatch job's exact
`-replace`/`-target` set, then the REAL gate run over the plan JSON):

```
out_of_scope=0 store_destroyed=0 secret_destroyed=0 volume_bad_update=0
server_replaced=1 nic_recreated=1 attachment_recreated=1 firewall_ok=1
registry_host_replace_gate: PASS — scoped registry-host recreate permitted
```

Three things this settles that the plan could only assert:
1. **AC8 holds** — `hcloud_server.registry → delete,create` and nothing out of scope; the store volume does not
   appear in the change set at all (preserved).
2. **The new `depends_on` edges do NOT trip the destroy-guard.** `doppler_secret.zot_{pull,push}_token_registry`
   are absent from the gate's 6-member allow-set, so a POSITIVE action on either would count as `out_of_scope`
   and ABORT the dispatch. They are already applied and stable ⇒ `no-op` ⇒ excluded by the gate's
   positive-action filter. This is a real latent edge (a fresh stand-up that must CREATE them would abort), and
   it is recorded as a Sharp Edge rather than pre-emptively widened — the abort is honest fail-loud behavior,
   and widening the allow-set on speculation would weaken a guard that exists to be narrow.
3. **`replace_triggered_by` fires no spurious rotation** — `random_password.*` is absent from the plan, which
   confirms the deepen pass's "no `keepers`" reasoning empirically rather than by inspection.

### Distinctness / drift safeguards

- `dev != prd`: the zot registry is prd-only; no dev counterpart exists.
- No `lifecycle.ignore_changes` is added anywhere — the whole defect is a value that was allowed to drift out of
  Terraform's sight.
- The two token values already land in `terraform.tfstate` (encrypted R2 backend) — unchanged by this plan.
- `random_password.zot_pull` has **no `keepers`**, so it does not regenerate on apply; `replace_triggered_by`
  fires only on an actual `-replace` rotation. Adding it does **not** cause a rotation now.

### Vendor-tier reality check

No vendor tier gates this — Hetzner server replace, Doppler secret reads, and the existing Better Stack Logs
source are all already provisioned and in-budget. No new recurring expense
(`wg-record-recurring-vendor-expense-before-ready` does not fire).

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-115** (`Dedicated hosts self-converge their private NIC at boot and self-report it`, status
`accepted`) — this is the same decision, one credential over. ADR-115 established that a dedicated, deny-all,
no-SSH host must **converge its own boot-time state and self-report it** rather than depend on an externally
pushed update. The htpasswd is exactly such boot-time state and was left out of that decision's scope. The
amendment adds to `## Decision`: *a boot-baked credential on a dedicated host must either (a) force host
replacement when its source value changes (`replace_triggered_by`), or (b) converge on a cron like the NIC guard
— and must self-report its match state so divergence is visible without SSH.* Add to
`## Alternatives Considered`: an SSH provisioner that rewrites htpasswd in place (rejected —
`hr-no-ssh-fallback-in-runbooks` + deny-all firewall), and a cron-converging htpasswd (rejected for now — it
would silently repair a rotation, defeating the immutable-redeploy audit trail; `replace_triggered_by` is the
honest edge).

**ADR-096 — checked at /work, does NOT need correcting.** `grep -niE 'one apply|re-propagat|htpasswd'` over
`ADR-096-*.md` returns only `:76` ("control-plane-minted htpasswd/JWT cred"), which is accurate. The false
guarantee was confined to `zot-registry.tf:80` — re-verified as that phrase's only occurrence in the entire
repo (`git grep -n 're-propagates htpasswd + Doppler in ONE apply'` → 1 hit), which is also what keeps AC3's
absence-grep safe. Phase 3.2 is a no-op, not a skip.

The ADR-115 ordinal is **not** provisional (it is an amendment to an accepted ADR, not a new ordinal), so the
`/ship` ADR-Ordinal Collision Gate does not apply.

### C4 views

**No C4 impact.** Enumeration performed against the model (`model.c4` + `views.c4` read for the registry/zot
surface; `spec.c4` to be confirmed at /work per the completeness mandate):

- **External human actors:** none added or changed — this path is machine-to-machine (CI/host → registry).
- **External systems / vendors:** none added. `zotRegistry` (model.c4:258), `ghcr` (:254), `doppler`, and
  `betterstack` (:264 — already documents receiving `SOLEUR_ZOT_DISK` from the deny-all registry host) are all
  already modeled.
- **Containers / data stores:** none added. `zotRegistry` already carries `10.0.1.30:5000`, the plain-HTTP
  private-net decision, the dark-launch gate, and the atomic GHCR fallback in its description.
- **Access relationships:** unchanged. The `zot-pull` / `zot-push` split and the `registry.` origin-relative
  tunnel edge (model.c4:369, ADR-114) are already modeled; this plan alters *when the credential is rebaked*, not
  who may reach what.

Both views already `include zotRegistry` (views.c4:14, :36), so nothing new needs a render line. A `.c4` edit
would add no element and change no edge — hence the "no impact" conclusion is cited, not asserted.

## Domain Review

**Domains relevant:** none

No cross-domain implications — infrastructure/supply-chain change on a dark-launched path with no user-facing
surface, no regulated data, and no new vendor. Product/UX gate does not fire: the mechanical UI-surface scan over
`## Files to Edit` / `## Files to Create` matches no `components/**/*.tsx`, `app/**/page.tsx`, or
`app/**/layout.tsx`. GDPR gate (§2.7) does not fire: no schema, migration, auth flow, API route, or `.sql`; no
LLM/external-API processing of operator data; threshold is `aggregate pattern`, not `single-user incident`; no
new artifact-distribution surface. The Phase 1 probe is explicitly designed to emit a boolean, never a
credential.

## Open Code-Review Overlap

**None.** Verified 2026-07-15:
`gh issue list --label code-review --state open --json number,title,body --limit 200` piped through
`jq -r --arg path "<p>" '.[] | select(.body // "" | contains($path))'` for each of `ci-deploy.sh`,
`zot-registry.tf`, `cloud-init-registry.yml` → zero matches.

Adjacent open issues, deliberately **not** folded in:
- **#6416** (web-2 private-net → mirror push unreachable) — different defect (mirror *push* path, not the pull
  login). AC12 encodes the discriminator so the two are not conflated. *Acknowledge.*
- **#6428** (post-cutover zot staleness uncovered) / **#6462** (soak has no denominator) — observability gaps
  that only bind after cutover. *Acknowledge.*
- **#6129** (cosign WARN→ENFORCE flip) — explicitly post-cutover. *Acknowledge.*

## Files to Edit

- `apps/web-platform/infra/ci-deploy.sh` — capture + classify login stderr; `host_id`, `zot_login_class`,
  `zot_login_http` on `zot_gate_degraded_event`.
- `apps/web-platform/infra/zot-registry.tf` — `replace_triggered_by`; complete `depends_on`; correct the false
  rotation comment.
- `apps/web-platform/infra/cloud-init-registry.yml` — `htpasswd -vb` match probe in `zot-disk-heartbeat.sh`.
- `apps/web-platform/infra/ci-deploy.test.sh` — classification + payload-hygiene tests.
- `apps/web-platform/infra/registry-insecure-config.test.sh` — TF-shape assertions.
- `knowledge-base/engineering/architecture/decisions/ADR-115-dedicated-host-private-nic-boot-convergence.md` — amendment.

## Files to Create

- None.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The registry host is replaced and the new one also fails to bake correctly | AC10's `htpasswd_pull_matches` is the post-apply gate — it reports the truth from inside the host within 5 min, no SSH. |
| `replace_triggered_by` causes an unintended replace on an unrelated apply | `random_password` has no `keepers`; it is stable across applies and only changes under an explicit `-replace`. AC8 asserts the plan replaces exactly one resource. |
| The store volume is wiped by the replace | Accepted and by design — model.c4:260 documents the volume as a disposable GHCR mirror that re-fills from CI dual-push. The pull path is dark (E2), so nothing depends on its contents today. |
| The probe leaks a token | `htpasswd -vb` verifies without printing; only a boolean crosses the boundary. AC5 asserts raw stderr never reaches the Sentry payload. Reviewed against `cq-silent-fallback-must-mirror-to-sentry` (the mirror stays; only the payload is sanitized). |
| H3 is refuted by the probe | Phase 2b is the pre-written H4 arm. Phase 2's edges ship regardless — they are proven latent defects, independent of which hypothesis wins. |
| The registry host is outside `apply-web-platform-infra.yml`'s `-target` set → silent no-op | §Infrastructure prescribes the `git grep -n 'target='` check; AC8 asserts the plan's replace set. |

## Research Insights (deepen-plan pass, 2026-07-15)

### Precedent diff (§4.4 gate) — every prescribed pattern has an in-repo canonical form

| Prescribed pattern | Precedent (verified) | Fit |
|---|---|---|
| stderr **content** classification for `zot_login_class` | `_pull_result_is_auth_denied` at `ci-deploy.sh:530-532`: `printf '%s' "${1:-}" \| grep -qiE 'unauthorized\|authentication required\|denied\|forbidden'` — takes a **string arg** (caller passes `tail -c 400 "$perr"`), greps content, never the path | **Exact.** Mirror this shape; do not invent a new one. Note the precedent's regex conflates `unauthorized` and `denied` into one bucket — Phase 1 must **split** them (401 vs 403) or it reproduces the very ambiguity being fixed. |
| adding tags to `zot_gate_degraded_event` | `pull_failure_event` at `ci-deploy.sh:559-563` already feeds multiple `--arg`s into a `tags` object literal | **Exact.** `tags` is a plain jq object (`:641-644`); new tags are additive `--arg` + `key: $var`. No structural risk. |
| boot-convergence + self-report on a deny-all host | the private-NIC guard (`cloud-init-registry.yml:457-467`, ADR-115) | **Same class.** This is why the ADR-115 *amendment* is the right home, not a new ADR. |
| immutable redeploy for a prod host config change | `hr-prod-host-config-change-immutable-redeploy` | **Exact.** |

### Verify-the-negative pass — all six load-bearing negative claims confirmed

1. **`htpasswd -vb`** — verified live: exit `0` match / exit `3` mismatch; prints only a fixed status line
   (`Password for user X correct.` / `password verification failed`), **never the token**. Plan discards it via
   `>/dev/null 2>&1` regardless. The boolean-only guarantee holds.
2. **`random_password` has no `keepers`** — `grep -n "keepers" zot-registry.tf` → **zero hits**;
   `random_password.zot_pull`/`zot_push` at `:81-88` are `{ length = 40, special = false }` only. Confirms
   `replace_triggered_by` will **not** fire spuriously on a routine apply.
3. **No token value in `user_data`** — the `templatefile()` call at `:248-279` passes exactly
   `registry_volume_id, doppler_token, zot_image, zot_pull_user, zot_push_user, doppler_arch, doppler_sha256,
   disk_heartbeat_url, betterstack_ingest_url, private_ip`. Only the non-secret **usernames**; zero references
   to `random_password.*.result`. **This is the mechanical proof of the root cause** — Terraform has no data
   edge from the password to the host, so it cannot know the bake is stale.
4. **The code says so explicitly** — `:252-254`: *"The tokens themselves are NEVER in this user_data."* The
   isolation was deliberate and correct; the missing `replace_triggered_by` is the unintended consequence.
5. **The `depends_on` gap is real, not a strawman** — `:289` is literally a single-element list:
   `depends_on = [doppler_secret.registry_betterstack_logs_token]`.
6. **No SSH dependency on the apply** — `grep -n "provisioner\|connection {" zot-registry.tf` → **zero hits**.
   `hcloud_server.registry` (`:226-294`) has no `provisioner`/`connection` block, so the network-outage gate's
   resource-shape trigger does **not** fire for this apply (unlike `terraform_data.registry_insecure_config`,
   which does have SSH provisioners but is not in this plan's change set).

### Implementation note surfaced by the pass

The precedent regex at `:530-532` buckets `unauthorized|denied|forbidden` **together**. Phase 1's whole purpose
is to separate `authn_rejected` (401 → H3, stale htpasswd) from `authz_denied` (403 → H4, accessControl). If the
implementer copies the precedent regex verbatim, the two hypotheses collapse into one bucket and the probe
cannot discriminate — the exact defect this plan exists to fix, reintroduced. Phase 3 test 2 (`tls_mismatch`
must not classify as `authn_rejected`) should be extended with a sibling case: **`403` must not classify as
`authn_rejected`.**

## Sharp Edges

- **`lifecycle` blocks are config-phase validated, `replace_triggered_by` is plan-phase.** Run `terraform
  validate` on the minimal body before trusting the plan output (the beta-provider trap from
  `2026-05-15-terraform-import-only-beta-provider-schema-validation.md`).
- **`replace_triggered_by` accepts a resource reference, not an attribute** for whole-resource triggers — use
  `random_password.zot_pull`, not `random_password.zot_pull.result`. Verify at /work against the installed
  Terraform version rather than from memory.
- **Do not "fix" this by rotating the token again.** Rotation is the *trigger*, not the cure — without Phase 2's
  edge, a rotation re-creates the exact divergence. Fix the edge first, then rotate if desired.
- **`SENTRY_AUTH_TOKEN` 403s and `sentry.io` returns `[]`/`Invalid token` for this org** — the org is EU-region:
  use `SENTRY_IAC_AUTH_TOKEN` against `https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/`. Verified
  2026-07-15. `scripts/betterstack-query.sh` requires the `doppler run -p soleur -c prd_terraform --` wrapper; an
  unwrapped run exits 3 with a hint — that is **not** a lack of access.
- **Bash-tool network calls in this repo's sandbox fail with curl exit 5** (proxy resolution). Any /work step
  that probes Sentry/Better Stack/Hetzner must run with the sandbox disabled, or it will look like an auth
  failure when it is a sandbox failure. Verified 2026-07-15.
- **A plan that "verified" the credential by comparing Doppler to Doppler proves nothing.** Both copies derive
  from the same `random_password`, so they agree *by construction* even when both have drifted away from the
  host's baked htpasswd. The only credential comparison with evidentiary value is host-htpasswd vs Doppler —
  which is precisely what Phase 1's probe adds, and why it must ship before the fix is believed.

### Discovered at /work (2026-07-15)

- **`git grep -n 'target='` answers the WRONG question — and this plan's §Infrastructure got the apply path
  backwards because of it.** The grep proves an address is *named somewhere* in the workflow; it does not prove
  the **merge path** applies it. `hcloud_server.registry` appears at `:1758`/`:1951` — both inside
  `workflow_dispatch` jobs — while every `zot-registry.tf` resource is an `OPERATOR_APPLIED_EXCLUSION` (CTO
  ruling 2026-07-06) deliberately excluded from the per-PR `-target=` list. The plan's own prescribed
  verification *passed* while its conclusion was false. To answer the real question, find the `-target` block's
  enclosing **job** and that job's **trigger** (`on: push` vs `workflow_dispatch`), or grep the exclusion
  contract (`git grep -n OPERATOR_APPLIED_EXCLUSION`) — the two together, never the bare address grep.
- **The `registry-host-replace` destroy-guard has a 6-member allow-set, so ANY new `depends_on` edge on
  `hcloud_server.registry` lands in its blast radius.** `out_of_scope` counts positive actions
  (create/update/delete/forget) on addresses outside that set; `no-op` and `read` are excluded. The two ZOT
  token secrets this plan adds to `depends_on` are absent from the allow-set, so they are safe *only* while
  they plan as no-op. Verified so against live prod state at /work (gate PASS, `out_of_scope=0`).
  **CORRECTED AT /work — the trigger this Sharp Edge originally named ("a fresh stand-up that must CREATE
  them") is unreachable**, so the fail-loud-vs-widen trade it described was a trade against nothing: with no
  host in state the plan is a bare `create`, so `server_replaced=0` aborts first, and
  `apply-web-platform-infra.yml:453` says no dispatch creates this host at all (that is the operator-local
  full apply's job). The **reachable** trigger is Doppler drift: a hand-edited or deleted
  `doppler_secret.zot_{pull,push}_token_registry` plans as `create`/`update` → `out_of_scope` → ABORT. That
  abort is **correct** — the credential the host bakes its htpasswd from has diverged from Terraform, and a
  scoped host-replace is precisely the wrong move while that is true. Do NOT widen the allow-set: `#6244` is
  not the precedent (its secret was a genuine pending CREATE against an already-existing host; these cannot
  acquire one on this path), and its `-target` companion is redundant here anyway since `-target` pulls the
  `depends_on` closure in automatically. The rationale now lives in the gate's own header, next to the
  allow-set it explains, rather than only in this plan — which is archived.
- **A `terraform plan` + the REAL gate function is cheap, read-only, and settles in one shot what the plan
  could only argue.** `terraform show -json <plan>` piped through the sourced
  `tests/scripts/lib/registry-host-replace-gate.sh` gave the authoritative verdict on AC8, the depends_on
  interaction, AND the "no spurious rotation" claim. Prefer it over reasoning about `-target` graph semantics.
  Shred the plan file + JSON afterwards (`shred -u`) — they carry state values.
- **`terraform console` cannot render a template from the real infra dir** (it demands full backend init, and
  `-backend=false` leaves `console` erroring on the s3 backend). Render from a genuine scratch dir:
  `printf 'templatefile("<abs>", {…})\n' | terraform -chdir="$(mktemp -d)" console`, strip the `<<EOT`/`EOT`
  wrapper, then `cloud-init schema -c <rendered>`.
