---
title: "feat(ci): auto-bump cloud-init inngest-bootstrap pin on vinngest-v* tag publish"
type: feat
date: 2026-09-19
slug: feat-auto-bump-inngest-bootstrap-pin
branch: feat-one-shot-auto-inngest-pin-bump
issue: 8359
closes: 8359
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# feat(ci): auto-bump cloud-init inngest-bootstrap pin on vinngest-v* tag publish

## Overview

Every `vinngest-v*` tag publish currently opens a drift window: the
`deploy-script-tests` drift guard (AC6/AC6b/Guard B in
`apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`) compares the
`soleur-inngest-bootstrap:vX.Y.Z@sha256:` pin at four sites in
`apps/web-platform/infra/cloud-init.yml` and
`apps/web-platform/infra/cloud-init-inngest.yml` against the semver-max
published tag, and goes red until a human lands a pin-bump PR. The drift has
been measured twice in one cycle (v1.1.31→v1.1.35, then v1.1.35→v1.1.37 within
24h). This plan makes the publishing workflow itself the bump author: after
`build-inngest-bootstrap-image.yml` pushes and signs a new tag+digest, a new
job in the same workflow rewrites the pin at all four sites, commits via the
soleur-ai GitHub App installation token (never a PAT, never the
non-event-firing GITHUB_TOKEN), and opens a pin-bump PR with auto-merge armed —
closing the drift window to the length of one CI cycle instead of
"until someone notices a red check".

## Problem Statement / Motivation

The `soleur-inngest-bootstrap` OCI image is published by
`.github/workflows/build-inngest-bootstrap-image.yml` on every `vinngest-v*`
tag push. The pin that fresh hosts boot lives in two cloud-init files, four
sites total (`IREF` + `ZIREF` in each of `apps/web-platform/infra/cloud-init.yml`
and `apps/web-platform/infra/cloud-init-inngest.yml`), and is a compound
`vX.Y.Z@sha256:` reference — the tag is what the drift guard compares, the
digest is what docker actually pulls.

`deploy-script-tests` (a job in `infra-validation.yml`; advisory, not a
required check) carries the AC6/AC6b/Guard B drift machinery in
`apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`: AC6 asserts
each file's pin equals the semver-max published `vinngest-v*` tag; AC6b asserts
two refs per file sharing one tag; Guard B asserts every `cloud-init*.yml` pin
site carries tag+digest, all identical. The instant a tag is pushed, AC6's
authoritative signal (git tags, not the registry) moves — and every
subsequent infra PR and main push goes red until a human writes the bump PR.
The drift class is measured: #8071 (v1.1.31 pin vs published v1.1.35) and the
v1.1.35→v1.1.37 drift within 24h of the previous bump; ten consecutive misses
(v1.0.1…v1.1.10) are what created the guard in the first place (#4675).

The toil is also the only step in the publish pipeline with no automation: tag
→ build → push → cosign → zot mirror are all mechanical, then a human greps a
run log for `Signed <image>@sha256:…`, hand-edits four sites, and opens a PR.

## Proposed Solution

Make the publishing run the bump author. Add a `bump-cloud-init-pin` job to
`build-inngest-bootstrap-image.yml`, ordered after `build` via `needs:`, that:

1. Checks out `main` (not the tag tree — the bump script and the files it
   edits live on the default branch), with `fetch-depth: 0` + `fetch-tags:
   true` so the semver-max tag computation sees the tag that triggered the run.
2. Resolves the published digest itself via `crane digest` — the only context
   in the pipeline that can bind tag↔digest authoritatively (the Guard B
   comment in the consumer test states PR-gating jobs cannot do this read;
   the publish job can and now does).
3. Runs `.github/scripts/bump-inngest-bootstrap-pin.sh`, a checked-out,
   unit-tested script that rewrites the compound pin at all four sites,
   commits with the `soleur-ai[bot]` identity, pushes a
   `soleur/inngest-pin-vX.Y.Z` branch, opens the PR, supersedes any stale
   bot-authored pin PR, and arms `--auto` squash merge.
4. Authenticates all GitHub writes via the soleur-ai GitHub App installation
   token minted inline (the `board-status-sync.yml` JWT→installation-token
   recipe; `hr-github-app-auth-not-pat`). The App token is load-bearing, not
   just policy: `GITHUB_TOKEN`-authored pushes do not fire `pull_request`
   events, so required checks would never run on the bump PR and auto-merge
   could never release it.

The target is always the **semver-max published tag** (identical to AC6's
authoritative signal), never blindly the triggered tag — a `workflow_dispatch`
re-publish of an older tag then correctly no-ops instead of opening a
downgrade PR.

## Technical Considerations

- **Where the logic lives.** The board-status-sync header states the repo
  convention: workflow logic lives in a unit-tested script; the YAML is a thin
  driver, because a workflow cannot be dispatch-tested from a feature branch.
  The bump job's `ref: main` checkout makes a checked-out script viable here
  (contrast with the `Resolve image tag` step, which must stay inline because
  the build job checks out the tag's tree — `test-inngest-bootstrap-tag-guard.sh`
  pins that invariant; this plan does not touch it).
- **Script/test placement.** `.github/scripts/bump-inngest-bootstrap-pin.sh` +
  `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`. The `test-*.sh`
  glob is auto-picked-up by `run-all.sh` → `guard-script-fixture-tests`
  (REQUIRED check, `merge_group`, no path filter), so the suite must be
  bash-only: `crane`, `gh`, and git are PATH-shimmed stubs per
  `scripts/board/set-board-status.test.sh` precedent. `MIN_SUITES=11` is a
  floor; adding a 12th suite needs no edit. No competing bump script exists —
  `git ls-files` + `git grep bump-inngest` across `scripts/` and
  `.github/scripts/` return zero hits; this location is canonical, not a
  duplicate.
- **Rewrite anchor.** Exactly four literals match
  `soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}` — 2
  per file (verified by grep: `cloud-init.yml` 736/742,
  `cloud-init-inngest.yml` 1358/1402). The ZIREF sites carry **variable
  registry prefixes** (`"$ZURL/jikig-ai/…"`, `"$ZOT_EP/jikig-ai/…"`), not
  `ghcr.io`, so the rewrite substitutes only the
  `soleur-inngest-bootstrap:<tag>@sha256:<digest>` suffix and leaves whatever
  precedes it untouched. A per-file replacement-count assertion (`== 2`) is
  the script's own anti-vacuity rail; `IREF="$ZIREF"` assignment lines contain
  no `soleur-inngest-bootstrap:` literal and cannot be hit by the anchor.
- **Digest provenance.** Export the signed digest from the `Cosign-sign the
  GHCR digest` step (add `id: sign` + a `digest=` output) and pass it to the
  bump job for cross-check; the script still re-resolves via `crane digest`
  and halts on mismatch — the passed value attests "what was signed", the
  crane value attests "what the tag resolves to now". **The cross-check is
  tag-conditioned:** the sign step runs under `mirror_only` too, so a
  `mirror_only` backfill of a non-max tag legitimately produces a signed
  digest that differs from the semver-max target's resolved digest. Compare
  `signed_tag` (from `steps.tag.outputs.tag`, already a step output) against
  the computed target: equal → enforce digest equality (halt on mismatch);
  unequal → the signed digest is for a different tag entirely — emit a note
  and skip the cross-check. Without this gate every non-max backfill reds
  the bump job.
- **Old-tag republish / dispatch.** `workflow_dispatch` re-publish of
  `vinngest-v1.1.30` while `v1.1.37` is max: script targets `v1.1.37`, pin
  already matches → `noop`, no PR. Same for `mirror_only` runs (digest
  preserved → noop).
- **Concurrent tags.** v1.1.38 and v1.1.39 published back-to-back: job-level
  `concurrency: { group: inngest-pin-bump, cancel-in-progress: false }`
  serializes the bump jobs; both compute semver-max → both target v1.1.39; the
  loser finds the branch/PR already exists and exits `existing`.
- **Supersede, don't stack.** Before opening, the script lists open
  `soleur/inngest-pin-*` PRs; any open PR for a different (older) target is
  closed with a "Superseded by <url>" comment — but only when its head-branch
  tip is bot-authored (the `fix-constraints-stage-b.yml` never-clobber-human-
  commits rule).
- **Zot-degraded mirror.** The mirror step is `continue-on-error` on the build
  path (`mirror_status=degraded` → Slack ⚠️, job stays green). The dedicated
  host's GHCR leg is dead (AP-016 lapsed read credential — it can only pull
  from zot), so a bump merged while zot does not serve the digest risks a
  dedicated-host boot pull failure that no PR gate can see. Design: the PR
  still opens (the pin is correct per the guard), but auto-merge is armed
  **only** when `mirror_status == 'ok'`; on `degraded` the script comments on
  the PR "auto-merge withheld — zot mirror degraded; verify zot serves
  `<digest>` before merging". `mirror_status` is exported as a build-job
  output.
