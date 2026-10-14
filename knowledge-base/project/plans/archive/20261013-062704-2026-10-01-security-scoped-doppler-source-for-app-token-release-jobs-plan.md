---
title: "security(infra): give the two App-token release jobs a Doppler source holding only the soleur-infra App values"
date: 2026-10-01
slug: scoped-doppler-source-for-app-token-release-jobs
branch: feat-one-shot-9321-scoped-app-token-doppler
issue: 9321
type: security
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
scope: "PR-1 of 2 (dormant IaC + operator bootstrap + census + ADR/runbook). PR-2 (the workflow/composite/test switch) is planned here and is NOT part of this PR."
closes: "none in PR-1 (PR-1 uses 'Ref #9321'); PR-2 carries 'Closes #9321'"
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# security(infra): scoped Doppler source for the two App-token release jobs

## Overview

Two unattended release jobs, `build-inngest-bootstrap-image.yml` job `bump-cloud-init-pin` and
`mint-inngest-bootstrap-tag.yml` job `mint`, mint a `soleur-infra` GitHub App installation token
through the composite `.github/actions/mint-infra-app-token`. The composite needs exactly two Doppler
values (`GITHUB_INFRA_APP_ID`, `GITHUB_INFRA_APP_PRIVATE_KEY`) but is handed
`DOPPLER_TOKEN_INFRA_PRIVILEGED`, a read token for the WHOLE `soleur-infra-privileged/prd` project.

**This plan splits the work into two PRs, because a one-PR landing cannot be made safe** (the new
credential can be minted only after the Terraform-declared container exists, and the release jobs run
on `main` the moment the switch merges):

| PR | Contents | Production effect on merge |
|---|---|---|
| **PR-1 (this PR, branch `feat-one-shot-9321-scoped-app-token-doppler`)** | A dormant Terraform container `soleur-infra-app` (project plus `prd` environment), its two `-target` lines, the generated bootstrap script (the repo operator-bootstrap kind), census Guard 7, the ADR-241 decision text (D11), the runbook sequence | CI's push run creates two EMPTY Doppler containers, and (because the new file is under `apps/web-platform/`) the web-platform release workflow also runs, as for any change there. No workflow, composite or test suite that the two release jobs depend on is touched. |
| **PR-2 (planned below, separate branch, opened only after the bootstrap script has run)** | The composite's fixed argv, the two release workflows' secret name, the two test suites, the remaining doc rows, census G7d | None until the first release run; a missing credential fails loud, before any tag, push or PR. `Closes #9321`. |

**Merging is the operator's decision; this pipeline merges nothing and writes nothing to production.**

## Enhancement Summary

**Deepened on:** 2026-10-01. **Agents/passes used:** repo-research-analyst (claim verification against the repo), best-practices-researcher (GitHub documentation), terraform-architect (IaC routing), code-simplicity-reviewer and architecture-strategist (plan review), learnings-researcher, functional-discovery; plus the mechanical halts (user-brand impact, observability, PAT-shaped variable, encryption posture, guard contract) all passing.

### Key improvements folded in
1. **Merge effects corrected.** Merging PR-1 also starts `web-platform-release.yml` and `infra-validation.yml` (path `apps/web-platform/**`), not only the Terraform apply; the plan now enumerates every push-triggered workflow matching the file set and says the apply kill-switch does not suppress the release.
2. **Census scope trimmed** (simplicity review): the target-list check is already enforced by `terraform-target-parity.test.ts`; Guard 7 shrank to G7c and G7d plus a project-literal-evasion row; C4 and the amendment marker moved to PR-2.
3. **Bootstrap script hardened** (architecture review): the token slug is recorded before the store step, "refused" means a recognised access-denied answer, `READY` means stored-and-scoped (environment secrets are write-only), the organisation-level secret list is checked, and `--rotate-token` handles non-unique token names.
4. **Boundary claim made honest:** the by-reference narrowing rests on GitHub's documentation (cited below) and does not cover a runner-root attacker; the App's own `administration:write`/`secrets:write` grant is unchanged.
5. **Rotation order** makes the second App-key copy a zero-downtime sequence (GitHub Apps accept several keys).

### New considerations discovered
- The first job that references `secrets.DOPPLER_TOKEN_INFRA_APP` becomes part of the census's Tier-B population (G1b, G1c, G1d, G1f, G1g, G1h all key on it). Both release jobs already declare `infra-privileged`, so PR-2 satisfies them; the PR-2 author must run the whole census, not only Guard 7.
- Precedence: an environment secret beats a repository secret of the same name for a job in that environment, so a stray repository-level copy would be shadowed in the release jobs but still be reachable from any branch workflow. The preflight check on the repository and organisation lists stays.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue body / task brief) | Reality (measured 2026-10-01) | Plan response |
|---|---|---|
| "Since the runtime-key PR merged, `soleur-infra-privileged/prd` also holds `GITHUB_APP_RUNTIME_DOPPLER_TOKEN`" | A read-only names listing of `soleur-infra-privileged/prd` shows 10 names (`CF_API_TOKEN_R2`, `DOPPLER_TOKEN_TF`, the three `GITHUB_INFRA_APP_*`, `GIT_DATA_ROOT_STATE_AWS_*` x2, `HCLOUD_TOKEN`, `TF_STATE_AWS_*` x2) plus the `DOPPLER_*` meta names. **`GITHUB_APP_RUNTIME_DOPPLER_TOKEN` is not there yet**: the runtime-key runbook's R-step 2 has not run. | The justification is stronger than the issue states: today the two jobs can already read `DOPPLER_TOKEN_TF` (a workplace personal token that can read and write every project and mint service tokens), `HCLOUD_TOKEN` read/write, `CF_API_TOKEN_R2` and both R2 state-key pairs. The runtime-key read token is one more name that arrives later. State both in the ADR text. |
| "A Doppler container (config or project)" | A branch config inherits its root's values, so a token scoped to it still reads them (ADR-241 D3; learning `security-issues/2026-07-07-doppler-branch-config-does-not-isolate-secrets.md`) | **A project.** See Design Decision 1. |
| "~11 secret-name lines, ~7 argv lines, ~22 test lines" | Confirmed by grep (build workflow 5 lines, mint workflow 7, composite 4 reads/messages plus prose, test-mint ~10, test-bump ~8) | Sizes the PR-2 edit list below. |
| "stored as a separate `infra-privileged` environment secret" | Only the two release jobs need it, both declare `environment: infra-privileged`. The other three Tier-B environments do not need it. | New environment secret `DOPPLER_TOKEN_INFRA_APP` on `infra-privileged` only. |
| Task brief: "Closes #9321" | The narrowing is not real until PR-2 merges | PR-1 body says `Ref #9321`; PR-2 says `Closes #9321`. Recorded as a decision for the lead. |
| Precedent | `apps/web-platform/infra/github-app-runtime-project.tf` (Terraform project plus environment, no secret, no token) and the runtime-key runbook's R2 row (operator-minted read token stored for Tier B) are the exact shape wanted | Mirror both. |

