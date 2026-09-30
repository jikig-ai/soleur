---
title: "security: the soleur-ai runtime App key in Doppler prd is reachable from any branch, and it can rewrite the ADR-241 boundary"
date: 2026-09-30
slug: security-evict-runtime-app-key-from-prd-reachability
branch: feat-one-shot-8609-evict-runtime-app-key-prd
issue: 8609
closes: 8609          # by PR-B only (the D2 flip); PR-A carries `Ref #8609`
type: security
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# Evict the soleur-ai runtime App key from branch-reachable Doppler `prd` (#8609, ADR-241 R1)

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

This plan closes ADR-241 residual R1. The soleur-ai GitHub App's **runtime** private key lives in
the Doppler `soleur/prd` root config. Every repository-secret Doppler token that resolves `prd` or
one of its `prd_*` branch configs can read it, and any branch workflow of this public repository
can name those secrets. The key mints installation tokens with write access on three
installations (two belong to third-party users) and holds `administration:write` on
`jikig-ai/soleur`, so a holder can rewrite the very deployment-branch policies ADR-241 D2 rests on.

**The mechanism (CTO-ratified, see Domain Review):**

1. **Move the key out of the `soleur` project.** A new Doppler **project**, `soleur-github-app`
   (config `prd`), holds `GITHUB_APP_PRIVATE_KEY` (plus, from R0 to R7 only, the parked old key
   `GITHUB_APP_PRIVATE_KEY_RETIRED` used for the final `401` probe). No `prd` or `prd_*` reader can
   see it, whatever branch config is added later.
2. **Rotate at the same time.** A **new** App key is generated straight into that project and never
   touches `prd`. The old key — every copy of which was branch-reachable, and which Doppler keeps in
   `prd`'s version history even after a delete — is deleted at GitHub last, so a copy taken
   earlier is dead. The new key is born only after #8209 O10/O13 take `DOPPLER_TOKEN_TF` (a
   workplace token that reads every project) out of branch reach.
