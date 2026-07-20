# Runbook — birthing or rebuilding a web host (operator-local)

**Status:** current as of 2026-07-20 (#6575).
**Applies to:** `hcloud_server.web["web-1"]` — the sole web host serving `app.soleur.ai`.

## Why this runbook exists

There is **no automated path** that births or recreates a web host. Every automated route that
can reach `hcloud_server.web` HALTs on `host_creates > 0`:

| Route | Gate |
|---|---|
| `apply-web-platform-infra.yml` job `apply` (per-merge) | `host_creates` HALT (#6416) |
| `apply-deploy-pipeline-fix.yml` (push:main) | `host_creates` HALT (#6718) |
| `workspaces-luks-cutover.yml` | gate requires zero actions on the web-1 server |

Building an automated, image-pinned birth path is tracked by
[#6730](https://github.com/jikig-ai/soleur/issues/6730). Until it lands, this procedure is the
only correct way, and it runs from an operator machine.

The two dispatches older runbooks name — `apply_target=web-2-recreate` and
`apply_target=warm-standby` — were **deleted** by #6575 after web-2 retired (#6538). `gh workflow
run` returns HTTP 422 for both. Do not go looking for them.

## Why the pin matters (read before running)

`var.image_name` defaults to the **mutable** tag `ghcr.io/jikig-ai/soleur-web-platform:latest`,
while `local.host_scripts_content_hash` is computed from the **applying commit's** host-script
files. Cloud-init recomputes that hash at boot and compares:

```
[ "$GOT" = "$HOST_SCRIPTS_HASH" ] || exit 1
```

That `exit 1` runs under `set -e` **before** the `set +e` region, so a mismatch aborts the entire
`runcmd` at `stage=verify`: no cloudflared, no webhook, no monitors, no egress firewall. `runcmd`
is once-per-instance, so **no reboot repairs it** — the host is dark until it is replaced.

Pinning a digest and verifying coherence *before* applying is what prevents that.

`hcloud_server.web` carries `lifecycle.ignore_changes = [user_data, ssh_keys, image,
placement_group_id]`, which has two consequences: an edit to cloud-init is **inert** for a running
host (only a create/replace picks it up), and the digest you pin here is honoured **at create
time** — a later routine apply will not drift it back to `:latest`.

## Procedure

### 1. Resolve a digest and pin it

```bash
DIGEST=$(crane digest ghcr.io/jikig-ai/soleur-web-platform:latest)
PINNED="ghcr.io/jikig-ai/soleur-web-platform@${DIGEST}"
echo "$PINNED"
```

`crane` is not preinstalled: `go install github.com/google/go-containerregistry/cmd/crane@latest`.
Any OCI digest reader works.

**Rebuilding a host while the current web-1 is still serving?** Prefer its *known-good* running
version over mutable `:latest` — `:latest` may have advanced past what is proven good in prod:

```bash
VERSION=$(curl -sS https://app.soleur.ai/health | jq -r .version)
TAG=$(bash apps/web-platform/infra/scripts/resolve-web1-known-good-tag.sh "$VERSION")
DIGEST=$(crane digest "ghcr.io/jikig-ai/soleur-web-platform:${TAG}")
PINNED="ghcr.io/jikig-ai/soleur-web-platform@${DIGEST}"
```

That resolver applies a strict three-part-semver guard and refuses anything else, so a
`:latest`-shaped or empty `.version` fails loudly rather than pinning garbage.

### 2. Verify image/apply coherence — MANDATORY

```bash
PINNED="$PINNED" bash apps/web-platform/infra/scripts/host-image-coherence-preflight.sh
```

This copies the pinned image's baked `/opt/soleur/host-scripts` out, recomputes their combined
sha256 **byte-identically to the cloud-init boot check**, and compares it against
`terraform console local.host_scripts_content_hash`.

- **exit 0** — coherent, safe to apply.
- **non-zero** — DO NOT APPLY. The host would abort at `stage=verify` and boot dark. Either pin an
  older digest whose baked scripts match, or wait for the image rebuild that matches this commit
  (`web-platform-release.yml` rebuilds on every merge to `main`).

Nothing is destroyed by a failed preflight — it runs before any apply.

### 3. Assert `SENTRY_DSN` is non-empty — MANDATORY

```bash
test -n "$(doppler secrets get SENTRY_DSN -p soleur -c prd_terraform --plain)" \
  || echo 'EMPTY SENTRY_DSN — do NOT create the host'
```

This is **not** optional and **nothing enforces it automatically** (#6575 removed the only
enforcement along with the `web_2_recreate` job; ADR-128 R1 makes it a MUST for #6730's birth
path).

The pre-extraction boot stages read **only** the baked `${sentry_dsn}` — Doppler is not installed
yet, so its documented fallback is dead code at that point. An empty DSN means a fresh host boots
**dark**: it fails, emits nothing, and pages nobody. You would find out when a user tells you
`app.soleur.ai` is down.

### 4. Apply with the pin

```bash
cd apps/web-platform/infra
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform apply -var image_name="$PINNED"
```

Read the plan before confirming. Expect a create of `hcloud_server.web["web-1"]` and its
dependents; anything touching another host's data volume is a stop signal.

### 5. Verify the boot

`runcmd` is once-per-instance, so a silent failure is terminal. Confirm:

- **Serving:** `curl -sS -o /dev/null -w '%{http_code}\n' https://app.soleur.ai/health` returns 200.
- **Boot telemetry:** check Sentry for `soleur-cloud-init boot stage` events on the new host id.
  A `fatal` at any stage means the boot died there; `cloud_init_complete` means it finished.
- **No page is not proof of health.** `betteruptime_monitor.app` probes the `app.soleur.ai`
  A-record, which *is* web-1 — on a dead web-1 it reddens only once the host is already dark.

## References

- ADR-128 — the two coherence invariants, the verifier retention rule, and R1–R5 (the
  requirements #6730's birth path must implement)
- ADR-096 — `OPERATOR_APPLIED_EXCLUSIONS`, the routing the `host_creates` HALT falls back to
- ADR-114 — origin-relative ingress; hazard #5 is the delivery-channel skew this preflight guards
- #6730 — build the automated, digest-pinned birth path that replaces this manual procedure
- #6712 — the residual apply-time skew this procedure mitigates by pinning
- `moved-block-wedge-cutover-5887.md` — historical #5887 cutover record (its web-2 sections are
  superseded and not executable)