- **CLA.** `soleur-ai[bot]` is on the CLA allowlist only when commits carry
  the `273333864+soleur-ai[bot]@users.noreply.github.com` author email
  (`cla.yml` comment + `fix-issue` Phase 5 pin). The script sets that identity
  explicitly; ambient runner git config is not trusted.
- **No tag minting.** #4326 (auto-mint `vinngest-v*` on infra push) is
  explicitly out of scope; if it lands, it feeds this same path unchanged.
- **Checkout credentials.** `persist-credentials: false` on the bump job's
  checkout — the `GITHUB_TOKEN` must not linger as `origin`'s credential next
  to an `x-access-token` push remote, and read-only is all the job needs.
- **Failure visibility.** A bump-job failure must not be silent — the drift
  guard stays red until reconciled, so on script failure the job posts a
  `SLACK_RELEASES_WEBHOOK_URL` notification (existing secret already wired in
  this workflow for the mirror-degraded path) naming the failed stage, then
  exits non-zero.

## Research Insights

**Reviewed-Coverage: sequential-fallback.** This plan ran inside a one-shot
pipeline subagent with no Task/fan-out primitive; the research, spec-flow,
and review passes below were executed sequentially inline by the orchestrator
rather than by the named agents.

**Premise Validation (Phase 0.6).** All cited premises verified live
2026-09-19: #8359 OPEN (filed today, `meta/machinery` label); #4326 OPEN and
out of scope; `build-inngest-bootstrap-image.yml` exists and is
`on: push: tags: ['vinngest-v*.*.*']`; all four pin sites verified at
`v1.1.37@sha256:e773fe5c…490bc` (`cloud-init.yml` IREF+ZIREF, `cloud-init-
inngest.yml` IREF+ZIREF — grep count 2 per file); `git tag --list 'vinngest-v*'`
semver-max is `vinngest-v1.1.37`; closed drift trackers #8071 and #6286
confirm the recurring class; `deploy-script-tests` confirmed advisory
(`infra-validation.yml` comment: "not in ruleset-ci-required.tf"). Nothing
stale found.

**Property List (Phase 0.6b).**

- P1: after every successful `vinngest-v*` publish, all four pin sites carry
  that tag+digest with zero human action (drift window → ~one CI cycle).
- P2: the bump lands through the PR path (ruleset + CI review preserved), not
  a direct push to `main`.
- P3: the written digest is bound to the tag by a registry read at publish
  time (the only point that CAN bind them).
- P4: re-runs, dispatches, and concurrent tags never produce duplicate or
  downgrade PRs (idempotent by construction).
- P5: failures are loud — a silent bump failure leaves the guard red with no
  signal naming why.

**Cut List (Phase 0.6b).**

