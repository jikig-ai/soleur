---
title: "feat: migrate every deploy-trio consumer to the deploy-channel carrier (#9294 PR-B)"
type: refactor
date: 2026-11-20
slug: deploy-trio-consumer-migration-prb
branch: feat-one-shot-9294-deploy-trio-prb
issue: 9294
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: true
---

# feat: migrate every deploy-trio consumer to the deploy-channel carrier (#9294 PR-B)

## Enhancement Summary

**Deepened on:** 2026-11-20
**Sections enhanced:** Sweeper partition (D-1 flag surface), script de-shaping
(D-2 residual set), probe retirement (citation sweep), Guard Contract (3
guards × 4 mutation rows), Observability (Check-10-clean probe), Scope Check,
Research Insights
**Research agents used:** none — `Reviewed-Coverage: sequential-fallback`
(this harness cannot spawn subagents; all gates ran inline in one context —
Sections 2/3/4/5 of the deepen skill, halts 4.5–4.13, lint-guard-contract,
and the round-1 realism passes executed sequentially with the results below)

### Key Improvements

1. Verify-the-negative pass confirmed `inngest-link-flip.sh`,
   `key-rotate.sh` and `inngest-key-rotate.sh` already read canonical names
   via `bc_curl`/`bc_hmac` name-args — and caught that `cutover-inngest.sh`'s
   `${!_sigvar}` signature indirection survives the rename and must stay
   pointed at `WEBHOOK_DEPLOY_SECRET`.
2. Post-edit self-audit found two live citations of the retired probe
   (`scheduled-followthrough-sweeper.yml:135`,
   `.claude/hooks/grep-q-pipe-guard.test.sh:2215`) added to the work-list.
3. The `discoverability_test` was rewritten to a Check-10-clean probe
   (no shell-active bytes, allowlisted verb, single-literal output).

### New Considerations Discovered

- The arc's own `discoverability_test` (`bash -c '…&&…'`) predates Check
  10's shell-active reject; any sibling plan copying that shape fails
  preflight — noted so it is not propagated.
- `sweep-deploy-channel`'s ADR-033 precedent check: the work is
  repo/issue-scoped (no app context), and the partition must live beside
  the existing `sweep` job for the overlap assertion — GH Actions job is
  the canonical placement here, matching `sweep` precedent.

## Overview

PR-B of the #9294 deploy-channel credential arc. PR-A (#12810, squash
9cfcc7f47, merged 2026-11-19) shipped the carrier: the `deploy-channel` GitHub
environment (main-only deployment branch policy, no reviewers), the
`soleur-deploy-channel` Doppler project holding a hash-equal copy of the trio
(`WEBHOOK_DEPLOY_SECRET`, `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`) in
`prd`, and the `infra-credentials` narrow loader arm
(`doppler-project=soleur-deploy-channel`, `source=tier_b_deploy_channel`). The
seed tranche is verified live (2026-11-20, `gh api` read-back): exactly one
branch-type policy `main`, no tag policies, and `DOPPLER_TOKEN_DEPLOY_CHANNEL`
present on both `deploy-channel` and `inngest-cutover`.

This change is the consumer migration. Every workflow job that names the trio
binds the literal `deploy-channel` environment and reads the trio from the
narrow loader's exported job env — never from `secrets.*` of the trio. Scripts
and docs are de-shaped so counted read shapes (`doppler run|secrets
get|download` commands, `${{ secrets.<NAME> }}` binds, `${!var}` indirections of
family names) disappear or are explicitly ruled. The follow-through sweeper is
partitioned so trio-declaring trackers are served only by a new Tier-B arm, the
retired #6178 soak probe is deleted, the trio joins `TIER_B_NAMES`, new
boundary-census rows pin the migration, `tests/scripts/trio-baseline.tsv`
reaches its terminal state (zero `tier-a`, `FALLBACK:*`, `ALIAS:*` rows), and
ADR-241 records the D1 census amendment.

The authoritative spec for this PR is the merged arc plan
`knowledge-base/project/plans/archive/20261117-181828-2026-11-16-9294-deploy-channel-creds-tier-move.md`
— its `### The consumer migration (PR-B)`, `### Baseline end-state rule`,
`## Guard Contract`, `## Downtime & Cutover`, and `## Dependencies & Risks`
sections are adopted wholesale; this file re-derives the consumer set against
the live tree and resolves the open residuals the arc left as named decision
points.

`lane:` defaulted to `cross-domain` — no `spec.md` exists for this branch (TR2
fail-closed).

## Problem Statement / Motivation

Acceptance criterion 1 of #9294: "Neither the Doppler copies nor the
GitHub-secret copies of the three credentials can be named by a workflow that
has not passed a main-only environment." Today eleven workflows still bind the
trio via `${{ secrets.* }}`, and ~30 non-workflow files keep counted read
shapes or stale `prd_terraform` recipes that pin `tier-a` rows in
`tests/scripts/trio-baseline.tsv`. PR-A built the destination; this PR moves
the traffic. The migration is what lets the owner-named tail delete the
`prd_terraform` and repo-secret copies — until then the trio exists in both
stores hash-equal, so a consumer reading either store receives byte-identical
values and no rotation race exists.

## Proposed Solution

### Workflow consumer migration

Per the arc's consumer table, verified against the live tree 2026-11-20. The
narrow-loader step shape in every migrated job is:

```yaml
environment: deploy-channel
steps:
  - uses: ./.github/actions/infra-credentials
    with:
      doppler-project: soleur-deploy-channel
      doppler-token-deploy-channel: ${{ secrets.DOPPLER_TOKEN_DEPLOY_CHANNEL }}
```

(`secrets.DOPPLER_TOKEN_DEPLOY_CHANNEL` is an `ENV_SECRETS` member — an
environment secret, resolvable only after the branch policy admits the ref —
not a trio name; the census permits exactly this shape.)

