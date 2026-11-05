---
title: "chore(ci): CI/infra hygiene batch — dispatch-ref publish gates (#8780), dedupe fail-open normalization (#9659), web-host EnvironmentFile conditioning (#10078), observability/probe-schema residuals (#8525 #8013 #8080 #8839 #9943), transit exceptions (#10136), legal posture (#9074 #8624)"
type: fix
date: 2026-11-04
slug: ci-infra-hygiene-batch
branch: feat-one-shot-10390-ci-hygiene-batch
issue: 10390
closes: [8780, 9659, 10078, 8525, 8013, 8080, 8839, 9943, 10136, 9074, 8624]
lane: cross-domain
---

## Enhancement Summary

**Expanded on:** 2026-11-05 — scope grew from 3 to 11 issues (epic
#10390 Bucket-4 residual drain, one PR #12064): Workstream D
(#8525 #8013 #8080 #8839 #9943), E (#10136), F (#9074 #8624). Each
issue's verified residual is restated against merged PRs before scoping
(#8013's code fix, #8080's witness, #8839's lifecycle settle, #9943's
report/credential seam, #10136's TLS arc + flip, #9074's reach
determination). 8 new decision rows ruled inline (6 CTO, 2 CLO) and
recorded in `decision-challenges.md`. deepen-plan halt gates re-verified
on the expanded file: User-Brand (addendum), Observability (addendum),
PAT clean, no UI surface, Encryption Posture (Workstream E is the
ledger itself), Guard Contract lint 4/4 entries green, Scope Check
single section + expansion ask-mapping all `mapped`/`asked`-or-
`inferred`-justified, Task Design emitted for the new cron.

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
| #9659 enumerates 12 workflow files | Census today: 76 hits across **19** files — additions include `review-reminder.yml`, `scheduled-integration-suites.yml`, `main-health-monitor.yml`, `cla-evidence-timestamp.yml`, `apply-deploy-pipeline-fix.yml`, `web-platform-release.yml`, `scheduled-rehearsal-skip-monitor.yml` (CTO ruling pass, 2026-11-04) | Every hit is classified into the issue's three buckets; the marker lint makes new unclassified sites RED |
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
  mid-alarm with no breadcrumb. 76 census hits across 19 files today.
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
`web-platform-release.yml`, `scheduled-rehearsal-skip-monitor.yml`);
plus `scripts/test-all.sh`,
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

### Guard 4 — git-data liveness flip precondition (#9943, expansion)

**Property.** `mode=flip` cannot proceed while the git-data host's
liveness heartbeat is unproven — the dispatch refuses
`verdict=liveness_unproven` unless the heartbeat reads `up` AND a
`state=ok first=1` event exists newer than the current host's
`boot_complete` row.

**Assembly.** The single `preconditions` step in
`git-data-cutover.yml` — the only `flip` entry point (dispatch-only
workflow; `refs_assert`/`proof` modes map to non-flip reads and are
unaffected). The predicate rides the same `BS_DOPPLER_TOKEN` +
`scripts/betterstack-query.sh` channel the `new_sessions_paused` read
already binds (#11704), so the chokepoint is one step, not a second
credential seam.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Drop the heartbeat-`up` conjunct (accept any `state=ok` event alone) | RED |
| 2 | Accept a `state=ok first=1` event older than the host's `boot_complete` row | RED (stale-evidence class — the flip-time re-read is the binding one) |
| 3 | Pass when the Better Stack read fails or is unparseable | RED (unreadable reads refuse closed, never silently pass) |
| 4 | Harness: fixture where `state=ok` exists only with `first=0` (a steady-state tick, not a post-boot first) | RED (the first-boot discriminator) |
| 5 | must-PASS: heartbeat `up` AND `state=ok first=1` post-`boot_complete` | PASS (the designed green path) |

**Anchor.** The predicate reads the live query channel at dispatch
time, not a stored fixture — the evidence is the event stream itself,
and a `bs_read_classify` failure refuses closed rather than passing on
absence.

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

### Ask Mapping — Expansion (added 2026-11-05)

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 7 | "Add a LUKS-type field (for example the `blkid -o value -s TYPE` of the backing device …) to the `inngest-bootstrap.sh` probe schema, then flip the ledger row's `live_verification` to `available`" [#8525] | Workstream D1 (probe_schema=9 `data_luks` + follow-through for the live-verified flip) | mapped |
| 8 | "Strip hash tags before segmenting … correct [the false claim] wherever it is cited" [#8013] | Workstream D2 (comment retraction + #7978 corrective + live-row check; the strip itself already merged as schema-8 allowlist) | mapped |
| 9 | "`RestartSec=5 → RestartSec=300` in the next scheduled image bump … Record the 55k/day figure against the #7577 row-count tracker in `knowledge-base/operations/expenses.md`" [#8080] | Workstream D3 (RestartSec=300 + expenses.md row) | mapped |
| 10 | "a liveness backstop that does not depend on an Inngest lifecycle event … A sweep cron could mark rows whose `current_turn_started_at` is older than the 10-minute finish timeout plus a margin" [#8839] | Workstream D4 (`cron-agent-spawn-stale-settle`) | mapped |
| 11 | "The flip precheck refuses (`verdict=liveness_unproven`) unless the host heartbeat reads `up` and a `state=ok first=1` event exists after the current host's `boot_complete`" [#9943] | Workstream D5 (preconditions-step predicate) | mapped |
| 12 | "Each link has TLS with certificate verification on, or a ruled written decision that private-network plaintext is accepted with a dated owner" [#10136] | Workstream E (leg-1 measured row, leg-2 A7-anchored exception, zot x2 ruled decision) | mapped |
| 13 | "A CLO determination on whether the PA-13 Inngest stores are personal-data-bearing. Then correct both DPD surfaces (re-pin `LEGAL_DOC_SHAS`), Art. 30 PA-13 (f) and the repeating notes … and fix the neither/no wording" [#9074] | Workstream F1 (CLO determination + corrections sweep + SHA re-pin) | mapped |
| 14 | "Add the PA-14 amendment in the register's dated-marker form, with one `(encryption-posture ledger: …)` clause per store, and add the matching `records` entries to the ledger rows … Get a CLO ruling on item 2. If the sentence changes, update all three published documents and their mirrors" [#8624] | Workstream F2 (PA-14 amendment + ledger records + CLO-ruled qualifier + mirrors + re-pin) | mapped |
| 15 | "complete all remaining open 'Bucket 4' unblocked residual-backlog items in ONE pull request … Each issue's plan section MUST first restate the verified residual scope, citing what already merged" [operator direction] | The whole `## Expanded Scope` section — per-issue residual restatements cite the merged PRs before scoping | mapped |

### Plan-Item Provenance — Expansion

| Plan item | User words cited | Verdict |
|-----------|------------------|---------|
| `scripts/followthroughs/inngest-luks-field-8525.sh` | "flip … in the commit that records a probe row carrying an explicit LUKS-type field" (ledger row text) | inferred — justification: the flip needs live evidence; a soak-gated close needs the enrolled probe (Phase 2.9.1 convention) |
| `cron-agent-spawn-stale-settle` (new cron) | "A sweep cron could mark rows whose `current_turn_started_at` is older than the 10-minute finish timeout plus a margin" | asked |
| `stale_working` dead-letter suffix + COVERAGE update | — | inferred — justification: a settle with no report channel is invisible; COVERAGE is the file's own contract comment and goes stale otherwise |
| #7978 corrective comment | "should be corrected wherever it is cited" | asked |
| expenses.md 55k row | "Record the 55k/day figure against the #7577 row-count tracker" | asked |
| `verdict=liveness_unproven` site in the workflow step (not the precheck script) | "The flip precheck refuses …" — issue names both files; the BS credential seam lives in the workflow step | inferred — justification: CTO ruling (decision-challenges.md); reuses the merged #11704 credential binding |
| Zot accepted-risk audit record + #10136 comment | "a ruled written decision that private-network plaintext is accepted with a dated owner" | asked (owner confirmation remains an operator step) |
| PA-21/PA-22 superseded markers | "the repeating notes" | asked |
| `legal-doc-shas.ts` re-pin | "re-pin `LEGAL_DOC_SHAS`" | asked |

### Split Assessment — Expansion update

- Planned files grows to ~55 across 6 roots (apps, .github, scripts,
  docs, knowledge-base, plugins tests); thresholds still crossed and the
  issue-boundary seam still holds (each workstream is a disjoint file
  set except `inngest-bootstrap.sh` inside D and
  `encryption-posture-ledger.json` shared by E/F2 — adjacent-commit
  discipline recorded in Expanded Dependencies). Single-PR batch per the
  operator direction.

## Acceptance Criteria

**#8780 — publish admission**

- [x] AC-A1: `github_repository_environment.inngest_config_signing` carries
  `deployment_branch_policy { protected_branches = false; custom_branch_policies = true }`,
  a `github_repository_environment_deployment_policy.inngest_config_signing_main`
  (`branch_pattern = "main"`), and retains non-empty `reviewers.users`.
- [x] AC-A2: `github_repository_environment.release_publish` exists with a
  `main`-only policy set, no reviewers, no secrets — declared in
  `apps/web-platform/infra/release-publish-environment.tf`.
- [x] AC-A3: all three new resources appear as `-target=` entries in
  `apply-web-platform-infra.yml`'s allow-list.
- [x] AC-A4: `reusable-release.yml` `release` job declares
  `environment: release-publish`; `build-inngest-bootstrap-image.yml`
  `build` job declares `environment: release-publish`.
- [x] AC-A5: `terraform-target-parity.test.ts` pins both new
  job↔environment bindings, asserts `inngest_config_signing` and
  `release_publish` are each in the exactly-`{main}` policy set, and pins
  the three `-target=` lines.
- [x] AC-A6: ADR-241 carries the amendment recording the admission-gate
  class (in this PR, not a follow-up).
- [ ] AC-A7 (post-merge verification): the targeted apply ran from main
  and `gh api repos/jikig-ai/soleur/environments/{release-publish,inngest-config-signing}/deployment-branch-policies`
  shows `main` as the sole pattern for both — recorded in the PR body or
  a linked comment (the O0-style read-back).

**#9659 — dedupe normalization**

- [x] AC-B1: every census hit of
  `git grep -nE '=\$\([[:space:]]*gh (issue|pr) (list|search)' -- '.github/workflows/'`
  is fail-open-wrapped, `||`-handled, or adjacent to a `# dedupe:
  fail-closed`/`# dedupe: benign` marker; `scripts/lint-gh-dedupe-shape.py`
  prints `unclassified: 0` and runs green in `test-all.sh`.
- [x] AC-B2: every filing-path site enumerated in the issue (the 12-file
  list) is rewritten to the fail-open shape with a per-site `::error::`
  slug preserving its monitor name.
- [x] AC-B3: `lint-gh-dedupe-shape.py` + `.test.sh` registered as a suite
  pair (`test-all.sh` run_suite lines, `suite-durations.tsv`,
  `suite-shard-legs.tsv`, `guard-vacuity-floor.test.sh` PROMOTED check).

**#10078 — EnvironmentFile conditioning**

- [x] AC-C1: the five probe units (`inngest-consumer-probe`,
  `web-bash-synthetic`, `web-git-data-probe`, `web-private-nic-guard`,
  `web-zot-consumer-probe`) each carry
  `ConditionPathExists=/etc/default/<their-file>` in `[Unit]`, keep
  `EnvironmentFile=` unprefixed, and carry a SKIP-VS-FAIL comment naming
  the boot-emit fatal channel + their own heartbeat-beat detector.
- [x] AC-C2: `webhook.service` (repo file + `cloud-init.yml` embedded
  twin) and the `vector.service` heredoc carry designed-loud comments;
  no `ConditionPathExists` on their env file; `WEBHOOK_SERVICE_B64`
  regenerated in `infra-config-apply.sh`.
- [x] AC-C3: per-unit test pins updated — condition-path-set ≡
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


---

## Expanded Scope — Bucket-4 Residual Drain (added 2026-11-05)

**Expansion mandate.** PR #12064 grows to cover the remaining OPEN
Bucket-4 residual-backlog items of epic #10390 in one PR. Workstreams
A/B/C (#8780, #9659, #10078) are already implemented on this branch —
do not re-implement. Workstream D is the observability/probe-schema
cluster, E the transit-exceptions ledger, F the legal items. #9294 is
explicitly deferred (open draft PR #10928 is a live race; do NOT touch).

### Expansion Premise Validation (verified 2026-11-05 against this branch)

Every issue body was fetched with `gh issue view`; each named merged PR
was located in git history; each claimed file state was re-grepped on
this worktree. Findings per issue are restated in each workstream
below — the residual, not the issue title, is the scope.

- #8525 OPEN — probe emit line carries `data_mount_devid` but no LUKS-type
  field (`inngest-bootstrap.sh`, `SOLEUR_INNGEST_SERVER_PROBE` emit);
  ledger row `hcloud_volume.inngest_redis_luks` `live_verification` still
  `unavailable: …the cipher half`.
- #8013 OPEN — the `redis_key_patterns` **code fix already merged**
  (probe_schema=8 allowlist `iscategory()` reduction, commits
  `75746ee7cb`/`4249bc4af7`, contained in vinngest tags ≥ v1.1.59 and
  therefore live since the 2026-10-20 host replace). Residual: the stale
  false-claim comment at `inngest-bootstrap.sh` ("the identifier never
  leaves the box", the `NAMES ONLY, NEVER VALUES` block) and a live-row
  verification; the issue stands open on those.
- #8080 OPEN — **part 1 merged** (PR #11782 `64184a02d7`: the
  execute-gate satisfiability witness in `scheduled-inngest-health.yml`
  calls `inngest_execute_registry_gate`/`inngest_host_dark_gate`
  report-only, streaks, files `ci/inngest-gate-witness`+`action-required`
  at streak ≥8, auto-closes on satisfy, crash arm on step outcome).
  **Part 2 is the residual:** `inngest-server.service` still carries
  `Restart=on-failure`/`RestartSec=5` in `inngest-bootstrap.sh`; the
  ~55k rows/day figure is absent from `knowledge-base/operations/expenses.md`.
- #8839 OPEN — PR #8837 (`38a4ac44b0`, merged 2026-09-25) settled
  orphaned spawns on failure/timeout/cancel — past the issue's 14-day
  re-evaluation window. `spawn-dead-letter.ts` COVERAGE names the four
  remaining "Working" cases: runs Inngest loses entirely, failed
  `persist-failure` UPDATEs, retry-exhausted settles/forwards, and the
  pre-fix historical rows.
- #9943 OPEN — PR #10153 (`9560c26a0a`) landed the flip-precondition
  *report*; the liveness feeder with paused heartbeat is merged
  (`git-data-cutover.yml` preconditions step reads `new_sessions_paused`
  via `BS_DOPPLER_TOKEN` + `scripts/betterstack-query.sh` — the issue's
  credential objection is dissolved). `git-data-flag-precheck.sh` and the
  flip preconditions step carry NO host-heartbeat predicate; the runbook
  item at `git-data-luks-cutover-5274.md` ("Until #9943 enforces it in
  the workflow…") is still the binding manual check.
- #10136 OPEN — Inngest TLS arc merged (`#10501` terminator inert-until-
  flipped; `inngest-link-flip.yml` dispatch machinery; A5/A6 owner-ask
  probe, A6 no-known-access record #11882, A7 leg-2 accepted-risk record
  `knowledge-base/legal/audits/2026-11-02-a7-leg2-accepted-risk-ledger-inngest-sdk-url-poll.md`).
  The flip **ran green 2026-10-26T13:48:55Z** (`gh run list
  --workflow inngest-link-flip.yml`); the 48h soak follow-through
  `inngest-tls-soak-10136.sh` exists. Residual: all three ledger
  exception rows still read `tls: none`/`cert_verification: off` renewed
  to 2026-11-12 "pending the CLO ruling due 2026-10-24" — the Inngest row
  is now stale post-flip, and the two zot rows still need either TLS or
  the ruled written decision.
- #9074 OPEN — PR #10848 merged the *reach* determination (DPD §2.3(o)
  and §2.3(aa) record that erasure/export do not reach the dedicated
  store; PA-13/PA-14/PA-27 carry the 2026-11-02 "Added … CLO ruling"
  markers). Residual: the **personal-data-bearing** determination is
  still open — DPD §2.3(o) store sentence still reads "neither store is
  personal-data-bearing" beside "THREE stores" (both canonical
  `docs/legal/` and mirror `plugins/soleur/docs/pages/legal/` carry it),
  and PA-13 (f) still carries "Not personal-data-bearing at v1 for THIS
  activity, because Stripe customer email is hashed BEFORE the envelope
  is signed", quoted downstream by PA-21/PA-22's #6894 amendments.
- #8624 OPEN — PA-14 never received the #6894 device amendment form
  (PA-21 L~428 and PA-22 L~446 carry the `[2026-09-18 AMENDMENT (#6894)
  …]` dated-marker blocks; PA-14's cells name the stores only
  functionally for retention). `docs/legal/privacy-policy.md` still
  asserts "**Encrypted workspace storage:** … **LUKS-encrypted
  (encryption at rest)**" unqualified while web-1's root disk holds the
  `prd_workspaces_luks`-scoped Doppler token (`/etc/default/luks-monitor`,
  ledger row `hcloud_server.web`, #8620).

### Workstream D — observability/probe-schema cluster

**D1 — #8525: LUKS-type field in the server probe (probe_schema=9).**
Residual restated: the emitter is the only missing half; the ledger
says "flip to available in the commit that records a probe row carrying
an explicit LUKS-type field". The shape authority is
`hcloud_volume.registry`'s `store_luks` (#8423): emit
`data_luks=<TYPE>` where `<TYPE>` is `blkid -o value -s TYPE` of the
device backing `/mnt/data` (resolved through the existing
`data_mount_src` mapper chain), with an unconditional-emit sentinel
(`n/a`, `__UNREADABLE__` family) matching every sibling field's
contract — no `if` may gate the emit line. probe_schema bumps 8→9; the
emit line, the phone-home mirror emit, and every consumer/test that
parses the row field-set update together (the `inngest-host-dark-gate.sh`
field set, probe-schema pins, and any `probe_schema=8`-keyed test).
Follow-through enrollment: `scripts/followthroughs/inngest-luks-field-8525.sh`
— exit 0 when a live `SOLEUR_INNGEST_SERVER_PROBE` row carries
`data_luks=crypto_LUKS` (and `probe_schema=9`) on the serving host;
directive `<!-- soleur:followthrough script=… earliest=<next replace+1d> -->`
commented on #8525 with the `follow-through` label. The ledger row's
`live_verification` flips to `available` ONLY in the commit that records
that live row — the flip is the follow-through's own edit, not this
PR's (the row is honest: the field ships inert until the next image +
host replace, the same baked-carrier constraint #8013 recorded).

**D2 — #8013: false-claim retraction + live verification.** Residual
restated: the fix shipped; the claim did not. (a) Rewrite the stale
`NAMES ONLY, NEVER VALUES` comment block in `inngest-bootstrap.sh` — the
"the identifier never leaves the box" sentence is false as written
(two-segment verbatim passed `{estate:<ULID>}` whole); the correction
states the schema-8 allowlist rule and cites #8013's measurement.
(b) Post a corrective comment on #7978 naming the false sentence and
the measured counter-example (the issue body/commit can't be edited —
a dated correction comment is the retraction the issue asks for).
(c) Live verification AC: a Better Stack query
(`bash scripts/betterstack-query.sh` with the reporter query; needs the
Doppler `prd_terraform` read secrets at run time) shows zero
`redis_key_patterns` rows containing a ≥20-char identifier-shaped
segment since the replaced host's first schema-8 emit. Record
evidence in the PR body; file `action-required` only if the query
itself is unreadable.

**D3 — #8080: quiet the P1-5 refuse loop + expenses ledger.** Residual
restated: the witness is done; the loop is not. (a)
`inngest-server.service` unit template: `RestartSec=5 → 300`, with the
comment updated to name the class (the flip-guard BLOCK loop at
~229 BLOCK + ~271 doppler-wrapper rows per 500-row window ≈ 55k/day
measured 2026-09-11) and why 300 was chosen (same loop semantics, no
`StartLimitBurst`, no `failed` latch → no `reset-failed` needed in
`inngest-cutover-flip.sh`'s bare `systemctl start`, ~55k→~1k rows/day).
This is a baked-carrier change — it rides the next image bump + host
replace; no live effect in this PR (same constraint as D1). (b)
`knowledge-base/operations/expenses.md`: record the 55k/day figure
against the Better Stack row (#7577 row-count tracker) so the decision
sits on the ledger.

**D4 — #8839: stale-"Working" backstop.** Residual restated: lifecycle-
event settling is done; the two non-event cases are not. The
`deriveTodayCardState`-renders-stale option is rejected (a UI
state-matrix change triggers the BLOCKING Product/UX gate and a `.pen`
wireframe obligation — disproportionate for a hygiene batch, and it
hides rather than settles the row). Build the sweep: a new cron Inngest
function `cron-agent-spawn-stale-settle` in
`apps/web-platform/server/inngest/functions/` that (a) selects
`action_sends` spawn rows still on Working whose
`current_turn_started_at` is older than the finish timeout + margin
(the 10-minute finish bound plus a fixed margin — name the constant),
(b) verifies no live Inngest run exists for the row (the lost-run
discriminator — a sweep that marks a live run's row is the defect
class), (c) writes `failure_reason` + terminal settle via the same
`agent-on-spawn-settle` path the lifecycle handlers use (never a new
write path), and (d) reports to `spawn-dead-letter` under a new
`stale_working` suffix so the paging rule's reason list and COVERAGE
comment update in the same diff. Historical rows settle on the first
run; lost runs settle each tick. Registered in `cron-manifest.ts` +
`EXPECTED_CRON_FUNCTIONS` census and the cron-budget table
(`cron-budgets.ts`) per the registration learning. New autonomous-task
surface → `## Task Design` block below.

**D5 — #9943: machine-enforce the liveness-heartbeat flip
precondition.** Residual restated: the runbook item and report merged;
the enforcement did not. Site: the flip `preconditions` step of
`git-data-cutover.yml` — the same step that already binds
`BS_DOPPLER_TOKEN` and calls `scripts/betterstack-query.sh` for the
`new_sessions_paused` read (#11704), so no new credential is needed
(the issue's "new Better Stack read credential" objection is dissolved
by that merged read). Predicate, per the issue's done-state: refuse
`verdict=liveness_unproven` (fail via the step's existing `fail`
helper) unless (a) the `soleur-git-data-host-prd` betteruptime heartbeat
reads `up` AND (b) a `state=ok first=1` event exists newer than the
current host's `boot_complete` row — both read via the same query
channel with the same `bs_read_classify` failure taxonomy (unreadable
reads refuse; never silently pass). Update the runbook's hard item at
`git-data-luks-cutover-5274.md` to record the machine check (the
flip-time re-read stays — the check IS the re-read). Guard Contract
entry below.

### Workstream E — #10136: transit-exception ledger reconciliation

Residual restated: leg-1 (app → inngest :8288) flipped to verified TLS
2026-10-26; leg-2 (inngest → app `sdk_url` poll :3000) stays plaintext
under the A7 accepted-risk record (until 2026-11-12, extendable to
2026-12-10 only if the replacement merges by then); the two zot rows
are untouched plaintext exceptions pending the CLO ruling the ledger
text already promises "due 2026-10-24".

1. **Rewrite the Inngest connection row** in
   `scripts/encryption-posture-ledger.json`: leg-1 becomes a measured
   row (`tls: TLS 1.2+ via soleur-inngest-tls.service`,
   `cert_verification: on` — CA-pinned fail-closed resolver, evidence
   = the 2026-10-26 `inngest-link-flip.yml` run + `tls-health` rows);
   leg-2 keeps an `exception` block quoting the A7 record verbatim —
   its accepted-until date, its voids (server beyond the five on
   10.0.1.0/24, public exposure), and `#10538` as the replacement
   tracking issue. The row's two legs are split explicitly (the current
   single-row form predates the flip).
2. **Zot x2: ruled written decision.** The issue's done-when admits
   "a ruled written decision that private-network plaintext is
   accepted with a dated owner" as an alternative to TLS. The CLO
   ruling (recorded in `decision-challenges.md`): private-network
   plaintext on the two zot links is **accepted** — bounded acceptance:
   expires on the next 10.0.1.0/24 topology change or any
   public/cross-network exposure of the registry (the issue's own
   re-evaluation triggers), owner-dated via the accepted-risk record
   mechanism the A7 precedent established. The ledger rows are updated
   to point at the ruling + record with a concrete `expires_on` and the
   ruling date; the "pending the CLO ruling" prose is retired.
   The owner-signature half (the "dated owner") is the same mechanism
   A7 used — an agent-posted record confirmed by the owner's in-session
   instruction; the PR posts the record for owner confirmation on
   #10136 (an operator confirmation item, recorded as the PR's single
   operator step; see Operator Steps).
3. Retire the stale "pending the CLO ruling due 2026-10-24" prose in
   all three rows — either measured (leg-1) or ruled (zot x2), nothing
   stays "pending" past its own date.

### Workstream F — legal items

**F1 — #9074: PA-13 personal-data-bearing determination.** Residual
restated: the reach determination merged; the bearing determination
did not, and the count defect survives.

- **CLO determination (executed inline, recorded in
  decision-challenges.md):** the PA-13 Inngest stores **are**
  personal-data-bearing for PA-13. The envelope carries `founderId`
  (a user identifier); `customerEmailHash` is an unsalted sha256 of an
  email address — pseudonymised, not anonymised, under Art. 4(5) and
  Recital 26; the generated draft text may name the customer; and the
  #8754 determination already treats the dedicated Inngest store as
  personal-data-bearing. The prior claim "not personal-data-bearing
  because customer email is hashed at the webhook boundary" is
  retracted.
- **Corrections** (all in the same PR, per the register's
  amendment-form conventions — dated markers, verbatim-quoted
  supersession):
  - DPD §2.3(o) store sentence in `docs/legal/data-protection-disclosure.md`
    AND its mirror `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
    — fix the "THREE stores … neither store" count defect AND restate
    the bearing determination; the `**Last Updated:**` entry is updated
    per the docs' own amendment convention (note that amendment notes
    quote the superseded phrase verbatim — the absence-grep trap from
    #10849 applies).
  - Art. 30 `article-30-register.md` PA-13 (f) — the
    "Not personal-data-bearing at v1 for THIS activity" clause is
    corrected in-cell with a `> **Superseded <date> (#9074): …**`
    marker, per the CLO correction convention (the cell changes AND the
    marker lands).
  - The **repeating notes**: PA-21 (L~428) and PA-22 (L~446) #6894
    amendments quote the PA-13 claim as their premise ("true there,
    because the Stripe customer email is hashed before the envelope is
    signed") — each gets a superseded-marker note so a reader is not
    told a retracted premise still stands; the amendments' own
    substance (the device naming) is unchanged. Grep the register for
    every other repeat of the claim before declaring the sweep closed
    (`not personal-data-bearing`, `personal-data-bearing`).
  - `apps/web-platform/scripts/check-tc-document-sha.sh` re-pin
    (`legal-doc-shas.ts`) after the canonical edit; run the five CI
    gates over `docs/legal/**` locally (scope-block lint,
    mirror-drift baseline, SHA pin, consistency vitest, EXPECTED_COUNT
    sentinel).
  - `knowledge-base/legal/compliance-posture.md` Active Items — close
    or annotate the #9074 tracking entry if present.

**F2 — #8624: PA-14 device amendment + workspace-encryption claim.**

- **PA-14 amendment** in the register's dated-marker form (mirror the
  PA-21/PA-22 `[2026-09-18 AMENDMENT (#6894) …]` shape, dated
  2026-11-05, `(#8624)`): the Inngest REDIS AOF is a store of PA-14's
  activity (the envelope tier pin + audit-viewer run-history reads), one
  `(encryption-posture ledger: …)` clause per store — today the live
  stores are `hcloud_volume.inngest_redis_luks` (Redis AOF, LUKS since
  2026-09-20; the plaintext `inngest_redis` backstop was destroyed
  2026-10-09 — the issue's two-volume enumeration is stale, re-derive
  rather than copy it), the dedicated Supabase Postgres project, and the
  root-disk SQLite fail-safe. Matching `records` entries on the ledger
  rows in `scripts/encryption-posture-ledger.json` (the register-entry
  citation each store row carries).
- **CLO ruling on the published claim (executed inline, recorded in
  decision-challenges.md):** the "Encrypted workspace storage" sentence
  **needs a qualifier**. The claim is true of the volume's at-rest
  mechanism, but web-1's unencrypted root disk holds a
  `prd_workspaces_luks`-scoped Doppler token
  (`/etc/default/luks-monitor`) that can fetch the passphrase — the
  encryption claim, read plainly, implies the ciphertext resists a
  host-root compromise, which the co-resident key-fetch path partially
  defeats. Qualify, do not retract: the sentence gains a bounded clause
  naming that the volume's passphrase is reachable through a credential
  held on the serving host itself (the honest bound, per the ledger's
  `hcloud_server.web` row and #8620). Update all three published
  documents (privacy-policy canonical + mirror; DPD §8.1's measure row
  if it repeats the claim; any third surface the grep finds —
  `grep -rn 'LUKS-encrypted\|Encrypted workspace' docs/legal/
  plugins/soleur/docs/pages/legal/`) and re-pin `legal-doc-shas.ts`.

### Expanded Files to Edit (supplements the lists above)

Workstream D:

- `apps/web-platform/infra/inngest-bootstrap.sh` — D1 probe_schema=9 +
  `data_luks` emit (emit line + phone-home mirror) + D2 false-claim
  comment rewrite + D3 `RestartSec=300` on the inngest-server template.
- `tests/scripts/lib/inngest-host-dark-gate.sh` and every probe-schema=8
  pin/test fixture — schema-9 field-set updates (exact census bound at
  implementation: `git grep -n 'probe_schema' tests/ apps/ scripts/`).
- `scripts/followthroughs/inngest-luks-field-8525.sh` (create) + its
  `.test.sh`.
- `apps/web-platform/server/inngest/functions/cron-agent-spawn-stale-settle.ts`
  (create) + `cron-manifest.ts`, `EXPECTED_CRON_FUNCTIONS`,
  `cron-budgets.ts` registrations; `spawn-dead-letter.ts` COVERAGE +
  `PAGED_DEAD_LETTER_REASONS`/`failure-reason.ts` suffix additions;
  `spawn-dead-letter-triage.md` runbook arm.
- `.github/workflows/git-data-cutover.yml` — D5 preconditions-step
  liveness predicate (reuses `BS_DOPPLER_TOKEN` + `betterstack-query.sh`).
- `apps/web-platform/infra/git-data-flag-precheck.sh` — verdict
  documentation update IF the check lands in the workflow step (the
  script's verdict header names the mode predicates; keep them honest)
  or the check itself if CTO sites it there (see ruling).
- `knowledge-base/operations/expenses.md` — the 55k/day row note.
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`
  — the hard item updated to machine-enforced.

Workstream E:

- `scripts/encryption-posture-ledger.json` — the three connection rows.
- `knowledge-base/legal/audits/<date>-zot-private-network-accepted-risk-10136.md`
  (create) — the ruled decision record (A7 precedent form).
- #10136 comment — the agent-posted accepted-risk record for owner
  confirmation.

Workstream F:

- `docs/legal/data-protection-disclosure.md` +
  `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` —
  §2.3(o) store sentence + Last Updated note.
- `docs/legal/privacy-policy.md` +
  `plugins/soleur/docs/pages/legal/privacy-policy.md` — the
  workspace-storage qualifier.
- `knowledge-base/legal/article-30-register.md` — PA-13 (f) in-cell
  correction + superseded markers on the PA-21/PA-22 quoting notes;
  PA-14 dated-marker amendment.
- `scripts/encryption-posture-ledger.json` — `records` entries for the
  PA-14 citation (shared file with Workstream E — same PR, no conflict;
  different rows).
- `apps/web-platform/lib/legal/legal-doc-shas.ts` — re-pin (both docs).
- `knowledge-base/legal/compliance-posture.md` — active-item updates.

### Expanded Acceptance Criteria

**D — observability/probe-schema**

- [ ] AC-D1: `SOLEUR_INNGEST_SERVER_PROBE` (and the phone-home mirror
  emit) carries `data_luks=` and `probe_schema=9` with an unconditional
  sentinel contract identical to sibling fields; every `probe_schema=8`
  consumer/pin updated; `bash tests/scripts/test-git-data-*`-class probe
  suites and the bootstrap pin suite green.
- [ ] AC-D2: `scripts/followthroughs/inngest-luks-field-8525.sh` exists
  with a green `.test.sh`; the follow-through directive + label are on
  #8525; the ledger `live_verification` flip is deferred to the
  follow-through commit (the row records that ordering).
- [ ] AC-D3: the stale "never leaves the box" sentence is retracted in
  `inngest-bootstrap.sh`; the #7978 corrective comment is posted; the
  live-row ULID-absence query is recorded in the PR body (or an
  `action-required` issue filed naming the unreadable query).
- [ ] AC-D4: `RestartSec=300` on the inngest-server template with the
  class-naming comment; the 55k/day figure is on the Better Stack
  expenses.md row; `inngest-cutover-flip.sh` needs no `reset-failed`
  (asserted: no `StartLimitBurst` introduced).
- [ ] AC-D5: `cron-agent-spawn-stale-settle` registered and settled
  only rows older than timeout+margin with NO live Inngest run — the
  negative pin (a live-run row is never marked) is a test, not a
  comment; `spawn-dead-letter` reports the `stale_working` suffix;
  COVERAGE updated.
- [ ] AC-D6: `git-data-cutover.yml` `mode=flip` refuses
  `verdict=liveness_unproven` when the host heartbeat is not `up` or no
  post-`boot_complete` `state=ok first=1` event exists; an unreadable
  Better Stack read also refuses (never passes); the runbook item is
  re-worded machine-enforced.

**E — #10136**

- [ ] AC-E1: the Inngest ledger row records leg-1 as measured TLS
  (evidence = the 2026-10-26 flip run + `tls-health`) and leg-2 as an
  exception anchored to the A7 record's dates and voids.
- [ ] AC-E2: both zot rows carry the ruled decision record path, a
  concrete `expires_on`, and no "pending … ruling" prose; `lint-
  encryption-posture.py` and the ledger vitest green.
- [ ] AC-E3: the accepted-risk record is posted on #10136 for owner
  confirmation (operator step, see below).

**F — legal**

- [ ] AC-F1: the CLO determination is recorded; DPD §2.3(o) (canonical
  + mirror) no longer says "neither … personal-data-bearing" and names
  the stores correctly; PA-13 (f) is corrected in-cell with a
  superseded marker; every register repeat of the claim carries a
  marker or is re-derived (grep-verified zero unmarked repeats).
- [ ] AC-F2: PA-14 carries the dated-marker amendment with one
  `(encryption-posture ledger: …)` clause per live store, and the
  ledger rows carry the matching `records` entries.
- [ ] AC-F3: the workspace-encryption sentence carries the qualifier in
  every published surface the grep finds; `legal-doc-shas.ts` re-pinned;
  the five legal-doc CI gates pass locally.

### Expanded Gates (addendum — the earlier gate sections still stand)

- **Domain Review addendum:** Legal domain is now relevant (F1/F2 touch
  `docs/legal/**`, the register, and published claims). The CLO agent
  was executed inline for the two legal rulings (recorded in
  `decision-challenges.md`); no Product/UX trigger — no UI-surface file
  is created or edited. D4 rejected the render-side fix precisely to
  keep that true.
- **User-Brand Impact addendum:** threshold stays `none` for D/E
  (internal machinery). F1/F2 change published legal sentences — the
  blast radius is a published overstatement; threshold `single-user
  incident` for the legal surfaces, and the CLO attestation is the
  sign-off (v1 posture: the agent CLO is the attestation authority).
  `threshold: none, reason:` for the sensitive-path surface remains as
  stated, and the legal surface is handled by the CLO ruling rows.
- **Observability addendum:** D4's sweep reports via the existing
  `spawn-dead-letter` paging path (destination: Sentry
  `sentry_alert.spawn_agent_dead_letter`; fail_loud: `stale_working`
  suffix). D5's predicate failures surface as `verdict=liveness_unproven`
  `::error::` rows + the workflow's existing `fail` annotation channel.
  D1/D3 ship inert until the next image+replace — their observability
  is the follow-through (D1) and the expenses/row-count ledger (D3).
- **Encryption Posture addendum:** Workstream E *is* the posture ledger
  — the row rewrites satisfy this section's own schema (each edited row
  carries mechanism/evidence/defends/does_not_defend/disclosed_as/exception
  verbatim where an exception remains).

- **Guard Contract addendum:** the #9943 liveness flip precondition
  lands as `### Guard 4` in the `## Guard Contract` section above
  (property/assembly/5-row matrix/anchor).
- **Operator Steps (single, named):** posting the #10136 zot
  accepted-risk record requires the owner's in-session confirmation to
  satisfy "a dated owner" (the A7 mechanism). Until confirmed, the
  ledger rows cite the ruling + the posted-for-confirmation record; the
  issue does not auto-close on merge — it closes on confirmation or is
  re-scoped by the owner. Everything else in the expansion is
  non-operator (the TLS flip already ran; no production mutation is in
  this PR's diff).

## Task Design

New autonomous-task surface (plan Phase 2.9.3): `cron-agent-spawn-stale-settle`
(Inngest cron function, `apps/web-platform/server/inngest/functions/`).

- **Trigger / cadence:** cron on the fleet convention (`*/15 * * * *` —
  at or below the finish-timeout granularity so a lost run cannot sit
  visibly stale for multiples of the bound); registered in
  `cron-manifest.ts` + `EXPECTED_CRON_FUNCTIONS`.
- **Action per tick:** selects `action_sends` spawn rows on Working whose
  `current_turn_started_at` exceeds finish-timeout + margin AND whose
  Inngest run is verifiably not live (the lost-run discriminator — a
  row with a live run is never marked, negative pin is a test);
  settles via the shared `agent-on-spawn-settle` path; reports
  `stale_working` to `spawn-dead-letter`.
- **Failure shape / alert route:** a settle failure reports through the
  existing `sentry_alert.spawn_agent_dead_letter` channel (Sentry →
  operator); a sweep crash is a failed routine run on `routine_runs`.
- **Idempotency:** the settle path is already idempotent (terminal
  `failure_reason` write); a re-tick over a settled row is a no-op by
  the Working predicate.
- **Cost:** no LLM, no Anthropic spend; budget entry in
  `cron-budgets.ts`.
- **Coverage / kill:** bounded by the Working+age predicate; disabling
  is removing the cron registration (manifest-keyed, no flag).

### Expanded Dependencies & Risks

- **`inngest-bootstrap.sh` is now a three-way touch** (D1 schema bump +
  D2 comment + D3 RestartSec) plus the already-merged A/B/C work —
  sequence the edits in one commit or three adjacent ones; the baked-
  carrier constraint means none takes live effect until the next
  image+replace, which is already the bucket-2 critical path — this
  PR deliberately does not spend a host replace.
- **`scripts/encryption-posture-ledger.json` is touched by both E and
  F2** — disjoint rows, same file; keep in one commit or adjacent ones.
- **Legal sweep completeness:** the `not personal-data-bearing` /
  `neither` / `LUKS-encrypted` greps are census obligations, not
  spot-checks — AC-F1/F3 make the zero-repeat count the predicate.
- **D4 write safety:** the sweep mutates production `action_sends`
  rows — the live-run discriminator check is the fail-safe; the
  mutation matrix for the sweep's own test battery must include a
  live-run-must-survive row.
- **#9294 live race** (unchanged): draft PR #10928 overlaps
  `apply-web-platform-infra.yml`, `terraform-target-parity.test.ts`,
  ADR-241 — this expansion adds `git-data-cutover.yml` and legal docs
  to the watch list; re-check `gh pr view 10928 --json files` before
  finalizing edits.
