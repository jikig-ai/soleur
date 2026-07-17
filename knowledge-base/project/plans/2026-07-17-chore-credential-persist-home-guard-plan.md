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

## Enhancement Summary (Deepened 2026-07-17)

**Deepened via 3 parallel agents:** test-design-reviewer, code-simplicity-reviewer, and a bash/systemd-parsing research pass. Their findings are load-bearing and are folded into the AC / Design / Mutation-battery sections below. Net effect: **simpler scaffolding, stronger invariant** — the complexity moved off peripheral apparatus and onto the anti-vacuity core.

### Key revisions applied
1. **Collapse to ONE file** (simplicity P-verdict). The two-file split (`guard` + `-mutation`) copied the wrong precedent: `scan-workflow-mutation.test.sh` isolates a *guard-pipeline meta-failure* (a `pipefail`+SIGPIPE inversion) — a genuinely separate subject. Here, M1-M8 are just the guard's ordinary RED-on-bad-input cases and belong beside the GREEN-on-good-input cases, exactly as `ci-deploy.test.sh` (same cred surface) does inline. One file → one CI registration → one preamble. The guard stays `CRED_GUARD_INFRA_ROOT`-parameterized; M-cases loop a `run_guard_expect_red()` helper over `mktemp -d` copies.
2. **P0 F1 — resolve one level of `${VAR:-default}`/`$VAR` indirection.** The real relocation (`ci-deploy.sh:73-74`) never puts the literal off-home path on the `export DOCKER_CONFIG=` line; it assigns `"$DEPLOY_DOCKER_CONFIG_DIR"` whose value is the `:-/mnt/data/deploy-docker` default one line up. A guard that only pins "DOCKER_CONFIG is assigned *something*" rubber-stamps a one-char evasion (flip the `:-` default to `$HOME/.docker`). Add **M7** (indirect-default-home → RED) + **M7b** (unresolvable/unset var → **FAIL**, fail-closed — also covers `$XDG_CONFIG_HOME` redirection).
3. **P0 F5 — in-guard non-empty-scan census (the anti-vacuity positive control).** AC2 GREEN can pass *vacuously* if comment-strip over-strips (there are ~20 commented `docker login` mentions vs the one real call at `ci-deploy.sh:990` inside `_docker_login_capture --password-stdin`), an anchor drifts, or association resolution returns empty. The guard MUST assert `CRED_SITES_DETECTED >= 1` and name the known `webhook.service → ci-deploy.sh` docker site as scanned+classified — converting "found nothing ⇒ green" into "found nothing ⇒ RED". New **AC8**.
4. **P1 F2 — `-` optional-path prefix + drop the `/mnt/data` blanket-allow.** `webhook.service:48` `ReadWritePaths` uses `-/var/lib/inngest -/var/lib/vector -/etc/vector`. Strip exactly one leading `-` before evaluating a token (else `-$HOME/.docker` escapes the "home ∈ RWP" check AND a valid relocation into a `-`-prefixed RW dir false-positives). Drop the unsound "off-home OR under /mnt/data" clause: under `ProtectSystem=strict`, `/mnt/data` is writable only if it is itself an RWP entry — require RW-membership. Add **M5b** (relocation to `/mnt/data/creds` while RWP omits `/mnt/data` → RED) + GREEN fixture (relocation into a `-`-prefixed RW entry).
5. **P1 F3/F4 — detect-form parity + heredoc-inline.** Add **M3b** (`--config=$HOME/.docker` equals-form → RED), **M3c** (`DOCKER_CONFIG="$HOME/.docker" docker login` inline-env, no `export` → RED), GREEN controls for the inline/`=` off-home forms, and **M8** (a heredoc-defined sandboxed unit whose `ExecStart` contains an inline `docker login` with no separate script → RED or fail-closed — the file-based association table would otherwise resolve to empty and skip it).
6. **P1 F6 — attribute each RED to its mutation.** `cmp -s`/`assert_mutated` only proves the mutation *landed*, not that it *caused* the RED (a pre-existing latent FAIL makes every M RED and the battery passes for the wrong reason). Fix: **fresh non-cumulative copy per mutation**, assert **GREEN-before-mutation per fixture** (per-mutation baseline, not just one global pristine check), and a **finding-text positive control** — after each mutation, `grep -qF <mutated-site>` the guard's output so the RED is attributed to the mutated unit/script.
7. **Simplicity trims.** Drop the stage-2(iii) "hooks.json still routes to ci-deploy-wrapper.sh" integrity check — already pinned by `inngest.test.sh:645-655`. Flatten the association table to `unit → {script | NONE}` (only `webhook` maps to a script; the 4 `doppler run` units map to `NONE`, their value being fail-closed enumeration coverage). Reframe AC6/gh+aws (see below).
8. **P2 F7 — doppler anchor precision.** Tighten the doppler *write* signal to `doppler login|setup|configure set|configure token` and explicitly EXCLUDE `configure get|debug` (`apps/cla-evidence/infra/bootstrap.sh:79` runs `doppler configure get token`, a read). Keep the "bare `doppler run` under ProtectHome stays GREEN" case as an **explicit named regression pin** (synthetic fixture), not merely implicit in AC2.

