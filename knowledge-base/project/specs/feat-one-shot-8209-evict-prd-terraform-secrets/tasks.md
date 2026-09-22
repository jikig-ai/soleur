# Tasks: evict the privileged Terraform credentials from prd_terraform (#8209)

Plan: `knowledge-base/project/plans/2026-09-22-feat-evict-privileged-terraform-credentials-plan.md`

Constraints:

- The pipeline never merges.
- No irreversible production action is performed. The Operator Sequence is prepared, never
  executed.
- No edits to #8211-owned files: `git-data-cutover.yml`, `git-data-pin-redeploy.yml`, and the
  cutover, rollback and wipe scripts.
- Do not touch #8451.

## Phase 0: Preconditions

- [ ] 0.1 Re-run the ADR-ordinal probe across every `origin/*` ref (plan chose ADR-239 because
  ADR-238 is claimed on `feat-8322-affected-test-gate`).
- [ ] 0.2 Re-verify these CLI forms with `--help`:
  - `doppler configs tokens create … --plain`;
  - `doppler secrets set` (stdin);
  - `doppler secrets download --no-file --format json`;
  - `gh secret set --env`;
  - `gh variable set`.
- [ ] 0.3 Record the ADR-231 byte baseline: `wc -c` of `apply-web-platform-infra.yml`
  (482,443 at plan time).

## Phase 1: Guard first (census plus consumer inventory)

- [ ] 1.1 Write `tests/scripts/test-infra-privileged-tier-census.sh`. It carries the Guard 1 and
  Guard 2 mutation matrices and harness rows, and holds its constants in the script. Register it
  in `scripts/test-all.sh`.
- [ ] 1.2 Run the census against the unmodified tree. It must be RED, and that output is the
  inventory. Classify every job: workflow::job, triggers, current environment, credentials, read
  or write, tier after. Include every writer of `soleur-terraform-state` (the sentry apply;
  verify `cla-evidence` and `telegram-bridge`).
- [ ] 1.3 Write the loader test `.github/actions/infra-credentials/infra-credentials.test.sh`: the
  six rows plus the `--preserve-env` sentinel row, all RED before implementation.

## Phase 2: Terraform

- [ ] 2.1 GitHub provider auth mode (`dynamic "app_auth"` plus `token`) in
  `apps/web-platform/infra/main.tf`, `infra/github/main.tf` and `git-data-root-key/main.tf`. Add
  the new variables with `default = ""`. Comment the installation id `122213433`.
- [ ] 2.2 Re-run probe M8 in a scratch copy for the legacy, token and infra modes (TF 1.10.5).
- [ ] 2.3 `infra-privileged-environment.tf`:
  - the `infra-privileged` environment and its `main` policy;
  - `doppler_project` and `doppler_environment`;
  - `cloudflare_r2_bucket.terraform_state_privileged`.

  No secrets and no tokens in this root.
- [ ] 2.4 Add a `workspaces_luks_cutover` `main` deployment policy.
- [ ] 2.5 Add `removed { from = … lifecycle { destroy = false } }` for:
  - the `doppler_secret.github_app_*` mirrors;
  - `github_actions_secret.doppler_token_write`;
  - `doppler_service_token.write`;
  - `github_actions_secret.doppler_token_git_data_root`;
  - `doppler_service_token.git_data_root_read`.
- [ ] 2.6 git-data-root-key: partial backend for the bucket, the legacy-bucket refusal once
  `GIT_DATA_ROOT_STATE_MIGRATED=1`, and updates to `git-data-root-key.test.sh`.
- [ ] 2.7 `apply-git-data-root-key.yml`: the one-shot `8209_custody_forget` arm plus the executed
  fixture rows (Guard 3).
- [ ] 2.8 Web-platform destroy guard: forget fixture rows for the four addresses.

## Phase 3: Loader

- [ ] 3.1 `.github/actions/infra-credentials/action.yml`. It installs the Doppler CLI, loads the
  whole privileged project, masks every line, exports `TF_VAR_*` plus the plain names, falls back
  to legacy, runs the mode check, and treats the git-data state key pair as all-or-none.
- [ ] 3.2 The loader test turns GREEN.

## Phase 4: Workflows (byte-budgeted; prototype one job first)

- [ ] 4.1 Tier-B jobs:
  - declare `environment: infra-privileged` where no environment exists;
  - swap the Doppler install step for the loader;
  - add `--preserve-env` to every `doppler run`;
  - change `HCLOUD_TOKEN` reads to `${HCLOUD_TOKEN:-}`;
  - change the extract steps to `${TF_STATE_AWS_ACCESS_KEY_ID:-…}`.
- [ ] 4.2 Make the `apply-sentry-infra.yml` apply job Tier B.
- [ ] 4.3 `infra-validation.yml` plan job: `-refresh=false`, the placeholders, `github.token`, the
  read-only Hetzner token with fallback, and `--preserve-env` for the listed variables.
- [ ] 4.4 `board-status-sync.yml`: the `soleur-board` App names with a legacy fallback that
  refuses the sentinel. Apply the same refusal to `mint-soleur-ai-app-token` and its bump
  consumer (Tier B).
- [ ] 4.5 `workspaces-luks-cutover.yml::cutover`: `HCLOUD_TOKEN_READONLY` with fallback.
- [ ] 4.6 Extend the `-target=` lists and sweep every suite that asserts on them
  (`git grep -ln -- '-target='`).
- [ ] 4.7 Check the byte gate: `apply-web-platform-infra.yml` must be ≤ 488,000 B, and
  `workflow-file-size.test.ts` must be green.
- [ ] 4.8 Census and loader suites green, plus `terraform validate`/`fmt` on every touched root.

## Phase 5: ADR, C4, runbook, legal, follow-ups

- [ ] 5.1 Write ADR-239 via `soleur:architecture`, and add the ADR-220 amendment entry (dated
  2026-09-22, #8209).
- [ ] 5.2 C4: read all three `.c4` files and amend the edges at model.c4:556, :610, :655 and the
  tfstate edge. Run the c4 syntax, render and count-parity tests.
- [ ] 5.3 Runbook `infra-credential-tiers-8209.md`: the consumer inventory, the Operator Sequence,
  the state-migration and rotation sections, and the local invocation (inner `--preserve-env`).
  Update the 7 runbooks that cite the old local invocation.
- [ ] 5.4 Write the manifests `github-infra-app-manifest.json` and `github-board-app-manifest.json`.
- [ ] 5.5 Legal:
  - the prior-exposure assessment in `knowledge-base/legal/audits/`, with the read-only
    `gh api` evidence limb, indexed in `breach-register.md`;
  - Article 30 PA-12 §(g) items (1)-(3);
  - the secrets bullet;
  - two `compliance-posture.md` rows.
- [ ] 5.6 File the R1 issue (p1-high, type/security, blocks #8211) and the R6 issue. Add a note
  on #6167. Do not touch #8451.
- [ ] 5.7 Generate the operator bootstrap via `soleur:operator-bootstrap` (ADR-228). The runbook
  stays canonical.

## Phase 6: Ship prep (pipeline stops at open PR plus green checks)

- [ ] 6.1 PR body:
  - first line: "merging applies the environment, project and bucket creation to production";
  - `Ref #8209`;
  - a link to the Operator Sequence and the order constraints;
  - D2 `proposed` until R1 closes;
  - decision-challenges DC-2, DC-3 and DC-4.
- [ ] 6.2 Rebase onto `origin/main`. Resolve ADR-220 and `model.c4` conflicts additively.
  Re-verify the ADR ordinal.
