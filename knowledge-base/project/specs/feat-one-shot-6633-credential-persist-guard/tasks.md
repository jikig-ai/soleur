# Tasks — chore(infra): credential-persist-to-home guard (#6633)

Plan: `knowledge-base/project/plans/2026-07-17-chore-credential-persist-home-guard-plan.md`
Lane: cross-domain (fail-closed default; substantively single-domain engineering/infra)
Branch: `feat-one-shot-6633-credential-persist-guard`

## Phase 1 — Preconditions (read before writing)

- [ ] 1.1 Re-enumerate sandboxed units: `grep -rnE 'ProtectHome=(read-only|yes)|ProtectSystem=strict' apps/web-platform/infra/` — confirm the 5-unit/6-definition inventory in the plan still holds.
- [ ] 1.2 Read the parsing precedents to mirror house style:
  - `apps/web-platform/infra/ci-deploy.test.sh:3517-3546` (narrow docker relocation guard; comment-strip + assignment-count invariant).
  - `apps/web-platform/infra/inngest.test.sh:639-666` (count-safe `ReadWritePaths` single-line extraction) and `:180-210` (Python-heredoc `ExecStart` parse).
  - `apps/web-platform/infra/supabase-advisor/scan-workflow-mutation.test.sh` (canonical mutation attestation: `mktemp -d` + cleanup `trap` + `SCRIPT_OVERRIDE`/root-env seam + `assert_mutated`/`cmp -s`).
- [ ] 1.3 Confirm the webhook dispatch chain: `hooks.json.tmpl` `execute-command` → `ci-deploy-wrapper.sh:21` `exec … ci-deploy.sh`. Confirm the DOCKER_CONFIG relocation anchor `ci-deploy.sh` (`DEPLOY_DOCKER_CONFIG_DIR:-/mnt/data/deploy-docker`).
- [ ] 1.4 Confirm no registration meta-guard exists yet (`grep -n 'deploy-script-tests' .github/scripts/validate-infra-templates.sh` — advisory only). If one has appeared, plan to satisfy it too.

## Phase 2 — Core: the guard (`credential-persist-home-guard.test.sh`)

- [ ] 2.1 Scaffold house style: `#!/usr/bin/env bash`, `set -euo pipefail`, `SCRIPT_DIR` via `${BASH_SOURCE[0]}`, `ROOT="${CRED_GUARD_INFRA_ROOT:-$SCRIPT_DIR}"`, inline `pass`/`fail` counters, non-zero exit on any fail. No shared lib.
- [ ] 2.2 **Stage 1 — derived enumeration.** Scan `$ROOT` for `[Service]`/heredoc/cloud-init unit bodies declaring `ProtectHome=(read-only|yes)` or `ProtectSystem=strict`; capture each unit's `ExecStart` and `ReadWritePaths` (count-safe extraction).
- [ ] 2.3 **Stage 2 — unit → in-namespace script resolution (fail-closed association table).**
  - Map each sandboxed unit to its in-namespace repo scripts. For `webhook.service`: resolve `hooks.json.tmpl` `execute-command` roster (map `/usr/local/bin/<X>` → `$ROOT/<X>`) + follow the one `exec` hop `ci-deploy-wrapper.sh → ci-deploy.sh`. For the `doppler run` units: audit the inline `ExecStart` command + unit `Environment=`.
  - Assert (i) every Stage-1 unit is covered by the table (uncovered → FAIL); (ii) every mapped script path exists (missing → FAIL); (iii) integrity: `hooks.json.tmpl` still routes to `ci-deploy-wrapper.sh` → `ci-deploy.sh`.
- [ ] 2.4 **Stage 3 — credential-persist scan + relocation check.** Comment-strip (`^\s*#`) each associated script; grep the family table signals; for each hit require the family's config-dir relocation to an off-home path that is in the unit's `ReadWritePaths` (or `/mnt/data`), rejecting `$HOME`/`~`/`/home`/`/root`-resolving *values*; OR the home dir listed in `ReadWritePaths`. Else `fail`.
- [ ] 2.5 Encode the extensible **family table** (docker, doppler; commented `gh`/`aws` stubs) with the relocation signal per family (AC6). Doppler signal scopes to `login`/`setup`/`configure` + literal `~/.doppler` writes — **not** bare `doppler run` (would false-positive the current tree).
- [ ] 2.6 Print a `PASS/FAIL` summary; `exit 1` on any fail. Verify GREEN on the real tree (AC2).

