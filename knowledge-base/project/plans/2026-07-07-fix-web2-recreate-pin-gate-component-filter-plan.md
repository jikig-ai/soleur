---
title: "fix(infra): web-2-recreate pin-gate resolves web-1's known-good tag from /health, not the contaminated deploy-status slot"
type: fix
date: 2026-07-07
issue: 6147
branch: feat-one-shot-6147-recreate-pin-gate-component-filter
lane: procedural
---

# fix(infra): web-2-recreate pin-gate reads deploy-status `.tag`, which a non-web writer wedges

## Overview

The `web_2_recreate` job in `.github/workflows/apply-web-platform-infra.yml` resolves web-1's
known-good running image tag by reading `https://deploy.soleur.ai/hooks/deploy-status` `.tag`
(step **"Resolve known-good image digest off-host (freeze $PINNED — AC3b TOCTOU)"**, `id: pin`,
`:1014`). The read at **`:1060`** — `TAG=$(echo "$BODY" | jq -r '.tag // ""')` — gates only on
`.exit_code==0`; it does **not** filter `.component`, and — more fundamentally — it reads the
ci-deploy **state file's last-ATTEMPT tag**, not web-1's actually-running image.

`/hooks/deploy-status` is a **single last-write-wins JSON object** (one frame, NOT an array —
`ci-deploy.sh` `write_state`, `apps/web-platform/infra/ci-deploy.sh:292`). Multiple independent
writers stamp that one slot:

| Writer | `.component` literal | Source |
|---|---|---|
| web-platform deploy | `web-platform` | `ci-deploy.sh:1058` (`read -r ACTION COMPONENT …`), case `:1181-1182` |
| inngest deploy / restart | `inngest` | `ci-deploy.sh`, `restart-inngest-server.yml` |
| git-lock sweep | `git-lock-chardevice-sweep` | `git-lock-chardevice-sweep.sh:100` |
| inngest wiped-volume verify | `inngest-wiped-volume-verify` | `inngest-wiped-volume-verify.sh:59` |

When a `restart-inngest-server` run (a scheduled watchdog, independent of any web release) is the
most recent writer, the slot holds `{"component":"inngest","tag":"latest","exit_code":0,"reason":"success"}`.
That frame passes the `exit_code==0` gate but yields `TAG=latest`, which fails the semver guard
`^v[0-9][A-Za-z0-9._-]*$` at `:1063`, so the pin-gate hard-aborts:

```
::error::could not read a valid, settled running tag from web-1 deploy-status (got 'latest').
Cannot resolve a known-good digest — aborting BEFORE any -replace.
```

Observed on run `28851593858` (2026-07-07). Because the slot holds one frame with no periodic web
re-write, the recreate stays blocked until the **next web-platform app deploy** re-stamps it.

**ADR-079 amendment #5955 already decided the correct source.** It established that
`/hooks/deploy-status` `.tag` is the ci-deploy state file's *last-ATTEMPT* tag (which the
Terraform bootstrap default and any rejected attempt leave as a non-semver value like `latest`) —
so the seccomp-reload path (`apply-deploy-pipeline-fix.yml:599-608`) resolves the running version
from the **public `/health` endpoint** (`.version` = the baked `BUILD_VERSION`) instead, and never
reads deploy-status `.tag`. The `web_2_recreate` pin-gate is an **un-swept reader** that never
adopted #5955. This fix brings it into line.

## Problem Statement / Motivation

`web_2_recreate` is the off-host verification path for the `#6090` fresh-boot / ghcr_login work
(PR `#6136`, merged CI-green). `#6090` stays open pending a green recreate. The recreate cannot be
dispatched-and-verified during any window a non-web writer (inngest restart, git-lock sweep, …)
owns the shared deploy-status slot. The safety property already holds — the job aborts **before**
any `-replace`, so web-1 and web-2 are both untouched — the defect is purely that a legitimate
recreate is **blocked**.

