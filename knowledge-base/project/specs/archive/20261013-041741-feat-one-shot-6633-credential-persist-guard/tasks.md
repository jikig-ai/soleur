# Tasks — chore(infra): credential-persist-to-home guard (#6633)

Plan: `knowledge-base/project/plans/2026-07-17-chore-credential-persist-home-guard-plan.md`
Lane: cross-domain (fail-closed default; substantively single-domain engineering/infra)
Branch: `feat-one-shot-6633-credential-persist-guard`

> **Deepened 2026-07-17** (test-design + simplicity + bash-parsing agents). Net: ONE guard file (not two), expanded M1-M8 battery with per-mutation fresh-copy + finding-text attribution, an in-guard non-empty-scan census (AC8), `${VAR:-default}` indirection resolution, `-`-prefix RWP handling, and a 3-shape unit extractor. See plan §Enhancement Summary.

## Phase 1 — Preconditions (read before writing)

- [x] 1.1 Re-enumerate sandboxed units: `grep -rnE 'ProtectHome=(read-only|yes)|ProtectSystem=strict' apps/web-platform/infra/` — confirm the 5-unit/6-definition inventory.
- [x] 1.2 Read the parsing precedents to mirror house style:
  - `apps/web-platform/infra/inngest.test.sh:176-217` (heredoc backreference-marker ExecStart parse + `>=3` non-vacuity count) and `:639-666` (count-safe `ReadWritePaths` `head -1` + `-`-prefix asserts).
  - `apps/web-platform/infra/ci-deploy.test.sh:3517-3546` (single-file cred-guard inline invariant + comment-strip).
  - `apps/web-platform/infra/supabase-advisor/scan-workflow-mutation.test.sh` (`mktemp -d` + cleanup `trap` + `SCRIPT_OVERRIDE` seam + `assert_mutated`).
  - `knowledge-base/project/learnings/best-practices/2026-07-14-cloud-init-templatefile-escaping-and-ci-deploy-payload-testing.md` (`$${…}` doubling; source-scoped `awk` range idiom).
- [x] 1.3 Confirm the REAL relocation shape: `ci-deploy.sh:73-74` — `readonly DEPLOY_DOCKER_CONFIG_DIR="${DEPLOY_DOCKER_CONFIG_DIR:-/mnt/data/deploy-docker}"` then `export DOCKER_CONFIG="$DEPLOY_DOCKER_CONFIG_DIR"`. Confirm the real `docker login` is at `ci-deploy.sh:990` inside `_docker_login_capture` (`--password-stdin`), and that ~20 commented `docker login` mentions exist (comment-strip must survive them).
- [x] 1.4 Confirm the webhook dispatch chain: `hooks.json.tmpl` `execute-command` → `ci-deploy-wrapper.sh:21` `exec … ci-deploy.sh`. Confirm `webhook.service:48` RWP uses `-`-prefixed tokens (`-/var/lib/inngest -/var/lib/vector -/etc/vector`).
- [x] 1.5 Confirm no registration meta-guard exists yet (`grep -n 'deploy-script-tests' .github/scripts/validate-infra-templates.sh` — advisory only). Satisfy it if one appeared.

## Phase 2 — The single guard (`credential-persist-home-guard.test.sh`)

- [x] 2.1 Scaffold house style: `#!/usr/bin/env bash`, `set -euo pipefail`, `SCRIPT_DIR` via `${BASH_SOURCE[0]}`, `ROOT="${CRED_GUARD_INFRA_ROOT:-$SCRIPT_DIR}"`, inline `pass`/`fail` counters, non-zero exit on any fail. No shared lib.
- [x] 2.2 **Stage 1 — 3-shape enumeration + count assert.** Extract `[Service]` unit blocks declaring `ProtectHome=(read-only|yes)`/`ProtectSystem=strict` via: (a) `.service` whole-file, (b) `.sh` heredoc backreference-marker (`inngest.test.sh:176-217`), (c) cloud-init `write_files: content: |` `^[[:space:]]*`-anchored per-line. Capture each unit's `ExecStart` + `ReadWritePaths` (count-safe `head -1`). Assert sandboxed-unit count **≥ 5** (non-vacuity). Mind `$${…}` source-vs-rendered `$` form.
- [x] 2.3 **Stage 2 — flat `unit → {script | NONE}` map (fail-closed).** `webhook.service` → `ci-deploy.sh` (+ `ci-deploy-wrapper.sh`, via the hooks/wrapper chain the ExecStart binary hides); the 4 `doppler run` units → `NONE`. Assert (i) every Stage-1 unit is in the map (else FAIL); (ii) every mapped script path exists (else FAIL). Do NOT add a hooks.json-routing integrity check (covered by `inngest.test.sh:645-655`).
- [x] 2.4 **Stage 3 — cred-persist scan + relocation check.** Comment-strip (`^\s*#`) each mapped script; grep the family signals; for each hit require the family's config-dir relocation off-home into an RWP entry — **resolving one level of `${VAR:-default}`/`$VAR` indirection**, **stripping one leading `-` from each RWP token**, rejecting a resolved value under `$HOME`/`~`/`/home`/`/root`, and treating an unresolvable target as fail-closed FAIL; OR home dir ∈ RWP. NO blanket `/mnt/data`-allow.
- [x] 2.5 **Census (AC8 — anti-vacuity positive control).** Assert `CRED_SITES_DETECTED ≥ 1` and that `webhook.service → ci-deploy.sh` was classified detected+relocated. Zero cred sites ⇒ FAIL (over-strip/anchor-drift/empty-resolution), never GREEN.
- [x] 2.6 **Family table.** docker (live, indirection-aware) + doppler (live scoping: `login|setup|configure set|configure token`; EXCLUDE `configure get|debug` + bare `doppler run`). gh/aws/generic `~/.config` = commented one-row extension point, NOT executable stubs.
- [x] 2.7 Verify GREEN + census on the real tree (AC2/AC8); print PASS/FAIL summary; `exit 1` on any fail.

