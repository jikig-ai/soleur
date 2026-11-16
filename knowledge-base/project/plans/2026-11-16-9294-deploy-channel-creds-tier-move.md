---
title: "Move the deploy-channel trio (WEBHOOK_DEPLOY_SECRET + CF Access pair) out of every branch-nameable location"
date: 2026-11-16
slug: 9294-deploy-channel-creds-tier-move
branch: feat-one-shot-9294-deploy-creds-tier-move
issue: "#9294"
closes: null
type: refactor
priority: P1
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: true
---

## Overview

Issue #9294 is G1 of the ADR-241 D10 residual that gates #8609: any workflow on
any branch of this public repository can reach the deploy HMAC
(`WEBHOOK_DEPLOY_SECRET`) and the Cloudflare Access service pair
(`CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`). Together the three
authenticate `/hooks/infra-config` on web-1 — a path that can replace
`ci-deploy.sh` and read the host credential file — plus `/hooks/deploy-status`.
The G1 partials already merged: PR-0 (#10376) landed the trio-baseline census
and the expiring tier-a ratchet; PR-1a (#10458) fixed the `fan_out` first-secret
rule; PR-2 (#10928) moved the Terraform-fed consumers onto the Tier-B loader and
forgot the deploy Access token from state; rotation PR-A/B (#12330, #12445)
admitted the new Access token id `d9204def-…` and dropped the old id, so the
provider-side Access-token rotation is already complete. What remains, and what
this slice ships: the trio still sits in Doppler `soleur/prd_terraform` and as
repo-level GitHub Actions secrets, and the non-Terraform consumers — workflows,
scripts, skill docs — still name it via `${{ secrets.* }}`. This plan builds the
narrow Tier-B carrier the CTO ruling specified (a `soleur-deploy-channel`
Doppler project, a main-only `deploy-channel` GitHub environment, and a narrow
mode on the infra-credentials loader), migrates every remaining consumer, lands
the boundary census rows in `test-infra-privileged-tier-census.sh`, ratchets the
trio baseline to its terminal state, amends ADR-241 D1, and updates the C4
`github -> doppler` edge. The credential rotation tail and the stale
`cloudflare_zero_trust_access_service_token.deploy` state reconciliation are
operator-reserved and excluded.

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

## Problem Statement / Motivation

Acceptance criterion 1 of #9294: "Neither the Doppler copies nor the
GitHub-secret copies of the three credentials can be named by a workflow that
has not passed a main-only environment." Today eleven workflows bind the trio
directly from `secrets.*` — a reach any branch workflow can exercise because a
repo secret's only policy is "a job asked". The narrow carrier exists because of
the ruling recorded in the G1 plan and the issue's epic context: the Tier-B
loader exports the whole selected Doppler project into every job bound to a
Tier-B environment, so binding the unattended release/inngest/followthrough jobs
to `infra-privileged` would hand them `HCLOUD_TOKEN` read/write to deliver a
deploy-trigger credential. The non-Terraform consumers therefore read a *narrow*
Tier-B project holding only the trio — the exact `soleur-infra-app` precedent of
ADR-241 D11 (`infra-app-project.tf`, Census Guard 7).

## Proposed Solution

### The carrier (PR-A)

1. `apps/web-platform/infra/deploy-channel-environment.tf` — new file, mirroring
   `infra-privileged-environment.tf` + `infra-app-project.tf`:
   - `doppler_project.deploy_channel` (`name = "soleur-deploy-channel"`,
     `prevent_destroy`, <=255-char description for
     `scripts/lint-doppler-description-length.py`). No `doppler_secret`,
     `doppler_service_token` or `data "doppler_secret(s)"` — this root's state is
     Tier-A readable (the file's own header must carry the D11 "no secret, no
     token, no data source" warning).
   - `doppler_environment.deploy_channel_prd` (`slug = "prd"`) — a TF-created
     project is born bare; the environment creates the `prd` root config the
     read token is scoped to.
   - `github_repository_environment.deploy_channel` with
     `deployment_branch_policy { protected_branches = false;
     custom_branch_policies = true }` — NO `reviewers` block (unattended jobs
     must auto-approve; the boundary is the branch policy, not a human click).
   - `github_repository_environment_deployment_policy.deploy_channel_main`
     (`branch_pattern = "main"`). Both halves are load-bearing: omitting the
     block leaves any branch able to deploy; omitting the policy resource
     leaves an empty named list that admits no branch.
   - Every resource must be added to the `-target=` allow-list of
     `apply-web-platform-infra.yml` (a bare `*.tf` is pruned and never applies).
2. `.github/actions/infra-credentials/action.yml` — narrow mode:
   - new input `doppler-project`, default `soleur-infra-privileged`, allowlist
     `{soleur-infra-privileged, soleur-deploy-channel}`, fail closed on any
     other value;
   - new input `doppler-token-deploy-channel`; when `doppler-project` selects
     the narrow project, an empty token fails closed
     (`verdict=no_credential_source`-style, naming the cause);
   - narrow mode runs a whole-project `doppler secrets download
     -p soleur-deploy-channel -c prd` and exports every key (plain names +
     `TF_VAR_` spellings), skipping the legacy arm, the App-runtime opt-in
     handling, and the state-bucket aliasing. It must **name no trio stem
     literally** — the whole-project download keeps `action.yml` outside the
     trio-baseline name family so no `tier-a` composite-action row is created.
   - `outputs.source` gains a distinct narrow marker (e.g. `tier_b_deploy_channel`)
     so post-run verification can tell which arm served the job.
3. `tests/scripts/test-infra-privileged-tier-census.sh` (PR-A portion):
   - `TIER_B_ENVIRONMENTS` += `deploy-channel` (the census derives the env set
     from the `.tf` policy — the new file must declare it parseably);
   - `ENV_SECRETS` += `DOPPLER_TOKEN_DEPLOY_CHANNEL`;
   - Guard 7 (no secret/token/data-source on narrow projects) must cover
     `soleur-deploy-channel` — extend its assembly if it enumerates projects;
   - new Guard rows for the loader narrow mode (allowlist enforced, empty-token
     refusal, narrow mode never reads `prd_terraform`) with mutation fixtures.
4. Operator-named seed steps (post-merge, recorded in the PR body — NOT
   implemented by the agent; these are production mutations gated on the
   owner's per-command go): verify the live env's `protection_rules` shows the
   main-only policy (an unseeded auto-created env has NO policy — the exact
   hazard `infra-privileged-environment.tf` documents); copy the trio
   hash-equal from `soleur-infra-privileged/prd` into
   `soleur-deploy-channel/prd`; mint a read service token on
   `soleur-deploy-channel/prd`; `gh secret set DOPPLER_TOKEN_DEPLOY_CHANNEL`
   `--env deploy-channel` and `--env inngest-cutover` (gated cutover ops keep
   their reviewer-gated environment). Mirror the D11 operator-run staged
   bootstrap script precedent; if a sibling script exists for `soleur-infra-app`
   it is the shape to copy.

### The consumer migration (PR-B)

Every job that names the trio binds a literal Tier-B environment and reads the
trio from the loader's exported env — never from `secrets.*` of the trio. The
workflow file itself should stop naming the family wherever possible (the
loader exports ambient env; steps call scripts that read env internally), which
is what lets the file's baseline rows be *deleted* rather than reclassed.

| Workflow | Job(s) | Environment binding |
|---|---|---|
| web-platform-release.yml | `deploy`, `verify-peer-deploy` | `deploy-channel` + narrow loader |
| canary-status.yml | canary job | `deploy-channel` + narrow loader |
| cutover-inngest.yml | `cutover` | `(gated ops) && 'inngest-cutover' || 'deploy-channel'`; narrow loader per arm — the `if: op == 'backup'` privileged-loader step stays for HCLOUD only |
| deploy-inngest-image.yml | `deploy` | `deploy-channel` + narrow loader |
| inngest-key-rotate.yml | `redeploy` | `deploy-channel` + narrow loader (apply1/apply2/reboot keep `infra-privileged`) |
| inngest-link-flip.yml | `flip`, `revert` | `deploy-channel` + narrow loader |
| key-rotate.yml | `redeploy` | `deploy-channel` + narrow loader (apply/clear keep `infra-privileged`; guard/notify hold no Doppler credential) |
| restart-inngest-server.yml | restart job | `deploy-channel` + narrow loader |
| scheduled-inngest-health.yml | `probe` | `deploy-channel` + narrow loader |
| scheduled-followthrough-sweeper.yml | `sweep` (existing) + NEW `sweep-deploy-channel` | `sweep` keeps no env and gets `FT_EXCLUDE_SECRETS=<trio>`; the new job binds `deploy-channel` + narrow loader + `FT_ONLY_SECRETS=<trio>,GH_TOKEN` |
| apply-deploy-pipeline-fix.yml | any job still naming the trio post-PR-2 | reads via the existing privileged export; remove residual `secrets.<trio>` binds |

Scripts and docs: the trio consumers keep reading process env (they must never
take credentials on argv — ADR-280, `bc_curl` stdin-config transport). Where a
file's tier-a row comes from a *counted* read shape (`doppler run|secrets
get|download` command, `${{ secrets.<NAME> }}`, `${!var}` indirection of a
family name, `terraform output -raw`), the shape is replaced by explicit named
env reads (`${VAR:?…}`), which the scanner does not count:

- `apps/web-platform/scripts/github-app-key-status.sh`: header recipe becomes
  `doppler run -p soleur-deploy-channel -c prd` (operator recipe, stated in
  prose, not as a scan-counted command if the recipe can avoid the literal
  token); the `${!v}` loop becomes three explicit `:?` checks → row -> sink.
- `scripts/ensure-doppler.sh`: comment-only recipe update.
- `scripts/followthroughs/sweep-followthroughs.sh`: `FT_ONLY_SECRETS` /
  `FT_EXCLUDE_SECRETS` partition flags (comma lists; a tracker runs iff its
  `secrets=` ⊆ ONLY and — in the Tier-B job — ∩ the required marker ≠ ∅); the
  Tier-B job refuses exit 0 when it ran zero trio probes while an open tracker
  declares one (the discriminating coverage assertion; a trio probe left
  homeless is a red, not silence). Tier-A Guard-3 "required secret missing"
  noise is eliminated by the exclusion flag, and skip decisions print summary
  lines on both sides.
- `scripts/followthroughs/inngest-soak-6178.sh` + its full artifact set:
  DELETE — probe, `inngest-soak-6178.test.sh`,
  `inngest-soak-6178.function-ids.txt`, and the
  `run_suite "scripts/inngest-soak-6178"` line in `scripts/test-all.sh` — #6178 is
  CLOSED, so its probe's `secrets=` retire directive executes. Early deletion
  before close+14d (2026-11-21) costs at most a daily `missing in repo HEAD`
  stderr line in the sweeper (fail→`return 0`, no reopen, no comment —
  `sweep-followthroughs.sh`).
- `scripts/followthroughs/sdk-bash-smoke-verdict-10548.sh`: stays (#10548 OPEN);
  its sink rows persist; it is served by the new `sweep-deploy-channel` job.
- `scripts/key-rotate.sh`, `scripts/inngest-link-flip.sh`,
  `scripts/cutover-inngest.sh`, `apps/web-platform/infra/infra-config-verify.sh`,
  `scripts/check-deploy-script-parity.sh`,
  `scripts/verify-tunnel-ingress-origin.sh`,
  `apps/web-platform/infra/soleur-host-bootstrap.sh`,
  `apps/web-platform/infra/cloud-init*.yml`: disposition per-file — de-shape any
  counted read shape to explicit named env reads; rows end deleted (file stops
  naming the family) or forward-classed `tier-a -> sink/tier-b` by the scanner's
  own computation.
- Skill docs (`plugins/soleur/skills/postmerge/SKILL.md`,
  `plugins/soleur/skills/qa/SKILL.md`, `plugins/soleur/skills/ship/SKILL.md`,
  `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`,
  `plugins/soleur/skills/plan/references/plan-sharp-edges.md`): replace every
  literal `doppler run -p soleur -c prd_terraform` trio recipe with prose naming
  `soleur-deploy-channel/prd` as the source — .md lines are all "code" to the
  scanner (no comment syntax), so a literal command token keeps the row tier-a;
  the recipe must name the project, not the command.
- `knowledge-base/project/specs/archive/…/bootstrap.sh` (the archived
  trio-naming bootstrap): de-shape in place — it is the standing operator
  recipe, and its `prd_terraform` recipe becomes wrong when the config is
  emptied.
- Pinned-shape tests that assert the old `secrets.*` wiring
  (`apps/web-platform/infra/cutover-inngest-workflow.test.sh`,
  `inngest-key-rotate-workflow.test.sh`, `inngest-link-flip-workflow.test.sh`,
  `key-rotate-workflow.test.sh`, `infra-config-verify` tests,
  `tests/scripts/test-argv-bearer-sweep.sh`,
  `.github/actions/dispatch-web-redeploy` tests, `cloud-init-web-zot-seed` /
  `web-host-provisioner-parity` tests, `check-deploy-script-parity` tests):
  assertions move to the loader-export/env-read shapes.

`hooks.json.tmpl`, `variables.tf` `var.webhook_deploy_secret`, `server.tf`: no
change — PR-2 already feeds them from the Tier-B export. The `or`/`_NEXT`
rotation render and `WEBHOOK_DEPLOY_SECRET_NEXT` machinery stay absent (their
`@allow` rows persist); that machinery is the operator-reserved rotation tail.

### Sequencing — why two PRs, not one

`apply-web-platform-infra.yml` must create `deploy-channel` and its main-only
policy **before** any workflow references `environment: deploy-channel`: GitHub
auto-creates a referenced-but-missing environment with NO protection — a
branch-reachable carrier worse than the repo secret it replaces. Additionally,
between a consumer's merge and the operator's token seeding, its job fails
closed — acceptable for dispatch workflows, unacceptable for the 15-minute
`scheduled-inngest-health` probe whose red run pages an inngest outage that does
not exist. Therefore:

- **PR-A**: carrier `.tf` + `-target=` additions + loader narrow mode + census
  constants/Guard rows for the new env and token + C4 edge update. No consumer
  touches `deploy-channel` yet; nothing changes at runtime.
- **Owner-named seed** (between the merges): verify live policy, hash-equal
  copy, mint token, set env secrets on `deploy-channel` + `inngest-cutover`.
- **PR-B**: every consumer migration, script/doc de-shaping, sweeper partition,
  probe retirement, baseline end-state, trio->`TIER_B_NAMES` + boundary census
  rows, ADR-241 D1 amendment.
- **Owner-named tail** (after PR-B green on main canaries): delete the trio from
  `prd_terraform`, the repo Actions secrets, and `CF_TUNNEL_TOKEN` if it rides
  the same path; record the deletion postcondition (census output +
  `doppler secrets` listing showing the names gone) in the tracking issue.
- **Operator-reserved, out of scope**: HMAC rotation machinery and execution;
  `cloudflare_zero_trust_access_service_token.deploy` stale-state
  reconciliation (#7103 B5).

## Technical Considerations

### Attack Surface Enumeration (security change)

- Reach-without-naming is closed by deleting the Tier-A/repo copies + the
  main-only policy, not by any census: `doppler run -c prd_terraform` injecting
  the whole project, `secrets: inherit`, `toJSON(secrets)`, computed
  `secrets[format(...)]`, and host-side readers of the rendered `hooks.json`
  are the suite's documented blind spots; the deletion postcondition is the
  proof they are dead.
- A job bound to `deploy-channel` runs branch YAML only from `main`; a fork/PR
  workflow naming the env is refused before secrets materialize.
- The narrow project holds *only* the trio — a leaked `DOPPLER_TOKEN_DEPLOY_CHANNEL`
  reads nothing else; the privileged token is never handed to these jobs.
- `${!var}` indirection and `doppler` commands are the scanner's counted shapes
  because they can reach a store opaquely; explicit `${VAR:?}` env reads are
  declared dependencies fed by the loader.
- `bc_curl`/`bc_hmac_sha256_hex` keep credentials off argv (ADR-280); the
  migration must not introduce an argv or `toJSON(secrets)` path.

### Baseline end-state rule

Each remaining `tier-a` row in `tests/scripts/trio-baseline.tsv` ends one of:
(a) deleted — the file stops naming the family (preferred: ambient loader env
means most workflow files need never name it); (b) forward-classed by the
scanner's own computation (`tier-a -> tier-b` when a workflow's naming jobs all
bind a literal Tier-B env; `tier-a -> sink` when a non-workflow file loses its
counted read shape); (c) an `Allow:`/`Reclass:`/`Re-date:` line in ADR-241 with
a baseline/ADR-only diff where the ratchet requires it. If a file's only
residual is a `doppler` command over *non-trio* creds in a literal-Tier-B-bound
job and it cannot stop naming the trio, that is a named decision point —
either a narrowly-scoped scanner class refinement (a suite change, recorded in
the same ADR-241 amendment) or a per-row `Re-class:` ruling; do not decide
silently (see `decision-challenges.md`). Terminal assertion: zero `tier-a`,
`FALLBACK:*`, `ALIAS:*` rows; every `tier-b` row proven.

## Downtime & Cutover

The gate's trigger classes (host reboot/replace, lock-taking DDL, dropped
in-flight requests) do not apply — no serving surface is restructured. The
change *is* a credential-source cutover, so the zero-downtime property is
proved here explicitly rather than left implicit:

- **Mechanism (expand-contract, not a hard cut):** the trio exists in BOTH
  stores during the migration — `prd_terraform`/repo secrets stay live until
  PR-B is green on main canaries (the owner-named tail deletes them last).
  The `soleur-deploy-channel` copy is hash-equal, so a consumer reading either
  store receives byte-identical values; there is no window in which a correct
  caller fails because the value moved.
- **Per-stage verification:** after PR-A, the operator read-back verifies
  `protection_rules` before any secret is seeded; after the seed, the first
  `scheduled-inngest-health` run reporting `source=tier_b_deploy_channel` is
  the live proof; after PR-B, the census suites + the deletion postcondition
  close the loop.
- **Rollback at every stage:** PR-A is inert (nothing references the new env);
  post-seed pre-PR-B a consumer PR can be reverted with no credential change;
  post-PR-B a revert restores `secrets.*` binds against still-live Tier-A
  copies. Rollback becomes impossible only after the owner-named deletion —
  which is exactly why it is gated on green canaries.
- **Residual window:** between PR-B's merge and the deletion step the trio is
  double-homed (bounded by the same-day owner step); between PR-A's merge and
  the seed, no job binds `deploy-channel`, so the empty carrier fails nothing.

## User-Brand Impact

- **If this lands broken, the user experiences:** deploys silently stop —
  `web-platform-release.yml`'s `deploy` job fails closed on an empty exported
  `WEBHOOK_DEPLOY_SECRET` (visible as a failed release run, or as a red
  `scheduled-inngest-health` probe if the probe job is mis-bound); no data is
  exposed by the fail-closed arm.
- **If this leaks, the user's data/workflow is exposed via:** a branch actor
  holding the trio signs `POST /hooks/infra-config` and replaces `ci-deploy.sh`
  on the deploy host — arbitrary code in the deploy path serving *every*
  tenant, plus reads of the host credential file.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the worst case is a cross-tenant
  supply-chain incident (poisoned deploy artifact on the shared host), not a
  single user's data — CPO sign-off required; headless-run persistence is in
  `decision-challenges.md`.

## Observability

```yaml
liveness_signal:
  what: "The migrated workflows' own run results — loader `source=tier_b_deploy_channel` line in the job log plus the existing per-workflow success/failure signal (deploy-status heartbeat, inngest-health probe verdict)"
  cadence: per-run (release/cutover/link-flip/key-rotate on dispatch; inngest-health every 15 min; sweeper daily)
  alert_target: "Actions run failures (existing); scheduled-inngest-health already pages on probe red"
  configured_in: ".github/workflows/scheduled-inngest-health.yml; .github/actions/infra-credentials/action.yml (source output)"

error_reporting:
  destination: "job log + step summary — the loader prints verdict=no_credential_source with the named cause; consumer steps fail closed on ${VAR:?…} with the loader-source hint"
  fail_loud: "::error title=infra-privileged::verdict=no_credential_source … or the consumer's named-missing-variable abort (exit 3/78 shape preserved)"

failure_modes:
  - mode: "deploy-channel environment secret absent or emptied"
    detection: "narrow loader fails closed before any credential use; every bound job red at the load step, never mid-deploy"
    alert_route: Actions run failure; scheduled probe red
  - mode: "a workflow job binds deploy-channel but the live env lost its main-only policy"
    detection: "census .tf-policy parse row + operator post-merge protection_rules read-back"
    alert_route: PR-time census RED; post-merge the seed script refuses
  - mode: "an open followthrough tracker declares a trio secret but no job serves it"
    detection: "sweep-deploy-channel coverage assertion refuses exit 0 on zero trio probes"
    alert_route: daily sweep run failure

logs:
  where: GitHub Actions job logs (source= line; sweep summary lines); no host logs
  retention: GitHub Actions log retention (90d)

discoverability_test:
  command: bash -c 'git grep -q soleur-deploy-channel .github/actions/infra-credentials/action.yml && printf "narrow-mode-present\n"'
  expected_output: narrow-mode-present
```

## Encryption Posture

```yaml
at_rest:
  - store: "doppler_project.deploy_channel (soleur-deploy-channel/prd — the trio)"
    mechanism: "provider-managed:Doppler workspace encryption-at-rest (same attestation the privileged/infra-app projects rely on)"
    evidence: "ADR-241 D3/D11 carrier precedent; Doppler encrypts project values at rest (vendor attestation); values never enter tfstate — the .tf declares containers only"
    defends_against: "a Terraform-state reader (Tier-A-readable web-platform state) recovering the trio; a prd_terraform branch-config read reaching it (a PROJECT, never a branch config — the #8209 lesson)"
    does_not_defend: "a holder of DOPPLER_TOKEN_DEPLOY_CHANNEL or DOPPLER_TOKEN_TF; a Doppler-side breach"
    disclosed_as: not-publicly-claimed
    live_verification: "available — post-seed `doppler secrets -p soleur-deploy-channel -c prd` listing is the operator postcondition"
  - store: "github_repository_environment.deploy_channel secret DOPPLER_TOKEN_DEPLOY_CHANNEL"
    mechanism: "provider-managed:GitHub Actions encrypted secrets (libsodium sealed box, environment-scoped)"
    evidence: "GitHub environment secrets are write-only-encrypted after set; reachable only by jobs that pass the deployment branch policy"
    defends_against: "any workflow on a non-main ref resolving the token (policy evaluated before secrets materialize)"
    does_not_defend: "an admin rewriting the branch policy (the ADR-241 D10 R1 nominal-boundary residual)"
    disclosed_as: not-publicly-claimed
    live_verification: "available — protection_rules read-back in the seed step"
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
    dedupe: "partition is exclusive: a tracker declaring a trio name is skipped by the Tier-A sweep (FT_EXCLUDE_SECRETS) and only runnable by this job (FT_ONLY_SECRETS + required-marker), so the same tracker is never swept twice in one cycle"
    source_dedupe: "not a ticket source — the followthrough labels on issues are created by humans/other tooling; the sweeper's existing directive parse decides what runs"
```

## Architecture Decision (ADR/C4)

- **ADR-241 amendment (deliverable):** a dated D1 census-amendment entry
  recording: the narrow carrier (`soleur-deploy-channel` project,
  `deploy-channel` environment, `DOPPLER_TOKEN_DEPLOY_CHANNEL`) adopted under
  the D11 `soleur-infra-app` precedent; consumers migrated and baseline
  end-state reached; Tier-A copies owner-deleted with the postcondition
  recorded; rotation machinery and the stale-state reconciliation remain
  operator-reserved; D1 keeps its adopting status (G1 closes with the issue
  after the rotation tail); plus any `Allow:`/`Reclass:`/`Re-date:` lines the
  baseline diff itself requires in the same change.
- **C4:** `knowledge-base/engineering/architecture/diagrams/model.c4`
  `github -> doppler` Tier-B edge — add `deploy-channel` to the environment
  enumeration, add the `soleur-deploy-channel` narrow project +
  `DOPPLER_TOKEN_DEPLOY_CHANNEL` clause (mirroring the existing
  `soleur-infra-app` D11 clause), and refresh the loader-consumer list
  (`inngest-key-rotate`'s "redeploy job holds the deploy webhook credentials
  only" sentence and the `key-rotate` parallel need the narrow-source wording).
  `views.c4`/`spec.c4` render by include — verify no explicit include change is
  needed; no new element is expected (the edge description carries the fact).

## Guard Contract

### Guard 1 — trio-boundary census rows (`test-infra-privileged-tier-census.sh`)

**Property.** No workflow job names the trio family (`secrets.<trio>`, a
`doppler` read of a trio name from `prd_terraform`, or a workflow-level `env:`/
`secrets:` bind) unless the job declares a literal Tier-B environment, and the
trio names live in `TIER_B_NAMES` so the existing no-non-loader-read rows apply.

**Assembly.** `git ls-files` workflow population (same parse the census already
runs), `ENV_SECRETS`/`TIER_B_NAMES`/`TIER_B_ENVIRONMENTS` constants, the `.tf`
policy parse proving `deploy-channel` is main-only, the loader's
`doppler-project` allowlist.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | A fixture workflow binding `env: {WEBHOOK_DEPLOY_SECRET: ${{ secrets.WEBHOOK_DEPLOY_SECRET }}` in a job with no `environment:` | RED — named row |
| 2 | `deploy-channel` removed from the env policy parse set while `TIER_B_ENVIRONMENTS` still names it | RED — the census proves the env from the `.tf`, not from its own list |
| 3 | A second job in the fixture binds the trio with `environment: deploy-channel` while a first binds it bare | RED — the guard must not stop at the compliant member |

### Guard 2 — loader narrow mode (`infra-credentials/action.yml` + its tests)

**Property.** `doppler-project` accepts only
`{soleur-infra-privileged, soleur-deploy-channel}`; narrow mode fails closed on
an empty `doppler-token-deploy-channel` and never evaluates the legacy arm.

**Assembly.** The composite's input validation block, the load step's arm
split, the allowlist literal, `outputs.source`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `doppler-project: soleur` (a non-allowlisted project) | RED — refused before any read |
| 2 | narrow project selected, `doppler-token-deploy-channel: ''` | RED — `verdict=no_credential_source` exit, no silent legacy arm |
| 3 | allowlist gains a third name with a token present for the second | RED — the second allowed member must still export correctly AND an injected third name must refuse; a check that only exercises member one is vacuous |

### Guard 3 — sweeper partition (`sweep-followthroughs.sh` + sweeper tests)

**Property.** A followthrough tracker declaring a trio name runs in exactly one
sweep job — the Tier-B one — and a tracker that fits neither partition
surfaces red rather than silently lapsing.

**Assembly.** `FT_ONLY_SECRETS`/`FT_EXCLUDE_SECRETS` parse, the `secrets=`
directive match, the zero-trio-probes coverage assertion, both job env blocks.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | fixture tracker declaring `secrets=WEBHOOK_DEPLOY_SECRET` while the Tier-B job env is absent | RED — coverage assertion, not Guard-3 comment noise |
| 2 | `FT_EXCLUDE_SECRETS` emptied in the Tier-A arm while a trio tracker is open | RED — partition overlap is refused/detected |
| 3 | a tracker declaring `secrets=WEBHOOK_DEPLOY_SECRET,SOME_OTHER` (declared ⊄ ONLY) | RED — skipped by both arms and reported by the coverage assertion |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "move WEBHOOK_DEPLOY_SECRET and the CF Access pair (CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET) out of every branch-nameable location" | carrier `.tf` + loader narrow mode + consumer migration (Proposed Solution) | mapped |
| 2 | "both the Doppler `soleur/prd_terraform` copies and the GitHub Actions repo/org secret copies" | owner-named tail: deletion postcondition after PR-B green | mapped |
| 3 | "into main-only environment secrets or Tier B (`soleur-infra-privileged`)" | `deploy-channel` env + `soleur-deploy-channel` narrow project (+ existing privileged export for already-Tier-B jobs) | mapped |
| 4 | "migrate every consumer (the workflows, scripts, Terraform `var.webhook_deploy_secret` and the `hooks.json` render enumerated in the issue body — re-derive the set with `git grep` first)" | consumer table + script/doc/test de-shape list (re-derived via git grep during research) | mapped |
| 5 | "add a census row in `tests/scripts/test-infra-privileged-tier-census.sh`" | Guard 1 rows + `TIER_B_ENVIRONMENTS`/`ENV_SECRETS`/`TIER_B_NAMES` additions | mapped |
| 6 | "record the move as a D1 census amendment to ADR-241" | ADR-241 dated amendment entry | mapped |
| 7 | "The credential rotation tail is OPERATOR-RESERVED — do NOT plan or perform any rotation" | exclusion in Proposed Solution; no `or`/`_NEXT` machinery | mapped — excluded by design |
| 8 | "the stale `cloudflare_zero_trust_access_service_token.deploy` Terraform-state reconciliation is also operator-reserved (#7103 B5)" | exclusion; `removed{destroy=false}` block untouched | mapped — excluded |
| 9 | "Prior partials already MERGED — reconcile the plan against them" | Research Insights premise table + sequencing built on post-PR-2 state | mapped |
| 10 | "Do NOT start work." | this plan only; no implementation files touched | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `deploy-channel-environment.tf` | "into main-only environment secrets or Tier B (`soleur-infra-privileged`)" | asked |
| loader narrow mode | "into main-only environment secrets or Tier B (`soleur-infra-privileged`)" + CTO-ruling narrow-carrier clause | asked (carrier shape ruled) |
| consumer workflow env binds | "migrate every consumer (the workflows, scripts, Terraform `var.webhook_deploy_secret` and the `hooks.json` render enumerated in the issue body — re-derive the set with `git grep` first)" | asked |
| sweeper partition + `sweep-deploy-channel` job | same quote — `scheduled-followthrough-sweeper.yml` is a re-derived consumer | asked |
| probe retirement (inngest-soak-6178.sh) | — | inferred — justification: #6178 is CLOSED; its `secrets=` directive is a retirement clause the migration is the only mover of |
| census constants + Guard rows | "add a census row in `tests/scripts/test-infra-privileged-tier-census.sh`" | asked |
| baseline end-state dispositions | same + "record the move as a D1 census amendment to ADR-241" (the baseline ratchet is the census's own mechanism) | asked |
| ADR-241 amendment + C4 edge update | "record the move as a D1 census amendment to ADR-241" | asked; C4 inferred — justification: the `github -> doppler` edge enumerates envs and loader consumers exhaustively and would lie otherwise |
| two-PR sequencing + owner-named seed/tail | "out of every branch-nameable location" + "move … into main-only environment secrets" | inferred — justification: GitHub auto-creates an unprotected env for a job that references a missing one; the 15-min probe must not page a false outage during the seed window |

### Split Assessment

- Subsystems touched: 6 — `.github`, `apps`, `scripts`, `tests`, `knowledge-base`, `plugins`
- Planned files: ~35–45 | Estimated changed lines: ~900–1400 (mostly de-shapes + assertions + census fixtures)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — PR-A (carrier + loader + census constants, infra only) → owner seed → PR-B (all consumers + docs + baseline + ADR). The boundary is the merge-ordering requirement, not taste: consumers cannot safely name `deploy-channel` until its TF-declared main-only policy exists live.

## Acceptance Criteria

1. `deploy-channel` exists with a TF-declared main-only deployment branch
   policy and zero reviewers; `soleur-deploy-channel/prd` holds a hash-equal
   copy of the trio (operator-seeded); `DOPPLER_TOKEN_DEPLOY_CHANNEL` is an
   environment secret on `deploy-channel` and `inngest-cutover`.
2. The loader's narrow mode exports the trio from `soleur-deploy-channel/prd`,
   fails closed on an empty token or non-allowlisted project, and names no
   trio stem literally.
3. Zero `${{ secrets.WEBHOOK_DEPLOY_SECRET }}` /
   `CF_ACCESS_CLIENT_ID` / `CF_ACCESS_CLIENT_SECRET` references remain in
   `.github/workflows/`; every job that names the trio declares a literal
   Tier-B environment.
4. `tests/scripts/trio-baseline.tsv` carries zero `tier-a`, `FALLBACK:*` and
   `ALIAS:*` rows; every surviving row is scanner-agreed `tier-b`/`sink`; the
   two suites are green (live + mutation fixtures).
5. `tests/scripts/test-infra-privileged-tier-census.sh` proves the boundary:
   trio in `TIER_B_NAMES`, `DOPPLER_TOKEN_DEPLOY_CHANNEL` in `ENV_SECRETS`,
   `deploy-channel` in `TIER_B_ENVIRONMENTS` with `.tf`-parseable policy,
   narrow-mode allowlist guarded — each with a mutation fixture driven RED.
6. The sweeper partition: `sweep` never touches a trio tracker;
   `sweep-deploy-channel` serves every open trio tracker and refuses green on
   a homeless one; `inngest-soak-6178.sh` is deleted.
7. ADR-241 carries the dated D1 census-amendment entry; model.c4's
   `github -> doppler` edge names `deploy-channel` + `soleur-deploy-channel`.
8. Post-merge postcondition (operator-recorded): trio absent from
   `prd_terraform` and repo Actions secrets; a canary run reports
   `source=tier_b_deploy_channel`.
9. Excluded and confirmed untouched: rotation machinery (`or` render,
   `WEBHOOK_DEPLOY_SECRET_NEXT`), `cloudflare_zero_trust_access_service_token.deploy`
   state reconciliation, any credential rotation.

## Test Scenarios

Mutation-driven (each maps to a Guard matrix row):

- census fixture: bare `secrets.<trio>` bind in a no-env job → RED
- census fixture: trio bind in a job binding a non-Tier-B env → RED
- census fixture: `doppler secrets get WEBHOOK_DEPLOY_SECRET -c prd_terraform`
  outside the loader → RED (G1g once trio joins `TIER_B_NAMES`)
- loader: `doppler-project: soleur` → refused; narrow + empty token →
  `no_credential_source`; narrow + token → exports trio + `TF_VAR_` spellings,
  `source=tier_b_deploy_channel`
- sweeper: trio tracker + absent Tier-B env → coverage RED; overlap → RED;
  declared-superset tracker → skipped-by-both reported
- ratchet: baseline diff adding an un-`@allow`ed tier-a row → RED; row
  deletions tracked; class moves forward-only
- positive control: full migration tree green on both suites and
  `bash tests/scripts/test-argv-bearer-sweep.sh` unchanged-green (no argv path
  introduced)

## Dependencies & Risks

- The `deploy-channel` env must exist with its live main-only policy before
  any job references it (auto-created envs are unprotected) — the two-PR
  boundary is load-bearing, not stylistic.
- Between PR-B merge and the owner-named tail, the trio exists in both stores
  — the narrow project is hash-equal, so no rotation race; the window is
  bounded by the same-day deletion step.
- `scheduled-inngest-health` (15-min cadence) and the daily sweeper are the
  only unattended consumers that would page on an empty carrier — both migrate
  in PR-B, after seeding.
- Files whose rows cannot de-tier under current scanner rules (residual
  `doppler` command over non-trio creds + unavoidable trio naming) need a
  named ruling — recorded in `decision-challenges.md` as a pending technical
  row rather than silently chosen.
- A scanner class-rule refinement, if needed, changes a guard suite itself —
  it lands only with the ADR-241 amendment recording it.

## Research Insights

Premise validation (authoritative `gh`/git output, 2026-11-16):

| Premise | Verdict |
|---|---|
| #9294 OPEN; #10390 epic; #8609 gated; #7103/#10382 open; #10548 open; #6178 CLOSED | confirmed |
| Prior partials #10376, #10458, #10928, #12330 MERGED | confirmed (`gh pr view`); rotation PR-B #12445 also merged — `local.deploy_service_token_ids` carries only the new id `d9204def…`, so the Access-token rotation tail the issue names is already done |
| No `deploy-channel-environment.tf`, `webhook_deploy_secret_next`, or `or` render exists | confirmed by grep — the carrier was never built; PR-1's remaining rungs are this slice |
| Trio already in `soleur-infra-privileged/prd` (Tier B) post-PR-2 | confirmed — `tunnel.tf` comment + loader whole-project export already serve Terraform-fed consumers |
| 11 workflows bind `secrets.<trio>` today | confirmed by git grep: web-platform-release, canary-status, cutover-inngest, deploy-inngest-image, inngest-key-rotate, inngest-link-flip, key-rotate, restart-inngest-server, scheduled-followthrough-sweeper, scheduled-inngest-health (+ residual binds in apply-deploy-pipeline-fix) |

Measured facts the design rests on:

- `infra-privileged-environment.tf` header (lines 41-49): a referenced-but-missing
  environment is auto-created with NO protection — the load-bearing reason for
  the two-PR sequence.
- `infra-app-project.tf` (lines 1-17): the D11 narrow-project precedent —
  Terraform declares the bare project + `prd` env; the operator-run script
  populates values and mints the read token; Census Guard 7 enforces
  no-secret/no-token/no-data-source.
- `trio-baseline` scanner classes: `tier-a` = file naming the family WITH a
  counted read shape (`doppler run|secrets get|download` command,
  `${{ secrets.<NAME> }}`, `${!var}` family indirection, `terraform output
  -raw`, composite action, FALLBACK/ALIAS); `tier-b` = workflow whose naming
  jobs all declare literal Tier-B envs; `sink` = non-workflow with no read
  shape. Rows are deleted when the file stops naming the family; classes are
  computed, never asserted.
- `bc_curl`/`bc_hmac_sha256_hex` transport keeps the trio off argv (ADR-280);
  scripts' `${VAR:?}` env reads are not counted shapes — that is what makes
  "de-shape to explicit env reads" a legitimate `tier-a -> sink` move.
- `cutover-inngest.yml:96` env expr `(rollback|resume|backup) ? 'inngest-cutover' : ''`
  — the only consumer with a conditional environment; its `op == 'backup'`
  privileged-loader step stays HCLOUD-only.
- `model.c4` `github -> doppler` edge (~line 816) enumerates Tier-B
  environments and loader consumers exhaustively — it must name
  `deploy-channel` + `soleur-deploy-channel` or it lies.
- No subagent consults ran (no spawn mechanism on this tool surface); the
  gates, fork rulings and adversarial checks were applied inline and every
  open technical fork is recorded `pending - assumed` in
  `decision-challenges.md` — no independent review is claimed.

## References & Research

- Issue #9294 (OPEN), epic #10390; gates #8609 (ADR-241 D10/G1).
- Merged partials: #10376 (PR-0), #10458 (PR-1a), #10928 (PR-2), #12330 +
  #12445 (rotation PRs — new Access id `d9204def` sole id in
  `local.deploy_service_token_ids`).
- Carrier precedent: `apps/web-platform/infra/infra-app-project.tf` (#9321,
  ADR-241 D11) + `infra-privileged-environment.tf` (#8209).
- Census: `tests/scripts/test-infra-privileged-tier-census.sh`,
  `tests/scripts/test-trio-baseline-census.sh` + `trio-baseline.tsv` (ratchet
  rules in its own header).
- Transport invariant: `scripts/lib/bearer-curl.sh` (ADR-280 — stdin-config,
  never argv).
- Stale-state hold: #7103 B5 (`cloudflare_zero_trust_access_service_token.deploy`
  `removed{destroy=false}` block in `tunnel.tf`).

## Enhancement Summary

deepen-plan run 2026-11-16 (sequential-fallback: no subagent spawn mechanism on
this tool surface; all gates evaluated inline, no independent review claimed).

### Gate verdicts

| Gate | Verdict |
|---|---|
| §4.4 Precedent-Diff | pass — carrier mirrors `infra-app-project.tf`/`infra-privileged-environment.tf` byte-for-byte in shape; divergences (no reviewers, narrow allowlist) are the CTO-ruled point |
| §4.45 Implementation-Realism | pass — every referenced file/env/constant read from the live tree; loader internals, census constants and scanner class rules verified against source |
| §4.55 Downtime & Cutover | pass — zero-downtime expand-contract proven in the new `## Downtime & Cutover` section |
| §4.6 User-Brand Impact | pass — threshold `aggregate pattern` with concrete artifacts |
| §4.7 Observability | pass after fix — probe was suite-shaped (`tests/` path tripped the 15s-cap heuristic); replaced with a `git grep` probe on the loader file |
| §4.8 PAT-shaped variables | pass — no `var.*_token`/`TF_VAR_(GITHUB|GH)_*`/literal token shapes; `GH_TOKEN` mentions are the sweeper's existing mechanism name |
| §4.9 UI wireframe | n/a — no UI surface |
| §4.10 Encryption Posture | pass — new Doppler project + env-secret connection declared; `does_not_defend` fields non-boilerplate |
| §4.11 Guard Contract | pass — `lint-guard-contract.py` RC 0, 3 guard entries, mutation matrices >=3 rows, assemblies structural |
| §4.12 Scope Check | pass — one unfenced section, all asks mapped, inferred rows justified |
| §4.13 Task Design | pass — `sweep-deploy-channel` answers all six questions; dedupe = exclusive partition |

### Key Improvements

- Two-PR sequence replaces a single-shot cutover after discovering GitHub
  auto-creates an unprotected environment for a job that references a missing
  one (`infra-privileged-environment.tf:41-49`) — a single-PR shape would have
  shipped a branch-reachable carrier worse than the repo secrets it replaces.
- Sweeper partition design (`FT_ONLY_SECRETS`/`FT_EXCLUDE_SECRETS` + coverage
  refusal) replaces the naive "drop the env binding", which would have made
  Guard 3 red every open trio tracker daily.
- Baseline end-state rule made explicit: rows are deleted/forward-classed per
  the scanner's own computation, with ADR-241 `Allow:`/`Reclass:`/`Re-date:`
  lines only where the ratchet demands — no silent reclass.
- Loader constraint added: narrow mode must name no trio stem literally, or
  the composite-action class would pin a permanent `tier-a` row.
- Rotation PR-B (#12445) discovered merged — the Access-token rotation the
  brief flags as a future tail is already done; only the HMAC machinery +
  stale-state reconciliation remain operator-reserved.

### New Considerations Discovered

- #6178 is CLOSED (was OPEN at the earlier G1 plan) — its followthrough probe
  retires in this slice rather than migrating.
- `DOPPLER_TOKEN_DEPLOY_CHANNEL` must be seeded on BOTH `deploy-channel` and
  `inngest-cutover` (gated cutover ops keep their reviewer-gated env).
