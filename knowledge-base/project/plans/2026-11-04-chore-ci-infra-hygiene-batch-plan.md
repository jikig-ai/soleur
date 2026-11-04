---
title: "chore(ci): CI/infra hygiene batch — dispatch-ref publish gates (#8780), dedupe fail-open normalization (#9659), web-host EnvironmentFile conditioning (#10078)"
type: fix
date: 2026-11-04
slug: ci-infra-hygiene-batch
branch: feat-one-shot-10390-ci-hygiene-batch
issue: 10390
closes: [8780, 9659, 10078]
lane: cross-domain
---

## Enhancement Summary

**Deepened on:** 2026-11-04
**Sections enhanced:** halt-gate verification across the whole plan
(Phases 4.5–4.13 all evaluated; Guard Contract resolved mechanically via
`scripts/lint-guard-contract.py` — 3 entries, green)
**Research agents used:** none — inline sequential-fallback execution (no
Task-spawn capability in the planning subagent); every prescribed seat
was run by the orchestrator against `origin/main` and cited sources.

### Key Improvements

1. **Gate verification (all PASS, none fired a halt):** User-Brand Impact
   (`none` + sensitive-path scope-out reason present); Observability (5
   fields, `python3`-allowlisted probe, literal `unclassified: 0`
   expectation); PAT sweep clean; Encryption Posture (named attestation,
   concrete `does_not_defend`, no exception needed); Guard Contract lint
   green; Scope Check exactly one unfenced section, all asks mapped,
   inferred rows justified; UI-wireframe / network-outage / downtime /
   task-design triggers evaluated and skipped (no UI files, no SSH
   provisioners in the changed resources, no downtime-inducing operation,
   no new autonomous task).
2. **Verify-the-negative pass (Phase 4.45, inline):** the plan's negative
   claims were re-grepped — `build:` job carries no `environment:` (~:68;
   the `:1066` binding is `bump-cloud-init-pin`), `inngest-config-signing`
   has no `deployment_branch_policy` (the .tf shown verbatim), 76/18
   census counts are measured not estimated, `web-bash-synthetic.service:22`
   is genuinely unprefixed. No contradiction found.
3. **Precedent-diff (Phase 4.4):** all three mechanisms are
   sibling-precedent-bound, not novel — the env/policy HCL shape mirrors
   `infra-privileged-environment.tf:32-58`, the SKIP-VS-FAIL contract
   mirrors PR #10073's diff verbatim-shape, the `|| { ::error:: }`
   dedupe handler mirrors `scheduled-inngest-health.yml` in-tree. The
   marker-lint is the one novel element; its Guard Contract names the
   vacuity and adjacency mutation rows.

### New Considerations Discovered

- The `REVIEWERS_RATCHET`/DP-11 F8 disjunction already licenses the new
  reviewer-less `release-publish` environment — the plan's explicit
  population pin (`expect(names).toContain("release_publish")`-style)
  keeps deletion loud.
- `version-bump-and-release.yml` is a second `reusable-release.yml`
  caller — the chokepoint placement covers it free; recorded so its
  admission is a decision, not an accident.
- Registration learning (2026-11-01): a new floor-bearing suite is three
  write sites — `test-all.sh`, `suite-durations.tsv`,
  `suite-shard-legs.tsv`, plus the `PROMOTED_FILES` check; encoded in
  AC-B3/tasks 2.5.

## Overview

Epic #10390 bucket-4 batch of three open chores, all internal CI/infra
machinery with no user-facing surface:

- **#8780** — three publish paths (`build-inngest-config-bundle.yml`,
  `web-platform-release.yml` via `reusable-release.yml`,
  `build-inngest-bootstrap-image.yml`'s `build` job) can be driven by a
  `workflow_dispatch` from a non-`main` ref, because a dispatch executes the
  selected ref's workflow bytes. The admission boundary is the GitHub
  environment deployment-branch policy evaluated before job start — the
  ADR-241 D2 mechanism — extended to the `inngest-config-signing`
  environment (reviewer-gated today, branch-open today) and to a new
  reviewer-less main-only admission environment for the two unattended
  publish jobs.
- **#9659** — residual bare/silent `gh issue|pr list|search` dedupe reads on
  filing paths outside #9612's enumerated scope; normalize each to the
  fail-open `if ! VAR="$(…)"; then ::error::; VAR=""; fi` shape or document a
  deliberate fail-closed / benign-direction disposition, and ratchet the
  classification so the class cannot silently re-grow a 14th site.
- **#10078** — web-host units whose `EnvironmentFile=` is a late-written
  product (`web-probe-envwrite.sh` runcmd, `|| true`-tolerated) storm the
  journal on boot when the file is absent; apply the #9939/#9962
  skip-vs-fail calibration (`ConditionPathExists=` skip where ordering is
  benign, designed-loud where the failure is the signal), including the
  fifth same-class unit the issue's enumeration missed
  (`web-bash-synthetic.service`).

## Research Insights

**Provenance note.** This plan ran inside a one-shot planning subagent with
no Task/agent-spawn capability. Every seat the skill fan-out prescribes —
repo research, learnings research, functional-overlap scan, domain sweep,
spec-flow analysis, scoped-advisor consult and the plan-review panel — was
executed inline by the orchestrator and is disclosed as
`Reviewed-Coverage: sequential-fallback`-equivalent. Findings below are
derived from direct `origin/main` reads on 2026-11-04, not delegated
summaries.

### Premise Validation (Phase 0.6)

- `gh issue view` on 2026-11-04: **#8780, #9659, #10078, #10390 all OPEN**.
  None is closed by a merged PR. Parent-verified collision probes (zero open
  PRs, no sibling worktrees, foreign-run check) are trusted per the
  scoping contract and were not re-run; the only open PR touching this
  branch's files is this pipeline's own draft #12064 (benign
  self-collision, same class as the one recorded in
  `learnings/2026-10-31-a-dedupe-sentinel-*.md` Session Errors §1).
- All files cited by the three issues exist on `origin/main` (verified by
  `git show origin/main:<path>` for every named workflow, unit file, and
  `.tf`). Divergences found are enumerated in Research Reconciliation —
  all are drift, none is absence.
- ADR corpus grep for the proposed mechanisms: `deployment_branch_policy`
  is the *endorsed* mechanism of ADR-241 D2 (its Alternatives Considered
  rejects reviewer-gates alone, not branch policies), so the #8780
  mechanism is a direct application, not a rejected alternative.
  `ConditionPathExists` + unprefixed `EnvironmentFile=` is the merged
  #9939/#9962 precedent. No ADR rejects either.
- Precedents verified merged: PR #10073 (closes #9962, SKIP-VS-FAIL
  pattern), PR #9944 (#9939), #9612's normalization sites visible in
  `scheduled-inngest-health.yml` (`|| { echo "::error::…"; EXISTING=""; }`).
- **Live-race overlap recorded, not re-probed:** draft PR #10928 (#9294)
  touches `apply-web-platform-infra.yml`, `terraform-target-parity.test.ts`
  and `ADR-241` — all three are also in this plan's file list. Rebase
  coordination is a named risk; the edits land in disjoint regions
  (allow-list lines vs. its deploy-pipeline changes; appended pins vs. its
  new describes; an appended ADR note vs. its R1 text).

### Property List (Phase 0.6b)

1. A `workflow_dispatch` of `build-inngest-config-bundle.yml`,
   `web-platform-release.yml`/`reusable-release.yml`, or
   `build-inngest-bootstrap-image.yml` from a non-`main` ref is refused
   *before any publish step runs*, by a control the dispatched ref's own
   bytes cannot weaken.