| Workflow | Job(s) | Migration | Baseline-row end state |
|---|---|---|---|
| `web-platform-release.yml` | `deploy` (@1283), `verify-peer-deploy` (@1915) | both bind `deploy-channel` + narrow loader; drop 4 `${{ secrets.* }}` bind sites; run bodies rename `WEBHOOK_SECRET`→`WEBHOOK_DEPLOY_SECRET` and de-shape the `${!_v}` CF-pair trim loops to explicit per-name expansions | forward-classed `tier-a → tier-b` (run bodies keep naming the family; every naming job binds a literal Tier-B env) |
| `canary-status.yml` | `read-canary-status` (@23) | `deploy-channel` + narrow loader; drop binds; `bc_hmac_sha256_hex WEBHOOK_DEPLOY_SECRET` canonical read | `tier-a → tier-b` |
| `cutover-inngest.yml` | `cutover` (@73) | env expression gains the third arm: `(inputs.op == 'rollback' \|\| inputs.op == 'resume' \|\| inputs.op == 'backup') && 'inngest-cutover' \|\| 'deploy-channel'`; narrow loader serves every arm (the token secret exists on both environments); the `if: op == 'backup'` privileged-loader step stays HCLOUD-only; drop the trio binds at :202-204; `scripts/cutover-inngest.sh` reads canonical names | deleted — the file stops naming the family |
| `deploy-inngest-image.yml` | `deploy` (@28) | `deploy-channel` + narrow loader; drop 2 bind sites; rename `WEBHOOK_SECRET` reads; de-shape the `${!_v}` trim loop (:58) | `tier-a → tier-b` |
| `inngest-key-rotate.yml` | `redeploy` (@388) | `deploy-channel` + narrow loader; drop binds at :422-424; `scripts/inngest-key-rotate.sh` reads ambient canonical env | deleted |
| `inngest-link-flip.yml` | `flip` (@66) + `Revert to http` step | `deploy-channel` + narrow loader; drop binds at :103-105 and :117-119; `scripts/inngest-link-flip.sh` already reads canonical names | deleted |
| `key-rotate.yml` | `redeploy` (@225) | `deploy-channel` + narrow loader; drop binds at :269-271 (track step) and :285-287 (vector step); `scripts/key-rotate.sh` reads ambient canonical env | deleted |
| `restart-inngest-server.yml` | `restart` (@29) | `deploy-channel` + narrow loader; drop 3 bind sites; rename `WEBHOOK_SECRET` reads | `tier-a → tier-b` |
| `scheduled-inngest-health.yml` | `probe` (@65) | `deploy-channel` + narrow loader; drop binds; rename `WEBHOOK_SECRET` reads | `tier-a → tier-b` |
| `scheduled-followthrough-sweeper.yml` | `sweep` (@61) + NEW `sweep-deploy-channel` | see Sweeper partition below | deleted or `→ tier-b` per the flag-surface ruling (D-1) |
| `apply-deploy-pipeline-fix.yml` | `apply` (@241, already `environment: infra-privileged`) | zero `secrets.<trio>` binds — no migration needed; its 3 `tier-a` rows come from `doppler` commands over NON-trio creds (`doppler run --name-transformer tf-var -- terraform …`, `doppler secrets get APP_DOMAIN_BASE`) while naming the trio via `${VAR:?}` env reads | **named decision point D-2** — it cannot de-tier under current scanner rules |

