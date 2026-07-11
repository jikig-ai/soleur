---
title: "fix(infra): deploy fan-out verify resolves web-1's re-swap tag from /health, not the shared deploy-status .tag slot"
type: fix
date: 2026-07-11
issue: 6353
lane: single-domain
brand_survival_threshold: aggregate pattern
adr: ADR-079 (amendment — extend the #6147 reader inventory)
---

# fix(infra): deploy fan-out aborts on every web-host recreate — web-1's recorded deploy tag is `latest` (`tag_malformed`)

The `web_2_recreate` and `warm_standby` deploy fan-outs both call the shared
`apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh`. That script seeds the tag it
re-POSTs (`DEPLOY_TAG`) by reading web-1's `.tag` from the shared
`https://deploy.soleur.ai/hooks/deploy-status` slot (line ~180). That slot is a single
last-write-wins object stamped by **multiple independent writers** — a web-platform deploy, an
inngest `restart inngest _ latest` (which legitimately stamps `tag:latest`), a git-lock sweep. When
the last writer left `latest`, the verify re-POSTs `deploy web-platform <image> latest`, which the
host-side immutable-tag contract (`ci-deploy.sh`: `^v[0-9]+\.[0-9]+\.[0-9]+$`) rejects as
`tag_malformed` (`exit_code:1`) — aborting **every** web-host recreate and blocking the #6178
Inngest cutover.

**The fix (CTO ruling, Option B — see Architecture Decision):** the shared verify script resolves
web-1's re-swap tag from web-1's public `/health` `.version` (the actually-running container's baked
`BUILD_VERSION`) via the existing pure resolver `resolve-web1-known-good-tag.sh`, exactly as
ADR-079 amendment #5955 and the #6147 pin-gate migration already established for the two sibling
readers. The verify keeps reading deploy-status for `exit_code`/`reason`/`start_ts` (acceptance
proof) but **never trusts `.tag` as the tag it POSTs**. This is a single-idiom, single-input change
that fixes **both** callers with zero per-caller workflow wiring, and lets us delete the
`latest`-tolerating baseline band-aid.

## Enhancement Summary

**Deepened on:** 2026-07-11
**Research inputs:** learnings-researcher (8 relevant learnings), repo/deploy-infra Explore pass, CTO domain advisory, architecture-strategist + spec-flow-analyzer + code-simplicity plan-review.

### Key groundings folded in
1. **This is the third un-swept `.tag` reader** — ADR-079 #5955 established the `/health .version` invariant; #6147 migrated the recreate pin-gate (second reader). The direct-predecessor learning classifies readers by what they DO with the value: **tag-resolver reads (baseline seed `:180`/`:197`) must migrate; positive-match poll reads (`:219`/`:228`) may stay.** This plan's Phase 3 scoping matches that classification exactly.
2. **CTO verdict: Option B** (shared script self-resolves `/health` behind a distinct seam) over Option A/hybrid — avoids re-introducing the #6040 two-divergent-copies drift and a Doppler/`APP_DOMAIN_BASE` preamble in warm_standby.
3. **The distinct `/health` test seam is the single highest-risk detail** — must be independently drivable from the deploy-status seam (different URL + fixture) or the fix is untestable in isolation.
4. **Delete the `latest` band-aid** and **replace** (not extend) AC4-latest / AC4-latest-resolve — those tests are green on a fiction (fixture pretends the host accepts `latest`).

## Research Insights (deepen-plan)

**Institutional learnings applied** (`knowledge-base/project/learnings/`):
- `best-practices/2026-07-07-deploy-status-tag-reader-resolve-running-version-from-health.md` — direct predecessor (#6147): the reader-classification sweep + pure-resolver extraction pattern this plan extends.
- `workflow-patterns/2026-07-03-chain-of-latent-defects-clearing-a-wedge-exposes-a-cascade.md` — #5955 had three fix approaches (resolve-from-/health vs relax semver vs digest-redeploy); the architectural call is an ADR-owner decision (here: CTO ruling → Option B, semver-only contract preserved). "Merged ≠ ever-ran-green": the fan-out verify was behind the recreate wedge, so treat its changed path as first-run code.
- `best-practices/2026-07-05-bounded-retry-off-host-verify-and-fail-loud-guard-detection-command-exit.md` — the exact script; keep the bounded fresh-boot degraded-retry (#6051) + fail-loud guards intact; prove non-vacuity by MUTATION (revert the seed change, confirm T-A/B/C flip RED). `grep -c` exits 1 on zero — use `|| true` where a zero count must reach a guard.
- `best-practices/2026-07-05-extracted-specialized-shared-script-not-clean-swap-and-parity-blind-spots.md` — the script is shared but specialized; #6040 (warm_standby migration) is a separate concern. Option B keeps a single code path across both callers (no per-caller divergence).
- `best-practices/2026-05-27-bash-set-e-leaks-from-functions-use-or-true.md` — the new `_resolve_known_good_tag()` must not toggle `set -e` inside the function; use `|| true` on the `/health` curl (mirror `_get_status`'s `|| echo "000"`).
- `best-practices/2026-06-03-every-run-durable-observability-info-silent-fallback.md` — success-path outcomes should stay queryable (the `deployed_tag` emit to `$GITHUB_OUTPUT` is preserved).

**Precedent-Diff (Phase 4.4 — pattern-bound behavior).** The `/health`→resolve→semver pattern is NOT novel — it is `git grep`-confirmed at two sibling call sites, adopted verbatim:
- `.github/workflows/apply-web-platform-infra.yml:1067-1093` (the `pin` step): `curl -sf app/health | jq -r '.version'` (12× bounded retry, public — no CF-Access) → `resolve-web1-known-good-tag.sh`.
- `.github/workflows/apply-deploy-pipeline-fix.yml` (item-4 redeploy, ADR-079 #5955): same shape.
Phase 2's `_resolve_known_good_tag()` MUST mirror the pin step's retry/timeout/jq shape and reuse `resolve-web1-known-good-tag.sh` unchanged (do NOT fork its regex). No novel pattern is introduced.

### Network-Outage Deep-Dive (Phase 4.5 — conditional trigger fired on "unreachable"/"timeout"/"SSH" prose)

This plan is a **tag-resolution bug fix, NOT an L3/L7 connectivity fault** — the keyword hits are in failure-handling prose (the plan's own `/health`-unreachable branch) and in "no-SSH" observability copy, not a connectivity hypothesis. Layer-by-layer status:
- **L3 firewall allow-list / egress IP:** N/A — no operator SSH, no `terraform apply` with `provisioner "file"`/`remote-exec"`/`connection { type = "ssh" }` introduced by this PR (the verify runs *after* the web-2 apply; the PR edits only the shared bash script the workflow calls). No firewall/egress-IP diagnosis needed.
- **L3 DNS/routing:** the new dependency is `app.<domain>/health` over the **same Cloudflare tunnel edge** the script already hits for `/hooks/deploy-status` — not a new failure domain.
- **L7 TLS/proxy:** unchanged; public HTTPS `/health` (no CF-Access headers), same as the `pin` step.
- **L7 application:** the one added failure mode (`/health` unreachable or non-semver) is handled by a **bounded retry (mirror pin's 12×) + loud terminal `exit 1`** — never a silent fallback. Covered by test T-B/T-C.
No gaps to close before implementation; no firewall/egress verification is applicable to this change.

## Root Cause (confirmed in-tree)

1. `restart-inngest-server.yml:47` / `cutover-inngest.yml:808` POST `restart inngest _ latest`.
   `ci-deploy.sh` handles `ACTION=restart` and on success calls `final_write_state 0 "success"`,
   which `write_state` stamps as `"tag":"latest"` (the payload TAG) into web-1's shared
   `/var/lock/ci-deploy.state` slot (`ci-deploy.sh:282` `write_state`). The `.tag` field is the
   **last-ATTEMPT tag, not the running image** (ADR-079 #5955).
2. `deploy-status-fanout-verify.sh:180` seeds `DEPLOY_TAG=CURRENT_TAG` from that slot; the
   `latest`-widened baseline guard (`:184-194`, band-aid) accepts `latest`.
3. `_trigger_fanout` (`:158`) POSTs `deploy web-platform <image> latest`. `ci-deploy.sh:1117-1120` rejects
   a non-semver `deploy` tag (`^v[0-9]+\.[0-9]+\.[0-9]+$`) → `final_write_state 1 "tag_malformed"`, which **re-stamps**
   `.tag=latest, exit_code:1` — self-perpetuating. The verify poll reads that and emits
   `deploy fan-out failed (exit=1, reason=tag_malformed, tag=latest)` (`:277`/`:282`).

The `restart`-writer + fan-out reader are two seams of one wedge; #6147 already moved the recreate
**pin-gate** off `.tag` onto `/health`. The fan-out verify is the **third un-swept reader**.

## Research Reconciliation — Issue Open Questions vs. Codebase Reality

| Issue open question / claim | Reality (verified) | Plan response |
|---|---|---|
| "Why is web-1's recorded tag `latest` vs the pinned digest?" | `.tag` is the last-ATTEMPT tag (`write_state`), stamped `latest` by the inngest `restart` writer and re-stamped `tag_malformed` by the fan-out's own rejected `latest` re-POST. It is NOT the running image (which is healthy, digest-pinned). | We stop **trusting** `.tag` as a tag source; we do not "fix the writer." Resolve from `/health .version` instead (ADR-079 #5955 invariant). |
| "Does web-1's own recreate path share the broken fan-out tag-resolution?" | web-1's recreate would use the SAME shared `deploy-status-fanout-verify.sh` and the SAME `.tag` seed → same failure. The recreate **pin-gate** (`id: pin`, `apply-web-platform-infra.yml:1021`) already resolves `/health` correctly for the Terraform digest, but does NOT feed the verify. | Fix is in the shared verify script → covers web-1's future recreate path too. |
| "Correct web-1's recorded deploy tag to the pinned digest, then re-verify." | Merging this PR touches `apps/web-platform/**` → `web-platform-release.yml` (`on.push.paths`) deploys `v<version>` and re-stamps web-1's `.tag` to a released semver — an **incidental self-heal** (not guaranteed; a no-version-mint push would skip). The next fan-out (now `/health`-resolved) also re-swaps web-1 at a semver. | No operator step needed; live-state correction is a side effect of merge + next fan-out. Do NOT rely on it — the fix makes the POSTed re-swap tag immune. (Architecture P2-A: the acceptance-match read `:228` is NOT fully immune — a writer stamping `latest` between web-2's `ok` and the poll can transiently mask acceptance → fail-loud RED + re-dispatchable; residual until #6178.) |
| AC4-latest unit tests assert `latest` baseline is "tolerated and reaches success." | Green on a **fiction**: the fixture `ok-latest-s300` pretends the host accepted `latest`; prod `ci-deploy.sh` **rejects** a `latest` `deploy`. The test masks exactly this bug. | Replace AC4-latest / AC4-latest-resolve with `/health`-resolution cases (deploy-status=`latest` + /health=`v1.2.3` → POST `v1.2.3`, never `latest`). |

## User-Brand Impact

- **If this lands broken, the user experiences:** the web-host recreate / deploy-recovery path stays wedged; a future web-1 recreate (or container replacement) during a real incident could fail to bring web-1 back cleanly → **prod-wide outage of `soleur.ai`** (all users), and the #6178 Inngest cutover stays blocked. Current state is ingress-safe (web-2 weight 0), so landing broken = status quo — no *new* user-facing regression, but the latent recovery-path risk persists.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A — no user data, secrets, or PII touched. The change is a CI tag-resolution edit reading a public `/health` endpoint (bare semver, no auth) and an already-authenticated deploy-status GET.
- **Brand-survival threshold:** `aggregate pattern` — the risk is systemic *availability* of the fleet deploy-recovery path (affects all users if a web-1 recreate fails), not a per-user data incident. No CPO sign-off required; no sensitive-path leak vector.

## Observability

(Touches `apps/web-platform/infra/**` → required.)

```yaml
liveness_signal:
  what:            "GitHub Actions run status of apply-web-platform-infra.yml (web_2_recreate / warm_standby jobs) + web-1 /hooks/deploy-status reason/exit_code after a fan-out"
  cadence:         "per web-host-recreate / warm-standby dispatch (workflow_dispatch)"
  alert_target:    "the dispatching operator via the red/green GitHub Actions run; ::error:: line names the failing reason + a recovery message"
  configured_in:   "apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh (::error:: emitters at :161/:250/:277/:282/:288 + the new /health-resolution failure branch)"

error_reporting:
  destination:     "GitHub Actions run log (log-visible, no SSH — hr-no-ssh-fallback-in-runbooks). No Sentry mirror: this is a CI orchestration script, not a runtime server path."
  fail_loud:       "terminal `exit 1` with `::error::deploy fan-out failed (...)` OR the new `::error::` when /health yields no strict semver (mirrors resolve-web1-known-good-tag.sh:56 wording + a recovery remediation). NEVER green-on-timeout; NEVER a silent fallback to the .tag seed."

failure_modes:
  - mode:          "web-1 /health unreachable or reports a non-released .version (BUILD_VERSION unset → 'dev')"
    detection:     "the new bounded /health retry (mirror pin's 12× loop) exhausts → resolve-web1-known-good-tag.sh rejects non-semver → terminal exit 1 with a named ::error:: in the run log"
    alert_route:   "red GitHub Actions run to the dispatching operator (remediation: trigger a normal web-platform release, confirm app/health reports the new version, re-run the recreate)"
  - mode:          "deploy-status .tag polluted with `latest` by an inngest restart / git-lock writer (the #6353 wedge)"
    detection:     "no longer a failure mode for the fan-out — the verify ignores .tag as a tag source; the /health-resolved semver is POSTed instead. Regression-guarded by the new RED fixture (deploy-status=latest + /health=v1.2.3 → POST v1.2.3)."
    alert_route:   "n/a (defect removed); unit test deploy-status-fanout-verify.test.sh fails loud if reintroduced"
  - mode:          "web-1 recorded deploy-status stays exit_code:1/tag_malformed while the container is healthy (pre-existing observability gap — nothing pages on it)"
    detection:     "NOT currently monitored (canary-status.yml reads only .sandbox_canary, dispatch-only; no Sentry/Better Stack alert references deploy-status .tag/exit_code). Documented as out-of-scope residual; self-heals on the next release/fan-out."
    alert_route:   "none today — surfaced only as a red recreate run. Tightening the monitor is deferred (see Alternatives / #6178)."

logs:
  where:           "GitHub Actions run logs for apply-web-platform-infra.yml; host-side ci-deploy state via `bash apps/web-platform/infra/cat-deploy-state.sh` (reads /hooks/deploy-status, no SSH)"
  retention:       "GitHub Actions default (90 days); deploy-status slot is last-write-wins (no history)"

discoverability_test:
  command:         "curl -sf --max-time 15 https://app.soleur.ai/health | jq -r '.version'   # web-1's running semver — the source the fix resolves from (no ssh)"
  expected_output: "a bare strict semver, e.g. 1.2.3 (resolve-web1-known-good-tag.sh maps it to v1.2.3). Empty/non-semver → the fix aborts loud instead of POSTing latest."
```

## Architecture Decision (ADR/C4)

### ADR
**Amend ADR-079** (`knowledge-base/engineering/architecture/decisions/ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md`) — extend the existing **"Reader inventory (#6147, 2026-07-07)"** paragraph under Amendment #5955 with a dated line: the fan-out verify (`deploy-status-fanout-verify.sh`) is the **third un-swept reader** of `/hooks/deploy-status` `.tag`; **BOTH** its baseline seed AND its `_trigger_fanout` retrigger now resolve web-1's re-swap tag from `app/health` `.version` via `resolve-web1-known-good-tag.sh` (same strict-semver guard) — the two former `.tag` tag-sources are both removed (architecture P1-A). Invariant restated (now honest against the shipped code): *`/health .version` is the canonical running-tag source; the shared deploy-status `.tag` is acceptance-proof-only, never a tag source; the deploy contract stays semver-only.* Also record the **host-targeting invariant** carried from the pin step (`app/health` must resolve to web-1; revisit on the #5274/#6178 canary-weighting). This is an in-scope plan deliverable (`wg-architecture-decision-is-a-plan-deliverable`), NOT a deferred issue. **Do NOT run `/soleur:architecture create`** — no new decision, same rationale, new consumer (CTO ruling).

### C4 views
**No C4 impact.** Checked all three model files —
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`:
- **External human actors:** none new (this is a CI-Actions → host-webhook orchestration change; no new correspondent/reviewer/recipient).
- **External systems / vendors:** GHCR/`zotRegistry` (image source) and `betterstack` (monitoring) are already modeled; this fix touches neither's edge. `betterstack` already probes `web-N.app.soleur.ai/health` for per-host absence (`model.c4:264`) — the fix READS the same `/health .version` but does not alter that edge.
- **Container / data store:** the web hosts are modeled as the `hetzner` "Compute" container (`model.c4:180`); the deploy fan-out / deploy-status `.tag` vs `/health` resolution is CI-internal orchestration within/against that container's ci-deploy webhook — not a distinct C4 element. No new data store.
- **Access relationship:** no owner/tenancy/trust-boundary change. The `hetzner -> claude "Hosts"` and image-pull edges are unchanged.

A competent engineer reading the existing ADR corpus + C4 would NOT be misled after this ships (the `.tag`→`/health` invariant is already recorded under ADR-079 #5955/#6147; this extends it).

### Sequencing
None — the decision is true at merge; the amendment describes the already-adopted #5955 source applied to a third reader.

## Infrastructure (IaC)

**No new infrastructure.** Pure edit to an existing bash script + its unit test + an ADR amendment,
against an already-provisioned surface (web hosts, deploy webhook, CF Access, `/health` all exist).
No new server, secret, vendor, DNS record, cron, or systemd unit → Phase 2.8 IaC-routing gate does
not fire. No Terraform change; no `apply-web-platform-infra.yml` infra `*.tf` touched (only the
shared script it invokes).

## Implementation Phases

### Phase 0 — Preconditions (verify before editing)
- Read `deploy-status-fanout-verify.sh` (seed at `:170-197`, band-aid `:184-194`, `_trigger_fanout` `:142-166`, poll `.tag` reads `:219`/`:228`) and `resolve-web1-known-good-tag.sh` (pure, `$1`-or-stdin, strict `^v[0-9]+\.[0-9]+\.[0-9]+$`).
- Confirm the test seam idiom in `deploy-status-fanout-verify.test.sh` (`DEPLOY_STATUS_SOURCE_CMD`, `DEPLOY_POST_SINK`, `DEPLOY_POST_CODE_CMD`; SEQ position contract `[0]`=baseline, `[1]`=trigger re-read, `[2..]`=polls; fixtures under `apps/web-platform/infra/fixtures/deploy-status/*.json`).
- Confirm `pin` step (`apply-web-platform-infra.yml:1021`) resolves `/health` for the digest only and does NOT feed the verify; confirm `warm_standby` verify step has no Doppler/`APP_DOMAIN_BASE` context (only WEBHOOK/CF secrets).

### Phase 1 — RED fixtures + harness capture first (`cq-write-failing-tests-before`)
Add failing cases to `deploy-status-fanout-verify.test.sh` (do NOT fork `resolve-web1-known-good-tag`'s regex — reuse it):
- **[spec-flow P0 — harness plumbing, do this FIRST]** `run_verify` computes `POSTS=$(wc -l < "$sink")` then `rm -rf "$tmp"` (test `:111-113`) — the sink FILE is deleted before content can be read; only the line count survives. Extend `run_verify` to **capture the sink contents into a global** (`POSTBODIES=$(cat "$sink" 2>/dev/null)`) BEFORE the `rm`, mirroring how it already captures `GHOUT`. T-A/T-B then assert on `$POSTBODIES`, NOT on the file. **Guard the vacuous-pass trap:** `! grep -q latest "$sink"` against a *missing* file returns non-zero → `!` flips it to a false GREEN proving nothing (the exact proxy-not-invariant failure). Assert against the captured string, and add a positive anchor (`grep -q 'v1.2.3' <<<"$POSTBODIES"`) so an empty capture fails.
- **T-A:** deploy-status `.tag=latest` + `/health=1.2.3` → the fan-out POST payload (in `$POSTBODIES`) **contains** `v1.2.3` AND does **not** contain `latest`; verify reaches `exit 0` on a matching `ok` completion.
- **T-B:** `/health` unreachable (`HEALTH_SOURCE_CMD='echo ""'`) → **terminal `exit 1`** with a named `::error::`; assert `$POSTBODIES` is empty / contains no `latest` and no old `.tag` (no silent fallback). Run once with default `OP_CONTEXT=recreate` AND once `OP_CONTEXT=warm-standby` (spec-flow P2 — the `_recovery_msg` wording diverges by caller and is otherwise unverified on the new abort branch).
- **T-C:** `/health=dev` (non-semver) → terminal `exit 1`, remediation `::error::`. (Overlaps T-B at the same fail-loud branch; kept as the string-shape smoke — the resolver's own suite covers full non-semver rejection, so this is the minimal integration echo, per code-simplicity Finding 3.)
- **T-D (retrigger, replaces AC4-latest-resolve):** `/health=v1.2.3` baseline, then a fresh-boot degraded → after the window, retrigger re-resolves from `/health` now reporting `1.3.0` → `$POSTBODIES` shows the SECOND POST carries `v1.3.0` (the retrigger adopts the advanced `/health` version, never `.tag`). Keeps the retained downgrade-safety path under test (architecture P2-B).
- **Non-vacuity:** confirm each new assertion FAILS against the current (unmodified) script before Phase 2 (MUTATION proof — learning `2026-07-05-bounded-retry-...`).

### Phase 2 — Add the `/health` seam + resolve in the shared script
- Add a **distinct** `/health` test seam, **separate** from `DEPLOY_STATUS_SOURCE_CMD` (the single load-bearing constraint — different URL + fixture so a test drives "deploy-status=latest, /health=1.2.3" independently). **Use the LIGHTER stdout-echo seam shape, NOT a copy of `_get_status`** (code-simplicity finding): since `resolve-web1-known-good-tag.sh` reads `$1`-or-stdin, the `/health` path needs only ONE string (`.version`) — no body-file, no HTTP-code popper. Seam form: `HEALTH_SOURCE_CMD` overrides the whole fetch, e.g. test drives `HEALTH_SOURCE_CMD='echo 1.2.3'` / `'echo ""'` / `'echo dev'`; prod path (unset) runs the curl.
- New `_resolve_known_good_tag()`: `version=$( [[ -n "$HEALTH_SOURCE_CMD" ]] && bash -c "$HEALTH_SOURCE_CMD" || curl -sf --max-time 15 --retry 3 --retry-connrefused "$HEALTH_URL" | jq -r '.version // ""' )` then `resolve-web1-known-good-tag.sh "$version"`. **Use `curl --retry 3 --retry-connrefused`, NOT a hand-rolled 12× loop** (code-simplicity YAGNI: `pin`'s 12× loop is calibrated for a *fresh-boot* host whose `/health` may not be up; web-1 here is the LIVE prod origin already serving — one-line retry covers transient CF-tunnel blips). Guard `set -e` leaks with `|| true` on the curl (mirror `_get_status`'s `|| echo "000"`; learning `2026-05-27-bash-set-e-leaks-from-functions-use-or-true.md`). On failure/non-semver emit a loud `::error::` (mirror `resolve-web1-known-good-tag.sh:56` + `_recovery_msg`) and `exit 1` — **never** fall back to the `.tag` seed (the loud CI failure IS the mirror; no silent path).
- **[spec-flow P2 — invocation form + stdout hygiene, load-bearing]** The function's ONLY stdout output MUST be the resolved `vX.Y.Z` tag; ALL diagnostics (`::error::`, `_recovery_msg`, retry chatter) go to `>&2`. Called as `DEPLOY_TAG="$(_resolve_known_good_tag)"`, any stray stdout is captured INTO `DEPLOY_TAG` and pollutes the fan-out payload. The `exit 1` inside the `$(…)` subshell aborts the parent via `set -e` (T-B/T-C rely on `2>&1` capture seeing the stderr `::error::`). The pure resolver already writes to `>&2` (`:56`); the new wrapper must too.
- **[architecture P1-B — host-targeting invariant]** Copy the `pin` step's `apply-web-platform-infra.yml:1058-1066` HOST-TARGETING INVARIANT comment into `_resolve_known_good_tag`: `app.<domain>/health` MUST resolve to web-1; if the #5274 multi-host DNS rewire / #6178 cutover makes `app` canary-weighted so web-2 can answer, this resolver MUST switch to a web-1-pinned health path. Holds today only because web-2 is weight-0 — and THIS PR unblocks the exact cutover that eventually changes that.

### Phase 3 — Seed `DEPLOY_TAG` from `/health`, delete the `latest` band-aid
- Replace the `DEPLOY_TAG=CURRENT_TAG` seed (`:197`) with `DEPLOY_TAG="$(_resolve_known_good_tag)"`. Keep the baseline read for `exit_code` (skip on `-1` in-flight) and `PRE_START_TS` (staleness baseline) — those stay `.tag`-independent.
- **Delete** the `latest`-widened baseline guard alternation + its `:184-190` justification (`:191` `^(v[0-9]...|latest)$` → the tag is no longer read from `.tag`, so the guard's tolerance is dead). Truly-unknown `/health` values now abort in `_resolve_known_good_tag`. **Also remove the now-dead `CURRENT_TAG` extraction (`:180`) + its log line (`:196`)** (architecture P2-C: after the seed change `CURRENT_TAG` is unused — leaving it is misleading; the baseline loop keeps only `exit_code`/`start_ts`). And update the `_trigger_fanout` comment at `:148` ("*unlike the baseline guard above*") which now references a deleted guard (comment rot on the highest-risk function).
- **`_trigger_fanout` re-trigger path (`:147-155`) — the second `.tag` tag-source (architecture P1-A, load-bearing).** This path re-reads `.tag` and *reassigns* `DEPLOY_TAG=$fresh_tag` on a downgrade-guarded retrigger; its guard (`:152`) uses a **looser** regex (`^v[0-9][A-Za-z0-9._-]*$`) than the deploy contract's strict `^v[0-9]+\.[0-9]+\.[0-9]+$`, so a v-prefixed non-strict pollutant (e.g. `v1.2.3-rc1`) would be adopted → POSTed → `tag_malformed` — the same bug class through the third seam. **Chosen fix (option a):** re-resolve the retrigger tag from `/health` via `_resolve_known_good_tag` too, so `/health` is the *uniform* tag source and the ADR's "`.tag` is never a tag source" invariant is literally true. (Keeps the downgrade-safety intent: `/health .version` is web-1's running version, never a downgrade.) The looser `:152` `.tag` re-read is then dropped. This makes the AC grep meaningful (no surviving `DEPLOY_TAG="$fresh_tag"` from `.tag`).
- Leave the verify-poll acceptance-match `.tag` reads (`:219`/`:228`) **untouched**: after web-2's deploy, `.tag` reflects the POSTed semver so `TAG==DEPLOY_TAG` still matches. **Caveat (architecture P2-A):** `:228` reads the same last-write-wins slot, so a concurrent inngest-`restart … latest` writer landing between web-2's genuine `ok` and the poll can still transiently mask acceptance → fail-loud RED + re-dispatchable (NOT silent), residual until #6178. The POSTed tag is immune; the acceptance match is not fully immune — see the softened User-Brand Impact wording.
- **Carry the pin step's HOST-TARGETING INVARIANT (architecture P1-B) into `_resolve_known_good_tag`:** copy the `apply-web-platform-infra.yml:1058-1066` comment — `app.<domain>/health` MUST resolve to web-1; if the multi-host DNS rewire (#5274) / #6178 cutover makes `app` canary-weighted so web-2 can answer, this resolver MUST switch to a web-1-pinned health path. Holds today only because web-2 is weight-0; this PR unblocks the exact cutover that eventually changes that.

### Phase 4 — Harness `/health` default, test re-homing, ADR amendment, green the suite
- **[spec-flow P1 — the single largest omission] Inject a DEFAULT `/health` seam into `run_verify` for EVERY existing test.** After the fix, every invocation seeds `DEPLOY_TAG` from `_resolve_known_good_tag()` → a `/health` fetch. With no default `HEALTH_SOURCE_CMD`, existing cases (AC1/AC2/AC3*/AC6/staleness/…) fall through to a **real network curl to `app.soleur.ai/health` in CI** — breaking the network-free contract. Default the seam to the version matching each family's fixture `.tag` so the poll `TAG==DEPLOY_TAG` (`:228`) still holds: `1.0.0` for the `settled-v1`/`ok-v1` family (v1.0.0), and drive `1.1.0` where a case expects a v1.1.0 completion. This is a harness-wide edit, NOT "tests stay green unchanged."
- **[spec-flow P1 + code-simplicity F1] Re-home AC4-tag / AC4-tag-empty (do NOT claim they "stay green").** They assert a garbage/empty **`.tag`** baseline aborts — i.e. they pin the DELETED baseline-`.tag`-validation guard (`:191-194`). After deletion the baseline no longer validates `.tag`, so they'd only exit 1 incidentally (misleading-green — the same fiction the plan condemns). Convert them into `/health`-garbage / `/health`-empty cases (they overlap T-C/T-B) — the tag-validation semantics MOVED to `/health` resolution.
- **Replace AC4-latest AND AC4-latest-resolve** with T-A (latest baseline tolerated but never POSTed) and T-D (retrigger re-resolves from `/health`); delete the orphaned `fixtures/deploy-status/ok-latest-s300.json` (referenced by nothing after AC4-latest goes).
- Add the dated reader-inventory line to ADR-079 (see Architecture Decision).
- Run `bash apps/web-platform/infra/deploy-status-fanout-verify.test.sh` → all green (T-A/B/C/D pass; AC4-latest / AC4-latest-resolve replaced; AC4-tag/-empty re-homed; staleness / degraded-retry / unexpected-reason / deploy-failed stay green *with the default `/health` seam in place*).
- Run `bash apps/web-platform/infra/resolve-web1-known-good-tag.test.sh` (unchanged — must stay green).
- Confirm both parity tests stay green: `web-hosts-fanout-parity.test.sh` (no `WEB_HOST_PRIVATE_IPS:` env added/removed → `min_copies` unchanged) and `web-1-swap-concurrency-parity.test.sh` (no new swap job → count==4 unchanged).

## Files to Edit

- `apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh` — add `/health` seam (`HEALTH_URL` + `HEALTH_SOURCE_CMD`) + `_resolve_known_good_tag()` (stdout=tag only, diagnostics `>&2`, `curl --retry 3`, host-targeting-invariant comment); seed `DEPLOY_TAG` from `/health` at baseline AND retrigger; delete the `latest` baseline band-aid + dead `CURRENT_TAG` + orphaned `:148` comment; loud-abort on no-semver.
- `apps/web-platform/infra/deploy-status-fanout-verify.test.sh` — **capture the POST-sink contents into a global before `run_verify`'s `rm` (spec-flow P0)**; inject a DEFAULT `/health` seam for every existing case (spec-flow P1); RED cases T-A/T-B/T-C/T-D; replace AC4-latest + AC4-latest-resolve; re-home AC4-tag/-empty to `/health`-garbage/-empty; assert POST-payload **contents** (semver present, `latest` absent) against the captured global, not the deleted file.
- `apps/web-platform/infra/fixtures/deploy-status/*.json` — `/health` fixtures are stdout strings via `HEALTH_SOURCE_CMD` (no JSON body needed for the light seam); reuse `latest-tag.json` for the deploy-status side of T-A. **Delete the orphaned `ok-latest-s300.json`** (unreferenced after AC4-latest is replaced). Synthesized only (`cq-test-fixtures-synthesized-only`).
- `knowledge-base/engineering/architecture/decisions/ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md` — extend the #6147 reader-inventory paragraph (~`:356`) with the #6353 third-reader line.

## Files to Create

- (Optionally) a new `/health` fixture file under `apps/web-platform/infra/fixtures/deploy-status/` if a semver-`/health` body doesn't already exist. No new scripts (`resolve-web1-known-good-tag.sh` is reused as-is — CTO: no change).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `deploy-status-fanout-verify.sh` seeds `DEPLOY_TAG` from web-1 `/health .version` via `resolve-web1-known-good-tag.sh` at BOTH the baseline seed and the `_trigger_fanout` retrigger; `git grep -nE 'DEPLOY_TAG=.*CURRENT_TAG|DEPLOY_TAG="\$fresh_tag"' apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh` returns **0** (neither `.tag` tag-source survives — architecture P1-A).
- [ ] The `latest`-widened baseline guard AND the dead `CURRENT_TAG` extraction are deleted: `git grep -nE '\^\(v\[0-9\].*\|latest\)\$|CURRENT_TAG' apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh` returns **0**.
- [ ] `_resolve_known_good_tag` carries the host-targeting-invariant comment (`git grep -c 'HOST-TARGETING\|resolve to web-1\|weight-0' apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh` ≥ 1 — architecture P1-B).
- [ ] The `/health` seam is **distinct** from the deploy-status seam: the script references `HEALTH_URL`/`HEALTH_SOURCE_CMD` separate from `DEPLOY_STATUS_URL`/`DEPLOY_STATUS_SOURCE_CMD`, and T-A drives deploy-status=`latest` + /health=`1.2.3` independently.
- [ ] **[spec-flow P0]** `run_verify` captures the POST-sink contents into a global BEFORE its `rm`; T-A/T-B assert on the captured string with a POSITIVE anchor (`grep -q 'v1.2.3'`) so an empty capture fails — NOT `! grep -q latest <file>` against a deleted file (vacuous pass).
- [ ] T-A: deploy-status `.tag=latest` + `/health=1.2.3` → captured POST payload contains `v1.2.3` AND not `latest`; verify exits 0.
- [ ] T-B: `/health` unreachable → terminal `exit 1`, named `::error::`, captured POSTs contain no `latest`/old `.tag`; asserted under BOTH `OP_CONTEXT=recreate` and `=warm-standby` (recovery-message wording).
- [ ] T-C: `/health` non-semver → terminal `exit 1` with a remediation `::error::`. T-D: retrigger re-resolves from `/health` (second POST carries the advanced semver, never `.tag`).
- [ ] A DEFAULT `/health` seam is injected into `run_verify` so every pre-existing case stays network-free and green (no real `app.soleur.ai/health` curl in CI); AC4-tag/-empty are re-homed to `/health`-garbage/-empty (not left asserting the deleted `.tag` guard).
- [ ] `bash apps/web-platform/infra/deploy-status-fanout-verify.test.sh` all green; `resolve-web1-known-good-tag.test.sh` all green; `web-hosts-fanout-parity.test.sh` + `web-1-swap-concurrency-parity.test.sh` green.
- [ ] ADR-079 carries the dated #6353 third-reader inventory line under Amendment #5955; `grep -c '#6353' knowledge-base/engineering/architecture/decisions/ADR-079-*.md` ≥ 1.
- [ ] PR body uses `Closes #6353` (the code fix fully resolves the blast radius at merge; no post-merge operator write is required — live-state self-heal is incidental, not a gating step).

### Post-merge (operator)
- [ ] None required. Live-state correction of web-1's `.tag` is an incidental side effect of the `web-platform-release.yml` deploy triggered by this PR's `apps/web-platform/**` change, and of the next `/health`-resolved fan-out. **Automation:** not applicable — no operator action; a web-2 recreate re-verification is the natural next dispatch that unblocks #6178, run by whoever proceeds with the cutover.

## Test Scenarios

- Given web-1's deploy-status `.tag=latest` (inngest-restart pollution) and `/health` reports `1.2.3`, when the fan-out verify runs, then it POSTs `deploy web-platform <image> v1.2.3` (never `latest`) and proves web-2 acceptance via `reason=ok`.
- Given web-1's `/health` is unreachable for the full bounded retry, when the verify runs, then it aborts with a terminal `exit 1` and a named `::error::` — it does NOT fall back to the `.tag` seed and does NOT POST `latest`.
- Given `/health` reports a non-released version (`dev`), when the verify runs, then it aborts loud with a remediation (trigger a normal release first).
- Given a fresh-boot web-2 that degrades then, after the window, the fan-out retriggers AND `/health` now reports an advanced `1.3.0`, when `_trigger_fanout` re-resolves, then the SECOND POST carries `v1.3.0` (retrigger adopts the advanced `/health` version, never `.tag`) — T-D, the replacement for AC4-latest-resolve.
- Given a healthy web-2 that returns `reason=ok` on the first fan-out (warm-standby), when the verify runs, then the bounded fresh-boot degraded-retry never engages and it exits 0 — unchanged behavior.
- Given the deploy-status poll's own `.tag` read after a successful web-2 deploy, when `TAG==DEPLOY_TAG` (both the `/health`-resolved semver), then acceptance matches — poll semantics unchanged.
- Given an inngest `restart … latest` writer stamps the slot between web-2's genuine `ok` and the poll read, when the verify polls, then it transiently sees `TAG=latest≠DEPLOY_TAG` and, worst case, times out fail-loud RED on a healthy web-2 (re-dispatchable, NOT silent) — the accepted P2-A residual until #6178.

## Domain Review

**Domains relevant:** engineering (CTO)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** CTO advisory delivered (folded in). Verdict: **Option B** (shared verify script self-resolves `/health` behind its own distinct test seam) over Option A (callers pass a resolved tag) — Option A re-introduces the two-divergent-copies drift #6040 eliminated and forces a Doppler/`APP_DOMAIN_BASE` + curl preamble into `warm_standby`'s verify step which has none today. **Do NOT build the optional-input hybrid** (asymmetric coverage). This is an **ADR-079 amendment**, not a new ADR. Keep narrow — do NOT fold in #6060 (web-2-only fan-out) or #6178 (inngest to its own host); #6178 is blocked on this. In-scope cleanup: delete the `latest` band-aid. Landing-broken mitigations are mandatory (this IS the prod-recovery path): RED fixtures first, the distinct `/health` seam (single highest-risk detail), no silent fallback to `.tag`, keep both caller fixture paths green in `infra-validation.yml`. Residual (accepted, out of scope): the inngest/git-lock writers keep polluting the shared slot until #6178 — the fix answers "why is web-1's tag `latest`" with "we stopped trusting it," not "we fixed the writer."

### Plan-Review Panel (deepen-plan — architecture-strategist + spec-flow-analyzer + code-simplicity-reviewer)

All findings folded into the plan above:

- **architecture P1-A (load-bearing):** `_trigger_fanout`'s retrigger `.tag` re-read (`:147-154`) was a *second* tag-source the plan initially kept; its looser `:152` regex would adopt a `v1.2.3-rc1`-shape pollutant → `tag_malformed`. **Fix (option a):** retrigger re-resolves from `/health` too, making the "`.tag` is never a tag source" invariant literally true. (Phase 3, ADR wording, AC grep updated.)
- **architecture P1-B:** carry the pin step's HOST-TARGETING INVARIANT (`app/health` must hit web-1; revisit on #5274/#6178 canary weighting) into `_resolve_known_good_tag`. (Phase 2 + AC.)
- **architecture P2-A / P2-B / P2-C:** softened the "immune regardless" claim (acceptance-match `:228` residual race); added T-D to keep the retained retrigger path under test; prune dead `CURRENT_TAG` + orphaned `:148` comment.
- **spec-flow P0 (load-bearing):** `run_verify` deletes the POST sink before content can be grepped → `! grep -q latest <missing-file>` is a vacuous GREEN. **Fix:** capture sink contents into a global before the `rm`; assert with a positive anchor. (Phase 1, Files-to-Edit, AC.)
- **spec-flow P1:** every existing test needs a DEFAULT `/health` seam (else real CI curl) resolving to the fixture's version; AC4-tag/-empty must be re-homed (they pin the deleted `.tag` guard). "Tests stay green unchanged" was false — corrected in Phase 4.
- **spec-flow P2 / code-simplicity:** stdout-hygiene (tag-only stdout, diagnostics `>&2`) on `_resolve_known_good_tag`; lighter stdout-echo seam (not a `_get_status` clone); `curl --retry 3` not a 12× loop; delete orphaned `ok-latest-s300.json`; T-C is the minimal string-shape echo (resolver suite covers the rest). Scope cut (defer #6060/#6178, delete band-aid in-PR) confirmed correct.
- **Ground-truth correction (spec-flow):** BOTH callers run `ROSTER_COUNT==2` (the single-peer guard is unconditional); the caller distinction is `OP_CONTEXT` wording, not roster count. `web-platform-release.yml` triggers on `apps/web-platform/**` with no `infra/**` exclusion, so the merge-time self-heal is *more* likely than the plan's conservative hedge.

### Product/UX Gate

Not applicable — Product domain is **NONE**. No files under `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`, or any UI-surface term/glob; the change is CI/infra orchestration (bash + ADR). Mechanical UI-surface override did not fire.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open` cross-referenced against every file in Files-to-Edit (`deploy-status-fanout-verify.sh`, `resolve-web1-known-good-tag.sh`, `ci-deploy.sh`, `ADR-079`) returned zero matches.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| **Option A** — callers resolve `/health` and pass `KNOWN_GOOD_TAG` into the verify | Re-introduces the two-divergent-copies drift #6040 eliminated; forces a Doppler/`APP_DOMAIN_BASE` + ~25-line curl preamble into `warm_standby`'s verify step (which has no such context). Worse fit for the two-caller shared-script constraint. (CTO) |
| **Hybrid** — optional `KNOWN_GOOD_TAG` input with `.tag` self-resolve fallback | Two code paths in the shared script (recreate exercises one, warm-standby the other) → asymmetric coverage, doubled test matrix. A `.tag` fallback reinstates the exact bug. (CTO / `cq` simplicity) |
| **Relax `ci-deploy.sh`'s semver guard to accept `latest`/digest** | Explicitly **rejected by ADR-079 #5955**: the guard backs the wrong-image-tagged-with-right-version check; a resolution bug in one caller must not widen the deploy contract. The deploy contract stays semver-only. |
| **Fold in #6060 (web-2-only fan-out, never re-swap web-1)** | The real root-cause fix, but a larger change on the prod-recovery path. Couples the #6178 unblock to a bigger refactor. Deferred (tracked by #6060). |
| **Fix the writer (inngest restart stamps a separate slot) / #6178** | Correct long-term fix (inngest to its own host stops polluting web-1's slot) but out of scope and blocked on THIS unblock. Deferred (#6178). |
| **Add a monitor on deploy-status `exit_code:1`/`tag_malformed`** | Real observability gap (nothing pages on web-1's corrupt-but-healthy state today), but scope-expansion adjacent to #6178's inngest extraction. Documented in Observability; deferred. |

## Risks & Mitigations

- **The distinct `/health` test seam is the single highest-risk detail.** If the seam conflates the `/health` and deploy-status curls (same override), the fix is untestable in isolation. Mitigation: separate `HEALTH_URL` override + separate fixture body; T-A explicitly drives deploy-status=`latest` + /health=`v1.2.3`.
- **Silent fallback reinstating the bug.** If `_resolve_known_good_tag` ever falls back to the `.tag` seed on `/health` failure, the wedge returns. Mitigation: fail loud + terminal `exit 1`; T-B asserts zero `latest`/`.tag` POSTs on `/health` failure.
- **`/health` reachability as a new dependency.** The verify now depends on `app.<domain>/health`. Not a new failure domain (same CF tunnel edge as `/hooks/deploy-status`); mirror `pin`'s bounded 12× retry.
- **Double `/health` read on the recreate path** (pin's coherence gate + verify's re-swap) could observe different semvers if a deploy lands between them — harmless: both valid; the `_trigger_fanout` downgrade guard already handles advance. Leave pin's resolution in place (distinct `-replace` coherence purpose).
- **`DEPLOY_POST_SINK` currently asserts line-count only.** New tests must grep the sink for payload **contents** (semver present / `latest` absent), not just count POSTs.
- **Rollback:** script-only edit, no infra-state mutation → PR-revertable, low blast radius.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This section is filled with a concrete artifact (prod-wide `soleur.ai` outage on a failed web-1 recreate), exposure vector (N/A — no data), and threshold (`aggregate pattern`).
- Do NOT prescribe exact learning filenames with dates in `tasks.md`; use directory + topic (the author picks the date at write-time).
- The current AC4-latest / AC4-latest-resolve tests are GREEN on a fiction (fixture `ok-latest-s300` pretends the host accepts `latest`); they must be **replaced**, not extended — leaving them green would re-assert the buggy "tolerate + re-POST latest" contract.
- Reuse `resolve-web1-known-good-tag.sh`'s strict-semver regex; do NOT fork it into the verify script (single source of the semver guard).
- `bunfig.toml`/vitest are irrelevant here — these are `.sh` self-tests run directly via `bash <file>.test.sh` (gated by `infra-validation.yml`); reference `infra-validation.yml` for the exact invocation, do not assume a JS runner.
