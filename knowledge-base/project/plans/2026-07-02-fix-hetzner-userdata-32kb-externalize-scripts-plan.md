---
title: "fix(infra): externalize cloud-init scripts + hooks.json out of Hetzner user_data (32 KB cap)"
issue: 5921
type: bug
lane: cross-domain
brand_survival_threshold: aggregate pattern
date: 2026-07-02
branch: feat-one-shot-5921-hetzner-userdata-32kb
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# 🐛 fix(infra): fresh Hetzner web-host `user_data` exceeds 32 KB — externalize baked scripts + hooks.json

Closes #5921 (use `Ref #5921` in the PR body if the fresh-host provision is deferred behind #5887; see Sequencing).

## Enhancement Summary

**Deepened on:** 2026-07-02
**Sections enhanced:** Overview, ACs, IaC, Observability, ADR/C4, Risks
**Research agents used:** terraform-architect, spec-flow-analyzer, CTO, architecture-strategist, code-simplicity-reviewer, observability-coverage-reviewer, security-sentinel, verify-the-negative pass

### Key improvements folded in from deepen-plan
1. **Corrected externalization count 24 → 22** (architecture-strategist P1-A): `fail2ban-sshd.local` + `journald-soleur.conf` MUST stay inline (consumed at runcmd L476/L488, before Docker at L508) AND their `base64encode(file())` args MUST stay in `server.tf` — dropping them while `cloud-init.yml` still interpolates `${fail2ban_sshd_local_b64}`/`${journald_soleur_conf_b64}` makes `templatefile()` fail → `terraform plan` errors.
2. **hooks.json must ALSO be externalized** (measured): externalizing the 22 scripts alone leaves web `user_data` at **~38,913 B — still over the cap**, because `hooks_json_b64` renders to **10,744 B**. Baking `hooks.json.tmpl` into the image + injecting the small secret at boot removes 10.7 KB → measured **29,631 B (≈3.1 KB headroom)**. This is the load-bearing correction — the original plan did not fit.
3. **Fail-closed sentinel** (security P1): cloud-init `runcmd` is NOT under a top-level `set -e`; a block-scoped `set -e` does not reliably halt the whole sequence. Extraction writes `/run/soleur-hostscripts.ok` only after hash-verify + all installs; the terminal `docker run` gates on it (`poweroff -f` on absence) so a failed extraction can never bring the app up with an unconfigured egress firewall (#5046 posture).
4. **Single combined content-hash integrity** (security P1): the 22 host-root scripts + hooks.tmpl now come from a public, unpinned `:latest` image with no content check. A Terraform-computed combined `sha256` over the source files (~70 B in user_data) is verified at boot; abort on mismatch. Driftless (recomputed each apply), complete, and cheap — and turns the ADR-080 stale-image trap into a LOUD boot failure.
5. **Observability**: dropped the mis-fitting periodic `betteruptime_heartbeat`; primary detector is a provision-armed Better Stack absence check (catches pre-trap aborts), secondary is a discriminating Sentry event in the `set -e` trap.
6. **Pull robustness** (arch P1-C): `--retry` pull loop + idempotent `docker rm -f || true` + `trap cleanup EXIT` (mirror plugin-seed at cloud-init.yml:606-608).
7. **ADR-080 amendment** (not a new ADR) + C4 refinement; AC set trimmed of ceremony.

### New considerations discovered
- The combined content-hash makes image↔config coherence a boot-time invariant (a stale/mis-built image fails the boot loudly instead of silently installing old scripts).
- After externalization the extraction `docker pull` is the FIRST, critical-path pull (not a "cache-hit no-op") — hence the `--retry` + provision-armed absence detection.

## Overview

A fresh Hetzner web host (`hcloud_server.web["web-2"]`) cannot be provisioned:
Terraform apply fails with `user_data … Length must be between 0 and 32768`.
`apps/web-platform/infra/server.tf:42-77` renders `cloud-init.yml` via
`templatefile()`, injecting **24 `base64encode(file())` args + 1 render-time
secret** (`hooks_json_b64`). The rendered web `user_data` is **~282,124 bytes** —
~8.6× the Hetzner 32,768-byte hard cap. `ci-deploy.sh` alone is 75,428 B raw
(100,572 base64), and `hooks_json_b64` renders to 10,744 B.

**The fix externalizes 22 static scripts AND hooks.json out of `user_data`:**
- The 22 static scripts are baked into the existing app image (`var.image_name`)
  via a Dockerfile `COPY`, then extracted at first boot with `docker create` +
  `docker cp` — reusing the plugin-seed idiom already in `cloud-init.yml:604-615`.
- `hooks.json.tmpl` (8 KB of webhook route definitions; only `webhook_deploy_secret`
  is secret) is likewise baked into the image; at boot the host extracts it and
  injects the small `webhook_deploy_secret` render-var → the webhook hooks file.
- **`fail2ban-sshd.local` and `journald-soleur.conf` stay inline** (consumed at
  runcmd L476/L488, before Docker installs at L508); their `base64encode(file())`
  args stay in `server.tf`.

Measured result: web `user_data` drops from ~282 KB to **~29,631 bytes** (≈3.1 KB
headroom under the cap). A CI size-guard test enforces the budget for both hosts.
This unblocks **ADR-068 multi-host GA** (Phase 2 git-data host + Phase 3 web-2).

### Why NOT the issue's proposed option 1 (gzip the whole user_data)

**Measured and falsified.** `gzip -9 | base64` of the rendered web `user_data` =
140,856 B (4.3× over). Compression cannot fit it; externalization is mandatory.
(Hetzner does not base64-decode `user_data`, so `base64gzip()` output is not
gzip-magic bytes to cloud-init — it would need a live probe and is out of scope.)

## Premise Validation (Phase 0.6)

- **#5887** (`moved`-block wedge) — **OPEN.** A *deployment* prerequisite, not a
  *merge* blocker (see Sequencing). Do NOT clear #5887 by editing the `-target=`
  allow-list (forces a prod reboot — it's an operator cutover).
- **#5875 / #5274** — OPEN; #5274 is the ADR-068 GA line this unblocks.
- **git-data "is blocked too"** — **IMPRECISE.** `git-data.tf:123` renders
  `cloud-init-git-data.yml` to **~28,087 B — UNDER the cap** (~14 % headroom).
  git-data fits today; the fix is web-host-only (git-data left byte-unchanged).
- **Mechanism vs ADR corpus** — `docker cp`-from-image is the **established**
  pattern (ADR-080 image-bake + `docker cp` re-seed; plugin-seed + inngest-bootstrap
  blocks). No ADR rejected it.
- **Own claims verified** (verify-the-negative pass, all confirmed): the 24
  `base64encode(file())` args are at server.tf:44-68 (fail2ban=53, journald=54,
  hooks_json_b64=55); `var.image_name` default is `…:latest` (variables.tf:47);
  **no `docker login`** in runcmd → the `soleur-web-platform` GHCR package is public;
  fail2ban(476)/journald(488) precede docker install(509-526); `cron-egress-nftables.sh`
  is DOCKER-USER/container-scoped so host `docker pull` is never firewall-blocked;
  the Dockerfile already COPYs `/app/infra/*` artifacts (Dockerfile:155).

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality (measured) | Plan response |
|---|---|---|
| gzip the whole user_data fixes it | web gzip+base64 = 140,856 B (4.3× over) | Reject; externalize |
| git-data host is blocked too | git-data renders ~28,087 B, **under** cap | Web-host-only; git-data guard-only |
| trim the largest offenders | web rendered ~282 KB | Trimming can't reach 32 KB |
| 7+ scripts inlined | **24** file() args; **22** externalizable (fail2ban+journald stay), + hooks.json | Externalize 22 scripts + hooks.json |
| externalize scripts → fits | 22 scripts alone = **38,913 B, still over** | ALSO externalize hooks.json → 29,631 B |

## User-Brand Impact

- **If this lands broken, the user experiences:** a fresh/replacement web host
  (web-2, or HA recovery of web-1) silently fails to come up — during a scale or
  failover event users routed to that host get degraded/absent service. Steady
  state is unaffected (web-1 has `ignore_changes=[user_data]`).
- **If this leaks, the user's data/workflow/money is exposed via:** N/A — backend
  provisioning infra; no user data/schema/auth/API surface (git-data host, which
  holds user git data, is untouched). Exposure-adjacent risk if botched: an
  extraction failure leaving container egress OPEN (#5046) — closed by the
  fail-closed sentinel below.
- **Brand-survival threshold:** `aggregate pattern` — a broken fetch-at-boot
  degrades capacity for the aggregate of users needing a fresh host, not a
  single-user data incident. No CPO sign-off; `observability-coverage-reviewer`
  and `security-sentinel` are the gating reviewers.

> Sharp edge: a plan whose `## User-Brand Impact` section is empty/placeholder
> fails `deepen-plan` Phase 4.6 — this section is filled.

## Acceptance Criteria

### Phase 0 preconditions (verify, record in PR body — not ACs)
- P0a — `ghcr.io/jikig-ai/soleur-web-platform` is public (auth-free extraction pull), consistent with the existing `docker pull ${image_name}` at cloud-init.yml:592.
- P0b — `apps/web-platform/infra/**` is within `web-platform-release.yml` / `reusable-release.yml` `check_changed` path filter, so a script/hooks-tmpl edit rebuilds the image (ADR-080 silent-no-op trap). Widen the filter in this PR if not.

### Pre-merge (PR / CI)
- [ ] **AC1 — web user_data under cap with headroom.** After externalizing 22 scripts + hooks.json, the rendered web `user_data` is < 30,500 bytes (measured ≈29,631). Verified by AC7.
- [ ] **AC2 — 22 scripts + hooks.tmpl baked.** `apps/web-platform/Dockerfile` COPYs the 22 script/unit/config files **and** `hooks.json.tmpl` into `/opt/soleur/host-scripts/`. (A glob/dir COPY is acceptable and avoids a 22-name enumeration; the boot combined-hash (AC5) + per-file assertion (AC4) catch any missing/divergent file, so a separate CI "COPY-set == removed-set" parity test is not required.)
- [ ] **AC3 — keep-inline set preserved.** `fail2ban-sshd.local`, `journald-soleur.conf`, the sshd-hardening drop-in, and the three `/etc/default/{disk,resource,container-restart}-monitor` secret files stay inline `write_files`; `server.tf` retains `fail2ban_sshd_local_b64`, `journald_soleur_conf_b64`, and the non-file args. A test asserts these paths are still inline and both b64 args still present in server.tf. *(server.tf keep-list = image_name, webhook_deploy_secret, fail2ban_sshd_local_b64, journald_soleur_conf_b64, tunnel_token, doppler_token, resend_api_key, ci_ssh_public_key_openssh, host_scripts_content_hash.)*
- [ ] **AC4 — extraction: ordered, loud, per-file, mode-correct.** The extraction runcmd block: (a) inserts after the docker restart (cloud-init.yml:526) and before the first consumer (webhook enable :565); (b) opens with a bounded `docker info` readiness poll; (c) `docker rm -f soleur-hostscript-seed || true` + `trap cleanup EXIT` then `docker create`; (d) `docker pull` with `--retry` (bounded loop, mirror :495/:559) and NO `|| true`; (e) `install -D` each file with its **authoritative per-file mode** (scripts `0755`, units/allowlists `0644`, all `root:root`), NEVER a preserve-mode copy (`cp -a/-p`, direct `docker cp`-to-dest); (f) per-file assertion — `test -x` for scripts, `test -f` for units, plus `[ "$(stat -c %a /usr/local/bin/infra-config-install)" = 755 ]` and not group/other-writable (it is a sudo-NOPASSWD root target); (g) reload the service manager. A test asserts no `|| true` on the pull, the per-file assertions exist, and the combined-hash verify (AC5) precedes `install`.
- [ ] **AC5 — combined content-hash integrity.** Terraform computes ONE `host_scripts_content_hash` = `sha256` over the sorted per-file `filesha256()` of the 22 scripts + `hooks.json.tmpl`, injected into `user_data` (~70 B). At boot, after extraction and BEFORE `install`, the stub recomputes the same hash from the extracted files and aborts (signal emitted, no sentinel) on mismatch. A test asserts the render var exists and the boot recompute+compare is present. *(This also makes a stale/mis-built image fail the boot loudly — the ADR-080 coherence guard.)*
- [ ] **AC6 — hooks.json externalized, secret injected at boot.** `hooks_json_b64` is REMOVED from the `user_data` templatefile map; `hooks.json.tmpl` is baked into the image; at boot the stub extracts it and injects `webhook_deploy_secret` (retained render-var) via a literal-safe substitution (jsonencode-equivalent) → the webhook hooks file, with the same post-write validation as the SSH path (server.tf:536-557). `local.hooks_json` and the web-1 SSH provisioner path (server.tf:527) are UNCHANGED. A test asserts `hooks_json_b64` no longer appears in the `hcloud_server.web` user_data map and `webhook_deploy_secret` still does.
- [ ] **AC7 — size guard test (primary deliverable).** New `plugins/soleur/test/cloud-init-user-data-size.test.ts` (bun:test) recomputes rendered `user_data` for **both** `hcloud_server.web` and `hcloud_server.git_data` from template + `file()` sources (base64 = `4*ceil(bytes/3)`; variable-length secrets modeled with fixed placeholders) and FAILs if either > 30,500 B, with a non-vacuity floor (web > 5,000 B). **AC11's live `terraform plan` is the byte-exact source of truth**; this test catches the gross re-inlining regression class, not byte-exact fidelity.
- [ ] **AC8 — fail-closed sentinel gate.** The extraction stub writes `/run/soleur-hostscripts.ok` ONLY after hash-verify + all installs + all assertions pass. The terminal app `docker run` runcmd block (cloud-init.yml:685) is gated: `test -f /run/soleur-hostscripts.ok || { echo "FATAL: host-script extraction incomplete"; poweroff -f; }`. A test asserts both the sentinel write (last) and the run-block gate exist — because cloud-init `runcmd` is NOT under a top-level `set -e`, block-scoped `set -e` cannot be relied on to halt the sequence.
- [ ] **AC9 — observability signal (see `## Observability`).** SSH-free, discriminating; drops the periodic heartbeat.
- [ ] **AC10 — ADR + C4 landed.** `## Architecture Decision (ADR/C4)` deliverables committed (ADR-080 amendment + `.c4` edit + C4 render tests green).

### Post-merge (operator, gated behind #5887)
- [ ] **AC11 — publish before cutover.** The app image carrying the baked scripts + hooks.tmpl is built + pushed (normal `web-platform-release.yml`) **before** #5887's cutover creates the first fresh host, AND the applied Terraform is from the same commit (so `host_scripts_content_hash` matches the baked files — else the boot aborts by design). Order: merge code → release builds+pushes image → verify a fresh `terraform plan` renders web `user_data` < 32,768 → #5887 cutover.
- [ ] **AC12 — rollback path.** Runbook documents SSH-free recovery: fix + re-release the image, `terraform apply` to **recreate** the fresh host (re-runs cloud-init). No SSH fallback (`hr-no-ssh-fallback-in-runbooks`).

## Implementation Phases

### Phase 1 — Bake scripts + hooks.tmpl into the app image
- `apps/web-platform/Dockerfile`: `COPY --from=builder /app/infra/…` the 22 scripts + `hooks.json.tmpl` into `/opt/soleur/host-scripts/` (mirror Dockerfile:154-155). Prefer a glob/dir copy over a 22-name list.

### Phase 2 — Terraform + cloud-init edits
- `server.tf`: delete the 22 externalized `base64encode(file())` args (lines 44-52 and 56-68). **Keep** `fail2ban_sshd_local_b64` (53), `journald_soleur_conf_b64` (54), and all non-file args. **Remove** `hooks_json_b64` (55); ADD `host_scripts_content_hash` (combined sha256, AC5) and keep `webhook_deploy_secret`. `local.hooks_json` and the web-1 provisioner at :527 are unchanged.
- `cloud-init.yml`: delete the 22 script `write_files` blocks and the `hooks.json` `write_files` block; keep the fail2ban/journald/sshd/`/etc/default/*` blocks. Insert the extraction runcmd block after the docker restart (:526) and before the webhook enable (:565): readiness poll → retrying `docker pull ${image_name}` → `docker create`/`docker cp :/opt/soleur/host-scripts/.` → recompute+verify `host_scripts_content_hash` → per-file `install -D` with authoritative modes → hooks.tmpl secret-inject → per-file assertions → reload the service manager → write `/run/soleur-hostscripts.ok`. Gate the terminal `docker run` block (:685) on the sentinel.

### Phase 3 — Size guard + structural tests (TDD: failing first)
- `plugins/soleur/test/cloud-init-user-data-size.test.ts` (AC1/AC7): web & git-data < 30,500 B; non-vacuity floor.
- Structural asserts (AC3/AC4/AC5/AC6/AC8): keep-inline set present; no `|| true` on pull; per-file assertions; hash-verify precedes install; `hooks_json_b64` absent from user_data map; sentinel write + run-block gate present.

### Phase 4 — Observability
- Implement the Sentry discriminating event in the `set -e` trap + document the provision-armed Better Stack absence check (see `## Observability`). No new Terraform resource.

### Phase 5 — ADR + C4
- Amend ADR-080; edit the `.c4` model per `## Architecture Decision (ADR/C4)`.

## Files to Edit
- `apps/web-platform/infra/server.tf` — drop 22 file() args + hooks_json_b64; add host_scripts_content_hash.
- `apps/web-platform/infra/cloud-init.yml` — remove 22 script blocks + hooks block; add extraction runcmd; gate terminal docker run.
- `apps/web-platform/Dockerfile` — COPY 22 scripts + hooks.json.tmpl into `/opt/soleur/host-scripts/`.
- `knowledge-base/engineering/architecture/decisions/ADR-080-runtime-plugin-deploys-via-image-rebuild.md` — amendment (fresh-host cloud-init delivery path).
- `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4}` — C4 (see ADR/C4).
- `.github/workflows/web-platform-release.yml` / `reusable-release.yml` — only if P0b shows the infra path is outside the build-trigger filter.

## Files to Create
- `plugins/soleur/test/cloud-init-user-data-size.test.ts` — rendered-size + structural guards.

## Mock / pseudo-code (extraction stub shape)

```sh
# cloud-init.yml runcmd, inserted after the docker restart (:526).
# NOTE: runcmd is NOT under a top-level set -e; the sentinel gate on the terminal
# docker run block (below) is the real fail-closed mechanism.
set -e
for i in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 2; done
docker rm -f soleur-hostscript-seed >/dev/null 2>&1 || true
cleanup(){ docker rm -f soleur-hostscript-seed >/dev/null 2>&1 || true; }
trap cleanup EXIT
n=0; until docker pull ${image_name}; do n=$((n+1)); [ $n -ge 3 ] && exit 1; sleep 5; done
docker create --name soleur-hostscript-seed ${image_name}
S=$(mktemp -d); docker cp soleur-hostscript-seed:/opt/soleur/host-scripts/. "$S/"
# integrity: recompute combined hash from extracted files, compare to render-var
got=$(cd "$S" && find . -type f | sort | xargs sha256sum | sha256sum | cut -d' ' -f1)
[ "$got" = "${host_scripts_content_hash}" ] || { emit_fail hash_mismatch; exit 1; }
install -D -m0755 -o root -g root "$S/ci-deploy.sh" /usr/local/bin/ci-deploy.sh
install -D -m0644 -o root -g root "$S/cron-egress-firewall.service" "<unit-dir>/cron-egress-firewall.service"
# … 20 more install -D with per-file authoritative mode + dest renames …
sed "s|__WEBHOOK_DEPLOY_SECRET__|${webhook_deploy_secret}|" "$S/hooks.json.tmpl" > <webhook-hooks-file>  # + post-write validation
for f in /usr/local/bin/*.sh; do test -x "$f" || { emit_fail "missing $f"; exit 1; }; done
[ "$(stat -c %a /usr/local/bin/infra-config-install)" = 755 ] || exit 1
<reload-service-manager>
rm -rf "$S"; trap - EXIT
: > /run/soleur-hostscripts.ok   # sentinel LAST
# --- terminal `docker run` block (:685) gains, at its top: ---
# test -f /run/soleur-hostscripts.ok || { echo "FATAL: host-script extraction incomplete"; poweroff -f; }
```

## Infrastructure (IaC)

### Terraform changes
- `server.tf` — remove 22 `base64encode(file())` args + `hooks_json_b64` from the
  `hcloud_server.web` `templatefile()`; keep `fail2ban_sshd_local_b64`,
  `journald_soleur_conf_b64`, `webhook_deploy_secret`, and non-file args; add
  `host_scripts_content_hash = sha256(join("", sort([for f in <fileset> : filesha256(f)])))`.
  No `terraform_data.*` resource is modified (SSH/webhook provisioners = running-host path).
- `cloud-init.yml` — delete 22 script blocks + hooks block; add extraction runcmd
  (create + `docker cp` + hash-verify + per-mode `install` + hooks secret-inject +
  sentinel); gate the terminal `docker run`. Inline `content:` blocks + fail2ban/journald stay.
- `apps/web-platform/Dockerfile` — `COPY` 22 scripts + `hooks.json.tmpl` into
  `/opt/soleur/host-scripts/` (mirrors sandbox-canary + `_plugin-vendored` bakes).
- Providers/version: no new provider, no new managed resource, no state-shape change.
- Sensitive variables: none added. `webhook_deploy_secret` (existing, ~64 B) stays
  in user_data and is injected into the extracted hooks.tmpl at boot.

### Apply path
- **cloud-init-only** for the affected hosts; consumed only on a **fresh** host boot
  (web-2), an operator maintenance-window apply (`OPERATOR_APPLIED_EXCLUSIONS` covers
  `hcloud_server.web`/`git_data`), gated behind #5887. The code merge is a no-op for
  running web-1. The 22 scripts continue to reach running web-1 via the existing
  SSH/webhook provisioners (unchanged); hooks.json on web-1 via server.tf:527 (unchanged).

### Distinctness / drift safeguards
- **web-1 will not re-provision** (`ignore_changes=[user_data]`, server.tf:84) — the edit is inert on the live host.
- **dev != prd**: same app-image artifact; no Doppler dev/prd divergence. Baked scripts are version-coherent with `var.image_name` (same coupling as `_plugin-vendored`).
- **image↔config coherence enforced at boot**: `host_scripts_content_hash` (Terraform-computed at plan time from the source files) must equal the recompute from the extracted image files — a stale/mis-built image aborts the boot loudly (converts the ADR-080 silent-no-op into a loud failure).
- **git-data untouched** (renders ~28 KB) but added to the size guard.
- **`cloud-init-git-data.yml` byte-unchanged** — it has no `ignore_changes`, so any edit force-replaces the running git-data host (git-data.tf:141-144).

### Vendor-tier reality check
- **Hetzner cap 32,768 B.** Web today ~282 KB; gzip = 140,856 B (compression insufficient). After externalizing 22 scripts + hooks.json: **measured 29,631 B** (~3.1 KB headroom). git-data ~28 KB.
- **GHCR**: no new pull — `${image_name}` is already pulled at boot (:592); public (no `docker login`), so extraction is auth-free. Scripts ride `${image_name}` — no separate pinned tag, avoiding the inngest-style pin-drift (cloud-init.yml:617-634). NOTE: the extraction pull is now the FIRST/critical-path pull (hence `--retry` + provision-armed absence detection), not a cache-hit no-op.
- **R2**: unchanged (TF-state backend only). R2-tarball option rejected (new object to pin + new parity entry).

### Network-Outage / SSH apply-path note (gate 4.5)
This change's apply path is cloud-init-only (no `provisioner`/`connection ssh` on the fresh-host path). The **operator's maintenance-window apply** that provisions web-2 does traverse the web-1 SSH provisioners in `server.tf`; per `hr-ssh-diagnosis-verify-firewall`, that apply requires the operator's egress IP to be in the firewall allowlist (`/soleur:admin-ip-refresh` if drifted) BEFORE any sshd/service hypothesis. The code merge in THIS PR does not run those provisioners (web-1 `ignore_changes`), so it carries no SSH apply-time dependency.

## Observability

Fresh-host cloud-init boot is a **blind execution surface** (no SSH; CI can't reach the host). Signals must reach Sentry/Better Stack without SSH, with fields that discriminate the failure mode (Phase 2.9 + 2.9.2; `hr-observability-as-plan-quality-gate`, `hr-no-ssh-fallback-in-runbooks`, `hr-observability-layer-citation`).

```yaml
liveness_signal:
  what: fresh-host bootstrap health — the app container reports healthy within a bounded
        window of the provision (the extraction sentinel + terminal docker run gate mean
        an unhealthy extraction never yields a healthy app)
  cadence: one-shot per fresh-host provision (web-1 never re-runs cloud-init, so NO periodic
           heartbeat — that would false-alarm permanently)
  alert_target: Better Stack — the EXISTING web-app uptime monitor, provision-armed against
                the new host id at maintenance-window apply time (absence of health within the
                window = failure). This is the PRIMARY detector and catches pre-trap aborts
                (docker-install fail, apt/network fail, cloud-init parse error) that the trap
                cannot, because it does not depend on the failing host emitting anything.
  configured_in: apps/web-platform/infra (Better Stack uptime monitor + operator provision runbook)
error_reporting:
  destination: Sentry — on extraction/hash/install failure, the set -e trap curls the Sentry
               store API (DSN sourced from the on-host Doppler token available at extraction,
               cloud-init.yml:491-502) with { stage, failed_file, image_ref, host_id }, using
               curl --retry. This is the SECONDARY, DISCRIMINATING signal (fast root cause);
               it is NOT the sole detector (the absence check above is).
  fail_loud: true  # trap emits, then exit 1 → no sentinel → terminal docker run poweroffs → host visibly absent
failure_modes:
  - mode: cloud-init abort BEFORE the trap arms (docker install fail, apt/network, parse error)
    detection: provision-armed absence check (no healthy app within the window)
    alert_route: Better Stack uptime incident on the new host id
  - mode: docker pull fails / rate-limited / tag missing
    detection: bounded --retry loop then non-zero under set -e (trap)
    alert_route: Sentry { stage: pull, image_ref, host_id }
  - mode: combined-hash mismatch (stale/mis-built/compromised image)
    detection: boot recompute != host_scripts_content_hash
    alert_route: Sentry { stage: verify, host_id }; boot aborts (no sentinel)
  - mode: docker cp missing file / wrong arch
    detection: per-file test -x/test -f (arch-mismatch vs absent distinguished by the assertion)
    alert_route: Sentry { stage: extract, failed_file, host_id }
  - mode: install perm/dest failure (incl. infra-config-install mode != 755)
    detection: install -D non-zero / stat assertion under set -e
    alert_route: Sentry { stage: install, failed_file, host_id }
  - mode: egress-firewall unit absent → OPEN container egress (security regression #5046)
    detection: cron-egress-firewall assertion fails → no sentinel → terminal run poweroffs
    alert_route: Better Stack absence (host never serves) — fail-closed, never green-but-open
logs:
  where: cloud-init-output.log on host (SSH-only, insufficient alone); the Sentry event +
         Better Stack absence are the SSH-free paths. Once journald-persistent + Vector are up,
         a structured `soleur-hostscript-seed status=ok` line drains to Better Stack.
  retention: Better Stack / Sentry per existing plan
discoverability_test:
  command: >-
    bun test plugins/soleur/test/cloud-init-user-data-size.test.ts  # asserts extraction has the
    per-file assertion, hash-verify-before-install, sentinel write, terminal-run gate, and no
    `|| true` on the pull; NO ssh
  expected_output: green — web + git-data < 30500; extraction fail-closed + discriminating signal present
```

## Architecture Decision (ADR/C4)

Extends ADR-080's image-baked-host-asset model to the fresh-host cloud-init bootstrap
scripts + hooks.json — an architectural decision, so the ADR + C4 edits are deliverables
of THIS PR (`wg-architecture-decision-is-a-plan-deliverable`).

### ADR
- **Amend ADR-080** (`…runtime-plugin-deploys-via-image-rebuild.md`) — its scope is already
  "host-run assets are baked into the image + `docker cp`-seeded." Add a section: fresh-host
  cloud-init bootstrap scripts + `hooks.json.tmpl` are delivered by the SAME image-bake +
  `docker cp` path (cloud-init-fresh), while running hosts keep the SSH/webhook `terraform_data`
  path; both install identical content from the same source files. Record: (a) the two-path
  contract; (b) scripts ride `var.image_name` (no separate pinned tag → no inngest-style
  pin-drift); (c) the `host_scripts_content_hash` boot-time integrity + image↔config coherence
  invariant; (d) the 32,768-byte `user_data` budget enforced by the new size guard; (e) GHCR
  public/auth-free-at-boot. (A standalone new ADR referencing ADR-080/ADR-068 is also defensible
  per architecture-strategist; the amendment is preferred for proportionality — same mechanism.)

### C4 views
Read `model.c4`, `views.c4`, `spec.c4`. Enumeration: no new external human actor. **GHCR** is
the boot image source and is currently unmodeled (no `ghcr`/`registry` element); the change makes
the host↔image coupling load-bearing for bootstrap. Add a `ghcr` element (`#external`, model.c4:205-211)
+ edge `hetzner -> ghcr "Pulls app image + baked bootstrap scripts/hooks at boot" { technology "Docker/GHCR" }`
+ the `views.c4` include line; refine the `hetzner` description (model.c4:166) to note bootstrap
scripts are extracted from the image at boot. Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Sequencing
Amendment authored now (target state); ADR-080 status stays `Adopting`. Not deferred.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)
**Status:** reviewed
**Assessment:** GO, conditional — conditions folded into ACs: CI size-guard is the primary
deliverable (AC7); thin margin → enforced sub-cap guard (AC1); SSH-blind surface → non-SSH
discriminating signal (AC9/Observability); bake into `${image_name}` not a new pinned image;
no `|| true` on the extraction path (AC4). No-go if the size-guard is deferred or the fresh-boot
failure path has no non-SSH signal. `observability-coverage-reviewer` + `security-sentinel` are
the gating PR reviewers (not `user-impact-reviewer` — degraded-service, not single-user data).

### Product/UX Gate
Not applicable — no UI surface. Product = NONE.

**Brainstorm-recommended specialists:** none (one-shot pipeline).

## Test Scenarios
- web & git-data rendered `user_data` < 30,500 B (AC7); non-vacuity floor.
- server.tf keep-list correct: fail2ban/journald b64 present, hooks_json_b64 absent, host_scripts_content_hash present (AC3/AC6).
- Extraction block: readiness poll, `--retry` pull, no `|| true`, hash-verify-before-install, per-file mode assertions, sentinel-write-last (AC4/AC5).
- Terminal docker run gated on sentinel (AC8).
- C4 render tests green (AC10).

## Risks & Mitigations
- **Thin margin (~29.6 KB / 3.1 KB headroom).** Mitigation: < 30,500 B guard (AC7) fails CI on re-inlining; AC11 live `terraform plan` is byte-exact truth.
- **Extraction/pull failure = silent absence.** Mitigation: `set -e` + per-file assertions + fail-closed sentinel gate (AC8) + non-SSH signals (AC9).
- **Supply-chain (public `:latest`, host-root scripts).** Mitigation: `host_scripts_content_hash` verified at boot (AC5); no secret is baked (verified — only hooks.tmpl STRUCTURE, secret injected at boot).
- **`terraform plan` breakage from dropping fail2ban/journald args.** Mitigation: AC3 keeps them (22 externalized, not 24).
- **ADR-080 silent-no-op (stale image).** Mitigation: P0b build-trigger + AC5 boot hash-verify (loud on stale image).
- **Precedent-diff:** the `docker create`/`docker cp`/`--retry`/`trap` shape mirrors the plugin-seed (cloud-init.yml:606-608) + inngest-bootstrap (:635-665) + the `--retry` at :495/:559 — established precedents, adopted verbatim. No novel pattern.

## Sequencing (safe-to-merge before #5887)
1. Merge is a no-op for running web-1 (`ignore_changes=[user_data]`); no fresh host until #5887's cutover → blast radius today is zero.
2. Merge code → `web-platform-release.yml` builds + pushes the image (scripts + hooks.tmpl baked).
3. Verify a fresh `terraform plan` renders web `user_data` < 32,768 AND the applied commit == the image build commit (so `host_scripts_content_hash` matches).
4. **Then** #5887 operator cutover provisions web-2/git-data. Use `Ref #5921` (not `Closes`) if the fresh-host provision is not completed in this PR's lifecycle; close #5921 after a fresh host boots green.

## Sharp Edges
- Only **22** scripts externalize — `fail2ban-sshd.local`/`journald-soleur.conf` (consumed pre-Docker) AND their `server.tf` b64 args stay, or `terraform plan` fails.
- **hooks.json must be externalized too** — 22 scripts alone is still ~38.9 KB (over cap); only the small `webhook_deploy_secret` stays inline.
- cloud-init `runcmd` has NO top-level `set -e` — the sentinel gate on the terminal `docker run`, not block-scoped `set -e`, is the fail-closed mechanism.
- Per-file install modes are heterogeneous (scripts 0755, units/allowlists 0644); a firewall SCRIPT installed 0644 is non-executable → open egress. No preserve-mode copies.
- Do NOT edit the `-target=` allow-list to "unblock" #5887 (forces a prod reboot).
- Do NOT touch `cloud-init-git-data.yml` (no `ignore_changes` → force-replaces the running host).
