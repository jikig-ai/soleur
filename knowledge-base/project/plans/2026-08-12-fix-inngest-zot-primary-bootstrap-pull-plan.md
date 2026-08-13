---
title: "fix(inngest): give the dedicated host a zot-primary bootstrap pull path"
date: 2026-08-12
slug: fix-inngest-zot-primary-bootstrap-pull
branch: feat-one-shot-7462-inngest-zot-bootstrap-pull
issue: 7462
closes: []
lane: single-domain
type: bug-fix
priority: p1
domain: engineering
brand_survival_threshold: none
---

## Overview

The dedicated inngest host (`10.0.1.40`) cannot bootstrap. Its cloud-init hard-pins a
`ghcr.io` ref for the `soleur-inngest-bootstrap` OCI image, the GHCR read credential is
revoked, and the pull 401s six seconds into every boot. Because `inngest-bootstrap.sh`
ships *inside* that image, nothing is installed, nothing binds `:8288`, and every
app-originated dispatch fails.

Every other pull site in the fleet was flipped to prefer the self-hosted zot registry in the
ADR-096 Phase-3 dark-launch. This file was missed. This plan gives it the same zot-primary
arm, with GHCR retained as break-glass and a loud marker on the flip.

Scope is the pull path only. The cutover FSM, the flip guard, the monotonic latch, and the
Redis AOF volume are untouched.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Probe | Result |
|---|---|---|
| `#7462` is an open work target | `gh issue view 7462 --json state` | **OPEN**, `closed_by: []` — holds |
| `#7228` is an open work target | `gh issue view 7228 --json state` | **OPEN**, `closed_by: []` — holds |
| No merged PR already did this | body+title+`linked:issue` probes, then `gh pr diff --name-only` | `#7203` = mirror/push side only (empty intersection). `#7457` touches the same file but is the heartbeat/detection change — see decisive grep below |
| The zot arm is absent | `grep -c ZOT_REGISTRY_URL cloud-init-inngest.yml` on base `154302d32` | **0** — gap confirmed on a tree that already contains `#7457` |
| The pattern to mirror exists | `grep -c ZOT_REGISTRY_URL cloud-init.yml` | **3** |
| GHCR credential is revoked | `GET api.github.com/user`; GHCR pull-token mint | **401** / **403** — matches the ADR-096 amendment dated 2026-07-30 verbatim |

The ADR-096 corpus was grepped for the proposed mechanism (not the issue number). ADR-096
does not merely permit this change — it **names this exact file as the gap** and predicts this
exact failure: it records that the file "hard-pins a `ghcr.io` ref with no zot path, no `/v2/`
probe" and that revoking the PAT means "its next fresh boot" fails. The prediction came true:
the credential stopped working ahead of the planned Phase-5 task that was supposed to retire it
deliberately. This mechanism is the ADR's own prescription, not an unconsidered alternative.

### Property List (Phase 0.6b)

1. The host obtains its bootstrap image from a registry that currently serves it.
2. A registry miss that falls back is visible off-box, not silent.
3. A total pull failure names which legs were tried and why each failed.
4. An unconfigured/unreachable zot degrades to today's behaviour, never to a worse boot.
5. The digest pin still governs which bytes run.

### Cut List (Phase 0.6b)

| Mechanism considered | Property it would buy | Why cut |
|---|---|---|
| A new `/v2/` health-probe helper | #1 | `cloud-init.yml`'s arm already probes-then-falls-back; reuse its shape rather than invent a second one |
| A retry/backoff loop around the zot pull | #1 | Two independent registry legs already provide the redundancy; a retry adds boot latency on the dark path for no new property |
| A new Better Stack marker family | #2, #3 | `inngest-boot-phone-home.sh` already exists, already survives reboot (`bs-token-restage-enabled`), and is the channel that made this diagnosis possible. Extend its stage vocabulary; do not add a channel |
| Removing the GHCR leg entirely | — | Buys no property in the list and front-runs ADR-096's staged Phase-5 retirement |

