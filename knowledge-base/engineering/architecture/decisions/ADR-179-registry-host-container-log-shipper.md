---
title: The registry host ships container logs with a self-contained journald shipper, not a Vector agent
status: adopting
date: 2026-08-11
amends: [ADR-172]
related_adrs: [ADR-062, ADR-096, ADR-130, ADR-143, ADR-151, ADR-172]
related: [7440]
related_plans:
  - knowledge-base/project/plans/2026-08-11-fix-registry-zot-log-shipping-plan.md
related_specs:
  - knowledge-base/project/specs/feat-one-shot-7440-zot-log-shipping/session-state.md
brand_survival_threshold: single-user incident
---

# The registry host ships container logs with a self-contained journald shipper, not a Vector agent

## Context

The `soleur-registry` host emitted exactly one telemetry channel off-box: a `SOLEUR_ZOT_DISK`
marker posted every five minutes by a cron reporter. The zot container's own log stream went
nowhere. Because the reporter samples `docker logs` once per interval and folds a truncated,
character-stripped excerpt into a single `zot_last_err` field, **every count derived from that
channel was a lower bound rather than a measurement**, and any zot log line appearing between two
samples was unobservable.

Measured 2026-08-11 over a 6-hour window, self-pulled per `hr-no-dashboard-eyeball-pull-data-yourself`:

| Query | Rows | Heartbeat echoes | Genuine zot rows |
|---|---|---|---|
| `--grep zotregistry.dev` | 53 | **53** | **0** |
| `--grep routes.go` | 0 | 0 | **0** |
| `--grep blobs/uploads` | 0 | 0 | **0** |
| `--grep 'garbage collected'` | 1 | **1** | **0** |

72 rows mentioned the host in that window; all 72 were heartbeats. For contrast the
`soleur-web-platform` host ships container logs normally — a 6h query on one container id returns
~400 rows of ordinary application output.

The consequence is that root-cause work on the registry terminated at the host boundary, which is
the one place `hr-no-ssh-fallback-in-runbooks` forbids a runbook to go. The host whose failure
caused the multi-day release blockage from 2026-08-04 through 2026-08-10 was the one host with no
log shipping. Observability layer: **5 — host/container journald shipped to Better Stack Logs
source 2457081** (`hr-observability-layer-citation`).

**This is a shipping problem, not an instrumentation problem** — the single most important scoping
fact. The container already runs `--log-driver journald` under the container name `zot`, so the
lines were already on the host as `CONTAINER_NAME=zot`. Nothing about zot's own configuration
changes here, which keeps this clear of ADR-172 §3's write-surface deadlock.

## Decision

### 1. A purpose-built journald→ingest shipper, not an agent

Container logs leave this host through a shipper that reuses the already-admitted
`BETTERSTACK_LOGS_TOKEN` and the existing per-line direct-POST transport the two reporters already
use. No new secret, no new vendor resource, no new Terraform resource, no zot config change.

### 2. The binding reason against the shared Vector config is PAYLOAD DESTRUCTION, not credentials

`vector.toml` deletes any top-level `message` key as an Art-9 user-content key, and zerolog's log
text **is** a top-level `message`. A Vector-shipped zot line would therefore arrive **with its
message text deleted** — nominally shipping, actually empty. That is disqualifying on its own.

Supporting reasons, each sufficient alone: `host_metrics` quota cost (~19.9k rows/day against a
25k/day threshold) on a shared source; a boot-time binary download on the sole container-image pull
path; a second config to hold in lockstep with the shared one; and the `user_data` budget.

**The pepper/isolation-guard argument an earlier draft gave is explicitly RETRACTED as false — do
not re-derive it.** Three ways it was wrong: the pepper lookup is nested inside `if raw_key != ""`
and needs a top-level `userId`/`user_id` key, which zot never emits (it logs `username:zot-pull`);
the degraded tag does not contain `structured`, so `pii_scrub_string` still runs the full string
scrub; and Vector needs only the already-admitted `BETTERSTACK_LOGS_TOKEN`, so the four-name
isolation guard never trips.

### 3. A direct host POST bypasses VRL redaction, so the shipper owns its own sanitizer

This is ADR-172 §1's reasoning applied to a host-side emitter. Two DIFFERENT jobs, deliberately
named apart because conflating them is how dead rules get restored later believing they were safety:

- **Payload integrity** (the `tr` pipeline): collapse whitespace, drop non-printable bytes, drop `"`
  and `\` so the value cannot corrupt the single-key JSON body. RFC 8259 §7 — an unescaped quote or
  a mid-sequence-sliced UTF-8 byte would make Better Stack reject the *whole* payload in exactly the
  crash case worth carrying.
- **Credential backstop** (one `Authorization` rule): anchored on the **raw quoted** shape.

**The log shape is measured, not inferred, and getting it wrong would have shipped two inert
mechanisms.** Running the pinned image (`ghcr.io/project-zot/zot-linux-amd64:v2.1.20@sha256:95a837a0afac…`,
the digest the live host reports) locally on 2026-08-11, zot emits quoted zerolog JSON:

```json
{"time":"…","level":"info","message":"HTTP API","path":"/v2/","statusCode":401,
 "headers":{"Accept":["*/*"],"Authorization":["******"],"User-Agent":["curl/8.18.0"]},
 "caller":"zotregistry.dev/zot/v2/pkg/api/session.go:92","func":"…","goroutine":156}
