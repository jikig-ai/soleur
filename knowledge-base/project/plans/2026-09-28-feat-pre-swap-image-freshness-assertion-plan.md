---
title: "feat(infra): abort a web deploy before the swap when the pulled image's baked version is not the requested tag (#6428)"
date: 2026-09-28
slug: feat-pre-swap-image-freshness-assertion
branch: feat-one-shot-6428-image-freshness
issue: 6428
closes: 6428
type: feat
lane: single-domain
brand_survival_threshold: aggregate pattern
---

# Pre-swap image freshness assertion in ci-deploy.sh (#6428)

## Overview

#6428: after the zot cutover, a zot that serves an **old but validly signed** image for a
requested tag passes every current control. `verify_image_signature` checks the signature of
whatever digest the tag resolved to, and an old image is validly signed. The only control that
notices is the release workflow's post-deploy `/health` check (`version == release`), which runs
**after** the stale container is already serving, and only on the ingress host.

This plan adds one check at the pull site, before the canary and the swap: read the
`BUILD_VERSION` baked into the image config of the ref about to be run (`VERIFIED_REF`: the
verified digest when the cosign verify passed; in WARN mode it can also be an unverified digest or
the tag, so the value is bound to the image's own bytes but signature-covered only on a passing
verify) and require it to equal the requested tag with the leading `v` stripped. The check fails
closed: on a mismatch the deploy aborts with `reason=image_stale_version`, and when the version
cannot be established (no `BUILD_VERSION`, `dev`, inspect failure) with
`reason=image_version_unverifiable`. The old container stays live, and a Sentry `error` event
(`op=image-freshness`, `freshness_result` in `version_mismatch|version_absent|inspect_failed`) pages
through a new IaC alert rule.

**Host coverage (explicit, not implied).** `ci-deploy.sh` reaches running hosts through
`terraform_data.deploy_pipeline_fix`, which pushes to **web-1 only** (#9151). web-2 keeps its
birth-time copy until its next replace. This change therefore covers web-1 on merge; web-2 is
covered only after a replace, tracked by #9151 (not fixed here).

## Research Insights

**Source.** Phase-B research (`phaseB-research.md` §2, 2026-09-28) plus re-verification against
`origin/main` @ `ec19040203` (after #9133 moved cosign to gcr.io and added the `cosign_absent`
pull classifier).

**Premise Validation.** #6428 is OPEN, no linked PR. #9151 is OPEN (web-2 never receives
ci-deploy.sh updates). Every cited site re-verified on the current tree:
- `ci-deploy.sh` web-platform case: `pull_image_with_fallback web` then
  `VERIFIED_REF="$LOCAL_CACHE_VERIFIED_REF"` or `VERIFIED_REF="$(verify_image_signature "$IMAGE:$TAG")"`,
  then the stale-canary cleanup, plugin seed, canary run, and swap. Nothing between verify and
  the canary inspects image content.
- Tag gate: `[[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]` → `tag_malformed`, before any pull.
- `apps/web-platform/Dockerfile`: `ARG BUILD_VERSION=dev` / `ENV BUILD_VERSION=$BUILD_VERSION`.
- `reusable-release.yml` build step: tags `${docker_image}:v${next}` and passes
  `BUILD_VERSION=${next}` (bare semver) — the only producer of the web image (`docker_image:` is
  set only by `web-platform-release.yml`). So a correctly built image always satisfies
  `BUILD_VERSION == ${TAG#v}`.
- `apply-deploy-pipeline-fix.yml`'s seccomp reload derives its tag as `v<.version from /health>`,
  which is the running image's `BUILD_VERSION` — self-consistent by construction.
- `_try_local_cache_reload` returns the running container's image ID only when that image carries
  a `<ref>:$TAG` RepoTag (same-version reload), so its `BUILD_VERSION` must match too.
- Precedent for reading image config env: the inngest branch's
  `docker inspect "$IMAGE:$TAG" -f '{{range .Config.Env}}{{println .}}{{end}}'`.
- Better Stack positive control: `betterstack-query.sh --grep "IMAGE_VERIFY: ok"` returns
  `SYSLOG_IDENTIFIER=ci-deploy` rows from today's deploys, so a new `logger -t ci-deploy` marker is
  queryable without SSH (vector.toml Source 4 allowlists the `ci-deploy` tag).
