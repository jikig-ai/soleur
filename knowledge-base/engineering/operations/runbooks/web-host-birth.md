# Runbook — birthing a web host

**Status:** current as of 2026-07-26 (#6730, ADR-145).
**Applies to:** any `hcloud_server.web[<key>]` declared in `var.web_hosts`, including `web-1`.

**Birthing `web-1` needs `-f image_tag=<vX.Y.Z>`.** The pin defaults to whatever web-1 is
currently serving, read from its live `/health` — which is circular when web-1 is the host
being born. Pass the last known-good released version explicitly; it still goes through the
strict-semver guard, the digest resolve and the coherence preflight. Without it the job
aborts rather than guessing, and during a web-1 outage it would abort every time.

## The procedure

### Step 0 — check the escrow config before you start; diagnose an abort (#9377)

A host born (or replaced) after #9377 reads its LUKS key and header-escrow pair from the separate
`prd_workspaces_luks_web` config. The provisioner **formats even when escrow is missing, by design**, so the
dispatch itself refuses to start without it: the `Escrow readiness preflight` step of `web-host-create` and
`web-host-replace` runs `scripts/web-host-escrow-preflight.sh` before any Terraform command, and **any
non-zero result aborts the run with nothing changed** (1 contract violated, 2 no token, 3 the config could not be
read; an unreadable config is never treated as a missing one).

**Ask first, with no human step.** The same check runs on its own, read-only, in a dispatch-only workflow, so you
learn the answer **before** you start a birth. Dispatch it from `main`, find the run created by your dispatch, watch it, and
read the verdict from the run log. The gh CLI exposes no job-summary field, so the log carries everything you need. Run it as
ONE shell call (the variables must survive between the commands):

```bash
W=web-host-escrow-diagnose.yml
B=$(gh run list --workflow=$W --limit 1 --json databaseId --jq '.[0].databaseId // 0')   # B: the newest run id before your dispatch
gh workflow run $W --ref main
for i in 1 2 3 4 5 6; do sleep 5; ID=$(gh run list --workflow=$W --event workflow_dispatch --branch main --limit 5 --json databaseId --jq "[.[]|select(.databaseId>$B)]|last|.databaseId // empty"); [ -n "$ID" ] && break; done
echo "run id: ${ID:-NONE}"; [ -n "$ID" ] || { echo "no run found: stop and report"; exit 1; }
timeout 540 gh run watch "$ID" --exit-status -i 10 >/dev/null; echo "watch-rc=$?"           # 0 green, 1 red, 124 still queued or running after 9 minutes
gh run view "$ID" --json headSha,conclusion --jq '"headSha=\(.headSha) conclusion=\(.conclusion)"'
git fetch -q origin main && git rev-parse origin/main        # the current main head, after the run
gh run view "$ID" --log | grep -E 'Z (Verdict: |Run-context: |escrow-split-contract:)'
```

The run is the one created after your dispatch (a higher id than B; dispatch is asynchronous, hence the short wait), and it is
fresh only if its `headSha` equals the `origin/main` printed after it. Take the verdict **only** from the **last** line that
starts with `Verdict:` right after the log timestamp, and read the `Run-context:` line for the commit, the person or agent
that dispatched, and the UTC time (several agents of one operator share one identity, so it names the dispatcher, not you).
Never test the log for `live-ok` or `PASS` as bare substrings: GitHub echoes the step's script into the log, and that text
contains both. A **green run with no `Verdict:` line did not run the check and is NOT a pass**. Dispatch at most twice per
session without a changed cause.

The run changes nothing: no Terraform, no Doppler write, `contents: read`. A ref that does not carry the file fails at
dispatch, before any run exists. A ref other than `main` that does carry it is stopped by the `infra-privileged`
environment's main-only policy: the run is created and its job is blocked before any step runs. That is expected; dispatch
with `--ref main` and never retry it with a token workaround.

| You see | It means | Do this |
|---|---|---|
| The credential-loading step red, no `Verdict:` line; its annotation contains `verdict=` (for example `no_credential_source`, `privileged_read_failed`, `privileged_empty`) | The Tier-B read token or the workplace-token entry in `soleur-infra-privileged` is missing, rejected or empty | Stop and report; do not loop. Read the annotation with `gh run view "$ID"`. The repairs are steps O2 (re-seed the project keys) and O3 (the read token and its environment seeding) of [infra-credential-tiers-8209.md](./infra-credential-tiers-8209.md), and they need a workplace-scoped Doppler login. Never run step O13's `DOPPLER_TOKEN_TF` revocation from this table: it is gated on O12b |
| Red or cancelled, no `Verdict:` line and no loader annotation (the job hit its 10-minute limit, was cancelled, or lost its runner) | The loader or the runner stalled before the check could report | Dispatch once more. A second identical outcome means Doppler or the network is down: stop and report |
| `gh workflow run` failed, or the run exists but its job never started | The ref is not `main`, or the workflow file is not on `main` yet | Dispatch with `--ref main`; if the file is absent from `main`, the PR that adds it has not merged |
| `watch-rc=124` with a run id (the run is still queued or running after 9 minutes) | No runner picked it up, or the job is stuck | Run the watch once more; a second 124 means stop and report with the run id. Do not dispatch again while it is still queued |
| Green, but no `Verdict:` line | The check step did not run its body (for example a `SHELLOPTS` value that skips execution) | **Not a pass.** Stop, open the step log and report |
| **PASS** | The five names are in `prd_workspaces_luks_web` and none of web-1's pair is in the `prd` root | The names are in place; do not birth on this alone. The check cannot see the signed `HEAD` of web-1's bucket with the new pair returning 403, which the mint step on #9377 requires. Read the latest comments on #9377 with the command under this table and look for an operator comment, dated after this pair's names appeared, that states both 403 results. If there is none, stop and report: do not birth |
| **NO TOKEN** (exit 2) | No provider token reached the check. Usually the Tier-B project has no usable workplace-token entry; the check also exits 2 when its own tools are missing | Read the step log. Stop and report: re-seeding the entry (step O2 of the same runbook) needs a workplace-scoped Doppler login. Never run step O13's revocation from this table |
| **FAIL** (exit 1) | A name is missing, or a forbidden one is present (`WORKSPACES_LUKS_KEY` or web-1's R2 pair in the `prd` root); the `CAUSE` lines say which family of missing name: a Terraform-managed name not created yet (none was missing on 2026-10-04; no workflow creates them now, see "Before any host dispatch" below), or the R2 pair (the live mint, the only gap on that date) | Stop and report to the operator: both families are operator steps. Never copy web-1's pair into the new config, and never delete a `prd` name to make this pass (a forbidden-name `FAIL` has no `CAUSE` line) |
| **NOT READY** (exit 1) | The check exited 0 but did not print the exact `escrow-split-contract:live-ok` line: a checker or workflow defect, which does not change between runs | Stop and report; open the step log. Do not dispatch again |
| **UNREADABLE** (exit 3) | A config could not be read. The checker reads `prd_workspaces_luks_web` first, so a bad or rotated token names it too. A `NOTE` line means Doppler reported the config as not found; without one, read the vendor detail in the step log (`Invalid Auth token` means the provider token is bad, rotated or not re-seeded) | Stop and report. With a `NOTE`, `prd_workspaces_luks_web` could not be read (it was in state on 2026-10-04, and no workflow creates it now): report it with the `NOTE` line and do not dispatch anything from here. Otherwise suspect the workflow before the credential on a first dispatch; the operator, not you, re-seeds the carrier entry from the current token (step O2 pattern) rather than rotating, and never run step O13's revocation from this table |
| **UNEXPECTED exit 124** (or **137**) | The check timed out after 240 seconds (137: it ignored the termination signal and was killed): Doppler or the network stalled | Dispatch once more; a repeat means Doppler is down: stop and report |
| **UNEXPECTED**, including exit 78 | The check ended in a way this table does not cover (78 is the check refusing to run under shell tracing) | Open the step log, look for tracing (`xtrace`, `SHELLOPTS`), fix it by a pull request, dispatch again |

```bash
gh issue view 9377 --json comments --jq '.comments[-6:][]|.createdAt+" "+(.body|.[0:600])'
```

The `NOTE` line reads: `escrow-split-contract:NOTE prd_workspaces_luks_web was not found; this is usually consistent with the web-platform push-apply (apply-web-platform-infra.yml) not having created it yet (unmeasured: the read failed, absence of the config is not proven)`. That says what the failed read is consistent with; it is not a diagnosis. (Read the push-apply's current state before relying on it. The single-use workflow that once created the three names is retired, and the apply HALT now refuses a create of the web-class passphrase pair.) The checker prints one `escrow-split-contract:CAUSE` line per family of missing name and is the single source for the cause map; it is not repeated here.

**A green run is necessary, not sufficient, and valid only when it ran.** The check reads secret *names*, so it cannot tell a
bucket-scoped R2 pair from web-1's pair pasted under the same names (the mint step on #9377 requires a signed `HEAD` of
web-1's bucket with the new pair to return 403), and it says nothing about a later change. The log's `Run-context:` line
prints the commit and the UTC time. Cite a green run only if it was created by your dispatch in this birth session (an id above
B), its `headSha` equals the current `main` head, and no more than an hour has passed; otherwise dispatch again. The birth and
replace jobs re-run the same preflight themselves (with their own copy of the read token) and still abort on any non-zero
result with nothing changed; the break-glass path below runs the preflight by hand and does not use this workflow.
Back-to-back dispatches are harmless to the environment. A red run blocks nothing automated: repair the named cause and
dispatch again.

The token this check uses is the workplace personal token the Tier-B loader exports. Read-only is a property of the workflow's
steps, not of the token; a narrower credential is tracked in <https://github.com/jikig-ai/soleur/issues/9461>.

**Before any host dispatch.** Four facts carry over from the retired escrow-create step:

1. The preflight (the diagnostic above, or the dispatch's own `Escrow readiness preflight` step) must print
   `escrow-split-contract:live-ok` before the web-host workflow is dispatched. The check is names only: it proves neither the
   R2 pair's scope nor its values.
2. The R2 credential pair is not Terraform (the stored Cloudflare tokens lack the "API Tokens: Edit" scope, so a
   `cloudflare_api_token` apply 403s). Its mint and the signed isolation proof stay tracked on #9377, which was still open on
   2026-10-06; its 2026-10-05 comment reports the pair minted and the isolation proven, and the preflight cannot confirm
   that. Until the pair exists the preflight fails with the checker's missing-R2-pair `CAUSE` line.
3. `web_host_create` and `web_host_replace` are jobs of `apply-web-platform-infra.yml`. When that workflow is disabled at the
   time (read its state with `gh workflow view apply-web-platform-infra.yml`), the push-apply enable window applies: enable
   it for the dispatch, dispatch, then disable it again, and note that a merge to main inside the enabled window triggers
   its push-apply.
4. Losing the passphrase pair or the escrow bucket has no automated creation route: the apply HALT refuses a `create` of
   `random_password.workspaces_luks_web` and `doppler_secret.workspaces_luks_web_key`, and no workflow creates them. The recovery
   is a reviewed change that imports the existing state entry, merged with the push-apply kill-switch line, never a re-create.
   If a web-class volume may be formatted, never remove or overwrite the existing entry. Run the import while no applier is
   queued, and record it on #9372.

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

Break-glass means the dispatch is unavailable, so the diagnostic workflow in Step 0 is unavailable too and this runs by hand. It needs a workplace-scoped Doppler login. The provider token is the value `DOPPLER_TOKEN_TF` in Doppler project `soleur-infra-privileged`, config `prd` (step O10 of [infra-credential-tiers-8209.md](./infra-credential-tiers-8209.md) removed it from `soleur/prd_terraform`, so a read from there no longer works). The command passes it through the environment only, never echoed:

```bash
TF_VAR_doppler_token_tf="$(doppler secrets get DOPPLER_TOKEN_TF -p soleur-infra-privileged -c prd --plain)" bash scripts/web-host-escrow-preflight.sh
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
- [Runbook — the web-2 LUKS rebirth (#9372, single-use)](./web2-luks-rebirth-9372.md) — the volume conversion that a plain `web-host-create` of web-2 cannot do
