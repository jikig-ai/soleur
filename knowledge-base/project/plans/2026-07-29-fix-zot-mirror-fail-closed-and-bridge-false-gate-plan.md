---
title: "fix(infra): make the zot mirror fail-closed, and replace the bridge's false gate"
date: 2026-07-29
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
branch: feat-one-shot-zot-mirror-fail-closed
pr: 7071
---

# fix(infra): make the zot mirror fail-closed, and replace the bridge's false gate

> **Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).** No
> `knowledge-base/project/specs/feat-one-shot-zot-mirror-fail-closed/spec.md` exists; this plan is
> the first artifact for the branch.

## Overview

On 2026-07-29 the web-platform release for **v0.244.1** built and pushed to GHCR successfully, the
release published, and then `deploy` died `image_pull_failed`. Production sat undeployable for ~5h.

The release was green because the CI zot-mirror step is **warn-only by design**: it emits
`mirror_status=degraded` + a `::warning::` and exits 0. That tolerance was a correct decision when
it was made — it rested on GHCR being a working break-glass fallback. **That premise is now
false**, so the mirror must fail-closed.

This plan delivers three things:

- **A — the mirror becomes release-blocking**, via a *positive* post-mirror assertion (the
  `v<version>` tag must resolve in zot at the same digest GHCR holds), not by trusting any step's
  self-reported status.
- **B — the bridge's `nc -z` false gate is replaced** with a positive `/v2/` probe, and two
  *factually false* claims in the degraded message are corrected. **No Terraform, no Cloudflare
  write, and no Doppler write is required** — see Premise Validation.
- **C — the discarded zot-pull stderr is logged**, so the next occurrence is one query, not log
  archaeology.

## Premise Validation

Run before any research was dispatched (plan Phase 0.6). **Two of the three stated premises for
Deliverable B were falsified by live evidence.** Deliverable A's premise was confirmed and
strengthened.

### Confirmed

| Premise | Evidence |
|---|---|
| Mirror step is warn-only and emitted `rc=bridge` | `reusable-release.yml` `degraded()` → `mirror_status=degraded`, `exit 0`, `continue-on-error: true`. Run **30468080168** annotation reproduces the quoted text verbatim. |
| **GHCR is dead** | `GHCR_READ_TOKEN` in Doppler `prd` is a 40-char `ghp_` classic PAT. `GET api.github.com/user` → **401**. Registry pull-token mint → **403 `{"errors":[{"code":"DENIED"}]}`**. `GHCR_MINTER_DISABLED=true`. |
| Deploy failed `image_pull_failed` | Job 90634334826: `##[error]ci-deploy.sh exited 1 (reason=image_pull_failed, tag=v0.244.1)`. |
| `ci-deploy.sh` discards `$perr` on the zot arm | `ci-deploy.sh:1589` logs only the bare `IMAGE_PULL: zot pull failed …` line; `$perr` is captured at `:1554` and only read later by `pull_failure_event` (`tail -c 400`). |
| A failed `release` job blocks deploy | `web-platform-release.yml`: `deploy: needs: [release, migrate, verify-migrations, verify-doppler-secrets, await-ci]`. |

### Falsified — Deliverable B is re-scoped

**F1. The `HTTP 200` + empty body from `https://registry.soleur.ai/v2/` is CORRECT BEHAVIOUR, not a
broken origin.** The tunnel ingress for that hostname is `service: tcp://10.0.1.30:5000` — a
**TCP-mode** ingress, consumable only via `cloudflared access tcp`. A plain HTTPS GET is not a
WebSocket upgrade for that stream, so nothing is proxied. The repo already documents this:
`cf-tunnel-registry-bridge/action.yml` header — *"`tcp://`, NOT `http://`: `cloudflared access tcp`
bridges a raw TCP stream over a WebSocket"*. Reproduced: with CF Access headers → `200`, `size=0`,
**no `content-type` at all**; without → `403`. A real origin response carries
`content-type: application/json`.

**F2. The private-net route to `10.0.1.30:5000` is present and working.** Live tunnel config
(`GET /accounts/{acct}/cfd_tunnel/6410c1ec…/configurations`) shows the `registry.soleur.ai` →
`tcp://10.0.1.30:5000` ingress. Verified end-to-end: `cloudflared access tcp --hostname
registry.soleur.ai --url 127.0.0.1:15000`, then `GET http://127.0.0.1:15000/v2/` returned
**HTTP 401 from zot itself** (`Www-Authenticate: Basic realm="Authorization Required"`, body
`{"code":"UNAUTHORIZED","message":"authentication required",…}`). That is the origin answering
through CF Access → tunnel → connector → zot. The 401 is simply "no htpasswd creds sent".

> **Honest limitation.** This probe ran from the operator's laptop, not a GitHub runner. It proves
> the path is *capable* now; it does not prove a runner will succeed. The faithful test is a CI
> run, which is a production mutation and is deliberately out of scope tonight. AC13 defers it.

**F3. The actual root cause was a CF Access service-token rotation that did not propagate.** The
bridge's own log, recovered from the teardown step of run 30468080168:

```
2026-07-29T16:01:14Z ERR failed to connect to origin error="websocket: bad handshake" originURL=https://registry.soleur.ai
```

`websocket: bad handshake` is the *client* failing to establish the session at the edge — CF Access
refused the upgrade. A missing origin route would instead produce a **successful** handshake then an
origin-side failure. Timeline, exact:

| Time (UTC) | Event |
|---|---|
| 15:53:26 | Run 30468080168 starts (release for #7065, *"make the CF Access service tokens rotatable via Terraform"*). |
| **15:57:52** | `github-actions-registry-push` service token **created** (live CF API `created_at` == `updated_at`) — i.e. replaced. |
| 16:01:14 | Bridge runs with the **stale** Doppler value → `websocket: bad handshake` ×4. |
| 16:01:14 | `nc -z 127.0.0.1 5000` still passes → bridge step `__run_2` reports **success**. |
| 16:01:15 | `docker login` through the dead stream → `connection reset by peer` → `__run_3` **fails**. |
| — | `zot_mirror` branches to `degraded "bridge"` → warn-only. Release **publishes v0.244.1**. |
| — | Deploy: zot has no v0.244.1; GHCR fallback → PAT revoked → `image_pull_failed`. |

The mechanism is gotcha #2 — every `doppler_secret` carrying a token declares
`lifecycle { ignore_changes = [value] }`, so Terraform recreated the CF Access token but could never
propagate the new secret. **The operator independently reached this same conclusion hours earlier**:
commit `5eba7ec07` (#7067) names `REGISTRY_PUSH_ACCESS_TOKEN_*` as *"`prd` root stale after a
Terraform replace"*. The token in Doppler `prd` works now (my probe minted a valid
`CF_Authorization`), so this specific staleness is already remediated.

**Net effect on scope:** Deliverable B has **no infrastructure defect to fix**. It becomes a
detection-and-truthfulness fix in code + docs. This is strictly better than the staged-Terraform
outcome the task anticipated, and it removes the only part of the task that would have needed an
operator `terraform apply`.

## Research Reconciliation — Spec vs. Codebase

| Task claim | Reality | Plan response |
|---|---|---|
| "fix the CF-tunnel registry bridge that silently mirrored nothing" | Bridge is healthy; it failed once on a stale CF Access token, since remediated. | Re-scope B to the **false gate** + **false comment** + **detector coverage**. No infra change. |
| "`/v2/` returns 200 empty ⇒ Cloudflare answering without a working origin" | Expected for a `tcp://` ingress (F1). | Correct the misdiagnosis in-repo so it is not repeated; add the correct probe shape to the runbook. |
| "the tunnel connector may lack a private-net route to 10.0.1.30:5000" | False (F2). `model.c4:428` already records this #6416 failure mode as **closed** (web-2 retired 2026-07-17, #6538; surviving web-1 connector is a subnet member). | Delete the false claim from `reusable-release.yml:782`; replace with the measured cause class. |
| "If the fix is Terraform, write it, run fmt/validate/plan only" | No Terraform needed. | Explicitly state no `.tf` change; skip the IaC gate with a reason. |
| ADR-096 permits a warn-only mirror | True, but justified on GHCR **redundancy** — *"a mirror failure degrades zot redundancy, never the release/build verdict."* GHCR is dead, so zot is not redundant; it is the sole path. | Fail-closed requires an **ADR-096 amendment** — a deliverable of this plan, not a follow-up. |
| "Keep `reusable-release-zot-mirror-retry.test.sh` green" | It extracts the step's `run:` block by literal `index($0, "- name: " target)` and executes it under stubs. | Deliver A as a **new sibling step**. *Corrected at review:* the original justification ("leaves the extracted block byte-identical") was self-contradictory — Phase 3 (FR-B3) edits the `degraded "bridge"` message, which lives **inside** that block. The real reason the sibling step is required is structural: **a step without `continue-on-error` cannot be the same step as one that has it.** The harness still needs no assertion change because it matches the literal step *name*, which is unchanged, and asserts on `mirror_status`, whose values are unchanged. |

## Hypotheses

Ordered L3 → L7 per `hr-ssh-diagnosis-verify-firewall`. Routing was verified **before** any
auth/service-layer conclusion.

1. **L3 — origin route missing (tunnel ingress lacks `10.0.1.30:5000`).** **REFUTED.** Live tunnel
   configuration contains the ingress; zot answered 401 through it (F2).
2. **L3 — DNS/edge.** **VERIFIED HEALTHY.** `registry.soleur.ai` is a proxied CNAME to
   `<tunnel-id>.cfargotunnel.com`; edge answered on every probe (`server: cloudflare`, `cf-ray`
   present).
3. **L3 — connector homogeneity (a replica without a private NIC).** **REFUTED for this incident.**
   Single web host since 2026-07-17 (#6538); `model.c4:428` records the mode closed. The tunnel's 4
   connections are one cloudflared instance's 4 HA edge links, not 4 hosts.
4. **L7 — TLS/proxy layer misconfiguration (empty 200 ⇒ broken origin).** **REFUTED.** Empty 200 is
   the documented consequence of a `tcp://` ingress answering a non-WebSocket request (F1).
5. **L7 — CF Access rejected the service token after a Terraform-driven rotation.** **CONFIRMED as
   the mechanism**, with a 3-minute causal window and a matching client-side error (F3). Already
   remediated in Doppler; the *detection* gap is what this plan closes.
6. **L7 — zot itself down / disk-full.** **REFUTED.** zot served both hosts' v0.244.0 pulls the same
   day (`IMAGE_PULL_OK: registry=zot`) and answered my probe.

## User-Brand Impact

- **If this lands broken, the user experiences:** a release that reports success while production
  keeps serving the previous build — the exact v0.244.1 shape, where `app.soleur.ai` silently stayed
  ~5h behind `main`. In the permissive direction the user sees no error at all, which is why this
  failed silently for a full release cycle.
- **If this leaks, the user's data is exposed via:** the *blocked* remediation — **not by this PR,
  which moves no personal data.** The exposure is **already live and independent of this change**: the
  2026-07-27 laptop compromise
  (`knowledge-base/project/learnings/security-issues/2026-07-28-vscode-folderopen-task-rce-and-fleet-wide-key-rotation.md`)
  left the legacy Supabase `service_role` key valid and compromised. That key **bypasses RLS on every
  table**, so the exposed class is the whole store — sharpest at the BYOK-encrypted customer API-key
  material (`server/byok.ts`) and user PII. Disabling it requires first migrating the browser client
  off the legacy anon key, which requires shipping a new image — which, with GHCR dead, requires the
  mirror to actually land. **This PR removes a blocker to remediation; it does not create the
  exposure.**
- **Brand-survival threshold:** `single-user incident`

**Threshold reasoning (re-framed at review — the first draft argued only the direction that favoured
its own design).** On *first-order* blast radius this change is `none`-to-`aggregate pattern`: its own
failure modes are release-pipeline availability, not data harm. It clears `single-user incident`
**transitively**, which is admissible because `hr-weigh-every-decision-against-target-user-impact` is
outcome-framed, not diff-framed. The honest form of the argument is that **both** failure directions
extend the same compromised-key window — fail-open silently, fail-closed by delaying the migration —
but the blocked-and-loud case is recoverable in minutes, while the silent case ran ~5h undetected and
spent its diagnostic budget on a misdiagnosis. `aggregate pattern` is the wrong label because
aggregate harms are *trend-shaped* (detected across many users over time); this harm is one named
credential against named rows. The threshold is also doing real work procedurally: it is what pulls
in `user-impact-reviewer` and CPO sign-off, and the CPO review is what caught the dead escape hatch
(FR-B7).

## Functional Requirements

### A — the mirror must fail-closed

- **FR-A1.** A new workflow step, **`Verify zot mirror landed (fail-closed)`** (id `zot_verify`),
  runs after `zot_mirror` and **before** `Tear down cloudflared registry bridge` (the probe needs
  the bridge up; teardown is `if: always()` so it still runs on failure). Gated
  `if: steps.docker_build.outcome == 'success'` — identical to `zot_mirror`, so a release that never
  built an image is unaffected. **No `continue-on-error`.**
- **FR-A2.** The gate is a **positive assertion, primary and independent of self-report**, and it
  compares **crane-to-crane** so both sides use identical manifest-resolution semantics:

  ```
  crane digest ghcr.io/${REPO}:v${VERSION}   ==   crane digest 127.0.0.1:5000/${REPO}:v${VERSION}
  ```

  Both invocations MUST succeed and the digests MUST be equal. **Do not compare against
  `steps.docker_build.outputs.digest` as the primary signal**: buildx's `outputs.digest` may be an
  index digest or a platform-manifest digest depending on provenance/multi-arch settings, whereas
  `crane digest <tag>` resolves whatever the registry serves for that tag. Any semantic mismatch
  there is *deterministic* red on every release — the "gate merged, first release fails, gate
  hot-reverted" path. Crane-on-both-sides removes the question entirely at zero cost.
  As a cheap extra check, when `steps.docker_build.outputs.digest` is **non-empty**, assert it also
  matches; skip that arm when empty rather than failing on it.
  `crane digest` is established precedent in this repo (16 existing call sites) and needs **no
  insecure/plain-HTTP flag** for a loopback ref — the mirror step already records the Phase-0 spike
  evidence: *"crane + cosign auto-treat loopback (127.0.0.1) as an insecure registry."*
  Implementation location: `.github/workflows/reusable-release.yml`, new step after `zot_mirror`.
- **FR-A3.** The gate ALSO requires `steps.zot_mirror.outputs.mirror_status == 'ok'` — the
  suspenders, catching the **present-but-unsigned** state that FR-A2 alone would pass.

  **This will be the MOST COMMON blocking discriminator, not the rarest** (corrected at review):
  `degraded()` ends in `exit 0`, so it is a *first-failure abort*, not an accumulator. The copy loop
  runs `v${VERSION}`, then `${COMMIT_SHA}`, then `latest` — so a failure on the `<sha>` or `latest`
  arm kills the loop **before `cosign sign` ever runs**, leaving `v<version>` present *at the correct
  digest* but unsigned. FR-A2 passes that state; FR-A3 blocks it.

  **The availability trade must be stated as chosen, not implied as a prevented failure.** Host-side
  verify is currently **`warn`**, not enforce — `ci-deploy.sh:54`:
  `readonly IMAGE_VERIFY_MODE="${IMAGE_VERIFY_MODE:-warn}"` (two tests actively assert the default
  stays `warn`; the enforce flip is soak-gated, #6023 open). So **today** an unsigned-but-present zot
  copy emits `cosign_verify_event "unsigned"` and **deploys anyway**. FR-A3 therefore converts a
  currently-deployable state into a blocked release, and adds **Sigstore (Fulcio/Rekor) availability
  as a new release-blocking third-party dependency**. The trade is still the right one — with host
  verify at `warn`, this gate becomes the *only* thing refusing an unsigned image in the sole pull
  path — but it is a choice, not a prevention, and the plan says so.

  Consequence for FR-A4: `mirror_degraded` MUST be split so the operator can tell "wait, Sigstore is
  down" from "your registry is broken", and the signing arm's message MUST state that
  **`v<version>` IS present in zot at the correct digest — the blocker is the missing signature** —
  plus the exact re-sign one-liner. Otherwise the operator reads "release blocked" for a state where
  production could in fact be served safely.
- **FR-A4.** **Self-report before abort** (`2026-07-19` fail-closed-gate learning + the
  evidence-discarding-gate learning). Before exiting non-zero the gate MUST emit one
  discriminating record — to `::error::` **and** `$GITHUB_STEP_SUMMARY` — naming the image ref, the
  tag, the expected and observed digests, a bounded tail of the failing command's stderr, and an
  `outcome` drawn from a set that separates **every** competing root cause in one event:

  **Every discriminator MUST ship with a plain-language operator remedy** — the observability
  plumbing is worthless to a non-technical founder without the comprehension layer
  (`hr-ship-message-no-operator-checklist`):

  | `outcome` | Means | Operator remedy (rendered in the step summary) |
  |---|---|---|
  | `bridge_refused` | nothing listening on `127.0.0.1:5000` — the bridge never came up | run the Cloudflare token-drift detector; the CF Access token may be stale |
  | `bridge_transport_error` | connected, then the stream failed (reset / empty reply / TLS negotiation) — **the v0.244.1 shape** | same as above; this is the rotation-staleness signature |
  | `crane_missing` | `crane` absent from `PATH` (mirror degraded at `install_crane`) | CI regression — file an issue; not a registry problem |
  | `ghcr_digest_unavailable` | the GHCR-side digest could not be read | GHCR read problem; no comparison possible — re-run |
  | `tag_absent` | zot cannot resolve `v<version>` — nothing was mirrored | zot degraded — see the revert runbook, fix, then re-run |
  | `digest_mismatch` | both sides resolve but differ | zot holds a different build — re-land via the backfill one-liner |
  | `signing_failed` | copied OK, `cosign sign` failed — **the image IS present at the correct digest** | likely a Sigstore outage: wait and re-run, or re-sign with the printed one-liner. **Not** a registry fault |
  | `mirror_degraded` | any other `mirror_status != ok` | read the mirror step's own warning |

  Two separations are load-bearing. `bridge_refused` vs `bridge_transport_error` are exactly what the
  old `nc -z` gate conflated, and the transport arm is the one that actually fired. `signing_failed`
  vs the rest is what keeps "wait 20 minutes" from being confused with "your registry is broken" —
  opposite remedies (FR-A3).

  The record MUST also print: the `crane copy … && cosign sign --yes …` backfill command for the
  affected tag (R1b), and the reassurance that **nothing was half-shipped** — the release is still an
  unpublished draft with no git tag, and re-running is non-destructive (R1). A failed release's
  default instinct is to fear a partial ship; that sentence belongs in the annotation, not only in a
  risks table the operator will never open mid-incident.
- **FR-A5.** A code comment at the gate MUST state the coupling: this gate is correct **only while
  GHCR is not a usable fallback**, name the evidence (revoked `ghp_` PAT + `GHCR_MINTER_DISABLED=true`
  per ADR-088 arm-b), and say explicitly that restoring a working GHCR pull credential is the
  condition under which the gate may be relaxed back to warn-only.
- **FR-A6.** `plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh` MUST stay green **with
  no change to its assertions**. Delivering A as a sibling step keeps the extracted `run:` block
  byte-identical; the harness matches on the literal step name
  `"Mirror image GHCR→zot (crane) + cosign-sign the zot digest"`, which this plan does not rename.
- **FR-A7 — bounded retry, so a transient blip is not a blocked release.** The assertion MUST retry
  (3 attempts, 5s then 15s backoff, mirroring the mirror step's existing `retry()` helper) before
  declaring failure. Without this, one mid-blob TCP reset over the multi-hop CF-tunnel — the exact
  transient `continue-on-error` was originally added for (#6274) — becomes a red release train, and
  the predictable organisational response to a flaky blocking gate is a hotfix that re-adds
  `continue-on-error`. That hotfix is the wrong-architecture commit this FR exists to prevent.
- **FR-A8 — a dispatch-only, reason-required override. (Three-way disagreement; this is the
  synthesis, not a coin flip.)** The strong-model advisor and the CTO both argued **for** an override;
  the CPO argued **against**. Each is right about a different case, and the distinction is whether
  the gate is *correct*:
  - When the gate is **right** (the image genuinely is not in zot), an override buys **nothing** — the
    image cannot be pulled by any host, so overriding publishes a release that still cannot deploy.
    That is the CPO's objection and it is valid.
  - When the gate is **wrong** (a misfire — the image *is* present and pullable), an override is the
    difference between a 30-second unblock and *editing a workflow on `main` under incident
    pressure*, which is an unacceptable ask for a non-technical operator. That is the CTO's SPOF
    finding and it is also valid.

  Resolution — take the override, and make misuse structurally hard:
  1. Available **only** via `workflow_dispatch`. A normal push-triggered release has no override at
     all, so it can never be tripped silently.
  2. Requires a **non-empty reason** input to take effect.
  3. When used, it emits a loud `::warning::`, records the reason + the unverified digest to
     `$GITHUB_STEP_SUMMARY`, fires FR-A10's notification, and **auto-files an `action-required`
     issue**.
  4. Its documentation states plainly that **the override does not make an unmirrored image
     pullable** — its only legitimate use is a suspected gate misfire, and the operator should
     otherwise prefer the `crane copy` + `cosign sign` backfill.

  Confirm the dispatch's `environment:` required-reviewer set is **non-empty** before treating it as
  a gate (DP-11 F8: a zero-reviewer environment auto-approves).
- **FR-A10 — an `if: failure()` operator notification (see R2).** Add an
  `if: failure()` + `./.github/actions/notify-ops-email` step to the release job so a blocked release
  reaches `ops@jikigai.com` rather than only the triggering actor. The body MUST carry the FR-A4
  discriminator **and** the one-sentence recovery action a non-technical operator can execute
  (`hr-ship-message-no-operator-checklist`, `hr-no-ssh-fallback-in-runbooks`) — never a checklist.
  Apply the same treatment to FR-B5's new scheduled detector workflow: a scheduled-workflow failure
  notification routes to the workflow file's last committer, which is not a signal.
- **FR-A11 — name the orphan-draft leak (see R1a).** The plan must not imply a clean self-heal. Either
  add a draft-orphan reaper, or explicitly record the leak plus its manual clean-up
  (`gh release delete <tag>`), and note the stale-release-notes case for the same-bump path. A reaper
  is preferred but may be scoped out **with a tracking issue** — silence is not an option.
- **FR-A9 — the skip condition must not drift away from the publish condition.** Verified for the
  current workflow: no release can publish an image reference without `docker_build` having run, so
  gating the new step on `steps.docker_build.outcome == 'success'` is sufficient today. Derivation:
  `Finalise release (publish draft)` requires `check_changed == 'true'`; `Compute next version` is
  gated on the same, so `next` is non-empty; `docker_build` is gated on
  `steps.version.outputs.next != '' && inputs.docker_image != ''`, so for any component carrying a
  `docker_image` the build necessarily ran. (`docker_build` has no `continue-on-error`, so a build
  *failure* fails the job before any publish.) **This is an invariant, not a coincidence** — the
  gate's skip expression and the publish expression are different expressions that happen to agree.
  A comment at the gate MUST state the invariant so a future edit to either condition does not
  silently open a publish-without-verify path.

### B — replace the false gate, and stop asserting a false cause

- **FR-B1.** In `.github/actions/cf-tunnel-registry-bridge/action.yml`, replace the `nc -z
  127.0.0.1 5000` readiness gate with a **positive HTTP assertion through the forward**: `GET
  http://127.0.0.1:5000/v2/` must return **200 or 401**. `nc -z` is a false gate — cloudflared opens
  its local listener before the far end is proven reachable, which is exactly how `__run_2` reported
  success while the path was dead. Measured expectation: pre-`docker login` the correct response is
  **401 with `Www-Authenticate: Basic`**; a broken bridge yields a curl transport failure or `000`.
  Reuses the `zot-entry-gate.sh` `manifest_resolves()` precedent shape.
- **FR-B2.** On bridge failure the step MUST dump `/tmp/cloudflared-registry.log` **at the failing
  step**. Today only the `nc -z` timeout path dumps it; the `docker login` path dumped nothing, and
  the four `websocket: bad handshake` lines survived only incidentally in the `if: always()`
  teardown, a step away from the error.
- **FR-B3.** Delete both false claims from the `degraded "bridge"` message at
  `.github/workflows/reusable-release.yml:782`:
  1. *"the tunnel connector serving registry.soleur.ai may lack a private-net route to
     10.0.1.30:5000 (#6416)"* — refuted (F2), and `model.c4:428` records #6416 as closed.
  2. *"the host's atomic GHCR fallback covers the pull"* — false since the PAT was revoked. This is
     the more dangerous of the two: it is the reassurance that made the warning ignorable.
  Replace with the measured cause class (stale CF Access service token after rotation), a pointer to
  `scripts/check-cloudflare-token-drift.sh`, and the correct diagnostic command.
- **FR-B4.** Extend `scripts/check-cloudflare-token-drift.sh` to cover CF **Access service tokens**.
  Two independent defects today: its key enumeration is `grep -oE 'CF_API_TOKEN[A-Z0-9_]*'`, which
  **cannot match** `REGISTRY_PUSH_ACCESS_TOKEN_ID`/`_SECRET` — the very case its own header cites
  first; and `verify_value()` uses `GET /client/v4/user/tokens/verify` with `Authorization: Bearer`,
  which is the **API-token** endpoint and is wrong for a client-id/secret pair. Add a second
  verification arm: present the pair as `CF-Access-Client-Id`/`CF-Access-Client-Secret` to the
  CF-Access-protected hostname; **200 → LIVE, 403 → DEAD**. Keep enumeration Doppler-derived
  (gotcha #4) — match `[A-Z0-9_]*ACCESS_TOKEN_(ID|SECRET)` rather than adding a hardcoded list.
- **FR-B5.** Wire the detector into CI. `grep -rln check-cloudflare-token-drift` currently returns
  **only the script itself** — nothing invokes it, so the class it was written to catch still
  recurs silently. Add it as a scheduled check (and/or a release preflight), non-blocking on
  transient API error (exit 2) and loud on exit 1.
- **FR-B6.** Record the `tcp://`-ingress probe trap in the runbook: a plain HTTPS GET to
  `registry.soleur.ai` returns an empty 200 **by design** and is **not** a health probe. Name the
  correct probe (`cloudflared access tcp` + `GET /v2/`, expect 200/401). This is the misdiagnosis
  that consumed the incident's diagnostic budget.
- **FR-B7 — the truthfulness sweep MUST reach the document the operator actually reads.** Found at
  plan review: my sweep fixed the machine-facing copy (`reusable-release.yml:782`) and the
  architecture-facing copy (`model.c4`) and **missed the operator-facing one**.
  `knowledge-base/engineering/operations/runbooks/zot-registry-revert.md` currently instructs the
  operator, during a zot outage, to delete `ZOT_REGISTRY_URL` from Doppler `prd` so hosts *"fall
  straight through to the unchanged private-GHCR path"*, and reassures them:

  > *"GHCR remains dual-pushed + break-glass through the entire soak (the interim classic PAT stays
  > live until Phase 5.5), so the fallback registry is always warm and current."*

  **That is false as of 2026-07-29**, and it is the single highest-consequence instance of the class:
  a runbook is *instructions*, not a comment, and this one documents a recovery procedure that now
  fails `image_pull_failed`. Deliverable: correct the claim, and add the post-change recovery
  (no bypass on the push path; fix zot or re-land the image, then re-run; re-running is safe because
  the draft is unpublished — R1).

  Sweep scope, verified and bounded: `grep -rniE "break-glass|always warm|fallback registry|PAT stays
  live|atomic GHCR fallback"` over `knowledge-base/engineering`, `.github`,
  `apps/web-platform/infra`, `scripts` returns this runbook, the two `model.c4` descriptions already
  in scope, and `ADR-088`'s "interim GHCR break-glass" phrasing (add a dated note). The
  2026-07-15 post-mortem also carries it and is **deliberately excluded** — a post-mortem is a
  point-in-time record and must not be rewritten, exactly like `**/archive/**`.

### C — stop discarding the pull error

- **FR-C1.** At `apps/web-platform/infra/ci-deploy.sh:1589`, the zot-failure branch MUST log a
  bounded tail of the captured stderr alongside the existing line, using the same shape
  `pull_failure_event` already uses: `tail -c 400 "$perr"`. Newlines must be collapsed so the
  `logger` record stays single-line and Vector-parseable.

## Implementation Phases

Phase order is dependency-directed: the contract-changing edits land before their consumers.

**Phase 0 — preconditions (no writes).**
1. Confirm `crane` persists on `PATH` across steps (`sudo install` to `/usr/local/bin`) and that the
   bridge's `docker login` to `127.0.0.1:5000` persists in `~/.docker/config.json` — both are what
   make a sibling verify step viable.
2. Re-run the two premise probes and paste the output into the PR: GHCR `401`/`403 DENIED`, and the
   `cloudflared access tcp` → `/v2/` → `401` bridge check.
3. Record the harness contract: `extract_run_block "Mirror image GHCR→zot (crane) + cosign-sign the
   zot digest"` — the step name is load-bearing and must not change.

**Phase 1 — FR-C (smallest, independent).** RED: extend `ci-deploy.test.sh` to assert the zot-arm
log line carries the stderr tail. GREEN: implement FR-C1.

**Phase 2 — FR-B1/B2 (bridge gate; contract change).** RED first: a test that a listener which
accepts TCP but resets the stream is now **rejected** (this is the regression the false gate let
through). GREEN: positive `/v2/` probe + failing-step log dump.

**Phase 3 — FR-B3 (truthfulness).** Rewrite the `degraded "bridge"` detail. Re-run the mirror test
to confirm the extracted block still executes (the message is inside the extracted block, so this
phase *does* touch it — assertions on `mirror_status=degraded` are unaffected, but any test
asserting the old message text must be updated).

**Phase 4 — FR-B4/B5 (detector coverage + wiring).** Add the Access-service-token arm with a unit
test for both verdicts; wire into CI.

**Phase 5 — FR-A (the fail-closed gate).** Add the `zot_verify` step per FR-A1–A5. Confirm the
mirror harness is still green **without assertion changes** (FR-A6).

**Phase 6 — ADR-096 amendment + C4 description corrections** (see below).

**Phase 7 — full-suite exit gate.** `plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh`,
`ci-deploy.test.sh`, `actionlint` on the workflow, `bash -c` on extracted `run:` snippets (never
`bash -n` on the YAML).

## Acceptance Criteria

### Pre-merge (PR)

- **AC1.** `.github/workflows/reusable-release.yml` contains a step named
  `Verify zot mirror landed (fail-closed)` with **no** `continue-on-error`, positioned between
  `zot_mirror` and `Tear down cloudflared registry bridge`.
  Verify: `awk '/- name: Verify zot mirror landed/{f=1} f&&/continue-on-error/{print "FOUND"} /- name: Tear down/{f=0}'`
  returns empty.
- **AC2.** The gate asserts digest equality against `steps.docker_build.outputs.digest` (FR-A2) —
  grep the step body for both `crane digest` and `docker_build.outputs.digest`.
- **AC3.** The gate asserts `mirror_status == 'ok'` (FR-A3).
- **AC4.** The gate emits all five `outcome` discriminators (FR-A4). Verify by asserting each of
  `bridge_unreachable`, `crane_missing`, `tag_absent`, `digest_mismatch`, `mirror_degraded` appears
  in the step body.
- **AC5.** The GHCR-coupling comment exists and names both `GHCR_MINTER_DISABLED` and ADR-088
  (FR-A5).
- **AC6.** `bash plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh` **passes**, and
  `git diff origin/main...HEAD -- plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh`
  shows **no change to any assertion** (FR-A6). Comment-only or zero diff is acceptable.
- **AC7.** `nc -z` is gone from the bridge's readiness gate and a `/v2/` probe accepting 200-or-401
  replaces it (FR-B1). Verify: `grep -c 'nc -z' .github/actions/cf-tunnel-registry-bridge/action.yml`
  returns `0`.
- **AC8.** The string `lack a private-net route to 10.0.1.30:5000` appears **0** times in
  `.github/workflows/reusable-release.yml`, and the phrase asserting the GHCR fallback covers the
  pull is likewise gone (FR-B3). *Guard against the self-reference trap: this plan file and the
  learning legitimately quote the old text, so scope the grep to the workflow only.*
- **AC9.** `scripts/check-cloudflare-token-drift.sh` enumerates `*ACCESS_TOKEN_(ID|SECRET)` keys and
  verifies them via `CF-Access-Client-Id`/`-Secret` against a protected hostname, asserting
  **200 → LIVE / 403 → DEAD** (FR-B4). A unit test covers both verdicts with synthesized fixtures
  (`cq-test-fixtures-synthesized-only`).
- **AC10.** `grep -rln check-cloudflare-token-drift .github` returns **≥1** file (FR-B5) — i.e. the
  detector is actually invoked by something.
- **AC11.** `apps/web-platform/infra/ci-deploy.sh` zot-arm logs a bounded stderr tail; `grep -c
  'tail -c 400 "$perr"'` increases by exactly 1 versus `origin/main` (FR-C1).
- **AC12.** `ci-deploy.test.sh` has a case asserting the zot-arm line carries the reason, and it
  passes.
- **AC13.** `actionlint` clean on `reusable-release.yml`; embedded `run:` snippets checked with
  `bash -c`, never `bash -n` on the YAML.
- **AC14.** The gate retries 3× with backoff before failing (FR-A7) — assert the `retry` helper (or
  an equivalent bounded loop) wraps both `crane digest` calls.
- **AC15.** An `if: failure()` step invoking `./.github/actions/notify-ops-email` exists in the
  release job, and its body interpolates the FR-A4 discriminator (FR-A10). The same idiom is present
  in FR-B5's new scheduled workflow.
- **AC16.** Each of the 8 FR-A4 discriminators appears in the step body **paired with its operator
  remedy string**, and the step summary carries the "unpublished draft — re-running is safe" line.
  *Assert the anchor, not the bare token* (`cq-assert-anchor-not-bare-token`): grep for the
  `outcome=<name>` emit site, not the word alone.
- **AC17.** The `signing_failed` message states that the digest is correct and the blocker is the
  signature, and prints the re-sign one-liner (FR-A3).
- **AC18.** The override is `workflow_dispatch`-only and inert without a non-empty reason (FR-A8):
  assert the input exists, that the gate's bypass branch requires it non-empty, and that no
  `push`-triggered path can reach it. Its documentation states the override does not make an
  unmirrored image pullable.
- **AC19.** `zot-registry-revert.md` no longer claims the GHCR fallback is "always warm and current",
  and contains the post-change recovery procedure (FR-B7). Verify with a grep **scoped to that file**
  — this plan and the learning legitimately quote the old text.
- **AC20.** A comment at the gate records (a) the FR-A9 publish-vs-skip invariant and (b) that the
  step must stay **before** the teardown because teardown runs `docker logout 127.0.0.1:5000`.
- **AC21.** The ADR-096 amendment cites ADR-088 arm-b's structural finding (App installation tokens
  are denied `docker pull` on private repo-linked packages) as the basis for rejecting a restored
  GHCR credential, and records the single-pull-path restoration path as open architectural debt with
  trackers.
- **AC22.** The orphan-draft leak is either reaped or explicitly recorded with a tracking issue
  (FR-A11) — not silent.

### Post-merge (operator)

- **AC23.** On the first release after merge, `zot_verify` passes and the Actions log records the
  digest match. **Automation: not feasible pre-merge** — the faithful test of a CI-side bridge is a
  real release, which is a production mutation and is out of scope for this unattended run
  (limitation stated under F2). Per `wg-block-pr-ready-on-undeferred-operator-steps` this MUST become
  a tracked follow-through issue (`runbooks/followthrough-convention.md`) before PR-ready, **not** an
  AC bullet left to memory.

## Observability

```yaml
liveness_signal:
  what: "zot_verify step outcome per release (digest match vs the five failure discriminators)"
  cadence: "every web-platform release (on push to main touching apps/web-platform/**)"
  alert_target: "GitHub Actions failed-workflow notification to ops@jikigai.com; ::error:: annotation + step summary on the run"
  configured_in: ".github/workflows/reusable-release.yml (step id zot_verify)"
error_reporting:
  destination: "GitHub Actions annotation + $GITHUB_STEP_SUMMARY (release job); host-side pull errors to journald -> Vector -> Better Stack"
  fail_loud: true
failure_modes:
  - mode: "bridge unreachable from the runner (stale CF Access token, tunnel down)"
    detection: "bridge step's positive /v2/ probe fails (transport error or code not in {200,401}); cloudflared log dumped at the failing step"
    alert_route: "bridge step fails -> zot_verify fails -> release job fails -> GitHub failed-workflow notification"
  - mode: "crane copy silently mirrored nothing (the v0.244.1 shape)"
    detection: "zot_verify outcome=tag_absent — crane digest against zot cannot resolve v<version>"
    alert_route: "release job fails; deploy is skipped via needs:[release]"
  - mode: "zot copy present but at a different digest"
    detection: "zot_verify outcome=digest_mismatch, expected vs observed both emitted"
    alert_route: "release job fails"
  - mode: "zot copy present at the correct digest but UNSIGNED (cosign sign failed after copy) — the most common blocking arm, since degraded() is a first-failure abort"
    detection: "zot_verify outcome=signing_failed via mirror_status != ok; message states the digest IS correct and the blocker is the signature"
    alert_route: "release job fails -> FR-A10 notify-ops-email carrying the discriminator + remedy"
  - mode: "Sigstore (Fulcio/Rekor) unavailable — a NEW release-blocking third-party dependency introduced by FR-A3, outside the operator's control and unrelated to deployability"
    detection: "zot_verify outcome=signing_failed; remedy line says wait-and-re-run, distinguishing it from a registry fault"
    alert_route: "release job fails -> FR-A10 notify-ops-email; bounded retry (FR-A7) absorbs short blips first"
  - mode: "host cannot pull from zot at deploy time"
    detection: "IMAGE_PULL: zot pull failed ... now carrying the stderr tail (FR-C1), plus pull_failure_event"
    alert_route: "Better Stack (Vector journald source) + Sentry via pull_failure_event"
  - mode: "a Cloudflare token rotation does not propagate to Doppler"
    detection: "scripts/check-cloudflare-token-drift.sh exit 1, now covering Access service tokens (FR-B4) and actually invoked (FR-B5)"
    alert_route: "scheduled workflow failure -> GitHub notification"
logs:
  where: "GitHub Actions run logs (release job); Better Stack Logs source soleur-inngest-vector-prd for host-side IMAGE_PULL_* records"
  retention: "GitHub Actions default retention; Better Stack per existing source retention"
discoverability_test:
  command: "gh run list --workflow=web-platform-release.yml --limit 5 --json databaseId,conclusion && doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --grep IMAGE_PULL --since 24h"
  expected_output: "release runs with conclusion, and IMAGE_PULL_OK/IMAGE_PULL_FAIL records including the stderr tail on any zot miss"
```

No `ssh` in any field. Both channels are reachable without touching a host.

## Architecture Decision (ADR/C4)

This plan reverses a recorded decision, so the ADR and C4 edits are **deliverables here**, not
follow-ups (`wg-architecture-decision-is-a-plan-deliverable`).

### ADR

**Amend ADR-096** (status: *Adopting*). Its `## Decision` states the CI mirror is *"explicitly
non-blocking … a mirror failure degrades zot **redundancy**, never the release/build verdict."* That
reasoning is sound only while GHCR is a working fallback. With the `ghp_` PAT revoked and the minter
deliberately off (ADR-088 arm-b), **zot is not redundant — it is the sole pull path**, so a mirror
miss is a release that cannot deploy.

The amendment must: (a) record the falsified premise with the 401/403 evidence; (b) change the
mirror's status from non-blocking to **release-blocking via a positive post-mirror assertion**; (c)
add to `## Alternatives Considered` the rejected option — *restore a GHCR pull credential and keep
the mirror warn-only*; (d) state the relaxation condition, mirroring FR-A5.

Two corrections from plan review:

- **(c) must be cited structurally, not as operator preference.** My first draft rejected it because
  "the operator deliberately removed a revocable personal PAT." That is a *reversible* reason — a
  future reader could simply re-add one. The real basis is a GitHub-side limitation recorded in
  ADR-088 arm-b and restated in `cron-ghcr-token-minter.ts`'s kill-switch comment: **a GitHub App
  installation token can `docker login` to GHCR but is DENIED `docker pull` of private, repo-linked
  packages.** So *no zero-touch GHCR pull credential exists today* — which also makes FR-A5's
  relaxation condition concrete and testable ("GHCR pull succeeds with a non-personal credential")
  instead of a matter of taste. This also satisfies `hr-github-app-auth-not-pat` rather than
  appearing to violate it.
- **The amendment must frame fail-closed as a MITIGATION for a single-pull-path architecture, not a
  resolution of it.** Marking `ghcr` and `hetzner -> ghcr` as a dead fallback in the C4 model risks
  enshrining single-path as the *intended* design, so that a future reader inherits "one registry, no
  fallback" as a decision rather than a constraint. The amendment must therefore record the
  restoration path — a working non-personal GHCR pull credential, or a second mirror — as **open
  architectural debt**, with #6031 / #6023 as trackers.

No new ADR ordinal is claimed, so there is no collision risk.

### C4 views

All three model files were read. No new element or `view include` is required — every external
system and relationship this change touches is already modeled: `ghcr`, `zotRegistry`, `cloudflare`,
`tunnel`, `github`, `doppler`, `betterstack`, `sentry`, `sigstore`, plus the edges
`github -> tunnel`, `tunnel -> zotRegistry`, `hetzner -> zotRegistry`, `hetzner -> ghcr`. Enumerated
and found already-present: **external human actors** — none new; **external systems/vendors** — none
new; **containers/data stores** — none new (no new store; zot's store is modeled); **access
relationships** — no new actor→surface grant.

Three **descriptions this change falsifies** must be corrected (the mandate requires fixing these,
not only adding elements):

1. `ghcr` (`model.c4:264`) — describes GHCR as the *"DUAL-PUSH + break-glass FALLBACK"*. It is no
   longer a usable fallback: the pull credential is revoked and the minter is disabled. Correct to
   record the fallback as **dead in practice**, with the date.
2. `hetzner -> ghcr` (`model.c4:454`) — *"Atomic fallback pull when zot is unconfigured/unreachable
   — dual-pushed + break-glass through the Phase-5 soak"*. Same falsification; the atomic fallback
   cannot authenticate.
3. `tunnel -> zotRegistry` (`model.c4:428`) — accurate that #6416's mode is closed, but should also
   record the **2026-07-29 cause class** (stale CF Access service token after a Terraform replace)
   so the next reader does not re-derive the refuted route hypothesis.

After editing, run `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` — a
`view include` referencing an undefined element fails there, not at `tsc`.

### Sequencing

The ADR amendment describes the state that is true the moment FR-A merges (the gate blocks
immediately; there is no soak), so it is authored in this PR at full strength — no `adopting` note
needed for the amendment itself.

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Core design endorsed — positive digest equality in a sibling step is the correct
mechanism and no cheaper stronger assertion exists. Both FR-A2 prerequisites verified: `crane`
persists (`sudo install` to `/usr/local/bin`, same job/filesystem) and the zot credential persists in
`~/.docker/config.json`. **New finding: step ordering is mandatory for a second reason** — the
teardown step runs `docker logout 127.0.0.1:5000`, so `zot_verify` must precede it for the
*credential*, not only the tunnel; a future reordering would break it silently. No cloudflared leak
(teardown is `if: always()`). No bootstrap deadlock (workflow files take effect on push, without a
deploy). Findings folded in: R1a (self-heal narrower than claimed), R1c (`:latest`/`:<sha>` orphan
tags, currently harmless), R2 reversal (FR-A10), FR-A3's `IMAGE_VERIFY_MODE=warn` trade, FR-A8
override, FR-A11 orphan-draft leak, the 6b reasoning fix, and the 6d ADR re-citation. One
recommendation escalated to the operator rather than applied unilaterally — see **Sequencing
decision** below.

### Product/UX Gate

**Tier:** none
**Decision:** reviewed
**Agents invoked:** cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

**CPO verdict: SIGN-OFF WITH CONDITIONS.** Threshold `single-user incident` **sustained**, with the
justification re-framed (the first draft argued only the fail-open direction — the direction that
favoured the chosen design); tier **NONE confirmed** (no `components/**/*.tsx`, no `app/**/page.tsx`,
no user-visible copy — the change does alter the operator's *failure* UX, but that surface is governed
by observability/runbook quality, not visual design, so it redirects to FR-A4/FR-B7 rather than a
`.pen`). Conditions folded in: C1 → **FR-B7** (the dead escape hatch in `zot-registry-revert.md` —
the material gap: my truthfulness sweep reached the code and the model but not the document the
operator reads during an outage); C2 → FR-A4's remedy column + the "nothing was half-shipped" line;
C3 → FR-A3's disclosed Sigstore dependency and the `signing_failed` split; C4 → AC14 converted to a
tracked follow-through plus the explicit residual-action note below.

**Residual action after this merges (must be stated to the operator):** disabling the compromised
legacy Supabase `service_role` key remains **OPEN**. This PR is a *prerequisite* for that
remediation, not the remediation itself.

### Sequencing decision — operator's call, deliberately not made here

The CTO's highest-value structural finding: because this branch edits
`apps/web-platform/infra/ci-deploy.sh`, which matches `on.push.paths: apps/web-platform/**`, **merging
it is itself the first-ever execution of both the new gate (FR-A) and the new bridge probe (FR-B1)**.
FR-B1 has **zero runner-side evidence** (F2's honest limitation — the probe was validated from a
laptop), and it composes into the gate: a stricter bridge gate → `zot_bridge` failure → `degraded
"bridge"` → FR-A3 blocks the release. One false negative in an unvalidated probe would block the
release train, including the credential remediation.

The CTO recommends a **two-PR split**: PR 1 = the non-gating set (FR-C, FR-B2, FR-B3, FR-B4/B5,
FR-B6, FR-B7, ADR + C4), whose own release exercises the runner-side bridge path for real; PR 2 = the
two gating changes (FR-A, FR-B1), landed once PR 1's release has proven the bridge works from a
runner.

**This plan does not unilaterally adopt the split**, because doing so would move the task's headline
deliverable (A) out of this PR — a scope reduction that is the operator's decision, not the agent's.
All of A/B/C is therefore planned and implemented on this branch, and because the run stops before
`/ship`, the operator chooses at ship time. The Phase order already separates the gating from the
non-gating work, so the split costs one branch if elected.

## Infrastructure (IaC)

**Skipped, with reason.** This plan introduces **no** new infrastructure: no server, service, cron,
vendor account, DNS record, cert, secret, or firewall rule. The tunnel ingress, DNS record, CF Access
application, and service token all already exist and were verified correct against the live API
(F2). No `.tf` file is edited, so `apply-web-platform-infra.yml` does not fire. **No `terraform
apply`, no Cloudflare write, and no Doppler write is required by this plan** — which satisfies the
unattended constraint by construction rather than by deferral. FR-B5's CI wiring is a workflow file,
not a provisioned resource.

## Encryption Posture

**Skipped, with reason.** No persistent data store is introduced and no new cross-component
connection is created. The `/v2/` probe (FR-B1) travels the **existing** `cloudflared access tcp`
bridge — the same connection the step already opened — and reads no data. zot's own at-rest posture
is unchanged and remains governed by ADR-140 / `encryption-posture-ledger.json`.

## GDPR / Compliance Gate

**Skipped, with reason.** No regulated-data surface is touched: no schema, migration, `.sql`, auth
flow, or API route. None of the expansion triggers fire — no LLM/external-API processing of
operator-session data, no new cron reading `learnings/` or `specs/`, no new artifact-distribution
surface. (The `single-user incident` threshold trigger is noted; it is satisfied by the
`user-impact-reviewer` invocation at review time rather than a data-protection assessment, because
this change moves no personal data.)

## Open Code-Review Overlap

**None.** Queried 60 open `code-review` issues; none names any of the five planned files
(`reusable-release.yml`, `cf-tunnel-registry-bridge/action.yml`, `ci-deploy.sh`,
`check-cloudflare-token-drift.sh`, `reusable-release-zot-mirror-retry.test.sh`).

## Files to Edit

- `.github/workflows/reusable-release.yml` — new `zot_verify` step (FR-A1–A9); `if: failure()`
  notify step (FR-A10); `workflow_dispatch` override input (FR-A8); rewrite the `degraded "bridge"`
  detail (FR-B3).
- `knowledge-base/engineering/operations/runbooks/zot-registry-revert.md` — correct the false
  GHCR-fallback reassurance + add the post-change recovery procedure (FR-B7, FR-B6).
- `knowledge-base/engineering/architecture/decisions/ADR-088-…private-ghcr-reads.md` — dated note on
  the "interim GHCR break-glass" phrasing (FR-B7 sweep).
- `.github/actions/cf-tunnel-registry-bridge/action.yml` — positive `/v2/` gate replacing `nc -z`
  (FR-B1); dump cloudflared log at the failing step (FR-B2).
- `apps/web-platform/infra/ci-deploy.sh` — log bounded `$perr` tail on the zot arm (FR-C1).
- `apps/web-platform/infra/ci-deploy.test.sh` — assertion for FR-C1.
- `scripts/check-cloudflare-token-drift.sh` — Access-service-token arm (FR-B4).
- `.github/workflows/` (one scheduled workflow) — invoke the detector (FR-B5).
- `knowledge-base/engineering/architecture/decisions/ADR-096-…zot.md` — amendment.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — three description corrections.
- A runbook under `knowledge-base/engineering/operations/runbooks/` — the `tcp://` probe trap
  (FR-B6).

## Files to Create

- A test for the detector's Access-token arm (alongside `scripts/`, following the repo's
  `*.test.sh` convention).
- `knowledge-base/project/learnings/` — the misdiagnosis learning (see Risks).

## Risks & Mitigations

- **R1 — a zot outage now blocks releases.** Accepted and intended: with GHCR dead, a release that
  cannot land in zot is a release that cannot deploy, so blocking at the release is strictly better
  than publishing an undeployable version. **No version drift accrues** — verified: `steps.version`
  derives `next` from `git tag --list "${TAG_PREFIX}*"`, and a draft materializes no git tag until
  `gh release edit --draft=false` runs (*"on a draft it publishes (materializing the git tag)"*). The
  gate sits **before** `Finalise release (publish draft)`, so a blocked release leaves an unpublished
  draft and **no tag**, and the version number is not consumed.
- **R1a — the #4902 self-heal is NARROWER than first stated (corrected at plan review).** My initial
  claim that "a later green re-run publishes it" is true **only when the later run recomputes the
  identical tag**. Two gaps, both real:
  1. *Same bump type* (blocked `patch` → next PR `patch`): `draft_exists=true`, so the draft is
     republished — but `Finalise release` only runs `gh release edit --draft=false` and **never
     rewrites the notes**. The published release then carries the **first** PR's changelog while the
     image contains both. Stale release notes, silently.
  2. *Different bump type* (blocked `patch` → next PR `minor`): `idempotency` computes a different
     tag, misses the orphan, `draft_exists=false`, and a new draft is created. **The original draft
     is never published and never cleaned up** — an accumulating orphan.
  Additionally, `check_changed` gates the job on the path filter, so a **docs-only** follow-up merge
  does not trigger a self-heal run at all; recovery is re-running the failed run or
  `workflow_dispatch`. The plan therefore names the orphan-draft leak explicitly rather than implying
  a clean self-heal, and FR-A11 covers it.
- **R1c — a blocked release leaves `:latest` and `:<sha>` pushed to both registries** pointing at a
  build with no published release (`docker_build` and `zot_mirror` both run *before* the gate).
  Verified currently harmless: nothing on the deploy path pulls `:latest` or `:<sha>` (no hits in
  `ci-deploy.sh`, `zot-entry-gate.sh`, or the cloud-init bootstraps — every pull is digest- or
  `v<version>`-addressed). Recorded so it **stays** harmless; a future consumer of `:latest` would
  turn this into a real hazard.
- **R1b — bootstrap deadlock: analysed, and the gate does not create one.** `ci-deploy.sh` is baked
  into the image (`COPY … /opt/soleur/host-scripts/`), so a fix to the pull path needs a new image,
  which needs a release. If zot were unreachable, could the gate block the very release that fixes
  it? **The deadlock pre-exists the gate**: with GHCR's pull credential revoked, a new image cannot
  reach production while zot is down *whether or not* the release publishes — today it simply fails
  later, at `deploy`, having published a version that never shipped. Three properties keep the
  escape hatches open: (i) `docker_build` runs **before** the gate, so the image is still pushed to
  GHCR at a known digest and nothing is lost; (ii) infrastructure fixes do **not** traverse this
  pipeline (`apply-web-platform-infra.yml` and the guarded `workflow_dispatch` routes are
  unaffected), so zot itself can be repaired while releases are blocked; (iii) the documented
  `crane copy` + `cosign sign` backfill re-lands the image in zot, after which a re-run publishes via
  the self-heal path. **FR-A4 is therefore extended:** the gate's failure record MUST print that exact
  backfill command, so the escape hatch is self-documenting at the point of failure rather than
  something the operator must go and find.
- **R2 — REVERSED at plan review; the failure notification is now in scope (FR-A10).** I originally
  deferred this as "a reasonable follow-up [that] widens this PR's surface." That was backwards.
  Both `Post to Slack (release)` and `Email notification (release)` gate on
  `create_release.released == 'true' || idempotency.draft_exists == 'true'` with **no status
  function**, so GitHub ANDs an implicit `success()` and **neither fires on a blocked release**. The
  only remaining signal is GitHub's own failed-workflow email, which routes to the run's *triggering
  actor* — on a merge-triggered push that may be a GitHub App identity (`hr-github-app-auth-not-pat`),
  i.e. **nobody**. Meanwhile `if: failure()` + `./.github/actions/notify-ops-email` is the
  **established idiom in this repo** (present in `weakness-miner.yml`, `rule-audit.yml`,
  `rule-metrics-aggregate.yml`, `scheduled-terraform-drift.yml`, `scheduled-realtime-probe.yml`,
  `post-merge-monitor.yml`, `scheduled-supabase-advisor-scan.yml`), so **omitting it was the
  deviation**, not adding it. ~8 lines reusing a composite this file already calls.
- **R3 — a spuriously-failing gate could block a healthy release.** Mitigated by choosing assertions
  with no trust configuration: `crane digest` equality needs no cosign root, no identity regexp, and
  no new credential. Signature correctness is delegated to the existing `mirror_status` signal rather
  than re-verified in CI.
- **R4 — editing the extracted `run:` block (Phase 3) could break the harness.** The harness matches
  the literal step **name**, which is unchanged; only message text inside the block changes. AC6
  gates on the harness passing with no assertion churn.
- **R5 — the bridge probe's expected-status set could be wrong on a future zot config.** The 200-or-401
  set is measured, not assumed (F2). If zot's access control changes, the probe fails closed, which
  is the safe direction.
- **R6 — the misdiagnosis recurs.** The empty-200 trap cost this incident its diagnostic budget and
  was *caused by* a false comment in the repo. FR-B3 deletes the false claim and FR-B6 records the
  correct probe. A learning file captures the general lesson: **a comment that names a root cause is
  a claim to verify, not a fact to route on** — here it survived long enough to mislead the operator
  into probing a `tcp://` ingress with HTTP.

## Alternatives Considered

| Alternative | Verdict |
|---|---|
| Make `degraded()` exit non-zero and drop `continue-on-error` from `zot_mirror` | **Rejected.** Trusts the step's own exit path — the precise signal the task calls untrustworthy — and forces churn in the harness that executes the block verbatim. |
| Gate on `steps.zot_mirror.outputs.mirror_status` alone | **Rejected as primary.** It is self-report. Used only as suspenders (FR-A3) behind the independent digest assertion. |
| Restore a GHCR pull credential and keep the mirror warn-only | **Rejected** (also recorded in the ADR amendment). The operator deliberately removed a revocable personal PAT from the deploy critical path; a replacement recreates the fragility a rotation just broke. |
| Change the tunnel ingress from `tcp://` to `http://` so `curl` works | **Rejected.** `tcp://` is the deliberate design (`action.yml` header, ADR-096); the empty 200 is a probe error, not an origin defect. Changing it would also be a production Cloudflare mutation. |
| Full `cosign verify` in the new gate | **Rejected.** Needs trust-root/identity configuration in CI and risks spuriously failing releases (R3). `mirror_status` already discriminates the unsigned state. |
| Remove `lifecycle { ignore_changes = [value] }` so Terraform propagates rotations | **Rejected**, consistent with `check-cloudflare-token-drift.sh`'s own reasoning: it trades silent staleness for a churn bug the comments say was already hit. Detection is the safer fix — but it must actually *cover* Access tokens and actually *run* (FR-B4/B5). |
| Defer B to a staged Terraform change for operator apply | **Unnecessary.** No infrastructure defect exists (F2). |

## Test Scenarios

1. Bridge opens a listener but the stream resets → **bridge step fails** (regression the old `nc -z`
   gate passed), cloudflared log dumped at the failing step.
2. Bridge healthy, unauthenticated `/v2/` → `401` → probe **passes**.
3. `crane copy` mirrored nothing → `zot_verify` → `tag_absent` → release job **fails**, deploy
   skipped.
4. zot holds the tag at a different digest → `digest_mismatch`, both digests emitted.
5. Copy of `v<version>` landed at the correct digest, then the `<sha>` or `latest` arm failed so
   `cosign sign` never ran → `signing_failed` → **fails**, with a message stating the digest is
   correct and printing the re-sign one-liner.
5b. Transient failure on attempt 1 that succeeds on attempt 2 → bounded retry absorbs it → **passes**
   (no blocked release for a single TCP reset).
5c. `workflow_dispatch` with an empty reason → override inert, gate still **fails**. With a non-empty
   reason → warning + notification + `action-required` issue, release proceeds.
6. Happy path → digest match + `mirror_status=ok` → release publishes and deploys.
7. `docker_build` skipped (docs-only release) → `zot_verify` skipped, release unaffected.
8. Detector: a dead Access service token (`403`) → exit 1 naming key + config; a live one (`200`) →
   LIVE.
9. `ci-deploy.sh` zot arm fails → log line carries a bounded, single-line stderr tail.
10. Mirror harness passes unchanged (FR-A6/AC6).