### Research Reconciliation — Spec vs. Codebase

This is the section that changes the implementation. The invoking brief said "mirror the
existing arm in `cloud-init.yml`". The web-host arm resolves zot config **from Doppler at boot**
(`doppler secrets get ZOT_REGISTRY_URL --project soleur --config prd`). That mechanism does not
transfer to this host.

| Claim | Codebase reality | Plan response |
|---|---|---|
| Read the ZOT_* keys from Doppler, as `cloud-init.yml` does | The inngest host's Doppler token is scoped to project `soleur-inngest`, config `prd`. It has **no token for project `soleur`**, so those keys are unreadable from this host | Bake via terraform template vars instead |
| Add the ZOT_* keys to `soleur-inngest/prd` | `cloud-init-inngest.yml` runs a **fail-closed boot isolation self-check** asserting every visible non-DOPPLER secret is a known inngest name (`n_total == n_inngest`). Three new keys make `n_total(10) != n_inngest(7)` → **FATAL**, no Vector, no boot | **Rejected.** Leave the Doppler config and the isolation allowlist untouched. The bake path avoids this check by construction |
| `zot_pull_user` / `zot_pull_token` TF variables exist | `grep zot_pull variables.tf` → **no matches**. The web host never needed them (it reads Doppler) | New variables required, `sensitive = true`, no default (`hr-tf-variable-no-operator-mint-default`) |
| The endpoint needs deriving | `local.registry_endpoint = "${local.registry_private_ip}:5000"` already exists in the same TF root (`zot-registry.tf:44`, `10.0.1.30:5000`) | Pass `local.registry_endpoint` directly — no new derivation |
| Docker can pull from zot on this host | The insecure-registry entry exists in **`cloud-init.yml` only**. zot serves plain HTTP on the private net; docker refuses a non-TLS registry that is not allowlisted in its daemon config | **Second required change.** Without it the zot leg cannot succeed even with correct creds |

The bake precedent is already established on this exact host: `ghcr_read_user`,
`ghcr_read_token` and `betterstack_logs_token` are all baked as template vars in
`inngest-host.tf` (search `ghcr_read_user  = var.ghcr_read_user`), for the stated reason that
cold-boot must not depend on Doppler answering at the boot instant. The zot creds belong in
exactly that set.

### Key anchors

- `apps/web-platform/infra/cloud-init-inngest.yml` — the `IREF=ghcr.io/jikig-ai/soleur-inngest-bootstrap:...` assignment; the `ghcr-login-ok`/`ghcr-login-FAILED`/`ghcr-creds-EMPTY` phone-home block; the `pre-oci-pull` / `oci-pull-rc-` stages.
- `apps/web-platform/infra/cloud-init.yml` — the zot login block (`bootstrap's zot_login is too late`) and the ref-resolution block emitting `app_zot` / `app_ghcr_fallback`.
- `apps/web-platform/infra/inngest-host.tf` — the `templatefile(...)` var map.
- `apps/web-platform/infra/zot-registry.tf` — `local.registry_endpoint`, `hcloud_firewall.registry` (deny-all public; pull transport private-net only).

### Reachability

`hcloud_firewall.registry` denies public inbound; the registry is reached over the private net,
which is how web-1 (`10.0.1.10`) pulls today. The inngest host's own nftables scoping governs
**inbound** to `:8288`/`:8289`, not egress. Phase 0 carries an explicit reachability assertion
rather than assuming this.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned no issue whose body names
`cloud-init-inngest.yml`, `inngest-host.tf`, or `variables.tf`.

## Implementation Phases

Phase ordering is contract-first: the TF variables and the template-var wiring must exist
before the cloud-init consumer references them, or the consumer is dead code.

### Phase 0 — Preconditions (no edits)

