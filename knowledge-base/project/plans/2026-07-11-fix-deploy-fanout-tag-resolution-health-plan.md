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

## Root Cause (confirmed in-tree)

1. `restart-inngest-server.yml:47` / `cutover-inngest.yml:808` POST `restart inngest _ latest`.
   `ci-deploy.sh` handles `ACTION=restart` and on success calls `final_write_state 0 "success"`,
   which `write_state` stamps as `"tag":"latest"` (the payload TAG) into web-1's shared
   `/var/lock/ci-deploy.state` slot (`ci-deploy.sh:282` `write_state`). The `.tag` field is the
   **last-ATTEMPT tag, not the running image** (ADR-079 #5955).
2. `deploy-status-fanout-verify.sh:180` seeds `DEPLOY_TAG=CURRENT_TAG` from that slot; the
   `latest`-widened baseline guard (`:184-194`, band-aid) accepts `latest`.
3. `_trigger_fanout` (`:158`) POSTs `deploy web-platform <image> latest`. `ci-deploy.sh:1118` rejects
   a non-semver `deploy` tag → `final_write_state 1 "tag_malformed"`, which **re-stamps**
   `.tag=latest, exit_code:1` — self-perpetuating. The verify poll reads that and emits
   `deploy fan-out failed (exit=1, reason=tag_malformed, tag=latest)` (`:277`/`:282`).

The `restart`-writer + fan-out reader are two seams of one wedge; #6147 already moved the recreate
**pin-gate** off `.tag` onto `/health`. The fan-out verify is the **third un-swept reader**.

## Research Reconciliation — Issue Open Questions vs. Codebase Reality

| Issue open question / claim | Reality (verified) | Plan response |
|---|---|---|
| "Why is web-1's recorded tag `latest` vs the pinned digest?" | `.tag` is the last-ATTEMPT tag (`write_state`), stamped `latest` by the inngest `restart` writer and re-stamped `tag_malformed` by the fan-out's own rejected `latest` re-POST. It is NOT the running image (which is healthy, digest-pinned). | We stop **trusting** `.tag` as a tag source; we do not "fix the writer." Resolve from `/health .version` instead (ADR-079 #5955 invariant). |
| "Does web-1's own recreate path share the broken fan-out tag-resolution?" | web-1's recreate would use the SAME shared `deploy-status-fanout-verify.sh` and the SAME `.tag` seed → same failure. The recreate **pin-gate** (`id: pin`, `apply-web-platform-infra.yml:1021`) already resolves `/health` correctly for the Terraform digest, but does NOT feed the verify. | Fix is in the shared verify script → covers web-1's future recreate path too. |
| "Correct web-1's recorded deploy tag to the pinned digest, then re-verify." | Merging this PR touches `apps/web-platform/**` → `web-platform-release.yml` (`on.push.paths`) deploys `v<version>` and re-stamps web-1's `.tag` to a released semver — an **incidental self-heal** (not guaranteed; a no-version-mint push would skip). The next fan-out (now `/health`-resolved) also re-swaps web-1 at a semver. | No operator step needed; live-state correction is a side effect of merge + next fan-out. Do NOT rely on it — the fix makes recreate immune regardless. |
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
**Amend ADR-079** (`knowledge-base/engineering/architecture/decisions/ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md`) — extend the existing **"Reader inventory (#6147, 2026-07-07)"** paragraph under Amendment #5955 with a dated line: the fan-out verify (`deploy-status-fanout-verify.sh`) is the **third un-swept reader** of `/hooks/deploy-status` `.tag`; it now resolves web-1's re-swap tag from `app/health` `.version` via `resolve-web1-known-good-tag.sh` (same strict-semver guard), adopting the amendment's source. Invariant restated: *`/health .version` is the canonical running-tag source; the shared deploy-status `.tag` is acceptance-proof-only, never a tag source; the deploy contract stays semver-only.* This is an in-scope plan deliverable (`wg-architecture-decision-is-a-plan-deliverable`), NOT a deferred issue. **Do NOT run `/soleur:architecture create`** — no new decision, same rationale, new consumer (CTO ruling).

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

### Phase 1 — RED fixtures first (`cq-write-failing-tests-before`)
Add failing cases to `deploy-status-fanout-verify.test.sh` (do NOT fork `resolve-web1-known-good-tag`'s regex — reuse it):
- **T-A:** deploy-status `.tag=latest` + `/health` reports `1.2.3` → the fan-out POST payload (in `DEPLOY_POST_SINK`) carries `v1.2.3`, **never** `latest`; verify reaches `exit 0` on a matching `ok` completion.
- **T-B:** `/health` unreachable (seam returns empty/non-200) → **terminal `exit 1`** with a named `::error::`; assert **no** `latest` (and no old `.tag`) POST occurred.
- **T-C:** `/health` returns a non-semver (`dev`) → terminal `exit 1`, remediation `::error::`.
- **Non-vacuity:** confirm each new assertion FAILS against the current (unmodified) script before Phase 2.

### Phase 2 — Add the `/health` seam + resolve in the shared script
- Add a **distinct** `/health` test seam (THE load-bearing constraint): a `HEALTH_URL` override + a `HEALTH_STATUS_SOURCE_CMD` (or equivalent) that is **separate** from `DEPLOY_STATUS_SOURCE_CMD` — different URLs, different fixture body — so a test can drive "deploy-status=latest, /health=1.2.3" independently. Mirror `_get_status`'s seam shape.
- New `_resolve_known_good_tag()`: bounded `/health` curl (mirror `pin`'s 12× retry, `--max-time 15`, public endpoint — no CF-Access headers) → `jq -r '.version // ""'` → pipe through `resolve-web1-known-good-tag.sh` (reuse as-is). On failure emit a loud `::error::` (mirror `resolve-web1-known-good-tag.sh:56` wording + `_recovery_msg`) and `exit 1` — **never** fall back to the `.tag` seed (`cq-silent-fallback-must-mirror-to-sentry` — here the loud CI failure IS the mirror; no silent path).

### Phase 3 — Seed `DEPLOY_TAG` from `/health`, delete the `latest` band-aid
- Replace the `DEPLOY_TAG=CURRENT_TAG` seed (`:197`) with `DEPLOY_TAG="$(_resolve_known_good_tag)"`. Keep the baseline read for `exit_code` (skip on `-1` in-flight) and `PRE_START_TS` (staleness baseline) — those stay `.tag`-independent.
- **Delete** the `latest`-widened baseline guard alternation + its `:184-190` justification (`:191` `^(v[0-9]...|latest)$` → the tag is no longer read from `.tag`, so the guard's tolerance is dead). Truly-unknown `/health` values now abort in `_resolve_known_good_tag`.
- Leave the verify-poll `.tag` reads (`:219`/`:228`) and the `_trigger_fanout` downgrade guard (`:147-155`) **untouched**: after web-2's deploy, `.tag` reflects the POSTed semver so `TAG==DEPLOY_TAG` still matches; the downgrade guard already rejects `latest` (`:152`) and only adopts newer pinned tags.

### Phase 4 — ADR-079 amendment + green the suite
- Add the dated reader-inventory line to ADR-079 (see Architecture Decision).
- Run `bash apps/web-platform/infra/deploy-status-fanout-verify.test.sh` → all green (new T-A/B/C pass; AC4-latest / AC4-latest-resolve replaced; AC4-tag / AC4-tag-empty / staleness / degraded-retry / unexpected-reason / deploy-failed stay green).
- Run `bash apps/web-platform/infra/resolve-web1-known-good-tag.test.sh` (unchanged — must stay green).
- Confirm both parity tests stay green: `web-hosts-fanout-parity.test.sh` (no `WEB_HOST_PRIVATE_IPS:` env added/removed → `min_copies` unchanged) and `web-1-swap-concurrency-parity.test.sh` (no new swap job → count==4 unchanged).

## Files to Edit

- `apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh` — add `/health` seam + `_resolve_known_good_tag()`; seed `DEPLOY_TAG` from `/health`; delete the `latest` baseline band-aid; loud-abort on no-semver.
- `apps/web-platform/infra/deploy-status-fanout-verify.test.sh` — RED fixtures T-A/T-B/T-C with the distinct `/health` seam; replace AC4-latest / AC4-latest-resolve; assert `DEPLOY_POST_SINK` payload **contents** (currently the harness counts lines only — add a grep of the sink for the semver / absence of `latest`).
- `apps/web-platform/infra/fixtures/deploy-status/*.json` — add fixtures as needed (e.g. a `latest`-tag deploy-status body reused with a separate `/health` fixture; a `/health` non-semver body). Synthesized only (`cq-test-fixtures-synthesized-only`).
- `knowledge-base/engineering/architecture/decisions/ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md` — extend the #6147 reader-inventory paragraph (~`:356`) with the #6353 third-reader line.

## Files to Create

- (Optionally) a new `/health` fixture file under `apps/web-platform/infra/fixtures/deploy-status/` if a semver-`/health` body doesn't already exist. No new scripts (`resolve-web1-known-good-tag.sh` is reused as-is — CTO: no change).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `deploy-status-fanout-verify.sh` seeds `DEPLOY_TAG` from web-1 `/health .version` via `resolve-web1-known-good-tag.sh`; `git grep -n 'DEPLOY_TAG=.*CURRENT_TAG' apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh` returns **0** (the `.tag` seed is gone).
- [ ] The `latest`-widened baseline guard is deleted: `git grep -nE '\^\(v\[0-9\].*\|latest\)\$' apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh` returns **0**.
- [ ] The `/health` seam is **distinct** from the deploy-status seam: the script references a `HEALTH_URL` override separate from `DEPLOY_STATUS_URL`, and the test drives deploy-status=`latest` + /health=`v1.2.3` independently (T-A).
- [ ] T-A: with deploy-status `.tag=latest` and `/health=1.2.3`, the fan-out POST payload contains `v1.2.3` and NOT `latest` (assert on `DEPLOY_POST_SINK` contents); verify exits 0.
- [ ] T-B: `/health` unreachable → terminal `exit 1`, a named `::error::`, and **zero** fan-out POSTs of `latest` or the old `.tag` (no silent fallback).
- [ ] T-C: `/health` non-semver → terminal `exit 1` with a remediation `::error::`.
- [ ] `bash apps/web-platform/infra/deploy-status-fanout-verify.test.sh` all green; `resolve-web1-known-good-tag.test.sh` all green; `web-hosts-fanout-parity.test.sh` + `web-1-swap-concurrency-parity.test.sh` green.
- [ ] ADR-079 carries the dated #6353 third-reader inventory line under Amendment #5955; `grep -c '#6353' knowledge-base/engineering/architecture/decisions/ADR-079-*.md` ≥ 1.
- [ ] PR body uses `Closes #6353` (the code fix fully resolves the blast radius at merge; no post-merge operator write is required — live-state self-heal is incidental, not a gating step).

### Post-merge (operator)
- [ ] None required. Live-state correction of web-1's `.tag` is an incidental side effect of the `web-platform-release.yml` deploy triggered by this PR's `apps/web-platform/**` change, and of the next `/health`-resolved fan-out. **Automation:** not applicable — no operator action; a web-2 recreate re-verification is the natural next dispatch that unblocks #6178, run by whoever proceeds with the cutover.

## Test Scenarios

- Given web-1's deploy-status `.tag=latest` (inngest-restart pollution) and `/health` reports `1.2.3`, when the fan-out verify runs, then it POSTs `deploy web-platform <image> v1.2.3` (never `latest`) and proves web-2 acceptance via `reason=ok`.
- Given web-1's `/health` is unreachable for the full bounded retry, when the verify runs, then it aborts with a terminal `exit 1` and a named `::error::` — it does NOT fall back to the `.tag` seed and does NOT POST `latest`.
- Given `/health` reports a non-released version (`dev`), when the verify runs, then it aborts loud with a remediation (trigger a normal release first).
- Given a healthy web-2 that returns `reason=ok` on the first fan-out (warm-standby), when the verify runs, then the bounded fresh-boot degraded-retry never engages and it exits 0 — unchanged behavior.
- Given the deploy-status poll's own `.tag` read after a successful web-2 deploy, when `TAG==DEPLOY_TAG` (both the `/health`-resolved semver), then acceptance still matches — poll semantics unchanged.

## Domain Review

**Domains relevant:** engineering (CTO)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** CTO advisory delivered (folded in). Verdict: **Option B** (shared verify script self-resolves `/health` behind its own distinct test seam) over Option A (callers pass a resolved tag) — Option A re-introduces the two-divergent-copies drift #6040 eliminated and forces a Doppler/`APP_DOMAIN_BASE` + curl preamble into `warm_standby`'s verify step which has none today. **Do NOT build the optional-input hybrid** (asymmetric coverage). This is an **ADR-079 amendment**, not a new ADR. Keep narrow — do NOT fold in #6060 (web-2-only fan-out) or #6178 (inngest to its own host); #6178 is blocked on this. In-scope cleanup: delete the `latest` band-aid. Landing-broken mitigations are mandatory (this IS the prod-recovery path): RED fixtures first, the distinct `/health` seam (single highest-risk detail), no silent fallback to `.tag`, keep both caller fixture paths green in `infra-validation.yml`. Residual (accepted, out of scope): the inngest/git-lock writers keep polluting the shared slot until #6178 — the fix answers "why is web-1's tag `latest`" with "we stopped trusting it," not "we fixed the writer."

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