2. Every `gh issue|pr list|search` read feeding a filing/dedupe decision
   degrades fail-open with a loud `::error::` breadcrumb, or is
   mechanically documented as deliberate fail-closed / benign-direction;
   the classification is exhaustive over the census and cannot silently
   re-grow.
3. A web-host unit whose `EnvironmentFile=` product is written late by a
   tolerated-failure path skips (not fails) on benign-ordering absence and
   self-heals when the file appears, while a unit whose env file is
   written unconditionally stays designed-loud; every skip names the
   external detector that reports the dark state.

### Mechanism Cut List (Phase 0.6b)

- **YAML-side dispatch-ref guard as the primary #8780 control — cut.**
  Buys property 1 in name only: a hostile dispatch runs the *branch's*
  YAML, so a check inside it is self-disarming. The deployment-branch
  policy already on `origin/main` (ADR-241 D2) is evaluated by GitHub
  before the job starts — existing mechanism covers the property.
  *Exception kept:* the bootstrap workflow's existing "Validate dispatch
  ref" step validates the *tag input*, a different property; untouched.
- **`-`-prefixed `EnvironmentFile=` for #10078 — cut.** Buys silence, not
  the property: it masks a missing file even on a real start attempt,
  discarding the fail-closed contract the #9939/#9962 precedent
  deliberately retains. `ConditionPathExists=` is the covering mechanism.
- **`infra-privileged` as the publish jobs' environment — cut.** It
  carries the broad Tier-B `DOPPLER_TOKEN_INFRA_PRIVILEGED`; declaring it
  on jobs that mint no Tier-B secret widens the secret boundary for an
  admission property a secrets-free environment buys for free.
- **Reviewer gate on the new publish environment — cut.** The publish
  jobs are unattended (auto-mint, push-arm releases); a required reviewer
  deadlocks them by design (same reasoning as `infra-privileged` in
  ADR-241 D2). The `REVIEWERS_RATCHET` disjunction in
  `terraform-target-parity.test.ts` already permits reviewer-less +
  main-only-policy environments.

### Relevant file paths (verified on `origin/main`)

- #8780 surfaces: `.github/workflows/build-inngest-config-bundle.yml`
  (`environment: inngest-config-signing`, job ~:43),
  `.github/workflows/reusable-release.yml` (single job `release:` ~:82 —
  the only publish chokepoint; callers are `web-platform-release.yml:104`
  and `version-bump-and-release.yml:24`, both `uses:`-only consumers),
  `.github/workflows/build-inngest-bootstrap-image.yml` (`build:` ~:68 —
  `packages: write` + `id-token: write`, no environment; sibling
  `bump-cloud-init-pin` already on `infra-privileged` ~:1066),
  `apps/web-platform/infra/inngest-config-signing.tf` (reviewer-only env),
  `.github/workflows/apply-web-platform-infra.yml` (`-target=` allow-list
  ~:546-555).