## Phase 3 — Core: the mutation attestation (`credential-persist-home-guard-mutation.test.sh`)

- [ ] 3.1 Scaffold: `set -uo pipefail`, `SCRIPT_DIR`, `mktemp -d` sandbox + cleanup `trap`, `cp -r "$SCRIPT_DIR"/* "$SANDBOX"/`, `assert_mutated`/`cmp -s` helper, `run_guard()` that invokes `CRED_GUARD_INFRA_ROOT="$SANDBOX" bash "$SCRIPT_DIR/credential-persist-home-guard.test.sh"` and captures exit code.
- [ ] 3.2 **M1** — inject a `ProtectHome=read-only` unit whose ExecStart script does `docker login` with `export DOCKER_CONFIG="$HOME/.docker"` → assert guard RED.
- [ ] 3.3 **M2** — `docker login` with no `DOCKER_CONFIG` relocation → RED.
- [ ] 3.4 **M3** — `docker … --config "$HOME/.docker"` on a continuation line → RED.
- [ ] 3.5 **M4** — new sandboxed unit running `doppler login`/`doppler setup` (or `~/.doppler` write) with no relocation → RED (class-wide/doppler coverage, AC3/AC6).
- [ ] 3.6 **M5** — relocation onto an off-home path NOT in `ReadWritePaths` (e.g. `/opt/creds`) under `ProtectSystem=strict` → RED.
- [ ] 3.7 **M6** — delete `ci-deploy.sh`'s real `DOCKER_CONFIG` export (re-introduce the exact #6565 shape) → RED.
- [ ] 3.8 **GREEN — pristine copy** (no mutation) → guard exits 0 (AC2 mirror).
- [ ] 3.9 **GREEN — boot false-positive probe (AC4).** Inject an un-relocated `docker login` into a `runcmd:` block of the copy's `cloud-init.yml`; assert guard emits ZERO finding. Also assert zero finding for the existing `cloud-init.yml:491/499/512`, `cloud-init-inngest.yml:260`, `soleur-host-bootstrap.sh:207/231` sites.
- [ ] 3.10 **GREEN — valid relocation** — new sandboxed unit whose ExecStart does `docker login` with `export DOCKER_CONFIG=/mnt/data/x` and `/mnt/data` in `ReadWritePaths` → guard GREEN.
- [ ] 3.11 **AC5 — fail-closed** — inject a novel `ProtectHome=read-only` unit not covered by the association table → guard RED (unknown unit ⇒ FAIL, not silent-skip).
- [ ] 3.12 Each RED mutation gated by `assert_mutated` (`cmp -s`) so a no-op mutation cannot masquerade as a catch. `exit 0` only when all attestations hold.

## Phase 4 — Registration & verification

- [ ] 4.1 Edit `.github/workflows/infra-validation.yml`: add two named steps to `deploy-script-tests` (append after `git-data-transport-wrapper.test.sh`, ~`:589`), each `- name:` carrying the `#6633` reference, `run: bash apps/web-platform/infra/credential-persist-home-guard{,-mutation}.test.sh`.
- [ ] 4.2 Verify registration: `grep -c 'credential-persist-home-guard' .github/workflows/infra-validation.yml` ≥ 2 (AC1).
- [ ] 4.3 Run locally: `bash apps/web-platform/infra/credential-persist-home-guard.test.sh && bash apps/web-platform/infra/credential-persist-home-guard-mutation.test.sh` → both exit 0.
- [ ] 4.4 `actionlint .github/workflows/infra-validation.yml` (do NOT `bash -n` the `.yml`); `bash -n` both test files.

## Phase 5 — Close-out

- [ ] 5.1 Write session learning `knowledge-base/project/learnings/workflow-patterns/2026-07-<dd>-<topic>.md` (date at write time; do not pin the filename now).
- [ ] 5.2 Verify ACs 1-7 in the plan are all satisfied (all pre-merge; the sole post-merge line is "None — author-time CI only").

## Notes
- **Anti-vacuity is the whole point** (learning `2026-07-17-buy-the-datum…` SE#3): a guard whose deletion/inversion leaves the mutation suite GREEN pins nothing. M1-M6 must each independently drive RED, proven via `assert_mutated`.
- **Registration is load-bearing** — the `deploy-script-tests` job is an explicit list with no meta-guard; an unregistered test is silently green.
- Cite content anchors, not line numbers, in the guard (`cq-cite-content-anchor-not-line-number`) — `ci-deploy.sh`/`cloud-init.yml` line numbers drift.