## Research Insights (deepen-plan)

### Bash/systemd parsing traps the guard MUST avoid (3-shape extraction)
Units are defined in THREE shapes, and a single extractor silently under-scans:
- **`.service` standalone** — whole file is one unit block.
- **`.sh` heredoc** (`inngest-bootstrap.sh`, `soleur-host-bootstrap.sh`) — use the **backreference-terminated** idiom from `inngest.test.sh:176-217`: `cat > "?$\{?(\w+)\}?"? <<'?(\w+EOF)'? \n(.*?)\n\2` with `re.S`+`re.M`; `\2` pins the closing marker so adjacent heredocs don't bleed; tolerate quoted+unquoted markers; `if '[Service]' not in body: continue`.
- **cloud-init `write_files: … content: |`** — units are **indented YAML block-scalar text, NOT heredocs**; a `cat >`/heredoc regex finds **ZERO** units here → the non-vacuous-zero false-green. Range on `^[[:space:]]*`-anchored per-line directives (as `inngest.test.sh:645/653`), not a `cat >` marker.
- **Mandatory non-vacuity count** (`inngest.test.sh:199-217`): after enumerating, assert the sandboxed-unit count `>= 5` (and the cred-site census `>= 1`, AC8). "A regex that matches nothing reports zero violators and passes forever — the exact false-green this guard exists to prevent."
- **RWP count-then-`head -1`** (`inngest.test.sh:639-666`): systemd *accumulates* `ReadWritePaths=` lines, so assert exactly-one line before trusting `head -1`; a removed line must FAIL under `set -e`, not pass.
- **`$${…}` templatefile doubling** (`2026-07-14-cloud-init-templatefile-escaping…` learning): `cloud-init.yml` is a Terraform `templatefile()` — shell `${VAR}` is written `$${VAR}` in source (e.g. `inngest-bootstrap.sh:523` `$${INNGEST_SIGNING_KEY#…}`). The ExecStart/path parser must match the correct source-vs-rendered `$` form; brace-free `$stage`/`$?` pass through unescaped. Endorsed idiom: source-scoped `awk '/^start/,/^end/'` range + tight paired greps against the extracted `$body`.

### Precedent-diff (Phase 4.4)
The guard is pattern-bound and its precedents exist and are mirrored: parsing/anti-vacuity idioms from `inngest.test.sh:176-217,639-666`; the single-file cred-guard invariant style from `ci-deploy.test.sh:3517-3546`; `mktemp -d`+`trap`+override-seam from `scan-workflow-mutation.test.sh` / `inngest-rls-mutation.test.sh`. No novel pattern.

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

