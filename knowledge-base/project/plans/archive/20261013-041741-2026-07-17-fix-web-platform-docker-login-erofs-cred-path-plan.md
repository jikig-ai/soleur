---
title: "fix: web-platform docker-login EROFS — relocate deploy-user DOCKER_CONFIG off ProtectHome"
issue: 6565
refs: [6497]
lane: single-domain
brand_survival_threshold: aggregate pattern
type: bug-fix
classification: infra-code-change
created: 2026-07-17
branch: feat-one-shot-6497-docker-login-readonly-cred
---

# fix: web-platform `docker login` fails at credential-persist (EROFS) on both deploy hosts

🐛 **P1** — `ci-deploy.sh`'s `docker login` (GHCR prelude + zot gate) authenticates, then **fails to save credentials** because it writes to `$HOME/.docker/` (`/home/deploy/.docker/config.json`), which sits under `ProtectHome=read-only` and is **not** in `webhook.service`'s `ReadWritePaths=` → `EROFS`. Systemic across **both** web hosts (a static, shared unit directive), independent of host age.

## Enhancement Summary

**Deepened on:** 2026-07-17 (one-shot pipeline: plan → 6-agent plan-review applied → deepen-plan)

**Key improvements folded in (plan-review, all Mechanical):** fix mechanism confirmed sound by architecture-strategist deep-trace; Phase 0 reframed to the one unmeasured link (`docker login` honors `DOCKER_CONFIG`); `GHCR_DOCKER_CONFIG` derived from exported `DOCKER_CONFIG` (single source of truth); tests collapsed to two load-bearing invariants with anchored greps; **repair retargeted to #6565** (not the instrument's #6497); **per-host_id soak PASS + forced-deploy Phase 4** (the close loop was previously unreachable).

**Deepen-plan gates run:** 4.6 User-Brand Impact ✓ (threshold `aggregate pattern`), 4.7 Observability ✓ (5 fields, no-ssh), 4.8 PAT-shaped ✓ (none), 4.9 UI-wireframe ✓ (no UI surface — skip), 4.4 precedent-diff ✓ (ProtectHome-relocate), 4.5 Network-Outage Deep-Dive (fired — see Hypotheses), 4.55 Downtime & Cutover (fired — see section).

**New considerations surfaced by the deepen gates:** (a) the delivery apply (`apply-deploy-pipeline-fix.yml` → `terraform_data.deploy_pipeline_fix`) carries an apply-time **SSH-provisioner dependency** (`server.tf:273-528` `connection{}`+`provisioner`), so the operator egress-IP must be in `hcloud_firewall.web`'s SSH allowlist at apply time (cross-ref #3061); (b) the web-2 `-replace` is a **warm-standby (drained, non-serving) recreate** — zero-downtime for users, and web-1 is never power-cycled (hot-push), so no serving surface goes offline.

## Overview