## Phase 3 — Inline mutation battery (same file: `run_guard_expect_red()` + GREEN pins)

- [x] 3.1 Helper: `run_guard_expect_red()` — fresh `mktemp -d` copy per call (`cp -r`, cleanup `trap`, **non-cumulative**), assert copy **GREEN before mutation**, apply mutation, `assert_mutated` (`cmp -s`), run the scan against `CRED_GUARD_INFRA_ROOT="$sbx"`, assert non-zero, AND `grep -qF <mutated-site>` the finding output (F6 attribution). `cq-test-fixtures-synthesized-only` — mutations touch only copies.
- [x] 3.2 **M1** `export DOCKER_CONFIG="$HOME/.docker"` → RED.
- [x] 3.3 **M2** `docker login`, no relocation → RED.
- [x] 3.4 **M3 / M3b / M3c** `--config "$HOME/.docker"` / `--config=$HOME/.docker` / `DOCKER_CONFIG="$HOME/.docker" docker login` (inline-env, no export) → all RED.
- [x] 3.5 **M4** new sandboxed unit running `doppler login`/`setup`/`configure set` (or `~/.doppler` write), no relocation → RED.
- [x] 3.6 **M5 / M5b** relocation to `/opt/creds` not in RWP / to `/mnt/data/creds` while RWP omits `/mnt/data` → both RED.
- [x] 3.7 **M6** delete `ci-deploy.sh`'s real `DOCKER_CONFIG` export/indirection → RED.
- [x] 3.8 **M7 / M7b** flip `ci-deploy.sh:73` `:-` default to `$HOME/.docker` (export unchanged) → RED (indirection resolved) / `export DOCKER_CONFIG="$UNSET_VAR"` → FAIL fail-closed (covers `$XDG_CONFIG_HOME`).
- [x] 3.9 **M8** heredoc-defined `ProtectHome=read-only` unit with inline `docker login` in ExecStart (no separate script) → RED (scan inline ExecStart, or fail-closed on "sandboxed unit, no script, family action in ExecStart").
- [x] 3.10 **GREEN — boot false-positive probe (AC4).** Inject an un-relocated `docker login` into a `runcmd:` block of a `cloud-init.yml` copy → GREEN. Also assert zero finding for the existing `cloud-init.yml:491/499/512`, `cloud-init-inngest.yml:260`, `soleur-host-bootstrap.sh:207/231` sites.
- [x] 3.11 **GREEN — bare `doppler run` pin.** Synthetic `ProtectHome=read-only` unit running `doppler run -- X` → GREEN (guards the redis/inngest/vector current-tree FP).
- [x] 3.12 **GREEN — valid relocation** (incl. relocation into a `-`-prefixed RW entry) → GREEN.
- [x] 3.13 **AC5 fail-closed** — inject a novel `ProtectHome=read-only` unit absent from the map → RED.

## Phase 4 — Registration & verification

- [x] 4.1 Edit `.github/workflows/infra-validation.yml`: add ONE named step to `deploy-script-tests` (append after `git-data-transport-wrapper.test.sh`, ~`:589`), `- name:` carrying `#6633`, `run: bash apps/web-platform/infra/credential-persist-home-guard.test.sh`.
- [x] 4.2 Verify: `grep -c 'credential-persist-home-guard' .github/workflows/infra-validation.yml` ≥ 1 (AC1).
- [x] 4.3 Run locally: `bash apps/web-platform/infra/credential-persist-home-guard.test.sh` → exit 0 (GREEN + census + M1-M8 RED + GREEN pins).
- [x] 4.4 `actionlint .github/workflows/infra-validation.yml` (do NOT `bash -n` the `.yml`); `bash -n` the guard file.

## Phase 5 — Close-out

- [x] 5.1 Write session learning `knowledge-base/project/learnings/workflow-patterns/2026-07-<dd>-<topic>.md` (date at write time).
- [x] 5.2 Verify ACs 1-8 satisfied (all pre-merge; sole post-merge line is "None — author-time CI only").

## Notes
- **Anti-vacuity is the whole point** (learning `2026-07-17-buy-the-datum…` SE#3): M1-M8 each independently RED on a fresh copy, finding-text-attributed; plus the AC8 census. A guard whose deletion/inversion leaves the suite green pins nothing.
- **The relocation is a `${VAR:-default}` indirection** (`ci-deploy.sh:73-74`), not a literal on the export line — resolve one level or the guard is vacuous (M7).
- **Registration is load-bearing** — advisory list, no meta-guard; an unregistered test is silently green.
- Cite content anchors, not line numbers, in the guard (`cq-cite-content-anchor-not-line-number`).
