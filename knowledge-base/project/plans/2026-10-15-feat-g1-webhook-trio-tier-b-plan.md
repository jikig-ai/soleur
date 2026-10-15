---
title: "security: move WEBHOOK_DEPLOY_SECRET and the CF Access pair out of branch-nameable storage, then rotate (G1)"
date: 2026-10-15
slug: g1-webhook-trio-tier-b
branch: feat-g1-webhook-trio-tier-b-9294
issue: 9294
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

## Overview

Gate G1 of ADR-241 residual R1: the deploy-webhook HMAC secret (`WEBHOOK_DEPLOY_SECRET`) and the Cloudflare Access client pair (`CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`) together authenticate `/hooks/infra-config` on web-1, which can replace `ci-deploy.sh` and read the host credential file. Any branch workflow of this public repository can name all three today, as Doppler `prd_terraform` values (Tier A) and as repo-level GitHub Actions secrets. This plan moves them to Tier B in a sequence of reviewable, revertible changes, then rotates all three with no gap.

Planning only. No apply, dispatch or production write is part of this plan's authoring; every production step below is named by the owner, one command each (`hr-menu-option-ack-not-prod-write-auth`). No secret value is printed anywhere (old values are saved to 0600 files so the negative probes can be proven).

Governing rulings, recorded and not re-opened here: Ruled by CTO agent, 2026-10-12 on #9294 (PR sequence; the Access token is removed from state with `removed { destroy = false }`, never `-replace`; the SSH trio is a separate window) and Ruled by CTO agent, 2026-10-15 (three forks, in Decisions below), plus Ruled by CTO agent, 2026-10-15 (review round, the census semantics: "Guard 1a" below). Three places where this plan departs from the 2026-10-12 comment are recorded here instead of left silent, and are flagged for the owner rather than re-ruled: PR-5 (a Tier-B leg for four probes) is replaced by retiring the five closed-issue probes in PR-4; the shared `dispatch-web-redeploy/track.sh` composite moves from PR-3 to PR-2 with the Terraform-fed group; and the ruled PR-0 row "every job naming the trio declares a Tier-B environment" is built in PR-0 as the `tier-b` class check (Guard 1a), proven against a fixture environment set until `deploy-channel` exists.

**Plan-review status (2026-10-15):** six reviewers reported; mechanical findings are applied below. The owner said "go with the CTO's recommendations"; Ruled by CTO agent, 2026-10-15 on D-1, D-2, T-1, T-2 and T-4 (see "Decisions ruled"). CPO re-review of the revised plan: see Domain Review.

## Research Insights

### Premise Validation (Phase 0.6)
Checked: #9294 is OPEN; #8209's three credential rotations are complete (HCLOUD_TOKEN, CF_API_TOKEN_R2, TF_STATE_AWS_*, each with its old value proven dead or deleted, 2026-10-15; operator-run in this session, with the evidence in `knowledge-base/project/specs/feat-git-data-cutover-recheck-8211/` on PR #10350, and not yet recorded as a comment on #8209); G2 (#9295) evidence is posted; #8609 stays blocked-by G1. The consumer count held under the 2026-10-12 definition: `git grep -l -E 'WEBHOOK_DEPLOY_SECRET|CF_ACCESS_CLIENT_(ID|SECRET)'` (case-sensitive) over `.github scripts apps/web-platform/scripts apps/web-platform/infra` returns 34 files, 25 non-test and 9 test. The census counts differently and is the authority: its emitter matches case-insensitively, so the lowercase Terraform variable names (`variables.tf`, `server.tf`, `hooks.json.tmpl`) count, and it skips comment-only mentions (`ensure-doppler.sh`), which gives 27 files in the baseline. Stale or newly found, each verified 2026-10-15 on `origin/main`:
1. `WEBHOOK_DEPLOY_SECRET` is a repo-level secret (the issue guessed org-level).
2. ADR-241's 2026-09-30 amendment reclassified the trio Tier B, but `TIER_B_NAMES` in `tests/scripts/test-infra-privileged-tier-census.sh` does not contain them; and the census classifies only a `doppler secrets get <name> ... prd_terraform` read through `TIER_B_NAMES` (the `secrets.X` and env-passthrough shapes go through `ENV_SECRETS`/`SEC_REF`), so adding the names alone classifies none of the repo-secret reads.
3. `CF_TUNNEL_TOKEN` is a repo secret with no consumer in `.github`, `scripts`, `apps` (non-doc).
4. `hooks.json.tmpl` has **13** `payload-hmac-sha256` matches (13 hook ids, 13 `jsonencode(webhook_deploy_secret)` lines), not 14.
5. `ci-deploy.sh` `fan_out_to_peers` reads the peer signing key with `jq '.[] | select(.id=="deploy-peer") | .["trigger-rule"].match.secret'`; under an `or` rule that path is null and the fan-out to web-2 stops with "FANOUT: webhook secret unavailable".
6. `infra-config-verify.sh` reads `CF_ACCESS_CLIENT_ID` with a silent fallback to `CI_SSH_ACCESS_TOKEN_ID` (a token the deploy policy does not admit).
7. Issues 7220, 5863, 2640 and 5875 are CLOSED; only 6178 is open. Five followthrough probes belong to the closed ones.
8. No `*.tfvars` file exists in the repository.
9. `hcloud` 1.63.0 keeps only a hash of `user_data` in state (comment in `server.tf`), and `deploy_pipeline_fix` triggers on a keyless render, so the HMAC is expected not to be in state. PR-0 asserts this rather than assuming it.