`git-data-cutover.yml` and `apply-web-platform-infra.yml` were in the issue's
known set but name no trio member on the live tree (the former migrated in
PR-2; the latter only *calls* `verify-tunnel-ingress-origin.sh`, whose env is
supplied by the caller's Tier-B loader). Issue-named scripts
`scripts/followthroughs/infra-config-*-7220` and
`canary-promotion-5875.sh` no longer exist. `inngest-link-flip.yml`,
`key-rotate.yml`, `inngest-key-rotate.yml` are re-derived consumers the issue's
list did not name.

### Sweeper partition

`scheduled-followthrough-sweeper.yml` gains a second job,
`sweep-deploy-channel`, and `scripts/sweep-followthroughs.sh` gains the
partition flags:

- **`sweep` (existing job):** loses the three `${{ secrets.<trio> }}` binds and
  gains a partition flag. A tracker whose `secrets=` names a credential this
  arm cannot forward is partition-skipped with a summary line — not the
  Guard-3 "REQUIRED SECRET MISSING" comment + red run, which is the noise the
  flag exists to eliminate.
- **`sweep-deploy-channel` (new job):** `environment: deploy-channel`, the
  narrow loader step, `actions/checkout` (same `persist-credentials: false` +
  `fetch-depth: 0` shape as `sweep`), `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}`,
  and the ONLY-side flag. It runs a tracker iff its `secrets=` ⊆ the ONLY set
  ∩ the required marker ≠ ∅. It refuses `exit 0` when it ran zero trio probes
  while an open tracker declares one — the discriminating coverage assertion;
  a homeless trio tracker is a red, not silence. (`#10548` is the only open
  trio tracker today.)
- **Flag surface (decision point D-1):** the arc prescribes
  `FT_ONLY_SECRETS=<trio>` / `FT_EXCLUDE_SECRETS=<trio>`. Literal trio names in
  the `sweep` job env would keep the file `tier-a` (the job binds no
  environment). The assumed ruling: derive the trio name set inside
  `sweep-followthroughs.sh` from the trio-baseline `@stems` record
  (single-sourced, no new naming surface anywhere) so the workflow file stops
  naming the family and its rows are *deleted*; if the parent CTO ruling
  prefers literal names, `sweep-deploy-channel` carries `FT_ONLY_SECRETS`
  literally (its job binds `deploy-channel`, still `tier-b`-legal) and the
  exclusion side uses the set-difference semantic.
- Skip decisions print summary lines on BOTH sides, and the partition is
  exclusive: a tracker declaring a trio name is skipped by `sweep` and only
  runnable by `sweep-deploy-channel`; one declaring a non-trio-only set is
  skipped by `sweep-deploy-channel`. A tracker declared ⊄ ONLY with a trio
  member is skipped by both and reported by the coverage assertion.

### Script and doc de-shaping

Per-file disposition against the scanner's classes (`tests/scripts/
test-trio-baseline-census.sh`: `tier-a` = family name + a counted read shape;
`sink` = non-workflow naming without a read shape; rows delete when the file
stops naming the family):

- `apps/web-platform/scripts/github-app-key-status.sh`: the `${!v}` loop (:25)
  becomes three explicit `${VAR:?}` checks; the header recipe names the
  `soleur-deploy-channel`/`prd` Doppler source in prose (no `doppler run`/`get`
  command token) → rows `tier-a → sink`.
- `scripts/inngest-link-flip.sh`: the printed `doppler run -p soleur -c
  prd_terraform` recipe (:306) is reworded to name the store in prose →
  `tier-a → sink`.
- `scripts/cutover-inngest.sh`: reads `WEBHOOK_DEPLOY_SECRET` (canonical) as
  its signature-var name instead of `WEBHOOK_SECRET` — the `${!_sigvar}`
  indirection at :95 survives and must keep dereferencing the renamed var;
  its `doppler run -p soleur -c prd_terraform -- bash
  scripts/betterstack-query.sh` invocations (:173, :323) are non-trio reads
  that cannot de-shape → **decision point D-2**.
- `scripts/key-rotate.sh`: `doppler secrets get/--only-names` calls (:696,
  :700, :913 — the KK_CP compare machinery and the EGRESS_AUDIT_INGEST_TOKEN
  read) over non-trio creds, while naming the trio via `bc_curl`/`bc_hmac`
  name-args → **decision point D-2**.
- `scripts/check-deploy-script-parity.sh`: the BS arm's
  `doppler run -p soleur -c prd_terraform -- betterstack-query.sh` (:201) →
  **decision point D-2**.
- `scripts/ensure-doppler.sh`, `scripts/inngest-key-rotate.sh`: comment-only
  trio mentions (no baseline rows); recipe comments corrected to name
  `soleur-deploy-channel/prd` as the trio's home.
- `apps/web-platform/infra/infra-config-verify.sh`: `doppler secrets get
  APP_DOMAIN_BASE` (:48) → the committed `scripts/derive-app-domain-base.sh`
  derivation or an env read; the `${!_cred}` credential-shape check (:137) →
  explicit named checks; the `doppler run` recipe inside the ::error string
  (:497) → prose → target `sink`; any residual → D-2.
- `apps/web-platform/infra/scripts/verify-tunnel-ingress-origin.sh`:
  `doppler run`/`secrets get` reads of `WEB1_IP`, `CF_API_TOKEN`,
  `CF_ACCOUNT_ID`, `APP_DOMAIN_BASE` (:52-134) → env reads supplied by the
  calling job's loader (`apply-web-platform-infra.yml` binds a Tier-B env)
  where the privileged project carries them, else D-2.
- `apps/web-platform/infra/soleur-host-bootstrap.sh`: real host-side `doppler`
  machinery (SENTRY_DSN, soleur-github-app download, vector unit, BETTERSTACK
  token) coexists with `os.environ["WEBHOOK_DEPLOY_SECRET"]` (:176) →
  **decision point D-2**.
- `apps/web-platform/infra/cloud-init.yml`, `hooks.json.tmpl`,
  `variables.tf`, `server.tf`: `sink` already; verified unchanged
  (`var.webhook_deploy_secret` + the `hooks.json` render keep their existing
  shape — no Terraform edit in this PR).
- `.github/actions/dispatch-web-redeploy/track.sh`: `sink` already; no
  change.
- Skill docs (`plugins/soleur/skills/postmerge/SKILL.md`,
  `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`,
  `plugins/soleur/skills/qa/SKILL.md`,
  `plugins/soleur/skills/ship/SKILL.md`,
  `plugins/soleur/skills/plan/references/plan-sharp-edges.md`): every literal
  `doppler run|secrets get` recipe naming the trio from `prd_terraform` becomes
  prose naming `soleur-deploy-channel/prd` as the trio's home — `.md` lines
  are all code to the scanner, so the recipe must name the project, not the
  command → rows `tier-a → sink` or deleted.
- `knowledge-base/project/specs/archive/20261013-051752-feat-one-shot-8609-evict-runtime-app-key-prd/bootstrap.sh`:
  the standing operator recipe — its `prd_terraform` trio reads get the
  narrow-project spelling; its remaining `doppler run` arms (hetzner/sentry
  reads) keep it a D-2 candidate if trio names persist.

### Probe retirement

`#6178` is CLOSED — its probe retires rather than migrates: delete
`scripts/followthroughs/inngest-soak-6178.sh`,
`scripts/followthroughs/inngest-soak-6178.test.sh`,
`scripts/followthroughs/inngest-soak-6178.function-ids.txt`, and the
`run_suite "scripts/inngest-soak-6178"` line + comment block in
`scripts/test-all.sh` (:6548-6551). Deletion before close+14d (2026-11-21)
costs at most a daily `missing in repo HEAD` stderr line in the sweeper —
fail→`return 0`, no reopen, no comment (`sweep-followthroughs.sh`). The
#9071 retirement-census lesson applies: the function-ids pin file is deleted
WITH the probe, in the same diff, so no registry gate outlives it.
Post-edit citation sweep (deepen-plan §4.45 audit): two live citations
point at the deleted files — the `scheduled-followthrough-sweeper.yml:135`
comment (folded into the partition edit) and a precedent comment in
`.claude/hooks/grep-q-pipe-guard.test.sh:2215` — both are updated to name
the retirement instead of the path. ADR-096/ADR-100 and the archived
`feat-one-shot-6178-soak-followthrough` spec are point-in-time records and
stay untouched.

`scripts/followthroughs/sdk-bash-smoke-verdict-10548.sh` stays (#10548 OPEN);
its `sink` rows persist and it is served by `sweep-deploy-channel`.

### Pinned-shape test updates

Assertions pinned to the old `${{ secrets.<trio> }}` wiring move to the
loader-export / canonical-env shapes:
`apps/web-platform/infra/cutover-inngest-workflow.test.sh`,
`inngest-key-rotate-workflow.test.sh`, `inngest-link-flip-workflow.test.sh`,
`key-rotate-workflow.test.sh`, `cloud-init-web-zot-seed.test.sh`,
`infra-config-verify.test.sh`, `infra-config-repush-mutation.test.sh`,
`inngest-dedicated-host-classify.test.sh`,
`scripts/check-deploy-script-parity.test.sh`,
`tests/scripts/test-argv-bearer-sweep.sh`,
`tests/scripts/test-dispatch-web-redeploy.sh`,
`plugins/soleur/test/preflight-discoverability-test.test.ts`,
`scripts/followthroughs/sdk-bash-smoke-verdict-10548.test.sh`,
`scripts/followthroughs/web2-luks-live-6931.test.sh`, and any
`.github/actions/dispatch-web-redeploy` test fixture. Exempt-class files
(`.test.*`) holding counted shapes carry `tier-a` rows that delete once the
shapes leave; exempt files that only name the family produce no keys.

### Baseline end-state rule (adopted from the arc)

Each remaining `tier-a` row in `tests/scripts/trio-baseline.tsv` ends one of:
(a) deleted — the file stops naming the family (preferred: ambient loader env
means most workflow files need never name it); (b) forward-classed by the
scanner's own computation (`tier-a → tier-b` when a workflow's naming jobs all
bind a literal Tier-B env; `tier-a → sink` when a non-workflow loses its
counted read shape); (c) an `Allow:`/`Reclass:`/`Re-date:` line in ADR-241 with
a baseline/ADR-only diff where the ratchet requires it. Residual
`doppler`-over-non-trio-creds files that cannot stop naming the trio are the
named decision point D-2 — a narrowly-scoped scanner class refinement (suite
change recorded in the same ADR-241 amendment) or per-row `Reclass:` rulings;
not decided silently. Terminal assertion: zero `tier-a`, `FALLBACK:*`,
`ALIAS:*` rows; every `tier-b`/`sink` row scanner-agreed.

## Technical Considerations

### Attack Surface Enumeration (security change)

- Reach-without-naming stays closed by the owner-named tail (deletion of the
  Tier-A copies) + the main-only policy — the census names; it does not trace:
  `doppler run -c prd_terraform` injecting the whole project, `secrets:
  inherit`, `toJSON(secrets)`, computed `secrets[format(...)]`, and host-side
  readers of the rendered `hooks.json` remain documented blind spots.
- A job bound to `deploy-channel` runs branch YAML only from `main`; a fork/PR
  workflow naming the env is refused before secrets materialize. A
  `workflow_dispatch` of a migrated workflow on a non-main ref is now refused
  where today it would run — the intended trade (the ADR-241 D2
  `git_data_host_replace` precedent).
- `DOPPLER_TOKEN_DEPLOY_CHANNEL` reads only `soleur-deploy-channel/prd` (the
  trio and nothing else); a leaked token reads nothing else; the privileged
  token is never handed to these jobs.
- `bc_curl`/`bc_hmac_sha256_hex` keep credentials off argv (ADR-280); the
  migration must not introduce an argv or `toJSON(secrets)` path — asserted by
  the unchanged-green `test-argv-bearer-sweep.sh`.
- `${!var}` indirection over family names is itself a counted read shape —
  the `${!_v}` CF-pair trim loops in `web-platform-release.yml`,
  `deploy-inngest-image.yml`, `verify-peer-deploy` are de-shaped to explicit
  per-name expansions, not left as "only" indirections.
- Migrated jobs read the trio from job env exported by the loader — step
  bodies must read the canonical names (`WEBHOOK_DEPLOY_SECRET`,
  `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`); renamed binds
  (`WEBHOOK_SECRET`, `CF_ACCESS_ID`, `CF_ACCESS_SECRET`) are deleted, not
  re-pointed at `env.*` (which would keep naming the family).

## Downtime & Cutover

Adopted from the arc — expand-contract, not a hard cut:

- The trio exists in BOTH stores during the migration; `prd_terraform`/repo
  secrets stay live until the owner-named tail after green canaries. The
  `soleur-deploy-channel` copy is hash-equal — no window in which a correct
  caller fails because the value moved.
- Per-stage verification: the loader `source=tier_b_deploy_channel` line in
  the first `scheduled-inngest-health` run post-merge is the live proof; the
  census suites + the deletion postcondition close the loop.
- Rollback: a revert restores `secrets.*` binds against still-live Tier-A
  copies until the owner-named deletion — which is exactly why the deletion
  is gated on green canaries.
- Residual window: between this merge and the deletion the trio is
  double-homed (bounded by the same-day owner step).

## User-Brand Impact

- **If this lands broken, the user experiences:** deploys silently stop —
  `web-platform-release.yml`'s `deploy` job fails closed on an empty exported
  `WEBHOOK_DEPLOY_SECRET` (visible as a failed release run, or as a red
  `scheduled-inngest-health` probe if the probe job is mis-bound); no data is
  exposed by the fail-closed arm.
- **If this leaks, the user's data/workflow is exposed via:** a branch actor
  holding the trio signs `POST /hooks/infra-config` and replaces
  `ci-deploy.sh` on the deploy host — arbitrary code in the deploy path
  serving *every* tenant, plus reads of the host credential file.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the worst case is a cross-tenant
  supply-chain incident (poisoned deploy artifact on the shared host), not a
  single user's data — CPO sign-off carried per the arc's ruling; headless-run
  persistence is in `decision-challenges.md`.

## Observability

```yaml
liveness_signal:
  what: "The migrated workflows' own run results — loader source=tier_b_deploy_channel line in each job log plus the existing per-workflow success/failure signal (deploy-status heartbeat, inngest-health probe verdict)"
  cadence: per-run (release/cutover/link-flip/key-rotate on dispatch; inngest-health every 15 min; sweeper daily)
  alert_target: "Actions run failures (existing); scheduled-inngest-health already pages on probe red"
  configured_in: ".github/workflows/scheduled-inngest-health.yml; .github/actions/infra-credentials/action.yml (source output)"
error_reporting:
  destination: "job log + step summary — the loader prints verdict=no_credential_source with the named cause; consumer steps fail closed on ${VAR:?} with the loader-source hint"
  fail_loud: "::error title=infra-privileged::verdict=no_credential_source … or the consumer's named-missing-variable abort"
failure_modes:
  - mode: "deploy-channel environment secret absent or emptied"
    detection: "narrow loader fails closed before any credential use; every bound job red at the load step, never mid-deploy"
    alert_route: "Actions run failure; scheduled probe red"
  - mode: "a workflow job binds deploy-channel but the live env lost its main-only policy"
    detection: "census .tf-policy parse row + the live protection_rules read-back"
    alert_route: "PR-time census RED"
  - mode: "an open followthrough tracker declares a trio secret but no job serves it"
    detection: "sweep-deploy-channel coverage assertion refuses exit 0 on zero trio probes"
    alert_route: "daily sweep run failure"
logs:
  where: "GitHub Actions job logs (source= line; sweep summary lines); no host logs"
  retention: "GitHub Actions log retention (90d)"
discoverability_test:
  command: git grep -l 'environment: deploy-channel' .github/workflows/web-platform-release.yml
  expected_output: .github/workflows/web-platform-release.yml
```

## Encryption Posture

No new persistent store and no new cross-component connection — PR-A declared
the carrier's posture (`doppler_project.deploy_channel`,
`github_repository_environment.deploy_channel` + the runner→Doppler TLS read);
this PR changes which jobs ride the existing edge, not the edge. Declared here
for the gate record:

