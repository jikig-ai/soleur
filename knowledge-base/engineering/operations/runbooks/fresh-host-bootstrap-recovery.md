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

- **PRIMARY — Better Stack uptime absence (no host emission required).** The existing
  web-app uptime monitor, provision-armed against the new host id at maintenance-window
  apply, fires an incident if the host does not report healthy within the provision
  window. Catches pre-trap aborts (docker/apt/network/cloud-init-parse failures) that
  the on-host trap cannot signal. **A failed bootstrap = a host that never serves = a
  Better Stack incident.** No dashboard-gazing (`hr-no-dashboard-eyeball-pull-data-yourself`).
- **SECONDARY — Sentry discriminating event.** On extraction/hash/install failure the
  bootstrap's `set -e` trap (and the launcher's pre-verify trap) POST a Sentry event
  tagged `{ stage, failed_file, image_ref, host_id }` — `stage` ∈ pull/extract/verify/
  install/hooks/assert. Use it to jump straight to root cause. Best-effort (DSN via the
  on-host Doppler token); the PRIMARY absence check is authoritative.

## Root-cause by `stage`

| `stage` | Meaning | Most likely cause |
|---|---|---|
| `pull` | `docker pull ${image_name}` failed after 3 retries | GHCR/registry/network; image tag missing |
| `extract` | `docker create` / `docker cp` failed | image lacks `/opt/soleur/host-scripts/` (build regression) |
| `verify` | boot recompute ≠ `host_scripts_content_hash` | **stale / mis-built / tampered image** — the applied Terraform commit ≠ the image build commit (AC11), or a supply-chain issue |
| `install`/`hooks`/`assert` | a file failed to install / hooks.json invalid / assertion failed | build baked a bad file; disk/permission issue |

## Recover (SSH-free — `hr-no-ssh-fallback-in-runbooks`)

There is **no SSH remediation**. The fresh-host path runs only cloud-init.

1. **Fix the cause** (bad script, bad Dockerfile COPY, wrong applied commit).
2. **Re-release the image** via the normal `web-platform-release.yml` so GHCR carries a
   corrected `ghcr.io/jikig-ai/soleur-web-platform` image whose baked files match the
   Terraform `host_scripts_content_hash` **at the commit you will apply**.
3. **`terraform apply` to RECREATE the fresh host** (re-runs cloud-init from scratch).
   For a `verify` (hash-mismatch) failure specifically: ensure the applied Terraform
   commit == the image build commit, else the boot aborts again **by design**.
4. Confirm recovery via the PRIMARY signal: the Better Stack uptime monitor clears and
   `app.soleur.ai/health` reports the expected `build_sha`.

## Guardrails

- Do **not** SSH in to hand-install the scripts — that reintroduces the drift the
  baked-hash invariant exists to prevent, and leaves the host in an unverifiable state.
- Do **not** relax the sentinel gate to "start anyway" — a host that serves without the
  egress firewall is the #5046 open-egress regression.
- The **running** host (`web-1`, `ignore_changes=[user_data]`) is unaffected by this
  path; its scripts arrive via the SSH/webhook `terraform_data` provisioners.
- git-data host bootstrap is a **different mechanism** (no docker) — see #5927.
