---
title: The registry host ships container logs with a self-contained journald shipper, not a Vector agent
status: adopting
date: 2026-08-11
amends: [ADR-172]
related_adrs: [ADR-062, ADR-096, ADR-130, ADR-143, ADR-151, ADR-172]
related: [7440]
related_plans:
  - knowledge-base/project/plans/archive/20260812-194844-2026-08-11-fix-registry-zot-log-shipping-plan.md
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

### 4. The shipper is a cron one-shot, not a daemon — because this host cannot be fixed in place

Every `.service` on this host is `Type=oneshot`, and the host keeps ZERO `Restart=always` units —
that is the load-bearing claim, and it is the one that is true. (An earlier draft said "every
recurring job is a 5-minute `cron.d` line", which the 60-second `zot-liveness-heartbeat.timer`
falsifies; that timer is deliberately a systemd timer and not `cron.d`, and one of its two stated
reasons is the very PATH trap §4 pins below.) Every recurring job that wraps `doppler run` is a
5-minute `cron.d` line
wrapped in `doppler run`. This change adds a third such line rather than the host's first
`Restart=always` unit.

The governing constraint is not efficiency, it is **reversibility**. `hcloud_server.registry` is
cloud-init-only (ADR-096) with no in-place execution path, so the repair cost of any defect shipped
here is an operator-authorized destructive replace of the fleet's sole image-pull path. The correct
question is therefore "which shape's failure modes are survivable without a replace?", not "which
shape is better in steady state." A daemon's are not: a bad `ExecStart`, a missing dependency, or a
fast-failing start all become permanent conditions. A one-shot's are: each is one failed tick, and
the next is five minutes away.

This is measured, not hypothesised. The first implementation of this change named
`ExecStart=/usr/bin/doppler` — a path this template never creates, since it installs to
`/usr/local/bin` and, unlike the inngest template, writes no symlink. That is `status=203/EXEC`, and
because `Restart=always` + `StartLimitIntervalSec=0` deliberately disable the start-limit latch, a
permanent 5-second restart loop shipping nothing, whose only fix is another destructive replace. The
local `systemd-analyze verify` gate passed it, because `verify` resolves `ExecStart` against the
**runner's** filesystem — which has `/usr/bin/doppler` and lacks `/usr/local/bin/doppler`, the exact
inverse of production.

Latency is what the daemon buys, and this channel has no consumer that can spend it. The disk
reporter runs at 5 minutes, the liveness feeder at 60 seconds against a 90-second deadline, and the
follow-through probe reads warehouse windows of 12 minutes and up. The consumer is post-hoc
root-cause work on a host blind for its entire existence; five-minute granularity is not
distinguishable from seconds there.

The resource governance offered in exchange was independently disproven, which is why it does not
appear as a counter-argument: `IOWeight=20` is a verified no-op (no BFQ; `io.cost.model`/`qos`
empty) and sat on the wrong cgroup for its stated goal, `RuntimeMaxUse=64M` **raised** the volatile
journal ceiling above journald's ~38 MB default rather than lowering it, the 1024 MB host reserve it
was sized against is mis-derived (the host reports 3,814 MB, so the true remainder is ~742 MB), and
every cap magnitude survived mutation — `MemoryMax` 128M→3000M and `CPUQuota` 20%→400% both passed a
green suite. Containment that cannot be asserted is not containment.