- #9659 census (measured 2026-11-04): 76 hits of
  `=\$\([[:space:]]*gh (issue|pr) (list|search)` across **18** workflow
  files — the issue's 12 plus `scheduled-inngest-health.yml` (25),
  `scheduled-zot-restart-loop.yml` (15), `main-health-monitor.yml`,
  `review-reminder.yml`, `scheduled-integration-suites.yml`,
  `cla-evidence-timestamp.yml`, `apply-deploy-pipeline-fix.yml`,
  `web-platform-release.yml` (growth since the issue's enumeration).
- #10078 surfaces: five probe units
  `apps/web-platform/infra/{inngest-consumer-probe,web-bash-synthetic,web-git-data-probe,web-private-nic-guard,web-zot-consumer-probe}.service`
  (env files written by `web-probe-envwrite.sh`, armed `enable --now` at
  `cloud-init.yml` ~:646-650); `apps/web-platform/infra/webhook.service`
  + its embedded twin at `cloud-init.yml` ~:235 (lockstep, #7220 AC-B2.3);
  `soleur-host-bootstrap.sh` ~:918-948 (`vector.service` heredoc);
  `infra-config-apply.sh` (`WEBHOOK_SERVICE_B64` content pin ~:228 —
  any `webhook.service` byte change MUST update the pin or deliveries are
  silently refused per #7220 AC-B1).
- Guards/tests to extend: `plugins/soleur/test/terraform-target-parity.test.ts`
  (DP-11 F8 disjunction, `REVIEWERS_RATCHET` ~:4255, job↔environment pins
  ~:3665/:4001); `scripts/test-all.sh` (`run_suite` registration ~:5588);
  `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`,
  `scripts/guard-vacuity-floor.test.sh` (`PROMOTED_FILES` — the
  three-write-site suite registration set per the 2026-11-01 learning);
  per-unit pins in `apps/web-platform/infra/*.test.sh`,
  `soleur-host-bootstrap-observability.test.sh` (AC22 asserts vector's
  `EnvironmentFile`), `web-bash-synthetic.test.sh:820`,
  `infra-config-apply.test.sh` (B5.3 pins webhook's disabled start limit),
  `fresh-boot-parity.test.sh` (§12 env-file key parity).

### Institutional learnings that shape this plan

- `2026-10-11-conditioning-a-unit-also-conditions-every-detector-wired-to-its-failures.md`
  (explicitly names #10078): the storm was doing detection work — every
  SKIP-VS-FAIL comment must name an *external* channel that does not share
  the gated dependency; a timer-level condition is once-per-boot while a
  service-level one re-evaluates per trigger; censuses must cover
  generator heredocs, not just `*.service` files; pins assert shape claims
  (path-set equality, unprefixed retention, no reset lines).
- `2026-10-31-a-dedupe-sentinel-*.md` / `2026-11-01-bounding-gh-probes-*.md`:
  sentinel identity must derive from the reported set, not a parallel
  array; a flag/argv contract change is a class change whose second
  consumer set is mocks and recorded-argv oracles — grep the test tree for
  the old call shape before declaring green; new floor-bearing suites are
  three write sites (durations tsv, shard-legs tsv, vacuity PROMOTED).
- `2026-09-29-a-source-census-*.md`: a census that checks an argument's
  *name* rather than its *binding* misses the defect — for #9659 classify
  the *call site's* failure handling, not its variable name.
- ADR-241 D2 + `learnings/security-issues` tier vocabulary: environments
  without deployment-branch policy are open to every branch; GitHub
  UNIONs deployment policies, so "exactly {main}" is the property, never
  "contains main"; an environment a job references but that does not
  exist is auto-created unprotected (the apply-ordering residual).

### CLAUDE.md / constitution conventions applied

- `set -euo pipefail` in every new `run:` body (and #7098's census
  compatibility); shell `[[ ]]` tests; `local` declarations; operator-
  protection signals to stdout.
- Exact-count pin convention for assertion inventories (no floor slack);
  per-file comment headers `# --- Section ---` where scripts grow.
- Docs link `plugins/soleur/` changes require a `semver:` label at ship
  (handled by the PR, not the plan).

### External research decision (Phase 1.6)

**Skipped beyond one docs check.** Every mechanism is established in-repo
precedent (ADR-241, PRs #9944/#10073, #9612) — external research adds
nothing to mechanism selection. The one load-bearing external claim —
"an `environment:` key on a job inside a *reusable* workflow is evaluated
against the caller run's ref" — was verified against GitHub's
"Reuse workflows" docs (the caller job cannot set `environment`; the
called job can, and the environment resolves in the caller's repo), which
also restates the auto-create-unprotected hazard ADR-241 recorded.

## Research Reconciliation — Spec vs. Codebase

| Issue / spec claim | Reality on `origin/main` (2026-11-04) | Plan response |
|---|---|---|
| #10078 lists four probe units (`inngest-consumer-probe`, `web-zot-consumer-probe`, `web-private-nic-guard`, `web-git-data-probe`) | `web-bash-synthetic.service:22` is a **fifth** unprefixed `EnvironmentFile=` unit fed by the same `web-probe-envwrite.sh` writer and armed in the same `cloud-init.yml` block (~:646-650) | Include it in the conditioning set; the class census — not the issue's enumeration — is the file list |
| #10078 cites probe-unit lines ~:28/:28/:27 and vector `RestartSec=5` | Actual: :30/:30/:29 (drifted +2/3); `vector.service` heredoc carries `RestartSec=10`, `webhook.service` `RestartSec=5` | Facts re-derived per unit at implementation; comments cite measured values |
| #9659 enumerates 12 workflow files | Census today: 76 hits across **18** files — additions include `review-reminder.yml`, `scheduled-integration-suites.yml`, `main-health-monitor.yml`, `cla-evidence-timestamp.yml`, `apply-deploy-pipeline-fix.yml`, `web-platform-release.yml` | Every hit is classified into the issue's three buckets; the marker lint makes new unclassified sites RED |
| #8780 says the bootstrap `build` job "keeps `packages: write` and `id-token: write`" | Confirmed ~:84-89, no `environment:` on `build:`; sibling `bump-cloud-init-pin` already main-gated via `infra-privileged` (~:1066) | `build` gets the new admission environment; bump job untouched |
| #8780 defers until "#8747's gate ships" | #8747's tag-ancestry gate merged via #9301 — the dispatch arm *is* the remaining bypass | Proceed now |
| "Reusable-release can't hold an environment" (implicit worry the fix must live in callers) | GitHub docs + ADR-241: `environment:` is valid on a job *inside* the reusable workflow and is evaluated against the calling run's ref | Gate lands inside `reusable-release.yml` — one chokepoint covering both callers |
| #9659 "Already deliberate fail-closed" and "benign" buckets are stated | Spot-verified the shapes exist (`*_rc` handlers, `|| true`, benign STALE reads) | Buckets are honored verbatim — no site in them is rewritten; markers document them |

## Problem Statement / Motivation

Three hygiene debts in the same CI/infra bucket of epic #10390, each small,
each mechanical, all sharing the theme *a cheap read or a missing gate
fails silently where the repo already learned the louder pattern*:

- **#8780:** `workflow_dispatch` runs the *selected ref's* workflow bytes.
  Three publish paths admit a dispatch from any ref, so a feature-branch
  or compromised-token dispatch can build and publish artifacts that look
  official. `inngest-config-signing` gates on a human reviewer but not on
  the ref; the reusable-release and bootstrap `build` jobs gate on
  neither. ADR-241 already settled the boundary: the deployment-branch
  policy, evaluated before job start — these surfaces just never got it.
- **#9659:** #9612 normalized its enumerated `EXISTING=$(gh issue list …)`
  dedupe sites but the class kept growing — a transient `gh` fault at a
  bare `VAR=$(gh …)` site under `set -euo pipefail` aborts the step
  mid-alarm with no breadcrumb. 76 census hits across 18 files today.
- **#10078:** five web-host probe units read `EnvironmentFile=` products
  written late by `web-probe-envwrite.sh` (`|| true`-tolerated), and their
  timers arm unconditionally — an envwrite miss is an armed timer firing
  failed oneshots every 60-120s. `webhook.service`/`vector.service` read
  `/etc/default/webhook-deploy` and crash-loop at 5s/10s unbounded when it
  is absent. #9962 calibrated the identical class on the inngest host.

## Proposed Solution

### Workstream A — #8780: main-only admission on the publish surfaces

The boundary is the GitHub environment deployment-branch policy
(ADR-241 D2): GitHub evaluates it **before the job starts**, against the
*run's* ref — a property a dispatched ref's YAML cannot edit, because the
check never runs any checked-out bytes.

1. **Terraform** (`apps/web-platform/infra/`):
   - `inngest-config-signing.tf`: add
     `deployment_branch_policy { protected_branches = false; custom_branch_policies = true }`
     to `github_repository_environment.inngest_config_signing` (reviewers
     retained — `REVIEWERS_RATCHET` requires them) and a new
     `github_repository_environment_deployment_policy.inngest_config_signing_main`
     with `branch_pattern = "main"`.
   - New `apps/web-platform/infra/release-publish-environment.tf` —
     `github_repository_environment.release_publish`, **no reviewers**
     (unattended publish jobs deadlock on a human gate), no secrets
     (admission-only), `deployment_branch_policy` main-only + policy
     resource `release_publish_main`. Header comment mirrors the
     `inngest-config-signing.tf` convention (why no reviewer, why no
     secret, why it must exist *before* any job references it —
     auto-create hazard).
   - `apply-web-platform-infra.yml`: three new `-target=` lines
     (`github_repository_environment.release_publish`,
     `github_repository_environment_deployment_policy.release_publish_main`,
     `github_repository_environment_deployment_policy.inngest_config_signing_main`)
     appended beside the existing environment targets ~:546-555. The
     targeted apply runs on merge to main (existing automation); a bare
     `*.tf` not in the list is pruned by the target filter and never
     applied — wiring is load-bearing.
2. **Workflows:**
   - `reusable-release.yml`: `environment: release-publish` on the
     `release` job (~:82). Covers **both** callers
     (`web-platform-release.yml`, `version-bump-and-release.yml`) — the
     chokepoint-correct site per the Assembly discipline. Push arms and
     `workflow_run`/`workflow_dispatch`-from-main all present
     `refs/heads/main` and pass.
   - `build-inngest-bootstrap-image.yml`: `environment: release-publish`
     on the `build` job (~:68). `bump-cloud-init-pin` keeps
     `infra-privileged` (it mints a Tier-B App token — correctly scoped).
   - `build-inngest-config-bundle.yml`: header-comment update only — the
     environment binding already exists; record that the signing env now
     also carries the main-only policy.
3. **Pins** in `terraform-target-parity.test.ts`: job↔environment
   bindings for `reusable-release.yml::release` and
   `build-inngest-bootstrap-image.yml::build` (same regex family as the
   `:3670` pin); `inngest_config_signing ∈ mainOnlyPolicyEnvs` *in
   addition to* its `REVIEWERS_RATCHET` membership (additive policy is
   asserted, not merely permitted); presence assertions for the three new
   `-target=` lines; `release_publish` lands in the DP-11 F8
   reviewer-less limb automatically — add it to the explicit-population
   assertion so a deleted `.tf` reds loudly.
4. **ADR-241 amendment:** record the admission-gate environment class
   (fifth environment, reviewer-less by design, holds no Tier-B secret —
   D2's mechanism extended to publish admission). No C4 change — see the
   Architecture section's enumeration.

### Workstream B — #9659: dedupe-shape normalization + ratchet

1. Re-run the census at implementation time:
   `git grep -nE '=\$\([[:space:]]*gh (issue|pr) (list|search)' -- '.github/workflows/'`
   and classify **every** hit into one of the issue's three buckets —
   filing-path dedupe (normalize), deliberate fail-closed (document),
   benign-direction read (leave). The issue's bucket assignments are the
   prior; sites added since are classified by the same test: *does this
   read feed a filing/dedupe decision whose silent abort loses the alarm?*
2. Normalize each filing-path site to the #9612 shape —
   `if ! VAR="$(gh …)"; then echo "::error::<slug>: dedupe query failed — filing without dedupe"; VAR=""; fi`
   or the inline `|| { ::error::…; VAR=""; }` form already used in
   `scheduled-inngest-health.yml`. Preserve each site's own slug so the
   breadcrumb names its monitor.
3. Marker comments on every non-normalized survivor:
   `# dedupe: fail-closed <reason>` or `# dedupe: benign <reason>` —
   adjacent (same or preceding line), so the classification is data, not
   prose in a closed issue.
4. New lint `scripts/lint-gh-dedupe-shape.py` (+ `.test.sh`): census over
   `.github/workflows/*.yml`; every `$(gh (issue|pr) (list|search)` hit
   must be (a) wrapped in `if !` or carry a `||` handler on its logical
   line, or (b) within 2 lines of a `# dedupe:` marker. Joins `\`
   continuations and strips YAML anchors the same way `lint-gh-argv-arg.py`
   does (sibling parser conventions; heredoc bodies skipped). Prints
   `dedupe-shape: unclassified: <n>` — `unclassified: 0` is the pass
   literal. Registered in `test-all.sh` beside the argv-arg pair, with
   `suite-durations.tsv`/`suite-shard-legs.tsv` rows and the
   `PROMOTED_FILES` check per the three-site registration learning.

### Workstream C — #10078: web-host EnvironmentFile conditioning

Per the #9939/#9962 precedent and the detector-wiring learning — the unit
census is the deliverable's file list, not the issue's enumeration:

| Unit | Env file | Writer | Disposition | Detector the comment must name |
|---|---|---|---|---|
| `inngest-consumer-probe.service` | `/etc/default/inngest-consumer-probe` | `web-probe-envwrite.sh` (`|| true` + `soleur-boot-emit web_probe_envwrite fatal`) | `ConditionPathExists=` skip in `[Unit]` | boot-emit fatal row + missing web-1-fed `inngest_consumer` betteruptime beat |
| `web-bash-synthetic.service` | `/etc/default/web-bash-synthetic` | same | skip | boot-emit row + missing synthetic beat |
| `web-git-data-probe.service` | `/etc/default/web-git-data-probe` | same | skip | boot-emit row + missing `git_data_prd` beat |
| `web-private-nic-guard.service` | `/etc/default/web-private-nic-guard` | same | skip | boot-emit row + missing nic-guard beat |
| `web-zot-consumer-probe.service` | `/etc/default/web-zot-consumer-probe` | same | skip | boot-emit row + missing zot-consumer beat |
| `webhook.service` (+ `cloud-init.yml` embedded twin) | `/etc/default/webhook-deploy` | unconditional runcmd printf (~:441) | **keep designed-loud** — comment + negative pin | the 5s crash-loop IS the signal; `infra-config-apply.test.sh` B5.3 already pins the deliberate start-limit disable |
| `vector.service` (`soleur-host-bootstrap.sh` heredoc ~:935) | `/etc/default/webhook-deploy` | same unconditional printf | **keep designed-loud** — comment + negative pin | same reasoning; log-flow darkness detection stays the Better Stack ingest-side signal |

Why the split (recorded, challengeable): for the five probe units the env
file is written by a *tolerated-failure* path — an absent file is a known
benign-ordering shape, the timer re-evaluates the condition each fire (a
service-level condition self-heals when the file appears), and the
upstream failure already has its own channel
(`soleur-boot-emit web_probe_envwrite fatal`). For `webhook`/`vector` the
same env file is written **unconditionally** and earlier in the same
runcmd — its absence is a real fault, not ordering; and they are
`Type=simple` `Restart=on-failure` services started once at boot, where a
condition-skip never retries (no self-heal) and converts a transient
fault into a permanently dead deploy channel / log shipper — strictly
worse than a bounded-noise crash-loop. `webhook.service`'s
`StartLimitIntervalSec=0` is already pinned as deliberate (B5.3). This
disposition is a technical ruling — see `decision-challenges.md` row.

Every SKIP-VS-FAIL comment follows the #9962 contract: names the env
file, says the `EnvironmentFile=` line **stays unprefixed** (once a start
is attempted, an absent file still fails — fail-closed retained), names
the *external* detector that does not share the gated dependency, and
(timer units) records that the condition re-evaluates per fire. Pins per
the precedent's full shape: per-unit condition-path-set ≡
envfile-path-set, unprefixed-`EnvironmentFile=` retention, no reset
lines, and the unnegated-latch additive guard where applicable.

**Lockstep obligations (the write-boundary sweep):**
`webhook.service` byte changes ⇒ `cloud-init.yml` embedded copy +
`infra-config-apply.sh` `WEBHOOK_SERVICE_B64` pin update (a stale pin
silently refuses every delivery — #7220 AC-B1). The comment-only change
still changes bytes — pin must be regenerated. `vector.service` heredoc
changes ⇒ `soleur-host-bootstrap-observability.test.sh` AC22 region.
Probe-unit changes ⇒ per-unit `*.test.sh` shape pins and
`fresh-boot-parity.test.sh` where the env-file key set is asserted.

## Technical Considerations

### Attack surface enumeration (#8780 — security boundary change)

- All paths that publish from a ref: the three named workflows, plus
  `version-bump-and-release.yml` (the second `reusable-release.yml`
  caller — covered free by the chokepoint placement; enumerated here so
  its admission is a decision, not an accident).
- Bypass mechanisms: a dispatch from a non-main ref runs *that ref's*
  YAML — so any YAML-side check is inside the blast radius (recorded in
  the Cut List). The environment policy is the only server-side control;
  the residual is the auto-create window (below, Risks).
- Which publish surfaces are NOT covered and why: `mint-inngest-bootstrap-tag.yml`
  dispatches from main by design (verified — its remediation strings pin
  `--ref main`); `apply-web-platform-infra.yml`/`git-data-cutover.yml`
  already sit on `web-platform-infra-apply`/`infra-privileged` policies;
  the `/hooks/deploy-peer` redeploy path is #9294/PR-#10928's live
  territory — explicitly out of scope.
- Fork-of-workflow dispatch: `workflow_dispatch` requires write access —
  threat model is compromised token / operator error / feature-branch
  convenience dispatch, not anonymous abuse.
- GitHub UNIONs deployment policies — the property is "the pattern set is
  exactly `{main}`", which the DP-11 F8 extractor already asserts; a
  second `*` policy resource would silently re-open the env (the guard
  catches it — see Guard Contract).

### NFR / performance

None user-facing. The dedupe wrapper adds one `if !` per site (zero cost).
The environment check adds zero runtime (pre-start admission). The unit
conditioning *removes* journal-noise CPU on the failure path.

## Implementation Phases

Phase 0 — implementation-time verification (before any edit): re-run both
censuses against the PR's own tree (`git grep` for the dedupe shape and
for unprefixed `EnvironmentFile=` over `*.service` + generator heredocs);
re-check `gh pr view 10928 --json files` for drift in the shared files;
re-derive every line number cited by the issues.

Phase 1 — Workstream B (#9659): census classification, site
normalizations, marker comments, `scripts/lint-gh-dedupe-shape.py` +
`.test.sh`, `test-all.sh`/tsv registration.

Phase 2 — Workstream C (#10078): five probe-unit conditions + comments,
webhook/vector designed-loud comments, `WEBHOOK_SERVICE_B64` +
`cloud-init.yml` lockstep, per-unit pin updates.

Phase 3 — Workstream A (#8780): `.tf` changes, `-target=` wiring,
workflow `environment:` declarations, `terraform-target-parity.test.ts`
pins, ADR-241 amendment.

Phase 4 — verification: full local suite subset (`lint-gh-dedupe-shape`,
`terraform-target-parity`, per-unit `.test.sh`, `infra-config-apply`,
`fresh-boot-parity`, `soleur-host-bootstrap-observability`,
`cloud-init-web-zot-seed` where touched); AC-A7 read-back recorded
post-merge.

Phases are independent and may run in any order; single-PR batch keeps
them as three commits.

## Files to Create

- `apps/web-platform/infra/release-publish-environment.tf` — new
  admission-gate environment + `release_publish_main` policy.
- `scripts/lint-gh-dedupe-shape.py` — the Guard 1 classifier.
- `scripts/lint-gh-dedupe-shape.test.sh` — its mutation/fixture battery.
- `knowledge-base/project/specs/feat-one-shot-10390-ci-hygiene-batch/decision-challenges.md`
  — headless ruling rows (written alongside tasks.md).

## Files to Edit

Workstream A (#8780):

- `apps/web-platform/infra/inngest-config-signing.tf` — dbp block +
  `inngest_config_signing_main` policy.
- `.github/workflows/apply-web-platform-infra.yml` — three `-target=`
  lines.
- `.github/workflows/reusable-release.yml` — `environment:` on `release`.
- `.github/workflows/build-inngest-bootstrap-image.yml` — `environment:`
  on `build` + header note.
- `.github/workflows/build-inngest-config-bundle.yml` — header note only.
- `plugins/soleur/test/terraform-target-parity.test.ts` — Guard 2 pins.
- `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`
  — amendment.

Workstream B (#9659) — the issue's 12 enumerated files plus every census
hit the classification lands in the fix/mark buckets (measured set:
`apply-inngest-rls.yml`, `apply-sentry-infra.yml`,
`fix-constraints-stage-b.yml`, `merge-queue-stall-check.yml`,
`rule-audit.yml`, `scheduled-cron-artifact-age.yml`,
`scheduled-domain-model-drift.yml`, `scheduled-expenses-verify-by.yml`,
`scheduled-realtime-probe.yml`, `scheduled-sentry-alert-drift.yml`,
`scheduled-supabase-advisor-scan.yml`, `scheduled-terraform-drift.yml`;
classification candidates: `scheduled-inngest-health.yml`,
`scheduled-zot-restart-loop.yml`, `main-health-monitor.yml`,
`review-reminder.yml`, `scheduled-integration-suites.yml`,
`cla-evidence-timestamp.yml`, `apply-deploy-pipeline-fix.yml`,
`web-platform-release.yml`); plus `scripts/test-all.sh`,
`scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`, and
`scripts/guard-vacuity-floor.test.sh` if PROMOTED applies.

Workstream C (#10078):

- `apps/web-platform/infra/inngest-consumer-probe.service`
- `apps/web-platform/infra/web-bash-synthetic.service`
- `apps/web-platform/infra/web-git-data-probe.service`
- `apps/web-platform/infra/web-private-nic-guard.service`
- `apps/web-platform/infra/web-zot-consumer-probe.service`
- `apps/web-platform/infra/webhook.service` (designed-loud comment)
- `apps/web-platform/infra/cloud-init.yml` (embedded twin lockstep)
- `apps/web-platform/infra/soleur-host-bootstrap.sh` (vector heredoc
  comment)
- `apps/web-platform/infra/infra-config-apply.sh`
  (`WEBHOOK_SERVICE_B64` regeneration)
- Per-unit test files: `web-bash-synthetic.test.sh`,
  `web-git-data-probe.test.sh`, `web-private-nic-guard.test.sh`,
  `web-zot-consumer-probe.test.sh`, `inngest-consumer-probe.test.sh` where
  pins live, `soleur-host-bootstrap-observability.test.sh`,
  `infra-config-apply.test.sh`, `fresh-boot-parity.test.sh` — the exact
  set is bound by which files carry env-file/condition assertions.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — the
  worst honest breakage is a publish workflow that refuses legitimate
  main dispatches (release pipeline stalls, operator-visible, reversible
  by env-policy fix) or a web probe that stays skipped past env-write
  (its heartbeat alarm pages — the designed detector).
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  no new exposure — the change *narrows* who can drive publish workflows
  and removes a boot-storm noise class; env files touched are existing
  credential files, not new stores.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** all surfaces are internal
  CI/infra machinery; the failure blast radius is a missed monitor filing
  or a refused publish, not user data.
- `threshold: none, reason:` the diff touches sensitive paths
  (`apps/web-platform/infra/**`, `web-platform-release.yml`,
  `version-bump-and-release.yml`, `apply-web-platform-infra.yml` per
  preflight Check 6's `SENSITIVE_PATH_RE`) but every change is a
  defensive admission gate, a failure-handling normalization, or a
  systemd ordering condition on internal host units — none reaches a
  user-facing surface, user data, or the product runtime.

## Observability

```yaml
liveness_signal:
  what: Better Stack heartbeat beats per probe (inngest_consumer, git_data_prd, nic-guard, zot-consumer, web-bash-synthetic), pinged only on successful probe exec; soleur-boot-emit fatal rows for boot-phase write failures; scheduled-terraform-drift for environment-policy drift
  cadence: 60-120s per probe timer; per boot for envwrite; scheduled for drift
  alert_target: operator via Better Stack alert / ci/* issue filing
  configured_in: apps/web-platform/infra/betterstack-logs-alerts.tf, apps/web-platform/infra/arm-heartbeats.sh, apps/web-platform/infra/cloud-init.yml (soleur-boot-emit), .github/workflows/scheduled-terraform-drift.yml

error_reporting:
  destination: workflow-run ::error:: rows (normalized dedupe sites) → Actions log; host journal → vector → Better Stack source 2457081
  fail_loud: "::error::<slug>: dedupe query failed — filing without dedupe" lines; "soleur-boot-emit web_probe_envwrite fatal" journal rows; a non-main dispatch shows as a held/refused environment deployment on the run

failure_modes:
  - mode: transient gh fault at a dedupe read
    detection: ::error:: breadcrumb in the step log + a duplicate filing (deliberate trade)
    alert_route: run annotation / ci/* issue
  - mode: envwrite failure on web host boot
    detection: soleur-boot-emit web_probe_envwrite fatal journal row (pre-existing channel)
    alert_route: Better Stack journal query / boot-health check
  - mode: probe skipped for missing env file
    detection: the probe's own missing heartbeat beat (external channel, not the gated dep)
    alert_route: betteruptime heartbeat alert
  - mode: environment policy weakened/absent post-merge
    detection: scheduled-terraform-drift on the -target'd resources + the DP-11 F8 pre-merge guard
    alert_route: scheduled-terraform-drift filing
logs:
  where: journald on web hosts → vector → Better Stack (source 2457081); Actions run logs for workflow changes
  retention: Better Stack plan retention; journald volatile per boot

discoverability_test:
  command: python3 scripts/lint-gh-dedupe-shape.py
  expected_output: "unclassified: 0"
```

## Encryption Posture

```yaml
at_rest:
  - store: github_repository_environment.release_publish (GitHub-hosted metadata object — name, reviewers, branch policy; declares NO secrets by construction and the header comment forbids adding one)
    mechanism: provider-managed: GitHub environment API (attestation: GitHub SOC2/ISO27001 reports, retrieved 2026-11-04)
    evidence: apps/web-platform/infra/release-publish-environment.tf resource block
    defends_against: nothing — admission metadata, not a credential store; the protection is the deployment-branch policy evaluated at run admission, not encryption of contents
    does_not_defend: a leaked GITHUB_TOKEN/App token already held by the workflow; UI-side policy edits by an admin (that gap is ADR-241 residual R1, unchanged)
    disclosed_as: not-publicly-claimed
    live_verification: available — gh api repos/jikig-ai/soleur/environments/release-publish/deployment-branch-policies
in_transit:
  - connection: github runner -> GitHub Actions/environment API (existing edge; no new connection is added — the plan adds a policy object on an edge that already exists)
    enforced_at: .github/workflows/reusable-release.yml release job + .github/workflows/build-inngest-bootstrap-image.yml build job (the environment: declarations)
    tls: HTTPS/TLS1.2+ (GitHub API)
    cert_verification: on
    does_not_defend: a dispatch that never reaches the environment (refused runs carry no payload); secrets delivered to Tier-A jobs stay Tier-A by ADR-241 design
    disclosed_as: not-publicly-claimed
```

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/inngest-config-signing.tf` — modify
  `github_repository_environment.inngest_config_signing` (add
  `deployment_branch_policy` block) + add
  `github_repository_environment_deployment_policy.inngest_config_signing_main`.
- `apps/web-platform/infra/release-publish-environment.tf` (new) —
  `github_repository_environment.release_publish` (no `reviewers` block,
  main-only `deployment_branch_policy`) +
  `github_repository_environment_deployment_policy.release_publish_main`
  (`branch_pattern = "main"`). Header comment states: no reviewer
  (unattended jobs deadlock), no secrets (admission-only), and the
  auto-create hazard that requires apply-before-dispatch.
- `.github/workflows/apply-web-platform-infra.yml` — three `-target=`
  additions beside ~:546-555.
- Providers: existing `integrations/github` (Tier-B App auth per ADR-241
  D5) — no new provider, no new variable, no `TF_VAR_` additions.

### Apply path

(b) `terraform apply` via the existing targeted apply
(`apply-web-platform-infra.yml`, `-target=` allow-list) on merge to main —
GitHub-side resources, no host blast radius, no downtime. The apply
precedes any dispatch that could auto-create `release-publish`
unprotected; the ordering residual and its read-back check are in
Dependencies & Risks.

### Host fan-out

None — no `terraform_data` SSH provisioner is added or modified.

### Distinctness / drift safeguards

`dev != prd` unaffected (GitHub environments are repo-scoped, not
host-scoped). `scheduled-terraform-drift.yml` covers drift on these
addresses via the target set. GitHub UNIONs policies — the "exactly
{main}" property is guarded pre-merge by DP-11 F8.

### Vendor-tier reality check

None — GitHub environments/branch policies are not a paid-tier feature in
this repo's plan.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-241** (`knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`)
— add an amendment entry recording the *admission-gate environment*
class: a fifth environment `release-publish`, reviewer-less by design
(unattended publish jobs), carrying **no** Tier-B secret — D2's
deployment-branch-policy mechanism extended from secret delivery to
publish admission, plus the same policy added to `inngest-config-signing`
(reviewer retained). The "four Tier-B environments" enumeration in D2 is
annotated so a reader is not misled into counting this as a fifth Tier-B
store. Provisional-ordinal caution does not apply (amendment, not new
ADR); if a sibling edit renumbers, the whole-artifact sweep rule applies.

### C4 views

**No C4 impact.** Enumerated per the completeness mandate against
`model.c4`/`views.c4`/`spec.c4`: (a) external human actors — the
dispatching operator and automation are already the `founder`/github
edges, no new actor; (b) external systems — `github` is already the
modeled system, environments are attributes of the existing edge, not a
new system; (c) containers/data stores — none added (the environment
object is GitHub-side metadata); (d) relationships — no edge moves, the
change narrows an admission attribute on existing CI edges. Grepping the
model for `environment|workflow|github` confirms environments are not
C4-modeled today and no element description is falsified.

### Sequencing

The ADR amendment lands in this PR describing the state after the
targeted apply; the environment resources are `adopting` until the
post-merge apply + read-back AC verifies them live — no separate
follow-up issue.

## Guard Contract

### Guard 1 — `scripts/lint-gh-dedupe-shape.py` (dedupe-shape classifier)

**Property.** Every `$(gh (issue|pr) (list|search)` invocation in
`.github/workflows/*.yml` is either fail-open-wrapped, `||`-handled, or
adjacent to a `# dedupe:` disposition marker — an unclassified new site
cannot merge.

**Assembly.** The census regex over the whole `.github/workflows/*.yml`
tree (single chokepoint: the lint itself); members are call sites, which
drift freely — the guard does not enumerate members, it enforces that
every member carries a disposition.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Strip the `\|\| { ::error:: … }` handler from a normalized site | RED |
| 2 | Add a new bare `X=$(gh issue list …)` site in any workflow | RED (re-growth — the property the issue exists for) |
| 3 | Move a `# dedupe:` marker >2 lines from its site | RED (adjacency is load-bearing, not decorative) |
| 4 | Run the lint against a fixture tree with zero census hits | RED (own-dispatch: a 0-match census must fail vacuity, not pass) |
| 5 | Harness: fixture where a `$(gh issue list)` appears inside a heredoc body | PASS (stdin data, not argv — mirrors lint-gh-argv-arg.py's skip) |

**Anchor.** The lint reads only the tree; a weakening requires editing
both a call site and its disposition in one diff — there is no stored
oracle to co-edit, so consistency-vs-integrity collapse does not apply;
the vacuity floor (row 4) is the anchor.

### Guard 2 — publish-admission pins (`terraform-target-parity.test.ts`)

**Property.** Every publish-path job in the three workflows is bound to
an environment whose deployment-policy set is exactly `{main}`, and every
new env resource is wired into the `-target=` apply list.

**Assembly.** Three chokepoints: `environment:` lines in
`reusable-release.yml` + `build-inngest-bootstrap-image.yml` +
`build-inngest-config-bundle.yml`; `github_repository_environment*` in
`apps/web-platform/infra/*.tf` (DP-11 F8 already enumerates them); the
`-target=` allow-list in `apply-web-platform-infra.yml`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Delete `environment: release-publish` from `reusable-release.yml::release` | RED |
| 2 | Add `github_repository_environment_deployment_policy` with `branch_pattern = "*"` beside the `main` one | RED (existing `isMainOnly` set-semantics check; union-reopen class) |
| 3 | Drop `custom_branch_policies = true` while keeping the `main` policy resource | RED (inert-policy class the DP-11 comment names) |
| 4 | Remove the `-target=github_repository_environment_deployment_policy.release_publish_main` line | RED (new -target presence pin; without it the policy never applies) |
| 5 | Harness: point `policyPatternsFor` at a synthetic tree where `release_publish` has zero policies | RED (extractor can't render "absent" as "main-only") |
| 6 | must-PASS: `inngest_config_signing` with reviewers AND a `main` policy | PASS (additive policy is the designed end-state, not a violation) |

**Anchor.** The `REVIEWERS_RATCHET`/main-only sets are asserted against a
live-tree extraction with explicit-population checks — a diff that
empties the population also reds the vacuity assertion; no single-diff
self-certification.

### Guard 3 — EnvironmentFile calibration pins (per-unit test files)

**Property.** For the five probe units, condition-path-set ≡
envfile-path-set with `EnvironmentFile=` unprefixed; `webhook.service`/
`vector.service` carry the designed-loud comment and NO
`ConditionPathExists` on their env file.

**Assembly.** The seven unit bodies across three carriers:
`apps/web-platform/infra/*.service` files, the `cloud-init.yml`
`write_files` embedded `webhook.service`, and the `soleur-host-bootstrap.sh`
`UNITEOF` heredoc — the generator heredocs the first #9962 census missed.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Delete `ConditionPathExists=` from `web-git-data-probe.service` | RED |
| 2 | Change a probe's `EnvironmentFile=` to `-`-prefixed | RED (fail-closed retention pin) |
| 3 | Add `ConditionPathExists=/etc/default/webhook-deploy` to `webhook.service` | RED (conditioning the deploy channel is the defect class — negative pin) |
| 4 | Reorder so the condition lands in `[Timer]` not `[Unit]` on a probe unit | RED (inert-lvalue class from the #9962 Session Errors) |
| 5 | Harness: assert the pin extractor reads the `soleur-host-bootstrap.sh` heredoc body, not just `*.service` files — a tree where only the file copy is conditioned | RED |

**Anchor.** Path-set equality is computed from the units themselves at
test time (per-unit extraction, not a stored count); `infra-config-apply.sh`'s
`WEBHOOK_SERVICE_B64` + `test_service_pin_matches_repo_unit` anchors the
`webhook.service` byte identity against the delivery pin — a unit edit
without the pin update reds.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "a `deployment_branch_policy` on a Terraform-managed environment, or a guard on the dispatch ref" [#8780] | Workstream A phases 1-2; `inngest-config-signing.tf` + `release-publish-environment.tf` + workflow `environment:` lines | mapped |
| 2 | "`.github/workflows/web-platform-release.yml`'s dispatch arm, via `reusable-release.yml`. It needs a check of which branch it may run from." [#8780] | `reusable-release.yml` `release` job `environment: release-publish` (covers both callers incl. `version-bump-and-release.yml`) | mapped |
| 3 | "`build-inngest-bootstrap-image.yml`'s own dispatch arm … The `build` job keeps `packages: write` and `id-token: write`." [#8780] | `build` job `environment: release-publish` | mapped |
| 4 | "normalize to fail-open `if ! VAR="$(…)"; then ::error::; VAR=""; fi` or document a deliberate fail-closed" [#9659] | Workstream B phases 1-3 (site rewrites + markers) | mapped |
| 5 | "Apply the same per-unit calibration as #9962 (ConditionPathExists= skip where benign ordering; keep designed-loud where the failure is the signal)." [#10078] | Workstream C conditioning table + lockstep obligations | mapped |
| 6 | "epic #10390 remains OPEN. Next items per epic buckets … Work targets: #8780 #9659 #10078" [operator direction] | Whole plan (three workstreams, one batch) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `release-publish-environment.tf` new env | "a `deployment_branch_policy` on a Terraform-managed environment" | asked |
| `reusable-release.yml` / `build-inngest-bootstrap-image.yml` `environment:` lines | "It needs a check of which branch it may run from." | asked |
| `inngest-config-signing.tf` policy additions | "Its signing environment `inngest-config-signing` … has a required reviewer but no `deployment_branch_policy`." | asked |
| `apply-web-platform-infra.yml` `-target=` lines | — | inferred — justification: the targeted apply prunes any `*.tf` resource not in its allow-list; without the lines the new resources never apply (per the `inngest-config-signing.tf` header comment) |
| `terraform-target-parity.test.ts` pins | — | inferred — justification: the admission property has no pre-merge enforcement otherwise; every environment change in this root pins its shape here (DP-11 F8 precedent) |
| ADR-241 amendment | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`; a fifth environment that a reader could mistake for Tier-B must be recorded |
| `scripts/lint-gh-dedupe-shape.py` + test + registration | — | inferred — justification: #9659 exists because the class grew past #9612's enumeration with no census; a document-only fix re-grows a 14th site (ADR-166: docs-only enforcement does not work) |
| Sites beyond the issue's 12 files (review-reminder, scheduled-integration-suites, main-health-monitor, cla-evidence-timestamp, apply-deploy-pipeline-fix, web-platform-release) | "A class-wide census … found the same dedupe shape in workflows the issue did not enumerate." | asked (the issue's own census framing licenses class-wide coverage) |
| `web-bash-synthetic.service` conditioning | — | inferred — justification: same writer, same arming block, same class; fixing four of five leaves the storm class alive on the fifth |
| `webhook.service`/`vector.service` designed-loud comments + negative pins | "keep designed-loud where the failure is the signal" | asked |
| `infra-config-apply.sh` `WEBHOOK_SERVICE_B64` regeneration | — | inferred — justification: a comment-only `webhook.service` edit still changes bytes; a stale pin silently refuses delivery (#7220 AC-B1) |
| `cloud-init.yml` embedded `webhook.service` lockstep | — | inferred — justification: #7220 AC-B2.3 lockstep — the two copies must stay byte-consistent |

### Split Assessment

- Subsystems touched: 2 — `apps/` (web-platform infra), `.github/` (workflows)
  plus `scripts/` + `plugins/` test surface (4 roots at lint level)
- Planned files: ~34 | Estimated changed lines: ~900
- Thresholds: `>= 4` subsystem roots OR `> 25` planned files OR `> 800` estimated lines
- Recommendation: **split — by issue boundary** (`#9659` workflows+lint |
  `#10078` unit conditioning | `#8780` env gates) if review requires it.
  The one-shot batch pipeline ships a single draft PR (#12064) with
  per-workstream commits; the three file sets are disjoint except
  `apply-web-platform-infra.yml`/`web-platform-release.yml` which only
  #8780 touches, so a split is a clean three-way seam, not a refactor.

## Acceptance Criteria

**#8780 — publish admission**

- [ ] AC-A1: `github_repository_environment.inngest_config_signing` carries
  `deployment_branch_policy { protected_branches = false; custom_branch_policies = true }`,
  a `github_repository_environment_deployment_policy.inngest_config_signing_main`
  (`branch_pattern = "main"`), and retains non-empty `reviewers.users`.
- [ ] AC-A2: `github_repository_environment.release_publish` exists with a
  `main`-only policy set, no reviewers, no secrets — declared in
  `apps/web-platform/infra/release-publish-environment.tf`.
- [ ] AC-A3: all three new resources appear as `-target=` entries in
  `apply-web-platform-infra.yml`'s allow-list.
- [ ] AC-A4: `reusable-release.yml` `release` job declares
  `environment: release-publish`; `build-inngest-bootstrap-image.yml`
  `build` job declares `environment: release-publish`.
- [ ] AC-A5: `terraform-target-parity.test.ts` pins both new
  job↔environment bindings, asserts `inngest_config_signing` and
  `release_publish` are each in the exactly-`{main}` policy set, and pins
  the three `-target=` lines.
- [ ] AC-A6: ADR-241 carries the amendment recording the admission-gate
  class (in this PR, not a follow-up).
- [ ] AC-A7 (post-merge verification): the targeted apply ran from main
  and `gh api repos/jikig-ai/soleur/environments/{release-publish,inngest-config-signing}/deployment-branch-policies`
  shows `main` as the sole pattern for both — recorded in the PR body or
  a linked comment (the O0-style read-back).

**#9659 — dedupe normalization**

- [ ] AC-B1: every census hit of
  `git grep -nE '=\$\([[:space:]]*gh (issue|pr) (list|search)' -- '.github/workflows/'`
  is fail-open-wrapped, `||`-handled, or adjacent to a `# dedupe:
  fail-closed`/`# dedupe: benign` marker; `scripts/lint-gh-dedupe-shape.py`
  prints `unclassified: 0` and runs green in `test-all.sh`.
- [ ] AC-B2: every filing-path site enumerated in the issue (the 12-file
  list) is rewritten to the fail-open shape with a per-site `::error::`
  slug preserving its monitor name.
- [ ] AC-B3: `lint-gh-dedupe-shape.py` + `.test.sh` registered as a suite
  pair (`test-all.sh` run_suite lines, `suite-durations.tsv`,
  `suite-shard-legs.tsv`, `guard-vacuity-floor.test.sh` PROMOTED check).

**#10078 — EnvironmentFile conditioning**

- [ ] AC-C1: the five probe units (`inngest-consumer-probe`,
  `web-bash-synthetic`, `web-git-data-probe`, `web-private-nic-guard`,
  `web-zot-consumer-probe`) each carry
  `ConditionPathExists=/etc/default/<their-file>` in `[Unit]`, keep
  `EnvironmentFile=` unprefixed, and carry a SKIP-VS-FAIL comment naming
  the boot-emit fatal channel + their own heartbeat-beat detector.
- [ ] AC-C2: `webhook.service` (repo file + `cloud-init.yml` embedded
  twin) and the `vector.service` heredoc carry designed-loud comments;
  no `ConditionPathExists` on their env file; `WEBHOOK_SERVICE_B64`
  regenerated in `infra-config-apply.sh`.
- [ ] AC-C3: per-unit test pins updated — condition-path-set ≡
  envfile-path-set per unit, unprefixed retention, no reset lines,
  negative pins on webhook/vector (incl. heredoc extraction, not only
  `*.service` files); all referenced `.test.sh` suites green.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal CI/infra machinery. The
mechanical UI-surface scan of `## Files to Create`/`## Files to Edit`
matched no UI-surface path (no `components/**/*.tsx`, `app/**/page.tsx`,
`app/**/layout.tsx`, or UI-term file); Product/UX Gate is `NONE` and the
UX pipeline does not run. `soleur:marketing:copywriter` was not
recommended by any domain assessment and is not invoked.

## Test Scenarios

- Given a `workflow_dispatch` of `web-platform-release.yml` from
  `refs/heads/feat-x`, when the `release` job evaluates
  `environment: release-publish`, then GitHub refuses the deployment
  before any step runs — verified post-merge by a test dispatch from a
  scratch branch expected to fail admission (integration; `environment`
  admission is GitHub-side and cannot be unit-tested — the pre-merge
  proxy is the Guard 2 pin set).
- Given the census regex over `.github/workflows/`, when a fixture
  workflow gains a bare `X=$(gh issue list …)` site with no handler and
  no marker, then `lint-gh-dedupe-shape.py` reports it unclassified and
  exits non-zero (unit — fixture battery per Guard 1's matrix).
- Given `web-probe-envwrite.sh` fails on a fresh web boot, when the five
  probe timers fire, then each unit logs a condition-skip (not a failed
  start) and the boot-emit fatal row + missing beats carry the alarm
  (integration — exercised by `systemd-analyze verify` + the per-unit
  pin suites; the live arm is the next fresh-boot, not this PR).
- Given `webhook.service` unchanged-but-commented, when
  `infra-config-apply.sh` runs, then `test_service_pin_matches_repo_unit`
  passes only with the regenerated `WEBHOOK_SERVICE_B64` (unit).
- Given the `DP-11 F8` disjunction, when `release_publish` is added
  reviewer-less with `main`-only policy, then the guard stays green; when
  a second `*` policy is appended, it goes red (unit — synthetic-tree
  direction test, Guard 2 row 5).

## Open Code-Review Overlap

- **#7098** (`ci: audit the 56 run: bodies whose set omits -e …`)
  mentions `apply-web-platform-infra.yml` and `apply-sentry-infra.yml`,
  both in this plan's file list. **Disposition: acknowledge** — different
  concern (bash strict-mode audit vs. admission-gate wiring and dedupe
  normalization); this plan's new `run:`-level edits keep
  `set -euo pipefail` so they do not worsen #7098's census. The scope-out
  remains open.

## Success Metrics

- Zero unclassified dedupe sites (lint literal `unclassified: 0`).
- The five probe units produce condition-skip journal rows (not
  `Failed to start`) on envwrite failure — measurable on next fresh
  web-host boot via the boot-emit channel.
- A non-main dispatch of any gated workflow shows a refused/held
  environment deployment; main-arm publishes unaffected (version-bump
  and web-platform release continue on push).
- No new journald `Failed to start` rows from the conditioned units on
  the class scenario.

## Dependencies & Risks

- **Live-race collision:** draft PR #10928 edits
  `apply-web-platform-infra.yml`, `terraform-target-parity.test.ts`, and
  `ADR-241`. Mitigation: disjoint regions (target lines / appended
  describes / appended amendment), standard rebase; if it merges first,
  the three files are re-read before final edit.
- **Apply-ordering residual:** a `workflow_dispatch` between merge and
  the targeted apply could hit a not-yet-created `release-publish` and
  auto-create it *unprotected*. Bounded because the apply runs on merge
  (existing automation) and AC-A7's read-back verifies the live policy;
  if the env pre-exists unprotected, the apply still attaches the policy
  (environments are create-or-update) — the window is minutes, not a
  persistent hole, and the auto-created state self-heals at apply.
- **Webhook pin regeneration risk:** a `webhook.service` byte change with
  a stale `WEBHOOK_SERVICE_B64` silently refuses delivery on web-1 —
  `test_service_pin_matches_repo_unit` is the tripwire; the pin
  regeneration step is a mandatory sub-task, not optional.
- **Operator-reserved scope honored:** no file touched belongs to the
  #10382/#8839/#9943 holds or the #8525/#8013/#8080/#10290 carrier batch;
  the inngest-host units in `inngest-bootstrap.sh`/`cloud-init-inngest.yml`
  are #9962's closed territory and are not re-opened here.
- **`# dedupe:` marker lint drift:** marker comments could be cargo-culted
  onto genuinely-filing sites to silence the lint — mitigated by the
  mutation matrix's adjacency + zero-hit arms and by review; a marker is
  documentation, not a suppression of the fail-open fix.

## References & Research

- ADR-241 D2 (deployment-branch policy as the boundary):
  `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`
- SKIP-VS-FAIL precedent: PR #10073 (closes #9962), PR #9944 (#9939);
  learning `2026-10-11-conditioning-a-unit-also-conditions-every-detector-wired-to-its-failures.md`
- #9612 normalization shape: `scheduled-inngest-health.yml` inline
  `|| { ::error::…; VAR=""; }`; sentinel `scripts/lint-gh-argv-arg.py`
- Deferred-from plan: `knowledge-base/project/plans/2026-09-24-fix-inngest-bootstrap-tag-ancestry-gate-plan.md`
- GitHub docs: "Reuse workflows" (environment on called-job, caller-ref
  evaluation); "Deployments and environments" (deployment branch policy)
- Issues: #8780, #9659, #10078, epic #10390; live-race PR #10928; overlap
  #7098

## Sharp Edges

- The `# dedupe:` marker lint must classify the *call site's* handling,
  not the variable's name (`2026-09-29-a-source-census-*.md`).
- Do not re-open inngest-host units — #9962's scope is closed; the
  `inngest-bootstrap.sh` unprefixed lines there are deliberate dispositions.
- `environment:` on a job inside `reusable-release.yml` resolves in the
  caller repo — do NOT try to set it on the caller's `uses:` job (invalid).
- A plan whose `## User-Brand Impact` section is empty, placeholder-text,
  or omits the threshold will fail `deepen-plan` Phase 4.6 — filled above.
- `environment:` declarations grant the env's secrets to the job —
  `release-publish` must stay secrets-free; adding any secret to it
  re-widens the boundary the design keeps narrow.

