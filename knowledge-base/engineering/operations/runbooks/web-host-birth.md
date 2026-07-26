# Runbook — birthing a web host

**Status:** current as of 2026-07-26 (#6730, ADR-145).
**Applies to:** any `hcloud_server.web[<key>]` declared in `var.web_hosts`, including `web-1`.

**Birthing `web-1` needs `-f image_tag=<vX.Y.Z>`.** The pin defaults to whatever web-1 is
currently serving, read from its live `/health` — which is circular when web-1 is the host
being born. Pass the last known-good released version explicitly; it still goes through the
strict-semver guard, the digest resolve and the coherence preflight. Without it the job
aborts rather than guessing, and during a web-1 outage it would abort every time.

## The procedure

Dispatch `web-host-create` and approve it:

```bash
# web-2 (or any host with a healthy sibling serving app.soleur.ai)
gh workflow run apply-web-platform-infra.yml \
  -f apply_target=web-host-create \
  -f web_host_key=web-2 \
  -f confirm=BIRTH-web-2 \
  -f reason='birth web-2 — <why>'

# web-1, or any birth while the fleet is down — the pin source must be explicit
gh workflow run apply-web-platform-infra.yml \
  -f apply_target=web-host-create \
  -f web_host_key=web-1 \
  -f confirm=BIRTH-web-1 \
  -f image_tag=v1.2.3 \
  -f reason='rebirth web-1 after <incident>'
```

The run pauses on the `web-platform-infra-apply` environment for reviewer approval before its
first step. Approve it in the Actions UI. That approval is the **only** human input; everything
below happens inside the job.

`web_host_key` must be a key that already exists in `var.web_hosts`
(`apps/web-platform/infra/variables.tf`) — this job births a host that is already declared, it
does not declare one. The `confirm` token must be exactly `BIRTH-<key>`; it is a typo-guard, not
the authorization, and it embeds the key so that authorizing the wrong host requires typing that
host's name.

### What the job does, and why each step is not optional

| Step | Guards against |
|---|---|
| Validates the key's shape and its membership in `var.web_hosts` | A typo'd key plans zero creates and would otherwise abort with a message about `-target` scope, hiding the real cause. |
| Asserts `SENTRY_DSN` non-empty in Doppler `prd_terraform`, failing closed if it is *unreadable* | The pre-extraction boot stages emit through the baked `${sentry_dsn}` and nothing else. Empty ⇒ a failed birth emits nothing and pages nobody (ADR-128 R1). |
| Resolves web-1's running version → tag → immutable `@sha256` digest, once | A mutable `:latest` can move between the coherence check and the apply, which would defeat the check entirely. |
| Runs `host-image-coherence-preflight.sh` against the pinned digest | An image whose baked host-scripts disagree with the applied hash aborts cloud-init at `stage=verify` (see below). Pre-apply, so nothing is created on a doomed boot. |
| Plans the host's **nine-address fan-out** and grades it with the inverted birth gate | Exactly one create, of the requested host, zero destroys/reboots/out-of-scope changes. |
| Surfaces the fresh host's Sentry boot trail, `if: always()` | A green apply is not a green boot — the two are indistinguishable without asking Sentry. |

### Why the pin matters

`var.image_name` defaults to the **mutable** tag `ghcr.io/jikig-ai/soleur-web-platform:latest`,
while `local.host_scripts_content_hash` is computed from the **applying commit's** host-script
files. Cloud-init recomputes that hash at boot and compares:

```
[ "$GOT" = "$HOST_SCRIPTS_HASH" ] || exit 1
```

That `exit 1` runs under `set -e` **before** the `set +e` region, so a mismatch aborts the entire
`runcmd` at `stage=verify`: no cloudflared, no webhook, no monitors, no egress firewall. `runcmd`
is once-per-instance, so **no reboot repairs it** — the host is dark until it is replaced. That is
why the preflight is mandatory and runs before anything is created.

`hcloud_server.web` carries `lifecycle.ignore_changes = [user_data, ssh_keys, image,
placement_group_id]`, which has two consequences: an edit to cloud-init is **inert** for a running
host (only a create/replace picks it up), and the pinned digest is honoured **at create time** — a
later routine apply will not drift it back to `:latest`.

### Why the `host_creates` HALT still exists

Every *other* route to `hcloud_server.web` still HALTs, and that is deliberate:

| Route | Gate |
|---|---|
| `apply-web-platform-infra.yml` job `apply` (per-merge) | `host_creates` HALT (#6416) |
| `apply-deploy-pipeline-fix.yml` (push:main) | `host_creates` HALT (#6718) |
| `workspaces-luks-cutover.yml` | gate requires zero actions on the web-1 server |

`-target` is transitive at the resource level, so the per-PR apply reaches the *server* but not
its `hcloud_server_network` attachment. A host born there comes up with no private IP and —
because `hcloud_firewall_attachment` does not attach before first boot — transiently no firewall.
That is #6416. The birth dispatch is safe precisely because it targets the whole fan-out and
proves it did; the HALT protects the paths that cannot.

**Consequence to plan around:** adding a key to `var.web_hosts` makes every subsequent merge to
main HALT until that host is actually born. Dispatch promptly after the merge that introduces the
key.

## Verify the result

- **Boot telemetry:** the run's own step summary carries the fresh-host Sentry trail. Expect
  `cloud_init_complete` as the last-reached stage; a `fatal` names where the boot died.
- **Serving** (only for a host that is in the serving path):
  `curl -sS -o /dev/null -w '%{http_code}\n' https://app.soleur.ai/health` returns 200.
- **No page is not proof of health.** `betteruptime_monitor.app` probes the `app.soleur.ai`
  A-record, which *is* web-1 — on a dead web-1 it reddens only once the host is already dark.

## Break-glass: operator-local apply

**Use this only when the dispatch itself is unavailable** (Actions down, the workflow broken).
It is the pre-#6730 procedure and it reproduces by hand every gate the job enforces
automatically — including the two that are easiest to skip and worst to skip.

<details>
<summary>Operator-local procedure</summary>

### 1. Resolve a digest and pin it

```bash
VERSION=$(curl -sS https://app.soleur.ai/health | jq -r .version)
TAG=$(bash apps/web-platform/infra/scripts/resolve-web1-known-good-tag.sh "$VERSION")
DIGEST=$(crane digest "ghcr.io/jikig-ai/soleur-web-platform:${TAG}")
PINNED="ghcr.io/jikig-ai/soleur-web-platform@${DIGEST}"
```

Prefer web-1's *known-good running* version over mutable `:latest`, which may have advanced past
what is proven good in prod. The resolver applies a strict three-part-semver guard and refuses
anything else, so a `:latest`-shaped or empty `.version` fails loudly rather than pinning garbage.

`crane` is not preinstalled: `go install github.com/google/go-containerregistry/cmd/crane@latest`.
Any OCI digest reader works — `docker buildx imagetools inspect <ref> --format '{{.Manifest.Digest}}'`
needs no extra install (authenticate to GHCR first; the package is private).

### 2. Verify image/apply coherence — MANDATORY

```bash
PINNED="$PINNED" bash apps/web-platform/infra/scripts/host-image-coherence-preflight.sh
```

- **exit 0** — coherent, safe to apply.
- **non-zero** — DO NOT APPLY. The host would abort at `stage=verify` and boot dark. Pin an older
  digest whose baked scripts match, or wait for the image rebuild that matches this commit
  (`web-platform-release.yml` rebuilds on every merge to `main`).

Nothing is destroyed by a failed preflight — it runs before any apply.

### 3. Assert `SENTRY_DSN` is non-empty — MANDATORY

```bash
test -n "$(doppler secrets get SENTRY_DSN -p soleur -c prd_terraform --plain)" \
  || echo 'EMPTY SENTRY_DSN — do NOT create the host'
```

An empty DSN means a fresh host boots **dark**: it fails, emits nothing, and pages nobody. You
would find out when a user tells you `app.soleur.ai` is down.

### 4. Apply with the pin

```bash
cd apps/web-platform/infra
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform apply -var image_name="$PINNED"
```

Read the plan before confirming. Expect a create of `hcloud_server.web[<key>]` **and its private
NIC** — a server create without `hcloud_server_network.web[<key>]` is the #6416 shape. Anything
touching another host's data volume is a stop signal.

</details>

## References

- ADR-145 — this birth path: why the HALT is inverted rather than removed, and the alternatives rejected
- ADR-128 — the two coherence invariants, the verifier retention rule, and R1–R5 (met by the dispatch)
- ADR-096 — `OPERATOR_APPLIED_EXCLUSIONS`, the routing the `host_creates` HALT falls back to
- ADR-114 — origin-relative ingress; hazard #5 is the delivery-channel skew this preflight guards
- #6712 — the residual apply-time skew this procedure mitigates by pinning
- `moved-block-wedge-cutover-5887.md` — historical #5887 cutover record (its web-2 sections are
  superseded and not executable)
