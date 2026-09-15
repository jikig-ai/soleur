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
deepened: 2026-09-15
---

# git-data root access: Terraform-minted key, separate root, reviewer-gated credential

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

Revision v4 (deepened 2026-09-15). v3 came out of domain review (CTO, CPO, CLO + GDPR gate), two spec-flow
passes, a scoped advisor consult and a seven-agent plan-review panel. Decisions that change the issue's or
the operator's stated shape are recorded in
`knowledge-base/project/specs/feat-one-shot-8189-git-data-root-key/decision-challenges.md`.

## Enhancement Summary

**Deepened on:** 2026-09-15
**Sections enhanced:** 14 (Overview, Research Insights, D-1..D-7, new Downtime & Cutover, IaC, ADR, Encryption
Posture, Guard Contract, Phases, Observability, User-Brand Impact, Acceptance Criteria, Risks)
**Agents used:** network-outage deep-dive, verify-the-negative + self-audit pass, security-sentinel,
user-impact-reviewer, observability-coverage-reviewer, test-design-reviewer, git-history-analyzer,
terraform-architect (precedent diff), provider/runtime verification (done directly after the agent returned
no report: schema reads, a scratch plan-JSON measurement, a Doppler CLI probe).

### Key Improvements

1. **Key-swap persistence closed.** The create gate now compares the resolved Hetzner key's SHA256
   fingerprint against a committed file, not only its label and name (security P1-1).
2. **The `prd` read token never reaches a process that handles host bytes.** The flag read moves to its own
   step before the bridge and the key fetch (security P1-3).
3. **The root-key apply is dispatch-only, allowlist-gated and loud on failure.** It refuses anything except
   create/read/no-op, including `forget`, and fails on an empty plan JSON. It prints only addresses and
   actions, and shreds the plan file. It runs `terraform_wrapper: false` against a readonly lock, and a notify
   job emails on any non-success (terraform-architect P1-a..e, security P1-2, observability P1-a).
4. **Downtime & Cutover section added.** It covers the git-data replace, the Delete Account path that stays
   live during it (`removeGitDataRepo` is deliberately not flag-gated), and a no-SSH private-NIC readiness
   read between the replace and the dry run (network deep-dive, user-impact).
5. **Guards are executed, not described.** A `mutate()` helper runs every code-edit row against a temp copy,
   with a mutant floor. The PyYAML `on:` → `True` trap and census lower bounds are fixed (test-design).

### New Considerations Discovered

- The host's own `prd_git_data` token is a branch-config token, so it likely resolves all of `prd` (#6167
  open). A leaked root key therefore exposes `prd` secrets **before** any repository exists. User-Brand
  Impact and ADR-220 D4 now say so.
- The dry run's store-probe evidence is unauthenticated while host keys are unverified (#7226): a
  compromised web-1 could answer "mounted, empty". D1b's flip is recorded with that caveat, and #7226 becomes
  a hard precondition of F2.
- F2 must start from a fresh replace plus a `GIT_DATA_LUKS_KEY` rotation, so nothing planted during the
  read-only period survives into the real cutover.
- `secrets: inherit` in `web-platform-release.yml` and `version-bump-and-release.yml` hands every repo
  secret, including the new token, to `reusable-release.yml`. The reference census accounts for it.

## Overview

