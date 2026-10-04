# Runbook — birthing a web host

**Status:** current as of 2026-07-26 (#6730, ADR-145).
**Applies to:** any `hcloud_server.web[<key>]` declared in `var.web_hosts`, including `web-1`.

**Birthing `web-1` needs `-f image_tag=<vX.Y.Z>`.** The pin defaults to whatever web-1 is
currently serving, read from its live `/health` — which is circular when web-1 is the host
being born. Pass the last known-good released version explicitly; it still goes through the
strict-semver guard, the digest resolve and the coherence preflight. Without it the job
aborts rather than guessing, and during a web-1 outage it would abort every time.

## The procedure

### Step 0 — the workflow checks the escrow config for you; diagnose an abort (#9377)

A host born (or replaced) after #9377 reads its LUKS key and header-escrow pair from the separate
`prd_workspaces_luks_web` config. The provisioner **formats even when escrow is missing, by design**, so the
dispatch itself refuses to start without it: the `Escrow readiness preflight` step of `web-host-create` and
`web-host-replace` runs `scripts/web-host-escrow-preflight.sh` before any Terraform command, and **any
non-zero result aborts the run with nothing changed** (1 contract violated, 2 usage, 3 the config could not be
read; an unreadable config is never treated as a missing one). There is nothing to run beforehand.

When the step goes red, the cause is in its annotations and its own log: the checker prints one `escrow-split-contract:CAUSE` line
per family of missing name (the push-apply has not created it, or the live R2 mint has not been done). That
output is the single source for the cause map; it is not repeated here. **If `prd_workspaces_luks_web` does not exist at all**,
the checker exits 3 and prints a NOTE instead of a CAUSE line: `escrow-split-contract:NOTE prd_workspaces_luks_web was not found; this is usually consistent with the web-platform push-apply (apply-web-platform-infra.yml) not having created it yet (unmeasured: the read failed, absence of the config is not proven)`.
That says what the failed read is consistent with; it is not a diagnosis. To re-run the identical check while
diagnosing, from a checkout (an agent can run this: the wrapper reads the provider token itself and the command below
passes it through the environment only, never echoed):

```bash
TF_VAR_doppler_token_tf="$(doppler secrets get DOPPLER_TOKEN_TF -p soleur -c prd_terraform --plain)" bash scripts/web-host-escrow-preflight.sh   # names only, never values
```

That token is write-capable; a read-only preflight token is tracked in <https://github.com/jikig-ai/soleur/issues/9461>.

It must print `escrow-split-contract:live-ok`. The check is **necessary, not sufficient**: it reads secret
*names*, so it cannot tell a bucket-scoped R2 pair from web-1's pair pasted under the same names — the mint step
on #9377 requires a signed `HEAD` of web-1's bucket with the new pair to return 403.

**If `escrow=missing` pages anyway** (alert `web-host-luks-boot-fatal`, stage `workspaces_luks_provision_escrow`;
the boot continued, the volume is formatted, the header has no off-host copy): escrow is attempted **once, at
birth**, so the only way to re-attempt it is a host replace (`web-host-replace`, with the config repaired first).
While the web-class host holds no user data that costs one replace. Once a web-class host holds data, the
remediation of this page is owned by the #9372 follow-up; no re-escrow step is defined here.

Read the stage's events for a host (no SSH):

```bash
# <host> is the server name: soleur-<web_host_key> (web-1 is soleur-web-platform)
doppler run -p soleur -c prd -- bash scripts/sentry-issue.sh --host-events <host> --stage workspaces_luks_provision_escrow
```

The event's detail reads `arm=escrow reason=<x>`; decode `<x>` with the table below. No event for the stage on a
fresh birth means escrow succeeded or the boot never reached it (the readiness row's `escrow=ok` is the positive
signal). That page is rate-limited by the alert's frequency throttle (**35 minutes, per rule per issue group**), and
every boot event from every host lands in one perpetually-active Sentry issue group, so the throttle is
**fleet-wide and spans boots**: an escrow page within 35 minutes of any other `web-host-luks-boot-fatal` page (any of
its fourteen stages, on any host, including an earlier failed attempt of this same birth) can be folded into
silence, and an escrow page can equally swallow a fatal one that follows it. Do not rely on the email alone: after
every web-class birth or replace, read the stage with the command above.

| `reason=` | Meaning | Remediation (the boot continued and the volume is formatted; escrow is attempted once, so every one ends in a host replace) |
|---|---|---|
| `creds` | At least one of the four names (bucket, key id, secret, endpoint) read back empty from `prd_workspaces_luks_web`. | Repair the config (the preflight reads names only, so an empty value passes it), then replace the host. |
| `shape` | The **bucket or the endpoint** failed its pattern (a lowercase DNS-style bucket name; exactly `https://<32 hex>.r2.cloudflarestorage.com`). | Fix the value in `prd_workspaces_luks_web`, then replace the host. |
| `creds_shape` | The **R2 key id or secret** failed its pattern (key id: 16 to 128 alphanumerics; secret: 16 to 256 of `A-Za-z0-9/+=_-`), for example a stray quote, space or newline from a paste. No value is ever echoed. | Re-mint or re-paste the pair cleanly in `prd_workspaces_luks_web`, then replace the host. |
| `uuid` | `cryptsetup luksUUID` did not return a UUID for the opened container. | Local to the host (not a config problem); replace the host. |
| `tmp` | The tmpfs directory for the header copy could not be created. | Local to the host; replace the host. |
| `backup` | `cryptsetup luksHeaderBackup` failed or wrote an empty file. | Local to the host; replace the host. |
| `put` | R2 refused the upload (a non-2xx answer): the pair is not write-scoped to the bucket, the bucket or endpoint is wrong, or R2 was unavailable. | Repair the config, then replace the host. No automated check of the pair's R2 scope or of R2 availability exists yet; the mint procedure and its probe are owned by the #9377 mint comment. |
| `readback` | The object read back after the upload did not match the header's size and md5 (an ETag mismatch). | Replace the host. No automated check of R2 availability exists yet; a persistent mismatch is owned by the #9377 mint comment. |

**During an outage, when the preflight cannot pass.** The preflight has **no in-workflow bypass**, by design (an
aborted dispatch costs one reviewer approval and a second dispatch needs a second one). If it cannot pass while the
fleet is down, the only route is the break-glass operator-local apply below, which **does not run the checker**:
repair `prd_workspaces_luks_web` first, or the host is born with `escrow=missing`. A **web-1** rebirth is not a
supported recovery today whatever the preflight says: a rebuilt web-1 fails closed at the provisioner's
`discriminate` arm (see "`web-1` is refused" in `web-host-replace.md`), and that stays true until the de-pet
rebuild (#9421).

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
| Plans the host's **ten-address fan-out** and grades it with the inverted birth gate | Exactly one create, OF the requested host, WITH its private NIC and volume attachment, and zero destroys/reboots/out-of-scope changes. The NIC and attachment are required, not merely permitted — a server without them is #6416 and silent data loss respectively. |
| Includes `cloudflare_record.app` in the fan-out | `-target` is transitive upstream only, so the apex A record — a *dependent* of the server — would otherwise never re-point. On a web-1 birth that means a green run and `app.soleur.ai` still resolving to the dead host. |
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
- **A web-2 birth/rebirth rotates its sshd host key.** `terraform_data.deploy_pipeline_fix_web2`
  (#9151) then fails closed at its pinned `host_key` — re-capture with
  `scripts/capture-web-2-host-key.sh <new-ip>` and land `web-2-ssh-host-key.pub` in a PR
  (ADR-237; `web-host-replace.md` carries the same note).

## Break-glass: operator-local apply

**Use this only when the dispatch itself is unavailable** (Actions down, the workflow broken).
It is the pre-#6730 procedure and it reproduces by hand every gate the job enforces
automatically — including the escrow preflight (step 0, which no part of the pre-#6730 procedure ran) and the two that
are easiest to skip and worst to skip.

<details>
<summary>Operator-local procedure</summary>

### 0. Run the escrow readiness preflight — MANDATORY (#9377)

```bash
TF_VAR_doppler_token_tf="$(doppler secrets get DOPPLER_TOKEN_TF -p soleur -c prd_terraform --plain)" bash scripts/web-host-escrow-preflight.sh
```

It must exit 0. The dispatch runs this as an in-job step; an operator-local run does not, and a host born without it is
formatted with `escrow=missing` (see Step 0 above for reading a red result, including the absent-config NOTE).

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

> **#8209 / ADR-241 — the single-loader form below is the PRE-cutover one.** After the Tier-B
> cutover the same command is wrapped by an outer `soleur-infra-privileged` loader, and the inner
> `prd_terraform` loader carries `--preserve-env` so the outer values win. Canonical form and
> rationale: [`infra-credential-tiers-8209.md`](./infra-credential-tiers-8209.md) §Local Terraform
> invocation.

```bash
cd apps/web-platform/infra
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform apply -var image_name="$PINNED"
```

Read the plan before confirming. Expect a create of `hcloud_server.web[<key>]` **and its private
NIC** — a server create without `hcloud_server_network.web[<key>]` is the #6416 shape. Anything
touching another host's data volume is a stop signal.

### 5. Verify the boot — MANDATORY

`terraform apply` returning 0 means the *server* was created, not that it *booted*. The dispatch
polls Sentry to a terminal state and fails the run on a dark boot; on this path nothing does, so
read the trail yourself. "Verify the result" above does not cover you here — it reads the run's
step summary, and a break-glass birth has no run.

```bash
export SENTRY_AUTH_TOKEN=$(doppler secrets get SENTRY_AUTH_TOKEN --plain -p soleur -c prd_terraform)
SENTRY_ORG=$(doppler secrets get SENTRY_ORG --plain -p soleur -c prd_terraform)
SENTRY_PROJECT=$(doppler secrets get SENTRY_PROJECT --plain -p soleur -c prd_terraform)

curl -sS -G -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
  --data-urlencode 'per_page=100' \
  --data-urlencode 'statsPeriod=1h' \
  --data-urlencode 'sort=-timestamp' \
  "https://de.sentry.io/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/events/" \
| jq -r '.[] | select(.title // .message // ""
    | test("soleur-hostscript-seed failed|soleur-host-bootstrap failed|soleur-host-bootstrap complete|soleur-cloud-init boot stage"))
    | "\(.dateCreated)  \(.title // .message)"'
```

Fetch **unfiltered and match client-side**, as above. The `/events/` endpoint silently ignores a
`message:"…"` search prefix and returns zero for events that provably exist — passing one produces
a confident, wrong "the host emitted nothing".

- **Expect** `cloud_init_complete` as the last-reached stage. A `fatal` names where the boot died.
- **Poll, do not sample once.** `cloud_init_complete` is the last line of cloud-init `runcmd` and
  the host's own budget is `SOLEUR_FRESH_BOOT_WINDOW_SECONDS=900`. Read immediately after apply and
  a *healthy* host looks identical to a dark one. Re-run until a terminal stage appears or ~16
  minutes elapse.
- **An empty result is not health.** This is a shared project — web-1 traffic and `host_metrics`
  can push the fresh host's events past the 100-event cap. Empty means *unproven*, not *good*.
- **A non-200 is not health either.** A failed read is a failed read; do not record it as a clean
  boot.

Then the serving check from "Verify the result" above, for a host in the serving path.

</details>

## Replacing an existing host

This runbook covers the ADDITIVE case only: a host declared in `var.web_hosts` that is absent
from the provider. A host that already exists cannot be birthed — the gate refuses a plan with
zero creates rather than rubber-stamping a no-op. To destroy and recreate an existing host, see
[Runbook — replacing a web host](./web-host-replace.md) (`apply_target=web-host-replace`,
#6969/ADR-148), which is a separate dispatch with its own gate and a `REPLACE-<key>` token.
That path refuses `web-1`.

## References

- ADR-148 — the REPLACE sibling of this path (what to use when the host already exists)
- ADR-145 — this birth path: why the HALT is inverted rather than removed, and the alternatives rejected
- ADR-128 — the two coherence invariants, the verifier retention rule, and R1–R5 (met by the dispatch)
- ADR-096 — `OPERATOR_APPLIED_EXCLUSIONS`, the routing the `host_creates` HALT falls back to
- ADR-114 — origin-relative ingress; hazard #5 is the delivery-channel skew this preflight guards
- #6712 — the residual apply-time skew this procedure mitigates by pinning
- `moved-block-wedge-cutover-5887.md` — historical #5887 cutover record (its web-2 sections are
  superseded and not executable)
