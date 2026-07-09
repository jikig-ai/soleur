---
title: "fix(release): make GHCR→zot mirror step non-release-blocking + observable"
issue: 6274
type: bug-fix
classification: infra-ci
lane: single-domain
brand_survival_threshold: none
requires_cpo_signoff: false
date: 2026-07-09
branch: feat-one-shot-6274-zot-mirror-nonblocking
---

# 🐛 fix(release): GHCR→zot mirror step reds every release after a successful deploy

## Overview

The `web-platform-release` → `release / release` job's **"Mirror image GHCR→zot
(crane) + cosign-sign the zot digest"** step (`.github/workflows/reusable-release.yml:669`)
fails with `connection reset by peer` mid blob-upload and **reds the whole release
job** — even though the primary deploy (`deploy` + `live-verify`) already SUCCEEDED
(prod pulled from GHCR, `/health` = 200, feature is live). The zot mirror is a
**secondary/shadow copy** during the ADR-096 soak (GHCR is still primary + break-glass
warm), so its failure must never fail a successful release.

**Root cause (confirmed):** the guard is incomplete. The **Bridge to zot registry**
step (`reusable-release.yml:655`) has `continue-on-error: true`, but the **Mirror**
step (line 669) is only gated on `if: steps.zot_bridge.outcome == 'success'` and
**lacks `continue-on-error: true`**. With `set -euo pipefail` (line 677) and no
built-in retry in `crane`, a single mid-blob TCP reset over the multi-hop CF-tunnel
bridge exits 1 → the `release / release` job concludes `failure`. The block's own
comment (lines 651-652) already states the intent — *"a zot/bridge failure must not
fail the GHCR release"* — but the code only delivers that guarantee for the bridge,
not the mirror.

**Sibling site:** `.github/workflows/build-inngest-bootstrap-image.yml:240` has the
identical bug — the inngest-bootstrap mirror (`docker push`, line 252) is bridge-gated
but lacks `continue-on-error: true` and runs under `set -euo pipefail`. Same failure
class; folded into this PR.