- The `#2205` note in `server.tf` about a cloud-init `write_files` copy of ci-deploy.sh is stale:
  `ci-deploy.sh` is in `local.host_script_files`, baked into the image and extracted at first boot
  (#5921). There is no second copy to keep in sync.

**Property List.**
1. P1: A web deploy whose pulled image is not the requested version never reaches the canary or
   the swap; the previously serving container stays live.
2. P2: That abort pages the operator without SSH (Sentry alert on first event) and is queryable in
   Better Stack and `/hooks/deploy-status` (`reason=image_stale_version`).
3. P3: A correctly built image, a same-version reload, a local-cache rescue of the running image,
   and a rollback to an older released image all still deploy (no false abort).
4. P4: An image whose version cannot be determined (no `BUILD_VERSION`, or `dev`, or the inspect
   fails) is refused too (fail closed): every image zot can serve for a v-tag has baked
   `BUILD_VERSION` since 2026-03, so the closed arm costs no legitimate deploy. [Updated 2026-09-28
   after plan review: was "indeterminate, no abort".]
5. P5: Every successful check leaves an `IMAGE_FRESHNESS: ok` marker in Better Stack, so a real
   web-1 deploy can be shown to have run the check.

**Cut List.**
- Digest pinning via the `/hooks/deploy` payload (issue's first suggestion) → P1 → changes the
  signed webhook contract, `hooks.json`, and the ci-deploy allow-list; the version self-consistency
  check buys P1 for the stale-image vector without it. Recorded as the upgrade path, not built.
- Freshness check for the inngest image → out of scope: that image bakes `INNGEST_CLI_VERSION`
  (the CLI's version), not the image tag, so there is no self-consistency value to compare.
- Cloud-init copy sync → no copy exists (see Premise Validation).
- Fixing web-2 delivery → #9151, a separate issue by instruction.

**Learnings applied.**
- `2026-07-15-sentry-event-frequency-threshold-unreachable-and-data-source-scope-403.md`: use
  `event_frequency_count value = 0` (fires on the first event of any group).
- Inngest `INNGEST_CLI_VERSION` hotfix (comment in ci-deploy.sh): considered and rejected as a
  precedent for fail-open — it concerns a different image whose old builds lacked the variable; the
  web image has baked `BUILD_VERSION` for every tag zot keeps (5 most recent `v*`).
- `lint-shell-capture-exit` S1: no `grep` inside a `$(...)` capture under `pipefail`; parse the env
  with a `while read` loop.
- Test mocks: a new `docker inspect` must be answered **before** the mock's mode `case`, or the
  `trace`-mode order assertions (`image|pull|stop|rm|run|exec|…`) gain an `inspect` and go red.

**Research Reconciliation — Spec vs. Codebase.**

| Claim | Reality | Plan response |
|---|---|---|
| research: verify call "around line 3246" | call is at ~3258 after #9133 | cite by content anchor, not line |
| issue: cosign verify at `ci-deploy.sh:1562` | moved; now `verify_image_signature` ~2248 | same |
| server.tf #2205: keep cloud-init copy in sync | no copy; baked host script | no cloud-init edit |

## Implementation Phases

### Phase 1 — RED (tests first)
In `apps/web-platform/infra/ci-deploy.test.sh`:
- Mock: a `docker inspect … .Config.Env …` handler placed **before** the mode `case`, scoped to
  non-inngest refs (inngest's own `.Config.Env` inspect keeps falling through, unchanged). It prints
  `BUILD_VERSION=<v>` where `<v>` is `MOCK_IMAGE_BUILD_VERSION` when set (`${VAR+x}` so an explicit
  empty means "no BUILD_VERSION line"), else derived from the tag in `SSH_ORIGINAL_COMMAND`
  (a correctly built image is the realistic default). It appends the inspected ref to
  `MOCK_FRESHNESS_INSPECT_FILE` when armed. `MOCK_IMAGE_INSPECT_FAIL=1` exits 1.
- Rows (new section `--- #6428 pre-swap image freshness ---`, all in trace mode):
  - F1 RED fixture: `MOCK_IMAGE_BUILD_VERSION=0.9.9`, deploy `v1.0.0` → exit ≠ 0,
    `reason=image_stale_version`, no `run`/`create` trace (no app container), error event with
    `freshness_result=version_mismatch`. On `origin/main` this deploy reaches the swap (RED).
  - F8a/F8b exact compare: `1.0.00` (prefix) and `11.0.0` (suffix) for `v1.0.0` → abort.
  - F9a/F9b whole-key parse: a decoy `X_BUILD_VERSION=1.0.0` printed first, with `BUILD_VERSION=0.9.9`
    → mismatch; with no `BUILD_VERSION` → `image_version_unverifiable`.
  - F3a/b/c fail closed: no `BUILD_VERSION`, `dev`, inspect failure → `image_version_unverifiable`,
    `freshness_result` `version_absent` / `inspect_failed`.
  - F5a local-cache rescue of a running image built as 0.9.9 → abort (second VERIFIED_REF arm).
  - F2 canonical must-PASS: exit 0, canary trace byte-identical to the canary-success row,
    `IMAGE_FRESHNESS: ok … expected=1.0.0 actual=1.0.0`, no freshness event.
  - F4 the inspected ref is the verified digest (`…@sha256:…`), exactly once.
  - F5b same-version local-cache reload of a matching image reloads; inspected ref = running image ID.
  - F7 must-PASS non-canonical: `v10.20.30` with explicit `BUILD_VERSION=10.20.30` deploys.
  - Suite floor `CI_DEPLOY_ASSERT_FLOOR` 342 → 355.
- `apps/web-platform/test/sentry-image-freshness-alert-op-contract.test.ts`: pins the op and
  `freshness_result` literals in BOTH `ci-deploy.sh` and `issue-alerts.tf`.

### Phase 2 — GREEN
In `apps/web-platform/infra/ci-deploy.sh`:
- `image_freshness_event <result> <ref> <expected> <actual> <detail>` next to `cosign_verify_event`
  (same env-guarded, fail-open Sentry store POST; always `level=error`; tags
  `feature=supply-chain op=image-freshness freshness_result=<result> host_id`; logger
  `IMAGE_FRESHNESS_FAIL: result=…` line).
- `verify_image_freshness <ref> <tag>`: one `docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$ref" 200>&-`;
  capture first (keeps the inspect rc), then parse `BUILD_VERSION` with a `while read` loop over
  `<<<`; returns 1 on mismatch or unverifiable and sets `FRESHNESS_ABORT_REASON`.
- Call site: immediately after the `VERIFIED_REF` if/elif block, before the stale-canary cleanup:
  `if ! verify_image_freshness "$VERIFIED_REF" "$TAG"; then … final_write_state 1 "$FRESHNESS_ABORT_REASON"; exit 1; fi`.

### Phase 3 — alert IaC
- `apps/web-platform/infra/sentry/issue-alerts.tf`: `sentry_alert.image_freshness_mismatch`
  (`name = "image-freshness-mismatch"`, `frequency_minutes = 28` — free, taken set is
  5,10-27,30,31,60-63,1440-1442; `event_frequency_count 1h value 0`; `logic_type = "all"` over
  `op eq image-freshness` — every such event is an aborted deploy; issue_owners → ActiveMembers).
- `apps/web-platform/infra/sentry/alert-reference.json`: matching projected entry (the PR-time
  `sentry-alert-reference-gate.sh` in `apply-sentry-infra.yml` `plan_pr` verifies it against the plan).
- Applied on merge by `apply-sentry-infra.yml` (paths `infra/sentry/**`). No bytes added to
  `apply-web-platform-infra.yml`.

## Files to Edit
- `apps/web-platform/infra/ci-deploy.sh`
- `apps/web-platform/infra/ci-deploy.test.sh`
- `apps/web-platform/infra/sentry/issue-alerts.tf`
- `apps/web-platform/infra/sentry/alert-reference.json`

## Files to Create
- `apps/web-platform/test/sentry-image-freshness-alert-op-contract.test.ts`

Not touched (by instruction): `cloud-init-registry.yml`, `zot-registry.tf`, the registry dispatcher.

## Open Code-Review Overlap

None (open `code-review` issues searched for both edited paths; no matches).

## User-Brand Impact

- **If this lands broken, the user experiences:** either (a) a false abort — every web deploy stops at `image_stale_version`, so fixes stop shipping while the current version keeps serving; or (b) a vacuous check — a stale app version (an already-fixed bug back in production) serves every user until the post-deploy `/health` check notices.
- **If this leaks, the user's data is exposed via:** nothing new; the Sentry event carries image refs and version strings only, no user content.
- **Brand-survival threshold:** `aggregate pattern`

## Observability

```yaml
liveness_signal:
  what: "logger -t ci-deploy 'IMAGE_FRESHNESS: ok ref=<digest> expected=<v> actual=<v>' on every web deploy that runs the check"
  cadence: "once per web-platform deploy (every release, plus seccomp reloads)"
  alert_target: "none for ok (liveness evidence only); the mismatch path pages via Sentry image-freshness-mismatch"
  configured_in: "apps/web-platform/infra/ci-deploy.sh verify_image_freshness; vector.toml Source 4 ships the ci-deploy tag to Better Stack"
error_reporting:
  destination: "Sentry store event op=image-freshness level=error + /hooks/deploy-status reason=image_stale_version|image_version_unverifiable"
  fail_loud: "yes: every refusal exits 1 before the canary; the release workflow's deploy-status poll reports the reason and goes red"
failure_modes:
  - mode: "stale-but-signed image served for the requested tag"
    detection: "BUILD_VERSION in the verified image config != TAG without v"
    alert_route: "Sentry alert image-freshness-mismatch (first event) -> email issue owners/ActiveMembers"
  - mode: "version unverifiable (no BUILD_VERSION, dev, inspect failed)"
    detection: "deploy aborts reason=image_version_unverifiable; IMAGE_FRESHNESS_FAIL log line; Sentry error event freshness_result=version_absent|inspect_failed"
    alert_route: "Sentry alert image-freshness-mismatch (same rule, op filter) -> email issue owners/ActiveMembers"
  - mode: "check never ran (host has an old ci-deploy.sh, e.g. web-2 per #9151)"
    detection: "absence of IMAGE_FRESHNESS rows for that host in Better Stack"
    alert_route: "tracked by #9151; not alerted here"
logs:
  where: "journald tag ci-deploy -> Better Stack (vector Source 4)"
  retention: "Better Stack source retention (paid tier since 2026-08-16)"
discoverability_test:
  command: "bash scripts/betterstack-query.sh --since 24h --grep 'IMAGE_FRESHNESS'"
  expected_output: "IMAGE_FRESHNESS"
  credentials_required: "Better Stack ClickHouse read connection (Doppler soleur/prd_terraform BETTERSTACK_QUERY_*) — deploy logs are not published on any unauthenticated surface"
```

## Guard Contract

### Guard 1 — pre-swap image freshness

**Property.** No web-platform deploy starts a canary or production container from an image whose baked `BUILD_VERSION` is a definite value different from the requested tag without its `v`.

**Assembly.** Every ref a web deploy can run flows through one chokepoint: the `VERIFIED_REF` assignment in the `web-platform)` case of `ci-deploy.sh`, which has exactly two arms (the local-cache rescue `LOCAL_CACHE_VERIFIED_REF`, and `verify_image_signature`'s echoed ref). The plugin-seed `docker create`, the canary `docker run` and the production `docker run` all consume `VERIFIED_REF`. The check sits after that assignment and before the first consumer, so it covers both arms.

**Mutation matrix.**

| # | Mutation (to ci-deploy.sh) | Row that must go RED |
|---|---|---|
| M1 | delete the call site | F1 (mismatch reaches the canary `run`) |
| M2 | `verify_image_freshness` body returns 0 unconditionally (own dispatch vacuous) | every abort row |
| M3 | move the call after the canary `docker run` (reorder, not delete) | F1 asserts no `run` trace before the abort |
| M4 | compare against `$TAG` instead of `${TAG#v}` | F2, F7 (must-PASS rows abort) |
| M5 | inspect `"$IMAGE:$TAG"` instead of `"$VERIFIED_REF"` | F4 |
| M6 | skip the check on the local-cache arm (second member after a compliant first) | F5 mismatch row |
| M7 | fail OPEN on missing/`dev` BUILD_VERSION or inspect failure | F3a/b/c, F9b |
| M9 | match the key as a substring (`*BUILD_VERSION=*`) | F9a |
| M10 | prefix/suffix compare (`== $expected*`) | F8a/F8b |
| M8 | emit the Sentry event with `level=warning` or a different `op` literal | every abort row's event assertion + op-contract test |

**Harness rows.** H1: if the mock ignored `MOCK_IMAGE_BUILD_VERSION` (always echoed the tag's version), F1/F8/F9/F5a go RED — the RED rows depend on the seam being wired. H2: F7 is a must-PASS input on a different release (`v10.20.30`, explicit version), so a guard that rejects everything, or one hard-wired to `v1.0.0`, is caught.

**Anchor.** Not a stored-value guard (compares two live values from the same signed image and the request), so no external anchor applies.

## Infrastructure (IaC)

### Terraform changes
`apps/web-platform/infra/sentry/issue-alerts.tf`: one new `sentry_alert` in the existing Sentry root (provider and backend unchanged). No new variables or secrets.

### Apply path
`apply-sentry-infra.yml` applies the full Sentry root on push to main (path filter `infra/sentry/**`). `ci-deploy.sh` reaches web-1 via `apply-deploy-pipeline-fix.yml` (`terraform_data.deploy_pipeline_fix`, path filter includes `ci-deploy.sh`) and fresh hosts via the baked image. No downtime: the script is replaced atomically; the next deploy uses it.

### Distinctness / drift safeguards
`alert-reference.json` is gated equal to the plan projection at PR time; the daily drift probe compares live Sentry to it. `lifecycle.ignore_changes = [environment]` like its siblings.

### Vendor-tier reality check
Sentry issue alerts are already in use at this tier (35 rules); no tier gate needed.

## Encryption Posture

```yaml
at_rest:
  - store: "none new — the change adds no persistent store"
    mechanism: "not applicable; no store introduced"
    evidence: "Files to Edit add a shell function, a test and one sentry_alert resource"
    defends_against: "not applicable"
    does_not_defend: "not applicable — no data at rest is created"
    disclosed_as: "not disclosed; no new store"
    live_verification: "not applicable"
in_transit:
  - connection: "web host -> Sentry store API (existing edge, same curl shape as cosign_verify_event)"
    tls: "HTTPS to https://${SENTRY_INGEST_DOMAIN}/api/<id>/store/"
    cert_verification: "on"
    does_not_defend: "a compromised host can forge or suppress the event"
    disclosed_as: "existing Sentry processing (DPD), unchanged"
```

## Architecture Decision (ADR/C4)

No ADR: this adds a check inside the existing ADR-087 verify step's trust boundary (same host, same image, same signed digest) and changes no ownership, substrate or dispatch boundary. C4: checked `model.c4`/`views.c4`/`spec.c4` — the actors (operator), systems (Sentry, Better Stack, zot) and the web-host → Sentry edge already exist; no element or relationship changes.

## Acceptance Criteria

### Pre-merge
- [ ] AC1: F1 is RED on `origin/main`'s `ci-deploy.sh` and GREEN after the change (`bash apps/web-platform/infra/ci-deploy.test.sh` → `355/355 passed`).
- [ ] AC2: all 13 #6428 rows GREEN; the pre-existing canary trace-order rows unchanged; the mutation matrix M1-M10 each reddens at least one row.
- [ ] AC3: op-contract vitest passes; `alert-reference.json` matches the plan projection (`plan_pr` gate green).
- [ ] AC4: `python3 scripts/lint-shell-capture-exit.py` adds no new finding for `ci-deploy.sh`; `bash -n` + shellcheck clean on the new function.
- [ ] AC5: PR body states web-1-only coverage and references #9151 for web-2; `Closes #6428` in the body.

### Post-merge
- [ ] AC6: `apply-deploy-pipeline-fix.yml` and `apply-sentry-infra.yml` runs for the merge sha succeed.
- [ ] AC7: a real web-1 deploy after the apply logs `IMAGE_FRESHNESS: ok` (Better Stack `--grep IMAGE_FRESHNESS`, host web-1) and the release deploy for the merge sha is served (`/health` version = release).
- [ ] AC8: live Sentry has the `image-freshness-mismatch` rule (fidelity probe in `apply-sentry-infra.yml` green).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change.

## Test Scenarios
See Phase 1 rows F1-F7 and the Guard Contract mutation matrix.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- The first deploy after merge may run on the old script if the release deploy reaches web-1 before `apply-deploy-pipeline-fix` lands; AC7 needs a deploy **after** the apply (the release build normally takes longer than the apply).
- web-2 is not covered until its next replace (#9151); do not claim it.