The cron line takes a **free minute offset** (`4-59/5`). `zot-disk-heartbeat` holds `*/5` and
`soleur-private-nic-guard` holds `2-59/5`, and that guard's own comment records why the offset
exists: the host budgets ~1024 MB for "cron+doppler+sshd+OS" and must not have these concurrently
resident. A third `doppler run` at `*/5` would reintroduce the daemon's RAM risk through the
schedule instead of the process table, on a host with an OOM restart-loop history (#6288). The
suite asserts this as a real disjointness check over the minutes each line actually fires, not a
string compare against a remembered literal.

`flock -n` — carried over from the daemon's `ExecStart`, where systemd's single-instance guarantee
already made it decorative — becomes load-bearing here as the tick-overrun guard, matching the NIC
guard's shape exactly.

The invocation also narrows its own secret scope, which the daemon could not usefully do: a
long-lived process held the **whole** `soleur-registry/prd` set (including `REGISTRY_LUKS_KEY`) in a
permanently-resident environment, and its `StateDirectory`-rooted `DOPPLER_CONFIG_DIR` made it the
first persistent doppler fallback-cache root on the estate. A tick's environment lives seconds, and
`--only-secrets BETTERSTACK_LOGS_TOKEN --no-fallback` (both verified against doppler v3.75.3)
narrows it explicitly rather than by inheritance.

### 5. The cursor means DELIVERED, not READ — and that is independent of the cadence

`journalctl --cursor-file` is **not** used, and the reason is semantic rather than incidental.

An earlier draft of this ADR rejected it because the file is written at clean exit only (SIGTERM
writes it, SIGKILL leaves it stale) and conceded, in the Alternatives table, that this rejection
"was corrected" once the shape became a sequential one-shot — the pattern the man page documents the
flag for. **That concession is withdrawn.** Measured on systemd 259: the flag writes the cursor of
the last entry **READ** (`man journalctl`: *"At the end, write the cursor of the last entry to
FILE"*), and journalctl has no channel by which to learn whether the consumer delivered anything.
Reading 5 entries lands the file on the 5th regardless of what the consumer did with them, and a
consumer exiting non-zero does not hold it back. Adopting it would make a transient sink outage a
permanent, silent, unaccounted loss — the defect, shipped as the design. Also measured: when the
consumer breaks the pipe early, journalctl takes SIGPIPE and the file is **never written at all**,
so the break-on-first-failure design below would replay the entire tick.

Instead the shipper persists the per-entry `__CURSOR` from the JSON it already parses, atomically,
**after each successful POST**. That is ~6 lines, is exact rather than tick-granular, and is the one
part of the original streaming design that is load-bearing independent of the scheduling shape.

A tick ends at its first undelivered row and exits non-zero. **Recovery is not the exit code** — it
is that the cursor was never advanced past the hole, so the next tick resumes exactly there. The
exit code is surfaced by piping the tick through `logger -t zot-log-shipper` on the cron line —
not by cron, which logs job start rather than exit status and has no MTA on this host to mail
output to. An earlier draft of this section claimed the exit code alone made a failing tick
visible without SSH; that was false, and the durable signal is `post_fail` in the state file,
carried off-box by the 5-minute reporter on its own egress path. This is also why the shipper posts
each row **once**: the disk reporter retries (`post || post || echo`) because its value is not
replayable, whereas every shipper row is replayable from the cursor, so an immediate second attempt
against a briefly-500ing ingest buys nothing the five-minute gap does not buy better — and
back-to-back attempts are the one retry shape guaranteed to fail both times against a transient
fault.

A cold start — a fresh host that has never persisted a cursor — still reads from the beginning of
the retained journal, because that host's journal is small and the boot backlog is exactly what the
persistence exists to preserve. Only a cursor **invalidation** (a journal rotated past the persisted
cursor during a sink outage) bounds the replay, with an explicit `--since`. Dropping `--no-tail` is
not a bound: measured, absent `--follow`/`-n` it is a strict no-op (702 vs 702 entries over a bounded
window) and only undoes an explicit `--lines=`.

### 6. Amendment to ADR-172 §8

ADR-172 §8 recorded that *"while the LUKS recut is unfired there is no safe provisioning event"*,
with the corollary that *"the read-only surface is currently the only instrumentable one"*. **Both
were true when written and are no longer.** The recut has fired: the live heartbeat reads `pcent=8`
(down from 100 across 2026-08-04 → 2026-08-10) on boot `bc135d5b-…`, and a step-6
`registry-host-replace` is the pending event this change rides.

§3's write-surface finding is **undisturbed**: this plan changes no `accessControl` and grants no
`delete`. ADR-096's cloud-init-only posture is restated here rather than amended separately — it
still holds, and it is why §7 below exists.

### 7. Ships inert until provisioned, and says so

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
| **A `Restart=always` streaming daemon** (this change's first implementation) | **Rejected** | Buys seconds-latency no consumer of this channel can spend — the disk reporter is 5-min, the liveness feeder 60s against a 90s deadline, the probe reads warehouse windows of 12+ min — and pays with the host's first always-on unit on the fleet's sole image-pull path, a host with no in-place execution path and an OOM restart-loop history (#6288). The trade is not latency-vs-complexity but latency-vs-**reversibility**: every daemon failure mode is repairable only by an operator-authorized destructive replace. Measured, not hypothesised — one wrong `ExecStart` path (`/usr/bin/doppler`, which this template never creates) made it a permanent 5s restart loop shipping nothing, and the local `systemd-analyze verify` gate passed it because it resolved against the runner's filesystem. Under cron that same defect is one failed tick per five minutes. The `MemoryMax`/`CPUQuota`/`IOWeight` containment offered in exchange was independently disproven: `IOWeight` is a no-op without BFQ and sits on the wrong cgroup, `RuntimeMaxUse=64M` **raises** the volatile ceiling it was meant to lower, and every cap magnitude survives mutation |
| **`journalctl --cursor-file`, under the cron one-shot** | **Rejected — and the earlier "its rejection was corrected" note is itself WITHDRAWN** | The one-shot IS the sequential-invocation pattern the man page documents the flag for, so the invocation-shape objection was indeed wrong. The semantics remain disqualifying, for a simpler reason than the SIGKILL staleness earlier cited: measured on systemd 259, the flag writes **the cursor of the last entry READ** (`man journalctl`: *"At the end, write the cursor of the last entry to FILE"*), and journalctl has no channel by which to learn whether the consumer delivered anything. Adopting it makes the cursor mean READ — precisely the defect that turns a transient sink outage into permanent, silent, unaccounted loss. Also measured: when the consumer breaks the pipe early, journalctl takes SIGPIPE and the file is **never written at all**, so a break-on-first-failure design would replay the whole tick. Self-persisting the per-entry `__CURSOR` after each successful POST is ~6 lines, is exact rather than tick-granular, and is the one part of the original design load-bearing independent of scheduling shape |
| A timer- or cron-driven shipper keyed on `journalctl --since <window>` | **Rejected** | Boundary arithmetic double-ships or gaps, and no window value fixes it, because the boundary is between the wall clock and the journal's own ordering. The cadence was never the defect — the **positioning mechanism** was. The adopted design takes the cron cadence and keeps cursor positioning |
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

  **Refined 2026-08-13 against the live channel (#7456).** Measured once delivery landed, three
  corrections to the sentence above — each changes what a consumer can actually build:

  - **The pairing is available PER REPOSITORY, which is the signal that matters.** Both
    `executing gc of orphaned blobs for /var/lib/zot/<owner>/<repo>` and `gc successfully
    completed for /var/lib/zot/<owner>/<repo>` carry the repo path. That is the zot#4235
    signature — gc completing for one repository and never another — and a *global* ratio renders
    it as a healthy-looking ~50%.
  - **`garbage collected blobs` is emitted BARE**, with no repository. It cannot serve as a
    per-repo completion numerator; it is reclaim evidence only.
  - **The shipped payload is not JSON and must not be split on `:`.** `sanitize()` strips only
    `"` and `\`, so the inner payload is comma-separated `key:value` with unescaped colons inside
    values (`caller:zotregistry.dev/…/gc.go:109`). A consumer must anchor on the parsed `message`
    field — through `{time:…,level:<word>,message:` — never on the whole line, or a header value
    can mint a repository that never completes.

  Consumed by the attribution lead in `scripts/followthroughs/zot-fill-rate-7341.sh`'s `FAIL`
  arm, which reports counts and unmatched repositories as a **lead rather than a verdict**:
  shipper-side row loss (the four classes are cap-exempt against their own 17-per-tick ceiling),
  `--limit` truncation dropping the window's oldest rows first, and the trailing window edge each
  remove a completion while its start survives, so an unmatched start is not by itself a stall.
- New standing row volume on a shared source, bounded by an explicit 5,000/day cap with the four
  measured evidence classes cap-exempt so the diagnostic evidence is not dropped preferentially
  during exactly the flood that accompanies disk growth.
- No new permanently-resident process: a 5-minute cron tick on the sole image-pull path (§4).
- Journald moves to `Storage=persistent` with both media explicitly bounded, which takes the log
  buffer off a `/run` tmpfs on a RAM-constrained host.

## Status flip condition

`adopting → accepted` on the **first PASS** of `scripts/followthroughs/zot-log-channel-7440.sh` —
an envelope-stamped row read back OUT of the warehouse, which no exit code on the host can fake.

The probe is enrolled on a **dedicated tracker (#7455)**, never on #7440. That is not a preference:
the sweeper lists `--state open`, and on the closed issue this PR's `Closes` produces, a correct
exit-2 probe is a permanent silent no-op with no artifact to flip this ADR.

Deferred work from this change is consolidated on **#7456**: the root-filesystem LUKS exception
recorded below (expires 2027-02-11), the forward-looking growth-attribution discriminator, and any
rate-cap retune. The retune is tracked rather than implied to be free because changing the cap needs
another cloud-init edit and therefore another provisioning event.

## Ordinal derivation

`scripts/check-adr-ordinals.sh` contains no remote-ref logic, so the ordinal has to be re-derived
by hand — and re-derived **immediately before merge**, because the contended range moves.

This ADR is **184**, and it has been renumbered **twice**: 179 -> 182 -> 184. The second renumber
is the point. The 182 derivation was run at the start of this review round and was correct then;
by the end of the round `feat-one-shot-7471-plugin-delivery-path` had claimed 182
(`keyless-manifests-and-a-dedicated-marketplace-source`) and another branch had claimed 183. A
review round is long enough for the contended range to move underneath you, which is why the
discipline is re-deriving late rather than deriving carefully.

The derivation recorded here previously concluded "179 is the next free",
which was wrong twice over: `ADR-179` is claimed on `origin/main` by
`bare-plugin-root-anchor-for-customer-facing-executables`, and the two contenders that derivation
named as double-claimed (`guard-contract-as-plan-time-deliverable`,
`local-gate-declines-are-counted-verdicts`) have since settled at **180** and **181**. Preserving a
derivation that reached the wrong answer, in the ADR's own voice, teaches the method as sound.

The lesson the earlier note drew was also the wrong one. It concluded that the danger was
*local-only branches invisible to `origin`* — but the collision that actually occurred was **on
`origin`**, inside the narrow scope that note dismissed as too narrow. So the operative discipline
is not a wider sweep, it is re-deriving late:

```
git ls-remote origin 'refs/heads/*' >/dev/null   # refresh
git for-each-ref --format='%(refname)' | while read -r r; do
  git ls-tree -r --name-only "$r" -- knowledge-base/engineering/architecture/decisions/ 2>/dev/null
done | grep -oE 'ADR-[0-9]+' | sort -u | tail -5
```

Re-run it immediately before merge. An ordinal derived at plan time is stale by the time a review
round finishes; this one was.

## `user_data` budget

This shipper took the registry payload from 9,408 B to 13,136 B stored (base64gzip of the
stripped render), which surfaced a three-way contradiction between the gates governing that
number. **ADR-185** rules it: the policy is 8,000 B of preserved headroom, single-sourced from
`REGISTRY_GZIP_BUDGET`, and the `headroom >= 20000` arm that blocked this change was #7299's
one-shot fix-verification criterion, not a policy. The shipper ships at 19,632 B headroom — 2.45x
the written policy and ~32x the largest measure-to-apply divergence ever observed on this class.

The ratchet is real regardless: this feature consumed 3,728 compressed bytes, and the next
`user_data` feature on this host meets the budget one level up.