1. Assert the bootstrap image digest currently pinned in `cloud-init-inngest.yml` is present in
   zot. The 2026-08-10 `build-inngest-bootstrap-image.yml` run's
   `Mirror inngest image GHCR→zot (crane, digest-preserving)` step reports success; confirm the
   **specific digest**, not just that a mirror ran. A zot-primary arm pointed at a digest zot
   does not hold would fall back on every boot.
2. Assert `10.0.1.40 → 10.0.1.30:5000` is permitted by the private-net topology.
3. Record both results in the PR body. If (1) fails, the plan stops here and the remedy is a
   `mirror_only=true` backfill dispatch, not a cloud-init edit.

### Phase 1 — RED tests

Extend `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` (and the host test
harness) with failing assertions for each mutation-matrix row in the Guard Contract below.
Tests land before the implementation (`cq-write-failing-tests-before`).

### Phase 2 — Terraform variables

`apps/web-platform/infra/variables.tf`: add `zot_pull_user` and `zot_pull_token`, both
`sensitive = true`, no default. These resolve from `TF_VAR_*` in Doppler `prd_terraform` like
every other root var.

### Phase 3 — Template-var wiring

`apps/web-platform/infra/inngest-host.tf`: extend the `templatefile(...)` map with
`zot_registry_endpoint = local.registry_endpoint`, `zot_pull_user = var.zot_pull_user`,
`zot_pull_token = var.zot_pull_token`, adjacent to the existing `ghcr_read_*` bake and carrying
the same rationale comment.

### Phase 4 — Docker insecure-registry entry

`cloud-init-inngest.yml`: add the baked zot endpoint to the docker daemon configuration's
insecure-registry list, mirroring the equivalent block in `cloud-init.yml` including its
justification (zot serves plain HTTP on the private net behind a deny-all-public firewall, so
docker rejects it unless allowlisted). cloud-init writes this into the daemon config file, so
the entry exists at first boot ahead of any pull.

### Phase 5 — zot login before the pull

`cloud-init-inngest.yml`: authenticate to zot from the baked creds in the same runcmd region as
the existing GHCR login, emitting `zot-login-ok` / `zot-login-FAILED` / `zot-creds-EMPTY`
phone-home stages that mirror the GHCR trio. Placement is load-bearing — the bootstrap image's
own `zot_login` runs too late to authorize the pull that fetches that very image.

### Phase 6 — zot-primary ref resolution

`cloud-init-inngest.yml`: resolve the effective ref once, before `pre-oci-pull`:

- When the baked endpoint is non-empty, try `<endpoint>/jikig-ai/soleur-inngest-bootstrap@<same-sha256>`.
- On success, emit `inngest_zot` (info) and use that ref for the pull **and** the subsequent
  `docker create`/`docker cp` extract, so every step follows one registry.
- On zot miss, emit `inngest_ghcr_fallback` (**warning** — this is what the fallback-rate alarm
  consumes) and fall back to the unchanged GHCR ref.
- When the endpoint is empty/unset, skip the zot leg entirely and take today's GHCR path.
- The `sha256:` digest is carried unchanged on both legs. The mirror is crane-copied
  digest-preserving, so the same digest must resolve on both.

### Phase 7 — both-legs-failed marker

`cloud-init-inngest.yml`: when both legs fail, emit a distinct, greppable phone-home stage
naming which legs were attempted and each leg's failure reason. Today's `oci-pull-rc-1` line
carried the whole diagnosis only because the phone-home channel happened to survive; make that
explicit rather than incidental.

## Files to Edit