The 2026-07-16 login-gate instrument (PR #6528) emitted the discriminating datum from live Better Stack telemetry (12h, 55 failed-login lines, zero `class=unclassified`):

```
class=cred_store  rc=1  stderr_chars=~96-97  stdout_chars=0  kw=errsaving  docker_ver=29.3.0
errno_chars=22    kw=errsaving,erofs
```

Decoded: **`docker login` AUTHENTICATES, then the credential-PERSIST step fails with Docker's "error saving credentials" on a READ-ONLY FILESYSTEM (EROFS).** Not empty-stderr H-B (`stderr_chars>0`), not disk-full (`kw` would be `nospace`), not a missing `credsStore` helper (`kw` would be `execnotfound`).

This is **the fix**, not a diagnosis. The measured mechanism, traced to exact lines on `main` (no SSH):

- `apps/web-platform/infra/ci-deploy.sh:69` → `GHCR_DOCKER_CONFIG` defaults to `/home/deploy/.docker/config.json`. `docker login` (via `_docker_login_capture`, `ci-deploy.sh:950`, no `--config` flag) writes to `$HOME/.docker/` = the same `/home/deploy/.docker` path (deploy user, `HOME=/home/deploy`).
- `apps/web-platform/infra/cloud-init.yml:250-251` sets `ProtectSystem=strict` + `ProtectHome=read-only` on `webhook.service`, which runs `ci-deploy.sh` as `User=deploy`. Its `ReadWritePaths=` (`cloud-init.yml:264`, and the lockstep standalone copy at `webhook.service:48`) is `/mnt/data /var/lock /etc/systemd/system /etc/default /etc/sudoers.d /etc/webhook -/var/lib/inngest -/var/lib/vector -/etc/vector /usr/local/bin` — it does **not** include `/home/deploy/.docker`. The unit's own comment (`cloud-init.yml:255-257`) notes `sudo` cannot escape the mount namespace, so the write to the docker config path hits the read-only `/home` mount → **EROFS**.
- `docker pull` survives today because the app image is authenticated-pulled at **boot** by the un-sandboxed cloud-init `runcmd` (`cloud-init.yml:487/495/508`, running as **root** → writes `/root/.docker`, un-sandboxed) and the digest is then cached locally. This is a **LATENT trap**: fine off the baked/cached cred, broken on the next rotation or fresh boot that needs a *working* `docker login` (exactly the redundancy ADR-096 exists to provide — see #6400/#6408, GHCR degradations where a working zot would have served the pull).

**The fix relocates the deploy-user docker config off `ProtectHome` onto `/mnt/data`** (already a `ReadWritePath`, already mounted), via a single exported `DOCKER_CONFIG` in `ci-deploy.sh`. This is the established codebase pattern for `ProtectHome=read-only` + a home config-dir write (learning `2026-04-06-doppler-protecthome-readonly-config-dir-fix.md`, which explicitly names `~/.docker` and argues **against** punching a home write-hole). It touches **one file** (+ its test + a soak), needs **no** systemd/cloud-init change, and **hot-reaches web-1 without a power-off**.

## Premise Validation — Spec vs. Codebase (Phase 0.6)

The cited issue #6497 and its own root-cause hypothesis were validated against `origin/main` and live telemetry. Two of the issue's premises are **stale / superseded** and the plan re-scopes accordingly.

| Cited premise (issue #6497 body) | Reality (measured) | Plan response |
| --- | --- | --- |
| Root cause is **zot `/etc/zot/htpasswd` per-entry stale-bake** on the **registry** host; fix is `lifecycle.replace_triggered_by` on `random_password.zot_{pull,push}` + `depends_on` (Phase 2) | **Falsified by the instrument.** Uniform `class=cred_store kw=errsaving,erofs` proves a **client-side credential-PERSIST EROFS on the web hosts**, before any registry request. The 2026-07-16 08:15Z htpasswd re-bake converged both users while `login_failed` continued → htpasswd falsified. | This plan implements the **EROFS repair** on the web hosts. The zot-htpasswd `replace_triggered_by` work (registry host) is a **separate concern**, out of scope here; not re-litigated. |
| Host attribution centered on the **registry** host / framed around a single degraded host | The failure is a **static shared `webhook.service` directive** → **both** web hosts (web-1 + web-2), **systemic**, **independent of host age**. | Plan explicitly corrects attribution to **both web hosts, systemic**. Close criterion asserts zero FAILED lines on the fleet (uses the `host_id` beacon field). |
| Issue Phase 1 (classify login stderr → enum + `host_id` beacon) is future work | **Already shipped** (PR #6484/#6528 + the errno round). The `class`/`kw`/`errno_chars`/`stderr_chars`/`stdout_chars`/`tok` vocabulary is live (`ci-deploy.sh` › `_login_kw`,`_login_hatch`). | Plan **consumes** the instrument; does not re-build it. The existing instrument soak `zot-login-gate-names-failure-6497.sh` (enrolled `earliest=2026-07-18`) is the *instrument's* close criterion — this fix adds its **own** repair soak (below). |

No repo capability claims were bounded from memory: the delivery paths (`apply-deploy-pipeline-fix.yml`, `infra-config-apply.sh`, `web-2-recreate` dispatch), the ReadWritePaths lines, and `/mnt/data`'s mount were all read from the tree (citations throughout).

## Research Reconciliation — Spec vs. Codebase

| Assumption in ARGUMENTS | Codebase reality | Impact on plan |
| --- | --- | --- |
| Option 1 = "minimal, same-shape-as-existing-entries" (add `/home/deploy/.docker` to `ReadWritePaths`) | The `ReadWritePaths` line is duplicated in **two** lockstep files (`cloud-init.yml:264` + standalone `webhook.service:48`). `/home/deploy/.docker` **does not exist** on a fresh host (deploy user created via cloud-init `users:` block `cloud-init.yml:46-53`, which makes `/home/deploy` but **not** `.docker`). A **hard** ReadWritePath on an absent dir → `226/NAMESPACE` (webhook.service fails to start = deploy listener DOWN). A `-`-prefixed optional path leaves it **read-only** → still EROFS. So Option 1 additionally needs a **boot `mkdir -p /home/deploy/.docker && chown deploy`** and edits **both** unit copies. | Option 1 is **not** a one-line same-shape change; it is 3 coordinated edits with a brick-risk on the hot-push path. Recommendation shifts to **Option 2** (see Fix Evaluation). Divergence recorded in `decision-challenges.md`. |
| Option 2 must "check the cosign-verifier `:ro` mount and the boot-bake path both reference the same location" | Cosign mount uses `$GHCR_DOCKER_CONFIG` (`ci-deploy.sh:1513` → `-v "$GHCR_DOCKER_CONFIG:/root/.docker/config.json:ro"`); the zot second auths entry is written into the same `$GHCR_DOCKER_CONFIG` (`ci-deploy.sh:1298-1309`, `zot_gate_and_login`). **All** `docker login` sites use the default HOME path (no `--config`), so `$GHCR_DOCKER_CONFIG` MUST point at the config under `$HOME/.docker/` for the mount to carry the auths. The boot-bake is a **separate** root/`/root/.docker` lifecycle (un-sandboxed), not the deploy-user path. | Option 2 sets one **exported** `DOCKER_CONFIG` → all login sites + cosign mount stay consistent automatically via `$GHCR_DOCKER_CONFIG`. Boot-bake is **untouched** (documented scope boundary). |
| "Extend `ci-deploy.test.sh`" | The harness loads `ci-deploy.sh` as sibling (`ci-deploy.test.sh:7-8`) and can read sibling files (precedent `ci-deploy.test.sh:1492`). Convention is **source-level assertion** (`awk` a function-body range + tight `grep -qE`), plus `run_deploy` / `run_deploy_traced` runtime modes (learning `2026-07-14-cloud-init-templatefile-escaping-and-ci-deploy-payload-testing.md`). CI runs it at `.github/workflows/infra-validation.yml:359`. | Tests are source-level assertions on `ci-deploy.sh` (Option 2 keeps all coverage in the constraint-named file). |

## User-Brand Impact

**If this lands broken, the user experiences:** a stalled deploy pipeline — a runtime deploy that cannot authenticate its image pull (the #6400 / #6408 class), freezing releases for the whole fleet until an operator intervenes. No user-facing data surface is touched.

**If this leaks, the user's data is exposed via:** N/A — no user data flows through the deploy-credential path. The only secrets involved are the scoped GHCR/zot **read** tokens, which move `--password-stdin` (never argv) and land in `config.json` at `0600`, deploy-owned, on a host-local block volume — same trust boundary as today (`/home/deploy` → `/mnt/data`, both root/deploy-only host paths; no world-readability change).

**Brand-survival threshold:** `aggregate pattern` — a broken deploy-auth path degrades fleet-wide release availability, not a single user's data. Not a `single-user incident` (no per-user data/money/workflow exposure), so no CPO plan-time sign-off is required. The diff touches no sensitive path per preflight Check 6 (no schema/migration/auth-flow/API-route/`.sql`); reason recorded: `threshold: aggregate pattern, reason: deploy-infra credential-path relocation with no user-data surface`.

## Hypotheses

Root cause is **measured, not hypothesized** (see Overview). For completeness:

- **Network-outage checklist (plan Phase 1.4):** considered and **N/A**. The trigger scan matches the substring `SSH` (in "no SSH") but the failure is definitively a **local filesystem write (EROFS)** — the telemetry proves `stderr_chars>0, stdout_chars=0, kw=erofs`, and `docker login` fails **before any registry request** (no L3-L7 connectivity involved). The L3→L7 firewall-first checklist governs connectivity **diagnoses**; this is a filesystem-permission fix on a measured root cause, so no `hr-ssh-diagnosis-verify-firewall` incident is emitted.
- **Falsified alternatives (do not re-derive):** htpasswd stale-bake (converged 2026-07-16 08:15Z, `login_failed` continued); credential drift (all three planes agree, per issue body); disk-full (`kw`≠`nospace`); missing `credsStore` (`kw`≠`execnotfound`); empty-stderr H-B (`stderr_chars>0`).

### Network-Outage Deep-Dive (deepen-plan Phase 4.5)

The keyword scan matched (`SSH`, `firewall`, `timeout`) **and** the resource-shape trigger fired: the reach-path drives a `terraform apply` on `terraform_data.deploy_pipeline_fix`, which has `connection {}` + `provisioner "file"`/`"remote-exec"` blocks (`server.tf:273-528`) — an apply-time SSH dependency (cross-ref #3061). Layer-by-layer status:

- **L3 firewall allow-list — VERIFY AT APPLY (delivery, not the bug):** the `apply-deploy-pipeline-fix.yml` apply reaches web-1 over SSH (the provisioner). Per `hr-ssh-diagnosis-verify-firewall` + #3061, the operator/CI egress IP MUST be in `hcloud_firewall.web`'s SSH allowlist when that apply runs, or it fails `connection reset by peer` with zero SSH keywords in the error. This is a **pre-existing** property of the delivery mechanism, not introduced by this fix; the plan does not change the provisioner or firewall. Action: the ship/apply step confirms the apply succeeded (workflow green) — a `connection reset` there is an egress-IP-drift signal, not a code defect.
- **L3 DNS/routing — N/A to the bug:** the failure is local (EROFS), pre-any-request.
- **L7 TLS/proxy — N/A to the bug:** `docker login` fails at the credential-PERSIST step, after auth, before any registry transport (`stderr_chars>0, stdout_chars=0, no network I/O`).
- **L7 application — the actual fault, MEASURED:** `class=cred_store kw=errsaving,erofs` — a filesystem write, not connectivity.

Conclusion: the **failure** is definitively non-network (local EROFS). The only network surface in scope is the **delivery apply's** pre-existing SSH provisioner, whose L3 allowlist is the operator's standing apply-time precondition (#3061) — flagged, not a new dependency.

## Fix Evaluation

Two options were evaluated against the tree. **Option 2 is recommended** on measured grounds; Option 1 is the considered-and-rejected alternative. (The ARGUMENTS listed Option 1 first as the presumptive minimal — see Decision Divergence.)

### Option 2 (RECOMMENDED) — relocate `DOCKER_CONFIG` onto `/mnt/data`

Set an exported `DOCKER_CONFIG` (the config **directory**, which `docker login` honors) to a subdir of `/mnt/data` (already a `ReadWritePath`, already mounted), and derive `GHCR_DOCKER_CONFIG` from it. `mkdir -p` the subdir at runtime (`/mnt/data` is writable, so the deploy user can create it — no boot dependency, no dir-existence trap).

- **Blast radius:** `apps/web-platform/infra/ci-deploy.sh` only (+ its test + a soak). **No** systemd/cloud-init edit; **no** `webhook.service` lockstep; **no** boot `mkdir`; **no** `user_data` gzip-budget consumption; **no** `templatefile` `$${}`/`%{` escaping hazard.
- **Correctness:** one `export DOCKER_CONFIG` covers **all** login sites (GHCR prelude `ci-deploy.sh:1203`, zot gate `:1298`, refetch-relogin `:1154`) since none pass `--config`. Cosign `:ro` mount (`:1513`) and the zot second-auths entry stay consistent via `$GHCR_DOCKER_CONFIG`. Boot-bake (`/root/.docker`, root) is a separate lifecycle — untouched.
- **Delivery to live hosts:** editing `ci-deploy.sh` auto-fires `apply-deploy-pipeline-fix.yml` (paths include `ci-deploy.sh`) → `infra-config` **hot-push** to web-1 (`infra-config-apply.sh:34`), effective on web-1's next deploy with **no power-off**. web-2 gets it via the image bake on the sanctioned `web-2-recreate` dispatch (below).
- **Precedent:** learning `2026-04-06-doppler-protecthome-readonly-config-dir-fix.md` — for `ProtectHome=read-only` + a home config-dir write, **relocate to a writable path rather than punch ProtectHome**; it names `~/.docker` explicitly. `/mnt/data` is the substrate-audit-sanctioned writable path (learning `2026-05-19-inngest-substrate-five-bug-cascade.md`).
- **Tighter sandbox** than Option 1 (no ProtectHome hole).

### Option 1 (REJECTED) — add `/home/deploy/.docker` to `ReadWritePaths`

Add the docker config dir to `webhook.service` `ReadWritePaths`, mirroring the substrate-audit RW-hole pattern.

- **Rejected because:** (a) contradicts the 2026-04-06 ProtectHome-relocate precedent (punches a home write-hole); (b) **dir-existence trap** — `/home/deploy/.docker` is absent on a fresh host; a hard ReadWritePath on an absent dir `226/NAMESPACE`s the unit (deploy listener DOWN), and a `-`-prefixed path stays read-only (still EROFS) — so it also needs a **boot `mkdir -p /home/deploy/.docker && chown deploy` runcmd**, which the `infra-config` hot-push path (web-1) **cannot** deliver (it writes only the listed files), risking a **bricked webhook.service on web-1** if the unit is hot-pushed before the dir exists; (c) requires editing **both** `cloud-init.yml:264` **and** standalone `webhook.service:48` in lockstep; (d) consumes `user_data` gzip budget (`cloud-init-user-data-size.test.ts`) and incurs the `templatefile` `$${}` escaping hazard; (e) reaches web-1 only via a **maintenance-window power-off replace** for the systemd-unit half (the standalone unit hot-push would need the dir pre-created). Strictly heavier and riskier than Option 2 for an identical outcome.

### Architecture Decision (ADR/C4) — gate assessment

**No new ADR / no C4 change.** This is a bug fix that **applies an existing, learning-documented pattern** (2026-04-06 ProtectHome-relocate; 2026-05-19 `/mnt/data` writable-substrate) — it moves a credential **file path** between two already-modeled host-local paths. It makes **no** ownership/tenancy, substrate/integration, resolver/trust-boundary, or ADR-reversing decision. External actors/systems checked and unchanged: **GHCR** and **zot** registries (already modeled; same auth, same tokens), **no** new datastore, **no** new access relationship (deploy user → its own config file). A competent engineer reading ADR-096/ADR-115 + the 2026-04-06 learning would **not** be misled after this ships. Gate 2.10 skips with this justification. The decision rationale is captured in this plan + `ci-deploy.sh` comments + a `/compound` learning at ship.

## Implementation Phases

### Phase 0 — Prove the ONE unmeasured link (the review reframe)

The constraint is "prove writable under the sandbox namespace, not assumed." Plan-review (DHH + code-simplicity + Kieran, converging) established that **two of the three facts are already proven in production, more rigorously than a dev-box reproduction could** — a synthetic `systemd-run` does not even replicate the real `webhook.service` directive set, so it is a *weaker* signal than the evidence in hand. Do **not** re-run a synthetic namespace reproduction. Cite the production evidence, then measure the one link that is genuinely unproven:

1. **`/home/deploy/.docker` is EROFS under the unit — already measured (prod telemetry):** 55 failed-login lines, `kw=errsaving,erofs`, `errno_chars=22`. Cite, do not re-run.
2. **`/mnt/data` is writable under `webhook.service`'s namespace — already proven in prod:** the deploy user writes `/mnt/data/workspaces/.deploy-lease` (`ci-deploy.sh:241`) and `/mnt/data/workspaces` (`:2192/2256`) on every deploy under this exact unit; it is in both `ReadWritePaths` copies (`cloud-init.yml:264`, `webhook.service:48`). Cite, do not re-run.
3. **THE ONE UNMEASURED LINK (Kieran) — `docker login` with no `--config` honors `DOCKER_CONFIG` as the config *directory*:** this is the behavioral assumption the whole fix rests on and the only fact not already in evidence. Prove it with a real `docker login` (the repo's own "MEASURED" Phase-0 discipline, `ci-deploy.sh:670` — docker 29.4.3, live registry:2):

```bash
# MEASURED proof — cred lands in $DOCKER_CONFIG/config.json, not $HOME/.docker:
tmp="$(mktemp -d)"; DOCKER_CONFIG="$tmp" docker login <reg> -u <u> --password-stdin <<<"<tok>" \
  && test -f "$tmp/config.json" && echo "HONORED rc=0"   # expect the file under $tmp, NOT ~/.docker
```

Pin only this one MEASURED output into the PR body. (No `systemd-run`, no dev-box mkdir reproduction, no gating AC on those.)

### Phase 1 — Relocate `DOCKER_CONFIG` in `ci-deploy.sh`

Edit `apps/web-platform/infra/ci-deploy.sh` at the config-path declaration (around line 69). Introduce a `/mnt/data`-rooted config dir, export `DOCKER_CONFIG`, and derive `GHCR_DOCKER_CONFIG` from it. Add an idempotent runtime `mkdir` before the first `docker login`. Illustrative shape (final wording at `/work`):

```bash
# ci-deploy.sh (~line 69)
# #6497/#6565: `docker login` persists creds to $DOCKER_CONFIG/config.json. The default
# $HOME/.docker (/home/deploy/.docker) is under ProtectHome=read-only and NOT in
# webhook.service ReadWritePaths -> EROFS ("error saving credentials"). Relocate to
# /mnt/data (already a ReadWritePath + guaranteed mounted) per the 2026-04-06
# ProtectHome-relocate precedent; tighter than punching ProtectHome for ~/.docker.
readonly DEPLOY_DOCKER_CONFIG_DIR="${DEPLOY_DOCKER_CONFIG_DIR:-/mnt/data/deploy-docker}"
export DOCKER_CONFIG="$DEPLOY_DOCKER_CONFIG_DIR"
mkdir -p "$DOCKER_CONFIG" 2>/dev/null || true
chmod 700 "$DOCKER_CONFIG" 2>/dev/null || true
# Single source of truth (architecture-strategist Finding 1): DERIVE from the exported
# DOCKER_CONFIG so the login-WRITE path ($DOCKER_CONFIG/config.json) and the cosign
# mount-READ path ($GHCR_DOCKER_CONFIG, :1513) can never be silently split by an
# independent override. NOT `${GHCR_DOCKER_CONFIG:-...}` (two knobs) — one knob.
readonly GHCR_DOCKER_CONFIG="${DOCKER_CONFIG}/config.json"
```

Notes for `/work`:
- **Single-source-of-truth (arch-strategist Finding 1, MEDIUM):** derive `GHCR_DOCKER_CONFIG="${DOCKER_CONFIG}/config.json"` from the *exported* `DOCKER_CONFIG`, not re-derived from `DEPLOY_DOCKER_CONFIG_DIR` and not left independently overridable (`${GHCR_DOCKER_CONFIG:-...}`). Existing tests already override `GHCR_DOCKER_CONFIG` alone (`ci-deploy.test.sh:3456-3466`), so an independent knob re-opens the exact login-write-vs-mount-read split this fix closes. `DEPLOY_DOCKER_CONFIG_DIR` stays overridable (for the test harness); `GHCR_DOCKER_CONFIG` becomes a pure function of `DOCKER_CONFIG`.
- `export DOCKER_CONFIG` is required (child `docker` reads it from env). `GHCR_DOCKER_CONFIG` needs no export (in-process, mount-arg only).
- The `mkdir`/`chmod` are fail-soft (`|| true`) so a transient does not `set -e`-abort the deploy — any resulting login failure is then **named** by the existing `_login_kw`/`_login_hatch` telemetry (`_login_kw` classifies `enoent` at its `printf 'enoent,'` / `'no such file or directory'` arm, distinguishable from the old `/home/.../erofs`).
- **`/mnt/data`-unmounted fail-safe (spec-flow F7):** `/mnt/data` is itself a `ReadWritePath`, so if the block volume is not mounted the write **succeeds on the root fs** (no error) — the fix stays fail-safe (login works, deploy proceeds; creds are re-written per deploy via `ghcr_prelude_and_login`, so ephemeral loss self-heals). Optional cheap breadcrumb: emit a one-line `logger` warning when `mountpoint -q /mnt/data` is false, so the "creds on ephemeral root" state is observable (not required for correctness).
- **cosign-mount-absent hardening (arch-strategist LOW, pre-existing):** when a login is skipped/fails, `$GHCR_DOCKER_CONFIG` (the *file*) does not exist while `mkdir` created its *dir*; `docker run -v "$GHCR_DOCKER_CONFIG:...:ro"` then bind-mounts a freshly auto-created empty **directory** onto `/root/.docker/config.json`, yielding a confusing cosign failure instead of a clean "unauthenticated". Optional while here: skip the cosign `-v` config mount arg when the file is absent. Pre-existing (true today with `/home/deploy/.docker`) — flag for `/work`, not blocking.
- **Do NOT** touch the boot-bake `runcmd` (`cloud-init.yml:487/495/508`) — it is root/`/root/.docker`, un-sandboxed, and correct (arch-strategist Q2: separate lifecycle, no divergence).
- Verify no other consumer reads `/home/deploy/.docker` (arch-strategist Q4 confirmed: only `ci-deploy.sh:69` + the path-agnostic `ci-deploy.test.sh` T16/T20/T21 classifier fixtures reference it — those are pre-fix stderr shapes, intentionally retained; do NOT "fix" them to `/mnt/data`).

### Phase 2 — Extend `ci-deploy.test.sh`

Plan-review (DHH + code-simplicity) cut the original five assertions (four were tautological "the line I wrote exists" greps) down to the **two load-bearing invariants**, plus two harness-hygiene items surfaced by Kieran + architecture-strategist:

1. **Relocation off ProtectHome (the regression that hurt):** assert `ci-deploy.sh`'s `GHCR_DOCKER_CONFIG` **assignment RHS** resolves under `/mnt/data` and **no assignment default** resolves under `/home/deploy`. **Anchor to the assignment line, strip comments** (`cq-assert-anchor-not-bare-token`) — a bare-token grep for `/home/deploy/.docker` **false-fails** because the Phase-1 explanatory comment itself contains that string (Kieran finding 2). E.g. assert on the `readonly GHCR_DOCKER_CONFIG=` / `readonly DEPLOY_DOCKER_CONFIG_DIR=` lines only, not the whole block.
2. **Login-write == cosign-mount, by construction (arch-strategist Finding 1):** assert `$GHCR_DOCKER_CONFIG` equals `${DOCKER_CONFIG}/config.json` — i.e. the mount source (`ci-deploy.sh:1513`) is *derived from* the exported `DOCKER_CONFIG`, not an independent knob. This is stronger than "mount source resolves under `/mnt/data`" (which passes even under a split). If asserting "no login site passes `docker --config`", match `docker[[:space:]].*--config`, **not** bare `--config` (8 `doppler … --config prd` lines would false-fail — Kieran finding 2).

Harness hygiene (make explicit so the suite is green on the CI runner):
- **Source-time env (arch-strategist LOW):** the new top-level `export DOCKER_CONFIG` + `mkdir -p` run at **source time**, and `ci-deploy.test.sh` sources `ci-deploy.sh` (`:7-8`). `/mnt/data` is absent on the GH runner, so the harness must set `DEPLOY_DOCKER_CONFIG_DIR="$(mktemp -d)"` (or similar) **before sourcing** — the `|| true` prevents an abort but otherwise leaves `DOCKER_CONFIG` exported to a nonexistent dir for the whole test process.
- Confirm the existing cosign-mount test (`ci-deploy.test.sh:1472`) and the recovery-relogin continuity test (`:3456-3466`) still pass under the relocation (they assert on the `$GHCR_DOCKER_CONFIG` symbol / `[^ ]+` source, so they survive — arch-strategist Q4). Add a one-line note at the T16/T20/T21 fixtures that the embedded `/home/deploy/.docker` is a **pre-fix, path-agnostic classifier shape, intentionally retained** — do not "fix" it to `/mnt/data`.

Run: `bash apps/web-platform/infra/ci-deploy.test.sh` (the CI invocation, `infra-validation.yml:359`).

### Phase 3 — Fix follow-through soak (repair close criterion) — enrolled on #6565, NOT #6497

**Critical issue-targeting correction (cto-F1, verified):** the repair soak must **not** be enrolled on **#6497**. #6497 is the *instrument* issue ("gate cannot name its own failure"); its body already carries the instrument directive `zot-login-gate-names-failure-6497.sh` with `earliest=2026-07-18`, and that instrument soak **PASSES on a still-broken world** (its criterion is "failed lines carry the hatch", satisfied while EROFS is live). The follow-through sweeper closes an issue on **any** enrolled script's exit-0, so the instrument soak would auto-close #6497 while the EROFS bug is unrepaired, de-enrolling any repair soak stacked on it. **The repair is tracked by the separate open issue #6565** ("P1: repair the zot/GHCR login failure — once #6528's instrument names the mode"). Enroll the repair soak on **#6565**; the PR uses `Ref #6565` (repair) + `Ref #6497` (instrument context). #6497 closes on its own instrument soak; #6565 closes on this repair soak.

Add `scripts/followthroughs/zot-login-gate-erofs-repaired-6565.sh` (sibling to the instrument soak, reusing its Better Stack query helper — a thin wrapper, not a second instrument, per DHH). It asserts the **repair** invariant the instrument soak structurally cannot ("failures stopped", not "failures are well-named"), with **per-host_id** semantics and **fleet coverage** (spec-flow F1/F3/F8):

- `PASS` — **≥2 distinct `host_id` values observed**, AND **each observed host** has ≥1 `ZOT_GATE: active … ok` / `PRELUDE: docker login ghcr.io ok` line **and zero** `ZOT_GATE|PRELUDE … FAILED` lines carrying `class=cred_store` or `kw=erofs`. Absence of failures is NOT evidence of repair — each host must **positively emit an OK line** (spec-flow F1: a fleet-global "≥1 OK + zero FAILED" false-PASSes when web-2 is silent).
- `TRANSIENT` — fewer than 2 host_ids seen, or a host with zero ZOT_GATE/PRELUDE lines in the window (no deploy exercised the relocated path on it) — **never PASS**.
- `FAIL` — any host emits a `class=cred_store`/`kw=erofs` FAILED line.

Notes:
- **Group by observed `host_id`, do not hardcode two values (spec-flow F8):** `host_id` is the Hetzner instance-id hash (`ci-deploy.sh:137-162`), so a `web-2-recreate` `-replace` mints a **new** `host_id`. The soak must discover host_ids from the window and assert coverage (≥2 distinct), not query a stale fixed pair.
- **The discriminating telemetry only fires on a real deploy-user `ci-deploy.sh` run** — see the Delivery + Verification flow below; the soak is preceded by forced deploys on each host so `PASS` is reachable rather than permanently `TRANSIENT`.
- `earliest=` is set **after** both forced deploys land, to the **max** of both hosts' first post-fix deploy timestamp (spec-flow F5) — not a web-2-only anchor. Resolve the placeholder at ship time.

```
<!-- soleur:followthrough
  script=scripts/followthroughs/zot-login-gate-erofs-repaired-6565.sh
  earliest=<max(web-1 first post-fix deploy, web-2 first post-recreate deploy)>
  secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD
-->
```

No new `secrets=` beyond the three the sweeper already wires (`scheduled-followthrough-sweeper.yml`) — reuse them.

### Phase 4 — Delivery + Verification: force the relocated path to be exercised

Plan-review (spec-flow F2/F3, cto-F2) found the fix mechanism sound but the **close loop unreachable as originally written**: delivering the file does not exercise it, and a web-2 recreate boots the *root* boot-bake login (untouched), not the sandboxed deploy-user login the telemetry keys on. So "file present" ≠ "fix verified", and nothing forced a deploy → the soak would sit `TRANSIENT` forever. This phase closes that loop (ship-driven, automatable — `feedback_never_defer_operator_actions` / `hr-ship-message-no-operator-checklist`):

```
merge ci-deploy.sh edit
  ├─ web-1 (running): apply-deploy-pipeline-fix.yml → infra-config hot-push writes /usr/local/bin/ci-deploy.sh
  │     → THEN force a deploy on web-1 (re-dispatch current pinned version via /hooks/deploy or
  │       web-platform-release re-run) so the deploy-user login runs the relocated path and emits telemetry
  └─ web-2 (warm standby): merge fires web-platform-release.yml (image rebuild carrying fixed ci-deploy.sh)
        → GATE: wait for that release build to be GREEN for the merge SHA AND the pinned image digest
          updated (else web2-recreate-preflight fails: baked hash != applied host_scripts_content_hash)
        → gh workflow run apply-web-platform-infra.yml -f apply_target=web-2-recreate  (operator ACK)
        → THEN force a deploy on web-2 so its deploy-user login runs the relocated path (recreate alone
          only runs the ROOT boot-bake login — the untouched path — and emits no cred_store telemetry)
  → resolve earliest= = max(both forced-deploy timestamps) → repair soak (#6565) → PASS → gh issue close 6565
```

Ship-automatable steps (make each an AC, not a passive "next deploy"):
- **Build-green gate before recreate (cto-F2, spec-flow F4):** ship confirms the `web-platform-release.yml` run for the merge SHA is green and the image pinned **before** emitting the `web-2-recreate` dispatch. The operator's single action is the **ACK** of the prod recreate, not the orchestration.
- **Force a deploy on each host** inside the soak window (re-deploy the current pinned version — a no-op-content deploy that still exercises `ghcr_prelude_and_login` + `zot_gate_and_login`). web-1's hot-push and web-2's recreate each get a forced deploy so both emit the discriminating telemetry.

## Files to Edit

- `apps/web-platform/infra/ci-deploy.sh` — relocate `DOCKER_CONFIG`/`GHCR_DOCKER_CONFIG` onto `/mnt/data/deploy-docker` + idempotent `mkdir`/`chmod` (Phase 1).
- `apps/web-platform/infra/ci-deploy.test.sh` — source-level assertions for the relocated path + cosign-mount continuity (Phase 2).

## Files to Create

- `scripts/followthroughs/zot-login-gate-erofs-repaired-6565.sh` — repair-close soak, enrolled on **#6565** (Phase 3), per-host_id + fleet-coverage semantics.

## Infrastructure (IaC)

This introduces **no new** infrastructure resource (no server, secret, vendor, service, DNS, cert, firewall rule). It changes an **existing** host script's credential file path. No `terraform-architect` invocation is warranted (Phase 2.8 skip: no new `.tf` resource).

### Apply path (how the fix reaches the two live web hosts — immutable-redeploy aware)

Per `hr-prod-host-config-change-immutable-redeploy`, host config only takes effect on the sanctioned delivery path — this fix does **not** assume in-place mutation:

- **web-1 (running, tunnel-connector-pinned):** merging the `ci-deploy.sh` edit **auto-fires** `apply-deploy-pipeline-fix.yml` (its `paths:` filter includes `apps/web-platform/infra/ci-deploy.sh`) → `terraform_data.deploy_pipeline_fix` → `push-infra-config.sh` → `/hooks/infra-config` → `infra-config-apply.sh` writes the new `/usr/local/bin/ci-deploy.sh` (`infra-config-apply.sh:34`). **No power-off, no maintenance window** (the `webhook.service` unit is unchanged, no reload needed). The relocation takes effect only when a deploy next **runs** `ci-deploy.sh` — Phase 4 forces that deploy so the path is exercised and verified, not merely delivered (spec-flow F2/F9).
- **web-2 (warm standby, no infra-config connector):** its `ci-deploy.sh` is baked into the app image (`Dockerfile:206`, `COPY … /opt/soleur/host-scripts/`) and seeded at first boot (`cloud-init.yml:546-548`). The merge updates `host_scripts_content_hash` (`server.tf:67-86`); the next app-image build carries the fixed `ci-deploy.sh`. web-2 receives it via the sanctioned `apply-web-platform-infra.yml` `workflow_dispatch` with `apply_target=web-2-recreate` (a scoped `-replace`, preflight-gated by `web2-recreate-preflight.sh`, which asserts the pinned image's baked host-scripts hash == applied `host_scripts_content_hash`). Automatable: `gh workflow run apply-web-platform-infra.yml -f apply_target=web-2-recreate` (operator-acknowledged prod host recreate; **not** SSH, **not** in-place).

Neither host is in the routine per-PR `-target` allow-list (`apply-web-platform-infra.yml:29-31`, both `hcloud_server.web` excluded per #5887) — host recreation is deliberately operator/dispatch-gated. **Option 2 avoids the web-1 power-off entirely** (the ci-deploy.sh hot-push), which is the primary operational advantage over Option 1.

### Distinctness / drift safeguards

No `dev`/`prd` variable, no new state, no `for_each`. `host_scripts_content_hash` drift is the existing, guarded mechanism (drift detector + `web2-recreate-preflight.sh`). No Terraform state touches secrets.

### Precedent-diff (deepen-plan Phase 4.4)

Pattern-bound behavior: writing a service-sandboxed process's config off a `ProtectHome=read-only` home dir onto a declared `ReadWritePath`. **Precedent exists** — `knowledge-base/project/learnings/integration-issues/2026-04-06-doppler-protecthome-readonly-config-dir-fix.md` (Doppler CLI `os.Mkdir(~/.doppler)` EROFS under `ProtectHome=read-only`). Side-by-side: the precedent **relocates the write to a writable path** and its Prevention section explicitly names Docker `~/.docker` as the same offender class to audit. This plan's Option 2 IS that precedent applied to `~/.docker` → `/mnt/data`. The substrate-audit learning (`2026-05-19-inngest-substrate-five-bug-cascade.md`) established `/mnt/data` as the sanctioned writable substrate in both `ReadWritePaths` copies. Pattern is **not novel** — it is the established, twice-documented form. (Option 1's ReadWritePaths-widening is the variant the precedent's "Why not ReadWritePaths" section argues against.)

## Downtime & Cutover

Deepen-plan Phase 4.55 fired (a `-replace` on `hcloud_server.web["web-2"]`). The plan **defaults to zero-downtime** and proves it — no serving surface goes offline:

- **web-1 (the serving host): NO downtime, NO reboot.** The fix is a `ci-deploy.sh` edit delivered via the `infra-config` **hot-push** (`apply-deploy-pipeline-fix.yml` → `/hooks/infra-config`), which writes `/usr/local/bin/ci-deploy.sh` in place. `hcloud_server.web` pins `lifecycle { ignore_changes = [user_data, …] }` (`server.tf:254-256`), so no `user_data`/replace is triggered on web-1, and the `webhook.service` unit is unchanged (no reload). web-1 keeps serving throughout. This is precisely why Option 2 was chosen over Option 1 (whose systemd-unit half would force a web-1 power-off).
- **web-2 (warm standby): zero-downtime recreate (blue-green-shaped).** web-2 is a drained, **non-serving** warm standby (`server.tf:233-253`, `lb-weight-gate.sh`); it takes no user traffic until failover. The `apply_target=web-2-recreate` `-replace` births a fresh host running first-boot cloud-init, preflight-gated (`web2-recreate-preflight.sh`), with **zero user-facing impact** — the only power-off is of a host that serves nobody. This is the #5887 zero-downtime-first pattern (`2026-07-02-zero-downtime-first-moved-block-statemv-and-blue-green-cutover.md`).
- **No database lock class, no in-flight-request drop class** — the change touches no migration and no router/connector on the serving path.

**Residual downtime: none.** No bounded maintenance window or serving-surface outage is required. Operator sign-off is the recreate **ACK** only (a prod host mutation), not an availability trade.

## Downtime & Cutover (deepen-plan Phase 4.55)

The web-2 delivery path is a `terraform -replace` on `hcloud_server.web["web-2"]` (a replace of a serving-class resource → the trigger fires). **Evaluated and defaults to zero-downtime** — no serving surface goes offline:

- **web-1 (the serving host): NO reboot, NO power-off.** The fix is delivered by the `ci-deploy.sh` **hot-push** (`apply-deploy-pipeline-fix.yml` → `/hooks/infra-config`), which writes `/usr/local/bin/ci-deploy.sh` in place. `hcloud_server.web` pins `user_data`/`image` via `lifecycle { ignore_changes = [...] }` (`server.tf:254-256`), so the cloud-init the plan does NOT edit cannot force a web-1 replace either. This is the decisive advantage of Option 2 over Option 1 (whose systemd-unit half would have needed a web-1 maintenance-window power-off).
- **web-2 (warm standby): recreate is zero-downtime for users.** web-2 is a **drained, non-serving** warm standby (LB-weight-gated, `lb-weight-gate.sh`), so replacing it never drops a live request — the blue-green shape of #5887 (`2026-07-02-zero-downtime-first-moved-block-statemv-and-blue-green-cutover.md`). Its recreate runs under the sanctioned `apply_target=web-2-recreate` dispatch, preflight-gated, inside the operator's own timing.
- **Residual downtime: none.** No bounded maintenance window is required for either host. The only operator-ACK'd action (web-2 recreate) affects a non-serving host.

## Precedent Diff (deepen-plan Phase 4.4)

The fix is a **pattern-bound behavior** (systemd `ProtectHome=read-only` + a process that writes a home config dir). Precedent exists and the fix mirrors it:

- **Precedent:** `knowledge-base/project/learnings/integration-issues/2026-04-06-doppler-protecthome-readonly-config-dir-fix.md` — Doppler CLI's `os.Mkdir(~/.doppler)` hit EROFS under `ProtectHome=read-only`; the resolution **relocated the write off the home dir to a writable path** (and its "Why not ReadWritePaths" section argues against punching a home hole; its Prevention names **Docker `~/.docker`** as the same offender class). This plan applies that precedent verbatim to `~/.docker` → `/mnt/data`. **No divergence.**
- **Substrate precedent for `/mnt/data` as the writable target:** `2026-05-19-inngest-substrate-five-bug-cascade.md` (#4017) established `/mnt/data` as the sanctioned `ReadWritePath` for deploy-written state. This plan writes there rather than adding a new hole — consistent.
- **No novel pattern introduced** — reviewers need not scrutinize a new sandbox mechanism.

## Observability

```yaml
liveness_signal:
  what: "ZOT_GATE: active … / PRELUDE: docker login ghcr.io ok journald lines (already instrumented, PR #6528)"
  cadence: "per deploy (every ci-deploy.sh run on each web host)"
  alert_target: "Better Stack (journald ship) + Sentry WEB-PLATFORM-5B (zot gate degraded)"
  configured_in: "apps/web-platform/infra/ci-deploy.sh (_login_kw/_login_hatch, ZOT_GATE/PRELUDE logger lines)"
error_reporting:
  destination: "Better Stack query API (host_id-scoped) + Sentry WEB-PLATFORM-5B"
  fail_loud: "yes — failed login emits rc=/class=/stderr_chars=/stdout_chars=/kw=/errno_chars= (fixed vocabulary)"
failure_modes:
  - mode: "login still EROFS after redeploy (fix not delivered / dir not writable)"
    detection: "FAILED line with class=cred_store AND kw=erofs persists post-redeploy (in-host journald→Better Stack); reachable only once a deploy exercises the deploy-user path (Phase 4 forced deploy)"
    alert_route: "fix soak zot-login-gate-erofs-repaired-6565.sh → follow-through sweeper (FAIL)"
  - mode: "config dir mkdir failed on a mounted /mnt/data (perm/quota)"
    detection: "FAILED line with kw=enoent — VERIFIED reachable: _login_kw classifies 'no such file or directory'→enoent at its printf 'enoent,' arm (spec-flow F6 resolved), distinguishable from the old /home erofs"
    alert_route: "same soak + Sentry WEB-PLATFORM-5B"
  - mode: "/mnt/data block volume not mounted (drift) — creds land on ephemeral root fs"
    detection: "FAIL-SAFE, no error emitted (root fs is writable) — login succeeds, deploy proceeds, per-deploy re-login self-heals ephemeral loss (spec-flow F7). Optional `mountpoint -q /mnt/data` warning breadcrumb makes the state observable"
    alert_route: "optional logger breadcrumb (not a hard failure)"
  - mode: "cosign mount references empty config (login-write path split from mount source)"
    detection: "IMAGE_VERIFY failure telemetry (existing ci-deploy.sh IMAGE_VERIFY logger line); structurally prevented by deriving GHCR_DOCKER_CONFIG from exported DOCKER_CONFIG (arch-strategist Finding 1)"
    alert_route: "Sentry + release-workflow deploy status"
logs:
  where: "host journald → Better Stack; Sentry for the zot gate event"
  retention: "Better Stack ingest retention (existing); Sentry event retention"
discoverability_test:
  command: "bash scripts/followthroughs/zot-login-gate-erofs-repaired-6565.sh   # Better Stack query API, NO ssh"
  expected_output: "PASS — ≥2 distinct host_ids, EACH with ≥1 ZOT_GATE/PRELUDE ok line and zero class=cred_store/kw=erofs FAILED lines (per-host, not fleet-global)"
```

This is an **affected-surface** observability case (Phase 2.9.2): `ci-deploy.sh` runs on a no-SSH host. The in-surface probe already exists (the `_login_hatch` structured fields discriminate cred_store/erofs/enoent/nospace/execnotfound in **one** event, `_login_kw` `ci-deploy.sh:679-699`), and the fix soak keys on the journald→Better Stack signal — no host-side-only inference. **Detection reachability depends on a real deploy** exercising the deploy-user path (Phase 4) — file delivery alone emits nothing (spec-flow F2).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Phase 0 MEASURED proof pinned into the PR body: a real `DOCKER_CONFIG=$tmp docker login … && test -f $tmp/config.json` shows `docker login` honors `DOCKER_CONFIG` as the config dir (the one unproven link). EROFS + `/mnt/data`-writable cited from prod evidence (telemetry + existing `/mnt/data/workspaces` writes), NOT re-run synthetically.
- [ ] `ci-deploy.sh`'s `GHCR_DOCKER_CONFIG` **assignment** resolves under `/mnt/data` and **no assignment default** resolves under `/home/deploy` — verified by a comment-stripped, assignment-line-anchored grep (`cq-assert-anchor-not-bare-token`), so it does not false-fail on the Phase-1 explanatory comment.
- [ ] `ci-deploy.sh` `export DOCKER_CONFIG` points at the `/mnt/data` dir; `GHCR_DOCKER_CONFIG` is `${DOCKER_CONFIG}/config.json` **by construction** (single source of truth — mount source cannot be split from login-write path).
- [ ] Boot-bake `runcmd` (`cloud-init.yml:487/495/508`) is **unchanged** — auto-satisfied (Files-to-Edit scopes out cloud-init); no separate check needed.
- [ ] `bash apps/web-platform/infra/ci-deploy.test.sh` passes, including the relocation assertion + the `$GHCR_DOCKER_CONFIG == ${DOCKER_CONFIG}/config.json` equality assertion; the harness sets `DEPLOY_DOCKER_CONFIG_DIR="$(mktemp -d)"` before sourcing.
- [ ] PR body uses **`Ref #6565`** (repair) + **`Ref #6497`** (instrument context) — NOT `Closes` (the repair completes post-merge via dispatch + soak). #6565 closes on the repair soak; #6497 closes on its own instrument soak.

### Post-redeploy (ship-driven; operator ACK only)

- [ ] **web-1 delivered:** merge auto-fires `apply-deploy-pipeline-fix.yml` → web-1 receives the fixed `/usr/local/bin/ci-deploy.sh` (verify the workflow run succeeded). *(Delivery ≠ verification — see next.)*
- [ ] **web-1 exercised:** a forced deploy on web-1 (re-deploy current pinned version) emits `PRELUDE: docker login ghcr.io ok` / `ZOT_GATE: active … ok` with no `class=`/`rc=` from web-1's `host_id`.
- [ ] **build-green gate:** ship confirms the `web-platform-release.yml` run for the merge SHA is green and the image pinned **before** the web-2 recreate dispatch (else `web2-recreate-preflight.sh` fails on a stale baked hash).
- [ ] **web-2 recreated + exercised:** operator ACKs `gh workflow run apply-web-platform-infra.yml -f apply_target=web-2-recreate` (passes preflight); a forced deploy on web-2 then emits an OK line from web-2's **new** `host_id` (recreate alone runs only the root boot-bake path).
- [ ] **Repair soak PASS:** `zot-login-gate-erofs-repaired-6565.sh` returns **PASS** — **≥2 distinct host_ids, each** with ≥1 OK line + zero `class=cred_store`/`kw=erofs` FAILED (per-host, not fleet-global) → then `gh issue close 6565`.

## Test Scenarios

- **Relocated path (source-level):** `ci-deploy.sh` default config path is `/mnt/data/...`, not `/home/deploy/...`.
- **Single-export coverage:** the exported `DOCKER_CONFIG` is declared once, ahead of every `docker login` site (GHCR prelude, zot gate, refetch-relogin) — so no per-site `--config` is needed and all three inherit it.
- **Cosign continuity:** the `docker run … -v $GHCR_DOCKER_CONFIG:/root/.docker/config.json:ro` mount source equals the relocated login-write path (login-write and mount-read never split).
- **Fail-soft mkdir:** a `mkdir`/`chmod` transient does not abort the deploy (`|| true`); any downstream login failure is still classified by `_login_kw`/`_login_hatch`.
- **Single-source-of-truth invariant:** `$GHCR_DOCKER_CONFIG == ${DOCKER_CONFIG}/config.json` holds by construction even when a test overrides `DEPLOY_DOCKER_CONFIG_DIR` (the login-write path and cosign mount source cannot be independently split).
- **Soak semantics (per-host):** the repair soak returns TRANSIENT when <2 host_ids seen or any host is silent, FAIL on a persisting cred_store/erofs line from any host, PASS only when ≥2 host_ids EACH show an OK line and zero cred_store/erofs failures.

## Domain Review

**Domains relevant:** Engineering / Infrastructure (primary). No Product/UX (no UI-surface file in Files-to-Edit/Create; mechanical UI-surface override does not fire → **NONE**). No Legal/GDPR (no regulated-data surface). No Finance/Sales/Marketing/Support.

### Engineering / Infrastructure

**Status:** reviewed (plan-time analysis; deepened by the always-run plan-review eng panel — DHH / Kieran / code-simplicity, escalating to architecture-strategist — and by `/deepen-plan` domain agents).
**Assessment:** Self-contained single-file credential-path relocation onto an existing sandboxed-writable volume, following the documented ProtectHome-relocate precedent. Security-adjacent (credential storage location): creds remain `0600`, deploy-owned, host-local; no world-readability or cross-boundary change. Reach-path is the sanctioned immutable-redeploy + hot-push, not in-place. Key risks (dir-existence trap, cosign-mount split, boot-bake scope) are enumerated and bounded above.

### Product/UX Gate

**Not applicable — NONE.** No user-facing surface; infrastructure/tooling change.

## Open Code-Review Overlap

**None** — no open `code-review`-labelled issue names `ci-deploy.sh`, `ci-deploy.test.sh`, or the followthroughs dir for this concern (verify at `/work` with the two-stage `gh issue list --label code-review --state open --json …` + standalone `jq --arg` against the three file paths). Adjacent open issues (#6400 GHCR-side auth, #6416 mirror backfill, #6415/ADR-115 private-NIC reach) are **different defects** and explicitly out of scope (issue #6497 states fixing this "does not fix #6400").

## Decision Divergence (recorded for ship → action-required)

The ARGUMENTS listed **Option 1** (add `/home/deploy/.docker` to `ReadWritePaths`) first as the presumptive "minimal, same-shape-as-existing-entries" fix, and the plan **recommends Option 2** instead. This is a reasoned, measured architecture recommendation (the ARGUMENTS explicitly asked to "evaluate in the plan"), grounded in: (a) the 2026-04-06 ProtectHome-relocate precedent that argues against punching a home write-hole; (b) the dir-existence brick-risk on the hot-push path; (c) the two-file lockstep + boot-`mkdir` that make Option 1 not actually a one-line same-shape change; (d) Option 2's avoidance of a web-1 power-off. Running headless in the one-shot pipeline, this divergence is **persisted** to `knowledge-base/project/specs/<branch>/decision-challenges.md` for `ship` to render into the PR body and file as an `action-required` issue — surfaced, not silently applied.

## Plan Review — Applied (6-agent panel)

DHH + Kieran + code-simplicity + architecture-strategist + spec-flow + cto (cto = named devex panel). **The fix mechanism was confirmed sound** — architecture-strategist deep-traced every docker invocation (one exported `DOCKER_CONFIG` covers all sites; no `sudo docker`/`HOME=`/`docker --config`; boot-bake is a separate root lifecycle with no regressable working credential); Kieran independently verified. All findings were **Mechanical** (correctness/flow, one right answer) and are applied:

| # | Finding | Source | Applied |
| --- | --- | --- | --- |
| 1 | Cut Phase 0 synthetic reproduction; prove the ONE unmeasured link (`docker login` honors `DOCKER_CONFIG`) | DHH, simplicity, Kieran | Phase 0 reframed to prod-evidence + one MEASURED docker-login check |
| 2 | Collapse 5 tautological tests → 2 load-bearing invariants | DHH, simplicity | Phase 2 rewritten (relocation + equality-by-construction) |
| 3 | Grep ACs false-fail on the patch's own comment + on `doppler --config prd` | Kieran | ACs anchored to assignment RHS, comment-stripped; `docker --config` not bare |
| 4 | Derive `GHCR_DOCKER_CONFIG` from exported `DOCKER_CONFIG` (single source of truth) so login-write/cosign-mount cannot split | architecture-strategist | Phase 1 uses `${DOCKER_CONFIG}/config.json`; test asserts equality |
| 5 | **Repair soak must target #6565, not #6497** (instrument soak auto-closes #6497 on a still-broken world) | cto | Retargeted to #6565; frontmatter + ACs + Sharp Edges updated |
| 6 | **Soak PASS must be per-host_id + fleet coverage** (fleet-global false-PASSes when web-2 silent) | spec-flow | Phase 3: ≥2 host_ids, each positive OK + zero cred_store/erofs |
| 7 | **Nothing forces a deploy** → soak permanently TRANSIENT; recreate runs the untouched root path | spec-flow, cto | New Phase 4: force a deploy per host to exercise the deploy-user path |
| 8 | Build-green + image-pin gate before web-2-recreate dispatch | cto, spec-flow | Phase 4 + AC: ship confirms release build green before recreate |
| 9 | `host_id` changes on `-replace` → discover, don't hardcode | spec-flow | Phase 3 note + Sharp Edge |
| 10 | `kw=enoent` reachability; `/mnt/data`-unmounted silent-write | spec-flow | Verified enoent classified (`:699`); /mnt/data-unmounted is fail-safe + optional breadcrumb |
| 11 | cosign-mount-absent auto-dir; test source-time tmpdir; fixture note | architecture-strategist | Folded into Phase 1/2 notes |

**Decision divergence (DC-1)** persisted to `decision-challenges.md` (Option 2 recommended over the ARGUMENTS' presumptive Option 1) — all six reviewers independently endorsed Option 2.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This section is filled (threshold: `aggregate pattern`).
- **The two soaks live on DIFFERENT issues (cto-F1).** Instrument soak `zot-login-gate-names-failure-6497.sh` → **#6497** ("gate NAMES failures", `earliest=2026-07-18`, PASSES on a still-broken world). Repair soak `zot-login-gate-erofs-repaired-6565.sh` → **#6565** ("failures STOPPED"). NEVER stack the repair directive on #6497 — the instrument soak would auto-close #6497 (and de-enroll the repair) while EROFS is still live.
- **Soak PASS is per-host, not fleet-global (spec-flow F1).** A fleet-global "≥1 OK + zero FAILED" false-PASSes when web-2 is silent (web-1's OK + web-2's absence). Require ≥2 distinct host_ids, each with a positive OK line.
- **File delivery ≠ fix verified (spec-flow F2/F9).** The hot-push/recreate place the file; only a real deploy-user `ci-deploy.sh` run emits the discriminating telemetry. Phase 4 forces a deploy per host — without it the soak is permanently `TRANSIENT`.
- **host_id changes on web-2 recreate (spec-flow F8):** a `-replace` mints a new Hetzner instance-id → new `host_id`. The soak must discover host_ids from the window, not query a stale fixed pair.
- The `mkdir`/`chmod` must be **fail-soft** — a hard `set -e` abort on a transient would take down the deploy for a cosmetic issue; a real failure is better surfaced by the existing login telemetry.
- On the `-target`-scoped web-2 recreate, verify the `-replace` actually lands on web-2 (learning `2026-07-17-target-scoped-terraform-apply-makes-resource-deletion-a-silent-noop.md`) and that `web2-recreate-preflight.sh` passed (baked hash == applied `host_scripts_content_hash`) — else the recreate re-aborts at cloud-init `stage=verify`.
- `Ref #6565` + `Ref #6497`, not `Closes` — the repair completes post-merge (dispatch + soak). Closing at merge would false-resolve.
