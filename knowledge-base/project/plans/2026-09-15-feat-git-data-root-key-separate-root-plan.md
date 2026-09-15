---
title: "git-data root access (ADR-220): Terraform-minted root key in a separate root, reviewer-gated read credential, fail-closed read-only dry run, and the replace that delivers it"
date: 2026-09-15
slug: feat-git-data-root-key-separate-root
branch: feat-one-shot-8189-git-data-root-key
issue: 8189
type: feat
lane: cross-domain
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# git-data root access: Terraform-minted key, separate root, reviewer-gated credential

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

Revision v3 (2026-09-15) — after domain review (CTO, CPO, CLO + GDPR gate), spec-flow ×2, a scoped advisor
consult and a seven-agent plan-review panel. Decisions that change the issue's or the operator's stated
shape are recorded in `knowledge-base/project/specs/feat-one-shot-8189-git-data-root-key/decision-challenges.md`.

## Overview

Objective 2 step 2 of the git-data LUKS cutover (#5274, ADR-068). The ADR-220 transport shipped in
0777caa9e; every cutover dispatch stops at the access gate with
`role=git-data-auth verdict=git_data_root_key_absent` (exit 3). This PR:

1. mints the git-data root SSH key in its own Terraform root (additive-only apply, serialized with every
   git-data host mutation), keeps the private half in an isolated Doppler project, and publishes a read
   token that only the reviewer-gated cutover job on `main` uses;
2. hands the public half to the web-platform root through a label-selected data source and makes both
   host-creating gates (replace and birth) refuse a plan that would not carry exactly that key;
3. turns `git-data-cutover.yml` into what it can honestly be until the real cutover is redesigned: a
   reviewer-gated, **read-only** proof — access gate, fail-closed flag read, and fail-closed store probes
   (mounted, not cut over, empty) — and deletes the cutover body whose freeze, reload and rollback call
   systemd units that do not exist;
4. serializes the run with git-data host mutations (`git-data-state`).

Post-merge, with explicit authorization at each prod step: the reviewer-gated apply of the new root, the
`git_data_host_replace` that delivers the key, then a dry run from `main` that must read
`role=git-data-auth verdict=ok` with every store probe clear, and exit 0.

## Blocker triage (inline, per `wg-defer-only-after-inline-triage`)

| Blocker | Disposition | Why |
|---|---|---|
| 1. `read_flag` fails open | **Fixed here** | Fail-closed read under the existing `prd`-scoped read secret, before any store probe |
| 2. `soleur-web` / `soleur-drain` units do not exist | **Removed here; the real mechanism is F2** | There are no real unit names to substitute: the app is a container whose env is fixed at `docker run`. The correct mechanism is a redesign (CTO: drop the hard freeze, since the only writer is gated by the flag; same-version redeploy accepting only a frame started after the flag write; lock-free probe; rollback restarts the webhook unit first; a windowed `prd` flag write token; gc timer stopped before the repoint; resume after a partial repoint). Review found three P0 and six P1 hazards on that path. Every caller of the units is deleted with the functions that held them |
| 3. Post-cutover self-rsync | **Fixed here by construction + probes** | The script no longer contains any rsync, mount or LUKS call (a census asserts it); the dry run refuses `old_store_unmounted`, `already_cut_over` and `store_not_empty`. F2's body carries the endpoint guard (`stat -L` on both repo endpoints, after `mkdir -p`) for when rsync returns |
| 4. No web-1 / git-data serialization | **git-data half fixed here; web-1 half moves to F2 with the first web-1 mutation** | The run holds workflow-level `git-data-state` (replace, create, rehearsal). A read-only dry run that also joined `web-1-swap` could cancel a pending release deploy under #8167 and buys no protection, because it mutates nothing on web-1. F2 joins `web-1-swap` on the job that drains web-1 (DC-5) |

## Research Insights

### Premise Validation (Phase 0.6)

- **#8189** OPEN, the target. **#6680** OPEN (closes after a main dry run reads `role=git-data-auth
  verdict=ok`). **#5274** OPEN. **#8009** CLOSED ("C1 re-approval" = re-approving the recorded
  authorization accounting; obtained from CPO and CTO). **#8167** OPEN.
- Must stay open and are not scoped in: #8101, #8094, #6604, #8202, #7025, #8010.
- **#8093** OPEN. Its "sibling unit names" item is the `sshd` unit name in `cloud-init.yml` /
  `cloud-init-registry.yml`, not blocker 2's units: no overlap. Its replace-environment item is **not**
  taken: `terraform-target-parity.test.ts` pins the replace job's HELD text and calls an environment on
  replace-class targets "a fleet-wide policy call", so taking it would break the 197/0 constraint. The PR
  body carries `Ref #8093` only for the comment this PR posts there (Phase 0).
- The session note `/var/tmp/soleur-session-8a29da98/session-notes.md` carries four post-compound errors
  from PR #8187; this PR's learning absorbs them (Phase 7).

### Measured facts that change the issue's design

1. **ADR-220 D2's custody goal is already unmet.** `prd_terraform` is readable by the
   `secrets.DOPPLER_TOKEN` repo secret, which any branch workflow can name, and holds `DOPPLER_TOKEN_TF`
   (`variables.tf` › `doppler_token_tf`: workplace-scope personal token), `CF_API_TOKEN_R2` (account-wide
   R2; derived S3 keys measured 200 on two buckets), `HCLOUD_TOKEN` and `GITHUB_APP_PRIVATE_KEY`. The repo
   is public, so run logs are public. The separate root's real value: the key never enters the
   web-platform root that dozens of plan/apply jobs read and print from. It does not defend against a
   repo-secret holder (F1; F1 needs its own ADR because it cuts across all roots, ADR-130 and ADR-164).
2. **A dedicated R2 bucket cannot be delivered and would buy nothing.** No token holds `API Tokens:Edit`
   (ADR-130), so only a human dashboard mint could create a bucket token (forbidden by
   `hr-tf-variable-no-operator-mint-default` and the task constraints), and `CF_API_TOKEN_R2` reads any
   bucket. The new root uses `soleur-terraform-state` with its own key — the literal shape of
   `hr-every-new-terraform-root-must-include-an` — and the parent's R2 credentials can read that object
   (stated, DC-1).
3. **A `prd` branch config does not isolate.** A branch-config token resolves ~116 `prd` secrets
   (`workspaces-luks.tf` › "THE MECHANISM IS INHERITANCE DIRECTIONALITY"; learning
   `security-issues/2026-07-07-doppler-branch-config-does-not-isolate-secrets.md`). The key lives in a
   separate Doppler project (zot/inngest precedent, no paid feature).
4. **Doppler OIDC is plan-gated** ("available with our Team and Enterprise plans",
   <https://docs.doppler.com/docs/service-account-identities>); the ledger records the Developer plan and
   config inheritance was measured denied on 2026-07-05 (`ghcr-minter-doppler-token.tf` › "CONTINGENCY
   TAKEN"). ADR fallback taken (DC-3).
5. **`doppler_service_token` has no expiry attribute** (1.21.2 schema: `access config id key name
   project`). A count-toggled window would revoke only the token — the public key stays authorized on the
   host until a replace after a rotation, and the private key stays in state and Doppler — so the window is
   cut (DC-4). Revocation is a reviewed PR that `-replace`s or removes the token.
6. **Environment secrets are not writable by the Terraform App** (403, `inngest-arm-write-token.tf`); repo
   secrets are. The environment is a human gate, not a secret boundary. The reference census prevents
   accidental use only.
7. **Existing environment.** `web-platform-infra-apply` is Terraform-managed (`web-host-birth-environment.tf`),
   reviewer `[54279]`, custom branch policy `main`, used by 5 jobs in `apply-web-platform-infra.yml` and
   the rehearsal. It is recorded as `can_admins_bypass: true`, `prevent_self_review: false`
   (`apply-web-platform-infra.yml` › birth disclosure). Reusing it removes the auto-create-unprotected
   hazard of a new environment name; its weaker properties are stated, not hidden (DC-6).
8. **Flag credentials.** `DOPPLER_TOKEN_WRITE` is `prd_terraform` read/write (`doppler-write-token.tf`), so
   today's `read_flag` gets a scope error that `|| echo ""` turns into "unset". `DOPPLER_TOKEN_PRD` exists
   as a repo secret, `prd`-root-scoped, used for reads (`apply-web-platform-infra.yml` ›
   "DOPPLER_TOKEN_PRD, NOT the generic DOPPLER_TOKEN"; ADR-164). A read needs nothing new.
9. **Neither systemd unit exists.** `soleur-web.service` / `soleur-drain.service` appear only in
   `git-data-cutover.sh` and ADR prose. The app is `soleur-web-platform` (`ci-deploy.sh` › `docker run
   ... --env-file` from `doppler secrets download --config prd`); `docker start` keeps the old env;
   `webhook.service` has no `KillMode`; ADR-119's freeze carries a dead-man timer; the only writer
   (`replicateToGitData`) runs only when the container's flag is `true`. All carried into F2.
10. **Self-rsync hazard (measured on `origin/main` bytes).** After `repoint_luks_mount`, a later dry run
    mounts the mapper at `FRESH_ROOT`, passes both `mountpoint` checks, reads "" from `read_flag`, and runs
    `rsync --delete` with source and destination on one filesystem.
11. **Concurrency pins count one file.** `terraform-target-parity.test.ts` and
    `git-data-rung2-rehearsal.test.sh` count `^\s{6}group: git-data-state` in `apply-web-platform-infra.yml`
    only (exactly 2). A workflow-level group in `git-data-cutover.yml` and a job-level group in a new
    workflow leave them green. A run waiting on approval holds its groups; a newer pending entry cancels an
    older one (#8167).
12. **Placement.** A root nested under `apps/web-platform/infra/` collapses to the parent in
    `infra-validation.yml` › `detect-changes` (pinned by `plugins/soleur/test/infra-validation-detect.test.sh`
    TS2), so the PR `plan` job never initializes it; `fmt -check -recursive` reaches it; the rung-2
    rehearsal root is validated by its own `infra-validation.yml` step with `TF_DATA_DIR` under
    `runner.temp`; the parity coverage walk is non-recursive; `scheduled-terraform-drift.yml` runs two legs
    (web-platform, infra/github).
13. **Plan JSON shape.** A data source read during plan appears in `.prior_state.values.root_module.resources[]`
    (`mode == "data"`), not in `resource_changes[]` (a deferred read shows there as `read`). hcloud 1.63.0
    `hcloud_ssh_keys.ssh_keys[].id` is a number; `hcloud_server.ssh_keys` is `list(string)`.
14. **The web-platform root change is inert on the live host.** `hcloud_server.git_data` keeps
    `ignore_changes = [ssh_keys]`; `with_selector` returns an empty list when absent; `git-data.tf` is not a
    rung-2 bound file (hash stays `5c50797be839…`).

### Property List (Phase 0.6b)

- P1. The cutover job authenticates to root on git-data through the ADR-220 jump, end to end.
- P2. The root private key is never in web-platform Terraform state, `prd_terraform`, or `prd`.
- P3. On `main` workflow bytes, the key is read only by a job that passed a human approval.
- P4. A flag read error stops the run (fail closed), and a `true` flag is refused.
- P5. No workflow or script path can call a host mechanism that does not exist.
- P6. No run proceeds on an unmounted, already cut over, or non-empty store; no rsync exists to target
  its own source.
- P7. A cutover run never overlaps a git-data replace, create or rehearsal, and a root-key apply never
  overlaps a replace.
- P8. Host-chosen bytes never become a compared value without validation.
- P9. The key reaches the host only through a create (replace or birth), and a create that would not
  carry exactly that key fails closed.

### Cut List (Phase 0.6b)

- Dedicated R2 bucket → P2 → unachievable and not protective (DC-1).
- `prd_git_data_root` branch config → P3 → full-`prd` token; separate project.
- Key-bearing resources in the web-platform root → P2 → moved to the new root.
- Doppler OIDC identity → P3 → plan-gated (DC-3).
- A new `git-data-cutover` environment, its policy, a preflight env-assert script and job → P3 → the
  existing `web-platform-infra-apply` environment already gates on `main` with a reviewer (DC-6).
- An `approve` job split from the key job → P7 → its only purpose was keeping an approval wait off
  `web-1-swap`, which the read-only job no longer joins; a single gated job also re-asks approval on re-run.
- `access_window_open` count toggle → none → revokes the token only (DC-4).
- A new `prd` read/write flag token → P4 → a read needs only `DOPPLER_TOKEN_PRD`; writing is F2.
- The cutover body (`prepare_luks_target`, `bulk_rsync`, `delta_rsync`, `verify_set_identity`,
  `repoint_luks_mount`, `canary_luks_device`, `old_volume_wipe`, `acquire_freeze`, `release_freeze`,
  `flip_flag_and_reload`, `rollback`, `web_ssh`, the recovery trap) → P5/P6 → unreachable, premised on
  nonexistent units, and to be redesigned by F2; git history keeps it (DC-2).
- `dry_run`, `rollback`, `confirm_wipe` inputs → P5 → removed so no dispatch can request a real mode.
- Host-output display pipe (`_host_out`) → P8 → no remaining display call outside the access gate's
  existing sanitized path.
- Cross-root label-parity guard → P9 → the create gate already refuses a label drift (zero matches).
- An Actions-API exclusion script → P7 → workflow-level + job-level group pattern already exists.
- `environment:` on `git_data_host_replace` (#8093 item) → none → breaks the pinned parity assertion.
- Bridge-side `ssh_config` writer; a resource `precondition` on `hcloud_server.git_data` → P1/P9 → bridge
  Guard 2 pins its exports; a precondition would fail every web-platform plan.
- Direct repo secret holding the key (simplicity suggestion) → not cut: AP-008 and the operator's "read
  credential" direction keep the Doppler hop (DC-7).

### Institutional learnings applied

- `security-issues/2026-07-23-new-tf-resource-in-target-scoped-apply-root-and-unprotected-env-autocreate.md`
  — dissolved by reusing an existing environment; no branch dispatch of `git-data-cutover.yml`.
- `security-issues/2026-07-07-doppler-branch-config-does-not-isolate-secrets.md` — Insight 3.
- `best-practices/2026-07-05-cross-pipeline-serialization-via-shared-job-level-concurrency-group.md`.
- `best-practices/2026-06-18-live-credential-rotation-and-argv-to-env-redeploy.md` — no `ignore_changes`
  on the repo secret.
- `best-practices/2026-07-08-doppler-secret-precedent-mirror-tf-managed-project-needs-references.md`.
- `integration-issues/2026-04-05-terraform-doppler-dual-credential-pattern.md`.
- `security-issues/2026-05-25-terraform-show-json-leaks-sensitive-variables-into-fixtures.md` — gate
  fixtures synthesized; the root's plan file is never uploaded or shown.
- `workflow-patterns/2026-07-19-real-cutover-routes-to-workflow-dispatch-and-failclosed-gate-must-self-report.md`.

### CLAUDE.md / constitution conventions

AP-001, AP-003, AP-008; `hr-prod-host-config-change-immutable-redeploy`; `hr-no-ssh-fallback-in-runbooks`;
`hr-github-app-auth-not-pat`; `cq-cite-content-anchor-not-line-number`; `cq-test-fixtures-synthesized-only`;
`cq-assert-anchor-not-bare-token`.

### Baselines (measured on this branch, pre-edit)

- `bun test plugins/soleur/test/terraform-target-parity.test.ts` → **197 pass / 0 fail**.
- `bash tests/scripts/test-git-data-host-replace-gate.sh` → 23 passed / 0 failed.
- `bash tests/scripts/test-git-data-host-birth-gate.sh` → 114 passed / 0 failed.
- `bash apps/web-platform/infra/git-data-cutover-access.test.sh` → 69 passed / 0 failed / 0 skipped.
- `git_data_rung2_rehearsal_gate` → `RELEASED … 5c50797be8392fe551a940ae04555c52a3f4409cf249ed11bb1280fec783d5b1`.
- Doppler CLI v3.75.3: `doppler secrets get` has `--plain`, `--json`, `--no-exit-on-missing-secret`
  (`doppler secrets get --help`, 2026-09-15).

## Research Reconciliation — Spec vs. Codebase

| Issue / ADR claim | Measured reality | Plan response |
|---|---|---|
| Key in `prd_git_data_root` under `soleur/prd` | Branch-config tokens resolve ~116 `prd` secrets | Separate Doppler project `soleur-git-data-root` |
| Dedicated R2 bucket isolates the root | Nothing can mint a bucket token; `CF_API_TOKEN_R2` reads every bucket | Shared bucket, own key (DC-1) |
| `doppler_config` + `doppler_secret` in the web-platform root | Would put the key in web-platform state | All key-bearing resources in the new root |
| OIDC preferred | Plan tier lacks identities | Repo-secret read token used by one gated job (DC-3) |
| A `git-data-cutover` environment | An equivalent Terraform-managed environment exists | Reuse `web-platform-infra-apply` (DC-6) |
| Mint-time expiry; window-scoped credential (D3) | No expiry attribute; a window revokes the token only | Token persists until a reviewed `-replace`/removal (DC-4) |
| Host "revoked at the next replace" (D3) | `prevent_destroy` + the create gate make every replace carry the same key | Host authorization ends only at a replace after a rotation |
| Freeze/reload via systemd units | Units do not exist | Cutover body deleted; F2 (DC-2) |
| Rollback split into ungated flag-off + gated sentinel (D2) | No rollback exists to split | F2 |
| `DOPPLER_TOKEN_WRITE` does the flag flip | `prd_terraform`-scoped | Not referenced; flag read via `DOPPLER_TOKEN_PRD` |
| "Once #8189 lands a dry run is no longer non-mutating" | This PR keeps it read-only | ADR-220 Consequences amended |
| Runbook: "reload both hosts", web-2 | web-2 retired (#6538) | Runbook sweep |

## Design

### D-1. The new root: `apps/web-platform/infra/git-data-root-key/`

Nested beside `rung2-rehearsal/`. Backend `soleur-terraform-state`, key
`web-platform/git-data-root-key/terraform.tfstate` (R2 block copied from `apps/web-platform/infra/main.tf`).
Providers pinned to the parent lock (doppler 1.21.2, hcloud 1.63.0, tls 4.3.0, github 6.12.1). Variables
reuse `prd_terraform` names via `--name-transformer tf-var` (`hcloud_token`, `doppler_token_tf`,
`github_app_id`, `github_app_private_key`): no new sensitive variable, no default, no human mint.
Cross-resource values are passed by reference.

| Address | Purpose | Lifecycle |
|---|---|---|
| `tls_private_key.git_data_root` | ED25519 root key | `prevent_destroy = true` |
| `hcloud_ssh_key.git_data_root` | name `soleur-git-data-root`, `labels = { "soleur-role" = "git-data-root" }`, `public_key = tls_private_key.git_data_root.public_key_openssh` | `prevent_destroy = true` |
| `doppler_project.git_data_root` + `doppler_environment.git_data_root_prd` | isolated project, root config `prd` | `prevent_destroy = true` on the project |
| `doppler_secret.git_data_root_ssh_private_key` | `GIT_DATA_ROOT_SSH_PRIVATE_KEY` = `private_key_openssh`, `visibility = "masked"` | `prevent_destroy = true` |
| `doppler_service_token.git_data_root_read` | read-only on the isolated config | — |
| `github_actions_secret.doppler_token_git_data_root` | repo secret `DOPPLER_TOKEN_GIT_DATA_ROOT` | no `ignore_changes` |

Applied by `.github/workflows/apply-git-data-root-key.yml`: `push` to `main` on the root's path plus
`workflow_dispatch`; one job with `environment: web-platform-infra-apply` and job-level
`concurrency: { group: git-data-state, cancel-in-progress: false }` (so a root-key apply cannot run between
a replace's `plan -out` and its `apply`); raw R2 creds exported; `terraform init`; `plan -out`; an
**additive-only refusal** over `terraform show -json` piped straight into `jq` (never printed, never
uploaded): any `delete`, `update` of the key/secret/project, or replace action → refuse
`verdict=git_data_root_key_non_additive`, with the single exception of
`doppler_service_token.git_data_root_read` and its repo secret when `workflow_dispatch` input
`rotate_read_token == ROTATE-GIT-DATA-ROOT-READ-TOKEN`; then `apply` of the saved plan.
`apply-web-platform-infra.yml` gains `!apps/web-platform/infra/git-data-root-key/**`; `infra-validation.yml`
gains a validate step for the root modeled on the rung-2 rehearsal root's (`terraform init -backend=false`,
`TF_DATA_DIR` under `runner.temp`).

### D-2. The web-platform root and the shared create-gate arm

`git-data.tf`: `data "hcloud_ssh_keys" "git_data_root" { with_selector = "soleur-role=git-data-root" }` and
`ssh_keys = concat([hcloud_ssh_key.default.id], [for k in data.hcloud_ssh_keys.git_data_root.ssh_keys : tostring(k.id)])`.
`ignore_changes = [ssh_keys]` stays; no `terraform_remote_state`.

New `tests/scripts/lib/git-data-root-key-arm.sh` defines `git_data_root_key_arm <plan.json>`, sourced by
both `git-data-host-replace-gate.sh` and `git-data-host-birth-gate.sh`. Over the saved plan JSON it requires:
`data.hcloud_ssh_keys.git_data_root` present in `.prior_state` (absent, or a deferred `read` in
`resource_changes[]` → refuse); exactly one resolved key, named `soleur-git-data-root`; and for every
created `hcloud_server.git_data`, `after.ssh_keys` equal **as a set** of size two to the default key's id
and that key's id, compared as strings. Refusal: `verdict=git_data_root_key_not_in_create` with the remedy
line "dispatch apply-git-data-root-key.yml, then re-dispatch; after a rotation, the previous key stops
authenticating at this create". Neither gate's allow-set literal changes.

### D-3. Fail-closed flag read (blocker 1)

`read_flag` binds `DOPPLER_TOKEN="$DOPPLER_FLAG_READ_TOKEN"` for one call of `doppler secrets get
"$FLAG_NAME" --plain --no-exit-on-missing-secret -p soleur -c prd` (Phase 0.3 confirms that an absent name
exits 0 with empty output; if it does not, the same call uses `--json` and a `jq` read of the one key).
Non-zero rc → `verdict=flag_read_failed` (exit 5); empty → unset; `true` → `verdict=flag_already_true`
(exit 5). It runs immediately after `access_gate`.

### D-4. The script after deletion (blocker 2 and 3)

`git-data-cutover.sh` keeps: the header (rewritten: purpose is a read-only proof until F2; exit codes 3
access, 5 refusal), configuration, `resolve_roster`, the access gate (unchanged), `gd_capture`, `read_flag`,
the three store probes and `main`. It deletes every function in the Cut List, the EXIT recovery trap
branches that called them (the trap keeps only the access-gate temp cleanup), `web_ssh`, and every
`DRY_RUN` / `CONFIRM_WIPE` / `ROLLBACK` branch. If any of those three variables is set to a non-default
value, `main` refuses first with `verdict=real_cutover_unreconciled` (exit 5), a remedy naming F2, and no
remote call.

### D-5. Read-only store probes (blocker 3)

After the flag read, through `gd_capture` on git-data, in order, each failing closed:

1. `refuse_if_unmounted`: `findmnt -no SOURCE "$OLD_ROOT"` must succeed and match `^/dev/[A-Za-z0-9/_.-]+$`;
   empty, non-zero, or no match → `verdict=old_store_unmounted`.
2. `refuse_if_cut_over`: that source equal to `$LUKS_MAPPER` → `verdict=already_cut_over`.
3. `refuse_if_store_not_empty` (CPO condition; holds until #7226 pins git-data's host key): the count of
   `*.git` entries under `$OLD_REPOS` must match `^[0-9]+$`; a missing `$OLD_REPOS` on the mounted root
   counts as 0; probe error → `verdict=probe_failed`; non-zero → `verdict=store_not_empty`.

All three pass → exit 0 with a summary listing the three verdicts.

### D-6. Workflow shape (blocker 4)

`git-data-cutover.yml`: inputs reduced to `confirm`; workflow-level
`concurrency: { group: git-data-state, cancel-in-progress: false }`; one job `cutover` with
`environment: web-platform-infra-apply`, secrets `DOPPLER_TOKEN` (bridge), `DOPPLER_TOKEN_PRD` (flag read,
bound only to the script step as `DOPPLER_FLAG_READ_TOKEN`) and `DOPPLER_TOKEN_GIT_DATA_ROOT`. Steps:
confirm token → Doppler CLI → secrets-present check (an empty `DOPPLER_TOKEN_GIT_DATA_ROOT` stops here with
`verdict=git_data_root_token_absent` before the bridge) → bridge (unchanged `server-ip` form) → key fetch
(step-level `set +x` refusal; `umask 077`; the `doppler secrets get ... --plain` output goes straight to
`$RUNNER_TEMP/gd-root-key` with a trailing newline, never to stdout; each key line passed to
`::add-mask::`) → `ssh_config` writer (jump block for `10.0.1.10` with `$CI_SSH_KEYFILE`; git-data block
`Host 10.0.1.20` with the root key and `ProxyCommand ssh -F <cfg> -W %h:%p 10.0.1.10`; `IdentitiesOnly yes`,
`BatchMode yes`, `LogLevel ERROR`, the bridge's host-key options on both) → script step with
`GIT_DATA_SSH="ssh -F <cfg>"` → teardown `if: always()` (bridge teardown plus `shred -u` of the key file and
config). `DOPPLER_TOKEN_WRITE` is no longer referenced. A re-run of the job asks for approval again (the
environment is on the key-reading job).

### D-7. Captured values (P8)

`gd_capture <anchored-regex> <remote-cmd>` runs `"${inv[@]}" "$GIT_DATA_HOST" "$cmd"` with stdout captured
and stderr to a temp file, strips one trailing newline, and returns 96 unless the value matches the pattern
in full (a multi-line value never matches an anchored single-line pattern); on failure it prints the capped,
filtered stderr through the access gate's existing `_access_stderr` path. The rc is captured with
`|| rc=$?`, not from a pipeline.

## Infrastructure (IaC)

### Terraform changes

- New root `apps/web-platform/infra/git-data-root-key/` (`main.tf`, `variables.tf`, `key.tf`, `access.tf`,
  `.terraform.lock.hcl`) per D-1. Inputs via `tf-var` from `prd_terraform`: `TF_VAR_hcloud_token`,
  `TF_VAR_doppler_token_tf`, `TF_VAR_github_app_id`, `TF_VAR_github_app_private_key`; raw
  `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` before `init`.
- `apps/web-platform/infra/git-data.tf`: data source + `ssh_keys` concat (D-2).

### Apply path

(b) push-triggered, reviewer-gated, additive-only apply of the new root; then (c) the existing
`git_data_host_replace` dispatch delivers the key at create. The replace destroys and recreates
`soleur-git-data`; its gate asserts both volumes are retained; users see no downtime (the flag is off, so no
web request touches git-data) — CPO. Merge-only blast radius: a Doppler project/secret/token, one repo
secret, one Hetzner key object; no host change.

### Distinctness / drift safeguards

- `prevent_destroy` on the key, the Hetzner key object, the Doppler project and secret; the additive-only
  refusal; rotation is a reviewed PR lifting `prevent_destroy` plus a dispatch.
- The create gate requires exactly one key by label and name.
- No drift leg for the new root: `scheduled-terraform-drift.yml` would need the root's state (the private
  key) in a scheduled job; recorded as a residual — the additive-only apply and the create gate are the
  checks.
- State readable by `prd_terraform` R2 credentials (Insight 1, F1).

### Vendor-tier reality check

Doppler Developer plan: no identities, no config inheritance (both avoided); Phase 0.2 probes the project
limit. GitHub: environment secrets not writable by the App (avoided). Hetzner key objects: free,
label-selectable.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-220** with a dated amendment log (no new ordinal; D2 and D3 are still `proposed`): D2 (custody
measured nominal, with the public-log justification for the separate root; separate Doppler project; shared
bucket; fallback taken on plan-tier evidence; reused environment and its `can_admins_bypass: true` /
`prevent_self_review: false` properties; environment is a human gate, not a secret boundary); D2.1 reversed;
D3 (no window; host authorization ends only at a replace after a rotation; token revocation is a reviewed
`-replace`); D4 new residuals (F1 reachability — to be decided in F1's own ADR; root logins on git-data not
detected, tracked on #8093; breach-triage trigger: once repositories exist a root-key leak is a likely
Art. 33 event; `store_not_empty` holds until #7226; no drift leg for the new root; after a key rotation,
dry runs fail auth until the next replace); D5 statuses; D6 sequencing and the F2 hand-off (the cutover
body, rollback split and `web-1-swap` membership move to F2); Consequences: the dry run stays read-only.

### C4 views

Read all three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` and check:
external actors (the approving reviewer is the existing founder actor), external systems (GitHub Actions,
Doppler, Hetzner API, Cloudflare R2 — confirm each is modeled), containers touched (`gitDataStore`, web-1),
and the relationship `github -> gitDataStore` (retire "until #8189"; describe the reviewer-gated read-only
root SSH through the web-1 jump). C4 models the running system, so no Terraform-root element is added.
Validate with `apps/web-platform/test/c4-code-syntax.test.ts`, `apps/web-platform/test/c4-render.test.ts`
and `bash plugins/soleur/test/c4-count-parity.test.sh`.

### Sequencing

D1b flips to `accepted` when the post-merge main dry run reads `role=git-data-auth verdict=ok`. D2–D3 stay
`proposed` until #7226, F1 and F2 land.

## Encryption Posture

```yaml
at_rest:
  - store: "R2 object web-platform/git-data-root-key/terraform.tfstate (bucket soleur-terraform-state)"
    mechanism: provider-managed
    evidence: "https://developers.cloudflare.com/r2/reference/data-security/"
    defends_against: "physical media disclosure at the provider"
    does_not_defend: "any holder of prd_terraform R2 keys or CF_API_TOKEN_R2 reads the private key in state"
    disclosed_as: "ADR-220 D4 residual, tracking issue F1"
    live_verification: "python3 scripts/lint-encryption-posture.py --repo-sweep"
  - store: "Doppler project soleur-git-data-root, config prd, secret GIT_DATA_ROOT_SSH_PRIVATE_KEY"
    mechanism: provider-managed
    evidence: "https://docs.doppler.com/docs/security-fact-sheet"
    defends_against: "disclosure from the Doppler storage layer"
    does_not_defend: "DOPPLER_TOKEN_TF (workplace scope, readable from prd_terraform) reads the project"
    disclosed_as: "ADR-220 D4 residual"
    live_verification: "python3 scripts/lint-encryption-posture.py --repo-sweep"
  - store: "runner $RUNNER_TEMP key file and ssh_config (ephemeral GitHub-hosted VM)"
    mechanism: plaintext-exception
    evidence: "git-data-cutover.yml cutover teardown shreds both files if: always()"
    defends_against: "reuse of the files after the job"
    does_not_defend: "another step of the same job reading the file while it exists"
    disclosed_as: "ADR-220 D2"
    live_verification: "bash apps/web-platform/infra/git-data-cutover-access.test.sh"
in_transit:
  - connection: "runner -> Doppler API (key read, flag read)"
    tls: "TLS 1.2+"
    cert_verification: on
    does_not_defend: "a leaked token used from elsewhere"
    disclosed_as: "ADR-220 D2"
  - connection: "runner -> web-1 -> git-data SSH (-W jump inside the CF tunnel)"
    tls: "CF tunnel TLS + SSH-2 end to end"
    cert_verification: off
    does_not_defend: "a compromised web-1 impersonating git-data (host keys unverified)"
    disclosed_as: "ADR-220 D4 (#7226)"
exception:
  - subject: "runner key file in plaintext; SSH host-key verification off on both hops"
    justification: "ssh needs a key file; host-key pinning is #7226's scope"
    tracking_issue: 7226
    reevaluate_when: "#7226 pins git-data's host key"
    expires_on: 2026-12-15
```

`/work` reconciles these rows with `scripts/encryption-posture-ledger.json` so the sweep stays
`0 unledgered, 0 failing`.

## Guard Contract

### Guard 1 — the flag read fails closed

**Property.** No run reaches a store probe unless the flag read succeeded and the value is not `true`.
**Assembly.** `read_flag` (the only runner-side `doppler secrets` call in the script), its position in
`main()`, the `doppler` shim in `git-data-cutover-access.test.sh`.
**Mutation matrix.**

| Edit | Must go RED |
|---|---|
| restore `\|\| echo ""` in `read_flag` | scope-error case |
| REORDER: move the flag read after `refuse_if_unmounted` | timeline case (no git-data store probe before the flag read) |
| compare with `== "true "` or a case-insensitive match | exact-`true` refusal case |
| add a second runner-side `doppler secrets` call outside `read_flag` | census of runner-side Doppler calls |

**Harness rows.** A shim that exits 0 with empty output for the absent name → must PASS as unset; a shim
that ignores `--no-exit-on-missing-secret` → the absent case must go RED.
**Anchor.** None stored.

### Guard 2 — no run on an unmounted, cut-over or non-empty store; no rsync to misdirect

**Property.** The dry run exits 0 only when the source of `$OLD_ROOT` is a device, is not the mapper, and
`$OLD_REPOS` holds zero `*.git` entries, each probe failing closed; and the script contains no
`rsync`, `cryptsetup`, `mount`, `umount`, `mkfs`, `rm -rf` or `touch` invocation.
**Assembly.** `refuse_if_unmounted`, `refuse_if_cut_over`, `refuse_if_store_not_empty`, their order in
`main()`, and a census over every line of `git-data-cutover.sh` (comments excluded).
**Mutation matrix.**

| Edit | Must go RED |
|---|---|
| accept an empty `findmnt` source | unmounted case |
| delete `refuse_if_cut_over` (keep the other two) | mapper-source case |
| treat a failed count probe as zero | probe-error case |
| reintroduce a `bulk_rsync` function | mutating-verb census |

**Harness rows.** A mounted plaintext source with a missing `$OLD_REPOS` → PASS; a count of `0` with a
trailing newline → PASS.
**Anchor.** None stored.

### Guard 3 — the root token is referenced only by the gated cutover job

**Property.** `DOPPLER_TOKEN_GIT_DATA_ROOT` appears in `.github/` only inside `git-data-cutover.yml` job
`cutover`, which declares `environment: web-platform-infra-apply`. It prevents accidental use on `main`
bytes; it does not stop a branch workflow from naming a repo secret (ADR-220).
**Assembly.** Every file under `.github/workflows/` and `.github/actions/` (census).
**Mutation matrix.**

| Edit | Must go RED |
|---|---|
| add a second job in `git-data-cutover.yml` referencing it | per-job predicate |
| add a second workflow file referencing it, after the compliant first | tree census |
| remove `environment:` from `cutover` | gated-job predicate |

**Harness rows.** The name only in a YAML comment → PASS; an empty scan set → the suite reports
`0 files scanned` as a failure.
**Anchor.** None stored.

### Guard 4 — a create carries exactly the root key

**Property.** Both host-creating gates refuse a plan unless the data source resolved in `prior_state` to
exactly one key named `soleur-git-data-root`, and every created `hcloud_server.git_data` carries, as a set of
strings, exactly the default key's id and that key's id.
**Assembly.** `git_data_root_key_arm` in `tests/scripts/lib/git-data-root-key-arm.sh`, and its call sites in
`git-data-host-replace-gate.sh` and `git-data-host-birth-gate.sh` (census over `tests/scripts/lib/`).
**Mutation matrix.**

| Edit | Must go RED |
|---|---|
| fixture: data source absent from `prior_state` (deferred read) | presence arm |
| fixture: two labeled keys resolved | exactly-one arm |
| fixture: created server carries only the default key | membership arm |
| remove the arm call from the birth gate (keep it in the replace gate) | second-member census |

**Harness rows.** Existing replace and birth fixtures extended with a `prior_state` data block and both ids
→ PASS; ids as numbers in the data source and strings on the server → PASS (string comparison); reordered
`ssh_keys` → PASS (set comparison).
**Anchor.** None stored.

### Guard 5 — captured host values are validated

**Property.** No value returned by a remote command is compared or counted unless it matched its anchored
pattern in full.
**Assembly.** `gd_capture` and every call site of it (census), plus any `$(...)` capture of `"${inv[@]}"` or
`$GIT_DATA_SSH` outside `access_gate`.
**Mutation matrix.**

| Edit | Must go RED |
|---|---|
| return the value without the pattern check | injected second-line case |
| unanchor a pattern (drop `$`) | trailing-garbage case |
| add a raw `$("${inv[@]}" ...)` capture outside `gd_capture` | capture census |

**Harness rows.** A value with one trailing newline → PASS and compares equal.
**Anchor.** None stored.

### Guard 6 — serialization

**Property.** `git-data-cutover.yml` holds workflow-level `git-data-state` and `apply-git-data-root-key.yml`
holds job-level `git-data-state`, both `cancel-in-progress: false`, with the literal equal to the replace
job's; the existing count pins stay at 2.
**Assembly.** The access suite's YAML checks and the new root suite's YAML checks, compared against the
group literal extracted from `git_data_host_replace` in `apply-web-platform-infra.yml`.
**Mutation matrix.**

| Edit | Must go RED |
|---|---|
| rename the cutover workflow's group to `git-data-cutover` | literal parity |
| set `cancel-in-progress: true` on the root-key apply job | cancel assertion |
| move the root-key apply's group to a different job-level name | literal parity |

**Harness rows.** `terraform-target-parity.test.ts` and `git-data-rung2-rehearsal.test.sh` unchanged → PASS.
**Anchor.** The replace job's literal (outside both new files).

### Guard 7 — a real mode cannot be requested

**Property.** `git-data-cutover.yml` declares only the `confirm` input, and the script exits 5 with
`verdict=real_cutover_unreconciled` and an empty timeline when `DRY_RUN`, `ROLLBACK` or `CONFIRM_WIPE` carry
a non-default value.
**Assembly.** The workflow's `on.workflow_dispatch.inputs`, `main()` entry.
**Mutation matrix.**

| Edit | Must go RED |
|---|---|
| re-add a `rollback` input | input census |
| refuse only `ROLLBACK` (drop the `CONFIRM_WIPE` arm) | wipe case |
| REORDER: move the refusal after `access_gate` | empty-timeline assertion |

**Harness rows.** No variables set → reaches the access gate (PASS).
**Anchor.** None stored.

### Guard 8 — the root-key apply is additive-only and never exposes its plan

**Property.** `apply-git-data-root-key.yml` applies only a plan with no delete, update-in-place of the key,
secret or project, or replace action (except the read token and its repo secret under the typed rotation
input), and contains no `upload-artifact`, `terraform show` to stdout, or `terraform output` step.
**Assembly.** The refusal step's `jq` over `resource_changes[]`, the workflow's step list (census).
**Mutation matrix.**

| Edit | Must go RED |
|---|---|
| fixture: `tls_private_key.git_data_root` replace | replace arm |
| fixture: `doppler_secret.git_data_root_ssh_private_key` delete | delete arm |
| fixture: read-token replace without the typed input | rotation-input arm |
| add an `actions/upload-artifact` step | step census |

**Harness rows.** A create-only fixture → PASS; a read-token replace with the typed input → PASS.
**Anchor.** None stored.

## Implementation Phases

### Phase 0 — Probes, baselines, follow-ups (no product code)

1. Re-measure the baselines above.
2. Doppler: read-only probe of the workplace project limit and identity availability; record verdicts.
3. `doppler secrets get <absent-name> --plain --no-exit-on-missing-secret -p soleur -c dev`: record rc and
   output; D-3's form follows it.
4. Plan-JSON shape: in the scratchpad, a throwaway root (local state, deleted after) with only
   `data "hcloud_ssh_keys"` (a selector matching nothing) and the pinned hcloud provider, planned with the
   read-only `HCLOUD_TOKEN`; record the key paths of the data source in `terraform show -json` (structure
   only, no values). Fixtures follow it.
5. Scratch `terraform validate` of the planned root (`-backend=false`).
6. Consumer sweep before deleting the cutover body: `git grep -n 'git-data-cutover.sh'` and
   `git grep -nE 'bulk_rsync|repoint_luks_mount|canary_luks_device|old_volume_wipe|verify_set_identity|prepare_luks_target'`
   outside the script; every hit is an edit (tests, runbooks, follow-through scripts, ADRs).
7. File, each after a duplicate search, in milestone **Post-MVP / Later**:
   - **F1** "evict repo-secret-reachable `DOPPLER_TOKEN_TF`, `CF_API_TOKEN_R2`, `GITHUB_APP_PRIVATE_KEY` from
     `prd_terraform`" — needs its own ADR; a precondition of the first real cutover; links #6167.
   - **F2** "git-data cutover real modes on real mechanisms" — body: the CTO recommendation (no hard freeze;
     in-container flag proof; same-version redeploy accepting only a frame started after the flag write;
     lock-free probe; rollback restarts the webhook unit first; windowed `prd` flag write token; gc timer
     stopped before the repoint; resume after a partial repoint); the spec-flow P0/P1 list (dead-man or no
     freeze, window-close/rollback interplay, `always()` result clauses, split-brain assertion via the
     container's env, tag read after the webhook unit stops, #8167 rollback displacement); the advisor's
     tiered rollback and shared deploy-status poller; `assert_distinct_endpoints` (`stat -L -c %d:%i` on
     both repo endpoints after `mkdir -p`); `web-1-swap` membership on the job that drains web-1; the
     rollback job split (ADR-220 D2); the missing `GIT_DATA_LUKS_CUTOVER_AT` writer; a mutating rehearsal
     with entry-state restore; downtime statements; `verify_set_identity` printing hashed names; the guards
     it inherits from this PR (1, 2, 5, 7); F1 and #7226 as preconditions.
   - **F4** "git-data: `/dev/mapper/git-data` is not reopened at boot" (a post-cutover reboot leaves
     `/mnt/git-data` without its backing device).
   - A comment on #8093: the stale "root path the cutover uses" prose in `git-data-pre-receive.sh` /
     `git-data-pre-receive-placeholder.sh`, and root-login detection on git-data, for the next hash-bound
     batch.

### Phase 1 — RED (matrices before code)

Write every Guard 1–8 mutation and harness row as failing cases against `origin/main` bytes:
`git-data-cutover-access.test.sh` (G1, G2, G3, G5, G6 cutover half, G7, D-6 YAML, the key-fetch and
`ssh_config` steps), new `tests/scripts/test-git-data-root-key-arm.sh` (G4, plus a call-site census) and the
two existing gate suites (their fixtures gain `prior_state`), new `apps/web-platform/infra/git-data-root-key.test.sh`
(G6 root half, G8, backend key, every `prevent_destroy`, no `terraform_remote_state` in the parent, the
path exclusion in `apply-web-platform-infra.yml`), and `plugins/soleur/test/infra-validation-detect.test.sh`
(nested root collapses to the parent). Remove the access suite's cases for deleted functions only after
their replacements exist.

### Phase 2 — New root and its apply workflow

D-1 files, `apply-git-data-root-key.yml`, the `infra-validation.yml` validate step.

### Phase 3 — Web-platform root and the create gates

D-2. Run `bun test plugins/soleur/test/terraform-target-parity.test.ts`: it must read **197 pass / 0 fail**.
If any pinned assertion would need to change, stop and re-plan rather than editing the pin.

### Phase 4 — Script

D-3, D-4, D-5, D-7 in `git-data-cutover.sh`.

### Phase 5 — Workflow

`git-data-cutover.yml` per D-6; register new suites in `infra-validation.yml`; `actionlint` on every changed
workflow.

### Phase 6 — Docs and records

- ADR-220 amendment log (Architecture Decision above).
- C4 edge.
- Runbook `git-data-luks-cutover-5274.md`: Precondition and Sequence rewritten (the dispatch is a read-only
  proof; real steps blocked on F2 and F1); web-2 removed; an order-of-operations verdict map (before the
  root-key apply → `git_data_root_token_absent`; before the replace → `role=git-data-auth verdict=failed
  reason=auth_refused`; after a rotation, until the next replace → `auth_refused`); a pending approval holds
  `git-data-state` (cancel or answer before dispatching a replace; an unanswered approval can hold it until
  the environment's approval timeout); #8167 re-dispatch note; the replace causes no user-facing downtime;
  the breach-triage trigger.
- Article 30 git-data entry: one (g) TOM, DRAFTED / NOT-YET-ACTIVE, within CLO's limits (a fourth SSH
  authority, root, with no forced command, able to bypass (g)(2) and (5)–(8); held in the isolated Doppler
  project and the R2 state object, not `prd`; delivered only by a create of `hcloud_server.git_data`; no
  claim of expiry, two-party review, custody isolation from repo-secret holders, host-key verification,
  host-side revocation at the next replace, or anything about encryption at rest); cross-references from
  (g)(5) and (g)(6); the stale "unborn" wording marked Superseded citing #8171 without touching any Status
  cell or PA-2 (g)(17); the Cross-Cutting "Secrets management" bullet qualified with F1.
- The git-data authorization accounting (#8009 C1): record the root key as a distinct authority beside the
  three forced-command keys (location found in Phase 0 with `git grep -n 'three distinct'`).
- `knowledge-base/product/roadmap.md` row for the #5274 cutover: add F1 and F2 as preconditions (CPO).
- Sweep "until #8189" / "not yet" wording in `git-data-cutover.yml`, the bridge action comment, the script
  header, the runbook, the C4 edge and ADR-220.

### Phase 7 — Validation battery and learning

Full battery launched with `setsid nohup` from a Bash call and watched from a separate Monitor (session
error 2); `python3 plugins/soleur/test/lib/fixture-scan.py --rule relative --repo .` on every new shell
write site before push (session error 1); `python3 scripts/lint-infra-no-human-steps.py --changed --base
origin/main`; `python3 scripts/lint-guard-contract.py` on this plan; the rung-2 gate prints `RELEASED
5c50797be839…`. Compound learning under `knowledge-base/project/learnings/security-issues/` (topic: a custody
boundary measured nominal, and a wrong-scope token whose error read as "unset") carrying the four
session-note errors with their prevention lines, including error 4 (a GitHub-managed CodeQL SARIF upload
failure is non-required and non-retryable: record it, do not chase it). PR body (session error 3): "this
diff changes Terraform; merging fires the reviewer-gated `apply-git-data-root-key.yml` apply (creates the
D-1 resources) and the web-platform push apply (its `-target` set does not include `hcloud_server.git_data`;
expected no resource change from `git-data.tf`)", and each Plan line is read after merge.

## Files to Create

- `apps/web-platform/infra/git-data-root-key/main.tf`
- `apps/web-platform/infra/git-data-root-key/variables.tf`
- `apps/web-platform/infra/git-data-root-key/key.tf`
- `apps/web-platform/infra/git-data-root-key/access.tf`
- `apps/web-platform/infra/git-data-root-key/.terraform.lock.hcl`
- `apps/web-platform/infra/git-data-root-key.test.sh`
- `tests/scripts/lib/git-data-root-key-arm.sh`
- `tests/scripts/test-git-data-root-key-arm.sh`
- `.github/workflows/apply-git-data-root-key.yml`
- `knowledge-base/project/learnings/security-issues/<date>-<topic>.md`

## Files to Edit

- `apps/web-platform/infra/git-data-cutover.sh`
- `apps/web-platform/infra/git-data-cutover-access.test.sh`
- `.github/workflows/git-data-cutover.yml`
- `apps/web-platform/infra/git-data.tf`
- `tests/scripts/lib/git-data-host-replace-gate.sh`
- `tests/scripts/test-git-data-host-replace-gate.sh`
- `tests/scripts/lib/git-data-host-birth-gate.sh`
- `tests/scripts/test-git-data-host-birth-gate.sh`
- `.github/workflows/apply-web-platform-infra.yml` (path exclusion only)
- `plugins/soleur/test/infra-validation-detect.test.sh`
- `.github/workflows/infra-validation.yml`
- `.github/actions/cf-tunnel-ssh-bridge/action.yml` (comment only; its Guard 2 exports unchanged)
- `knowledge-base/engineering/architecture/decisions/ADR-220-git-data-root-access-via-web-1-jump-and-a-dedicated-terraform-minted-key.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4` (and `views.c4` only if an include changes)
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`
- `knowledge-base/legal/article-30-register.md`
- `knowledge-base/product/roadmap.md`
- `scripts/encryption-posture-ledger.json` (if the sweep requires the new rows)
- every consumer found by the Phase 0.6 sweep, and the authorization accounting record

**Untouchable (hash-bound; AC10), full paths:**
`apps/web-platform/infra/cloud-init-git-data.yml`, `apps/web-platform/infra/modules/git-data-userdata/main.tf`,
`apps/web-platform/infra/modules/git-data-userdata/outputs.tf`,
`apps/web-platform/infra/modules/git-data-userdata/variables.tf`, `apps/web-platform/infra/git-data-bootstrap.sh`,
`apps/web-platform/infra/git-data-gc-failure.service`, `apps/web-platform/infra/git-data-gc.service`,
`apps/web-platform/infra/git-data-gc.sh`, `apps/web-platform/infra/git-data-gc.timer`,
`apps/web-platform/infra/git-data-pre-receive-placeholder.sh`, `apps/web-platform/infra/git-data-provision.sh`,
`apps/web-platform/infra/git-data-remove.sh`, `apps/web-platform/infra/git-data-transport-wrapper.sh`,
`apps/web-platform/infra/git-data-rung2-boot-evidence.env`.

## Open Code-Review Overlap

1 open scope-out touches these files: #7098 (audit `run:` bodies whose `set` omits `-e`; names
`apply-web-platform-infra.yml`). **Acknowledge:** a repo-wide lint audit, a different concern; this plan's
only edit there is a path-filter line.

## Observability

```yaml
liveness_signal:
  what: "git-data-cutover.yml run conclusion with the script's ACCESS and REFUSE verdict annotations; apply-git-data-root-key.yml run conclusion"
  cadence: "per dispatch; per push to the new root's path"
  alert_target: "GitHub check-run annotations on the run (readable via the check-runs annotations API)"
  configured_in: ".github/workflows/git-data-cutover.yml, .github/workflows/apply-git-data-root-key.yml"
error_reporting:
  destination: "::error title=git-data-cutover refuse::verdict=<word> and ::error title=git-data-cutover access::role=<r> verdict=<v> annotations"
  fail_loud: true
failure_modes:
  - mode: "flag read error or flag already true"
    detection: "verdict=flag_read_failed | flag_already_true, exit 5"
    alert_route: "run annotation"
  - mode: "store unmounted, cut over, not empty, or probe error"
    detection: "verdict=old_store_unmounted | already_cut_over | store_not_empty | probe_failed, exit 5"
    alert_route: "run annotation"
  - mode: "real mode requested by a stale invocation"
    detection: "verdict=real_cutover_unreconciled, exit 5"
    alert_route: "run annotation"
  - mode: "root read token not yet published"
    detection: "verdict=git_data_root_token_absent in the secrets-present step"
    alert_route: "run annotation"
  - mode: "create plan without exactly the root key"
    detection: "replace/birth gate verdict=git_data_root_key_not_in_create"
    alert_route: "apply-web-platform-infra run annotation"
  - mode: "root-key apply would delete or replace key material"
    detection: "verdict=git_data_root_key_non_additive"
    alert_route: "apply-git-data-root-key run annotation"
logs:
  where: "GitHub Actions run logs (host stderr capped and filtered; no workspace ids printed)"
  retention: "GitHub Actions default (90 days)"
discoverability_test:
  command: "bash apps/web-platform/infra/git-data-cutover-access.test.sh"
  expected_output: "a final summary line reporting N passed, 0 failed, 0 skipped"
```

## User-Brand Impact

**If this lands broken, the user experiences:** a replace that brings git-data back without the key (the
cutover stays blocked) or a create gate that refuses a needed recovery replace until the root-key apply is
re-run; with the cutover body removed, a broken PR cannot rsync, repoint or flip the store. The replace
itself causes no user-facing downtime while the flag is off.

**If this leaks, the user's data is exposed via:** (a) the root SSH key for the host that will hold every
workspace's full git history (source, commit authors' names and e-mails), usable through the web-1 jump;
(b) the R2 state object and the Doppler project holding that key, both reachable by any branch workflow
through `DOPPLER_TOKEN` (F1). Both matter once repositories exist, which the flag-off state and the
`store_not_empty` refusal keep false until F1, F2 and #7226.

**Brand-survival threshold:** single-user incident

CPO sign-off (with the #8009 C1 re-approval, CPO + CTO) is recorded in Domain Review;
`user-impact-reviewer` runs at review time.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** `bash apps/web-platform/infra/git-data-cutover-access.test.sh` exits 0 with `0 failed` and
  `0 skipped` under `CI=true`, covers every Guard 1, 2, 3, 5, 6 (cutover half) and 7 row, and Phase 1
  recorded each behavioral row RED against `origin/main` bytes.
- [ ] **AC2** Canonical dry run (token and key present, flag absent, plaintext device source, empty store):
  exit 0, and the recorded remote timeline equals exactly, in order: web probe, jump probe, auth probe,
  `findmnt -no SOURCE /mnt/git-data`, the `*.git` count — nothing else (`git-data-cutover.sh › main`).
- [ ] **AC3** `git grep -nE 'soleur-(web|drain)\.service|bulk_rsync|repoint_luks_mount|old_volume_wipe' -- apps .github knowledge-base/engineering/operations`
  returns nothing, and every hit of the Phase 0.6 sweep outside those paths is updated or states F2.
- [ ] **AC4** `bash tests/scripts/test-git-data-root-key-arm.sh`, `bash tests/scripts/test-git-data-host-replace-gate.sh`
  and `bash tests/scripts/test-git-data-host-birth-gate.sh` exit 0 with `0 failed`.
- [ ] **AC5** `bash apps/web-platform/infra/git-data-root-key.test.sh` exits 0 (Guards 6 root half and 8,
  backend key, every `prevent_destroy`, no `terraform_remote_state`, the path exclusion present), and the
  `infra-validation.yml` validate step for the root passes on the PR.
- [ ] **AC6** `bash plugins/soleur/test/infra-validation-detect.test.sh`,
  `bash apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh` and
  `bash apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` exit 0.
- [ ] **AC7** `bun test plugins/soleur/test/terraform-target-parity.test.ts` reads **197 pass / 0 fail**,
  with no edit to that file.
- [ ] **AC8** For every path in the untouchable list, `git ls-files --error-unmatch <path>` succeeds and
  `git diff --quiet origin/main -- <path>` exits 0; the rung-2 gate prints
  `RELEASED … 5c50797be8392fe551a940ae04555c52a3f4409cf249ed11bb1280fec783d5b1`.
- [ ] **AC9** Parsed as YAML, `git-data-cutover.yml` has exactly one input (`confirm`), workflow-level group
  `git-data-state` without cancel, one job `cutover` with `environment: web-platform-infra-apply`, the D-6
  step order, secrets exactly `DOPPLER_TOKEN`, `DOPPLER_TOKEN_PRD`, `DOPPLER_TOKEN_GIT_DATA_ROOT`, and no
  `DOPPLER_TOKEN_WRITE`; `actionlint` passes on every changed workflow.
- [ ] **AC10** Every new suite is an `infra-validation.yml` step whose `run` equals `bash <path>`.
- [ ] **AC11** `python3 scripts/lint-encryption-posture.py --repo-sweep` → `0 unledgered, 0 failing checks`;
  the C4 tests and `c4-count-parity` pass; `python3 scripts/lint-infra-no-human-steps.py --changed --base
  origin/main` exits 0.
- [ ] **AC12** ADR-220 carries the dated amendment log listed under Architecture Decision, and
  `git grep -n 'until #8189'` over `git-data-cutover.yml`, the bridge action, `git-data-cutover.sh`, the
  runbook, `model.c4` and ADR-220 returns nothing.
- [ ] **AC13** `git diff origin/main -- knowledge-base/legal/article-30-register.md` adds exactly one (g)
  TOM, the two cross-references, the Superseded markers and the qualified secrets bullet, and changes no
  `Status` cell and no PA-2 (g)(17) text.
- [ ] **AC14** F1, F2 and F4 exist in milestone Post-MVP / Later, the #8093 comment is posted, and the
  roadmap row names F1 and F2; the PR body uses `Ref #8189`, `Ref #6680`, `Ref #8093` (no `Closes`), states
  the two applies the merge fires, and names no prod dispatch as done.
- [ ] **AC15** No `git-data-cutover.yml` or `apply-git-data-root-key.yml` dispatch was made in this PR.

### Post-merge (automated; explicit authorization where stated)

- [ ] **AC16** The push-triggered `apply-git-data-root-key.yml` run is approved, passes the additive-only
  refusal, and applies exactly the D-1 addresses.
- [ ] **AC17** The merge's `apply-web-platform-infra.yml` push run is green and its Plan line is recorded in
  the PR thread.
- [ ] **AC18** With explicit authorization, after AC16, `git_data_host_replace` is dispatched from `main`;
  the replace gate's `git_data_root_key_arm` passes and the run is green.
- [ ] **AC19** With explicit authorization and environment approval, after AC18, a `git-data-cutover.yml`
  dispatch from `main` reads `role=git-data-auth verdict=ok`, and all three store probes report clear, and
  exits 0; then ADR-220 D1b flips to `accepted`, and #6680 and #8189 close, each with the run URL.

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering (CTO)

**Status:** reviewed (v1 assessment; v2 devex re-review: CONDITIONS MET)
**Assessment:** #8009 C1 re-approval **APPROVE WITH CONDITIONS**, all met: C1-a (no window; closing a
token is not host revocation — D3, Insight 5); C1-b (root-login detection tracked on #8093); value capture
separated from display (D-7, Guard 5); freeze/reload redesign moved to F2 with the recommendation in its
body; workflow-level `git-data-state`; honest reference census; create gate by name and exactly-one;
Doppler project-limit probe. v2 advisories applied in v3: the post-merge order is explicit (AC18 "after
AC16", runbook verdict map); the window question is dissolved by cutting the window (DC-4); F2's body lists
the guards it inherits.

### Legal (CLO + GDPR gate)

**Status:** reviewed
**Assessment:** GDPR gate: 0 regulated-data paths, no Critical finding, no Art. 30 trigger (one TOM on an
existing activity). Adopted: TOM wording limits (Phase 6, AC13); D3 corrected; cross-references to (g)(5) and
(g)(6); Superseded markers on "unborn"; qualified secrets bullet; breach-triage trigger in ADR-220 D4 and the
runbook; no workspace ids printed (the function that printed them is deleted); the stray-copy residual
dissolved by `store_not_empty` and the removal of the rsync path. Advisory only — not legal advice.

### Product/UX Gate

**Tier:** none (no UI surface; no file in the lists matches the UI-surface globs)
**Decision:** reviewed (CPO plan-time sign-off for the single-user-incident threshold)
**Agents invoked:** cpo, spec-flow-analyzer
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

CPO v2: **SIGN-OFF GRANTED**. v1 conditions: store-emptiness runtime refusal — met (D-5, now also refusing an
unmounted store); dry-run cleanup — dissolved (read-only dry run); User-Brand Impact extensions — met; F1 as a
precondition of the real cutover — met; downtime — the replace's no-downtime line added. Non-blocking v2
conditions applied: F1/F2/F4 in Post-MVP / Later and the roadmap row updated (Phase 6, AC14). DC-1..DC-3
accepted. Spec-flow v2: no P0; P1s applied (unmounted store refusal; no `web-1-swap` on the read-only job;
create-gate remedy text and birth-path decision); P2s applied (exact timeline AC2, AC17 no longer claims an
unplanned address, key masking, order-of-operations map, pending-approval hold note).

### Plan-review panel (v2 → v3)

DHH, Kieran, code-simplicity, architecture-strategist, spec-flow, CTO (devex), CPO. Applied: delete the
unreachable cutover body and the real-mode inputs (DHH + simplicity + architecture); drop `environment:` on
the replace job (architecture P0: pinned parity assertion); new-root apply on `git-data-state`, additive-only
refusal, `prevent_destroy` on the Doppler project and secret, no plan exposure (architecture P1); shared
create-gate arm for replace and birth, read from `prior_state`, string ids, set comparison (architecture P1,
Kieran P1); unmounted-store refusal (Kieran P1, spec-flow P1); reuse the existing environment and a single
gated job, which also re-asks approval on re-run (simplicity, Kieran P1); drop `web-1-swap` from the
read-only job (spec-flow P1); cut the access window, Guard 5 label parity, the display pipe, the preflight
and env-assert (DHH + simplicity); root validate step via `infra-validation.yml` (architecture P2); key file
from `private_key_openssh` with a trailing newline and per-line masks (Kieran P2); full-path untouchable AC
with `--error-unmatch` (Kieran P2). Not applied: dropping the Doppler hop (DC-7); moving the PR #8187
session errors out of this PR's learning (the operator required them here); scoping the Article 30 edit to
the TOM only (CLO P1 items retained).

## Test Scenarios

1. Dry run, flag absent, plaintext device source, empty store → exit 0; AC2 timeline.
2. Flag read scope error → exit 5 `flag_read_failed`; no store probe.
3. Flag `true` → exit 5 `flag_already_true`.
4. `findmnt` empty or failing → exit 5 `old_store_unmounted`.
5. `findmnt` prints the mapper → exit 5 `already_cut_over`.
6. One `*.git` under `$OLD_REPOS` → exit 5 `store_not_empty`.
7. `$OLD_REPOS` missing on a mounted root → count 0, exit 0.
8. `findmnt` output with an injected second line → `gd_capture` rejects, exit 5.
9. `ROLLBACK=1` or `CONFIRM_WIPE=1` or `DRY_RUN=0` → exit 5, empty timeline.
10. `DOPPLER_TOKEN_GIT_DATA_ROOT` empty → the secrets-present step fails with `git_data_root_token_absent`
    before the bridge.
11. Replace or birth plan: data source deferred, two labeled keys, or server missing the root key → gate
    refuses with the remedy line.
12. Root-key apply plan replacing the key or deleting the secret → refused before `apply`.

## Risks and Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6.
- The create gate now depends on the new root: if its apply is rejected or the Hetzner key object is lost, a
  recovery replace refuses until `apply-git-data-root-key.yml` runs again. Accepted while the store is empty;
  the verdict names the remedy.
- A pending cutover approval holds `git-data-state`; a replace dispatched meanwhile waits while holding the
  workflow-wide `terraform-apply-web-platform-host` group, which stalls web-platform applies and lets #8167
  cancel pending push applies. The runbook says to answer or cancel the approval first.
- `web-platform-infra-apply` has `can_admins_bypass: true` and `prevent_self_review: false`; the gate is a
  single-human acknowledgement, not two-party review (stated in ADR-220 and the TOM limits).
- Deleting the cutover body means F2 rebuilds it; git history and F2's body carry the design and the review
  findings so nothing learned here is lost.
- `detect-changes` treats the nested root as the parent; moving it to a top-level path would put it into the
  PR `plan` matrix — the detect test pins the nested behavior.