- Scheduled drift-reconciler cron → buys P1 partially but reintroduces lag and
  a second trigger surface; the publish workflow already holds tag+digest.
  Rejected.
- Separate tag-triggered sibling workflow → races the build (digest may not
  exist yet when it fires); `workflow_run` ordering is weaker than `needs:`.
  Rejected.
- `peter-evans/create-pull-request` or `claude-code-action` wrapper → the
  wrapper-vs-curl check: this is ~15 lines of `git` + `gh` + `jq`; the
  wrapper's value (agent loops, generality) is absent. Rejected.
- Rewriting the "Bumped to vX.Y.Z / Run <id>" comment prose in the two
  cloud-init files → buys no guarded property (comments are historical prose,
  already stale at v1.1.17/v1.1.26 vs the v1.1.37 pin, and asserted by no
  guard); the PR body carries provenance instead. Cut from the writer's scope.
- New `.test.sh` under `apps/web-platform/infra/` → the suite needs no
  terraform/cloud-init, and `.github/scripts/test/` is the bash-only home that
  a REQUIRED, path-filter-free job auto-globs; placing it in the infra dir
  would require registration plumbing for zero gain. Rejected.

**Value-Proposition Measurement (Phase 0.6c).** The justification is toil +
drift-window removal, not a token/time saving claim — nothing to measure at
plan time beyond the drift evidence above.

**Relevant file paths.**

- `.github/workflows/build-inngest-bootstrap-image.yml` — publish pipeline;
  `Resolve image tag` step (`id: tag`); `Cosign-sign the GHCR digest` step
  (resolves `DIGEST` via `crane digest` inside a `run:` block, currently no
  `id:`); `zot_mirror` step (`mirror_status`/`mirror_reason` outputs); Slack
  notify step (`SLACK_RELEASES_WEBHOOK_URL` precedent); `concurrency:
  inngest-bootstrap-image-<ref>` at workflow level.
- `apps/web-platform/infra/cloud-init.yml:736,742` and
  `apps/web-platform/infra/cloud-init-inngest.yml:1358,1402` — the four pin
  sites, `soleur-inngest-bootstrap:vX.Y.Z@sha256:<64-hex>` each.
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — AC6
  (semver-max tag pipeline, `git -C tag --list 'vinngest-v*' | sort -V |
  tail -1`), AC6b (2 refs/file, 1 distinct), Guard B (all `cloud-init*.yml`
  sites: no tag-only, one tag, one digest, row6 tag↔digest co-move vs
  merge-base), plus its stated limit: binding digest to tag needs a registry
  read no PR-gating job can do — exactly the hole the bump job fills.
- `.github/workflows/board-status-sync.yml` — canonical inline App-JWT mint:
  Doppler `soleur/prd_terraform` `GITHUB_APP_ID`/`GITHUB_APP_PRIVATE_KEY` →
  openssl RS256 JWT → `POST /app/installations/122213433/access_tokens` →
  `GH_TOKEN`. App permissions verified live via
  `gh api /orgs/jikig-ai/installations`: `contents:write`,
  `pull_requests:write` both already granted.
- `.github/workflows/fix-constraints-stage-b.yml` — bot-PR conventions: `Ref
  #N` body line, `gh pr list --head` before `gh pr create`, never force-over a
  non-bot-authored tip.
- `.github/workflows/cla.yml` — `soleur-ai[bot]` allowlist +
  `273333864+soleur-ai[bot]@users.noreply.github.com` author-email contract.
- `.github/scripts/test/run-all.sh` — `test-*.sh` glob contract: bash-only,
  `MIN_SUITES=11` floor; `test-inngest-bootstrap-tag-guard.sh` is the
  shape-mirror precedent for asserting this workflow's YAML.
- `scripts/post-bot-statuses.sh` — existing synthetic-status escape hatch for
  bot commits; NOT used here: the bump PR should run real CI (its own
  deploy-script-tests run is the end-to-end verification of the bump).

**Institutional learnings applied.**

- `2026-05-25-app-jwt-inline-mint-…` — inline mint's five defensive
  properties; extract a composite action only at the third consumer (this is
  the third — board-status-sync, apply-github-infra, now this; flag the
  extraction option in the ADR, do not build it — two inline copies are the
  measured-cheap state and a third still leaves the threshold marginal).
- Learning in `fix-constraints-stage-b.yml` — never clobber human commits on
  a bot branch; check tip author before force-push.
- `#7630`/`#7695` — bumping tag without re-resolving digest pins new tag to
  old bytes; measured bypass. The bump resolves digest by command, always.
- `test-inngest-bootstrap-tag-guard.sh` header — workflow YAML shape +
  reimplemented-pipeline parity testing is the established way to pre-verify
  workflow invariants that cannot be dispatch-tested on a branch.
- `2026-05-11-…-architectural-false-trails` — wrapper-vs-curl check applied
  (Cut List above).

**External research (Phase 1.6).** Skipped — every mechanism in this plan is a
repo-established pattern (inline JWT mint, fixture-suite testing, thin-driver
YAML, Git Data/gh PR creation). No uncovered stack.

**Functional overlap (Phase 1.5b).** Grep for existing pin-bump automation:
zero hits — the three workflows touching `soleur-inngest-bootstrap`
(`build-…-image`, `deploy-inngest-image`, `apply-web-platform-infra`) only
read/deploy it. No existing mechanism writes the pin.

**Open code-review overlap (Phase 1.7.5).** Queried 65 open `code-review`
issues against every planned file path — **None**.

**Skill description budget (Phase 1.8).** No `SKILL.md` `description:` edit is
candidate — skipped.

**Related open issues (acknowledged, not folded):** #7632 (web-host tag-only
pin — Guard B row4 now asserts no tag-only site and `cloud-init.yml` already
carries digests; likely stale), #4699 (drift-guard doesn't verify
content-freshness of non-max tags — orthogonal), #7308 (inngest-cli version
freshness — different pin), #4326 (tag minting — out of scope).