- `apps/web-platform/infra/variables.tf`
- `apps/web-platform/infra/inngest-host.tf`
- `apps/web-platform/infra/cloud-init-inngest.yml`
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`

## Files to Create

None.

## Guard Contract

### Guard 1 — zot-primary bootstrap pull arm

**Property.** The dedicated inngest host resolves its bootstrap image from zot whenever zot is
configured and serving that digest; every registry outcome is reported off-box; and no registry
outcome yields a boot worse than today's GHCR-only path.

**Assembly.** The chokepoint is the single ref-resolution region in `cloud-init-inngest.yml`
that computes the effective ref before `pre-oci-pull`. Every consumer of the image ref
downstream of that point must read the resolved value, not re-derive it: the `docker pull`, the
`docker create ... -extract` container, and the `/etc/default/soleur-inngest-image` record.
There is exactly one such region and three such consumers — the guard quantifies over all
three, because a second consumer re-deriving the GHCR literal is precisely how a "zot-primary"
change ships while still pulling from GHCR.

**Mutation matrix.**

| # | Mutation | Guard must |
|---|---|---|
| 1 | Reorder so the GHCR ref is attempted first | RED |
| 2 | Drop the `@sha256:` digest from the zot ref (mutable tag) | RED |
| 3 | Silence the `inngest_ghcr_fallback` emit on the flip | RED |
| 4 | Point one downstream consumer (the extract container) at the GHCR literal while the pull uses zot | RED |
| 5 | Remove the both-legs-failed marker | RED |
| 6 | Make the test dispatch itself vacuous — assert the suite fails when it checks zero files | RED |

Row 6 targets the guard's own dispatch; row 4 adds a second member after a compliant first.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing new at merge — the change is inert until
delivered. If delivered broken, the dedicated host stays dark exactly as it is now, so
app-originated dispatch (inbound email, PR-review events) continues to fail silently.

**If this leaks, the user's data is exposed via:** the zot pull credential is baked into
`user_data`, retrievable via the Hetzner metadata API by anyone with host access. This is the
same trust boundary the existing `ghcr_read_token` and `betterstack_logs_token` bakes already
occupy, and the credential is read-only against a private-net registry. No widening.

**Brand-survival threshold:** none — this is a restoration of a currently-dark path. The failure
mode of the change is "stays dark", not "new user-facing breakage". No CPO sign-off required.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_INNGEST_BOOT_STAGE phone-home markers (shipper=cloud-init-phone-home)
  cadence: once per host boot
  alert_target: Better Stack (queryable via betterstack-query.sh). See the 2026-08-13 addendum — this does NOT reach the Sentry-based zot-soak fallback query.
  configured_in: apps/web-platform/infra/cloud-init-inngest.yml
error_reporting:
  destination: Better Stack Logs via inngest-boot-phone-home.sh (curl-direct, Vector-independent)
  fail_loud: true
failure_modes:
  - mode: zot configured but miss (digest absent, endpoint unreachable)
    detection: inngest_ghcr_fallback (warning)
    alert_route: zot fallback-rate alarm
  - mode: zot authentication fails
    detection: zot-login-FAILED
    alert_route: Better Stack marker query
  - mode: zot creds not baked
    detection: zot-creds-EMPTY
    alert_route: Better Stack marker query
  - mode: both registry legs fail
    detection: distinct both-legs-failed stage naming each leg and its reason
    alert_route: Better Stack marker query
logs:
  where: Better Stack (soleur-inngest source), plus host journald via Vector once bootstrap runs
  retention: ~3 days measured
discoverability_test:
  command: doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep inngest_zot --grep inngest_ghcr_fallback
  expected_output: at least one inngest_zot row after a delivered boot; no inngest_ghcr_fallback rows in steady state
  credentials_required: "Better Stack ClickHouse query connection — the log warehouse has no unauthenticated read surface"
```

This host is not SSH-inspectable by policy (`hr-no-ssh-fallback-in-runbooks`); every failure
mode above is reachable from Better Stack alone. Observability layer: the boot phone-home
channel, which is the layer that produced this diagnosis.

## Architecture Decision (ADR/C4)