- [x] **AC1 — Guard exists & is registered.** A single guard `apps/web-platform/infra/credential-persist-home-guard.test.sh` (GREEN cases + the M1-M8 RED loop inline — one file, per the deepen collapse decision) exists and is added as an explicit `- name:`/`run: bash …` step in the `deploy-script-tests` job of `.github/workflows/infra-validation.yml` (the job is an explicit hardcoded list — an unregistered test "gates NOTHING and fails silently green", `infra-validation.yml:452-455`). Verify: `grep -c 'credential-persist-home-guard' .github/workflows/infra-validation.yml` ≥ 1.
- [x] **AC2 — Current tree GREEN.** `bash apps/web-platform/infra/credential-persist-home-guard.test.sh` exits 0 against the real infra tree (ci-deploy.sh's relocated docker write passes; the four token-`doppler run` units pass; no false positive).
- [x] **AC3 — Mutation-proven RED (the anti-vacuity battery).** The guard's inline `run_guard_expect_red()` loop independently drives the guard **RED** on each mutation below. Each is applied to a **fresh, non-cumulative** `mktemp -d` copy (`cq-test-fixtures-synthesized-only`), the fresh copy is asserted **GREEN before mutation** (per-mutation baseline), the mutation landing is gated by `assert_mutated`/`cmp -s`, AND the guard's finding output is `grep -qF`'d for the mutated unit/script so the RED is **attributed** to the mutation (F6 — not a pre-existing latent FAIL):
  - **M1** — `export DOCKER_CONFIG="$HOME/.docker"` (relocation points **back** to home — the sneaky dual-false-PASS case from the learning).
  - **M2** — `docker login` with **no** `DOCKER_CONFIG` relocation (bare default `~/.docker`).
  - **M3 / M3b / M3c** — `docker … --config "$HOME/.docker"` (space form) / `--config=$HOME/.docker` (equals form) / `DOCKER_CONFIG="$HOME/.docker" docker login` (inline-env prefix, no `export`) → all RED (detect-form parity).
  - **M4** — a **new** sandboxed unit whose ExecStart script runs `doppler login`/`doppler setup`/`doppler configure set` (or writes `~/.doppler`) with no relocation → class-wide coverage beyond docker.
  - **M5 / M5b** — relocation onto an off-home path **not** in `ReadWritePaths` (e.g. `/opt/creds`) under `ProtectSystem=strict` / relocation onto `/mnt/data/creds` while the unit's `ReadWritePaths` **omits** `/mnt/data` → both RED (RW-membership check; the old blanket `/mnt/data`-allow is dropped).
  - **M6** — deleting `ci-deploy.sh`'s real `DOCKER_CONFIG` export/indirection (re-introduces the exact #6565 shape) → RED.
  - **M7 / M7b** — flip `ci-deploy.sh:73`'s `${DEPLOY_DOCKER_CONFIG_DIR:-/mnt/data/deploy-docker}` default to `$HOME/.docker` (export line unchanged) → RED (proves the guard resolves one level of `${VAR:-default}` indirection) / `export DOCKER_CONFIG="$SOME_UNSET_VAR"` with no in-script assignment → **FAIL** fail-closed (covers `$XDG_CONFIG_HOME` redirection).
  - **M8** — a heredoc-defined `ProtectHome=read-only` unit whose `ExecStart` contains an inline `docker login` (no separate repo script) → RED, either by scanning the inline ExecStart text or fail-closed ("sandboxed unit resolves to no script yet its ExecStart contains a family cred action").
- [x] **AC4 — Boot-immune sites stay GREEN (no false positives).** The guard emits **zero** finding for `cloud-init.yml:491/499/512`, `cloud-init-inngest.yml:260`, and `soleur-host-bootstrap.sh:207/231` — even though they contain `docker login` — because none is inside a `[Service]` stanza carrying a `Protect*` directive. Includes an explicit **boot false-positive probe** (inject an un-relocated `docker login` into a `runcmd:` block of a fixture copy → guard stays GREEN) and an **explicit named regression pin** that bare `doppler run` under `ProtectHome` stays GREEN (guards the redis/inngest/vector current-tree FP).
- [x] **AC5 — Fail-closed enumeration.** The guard goes RED when a **new** `ProtectHome=read-only` unit is not covered by the unit→`{script|NONE}` association table (unknown sandboxed unit ⇒ FAIL, never silent-skip), verified by injecting a novel sandboxed unit into a fixture copy; and the enumeration carries a non-vacuity **count assert** (sandboxed-unit count ≥ 5, `inngest.test.sh:199-217` precedent) so a parser that matches nothing cannot pass forever.
- [x] **AC6 — Family extensibility (docker + doppler live; gh/aws/generic documented).** The guard covers docker (`~/.docker`, resolving one level of `${VAR:-default}`/`$VAR` indirection) and doppler (`~/.doppler`; write subcommands `login|setup|configure set|configure token` only — NOT `configure get`/bare `doppler run`). The family table is structured so `gh` (`GH_CONFIG_DIR`/`~/.config/gh`), `aws` (`AWS_CONFIG_FILE`/`~/.aws`), and generic `~/.config` are a **documented one-row extension point** — not shipped as executable stubs (zero occurrences in the tree today; adding a row when the family appears is also one line, and gets a real fixture then).
- [x] **AC7 — House-style conformance.** The single file: `#!/usr/bin/env bash` + `set -euo pipefail`, `SCRIPT_DIR` via `${BASH_SOURCE[0]}`, `CRED_GUARD_INFRA_ROOT` override (default = real infra dir), inline helpers (no shared lib), pass/fail counters, non-zero exit on any failure, `mktemp -d` + cleanup `trap` for the M-loop fixtures. Self-contained bash; no network/root/docker/terraform required.
- [x] **AC8 — In-guard non-empty-scan census (anti-vacuity positive control).** On the real tree the guard asserts `CRED_SITES_DETECTED ≥ 1` and explicitly names `webhook.service → ci-deploy.sh` as a **detected, relocated** docker site — so an over-strip (the ~20 commented `docker login` mentions vs the one real call at `ci-deploy.sh:990`), anchor drift, or empty association resolution makes the guard **RED**, never a vacuous GREEN. This is the F5 gap the M-battery alone does not close (M6 lives in the loop; AC2 in isolation must not pass for the wrong reason).

## Design

### Guard invariant (precise)

> For every systemd unit `U` in the infra tree declaring `ProtectHome=(read-only|yes)` **or** `ProtectSystem=strict`, whose ExecStart chain resolves (via the association table) to repo script(s) `S`: if any `S` invokes a **config-persisting** credential action from the family table, then `S` MUST relocate that family's config directory to an **off-home** path that is within one of `U`'s `ReadWritePaths` entries (or `/mnt/data`), **or** `U` MUST list the family's home config dir in `ReadWritePaths`. Otherwise **FAIL**.

### Three mechanical stages (all fail-closed)

1. **Enumerate sandboxed units (derived, ungameable) — 3-shape extractor + count assert.** Enumerate `[Service]` blocks declaring `ProtectHome=(read-only|yes)`/`ProtectSystem=strict` across the infra root using the three shape-specific extractors (`.service` whole-file; `.sh` heredoc backreference-marker per `inngest.test.sh:176-217`; cloud-init `write_files: content: |` indented block-scalar — a `cat >` regex finds ZERO there). Assert the sandboxed-unit **count ≥ 5** (`inngest.test.sh:199-217` non-vacuity precedent) so a broken extractor can't false-green. This is ground truth; the flat association map asserts coverage against it.
2. **Resolve unit → `{script | NONE}` (explicit, fail-closed, flat map).** A commented flat map: `webhook.service → ci-deploy.sh` (+ `ci-deploy-wrapper.sh`) — the hook/wrapper chain a naive "grep the ExecStart binary" misses (ExecStart is `/usr/local/bin/webhook`, a binary); the four `doppler run` units → `NONE` (token read, no cred surface — their entry exists only to make enumeration fail-closed). Assertions: (i) **every** stage-1 unit appears in the map (else FAIL — new unit needs classification); (ii) every mapped script path exists (else FAIL). *(The stage-2(iii) "hooks.json still routes to ci-deploy-wrapper.sh" integrity check is dropped — already pinned by `inngest.test.sh:645-655`.)*
3. **Credential-persist scan + relocation check + census.** For each mapped script (and any inline-ExecStart cred action, M8), comment-strip (`^\s*#`, per `ci-deploy.test.sh`) so the ~20 commented `docker login` mentions don't trip the scan; grep the family signals; for each hit require the family's config-dir relocation off-home into an RWP entry (indirection resolved one level; `-`-prefix stripped), or the home dir ∈ RWP, else FAIL. **Census (AC8):** assert `CRED_SITES_DETECTED ≥ 1` and that `webhook.service → ci-deploy.sh` was classified as detected+relocated — so an over-strip / anchor-drift / empty-resolution yields RED, not a vacuous GREEN.

### Family table (extensible)

| Family | Config-persisting signal (grep in `S`) | Relocation signal (off-home) | Default home target |
|---|---|---|---|
| docker (live) | `docker login`; `docker … --config <path>` / `--config=<path>`; inline-env `DOCKER_CONFIG=<path> docker …` | `DOCKER_CONFIG=<off-home>` (via `export`, in-script `${VAR:-default}`/`$VAR` **indirection resolved one level**, or inline-env), or `--config <off-home>`/`--config=<off-home>`; OR `~/.docker` ∈ `ReadWritePaths` | `~/.docker` |
| doppler (live scoping) | `doppler login`, `doppler setup`, `doppler configure set`, `doppler configure token`, literal `~/.doppler`/`$HOME/.doppler` write. **EXCLUDE** `doppler configure get\|debug` (reads) and bare `doppler run` (token read — flagging it turns the current tree RED). | `DOPPLER_CONFIG_DIR=<off-home>` or `--config-dir <off-home>` | `~/.doppler` |
| gh / aws / generic `~/.config` | *(documented extension point — one-row addition when a matching invocation first appears; NOT shipped as executable stubs, zero occurrences today)* | `GH_CONFIG_DIR` / `AWS_CONFIG_FILE` / relocate the specific path | `~/.config/gh`, `~/.aws`, `~/.config/**` |

**"off-home / writable"** = an absolute path not under `/home/`, `/root/`, `$HOME`, or `~`, that is **contained in one of `U`'s `ReadWritePaths` entries** (after stripping exactly one leading `-` ignore-if-absent prefix from each RWP token — `webhook.service:48` uses `-/var/lib/inngest` etc.). The old "OR under `/mnt/data`" blanket-allow is **dropped**: under `ProtectSystem=strict`, `/mnt/data` is writable only if it is itself an RWP entry (M5b). A relocation whose resolved *value* falls under `$HOME`/`~`/`/home`/`/root` is NOT a relocation (M1/M7); an unresolvable relocation target is fail-closed FAIL (M7b).

### Boot-vs-sandbox discriminator (why the boot sites are GREEN by construction)

The enumeration (stage 1) keys strictly on `[Service]` stanzas carrying a `Protect*` directive. cloud-init `runcmd`/`bootcmd` items and fresh-boot bootstrap scripts are **not** `[Service]` ExecStarts, so they never enter the sandboxed-unit set and never reach stage 3. `soleur-host-bootstrap.sh` *installs* the sandboxed `vector.service` but is itself invoked un-sandboxed from `cloud-init.yml:565` runcmd — its own `docker login` lines (207/231) are boot-immune. AC4 pins this with explicit negative assertions.

### Single-file layout (mirrors `ci-deploy.test.sh` inline-invariant pattern — deepen collapse decision)

- `credential-persist-home-guard.test.sh` — one file. Runs stages 1-3 against `CRED_GUARD_INFRA_ROOT` (env override; default = the real `apps/web-platform/infra` from `${BASH_SOURCE[0]}`) → GREEN on the real tree + census (AC2/AC8). Then an inline `run_guard_expect_red()` loop over M1-M8 (each a fresh non-cumulative `mktemp -d` copy, asserted GREEN-before-mutation, `assert_mutated` on landing, finding-text `grep -qF` attribution) + the boot false-positive / bare-`doppler run` GREEN pins (AC3-AC5). **Rejected** the two-file `scan-workflow*.test.sh` split: that split isolates a guard-pipeline *meta-failure* (pipefail+SIGPIPE), a separate subject; here the RED cases are the guard's ordinary test cases and belong beside the GREEN cases. One file = one `infra-validation.yml` registration = no silent-un-gating surface.

## Files to Create

- `apps/web-platform/infra/credential-persist-home-guard.test.sh` — the **single** class-wide guard: stages 1-3 (`CRED_GUARD_INFRA_ROOT`-parameterized) + census (AC8) + inline M1-M8 `run_guard_expect_red` loop + boot/bare-doppler GREEN pins. (Deepen collapse — no separate mutation file.)
- `knowledge-base/project/learnings/workflow-patterns/2026-07-<dd>-<topic>.md` — session learning (date at write time; do not pin the filename now).

## Files to Edit

- `.github/workflows/infra-validation.yml` — add **one** explicit `- name:`/`run: bash apps/web-platform/infra/credential-persist-home-guard.test.sh` step to the `deploy-script-tests` job (append after `git-data-transport-wrapper.test.sh`, ~`:589`), with the `#6633` reference in the step name (house convention).

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
  - mode: "guard itself goes vacuous (line-shape pin, over-strip, empty resolution → GREEN-on-broken)"
    detection: "inline M1-M8 RED loop + the AC8 census (CRED_SITES_DETECTED >= 1, ci-deploy.sh named) — a vacuous guard fails its own attestation in the same run"
    alert_route: "red infra-validation check"
  - mode: "test file added but not registered in the explicit job list (silent-green)"
    detection: "AC1 grep + registration is a named step; the guard file must appear"
    alert_route: "review-time AC1 check; consider a registration meta-assertion at /work"
logs:
  where: "GitHub Actions run logs for the deploy-script-tests job"
  retention: "GitHub default (90 days)"
discoverability_test:
  command: "grep -c credential-persist-home-guard .github/workflows/infra-validation.yml"
  expected_output: "1"
  note: "Author-time CI gate — the liveness signal is 'the guard is REGISTERED as a named step and will run on every infra PR' (an unregistered infra test gates nothing, #3366/#6520). The full battery + census + M1-M8 RED attestation runs via `bash apps/web-platform/infra/credential-persist-home-guard.test.sh` (exit 0, PASS=28 FAIL=0)."
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
- **The doppler false-positive trap.** Flagging bare `doppler run` would turn the current tree RED (redis/inngest/vector all run `doppler run` under `ProtectHome=read-only` with tokens, no home write). Scope the doppler signal to WRITE subcommands (`login`/`setup`/`configure set`/`configure token`) + literal `~/.doppler` writes, and EXCLUDE `configure get`/`configure debug` (reads — `apps/cla-evidence/infra/bootstrap.sh:79` runs `doppler configure get token`). Ship the "bare `doppler run` under ProtectHome stays GREEN" case as an explicit named regression pin, not merely implicit in AC2.
- **The vacuous-guard trap (the whole reason this issue exists).** Per the learning's Session Error #3, knowing about vacuous guards does not immunize your own. Every M1-M8 invariant must be mutation-proven RED on a **fresh** `mktemp -d` copy, asserted GREEN-before-mutation, gated by `assert_mutated`/`cmp -s`, AND finding-text-attributed (`grep -qF <mutated-site>` the guard output) so the RED is caused by the mutation, not a pre-existing latent FAIL (F6). Plus the AC8 census (`CRED_SITES_DETECTED >= 1`, ci-deploy.sh named) so a green run cannot mean "scanned nothing".
- **The relocation is a two-line `${VAR:-default}` indirection, not a literal.** `ci-deploy.sh:73-74` assigns `DOCKER_CONFIG="$DEPLOY_DOCKER_CONFIG_DIR"` whose value is the `:-/mnt/data/deploy-docker` default one line up — the off-home literal is never on the `export` line. Pinning "DOCKER_CONFIG is assigned something" rubber-stamps a one-char evasion (flip the `:-` default to `$HOME`). Resolve one level of `${VAR:-default}`/`$VAR`; unresolvable target ⇒ fail-closed (M7/M7b).
- **The `-` ignore-if-absent RWP prefix + the dropped `/mnt/data` blanket-allow.** `webhook.service:48` RWP uses `-/var/lib/inngest` etc. Strip exactly one leading `-` before evaluating an RWP token (else `-$HOME/.docker` escapes the "home ∈ RWP" check and a valid `-`-prefixed relocation false-positives). Do NOT blanket-allow `/mnt/data`: under `ProtectSystem=strict` it is writable only if it is an RWP entry (M5b).
- **The 3-shape extractor + non-vacuous-zero.** Units live in `.service` files, `.sh` heredocs, AND cloud-init `write_files: content: |` block-scalars. A `cat >`/heredoc regex finds ZERO units in cloud-init → a silent false-green. Use shape-specific extractors (heredoc backreference-marker per `inngest.test.sh:176-217`; `^[[:space:]]*`-anchored per-line for `.yml`/`.service`) + a count assert (≥5 units). Mind `$${…}` templatefile doubling in cloud-init source (Terraform `templatefile()` — source shows `$$`, host sees `$`).
- **Silent-green registration.** `infra-validation.yml`'s `deploy-script-tests` job is an explicit hardcoded list, not a glob. An unregistered test gates nothing (`infra-validation.yml:452-455`, #3366/#6520). AC1 asserts the guard file is registered; consider a registration meta-assertion at /work.
- **ExecStart is a binary, not a script, for webhook.service.** `ExecStart=/usr/local/bin/webhook …`; the cred logic is reached via `hooks.json` → `ci-deploy-wrapper.sh` → `ci-deploy.sh`. The flat `{script|NONE}` map encodes this; a naive ExecStart-grep finds nothing and silently passes. Keep the map fail-closed. (Do NOT re-add a hooks.json-routing integrity check — already pinned by `inngest.test.sh:645-655`.)
- **Two webhook.service copies.** `webhook.service` and the inline `cloud-init.yml:231-266` copy must both be enumerated (pinned to lockstep by `inngest.test.sh:645-655`).
- **Cite content anchors, not line numbers, in the guard/tests** (`cq-cite-content-anchor-not-line-number`) — line numbers in `ci-deploy.sh`/`cloud-init.yml` drift; grep for anchors like `DEPLOY_DOCKER_CONFIG_DIR:-/mnt/data/` and `ProtectHome=read-only`.

## Test Scenarios

Covered by AC2 (GREEN on real tree), AC8 (non-empty-scan census), AC3 (M1-M8 + M3b/M3c/M5b/M7b RED, each fresh-copy + finding-text-attributed), AC4 (boot sites GREEN + bare-`doppler run` pin), AC5 (fail-closed on unknown unit + count assert ≥5). No production/integration test against prod (author-time bash only; `hr-dev-prd-distinct-supabase-projects` not implicated).