**GDPR gate (Phase 2.7, inline).** Fired by trigger (d): the repo is public
and the mechanism auto-authors public PR bodies. Finding: no regulated-data
surface — PR body carries tag/digest/run-id/issue-ref machinery metadata;
commit identity is the existing `soleur-ai[bot]` noreply; no new vendor, no
personal data, no Art. 9 surface. Advisory: keep the PR body free of
user-derived content (it is templated constants). No criticals.

**SpecFlow pass (Phase 3, inline).** Edge enumeration: (a) tag pushed but
build fails → no bump, guard reds = correct (no image published; the tag
itself is the broken promise — deleting the tag or fixing the build is a
human call); (b) re-publish of old tag → noop; (c) `mirror_only` → noop;
(d) two rapid tags → serialized job, both target max, loser exits
`existing`; (e) rerun of an old publish → noop/`existing`; (f) human commits
on bot branch → `branch-has-manual-commits`, skip push, warn; (g) passed
digest ≠ crane-resolved → halt (sign/drift divergence is a stop-the-line
event); (h) tag-only ref somehow present → upgraded to full digest form by the
same rewrite (never left tag-only); (i) App scopes revoked → mint step fails
loud naming the scope.

**Scoped advisor consult (Phase 4.5).** Not available in this context (no
subagent primitive); highest-risk decisions recorded for deepen-plan review:
same-workflow vs sibling, auto-merge policy, semver-max vs triggered-tag
target.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| pin at ~lines 736/742 and ~1358/1402 | verified: 736/742 and 1358/1402, `v1.1.37@sha256:e773fe5c…` | bump script rewrites by regex, not line number |
| pin = tag AND sha256 | verified — both sites carry `vX.Y.Z@sha256:` | script substitutes the whole compound ref |
| "same workflow (or a triggered sibling)" | build job holds tag+digest in-hand; a tag-triggered sibling races the push | same workflow, `needs: build` job |
| GitHub App auth, never PAT | soleur-ai App (installation 122213433) verified to hold `contents:write` + `pull_requests:write`; repo `allow_auto_merge`/`allow_squash_merge`/`delete_branch_on_merge` all `true` (verified live via `gh api repos/jikig-ai/soleur`); inline-JWT mint is the repo recipe | reuse board-status-sync recipe verbatim; PAT absent by fixture assertion; auto-merge arm is repo-capable |
| drift guard "never goes red between publish and bump" | guard reds on the tag push itself (git-tag signal precedes any PR); window closes only on bump merge | auto-merge armed → window ≈ one CI cycle; stated honestly, not "zero" |

## User-Brand Impact

- **If this lands broken, the user experiences:** scheduled Inngest background
  work (email triage, crons) stalls on the next fresh dedicated-host or
  web-host boot — the pinned image is unreachable or stale; the failure
  surfaces as an infra alert before any user-visible feature degrades, but a
  worst-case wrong-digest merge could delay a host rebuild carrying a fix.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  nothing user-derived — the automated artifact is a PR containing registry
  tag/digest constants on a public repo; the App token is the only credential
  and it never reaches the PR or logs (masked per the mint recipe).
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the touched surfaces are CI/infra plumbing whose
  failure modes are a red advisory check, a failed workflow run, or a delayed
  host image update — no user data or user-facing artifact is in the write
  path.`

## Observability

```yaml
liveness_signal:
  what: "bump PR opened (or noop/existing recorded) by the bump-cloud-init-pin
         job inside every vinngest-v* publish run; drift-guard green on the
         next deploy-script-tests run after merge"
  cadence: "per vinngest-v* publish (event-driven, needs: build)"
  alert_target: "GitHub Actions run failure + SLACK_RELEASES_WEBHOOK_URL"
  configured_in: ".github/workflows/build-inngest-bootstrap-image.yml (bump-cloud-init-pin job + failure-notification step)"
error_reporting:
  destination: "workflow run log (stage-named ::error) + Slack releases webhook on job failure"
  fail_loud: "script exits non-zero naming the stage (mint|resolve|rewrite|push|pr|merge); a failed publish that leaves the guard red also posts to Slack"
failure_modes:
  - mode: "App credentials absent/invalid in Doppler soleur/prd_terraform"
    detection: "mint step exits 1 with ::error naming GITHUB_APP_ID or GITHUB_APP_PRIVATE_KEY (mirrors board-status-sync)"
    alert_route: "workflow failure + Slack notification step"
  - mode: "crane digest cannot resolve the target tag at GHCR, or resolved != signed digest"
    detection: "script halts non-zero naming tag + both digests"
    alert_route: "workflow failure + Slack notification step"
  - mode: "bot branch tip carries human commits"
    detection: "script emits branch-has-manual-commits, skips the push"
    alert_route: "::warning in run log; PR left for humans"
  - mode: "PR create or auto-merge arm fails"
    detection: "gh rc != 0 surfaced as stage failure; an un-armed PR also stays visibly open and the next publish's supersede sweep re-reports it"
    alert_route: "workflow failure or ::warning + advisory deploy-script-tests red until merged"
logs:
  where: "GitHub Actions run log, job bump-cloud-init-pin, in the publish run"
  retention: "GitHub Actions default retention (90 days)"
discoverability_test:
  command: "bash .github/scripts/test/test-bump-inngest-bootstrap-pin.sh"
  expected_output: "per-assert PASS lines and a final results line reporting 0 failures (e.g. 'RESULTS: N pass, 0 fail')"
```

## Encryption Posture

```yaml
at_rest:
  - store: "none — no persistent store is introduced; the mechanism writes
           only git refs + a PR via the GitHub API"
    mechanism: "n/a — no store (declared negative; not a placeholder — there is no data at rest to posture)"
    evidence: "diff inspection: Files-to-Create/Edit below contain no volume/bucket/table/queue/cache/log-sink resource"
    defends_against: "n/a"
    does_not_defend: "any pre-existing store's posture — unchanged by this plan and not claimed here"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable:no store exists to verify"