```

The colon-joined `{time:…,caller:zotregistry.dev/…}` form visible in `zot_last_err` is the
**sampler's rendering** — that field passes through `tr -d '"\\'`, which removes every double quote
and backslash. Two consequences:

1. A rule shaped like `vector.toml`'s `(?i)(authorization:\s*)bearer\s+\S+` cannot match
   `"Authorization":["…"]`. Anchoring on the stripped shape ships redaction that is nominally
   present and actually inert — precisely the failure mode invoked to reject Vector.
2. A probe discriminator anchored on `caller:zotregistry.dev` matches ONLY the echo, and would
   report zero genuine rows forever even after a fully successful delivery.

**Also measured: zot masks the Authorization header itself** (`["******"]`) — the literal credential
appeared 0 times across basic-auth, Bearer and Basic probes. So the backstop is **defence in depth**
against a future zot that stops masking, not the primary control. But a NON-Authorization header IS
logged verbatim (`"X-Custom":["plainvalue"]`), which is why the rule is anchored on the header-object
shape rather than trusting one header name's known masking. Four rules an earlier draft carried
cannot fire on this host at all (no email in zot's identity model; no `sync`/`extensions`/
`credentialsFile` in the config, so no credentialed upstream URL; htpasswd values are never echoed)
and were dropped rather than kept as decorative safety.

### 4. This is the registry host's FIRST `Restart=always` unit

Every existing unit here is `Type=oneshot`. Recorded because it changes the host's failure surface,
and it is why §5 exists.

### 5. Resource governance is the ONLY containment available

With no in-place execution path there is no kill switch, so the unit must be incapable of needing
one: `MemoryMax=128M`, `CPUQuota=20%`, `IOWeight=20`, `RestartSec=5`, and `StartLimitIntervalSec=0`.

The start-limit setting is load-bearing rather than cosmetic. Bare `Restart=always` inherits
`RestartSec=100ms` with `StartLimitBurst=5` in `StartLimitIntervalSec=10s`, so a shipper that fails
fast at boot (Doppler or the network not yet up) **latches `failed` in under a second and stays dead
until the next boot** — indistinguishable from "never provisioned", which is exactly the
discrimination the follow-through probe exists to make.

The caps are sized against a real precedent: #6288 was a host-level OOM restart loop on this same
host, and zot's own cgroup cap is *derived* as host RAM minus a 1024 MB reserve documented for
"cron+doppler+sshd+OS". This unit is a new line item against that reserve, on the host whose failure
darks every deploy.

### 6. The cursor means DELIVERED, not READ

`journalctl --cursor-file` is **not** used. Measured on systemd 259: the file is written at clean
exit only — SIGTERM writes it, **SIGKILL leaves it stale**. The man page explains why (it documents
the flag for sequential one-shot invocations, not a `Restart=always` daemon). So on an OOM-kill the
shipper would resume from the last clean-exit cursor and **re-ship everything since, unbounded** —
the runaway-volume mode triggered by the very mechanism chosen to prevent gaps.

Instead the shipper persists the per-entry `__CURSOR` from the JSON it already parses, atomically,
**after each successful POST**. `--no-tail` is passed because with no cursor `--follow` implies
`-n 10`, so a fresh host would discard the boot backlog the persistence exists to preserve.

### 7. Amendment to ADR-172 §8

ADR-172 §8 recorded that *"while the LUKS recut is unfired there is no safe provisioning event"*,
with the corollary that *"the read-only surface is currently the only instrumentable one"*. **Both
were true when written and are no longer.** The recut has fired: the live heartbeat reads `pcent=8`
(down from 100 across 2026-08-04 → 2026-08-10) on boot `bc135d5b-…`, and a step-6
`registry-host-replace` is the pending event this change rides.

§3's write-surface finding is **undisturbed**: this plan changes no `accessControl` and grants no
`delete`. ADR-096's cloud-init-only posture is restated here rather than amended separately — it
still holds, and it is why §8 below exists.

### 8. Ships inert until provisioned, and says so

`hcloud_server.registry` is cloud-init-only and every registry resource is an
`OPERATOR_APPLIED_EXCLUSION`, so **merging this applies nothing**. This is a deferral of delivery and
is named as one rather than hidden: the rider is recorded on the open zot-pin ordered path, and the
follow-through probe carries a 90-day escalation horizon so an indefinitely-undelivered change
escalates instead of reporting TRANSIENT forever.

## Alternatives Considered

| Alternative | Verdict | Reason |
|---|---|---|
| **Install a Vector agent** (the issue's literal framing) | **Rejected** | §2 — the shared config deletes the top-level `message` key that IS zerolog's log text. Supporting: quota, boot-time download on the sole pull path, lockstep, `user_data` budget. The pepper argument is retracted as false. |
| A trimmed registry-specific Vector config | **Rejected** | Dodges the `message` deletion but keeps the boot-time download on the sole pull path and adds a second config to hold in lockstep |
| Widen the reporter's `zot_last_err` field | **Rejected** | Stays a 5-minute sampler — the defect itself. A wider field raises the lower bound without producing a count |
| Ship from CI, extending ADR-172's inventory lever | **Rejected** | CI reaches only the read-only `/v2/` surface; container logs are unreachable from a runner |
| Grant `delete` / edit `/etc/zot/config.json` | **Rejected, out of scope** | The write-surface deadlock ADR-172 §3 declines to pretend around |
| A timer-driven shipper with `journalctl --since <window>` | **Rejected, but its rejection was corrected** | Boundary arithmetic double-ships or gaps. The original rejection cited `--cursor-file` continuity, which was **measured false under SIGKILL** — the actual resolution is self-persisted `__CURSOR`, not the `--cursor-file` idiom whose man page documents this very timer pattern |
| A selectivity filter admitting named log classes | **Rejected** | Duplicates the rate cap, suppresses the free 60s positive control, needs lockstep with zot's log vocabulary across version bumps, and creates a "filter admits nothing" mode needing its own detector. Wholesale admission + a class-prioritised cap is simpler and admits `executing gc`, the denominator the downstream question needs |
| A dedicated `SOLEUR_ZOT_LOG_CANARY` | **Rejected** | `zot-liveness-heartbeat.timer` already GETs `/v2/` every 60s and zot logs every request at info, so a genuine zot line lands every minute BY CONSTRUCTION (~1,440/day). That control traverses the WHOLE path (zot → journald → match → sanitize → POST → warehouse); a shipper-emitted canary would skip journald ingestion and the field match — the two actual failure modes — so it would certify something other than what it claims |
| Batched JSON-array POSTs | **Rejected** | Flush-trigger ambiguity, partial-batch loss across restarts, an unbounded in-memory buffer under a sink outage, and a second JSON-escaping surface. Per-line POST is the proven transport |
| A negative discriminator ("`raw` does not begin with the heartbeat prefix") | **Rejected** | Fail-open: under any `raw`-encoding drift every echo row reclassifies as genuine and the probe auto-PASSes on the exact state it exists to reject. The same literal used positively fails visibly instead |
| Enroll the probe on #7440 | **Rejected — it would have been a silent no-op** | The sweeper lists `--state open`; on a closed issue both `rc=0` and `rc=2` take "no action, no comment", and the closed-lookback drops it entirely after two weeks. Even a real PASS would leave nothing to flip this ADR |
| Request a host replace in this PR | **Rejected** | A destructive replace of the sole pull path is separately authorized (`hr-menu-option-ack-not-prod-write-auth`), and the zot-pin ordered path owns it |
| Assert liveness in a pre-merge AC | **Rejected** | Structurally impossible; any pre-merge "logs are queryable" claim is an inert-until-dispatched false green |

## Consequences

- The registry stops being the one blind host in the estate. `hr-no-ssh-fallback-in-runbooks`
  becomes satisfiable for it rather than merely declared.
- The downstream growth-attribution question becomes answerable from telemetry: the gc
  start/complete ratio and `PatchBlobUpload` counts are readable rather than sampled.
- New standing row volume on a shared source, bounded by an explicit 5,000/day cap with the four
  measured evidence classes cap-exempt so the diagnostic evidence is not dropped preferentially
  during exactly the flood that accompanies disk growth.
- A new permanently-resident process on the sole image-pull path, contained by §5's hard caps.
- Journald moves to `Storage=persistent` with both media explicitly bounded, which takes the log
  buffer off a `/run` tmpfs on a RAM-constrained host.

## Status flip condition

`adopting → accepted` on the **first PASS** of `scripts/followthroughs/zot-log-channel-7440.sh` —
an envelope-stamped row read back OUT of the warehouse, which no exit code on the host can fake.

The probe is enrolled on a **dedicated tracker**, never on #7440. That is not a preference: the
sweeper lists `--state open`, and on the closed issue this PR's `Closes` produces, a correct exit-2
probe is a permanent silent no-op with no artifact to flip this ADR.

## Ordinal derivation

`scripts/check-adr-ordinals.sh` contains no remote-ref logic, so the ordinal was re-derived here.
**Quantified over all 2,986 refs** plus the local tree: `ADR-177` is claimed twice
(`shared-bash-primitives-ship-in-plugin`, `test-runner-result-taxonomy-unresolved-is-not-failed`)
and `ADR-178` is claimed twice (`guard-contract-as-plan-time-deliverable`,
`local-gate-declines-are-counted-verdicts`). **179 is the next free.**

A narrower first pass over `refs/remotes/origin` only (65 refs) reported 178 as free — both claims
live on **local-only branches invisible to origin entirely**, which is a wider blind spot than the
pushed-branch case the plan warned about. An ordinal probe that does not quantify over local heads
returns a confidently wrong answer.