```yaml
at_rest:
  - store: "doppler_project.deploy_channel (soleur-deploy-channel/prd — the trio)"
    mechanism: "provider-managed:Doppler workspace encryption-at-rest"
    evidence: "ADR-241 D3/D11 carrier precedent; values never enter tfstate — the .tf declares containers only"
    defends_against: "a Terraform-state reader recovering the trio; a prd_terraform branch-config read reaching it"
    does_not_defend: "a holder of DOPPLER_TOKEN_DEPLOY_CHANNEL or DOPPLER_TOKEN_TF; a Doppler-side breach"
    disclosed_as: not-publicly-claimed
    live_verification: "available — post-seed doppler secrets listing"
  - store: "github_repository_environment.deploy_channel secret DOPPLER_TOKEN_DEPLOY_CHANNEL"
    mechanism: "provider-managed:GitHub Actions encrypted secrets (libsodium sealed box, environment-scoped)"
    evidence: "GitHub environment secrets are write-only-encrypted after set; reachable only by jobs that pass the deployment branch policy"
    defends_against: "any workflow on a non-main ref resolving the token"
    does_not_defend: "an admin rewriting the branch policy (the ADR-241 D10 R1 nominal-boundary residual)"
    disclosed_as: not-publicly-claimed
    live_verification: "available — protection_rules read-back (done 2026-11-20)"
in_transit:
  - connection: "GitHub runner -> Doppler API (loader narrow mode, doppler secrets download)"
    enforced_at: ".github/actions/infra-credentials/action.yml — pinned CLI 3.75.3 + sha256"
    tls: "HTTPS/TLS 1.2+ (Doppler API)"
    cert_verification: on
    does_not_defend: "a compromised runner env post-export (values are job-env thereafter, never argv)"
    disclosed_as: not-publicly-claimed
```

