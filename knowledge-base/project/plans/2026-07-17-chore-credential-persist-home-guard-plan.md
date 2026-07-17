---
title: "chore(infra): author-time guard — no credential-persist to a home dir under a ProtectHome=read-only unit"
date: 2026-07-17
type: chore
issue: 6633
branch: feat-one-shot-6633-credential-persist-guard
lane: cross-domain
brand_survival_threshold: none
status: draft
---

# 🧰 chore(infra): author-time guard — no credential-persist to a home dir under a sandboxed unit

Closes #6633.

> Spec lacks valid `lane:` (no spec.md for this branch) — defaulted to `cross-domain` (TR2 fail-closed). In substance this is a single-domain engineering/infra change.

## Overview

A credential-persist-to-home failure class has now recurred **twice** in production, both times found only in the real service mount namespace (never by `terraform validate`, `cloud-init schema`, or the shell suites):

1. **docker** (#6565, fixed by merged PR #6623, commit `6db2274f3`): `ci-deploy.sh` under `webhook.service` (`ProtectHome=read-only`) wrote `docker login` creds to `/home/deploy/.docker/config.json` → EROFS `class=cred_store kw=errsaving,erofs`. Repaired by `export DOCKER_CONFIG=/mnt/data/deploy-docker` (an existing `ReadWritePath`).
2. **doppler** (2026-04-06 precedent): the Doppler CLI's `os.Mkdir(~/.doppler)` hit the same EROFS under `ProtectHome=read-only`; resolved by relocating its config dir.

This plan adds a **deterministic, author-time CI guard** — a pair of `*.test.sh` files registered in `.github/workflows/infra-validation.yml` — that fails the build if any systemd unit shipping `ProtectHome=read-only`/`ProtectSystem=strict` runs an ExecStart chain that persists a credential to a `$HOME` path without either (a) relocating that tool's config dir off `$HOME` onto a writable path, or (b) listing the home config dir in the unit's `ReadWritePaths`. The guard is scoped strictly to sandboxed-unit ExecStart chains, so un-sandboxed boot-time root logins (cloud-init `runcmd`/`bootcmd`, fresh-boot bootstrap) are **not** flagged.

**Design north star (load-bearing):** the learning `2026-07-17-buy-the-datum-then-read-it-with-the-right-telemetry-key.md` Session Error #3 records that the *first* attempt at this exact guard shipped **two vacuous assertions** — they pinned literal line-shapes, so three realistic mutations produced dual-false-PASS. This plan's central quality bar is therefore an **adversarial mutation battery**: a guard whose deletion/inversion leaves the suite green pins nothing. Every invariant below is paired with a mutation that must independently drive RED.

## Research Reconciliation — cited premises vs. codebase reality

| Cited premise | Reality (measured) | Plan response |
|---|---|---|
| "#6565 … fixed in PR #6623" | PR #6623 is **MERGED** (`6db2274f3`), relocating `DOCKER_CONFIG` in `ci-deploy.sh:73-80`. Issue **#6565 is OPEN** — titled "P1: repair the zot/GHCR login failure"; per the learning it is the *repair* issue that closes on a "failures stopped" soak (followthrough `scripts/followthroughs/zot-login-gate-erofs-repaired-6565.sh`). | Premise holds — the docker EROFS *was* repaired by #6623. #6565's open state is a pending soak, not a stale premise; this preventive guard is independent of that soak. No plan-shape change. |
| "doppler … writes `~/.doppler`" | True in general, but every **current** sandboxed doppler invocation is `doppler run --project X --config prd --` (a **read** using a `DOPPLER_TOKEN`/service token) — **no** `~/.doppler` write. `ci-deploy.sh` additionally sets `DOPPLER_CONFIG_DIR=/tmp/.doppler`. | The guard must **not** flag bare `doppler run` (would turn the current tree RED — false positive on `inngest-redis`/`inngest-server`/`vector`). Doppler family signal scopes to config-persisting subcommands (`login`/`setup`/`configure`) + literal `~/.doppler` writes. See Sharp Edges. |
| Guard should enumerate "webhook.service, inngest-*.service, soleur-host-bootstrap-installed units, etc." | Grep of `ProtectHome`/`ProtectSystem` across `apps/*/infra/` returns exactly **5 distinct sandboxed units** (6 definitions). **Only `webhook.service` performs a home-cred write** (via `ci-deploy.sh`), and it is already relocated. All others (`inngest-redis`, `inngest-server`, `vector`×2) run token-based `doppler run` with no home-cred write. | Guard enumerates the 5 units mechanically (fail-closed on any new one) but only `ci-deploy.sh` carries a real cred-persist site today. |
| Guard is "sibling to the existing `apps/web-platform/infra/*.test.sh`"; a narrow `ci-deploy.test.sh` guard already exists | `ci-deploy.test.sh:3517-3546` already pins ci-deploy.sh's DOCKER_CONFIG relocation (exactly-once, `/mnt/data`, no `/home/deploy`). | New guard is the **class-wide net**; the narrow guard stays (intentional defense-in-depth overlap). See Open Code-Review Overlap. |

## Sandboxed-unit inventory (guard ground truth)

Enumerated from `grep -rnE 'ProtectHome=(read-only|yes)|ProtectSystem=strict' apps/*/infra/`. Every occurrence is `ProtectHome=read-only` + `ProtectSystem=strict` + `PrivateTmp=true`.

| Unit | Defined in | ExecStart chain → repo cred surface | Home-cred write? | Relocated? |
|---|---|---|---|---|
| `webhook.service` | `apps/web-platform/infra/webhook.service` **and** inline copy in `cloud-init.yml:231-266` (lockstep) | `webhook` binary → `hooks.json.tmpl` (`execute-command: ci-deploy-wrapper.sh`) → `ci-deploy-wrapper.sh:21` (`exec … ci-deploy.sh`) → **`ci-deploy.sh`** (`docker login`) | **YES** (docker) | **YES** → `DOCKER_CONFIG=/mnt/data/deploy-docker`, `/mnt/data` ∈ `ReadWritePaths` (`webhook.service:48`) |
| `inngest-redis.service` | `apps/web-platform/infra/inngest-redis.service` | `doppler run … -- redis-server` | No (token read) | N/A |
| `inngest-server.service` | heredoc in `inngest-bootstrap.sh` (target line 60, heredoc line 504) | `doppler run … -- inngest start` | No (token read) | N/A |
| `vector.service` (inngest host) | heredoc in `inngest-bootstrap.sh` (line 725) | `doppler run … -- vector` | No (token read) | N/A |
| `vector.service` (web host) | heredoc in `soleur-host-bootstrap.sh` (line 391) | `doppler run … -- vector` (token-optional) | No (token read) | N/A |

**Boot-immune sites the guard MUST NOT flag** (un-sandboxed root at cloud-init `runcmd`/fresh-boot bootstrap — NOT a `[Service]` ExecStart):
- `cloud-init.yml` runcmd logins: lines **491, 499, 512** (`runcmd:` starts line 299, `STAGE=ghcr_login` line 476).
- `cloud-init-inngest.yml` runcmd login: line **260** (`runcmd:` starts line 154).
- `soleur-host-bootstrap.sh` fresh-boot logins: lines **207, 231** (invoked from `cloud-init.yml:565`, inside `runcmd:`, as root).

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — this is an author-time CI guard with no production runtime and no data surface. A **false negative** (guard fails to catch a real trap) degrades only to the pre-guard status quo: a future credential-persist-to-home write could ship latent and, on the next deploy, EROFS a host's `docker login`/`doppler` → deploys silently fail (the #6565 shape). A **false positive** blocks a legitimate infra PR (developer friction), never a user.

**If this leaks, the user's data is exposed via:** N/A — the guard reads systemd unit text and shell source only; it handles and persists no secrets or credentials.

**Brand-survival threshold:** none.

- `threshold: none, reason:` the deliverable is a preventive CI lint that executes only in GitHub Actions and reads repo files; its failure mode is "does not prevent a future latent trap" (status-quo), not a direct single-user incident, and it moves no user data. (Scope-out bullet required because the diff touches `apps/*/infra/` and `.github/workflows/*infra-validation*` — both match the canonical sensitive-path regex.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Guard exists & is registered.** A guard `apps/web-platform/infra/credential-persist-home-guard.test.sh` (+ its mutation-attestation sibling) exists and is added as an explicit `- name:`/`run: bash …` step in the `deploy-script-tests` job of `.github/workflows/infra-validation.yml` (the job is an explicit hardcoded list — an unregistered test "gates NOTHING and fails silently green", `infra-validation.yml:452-455`). Verify: `grep -c 'credential-persist-home-guard' .github/workflows/infra-validation.yml` ≥ 2 (guard + mutation).
- [ ] **AC2 — Current tree GREEN.** `bash apps/web-platform/infra/credential-persist-home-guard.test.sh` exits 0 against the real infra tree (ci-deploy.sh's relocated docker write passes; the four token-`doppler run` units pass; no false positive).
- [ ] **AC3 — Mutation-proven RED (the anti-vacuity battery).** `bash apps/web-platform/infra/credential-persist-home-guard-mutation.test.sh` exits 0, and it independently drives the guard **RED** on each mutation below (each applied only to a `mktemp -d` copy, `cq-test-fixtures-synthesized-only`; each gated by an `assert_mutated`/`cmp -s` so a no-op mutation cannot masquerade as a catch):
  - **M1** — a `ProtectHome=read-only` unit whose ExecStart script does `docker login` with `export DOCKER_CONFIG="$HOME/.docker"` (relocation that points **back** to home — the sneaky dual-false-PASS case from the learning).
  - **M2** — `docker login` with **no** `DOCKER_CONFIG` relocation at all (bare keyword-less default `~/.docker`).
  - **M3** — a `docker … --config "$HOME/.docker"` (or `/root/.docker`) on a `docker run`/continuation line.
  - **M4** — a **new** sandboxed unit whose ExecStart script runs `doppler login`/`doppler setup` (or writes `~/.doppler`) with no relocation → proves class-wide coverage beyond docker.
  - **M5** — a relocation onto an absolute off-home path that is **not** in the unit's `ReadWritePaths` (e.g. `/opt/creds`) under `ProtectSystem=strict` → proves the RW-membership check, not just an off-home string match.
  - **M6** — deleting `ci-deploy.sh`'s real `DOCKER_CONFIG` export (re-introduces the exact #6565 shape) → RED.
- [ ] **AC4 — Boot-immune sites stay GREEN (no false positives).** The mutation test asserts the guard emits **zero** finding for `cloud-init.yml:491/499/512`, `cloud-init-inngest.yml:260`, and `soleur-host-bootstrap.sh:207/231` — even though they contain `docker login` — because none is inside a `[Service]` stanza carrying a `Protect*` directive.
- [ ] **AC5 — Fail-closed enumeration.** The mutation test proves that adding a **new** `ProtectHome=read-only` unit that the guard's unit→script association table does not cover makes the guard RED (unknown sandboxed unit ⇒ FAIL, never silent-skip). Verify by injecting a novel sandboxed unit into the fixture root.
- [ ] **AC6 — Family extensibility documented.** The guard covers docker (`~/.docker`) and doppler (`~/.doppler`) and carries an explicit, commented family table with the config-dir relocation signal for each, plus stubs for `gh` (`GH_CONFIG_DIR`/`~/.config/gh`) and `aws` (`AWS_CONFIG_FILE`/`~/.aws`) so a future family is a one-row addition.
- [ ] **AC7 — House-style conformance.** Both files: `#!/usr/bin/env bash` + `set -euo pipefail` (guard) / `set -uo pipefail` (mutation, per precedent), `SCRIPT_DIR` via `${BASH_SOURCE[0]}`, inline helpers (no shared lib), pass/fail counters, non-zero exit on any failure, `mktemp -d` + cleanup `trap` for mutations. Self-contained bash; no network/root/docker/terraform required.

## Design

### Guard invariant (precise)

> For every systemd unit `U` in the infra tree declaring `ProtectHome=(read-only|yes)` **or** `ProtectSystem=strict`, whose ExecStart chain resolves (via the association table) to repo script(s) `S`: if any `S` invokes a **config-persisting** credential action from the family table, then `S` MUST relocate that family's config directory to an **off-home** path that is within one of `U`'s `ReadWritePaths` entries (or `/mnt/data`), **or** `U` MUST list the family's home config dir in `ReadWritePaths`. Otherwise **FAIL**.

### Three mechanical stages (all fail-closed)

1. **Enumerate sandboxed units (derived, ungameable).** `grep -rnE 'ProtectHome=(read-only|yes)|ProtectSystem=strict'` over the infra root → the sandboxed-unit set. This is ground truth; the association table cannot silently omit a unit because stage 2 asserts coverage against this set.
2. **Resolve unit → in-namespace repo scripts (explicit, fail-closed association table).** A commented table in the guard maps each sandboxed unit to the repo script(s) that execute in its namespace — including the **hook/wrapper chain** for `webhook.service` (`ci-deploy-wrapper.sh` + `ci-deploy.sh`), which a naive "grep the ExecStart binary" would miss (ExecStart is `/usr/local/bin/webhook`, a binary with no repo cred source). Assertions: (i) **every** stage-1 unit appears in the table (else FAIL — new unit needs classification, satisfies the hand-maintained-allowlist scope-guard Sharp Edge); (ii) every script path in the table exists (else FAIL); (iii) optional integrity check that `hooks.json.tmpl` still routes to `ci-deploy-wrapper.sh` → `ci-deploy.sh` so the association can't silently rot.
3. **Credential-persist scan + relocation check.** For each associated script, grep the family signals; for each hit, require the family's config-dir relocation off-home into a ReadWritePath (or the home dir ∈ ReadWritePaths). Comment-strip first (drop `^\s*#` lines, per `ci-deploy.test.sh` precedent) so commented examples don't trip the scan.

### Family table (extensible)

| Family | Config-persisting signal (grep in `S`) | Relocation signal (off-home) | Default home target |
|---|---|---|---|
| docker | `docker login`, `docker … --config <path>` | `export DOCKER_CONFIG=<off-home>` (or `--config <off-home>`) | `~/.docker` |
| doppler | `doppler login`, `doppler setup`, `doppler configure`, literal `~/.doppler`/`$HOME/.doppler` write | `DOPPLER_CONFIG_DIR=<off-home>` or `--config-dir <off-home>` | `~/.doppler` |
| gh (stub) | `gh auth login` | `GH_CONFIG_DIR=<off-home>` | `~/.config/gh` |
| aws (stub) | `aws configure` | `AWS_CONFIG_FILE`/`AWS_SHARED_CREDENTIALS_FILE=<off-home>` | `~/.aws` |

**"off-home / writable"** = an absolute path not under `/home/`, `/root/`, `$HOME`, or `~`, that is either listed in `U`'s `ReadWritePaths` **or** under `/mnt/data`. (Under `ProtectSystem=strict`, a relocation must land in a `ReadWritePaths` entry to actually be writable; a bare off-home string that is not RW-covered is the M5 failure.)

### Boot-vs-sandbox discriminator (why the boot sites are GREEN by construction)

The enumeration (stage 1) keys strictly on `[Service]` stanzas carrying a `Protect*` directive. cloud-init `runcmd`/`bootcmd` items and fresh-boot bootstrap scripts are **not** `[Service]` ExecStarts, so they never enter the sandboxed-unit set and never reach stage 3. `soleur-host-bootstrap.sh` *installs* the sandboxed `vector.service` but is itself invoked un-sandboxed from `cloud-init.yml:565` runcmd — its own `docker login` lines (207/231) are boot-immune. AC4 pins this with explicit negative assertions.

### Two-file layout (mirrors canonical `scan-workflow*.test.sh` pattern)

- `credential-persist-home-guard.test.sh` — the guard. Runs stages 1-3 against `CRED_GUARD_INFRA_ROOT` (env override; default = the real `apps/web-platform/infra` derived from `${BASH_SOURCE[0]}`). GREEN on the real tree (AC2). Registered in infra-validation.yml.
- `credential-persist-home-guard-mutation.test.sh` — RED/GREEN attestation. Copies the infra tree into `mktemp -d`, applies each M1-M6 mutation, points the guard at the sandbox via `CRED_GUARD_INFRA_ROOT`, asserts RED (with `assert_mutated`/`cmp -s`); asserts pristine + boot sites GREEN (AC3-AC5). Registered in infra-validation.yml.

## Files to Create

- `apps/web-platform/infra/credential-persist-home-guard.test.sh` — the class-wide guard (stages 1-3, `CRED_GUARD_INFRA_ROOT`-parameterized).
- `apps/web-platform/infra/credential-persist-home-guard-mutation.test.sh` — the M1-M6 mutation battery + boot-immune GREEN assertions.
- `knowledge-base/project/learnings/workflow-patterns/2026-07-17-<topic>.md` — session learning (date at write time; do not pin the filename now).

## Files to Edit

- `.github/workflows/infra-validation.yml` — add two explicit `- name:`/`run: bash apps/web-platform/infra/credential-persist-home-guard*.test.sh` steps to the `deploy-script-tests` job (~lines 358-589 block), each with the `#6633` reference in the step name (house convention).

## Non-Goals

- Rewriting or removing the existing narrow guard `ci-deploy.test.sh:3517-3546` — it stays as script-specific defense-in-depth.
- Enforcing anything at runtime (this is author-time only; no systemd/host change).
- Flagging bare `doppler run` (token-based reads) — out of scope by design to avoid current-tree false positives; documented as a known limitation, extensible if a future unit adds a config-persisting doppler call.
- Static resolution of arbitrary hook/wrapper chains — the association table is explicit + fail-closed rather than a general parser.

## Open Code-Review Overlap

**Confirmed at plan time:** swept 61 open `code-review`-labelled issues (`gh issue list --label code-review --state open --json number,title,body --limit 200`) for `credential-persist`, `infra-validation.yml`, and `ci-deploy.sh` in bodies — **zero matches**. No fold-in, no double-count.

`ci-deploy.test.sh` (touches `ci-deploy.sh`, the same cred surface): **Acknowledge.** The narrow guard pins ci-deploy.sh's specific relocation (exactly-once `DOCKER_CONFIG`, no `/home/deploy`, hardened per the learning's Session Error #3); the new class-wide guard is the net for *new* units/scripts/families. Intentional overlap; the narrow guard remains open/unchanged.

## Observability (CI-gate surface)

```yaml
liveness_signal:
  what: "credential-persist-home-guard*.test.sh run as named steps in the deploy-script-tests job"
  cadence: "every PR/push that touches apps/web-platform/infra/** or .github/workflows/infra-validation.yml (infra-validation.yml triggers)"
  alert_target: "GitHub Actions required-check status on the PR (red = block merge)"
  configured_in: ".github/workflows/infra-validation.yml (deploy-script-tests job)"
error_reporting:
  destination: "GitHub Actions job log + failed check annotation on the PR"
  fail_loud: "guard exits non-zero on any FAIL; job step fails; PR check goes red (no continue-on-error)"
failure_modes:
  - mode: "new sandboxed unit adds an unrelocated home-cred write (the #6565 regression class)"
    detection: "guard stage 3 relocation check FAILs"
    alert_route: "red infra-validation check on the introducing PR"
  - mode: "guard itself goes vacuous (assertion pins line-shape, not invariant)"
    detection: "credential-persist-home-guard-mutation.test.sh drives M1-M6 and asserts RED; a vacuous guard fails the mutation attestation"
    alert_route: "red infra-validation check"
  - mode: "test file added but not registered in the explicit job list (silent-green)"
    detection: "AC1 grep + registration is a named step; both guard files must appear"
    alert_route: "review-time AC1 check; consider a registration meta-assertion at /work"
logs:
  where: "GitHub Actions run logs for the deploy-script-tests job"
  retention: "GitHub default (90 days)"
discoverability_test:
  command: "bash apps/web-platform/infra/credential-persist-home-guard.test.sh && bash apps/web-platform/infra/credential-persist-home-guard-mutation.test.sh"
  expected_output: "both exit 0; guard prints GREEN summary; mutation prints RED-on-each-M / GREEN-on-pristine attestation. No ssh, no network, no root."
```

## Gate dispositions (plan-skill phases)

- **Domain Review (2.5):** Domains relevant: **none** — infrastructure/tooling change, no Product/UX surface (no `components/**`, `app/**/page.tsx`, or UI-surface files; mechanical override does not fire). No business-domain implications.
- **IaC (2.8):** Skip — no new infrastructure provisioned; the guard *reads* existing systemd definitions, adds no server/service/secret/vendor.
- **GDPR (2.7):** Skip — no regulated-data surface (a CI lint over systemd unit text).
- **ADR/C4 (2.10):** Skip — no architectural decision. C4 completeness check: the guard introduces **no** new external human actor, external system/vendor, container/data-store, or actor↔surface access relationship — it executes only inside GitHub Actions CI and reads repo files. A future engineer reading the ADR/C4 corpus is not misled by this change.
- **Network-outage (1.4):** No trigger keyword in a diagnosis sense. Skip.
- **Plan-review:** folded into the mandated `deepen-plan` step (one-shot pipeline path) — deepen-plan spawns per-section research + precedent-diff (Phase 4.4) and domain review.

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, `TBD`, or omits the threshold fails `deepen-plan` Phase 4.6.** This plan's section is filled with a `threshold: none, reason:` scope-out bullet (required because the diff touches sensitive paths).
- **The doppler false-positive trap.** Flagging bare `doppler run` would turn the current tree RED (the redis/inngest/vector units all run `doppler run` under `ProtectHome=read-only` with tokens and no home write). The guard's doppler family signal is deliberately scoped to config-persisting subcommands (`login`/`setup`/`configure`) + literal `~/.doppler` writes. Do not broaden it to bare `doppler run` without also proving the current tree stays GREEN.
- **The vacuous-guard trap (the whole reason this issue exists).** Per the learning's Session Error #3, knowing about vacuous guards does not immunize your own — an independent adversarial mutation pass is non-optional. Every AC2/AC3 invariant must be mutation-proven RED on a `mktemp -d` copy, gated by `assert_mutated`/`cmp -s`. A guard whose deletion/inversion leaves the suite green pins nothing.
- **Silent-green registration.** `infra-validation.yml`'s `deploy-script-tests` job is an explicit hardcoded list, not a glob. A test file that exists but is not registered gates nothing (`infra-validation.yml:452-455`, #3366/#6520). AC1 asserts both files are registered; consider a registration meta-assertion at /work.
- **ExecStart is a binary, not a script, for webhook.service.** `ExecStart=/usr/local/bin/webhook …`; the cred logic is reached via `hooks.json` → `ci-deploy-wrapper.sh` → `ci-deploy.sh`. The association table encodes this; a naive ExecStart-grep would find nothing and silently pass. Keep the association fail-closed and (optionally) assert the hook chain is intact.
- **Two webhook.service copies.** `webhook.service` and the inline `cloud-init.yml:231-266` copy must both be scanned (they are pinned to lockstep by `inngest.test.sh:645-655`). The guard's enumeration naturally picks up both; the association table must map both to the ci-deploy chain.
- **Cite content anchors, not line numbers, in the guard/tests** (`cq-cite-content-anchor-not-line-number`) — line numbers in `ci-deploy.sh`/`cloud-init.yml` drift; grep for anchors like `DEPLOY_DOCKER_CONFIG_DIR:-/mnt/data/` and `ProtectHome=read-only`.

## Test Scenarios

Covered by AC2 (GREEN on real tree), AC3 (M1-M6 RED), AC4 (boot sites GREEN), AC5 (fail-closed on unknown unit). No production/integration test against prod (author-time bash only; `hr-dev-prd-distinct-supabase-projects` not implicated).