## Research Insights

**Premise Validation.** Checked: #9321 is open with no closing PR; the Tier-B re-tier PR is merged (this
worktree's merge-base contains it); the soleur-ai runtime-key PR is merged and its issue closed; #9320
(runbook step O4c: widen the live `soleur-infra` App and prove the re-tiered release jobs) is OPEN and
relevant (see Landing Order). Cited paths all exist on `origin/main`:
`.github/actions/mint-infra-app-token/action.yml`, both workflows, both test suites,
`apps/web-platform/infra/infra-privileged-environment.tf`, `github-app-runtime-project.tf`. Mechanism vs
the ADR corpus: ADR-241 D3 (carrier is a project, never a branch config), D10 (isolated project,
operator-minted read token stored only in Tier B) and ADR-232's 2026-09-30 amendment (which records this
exact narrowing as a deferral) already decide the shape. Nothing here sits in a rejected-alternatives
table; the issue's "config" option is excluded by D3.

**Property List.**
- P1. The two release jobs hold a credential that reads only `GITHUB_INFRA_APP_ID` and `GITHUB_INFRA_APP_PRIVATE_KEY`, and cannot read any other Tier-B name.
- P2. The container and its token never put a secret or a token into Terraform state (state is readable by the Tier-A backend keys).
- P3. Between the merge of the Terraform part and the minting of the token, no release job breaks.
- P4. The part that cannot be IaC is one runnable, re-runnable script, not a checklist.
- P5. A stale copy after an App key rotation is prevented by rotation order and, if it happens anyway, fails closed with a stage-named error (not silently). It can surface only at the next release run, which may be days later; that residual is accepted and stated.

**Cut List.**
- Separate GitHub environment for the release jobs -> P1 is met by reference narrowing in main's own YAML; a fifth Tier-B environment adds policy/census churn and no property.
- A `doppler_service_token` / `github_actions_environment_secret` resource in Terraform -> would put the token in Tier-A-readable state (violates P2; ADR-241 D3). The older learning that recommends `doppler_service_token` predates the tiering and does not apply to Tier B.
- A fallback "new token else old token" in the composite -> keeps the broad token reachable and cannot serve both projects with fixed argv (see Alternatives).
- A cross-project Doppler reference (Tier-B value referencing the new project) to avoid a second copy -> its resolution behaviour cannot be probed without a Doppler write, and the census already forbids cross-project references into isolated projects. The two copies are reconciled by the bootstrap script's equality stage instead.

**Institutional learnings applied:**
- Doppler branch config does not isolate secrets -> project, not config.
- Terraform state is Tier-A readable -> no `doppler_secret`/`doppler_service_token` in any root (census G6c is the model for G7c).
- Census checks must verify provenance (binding), not just names, and must not use a closed file list -> G7d keys on the composite's `--project`/`--config` pair on every read, and Guard 7 enumerates every `.tf` under every root.
- Fixed `--project/--config` argv in the composite (never an input or `DOPPLER_PROJECT`) -> kept in PR-2.
- A Doppler-fetched secret is not auto-masked -> the composite already masks the id and each PEM line; the bootstrap script never echoes a value and uses stdin pipes.
- A red gate arms what it was silently gating -> `CENSUS_ROWS` is a counted floor; bump it with the new rows.
- Tests pinned to exact step names -> PR-2 renames `Verify DOPPLER_TOKEN_INFRA_PRIVILEGED present`, which both suites pin by name.