### Property List and Cut List (Phase 0.6b)
Properties: P1 no workflow that has not passed a main-only environment can name any of the three; P2 the three old values are rejected after rotation; P3 no secret-bearing Access token attribute sits in Tier-A-readable Terraform state; P4 a rotation never strands web-1's remote write path; P5 a new consumer of the trio (or of the rotation's "next" secret) cannot be added without a reviewed change.
Cut: a per-file environment-secret copy mechanism (the Terraform App gets 403 on environment secrets, R6; the loader already covers it); promoting the sweeper to Tier B (it runs arbitrary issue-bound probes with every repo secret); a permanent census allowlist (D8 forbids it); the former PR-5 (a Tier-B sweeper leg for probes of closed issues): replaced by retiring those probes; a committed reconciliation script (see taste item T-3); the row-count ceiling row (covered by the shrink-only row).

### Live facts (read 2026-10-15)
- Where the three live: Doppler `soleur/prd_terraform` and repo-level GitHub secrets. None is in `soleur-infra-privileged`.
- Environments carrying `DOPPLER_TOKEN_INFRA_PRIVILEGED`: `infra-privileged` (0 reviewers, main-only), `web-platform-infra-apply` (1 reviewer, self-review allowed), `inngest-cutover`, `workspaces-luks-cutover`. `inngest-config-signing` does not.
- The Tier-B loader (`.github/actions/infra-credentials/action.yml`) hardcodes `-p soleur-infra-privileged -c prd`, takes its token through the input `doppler-token-infra-privileged` (a composite action cannot read `secrets`), loads the whole project into every job, and on an empty token takes the legacy arm that reads `prd_terraform` (including `HCLOUD_TOKEN`). #10300 (single-name carrier) is open.
- `tunnel.tf`: `cloudflare_zero_trust_access_service_token.deploy` (create_before_destroy) is referenced by `cloudflare_zero_trust_access_policy.deploy_service_token`; its `client_id` and `client_secret` are sensitive outputs and so sit in Tier-A-readable state; `server.tf` passes `var.cf_access_client_id/_secret` to `deploy_pipeline_fix` in the provisioner environment (not persisted in state).
- Host coverage: web-1 gets `hooks.json` through `deploy_pipeline_fix`; web-2 over SSH through `deploy_pipeline_fix_web2`; fresh web hosts through `cloud-init.yml` (`WEBHOOK_DEPLOY_SECRET='...' sh soleur-host-bootstrap.sh`). The inngest and registry cloud-inits carry no webhook secret and no `hooks.json`.

## Research Reconciliation: Spec vs. Codebase

| Claim (issue / ruling / earlier draft) | Reality | Plan response |
|---|---|---|
| Consumers are the 10 workflows plus scripts listed | 25 non-test files, including the composite action `track.sh`, `cloud-init.yml`, `infra-config-verify.sh`, `verify-tunnel-ingress-origin.sh`, `soleur-host-bootstrap.sh`, `cutover-inngest.sh`, `check-deploy-script-parity.sh` | the derived consumer table below; a census row keeps it derived |
| Move into "main-only environment secrets or Tier B" | the loader hands a Tier-B job the whole privileged project, including `HCLOUD_TOKEN` read/write | narrow Tier-B project for non-Terraform consumers (Fork 1) |
| Adding the trio to `TIER_B_NAMES` makes the census see them | only the `prd_terraform` read shape is classified by `TIER_B_NAMES` | PR-0 adds classifiers for the `secrets.X` and env-passthrough shapes |
| `or` of two HMAC matches is inert while the second secret is empty | an empty-key HMAC match is forgeable; and `fan_out_to_peers` reads `.trigger-rule.match.secret` | `or` rendered only when "next" is non-empty; the fan-out reader is fixed first (PR-1) |
| 14 HMAC rules | 13 | corrected everywhere |
| `removed { destroy = false }` revert-safe "while Tier-A copies exist" | after the removal a revert would re-declare a resource state no longer holds | forward-fix path, no revert (PR-2) |
| PR-5 migrates five probes | their issues are closed | retire the probes |
| Committed tfvars holds the ids | no tfvars file exists | a variable default in `variables.tf` |

## Scope Check

| Ask | Where it lands | Provenance |
|---|---|---|
| Move the three out of every branch-nameable location, Doppler Tier A and GitHub repo secrets | PRs 0-4 and the deletion step | issue |
| Rotate all three; old values rejected | Rotation section | issue |
| ADR-241 D1 census amendment | PR-0 | issue |
| Census row proving no branch-nameable copy | PR-0 and the final PR | issue |
| G1b: SSH trio | out of this plan's PR chain; tracked under #9294; separate window | CTO ruling |
| Delete orphan `CF_TUNNEL_TOKEN` repo secret | final cleanup | CTO ruling, verified: no consumer |
| Retire probes of closed issues | PR-4 | inferred from review; verified (issues CLOSED); removes consumers rather than migrating them |

Split assessment: one chain of five PRs (PR-0 to PR-4, then the owner-named deletions and the rotation), each safe to merge while the Tier-A copies exist (PR-2 forward-fix only, see its section). It is not split into separate plans because each PR's safety depends on the previous census baseline.

## Open Code-Review Overlap

One open scope-out touches a planned file: #2197 (`server.tf`, billing type refactor). Acknowledge: a different concern; this plan edits only the webhook and Access sections.

## Consumer table (derived 2026-10-15; keep derived, never hand-listed)

Source today: R = repo secret `secrets.X`; D = Doppler `prd_terraform` read; E = env passed from a caller. Names: W = webhook secret, I = Access id, S = Access secret.