## Task Design

```yaml
tasks:
  - task: "sweep-deploy-channel (new job on scheduled-followthrough-sweeper.yml)"
    trigger: "existing daily schedule of scheduled-followthrough-sweeper.yml (no new schedule)"
    services: "reads open follow-through trackers via gh api (GH_TOKEN); reads the trio from soleur-deploy-channel/prd via the narrow loader; writes issue comments on served trackers"
    next: "nothing — serves the same comment/close lifecycle the Tier-A sweep arm performs"
    human_reentry: "workflow_dispatch of scheduled-followthrough-sweeper.yml; FT_* flags are env constants a dispatch can override; stopping = disabling the job"
    dedupe: "partition is exclusive: a tracker declaring a trio name is skipped by the Tier-A sweep and only runnable by this job (ONLY set + required marker), so the same tracker is never swept twice in one cycle"
    source_dedupe: "not a ticket source — the follow-through labels on issues are created by humans/other tooling; the sweeper's existing directive parse decides what runs"
```

## Architecture Decision (ADR/C4)

- **ADR-241 amendment (deliverable):** a dated D1 census-amendment entry in
  `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`
  recording: the narrow carrier adopted under the D11 precedent (PR-A merged);
  consumers migrated and baseline end-state reached; Tier-A copies
  owner-deleted with the postcondition recorded (the tail's report slot);
  rotation machinery and the stale-state reconciliation remain
  operator-reserved; D1 keeps `adopting` (G1 closes with the issue after the
  rotation tail); plus any `Allow:`/`Reclass:`/`Re-date:` lines the baseline
  diff itself requires, and the scanner class refinement if D-2 rules for it.
- **C4:** `knowledge-base/engineering/architecture/diagrams/model.c4` — the
  PR-A carrier edge (:820-827) carries a `STATUS (Phase 1)` clause saying no
  consumer references `DOPPLER_TOKEN_DEPLOY_CHANNEL` yet; this PR rewrites
  that clause to the live state (consumers migrated; the tail pending), adds
  `deploy-channel` to the Tier-B edge's environment enumeration (:819), and
  refreshes the loader-consumer list (`inngest-key-rotate`'s "redeploy job
  holds the deploy webhook credentials only" and the `key-rotate` parallel
  need the narrow-source wording). `views.c4`/`spec.c4` were read: `github`
  and `doppler` are included in the context and containers views, so the edge
  renders — no include change; no new element (the edge description carries
  the fact).

## Guard Contract

### Guard 1 — trio boundary census rows (`test-infra-privileged-tier-census.sh`)

**Property.** No workflow job names the trio family (`secrets.<trio>`, a
`doppler` read of a trio name, or a workflow-level `env:`/`secrets:` bind)
unless the job declares a literal Tier-B environment, and the trio names in
`TIER_B_NAMES` make the existing no-non-loader-read rows apply to them.

**Assembly.** The `git ls-files` workflow population (the parse the census
already runs), `ENV_SECRETS`/`TIER_B_NAMES`/`TIER_B_ENVIRONMENTS` constants,
the `.tf` policy parse proving `deploy-channel` is main-only, the loader's
`doppler-project` allowlist.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | A fixture workflow binding `env: {WEBHOOK_DEPLOY_SECRET: ${{ secrets.WEBHOOK_DEPLOY_SECRET }}` in a job with no `environment:` | RED — named row |
| 2 | `deploy-channel` removed from the env policy parse set while `TIER_B_ENVIRONMENTS` still names it | RED — the census proves the env from the `.tf`, not from its own list |
| 3 | A second job in the fixture binds the trio with `environment: deploy-channel` while a first binds it bare | RED — the guard must not stop at the compliant member |
| 4 | A fixture job binding `secrets.CF_ACCESS_CLIENT_ID` under `environment: some-unlisted-env` | RED — every trio name, not just the HMAC key, trips the row |

### Guard 2 — sweeper partition (`sweep-followthroughs.sh` + sweeper tests)

**Property.** A followthrough tracker declaring a trio name runs in exactly
one sweep job — the Tier-B one — and a tracker that fits neither partition
surfaces red rather than silently lapsing.

**Assembly.** The `FT_*` partition-flag parse, the `secrets=` directive match,
the zero-trio-probes coverage assertion, both job env blocks.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | fixture tracker declaring `secrets=WEBHOOK_DEPLOY_SECRET` while the Tier-B job env is absent | RED — coverage assertion, not Guard-3 comment noise |
| 2 | the Tier-A arm's exclusion emptied while a trio tracker is open | RED — partition overlap is refused/detected |
| 3 | a tracker declaring `secrets=WEBHOOK_DEPLOY_SECRET,SOME_OTHER` (declared ⊄ ONLY) | RED — skipped by both arms and reported by the coverage assertion |
| 4 | the coverage assertion removed and the Tier-B job run with no open trio tracker | RED — the harness itself must fail on a vacuous-green arm |

### Guard 3 — baseline terminal state (`trio-baseline.tsv` + its census suite)

**Property.** Every surviving row's class equals the scanner's own
computation, zero `tier-a`/`FALLBACK:*`/`ALIAS:*` rows remain, and a diff that
adds a family-naming key without a spent `@allow` is refused.

**Assembly.** `tests/scripts/test-trio-baseline-census.sh`, the `.tsv` records
(`@stems`, `@exempt`, `@binary`, `@kbcode`, `@allow`), the merge-base row
diff, the class-forward-only ratchet.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | a fixture diff re-adding `secrets.WEBHOOK_DEPLOY_SECRET` to a migrated workflow without an `@allow` | RED — new-key refusal |
| 2 | a fixture baseline row reclassed `tier-b → tier-a` | RED — no backward lane exists |
| 3 | a fixture diff deleting a row while a same-diff added file re-names the family with a read shape | RED — resurrection without a spent allow |
| 4 | the scanner's emit run against a baseline missing a live key | RED — the baseline must agree with computed keys, not merely parse |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Move WEBHOOK_DEPLOY_SECRET, CF_ACCESS_CLIENT_ID and CF_ACCESS_CLIENT_SECRET out of every branch-nameable location, both the Doppler soleur/prd_terraform copies and the GitHub Actions secret copies, into main-only environment secrets or Tier B (soleur-infra-privileged). Then rotate all three." | workflow consumer table + sweeper partition (move); rotation is operator-reserved — descoped by the arc plan's exclusion | mapped (move) / excluded (rotate, per ask 7 below) |
| 2 | "Consumers to migrate. These are the known set; re-derive it with git grep before starting" | consumer table re-derived 2026-11-20 (adds inngest-link-flip/key-rotate/inngest-key-rotate; drops git-data-cutover/apply-web-platform-infra/7220/5875 which no longer name the trio) | mapped |
| 3 | "Terraform: var.webhook_deploy_secret and the hooks.json render" | verified `sink`, no change needed — already Tier-B-fed since PR-2 | mapped — no-op |
| 4 | "Verify this with a census row in tests/scripts/test-infra-privileged-tier-census.sh" | Guard 1 rows + `TIER_B_NAMES`/`ENV_SECRETS`/`TIER_B_ENVIRONMENTS` constants | mapped |
| 5 | "ADR-241 gets a D1 census amendment recording the move" | ADR-241 dated amendment entry + C4 edge updates | mapped |
| 6 | "All three are rotated. The old values are rejected" | — | descoped — justification: operator-reserved per the arc plan's explicit exclusion (rotation machinery + execution); the D1 amendment records the hold |
| 7 | "cloudflare_zero_trust_access_service_token.deploy is stale in Terraform state … Reconcile that state before rotating" | — | descoped — justification: operator-reserved (#7103 B5), unchanged `removed{destroy=false}` block |
| 8 | "Implement the #9294 PR-B consumer migration on branch feat-one-shot-9294-deploy-trio-prb" [prompt] | this plan, all items | mapped |
| 9 | "sweeper partition, probe retirements, script/doc de-shaping, trio->TIER_B_NAMES + boundary census rows so every remaining tier-a row … ends deleted/forward-classed/Allow-lined, and the ADR-241 D1 census amendment" [prompt] | sweeper partition + probe retirement + de-shape list + census constants + baseline end state + ADR-241 amendment | mapped |
| 10 | NON-GOALS: "touching the carrier .tf or loader arm … deleting old copies … rotating the trio … stale-state reconciliation" [prompt] | exclusion list in Proposed Solution; no item | mapped — excluded by design |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| workflow `environment: deploy-channel` + narrow loader binds | "into main-only environment secrets or Tier B (soleur-infra-privileged)" + "migrate every consumer … re-derive the set with git grep first" | asked |
| sweeper partition + `sweep-deploy-channel` job | "sweeper partition" [prompt] | asked |
| probe retirement (`inngest-soak-6178.sh` et al.) | "probe retirements" [prompt] | asked |
| script/doc de-shapes | "script/doc de-shaping" [prompt] | asked |
| `TIER_B_NAMES` += trio + boundary census rows | "trio->TIER_B_NAMES + boundary census rows" [prompt] + "Verify this with a census row" [issue] | asked |
| baseline end-state dispositions | "every remaining tier-a row … ends deleted/forward-classed/Allow-lined" [prompt] | asked |
| ADR-241 D1 amendment + C4 edge update | "the ADR-241 D1 census amendment" [prompt]; C4 — inferred — justification: the `github -> doppler` edges enumerate envs and loader consumers exhaustively and would lie otherwise | asked / inferred |
| decision-challenge rows D-1/D-2 | "record pending - assumed: <default> as the Ruling of a technical row and flag it for the parent's CTO spawn" [prompt] | asked |
| `${!_v}` indirection de-shapes in workflow run bodies | — | inferred — justification: `${!var}` over a family name is itself a counted read shape; leaving it keeps the row `tier-a` (the scanner's `indirect` rule) |

### Split Assessment

- Subsystems touched: 6 — `.github`, `apps`, `scripts`, `tests`, `knowledge-base`, `plugins`
- Planned files: ~40 | Estimated changed lines: ~900–1400
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — declined: the arc plan already cut the seam at the merge-ordering requirement (PR-A carrier → owner seed → PR-B consumers); a further intra-PR-B split (workflows / scripts+docs / baseline+ADR) would leave interim states that still satisfy the ratchet but each PR would re-run the same baseline suites for less assurance than the single-diff end-state proof. Single PR, phased internally.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. The
plan's file lists contain no UI-surface paths, so the mechanical Product
override does not fire; Product/UX Gate tier: NONE. Legal/GDPR gate skipped:
no schema/migration/auth/API/.sql surface, and none of the four expanded
triggers (LLM processing of operator data, single-user threshold, cron reading
learnings/specs, new distribution surface) fire — the sweeper job shape
predates this change and reads issue bodies only. IaC routing gate skipped:
no new infrastructure — the carrier `.tf` is merged (PR-A) and explicitly out
of scope; the plan prescribes no operator-provisioning step (the owner-named
tail is recorded as an exclusion, not an implementation phase).

## User-visible / Open Code-Review Overlap

None — 96 open `code-review` issues checked against every planned file path;
no body matches.

## Acceptance Criteria

1. Zero `${{ secrets.WEBHOOK_DEPLOY_SECRET }}` / `CF_ACCESS_CLIENT_ID` /
   `CF_ACCESS_CLIENT_SECRET` references remain in `.github/workflows/`; every
   job whose file still names the trio declares a literal Tier-B environment
   (in the `TIER_B_ENVIRONMENTS` set).
2. Every migrated job loads the trio through
   `doppler-project: soleur-deploy-channel` +
   `doppler-token-deploy-channel: ${{ secrets.DOPPLER_TOKEN_DEPLOY_CHANNEL }}`;
   `cutover-inngest.yml`'s environment expression resolves a Tier-B member on
   every arm (`inngest-cutover` for gated ops, `deploy-channel` otherwise),
   and its `op == 'backup'` privileged-loader step is unchanged.
3. `tests/scripts/trio-baseline.tsv` carries zero `tier-a`, `FALLBACK:*` and
   `ALIAS:*` rows; every surviving row is scanner-agreed `tier-b`/`sink`;
   `bash tests/scripts/test-trio-baseline-census.sh` and
   `bash tests/scripts/test-infra-privileged-tier-census.sh` are green,
   mutation fixtures included.
4. `WEBHOOK_DEPLOY_SECRET`, `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`
   are in `TIER_B_NAMES`; the boundary census proves no job names the trio
   outside a literal Tier-B environment — each new row with a mutation
   fixture driven RED.
5. The sweeper partition: `sweep` never touches a trio tracker;
   `sweep-deploy-channel` serves every open trio tracker and refuses green on
   a homeless one; skip decisions print summary lines on both sides.
6. `scripts/followthroughs/inngest-soak-6178.sh`, its test, its
   `function-ids.txt`, and its `test-all.sh` suite line are deleted;
   `sdk-bash-smoke-verdict-10548.sh` is untouched and served by the new job.
7. ADR-241 carries the dated D1 census-amendment entry (including any
   `Allow:`/`Reclass:`/`Re-date:` lines the baseline diff requires and the
   scanner refinement if D-2 rules for it); `model.c4`'s deploy-channel edge
   `STATUS` clause and the Tier-B edge's environment enumeration name the
   migrated state.
8. `bash tests/scripts/test-argv-bearer-sweep.sh` is unchanged-green — no
   argv credential path introduced.
9. Excluded and confirmed untouched:
   `apps/web-platform/infra/deploy-channel-environment.tf`, the loader arm in
   `.github/actions/infra-credentials/action.yml`, rotation machinery
   (`or`/`_NEXT` renders, `WEBHOOK_DEPLOY_SECRET_NEXT`), the
   `cloudflare_zero_trust_access_service_token.deploy` `removed` block, any
   credential rotation, and the `prd_terraform`/repo-secret copies (the
   owner-named tail).

## Test Scenarios

Mutation-driven (each maps to a Guard matrix row):

- census fixture: bare `secrets.<trio>` bind in a no-env job → RED (unit)
- census fixture: trio bind in a job binding a non-Tier-B env → RED (unit)
- census fixture: `doppler secrets get WEBHOOK_DEPLOY_SECRET -c prd_terraform`
  outside the loader → RED via the `TIER_B_NAMES` no-non-loader-read row (unit)
- sweeper: trio tracker + absent Tier-B env → coverage RED; partition overlap
  → RED; declared-superset tracker → skipped-by-both reported (unit)
- ratchet: baseline diff adding an un-`@allow`ed tier-a row → RED; row
  deletions tracked; class moves forward-only (unit)
- positive control: full migration tree green on both suites and
  `bash tests/scripts/test-argv-bearer-sweep.sh` unchanged-green (no argv
  path introduced) (integration)

## Dependencies & Risks

- The `deploy-channel` env exists live with its main-only policy (verified
  2026-11-20); a regression there is caught by the census `.tf`-policy parse
  row and the live read-back.
- Between merge and the owner-named tail the trio is double-homed — hash-equal,
  no rotation race; the window is bounded by the same-day deletion step.
- `scheduled-inngest-health` (15-min cadence) and the daily sweeper are the
  only unattended consumers that would page on an empty carrier — the seed
  is already verified, so the window is merge-time only.
- D-2 files (residual `doppler` over non-trio creds + unavoidable trio
  naming) need the recorded ruling; a scanner class-rule refinement changes
  a guard suite and lands only with the ADR-241 amendment recording it.
- A mid-migration revert restores `secrets.*` binds against still-live
  Tier-A copies — the expansion ordering is the rollback path.
- `cutover-inngest.yml`'s `environment:` expression arms must all be members
  of `TIER_B_ENVIRONMENTS` — the sibling census parses expression arms;
  `deploy-channel` is already a member (PR-A).
- The deleted probe's `function-ids.txt` must go in the same diff (the #9071
  pinned-id lesson); a leftover pin would red the registry gate forever.

## Research Insights

Reviewed-Coverage: sequential-fallback — no subagent spawn mechanism on this
tool surface; all research, gate checks, and review lenses ran inline in one
context. No independent review is claimed.

**Premise Validation (2026-11-20):** #9294 OPEN (verified); PR #12810
MERGED at squash `9cfcc7f47` (verified via `gh pr view`); the arc plan file
exists at the cited archive path; `apps/web-platform/infra/
deploy-channel-environment.tf` and the narrow loader arm
(`doppler-project=soleur-deploy-channel`, `source=tier_b_deploy_channel`)
exist on this branch's base; live read-back confirms `deploy-channel`'s
single `main` branch policy and `DOPPLER_TOKEN_DEPLOY_CHANNEL` on both
environments. Collision precheck: PR #13006 is THIS branch's own WIP draft;
two `test-all.sh` processes run in the sibling worktree
`feat-one-shot-12931-cf-account-migration` (a different feature — reported,
not a duplicate of this work). Stale premises in the issue body:
`git-data-cutover.yml`, `apply-web-platform-infra.yml`,
`infra-config-*-7220`, `canary-promotion-5875.sh` no longer name the trio.

**Property List (mechanism-minimality gate):**

- P1 — no job names the trio outside a literal Tier-B environment
- P2 — migrated jobs source the trio from `soleur-deploy-channel/prd` via the
  narrow loader arm (PR-A machinery, not re-derived)
- P3 — no open trio-declaring followthrough tracker is homeless or doubly
  served
- P4 — `trio-baseline.tsv` reaches zero `tier-a`/`FALLBACK:`/`ALIAS:` rows
- P5 — the move is recorded (ADR-241 D1 amendment + C4 edge truth)
- P6 — no credential reaches an argument list (ADR-280 invariant preserved)
- P7 — an absent carrier fails closed before any credential use (loader's
  existing `no_credential_source` verdict; no new machinery)

**Cut List:** no mechanism this plan proposes is un-covered by machinery on
`origin/main` — the loader arm, census suites, baseline ratchet and sweeper
already exist; PR-B adds consumers, partition flags, and constants, not new
infrastructure. Nothing was cut.

**Findings that shape the plan:**

- The scanner's `tier-b` requires NO read shape AND every naming job on a
  literal Tier-B env; `env_literal` never accepts an expression, and
  `gen_read` is file-level (ANY `doppler` command in a family-naming file
  counts). Consequences: (a) `cutover-inngest.yml` must stop naming the trio
  entirely (its `environment:` is an expression — rows delete, not reclass);
  (b) `${!_v}` indirections over family names are counted shapes and must be
  de-shaped; (c) files retaining `doppler` commands over non-trio creds while
  naming the trio are the D-2 residual.
- Consumer scripts already read canonical env names via `bc_curl`/`bc_hmac`
  name-args — the workflow-side migration is binds-removal + env + loader;
  `scripts/cutover-inngest.sh` is the one script whose signature-var name is
  `WEBHOOK_SECRET` (renamed) and becomes `WEBHOOK_DEPLOY_SECRET`.
- `#6178` CLOSED → probe retirement in this slice; `#10548` OPEN and the only
  open trio tracker → the new job's coverage assertion has exactly one member
  to serve.
- `scripts/derive-app-domain-base.sh` is the committed derivation that
  replaces `doppler secrets get APP_DOMAIN_BASE` reads.
- `sweep-followthroughs.sh`'s Guard 3 (the required-secret-missing
  comment-plus-red-run) is the noise source the partition flag suppresses;
  `valid_secret_name` and `fwd_names` are the forwarding chokepoint the
  partition mounts on.
- External (deepen-plan §4 research): GitHub's own docs confirm an
  environment referenced by a job before it exists is auto-created with **no
  protection rules or secrets** — "anyone with permission to edit workflows
  or create deployments can create environments"; branch policies are checked
  at job start and refuse non-matching `GITHUB_REF`s before secrets
  materialize (`docs.github.com` Deployments-and-environments + REST
  environments reference, verified 2026-11-20). This is why the carrier must
  pre-date consumers — satisfied: PR-A merged and the env policy read-back
  verified live.
- Relevant learnings:
  `2026-09-27-a-retirement-census-by-name-missed-the-consumer-that-pinned-the-id.md`
  (function-ids pin deletes with the probe);
  `2026-09-11-a-filer-with-no-honest-exit-takes-the-free-one-at-any-price.md`
  (derive populations from the enforcing mechanism's call sites — the
  consumer set is re-derived by grep, not the issue's list);
  `2026-03-21-github-actions-heredoc-yaml-and-credential-masking.md`;
  `2026-10-02-early-exit-pipe-consumers-sigpipe-under-pipefail.md` (strict-mode
  edits to `sweep-followthroughs.sh`);
  `2026-05-15-token-namespace-divergence-across-secret-stores.md` (tiering by
  measured access, not names).

## References & Research

- Issue #9294 (OPEN), epic #10390; blocks #8609 (ADR-241 D10 G1).
- Arc plan:
  `knowledge-base/project/plans/archive/20261117-181828-2026-11-16-9294-deploy-channel-creds-tier-move.md`
- PR-A: #12810 (squash `9cfcc7f47`) —
  `apps/web-platform/infra/deploy-channel-environment.tf`,
  `.github/actions/infra-credentials/action.yml` (narrow arm),
  `tests/scripts/test-infra-privileged-tier-census.sh` (constants + guards)
- Scanner: `tests/scripts/test-trio-baseline-census.sh` +
  `tests/scripts/trio-baseline.tsv` (ratchet rules in its header)
- Sweeper: `scripts/sweep-followthroughs.sh` (`valid_secret_name`,
  `fwd_names`, Guard 3) + `.github/workflows/scheduled-followthrough-sweeper.yml`
- ADR-241:
  `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`
  (D1 blockquote :100, amendment log tail)
- C4: `knowledge-base/engineering/architecture/diagrams/model.c4` (:819 Tier-B
  edge, :820-827 deploy-channel edge), `views.c4`, `spec.c4`
- Transport invariant: `scripts/lib/bearer-curl.sh` (ADR-280)
- Non-goals: rotation machinery, `cloudflare_zero_trust_access_service_token.deploy`
  stale-state reconciliation (#7103 B5), carrier `.tf`, loader arm, Tier-A
  copy deletion (owner-named tail)

## Files to Create

- (none — `sweep-deploy-channel` is a job in an existing workflow)

## Files to Edit

- `.github/workflows/web-platform-release.yml`,
  `.github/workflows/canary-status.yml`,
  `.github/workflows/cutover-inngest.yml`,
  `.github/workflows/deploy-inngest-image.yml`,
  `.github/workflows/inngest-key-rotate.yml`,
  `.github/workflows/inngest-link-flip.yml`,
  `.github/workflows/key-rotate.yml`,
  `.github/workflows/restart-inngest-server.yml`,
  `.github/workflows/scheduled-inngest-health.yml`,
  `.github/workflows/scheduled-followthrough-sweeper.yml`,
  `.github/workflows/apply-deploy-pipeline-fix.yml` (D-2 disposition only)
- `scripts/sweep-followthroughs.sh`, `scripts/key-rotate.sh`,
  `scripts/inngest-link-flip.sh`, `scripts/cutover-inngest.sh`,
  `scripts/inngest-key-rotate.sh`, `scripts/check-deploy-script-parity.sh`,
  `scripts/ensure-doppler.sh`, `scripts/test-all.sh`,
  `.claude/hooks/grep-q-pipe-guard.test.sh` (stale precedent comment at
  :2215 — names the deleted soak-probe test file)
- `apps/web-platform/scripts/github-app-key-status.sh`
- `apps/web-platform/infra/infra-config-verify.sh`,
  `apps/web-platform/infra/scripts/verify-tunnel-ingress-origin.sh`,
  `apps/web-platform/infra/soleur-host-bootstrap.sh`
- `tests/scripts/test-infra-privileged-tier-census.sh`,
  `tests/scripts/test-trio-baseline-census.sh`,
  `tests/scripts/trio-baseline.tsv`,
  `tests/scripts/test-argv-bearer-sweep.sh`,
  `tests/scripts/test-dispatch-web-redeploy.sh`
- `apps/web-platform/infra/cutover-inngest-workflow.test.sh`,
  `inngest-key-rotate-workflow.test.sh`,
  `inngest-link-flip-workflow.test.sh`, `key-rotate-workflow.test.sh`,
  `cloud-init-web-zot-seed.test.sh`, `infra-config-verify.test.sh`,
  `infra-config-repush-mutation.test.sh`,
  `inngest-dedicated-host-classify.test.sh` (same directory)
- `scripts/check-deploy-script-parity.test.sh`,
  `scripts/followthroughs/sdk-bash-smoke-verdict-10548.test.sh`,
  `scripts/followthroughs/web2-luks-live-6931.test.sh`
- `plugins/soleur/test/preflight-discoverability-test.test.ts`
- `plugins/soleur/skills/postmerge/SKILL.md`,
  `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`,
  `plugins/soleur/skills/qa/SKILL.md`,
  `plugins/soleur/skills/ship/SKILL.md`,
  `plugins/soleur/skills/plan/references/plan-sharp-edges.md`
- `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`,
  `knowledge-base/engineering/architecture/diagrams/model.c4`,
  `knowledge-base/project/specs/archive/20261013-051752-feat-one-shot-8609-evict-runtime-app-key-prd/bootstrap.sh`

## Files to Delete

- `scripts/followthroughs/inngest-soak-6178.sh`,
  `scripts/followthroughs/inngest-soak-6178.test.sh`,
  `scripts/followthroughs/inngest-soak-6178.function-ids.txt`