No new ADR. This plan **executes** an existing decision rather than making one: ADR-096 already
chose zot as the registry and already identifies this file as an unmigrated pull site. Amend
ADR-096 in place to record that the inngest cold-boot pull site is now migrated, and that its
mechanism is a **terraform bake** rather than the Doppler fetch used elsewhere — because this
host's fail-closed secret-isolation check makes the Doppler path structurally unavailable. That
divergence is a fact a future reader would otherwise be misled about.

**C4 views:** no change. All three model files (`model.c4`, `views.c4`, `spec.c4`) were read.
The registry is already modeled as a container with the pull edge from the host set; this plan
changes which registry an existing edge resolves to, and adds no external actor (no new human
role, no new vendor — zot is self-hosted and already modeled, GHCR already modeled), no new
container, and no changed access relationship.

## Infrastructure (IaC)

### Terraform changes

`variables.tf` (+2 sensitive no-default vars), `inngest-host.tf` (+3 template vars). No new
provider, no new resource, no state-shape change.

### Apply path

cloud-init only, delivered by host replace. The file is baked into `user_data` and
`hcloud_server.inngest` deliberately carries no `lifecycle.ignore_changes=[user_data]`, so the
edit forces a replace. Its resources are excluded from the per-PR CI `-target`, so **the change
is inert at merge**. Delivery is the gated `apply_target=inngest-host-replace` dispatch, which
is out of scope for this PR.

### Distinctness / drift safeguards

The two new `TF_VAR_*` values must exist in Doppler `prd_terraform` before any merge-triggered
apply resolves root variables. Because the inngest resources are `-target`-excluded, a
merge-triggered apply does not reach them — but Terraform resolves **all** root variables before
`-target` pruning, so a no-default var that is unprovisioned fails the whole apply. Phase 2
therefore has a hard precondition: the values exist in `prd_terraform` before merge.

### Vendor-tier reality check

Not applicable — self-hosted registry, no vendor tier.

## Domain Review

**Domains relevant:** Engineering.

### Engineering

**Status:** reviewed
**Assessment:** Infrastructure restoration on an already-provisioned surface. The material
finding is the mechanism divergence (bake vs Doppler) forced by this host's secret-isolation
check; carried into Research Reconciliation and the ADR-096 amendment. No product, legal,
marketing, sales, finance, support, or operations implications. No UI surface — the Product/UX
gate's mechanical override does not fire (no path in Files to Edit matches a UI-surface glob).

## Encryption Posture

Not applicable — introduces no persistent store. The one new cross-component connection is
host → zot over the private net, which is **plain HTTP by existing design** (ADR-096: deny-all
public firewall, private-net-only transport, digest pinning as the integrity guard). This plan
adopts the established posture for that connection rather than introducing a new one; the
insecure-registry entry in Phase 4 is what makes the existing posture usable from this host.

## Acceptance Criteria

### Pre-merge