in_transit:
  - connection: "CI runner -> ghcr.io (crane digest, docker login already established by build job's packages: write GITHUB_TOKEN)"
    enforced_at: ".github/workflows/build-inngest-bootstrap-image.yml — existing GHCR login + crane usage"
    tls: "https/443, TLS >= 1.2 (registry endpoint)"
    cert_verification: "on (default crane/net-stack verification; no --insecure flag anywhere in the file)"
    does_not_defend: "a digest that is correct-but-for-the-wrong-tag — covered by the script's signed-vs-resolved cross-check, not by TLS"
    disclosed_as: "not-publicly-claimed"
  - connection: "CI runner -> api.github.com (installation-token exchange, git push, gh pr create/merge)"
    enforced_at: ".github/scripts/bump-inngest-bootstrap-pin.sh + the mint step (HTTPS endpoints, x-access-token remote)"
    tls: "https/443, TLS >= 1.2"
    cert_verification: "on"
    does_not_defend: "scope misuse of a validly-issued token — bounded by the App's repo-scoped permissions and the never-clobber-human-commits check"
    disclosed_as: "not-publicly-claimed"
  - connection: "CI runner -> api.doppler.com (GITHUB_APP_ID / GITHUB_APP_PRIVATE_KEY read, soleur/prd_terraform)"
    enforced_at: "bump job Doppler step (DopplerHQ/cli-action, DOPPLER_TOKEN env)"
    tls: "https/443, TLS >= 1.2"
    cert_verification: "on"
    does_not_defend: "credential exposure via runner logs — mitigated by per-line ::add-mask:: on the PEM and token (mirrored from board-status-sync)"
    disclosed_as: "not-publicly-claimed"