## Proposed Solution

**Resolve web-1's running tag from `https://app.<APP_DOMAIN_BASE>/health` `.version` and drop the
deploy-status `.tag` read entirely** (verbatim ADR-079 #5955; adopted over the issue's "filter by
component" sketch on the recommendation of the plan-review panel — see Alternatives + Decision
Challenge). `.version` is web-1's *running* container's baked `BUILD_VERSION` — it **is** the
known-good running tag by definition, and it is immune to deploy-status writer contention because
it never reads the shared slot.

1. **Resolve.** `RUNNING_VERSION=$(curl -sf --max-time 15 "https://app.${APP_DOMAIN_BASE}/health"
   | jq -r '.version // ""')`; `TAG="v${RUNNING_VERSION}"` (bare semver → prepend `v`), inside a
   bounded retry loop.
2. **Validate strictly.** Require `^v[0-9]+\.[0-9]+\.[0-9]+$` (the shape #5955 tightened to, the
   shape `ci-deploy.sh:1097` enforces, and the shape the release pipeline actually pushes —
   `reusable-release.yml:597,686` tag `:v${next}`). A non-released `/health`
   (`BUILD_VERSION` unset → `"dev"` → `"vdev"`) or a prerelease (`1.2.3-rc1`) fails loud with a
   remediation, never silently pins a floating/prerelease tag.
3. **Unchanged downstream.** The resolved `v<version>` still goes through the identical
   `docker buildx imagetools inspect … {{.Manifest.Digest}}` → `^sha256:[0-9a-f]{64}$` →
   `$PINNED` → **coherence preflight** (`:1089`, recomputes `host_scripts_content_hash`, aborts
   before `-replace` on mismatch). The safety envelope is untouched; only the tag *source* changes.

This deletes the entire deploy-status branch (component filtering, `exit_code` gating, the
`latest`-wedge failure mode) from the pin path — there is no `web`/`web-platform` literal to get
wrong, no last-write-wins contention, and no `.tag`-vs-running-image skew.

### Host-targeting invariant (LOAD-BEARING — resolves SpecFlow Gap 5)