3. **The web host reads it with its own read token.** An operator-minted, read-only service token
   for `soleur-github-app/prd` is stored only in the Tier-B project `soleur-infra-privileged`,
   loaded only by Tier-B jobs, and added as **one conditional line** to the host's existing credential
   file (`soleur-doppler-token.tmpl`). That render already feeds cloud-init for fresh hosts (state
   keeps a hash) and the Terraform-driven, hash-bound push to the running web-1
   (`terraform_data.deploy_pipeline_fix`, #7095). web-2, whose credentials are birth-frozen, is
   immutably replaced from `main`.
4. **The deploy overlays exactly one name.** `ci-deploy.sh` and the boot path download `prd` as
   today, then fetch `GITHUB_APP_PRIVATE_KEY` from the isolated project and let it win. Before
   promotion, the canary container proves GitHub accepts its key for `slug=soleur-ai`
   (`GET /app`); a missing or rejected key leaves the running container serving.
5. **Two PRs.** PR-A ships the code, the Terraform container, the guards, the ADR-241 D10
   amendment and the runbook sequence (`Ref #8609`). PR-B flips ADR-241 D2 to `accepted` (and closes
   #8609) only after the operator sequence is measured: an old-key JWT gets `401`, the new key serves,
   and the App's key list holds exactly one fingerprint.

`GITHUB_APP_ID` stays in `prd` (public identifier). `GITHUB_APP_WEBHOOK_SECRET` and
`GITHUB_CLIENT_SECRET` are deferred to a tracking issue (see Non-Goals).

## Research Reconciliation — Spec vs. Codebase

| # | Claim (issue / ADR / parent brief) | Reality (measured) | Plan response |
|---|---|---|---|
| 1 | "ADR-241 A11 names the required shape: hash-bound cloud-init, immutable redeploy" | web-1 has no automated replace path: every route to `hcloud_server.web` halts at host create (#6718, gap #6730), and `server.tf` records web-1 as a host that "cannot be replaced". The running-host delivery that exists is the Terraform-declared, hash-triggered push (`terraform_data.deploy_pipeline_fix` → `/hooks/infra-config`) | Fresh hosts: cloud-init (hash-bound through the shared render). web-1: the #7095 push channel, which is Terraform-declared and shares its source with cloud-init — not an SSH/rescue edit, so `hr-prod-host-config-change-immutable-redeploy` holds. web-2: immutable `web_host_replace` from `main`. D10 records that A11's "immutable redeploy" wording is superseded for web-1 until #6730 closes |
| 2 | "Tier-B token could be Terraform-minted like `soleur-inngest`" | Web-platform state is Tier-A readable (ADR-241 D4); a `doppler_service_token` minted there is branch-readable (ADR-241 D3's rule) | Operator-minted into `soleur-infra-privileged`, marked `autonomy-considered: operator-mint` citing ADR-241 D3 (exempt from `hr-tf-variable-no-operator-mint-default`, same as O2/O3 of #8209) |
| 3 | "A fix that re-scopes the token must enumerate `DOPPLER_TOKEN_PRD` consumers" | The `prd` reader set is larger than `DOPPLER_TOKEN_PRD`: `DOPPLER_TOKEN`, `DOPPLER_TOKEN_WEB_ARM`, `DOPPLER_TOKEN_KB_DRIFT`, `DOPPLER_TOKEN_DRIFT_MAP` (includes `prd`) and every future branch config | Not re-scoped; the key leaves the project instead. No `prd` reader changes, so P4 holds by construction. The CPO's pre-delete check (no CI reader of `GITHUB_APP_PRIVATE_KEY` from `prd`) is AC-R6a |
| 4 | "Moving the key must not break the CI `prd` readers" | No workflow reads the runtime PEM via `DOPPLER_TOKEN_PRD`; the shared mint action reads `prd_terraform` (CTO sweep) | AC-R6a verifies it once before R6, resolving each reader's config (after R6 a `prd` read of the key fails loudly on its own) |
| 5 | "A `prd`-reading repo secret can no longer obtain a key that holds `administration:write`" (issue AC1) | `prd_terraform` holds a **second, distinct** soleur-ai key (ADR-241 M3). #8209 O10 shadows it and O13 deletes it at GitHub; O10 is held on #9262 | **PR-B is gated on #8209 O10 and O13's App-key delete** (Dependencies). This plan does not fold #9262 in, and does not delete the `prd_terraform` key itself: deleting it before #9262 lands breaks `mint-inngest-bootstrap-tag` and `bump-cloud-init-pin` |
| 6 | "The web host reads `prd` with its boot token" | That boot token's **value** is the `DOPPLER_TOKEN` key in `prd_terraform` (Tier A) | Irrelevant after the move — it cannot read `soleur-github-app`. The **new** token must never land in any `soleur` config (census G6b), and the loader exports its name unconditionally so the `prd_terraform` arm cannot supply it (G6f) |
| 7 | "Cloud-init has room for another file" | `server.tf` records under ~300 B of `WEB_GZIP_BUDGET` headroom; a random token barely compresses | One conditional line in the existing `/etc/default/soleur-doppler-token` (plan review: a separate file needs four more delivery surfaces and cannot be removed without SSH). Measured first in Phase 0.1 against `WEB_GZIP_BUDGET` in `plugins/soleur/test/cloud-init-user-data-size.test.ts`; the unit-env widening is recorded in D10 |
| 8 | "`DOPPLER_TOKEN_TF` is Tier B since #8209" | It is still in `prd_terraform` until O10 (held on #9262); it reads every Doppler project and can mint service tokens in them | R1 is gated on O10 + O13's `DOPPLER_TOKEN_TF` rotation; R8 lists the new project's tokens and members after O13 (architecture review P0) |

## Research Insights

### Premise Validation (Phase 0.6)

Checked on 2026-09-30 against `origin/main` at `69fcf4b53c` and live GitHub:

| Cited reference | State | Holds? |
|---|---|---|
| #8609 (this issue) | OPEN, `priority/p1-high`, `type/security` | yes |
| #8209 (parent eviction) | OPEN | yes — cannot close until this and its O13 rotation are done |
| #8211 (git-data cutover, blocked by this) | OPEN | yes |
| #9262 (re-tier two App-key minters before #8209 O10) | OPEN | yes — **not folded in** (parent instruction), but see Reconciliation row 5: it gates this plan's D2 flip |
| #6167 (branch-config non-isolation audit) | OPEN | yes — this plan closes one instance of the class, not the class |
| #8610 (Terraform-manage Tier-B env secrets, R6) | OPEN | yes, independent |
| ADR-241 `status: proposed`, D2 `proposed`, R1 row "OPEN — #8609", A11 "needs runtime and host bootstrap changes (hash-bound cloud-init, immutable redeploy)" | `ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md` | yes |
| ADR-220 D2–D3 flip condition names "ADR-241 residual R1 closed and R7 closed" | ADR-220 §Amendment log 2026-09-22 (#8209), D5 row | yes; R7 closed at O5b (2026-09-29, parent context) |
| Mechanism named by the ask ("hash-bound cloud-init, immutable redeploy") vs ADR corpus | ADR-241 A11 is the *deferral* row, not a rejection. No ADR rejects moving the runtime key to an isolated project; ADR-241 D3 **rejects Terraform-minting a secret in the web-platform root** (its state is Tier-A readable) — a constraint on *where the read token is minted*, which this plan honours | yes |

### Property List (Phase 0.6b)

- **P1.** No credential delivered as a repository secret — or readable through any Doppler config a
  repository-secret token resolves (`prd` and every `prd_*` branch config) — yields a usable private
  key of the soleur-ai App.
- **P2.** Every copy of a soleur-ai runtime key that was ever branch-reachable is invalid at GitHub
  (a JWT signed with it gets `401` from `GET /app`), so a copy taken before this change is dead.
- **P3.** The web app keeps minting installation tokens for all three installations through the
  cutover: no connected user sees a disconnect, a failed repo operation, or a rejected webhook.
- **P4.** Every existing `prd` reader in CI (`DOPPLER_TOKEN_PRD` consumers, the drift map, board
  sync, release migrate/verify, registry inventory, bootstrap-image build) keeps working unchanged.
- **P5.** A fresh web host (cloud-init from empty state) comes up with the key, with zero operator
  action (`hr-fresh-host-provisioning-reachable-from-terraform-apply`).
- **P6.** A regression — a workflow, action, script or `.tf` that re-exposes the key or its new
  read token to Tier A — goes red on the PR that introduces it.
- **P7.** The decision is recorded: ADR-241 R1 closed with its mechanism, D2 `accepted` with the PR
  saying why, ADR-220 D2–D3's #8209 limb marked satisfied, C4 updated.
- **P8.** The prior exposure is assessed on the record: the evidence limbs that expire (the App's
  key "added" dates, 90-day Actions logs) are captured before they are lost, and the disposition
  is stated in a dated, append-only legal record.

### Cut List (Phase 0.6b)

- **Re-scope `DOPPLER_TOKEN_PRD` to a main-only environment secret** → P1 → does not cover it: the
  `prd` reader set also includes `DOPPLER_TOKEN` (`prd_terraform`, must stay branch-reachable for PR
  plans), `DOPPLER_TOKEN_WEB_ARM` (`prd_terraform`), `DOPPLER_TOKEN_KB_DRIFT`
  (`prd_kb_drift_walker`), `DOPPLER_TOKEN_DRIFT_MAP` (one read token per `soleur` config, `prd`
  included — `token-drift-read-tokens.tf`, anchor `resource "github_actions_secret"
  "doppler_token_drift_map"`) and every future branch config (#6167). Moving the key out of the
  `soleur` project covers all of them at once. **Cut.**
- **Per-branch-config sentinel overrides** (the ADR-241 D4 `prd_terraform` trick, repeated in every
  `prd_*` config) → P1 → fails open on the next new branch config; the move covers it. **Cut.**
- **Strip `administration:write` / remove `jikig-ai/soleur` from the soleur-ai installation** → P1's
  "rewrite the boundary" half only → breaks runtime features that use it
  (`cron-gh-pages-cert-reissue.ts` `PUT /repos/{owner}/{repo}/pages` on this repo;
  `github-app.ts` `createRepoForOrg`), and leaves the two third-party installations reachable. **Cut**
  as a primary mechanism; recorded under Alternatives.
- **A new runtime App** → P1 → forces every connected user to reinstall (P3 violated). **Cut.**
- **Doppler Team plan / OIDC** → P1 → a branch config still inherits its root on any plan; ADR-241 A1
  already records it as a cost decision. **Cut.**
- **Moving `GITHUB_APP_ID`** → no property: the App ID is a public identifier (it is the JWT `iss`),
  and `prd_terraform`'s legacy minters still read it until #9262/O10. It stays in `prd`. **Cut.**

### Consumers and delivery path (measured)

- **Runtime consumers of the key** — all in the web container's Next.js process:
  `apps/web-platform/server/github-app.ts` (`getPrivateKey()`), `server/github/app-client.ts`
  (`PRIVATE_KEY_ENV`), `server/github/probe-octokit.ts`, normalised by
  `server/github/app-private-key.ts`. Inngest functions run in the same process; every agent-sandbox
  spawn-env allowlist already excludes `GITHUB_APP_PRIVATE_KEY` (comment in each
  `server/inngest/functions/cron-*.ts`). The inngest, git-data and registry hosts read their own
  isolated projects and never receive the key.
- **How the container gets it** — `apps/web-platform/infra/ci-deploy.sh` `resolve_env_file()`
  runs `doppler secrets download --no-file --format docker --project soleur --config prd` into a temp
  env-file; the boot path does the same in `soleur-host-bootstrap.sh` (`soleur-doppler-download`,
  `--project soleur --config prd`). Both read with the host's full-`prd` token from
  `/etc/default/soleur-doppler-token` / `/etc/default/webhook-deploy`, rendered from
  `var.doppler_token` (`server.tf` `local.webhook_doppler_token_env`).
- **Where `var.doppler_token` comes from** — the key `DOPPLER_TOKEN` in `soleur/prd_terraform`,
  mapped to `TF_VAR_doppler_token` by `doppler run --name-transformer tf-var`. So the host's
  full-`prd` token is itself Tier-A readable today. After this change that is harmless for the App
  key, because that token cannot read the new project.
- **Running-host re-delivery channel** — `terraform_data.deploy_pipeline_fix` (`server.tf`) pushes
  `/etc/default/soleur-doppler-token` to web-1 through `push-infra-config.sh` →
  `/hooks/infra-config` (#7095 precedent), with only a `sha256` in `triggers_replace`. It is applied
  by `apply-deploy-pipeline-fix.yml`, whose job declares `environment: infra-privileged` and loads
  credentials through `.github/actions/infra-credentials`. `terraform_data.deploy_pipeline_fix_web2`
  deliberately carries **no** credential file (#7103-B4 — web-2's credentials are birth-frozen).
- **Hosts** — `var.web_hosts` default: `web-1` (cx33, hel1, 10.0.1.10) and `web-2` (cpx22, hel1,
  10.0.1.11, cattle standby). `hcloud_server.web` has `ignore_changes = [user_data, ...]`.
- **Prior art for an isolated host-read project** — `soleur-inngest` (`inngest-host.tf`),
  `soleur-registry` (`zot-registry.tf`), `prd_git_data`/`prd_workspaces_luks` configs, and the
  Tier-B nested root `apps/web-platform/infra/git-data-root-key/` (partial backend on
  `soleur-terraform-state-privileged`, mints into the separate project `soleur-git-data-root`,
  applied only by `apply-git-data-root-key.yml`). The inngest/registry boot tokens are minted in the
  web-platform root, i.e. into Tier-A-readable state — acceptable for them (ADR-241 R2), **not** for a
  token that reads this key.
- **App permissions** (`apps/web-platform/infra/github-app-manifest.json`): `actions`,
  `administration`, `checks`, `contents`, `issues`, `pages`, `pull_requests`, `secrets` = write.
- **The other soleur-ai key.** `prd_terraform` holds a *distinct* soleur-ai private key (ADR-241 M3)
  that #8209 O10 shadows with `EVICTED_SEE_ADR_241` and O13 deletes in App settings. O10 is held on
  #9262. Until both are done, a Tier-A reader still obtains **a** soleur-ai key with
  `administration:write` — see Reconciliation row 5.

### Institutional learnings applied

- `security-issues/2026-07-07-doppler-branch-config-does-not-isolate-secrets.md` — only a separate
  Doppler **project** isolates; the mechanism choice rests on it.
- `security-issues/2026-05-26-doppler-secrets-delete-dumps-full-config-to-stdout.md` — the eviction
  `doppler secrets delete` must send stdout to `/dev/null`, or it prints the whole `prd` config into
  the operator's terminal/log.
- `security-issues/2026-09-25-doppler-token-rotation-with-a-secret-consumer-and-revoke-first-removes-the-blanket-ack.md`
  — mint-new-before-revoke-old ordering for the read token.
- `2026-07-07-immutable-redeploy.md` — a `-replace` must `-target` the dependents
  (`hcloud_server_network`, `hcloud_volume_attachment`, `hcloud_firewall_attachment`) and may boot
  with the private NIC down; applies to the web-2 replace.
- `2026-05-20-github-app-installation-grant-vs-manifest-three-plane-drift.md` — permissions are not
  touched here, so no re-approval is triggered; keep it that way.
- `2026-03-19-github-ruleset-stale-bypass-actors.md` — the soleur-ai App stays a bypass actor on the
  marketplace ruleset; the drift job keeps watching it (detective control, unchanged).
- `2026-07-10-shared-vendor-key-fingerprint-attribution-and-required-iac-secret-apply-gate.md` and
  ADR-241 U2 — the two App keys are distinguishable only by DER-SHA-256 fingerprint; compare before
  the delete click, prove the runtime after it.
- `2026-05-15-token-namespace-divergence-across-secret-stores.md` — tier by measured reach, never by
  name; the census must key on what a job references.

### Functional overlap

`soleur:engineering:discovery:functional-discovery` queried three registries; nothing covers moving
a secret between Doppler projects by token reach, hash-bound boot-token delivery, or GitHub App key
rotation. Nothing installed. No stack gap (TypeScript/Terraform/shell are covered).

### CLAUDE.md / AGENTS.md conventions carried

`hr-prod-host-config-change-immutable-redeploy`, `hr-fresh-host-provisioning-reachable-from-terraform-apply`,
`hr-tf-variable-no-operator-mint-default`, `hr-menu-option-ack-not-prod-write-auth` (every prod write
and dispatch gets its own per-command go-ahead), `hr-no-ssh-fallback-in-runbooks`,
`hr-observability-layer-citation`, `hr-github-app-auth-not-pat`, `cq-silent-fallback-must-mirror-to-sentry`,
`wg-architecture-decision-is-a-plan-deliverable`. Dated records (legal audits, breach register,
ADR amendment logs) are append-only.

## Problem Statement

ADR-241 made a Tier-B credential reachable only from `main`, through environment secrets whose
deployment-branch policy admits `main` alone. That boundary is enforced by GitHub, and GitHub lets
any identity with `administration:write` on the repository rewrite the policy. The soleur-ai App
has that permission, and its runtime key sits in the one Doppler config every branch-reachable token
inherits from. So the boundary's own enforcement is inside the blast radius, which is why D2 is
`proposed`, ADR-220 D2–D3's #8209 limb is unsatisfied, and #8211's real cutover is blocked.

The blast radius is larger than the boundary. The same key mints installation tokens carrying
`contents`, `actions`, `secrets`, `administration` and `pull_requests` write on every repository a
connected user granted — including two installations outside `jikig-ai`. The exposure is
reachability-only (no evidence of use), but it has existed since the key was added to `prd`, and
Doppler's version history keeps the old value even after a delete. Moving the key without rotating
it would therefore close nothing against a copy already taken.

## Proposed Solution

### Architecture

```text
BEFORE                                         AFTER
Doppler soleur/prd  (root)                     Doppler soleur/prd  (root)
  GITHUB_APP_ID                                  GITHUB_APP_ID            (public; unchanged)
  GITHUB_APP_PRIVATE_KEY  <-- every prd/prd_*    (key absent)
     reader, any branch
                                               Doppler soleur-github-app/prd  (NEW PROJECT)
                                                 GITHUB_APP_PRIVATE_KEY           (NEW key, rotated)
                                                 GITHUB_APP_PRIVATE_KEY_RETIRED   (old key, R0 -> R7 only)
                                                    ^ read-only service token "web-host-github-app-read"
                                               Doppler soleur-infra-privileged/prd (Tier B)
                                                 GITHUB_APP_RUNTIME_DOPPLER_TOKEN
                                                    | infra-credentials loader (always exports the
                                                    |  name, empty when absent), main-only envs
                                                    v TF_VAR_github_app_runtime_doppler_token
                                               web-platform root: one conditional line in the
                                                 existing soleur-doppler-token.tmpl render
                                                 -> cloud-init (fresh web hosts; state keeps a hash)
                                                 -> deploy_pipeline_fix push (running web-1; sha256 trigger)
                                               web host /etc/default/soleur-doppler-token
                                                 GITHUB_APP_DOPPLER_TOKEN=dp.st...  (new line)
                                                 -> ci-deploy.sh (parent shell) / boot: prd download,
                                                    then overlay of exactly one name from the project
                                                 -> canary probe: App JWT -> GET /app -> 200, slug soleur-ai
                                                 -> container env (unchanged shape)
```

**Remaining readers of the new key once the sequence completes:** the web host (its credential
file, units that load that file, and the container env — the same class as today's full-`prd`
token, recorded in D10); every Tier-B job, because the loader exports the whole Tier-B project into
`$GITHUB_ENV` (they hold the *token*, not the key; recorded in D10 next to ADR-241 A3); Doppler
workplace administrators and `DOPPLER_TOKEN_TF` (a workplace personal token that reads every
project). **`DOPPLER_TOKEN_TF` is still in branch-reachable `prd_terraform` until #8209 O10, and a
copy taken before O10 could mint a service token on the new project that outlives O13's
revocation** — which is why R1 (the new key's birth) is gated on O10 and O13's
`DOPPLER_TOKEN_TF` revocation, and R8 lists the project's tokens after O13.

### Implementation Phases

#### Phase 0 — Settle the facts the design rests on (before any test)

0.1 **Budget.** Add a synthesized 60-character `dp.st.prd.<random>` value for the new variable to the
    fixture of `plugins/soleur/test/cloud-init-user-data-size.test.ts` and run it against
    `WEB_GZIP_BUDGET` (`const WEB_GZIP_BUDGET = 23_580` in that file). If it does not fit, move the
    two comment lines of `soleur-doppler-token.tmpl` into the `server.tf`
    `local.webhook_doppler_token_env` prose (they are the only non-functional bytes in that render)
    and re-measure; if it still does not fit, stop and bring the measured overage back to planning.
0.2 **Encoding (measured at plan time).** `doppler secrets download --no-file --format docker` emits a
    multi-line PEM as **one** line with escaped `\n` and no continuation lines — measured 2026-09-30
    against `soleur/dev`, Doppler CLI v3.76.6, counts only: `keyline=1 bare_pem_lines=0
    escaped_n_in_keyline=1`. The host pins v3.75.3; repeat the count with that version. The Guard 7
    stub emits exactly this shape.
0.3 **State residency (measured at plan time).** The locked `hetznercloud/hcloud` provider is 1.63.0
    (`apps/web-platform/infra/.terraform.lock.hcl`); its binary contains
    `internal/server.userDataHashSum`, i.e. `hcloud_server.user_data` is stored in state as a hash,
    not the value. `terraform_data.deploy_pipeline_fix.triggers_replace` is a `sha256`. So the token
    never reaches Tier-A-readable state through either path. Re-check the lockfile version at work
    time; a provider bump that drops the hashing invalidates this design.
0.4 **Canary network path.** Confirm the canary container can reach `api.github.com` (the app already
    calls it; confirm the canary is not on a narrower egress rule) — `apps/web-platform/infra/cron-egress-allowlist.txt`
    and the canary `docker run` flags in `ci-deploy.sh`.

#### Phase 1 — Guards first (RED before GREEN)

1.1 `tests/scripts/test-infra-privileged-tier-census.sh` gains **Guard 6** (rows below), following
    the file's conventions (instrument self-test, floors, `mutant_red` rows, input-tree seam).
1.2 `apps/web-platform/infra/ci-deploy.test.sh` gains the overlay and canary-probe scenarios
    (Guard 7) with a stubbed `doppler` that records `--project/--config` per call and emits the
    Phase 0.2 shape, and a stubbed probe.
1.3 `apps/web-platform/infra/cat-deploy-state.test.sh` gains the `github_app_key_source` field.
1.4 `apps/web-platform/infra/web-host-provisioner-parity.test.sh` §1 keeps web-2's credential
    denylist intact (no change expected — the new line rides the file web-2 does not receive in
    place; assert it).

#### Phase 2 — Terraform: container, variable, render

2.1 **New file** `apps/web-platform/infra/github-app-runtime-project.tf`: `doppler_project
    "github_app_runtime"` (`name = "soleur-github-app"`, description ≤ 255 chars —
    `scripts/lint-doppler-description-length.py`) and `doppler_environment
    "github_app_runtime_prd"` (`slug = "prd"`, `name = "Production"`), both `prevent_destroy`,
    mirroring `infra-privileged-environment.tf` (`resource "doppler_project" "infra_privileged"`,
    `resource "doppler_environment" "infra_privileged_prd"`). **No `doppler_secret`, no
    `doppler_service_token`, no `data "doppler_secret(s)"`** — the header comment says why (ADR-241
    D3); census G6c enforces it.
2.2 `.github/workflows/apply-web-platform-infra.yml`: the push apply is `-target=`-scoped (it lists
    `-target=doppler_project.infra_privileged` / `-target=doppler_environment.infra_privileged_prd`),
    so the two new addresses join that list; sweep every suite that asserts the list
    (`git grep -ln -e '-target=' tests/ scripts/ apps/web-platform/test/ apps/web-platform/infra/`).
    This workflow edit makes PR-A UNTRUSTED-CI (auto-merge only).
2.3 `apps/web-platform/infra/variables.tf`: `variable "github_app_runtime_doppler_token"`
    (`type = string`, `sensitive = true`, `default = ""`), no `validation` block (it would echo the
    value — see the `variable "doppler_token"` comment).
2.4 `apps/web-platform/infra/soleur-doppler-token.tmpl`: one conditional line,
    `%{ if github_app_doppler_token != "" }GITHUB_APP_DOPPLER_TOKEN=${github_app_doppler_token}` +
    newline + `%{ endif }`, so an empty variable renders **byte-identical** content. `server.tf`
    passes the variable into the `templatefile()` call of `local.webhook_doppler_token_env`. Nothing
    else in the delivery chain changes: the rendered file already feeds cloud-init (fresh hosts), the
    `deploy_pipeline_fix` trigger hash and `SOLEUR_DOPPLER_TOKEN_B64` (web-1), and the installer
    already admits `/etc/default/soleur-doppler-token`. **Do not edit `infra-config-apply.sh`,
    `infra-config-install.sh` or `hooks.json.tmpl`**: any of them re-fires
    `terraform_data.infra_config_handler_bootstrap`'s root remote-exec on web-1 at merge, and the
    single-line carrier needs none of them.
2.5 `server.tf` `terraform_data.deploy_pipeline_fix`: add a `precondition` — the variable is empty
    **or** matches `^dp\.st\.[A-Za-z0-9._-]{20,}$`; the error message never contains the value.
    Rollback is SSH-free by construction: an empty variable plus a re-push re-renders the file
    without the line.
2.6 `.github/actions/infra-credentials/action.yml`: **always export**
    `TF_VAR_github_app_runtime_doppler_token` into `$GITHUB_ENV` (empty when the Tier-B project has no
    such key), so the `prd_terraform` legacy arm — writable by `DOPPLER_TOKEN_WRITE` until #8209 O11 —
    can never supply it under `--preserve-env` (architecture review P1-2). Census row G6f.
2.7 `terraform_data.deploy_pipeline_fix_web2`: **unchanged** (web-2's credentials stay
    birth-frozen, #7103-B4; web-2 gets the line only through R5's replace).

#### Phase 3 — Host: overlay, key-source record, canary probe

3.1 `apps/web-platform/infra/ci-deploy.sh`: add `GITHUB_APP_DOPPLER_TOKEN` to the key allowlist of
    the existing guarded `while IFS='=' read` loop over `/etc/default/soleur-doppler-token`. Read it
    into a local variable; **do not export it** (the container must never see it).
3.2 **Overlay in the parent shell.** `ENV_FILE=$(resolve_env_file)` runs in a subshell, so nothing it
    sets reaches the caller (Kieran P0-2). Add `overlay_github_app_key "$ENV_FILE"`, called by the
    parent right after that line:
    - **Token present:** `DOPPLER_TOKEN="$GITHUB_APP_DOPPLER_TOKEN" doppler secrets download
      --no-file --format docker --project soleur-github-app --config prd`, keep **only** lines
      matching `^GITHUB_APP_PRIVATE_KEY=` (anchored, so `GITHUB_APP_PRIVATE_KEY_RETIRED=` never
      passes), drop every `^GITHUB_APP_PRIVATE_KEY=` line from the `prd` output, append the isolated
      one. Isolated wins by construction. `GITHUB_APP_KEY_SOURCE=isolated`.
    - **Token present, fetch fails or yields no key line:** keep what `prd` supplied,
      `GITHUB_APP_KEY_SOURCE=prd`, and emit a Sentry **error** with `reason=fetch_failed`. Not
      fatal here: before R6 the `prd` key is still valid, so this degrades to today and is loud;
      after R6 `prd` has no key and the next check refuses. One rule, both states.
    - **Token absent:** keep the `prd` value, `GITHUB_APP_KEY_SOURCE=prd`, log it (no Sentry: it is
      the expected pre-R3 state, not a fallback — spec-flow P2-11).
    - The source value is written to deploy state (`cat-deploy-state.sh` prints
      `github_app_key_source=`). No fingerprint is computed on the host (review cut: `source=isolated`
      already proves the R1 key, which is the only key the project ever holds under that name).
3.3 **Key check before the swap, in the canary stage.** Two layers, both before promotion, both
    leaving the running container serving on failure:
    - **Presence (no network):** the env-file holds exactly one `^GITHUB_APP_PRIVATE_KEY=` line and
      its value is not `EVICTED_SEE_ADR_241`; else `CANARY_FAIL_REASON=github_app_key_missing`.
    - **Acceptance (the invariant, not a proxy):** `docker exec soleur-web-platform-canary node
      /app/scripts/github-app-key-probe.mjs` — a new standalone script (`node:crypto` RS256 +
      `fetch`, no app imports), copied into the image exactly as `scripts/sandbox-canary.mjs` is
      (`apps/web-platform/Dockerfile`, the `COPY --from=builder /app/scripts/sandbox-canary.mjs`
      line) and run the way `ci-deploy.sh` already runs that canary. It signs an App JWT with the
      canary's own `GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY`, applying the same `\n` unescape as
      `server/github/app-private-key.ts` `normalizeAppPrivateKey()` (a parity test pins the two), and
      calls `GET /app`. `200` with
      `slug == "soleur-ai"` passes; `401`/`403`/`404` or any other slug fails with
      `CANARY_FAIL_REASON=github_app_key_rejected`; a transport error or `5xx` emits a Sentry warning
      and passes (a GitHub outage must not block deploys). Script absent (an image older than PR-A)
      → skip with a log line. This catches a wrong-but-valid PEM (the dev key, the `prd_terraform`
      key, a planted token's key) that a shape check would wave through (spec-flow P0-1,
      architecture P1-2, Kieran P1-7).
    - Register the probe in `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`
      per its "Adding a new probe" section.
3.4 **Boot path** (`apps/web-platform/infra/soleur-host-bootstrap.sh` `soleur-doppler-download`, used
    by `cloud-init.yml` before the first `docker run`): the same overlay as a **byte-identical block
    between sentinel markers** in both files (CTO devex review: byte equality, not a fuzzy
    normalised comparison), pinned by Guard 7 row 7.6. After `docker run`, run the same probe via
    `docker exec soleur-web-platform` and emit its verdict and `github_app_key_source` with the host
    name through the existing `soleur-boot-emit` channel (Sentry + Better Stack) — this is how R5/R7
    read web-2 without SSH (spec-flow P0-2). A rejected key at boot emits at `fatal`.
    Two copies rather than one shared file: `soleur-host-bootstrap.sh` is baked into the image and
    hash-checked via `local.host_scripts_content_hash`, while `ci-deploy.sh` is pushed through the
    FILE_MAP; a shared file would need both channels plus `DEPLOY_PIPELINE_FIX_TRIGGERS`.
3.5 New `apps/web-platform/scripts/github-app-key-status.sh` (≤ 30 lines, discoverability): signs a
    GET to `/hooks/deploy-status` the way `scripts/inngest-host-state.sh` does and prints only the
    `github_app_key_source=` line.

#### Phase 4 — Records (PR-A)

4.1 **ADR-241** via `soleur:architecture`: ADR-241 has **no** `## Amendment log` yet — create it with a
    dated 2026-09-30 (#8609) entry. Add **D10 — the runtime App key lives in `soleur-github-app`**
    (mechanism; rotation on the move; A11's "immutable redeploy" superseded for web-1 by the
    Terraform-declared credential push until #6730 closes; residuals: host/container/unit-env and
    Hetzner-metadata exposure, the loader exporting the token to every Tier-B job,
    `DOPPLER_TOKEN_TF` and workplace admins). Add a **D10 row to the Statuses table**
    (`adopting` → `accepted` when R7/R8 pass). D9 R1 → "CLOSING — mechanism merged; closes when the
    old key's JWT gets `401`, the App lists exactly one key, and the project lists exactly one
    token after #8209 O13". New D9 row **R8** (webhook/client secrets). Annotate A11 "superseded by
    D10" without rewriting it. D2 stays `proposed`.
4.2 **Runbook** `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`:
    new section "Runtime App key (#8609)" carrying the canonical R-table below, plus
    **"Routine rotation (steady state)"**: R0 → R1 → release → web-2 replace → R7 (R2, R3, R6 are
    one-time), and a rotation cadence for the read token (rotate it with each key rotation,
    mint-new-before-revoke per the 2026-09-25 token-rotation learning). Append dated notes to the
    O0 U1 row and O13(b) — both read `GITHUB_APP_PRIVATE_KEY -p soleur -c prd`, and O13's rollback
    writes a key back to `prd`; after R6 those reads point at `soleur-github-app` (Kieran P1-6).
    The "Residual R1, stated up front" paragraph gets a dated note, not a rewrite.
4.3 **Operator bootstrap script** via `soleur:operator-bootstrap` (required by
    `hr-multi-step-post-merge-bootstrap-script`; ADR-228): stages R0–R8 on
    `plugins/soleur/scripts/lib/operator-script.sh`, one per-command go-ahead each, each prompt
    opening with one plain sentence on what users would notice if the step fails and what the
    rollback is (R7: "no rollback"). The script links the runbook as canonical and does not restate
    it. It also runs the per-step verifications and prints PASS/FAIL per check.
4.4 **C4** (`knowledge-base/engineering/architecture/diagrams/model.c4`): amend the `doppler ->
    hetzner` edge to name the isolated `soleur-github-app` project read by the web host's dedicated
    token, and the `github -> doppler` Tier-B edge to name the new Tier-B key. Run
    `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and
    `plugins/soleur/test/c4-count-parity.test.sh`.
4.5 **Legal, PR-A (through the CLO agent), time-sensitive only:** new dated record
    `knowledge-base/legal/audits/2026-09-30-8609-runtime-app-key-exposure-assessment.md`
    (REACHABILITY-ONLY; K0–K4; awareness anchor 2026-09-22); an appended pointer `## Addendum —
    2026-09-30 (#8609)` on `2026-09-8209-prior-exposure-assessment.md`, worded as conditional;
    `breach-register.md` new index row plus a note under the #8209 row; `compliance-posture.md` R1
    → IN-PROGRESS (#8609) and a new evidence-limb row carrying the deadlines (K0 before any key
    delete; K1 before the 90-day Actions retention), with a dated log comment. The Article-30
    markers and the closures land once, in PR-B, stated as fact (review cut: no write-twice).
4.6 **Deferral issues** (created in the work phase; milestone from `knowledge-base/product/roadmap.md`):
    (a) move `GITHUB_APP_WEBHOOK_SECRET` minting out of the web-platform root, then it and
    `GITHUB_CLIENT_SECRET` into `soleur-github-app` — re-evaluate when #8610 lands; (b) a web-host
    nftables drop of `169.254.169.254` that also covers forwarded Docker traffic (the token now sits
    in web `user_data`; git-data already drops it, #7772) — re-evaluate at the next web-host
    hardening pass.
4.7 `plugins/soleur/test/preflight-discoverability-test.test.ts`: `BASELINE_DECLARED_PROBES` +1 from
    `origin/main`'s value at work time, with a PLACEMENT / TRUTH / NO-SUBSTITUTE comment (this plan
    declares `credentials_required`).

#### Phase 5 — PR-B (after R7 and R8)

5.1 ADR-241: D2 → `accepted` and D10 → `accepted` in the Statuses table, the PR body stating why (R1
    closed with the measured probes; R7 closed at O5b); R1 → "CLOSED <date>"; frontmatter `status:`
    recomputed as the least-advanced decision; a dated Amendment-log entry.
5.2 ADR-220: a dated Amendment-log entry recording that the #8209 limb of D2–D3 is satisfied (the row
    still waits on #7226/ADR-237 and #8211).
5.3 Runbook, `compliance-posture.md` (R1 CLOSED on the old-key deletion date), the assessment's
    closure addendum, and the Article-30 register (Cross-Cutting "Secrets management" and PA-12
    §(g)(3)) — all through the CLO agent, append-only on dated records. Sweep `knowledge-base/legal/`
    for the R1 nouns (`runtime key`, `R1`, `#8609`, `GITHUB_APP_PRIVATE_KEY`, `NOMINAL`) so no
    future-tense sentence about the mechanism survives the flip.
5.4 `Closes #8609` in the PR body (not the title).

### Operator Sequence (R0–R8) — the canonical copy moves to the runbook in PR-A

Every step that writes to production or dispatches a production workflow is shown as the exact
command and runs only after its own go-ahead (`hr-menu-option-ack-not-prod-write-auth`). No secret
value is printed; every `doppler secrets set`/`delete` ends `>/dev/null` and is verified by a
separate read that prints a hash comparison or a count.

**Gate before R1:** #8209 O10 is done (`DOPPLER_TOKEN_TF` gone from `prd_terraform`) **and** O13's
`DOPPLER_TOKEN_TF` rotation is done (the old personal token revoked). Before that, the new key would
be branch-reachable at birth through `DOPPLER_TOKEN_TF` (architecture review P0). PR-A may merge and
R0 may run before the gate.

<!-- lint-infra-ignore start: GitHub exposes no API to list, generate or delete an App private key; these rows name the one gated page action each and automate everything around it -->
| Step | What | Mechanism | Verification (pass condition) | Rollback |
|---|---|---|---|---|
| R0 | **Key inventory (K0) and park the old key.** Read every private-key row on the App settings page (fingerprint, added date). Pipe `soleur/prd` `GITHUB_APP_PRIVATE_KEY` straight into `doppler secrets set GITHUB_APP_PRIVATE_KEY_RETIRED -p soleur-github-app -c prd --silent >/dev/null` (no file on disk). Compute the DER-SHA-256 fingerprints of the `prd` and `prd_terraform` values in memory | Playwright read of the App page; Doppler CLI; `openssl pkey -pubout -outform DER \| openssl dgst -sha256 -binary \| base64` | Every row maps to a holder. **Stop** if the `prd` and `prd_terraform` fingerprints are equal (the two configs would not hold distinct keys) or if a row is unmapped (breach triage) | delete the parked name |
| R0b | **Evidence limbs K1–K3 (CLO, read-only).** Non-`main` run census naming a `prd`-reading token (ids/counts only), Doppler access-log retention and entries for `soleur/prd*`, org audit log for `soleur-ai[bot]` admin actions | `gh api` + Doppler CLI activity logs | Recorded in the new assessment; `API-UNAVAILABLE` is INCONCLUSIVE, not clean | n/a |
| R1 | **New key into the isolated project** (after the gate). Generate a key on the App page (the gated click), then `doppler secrets set GITHUB_APP_PRIVATE_KEY -p soleur-github-app -c prd --silent < "$PEM" >/dev/null`; `shred -u "$PEM"` (an EXIT trap shreds on abort) | Playwright to the click; Doppler CLI | The fingerprint of the value read back from Doppler equals the new row's fingerprint on the App page; a JWT signed with it gets `200` from `GET /app` with `slug=soleur-ai` | delete the new row + the secret |
| R2 | **Read token into Tier B.** `doppler configs tokens create web-host-github-app-read -p soleur-github-app -c prd --access read --plain \| doppler secrets set GITHUB_APP_RUNTIME_DOPPLER_TOKEN -p soleur-infra-privileged -c prd --silent >/dev/null` | Doppler CLI, piped | With the stored value: the key it reads has R1's fingerprint (prints `equal`), and a read of `soleur/prd` with it is refused (not `200`) | revoke the token; delete the Tier-B name |
| R3 | **Deliver to web-1.** `gh workflow run apply-deploy-pipeline-fix.yml --ref main -f reason=8609-github-app-token` | Tier-B job, `environment: infra-privileged` | Run green; the infra-config state shows `/etc/default/soleur-doppler-token` delivered with a new content hash | set the Tier-B name empty and re-dispatch: the file re-renders without the line (SSH-free) |
| R4 | **Ship on the new key.** `gh workflow run web-platform-release.yml --ref main -f bump_type=patch` | release → `ci-deploy.sh` | `github-app-key-status.sh` prints `github_app_key_source=isolated`; the canary probe passed (deploy state); `cron/github-app-drift-guard.manual-trigger` via `soleur:trigger-cron` clean; `cron/oauth-probe.manual-trigger` clean; `GET /app/installations` with the new key lists three installations; one installation-token mint on `jikig-ai` | R3 rollback + release (source falls back to `prd`, still valid) |
| R5 | **Replace standby web-2 from `main`.** Preconditions: the `latest` web image was built after PR-A merged (R4's release); cpx22 in stock in hel1. `gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=web-host-replace -f web_host_key=web-2 -f confirm=REPLACE-web-2 -f reason=8609-github-app-token` | Tier-B job, reviewer-gated `web-platform-infra-apply` | web-2's boot emit (Sentry/Better Stack, host `web-2`) shows `github_app_key_source=isolated` and probe `ok`; private NIC reachable per the immutable-redeploy learning | web-2 is cattle; re-replace |
| R6 | **Evict from `prd`.** Pre-check AC-R6a, then `doppler secrets delete GITHUB_APP_PRIVATE_KEY -p soleur -c prd --yes >/dev/null` | Doppler CLI | Every `prd`/`prd_*` config in `apps/web-platform/infra/doppler-config-inventory.txt` returns not-found, except `prd_terraform` (its own sentinel/override, #8209); raw `prd` values hold no `${soleur-github-app.` reference (count only); Doppler syncs on `prd` listed; a fresh release is `isolated` and the R4 probes pass | restore a key to `prd` from the isolated project — this **burns** the new key (it is branch-readable again): restart at R1 with a fresh key; PR-B may not cite a burned key |
| R7 | **Kill the old key at GitHub.** Preconditions: a release **other than R4's** has shipped on `isolated`; web-1 (deploy state) and web-2 (boot emit) both report `isolated` + probe `ok` after R6; the row's fingerprint equals R0's `prd` fingerprint, **differs** from R1's, and **differs** from R0's `prd_terraform` fingerprint. Delete that row (the gated click) | Playwright to the click | A JWT from the new key → `200` (`slug=soleur-ai`); a JWT from `GITHUB_APP_PRIVATE_KEY_RETIRED` → `401`; then delete the parked name; drift-guard clean; the Sentry per-installation mint-failure query stays quiet for 1 h | **none** — a wrong delete disconnects every user. Short recovery: generate a key → `doppler secrets set` into the isolated project → release (R3 is not needed; the token is unchanged) |
| R8 | **Gate for PR-B** (after #8209 O13's App-key delete) | Playwright read; Doppler CLI/API | The App lists exactly one key, equal to R1's fingerprint; `doppler configs tokens -p soleur-github-app -c prd --json \| jq -r '.[].name'` prints exactly `web-host-github-app-read`; the project's member list holds no service account or group | n/a |
<!-- lint-infra-ignore end -->

**Automation status of the App-page steps (R0, R1, R7, R8):** GitHub has no REST endpoint to list,
generate or delete an App's private keys. `automation-status: UNVERIFIED — soleur:work MUST run a
Playwright attempt before any operator handoff.` The attempt opens the App's settings page (resolve
the URL from `GET /app` `html_url`) and records `playwright-attempt: navigated <URL>; reached <named
human gate>` — GitHub's sudo-mode re-authentication (password, TOTP or passkey) is the expected gate
for generate and delete; R0 and R8 are reads and should complete without one. If the Playwright MCP
server is unreachable (it was during this planning session), the fallback is the operator opening
the page, reading the fingerprints into the script's prompt, and making the single click.

Order: R0 before R1 and R7 (a delete destroys the "added" date); R0b's K1 before the 90-day Actions
retention; the gate before R1; R1 → R2 → R3 → R4 → R5 → R6 → R7 strictly; R8 before PR-B.
Installation tokens minted before R7 are expected to stay valid until their ~1 h expiry; R7's 1-hour
mint-failure watch is what confirms it rather than assumes it.

## Alternative Approaches Considered

| # | Alternative | Why not |
|---|---|---|
| 1 | Re-scope `DOPPLER_TOKEN_PRD` (and the other `prd` readers) to main-only environment secrets | The reader set includes `DOPPLER_TOKEN` (`prd_terraform`), which PR plans need from branches, and grows with every branch config (#6167). Moving the key covers all readers at once |
| 2 | Sentinel overrides in every `prd_*` config | Fails open on the next new branch config |
| 3 | Strip `administration:write`, or remove `jikig-ai/soleur` from the installation | Breaks `cron-gh-pages-cert-reissue` (`PUT /pages` on this repo) and `createRepoForOrg`; leaves the two third-party installations reachable |
| 4 | A new runtime App | Every connected user reinstalls |
| 5 | Terraform-mint the read token in the web-platform root (the `soleur-inngest` pattern) | That state is Tier-A readable — ADR-241 D3 |
| 6 | Terraform-mint it in a nested root on the privileged bucket, writing into `soleur-infra-privileged` | The web-platform root still takes it as a variable to deliver it; a whole root and a Doppler write buy no property (CTO F1) |
| 7 | Immutable `-replace` of web-1 | No automated web-1 birth path exists (#6730); the Terraform-declared push is the codified credential channel |
| 8 | Move the key without rotating | Old copies (and Doppler's version history) stay valid |
| 9 | Doppler Team plan + OIDC | Branch configs still inherit; ADR-241 A1 cost decision |
| 10 | A separate `/etc/default/soleur-github-app-token` file | Needs new FILE_MAP/`hooks.json`/installer/gate entries (each re-fires a root remote-exec on web-1 at merge), cannot be removed without SSH once delivered, and costs more `user_data` bytes. Its one benefit — keeping the token out of the eight units that load the existing file — protects against a host compromise that already reaches the key today (Kieran P0-1, simplicity review) |
| 11 | Fail the deploy when the isolated fetch fails | With no SSH-free way to remove a delivered token, a revoked token would fail every deploy; falling back to the still-valid `prd` key until R6 keeps rollback live (advisor) |
| 12 | A committed key fingerprint checked by a shape gate, or a residency grep over state | The fingerprint is replaced by a stronger check — GitHub itself accepting the key for `slug=soleur-ai`; the residency grep could not see a gzip+base64 `user_data` and was replaced by the measured provider fact (Phase 0.3) (DHH, simplicity) |

## Non-Goals

- **#9262** (re-tier the two `prd_terraform` App-key minters) and **#8209 O10/O13** — separate work.
  This plan *gates* R1 on O10 + O13's `DOPPLER_TOKEN_TF` rotation, and PR-B on O13's App-key delete.
- **`GITHUB_APP_WEBHOOK_SECRET` and `GITHUB_CLIENT_SECRET`** — deferral issue 4.6(a). The webhook
  secret is minted by `random_id.github_webhook_secret` in branch-readable web-platform state
  (`github-app.tf`), so moving its Doppler copy closes nothing until its minting moves. ADR-241 D9 R8.
- **Host, container or metadata-endpoint compromise.** The PEM stays in the web container's env, the
  token in the web host's credential file (loaded by eight units) and in web `user_data` (served to
  host processes by the Hetzner metadata endpoint; an SSRF in the app could reach it). Same class as
  today's full-`prd` token; recorded in D10; the metadata drop is deferral issue 4.6(b).
- **App permission reduction** (Alternative 3).

## User-Brand Impact

- **If this lands broken, the user experiences:** their GitHub connection stops working — the
  dashboard cannot list or open their repositories, agent runs cannot clone, push or open PRs, and
  inbound GitHub webhooks for their installation are rejected. Worst case (R7 deletes the wrong
  key): every connected user at once, with no rollback, until a new key is generated and released.
- **If this lands broken (partial), the user experiences:** a release refuses at the canary
  (`github_app_key_missing` / `github_app_key_rejected`) and the previous release keeps serving —
  users see a stale release, not an outage. A failover to a web-2 that R5 did not replace would
  serve a key R7 has killed.
- **If this leaks, the user's data and workflow are exposed via:** the read token for
  `soleur-github-app` reaching any branch-readable surface (Tier-A Doppler config, repository secret,
  Tier-A-readable state, a plan artifact, a log) — or `DOPPLER_TOKEN_TF` still being branch-reachable
  when the new key is born — which re-creates the path this plan removes, to a key that writes to
  users' repositories.
- **If this leaks (prior exposure):** a copy of the old key taken during the reachable window keeps
  working until R7 — closed only by R7's `401` probe.
- **Brand-survival threshold:** `single-user incident`

`requires_cpo_signoff: true` — CPO sign-off **GRANTED** at plan time (Domain Review).
`soleur:engineering:review:user-impact-reviewer` runs at review time.

## Observability

```yaml
liveness_signal:
  what: "scheduled-github-app-drift-guard Sentry cron monitor (cron-github-app-drift-guard.ts mints an App JWT from the serving container's GITHUB_APP_PRIVATE_KEY and calls GET /app plus the installation-grant diff); per-deploy canary probe verdict; per-boot soleur-boot-emit verdict carrying the host name"
  cadence: "drift-guard: its existing cron schedule; canary: every release; boot emit: every host boot"
  alert_target: "Sentry issue alerts (org jikigai-eu) on the drift-guard monitor and on the host emitter; failed release workflow email for a refused canary"
  configured_in: "apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts (SENTRY_MONITOR_SLUG); apps/web-platform/infra/ci-deploy.sh canary stage; apps/web-platform/infra/soleur-host-bootstrap.sh soleur-boot-emit"
error_reporting:
  destination: "Sentry web-platform project for app-side mint failures; the host emitter (SENTRY_INGEST_DOMAIN/PROJECT_ID/PUBLIC_KEY baked in /etc/default/soleur-doppler-token) for deploy/boot failures"
  fail_loud: "canary CANARY_FAIL_REASON github_app_key_missing or github_app_key_rejected (release fails, old container keeps serving); Sentry error reason=fetch_failed when the token is present but the isolated fetch fails; boot emit at fatal on a rejected key"
failure_modes:
  - mode: "token present but the isolated fetch fails (revoked/mistyped token, Doppler down)"
    detection: "Sentry error reason=fetch_failed from the host emitter + deploy state github_app_key_source=prd; after R6 the same failure also trips the canary (github_app_key_missing)"
    alert_route: "Sentry issue; after R6 also the failed release email"
  - mode: "a wrong but well-formed key reaches the env (dev key, prd_terraform key, a planted token's key)"
    detection: "canary probe GET /app returns 401/403 or a slug other than soleur-ai -> github_app_key_rejected"
    alert_route: "failed release workflow email + Sentry"
  - mode: "serving container on a key GitHub no longer accepts (wrong key deleted at R7)"
    detection: "scheduled-github-app-drift-guard app_jwt 401 + per-installation mint-failure events"
    alert_route: "Sentry issue alert"
  - mode: "a fresh or replaced web host boots without an accepted key"
    detection: "soleur-boot-emit at fatal with host name and probe verdict"
    alert_route: "Sentry issue"
logs:
  where: "journald on the web hosts shipped by vector to Better Stack (ci-deploy.sh LOG_TAG, soleur-boot-emit); GitHub Actions logs for the Tier-B jobs"
  retention: "Better Stack source retention; Actions logs 90 days"
discoverability_test:
  command: "bash apps/web-platform/scripts/github-app-key-status.sh"
  expected_output: "github_app_key_source=isolated"
  credentials_required: "Doppler soleur/prd_terraform read (WEBHOOK_DEPLOY_SECRET for the HMAC plus the CF Access pair) — /hooks/deploy-status is HMAC-gated by design, and no unauthenticated endpoint may disclose which key source a production host runs"
```

## Encryption Posture

```yaml
at_rest:
  - store: "Doppler project soleur-github-app / config prd (doppler_project.github_app_runtime)"
    mechanism: "provider-managed:doppler-aes256-gcm"
    evidence: "scripts/encryption-posture-ledger.json row store=doppler.secrets (attestation_url https://www.doppler.com/security, retrieved_on 2026-07-24) — the new project is covered by that existing row; no new ledger row"
    defends_against: "a Doppler storage-layer disclosure (disk, backup, database snapshot)"
    does_not_defend: "any holder of a token that reads the config (the web host token, DOPPLER_TOKEN_TF, workplace admins), a web-host or web-container compromise, Doppler's own version history of the value"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable:named SOC 2 attestation formalization pending; tracked #6911 (same as the doppler.secrets ledger row)"
  - store: "web host /etc/default/soleur-doppler-token (root disk, 0640 root:deploy) — gains one line"
    mechanism: "plaintext-exception"
    evidence: "apps/web-platform/infra/cloud-init.yml install of /etc/default/soleur-doppler-token and apps/web-platform/infra/infra-config-install.sh dest map — unchanged posture, one more KEY=VALUE line"
    defends_against: "other unprivileged host users (mode 0640 root:deploy)"
    does_not_defend: "root on the host, the eight units that load the file, a disk image/snapshot of the host, the Hetzner metadata endpoint serving user_data to host processes"
    disclosed_as: "not-publicly-claimed"
    live_verification: "available"
in_transit:
  - connection: "web host (ci-deploy.sh / boot) -> api.doppler.com"
    enforced_at: "Doppler CLI v3.75.3 (cloud-init.yml doppler_dl stage, sha256-pinned) — HTTPS only"
    tls: "HTTPS, TLS 1.2+"
    cert_verification: "on"
    does_not_defend: "a compromised host or a leaked read token"
    disclosed_as: "not-publicly-claimed"
  - connection: "canary / boot probe (node fetch) -> api.github.com GET /app"
    enforced_at: "apps/web-platform/scripts/github-app-key-probe.mjs (new; fetch over https with Node's default CA verification)"
    tls: "HTTPS, TLS 1.2+"
    cert_verification: "on"
    does_not_defend: "a compromised container (it already holds the key)"
    disclosed_as: "not-publicly-claimed"
exception:
  justification: "A host boot credential must be readable by the deploy user at boot without an operator; the file already carries the host's full-prd token under the same posture"
  tracking_issue: "#7103"
  reevaluate_when: "#7103 hardens the host credential path, or the workplace moves to Doppler service-account identities (ADR-241 A1)"
  expires_on: "2026-12-29"
```

## Guard Contract

### Guard 6 — runtime App key confinement (census)

**Property.** No branch-reachable surface — a repository secret, a Tier-A Doppler config, a
Terraform resource or data source whose state Tier A reads, a non-Tier-B job, or a plan artifact —
can carry the `soleur-github-app` read token, mint one, or read the new project.

**Assembly.** Every file matched by the census's existing walk (`.github/workflows/*.y*ml`,
`.github/actions/**/action.yml`, every `*.tf` under `apps/web-platform/infra/` and its nested roots,
`infra/github/*.tf`) plus the scripts those jobs invoke through one level of `bash <repo-path>`
indirection. Chokepoints, each a separate row family: (1) the token's names —
`GITHUB_APP_RUNTIME_DOPPLER_TOKEN`, `TF_VAR_github_app_runtime_doppler_token`,
`var.github_app_runtime_doppler_token`; (2) the project literal `soleur-github-app` and the address
`doppler_project.github_app_runtime`; (3) Terraform constructs that put a value in state
(`doppler_service_token`, `doppler_secret`, `data "doppler_secret"`, `data "doppler_secrets"`,
`output`, `nonsensitive(`); (4) Doppler writes of the token name and token mints on the project; (5)
the loader's unconditional export of the token name; (6) `actions/upload-artifact` in a Tier-B job.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| G6a | A job with no `environment:` (or a `pull_request` job) references `TF_VAR_github_app_runtime_doppler_token` after a compliant Tier-B job in the same file | RED |
| G6b | A workflow or script runs `doppler secrets set GITHUB_APP_RUNTIME_DOPPLER_TOKEN` against any `-p soleur` config (not only `prd_terraform`) | RED |
| G6c | Any root declares `doppler_service_token`, `doppler_secret`, `data "doppler_secret"` or `data "doppler_secrets"` on `soleur-github-app` / `doppler_project.github_app_runtime`, or an `output`/`nonsensitive(var.github_app_runtime_doppler_token)` | RED |
| G6d | A workflow or script runs `doppler configs tokens create` with `-p soleur-github-app` | RED |
| G6e | A Tier-B job adds `actions/upload-artifact` with a `tfplan` path | RED |
| G6f | The loader stops exporting `TF_VAR_github_app_runtime_doppler_token` when the Tier-B project lacks it (reorder: export moved after the legacy-arm fallback) | RED |
| G6g | Dispatch: point the census at an input tree with zero workflow files | RED ("0 checked" is a failure) |
| G6h | Harness: replace a row function with one that always passes | RED (instrument self-test) |
| G6p | Must-PASS: the edited `apply-deploy-pipeline-fix.yml` with the token used only inside the loader-driven Tier-B job, steps in a different order from the canonical | PASS |

### Guard 7 — the deploy overlay and canary key check (ci-deploy.test.sh)

**Property.** A container is promoted only with exactly one `GITHUB_APP_PRIVATE_KEY`, taken from
`soleur-github-app` whenever the token is present and the fetch succeeds, and only after GitHub has
accepted that key for `slug=soleur-ai` (or the check could not reach GitHub).

**Assembly.** Two env-file assembly sites — `ci-deploy.sh` (overlay in the parent shell after
`ENV_FILE=$(resolve_env_file)`) and the boot path in `soleur-host-bootstrap.sh` (before the first
`docker run`) — the sentinel-bounded overlay block both carry, and the canary promotion point in
`ci-deploy.sh`. Every overlay row runs against both sites; row 7.6 pins their byte equality.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 7.1 | Overlay appends the isolated line but does not drop the `prd` line (two key lines) | RED |
| 7.2 | Overlay filter unanchored, so `GITHUB_APP_PRIVATE_KEY_RETIRED=` also passes (a second name leaks in) | RED |
| 7.3 | Token present, isolated fetch fails, `prd` holds no key; the canary still promotes | RED |
| 7.4 | Stub returns `EVICTED_SEE_ADR_241` for the key; presence check passes | RED |
| 7.5 | Reorder: overlay runs before the `prd` download (prd wins) | RED |
| 7.6 | The boot-path sentinel block differs by one byte from the ci-deploy block | RED |
| 7.7 | The token value is written into the container env-file | RED |
| 7.8 | Overlay moved back inside `resolve_env_file` (subshell): deploy state never records `isolated` | RED |
| 7.9 | Probe stub returns `401` (wrong key); the canary promotes | RED |
| 7.10 | Probe stub returns `200` with `slug=other-app`; the canary promotes | RED |
| 7.11 | Must-PASS: token absent, `prd` holds a valid PEM, probe `200 soleur-ai` → promotes with `source=prd`, no Sentry event | PASS |
| 7.12 | Must-PASS: token present, both projects hold keys, escaped-`\n` PEM, probe `200 soleur-ai` → isolated wins, one line, promotes | PASS |
| 7.13 | Must-PASS: probe transport error → promotes with a Sentry warning | PASS |

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/github-app-runtime-project.tf` (new): `doppler_project.github_app_runtime`,
  `doppler_environment.github_app_runtime_prd`, both `prevent_destroy`, both added to the push
  apply's `-target=` list. Provider: the existing `DopplerHQ/doppler` pin in `main.tf`.
- `variables.tf`: `github_app_runtime_doppler_token` (sensitive, default `""`). Sourced as
  `TF_VAR_github_app_runtime_doppler_token` from Tier-B `soleur-infra-privileged` by
  `.github/actions/infra-credentials` — which downloads the project with `--format json` and
  lowercases each name into `TF_VAR_*` (not `--name-transformer`), and which now exports this one
  name unconditionally.
- `server.tf` + `soleur-doppler-token.tmpl`: the conditional line and the `deploy_pipeline_fix`
  precondition.

### Apply path

**Does merging PR-A alone mutate production? Yes — the PR body's first line says so**, derived at work
time from each workflow's `on.push.paths` and `-target=` list. Expected: (1)
`apply-web-platform-infra.yml`'s push apply creates the empty `soleur-github-app` project and its
`prd` environment; (2) `apply-deploy-pipeline-fix.yml` re-delivers the changed `ci-deploy.sh` (and any
other FILE_MAP script whose bytes changed) to web-1, with the Tier-B variable still empty so the
credential file is byte-identical; (3) `web-platform-release.yml` fires if the diff touches its
`paths:` (the new probe script and Dockerfile line do), shipping an image whose canary runs the new
probe against the **current** `prd` key. `infra_config_handler_bootstrap` does not re-fire, because
Phase 2.4 edits none of its inputs. All are safe in the legacy state by construction; the merge
click is their authorization. **Pre-merge check:** fire `cron/github-app-drift-guard.manual-trigger`
(per-command go-ahead) — a clean run proves the current `prd` key parses and is accepted, so the new
canary probe will pass at merge.

(b) cloud-init + idempotent re-delivery thereafter: R3 delivers the token to web-1, R5 to web-2.

### Distinctness / drift safeguards

`dev` is untouched (a separate dev App). `hcloud_server.web` keeps `ignore_changes = [user_data]`.
After R3, every Tier-A PR plan renders the variable empty and so shows `deploy_pipeline_fix` as a
replace: expected noise, noted in the PR-plan comment header next to ADR-241 R4.
`scheduled-terraform-drift.yml` keeps planning the environment policies and rulesets (the detective
control stays).

### Vendor-tier reality check

Doppler Developer plan: projects and read service tokens are available; service-account identities
and OIDC are not (ADR-241 A1). GitHub: App private keys can only be listed, generated and deleted on
the App settings page.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-241** (not a new ADR — this closes its own residual): **D10**, a new `## Amendment log`
section with its first dated entry, a D10 row in the Statuses table, R1's status change, new R8,
and the residuals listed in Phase 4.1. D2 and D10 flip only in PR-B. ADR-220 gets a dated
Amendment-log entry in PR-B. No new ordinal is claimed.

### C4 views

Read all three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`
before editing. Checked for this plan: **actors** — connected users (via the App installations,
modeled through `github`), the operator (unchanged); **external systems** — `doppler` (one system;
the new project is a project inside it, described in edge prose the way `soleur-inngest` and
`soleur-registry` already are), `github` (modeled; the canary now calls `GET /app` on it, already
covered by the app's existing GitHub edges), `hetzner` web hosts (modeled); **relationships** —
`doppler -> hetzner` changes (two credentials from two projects), `github -> doppler` gains the new
Tier-B key. No new container. Edit those two edges; run the three C4 tests including
`plugins/soleur/test/c4-count-parity.test.sh`.

### Sequencing

D10 lands `adopting` in PR-A; R1 and D2/D10 change status only in PR-B, after the measured R7/R8
probes.

## Open Code-Review Overlap

3 open code-review issues mention files this plan touches:

- #2197 (billing throttle docs; mentions `infra/server.tf` `count`) — **Acknowledge**: different
  concern (instance-count assumption), untouched by this plan.
- #8735 (infra-validation notify-main-failure misses cancelled jobs) — **Acknowledge**: this plan
  does not edit `infra-validation.yml`.
- #7942 (mutation batteries run in no gate) — **Acknowledge**: unrelated; this plan's mutation rows
  live in suites already registered in `scripts/test-all.sh`.

## Files to Edit

- `apps/web-platform/infra/variables.tf`, `server.tf`, `soleur-doppler-token.tmpl`
- `apps/web-platform/infra/ci-deploy.sh`, `soleur-host-bootstrap.sh`, `cat-deploy-state.sh`
- `apps/web-platform/infra/ci-deploy.test.sh`, `cat-deploy-state.test.sh`, `web-host-provisioner-parity.test.sh`
- `apps/web-platform/Dockerfile` (copy the probe script, as `scripts/sandbox-canary.mjs` is)
- `plugins/soleur/test/cloud-init-user-data-size.test.ts` (fixture gains the variable)
- `plugins/soleur/test/preflight-discoverability-test.test.ts` (`BASELINE_DECLARED_PROBES` +1)
- `.github/actions/infra-credentials/action.yml` (unconditional export of the token name)
- `.github/workflows/apply-web-platform-infra.yml` (`-target=` list) plus every suite asserting that list
- `tests/scripts/test-infra-privileged-tier-census.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`
- `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/legal/audits/2026-09-8209-prior-exposure-assessment.md` (append-only pointer addendum)
- `knowledge-base/legal/compliance-posture.md`, `knowledge-base/legal/breach-register.md`
- PR-B: ADR-241, ADR-220, the runbook, `compliance-posture.md`, `article-30-register.md`, the new assessment (closure addendum)

## Files to Create

- `apps/web-platform/infra/github-app-runtime-project.tf`
- `apps/web-platform/scripts/github-app-key-probe.mjs`
- `apps/web-platform/scripts/github-app-key-status.sh`
- the operator bootstrap script generated by `soleur:operator-bootstrap` (location per that skill)
- `knowledge-base/legal/audits/2026-09-30-8609-runtime-app-key-exposure-assessment.md`

## Dependencies & Prerequisites

- **PR-A:** none beyond `main`. Merge-safe in the legacy state by construction (empty variable →
  byte-identical credential file; the canary probe passes on the current `prd` key, proved by the
  pre-merge drift-guard trigger).
- **R0/R0b:** PR-A merged (the project exists to park the old key in).
- **R1 onward:** #9262 → #8209 O10 (`DOPPLER_TOKEN_TF` out of `prd_terraform`) → #8209 O13's
  `DOPPLER_TOKEN_TF` rotation.
- **PR-B (the D2 flip, `Closes #8609`):** R7 done **and** R8 — which needs #8209 O13's App-key delete,
  so the `prd_terraform` soleur-ai key is dead too. Until then the issue's first acceptance bullet
  is not met.

## Risk Analysis & Mitigation

| Risk | Severity | Mitigation |
|---|---|---|
| Wrong key deleted at R7 | High, no rollback | R0 inventory; fingerprint equality with R0's `prd` fp and inequality with R1's and with `prd_terraform`'s; both hosts proven on `isolated`; a second release shipped first; post-delete probes and a 1 h mint-failure watch |
| New key born while `DOPPLER_TOKEN_TF` is branch-reachable | High | R1 gated on #8209 O10 + O13; R8 lists the project's tokens and members |
| Wrong-but-valid key reaches the env (planted token, dev key) | High | Canary `GET /app` + slug check before promotion; loader always exports the token name so the `prd_terraform` arm cannot supply it |
| web-2 serves a killed key | Medium | R5 before R6; R7 precondition reads web-2's boot emit |
| `user_data` budget overflow | Medium | Phase 0.1 measurement; comment lines move to `server.tf` |
| Merge-time canary refuses the current key | Medium | Pre-merge drift-guard trigger; transport errors pass with a warning |
| Overlay order wrong / subshell loses the source | Low | Guard 7 rows 7.5 and 7.8 |
| Doppler cross-project reference from `prd` | Low | R6 raw-value count check |
| `doppler secrets set/delete` dump a config to the terminal | Medium | `>/dev/null` on every set/delete (a PreToolUse hook blocks either without it) |

## Acceptance Criteria

### Pre-merge (PR-A)

- [ ] AC1 — `github-app-runtime-project.tf` declares the project and `prd` environment with
      `prevent_destroy`, no `doppler_secret`/`doppler_service_token`/data source; description ≤ 255
      chars (`python3 scripts/lint-doppler-description-length.py` green); both addresses are in the
      push apply's `-target=` list and every suite asserting that list is green.
- [ ] AC2 — With the variable empty, the rendered `/etc/default/soleur-doppler-token` content is
      byte-identical to `main`'s, and web `user_data` differs from `main`'s only in
      `host_scripts_content_hash` (render-diff test with that field masked).
- [ ] AC3 — With a synthesized token, `plugins/soleur/test/cloud-init-user-data-size.test.ts` is green
      against `WEB_GZIP_BUDGET`, and the render carries the `GITHUB_APP_DOPPLER_TOKEN=` line.
- [ ] AC4 — Guard 6 rows G6a–G6p and the instrument self-test behave as tabulated; suite green on the
      PR head.
- [ ] AC5 — Guard 7 rows 7.1–7.13 behave as tabulated against both assembly sites.
- [ ] AC6 — `terraform validate` and the PR plan job green; the PR plan shows no replace of any
      `hcloud_server`.
- [ ] AC7 — ADR-241 carries a new `## Amendment log` section with a dated entry, D10, a D10 row in the
      Statuses table, R1 "CLOSING", R8, A11 annotated, and D2 still `proposed`;
      `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` green.
- [ ] AC8 — The runbook carries the R-table as the canonical copy, the "Routine rotation (steady
      state)" subsection, and dated notes on O0 U1 and O13(b); `canary-probe-set.md` registers the
      probe.
- [ ] AC9 — The operator bootstrap script exists, sources `plugins/soleur/scripts/lib/operator-script.sh`,
      and has one stage per R-step with a per-command go-ahead.
- [ ] AC10 — C4 edits made; `c4-code-syntax.test.ts`, `c4-render.test.ts`,
      `c4-count-parity.test.sh` green.
- [ ] AC11 — The PR-A legal records (Phase 4.5) are drafted through the CLO agent and committed;
      dated files are only appended to.
- [ ] AC12 — Both deferral issues (4.6 a/b) exist and are linked from D10/R8.
- [ ] AC13 — `BASELINE_DECLARED_PROBES` bumped by exactly +1 from `origin/main` at work time with its
      PLACEMENT / TRUTH / NO-SUBSTITUTE comment; `apps/web-platform/scripts/github-app-key-status.sh`
      exists in PR-A's tree and prints only the `github_app_key_source=` line.
- [ ] AC14 — The PR body's first line states the production mutations the merge triggers (Apply
      path); the pre-merge drift-guard trigger ran clean (per-command go-ahead).
- [ ] AC15 — Required checks green **by name on the exact head SHA**; PR-A merges by auto-merge
      (workflow edits → UNTRUSTED-CI).

### Post-merge (operator sequence, each step individually authorized)

- [ ] AC-R0 — Every App key row maps to a holder; `prd` and `prd_terraform` fingerprints differ; the
      old key is parked as `GITHUB_APP_PRIVATE_KEY_RETIRED`.
- [ ] AC-R2 — The stored Tier-B token reads a key whose fingerprint equals R1's (`equal`) and is
      refused on `soleur/prd`.
- [ ] AC-R4 — `bash apps/web-platform/scripts/github-app-key-status.sh` prints
      `github_app_key_source=isolated`; drift-guard and oauth-probe clean; `GET /app/installations`
      lists 3.
- [ ] AC-R5 — web-2's boot emit reports `isolated` and probe `ok`.
- [ ] AC-R6a — Before the delete: every repo reader of `GITHUB_APP_PRIVATE_KEY` is listed with the
      Doppler config its step, job or action input resolves to (today:
      `.github/actions/mint-soleur-ai-app-token/action.yml`, `board-status-sync.yml`,
      `apply-github-infra.yml`, `apply-web-platform-infra.yml`, all `prd_terraform`), and none
      resolves to `prd` (Kieran P1-5: a same-line `-c prd` grep would miss all four shapes).
- [ ] AC-R6 — Every `prd`/`prd_*` config in `doppler-config-inventory.txt` returns not-found for the
      key (except `prd_terraform`'s own override); a fresh release still `isolated`.
- [ ] AC-R7 — New-key JWT `200` from `GET /app`; retired-key JWT `401`; the parked name deleted;
      drift-guard clean; mint-failure query quiet for 1 h.

### PR-B

- [ ] AC-B1 — R8: exactly one App key (R1's fingerprint); exactly one project token
      (`web-host-github-app-read`); no service account or group on the project.
- [ ] AC-B2 — ADR-241 D2 and D10 `accepted` with the PR body stating why; R1 `CLOSED <date>`;
      ADR-220 Amendment-log entry; `compliance-posture.md` R1 CLOSED; the legal sweep finds no
      future-tense R1 sentence; body carries `Closes #8609`.

## Domain Review

**Domains relevant:** Engineering, Legal, Product

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Direction ratified. F1: operator-mint into `soleur-infra-privileged`, marked
`autonomy-considered: operator-mint` citing ADR-241 D3. F2: web-1 via the Terraform-declared push
(no automated web-1 replace exists, #6730); web-2 `web_host_replace` from `main` before the `prd`
delete. F3: prove state absence — now by the measured provider fact (Phase 0.3) rather than a grep
that cannot see gzip+base64 `user_data`; forbid plan uploads (G6e). F4: defer webhook/client
secrets; move only the PEM; keep `GITHUB_APP_ID` in `prd`. F5: amend ADR-241 with D10; flip D2 in a
follow-up PR. F6, item by item: F6.1 Doppler version history → rotation is mandatory (R1/R7); F6.2
other live App keys → R0 inventory and R7/R8 fingerprint gates; F6.3 cloud-init budget → Phase 0.1;
F6.4 placeholder clobber → Phase 2.5 precondition plus the Phase 2.6 unconditional loader export;
F6.5 cross-project references and syncs → R6 checks; F6.6 `DOPPLER_TOKEN_TF` → the R1 gate and R8;
F6.7 container/sandbox/metadata exposure → D10 residuals and deferral issue 4.6(b); F6.8 consumer
sweep → AC-R6a. Devex review: routine-rotation subsection, a generated operator bootstrap script with
PASS/FAIL checks and plain-language prompts, the old key parked in the isolated project instead of on
disk, a read-token rotation cadence, byte-equal sentinel blocks for the two overlay copies, and a
Playwright fallback.

### Legal (CLO)

**Status:** reviewed
**Assessment:** New dated REACHABILITY-ONLY Art. 33 assessment for the runtime key (distinct key,
wider read paths, earlier window start) plus a conditional pointer addendum on the #8209 record.
Evidence: K0 key inventory before any key delete, K1 non-`main` run census before the 90-day expiry,
K2 Doppler access logs, K3 org audit log, K4 third-party installation token issuance (unmeasurable).
No Art. 33(2)/34 or contractual notification duty on reachability alone; record "no notification"
as a controller decision (the courtesy notice is DC-1 in `decision-challenges.md`). No public legal
doc changes; Article-30 markers in PR-B.

### Product/UX Gate

**Tier:** none (no UI surface; the mechanical UI-surface override did not fire — no
`components/**`, `app/**/page.tsx` or `app/**/layout.tsx` in the file lists)
**Decision:** reviewed (CPO sign-off for the single-user-incident threshold)
**Agents invoked:** soleur:product:cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

CPO sign-off **GRANTED**. Folded: `GET /app/installations` with the new key lists all three
installations (a key valid for the App is valid for every installation's mint, so one mint on
`jikig-ai` plus the listing suffices without issuing tokens against users' installations); a
per-installation mint-failure watch from R4 to R7; the old key deleted only after a second release
shipped on `isolated`; the R6 rollback written down before R6. In-flight agent runs are unaffected
(already-minted installation tokens live ~1 h; Inngest runs in the web process). The courtesy notice
to the two third-party installers is a trust decision, not a duty — DC-1.

## Test Scenarios

- Given no token and `prd` holding a PEM, when ci-deploy runs, then the container is promoted on the
  `prd` key, deploy state says `source=prd`, and no Sentry event fires.
- Given a token and both projects holding keys, when ci-deploy runs, then the env-file holds exactly
  one key line, the isolated one, and deploy state says `source=isolated`.
- Given a token, a failing isolated fetch and a valid `prd` key, when ci-deploy runs, then it promotes
  on the `prd` key with `source=prd` and a Sentry error `reason=fetch_failed`.
- Given a token, a failing isolated fetch and no `prd` key (post-R6), when ci-deploy runs, then the
  canary fails `github_app_key_missing` and the running container is untouched.
- Given a key GitHub rejects (or a different App's key), when the canary probe runs, then the canary
  fails `github_app_key_rejected` and the running container is untouched.
- Given the variable empty, when the web-platform root renders, then the credential file equals
  `main`'s byte for byte.
- Given a malformed token value, when `terraform plan` runs in a Tier-B job, then the precondition
  fails without printing the value.
- Given a workflow on `pull_request` naming the Tier-B token, when the census runs, then it is red.

### Integration Verification (for `soleur:qa`)

- **API verify:** `bash apps/web-platform/scripts/github-app-key-status.sh` prints
  `github_app_key_source=prd` before R3 and `github_app_key_source=isolated` after R4.
- **Probe:** `soleur:trigger-cron` with `cron/github-app-drift-guard.manual-trigger` → clean run.

## Plan Review Revisions (2026-09-30)

Six-seat review (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow, CTO devex) plus
the Step 4.5 advisor consult. Applied as Mechanical unless noted:

| Finding | Seat | Change |
|---|---|---|
| New key branch-reachable at birth via `DOPPLER_TOKEN_TF` in `prd_terraform` | architecture P0 | R1 gated on #8209 O10 + O13; R8 checks project tokens and members |
| Shape gate cannot tell a wrong-but-valid key | spec-flow P0, architecture P1 | Canary `GET /app` + slug probe; loader exports the token name unconditionally |
| web-2 unreadable without SSH | spec-flow P0 | Boot probe verdict through `soleur-boot-emit` with host name |
| Separate token file needs FILE_MAP/hooks/installer/gate entries and fails `missing_env` | Kieran P0 | Single conditional line in the existing template (also simplicity) |
| Key source set inside a subshell never reaches deploy state | Kieran P0 | Overlay runs in the parent after `resolve_env_file` returns |
| Residency grep cannot see gzip+base64 `user_data` | DHH P0 | Guard 8 cut; provider hashing measured (Phase 0.3) |
| Host-side fingerprint plumbing | DHH, simplicity | Cut; `source=isolated` + the canary probe cover it |
| Three key-source states; warning noise before R3 | DHH, simplicity, spec-flow | Two states (`isolated`, `prd`); Sentry only on a failed fetch |
| Rollback impossible with fail-on-fetch | advisor | Fetch failure falls back to `prd` until R6 |
| `WEB_GZIP_BUDGET` location; no placeholder for this variable | Kieran P1 | Phase 0.1 uses `cloud-init-user-data-size.test.ts`; placeholder clause dropped |
| AC2 unpassable (host-script hash changes) | Kieran, architecture | AC2 rescoped; R5 requires an image built after PR-A |
| AC-R6a regex misses real readers | Kieran P1 | Resolve each reader's config |
| Runbook O0/O13 read the `prd` key | Kieran P1 | Dated notes in Phase 4.2 |
| R7 must also differ from the `prd_terraform` fingerprint; R6 rollback burns the key; short R7 recovery; R2 must prove what the token reads | spec-flow P1/P2 | R-table updated |
| No routine rotation; hand-run checks; old PEM on disk | CTO devex | Routine-rotation subsection; bootstrap script; `GITHUB_APP_PRIVATE_KEY_RETIRED` |
| ADR-241 has no Amendment log; no D10 Statuses row | architecture P2 | Phase 4.1 |
| Metadata endpoint not dropped on web hosts | architecture P2 | Deferral issue 4.6(b) |
| Legal records written twice | DHH, simplicity | PR-A time-sensitive records only; Article-30 once in PR-B |
| Census rows G6a/a2 tested a non-existent repo secret | architecture P1 | Guard 6 rebuilt around data sources, token mints, any-config writes, loader export |

Not applied: DHH's "drop the discoverability wrapper and ratchet bump" (Taste — the wrapper is the
only local, SSH-free read of the key source, which `hr-observability-as-plan-quality-gate` requires;
kept at ≤ 30 lines). Spec-flow's "refuse host create/replace when the token is empty after R6" (the
boot emit's fatal verdict already makes that failure loud; a repo-variable gate adds a mechanism for
a state only a deliberate Tier-B deletion produces).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold fails `deepen-plan` Phase 4.6.
- `doppler secrets delete` and `doppler secrets set` print the remaining config to stdout; every set
  and delete ends with `>/dev/null` (a PreToolUse hook blocks either without it) and is verified by a
  separate read that prints a hash comparison or a count.
- The overlay filter must be anchored (`^GITHUB_APP_PRIVATE_KEY=`): the parked
  `GITHUB_APP_PRIVATE_KEY_RETIRED` shares the prefix (Guard 7 row 7.2).
- `ENV_FILE=$(resolve_env_file)` is a subshell; anything that must reach deploy state is set in the
  parent (row 7.8).
- Never compare fingerprints across the wrong pair: R7's row must equal R0's **`prd`** fingerprint and
  differ from both R1's and `prd_terraform`'s; the `prd_terraform` key belongs to #8209 O13.
- PR-B must not land on R7 alone: the `prd_terraform` soleur-ai key keeps the issue's first
  acceptance bullet unmet until #8209 O13's App-key delete, and `DOPPLER_TOKEN_TF` keeps the new
  project reachable until O10/O13.
- Editing `infra-config-apply.sh`, `infra-config-install.sh` or `hooks.json.tmpl` re-fires a root
  remote-exec on web-1 at merge; the single-line carrier needs none of them.
- `EVICTED_SEE_ADR_241` is a sentinel, not a key; the presence check rejects it explicitly (row 7.4).