# exception: absent — no plaintext-exception mechanism and no cert_verification: off row
```

## Guard Contract

### Guard 1 — bump-script behavior suite (`.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`, behavior section)

**Property.** Every invocation of the bump script either rewrites all four
pin sites atomically to `<semver-max tag>@<registry-resolved digest>`,
exits `noop`/`existing` with zero writes, or exits non-zero — it can never
emit a partial bump, a tag-only site, a divergent-digest site, or a downgrade.

**Assembly.** The single writer `.github/scripts/bump-inngest-bootstrap-pin.sh`
— all of its write paths (file rewrite, commit, branch push, PR create/close/
comment/merge) — quantified over the two target files and over its trigger
inputs (`--signed-tag`, `--signed-digest`, `--mirror-status`, repo tag set).
The chokepoint is the script itself: no other code path writes these refs.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture with `cloud-init.yml` IREF bumped but ZIREF left stale (partial prior bump) | script exits non-zero or repairs to 4 identical refs; suite asserts no `tag-only` and `distinct==1` — RED if either remains |
| 2 | Remove the script's own per-file replacement-count assertion (guard's own dispatch: a rewrite reporting "0 replaced" and continuing) | RED — suite's anti-vacuity floor on assert count + a fixture whose write must land fails |
| 3 | Repo tag set where triggered tag `v1.1.38` < semver-max `v1.1.39` (second member after a compliant first) | RED unless the script targets `v1.1.39`, proving target selection is max-driven not arg-driven |
| 4 | Stub `gh` that returns a human-authored tip on the bot branch | RED unless script emits `branch-has-manual-commits` and skips the push |
| 5 | `--signed-digest` differing from the crane-stubbed resolution while `--signed-tag == semver-max target` | RED unless the script halts on the signed-vs-resolved mismatch |
| 5b | `--signed-digest` differing from resolution while `--signed-tag != target` (mirror_only backfill of a non-max tag — the sign step re-signs the DISPATCHED tag, not the max) | PASS/no-halt — cross-check is tag-conditioned; emits a note, never a spurious RED on a benign backfill |
| 6 | Suite-only: delete the noop fixture's assertion that `gh pr create` was never invoked (must-PASS path) | RED — a noop that still opens a PR must be caught |
| 7 | Must-PASS non-canonical: fixture files where ZIREF legs carry different quoting/prefix shapes but the same compound ref | PASS — permitted difference (mirrors Guard B H2), pins still rewrite correctly |

**Anchor.** The suite stubs `crane`/`gh`/git via PATH shims; the tag↔digest
binding it asserts is anchored outside the commit by the publish run's own
registry read at runtime — a weakening that only stubs `crane` differently
inside the suite cannot pass the real job, and the workflow-shape section
(Guard 2) pins the job wiring that feeds the script its inputs.

### Guard 2 — workflow-shape + parity assertions (same suite, shape section, mirroring `test-inngest-bootstrap-tag-guard.sh`)

**Property.** The `bump-cloud-init-pin` job is structurally present and
correctly wired in `build-inngest-bootstrap-image.yml`: ordered after build,
checking out `main` with tags, writing through the App-token path only.

**Assembly.** `.github/workflows/build-inngest-bootstrap-image.yml` job
block, the `build` job's `outputs:` (tag, digest, mirror_status), the `id:
sign` + `digest=` output on the cosign step, job `concurrency`, the checkout
`ref: main` + `fetch-tags` + `persist-credentials: false`, the Doppler
`prd_terraform` + `INSTALLATION_ID` literals, and the parity between the
script's semver-max tag-selection regex and AC6's pipeline in
`cloud-init-inngest-bootstrap.test.sh`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete `needs: build` (or rename the job) from the workflow | RED — shape assert on job wiring fails |
| 2 | Change the bump checkout to the tag ref or drop `fetch-tags: true` (semver-max input silently wrong — the guard's own dispatch blind spot) | RED — shape asserts on `ref: main` + `fetch-tags` fail |
| 3 | Add a `GH_TOKEN_PAT` / `secrets.*PAT` reference anywhere in the workflow (a second auth path after a compliant first) | RED — absent-token assert fails (hr-github-app-auth-not-pat). Asserted literal must be the precise `GH_TOKEN_PAT`/`secrets\.[A-Z_]*PAT` form, NEVER a bare `PAT` substring — `dispatch` (already in this file) contains `pat` and a bare grep is red on the compliant tree |
| 4 | Drop `digest=` from the sign step's `$GITHUB_OUTPUT` while keeping `id: sign` | RED — output-plumbing assert fails |
| 5 | Diverge the script's tag-selection regex from AC6's (e.g. lexicographic `sort` or a different tag glob) | RED — parity grep across the two files fails |
| 6 | Must-PASS non-canonical: workflow whose `mirror_status` output is absent but sign/tag outputs present | PASS on the auth/ordering asserts, RED on the mirror_status assert — a partial wiring must not green the whole section |

**Anchor.** These are structural asserts over YAML literals + a cross-file
regex parity — the anchor is AC6's own pipeline text in the consumer test
(independently reviewed machinery), not a copy embedded in the suite.

## Architecture Decision (ADR/C4)

This plan makes an architectural decision worth recording: it adds a new
event-driven repo-write automation (tag publish → App-token PR + auto-merge),
a third consumer of the soleur-ai App credential boundary, and a new
invariant ("pin follows publish within one CI cycle").

- `### ADR` — create **ADR-230** (provisional ordinal — `ship`'s ADR-Ordinal
  Collision Gate re-verifies against `origin/main`; on renumber, sweep
  `grep -rn 'ADR-230' knowledge-base/project/{plans,specs}/feat-one-shot-auto-inngest-pin-bump/`):
  *"Pin-bump PRs are authored by the publishing workflow via the soleur-ai
  App installation token — never a scheduled reconciler, never GITHUB_TOKEN,
  never a direct push."* Alternatives Considered must record: scheduled
  reconciler cron (reintroduces lag + second trigger), `workflow_run` sibling
  (weaker ordering than `needs:` + new-file registration), `GITHUB_TOKEN`
  writes (pushes don't fire `pull_request` events → required checks never
  run → unmergeable), direct-to-main push (violates the PR-required ruleset
  and forfeits the PR's own deploy-script-tests verification), and the
  composite-action extraction threshold from the app-jwt-inline-mint learning
  (third consumer — still below the extract line per its own guidance).
- `### C4 views` — Container view in
  `knowledge-base/engineering/architecture/diagrams/model.c4`: the `github`
  system gains a documented repo-write relationship for tag-publish-driven
  pin-bump PRs (pattern follows the modeled `github -> soleurMarketplace`
  App-write edge; a `github -> github` edge or an extension of the existing
  App-write edge description — implementer picks whichever renders in
  `views.c4`). Completeness check performed against all three `.c4` files:
  no new external human actor, no new external system (GHCR, Doppler,
  api.github.com, the soleur-ai App are all already modeled), no new
  container/data-store; the only new element is the github-internal
  write relationship. Run `apps/web-platform/test/c4-code-syntax.test.ts` +
  `c4-render.test.ts` after the edit.
- `### Sequencing` — the ADR is authored in this PR describing the mechanism
  as-built (`status: accepted` once the first live publish exercises it; an
  `adopting` note until then).

## Files to Create

- `.github/scripts/bump-inngest-bootstrap-pin.sh` — the bump writer (contract below).
- `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh` — fixture suite, bash-only, PATH-shimmed `crane`/`gh`/git (auto-globbed by `run-all.sh` → required `guard-script-fixture-tests`).
- `knowledge-base/engineering/architecture/decisions/ADR-230-*.md` — per the ADR task above.
- `knowledge-base/project/specs/feat-one-shot-auto-inngest-pin-bump/tasks.md` — generated at Save Tasks.

## Files to Edit

- `.github/workflows/build-inngest-bootstrap-image.yml` —
  (a) add `id: sign` to the `Cosign-sign the GHCR digest` step and
  `printf 'digest=%s\n' "$DIGEST" >> "$GITHUB_OUTPUT"` next to the existing
  summary line;
  (b) add `outputs:` on `jobs.build`: `tag: ${{ steps.tag.outputs.tag }}`,
  `digest: ${{ steps.sign.outputs.digest }}`, `mirror_status: ${{ steps.zot_mirror.outputs.mirror_status }}`;
  (c) append job `bump-cloud-init-pin` (contract below).
- `knowledge-base/engineering/architecture/diagrams/model.c4` — repo-write
  relationship for the pin-bump automation (see ADR/C4 task).
- `knowledge-base/engineering/architecture/diagrams/views.c4` — `include` the
  new relationship/element if a new edge is added.

*(No edit to `apps/web-platform/infra/cloud-init*.yml` in this PR — the pins
are current at v1.1.37; the automation owns them from the next publish. No
edit to `cloud-init-inngest-bootstrap.test.sh` — parity is asserted from the
new suite, which reads it.)*

## Implementation Phases

### Phase 1: the bump script + fixture suite (TDD)

1. Write `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh` FIRST
   (failing): fixture git repo with synthetic `vinngest-v*` tags + fixture
   copies of the two cloud-init files; PATH-shimmed `crane` (returns a
   configured digest), `gh` (records `pr create/close/comment/merge` calls,
   serves `pr list`), git real (fixture repo). Cover the mutation-matrix rows.
2. Write `.github/scripts/bump-inngest-bootstrap-pin.sh` until green:
   - args: `--tag <vX.Y.Z> --digest <sha256:…> --mirror-status <ok|degraded|>`
     plus `--dry-run` (no writes — used by the suite for the pure paths);
   - validate inputs (fail closed on malformed tag/digest);
   - compute target = semver-max `vinngest-v*` via the AC6-identical pipeline
     (`git -C <repo> tag --list 'vinngest-v*' | sed 's/^vinngest-//' |
     grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1`);
   - `crane digest ghcr.io/jikig-ai/soleur-inngest-bootstrap:<target>` →
     resolved digest, fail closed on unparseable; when `--tag == target`
     assert `--digest == resolved` (halt on mismatch);
   - idempotent: all four refs already `:<target>@<resolved>` → `result=noop`;
   - rewrite both files with one anchored substitution
     (`soleur-inngest-bootstrap:v…(@sha256:…)?` → `:<target>@<resolved>`),
     assert exactly 2 substitutions per file, zero tag-only refs remaining,
     `distinct==1`;
   - git: `git config user.name 'soleur-ai[bot]'` +
     `user.email '273333864+soleur-ai[bot]@users.noreply.github.com'`, branch
     `soleur/inngest-pin-<target>`, commit `chore(infra): bump
     inngest-bootstrap pin <old> -> <target> (vinngest-<target>)`;
   - push via `https://x-access-token:${GH_TOKEN}@github.com/<repo>.git`;
     remote-tip bot-authored check before any force; human tip →
     `branch-has-manual-commits`, no push;
   - PR: `gh pr list --head` → exists ⇒ comment + `result=existing`; else
     `gh pr create --base main` (title above; body: tag, digest, publishing
     run URL, `Ref #8359` on its own line, mirror-degraded note when set);
   - supersede: close open `soleur/inngest-pin-*` PRs for other targets with a
     `Superseded by <url>` comment, bot-tip check first;
   - auto-merge: `gh pr merge --auto --squash` iff `--mirror-status == 'ok'`,
     else PR comment explaining the hold; arm-failure → `::warning`, not fatal;
   - emit `result=opened|existing|noop|skipped|error` + GITHUB_STEP_SUMMARY.

### Phase 2: workflow wiring

3. `build` job: `id: sign` + `digest=` output; `outputs:` block (tag, digest,
   mirror_status).
4. New `bump-cloud-init-pin` job: `needs: build`; `runs-on: ubuntu-latest`;
   `timeout-minutes: 10`; `concurrency: { group: inngest-pin-bump,
   cancel-in-progress: false }`; `permissions: { contents: read }`; steps —
   checkout (`ref: main`, `fetch-depth: 0`, `fetch-tags: true`,
   `persist-credentials: false`), install crane (same pinned recipe as the
   build job's), install Doppler CLI, verify `secrets.DOPPLER_TOKEN`, mint
   soleur-ai installation token (inline JWT recipe, `DOPPLER_CONFIG:
   prd_terraform`, `INSTALLATION_ID: "122213433"`), run the script with the
   three job outputs as args, then a `if: failure()` Slack-notification step
   reusing `SLACK_RELEASES_WEBHOOK_URL`.

### Phase 3: ADR + C4

5. ADR-230 (provisional) + `model.c4`/`views.c4` repo-write relationship;
   run the two c4 tests.

## Success Metrics

- Next `vinngest-v*` publish opens a pin-bump PR within the same run and it
  merges without human action; `deploy-script-tests` never reports drift for
  that tag on any subsequent run.
- Zero manual pin-bump PRs after this ships (the chore-PR class that #6286 and
  #8071 tracked disappears).

## Dependencies & Risks

- **App scope regression.** Verified live today (`contents:write` +
  `pull_requests:write` on installation 122213433); a future permission change
  fails loud at the mint step, named. The failure mode is a red workflow +
  Slack post, not a silent gap.
- **Merge-queue latency.** Required checks run on the bump PR (ci.yml has no
  path filter); the drift window is bounded by check duration (~tens of
  minutes), not human notice.
- **`mirror_status=degraded` holds auto-merge** — a zot outage then still
  requires a human merge after verification, by design (dedicated host cannot
  pull from GHCR).
- **Tag-push-without-image edge.** AC6 fires on the git tag even if the build
  fails; a failed publish still reds the guard until the tag is deleted or
  the build is fixed — stated so nobody reads a post-failure red as a bump-mechanism
  defect.

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| Scheduled drift-reconciler cron | reintroduces lag (the exact defect); a second trigger to keep honest; publish workflow already holds tag+digest |
| Tag-triggered sibling workflow | fires before the digest exists → races the build; `workflow_run` is weaker ordering than `needs:`; new file also pays the workflow-registration cost |
| `GITHUB_TOKEN` push/PR | token-authored pushes don't fire `pull_request` events → required checks never run → PR can never merge; also bypasses review |
| Direct push to `main` (App bypass) | violates the PR-required ruleset spirit and forfeits the bump PR's own deploy-script-tests verification — the one run that exercises the guard against the bump |
| `peter-evans/create-pull-request` | wrapper-vs-curl: ~15 lines of git/gh/jq; the wrapper's constraints (token handling, mandated ordering) buy nothing for a single-PR flow |
| Extend `deploy-inngest-image.yml` | dispatch-only deploy webhook trigger; wrong lifecycle (deploy, not publish) |

## Non-Goals

- Minting `vinngest-v*` tags on infra push (#4326 — adjacent, explicitly out).
- Updating historical "Bumped to vX.Y.Z"/"Run <id>" comment prose in the two
  cloud-init files (already stale; asserted by no guard; provenance moves to
  the PR body).
- Making `deploy-script-tests` a required check, or extending Guard B to a
  registry read (the bump is what makes the binding possible; the guards are
  unchanged).
- Host-side rollout of the new pin (existing deploy-webhook/immutable-redeploy
  paths own that).

## Open Code-Review Overlap

None — 65 open `code-review` issues queried 2026-09-19 against every path in
Files to Create/Edit; zero matches.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. No
UI-surface files in Files to Create/Edit (mechanical override checked: no
`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`; no path
matching the ui-surface-terms superset), so the Product/UX gate is NONE.
No brainstorm ran (pipeline entry); no specialist carry-forward applies.

## Acceptance Criteria

- [ ] AC1: `.github/scripts/bump-inngest-bootstrap-pin.sh` exists, is executable, and rewrites all four `soleur-inngest-bootstrap:v…@sha256:…` sites across `cloud-init.yml` + `cloud-init-inngest.yml` to `<target>@<resolved>` in a single commit — verified by the fixture suite.
- [ ] AC2: `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh` exists under the `test-*.sh` glob, is bash-only (no terraform/cloud-init/apt/network), and covers every mutation-matrix row in the Guard Contract including an anti-vacuity assertion floor.
- [ ] AC3: `build-inngest-bootstrap-image.yml` carries the `bump-cloud-init-pin` job with `needs: build`, `ref: main` + `fetch-tags: true` + `persist-credentials: false` checkout, job-level `concurrency: inngest-pin-bump`, `permissions: { contents: read }`, and the inline App-JWT mint (`DOPPLER_CONFIG: prd_terraform`, `INSTALLATION_ID: "122213433"`).
- [ ] AC4: The `build` job exports `tag`, `digest` (from `id: sign`), and `mirror_status` outputs consumed by the bump job.
- [ ] AC5: No PAT anywhere: the workflow contains no `GH_TOKEN_PAT`/`secrets.*PAT` reference and the script pushes only via `x-access-token` with the minted installation token (asserted by the suite).
- [ ] AC6: The script targets the semver-max published tag, not blindly the triggered tag (re-publish of an older tag ⇒ `noop`), and halts when the passed signed digest ≠ the crane-resolved digest for that tag.
- [ ] AC7: Idempotence — a re-run with the pin already at target produces `result=noop`, zero commits, zero PRs; a rerun with an open PR for the same branch produces `result=existing` + a comment, not a second PR.
- [ ] AC8: Supersede — an open bot-authored `soleur/inngest-pin-*` PR for an older tag is closed with a `Superseded by <url>` comment; a bot branch carrying human commits is never force-pushed (`branch-has-manual-commits`).
- [ ] AC9: Auto-merge is armed (`gh pr merge --auto --squash`) iff `mirror_status == 'ok'`; on `degraded` the PR carries a comment stating the hold and the verification needed.
- [ ] AC10: Bump commits carry `soleur-ai[bot]` + `273333864+soleur-ai[bot]@users.noreply.github.com` (the CLA-allowlisted identity).
- [ ] AC11: The bump PR body names the tag, the resolved digest, the publishing run URL, and carries `Ref #8359` on its own line — no close-keywords inside prose (pr-auto-close-scanner-clean).
- [ ] AC12: `## Observability`, `## Encryption Posture`, `## Guard Contract`, `## User-Brand Impact`, and `## Architecture Decision (ADR/C4)` sections are present here and the ADR-230 (provisional) file + C4 edit land in the same PR.
- [ ] AC13: `guard-script-fixture-tests` is green on this PR with the new suite included (suite count ≥ 12, above the `MIN_SUITES=11` floor), and `deploy-script-tests` remains green (the plan edits neither cloud-init file's pin).
- [ ] AC14: End-to-end proof is deferred-by-design to the first post-merge `vinngest-v*` publish (workflows cannot be dispatch-tested from a feature branch — the repo's stated reason for script+fixture coverage); the PR body records this explicitly.

## Test Scenarios

- Given a fixture repo pinned `v1.1.37@<old-digest>` with tags through
  `vinngest-v1.1.38`, when the script runs with `--tag v1.1.38 --digest
  <new>`, then all four sites carry `v1.1.38@<new>`, commit exists on
  `soleur/inngest-pin-v1.1.38`, `gh pr create` was invoked once, `gh pr merge
  --auto --squash` was invoked (mirror-status ok).
- Given the pin already at `v1.1.38@<new>`, when the script runs, then
  `result=noop`, no commit, no `gh pr create`.
- Given `--tag v1.1.35` with `vinngest-v1.1.38` present (old-tag republish),
  when the script runs, then it targets `v1.1.38` (and noops if already
  pinned there) — never a downgrade PR.
- Given `--digest` ≠ stubbed crane resolution while `--tag == max`, when the
  script runs, then it exits non-zero naming both digests and writes nothing.
- Given `--mirror-status degraded`, when the script opens the PR, then
  `gh pr merge --auto` is NOT invoked and `gh pr comment` records the hold.
- Given a human-authored tip on `soleur/inngest-pin-v1.1.38`, when the script
  runs, then `branch-has-manual-commits` and no push.
- Given an open bot-authored `soleur/inngest-pin-v1.1.37` PR when the
  `v1.1.38` bump runs, then it is closed with `Superseded by <url>`.
- Given a partial state (IREF bumped, ZIREF stale), when the script runs,
  then all four sites converge and no tag-only ref remains.
- Shape tests: workflow without `needs: build`, without `ref: main`,
  without `fetch-tags`, with a `*PAT*` literal, or without the `digest=`
  output → each yields RED on its named assert.

## References & Research

- Issue: #8359 (spec seed; `meta/machinery`). Adjacent: #4326 (out of scope),
  #8071 + #6286 (closed drift trackers proving the class), #7632 / #4699 /
  #7308 (related open, acknowledged).
- Canonical auth recipe: `.github/workflows/board-status-sync.yml` (inline
  App-JWT mint); scope verification: `gh api /orgs/jikig-ai/installations`
  (run 2026-09-19).
- Bot-PR conventions: `.github/workflows/fix-constraints-stage-b.yml`,
  `scripts/post-bot-statuses.sh` (deliberately unused), `.github/workflows/cla.yml`.
- Guard machinery: `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`
  (AC6/AC6b/Guard B + its registry-read limitation note);
  `.github/scripts/test/test-inngest-bootstrap-tag-guard.sh` (shape-test
  precedent); `.github/scripts/test/run-all.sh` (glob contract).
- Learnings: `2026-05-25-app-jwt-inline-mint-for-workflow-gh-api-administration-read.md`,
  `2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails.md`
  (wrapper-vs-curl).