`/health` must reflect **web-1**, not a partially-recreated web-2. This holds by construction in
the current topology: `cloudflare_record.app` (`apps/web-platform/infra/dns.tf:13-20`) is a
**single proxied A record hard-pinned to `hcloud_server.web["web-1"].ipv4_address`** — it is NOT a
multi-origin round-robin LB. Multi-host DNS rewire (one A record per host, CF round-robin) is
**explicitly deferred** to the operator maintenance-window cutover (`dns.tf:4-12`, #5274 Phase 3.D)
and does not exist yet. So `app.soleur.ai/health` == web-1 before, during, and after this recreate.
The resolver's callsite comment MUST cite `dns.tf:13` and name **#5274 (multi-host rewire) as the
revisit trigger** — if/when `app` becomes a round-robin record, this resolver must switch to a
web-1-pinned health path or re-add a host check.

### Architecture — extract the decision logic into a testable script

The pin logic is embedded in a workflow `run:` block, which cannot be fixture-tested. The workflow
already delegates its other off-host read to a script — `deploy-status-fanout-verify.sh` (called
at `:848`/`:1193`), whose test uses injectable seams. Follow that precedent (DHH-approved):

- Extract a **pure resolver** `apps/web-platform/infra/scripts/resolve-web1-known-good-tag.sh` that
  takes the fetched `/health` **version string** as input (arg/stdin — **no network inside the
  resolver**) and prints `v<version>` if it is strict semver, else exits non-zero with a clear
  diagnostic.
- The `pin` step keeps the curl **retry loop** against `app/health`, passes the fetched version to
  the resolver, then proceeds to digest resolution exactly as today.
- Unit-test the resolver with fixtures in `resolve-web1-known-good-tag.test.sh` and register it as
  an explicit `run:` step in `infra-validation.yml`.

*(Inline-in-workflow is a defensible simpler alternative — the resolver is ~4 lines — but the
extracted script + fixture test gives cheap regression protection on the semver guard and matches
the sibling precedent; kept as primary. Plan-review may collapse to inline.)*

## SpecFlow Findings & Resolutions

The SpecFlow pass audited the *hybrid* (component-filter + fallback) draft and found flow gaps.
Adopting pure `/health` **dissolves** most of them; the remainder are addressed:

| SpecFlow gap (against the hybrid draft) | Resolution under pure `/health` |
|---|---|
| G1: `web-platform`+`exit0`+`tag∈{latest,malformed}` → undefined outcome (could re-reproduce #6147) | Evaporates — no deploy-status `.tag` read at all |
| G2: in-flight web deploy (`exit_code=-1`) masked by a non-web last write | Evaporates — no `exit_code` read; `/health` returns the running (old) version, which is still known-good |
| G3: 2-outcome resolver contract can't express "retry" | Evaporates — resolver is cleanly two-outcome (tag \| non-zero); the retry loop lives in the workflow around the curl |
| G5: `/health` may return the wrong host (LB routes to web-2) | Resolved — `dns.tf:13` hard-pins `app` → web-1; multi-host deferred (#5274). Documented as the callsite invariant + revisit trigger |
| G1e: prerelease `/health` (`1.2.3-rc1`) silently rejected | Made explicit — strict `^v[0-9]+\.[0-9]+\.[0-9]+$` abort with a remediation message; covered by a fixture |
| Bounded loop / no hang | The curl retry loop has a fixed attempt cap; on exhaustion it aborts (before `-replace`). No tri-state, no unbounded wait |

## Research Reconciliation — Issue / Research / Review Claims vs. Codebase

| Claim | Codebase reality | Plan response |
|---|---|---|
| Fix via `select(.component=="web")` (issue option 1) | Producer writes `component="web-platform"`, and `.tag` is the last-ATTEMPT tag (#5955), not the running image | Superseded — resolve running version from `/health`, don't read the slot |
| `jq '.[] \| select(...)'` (learnings agent) | Slot is a **single object**, not an array (`ci-deploy.sh:292`) | Moot — no deploy-status read |
| Component filter is the established pattern | ADR-079 #5955 established `/health` resolution for exactly this "`.tag`=latest wedge" | Adopt #5955's `/health` source directly |
| `app.soleur.ai` is a round-robin LB (SpecFlow Gap 5 risk) | `dns.tf:13` — single A record hard-pinned to web-1; multi-host deferred to #5274 | `/health` is web-1-specific; document the invariant + revisit trigger |
| Loose pin regex `^v[0-9][A-Za-z0-9._-]*$` (`:1063`) | Release pushes strict `vX.Y.Z` (`reusable-release.yml:597`); `ci-deploy.sh:1097` enforces strict | Tighten resolver to `^v[0-9]+\.[0-9]+\.[0-9]+$`; no legitimate tag is rejected (Kieran-confirmed) |

## Sibling Reader Sweep

`deploy-status-fanout-verify.sh:219` also reads `.tag` without a component filter, from the **same**
`web_2_recreate` job (`:1193`). It runs *after* web-2's own deploy has stamped the slot with
`component=web-platform`, so it is not the failing surface. **Disposition: Acknowledge** (do not
fold in) — different purpose (fanout accept-check, not tag-pin); folding it in drags a second reader
with different semantics into the diff. If plan-review judges the sweep cheap it may be promoted;
otherwise a one-line follow-up note on #6147 tracks it. (Note: this reader's `.tag` need is also a
last-ATTEMPT-tag read and could likewise move to `/health` in a follow-up.)

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. `web_2_recreate` is an
  operator-dispatched CI verification path; a broken fix either leaves the recreate blocked
  (status quo) or aborts before `-replace` (safety preserved by the coherence preflight at
  `:1089`). No end-user artifact is on this path.
- **If this leaks, the user's data/workflow/money is exposed via:** nothing. The change reads a
  public `/health` version; writes no secrets, touches no user data.
- **Brand-survival threshold:** `none`

*Scope-out override (threshold `none`, diff touches sensitive paths `.github/workflows/` +
`apps/web-platform/infra/`):* `threshold: none, reason: the touched paths are an
operator-dispatched infra-recreate CI gate whose only failure modes are "recreate blocked" or
"abort before -replace" — both non-user-impacting; the digest/coherence safety gates downstream
are unchanged.`

## Observability

```yaml
liveness_signal:
  what:            "GitHub Actions job status for web_2_recreate (workflow_dispatch run)"
  cadence:         "per manual dispatch (recreate is operator-triggered, not scheduled)"
  alert_target:    "operator reads the Actions run log directly on dispatch"
  configured_in:   ".github/workflows/apply-web-platform-infra.yml (job web_2_recreate, step id: pin)"

error_reporting:
  destination:     "GitHub Actions run annotations (::error::) — the workflow surface itself"
  fail_loud:       "the pin step emits a distinct ::error:: naming the /health URL and the non-semver .version; the job fails red before -replace"

failure_modes:
  - mode:          "app/health unreachable or returns non-JSON"
    detection:     "curl retry loop exhausts its cap; resolver receives empty version; pin step ::error:: names the /health URL"
    alert_route:   "Actions run log (red run before -replace); operator investigates web-1 health"
  - mode:          "/health .version is non-released (dev) or prerelease (1.2.3-rc1)"
    detection:     "resolver exits non-zero; ::error:: names the rejected version + remediation (release web-platform first)"
    alert_route:   "Actions run log (red run before -replace)"
  - mode:          "semver-regex regression (resolver accepts a floating/prerelease tag)"
    detection:     "resolve-web1-known-good-tag.test.sh fixture case fails in infra-validation.yml CI"
    alert_route:   "CI red on the PR (blocks merge)"

logs:
  where:           "GitHub Actions run logs for apply-web-platform-infra.yml"
  retention:       "GitHub default (90 days)"

discoverability_test:
  command:         "gh run view <run-id> --log --job web_2_recreate | grep -E 'known-good|/health|running tag'"
  expected_output: "a line resolving the pinned tag from app/health .version (no 'got latest' abort)"
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/infra/scripts/resolve-web1-known-good-tag.sh` exists as a **pure**
      resolver (no network I/O; input = `/health` version string; output = `v<semver>` on stdout
      or non-zero exit + diagnostic).
- [ ] Resolver validates the final tag against `^v[0-9]+\.[0-9]+\.[0-9]+$` before emitting it
      (verify: `grep -c '0-9]\+\\\.\[0-9]\+\\\.\[0-9]\+' …` ≥ 1, i.e. the strict three-part anchor).
- [ ] `apps/web-platform/infra/resolve-web1-known-good-tag.test.sh` exists with fixture cases:
      (a) `.version=1.2.3` → prints `v1.2.3`; (b) `.version=""` (unreachable/empty) → non-zero, no
      tag; (c) `.version=dev` → non-zero, no tag; (d) `.version=1.2.3-rc1` (prerelease) → non-zero,
      no tag.
- [ ] The test is registered as an explicit `run:` step in `.github/workflows/infra-validation.yml`.
- [ ] `bash apps/web-platform/infra/resolve-web1-known-good-tag.test.sh` passes locally (all cases).
- [ ] `apply-web-platform-infra.yml` `pin` step resolves `APP_DOMAIN_BASE`
      (`doppler secrets get APP_DOMAIN_BASE --plain 2>/dev/null || echo "soleur.ai"`), curls
      `https://app.${APP_DOMAIN_BASE}/health` in a bounded retry loop, calls the resolver, and
      **no longer reads `/hooks/deploy-status` `.tag`** in the pin path. Add `DOPPLER_TOKEN` to the
      step `env:` (currently absent, `:1016-1022`).
- [ ] The pin step's `/health` curl uses **no CF-Access headers** (public endpoint — contrast the
      deploy-status curl which sends them at `:1038-1039`).
- [ ] The resolver callsite carries a comment citing `dns.tf:13` (app→web-1 hard-pin) and naming
      **#5274 (multi-host rewire) as the revisit trigger**.
- [ ] `actionlint .github/workflows/apply-web-platform-infra.yml .github/workflows/infra-validation.yml`
      is clean; validate embedded `run:` shell via `bash -c` extraction (do NOT `bash -n` the `.yml`).
- [ ] PR body uses `Ref #6147` (not `Closes`) — closure is post-merge after a green recreate.

### Post-merge (operator)

- [ ] Dispatch `gh workflow run apply-web-platform-infra.yml -f apply_target=web-2-recreate
      -f reason="verify #6147 fix"`; confirm the `pin` step resolves a tag from `app/health`
      instead of aborting on `got 'latest'`. **Automatable** via `gh` + `gh run watch`; fold into
      `/soleur:ship` post-merge verification.
- [ ] After a green recreate, `gh issue close 6147` and note on `#6090` that its off-host
      verification path is unblocked.

## Test Scenarios

- Given `app/health` returns `{"version":"1.2.3"}`, when the resolver runs, then it prints `v1.2.3`.
- Given `app/health` is unreachable (empty version), when the retry loop exhausts, then the pin
  step aborts **before** `-replace` with a `/health`-naming `::error::`.
- Given `app/health` returns `{"version":"dev"}` or `{"version":"1.2.3-rc1"}`, when the resolver
  runs, then it exits non-zero with a remediation, and the job aborts before `-replace`.
- **Regression (the bug):** Given run `28851593858`'s state (inngest owns the deploy-status slot),
  when a recreate is dispatched, then the pin step no longer reads that slot and no longer aborts
  with `got 'latest'`.

## Dependencies & Risks

- **Risk — host-targeting drift (SpecFlow Gap 5).** Mitigated by the `dns.tf:13` invariant
  (app→web-1) + the callsite comment naming #5274 as the revisit trigger. If the multi-host rewire
  lands first, this resolver must switch to a web-1-pinned health path.
- **Risk — `/health` returns a stale/cached `.version`.** Low: the endpoint is CF-proxied but
  `/health` is dynamic (not cached); the sibling `apply-deploy-pipeline-fix.yml` and
  `web-platform-release.yml:667` both rely on live `app/health`. Note in the resolver comment.
- **Dependency:** none new. No new infra/secret/vendor/DNS (`DOPPLER_TOKEN`, `APP_DOMAIN_BASE`
  already in `prd_terraform`).

## Alternative Approaches Considered

1. **Component-filter + `/health` fallback (the hybrid — issue option 1 realized).** Reads the
   deploy-status slot, trusts `.tag` only when `component=="web-platform"` && `exit_code==0`, else
   falls back to `/health`. **Rejected by the plan-review panel** (DHH, code-simplicity) and by
   SpecFlow: the `/health` fallback is mandatory regardless (a single non-web frame has no web tag
   to select), so the retained deploy-status read is a second, *less-correct* source (last-ATTEMPT
   vs running tag) that doubles the branch count and reintroduces the `web`/`web-platform` literal
   risk and SpecFlow gaps G1–G3. The `exit_code==0` settledness gate it "preserves" guards a
   mid-deploy state web-1 is not in during a recreate. See Decision Challenge.
2. **Pure component filter, no fallback (issue option 1b).** Rejected as insufficient: single
   last-write-wins slot with no periodic web re-write → retrying stays blocked until the next web
   deploy; improves the message but does not unblock.
3. **Component-scoped deploy-status slot (issue option 2).** Rejected as over-scoped: changes
   `ci-deploy.sh` `write_state` to track last-deploy per component plus a new read path — a larger
   blast radius across the deploy contract for a fix `/health` already achieves with zero
   writer-side change.

## Architecture Decision (ADR/C4)

**No new ADR.** This fix brings the `web_2_recreate` pin-gate reader into compliance with the
**existing** ADR-079 amendment #5955 (`/health`-derived running semver). No architectural decision
is created or reversed. **No C4 impact:** the change adds no external actor, external system,
container, or data-store, and no actor↔surface access relationship changes — `app/health` and the
web host are already-modeled edges; this only changes which endpoint a CI job reads. (Checked
`model.c4`/`views.c4`/`spec.c4` — the web host and its ingress are present; no element or
relationship is added or falsified.)

*Optional (advisory, for plan-review):* one-line bullet on ADR-079's reader inventory noting the
pin-gate reader now uses the #5955 `/health` source (`#6147`).

## Domain Review

**Domains relevant:** none

Infrastructure / CI-tooling change. No UI surface (no `components/**`, `app/**/page.tsx`,
`app/**/layout.tsx` → Product/UX Gate not triggered), no regulated-data surface (no
schema/migration/auth/API route → GDPR gate not triggered), no new infrastructure (no new
server/secret/vendor/DNS/cert → IaC gate not triggered; the change is shell-logic in an existing
workflow + a called script). Engineering is the implementing lane, not a business domain requiring
a leader consult.

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml` — `pin` step: resolve `APP_DOMAIN_BASE`, curl
  `app/health` in a bounded retry loop, call the resolver, add `DOPPLER_TOKEN` env, remove the
  deploy-status `.tag` read + `exit_code`/component logic from the pin path.
- `.github/workflows/infra-validation.yml` — add a `run:` step for the new resolver test.
- *(optional)* `knowledge-base/engineering/architecture/decisions/ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md`
  — one-line reader-inventory bullet (advisory).

## Files to Create

- `apps/web-platform/infra/scripts/resolve-web1-known-good-tag.sh` — pure semver resolver.
- `apps/web-platform/infra/resolve-web1-known-good-tag.test.sh` — fixture-driven unit test.

## Open Code-Review Overlap

None. (No open `code-review`-labelled issue references these paths.)

## References & Research

- Bug read site: `.github/workflows/apply-web-platform-infra.yml:1014-1090` (step `id: pin`),
  abort at `:1060`/`:1063`; pin step env at `:1016-1022`; deploy-status curl (CF-Access) at
  `:1038-1039`.
- `/health` source of truth: `apply-deploy-pipeline-fix.yml:599-608` (`.version // ""`,
  `TAG=v${…}`, public/no-CF-Access); `web-platform-release.yml:667` (`curl -sf app/health`).
- Release tag shape (strict semver): `reusable-release.yml:597` (`:v${next}`), `:686` (tags).
- Host-pin invariant: `apps/web-platform/infra/dns.tf:1-20` (`app` → `web["web-1"]`, multi-host
  deferred to #5274 Phase 3.D).
- deploy-status is last-ATTEMPT / single-object: `ci-deploy.sh:292` (write_state), `:1097` (strict
  semver guard), `:1181-1182` (`web-platform)` case), `:1058` (parse); `ci-deploy.test.sh:~2060`.
- Non-web writers: `restart-inngest-server.yml`, `git-lock-chardevice-sweep.sh:100`,
  `inngest-wiped-volume-verify.sh:59`.
- Script-extraction + test-seam precedent: `deploy-status-fanout-verify.{sh,test.sh}`
  (registered `infra-validation.yml:205`); `ci-deploy.test.sh:154`.
- ADR-079 amendment #5955 (`/health` resolution): `ADR-079-…-verification.md:328`.
- Related: `#6147` (this), `#6090` (blocked verification), `#6136` (merged ghcr_login fix),
  `#5955`/`#5960` (ADR-079 amendments).
