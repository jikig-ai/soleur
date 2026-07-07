# Runbook: fresh Hetzner web-host bootstrap failure — detect + recover (SSH-free)

Covers the `soleur-host-bootstrap.sh` extraction path introduced in #5921 (ADR-080
amendment). On a **fresh** web host (`web-2`, or HA recovery of `web-1`), cloud-init
pulls the web app image, `docker cp`s the baked `/opt/soleur/host-scripts/`, verifies
`host_scripts_content_hash`, then runs the baked bootstrap installer. If any step
fails, the host **refuses to serve** (`poweroff -f` on a missing
`/run/soleur-hostscripts.ok` sentinel) rather than come up with an unconfigured egress
firewall / missing deploy scripts. This is a **blind execution surface** — no SSH, CI
can't reach the host — so detection and recovery are both SSH-free.

## Detect

> ⚠️ **PRIMARY detector NOT YET IMPLEMENTED — tracked in #5933 (hard blocker on #5887 web-2
> provisioning).** The design calls for a per-host uptime absence check, but there is currently
> **no per-host web monitor** (the apex monitors cover the docs site; `app.soleur.ai` is a CF
> round-robin with no origin health-check). Until #5933 lands, a *pre-token* boot failure
> (before `/etc/default/webhook-deploy` exists — doppler-CLI install or the package audit) is
> **not observable**, and a failed host's A-record persists in the `app.soleur.ai` rotation (CF
> keeps sending it traffic). Do NOT provision web-2 until #5933 closes.

- **SECONDARY — Sentry discriminating event (the signal that exists today).** On
  extraction/hash/install failure **after** `/etc/default/webhook-deploy` is written, the
  bootstrap's `emit_fail` trap (and the launcher's pre-verify `on_err` trap) POST a Sentry event
  tagged `{ stage, failed_file, image_ref, host_id }` — `stage` in pull/extract/verify/install/
  hooks/assert/reload/journald. Fast root-cause path for the classes it covers; does NOT cover
  pre-token failures. Best-effort (DSN via the on-host Doppler token).
- **PRIMARY (once #5933 lands) — per-host uptime absence.** A per-host monitor hitting each
  host's origin directly, so the detector does not depend on the failing host emitting anything.
  A failed bootstrap = a host that never serves = an absence incident. No dashboard-gazing
  (`hr-no-dashboard-eyeball-pull-data-yourself`).

## Root-cause by `stage`

| `stage` | Meaning | Most likely cause |
|---|---|---|
| `pull` | `docker pull ${image_name}` failed after 3 retries | zot/GHCR/registry/network; image tag missing. Post-#6122 (ADR-096) the seed pull is **zot-primary with an atomic GHCR fallback** (dark-launch gated): it resolves the effective ref into `/run/soleur-image-ref` and retries the GHCR ref if zot misses, so a `pull` FATAL means BOTH registries failed. If zot is the suspect, revert via `zot-registry-revert.md` (unset `ZOT_REGISTRY_URL` → GHCR-primary) before recreating. |
| `extract` | `docker create` / `docker cp` failed | image lacks `/opt/soleur/host-scripts/` (build regression) |
| `verify` | boot recompute ≠ `host_scripts_content_hash` | **stale / mis-built / tampered image** — the applied Terraform commit ≠ the image build commit (AC11), or a supply-chain issue |
| `extract` | `docker create`/`docker cp` failed | image lacks `/opt/soleur/host-scripts/` (build regression) — note: a *missing/extra baked file* usually surfaces later at `verify` (hash) or `install`/`assert` (per-file), since `docker cp` of the whole dir succeeds |
| `install`/`hooks`/`assert` | a file failed to install / hooks.json invalid / assertion failed | build baked a bad file; disk/permission issue |
| `reload`/`journald` | `systemctl daemon-reload` / journald persistence apply failed | systemd/journald state issue (rare) |

<!-- lint-infra-ignore start -->
## Recover (SSH-free — `hr-no-ssh-fallback-in-runbooks`)

There is **no SSH remediation**. The fresh-host path runs only cloud-init.

1. **Fix the cause** (bad script, bad Dockerfile COPY, wrong applied commit).
2. **Re-release the image** via the normal `web-platform-release.yml` so GHCR carries a
   corrected `ghcr.io/jikig-ai/soleur-web-platform` image whose baked files match the
   Terraform `host_scripts_content_hash` **at the commit you will apply**.
3. **`terraform apply` to RECREATE the fresh host** (re-runs cloud-init from scratch).
   For a `verify` (hash-mismatch) failure specifically: ensure the applied Terraform
   commit == the image build commit, else the boot aborts again **by design**.
4. Confirm recovery: `app.soleur.ai/health` reports the expected `build_sha` (and, once #5933
   lands, the per-host uptime monitor clears).

**Mutable-`:latest` race (fail-safe, but know it):** `host_scripts_content_hash` is computed at
`terraform plan` from the source at commit X, but the host boots by pulling `…:latest`. If a new
web-platform image is pushed to `:latest` **between** `terraform apply` and the fresh host's first
boot, the boot hash (the new image's baked files) will not match the plan hash (commit X's
source) → the host aborts at `stage=verify` **by design** (loud, never wrong-serves). Do NOT push
a web-platform release during a fresh-host maintenance-window apply; if you must, re-apply so the
plan hash tracks the new image. (Digest-pinning `var.image_name` closes this race — tracked in
#5933.)

<!-- lint-infra-ignore end -->

## Guardrails

- Do **not** SSH in to hand-install the scripts — that reintroduces the drift the
  baked-hash invariant exists to prevent, and leaves the host in an unverifiable state.
- Do **not** relax the sentinel gate to "start anyway" — a host that serves without the
  egress firewall is the #5046 open-egress regression.
- The **running** host (`web-1`, `ignore_changes=[user_data]`) is unaffected by this
  path; its scripts arrive via the SSH/webhook `terraform_data` provisioners.
- git-data host bootstrap is a **different mechanism** (no docker) — see #5927.