**Fix shape:** make both mirror steps non-release-blocking (`continue-on-error: true`
+ belt-and-suspenders exit-0 inner shell, mirroring the in-workflow Sentry-audit
precedent at `reusable-release.yml:362-415`), add a **bounded retry** around the
network ops to self-heal transient resets, and — because a green release must NOT
silently swallow a degraded mirror — emit an **operator-visible degraded signal**
(`::warning::` + step summary + `mirror_status` output threaded into the existing Slack
release notification). This is consistent with ADR-096's "Loud, no-SSH signal" axis and
fills the currently-empty mirror-staleness observability gap.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (verified) | Plan response |
|---|---|---|
| Issue: "make the mirror step non-blocking (or self-heal)" | The block was *designed* non-blocking but the guard covers only the bridge step, not the mirror (`reusable-release.yml:669` has no `continue-on-error`). | Add `continue-on-error` + exit-0 shell to the mirror step; do BOTH non-blocking AND retry (self-heal transient). |
| Issue hypothesizes "disk-full again or tunnel/token flaked" | #6240 (CLOSED) already root-caused a prior recurrence (`zot 500` blob-upload) to **filesystem disk-full**; PR #6246 shipped `SOLEUR_ZOT_DISK` df% telemetry + fail-loud `resize2fs`. This recurrence is `connection reset`, a different error mode on the same flaky secondary path. | This PR does NOT re-fix the root cause (that is #6246's layer). It **decouples the release verdict** from the inherently-flaky secondary mirror + makes any miss observable. Recurring-symptom discipline: fix the right layer, not a 3rd root-cause patch. |
| ADR-096: does it require a blocking mirror? | No. ADR-096 (status: **Adopting**, soak phase) §Cold-boot-dependency mandates *"a zot outage degrades latency, not availability"* + *"Loud, no-SSH signal"*. Pull-side (`ci-deploy.sh` `pull_image_with_fallback`) does an **atomic GHCR fallback** on any zot miss. | Non-blocking is fully consistent with ADR-096. Amend ADR-096 with a one-line note that the mirror push is explicitly non-blocking + names the CI degraded signal. |
| Existing observability catches a stale/missing mirror | **No.** All zot signals are HOST-down / DISK-full / (post-hoc) soak-gate. There is NO live signal when a *mirror* silently fails. ADR-096 line 78 claims a `>3/1h` fallback-rate Sentry alarm, but it is **not provisioned** (design intent, unwired). | This PR adds the CI-level degraded signal (Slack + `::warning::`). The live mirror-staleness Sentry alert rule (terraform) is a separate IaC follow-up (deferred issue). |
| Is the miss self-healing? | Runtime *availability* yes (atomic GHCR fallback). The *per-version zot tag* is NOT: the mirror only copies the current release's tags; a future release copies its own version, never backfills the skipped `vX.Y.Z`. `latest` is overwritten; the pinned version stays absent until an operator `crane copy` backfill. | Retry self-heals transient within-run; the observable signal prompts operator backfill for a persistent miss; the pre-flip `zot-entry-gate.sh` / `zot-soak-6122.sh` gates catch it before cutover. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — the operator
keeps seeing every release run red after a successful deploy (a false-alarm pipeline
signal that erodes trust in "green = shipped").
**If this leaks, the user's data/workflow is exposed via:** no exposure vector.
During the ADR-096 soak GHCR is primary + break-glass warm and the pull-side does an
atomic GHCR fallback on any zot miss, so a silently-missing zot mirror degrades
redundancy/latency, never availability. (Post-soak, once GHCR push is retired, a
silent miss *could* gate a boot — which is exactly why the observable degraded signal
is load-bearing, and why the pre-flip entry-gate/soak-gate exist.)
**Brand-survival threshold:** none — secondary/shadow registry copy behind an atomic
GHCR fallback; no user-facing surface.

- `threshold: none, reason: CI release-workflow failure-semantics change; the secondary
  zot mirror is non-user-facing (GHCR primary + break-glass during the ADR-096 soak,
  atomic pull-side GHCR fallback). No schema/auth/API/PII surface touched.`

## Hypotheses

*Triggered by the `connection reset` / `reset by peer` keyword match. The deliverable
is decoupling the release verdict from the mirror, NOT a network/sshd fix — so no
service-layer fix is proposed. Live triage (if the mirror keeps failing post-fix) routes
through the existing **no-SSH** observability below, never SSH (`hr-no-ssh-fallback-in-runbooks`).*

The failing path is **not SSH** — it is a plain-TCP-over-CF-tunnel blob PUT:
`GH runner → cloudflared access tcp (127.0.0.1:5000) → CF Access edge → web-host
cloudflared → zot (10.0.1.30:5000)`. L3→L7 layers, verification via no-SSH artifacts:

1. **L3 — Firewall / ingress.** The registry host is deny-all-public; the CF Tunnel is
   the only ingress (ADR-096). Nothing to open/diff on a client egress IP (unlike the
   SSH case). CF Access service token = `REGISTRY_PUSH_ACCESS_TOKEN_ID/_SECRET` (Doppler
   `prd`). Verify via the **bridge step logs** (`cf-tunnel-registry-bridge` action emits
   `::error::` on token/listener failure) — the bridge step already `continue-on-error`s
   and succeeds here (the failure is in the *mirror* step), so L3 ingress is confirmed up.
2. **L3 — DNS/routing.** `registry.${APP_DOMAIN_BASE}` resolves via Cloudflare; the
   bridge readiness check (listener opens within 15s) passing confirms routing to the edge.
3. **L7 — TLS/proxy.** CF Access edge terminates; zot is plain-HTTP on the private net
   (integrity via cosign digest-pinning, not TLS — ADR-096 Edge A/B). A mid-stream reset
   on a multi-MB blob PUT is the CF-edge idle/rebalance or web-host cloudflared restart
   dropping a long-lived stream — no application-level retry exists in `crane`, so one
   reset fails the whole copy.