Objective 2 step 2 of the git-data LUKS cutover (#5274, ADR-068). The ADR-220 transport shipped in
0777caa9e; every cutover dispatch stops at the access gate with
`role=git-data-auth verdict=git_data_root_key_absent` (exit 3). This PR:

1. mints the git-data root SSH key in its own Terraform root, applied by a dispatch-only, reviewer-gated,
   allowlist-refusing workflow serialized with every git-data host mutation. The private half lives in an
   isolated Doppler project, and a read token is published for the one reviewer-gated cutover job on `main`;
2. hands the public half to the web-platform root through a label-selected data source. Both host-creating
   gates (replace and birth) refuse a plan that would not carry exactly that key, checked by fingerprint;
3. turns `git-data-cutover.yml` into what it can honestly be until the real cutover is redesigned: a
   reviewer-gated, **read-only** proof. It runs a fail-closed flag read in its own step, then the access gate,
   then fail-closed store probes (mounted, not cut over, empty). It deletes the cutover body whose freeze,
   reload and rollback call systemd units that do not exist;
4. serializes the run with git-data host mutations (`git-data-state`).

Post-merge, with explicit authorization at each prod step:

1. dispatch the root-key apply;
2. a PR commits the printed public-key fingerprint;
3. run the `git_data_host_replace` that delivers the key;
4. read the private-net readiness heartbeat;
5. dispatch a dry run from `main`, which must read `role=git-data-auth verdict=ok` with every store probe
   clear and exit 0.

## Blocker triage (inline, per `wg-defer-only-after-inline-triage`)

| Blocker | Disposition | Why |
|---|---|---|
| 1. `read_flag` fails open | **Fixed here** | Fail-closed read under the existing `prd`-scoped read secret, in its own step, before the bridge and the key exist |
| 2. `soleur-web` / `soleur-drain` units do not exist | **Removed here; the real mechanism is F2** | There are no real unit names to substitute: the app is a container whose env is fixed at `docker run`. The correct mechanism is a redesign. The CTO recommends dropping the hard freeze, because the only writer is gated by the flag. The rest: a same-version redeploy that accepts only a frame started after the flag write; a lock-free probe; rollback that restarts the webhook unit first; a windowed `prd` flag write token; the gc timer stopped before the repoint; resume after a partial repoint. Review found three P0 and six P1 hazards on that path. Every caller of the units is deleted along with the functions that held them |
| 3. Post-cutover self-rsync | **Fixed here by construction + probes** | The script no longer contains any rsync, mount or LUKS call (a census asserts it), and the dry run refuses `old_store_unmounted`, `already_cut_over` and `store_not_empty`. F2's body carries the endpoint guard for when rsync returns |
| 4. No web-1 / git-data serialization | **git-data half fixed here; web-1 half moves to F2 with the first web-1 mutation** | The run holds workflow-level `git-data-state`. A read-only dry run that also joined `web-1-swap` could cancel a pending release deploy under #8167, and buys no protection because it mutates nothing on web-1 (DC-5) |

## Research Insights

### Premise Validation (Phase 0.6)

- **#8189** OPEN, the target. **#6680** OPEN (closes after a main dry run reads `role=git-data-auth
  verdict=ok`). **#5274** OPEN. **#8009** CLOSED ("C1 re-approval" = re-approving the recorded
  authorization accounting; obtained from CPO and CTO). **#8167** OPEN. **#6167** OPEN (branch-config
  non-isolation audit, names `prd_git_data`). **#6976** OPEN ("`hcloud_volume.git_data` is vestigial — it can
  never hold user data"). **#7226** OPEN. **#6538** CLOSED (web-2 orphan).
- Must stay open and are not scoped in: #8101, #8094, #6604, #8202, #7025, #8010.
- **#8093** OPEN. Its "sibling unit names" item is about the `sshd` unit name in `cloud-init.yml` /
  `cloud-init-registry.yml`, not blocker 2's units, so there is no overlap. Its replace-environment item is **not**
  taken: `terraform-target-parity.test.ts` asserts the replace job declares no `environment:` and calls an
  environment on replace-class targets "a fleet-wide policy call, not a local fix". The PR body carries
  `Ref #8093` only for the comment this PR posts there (Phase 0).
- The session note `/var/tmp/soleur-session-8a29da98/session-notes.md` carries four post-compound errors
  from PR #8187; this PR's learning absorbs them (Phase 7).
- Attribution claims verified live (git-history-analyzer): 0777caa9e (#8187), #8171 (`dde55bcf2` post-birth
  sweep), #6122, #8009, ADR-164 ("`DOPPLER_TOKEN_PRD`, which is `prd`-root-scoped"), ADR-088, ADR-119, ADR-130,
  the parity-test wording, `web-host-birth-environment.tf`, the birth disclosure, the 2026-07-05 contingency.

### Measured facts that change the issue's design

1. **ADR-220 D2's custody goal is already unmet.** Any branch workflow can name the `secrets.DOPPLER_TOKEN`
   repo secret, and it can read `prd_terraform`. That config holds:
   - `DOPPLER_TOKEN_TF` (a workplace-scope personal token)
   - `CF_API_TOKEN_R2` (account-wide R2; derived S3 keys measured 200 on two buckets)
   - `HCLOUD_TOKEN` (root on any host through rescue, rebuild or a volume re-attach)
   - `GITHUB_APP_PRIVATE_KEY`

   The repo is public, so run logs are public. The separate root's real value is that the key never enters
   the web-platform root, which dozens of plan and apply jobs read and print from. It does not protect
   against a repo-secret holder (F1, which needs its own ADR).
2. **A dedicated R2 bucket cannot be delivered and would buy nothing.** No token holds `API Tokens:Edit`
   (ADR-130). Only a human dashboard mint could create a bucket token, which
   `hr-tf-variable-no-operator-mint-default` and the task constraints forbid. `CF_API_TOKEN_R2` reads any
   bucket anyway. The new root uses `soleur-terraform-state` with its own key, the literal shape of
   `hr-every-new-terraform-root-must-include-an`. The parent's R2 credentials can read that object (DC-1).
3. **A `prd` branch config does not isolate.** A branch-config token resolves about 116 `prd` secrets
   (`workspaces-luks.tf` › "THE MECHANISM IS INHERITANCE DIRECTIONALITY"; learning
   `security-issues/2026-07-07-doppler-branch-config-does-not-isolate-secrets.md`). The key lives in a
   separate Doppler project. The same mechanism means the git-data host's own boot token (`prd_git_data`,
   readable by root there) likely resolves all of `prd` (#6167).
4. **Doppler OIDC is plan-gated.** Identities are "available with our Team and Enterprise plans"
   (<https://docs.doppler.com/docs/service-account-identities>). The ledger records the Developer plan, and
   config inheritance was measured denied on 2026-07-05. ADR fallback taken (DC-3).
5. **`doppler_service_token` has no expiry attribute** (1.21.2 schema: `access config id key name project`).
   A window toggle would revoke only the token (DC-4). Revocation is a reviewed PR that `-replace`s or
   removes the token.
6. **Environment secrets are not writable by the Terraform App** (403, `inngest-arm-write-token.tf`); repo
   secrets are. The environment is a human gate, not a secret boundary. `secrets: inherit` in two release
   workflows passes every repo secret to `reusable-release.yml`. The real boundary is repo write access.
7. **Existing environment.** `web-platform-infra-apply` is Terraform-managed (`web-host-birth-environment.tf`),
   with reviewer `[54279]` and custom branch policy `main`. It is recorded with `can_admins_bypass: true` and
   `prevent_self_review: false` (`apply-web-platform-infra.yml` › birth disclosure). Reuse removes the
   auto-create-unprotected hazard (DC-6); the weaker properties are stated.
8. **Flag credentials.** `DOPPLER_TOKEN_WRITE` has `prd_terraform` read/write scope. Today's `read_flag` gets a scope
   error that `|| echo ""` turns into "unset". `DOPPLER_TOKEN_PRD` exists as a repo secret with `prd`-root
   read scope. **Measured** with Doppler CLI v3.75.3 on 2026-09-15:
   - `doppler secrets get <absent> --plain --no-exit-on-missing-secret -p soleur -c dev` exits 0 with empty
     stdout.
   - Without the flag, the same call exits 1 with "Could not find requested secret".
   - A nonexistent config exits 1 even with the flag.
9. **Neither systemd unit exists.**
   - `soleur-web.service` and `soleur-drain.service` appear only in `git-data-cutover.sh` and ADR prose.
   - The app is `soleur-web-platform`, started by `docker run ... --env-file` from
     `doppler secrets download --config prd`.
   - `docker start` keeps the old env.
   - `webhook.service` has no `KillMode`.
   - ADR-119's freeze carries a dead-man timer.
   - The only writer (`replicateToGitData`) returns early unless the container's flag is `true`.

   All of this is carried into F2.
10. **Flag gating of git-data calls** (`apps/web-platform/server/git-data-replication.ts`). `provisionGitDataRepo`,
    `ensureGitDataRemote`, `replicateToGitData` and `fetchFromGitData` return early when the flag is off, so
    no repository has ever been created: the store is empty by construction.
    `removeGitDataRepo` is **deliberately not gated** ("data-integrity review LOW"). It runs whenever
    `GIT_REMOVE_SSH_PRIVATE_KEY` is set, and `account-delete.ts` calls it on every account deletion and
    mirrors a failure to Sentry.
11. **Self-rsync hazard (measured on `origin/main` bytes).** After `repoint_luks_mount`, a later dry run
    mounts the mapper at `FRESH_ROOT`, passes both `mountpoint` checks and reads "" from `read_flag`. It then
    runs `rsync --delete` with source and destination on one filesystem.
12. **Concurrency pins count one file.** `terraform-target-parity.test.ts` and
    `git-data-rung2-rehearsal.test.sh` count `^\s{6}group: git-data-state` in
    `apply-web-platform-infra.yml` only (exactly 2). A run waiting on approval holds its groups, and a newer
    pending entry cancels an older one (#8167).
13. **Placement and precedent.**
    - A root nested under `apps/web-platform/infra/` collapses to the parent in
      `detect-changes` (pinned by `plugins/soleur/test/infra-validation-detect.test.sh` TS2), so the PR `plan`
      job never initializes it.
    - `fmt -check -recursive` reaches it.
    - The rung-2 rehearsal root is the closest precedent: dispatch-only, workflow-level `git-data-state`,
      `environment: web-platform-infra-apply`, `init -input=false -lockfile=readonly`, allowlist refusal with a
      JSON parse check, and a validate step with `TF_DATA_DIR`.
    - `scheduled-terraform-drift.yml` runs two legs.
    - `apply-web-platform-infra.yml` › `notify-apply-failure` is the email-on-non-success pattern (#7586).
14. **Plan JSON shape (measured, Terraform 1.10.5, scratch root, 2026-09-15).** A data source fully known at
    plan time appears only in `.prior_state.values.root_module.resources[]` (`mode == "data"`). It does
    **not** appear in `resource_changes[]`.
15. **Provider schema (measured from the pinned schema JSON).** `hcloud_ssh_keys.ssh_keys` is a nested list
    with `id` **number**, `name`, `fingerprint`, `labels`, `public_key`. `hcloud_server.ssh_keys` is
    `list(string)`, so `tostring()` is required. `doppler_environment` requires `name`, `project`, `slug`.
    `doppler_project` requires `name`. `doppler_secret` has an optional `visibility`.
16. **Private NIC after a replace.** A fresh Hetzner host can boot with its private NIC down
    (`knowledge-base/project/learnings/2026-07-07-immutable-redeploy.md`; the auto-heal ships for the
    registry only). The replace job already states that authoritative liveness is the web-host-driven
    `git ls-remote` probe (`web-git-data-probe.sh`, every 60 s, pings its heartbeat URL on success), not SSH.
17. **The web-platform root change is inert on the live host.**
    - `hcloud_server.git_data` keeps `ignore_changes = [ssh_keys]`.
    - `with_selector` returns an empty list when nothing matches.
    - `git-data.tf` is not a rung-2 bound file, so the hash stays `5c50797be839…`.
    - The parity test asserts the replace job has no `environment:`.

### Property List (Phase 0.6b)

- P1. The cutover job authenticates to root on git-data through the ADR-220 jump, end to end.
- P2. The root private key is never in web-platform Terraform state, `prd_terraform`, `prd`, a log, an
  output or an artifact.
- P3. On `main` workflow bytes, the key is read only by a job that passed a human approval.
- P4. A flag read error stops the run (fail closed), a `true` flag is refused, and the `prd` read token never
  reaches a process that handles host bytes.
- P5. No workflow or script path can call a host mechanism that does not exist.
- P6. No run proceeds on an unmounted, already cut over, or non-empty store, and no rsync exists that could
  target its own source.
- P7. A cutover run never overlaps a git-data replace, create or rehearsal, and a root-key apply never
  overlaps a replace.
- P8. Host-chosen bytes never become a compared value without validation, a timeout and a size cap.
- P9. The key reaches the host only through a create (replace or birth), and a create that would not carry
  exactly that key, by fingerprint, fails closed.

### Cut List (Phase 0.6b)

- Dedicated R2 bucket → P2 → unachievable and not protective (DC-1).
- `prd_git_data_root` branch config → P3 → full-`prd` token; separate project instead.
- Key-bearing resources in the web-platform root → P2 → moved to the new root.
- Doppler OIDC identity → P3 → plan-gated (DC-3).
- A new `git-data-cutover` environment, its policy, a preflight env-assert script and job → P3 → the existing
  `web-platform-infra-apply` environment already gates on `main` with a reviewer (DC-6).
- An `approve` job split from the key job → P7 → its only purpose was keeping an approval wait off
  `web-1-swap`, which the read-only job no longer joins.
- `access_window_open` count toggle → none → revokes the token only (DC-4).
- A new `prd` read/write flag token → P4 → a read needs only `DOPPLER_TOKEN_PRD`; writing is F2.
- The cutover body (`prepare_luks_target`, `bulk_rsync`, `delta_rsync`, `verify_set_identity`,
  `repoint_luks_mount`, `canary_luks_device`, `old_volume_wipe`, `acquire_freeze`, `release_freeze`,
  `flip_flag_and_reload`, `rollback`, `web_ssh`, the recovery trap) → P5/P6 → unreachable, premised on
  nonexistent units, and to be redesigned by F2; git history keeps it (DC-2).
- `dry_run`, `rollback`, `confirm_wipe` inputs → P5 → removed.
- Host-output display pipe (`_host_out`) → P8 → no remaining display call outside the access gate.
- Cross-root label-parity guard → P9 → the create gate refuses a drift by name, label and fingerprint.
- An Actions-API exclusion script → P7 → the workflow-level + job-level group pattern already exists.
- `environment:` on `git_data_host_replace` (#8093 item) → none → contradicts the pinned parity assertion.
- Push trigger on the root-key apply → none → a merge alone has no blast radius. A push-queued approval would
  hold `git-data-state` and could cancel a queued replace (#8167), so the apply is dispatch-only, like the
  rung-2 rehearsal.
- Bridge-side `ssh_config` writer; a resource `precondition` on `hcloud_server.git_data` → P1/P9 → the bridge's
  Guard 2 pins its exports; a precondition would fail every web-platform plan.
- Direct repo secret holding the key (simplicity suggestion) → not cut: AP-008 and the operator's "read
  credential" direction keep the Doppler hop (DC-7).

### Institutional learnings applied

- `security-issues/2026-07-23-new-tf-resource-in-target-scoped-apply-root-and-unprotected-env-autocreate.md`
  — dissolved by reusing an existing environment; no branch dispatch of either workflow.
- `security-issues/2026-07-07-doppler-branch-config-does-not-isolate-secrets.md` — Insight 3.
- `best-practices/2026-07-05-cross-pipeline-serialization-via-shared-job-level-concurrency-group.md`.
- `best-practices/2026-06-18-live-credential-rotation-and-argv-to-env-redeploy.md` — no `ignore_changes`
  on the repo secret.
- `best-practices/2026-07-08-doppler-secret-precedent-mirror-tf-managed-project-needs-references.md`.
- `integration-issues/2026-04-05-terraform-doppler-dual-credential-pattern.md`.
- `security-issues/2026-05-25-terraform-show-json-leaks-sensitive-variables-into-fixtures.md` — gate fixtures
  synthesized; the root's plan JSON is never printed or uploaded, and the jq program reads only addresses and
  actions.
- `workflow-patterns/2026-07-19-real-cutover-routes-to-workflow-dispatch-and-failclosed-gate-must-self-report.md`.
- `2026-07-07-immutable-redeploy.md` — private NIC after a replace (Downtime & Cutover).

### CLAUDE.md / constitution conventions

AP-001, AP-003, AP-008; `hr-prod-host-config-change-immutable-redeploy`; `hr-no-ssh-fallback-in-runbooks`;
`hr-no-dashboard-eyeball-pull-data-yourself`; `hr-github-app-auth-not-pat`; `hr-observability-layer-citation`;
`cq-cite-content-anchor-not-line-number`; `cq-test-fixtures-synthesized-only`; `cq-assert-anchor-not-bare-token`.

### Baselines (measured on this branch, pre-edit)

- `bun test plugins/soleur/test/terraform-target-parity.test.ts` → **197 pass / 0 fail**.
- `bash tests/scripts/test-git-data-host-replace-gate.sh` → 23 passed / 0 failed.
- `bash tests/scripts/test-git-data-host-birth-gate.sh` → 114 passed / 0 failed.
- `bash apps/web-platform/infra/git-data-cutover-access.test.sh` → 69 passed / 0 failed / 0 skipped.
- `git_data_rung2_rehearsal_gate` → `RELEASED … 5c50797be8392fe551a940ae04555c52a3f4409cf249ed11bb1280fec783d5b1`.

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
| The key is delivered "at replace" | A label and a name can be forged by any `HCLOUD_TOKEN` holder | The create gate also compares a committed fingerprint |
| Freeze/reload via systemd units | Units do not exist | Cutover body deleted; F2 (DC-2) |
| Rollback split into ungated flag-off + gated sentinel (D2) | No rollback exists to split | F2 |
| `DOPPLER_TOKEN_WRITE` does the flag flip | `prd_terraform`-scoped | Not referenced; flag read via `DOPPLER_TOKEN_PRD` in its own step |
| "Once #8189 lands a dry run is no longer non-mutating" | This PR keeps it read-only | ADR-220 Consequences amended |
| Runbook: "reload both hosts", web-2 | web-2 retired (#6538) | Runbook sweep |

## Design

### D-1. The new root: `apps/web-platform/infra/git-data-root-key/`

Nested beside `rung2-rehearsal/`.

- **Backend.** `soleur-terraform-state`, key `web-platform/git-data-root-key/terraform.tfstate` (R2 block copied from
  `apps/web-platform/infra/main.tf`).
- **Providers.** doppler 1.21.2, hcloud 1.63.0, tls 4.3.0, github 6.12.1, with `~>` constraints like the
  rung-2 root. The lock is generated in the root with
  `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64`, and every init uses
  `-input=false -lockfile=readonly`.
- **`provider "github"`.** Copied verbatim from the parent's `app_auth` block (owner `jikig-ai`,
  installation `122213433`).
- **Variables.** Reuse `prd_terraform` names through `--name-transformer tf-var` (`hcloud_token`,
  `doppler_token_tf`, `github_app_id`, `github_app_private_key`). There is no new sensitive variable, no
  default and no human mint.
- **Hygiene.** Values are passed by reference. The root has no `output` block, no `nonsensitive(`, no
  `local_file`, no `local-exec` and no `provisioner`.

| Address | Purpose | Lifecycle |
|---|---|---|
| `tls_private_key.git_data_root` | ED25519 root key | `prevent_destroy = true` |
| `hcloud_ssh_key.git_data_root` | name `soleur-git-data-root`, `labels = { "soleur-role" = "git-data-root" }`, `public_key = tls_private_key.git_data_root.public_key_openssh` | `prevent_destroy = true` |
| `doppler_project.git_data_root` | isolated project | `prevent_destroy = true` |
| `doppler_environment.git_data_root_prd` | `slug = "prd"`, root config `prd` | `prevent_destroy = true` |
| `doppler_secret.git_data_root_ssh_private_key` | `GIT_DATA_ROOT_SSH_PRIVATE_KEY` = `private_key_openssh`, `visibility = "masked"` | `prevent_destroy = true` |
| `doppler_service_token.git_data_root_read` | read-only on the isolated config | — |
| `github_actions_secret.doppler_token_git_data_root` | repo secret `DOPPLER_TOKEN_GIT_DATA_ROOT` | no `ignore_changes` |

`.github/workflows/apply-git-data-root-key.yml`, modeled on `git-data-rung2-rehearsal.yml`:

- **Trigger and job setup.**
  - `workflow_dispatch` only, with inputs `confirm` (typed `APPLY-GIT-DATA-ROOT-KEY`) and
    `rotate_read_token` (optional typed `ROTATE-GIT-DATA-ROOT-READ-TOKEN`). Both are passed through `env:`
    and compared as literals.
  - `permissions: contents: read`, `timeout-minutes: 20`.
  - One `apply` job with `environment: web-platform-infra-apply` and job-level
    `concurrency: { group: git-data-state, cancel-in-progress: false }`, so it can never run between a
    replace's `plan -out` and its `apply`.
  - Every `uses:` pinned to a 40-character SHA with a `# vX` comment. `hashicorp/setup-terraform` at the
    repo's pin with `terraform_version: 1.10.5` and `terraform_wrapper: false`, and a pinned Doppler CLI
    version.
- **Plan.**
  - R2 creds are extracted with `::add-mask::`, as the rehearsal does.
  - `init -input=false -lockfile=readonly`, then `plan -input=false -out "$RUNNER_TEMP/tfplan"`.
- **Allowlist refusal.** `terraform show -json` is piped straight into `jq`, never to stdout.
  - The JSON must parse and carry a non-empty `resource_changes` array, else
    `verdict=git_data_root_key_plan_unreadable`.
  - Every change's `.change.actions` must be within `["no-op"]`, `["create"]` or `["read"]`, else
    `verdict=git_data_root_key_non_additive`. This rejects delete, update, replace and `forget`.
  - One exception: when `rotate_read_token` matches, `update`/replace/delete is allowed on
    `doppler_service_token.git_data_root_read` and `github_actions_secret.doppler_token_git_data_root`, and
    only if every other change is `no-op`.
  - The jq program reads only `.address` and `.change.actions`; a refusal prints only those two fields.
- **Apply and cleanup.**
  - `apply` of the saved plan.
  - A step prints the created key's `SHA256:` fingerprint, derived from `hcloud_ssh_key.git_data_root`
    through the Hetzner API. It is public and non-sensitive, and it is what the fingerprint PR commits.
  - An `if: always()` step shreds the plan file (hygiene; the ephemeral VM is the control). No `TF_LOG` is set.
- **Failure notice.** A `notify-root-key-apply` job with `needs: [apply]`,
  `if: always() && needs.apply.result != 'success'` and no environment calls `notify-ops-email`. It covers
  red, cancelled, refused and approval-rejected runs.

`apply-web-platform-infra.yml` gains `!apps/web-platform/infra/git-data-root-key/**`. `infra-validation.yml`
gains a validate step for the root modeled on the rung-2 root's (`terraform init -backend=false`,
`TF_DATA_DIR` under `runner.temp`).

### D-2. The web-platform root, the fingerprint anchor and the shared create-gate arm

`git-data.tf`: `data "hcloud_ssh_keys" "git_data_root" { with_selector = "soleur-role=git-data-root" }` and
`ssh_keys = concat([hcloud_ssh_key.default.id], [for k in data.hcloud_ssh_keys.git_data_root.ssh_keys : tostring(k.id)])`.
`ignore_changes = [ssh_keys]` stays; no `terraform_remote_state`.

**Fingerprint anchor.** `apps/web-platform/infra/git-data-root-key.fingerprint` holds one line,
`SHA256:<base64>`. A PR commits it after the first root-key apply, reviewed like any change. It is the
only value outside the reach of a repo-secret holder (security P1-1).

New `tests/scripts/lib/git-data-root-key-arm.sh` defines `git_data_root_key_arm <plan.json> <fingerprint-file>`,
sourced by both `git-data-host-replace-gate.sh` and `git-data-host-birth-gate.sh`. Over the saved plan JSON
it requires:

- the fingerprint file to exist and match `^SHA256:[A-Za-z0-9+/]{43}$`;
- `data.hcloud_ssh_keys.git_data_root` to be present in `.prior_state.values.root_module.resources[]`. If it
  is absent, or appears as a deferred `read` in `resource_changes[]`, the arm refuses;
- exactly one resolved key, named `soleur-git-data-root`, whose `fingerprint` equals the file (both
  normalized to the same form, checked in Phase 0.4);
- for every created `hcloud_server.git_data`, `after.ssh_keys` equal **as a set**, compared as strings, to
  the default key's id and that key's id.

A refusal emits `verdict=git_data_root_key_not_in_create reason=<fingerprint_file_missing|data_source_absent|key_count|name|fingerprint|server_keys>`
with a remedy line: "dispatch apply-git-data-root-key.yml; commit its printed fingerprint; re-dispatch.
After a rotation, the previous key stops authenticating at this create." Neither gate's allow-set literal
changes.

### D-3. Fail-closed flag read in its own step (blocker 1)

New `apps/web-platform/infra/git-data-flag-precheck.sh`. `git-data-cutover.yml` runs it as its own step,
**before** the bridge and the key fetch; it is the only step that receives `DOPPLER_TOKEN_PRD` (bound as
`DOPPLER_TOKEN` for that step). It runs `doppler secrets get GIT_DATA_STORE_ENABLED --plain
--no-exit-on-missing-secret -p soleur -c prd` (form measured, Insight 8). Non-zero rc →
`verdict=flag_read_failed`; `true` → `verdict=flag_already_true`; both exit 5; empty or any other value → prints
`flag=unset` or `flag=off` and exits 0. It prints nothing else. `git-data-cutover.sh` no longer reads Doppler.

### D-4. The script after deletion (blockers 2 and 3)

`git-data-cutover.sh` keeps:

- the header, rewritten: a read-only proof until F2; exit codes 3 access, 5 refusal;
- configuration and `resolve_roster`;
- the access gate, unchanged;
- `gd_capture`;
- the three store probes and `main`.

It deletes every function in the Cut List, the EXIT recovery-trap branches that called them (the trap keeps only
the access-gate temp cleanup), `web_ssh`, and every `DRY_RUN` / `CONFIRM_WIPE` / `ROLLBACK` branch. If any of
those three variables carries a non-default value, `main` refuses first with
`verdict=real_cutover_unreconciled` (exit 5), a remedy naming F2, and no remote call.

### D-5. Read-only store probes (blocker 3)

After the access gate, three probes run through `gd_capture` on git-data, in order. Each fails closed:

1. `refuse_if_unmounted`: `findmnt -no SOURCE "$OLD_ROOT"` must succeed and match `^/dev/[A-Za-z0-9/_.-]+$`;
   empty, non-zero, or no match → `verdict=old_store_unmounted`.
2. `refuse_if_cut_over`: that source equal to `$LUKS_MAPPER` → `verdict=already_cut_over`.
3. `refuse_if_store_not_empty` (CPO condition; it holds until #7226 pins git-data's host key):
   - the count of `*.git` entries under `$OLD_REPOS` must match `^[0-9]+$`;
   - a missing `$OLD_REPOS` on the mounted root counts as 0;
   - a probe error → `verdict=probe_failed`;
   - a non-zero count → `verdict=store_not_empty`.

When all three pass, the script exits 0 with a summary of fixed verdict words only. While host keys are
unverified, this evidence is not authenticated: a compromised web-1 could answer it (ADR-220 D4).

### D-6. Workflow shape (blocker 4)

`git-data-cutover.yml`:

- **Shape.** Inputs reduced to `confirm`; `permissions: contents: read`; workflow-level
  `concurrency: { group: git-data-state, cancel-in-progress: false }`.
- **Job.** One job, `cutover`, with `environment: web-platform-infra-apply`. Every `uses:` is SHA-pinned.

Steps, in order:

1. confirm token;
2. Doppler CLI (pinned version);
3. **flag precheck** (D-3; `DOPPLER_TOKEN_PRD` bound here only);
4. secrets-present check. An empty `DOPPLER_TOKEN_GIT_DATA_ROOT` → `verdict=git_data_root_token_absent`;
5. bridge (unchanged `server-ip` form);
6. **key fetch**:
   - refuses xtrace, `umask 077`;
   - the fixed path `$RUNNER_TEMP/gd-root-key` is never written to `$GITHUB_ENV`;
   - `doppler secrets get GIT_DATA_ROOT_SSH_PRIVATE_KEY --plain -p soleur-git-data-root -c prd` runs under
     `DOPPLER_TOKEN_GIT_DATA_ROOT`, straight into the file with a trailing newline;
   - `::add-mask::` for each key line is emitted before any other output, as defence in depth (the key
     never reaches stdout);
   - `ssh-keygen -y -f` must derive a public key, else `verdict=git_data_root_key_fetch_failed
     reason=<rc_nonzero|empty|not_openssh_key>`, printing the reason word only;
7. **`ssh_config` writer**, fixed path `$RUNNER_TEMP/gd-ssh-config`:
   - exact `Host 10.0.1.10` and `Host 10.0.1.20` blocks, with no `Host *`;
   - `IdentityFile` only in its own block: `$CI_SSH_KEYFILE` for web-1, the root key for git-data;
   - git-data block: `ProxyCommand ssh -F <cfg> -W 10.0.1.20:22 10.0.1.10` with a **literal** target, no `%h`;
   - both blocks: `IdentitiesOnly yes`, `BatchMode yes`, `LogLevel ERROR`, `ForwardAgent no`,
     `ClearAllForwardings yes`, `PermitLocalCommand no`, `ControlPath none`, `UpdateHostKeys no`, and the
     bridge's host-key options;
8. script step with `GIT_DATA_SSH="ssh -F <cfg>"`; it receives no Doppler token except the bridge's
   `DOPPLER_TOKEN` scope already present;
9. teardown `if: always()`: bridge teardown plus `shred -u` of the key file and config (hygiene; the ephemeral
   VM is the control).

`DOPPLER_TOKEN_WRITE` is no longer referenced. Because the environment sits on the key-reading job, a re-run
asks for approval again.

### D-7. Captured values (P8)

`gd_capture <anchored-regex> <remote-cmd>` runs
`timeout 30 "${inv[@]}" -o BatchMode=yes -o ConnectTimeout=20 "$GIT_DATA_HOST" "$cmd" </dev/null` with
stdout piped through `head -c 4096` into a variable, and stderr to a temp file. It takes the ssh rc from
`PIPESTATUS[0]` via `|| rc=...` (not the pipeline). It strips one trailing newline and returns 96 unless the
value matches the pattern in full; a multi-line value never matches. It never prints the value. On failure it
prints the capped, filtered stderr through the access gate's existing `_access_stderr` path.

## Downtime & Cutover

**Operation.** `git_data_host_replace` (AC18) destroys and recreates `hcloud_server.git_data`
(`soleur-git-data`) so its create-time `ssh_keys` carry the root key. It re-attaches the private NIC, both
store volumes and the firewall.

**Surfaces affected.**

- **Web requests: none.** The flag is off, so provision, replicate and fetch return before touching git-data
  (Insight 10).
- **Settings → Delete Account.** It still calls `removeGitDataRepo` during the replace window. Each deletion
  can wait for ssh's connect timeout and records an "Art. 17 erasure failed" Sentry event. The account
  deletion still completes, because `account-delete.ts` mirrors the failure and continues. No repository can
  exist (Insight 10), so no personal data is left behind. The events are expected noise for the window.
- **git-data readiness probe.** It goes red for the window.

**Zero-downtime path evaluated.**

- **Blue-green (a second host, then switch): rejected.** Both store volumes attach to one server and the
  private address `10.0.1.20` is fixed in every consumer. A second host would need a new address, volume
  moves and a consumer repoint, which is more risk than a minutes-long outage of a surface no user request
  depends on.
- **In-place key delivery: rejected.** It violates `hr-prod-host-config-change-immutable-redeploy`.
- **Accepted: the existing replace**, whose gate already asserts both volumes are retained. It runs in a
  window bounded by the replace job's own duration and requires explicit authorization (AC18).

**Stage verification and rollback.**

1. The replace job's applied-plan asserts (volumes preserved, NIC and attachments re-created).
2. **Private-NIC readiness (no SSH).** Before AC19, read the `web-git-data-probe` heartbeat's state through
   its provider API (identified in Phase 0.8) and require it green after the replace finished. This proves
   `git ls-remote` over the private network reaches `10.0.1.20`.
3. The dry run (AC19). The runbook verdict map separates L3 from L7:
   - L3: `role=git-data-jump reason=timeout|no_route|connect_refused` (NIC or sshd not up).
   - L7: `role=git-data-auth reason=auth_refused` (key not delivered, or delivered before a rotation).

Rollback of a failed create is the existing re-dispatch path: the volumes are retained. If the root key's
Hetzner object is missing, the create gate refuses until the root-key apply runs again. While the host is
down, every account deletion logs an erasure failure. The runbook names both.

## Infrastructure (IaC)

### Terraform changes

- New root `apps/web-platform/infra/git-data-root-key/` (`main.tf`, `variables.tf`, `key.tf`, `access.tf`,
  `.terraform.lock.hcl`) per D-1.
  - Inputs via `tf-var` from `prd_terraform`: `TF_VAR_hcloud_token`, `TF_VAR_doppler_token_tf`,
    `TF_VAR_github_app_id`, `TF_VAR_github_app_private_key`.
  - Raw `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` are set before `init`.
- `apps/web-platform/infra/git-data.tf`: data source plus `ssh_keys` concat (D-2).
- `apps/web-platform/infra/git-data-root-key.fingerprint` (post-merge PR, AC17).

### Apply path

1. (b) an authorized dispatch of the allowlist-gated root-key apply;
2. a fingerprint PR;
3. (c) the existing `git_data_host_replace` dispatch delivers the key at create (Downtime & Cutover).

Merging changes no infrastructure. It fires the web-platform push apply, whose `-target` set does not include
`hcloud_server.git_data` or the new data source's consumers.

### Distinctness / drift safeguards

- **Destroy protection.** `prevent_destroy` covers the key, the Hetzner key object, the Doppler project, its
  environment and the secret. The allowlist refusal rejects `forget`. A rotation is a reviewed PR that lifts
  `prevent_destroy`, plus a dispatch and a new fingerprint PR.
- **Create gate.** It requires exactly one key by label, name and committed fingerprint.
- **Drift, by case** (no drift leg for the new root: a scheduled leg would need state that holds the private key).
  - A deleted or swapped Hetzner key object → the create gate.
  - A deleted Doppler secret or a revoked token → `git_data_root_key_fetch_failed` on the next dispatch.
- **State.** It is readable by `prd_terraform` R2 credentials (Insight 1, F1).

### Vendor-tier reality check

Doppler Developer plan: no identities and no config inheritance (both avoided). Phase 0.2 probes the project
limit; the zot and inngest projects already count against it. GitHub environment secrets are not writable
by the App (avoided). Hetzner key objects are free and label-selectable.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-220** with a dated amendment log. There is no new ordinal; D2 and D3 are still `proposed`.

**D2**
- Custody measured nominal, with the public-log justification for the separate root.
- Separate Doppler project; shared bucket (D2.1 reversed).
- OIDC fallback taken on plan-tier evidence.
- The reused environment and its `can_admins_bypass: true` / `prevent_self_review: false`.
- The environment is a human gate, not a secret boundary; `secrets: inherit` passes repo secrets to
  reusable workflows. The real boundary is repo write access, and the service token never expires.
- The fingerprint anchor.

**D3**
- No window.
- Host authorization ends only at a replace after a rotation.
- Token revocation is a reviewed `-replace`.

**D4 — new residuals**
- F1 reachability, to be decided in F1's own ADR.
- `HCLOUD_TOKEN` already reaches root on the host through rescue, rebuild or a volume re-attach; the separate
  root does not protect against that holder.
- A leaked root key already exposes `prd` secrets through the host's `prd_git_data` token (#6167), before any
  repository exists.
- Store-probe evidence is unauthenticated until #7226.
- Root logins on git-data are not detected (tracked on #8093).
- Breach triage: once repositories exist, a root-key leak is a likely Art. 33 event.
- `store_not_empty` holds until #7226.
- There is no drift leg for the new root.
- After a key rotation, dry runs fail auth until the next replace.

**D5.** Statuses updated. D1b flips on the AC19 run, recorded with the unauthenticated-evidence caveat.

**D6.** Sequencing, and the F2 hand-off: the cutover body, the rollback split, `web-1-swap` membership, and
three preconditions (#7226, F1, and a fresh replace plus a `GIT_DATA_LUKS_KEY` rotation immediately before
the real cutover).

**Consequences.** The dry run stays read-only.

### C4 views

Read all three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` and check:

- **External actors.** The approving reviewer is the existing founder actor.
- **External systems.** GitHub Actions, Doppler, Hetzner API, Cloudflare R2. Confirm each is modeled.
- **Containers touched.** `gitDataStore` and web-1.
- **Relationship `github -> gitDataStore`.** Retire "until #8189" and describe the reviewer-gated, read-only
  root SSH through the web-1 jump.

C4 models the running system, so no Terraform-root element is added. Validate with
`apps/web-platform/test/c4-code-syntax.test.ts`, `apps/web-platform/test/c4-render.test.ts` and
`bash plugins/soleur/test/c4-count-parity.test.sh`.

### Sequencing

D1b flips to `accepted` when the post-merge main dry run reads `role=git-data-auth verdict=ok`. D2 and D3
stay `proposed` until #7226, F1 and F2 land.

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
  - store: "runner $RUNNER_TEMP key file, ssh_config and the root-key plan file (ephemeral GitHub-hosted VM)"
    mechanism: plaintext-exception
    evidence: "the job's VM is discarded after the run; shred -u in if: always() steps is hygiene only"
    defends_against: "reuse of the files by a later job"
    does_not_defend: "another step of the same job reading a file while it exists, or recovery from journaled/SSD storage before the VM is discarded"
    disclosed_as: "ADR-220 D2"
    live_verification: "bash apps/web-platform/infra/git-data-cutover-access.test.sh"
in_transit:
  - connection: "runner -> Doppler API (flag read, key read)"
    tls: "TLS 1.2+"
    cert_verification: on
    does_not_defend: "a leaked token used from elsewhere"
    disclosed_as: "ADR-220 D2"
  - connection: "runner -> web-1 -> git-data SSH (-W jump inside the CF tunnel)"
    tls: "CF tunnel TLS + SSH-2 end to end"
    cert_verification: off
    does_not_defend: "a compromised web-1 impersonating git-data (host keys unverified), including forging store-probe answers"
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

**Harness conventions (apply to every guard below).**

- **Code-edit rows run as mutants.** They use a `mutate()` helper modeled on
  `apps/web-platform/infra/arm-heartbeats.test.sh`: copy the file under test, apply the edit with `sed` to the
  copy, assert the edit landed on the expected number of lines, point the suite's override (`GDC_SCRIPT`,
  `GDC_WORKFLOW`, `GDC_GITHUB_DIR`, `GD_ROOT_KEY_DIR`) at the copy, and require the named case to fail.
- **Fixture rows run as negative cases.**
- **Floors.** Each suite declares `MUTANT_FLOOR` equal to its matrix-row count, and an assertion `FLOOR`
  stated after Phase 1 (69 will not survive the deleted cases).
- **YAML parsing.** Look up `on:` as `wf.get(True) or wf.get("on")`. Booleans are compared with `is False`.
  Every census has a lower bound as well as a ban.
- **Doppler shim.** It answers per secret name and flag; the existing argument-blind shim is replaced.
- **Timelines.** They are asserted with `diff` against an expected file.
- **Stale assertions.** `mutating()` must stop classifying `findmnt` as mutating; WF9's `DOPPLER_TOKEN_WRITE`
  allowance is rewritten.
- **RED against `origin/main`.** Each named case must fail on its own assertion, using a stub arm that
  accepts every plan and an empty root directory, recorded in a per-row ledger.

### Guard 1 — the flag read fails closed and stays away from host bytes

**Property.** No run reaches the bridge unless the flag read succeeded and the value is not `true`, and the
`prd` read token appears in no step other than the flag precheck.
**Assembly.** `git-data-flag-precheck.sh`, the step list of `git-data-cutover.yml` (order and each step's
`env:`), the per-name `doppler` shim.
**Mutation matrix.**

| Edit | Must go RED |
|---|---|
| restore `\|\| echo ""` semantics (treat a non-zero rc as unset) | scope-error case |
| REORDER: move the flag precheck step after the bridge step | step-order assertion |
| bind `DOPPLER_TOKEN_PRD` in the script step's `env:` as well | token-placement census |
| compare `true` case-insensitively or with trailing space | exact-`true` refusal case |

**Harness rows.** A shim that exits 0 with empty output for the absent name → PASS as unset; a shim that exits
non-zero on absent (ignores the flag) → the absent case goes RED.
**Anchor.** None stored.

### Guard 2 — no run on an unmounted, cut-over or non-empty store; no rsync to misdirect

**Property.** The dry run exits 0 only when the source of `$OLD_ROOT` is a device, is not the mapper, and
`$OLD_REPOS` holds zero `*.git` entries, each probe failing closed; and the script contains no `rsync`,
`cryptsetup`, `mount`, `umount`, `mkfs`, `rm -rf` or `touch` invocation.
**Assembly.** `refuse_if_unmounted`, `refuse_if_cut_over`, `refuse_if_store_not_empty`, their order in
`main()`, and a census over every non-comment line of `git-data-cutover.sh` (at least one line scanned).
**Mutation matrix.**

| Edit | Must go RED |
|---|---|
| accept an empty `findmnt` source | unmounted case |
| delete `refuse_if_cut_over` (keep the other two) | mapper-source case |
| treat a failed count probe as zero | probe-error case |
| reintroduce a `bulk_rsync` function | mutating-verb census |

**Harness rows.** A mounted plaintext source with a missing `$OLD_REPOS` → PASS; a count of `0` with a trailing
newline → PASS.
**Anchor.** None stored.

### Guard 3 — the root token is referenced only by the gated cutover job

**Property.** `DOPPLER_TOKEN_GIT_DATA_ROOT` appears under `.github/` only in `git-data-cutover.yml` job
`cutover`, which declares `environment: web-platform-infra-apply`. The only `secrets: inherit` sites are the
known release callers, and `reusable-release.yml` never names the token. It prevents accidental use on `main`
bytes; it does not stop a branch workflow from naming a repo secret (ADR-220).
**Assembly.** Every file under `.github/workflows/` and `.github/actions/` (census; at least one file scanned),
plus every `secrets: inherit`, `toJSON(secrets)` and `secrets[` occurrence.
**Mutation matrix.**

| Edit | Must go RED |
|---|---|
| add a second job in `git-data-cutover.yml` referencing the token | per-job predicate |
| add a second workflow file referencing it, after the compliant first | tree census |
| add `secrets: inherit` to a new caller | inherit-site allow set |
| remove `environment:` from `cutover` | gated-job predicate |

**Harness rows.** The name only in a YAML comment → PASS; an empty scan set → reports `0 files scanned` as a
failure.
**Anchor.** The known inherit-site set lives in the test; widening it is a reviewed edit.

### Guard 4 — a create carries exactly the root key, by fingerprint

**Property.** Both host-creating gates refuse a plan unless the committed fingerprint file is well-formed, the
data source resolved in `prior_state` to exactly one key named `soleur-git-data-root` whose fingerprint equals
the file, and every created `hcloud_server.git_data` carries, as a set of strings, exactly the default key's id
and that key's id.
**Assembly.** `git_data_root_key_arm` in `tests/scripts/lib/git-data-root-key-arm.sh`, its call sites in the
replace and birth gates (census: exactly those two), and the fingerprint file.
**Mutation matrix.**

| Edit | Must go RED |
|---|---|
| fixture: resolved key has the right name and label but a different fingerprint | fingerprint arm |
| fixture: data source absent from `prior_state` | presence arm |
| fixture: created server carries only the default key | membership arm |
| remove the arm call from the birth gate (keep it in the replace gate) | call-site census |

**Harness rows.** Replace and birth fixtures extended with a `prior_state` data block and both ids → PASS;
numeric id in the data source and string on the server → PASS; reordered `ssh_keys` → PASS; a missing
fingerprint file → RED with `reason=fingerprint_file_missing`.
**Anchor.** `apps/web-platform/infra/git-data-root-key.fingerprint`, committed by a reviewed PR; a
`HCLOUD_TOKEN` holder cannot move it.

### Guard 5 — captured host values are validated, bounded and never printed

**Property.** No value returned by a remote command is compared or counted unless it matched its anchored
pattern in full, arrived within 30 s and 4096 bytes, and it is never echoed.
**Assembly.** `gd_capture` and every call site of it (census; at least one), plus any `$(...)` capture of
`"${inv[@]}"` or `$GIT_DATA_SSH` outside `access_gate`.
**Mutation matrix.**

| Edit | Must go RED |
|---|---|
| return the value without the pattern check | injected second-line case |
| drop the `timeout` wrapper | hung-shim case (bounded by the suite's own timeout) |
| echo the captured value in the mismatch branch | no-echo assertion |
| add a raw `$("${inv[@]}" ...)` capture outside `gd_capture` | capture census |

**Harness rows.** A value with one trailing newline → PASS and compares equal.
**Anchor.** None stored.

### Guard 6 — serialization

**Property.** `git-data-cutover.yml` holds workflow-level `git-data-state` and `apply-git-data-root-key.yml`
holds job-level `git-data-state`, both with `cancel-in-progress` `is False`, with the literal equal to the
replace job's; the existing count pins stay at 2.
**Assembly.** The access suite's and the root suite's YAML checks, compared against the group literal extracted
from `git_data_host_replace` in `apply-web-platform-infra.yml`.
**Mutation matrix.**

| Edit | Must go RED |
|---|---|
| rename the cutover workflow's group to `git-data-cutover` | literal parity |
| delete the `cancel-in-progress` key on the root-key apply job | `is False` assertion |
| move the root-key apply's group to another job-level name | literal parity |

**Harness rows.** `terraform-target-parity.test.ts` and `git-data-rung2-rehearsal.test.sh` unchanged → PASS.
**Anchor.** The replace job's literal (outside both new files).

### Guard 7 — a real mode cannot be requested

**Property.** `git-data-cutover.yml` declares exactly the input set `{confirm}`, and the script exits 5 with
`verdict=real_cutover_unreconciled` and an empty timeline when `DRY_RUN`, `ROLLBACK` or `CONFIRM_WIPE` carry a
non-default value.
**Assembly.** The workflow's `workflow_dispatch.inputs` (read via the `True`-key lookup), `main()` entry.
**Mutation matrix.**

| Edit | Must go RED |
|---|---|
| re-add a `rollback` input | exact input set |
| refuse only `ROLLBACK` (drop the `CONFIRM_WIPE` arm) | wipe case |
| REORDER: move the refusal after `access_gate` | empty-timeline assertion |

**Harness rows.** No variables set → reaches the access gate (PASS); a workflow whose `on:` key parses as `True`
→ still read correctly (PASS).
**Anchor.** None stored.

### Guard 8 — the root-key apply is additive-only, exposes nothing and reports failure

**Property.** `apply-git-data-root-key.yml` applies only a plan whose every change is `no-op`, `create` or
`read`, except the typed read-token rotation. It refuses an unreadable plan JSON, and its jq reads only
`.address` and `.change.actions`. It uses SHA-pinned actions with `terraform_wrapper: false` and a readonly
lock, and has no push trigger, `upload-artifact`, stdout `terraform show`, `terraform output` or `TF_LOG`. It
shreds the plan file `if: always()` and notifies on any non-success. The root contains no `output`,
`nonsensitive(`, `local_file`, `local-exec` or `provisioner`.
**Assembly.** The refusal step's jq over `resource_changes[]`, the workflow's triggers and step list (census),
the root's `.tf` files (census).
**Mutation matrix.**

| Edit | Must go RED |
|---|---|
| fixture: `tls_private_key.git_data_root` with actions `["forget"]` | allowlist arm |
| fixture: read-token replace without the typed input | rotation-input arm |
| fixture: empty `show -json` output | parse arm |
| add an `output` block with `nonsensitive(` to the root | root census |
| remove the `notify-root-key-apply` job | step census |

**Harness rows.** A create-only fixture → PASS; a read-token replace with the typed input and all else `no-op` →
PASS; the same with one other `update` → RED.
**Anchor.** None stored.

## Implementation Phases

### Phase 0 — Probes, baselines, follow-ups (no product code)

1. Re-measure the baselines above.
2. Doppler: read-only probe of the workplace project limit and identity availability; record verdicts.
3. Record the already-measured Doppler CLI semantics (Insight 8) in the flag-precheck script header.
4. Fingerprint form: check whether the Hetzner API's `fingerprint` is MD5-hex or `SHA256:` form. Normalize the
   arm and the apply's print step to one form: `ssh-keygen -l -E sha256` on the public key, compared with a
   value derived the same way from the data source's `public_key`.
5. Scratch `terraform validate` of the planned root (`-backend=false`), and generate the lock file with
   `terraform providers lock`.
6. Consumer sweep before deleting the cutover body: `git grep -n 'git-data-cutover.sh'` and
   `git grep -nE 'bulk_rsync|repoint_luks_mount|canary_luks_device|old_volume_wipe|verify_set_identity|prepare_luks_target'`
   outside the script. Every hit is an edit.
7. Resolve the pinned SHAs for `actions/checkout`, `hashicorp/setup-terraform` and `DopplerHQ/cli-action`
   from the repo's existing uses. Confirm each is exactly 40 characters (`git grep -hE 'uses: <action>@'`), and
   pin the Doppler CLI version the action installs.
8. Identify the `web-git-data-probe` heartbeat's monitor and the read-only API call that returns its state (for
   the Downtime & Cutover stage-2 read).
9. File these issues, each after a duplicate search, in milestone **Post-MVP / Later**:
   - **F1** "evict repo-secret-reachable `DOPPLER_TOKEN_TF`, `CF_API_TOKEN_R2`, `GITHUB_APP_PRIVATE_KEY`,
     `HCLOUD_TOKEN` from `prd_terraform`". Needs its own ADR; a precondition of the first real cutover;
     links #6167.
   - **F2** "git-data cutover real modes on real mechanisms". Its body carries:
     - the CTO recommendation: no hard freeze; in-container flag proof; a same-version redeploy accepting only
       a frame started after the flag write; a lock-free probe; rollback restarts the webhook unit first; a
       windowed `prd` flag write token; the gc timer stopped before the repoint; resume after a partial
       repoint;
     - the spec-flow P0/P1 list: dead-man or no freeze; window-close/rollback interplay; `always()` result
       clauses; a split-brain assertion via the container's env; the tag read after the webhook unit stops;
       #8167 rollback displacement;
     - the advisor's tiered rollback and shared deploy-status poller;
     - `assert_distinct_endpoints` (`stat -L -c %d:%i` on both repo endpoints after `mkdir -p`);
     - `web-1-swap` membership on the job that drains web-1, and the rollback job split (ADR-220 D2);
     - the missing `GIT_DATA_LUKS_CUTOVER_AT` writer;
     - a mutating rehearsal with entry-state restore;
     - downtime statements;
     - `verify_set_identity` printing hashed names;
     - the guards it inherits (1, 2, 5, 7);
     - preconditions: #7226, F1, and a fresh replace plus a `GIT_DATA_LUKS_KEY` rotation immediately before
       the cutover.
   - **F4** "git-data: `/dev/mapper/git-data` is not reopened at boot". A post-cutover reboot leaves
     `/mnt/git-data` without its backing device.
   - **A comment on #8093** covering: the stale "root path the cutover uses" prose in
     `git-data-pre-receive.sh` / `git-data-pre-receive-placeholder.sh`; root-login detection on git-data; and
     a Delete Account connect timeout on `removeGitDataRepo` (`sshWithPrivateKeyAuth` sets no
     `ConnectTimeout`). All for the next batch.

### Phase 1 — RED (matrices before code)

Write every Guard 1–8 mutation and harness row as failing cases against `origin/main` bytes, using the harness
conventions:

- `git-data-cutover-access.test.sh`: G2, G3, G5, G6 (cutover half), G7, the D-6 step order and YAML, the
  key-fetch and `ssh_config` steps.
- New `apps/web-platform/infra/git-data-flag-precheck.test.sh`: G1.
- New `tests/scripts/test-git-data-root-key-arm.sh`: G4, plus the two existing gate suites, whose fixtures gain
  `prior_state` and a fingerprint file.
- New `apps/web-platform/infra/git-data-root-key.test.sh`: G6 (root half), G8, the backend key, every
  `prevent_destroy`, no `terraform_remote_state` in the parent, and the path exclusion in
  `apply-web-platform-infra.yml`.
- `plugins/soleur/test/infra-validation-detect.test.sh`: the nested root collapses to the parent.

Remove the access suite's cases for deleted functions only after their replacements exist.

### Phase 2 — New root and its apply workflow

D-1 files, the lock file, `apply-git-data-root-key.yml` (with the notify job) and the `infra-validation.yml`
validate step.

### Phase 3 — Web-platform root and the create gates

D-2. Run `bun test plugins/soleur/test/terraform-target-parity.test.ts`: it must read **197 pass / 0 fail**. If
any pinned assertion would need to change, stop and re-plan rather than editing the pin.

### Phase 4 — Script and flag precheck

D-3, D-4, D-5 and D-7.

### Phase 5 — Workflow

`git-data-cutover.yml` per D-6. Register new suites in `infra-validation.yml`. Run `actionlint` on every
changed workflow.

### Phase 6 — Docs and records

- ADR-220 amendment log (see Architecture Decision above).
- C4 edge.
- Runbook `git-data-luks-cutover-5274.md`:
  - rewrite the Precondition and Sequence: the dispatch is a read-only proof, and the real steps are blocked
    on F2, F1 and #7226;
  - remove web-2;
  - add the post-merge order (AC16–AC19);
  - add the verdict map:
    - before the root-key apply → `git_data_root_token_absent`;
    - before the fingerprint PR or with a swapped key → the create gate's `reason=`;
    - before the replace → `role=git-data-auth reason=auth_refused`;
    - private NIC down → `role=git-data-jump reason=timeout|no_route`;
    - after a rotation, until the next replace → `auth_refused`;
  - note that a pending approval holds `git-data-state`: answer or cancel it before dispatching a replace;
  - add the #8167 re-dispatch note;
  - describe what users see during the replace (Delete Account erasure-failure events, no request impact);
  - add the breach-triage trigger.
- Article 30 git-data entry, one (g) TOM, DRAFTED / NOT-YET-ACTIVE, within CLO's limits:
  - **May say:** it is a fourth SSH authority, root, with no forced command, able to bypass (g)(2) and
    (5)–(8); it is held in the isolated Doppler project and the R2 state object, not `prd`; it is delivered
    only by a create of `hcloud_server.git_data` and checked by a committed fingerprint.
  - **Must not claim:** expiry, two-party review, custody isolation from repo-secret holders, host-key
    verification, host-side revocation at the next replace, or anything about encryption at rest.
  - Also add cross-references from (g)(5) and (g)(6).
  - Mark the stale "unborn" wording Superseded, citing #8171, without touching any Status cell or PA-2
    (g)(17).
  - Qualify the Cross-Cutting "Secrets management" bullet with F1.
- The git-data authorization accounting (#8009 C1): record the root key as a distinct authority beside the three
  forced-command keys (location found with `git grep -n 'three distinct'`).
- `knowledge-base/product/roadmap.md`, the #5274 cutover row: add F1 and F2 as preconditions (CPO).
- Sweep "until #8189" / "not yet" wording.

### Phase 7 — Validation battery and learning

- **Battery.** Launch the full battery with `setsid nohup` from a Bash call and watch it from a separate
  Monitor (session error 2).
- **Pre-push checks.**
  - `python3 plugins/soleur/test/lib/fixture-scan.py --rule relative --repo .` on every new shell write site
    (session error 1).
  - `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.
  - `python3 scripts/lint-guard-contract.py` on this plan.
  - The rung-2 gate prints `RELEASED 5c50797be839…`.
- **Learning.** Write the compound learning under `knowledge-base/project/learnings/security-issues/`. Topic: a
  custody boundary measured nominal, and a wrong-scope token whose error read as "unset". It carries the four
  session-note errors with their prevention lines, including error 4: a GitHub-managed CodeQL SARIF upload
  failure is non-required and non-retryable, so record it and do not chase it.
- **PR body (session error 3).** "this diff changes Terraform code; merging fires only the web-platform push
  apply, whose `-target` set does not include `hcloud_server.git_data` (expected no resource change from
  `git-data.tf`); the root-key apply is dispatch-only". Read the push apply's Plan line after merge.

## Files to Create

- `apps/web-platform/infra/git-data-root-key/main.tf`
- `apps/web-platform/infra/git-data-root-key/variables.tf`
- `apps/web-platform/infra/git-data-root-key/key.tf`
- `apps/web-platform/infra/git-data-root-key/access.tf`
- `apps/web-platform/infra/git-data-root-key/.terraform.lock.hcl`
- `apps/web-platform/infra/git-data-root-key.test.sh`
- `apps/web-platform/infra/git-data-flag-precheck.sh`
- `apps/web-platform/infra/git-data-flag-precheck.test.sh`
- `tests/scripts/lib/git-data-root-key-arm.sh`
- `tests/scripts/test-git-data-root-key-arm.sh`
- `.github/workflows/apply-git-data-root-key.yml`
- `knowledge-base/project/learnings/security-issues/<date>-<topic>.md`
- Post-merge PR: `apps/web-platform/infra/git-data-root-key.fingerprint`

## Files to Edit

- `apps/web-platform/infra/git-data-cutover.sh`
- `apps/web-platform/infra/git-data-cutover-access.test.sh`
- `.github/workflows/git-data-cutover.yml`
- `apps/web-platform/infra/git-data.tf`
- `tests/scripts/lib/git-data-host-replace-gate.sh`
- `tests/scripts/test-git-data-host-replace-gate.sh`
- `tests/scripts/lib/git-data-host-birth-gate.sh`
- `tests/scripts/test-git-data-host-birth-gate.sh`
- `.github/workflows/apply-web-platform-infra.yml` (path exclusion; the replace and create gate calls pass the
  fingerprint file path)
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

**Untouchable (hash-bound; AC8), full paths:**

- `apps/web-platform/infra/cloud-init-git-data.yml`
- `apps/web-platform/infra/modules/git-data-userdata/main.tf`
- `apps/web-platform/infra/modules/git-data-userdata/outputs.tf`
- `apps/web-platform/infra/modules/git-data-userdata/variables.tf`
- `apps/web-platform/infra/git-data-bootstrap.sh`
- `apps/web-platform/infra/git-data-gc-failure.service`
- `apps/web-platform/infra/git-data-gc.service`
- `apps/web-platform/infra/git-data-gc.sh`
- `apps/web-platform/infra/git-data-gc.timer`
- `apps/web-platform/infra/git-data-pre-receive-placeholder.sh`
- `apps/web-platform/infra/git-data-provision.sh`
- `apps/web-platform/infra/git-data-remove.sh`
- `apps/web-platform/infra/git-data-transport-wrapper.sh`
- `apps/web-platform/infra/git-data-rung2-boot-evidence.env`

## Open Code-Review Overlap

1 open scope-out touches these files: #7098 (audit `run:` bodies whose `set` omits `-e`; names
`apply-web-platform-infra.yml`). **Acknowledge:** a repo-wide lint audit, a different concern; this plan's edits
there are a path-filter line and a gate argument.

## Observability

```yaml
liveness_signal:
  what: "git-data-cutover.yml and apply-git-data-root-key.yml run conclusions with their verdict annotations; the web-git-data-probe heartbeat for private-net reachability of 10.0.1.20"
  cadence: "per dispatch; heartbeat every 60 s"
  alert_target: "layer 6: workflow run log ::error:: annotation (check-runs annotations API); notify-ops-email (ops@jikigai.com) for any non-success root-key apply; the heartbeat provider's missed-ping alert"
  configured_in: ".github/workflows/git-data-cutover.yml, .github/workflows/apply-git-data-root-key.yml (notify-root-key-apply job), apps/web-platform/infra/web-git-data-probe.sh"
error_reporting:
  destination: "layer 6: workflow run log ::error:: annotations with fixed verdict words (never host or plan bytes); notify-ops-email for the root-key apply"
  fail_loud: true
failure_modes:
  - mode: "flag read error or flag already true"
    detection: "verdict=flag_read_failed | flag_already_true, exit 5, in the flag precheck step"
    alert_route: "layer 6: workflow run log ::error:: annotation"
  - mode: "store unmounted, cut over, not empty, or probe error"
    detection: "verdict=old_store_unmounted | already_cut_over | store_not_empty | probe_failed, exit 5"
    alert_route: "layer 6: workflow run log ::error:: annotation"
  - mode: "real mode requested by a stale invocation"
    detection: "verdict=real_cutover_unreconciled, exit 5"
    alert_route: "layer 6: workflow run log ::error:: annotation"
  - mode: "root read token not published, revoked, wrong scope, or key missing/malformed"
    detection: "verdict=git_data_root_token_absent | git_data_root_key_fetch_failed reason=<rc_nonzero|empty|not_openssh_key>"
    alert_route: "layer 6: workflow run log ::error:: annotation"
  - mode: "key rotated but host not yet replaced, or replace not yet run"
    detection: "role=git-data-auth verdict=failed reason=auth_refused"
    alert_route: "layer 6: workflow run log ::error:: annotation; runbook verdict map"
  - mode: "private NIC down after a replace"
    detection: "web-git-data-probe heartbeat missed; role=git-data-jump reason=timeout|no_route"
    alert_route: "heartbeat provider missed-ping alert; layer 6: workflow run log ::error:: annotation"
  - mode: "create plan without exactly the root key (swapped key, missing fingerprint file, deferred data source)"
    detection: "replace/birth gate verdict=git_data_root_key_not_in_create reason=<word>"
    alert_route: "layer 6: workflow run log ::error:: annotation (apply-web-platform-infra run)"
  - mode: "root-key apply red, cancelled, refused (non-additive, unreadable plan) or approval rejected/timed out"
    detection: "needs.apply.result != 'success' in notify-root-key-apply; verdict=git_data_root_key_non_additive | git_data_root_key_plan_unreadable"
    alert_route: "notify-ops-email (ops@jikigai.com); layer 6: workflow run log ::error:: annotation"
logs:
  where: "GitHub Actions run logs (fixed verdict words; host stderr capped and filtered; no plan JSON, no key bytes, no workspace ids)"
  retention: "GitHub Actions default (90 days)"
discoverability_test:
  command: "bash apps/web-platform/infra/git-data-root-key.test.sh"
  expected_output: "a final summary line reporting N passed, 0 failed, 0 skipped, including the notify-job and allowlist-refusal census rows"
```

## User-Brand Impact

**If this lands broken, the user experiences:**

- A replace that brings git-data back without the key. The cutover stays blocked.
- A create gate that refuses a needed recovery replace until the root-key apply and the fingerprint PR run
  again. Until then every Settings → Delete Account completes but logs an "Art. 17 erasure failed" event.
- During any replace, account deletions can take up to ssh's connect timeout longer.

With the cutover body removed, a broken PR cannot rsync, repoint or flip the store, and no web request depends on
git-data while the flag is off.

**If this leaks, the user's data is exposed via:**

- **(a) The root SSH key for the git-data host.** It is usable through the web-1 jump. **Before any repository
  exists** it already reaches the host's `prd_git_data` Doppler token. That token is a `soleur/prd` branch
  config, likely resolving all `prd` secrets including `SUPABASE_SERVICE_ROLE_KEY` (#6167), and therefore
  every user's conversations, messages and encrypted keys. Once repositories exist, it also reaches every
  workspace's full git history (source, commit authors' names and e-mails).
- **(b) The R2 state object and the Doppler project holding that key.** Both are reachable by any branch
  workflow through `DOPPLER_TOKEN` (F1). The same class of holder already reaches `prd` through
  `DOPPLER_TOKEN_TF`, so this adds a single-hop, never-expiring path rather than new reach.
- **(c) A key-swap persistence attempt by an `HCLOUD_TOKEN` holder.** The fingerprint anchor blocks it. It is
  why F2 starts from a fresh replace plus a LUKS key rotation.

**Brand-survival threshold:** single-user incident

CPO sign-off (with the #8009 C1 re-approval, CPO + CTO) is recorded in Domain Review;
`user-impact-reviewer` ran at plan time and runs again at review time.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** `bash apps/web-platform/infra/git-data-cutover-access.test.sh` and
  `bash apps/web-platform/infra/git-data-flag-precheck.test.sh` exit 0 with `0 failed` and `0 skipped` under
  `CI=true`. Their executed mutant counts reach `MUTANT_FLOOR`, they cover every Guard 1, 2, 3, 5, 6 (cutover
  half) and 7 row, and the per-row ledger records each behavioral row RED against `origin/main` bytes.
- [ ] **AC2** Canonical dry run (key present, plaintext device source, empty store): the script exits 0, and
  `diff` of the recorded remote timeline against the expected file is empty. The expected file holds, in order:
  web probe, jump probe, auth probe, `findmnt -no SOURCE /mnt/git-data`, the `*.git` count — nothing else
  (`git-data-cutover.sh › main`).
- [ ] **AC3** `git grep -nE 'soleur-(web|drain)\.service|bulk_rsync|repoint_luks_mount|old_volume_wipe' -- apps .github knowledge-base/engineering/operations`
  returns nothing, and every other Phase 0.6 hit is updated or states F2.
- [ ] **AC4** `bash tests/scripts/test-git-data-root-key-arm.sh`, `bash tests/scripts/test-git-data-host-replace-gate.sh`
  and `bash tests/scripts/test-git-data-host-birth-gate.sh` exit 0 with `0 failed`, including the fingerprint
  rows.
- [ ] **AC5** `bash apps/web-platform/infra/git-data-root-key.test.sh` exits 0 with its mutant floor reached
  (Guards 6 root half and 8, backend key, every `prevent_destroy`, the root census, no `terraform_remote_state`,
  the path exclusion). The `infra-validation.yml` validate step for the root passes on the PR.
- [ ] **AC6** `bash plugins/soleur/test/infra-validation-detect.test.sh`,
  `bash apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh` and
  `bash apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` exit 0.
- [ ] **AC7** `bun test plugins/soleur/test/terraform-target-parity.test.ts` reads **197 pass / 0 fail**, with no
  edit to that file.
- [ ] **AC8** For every path in the untouchable list, `git ls-files --error-unmatch <path>` succeeds and
  `git diff --quiet origin/main -- <path>` exits 0. The rung-2 gate prints
  `RELEASED … 5c50797be8392fe551a940ae04555c52a3f4409cf249ed11bb1280fec783d5b1`.
- [ ] **AC9** Parsed as YAML (with the `True`-key lookup), `git-data-cutover.yml`:
  - has exactly the input set `{confirm}`;
  - has workflow-level group `git-data-state` with `cancel-in-progress` `is False`;
  - has one job `cutover` with `environment: web-platform-infra-apply` and the D-6 step order;
  - binds `DOPPLER_TOKEN_PRD` only in the flag-precheck step and `DOPPLER_TOKEN_GIT_DATA_ROOT` only in the
    key-fetch step;
  - does not reference `DOPPLER_TOKEN_WRITE`.

  In both changed workflows, every `uses:` matches `@[0-9a-f]{40} # v`, and `actionlint` passes.
- [ ] **AC10** Every new suite is an `infra-validation.yml` step whose `run` equals `bash <path>`.
- [ ] **AC11** `python3 scripts/lint-encryption-posture.py --repo-sweep` → `0 unledgered, 0 failing checks`.
  The C4 tests and `c4-count-parity` pass. `python3 scripts/lint-infra-no-human-steps.py --changed --base
  origin/main` exits 0.
- [ ] **AC12** ADR-220 carries the dated amendment log listed under Architecture Decision. `git grep -n 'until #8189'`
  over `git-data-cutover.yml`, the bridge action, `git-data-cutover.sh`, the runbook, `model.c4` and ADR-220
  returns nothing.
- [ ] **AC13** `git diff origin/main -- knowledge-base/legal/article-30-register.md` adds exactly:
  - one (g) TOM;
  - the two cross-references;
  - the Superseded markers;
  - the qualified secrets bullet.

  It changes no `Status` cell and no PA-2 (g)(17) text.
- [ ] **AC14** F1, F2 and F4 exist in milestone Post-MVP / Later, the #8093 comment is posted, and the roadmap row
  names F1 and F2. The PR body uses `Ref #8189`, `Ref #6680` and `Ref #8093` (no `Closes`), states that merging
  fires only the web-platform push apply, and names no prod dispatch as done.
- [ ] **AC15** No `git-data-cutover.yml` or `apply-git-data-root-key.yml` dispatch was made in this PR.

### Post-merge (automated; explicit authorization where stated)

- [ ] **AC16** With explicit authorization and environment approval, `apply-git-data-root-key.yml` is dispatched
  from `main`. It passes the allowlist refusal, applies exactly the D-1 addresses, and prints the key's `SHA256:`
  fingerprint. The merge's `apply-web-platform-infra.yml` push run is green, and its Plan line is recorded in
  the PR thread.
- [ ] **AC17** A PR commits `apps/web-platform/infra/git-data-root-key.fingerprint` with the printed value and
  merges.
- [ ] **AC18** With explicit authorization, after AC17, `git_data_host_replace` is dispatched from `main`. The
  replace gate's `git_data_root_key_arm` passes, the run is green, and the `web-git-data-probe` heartbeat reads
  green through its provider API after the run finished.
- [ ] **AC19** With explicit authorization and environment approval, after AC18, a `git-data-cutover.yml` dispatch
  from `main` reads `role=git-data-auth verdict=ok`, all three store probes report clear, and it exits 0. Then
  ADR-220 D1b flips to `accepted` with the unauthenticated-evidence caveat, and #6680 and #8189 close, each
  with the run URL.

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering (CTO)

**Status:** reviewed (v1 assessment; v2 devex re-review: CONDITIONS MET)
**Assessment:** #8009 C1 re-approval **APPROVE WITH CONDITIONS**. All conditions are met:

- C1-a: there is no window, and closing a token is not host revocation.
- C1-b: root-login detection is tracked on #8093.
- Value capture is separated from display.
- The freeze/reload redesign moved to F2.
- Workflow-level `git-data-state`.
- An honest reference census.
- The create gate checks name, exactly-one and (deepened) fingerprint.
- The Doppler project-limit probe.

v2 advisories applied: the post-merge order is explicit (AC16–AC19 and the runbook verdict map), and F2's body
lists the guards it inherits.

### Legal (CLO + GDPR gate)

**Status:** reviewed
**Assessment:** GDPR gate: 0 regulated-data paths, no Critical finding, no Art. 30 trigger (one TOM on an
existing activity). Adopted:

- TOM wording limits (Phase 6, AC13).
- D3 corrected.
- Cross-references to (g)(5) and (g)(6).
- Superseded markers on "unborn".
- The qualified secrets bullet.
- The breach-triage trigger.
- No workspace ids are printed.
- The stray-copy residual dissolved.

Deepen addition: Delete Account erasure-failure events during a replace are expected and carry no data residual,
because no repository can exist (Insight 10). Advisory only — not legal advice.

### Product/UX Gate

**Tier:** none (no UI surface; no file in the lists matches the UI-surface globs)
**Decision:** reviewed (CPO plan-time sign-off for the single-user-incident threshold)
**Agents invoked:** cpo, spec-flow-analyzer
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

CPO v2: **SIGN-OFF GRANTED**. The v1 conditions are met or dissolved, and the v2 non-blocking conditions are
applied (milestone, roadmap row, and the replace's user-facing statement, now made precise in Downtime & Cutover).

Spec-flow v2: no P0. The P1s and P2s are applied.

### Plan-review panel (v2 → v3)

The panel: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow, CTO (devex), CPO.

**Applied:**
- Delete the unreachable cutover body and the real-mode inputs.
- Drop `environment:` on the replace job.
- New-root apply on `git-data-state`, with an additive refusal and `prevent_destroy`.
- Shared create-gate arm reading from `prior_state`.
- Unmounted-store refusal.
- Reuse the existing environment in a single gated job.
- Drop `web-1-swap` from the read-only job.
- Cut the access window, label parity, the display pipe and the preflight.
- Root validate step.
- Key file handling.
- Full-path untouchable AC.

**Not applied:**
- Dropping the Doppler hop (DC-7).
- Moving the PR #8187 session errors out of this PR's learning (the operator required them here).
- Scoping the Article 30 edit to the TOM only (CLO P1 items retained).

### Deepen panel (v3 → v4)

**Applied:**
- **security-sentinel:** fingerprint anchor; flag read in its own step; output and plan hygiene census; SHA
  pins; `ssh_config` hardening with a literal ProxyCommand target; `gd_capture` timeout and cap; shred wording;
  unauthenticated-evidence caveat; `secrets: inherit` census.
- **terraform-architect:** readonly lock via `providers lock`; allowlist refusal with a parse check; dispatch-only
  trigger; `terraform_wrapper: false`; notify job; `app_auth` copy; permissions and timeout; `prevent_destroy` on
  the Doppler environment.
- **observability:** notify job; key-fetch verdict; layer citations; discoverability on the root suite; drift by
  detector.
- **user-impact:** Delete Account during the replace; pre-repository `prd` exposure through the host token; F2's
  fresh replace plus LUKS rotation precondition; stuck-replace user impact.
- **test-design:** `mutate()` helper and mutant floors; `True`-key lookup; `is False`; census lower bounds;
  per-name Doppler shim; `diff` timeline; stub-based RED ledger.
- **network deep-dive:** private-NIC readiness read and L3/L7 verdict map.

**Verified clean:**
- verify-the-negative: 14 of 20 claims confirmed, none contradicted.
- self-audit: no leaked cut symbols, no contradictions.
- git-history: attributions confirmed, no corrections.
- Measured directly:
  - the plan-JSON data-source location;
  - the hcloud id type;
  - the Doppler CLI absent-secret semantics;
  - the flag gating of every git-data call except removal.

## Test Scenarios

1. Dry run with a plaintext device source and an empty store → exit 0; AC2 timeline.
2. Flag read scope error → the precheck step exits 5 with `flag_read_failed`; the bridge never runs.
3. Flag `true` → `flag_already_true`, exit 5.
4. `findmnt` empty or failing → exit 5 `old_store_unmounted`.
5. `findmnt` prints the mapper → exit 5 `already_cut_over`.
6. One `*.git` under `$OLD_REPOS` → exit 5 `store_not_empty`.
7. `$OLD_REPOS` missing on a mounted root → count 0, exit 0.
8. `findmnt` output with an injected second line, or a hung host → `gd_capture` rejects within 30 s, exit 5.
9. `ROLLBACK=1` or `CONFIRM_WIPE=1` or `DRY_RUN=0` → exit 5, empty timeline.
10. `DOPPLER_TOKEN_GIT_DATA_ROOT` empty → `git_data_root_token_absent` before the bridge; set but revoked →
    `git_data_root_key_fetch_failed reason=rc_nonzero`.
11. Replace or birth plan with a swapped-fingerprint key, a missing fingerprint file, a deferred data source,
    two labeled keys, or a server missing the root key → gate refuses with `reason=`.
12. Root-key apply plan with a `forget`, a delete, an empty JSON, or a read-token replace without the typed
    input → refused before `apply`; notify job emails.

## Risks and Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6.
- **The create gate now depends on the new root and the fingerprint file.** If the root-key apply is rejected,
  the Hetzner key object is lost, or the fingerprint PR has not merged, a recovery replace refuses. Account
  deletions then log erasure failures until it runs. This is accepted while the store is empty, and the verdict
  names the remedy.
- **A pending approval holds `git-data-state`.**
  - A replace dispatched meanwhile waits while holding the workflow-wide
    `terraform-apply-web-platform-host` group. That stalls web-platform applies and lets #8167 cancel pending
    push applies.
  - The root-key apply is dispatch-only, so no push can queue this hold.
  - The runbook says to answer or cancel before dispatching a replace.
- **The environment is a single-human acknowledgement, not two-party review.**
  `web-platform-infra-apply` has `can_admins_bypass: true` and `prevent_self_review: false` (stated in
  ADR-220 and in the TOM limits).
- **F2 rebuilds the deleted cutover body.** Git history and F2's body carry the design and every review
  finding.
- **Store-probe evidence is unauthenticated until #7226.** D1b's `accepted` flip is recorded with that caveat.
- **`detect-changes` treats the nested root as the parent.** Moving it to a top-level path would put it into
  the PR `plan` matrix; the detect test pins the nested behavior.

## Work-phase reconciliation (2026-09-15)

Measured during `/work`; each item corrects a plan statement above without rewriting it.

- **Insight 16 / Downtime & Cutover stage 2.** `web-git-data-probe.sh` does not run `git ls-remote`: it opens a
  TCP connection to `10.0.1.20:22` (`nc -z`) and pings `GIT_DATA_HEARTBEAT_URL` on success. A green heartbeat
  proves the private NIC and the sshd port, not the key. The runbook states this; the key is proven only by the
  AC19 dry run.
- **"web-2 retired (#6538)".** False: `var.web_hosts` still carries `web-2` (ADR-143, re-added 2026-07-24);
  #6538 retired a different host. The runbook keeps the DNS-rewire section `dns.tf` links to.
- **AC3, amended.** Its literal grep also matches (a) the two mutation rows that re-introduce a deleted function
  to prove the absence guards fire (`git-data-cutover-access.test.sh` G2, `git-data-luks.test.sh` A8) and
  (b) `workspaces-cutover.sh` / `workspaces-luks-staging.test.sh`, the separate `/workspaces` cutover, which
  pre-date this PR. AC3 is satisfied when every remaining hit is one of those.
- **Phase 0.6 consumer missed by the plan.** `git-data-luks.test.sh` asserted the deleted body (A8–A12); those
  rows now assert its absence and cite #8211.
- **Follow-up numbers.** F1 = #8209, F4 = #8210, F2 = #8211.
- **Fingerprint form (Phase 0.4).** Hetzner's `fingerprint` is MD5 colon-hex; both the arm and the apply's print
  step derive `SHA256:` from `public_key` with `ssh-keygen -l -E sha256`.
- **Fingerprint path.** Passed to both gates by `GIT_DATA_ROOT_KEY_FINGERPRINT_FILE`, not an argument, because
  the parity suite pins the gate call shapes.
- **Doppler CLI version.** `DopplerHQ/cli-action@5351693…` takes no version input; only the action is pinned.