1. The baked-endpoint reference appears in `cloud-init-inngest.yml` where `grep -c '${zot_registry_endpoint}'` previously returned 0. **Amended 2026-08-13 (#7516)** — this AC originally named `ZOT_REGISTRY_URL`, which is the *Doppler key* the web host reads. It is a leftover from the superseded "mirror the arm in `cloud-init.yml`" framing that this plan's own Research Reconciliation rejected: the bake path never reads that key, so the literal command could not pass against a correct implementation. Verified command: `grep -c '\${zot_registry_endpoint}' apps/web-platform/infra/cloud-init-inngest.yml` → **2**, against **0** on `origin/main` (same command). The two sites are the docker daemon-config gate and the credential bake; the ref-resolution region deliberately reads the endpoint back from `/etc/default/soleur-zot-read` rather than re-interpolating the template var, so two copies of it cannot disagree.
2. The `sha256:` digest is byte-identical on the zot and GHCR refs; no mutable-tag form appears on either leg.
3. All three downstream ref consumers (pull, extract container, `/etc/default/soleur-inngest-image`) read the single resolved ref.
4. `zot_pull_user` / `zot_pull_token` are declared `sensitive = true` with no default.
5. Every Guard Contract mutation row drives the suite RED; the vacuity row (6) is included.
6. `terraform validate` passes on the infra root.
7. The full-suite gate is green, run at the commit under review.
8. Phase 0's two precondition results are recorded in the PR body.
9. The PR body states plainly that the change is inert at merge and names the gated dispatch as the delivery path.
10. The PR body records that the cutover-sequence arm step in `#7462` requires `INNGEST_DIAGNOSTIC_BOOT` cleared from `soleur-inngest/prd`; this PR deliberately leaves it set.
11. `#7462` and `#7228` are referenced (`Ref`, not `Closes`) and both remain open.

### Post-merge

None in this PR. Delivery and verification belong to `#7462` steps 4–6.

## Test Scenarios

1. Endpoint baked + digest present in zot → zot ref used, `inngest_zot` emitted, GHCR untouched.
2. Endpoint baked + digest absent from zot → `inngest_ghcr_fallback` (warning) emitted, GHCR ref used, boot proceeds.
3. Endpoint empty/unset → today's GHCR path exactly, no zot markers, no new failure.
4. Both legs fail → both-legs-failed marker names each leg and its reason.
5. zot creds absent while endpoint present → `zot-creds-EMPTY`, fallback to GHCR.
6. Digest-pin mutation → suite RED.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| zot lacks the pinned digest → fallback on every boot into a revoked GHCR = still dark | Phase 0 asserts the specific digest before any edit; failure stops the plan and routes to a `mirror_only=true` backfill |
| New no-default TF vars break a merge-triggered apply | Values provisioned in `prd_terraform` before merge; called out as a Phase 2 hard precondition |
| Baked pull credential widens the host's secret surface | Same trust boundary as the existing `ghcr_read_token` / `betterstack_logs_token` bakes; read-only, private-net scope |
| Editing this file forces a host replace | Already true of every line in it (ADR-100); delivery is deliberately deferred to the gated dispatch |
| The zot copy is unsigned while GHCR is signed | Pre-existing and unchanged: this cold-boot path performs no signature verification on either leg (documented in the file). Integrity rests on the digest pin, which this plan preserves. Not a regression introduced here |

## Addendum — 2026-08-13 (#7516, implementation)

Appended rather than edited in place. Each entry records a plan claim that measurement
changed, so a future reader sees what was believed and what was found.

### Phase 0 results (both preconditions HOLD)

**0.1 — digest present in zot.** Re-probed LIVE rather than read off the 2026-08-10 record:
`build-inngest-bootstrap-image.yml` run **31681702541** (`mirror_only=true`, 2026-08-13T08:26Z)
reported `ghcr=sha256:6cdaa63d…a0f8 zot=sha256:6cdaa63d…a0f8` — identical to each other and to
the `cloud-init-inngest.yml` pin — and `crane validate --remote` returned
`PASS: 127.0.0.1:5000/jikig-ai/soleur-inngest-bootstrap:v1.1.24`.

The re-probe was not ceremony. The plan asked only that the mirror step's success name the
specific digest; the 2026-08-10 run did, but zot runs gc + dedupe, and the workflow's own
comment records that a reclaimed layer yields **green digest parity and `blob unknown` on the
host's docker pull**. `crane validate --remote` fetches every blob, so it answers the question
a pin actually depends on. A three-day-old manifest HEAD would not have.

**0.2 — `10.0.1.40 → 10.0.1.30:5000` permitted.** Three independent legs, all from source:
`hcloud_server_network.inngest` (10.0.1.40) and `hcloud_server_network.registry` (10.0.1.30)
attach to the same `hcloud_network_subnet.private`; `hcloud_firewall.registry` carries ZERO
inbound rules and Hetzner firewalls filter only the PUBLIC interface, so intra-network traffic
is open by membership; and `inngest-nftables.sh` declares an `input` chain only — no `output`
chain exists, so egress from this host is unrestricted. `cloud-init-registry.yml` adds no
host-local packet filter on `:5000`.

### Corrections to plan claims

| Plan claim | Measurement | Resolution |
|---|---|---|
| AC1's verify command greps `ZOT_REGISTRY_URL` | That is the *Doppler key* the web host reads; the bake path never reads it, so the literal command cannot pass against a correct implementation | AC1 amended in place (leftover from the framing this plan's own Research Reconciliation rejected) |
| `inngest_ghcr_fallback` "feeds the existing zot fallback-rate alarm" | The soak's `[freshboot]='stage:"inngest_ghcr_fallback"'` entry in `scripts/followthroughs/zot-soak-6122.sh` is a **Sentry** query. This host has ZERO `soleur-boot-emit` occurrences — that emitter ships with the WEB host's host-script bundle — so its markers reach **Better Stack only** and the Sentry soak does not count them | Implemented as specified (stage name identical to the web host's, so one Better Stack query covers both) and the divergence recorded in-file. NOT closed here: adding a Sentry route would be a new channel, which this plan's own Cut List rejected. Tracked for ADR-096 Phase 5, whose GHCR-retirement decision is the consumer that would need it |
| "Files to Create: None" | AC5 requires every mutation row to drive the suite RED. Verified once by hand, that is an observation that decays | Added `cloud-init-inngest-zot-pull-mutation.test.sh`, following the three sibling `*-mutation.test.sh` suites already registered. Deliberate scope deviation, recorded here |
| Guard assembly quantifies over "three such consumers" | The file carries a **fourth** — `docker inspect "$IREF"`, which sources `INNGEST_CLI_VERSION`/`SHA256` from the image env | Guard quantifies over all four. The plan's list was an example, and the property is over the class |
| Phase 2.3 "hard precondition: the values exist in `prd_terraform` before merge" | `ZOT_PULL_USER` / `ZOT_PULL_TOKEN` are **already present** in `soleur/prd_terraform`; `--name-transformer tf-var` adds the prefix, so they resolve as `TF_VAR_zot_pull_user` / `TF_VAR_zot_pull_token` | Already satisfied. No operator step, and no merge-apply hazard from the no-default vars |

### Defects found and fixed during implementation

1. **`docker login ""` on every boot.** The first draft of the zot-login runcmd item referenced
   `$ZOT_EP`, which is set in a *different* runcmd item — each `- |` is its own shell. The
   login would have failed on every boot, emitting `zot-login-FAILED` and falling back to the
   revoked GHCR leg permanently: the arm would have been inert while every gate stayed green.
2. **`systemctl enable --now docker` cannot re-read `daemon.json`.** Unlike the web host, this
   host installs `docker.io` via cloud-config `packages:`, which runs before `runcmd` and
   STARTS the daemon — so `--now` is a no-op against an already-running daemon and the
   insecure-registry allowlist would have sat on disk unread. Without it docker refuses the
   plain-HTTP registry and the zot leg fails on every boot. An explicit `systemctl restart
   docker` closes it, and a mutation case pins it.
3. **The zot token was not redactable.** `inngest-redact.sh` redacts by known VALUE. The zot
   leg's failure tail is shipped off-box by `inngest_ghcr_fallback` and
   `oci-pull-ALL-LEGS-FAILED`, and a registry auth failure is precisely the case that produces
   a tail worth shipping — so the credential would have shipped in clear on the one path
   carrying it. Added to the value list.
4. **An empty input killed the bootstrap guard before its results summary.** Pre-existing
   `pipefail` footgun in the cosign section (`INNGEST_CI_PROSE="$(grep … | … )"`): a zero-match
   grep aborted the whole script under `set -e`, so the run exited 1 having printed no
   `=== Results ===` line and no failing assertion. Fixed inline with the `|| true` convention
   AC6 already uses. This is also what makes the row-6 anti-vacuity accounting reachable.