4. **L7 — Application (zot host).** The known recurring cause is **filesystem disk-full**
   (#6240/#6246). Verify **without SSH** via `scripts/betterstack-query.sh --grep
   SOLEUR_ZOT_DISK` (df% telemetry, #6246) and the Better Stack `registry_disk_prd`
   heartbeat (`zot-registry.tf:369+`, pings only while `/var/lib/zot` < 85%). Absence of
   a disk alert during a mirror failure ⇒ the cause is the L7 stream reset (transient),
   which the retry loop is designed to clear.

**Opt-out on live host triage:** part (a) of the issue's ask ("confirm zot host disk +
cloudflared token/tunnel health") is a live diagnostic that this durable code change does
not require — the existing #6246/#6238 no-SSH observability owns it, and the retry +
non-blocking + degraded-signal change makes the release resilient regardless of which L7
cause fires. If the mirror keeps failing after this PR, triage via the L4 above.

## Implementation Phases

> **Phase order is load-bearing:** the mirror step's `id:` + `mirror_status` output
> (Phase 1) must exist before the Slack step consumes it (Phase 2).

### Phase 0 — Preconditions (verify before editing)
- [ ] `actionlint` available (`command -v actionlint` or `go run github.com/rhysd/actionlint/cmd/actionlint@latest`); if absent, install per repo convention. Do NOT use `bash -n <file.yml>` (parses YAML header as bash — Sharp Edge).
- [ ] Confirm the two mirror steps still lack `continue-on-error` on the working tree (`grep -n 'continue-on-error' .github/workflows/reusable-release.yml` around the mirror step at 669; same for inngest at 240).
- [ ] Confirm the Slack step id/shape: `reusable-release.yml:765-836` ("Post to Slack (release)", `continue-on-error: true`, gated on `released == 'true'`, builds mrkdwn payload).

### Phase 1 — `reusable-release.yml`: mirror step non-blocking + retry + degraded signal
File: `.github/workflows/reusable-release.yml` (mirror step 669-702)
- [ ] Add `id: zot_mirror` and `continue-on-error: true` to the "Mirror image GHCR→zot" step (belt).
- [ ] Restructure the inner `run:` to the belt-and-suspenders pattern used by the Sentry-audit step (362-415):
  - Change `set -euo pipefail` → `set -uo pipefail` (drop `-e`; every failure path exits 0).
  - Add a bounded retry helper around the network ops (transient self-heal). Shape:
    ```bash
    retry() {  # 3 attempts, backoff 5s then 15s
      local n=1 max=3; local -a sleeps=(0 5 15)
      until "$@"; do
        rc=$?
        if (( n >= max )); then return "$rc"; fi
        echo "::notice::zot mirror attempt ${n}/${max} failed (rc=${rc}); retrying in ${sleeps[$n]}s"
        sleep "${sleeps[$n]}"; n=$(( n + 1 ))
      done
    }
    ```
  - Wrap each idempotent op: `retry crane copy "${IMAGE}:${TAG}" "${ZOT}:${TAG}"` (per-tag loop preserved — crane skips already-uploaded blobs, so a retry is cheap) and `retry cosign sign --yes "${ZOT}@${DIGEST}"`. Capture `set +e` / rc / `set -e` around the guarded block (suspenders), matching lines 400-408.
  - On overall failure: `echo "mirror_status=degraded" >> "$GITHUB_OUTPUT"`, `echo "::warning::zot mirror degraded for ${ZOT} (rc=${rc}) — release UNAFFECTED (GHCR primary/break-glass); zot redundancy reduced, backfill via 'crane copy GHCR→zot'. If disk-full: see SOLEUR_ZOT_DISK / registry_disk_prd."`, append the same line to `"$GITHUB_STEP_SUMMARY"`, then `exit 0`.
  - On success: `echo "mirror_status=ok" >> "$GITHUB_OUTPUT"` and a one-line confirmation.
- [ ] Leave the `if: steps.zot_bridge.outcome == 'success'` guard AND the `if: always()` teardown (704-713) unchanged (a skipped mirror when the bridge failed must still set no output — reference `steps.zot_mirror.outputs.mirror_status || ''` defensively downstream).

### Phase 2 — `reusable-release.yml`: surface the degraded mirror to the operator (Slack)
File: `.github/workflows/reusable-release.yml` (Slack step 765-836)
- [ ] In the "Post to Slack (release)" payload construction, when
  `steps.zot_mirror.outputs.mirror_status == 'degraded'`, append a line to the release
  message: `⚠️ zot mirror degraded — release OK (GHCR primary), zot redundancy reduced; backfill needed.`
  Use a shell conditional that reads the output env; keep the payload valid mrkdwn (reuse
  the existing converter path). Non-degraded (ok / empty) → no extra line.
- [ ] Do NOT gate the Slack step itself on mirror status — it stays gated on
  `released == 'true'`; the mirror line is additive to the existing message.

### Phase 3 — `build-inngest-bootstrap-image.yml`: sibling non-blocking + retry + signal
File: `.github/workflows/build-inngest-bootstrap-image.yml` (mirror step 240-253)
- [ ] Add `id: zot_mirror` + `continue-on-error: true` to "Mirror inngest image GHCR→zot".
- [ ] Same belt-and-suspenders restructure: `set -uo pipefail`, `retry docker tag ...` (local, cheap) + `retry docker push "$ZOT:$TAG"`, on failure `::warning::` + `$GITHUB_STEP_SUMMARY` + `mirror_status=degraded` + `exit 0`; on success `mirror_status=ok`.
- [ ] **Deliberate scope decision (documented):** this workflow has **no Slack step** and
  fires on inngest-bootstrap infra changes (not a per-release operator event), so its
  degraded signal is `::warning::` + step summary only (the operator watches the run they
  triggered). Not adding a Slack post here = avoiding scope creep / a new secret wiring.

### Phase 4 — ADR-096 amendment (Architecture Decision deliverable)
File: `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`
- [ ] Under the **Cold-boot-dependency statement → "Loud, no-SSH signal"** axis (lines
  ~76-79), append a one-line note: the CI dual-push mirror step is **explicitly
  non-blocking** (`continue-on-error` + exit-0 + bounded retry); a persistent mirror miss
  emits a CI-level degraded signal (`mirror_status` → Slack release message + `::warning::`
  / step summary), and the not-yet-provisioned live fallback-rate Sentry alarm is tracked
  separately (Phase 6 follow-up). Status stays **Adopting** (no decision reversal — this
  brings the code in line with the ADR's existing latency-not-availability semantics).

### Phase 5 — Tests
- [ ] `actionlint .github/workflows/reusable-release.yml .github/workflows/build-inngest-bootstrap-image.yml` — YAML + embedded-shell lint (workflows, not composite actions).
- [ ] Extract the `retry` helper + guarded block into a `bash -c` harness with a stub
  `crane`/`docker`/`cosign` on `PATH` and a temp `GITHUB_OUTPUT`/`GITHUB_STEP_SUMMARY`:
  - **T1 (persistent fail):** stub always exits 1 → assert the loop runs exactly 3
    attempts, writes `mirror_status=degraded`, emits `::warning::`, and the harness exits **0**.
  - **T2 (transient self-heal):** stub fails attempt 1 then succeeds → assert `mirror_status=ok`, exit 0, no `::warning::`.
  - **T3 (happy path):** stub succeeds first try → `mirror_status=ok`, exit 0.
- [ ] Place the harness as `plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh`,
  following the existing `plugins/soleur/test/reusable-release-idempotency.test.sh`
  convention (a `.test.sh` that extracts and exercises this workflow's shell). Do NOT
  introduce a new framework.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1: `grep -c 'continue-on-error: true' .github/workflows/reusable-release.yml` increases by 1 vs origin/main, and the new occurrence is within the "Mirror image GHCR→zot" step (verify by reading the step block, not count alone).
- [ ] AC2: `build-inngest-bootstrap-image.yml` "Mirror inngest image" step has `continue-on-error: true` + `id: zot_mirror` (read the block).
- [ ] AC3: Both mirror steps' inner shells use `set -uo pipefail` (NOT `-euo`) and end every failure path with `exit 0`; a `grep -n 'set -euo pipefail' <both files>` shows the mirror steps no longer match.
- [ ] AC4: `actionlint` passes on both files (exit 0).
- [ ] AC5: Retry-helper unit harness T1/T2/T3 all pass (persistent→degraded+exit0, transient→ok, happy→ok).
- [ ] AC6: The Slack payload in `reusable-release.yml` conditionally appends the "zot mirror degraded" line on `mirror_status == 'degraded'` (read the step); default path emits no extra line.
- [ ] AC7: ADR-096 contains the non-blocking + degraded-signal amendment line under the "Loud, no-SSH signal" axis; status remains `Adopting`.
- [ ] AC8: PR body uses `Closes #6274` (this is a code change that closes at merge — NOT ops-remediation; the fix ships in the workflow file itself).

### Post-merge (verification — automatable, no operator SSH)
- [ ] AC9: On the first release run after merge, the `release / release` job concludes
  `success` even if the mirror step reports degraded. Verify: `gh run list --workflow
  web-platform-release.yml --limit 1 --json conclusion,databaseId` → `success`; and
  `gh run view <id> --log | grep -E 'zot mirror|mirror_status'` shows either a clean copy
  or the `::warning::` degraded line (never a job-failing exit). (Automatable via `gh`.)

## Open Code-Review Overlap

None. Queried 62 open `code-review` issues; zero reference
`reusable-release.yml` or `build-inngest-bootstrap-image.yml`.

## Observability

```yaml
liveness_signal:
  what: "release / release job conclusion + mirror_status step output"
  cadence: "every web-platform-release run (on merge to main touching apps/web-platform/**)"
  alert_target: "Slack #releases (operator-visible) + GitHub Actions run annotations"
  configured_in: ".github/workflows/reusable-release.yml (mirror + Slack steps); host liveness in apps/web-platform/infra/zot-registry.tf (Better Stack registry_prd / registry_disk_prd heartbeats)"
error_reporting:
  destination: "GitHub Actions ::warning:: + $GITHUB_STEP_SUMMARY (both workflows) AND the Slack release notification (reusable-release only)"
  fail_loud: "a persistent mirror failure surfaces as a Slack ⚠️ line on the release message; the release job stays green (deploy unaffected). NOT silently swallowed."
failure_modes:
  - mode: "transient connection reset mid-blob-upload"
    detection: "retry ::notice:: attempt lines in the run log; mirror_status=ok after self-heal"
    alert_route: "none (recovered within run)"
  - mode: "persistent mirror failure (disk-full / tunnel down / cosign fail)"
    detection: "mirror_status=degraded → ::warning:: + step summary + Slack ⚠️ line; corroborate disk via SOLEUR_ZOT_DISK / Better Stack registry_disk_prd heartbeat"
    alert_route: "Slack #releases + (disk) Better Stack → ops@jikigai.com"
  - mode: "bridge step fails (tunnel/token) → mirror skipped"
    detection: "steps.zot_bridge.outcome == 'failure' (already continue-on-error); mirror step skipped, no mirror_status set"
    alert_route: "Actions run annotations (bridge action ::error::)"
logs:
  where: "GitHub Actions run logs (retry attempts, crane/cosign/docker output, if:always() teardown tails /tmp/cloudflared-registry.log)"
  retention: "GitHub Actions default (90 days)"
discoverability_test:
  command: "gh run view <release-run-id> --log | grep -E 'zot mirror|mirror_status'   # plus: check Slack #releases for the ⚠️ line; scripts/betterstack-query.sh --grep SOLEUR_ZOT_DISK"
  expected_output: "mirror degradation is visible (Slack line + ::warning::) with the release job still green — no SSH required"
```

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-096** (`ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`) —
one-line note under the "Loud, no-SSH signal" cold-boot axis that the CI mirror push is
explicitly non-blocking with a CI-level `mirror_status` degraded signal. This is a
clarification/alignment, NOT a decision reversal (the ADR already commits to
"latency, not availability" + a loud signal). Status stays `Adopting`. No new ADR.

### C4 views
**No C4 impact** — verified against all three model files. The relevant systems are
already modeled: `ghcr` (`model.c4:254`, "DUAL-PUSH + break-glass FALLBACK"),
`zotRegistry` (`model.c4:258`), and `github`/CI; both appear in `views.c4:14,36`. This
change alters a **CI failure-handling semantic** on the already-modeled CI→zotRegistry
dual-push edge — it adds/removes no external human actor, no external system, no
container/data-store, and no actor↔surface access relationship. Nothing to add or
re-render.

### Sequencing
None — the ADR amendment describes the current (already-adopting) target state and ships
in this PR.

## Domain Review

**Domains relevant:** none

Infrastructure/tooling change — `.github/workflows/*.yml` + one ADR markdown edit. No
user-facing surface (mechanical UI-surface scan of Files-to-Edit: no
`components/**`, `app/**/page.tsx`, or `app/**/layout.tsx` match → Product NONE). No
finance/legal/marketing/sales/support implications. CTO lens is carried by the plan body
(root-cause layering vs #6246, ADR-096 consistency, observability gap).

## Files to Edit
- `.github/workflows/reusable-release.yml` — mirror step (669-702): `continue-on-error` + `id` + retry + exit-0 + degraded signal; Slack step (765-836): conditional degraded line.
- `.github/workflows/build-inngest-bootstrap-image.yml` — mirror step (240-253): `continue-on-error` + `id` + retry + exit-0 + degraded signal.
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` — non-blocking + degraded-signal amendment.

## Files to Create
- `plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh` — retry-helper unit harness (T1/T2/T3), following the `plugins/soleur/test/reusable-release-idempotency.test.sh` convention.

## Deferred / Follow-up
- **Live zot mirror-staleness Sentry alert rule** (the `>3/1h` fallback-rate alarm
  ADR-096 line 78 *claims* but does not provision). This is separate IaC (a
  `sentry_issue_alert` in `apps/web-platform/infra/sentry/issue-alerts.tf` matching
  `feature:supply-chain op:image-pull registry:"ghcr-fallback"`), out of scope for the
  non-blocking fix. **Action:** file a GitHub issue (labels `observability`,
  `domain/engineering`, `deferred-automation`, `priority/p3-low`) with re-eval criterion:
  "provision before the ADR-096 Phase-5 cutover retires GHCR push (milestone: registry
  cutover)". A missing live alert is acceptable during soak (GHCR break-glass warm);
  it becomes load-bearing at cutover.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails
  `deepen-plan` Phase 4.6 — this plan sets `threshold: none` with a sensitive-path reason bullet.
- Do NOT use `bash -n` on `.yml` workflow files (parses the YAML header as bash) — use
  `actionlint` for YAML + `bash -c '<extracted snippet>'` for the retry-shell.
- Because the mirror step now `exit 0`s on failure, `steps.zot_mirror.outcome` is always
  `success` — downstream gating MUST read the explicit `mirror_status` **output**, never `outcome`.
- The retry loop must wrap only **idempotent** ops (crane copy skips existing blobs;
  docker push / cosign sign re-run safely). Confirmed idempotent for all three.
- `crane copy` retry re-checks already-uploaded blobs, so a retry after a mid-blob reset
  resumes cheaply rather than re-uploading the whole image.
