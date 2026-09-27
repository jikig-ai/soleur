---
title: "chore(infra): retire the GHCR token minter and the host-side GHCR credential plumbing (ADR-096 task 5.4)"
date: 2026-09-27
slug: chore-retire-ghcr-token-minter-and-host-credential-plumbing
branch: feat-one-shot-8714-5-4-ghcr-minter
issue: 8714
closes: none
lane: single-domain
type: chore
domain: engineering
brand_survival_threshold: none
---

# Retire the GHCR token minter and the host-side GHCR credential plumbing (#8714 task 5.4)

## Overview

Task 5.4 of the ADR-096 GHCR-to-zot migration. Both hosts boot from zot only (#8708), the GHCR read
PAT is revoked, and the control-plane minter (ADR-088) has been disabled since July behind
`GHCR_MINTER_DISABLED=true`. What is left is dead plumbing that still does two harmful things:

1. It keeps the revoked `GHCR_READ_TOKEN` / `GHCR_READ_USER` in Doppler `soleur/prd`, which
   `ci-deploy.sh` downloads whole into the app container env.
2. It keeps a live **read/write** `soleur/prd` Doppler service token (`ghcr-minter-write-2026-09-25`)
   and its copy `GHCR_MINTER_DOPPLER_TOKEN` in the same config, readable by every prd reader
   (#8737 UC-1; #8714 comment asks for 5.4 before the encryption-posture exception expiry).

This PR deletes the Terraform resources, the variables, the Inngest function and its test and
wiring, and the now-dead follow-through probe, and rewords the comments/docs that describe the
deleted objects as live. The per-merge apply destroys the four Doppler objects via the bare
`-target` lines that stay in `apply-web-platform-infra.yml` for this merge (precedent #9062), with
`[ack-destroy]`.

Out of scope (separate PRs on #8714): 5.3b-iii (cosign/zot image moves, egress allow) and 5.6 (ADR-096
flip). PR body carries `Ref #8714`, not `Closes`.

## Research Insights

Research was performed directly by the planning agent (commands below), not through the research
sub-agent fan-out: the whole task is a consumer census, which the operator required be run by grep
over the whole repo, and the machine is CPU-contended.

### Premise Validation

- #8714 OPEN; 5.4 unchecked. Its only comment (the #8737 carry-over) states the retirement trap: the
  destroying merge must KEEP `-target=doppler_service_token.ghcr_minter` /
  `-target=doppler_secret.ghcr_minter_doppler_token` (and the two `ghcr_read_*` targets) so the
  deletes are planned; a follow-up removes the targets. Held.
- #9062 (PR-B, merged e980b9bfc8) is the bare-target destroy precedent: it destroyed
  `doppler_secret.zot_heartbeat_url_prd` with the resource deleted and the `-target` kept, plus
  `[ack-destroy]` on its own line in both the branch commit and the squash body. Its merge apply
  (run 36331513256) planned `1 to import, 2 to add, 0 to change, 1 to destroy` and succeeded, so
  the next main plan starts from 0 destroys.
- #8852/#9029: the `ghcr_minter` token was rotated (rename + create_before_destroy) and the recovery
  ack merged. Live prd tokens (read 2026-09-27): `terraform-prd-20260730`,
  `web-probes-read-2026-09-24`, `github-ci-prd`, `token-drift-ci-tf-prd`,
  `ghcr-minter-write-2026-09-25` (slug 1df8edd4, read/write). This PR deletes, not rotates, so it
  cannot collide with the rotation mechanics; the `create_before_destroy` lifecycle is irrelevant
  to a pure delete.
- #6031 (the minter feature) CLOSED 2026-07-06; its follow-through probe
  `scripts/followthroughs/ghcr-minter-live-6031.sh` polls a Sentry monitor
  (`scheduled-ghcr-token-minter`) that was removed from IaC in July. The sweeper's closed-set
  lookback is 14 days (`CLOSED_LOOKBACK_DAYS`), so the probe is never evaluated.
- The GitHub App manifest's `packages: read` grant exists only for the minter. Removing it from the
  manifest while the live App still carries it makes `cron-github-app-drift-guard` report
  `permission_unexpected_grant` (`server/github/manifest-diff.ts`), so the manifest change must be
  paired with a live-App permission change and org re-consent. That is not a Terraform-reachable
  change; it is deferred to an issue (see Deferrals).

### Property List

- P1. No Doppler config in project `soleur` holds `GHCR_READ_TOKEN`, `GHCR_READ_USER` or
  `GHCR_MINTER_DOPPLER_TOKEN` after the merge apply (so the next deploy's container env lacks them).
- P2. The read/write service token `ghcr-minter-write-2026-09-25` no longer exists.
- P3. No code, IaC, workflow or test in the repo keeps a live reference to the deleted objects (the
  census below reaches zero live consumers; historical records are left).
- P4. The deploy, the Inngest function registry and every count/parity test stay green with one
  fewer function (70 -> 69 served functions in `route.ts`).
- P5. The merge apply's plan contains exactly the four intended deletes and nothing else destructive.

### Cut List

- Removing the four `-target` lines in this PR -> would stop the deletes being planned (P5 fails:
  zero destroys, objects survive in state and Doppler). Kept; removal deferred to a follow-up after
  the apply (Deferrals).
- `removed { from = ...; destroy = false }` blocks -> would forget the objects and leave the values
  in Doppler (P1/P2 fail). Not used.
- Manual `doppler secrets delete` of the TF-managed keys -> the Terraform destroy already buys
  P1/P2, audited in the apply log. Not used.

### Consumer census (run 2026-09-27 against origin/main e980b9bfc8)

Command (whole repo, every spelling, case-insensitive):

```text
git grep -nIiE 'ghcr[_-]read|ghcr[_-]minter|ghcr-token-minter|ghcr_token|GHCR_USER|ghcrTokenMinter|ghcr-minter' -- ':!knowledge-base'
```

49 files outside `knowledge-base/` (plus the `GHCR_MINTER_DISABLED`, `prd_ghcr`,
`token-minter.mint-now`, `findInstallationByAccountLogin`, `packages:read` side-greps). Dispositions:

| Hit | Disposition |
|---|---|
| `apps/web-platform/infra/ghcr-minter-doppler-token.tf` (service token + `GHCR_MINTER_DOPPLER_TOKEN`) | **delete** (destroyed by the merge apply) |
| `apps/web-platform/infra/ghcr-read-credential.tf` (`doppler_secret.ghcr_read_user/_token`) | **delete** (destroyed by the merge apply) |
| `apps/web-platform/infra/variables.tf` `var.ghcr_read_user`, `var.ghcr_read_token` + comment | **delete** |
| `apps/web-platform/infra/tests/web-hosts-eu-pin.tftest.hcl` dummy `ghcr_read_*` values | **delete** (an undeclared variable in a test `variables` block errors) |
| `apps/web-platform/server/inngest/functions/cron-ghcr-token-minter.ts` | **delete** |
| `apps/web-platform/test/server/inngest/cron-ghcr-token-minter.test.ts` | **delete** |
| `apps/web-platform/app/api/inngest/route.ts` import + `functions` entry | **edit** (remove) |
| `apps/web-platform/server/inngest/cron-manifest.ts` `EXPECTED_CRON_FUNCTIONS` entry | **edit** (remove; also removes it from the manual-trigger allowlist, which derives from it) |
| `apps/web-platform/server/inngest/routine-metadata.ts` entry | **edit** (remove; `routine-metadata-parity.test.ts` pins keys = manifest) |
| `test/server/inngest/function-registry-count.test.ts` count 70 + `KNOWN_UNMONITORED_SLUGS` entry | **edit** (69; drop the exemption) |
| `test/server/inngest/sentry-monitor-iac-parity.test.ts` `DISABLED_CRON_SLUG_EXEMPTIONS` | **edit** (drop the entry) |
| `test/server/inngest/cron-shared.test.ts` "minter is live" case | **edit** (delete the case) |
| `test/server/inngest/cron-safe-commit-parity.test.ts` "#6031 non-git cron" describe | **edit** (delete the describe) |
| `test/github-app-manifest-parity.test.ts` `packages: read` comments | **edit** (comment only: the grant has no consumer after 5.4; removal deferred, see Deferrals). Assertion kept — it still blocks a `packages: write` escalation |
| `scripts/followthroughs/ghcr-minter-live-6031.sh` | **delete** (dead probe, see Premise Validation) |
| `.github/workflows/apply-web-platform-infra.yml` four `-target` lines | **keep this PR** (plans the deletes); removal deferred |
| `apps/web-platform/infra/zot-registry.tf` comment citing both deleted files as shape precedents | **edit** (describe the shape without the dead file names) |
| `apps/web-platform/infra/inngest-betterstack-token.tf` two "mirrors ghcr-read-credential.tf" comments | **edit** |
| `apps/web-platform/infra/inngest-host.tf` "`var.ghcr_read_*` survives ... until task 5.4" | **edit** |
| `apps/web-platform/infra/token-drift-read-tokens.tf` blast-radius/rename-route comments naming `ghcr_minter` / `GHCR_MINTER_DOPPLER_TOKEN` | **edit** (mark retired) |
| `apps/web-platform/infra/zot-entry-gate.sh` "(task 1.8) + backfilled (task 1.9)" phrasing (named on #8714) | **edit** |
| `scripts/encryption-posture-ledger.json` evidence citing `ghcr-minter-doppler-token.tf:36` | **edit** (the cited file is deleted) |
| `apps/web-platform/infra/scripts/web-probes-token-rotation-verify.sh` header naming the #8737 use | historical-record-leave (a generic tool; the header records past uses) |
| `apps/web-platform/infra/server.tf:413`, `ci-deploy.sh` comments (812, 1438, 1577, 1689, 1810, 2016) | historical-record-leave (they narrate #8036 1c/1d; no code reads a GHCR credential) |
| `ci-deploy.test.sh`, `cloud-init-ghcr-seed-login.test.sh`, `cloud-init-inngest-bootstrap.test.sh`, `cloud-init-web-zot-seed.test.sh`, `soleur-host-bootstrap-observability.test.sh`, `inngest-boot-emitter.test.sh` | keep — negative guards asserting the host-side GHCR credential stays ABSENT; they stay valid and green |
| `apps/web-platform/infra/sentry/cron-monitors.tf:1149` comment, `.github/workflows/apply-sentry-infra.yml:18`, `apps/web-platform/scripts/sentry-monitors-audit.sh:1276`, `tests/scripts/test-sentry-monitors-audit-class-d.sh:258` | historical-record-leave (the monitor's removal in July; editing the sentry root re-runs its apply for nothing) |
| `.github/workflows/reusable-release.yml:908,1248` | historical-record-leave (why the release does not use GHCR reads) |
| `.github/workflows/apply-web-platform-infra.yml:3380,3990`, `scripts/registry-restore-from-ghcr.sh`, `scripts/registry-pull-path-health.sh` (`GHCR_USER`/`GHCR_TOKEN` = the Actions `GITHUB_TOKEN`) | keep — a different credential (CI-side restore source, ADR-169) |
| `scripts/followthroughs/ghcr-read-retired-8036.sh` + test, `suite-shard-legs.tsv`, `test-all.sh`, `sweep-followthroughs.sh`, `zot-login-gate-erofs-repaired-6565.sh` | keep — journald probe of the #8036 1c deploy path, reads no Doppler key |
| `scripts/followthroughs/inngest-soak-6178.sh` | historical-record-leave (explains a past catch-up window) |
| `scripts/lint-followthrough-varq-ban.sh:35`, `scripts/rotate-sentry-actions-ro-token.sh:209` | historical-record-leave (examples in comments; both files are shell-lint baselined, so a drive-by edit owes unrelated debt) |
| `plugins/soleur/test/preflight-discoverability-test.test.ts:2735` | historical-record-leave (a plan-file count note) |
| `apps/web-platform/infra/doppler-config-inventory.txt` `prd_ghcr`, `scripts/check-cloudflare-token-drift.test.sh` fixtures | keep — the `prd_ghcr` config still exists live; its removal is deferred |
| `findInstallationByAccountLogin` (`server/github-app.ts`) | keep — second caller at `github-app.ts:646` |
| C4 `model.c4` minter comment + edges `inngest -> github` ("Mints packages:read ...") and `inngest -> doppler` ("Writes GHCR_READ_TOKEN ...") | **edit** (delete both edges and the comment; regenerate `model.likec4.json` if the gate requires it) |
| ADR-096 "remain until 5.4" bullet; ADR-088 (status already `superseded`) | **edit** (ADR-096 amendment for 5.4; ADR-088 note that the implementation is deleted) |
| `runbooks/zot-registry-revert.md` "minter is disabled (`GHCR_MINTER_DISABLED=true`)" | **edit** (minter deleted) |
| `runbooks/infra-credential-tiers-8209.md` O12b | historical-record-leave (a dated determination) |
| `knowledge-base/project/{plans,specs,learnings}`, post-mortems (105 files) | historical-record-leave |

Suites that were checked and hold no hit: `terraform-target-parity.test.ts` (no `ghcr` rows;
`OPERATOR_APPLIED_EXCLUSIONS` has none), `tests/scripts/lib/destroy-guard-filter-web-platform.jq`,
the infra-privileged census, `supabase/` (no migration or seed names the routine).

### Live state (names only, never values)

- Doppler `soleur`: `GHCR_READ_TOKEN`, `GHCR_READ_USER`, `GHCR_MINTER_DOPPLER_TOKEN`,
  `GHCR_MINTER_DISABLED` present in `prd` and, with identical value hashes, in
  `prd_terraform`, `prd_ghcr`, `prd_scheduled`. [Updated 2026-09-27, review] Identical hashes do not
  prove inheritance: the structural review read Doppler's log and found `prd_terraform` holds its
  OWN `GHCR_READ_USER`/`GHCR_READ_TOKEN` entries (written 2026-07-05, before `prd` root had them), so
  a root delete likely leaves those two there. Tracked on #9080. Absent from `dev`, `ci`, `soleur-inngest/prd`,
  `soleur-registry/prd`, `soleur-infra-privileged/prd`.
- `GHCR_MINTER_DISABLED` is NOT Terraform-managed. After this PR no code reads it; deleting it is a
  manual prd write and is left for an explicit operator go-ahead (Deferrals).
- The Terraform runner reads `prd_terraform` with `--name-transformer tf-var`, so
  `TF_VAR_ghcr_read_*` stops existing when the prd keys are destroyed. Terraform ignores
  environment `TF_VAR_*` values for undeclared variables, so the ordering (variable removed in the
  same plan that destroys the key) is safe.
- GitHub: no repo secret, repo variable, org secret, or environment secret/variable in any of the 8
  environments has a GHCR name. Nothing to remove there.

### Relevant learnings

- `2026-09-27-an-import-block-breaks-terraform-test-and-a-count-ack-reaches-every-destroy.md`:
  `[ack-destroy]` is a boolean over `destroy_count`; anything else destructive in the same plan
  rides the ack. Verify the plan comment before merge and merge only when no apply is queued.
- `security-issues/2026-09-25-doppler-token-rotation-with-a-secret-consumer-and-revoke-first-removes-the-blanket-ack.md`
  and #8737: the token listing API lags; verify from the apply log, not a single listing read.

## Implementation Phases

### Phase 1 — RED

1. Add a describe `#8714 5.4 GHCR minter retirement: bare -targets destroy the four Doppler objects`
   to `plugins/soleur/test/terraform-target-parity.test.ts` (Guard 1 below). Raise `TEST_FLOOR` by
   the number of `test(` calls added. Run it: RED against the current tree.
2. Update the app tests to the post-retirement shape (count 69, exemptions removed, minter cases
   deleted). `function-registry-count` (a) and the cron-file/manifest set equality go RED until the
   function file and wiring are removed.

### Phase 2 — GREEN

1. Delete the two `.tf` files, the two variables, the tftest dummies.
2. Delete the Inngest function + its test; remove route/manifest/metadata entries.
3. Delete `scripts/followthroughs/ghcr-minter-live-6031.sh`.
4. Comment/doc edits per the census table; C4 edges; ADR-096 amendment; ADR-088 note; runbook line.

### Phase 3 — Verify locally (targeted, CPU-contended host)

- `bun test plugins/soleur/test/terraform-target-parity.test.ts`
- vitest: `function-registry-count`, `sentry-monitor-iac-parity`, `cron-shared`,
  `cron-safe-commit-parity`, `routine-metadata-parity`, `github-app-manifest-parity`, and any
  trigger-cron allowlist test (grep `manual-trigger-allowlist` under `test/`).
- `terraform fmt -check -recursive`, `terraform init -backend=false && terraform validate`,
  `terraform test` in `apps/web-platform/infra`.
- `bash plugins/soleur/test/c4-count-parity.test.sh`, C4 syntax/render tests.
- `python3 scripts/lint-encryption-posture.py` (+ its test), `lint-infra-no-human-steps --changed`,
  markdownlint on changed `.md`.
- `bunx tsc --noEmit` scoped to web-platform if feasible.

### Phase 4 — Ship

- Branch commit carries `[ack-destroy]` on its own line. PR body `Ref #8714`.
- Before merge: infra-validation green on the PR head; its plan comment lists exactly the four
  deletes (`doppler_secret.ghcr_read_user`, `doppler_secret.ghcr_read_token`,
  `doppler_secret.ghcr_minter_doppler_token`, `doppler_service_token.ghcr_minter`) and no other
  destroy/replace; nothing queued or in progress on `apply-web-platform-infra.yml`.
- Merge with `gh pr merge --squash --body-file <file>` whose body keeps a line exactly `[ack-destroy]`.
- Post-merge: the merge apply succeeds with `Plan: 0 to add, 0 to change, 4 to destroy.` (plus any
  in-place updates a sibling merge brings, which must be read); Doppler names gone from all four
  prd-family configs; `ghcr-minter-write-2026-09-25` gone from the token list (read after the apply,
  twice, per the listing-lag learning); release + deploy workflows green; tick 5.4 on #8714 with
  evidence.

## Deferrals

[Updated 2026-09-27] Both deferrals below are consolidated on #9080.

- **Remove the four bare `-target` lines** (and this PR's parity describe rows that require them)
  once the merge apply shows the destroys applied. Same class as the `zot_heartbeat_url_prd` item on
  #9060. File as its own issue, re-evaluate after this PR's merge apply concludes `success`.
- **Non-Terraform residue** (needs operator go-ahead or a browser/App-owner action): delete
  `GHCR_MINTER_DISABLED` from Doppler prd (dead flag, no reader after deploy); decide whether to
  retire the `prd_ghcr` branch config (and its TF-managed `token-drift-ci-tf-prd_ghcr` read token,
  `doppler-config-inventory.txt`); drop `packages: read` from the live GitHub App and then from the
  manifest + parity test in one change (a manifest-only drop pages `permission_unexpected_grant`).
  File as one issue.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — the minter has been a no-op
since July and no host reads these keys. The realistic break is operational: a merge apply that
halts on the destroy guard (missing ack) blocks every later web-platform merge apply until a
recovery ack merge, and a deploy regression if the app build breaks on a dangling import.

**If this leaks, the user's data is exposed via:** nothing new — the change removes a read/write
`soleur/prd` Doppler credential (whose leak would expose every prd secret, including the Supabase
service-role key) and a revoked PAT. It strictly shrinks the exposure surface.

**Brand-survival threshold:** none

- threshold: none, reason: deletes a disabled function and dead credentials; no user data path, auth flow or schema changes, and the removed service token only reduced security while it existed.

## Observability

```yaml
liveness_signal:
  what: the per-merge apply's plan/apply lines ("Plan: ... 4 to destroy", "Apply complete! ... 4 destroyed") in the apply-web-platform-infra run log
  cadence: once, at the merge apply
  alert_target: the workflow's failure notification (a halted or failed apply is red on main)
  configured_in: .github/workflows/apply-web-platform-infra.yml
error_reporting:
  destination: GitHub Actions run status on main (+ the destroy-guard ::error:: lines)
  fail_loud: true
failure_modes:
  - mode: merge body lost the [ack-destroy] line
    detection: destroy guard HALT in the apply job
    alert_route: red apply run on main; recovery is a one-line [ack-destroy] PR
  - mode: a dangling reference to the deleted function breaks the build
    detection: CI test/tsc on the PR, then the release workflow
    alert_route: red PR checks (blocks merge)
  - mode: a stale Inngest registration of cron-ghcr-token-minter survives the app sync
    detection: registry probes read only non-zero counts (scheduled-inngest-health fails only on an EMPTY registry), so a 70->69 drop is not a failure; a stale entry would be a no-op function the app no longer serves
    alert_route: none needed (Inngest archives functions the app stops serving at sync)
logs:
  where: GitHub Actions logs for apply-web-platform-infra and the release/deploy runs
  retention: GitHub default (90 days)
discoverability_test:
  command: bash -c "git grep -qE 'resource \"doppler_(secret|service_token)\" \"ghcr_' -- apps/web-platform/infra && echo PRESENT || echo RETIRED"
  expected_output: "RETIRED"
```

## Encryption Posture

No persistent store and no cross-component connection is introduced; `.tf` edits only delete
resources. The deleted service token's `key` leaves `terraform.tfstate` (R2, server-side encrypted)
at the apply. No exception block is added or changed; the ledger's evidence string loses a citation
to a deleted file.

## Architecture Decision (ADR/C4)

### ADR

- Amend ADR-096: record task 5.4 done (what was deleted, the destroy route, what remains:
  `GHCR_MINTER_DISABLED`, `prd_ghcr`, the App `packages: read` grant, the target cleanup).
- ADR-088 is already `superseded`; add a one-line note that its implementation is deleted (#8714 5.4).

### C4 views

Container view: delete the two minter edges (`inngest -> github` mint, `inngest -> doppler` write
GHCR_READ_TOKEN) and their comment in `model.c4`. Elements `inngest`, `github`, `doppler` stay (other
edges use them). Checked against `model.c4`, `views.c4`, `spec.c4`: no element exists only for the
minter; the `ghcr` registry element stays (CI still pushes to it). `c4-count-parity.test.sh` must be
green after the edit.

### Sequencing

None: the decision is true at merge (the apply deletes the objects in the same pipeline).

## Guard Contract

### Guard 1 — the four GHCR Doppler objects are destroyed by bare -target, never kept or forgotten

**Property.** The per-merge saved plan targets all four addresses while no `.tf` file declares,
names, or forgets any of them, and the two `ghcr_read_*` variables are gone, so the merge apply
plans their deletion.

**Assembly.** The saved-plan command inside the `apply` job of
`.github/workflows/apply-web-platform-infra.yml` (the `terraform plan ... -out=tfplan` command, read
by `commandIn`/`extractAllTargets`), and every `*.tf` file under `apps/web-platform/infra` (read by
`listInfraTfFiles`, comments stripped). The addresses: `doppler_secret.ghcr_read_user`,
`doppler_secret.ghcr_read_token`, `doppler_service_token.ghcr_minter`,
`doppler_secret.ghcr_minter_doppler_token`.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete one of the four `-target` lines | RED (address absent from `planTargets`) |
| 2 | Target an address with an instance key (`-target=doppler_secret.ghcr_read_token[0]`) | RED (bare-target row) |
| 3 | Restore `resource "doppler_secret" "ghcr_read_token"` in any `.tf` | RED |
| 4 | Add `removed { from = doppler_service_token.ghcr_minter ... }` | RED |
| 5 | A second resource publishing `name = "GHCR_MINTER_DOPPLER_TOKEN"` | RED |
| 6 | A module-subdirectory resource naming `ghcr_read_token` in any spelling | RED (recursive no-mention row) |
| 7 | Re-add `variable "ghcr_read_user"` | RED |
| 8 | Dispatch: the describe reads a job with no targets | RED (`github_app_id` non-vacuity) |

**Harness rows.** Must-PASS: the real tree after the change. RED on the suite side: removing the
`test(` from the describe lowers the count below the raised `TEST_FLOOR`.

**Anchor.** The addresses are literals in the test and the workflow; one diff could edit both, which
is accepted here because the post-merge verification reads the live apply log, not the test.

### Guard 2 — the census allows a deleted resource block only as a listed, bare-targeted intended destroy

**Property.** `tests/scripts/test-infra-privileged-tier-census.sh` G4c refuses any resource block the base declares and HEAD deletes without a `removed` block, EXCEPT an address listed in `INTENDED_DESTROYS` that its root's apply still targets bare and that is not the App identity pair (G4f).

**Assembly.** The census's `orphans` loop over `GUARD4_ROOTS`, `root_targets` (every `-target=` in every apply step, keyed by working dir), `INTENDED_DESTROYS` and `G4_PROTECTED` in the same file.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Listed address deleted with no `-target=` line (M-g4-7) | RED (G4c) |
| 2 | Listed address deleted and bare-targeted (M-g4-6) | GREEN (accept arm) |
| 3 | `doppler_secret.github_app_id` added to `INTENDED_DESTROYS` | RED (G4f) |
| 4 | Unlisted address deleted with no `removed` block (existing M-g4-3) | RED (G4c) |

**Harness rows.** The census's control fixture must stay green (H0); `MUTANT_FLOOR` 30 and `FLOOR` 88 are the measured counts.

**Anchor.** The allowance is a literal list in the suite; a merge-base diff reviewer sees any entry added.

## Acceptance Criteria

- [ ] AC1: `ghcr-minter-doppler-token.tf`, `ghcr-read-credential.tf`, `cron-ghcr-token-minter.ts`,
  its test and `ghcr-minter-live-6031.sh` do not exist; `var.ghcr_read_*` and the tftest dummies are gone.
- [ ] AC2: the census grep over non-`knowledge-base` paths returns only rows whose disposition is
  keep / historical-record-leave (re-run and recorded in the PR body).
- [ ] AC3: `route.ts` serves 69 functions; `function-registry-count`, `sentry-monitor-iac-parity`,
  `routine-metadata-parity`, `cron-shared`, `cron-safe-commit-parity` green.
- [ ] AC4: Guard 1 green on the change and each mutation-matrix row turns it RED.
- [ ] AC5: `terraform validate`, `fmt -check`, `terraform test` pass; C4 parity + lint-encryption-posture pass.
- [ ] AC6: infra-validation green on the PR head; its plan comment shows exactly the four deletes.
- [ ] AC7: branch commit and squash body each carry a line exactly `[ack-destroy]`.
- [ ] AC8: merge apply succeeds; its Plan line shows 4 to destroy and no other destructive change.
- [ ] AC9: post-apply, `doppler secrets --only-names` for `prd`, `prd_terraform`, `prd_ghcr`,
  `prd_scheduled` shows none of the three TF-managed GHCR names; `ghcr-minter-write-2026-09-25` is
  absent from `doppler configs tokens -c prd`.
- [ ] AC10: release/deploy for the merge sha succeed; 5.4 ticked on #8714 with an evidence comment.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Deletes-only infra/app change. Risk is operational (destroy guard, build), covered by
the pre-merge plan read, the ack, and the targeted suites. No product, legal, marketing, sales,
finance, support or operations-cost implication (the Doppler plan is unchanged).

## Test Scenarios

- Parity suite with the new describe (RED before, GREEN after, mutation battery in a sandbox copy).
- Vitest suites listed in Phase 3.
- `terraform test` (the tftest file must not pass undeclared variables).

## Open Code-Review Overlap

1 open scope-out touches these files: #8595 (monitor registry guard gaps: NON_INNGEST_MONITORS stale entries, no cadence parity) names `function-registry-count` and `sentry-monitor-iac-parity`. **Acknowledge:** this PR only drops one KNOWN_UNMONITORED / DISABLED exemption for a deleted function; #8595's stale-entry and cadence guards are a different concern. (The `route.ts` hits #2246/#3351/#3739 name other `route.ts` files, not `app/api/inngest/route.ts`.)

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits
  the threshold will fail `deepen-plan` Phase 4.6.
- Do not remove the four `-target` lines in this PR — that silently converts the destroys into a
  no-op and leaves the read/write token live.
- The squash body must be passed with `--body-file`; GitHub's default squash body would drop the
  ack if the PR body lacks it.
- A release deploy that downloads the prd env BEFORE the apply destroys the keys leaves the revoked
  values in the running container until the next deploy. Record the apply/deploy timestamps; both
  values are inert (revoked PAT; revoked service token).