**Verified facts (deepen pass, 2026-10-01; sources are the vendors' own documentation or the repo):**
- GitHub: "GitHub Actions can only read a secret if you explicitly include the secret in a workflow" (docs.github.com/en/actions/concepts/security/secrets). GitHub's compromised-runner page adds that unreferenced secrets are scrubbed from runner memory, while "the `GITHUB_TOKEN` and any referenced secrets can be harvested by a determined attacker" (docs.github.com/en/actions/concepts/security/compromised-runners). That is the exact scope of the by-reference narrowing, and D11 cites both pages.
- GitHub: if a secret name exists at several levels, "the environment-level secret takes precedence" (docs.github.com/en/actions/reference/security/secrets).
- GitHub REST: `GET /repos/{owner}/{repo}/environments/{environment_name}/secrets` returns `name`, `created_at`, `updated_at` and no value; `GET /orgs/{org}/actions/secrets` needs an organisation-admin scope, so an unreadable answer from the script is INCONCLUSIVE.
- `gh secret set <NAME> --env <environment> -R <owner/repo>` exists and reads the value from stdin when no body flag is given (cli.github.com/manual/gh_secret_set).
- Repo: `.github/actions/infra-credentials/action.yml` downloads the whole `soleur-infra-privileged/prd` project and exports every key, including as `TF_VAR_<name>`; `apps/web-platform/infra/main.tf` and `infra/github/main.tf` read `var.github_infra_app_*`. The two values cannot move out of that project.
- Repo: `plugins/soleur/test/terraform-target-parity.test.ts` requires every `resource` in `apps/web-platform/infra/*.tf` to appear in an `-target=` line of the push apply (or an exclusion list); a resource in no list fails it. `scripts/lint-doppler-description-length.py` caps `description` at 255 BYTES. `.gitignore` already covers `.env`, `.env.tmp.*` and `bootstrap-runs.jsonl` at any depth.
- Repo: no project inventory, token-drift scan or allowlist enumerates Doppler projects, so a sibling project invalidates nothing. The literal `soleur-infra-privileged` appears in the composite, the two release suites (argv pins, PR-2) and unrelated Tier-B files only.
- ADR ordinal: no new ADR is created (D11 amends ADR-241); latest ordinals on `origin/main` are ADR-260 and ADR-261, for reference only.

**Other facts recorded for the implementer:**
- `apply-web-platform-infra.yml` is 483,707 bytes against the 490,000-byte test ceiling; two `-target` lines (~130 bytes) fit.
- One open code-review scope-out touches `build-inngest-bootstrap-image.yml` (the probe-gate window); it is a different concern (see Open Code-Review Overlap).
- `soleur_op_gh_secret_set` in the operator library writes a REPOSITORY secret. A repository secret is branch-reachable, which is exactly what this work removes. The bootstrap script must call `gh secret set ... --env infra-privileged` directly.

## Landing Order and Auto-Apply Evidence

**Does merging this PR auto-apply anything? Yes, two things, and the second is easy to miss.**
(1) The Terraform apply creates two empty Doppler containers. (2) Any change under `apps/web-platform/**`
also starts `web-platform-release.yml` (push to `main`, `paths: apps/web-platform/**`; its
`path_filter` has no infra exclusion), which cuts a web-platform release and deploys it once CI is green,
and `infra-validation.yml` (`apps/*/infra/**`). That is the same as every other infra-only change to
this directory, and it is a production deploy, so it is part of the merge decision. The kill-switch
line below suppresses ONLY the Terraform apply, not the release. PR-2 touches only `.github/**`,
`tests/**` and `knowledge-base/**`, none of which match the release workflow's paths.
Evidence for (1), read from `.github/workflows/apply-web-platform-infra.yml`:

- Trigger: `on.push.branches: [main]` with `paths:` including `apps/web-platform/infra/**` (minus the
  rehearsal and git-data-root-key subtrees) and the workflow file itself. The new
  `apps/web-platform/infra/infra-app-project.tf` and the edit to the workflow file both match.
- Job `apply` (`environment: infra-privileged`, `needs: preflight`) runs on `push`, and its
  `terraform plan` is restricted by an explicit `-target=` allow-list. The plan therefore contains
  exactly what PR-1 adds to that list: `doppler_project.infra_app` and
  `doppler_environment.infra_app_prd` (no destroys and exactly these two creates; do not assert exact change counts, drift on another targeted resource would change them). A `.tf` resource that is
  not in the list is pruned and applies nothing.
- Opt-out: the `preflight` job reads the head commit message and skips the apply when a line is
  exactly `[skip-web-platform-apply]`. PR-1 does not put that line in its PR body (a default squash
  message would carry it and silently suppress the apply). To merge without applying, add the line to
  the squash message.
- Push-triggered workflows whose path filters match PR-1's file set, enumerated by reading every workflow's `on.push.paths` (re-run this enumeration when the file list changes): `apply-web-platform-infra.yml`, `infra-validation.yml`, `web-platform-release.yml`.
- Not triggered by PR-1: `mint-inngest-bootstrap-tag.yml` (push `paths:` are
  `apps/web-platform/infra/inngest*`, `vector.*`, `cat-inngest-*`, the two inngest workflows and its
  script; the new file matches none); `build-inngest-bootstrap-image.yml` (`workflow_dispatch` only);
  `apply-github-infra.yml` (`infra/github/**`); `apply-sentry-infra.yml` (its own subtree);
  `scheduled-terraform-drift.yml` (`workflow_dispatch`, fired by Inngest).
- Safety of the create: the Doppler project name `soleur-infra-app` is free (a read-only project
  lookup returned "Could not find requested project" on 2026-10-01). Nothing reads the new
  containers, so a failed or skipped apply affects no consumer; a failure surfaces through the
  existing `notify-apply-failure` job.

**The order, with what each step does to the release jobs:**

| # | Step | Performed by | Release jobs at this point |
|---|---|---|---|
| 1 | Merge PR-1 | the operator's decision | unchanged, still on the broad token |
| 2 | Push apply creates the two empty containers | CI, automatic on step 1 | unchanged |
| 3 | Run `bash knowledge-base/project/specs/feat-one-shot-9321-scoped-app-token-doppler/bootstrap.sh` (copy two values, prove them, mint the read token, prove its reach, store it as an `infra-privileged` environment secret, final read-only verification) | the generated bootstrap script; every write behind its own go-ahead | unchanged |
| 4 | Open and merge PR-2 only after step 3 printed `SOLEUR_BOOTSTRAP_READY_FOR_PR2` | the operator's decision | switched to the narrow token |
| 5 | Prove the switch with a `mirror_only` dispatch (the command in the runbook's O4c row; #9320 itself is closed) run after PR-2 | the operator | on the narrow token |

If PR-2 were merged early (before step 3), the failure is safe by construction: the
`Verify DOPPLER_TOKEN_INFRA_APP present` step fails before the App-token mint, and both jobs mint
before the tag and before the push, so nothing is tagged, pushed or opened, and the existing Slack
failure post fires. Re-running the script and then the job recovers it.

**Relation to #9320.** #9320 (widen the live App's permissions, prove the release jobs on Tier B)
is independent of this work and still open. Until it is done the two jobs already fail at the
mint step's exact-grant check, loudly and before any write. This plan neither depends on it nor does
it; it only schedules the proof run after PR-2 so one dispatch covers both.

## Design Decisions

**1. A new Doppler PROJECT, `soleur-infra-app` (environment and config `prd`), not a config.** A branch
config resolves its root's secrets; ADR-241 D3 and D10 already chose projects for that reason. A
token scoped to the root config `prd` of a separate project can read nothing else. (An extra
environment inside the Tier-B project would also isolate by config, but a project has precedent in
this repo and in the census's project-literal regexes and gives project-level role separation; a
per-project environment limit on the Doppler plan could not be checked without a write.)

**2. Names.** Project `soleur-infra-app`; Terraform addresses `doppler_project.infra_app` and
`doppler_environment.infra_app_prd`; the read token is named `release-app-mint` in Doppler; the
GitHub **environment** secret on `infra-privileged` is `DOPPLER_TOKEN_INFRA_APP`. The census
`ENV_SECRETS` list gains the name so any job that references it must declare a main-only Tier-B
environment.

**3. The container holds a COPY of the two values.** The Tier-B project's `GITHUB_INFRA_APP_*` names
are also consumed whole-project by the Terraform roots through `.github/actions/infra-credentials`
(`TF_VAR_github_infra_app_*`), so they cannot be moved. The bootstrap script copies both values by
stdin and proves equality by hash (printing only `equal`). The cost is two copies of the App private
key. The mitigation is P5. GitHub Apps accept several private keys at once, so the runbook's rotation
order is: add the new App key, update BOTH copies (re-run the script's copy stage), prove both with
`GET /app`, and only then delete the old key at GitHub; that makes the stale-copy case a zero-downtime
sequence. If a copy is stale anyway, the composite's `openssl rsa -check` or the installation-token
exchange fails with a stage-named error and a Slack post. A scheduled equality check of the two copies
was considered and not adopted: it needs a job holding both tokens, adds a workflow for a rare
event, and the on-demand script stage plus the rotation order cover it.

**4. Terraform creates containers only.** No `doppler_secret`, no `doppler_service_token`, no data
source, no variable, no output on the new project, in any root (the state object is readable by the
Tier-A backend keys, so any value there is branch-reachable). The token is minted by the script. This
satisfies `hr-tf-variable-no-operator-mint-default` trivially (no variable exists) and
`hr-github-app-auth-not-pat` (the composite's App-JWT recipe is untouched, and the script's own
proof uses an App JWT, never a PAT).

**5. The new token is read-only on `soleur-infra-app/prd`, stored only as an `infra-privileged`
environment secret.** Never a repository secret (reachable from any branch of this public
repository), and not on the other three Tier-B environments.

**6. Honest boundary statement (goes in ADR D11).** The narrowing is least-privilege BY REFERENCE: the
two release jobs' YAML no longer names the broad secret, so a compromised step inside those jobs
should not be able to read it (GitHub passes a secret to a step only when that step's `env`/`with`
names it). D11 must cite GitHub's documentation for that sentence rather than assert it, must not
claim protection against a runner-root step reading process memory, and must say that the soleur-infra
App itself still holds `administration:write` and `secrets:write` (committed manifest): the narrowing
removes reach to the other Tier-B names (`DOPPLER_TOKEN_TF`, `HCLOUD_TOKEN`, ...), not the App's own grant. It is not a boundary against
a change merged to `main`, which can name any secret of the environment; the `main`-only branch
policy remains the boundary and stays nominal while the runtime-key residual stays open.

## Implementation Phases (PR-1, this PR)

### Phase 1 - Terraform container (dormant)

1. Create `apps/web-platform/infra/infra-app-project.tf` modelled on
   `github-app-runtime-project.tf`: `doppler_project.infra_app` (`name = "soleur-infra-app"`,
   description under 255 characters stating purpose and "Operator-supplied; never in tfstate",
   `lifecycle { prevent_destroy = true }`) and `doppler_environment.infra_app_prd` (`slug = "prd"`,
   `name = "Production"`, `prevent_destroy`). The header comment states why no secret/token resource
   may ever be added here (same reasoning as the two sibling files) and names the census guard.
2. Edit `.github/workflows/apply-web-platform-infra.yml`: add
   `-target=doppler_project.infra_app \` and `-target=doppler_environment.infra_app_prd \` next to the
   existing `doppler_project.github_app_runtime` lines (inside the push `apply` job's plan list;
   verify with grep that there is exactly one list to extend). Confirm
   `plugins/soleur/test/workflow-file-size.test.ts` stays green.
   Put no `#` comment lines inside the backslash-continued list (shellcheck SC2215), and have the
   environment reference `doppler_project.infra_app.name`, never a string literal.
3. Run `python3 scripts/lint-doppler-description-length.py` (or its test) against the new file.
4. Run `bun test plugins/soleur/test/terraform-target-parity.test.ts`: the Terraform IaC reviewer
   found no exempt-list entry is needed (the sibling Tier-B projects are `-target`ed and in no
   exempt list), but this test is the check. The destroy-guard filter is type-scoped to Hetzner
   server and volume resources and needs no edit.

### Phase 2 - Operator bootstrap script (generated via `soleur:operator-bootstrap`)

Generate `knowledge-base/project/specs/feat-one-shot-9321-scoped-app-token-doppler/bootstrap.sh` from
`plugins/soleur/skills/operator-bootstrap/template.sh` (bake the library path as the skill's section 3
prescribes). Stages, each opening with an "already satisfied?" check and closing with a verification;
every write sits behind the library's per-command go-ahead (class 2, no skip variable); no value is
ever printed:

1. **Preflight (read-only).** Binaries; Doppler auth; the project `soleur-infra-app` and its `prd`
   config exist (a missing project is a hard failure naming "PR-1's push apply has not run or failed",
   never a prompt); `infra-privileged`'s deployment-branch policy is exactly `["main"]`; the
   repository-level AND organisation-level secret lists do NOT contain `DOPPLER_TOKEN_INFRA_APP` (an unreadable org list is INCONCLUSIVE, not a pass; a repository- or org-level copy
   would be branch-reachable: stop and name the delete).
2. **Copy the two values (write).** Skip when source and destination hashes are equal. Otherwise read
   each name from `soleur-infra-privileged/prd` with `--plain` and pipe it on stdin into the Doppler
   set command for `soleur-infra-app/prd` with `--silent` and output to `/dev/null`; then compare
   hashes in-process and print only `equal`.
3. **Prove the copy is the live App (read-only).** Build an App JWT from the NEW project's values
   (PEM on tmpfs at mode 0600, removed by trap) and call `GET /app`: expect `slug == "soleur-infra"`
   and `id` equal to `GITHUB_INFRA_APP_ID`. A 401 means a stale or wrong copy: stop.
4. **Mint, prove the reach, store (write).** `*_ATTEMPTED` marker first (template control). Mint a
   read token named `release-app-mint` on `soleur-infra-app` config `prd` into a shell variable only;
   with it supplied through the environment (never `--token`, never argv): reading both names
   succeeds; the names listing returns exactly the two names plus the `DOPPLER_*` meta names; reading
   `soleur-infra-privileged/prd` and `soleur/prd` is REFUSED, where "refused" means a recognised
   access-denied answer (a transport error or an unknown shape is INCONCLUSIVE, never a pass). The
   token's slug (not a secret) is written to the ledger BEFORE the store step, so a crash between mint
   and store leaves a revocable record, not an orphan. Then pipe the token on stdin into
   `gh secret set DOPPLER_TOKEN_INFRA_APP --env infra-privileged -R jikig-ai/soleur` (never the
   library's repository-level helper), read the environment's secret names back
   (`gh api repos/jikig-ai/soleur/environments/infra-privileged/secrets`; environment secrets are
   write-only, so the listing proves the name and its `updated_at`, not the value), and on any failure revoke
   the just-minted token by slug. A token that exists with no environment secret (the value is not
   retrievable) is revoked and re-minted; one environment secret with no token is overwritten.
5. **Final read-only verification and handoff.** The environment secret is listed; the repository
   level is not; the project's token listing shows exactly `release-app-mint`; the project has no
   copies are equal (the Doppler CLI has no read for project members, webhooks or syncs, so the script does not check them; see the review addendum). Print
   `SOLEUR_BOOTSTRAP_READY_FOR_PR2` and the PR-2 pointer, worded as "stored and scoped", not "works":
   the first proof is the first release run after PR-2, and on re-run an existing secret plus an
   existing token is compared by the ledger's recorded slug and the secret's `updated_at`. An unreadable Doppler answer is
   INCONCLUSIVE, never a pass.
6. **`--rotate-token`** (a documented flag, not a default): Doppler token names are not unique, so
   record the current slug in the ledger first, mint a second token, record its slug, store it, then
   revoke the first slug after confirmation (new before old). A crash in between leaves two slugs in
   the ledger and the next run refuses to continue until one is revoked. Re-running without the flag after an App key rotation re-copies through stage 2.

Verification of the script itself follows the skill's section 4: two runs (all skip variables set with
stdin not a TTY: runs unattended to the first go-ahead and exits 64; no skip variables: exits 64
naming the first one before any read), and the ledger's `total_stages` matches. Neither run performs a
write.

### Phase 3 - Census Guard 7 (`tests/scripts/test-infra-privileged-tier-census.sh`)

Add `DOPPLER_TOKEN_INFRA_APP` to `ENV_SECRETS` (so the existing G1b/G1c rows already require a
Tier-B environment of any job that names it). That the two addresses are in the `-target` list is
already enforced by `plugins/soleur/test/terraform-target-parity.test.ts`, so no census row repeats it. Add a compact Guard 7, reusing the file's
`tf_root_files`, `RES_OPEN`, `block_bodies`, `cmd_sites` helpers. Rows (see Guard Contract):

- **G7c** the project is declared (`name = "soleur-infra-app"`, the `prd` environment) and the scanned `.tf` count is at least 1 (a zero-scan must not pass); and no root declares a `doppler_secret`, `doppler_service_token` or `doppler_service_account_token` resource, or a data `doppler_secret(s)`, that names the project literal or its addresses. (Reviewer note: this could instead widen G6c's constants; kept as its own row so G6c's `soleur-github-app` property stays unmuddied.)
- **G7d (PR-1 half)** nothing in CI mints a Doppler token on `soleur-infra-app` (same shape as G6d), and the bootstrap script stores the token only with `--env infra-privileged`.
- **G7d (PR-2 half, added there)** every `doppler secrets get` in the composite names only the two App values and carries `--project soleur-infra-app --config prd`; no `soleur-infra-privileged` literal remains in the composite or either release workflow.

Bump `CENSUS_ROWS` by the number of rows added and extend the suite's own dispatch self-tests (the
existing `wf_row` empty-tree fixtures) so an empty tree reds G7c.

### Phase 4 - ADR, runbook, C4 (deliverables of this plan, not follow-ups)

- ADR-241: new **D11** ("The inngest-release App values live in their own Doppler project,
  `soleur-infra-app`"), an Amendment-log entry, and a Statuses row (`adopting`; flips when PR-2 is
  merged and one real release run shows the `app-token` notice on the narrow source). D11 states the
  honest boundary (Design Decision 6), the measured reach of the broad token (names above), the
  two-copies cost, and the rejected alternatives. (The dated marker on the 2026-09-30
  amendment's "recorded deferral" sentence is a PR-2 edit.)
- Runbook `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`: a new
  section "Release-job App source (#9321)" holding the canonical order (the table above), the script
  pointer (the runbook links, it does not restate the script's stages), the verification reads, the
  rotation line (update BOTH copies; the token rotates new-before-old), and the rollback (a PR-2
  revert restores the broad token; the container and token can stay dormant). Group-4 table rows are
  edited in PR-2, when they become true.
- C4 and the dated marker on the 2026-09-30 amendment's "recorded deferral" sentence move to PR-2
  (reviewer finding, accepted): that wording stays true until the switch merges, and editing it in
  PR-1 would force a `model.likec4.json` regeneration (a conflict risk with a parallel session's
  likec4-pin work) and a second edit in PR-2. ADR-241 D11 itself is authored in PR-1, so the
  architecture record does not lag the decision.

### Phase 5 - PR hygiene

PR body: `Ref #9321` (not `Closes`), the merge-effects statement and evidence above (the Terraform apply AND the web-platform release/infra-validation runs that the `apps/web-platform/` path triggers), the order table, no
issue references other than #9321 and #9320. #9321 stays open and is the follow-through tracker for
steps 3 to 5.

## PR-2 plan (planned here, NOT part of this PR; separate branch off `main` after step 3)

Edit list (sized from the issue's measurements, re-verified):

- `.github/actions/mint-infra-app-token/action.yml`: the two `doppler secrets get` argv (`--project soleur-infra-app --config prd`), their two `::error::` strings, the `description`, the `doppler-token` input description and the empty-input error text (they name `DOPPLER_TOKEN_INFRA_PRIVILEGED` and `soleur-infra-privileged`).
- `.github/workflows/build-inngest-bootstrap-image.yml` (`bump-cloud-init-pin`): the comment, step name `Verify DOPPLER_TOKEN_INFRA_APP present`, its `env`, `::error::` text, and the composite's `with: doppler-token`. Do not touch the unrelated probe-gate code.
- `.github/workflows/mint-inngest-bootstrap-tag.yml` (`mint`): the same five spots plus the two header comments.
- `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh` and `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`: the exact-step pins (step name, `env`, `with`), the Tier-A mutation rows, the argv pin (`--project soleur-infra-app --config prd`) and the `s.replace` project mutation, keeping the composite's refusal of a wrong project.
- `tests/scripts/test-infra-privileged-tier-census.sh`: the G7d PR-2 half and its mutation rows.
- Docs: ADR-232 dated marker, ADR-241 D11 status and Statuses row, runbook Group-4 rows and the O4c row, `inngest-server.md`'s recovery row for `DOPPLER_TOKEN_INFRA_PRIVILEGED is not available`, the C4 edge.
- Gate before opening: the script's final stage printed `SOLEUR_BOOTSTRAP_READY_FOR_PR2`.
- Merging PR-2 edits both workflows, which fires the `mint` job's push trigger; its `Decide` step is credential-free and later steps run only when it says `would-mint`, so an early merge is safe, but the first real mint depends on the secret.

## Infrastructure (IaC)

### Terraform changes
- New `apps/web-platform/infra/infra-app-project.tf`: `doppler_project.infra_app`, `doppler_environment.infra_app_prd` (provider `DopplerHQ/doppler` already pinned in this root).
- `.github/workflows/apply-web-platform-infra.yml`: two `-target` lines.
- Sensitive variables: none. No `TF_VAR_*` is added. The read token is deliberately not a Terraform variable.

### Terraform IaC review (Phase 2.8, `soleur:engineering:infra:terraform-architect`)
Verdict: routing OK. The values, the token and the environment secret must stay out of Terraform:
the web-platform root's state is Tier-A readable, a service-token resource stores its key as an
unreadable computed value, and the Terraform GitHub App cannot write environment secrets (a 403
recorded in `inngest-arm-write-token.tf`). Findings folded in: census G6c covers only the runtime
project, so Guard 7 is what enforces the rule for `infra_app` (the header comment alone would be the
only barrier otherwise); ADR-241 D3 lists `GITHUB_INFRA_APP_PRIVATE_KEY` as a single-project value, so
D11 plus an Amendment-log line record the second copy; the script must run after the push apply (its
preflight fails with a named cause otherwise, and the runbook says so).

### Apply path
(a) create-only push apply on merge (the resources do not exist yet). No taint, no host contact, no downtime. The parts Terraform cannot hold without leaking into state (the two values, the read token, the GitHub environment secret) are performed by the generated bootstrap script, which is idempotent and re-runnable (`hr-multi-step-post-merge-bootstrap-script`; `hr-never-label-any-step-as-manual-without`: the script drives the Doppler CLI and `gh`, and the only interactive input is the per-command go-ahead).

### Distinctness / drift safeguards
Both resources carry `prevent_destroy`. The state object (`web-platform/terraform.tfstate`) is Tier-A readable, which is harmless here: it holds names and slugs only. Drift: `scheduled-terraform-drift` reports a missing project as a create diff. The dev/prd distinctness rule does not apply (Doppler infra projects have no dev twin).

### Vendor-tier reality check
Seven Doppler projects already exist (two created by the same pattern), so project creation is within the plan. No free-tier gate (`count`) is needed.

## Observability

```yaml
liveness_signal:
  what: "PR-1: the push run of apply-web-platform-infra.yml concludes success and its plan shows no destroys and exactly the two creates; thereafter scheduled-terraform-drift shows no diff for the two resources. PR-2: the per-run notice title=app-token (app=soleur-infra installation=166065653) in each release run, and the existing Slack failure post of both release workflows"
  cadence: "once per merge (apply); per release run (mint/bump); drift check twice daily via Inngest"
  alert_target: "notify-apply-failure job (existing Slack path) for the apply; the existing Slack step of build-inngest-bootstrap-image.yml and mint-inngest-bootstrap-tag.yml for the release jobs"
  configured_in: ".github/workflows/apply-web-platform-infra.yml; .github/workflows/mint-inngest-bootstrap-tag.yml; .github/workflows/build-inngest-bootstrap-image.yml"
error_reporting:
  destination: "GitHub Actions run annotations plus the existing Slack posts; no secret value is ever in an annotation (the composite masks the id and each PEM line, and prints only sanitised vendor message text)"
  fail_loud: "PR-2: a missing environment secret fails the 'Verify DOPPLER_TOKEN_INFRA_APP present' step before the mint; an unreadable value fails with '::error::mint-infra-app-token: ... not readable from Doppler soleur-infra-app/prd'; both jobs mint before the tag and before the push, so a credential failure publishes nothing"
failure_modes:
  - mode: "PR-1 apply fails or is skipped by the kill switch"
    detection: "workflow run conclusion plus the script's preflight (project exists), which stops with a named cause"
    alert_route: "notify-apply-failure (Slack)"
  - mode: "stale copy after an App key rotation"
    detection: "composite: openssl rsa -check or the installation-token exchange returns no token, stage-named error; the script's stage 3 (GET /app with the copy) is the pre-rotation check"
    alert_route: "release workflow Slack failure post"
  - mode: "read token revoked, rotated away or the environment secret deleted"
    detection: "'DOPPLER_TOKEN_INFRA_APP is not available' or 'not readable from Doppler soleur-infra-app/prd' before any publish"
    alert_route: "release workflow Slack failure post"
  - mode: "a repository-level secret of the same name appears (branch-reachable)"
    detection: "census G1b/G1c via ENV_SECRETS on every PR; the script's preflight and final stage list repository-level secret names"
    alert_route: "failing CI check on the PR"
logs:
  where: "GitHub Actions run logs (apply, mint, bump); the script's ledger bootstrap-runs.jsonl beside it on the operator's machine"
  retention: "Actions logs 90 days; the ledger until the follow-through closes and the script is deleted"
discoverability_test:
  command: "grep -cF -e target=doppler_project.infra_app -e target=doppler_environment.infra_app_prd .github/workflows/apply-web-platform-infra.yml"
  expected_output: "2"
```

(The declared command checks the committed wiring the apply depends on, locally and without SSH. The
live liveness evidence is the apply run's conclusion and, after PR-2, the `app-token` notice; both are
read with `gh run list`/`gh run view`, which is not an allowlisted preflight verb and so is not the
declared probe.)

## Encryption Posture

```yaml
at_rest:
  - store: "Doppler project soleur-infra-app / config prd (doppler_project.infra_app)"
    mechanism: "provider-managed:doppler-aes256-gcm"
    evidence: "scripts/encryption-posture-ledger.json row store=doppler.secrets (attestation_url https://www.doppler.com/security) already covers every Doppler project; no new ledger row"
    defends_against: "a Doppler storage-layer disclosure (disk, backup, database snapshot)"
    does_not_defend: "any holder of a token that reads the config (the new release-app-mint token, DOPPLER_TOKEN_TF, workplace admins), a compromised release job at the moment its step names the token, Doppler's own version history of the value"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable:the attestation is the vendor's published statement; same status as the doppler.secrets ledger row"
in_transit:
  - connection: "GitHub Actions runner / operator terminal -> api.doppler.com (Doppler CLI)"
    enforced_at: "Doppler CLI (HTTPS only)"
    tls: "HTTPS, TLS 1.2+"
    cert_verification: "on"
    does_not_defend: "a compromised runner or a leaked read token"
    disclosed_as: "not-publicly-claimed"
  - connection: "release job / bootstrap script -> api.github.com (App JWT exchange, GET /app)"
    enforced_at: "curl default CA verification (composite and script)"
    tls: "HTTPS, TLS 1.2+"
    cert_verification: "on"
    does_not_defend: "a compromised runner"
    disclosed_as: "not-publicly-claimed"
```

## Guard Contract

### Guard 1 - Census Guard 7 (the narrowed container stays narrow)

**Property.** No Terraform root writes a secret, token or reader into the `soleur-infra-app` project, the container is declared, and nothing in CI or the bootstrap script can put the narrowed token anywhere branch-reachable.

**Assembly.** Quantifies over every `.tf` file in every Terraform root the census already enumerates (`tf_root_files`: `apps/web-platform/infra`, `infra/github`, `git-data-root-key`, rung2), over every workflow/action step and every script reached through one level of `bash <repo-path>` (the census's existing derived `jobs`/`g6_scripts` population, not a hand list), and over the bootstrap script file. The chokepoint is the census's own derivation, so a new root or a new job is in scope without an edit.

**Mutation matrix.** Each row must be measured RED against the suite before the guard is written:

| # | Mutation | Must redden |
|---|---|---|
| M1 | add a `doppler_secret` naming `doppler_project.infra_app` in a NEW `.tf` file in the main root | G7c |
| M2 | after a compliant first (M1 reverted), add a `doppler_service_token` naming the literal `"soleur-infra-app"` in `infra/github/` (a second root) | G7c (a check that stops at the first root is itself the defect) |
| M3a | add a `doppler_secret` whose `project = var.some_project` (or a `local`, or a module call) in any root | G7c (a stateful Doppler resource whose project is not a plain literal or a resource reference is flagged, so the literal-keyed check cannot be sidestepped) |
| M3 | rename the project literal in the `.tf` (`soleur-infra-app` -> `soleur-infra-app2`) | G7c (declared check) |
| M4 | run the census on an empty `.tf` tree (dispatch row: "0 scanned" must not pass) | G7c, plus the suite's scan-floor exit |
| M5 | add a step that mints a token on `soleur-infra-app` to any workflow | G7d |
| M6 | in the bootstrap script change `--env infra-privileged` to a repository-level `gh secret set` | G7d |

**Harness rows.** H1: delete the Guard 7 dispatch block from the suite; the dispatch self-test (the existing `wf_row` empty-tree pattern) must go RED. H2 (must-PASS, not the canonical): a fixture tree that declares the project plus an unrelated `doppler_secret` on a different project, and mentions `soleur-infra-app` only in a comment, must PASS G7c, so a guard that rejects everything is also caught.

**Anchor.** The guard compares literals held in the suite itself (the project name, the two addresses, the secret name). Weakening any of them requires editing the suite in the same diff, which review sees; there is no stored hash or count floor to substitute (the only count is `CENSUS_ROWS`, bumped with the rows, and M5's floor).

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-241** with **D11** (the release-job App values live in their own Doppler project) as an in-scope task of Phase 4, with an Amendment-log entry, a Statuses row (`adopting`). ADR-232 and the 2026-09-30 amendment's deferral sentence get dated markers in PR-2 (when the source actually changes). No new ordinal is taken, so no ADR-ordinal collision is possible.

### C4 views
Read all three model files (`model.c4`, `views.c4`, `spec.c4`) for the enumeration: (a) external human actors: none new (the operator already appears through the Tier-B edge); (b) external systems: Doppler, GitHub and the soleur-infra App are already modeled, and the new container is a project inside Doppler, which the model describes in edge prose rather than as a separate element; (c) data stores/containers: none new at C4 altitude; (d) actor-to-surface relationships changed: none (the same two jobs read the same App values from a narrower source). The one falsified statement is the `github -> doppler` edge description that calls the narrower source "a recorded deferral": it stays true while the container is dormant, so the edit and the `model.likec4.json` regeneration land in PR-2 (see Phase 4); PR-2 runs `plugins/soleur/test/c4-count-parity.test.sh` and the freshness test (the edit adds no derived cardinality).

### Sequencing
D11 is authored now describing the target state with `adopting` status; it flips when PR-2 is merged and a real release run shows the notice.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing from the containers themselves (unread), but merging PR-1 starts a routine web-platform release and deploy of unchanged application code (the new file is under `apps/web-platform/`). If PR-2 lands before its credential exists, the inngest-bootstrap release stalls: a carrier-changing merge publishes no new image and no pin-bump PR opens, with nothing published and a Slack post; no user-facing surface is touched.
**If this leaks, the user's workflow and repositories are exposed via:** the soleur-infra App private key (one extra copy in `soleur-infra-app`) or the new read token; and, today, the broad Tier-B token, which reaches `DOPPLER_TOKEN_TF`, a read/write Hetzner token and, once the runtime-key sequence has run, the path to the soleur-ai runtime key that web-platform uses on every connected user's repositories. This work narrows who can reach those; it adds one more copy of the infra App key, which is the accepted cost.
**Brand-survival threshold:** single-user incident

CPO sign-off is required before `soleur:work` begins (carried from the issue's own User-Impact line). `soleur:engineering:review:user-impact-reviewer` runs at review time. The CTO concern that motivated the issue is the design driver. CLO: no processing activity changes; the Article 30 register's mention of the Tier-B token is a legal document and is out of scope for this change.

## Open Code-Review Overlap

One open code-review scope-out names `build-inngest-bootstrap-image.yml` (the probe-gate window versus a silent-truncation property). **Acknowledge:** different concern; PR-2 touches only the Doppler-token lines of that file, so that issue stays open and untouched. No other open code-review issue names any planned file.

## Files to Edit (PR-1)

- `.github/workflows/apply-web-platform-infra.yml` (two `-target` lines)
- `tests/scripts/test-infra-privileged-tier-census.sh` (`ENV_SECRETS`, Guard 7, `CENSUS_ROWS`, mutation rows, dispatch self-test)
- `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`

Path-glob check: each file above exists in `git ls-files`; the apply workflow's `paths:` filter matches `apps/web-platform/infra/**` and the workflow file itself.

## Files to Create (PR-1)

- `apps/web-platform/infra/infra-app-project.tf`
- `knowledge-base/project/specs/feat-one-shot-9321-scoped-app-token-doppler/bootstrap.sh` (generated; its run ledger and any `.env` beside it stay untracked)
- `knowledge-base/project/specs/feat-one-shot-9321-scoped-app-token-doppler/tasks.md`

**Explicitly NOT touched in PR-1** (a negative-scope acceptance criterion): the composite, `build-inngest-bootstrap-image.yml`, `mint-inngest-bootstrap-tag.yml`, the two `.github/scripts/test/` suites, `cla.yml`, any legal document, anything GHCR.

## Acceptance Criteria

### Pre-merge (PR-1)
- [ ] `infra-app-project.tf` declares exactly `doppler_project.infra_app` and `doppler_environment.infra_app_prd`, both `prevent_destroy`, description under 255 characters (`scripts/lint-doppler-description-length.py` green), and no `doppler_secret`, `doppler_service_token`, data source, variable or output.
- [ ] Both addresses are in the push `apply` job's `-target` list; `plugins/soleur/test/workflow-file-size.test.ts` and `plugins/soleur/test/terraform-target-parity.test.ts` green.
- [ ] Census Guard 7 rows G7c and G7d (PR-1 halves) green; every mutation row M1 to M6 measured RED and H1/H2 behave as stated; `CENSUS_ROWS` matches.
- [ ] `bootstrap.sh` exists, is generated from the template with the library path baked, passes both skill-section-4 runs with no write performed, `scripts/lint-shell-trace-credential-refusal.py` green, and contains no repository-level `gh secret set` and no value echo.
- [ ] ADR-241 D11, Amendment-log entry and Statuses row present; runbook section present; (the C4 edge edit and regeneration are PR-2's); `scripts/lint-infra-no-human-steps.py` green on every changed markdown file.
- [ ] `git diff --stat origin/main...HEAD` shows none of the files listed under "Explicitly NOT touched".
- [ ] PR body says `Ref #9321`, states that merging auto-applies two empty containers and also starts the web-platform release and infra-validation workflows (with the evidence), links the order table and contains no `#N` other than 9321 and 9320.
- [ ] CI is green (CI is the test gate).

### Post-merge (performed by CI and the bootstrap script, not by this pipeline)
- [ ] The push apply on `main` concludes success with no destroys and exactly the two creates.
- [ ] The bootstrap script runs to `SOLEUR_BOOTSTRAP_READY_FOR_PR2`; its final stage shows the environment secret listed, no repository-level copy, exactly one token named `release-app-mint`.
- [ ] PR-2 opened only after that, with `Closes #9321`.

## Domain Review

**Domains relevant:** engineering (CTO), legal (noted, out of scope)

### Engineering (CTO)
**Status:** reviewed (carried from the issue: the CTO concern recorded in the predecessor plan and the architecture review on the Tier-B re-tier PR). **Assessment:** project-not-config, operator-minted token, no secret in state, dormant-first landing; boundary stated honestly as by-reference narrowing under a main-only policy.

### Legal (CLO)
**Status:** reviewed (scoping only). **Assessment:** no new processing activity and no new data category; the Article 30 register mentions the Tier-B token but legal documents are out of scope for this change by the operator's standing constraint.

### Product/UX Gate
**Tier:** none (no user-facing surface). No `components/**`, `app/**/page.tsx` or `layout.tsx` path is created.

## Test Scenarios

1. Empty `.tf` tree -> G7c RED (not "0 checked, exit 0").
2. M1/M2 (secret or token on the project in a first and a second root) -> G7c RED.
3. Target line deleted -> `terraform-target-parity.test.ts` RED (existing test, no census row).
4. Bootstrap run 1 (skip variables set, no TTY): unattended up to the first go-ahead, exit 64, no write.
5. Bootstrap run 2 (no skip variables, no TTY): `SOLEUR_BOOTSTRAP_INPUT_REQUIRED` naming the first variable, before any read.
6. Bootstrap re-run after completion: every stage reports "already satisfied", no write.
7. PR-2 CI (fixture `doppler` stub): a read against `--project soleur-infra-privileged` is refused by the fixture and the composite names only the two values.

## Risks and Mitigations

- **Two copies of the infra App private key.** Accepted cost; a stale copy fails closed (P5); the runbook rotation line and script stage 2 reconcile.
- **A repository-level secret by mistake.** The library helper writes repository-level secrets; the script uses `--env` directly, the preflight and final stage read the repository-level list, and G7d/M6 pin it.
- **Early PR-2 merge.** Fails before any publish with a Slack post (see Landing Order).
- **Auto-apply on PR-1.** Two creates only; kill switch available; name verified free.
- **Parallel C4 regeneration** by another session: regenerate on conflict.
- **The runtime-key boundary stays nominal.** Unchanged by this work and stated in D11.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| A Doppler branch config of the Tier-B project | Inherits the root's values; a token on it reads the whole project (ADR-241 D3). |
| An extra environment inside `soleur-infra-privileged` | Isolates by config too, but breaks the project-per-boundary precedent the census keys on, and a plan-level environment limit could not be checked without a write. |
| One PR with the switch plus a fallback to the broad token | Keeps the broad token reachable, cannot serve two projects with fixed argv, and a silent downgrade path is worse than a loud failure. |
| One PR that merges the switch and relies on a fast mint | Release jobs break between merge and mint; violates the standing constraint. |
| Terraform-minted token (service-token resource plus an environment-secret resource) | Lands the token in Tier-A-readable state (ADR-241 D3, census G6c). |
| Cross-project reference so there is one copy | Cannot be probed without a Doppler write; the census forbids references into isolated projects. |
| A dedicated fifth Tier-B GitHub environment | No extra property for jobs that run main's YAML; adds a policy resource and census churn. |

## Non-Goals

GHCR retirement; the legal cluster (`cla.yml` allowlist, legal documents including the Article 30 register); widening the live App (#9320); moving the runtime key; any change to the other Tier-B consumers; automatic reconciliation of the second copy (the script does it on demand).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan`; it is filled above.
- The library's `soleur_op_gh_secret_set` is repository-level; do not use it for this token.
- Do not put `[skip-web-platform-apply]` in the PR body: a default squash message would carry it and suppress the apply.
- The workflow file is near its byte ceiling; add no prose to it (put rationale in the runbook).
- Guard rows are written before the guard (Guard Contract); a matrix derived from finished code tests the code that exists.
- The two release suites pin step names exactly; PR-2 must rename them in the same diff or CI goes red.

## Review addendum (2026-10-01, the 12-seat review of PR 9349)

Applied in the PR-1 branch, recorded here so the plan above is read against what shipped:

- **bootstrap.sh stage 4** is a state machine: `TOKEN_STORED` proves the stored token before the already-satisfied skip; a sole token the run cannot show is stored is rotated new before old (this also covers a lost `.env`); an interrupted rotation is finished; a failed revoke is never reported as done (`revoke_confirmed` re-lists); an unreadable environment-secret list is INCONCLUSIVE, not absent; `secrets download` uses `--no-fallback`; the READY line carries the organisation-list verdict.
- **Census Guard 7** is derived and hardened: the project's address set comes from the declaring block (renamed label, environment/config alias), data sources and project-less tokens are flagged, block comments and `.tf.json` are handled, G7d catches quoted, flag-first and variable mints and stores that are a trailing-comment `--env`, the library helper, a REST PUT or a repointed `GH_ENVIRONMENT`, its script glob includes `specs/archive/`, G7e forbids a `${soleur-infra-app.` cross-project reference, and a must-pass fixture, a row-presence check and an `ENV_SECRETS` tripwire were added. It remains a census of spelled patterns; its header lists what it does not cover.
- **Not implemented, by design:** the project-member, webhook and sync checks the Phase 2 stage list promised (the Doppler CLI has no read for them; D11 now says so and tells the operator to compare members before running the script), a `--verify-only` mode, and a scheduled equality probe of the two copies.
- **D11 is `proposed`**, not `adopting`, until the switch change merges (it states target-state consumer sentences in the future tense), and the release-scoped App is recorded as a follow-up.
- **Observability:** `notify-apply-failure` is an ops email (Resend), not Slack; the release jobs post to Slack. The discoverability probe above counts both `-target` lines (Check 10's sandbox refuses shell-active tokens, so the probe uses fixed-string `-e` patterns rather than an alternation).