| Group | File | Names | Source today | Environment today | After the move |
|---|---|---|---|---|---|
| PR-2 Terraform-fed + shared composite | `.github/workflows/apply-web-platform-infra.yml` | W I S | D | `infra-privileged`, `web-platform-infra-apply`, `workspaces-luks-cutover` | loader, privileged project (TF_VAR) |
| PR-2 | `.github/workflows/apply-deploy-pipeline-fix.yml` | W I S | D | `infra-privileged` | loader, privileged project |
| PR-2 | `.github/workflows/git-data-cutover.yml` | W I S | D | `web-platform-infra-apply` | loader, privileged project (see D-1) |
| PR-2 | `.github/actions/dispatch-web-redeploy/track.sh` (called from `apply-web-platform-infra`, `git-data-cutover` and the release workflow, so it moves with its first callers and reads the caller's env) | W I S | E | n/a | reads the caller's loader-filled env |
| PR-2 | `apps/web-platform/infra/{infra-config-verify.sh, scripts/verify-tunnel-ingress-origin.sh, soleur-host-bootstrap.sh, cloud-init.yml}`, `scripts/{check-deploy-script-parity.sh, cutover-inngest.sh, ensure-doppler.sh}` | W (I S in the verify scripts) | E from callers | n/a | the caller's env; `infra-config-verify.sh` loses its silent `CI_SSH_ACCESS_TOKEN_ID` fallback |
| PR-3 release chain | `.github/workflows/web-platform-release.yml` (9 refs), `.github/workflows/canary-status.yml` | W I S | R | none | `deploy-channel` environment, narrow project |
| PR-4 inngest + retirements | `.github/workflows/{cutover-inngest, deploy-inngest-image, restart-inngest-server, scheduled-inngest-health}.yml`, `scripts/followthroughs/inngest-soak-6178.sh` | W I S | R | none, except `cutover-inngest.yml` (`inngest-cutover` for some ops) | `deploy-channel` (unattended) or `inngest-cutover` (reviewer-gated ops), narrow project |
| PR-4 retire | `scripts/followthroughs/{infra-config-activation-7220, infra-config-fatal-channel-7220, tenant-outer-wrap-soak-5863, workspace-isolation-verdict-2640, canary-promotion-5875}.sh` and their trackers' directives | W I S | R | none | deleted (issues CLOSED); `scheduled-followthrough-sweeper.yml` and `apps/web-platform/scripts/github-app-key-status.sh` (operator-run via Doppler) lose their trio reads; the sweeper stays Tier A and is verified to need none of the three |
| Terraform | `variables.tf`, `server.tf` (`hooks.json` render, `deploy_pipeline_fix` provisioner env), `tunnel.tf` | W I S | D via TF_VAR | n/a | TF_VAR from the loader |
| Hosts | web-1 and web-2 `hooks.json`; fresh-host cloud-init | W | rendered | n/a | `deploy_pipeline_fix`, `deploy_pipeline_fix_web2`, cloud-init; the inngest and registry hosts are verified to carry none |
| Tests (9 files) | named by the census | | | | updated with their consumers |

Jobs that break if the Tier-A copy is deleted before their group moves: every row above except Terraform-fed jobs that already read through the loader. That is why deletion is the last irreversible step.

## Decisions made for this plan

- **Carrier (Ruled by CTO agent, 2026-10-15, Fork 1).** A narrow Tier-B project for the non-Terraform consumers, in the D11 shape (`mint-infra-app-token` precedent): Doppler project `soleur-deploy-channel` holding only the trio, a main-only environment `deploy-channel` carrying its own read token `DOPPLER_TOKEN_DEPLOY_CHANNEL`. The Terraform-fed group keeps the trio in `soleur-infra-privileged` as the source of truth; the narrow project is a one-way copy. Not folded into `soleur-infra-app`.
- **Loader narrow mode (review finding, mechanical).** The loader gains two inputs: `doppler-project` (default `soleur-infra-privileged`, allowlisted to exactly two names, unknown value fails closed) and `doppler-token-deploy-channel`. In narrow mode the loader reads only `soleur-deploy-channel/prd`, skips the legacy `prd_terraform` arm, the App-runtime handling and the state-key aliasing, and **fails closed on an empty token** (it never falls back to `prd_terraform`, which would hand a mis-bound job `HCLOUD_TOKEN`).
- **Access token ids (Ruled by CTO agent, 2026-10-15, Fork 2).** A committed Terraform list variable `deploy_service_token_ids` with its default in `variables.tf` (no tfvars file exists; the ids are not secret and the default is reviewed in a PR), because the policy `include` is an authorization boundary. Rotation is two PRs (add the new id, then remove the old).
- **Census (Ruled by CTO agent, 2026-10-15, Fork 3).** The trio and the rotation "next" secret are tracked by a name-reference census with an expiring baseline keyed by (file, name); they join `TIER_B_NAMES` only as their groups migrate (see PR-0). The review round refined this into "Guard 1a" (Ruled by CTO agent, 2026-10-15): a regression ratchet over where the names are written, not a proof of reachability. The baseline lives in its own file `tests/scripts/trio-baseline.tsv` (rows `file<TAB>name<TAB>expires<TAB>issue`) and is compared against the merge-base copy through `git show <base>:<path>` (the existing `BASE_ROOT` mechanism materializes only `*.tf`, so this is a new, small comparison).
- **Rotation "next" secret (review finding, mechanical).** New Terraform variable `webhook_deploy_secret_next` (default empty, with a validation that it is empty or at least 32 hex characters) and Tier-B name `WEBHOOK_DEPLOY_SECRET_NEXT`. Semantics: `WEBHOOK_DEPLOY_SECRET` is what signers use; the host accepts it or the next.
- **Two copies, one writer.** The privileged-project copy is the source of truth; the narrow-project copy is written from it by a hash-equal pipe and verified equal by a read-only check at every rotation step; both are updated before any canary.
- **No revert for PR-2's state change (review finding).** After `removed { destroy = false }` a revert would re-declare a resource state no longer holds and create a new token whose secret is in no Doppler project. PR-2 is therefore forward-fix only; its CI gate asserts that the default of `deploy_service_token_ids` equals the live token id before merge.

## Implementation Phases

### PR-0: docs and tests, no behaviour change
- ADR-241 D1 amendment: the consumer inventory in groups, the SSH-bridge census miss (G1b), the orphan `CF_TUNNEL_TOKEN`, the narrow-project decision, and the result of the host-coverage verification above.
- Census, implemented as its own suite (refinement found at implementation, 2026-10-15): `tests/scripts/test-trio-baseline-census.sh` plus `tests/scripts/trio-baseline.tsv`. Adding the trio to `TIER_B_NAMES` in the existing census reds its row G1g on the live tree (the trio is read with `-c prd_terraform` by git-data-cutover and others) and its classifier sees only that one read shape, so the existing census is left unchanged in PR-0 and the trio enters `TIER_B_NAMES` in the PRs that migrate each group, as the baseline shrinks. The new suite derives every (file, name) from the tree (any non-comment mention of a trio name, whatever the read shape), keys the baseline by (file, name), compares it with the merge-base copy through `git show`, and carries the HMAC-not-in-state rows (H1 to H3), a fallback row and the HCLOUD_TOKEN-creep row. The `deploy-channel` environment constants stay in PR-1 with its Terraform policy.
- Review-round rework of the census (Ruled by CTO agent, 2026-10-15; ten-seat panel on the first PR-0 commit): the population is every tracked-or-untracked-unignored file from `git ls-files` minus `knowledge-base/`, `docs/`, binaries, symlinks and the suite's two own files (no hand-listed roots; the four skill docs that read the trio from Tier A are in scope); the only test exemption is structural (a `test`/`tests`/`__tests__`/`fixtures` directory or a `.test.`/`.spec.`/`.tftest.hcl` suffix, never under `.github/`, and still needing a row for a direct-store read shape); names are a token family (optional `TF_VAR_`, a stem, any `_SUFFIX`, so `WEBHOOK_DEPLOY_SECRET_NEXT` is a member), the three stems are pinned in a baseline header and compared to the merge-base, and the `access_service_token_client_*` outputs are `ALIAS:*` rows. The ratchet compares tag, class and expiry as well as the key, resolves its base through the merge-base (or `HEAD^1` on a main push) and fails closed when it cannot; a new key is admitted only through an `@allow` line already present at the merge-base and deleted by the diff that spends it (PR-0 carries the three `WEBHOOK_DEPLOY_SECRET_NEXT` allows PR-1 needs); a renamed file carries its row. Rows have a computed class: `tier-a` (expiring, the thing to drive to zero), `tier-b` (a workflow file proven to declare a Tier-B environment) and `sink` (a non-workflow file with no direct-store read shape, such as `variables.tf`). Expiry is a strict ISO date; it is a hard red only for a pull request whose diff touches a `tier-a` file (or the baseline, ADR-241 or this plan), and a non-blocking annotation on a main push, so the date can never stop tenant deploys through `ci_not_green`. Reach without naming (`doppler run` against `prd_terraform`, `secrets: inherit`, `toJSON(secrets)`, computed names, callers of self-fetching scripts) is listed as a known blind spot, not covered by rows: it is closed by deleting the Tier-A and repo-secret copies and by the main-only environment policy.
- Read-only reconciliation of the three ids (state `client_id`, the policy's referenced id, the Doppler `CF_ACCESS_CLIENT_ID`), run once as a command and pasted into the PR body (see T-3). Note the comparison is client_id to client_id and resource id to policy id; they are different identifiers, so the command prints both mappings.
- Comment on #9294 adding G1b as tracked scope (the owner approves the comment).

### PR-1: prep, plan-neutral
- `apps/web-platform/infra/ci-deploy.sh`: change `fan_out_to_peers`' key read to find the first `secret` anywhere under the rule's `trigger-rule` (not only `.match.secret`), with its `ci-deploy.test.sh` fixture covering both the single-match and the `or` shapes. **This lands before any `or` render.**
- `hooks.json.tmpl`: render an `or` of two `payload-hmac-sha256` matches on all 13 rules only under a `%{ if webhook_deploy_secret_next != "" }` guard; with an empty "next" the template renders exactly today's single match (an empty-key match is forgeable and must never be rendered). Verify against the `adnanh/webhook` documentation that `trigger-rule` supports `or` of `match` rules and record the URL in the PR. Key `deploy_pipeline_fix`'s trigger on the keyless render plus a `webhook_secret_generation=N` literal (as D10 did).
- New `apps/web-platform/infra/deploy-channel-environment.tf`: Doppler project `soleur-deploy-channel` (empty), environment `deploy-channel` with a main-only deployment-branch policy, in the `infra-privileged-environment.tf` pattern. Census constants for the new environment and the new token secret name land here.
- Loader: the narrow mode described under Decisions, with fixtures for both modes and for an empty narrow token.

### PR-2: the Terraform-fed group together (forward-fix only)
`apply-web-platform-infra`, `apply-deploy-pipeline-fix`, `git-data-cutover` and what they invoke, plus the `track.sh` composite. The owner-named copy step comes first (hash-equal copy of the trio into `soleur-infra-privileged/prd`), then a canary reading `source=tier_b` for all names. Then the PR removes the group's reads of the trio from `prd_terraform` and repo secrets, and removes `infra-config-verify.sh`'s fallback.

State surgery for the Access token (Ruled by CTO agent, 2026-10-12):
1. `tunnel.tf`: replace `include.service_token = [cloudflare_zero_trust_access_service_token.deploy.id]` with `var.deploy_service_token_ids`, default = the current token id (non-secret, read from Cloudflare).
2. Add `removed { from = cloudflare_zero_trust_access_service_token.deploy  lifecycle { destroy = false } }`; delete the two sensitive outputs (verified: nothing outside `tunnel.tf` reads them). The `-target=cloudflare_zero_trust_access_service_token.deploy` line in `apply-web-platform-infra.yml` stays (census G4b requires every `removed` address to be in the target list). Guard 4 shape.
3. Plan-shape proof (offline fixture plus the real plan): 0 add, 0 destroy, 1 in-place change (the policy), the token only forgotten.
4. P3 is stated precisely: after this PR the secret is absent from the current state; older state object versions in R2 keep it until the old token is deleted in the rotation. The live token keeps working until then. Never `-replace`.

### PR-3: release chain together
`web-platform-release` (3 sites, 9 refs) and `canary-status`. Jobs declare `environment: deploy-channel` and call the loader in narrow mode. Triggers checked: `push` to main, `schedule` and `workflow_run` run on the default branch and satisfy the main-only policy; `workflow_dispatch` from a branch fails by design (a fixture row asserts it).

### PR-4: inngest group and probe retirement
`cutover-inngest`, `deploy-inngest-image`, `restart-inngest-server`, `scheduled-inngest-health`, `inngest-soak-6178` move as in PR-3 (reviewer-gated ops keep `inngest-cutover`). Open decision found in review, for PR-4 (task 5.3): #6178 is still OPEN and `inngest-soak-6178.sh` runs only under `scheduled-followthrough-sweeper.yml`, which stays Tier A and needs none of the three, so "moves as in PR-3" and "the sweeper stays Tier A" cannot both hold for that probe; PR-4 retires the probe or gives it a dedicated workflow. The five closed-issue probes and their tracker directives are deleted (the issues are CLOSED); the sweeper and `github-app-key-status.sh` lose their trio reads.

### After PR-4: owner-named, irreversible
Delete the three Tier-A Doppler copies in `prd_terraform`, the three repo secrets and the orphan `CF_TUNNEL_TOKEN`; migrate the census baseline to its end state (the final PR asserts zero `tier-a`, `FALLBACK:*` and `ALIAS:*` rows with every `tier-b` row proven; no permanent allowlist for readers, D8). Before deleting each Tier-A value, the hash-equal copy in Tier B is re-verified equal and the old value is held in a 0600 file for the duration of the step.

### Rotation, with no gap (after the deletions)
**Access pair.** Mint a new service token (the value is shown once and captured to a 0600 file, never printed). PR-A adds its id beside the old one in `deploy_service_token_ids`; apply. Update both Tier-B copies; verify equal; canary (the infra-config verify reads the new pair). PR-B (remove the old id) is gated on that canary passing with the new pair, not on step order. Save the old pair to a 0600 file before deleting the old token (irreversible), then probe: the old pair is denied at the edge, the new pair reaches the origin.
**HMAC secret, three generations.** Generate the new secret locally into a 0600 file; save the current value to another 0600 file first. Phase A: set `WEBHOOK_DEPLOY_SECRET_NEXT` to the new value in both projects; bump `webhook_secret_generation` (N+1); hosts now accept the old (signers) or the new. Phase B: set `WEBHOOK_DEPLOY_SECRET` to the new value and `WEBHOOK_DEPLOY_SECRET_NEXT` to the old; bump (N+2); consumers sign with the new value; canary. Phase C: clear "next"; bump (N+3); hosts accept only the new. Probe with the saved old secret that a signed request returns 403 (the template's mismatch code). A freeze applies from Phase A to C: no release, no `apply-deploy-pipeline-fix` and no `deploy_pipeline_fix` re-push except the rotation's own bumps; the check is "no run in progress or queued" for the release, apply and cutover workflows before each phase. A host created mid-rotation bakes the then-current primary, so fresh-host creation is also frozen. If web-1 is updated and web-2 fails at a phase, the phase is re-run (the generation literal makes the push idempotent) before the next starts.

## Owner-named command chain (one step each; refusal text is what the step prints)

Every step is run by the agent only after the owner names that exact command; the Doppler, `gh` and Cloudflare calls need no human hands (the agent uses the owner's authenticated CLI and a signed-in browser session). Where the owner is needed is the authorization, not the typing.

| # | Step | Command | Preconditions it checks | Refusal looks like |
|---|---|---|---|---|
| 1 | Read-only reconciliation of the ids | the command pasted in PR-0's body | none | prints both id mappings and `differ`; stop |
| 2 | Hash-equal copy into `soleur-infra-privileged/prd` | `doppler secrets get <NAME> -p soleur -c prd_terraform --plain \| doppler secrets set <NAME> -p soleur-infra-privileged -c prd --silent > /dev/null`, one name per command | the project exists; no run in progress or queued for the release, apply and cutover workflows | non-zero exit; the equality read reports `differ` |
| 3 | Narrow project's read token and environment secret | `doppler configs tokens create gha-deploy-channel -p soleur-deploy-channel -c prd --access read --plain` piped into `gh secret set DOPPLER_TOKEN_DEPLOY_CHANNEL --env deploy-channel -R jikig-ai/soleur` | PR-1 merged and applied | `gh` reports the environment is missing |
| 4 | Hash-equal copy into the narrow project | the step 2 pipe with `-p soleur-deploy-channel` | step 3 done | equality read `differ` |
| 5 | Canary per group | a read-only drift dispatch (`gh workflow run scheduled-terraform-drift.yml -R jikig-ai/soleur --ref main`) for the Terraform-fed group; for the release and inngest groups the first real run on `main` after the merge, watched to completion | the group's PR merged | `source=legacy` instead of `source=tier_b` in the loader line; stop |
| 6 | Delete the Tier-A copies and repo secrets | `doppler secrets delete <NAME> -p soleur -c prd_terraform --yes`; `gh secret delete <NAME> -R jikig-ai/soleur` | all groups green; no `tier-a`, `FALLBACK:*` or `ALIAS:*` row left in the baseline; the Tier-B copies re-verified equal; a live `doppler secrets get` of each name against `prd_terraform` and `gh secret list` both report it absent (recorded in the PR body) | the census reds if a consumer still names the trio as `tier-a`; a consumer that never named it reads an empty value and fails closed |
| 7 | Rotation | as in the Rotation section; each sub-step its own command | step 6 done; old values in 0600 files; freeze check | an unexpected probe status; stop and do not delete the old value |

## Sequencing against the git-data deadline (Ruled by CTO agent, 2026-10-15, D-1)

G1 gates #8609, not the git-data flip. The git-data date is hard (plaintext volume 2026-11-12 per ADR-239 and the runbook; a flip stamped after 2026-11-04 cannot finish the 7-day soak by then, which is where the 2026-11-04 figure comes from), and the rehearsal must certify the exact credential path the flip uses, so G1 yields:

- **PR-0 proceeds now** (no behaviour change).
- **PR-1 proceeds now, but only if** it is merged and deployed through one normal release, with the empty-"next" render proven byte-identical to today's hooks output, **before the owner names the rehearsal dispatch** (`ci-deploy.sh` is on the flip's redeploy path). If it misses that cutoff, all of PR-1 waits until after the wipe.
- **PR-2 to PR-4 and the Tier-A deletions** may run before the rehearsal only as units that are merged, canaried (`source=tier_b`) and green by the time the owner names the rehearsal dispatch. Whatever is unfinished then resumes after the wipe.
- **Hard cutoff:** nothing G1-related lands between the rehearsal dispatch and the end of the wipe, because a rollback during the soak still uses the webhook and the builds.
- **`git-data-cutover.yml` is frozen against G1 edits** from the moment the owner names the rehearsal dispatch until the wipe completes; a later edit invalidates the rehearsal and it is repeated.
- **The rotation starts only after the wipe**, never before the flip: its phase A to C freeze would block the release builds the git-data gates need and would change credentials between the rehearsal and the flip. The owner stamps a rotation start date at the wipe (CPO condition 2); the stamp has an owner-visible hook in the expiry follow-through issues (tasks 1.7), not only in this prose. The freeze is bounded: phases A to C together are time-boxed to the owner's named window, an unexpected probe status stops the sequence and leaves the old value live (never half-rotated), and a security hotfix during a freeze is released by the owner through the same named-command path. The 0600 files for the old and new values live in the operator's own scratch directory outside the repo and are shredded after the negative probe is recorded (the retained evidence is the probe status line, not the value).
- **Override:** evidence of credential misuse preempts all of this; the git-data date then moves to the owner and the CLO.

## Decisions ruled (Ruled by CTO agent, 2026-10-15; the owner said "go with the CTO's recommendations")

- **D-2 interim exposure: "move, delete the Tier-A copies, then rotate" is accepted; rotating first is rejected** (consumers that had not moved would need the new values written into Tier A, which branch workflows can read, defeating P3). What the owner accepts: the old HMAC and old Access pair stay valid until phase C and the old token's deletion, which given D-1 is weeks; deletion stops new reads but does not cure past ones (branch workflows that already read the values, logs, and any copy of the state file a Tier-A reader already pulled; the R2 state bucket has no object versioning, ADR-006's 2026-09-09 amendment, so the next apply after `removed { destroy = false }` overwrites the only stored copy and there is no history to scrub); abuse needs both the Access pair (to pass the edge) and the HMAC (to authorize the hooks); the `deploy-channel` environment has 0 reviewers by design (unattended jobs); G1b stays open, so #8609 stays blocked.
- **T-1: keep one PR per consumer group** (PR-3 touches the release chain the git-data builds use, so it falls under the cutoff; PR-4 does not; their canaries and reverts differ).
- **T-2: keep the `or` two-secret HMAC rotation** (a single-secret change is not atomic across two hosts and all signers; every signed request would get 403 in the gap and `fan_out_to_peers` would mis-sign for the peer). PR-1's guard keeps the empty-"next" render identical to today's.
- **T-3 applied** (no committed reconciliation script).
- **T-4: keep two copies** (the narrow project exists so unprivileged jobs never hold a token for a project holding more than the trio; the hash-equal check at each rotation step contains drift).

## Files to Create
- `apps/web-platform/infra/deploy-channel-environment.tf`
- `tests/scripts/trio-baseline.tsv`
- `knowledge-base/project/specs/feat-g1-webhook-trio-tier-b-9294/tasks.md`

## Files to Edit
- `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`
- `tests/scripts/test-infra-privileged-tier-census.sh` and its fixtures
- `.github/actions/infra-credentials/action.yml`
- `apps/web-platform/infra/{tunnel.tf, variables.tf, server.tf, hooks.json.tmpl, ci-deploy.sh, ci-deploy.test.sh, infra-config-verify.sh}`
- the consumer files in the table, group by group

## User-Brand Impact

**If this lands broken, the user experiences:** a stranded deploy path to web-1 (no deploys and no hotfix until the SSH recovery path is used, with a stale `ci-deploy.sh` meanwhile), or a web outage if a rotation cuts off the remote write path; a half-rotated webhook also silently stops deploys reaching web-2.
**If this leaks, the user's workflow and data are exposed via:** the three credentials, which together can replace `ci-deploy.sh` and read the host credential file on web-1, reaching every tenant on that host; the window between the move and the rotation, and the temporary second copy and "next" secret, widen that exposure briefly.
**Brand-survival threshold:** single-user incident

`requires_cpo_signoff: true`. CPO sign-off: **granted** on re-review (2026-10-15, conditions in Domain Review); `soleur:engineering:review:user-impact-reviewer` runs at review.

## Domain Review

**Domains relevant:** Engineering (security and infrastructure), Product (CPO sign-off for the single-user-incident threshold)

### Engineering
**Status:** reviewed
**Assessment:** Ruled by CTO agent on 2026-10-12 and 2026-10-15; reviewed by the plan-review panel on 2026-10-15 (architecture, flow, correctness, simplicity, overengineering): mechanical findings applied above.

### Product
**Status:** reviewed
**Assessment:** CPO advisory 2026-10-15: user-brand impact adequate on exposure and thin on tenant-visible failure (now expanded); web-1 protection per step good; the plan must state where G1 sits relative to the 2026-11-04 git-data deadline and the owner must accept the interim exposure. CPO sign-off: withheld on the first review (no sequencing against the git-data deadline, no acceptance of the interim exposure); the CTO rulings above supply both and the owner has adopted them; re-review result below.

**CPO re-review, 2026-10-15: CPO sign-off: granted**, with two conditions: (1) this result is recorded here (done); (2) the owner stamps the rotation start date at the wipe (D-1). Both of the first review's conditions are met: G1 yields to the 2026-11-04 git-data deadline (PR-0 now; PR-1 only if released before the rehearsal dispatch; PR-2 to PR-4 only if green by then; nothing between the rehearsal and the wipe; the rotation after the wipe), and D-2 names what the owner accepts. No new product or brand risk.

No Marketing, Legal, Sales, Finance or Support implications: no user-facing surface, no personal data processed by these credentials, no vendor or contract change.

## Infrastructure (IaC)

### Terraform changes
New `deploy-channel-environment.tf` (Doppler project, GitHub environment, main-only deployment policy), following `infra-privileged-environment.tf`. `tunnel.tf` gains `variable deploy_service_token_ids`, a `removed` block, and loses two sensitive outputs. `variables.tf` gains `webhook_deploy_secret_next` (default empty, validated). Providers are already pinned.

### Why the secret values are deliberately not Terraform resources
None of the three values may sit in Terraform state, because the state is readable by any branch workflow (Tier A). A `doppler_secret` resource would write the values into that state and defeat property P3, which is why the Access token is minted outside Terraform and the values are copied between Doppler projects by a hash-equal pipe. This follows operator steps O2 to O7 in `infra-credential-tiers-8209.md`. The project, the environment and the deployment policy, which carry no secret, are Terraform.

### Apply path
(a) Existing roots, push-applied from `main`; no host replace. `webhook_secret_generation` bumps re-fire `deploy_pipeline_fix` (webhook push for web-1; SSH remote-exec for web-2). Downtime: none expected; each bump is canaried and the freeze above applies.

### Host fan-out
`terraform_data.deploy_pipeline_fix` (web-1) and `deploy_pipeline_fix_web2` (web-2) both receive the `or` hooks render and the generation literal; the fresh-host cloud-init path bakes the current primary. The inngest and registry hosts carry no webhook secret (verified in `cloud-init-inngest.yml`).

### Distinctness / drift safeguards
The two Tier-B copies are checked equal at every rotation sub-step. The HMAC's absence from state is asserted by a census row. The Access secret leaves current state with the `removed` block.

### Vendor-tier reality check
Cloudflare permits duplicate Access service-token names (probed 2026-07-29, recorded in `tunnel.tf`); no free-tier gate applies.

## Observability

```yaml
liveness_signal:
  what: deploy webhook round-trip succeeds (infra-config verify posts a signed request and reads the origin's answer) and web-2 fan-out succeeds (no "FANOUT: webhook secret unavailable" line)
  cadence: every release deploy and every apply-deploy-pipeline-fix run
  alert_target: the existing release and apply workflow failure notifications
  configured_in: .github/workflows/web-platform-release.yml and apps/web-platform/infra/infra-config-verify.sh
error_reporting:
  destination: workflow run annotations (::error title=infra-privileged::verdict=...), the existing Sentry cron monitors, and the host's FANOUT log line shipped to Better Stack
  fail_loud: yes (the loader fails closed on an unknown project and on an empty narrow token)
failure_modes:
  - mode: a consumer still reads the old Tier-A or repo copy after deletion
    detection: the census row reds before merge
    alert_route: PR check
  - mode: the Access policy admits neither token during rotation
    detection: infra-config verify returns the Access edge denial instead of the origin's 403
    alert_route: the run's failure annotation, then stop
  - mode: the new HMAC is accepted by web-1 but not web-2
    detection: a per-host signed probe result, and the FANOUT line
    alert_route: the rotation step's own probe output
  - mode: an empty or missing "next" secret renders a forgeable match
    detection: the template test and the census row (no empty `secret` in any rendered rule)
    alert_route: PR check
logs:
  where: GitHub Actions run logs (values masked) and Better Stack for host webhook logs
  retention: Actions 90 days
discoverability_test:
  command: bash tests/scripts/test-trio-baseline-census.sh
  expected_output: PASS
```

## Encryption Posture

```yaml
at_rest:
  store: Doppler project soleur-deploy-channel (secret values)
  mechanism: Doppler-managed encryption at rest (vendor attestation: Doppler security documentation and SOC 2 report)
  defends_against: disk or backup theft at the vendor
  does_not_defend: a holder of the project's read token, or a Doppler workplace admin, reads every value
  disclosed_as: ADR-241 D1 amendment (PR-0)
  live_verification: not applicable to a vendor-managed store; the read token's scope is verified by the census
in_transit:
  connection: GitHub runner to the Doppler API, and runner to the deploy webhook host
  tls: yes
  cert_verification: on
  does_not_defend: a compromised runner sees the values it is given
  disclosed_as: ADR-241 D6
```

## Guard Contract

### Guard 1a — the trio name-reference census and its expiring (file, name) baseline

**Property (narrowed in the review round, Ruled by CTO agent, 2026-10-15).** No file names a trio name (the stems `WEBHOOK_DEPLOY_SECRET`, `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET` and any token built on them, including the rotation `_NEXT` name) except through a baseline row that exists at the merge-base and only shrinks; a row's class is computed from the file, and the end state is zero `tier-a` rows. This is a regression ratchet over where the names are written. It does not prove that no job can reach the values: reach without naming is closed by deleting the Tier-A and repo-secret copies (a consumer that never named the trio then reads an empty value and fails closed) and by the main-only environment policy that the existing census already guards (G1b to G1d, G1h).

**Assembly.** Every file `git ls-files --cached --others --exclude-standard` returns, minus `knowledge-base/`, `docs/`, binaries, symlinks, the suite's two own files and the structural test class (a `test`/`tests`/`__tests__`/`fixtures` directory or a `.test.`/`.spec.`/`.tftest.hcl` suffix, never under `.github/`; an exempt file still needs a row if it holds a direct-store read shape). A name is matched as a token family, not four literals, and the `ALIAS:*` rows cover the Access token outputs. The derivation is never hand-listed.

**Mutation matrix.**

| # | Edit | Must be |
|---|---|---|
| 1 | Add a new workflow reading `secrets.WEBHOOK_DEPLOY_SECRET` with no baseline row | RED |
| 2 | Add a baseline row for a (file, name) absent at the merge-base copy of `trio-baseline.tsv` | RED (shrink-only) |
| 3 | Leave a baseline row whose consumer no longer reads the name | RED (a fixed consumer must delete its row) |
| 4 | Set a baseline row's expiry to a past date | RED |
| 5 | Add a read of `HCLOUD_TOKEN` to an already-baselined release file | RED (keyed by (file, name), not file) |
| 6 | Point the scan at an empty file set | RED (the census fails on "0 checked") |
| 7 | In a file that already has one compliant `secrets.X` read, add an `env:` passthrough read of a second trio name | RED (the check must not stop at the first member) |
| 8 | Reintroduce the `|| doppler secrets get CI_SSH_ACCESS_TOKEN_ID` fallback in `infra-config-verify.sh` | RED |
| 9 | Make `hooks.json.tmpl` render an `or` with an empty `secret` | RED (no rendered rule may carry an empty secret) |

**Harness rows.** RED: delete the `deploy-channel` entry from the fixture environment set; the row must fail. Must-PASS non-canonical: a consumer that reads the trio through the narrow loader mode with a different step name and indentation than the canonical fixture.

**Anchor.** A baseline row's key, tag, class and expiry are compared to the merge-base copy of `tests/scripts/trio-baseline.tsv` (`git show <base>:<path>`; `HEAD^1` on a main push; an unresolved base is a red row, never a silent pass), so one diff cannot edit both the baseline and the thing it protects; set identity of the rows is checked, not a count. A new key needs an `@allow` already present at the base.

**Where the rows live (review round).** The table above is the plan-level view. The authoritative list is the suite's own mutant matrix (13 original rows plus the 20 review-round rows: test-named and out-of-root consumers, name variants, `ALIAS:*`, tag/class/expiry compare, `@allow`, renames, the unresolved-base and CI-seam refusals, expiry formats and the event table, the stem pin, and a no-op-mutant control). Rows 8 and 9 above need `ci-deploy.sh`-adjacent and render changes that do not exist until PR-2, so they are PR-2 rows, not PR-0 rows; the `deploy-channel` environment harness row is built in PR-0 against a fixture set.

### Guard 2 — the loader's narrow mode and allowlist

**Property.** The loader exports only `soleur-infra-privileged` or `soleur-deploy-channel`; any other value fails closed before any Doppler call; and in narrow mode it never reads `prd_terraform` and never proceeds with an empty token.

**Assembly.** The loader inputs, its `case` statement, its legacy arm, and every caller passing the inputs (derived by grep over `.github`).

**Mutation matrix.**

| # | Edit | Must be |
|---|---|---|
| 1 | Add a third project name to the `case` | RED (the allowlist is pinned to two names) |
| 2 | Pass an unknown project from a caller fixture | RED (the action exits non-zero) |
| 3 | Narrow mode with an empty narrow token | RED unless it fails closed (it must not take the legacy arm) |
| 4 | Make the unknown-value arm warn instead of fail | RED |
| 5 | Let narrow mode export a name that exists only in the privileged project | RED |

**Harness rows.** RED: a fixture where the project input is empty must still select the privileged project and pass the existing rows. Must-PASS: the narrow project with the narrow token.

**Anchor.** The allowlist is compared to the census constants for the two environment names.

## Test Scenarios (offline)
1. Census: each mutation row above reds; the live tree is green with a baseline that exactly matches today's reads.
2. `terraform plan` fixture for PR-2: 0 add, 0 destroy, the policy changes in place, no `client_secret` in the planned state.
3. `hooks.json.tmpl`: a single match for each of the 13 rules when "next" is empty; an `or` of two for all 13 when set; never an empty `secret`.
4. `ci-deploy.sh` fan-out reads the key under both rule shapes.
5. Loader: privileged default; narrow with the narrow token; unknown project fails; narrow with an empty token fails.
6. A `workflow_dispatch` from a non-main ref on a `deploy-channel` job fails by policy (fixture row).

## Acceptance Criteria
- [ ] The census proves neither the Doppler Tier-A copies nor the GitHub repo-secret copies of the three can be named by a workflow that has not passed a main-only environment (narrowed in the review round: the census is a name-reference ratchet, Guard 1a; the final PR asserts zero `tier-a`, `FALLBACK:*` and `ALIAS:*` rows, every `tier-b` row proven to declare a Tier-B environment, and the owner-run postcondition that the live Tier-A and repo-secret copies are gone).
- [ ] All three are rotated; the old HMAC returns 403 and the old Access pair is denied, each probed against a saved old value.
- [ ] ADR-241 carries the D1 census amendment (PR-0) and a closing amendment (final PR).
- [ ] `cloudflare_zero_trust_access_service_token.deploy` is out of the current state with 0 destroys; no secret-bearing Access attribute remains in current state or outputs.
- [ ] The five closed-issue probes are deleted; the `CF_TUNNEL_TOKEN` repo secret is deleted.
- [ ] G1b is tracked under #9294 and not executed in the same window as any step here.
- [ ] #9294 can close; #8609 remains gated on G1b.

## Sharp Edges
- A plan whose `## User-Brand Impact` is empty or unfilled fails `deepen-plan`; this one is filled.
- The Tier-B loader exports the whole selected project: never point a release or followthrough job at `soleur-infra-privileged` for these credentials (Fork 1).
- Never `-replace` the Access token; never print or log any of the values; save old values to 0600 files before any rotation so the negative probe can be proven.
- Do not move the webhook trio and the SSH trio in one window: the SSH bridge is the recovery path for a stranded webhook.
- Each rotation sub-step is its own owner-named command; a menu answer is not authorization.
- An empty HMAC key is forgeable: no rendered rule may carry an empty `secret`.
