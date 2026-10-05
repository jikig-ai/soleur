---
title: "The registry host ships no zot logs — only the 5-min heartbeat, which blocks the disk-attribution criterion"
date: 2026-08-11
slug: fix-registry-zot-log-shipping
branch: feat-one-shot-7440-zot-log-shipping
issue: 7440
closes: 7440
type: fix
lane: cross-domain
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

> No `spec.md` exists for this branch, so no `lane:` could be carried forward — defaulted to
> `cross-domain` (TR2 fail-closed). The Domain Review below assessed only engineering as relevant;
> the fail-closed lane widens review rather than narrowing it, which is the intended direction.

## Overview

The `soleur-registry` host emits exactly one telemetry channel to Better Stack: a
`SOLEUR_ZOT_DISK` marker line posted every five minutes by a cron reporter. The zot container's own
log stream is not shipped anywhere off-box. Because the reporter samples `docker logs` once per
interval and folds a truncated, character-stripped excerpt into a single field, every count derived
from that channel is a lower bound rather than a measurement, and any zot log line that appears
between two samples is unobservable.

The consequence is that root-cause work on the registry terminates at the host boundary. This plan
closes that gap by giving the zot container a real off-box log channel and by adding a verification
probe that distinguishes a genuine zot log line from the heartbeat's echo of one.

This plan was revised substantially after a five-reviewer panel. Four findings changed its
architecture rather than polishing it, and each is recorded in place rather than silently absorbed:
the stated reason for rejecting Vector was **falsified**; the log shape the design was built on was
an **artifact of the sampler**; the verification enrollment would have been a **permanent silent
no-op**; and the shipper had **no resource governance** on the host whose failure blocks every
release.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Probe | Verdict |
|---|---|---|
| #7440 is open and actionable | `gh issue view 7440` | **HOLDS** — OPEN, labels `priority/p1-high`, `type/bug`, `domain/engineering` |
| The disk-attribution issue is open | `gh issue view 7341` | **HOLDS** — OPEN |
| "Follow the existing Vector source/allowlist pattern used for the web-platform host" | Read `cloud-init-registry.yml` (1049 lines) | **STALE — the plan's shape changes.** The registry host runs **no Vector agent**. There is no allowlist entry to add |
| A host-side change can be delivered | ADR-172 §8 + #7287 ordered path + live heartbeat | **HOLDS, and a pending event exists** — see *the delivery window* |
| `routes.go` / `blobs/uploads` are zot-only strings | Live Better Stack query, measured | **HOLDS as absences, but they are the WRONG tokens to assert on** — see *the discriminator must be positive* |

### The falsification table, re-measured independently (2026-08-11, 6h window)

Self-pulled per `hr-no-dashboard-eyeball-pull-data-yourself` via
`doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh`:

| Query | Rows | Heartbeat echoes | Genuine zot rows |
|---|---|---|---|
| `--grep zotregistry.dev` | 53 | **53** | **0** |
| `--grep routes.go` | 0 | 0 | **0** |
| `--grep blobs/uploads` | 0 | 0 | **0** |
| `--grep 'garbage collected'` | 1 | **1** | **0** |

This reproduces the issue's table row-for-row, which makes it a re-runnable regression baseline
rather than a claim.

### zot's real log shape — and the correction that reshaped this plan

**An earlier draft of this section claimed to have "measured" zot's log format. It had not.** The
sample was read out of the heartbeat's `zot_last_err` field, and the reporter strips characters
before shipping:

```bash
ZOT_LAST_ERR=$(printf '%s' "$ZOT_ERR_RAW" | tr '\n\r\t' ' ' \
  | LC_ALL=C tr -cd '\40-\176' | tr -d '"\\' | head -c 300)
```

`tr -d '"\\'` removes **every double quote and backslash**. So the unquoted, colon-joined form

```text
{time:2026-08-11T09:34:13Z,level:info,message:HTTP API,caller:zotregistry.dev/zot/v2/pkg/api/authn.go:229,…}
```

is the **sampler's rendering**, not zot's output. zot emits quoted zerolog JSON. Two independent
in-repo confirmations:

- The reporter's own tier-2 error selector greps `docker logs zot` directly with
  `'"level":"(error|fatal)"|level:(error|fatal)|level=(error|fatal)'` — the **first** alternative is
  the quoted JSON form, which only makes sense if that is what the container actually writes.
- `/etc/zot/config.json` sets `"log": { "level": "info" }` with no output override, i.e. zerolog's
  default JSON encoder.

**This correction is load-bearing in two places, and getting it wrong would have shipped two
inert mechanisms:**

1. **Redaction anchored on the stripped shape cannot match production.** A rule shaped like
   `vector.toml`'s `(?i)(authorization:\s*)bearer\s+\S+` does not match `"Authorization":["Bearer …"]`.
   The plan would have shipped redaction that is nominally present and actually inert — precisely
   the failure mode it invokes to reject Vector.
2. **A discriminator anchored on `caller:zotregistry.dev` matches ONLY the echo.** A genuine
   shipped row carries `"caller":"zotregistry.dev/…"`. The probe would have reported `genuine=0`
   forever, even after a fully successful delivery — a permanent false-TRANSIENT.

It also explains the falsification table exactly: bare `--grep zotregistry.dev` hits 53 rows
because the *domain substring* survives quote-stripping, while the colon-joined form exists **only**
inside the echo.

**Phase 0 therefore measures the raw shape before any rule or discriminator is written.** The
fixture *values* remain synthesized (`cq-test-fixtures-synthesized-only`); what Phase 0 buys is the
*shape* they must model. Synthesized fixtures against a wrong shape are exactly why the test suite
could not have caught this.

### The discriminator must be POSITIVE and host-isolated

An earlier draft asserted a genuine row as one matching a zot-only string whose stored `raw` does
**not** begin with `{"message":"SOLEUR_ZOT_DISK `. That negation is **fail-open**, and it inverts
the safety polarity of its own precedent:

- `scripts/zot-disk-sample.sh` uses that same literal **positively** — to *find* heartbeat rows. If
  Better Stack's `raw` encoding ever drifts, it matches nothing and fails **visibly**.
- Used as an exclusion, the same drift reclassifies **every echo row as genuine**, and the probe
  auto-PASSes on exactly the production state it exists to reject. A synthesized false-green
  fixture cannot detect this, because the fixture encodes the assumed shape.

Two further defects in the negative form: **all hosts multiplex into Logs source 2457081** and
`host_name` is the sole discriminator (`vector.toml` states this plainly), yet the draft had no host
isolation; and the fallback tokens are generic — `routes.go` is an ordinary Go filename the (Go)
inngest service could log, so a single Vector row from another host would pass as "genuine" with no
registry shipper in existence.

**Resolution: the shipper stamps its own envelope on every line it ships**, and the probe asserts on
that envelope positively and field-isolated — the house rule from
`2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md`. This single
mechanism also removes the need for a separate liveness canary (see below).

### The free positive control that made the canary unnecessary

An earlier draft added a `SOLEUR_ZOT_LOG_CANARY` marker for shipper liveness. It was cut, because a
strictly better control already exists and costs nothing:

- `zot-liveness-heartbeat.timer` fires every **60 s** (`OnUnitActiveSec=60s`, `OnBootSec=30s`) and
  its feeder GETs `http://<private_ip>:5000/v2/`.
- zot logs **every** request at info level. So a genuine, zot-originated log line lands in the
  journal every 60 seconds **by construction** — ~1,440/day before any real traffic.

That control is superior to a canary on the axis that matters: it traverses the **whole** path under
test (zot → journald → field match → sanitize → POST → warehouse), whereas a shipper-emitted canary
skips journald ingestion and the field match — the two stages that are the actual failure modes. A
present canary alongside zero genuine rows is exactly what a broken `CONTAINER_NAME=zot` match
produces, so the canary would have certified something other than what it claimed.

Note one stale comment to fix while in the file: the `zot_last_err` rationale block says the
liveness probe GETs `/v2/` "every 5 min"; the timer says 60 s. The **timer** is authoritative.

### The delivery window

- `hcloud_server.registry` is **cloud-init-only** (ADR-096, amended by **ADR-172 §8**): no config
  webhook, no provisioner, no cloud-init re-run. A committed edit is **inert until the host is
  re-provisioned**.
- Every registry resource is an `OPERATOR_APPLIED_EXCLUSION` — merging applies nothing. Delivery is
  the dispatch-only `registry-host-replace` path.
- **A pending event exists, and it is the whole reason this is not a dead end.** #7287 is OPEN,
  titled *"Apply the staged zot v2.1.20 pin — ordered path, recut BEFORE host-replace"*, and its
  ordered path ends at step 6: *"Only now is `registry-host-replace` the correct tool."* That step-6
  replace is the vehicle this change rides.
- **ADR-172 §8 recorded that no safe provisioning event existed** while the recut was unfired. The
  live heartbeat reads `pcent=8 zot_restarts=0 zot_uptime_s=40317 state_status=running
  boot_id=bc135d5b-d509-41c4-8129-9181421e845c`, placing the current boot at ~2026-08-10T22:18Z on
  an 8%-full store — consistent with the recut having fired. **Re-probed at implementation time, not
  inherited** (Phase 0.1).

### The reset already happened — reframing the downstream unblock

The recut **emptied the store**: `pcent` went from 100 (2026-08-04 → 2026-08-10) to **8** today.
Attribution of the original ~44.22 GB against ~14.78 GB manifest-referenced is no longer recoverable
— the growth was reset before it was explained, which is the outcome the attribution criterion
existed to prevent. The value here is therefore **forward-looking**: the next growth cycle becomes
attributable. Because that reframing changes a *different* issue's closure criterion, Phase 4 writes
it there rather than leaving it only in this file (see Phase 4.3).

### Evidence vocabulary for the downstream discrimination — measured, not guessed

The downstream work must discriminate **(a) gc non-completion** from **(b) orphaned `.uploads/`**.
Candidate (a)'s evidence is a *missing completion*, which is only readable against a shipped
**start** line. zot's real vocabulary, from repo evidence:

| String | Source |
|---|---|
| `executing gc` | `knowledge-base/project/specs/feat-registry-oidc-migration/phase-0-spike-evidence.md` |
| `gc successfully completed` | `knowledge-base/project/specs/feat-one-shot-7278-registry-restart-lever/session-state.md` |
| `garbage collected blobs` | #7440 body; observed once in a heartbeat echo at 07:20Z |
| `PatchBlobUpload` | #7440 body — the token the `.uploads/` i/o-timeout evidence actually carries |

`gc` runs **hourly** (`"gc": true`, `"gcDelay": "1h"`, `gcInterval` 1h per #6240). So a stalled gc
that never completes emits a start with no completion — and if only completion lines were admitted,
the channel would emit **zero** gc rows, indistinguishable from "gc never ran", "gc ran fine", and
"the shipper filtered it". That is the lower-bound defect reproduced one layer up.

Note `PatchBlobUpload` appears nowhere in the issue's suggested query tokens, and `blobs/uploads`
returned **0 rows even inside the heartbeat echoes** — so the token the issue proposes has no
measured association with the upload evidence. This is why the plan admits **everything** rather
than an allowlist, and gives these four classes cap-exempt priority.

### Userdata budget — and a strip regex that is not what it looks like

`registry-userdata-budget.sh` measures
`base64gzip(replace(templatefile(...), local.registry_rationale_strip, ""))` against Hetzner's
**32,768 B ForceNew hard cap**. Post-`#7300` (merged 2026-08-06) it measures what Terraform stores:
**~9.4 kB stored, ~23.4 kB headroom**. Three documented traps:

- With `terraform` absent the script prints `SKIP` and **exits 0** — indistinguishable from "under
  cap" if only `$?` is read. Read the output.
- An over-cap render fails the CREATE *after* the DESTROY succeeded, stranding the sole pull path.
- **`local.registry_rationale_strip` is `"/(?m)^[ \t]*#([ \t][^\n]*)?\n/"` — a blanket whole-line
  comment strip, not a delimited region.** Consequences: (i) it strips comment lines *anywhere*,
  including inside `write_files` heredocs, so any line in an embedded awk/sed/jq program beginning
  with `#` is **silently deleted from what the host runs while surviving in the repo file the test
  exercises** — a drift pair between test and production on a host whose only delivery is a
  destructive replace; (ii) a comment written `#like-this` with no space after `#` is **not**
  stripped and does cost bytes. The test must therefore **apply the strip before executing** and
  assert the post-strip program is still valid bash.

### Institutional learnings that bind this plan

| Learning | Binding constraint |
|---|---|
| `2026-07-18-web-1-root-doppler-unit-needs-home-and-dedicated-token-and-vector-toml-has-no-running-host-delivery.md` | A committed shipper config is **file-only** until re-delivered. On a cloud-init-only host the only delivery is re-provisioning |
| `2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md` | Discriminate on the **field**, not a bare substring; fixtures must model the real backslash-escaped ClickHouse `raw` shape |
| `2026-07-17-inert-until-dispatched-verify-steps-are-false-green-vectors-only-review-catches.md` | This plan's verify gate is inert until dispatch; multi-agent review of the script *as an executing program* is mandatory |
| `2026-08-10-six-times-a-check-certified-something-other-than-what-it-named.md`, `2026-08-05-every-green-signal-certified-something-other-than-what-it-claimed.md` | Name what is certified. "Query returned rows" ≠ "a genuine zot event exists" |
| `2026-06-10-betterstack-quota-diagnosis-host-metrics-dominate-generic-http-sink.md` | Quota is a design input, measured not asserted |
| `2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire.md` | `curl -f` exits 22 on 401; and the `/tmp/.doppler` + `PrivateTmp=` interaction is a measured defect on this estate |
| `2026-07-26-cloud-init-comment-is-a-live-host-input-and-an-unreadable-vendor-limit-decays.md` | `hcloud_server.registry` has no `ignore_changes=[user_data]`; comment-only edits are ForceNew input |
| `hr-observability-layer-citation` | This plan's surface is **layer 5 — host/container journald shipped to Better Stack Logs source 2457081** |

### Prior art reused rather than reinvented

- **ADR-172**: a marker is trusted **only after readback**; the poll budget is a multiple of the
  **measured 17 s** POST→queryable latency; a readback needs a positive control, and **zero control
  rows means `channel_dark`, never `marker_absent`**.
- **The existing registry emit pattern**: a per-line direct `curl` POST to a Terraform-interpolated
  `betterstack_ingest_url`, wrapped in `doppler run --project soleur-registry --config prd`, using
  the already-admitted `BETTERSTACK_LOGS_TOKEN`. No new secret.
- **The existing sanitizer**, reusable verbatim:
  `tr '\n\r\t' ' ' | LC_ALL=C tr -cd '\40-\176' | tr -d '"\\'`.
- **Resource-governance precedent for a long-running unit**: `inngest-bootstrap.sh` sets
  `MemoryMax=512M`, `CPUQuota=100%`, `RestartSec=5`.
- **`scripts/betterstack-query.sh`** verified flags: `--since <Nh|Nm|Nd|ISO>`, `--until <ISO>`,
  `--grep <substring>` (repeatable, OR-combined), `--limit <N>`, `--raw-only`, `--no-archive`,
  `--table`, `--table-s3`.

### Verified: the zot container already logs to journald

```bash
docker run -d --name zot --restart unless-stopped \
  --log-driver journald \
  --memory "$ZOT_MEMORY_CAP" --memory-swap "$ZOT_MEMORY_CAP" \
  ... '${zot_image}' serve /etc/zot/config.json
```

The container name is literally `zot` and `--log-driver journald` is **already present**. The logs
are already on the host as `CONTAINER_NAME=zot`. **This is a shipping problem, not an
instrumentation problem** — the single most important scoping fact in the plan.

### External research decision (Phase 1.6)

**Skipped as low-value.** The emit transport, credential boundary, readback discipline, quota model
and delivery path are all established in-repo. The one external contract that mattered — zot's log
format — is measured from the host itself in Phase 0 rather than read from documentation.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality | Plan response |
|---|---|---|
| "Ship the logs the same way soleur-web-platform does… follow the existing Vector source/allowlist pattern" | The registry host runs **no Vector agent**; no `include_matches` list exists to extend | **Shape change.** The task is a new shipper. The Vector *discipline* is adopted (exact-value field match, explicit quota budget, redaction before egress); the *agent* is not |
| "the missing-allowlist-entry class is a known failure mode" | Real, but it is the failure mode of a host that **has** a shipper. Here the failure mode one level up applies | Both addressed: field match asserted on both sides by test, **and** the delivery gap made self-reporting by the probe |
| Assert the gate on `routes.go` / `blobs/uploads` / `v2/<repo>` | These are **generic** (any Go service logs `routes.go`) and `blobs/uploads` returned 0 rows even inside echoes. All hosts multiplex into one Logs source | The gate asserts a **positive, host-isolated envelope** the shipper stamps, **and** a zot-only string within it. The issue's requirement is met without inheriting its token choice |
| Implicit: instrumenting zot requires changing zot | The container already logs to journald | Scope narrows to a shipper; no `/etc/zot/config.json` change, keeping clear of ADR-172 §3's write-surface deadlock |
| Implicit: the fix takes effect on merge | Registry resources are `OPERATOR_APPLIED_EXCLUSIONS` | Ships **inert-until-provisioned** and says so. Pre-merge ACs assert *correctness*; *liveness* is owned by an enrolled probe on a **dedicated tracker** |
| Attribute the ~44.22 GB before reclaiming | The recut **already reset** the store (`pcent=8`) | Original attribution unrecoverable; reframed forward-looking, and written into the downstream issue rather than only here |

## Hypotheses

Phase 1.4 fired on the substrings `timeout` and `SSH`. **This is not a connectivity-outage
diagnosis** — the registry answers `/v2/` (`ping_rc=0`), and the `.uploads/` i/o timeouts are cited
as *examples of what becomes queryable*, not as the defect being fixed. The L3/L7 rows are scoped
opt-outs with artifacts, per the checklist's opt-out clause.

| Layer | Disposition | Artifact |
|---|---|---|
| **L3 — firewall** | **Opt-out, not applicable.** No inbound access is required or changed; the shipper is egress-only, and the identical egress demonstrably works — the heartbeat POST lands every 5 min | The 53 heartbeat rows |
| **L3 — DNS / routing** | **Opt-out, same artifact** — the heartbeat resolves and reaches the same ingest host | Same 53 rows |
| **L7 — TLS / proxy** | **Opt-out, same artifact** — same URI, header, and TLS endpoint | Same 53 rows |
| **L7 — application** | **Verified, and it is the finding.** The host journal is exactly what cannot be read off-box; the heartbeat's `zot_last_err` proves the journal holds the data | The `zot_last_err` sample |

### Why no genuine zot rows reach the warehouse

| # | Hypothesis | Discriminator | Verdict |
|---|---|---|---|
| **H0** | The host cannot receive a config change, so no fix is deliverable | Live heartbeat `boot_id`/`zot_uptime_s`; #7287 ordered-path state | **CLEARED, RE-PROBE REQUIRED (Phase 0.1).** A step-6 replace is pending in #7287 and is the delivery vehicle |
| **H1** | No shipper process exists | Read `cloud-init-registry.yml` end to end | **CONFIRMED by direct file read.** The only egress paths are the two 5-min reporters and two heartbeat pings; none forwards container logs |
| **H2** | A shipper exists but zot is not matched | `docker run` flags | **REFUTED.** `--log-driver journald` present, container named `zot`. H1 makes it moot; recorded because it is what the issue's framing assumes |
| **H3** | The journal does not retain the lines | Image default for `Storage=` + journald size caps | **PARTIALLY RESOLVED, NOT BY FILE READ.** `cloud-init-registry.yml` sets no `Storage=`, no `SystemMaxUse=`, no `/var/log/journal`. So the *config* answer is "unset" and the *effective* answer is the image default — see Phase 0.2. A file read cannot answer a host-state question |
| **H4** | Rows ship but the query cannot see them | Positive control: 53 heartbeat rows, same window/source/credentials | **REFUTED by measurement.** The query path works; the zero is a real zero |

## Open Code-Review Overlap

**None.** Queried all 64 open `code-review` issues for any body reference to
`cloud-init-registry.yml`, `zot-registry.tf`, `registry-userdata-budget`, `scripts/test-all.sh`,
`model.c4`, `scheduled-followthrough-sweeper.yml`, `betterstack-query.sh` — zero matches.

## Panel Findings That Changed the Architecture

Recorded in place, because each was a premise a future reader would otherwise re-derive.

| # | Finding | Disposition |
|---|---|---|
| **A1** | **The ADR's binding reason was falsified.** The claim that Vector's scrub could only run in its `+skipped_pepper_unset` degraded arm is wrong three ways: the pepper lookup is nested inside `if raw_key != ""` and needs a top-level `userId`/`user_id` key, which zot never emits (it logs `username:zot-pull`); the degraded tag does **not** contain `structured`, so `pii_scrub_string` still runs the full string scrub; and Vector needs only the already-admitted `BETTERSTACK_LOGS_TOKEN`, so the 4-name guard never trips | **Reason replaced.** The genuinely disqualifying finding is `vector.toml:298` — `pii_scrub_drop_userdata` does `if exists(parsed_obj.message) { del(parsed_obj.message) }`, and zerolog emits a top-level `message`. A Vector-shipped zot line would arrive **with its message text deleted**: nominally shipping, actually empty |
| **A2** | **The "measured" log shape was the sampler's** quote-stripped rendering | **Corrected**; Phase 0.3 measures the raw shape before any rule or discriminator is written |
| **A3** | **The enrollment was a permanent silent no-op** — the directive sat on the issue the PR closes | **Dedicated tracker.** See Phase 3.2 |
| **A4** | **No resource governance** on what would be the host's first `Restart=always` unit | **Hard caps added.** See Phase 2.1 |
| **A5** | `--cursor-file` **does not survive SIGKILL** (measured on systemd 259: SIGKILL → file never created; SIGTERM → written). The man page documents the *timer* idiom this plan rejected, so the alternatives-table rejection was asserted, not verified | **Design changed** to self-persisted `__CURSOR` + `--after-cursor` — durable under SIGKILL and better than either original option |
| **A6** | The selectivity filter duplicated the rate cap **and suppressed the free positive control**, then a canary was built to reintroduce it | **Filter cut, canary cut.** Ship `CONTAINER_NAME=zot` wholesale; the cap bounds volume with class priority |
| **A7** | Four of six redaction rules **cannot fire** (no email in zot's identity model; no `sync`/`extensions`/`credentialsFile` in the config, so no credentialed upstream URL; htpasswd values never echoed; `Authorization` masked upstream). The `tr` pipeline is **payload integrity**, not redaction, and was mislabelled | **Reduced to sanitizer + one backstop**, with the reframing named so a future reader does not restore five dead rules believing they were safety |
| **A8** | Phase 5.1's premise was already false — both registry runbooks already declare no-SSH — and it would have pointed operators at a **dark** channel | **Phase cut.** Replaced by an edit to `betterstack-log-query.md`, the reader's actual entry point, which was missing from Files to Edit |
| **A9** | Nothing wrote into the downstream issue whose criterion this exists to unblock | **Phase 4.3 added** |
| **A10** | **The C4 finding was false.** An earlier draft asserted `zotRegistry -> betterstack` did not exist; it is at `model.c4:562`. The probe's character class was lowercase-only and could not match the camelCase element name, and the AC built on it **passed on `main` unmodified** | **Corrected to an amendment**, and the AC now asserts amended *content*. The real work was found inside line 562: it asserts the unfired-recut blocker that ADR-184 retires, so the two would have shipped contradicting each other |
| **A11** | **Wrong test registration point.** `scripts/test-all.sh` does not register infra suites; `run-registered-suites.sh` derives its list from `infra-validation.yml`, which appeared in no Files list. Following the plan literally produced a silent orphan suite | **`infra-validation.yml` added to Files to Edit**, and AC 1 now asserts the suite actually ran rather than that the runner was green |
| **A12** | **ADR-178 was also taken** — the plan applied the ordinal lesson to 177 and then walked into 178 | **Moved to 179**, with the measurement across all 2,984 refs and the note that `check-adr-ordinals.sh` has no remote-ref logic |
| **A13** | **The discriminator could never match**: ClickHouse stores `raw` double-encoded, so `caller:zotregistry.dev` becomes a `LIKE` that matches nothing | **Encoding-safe grep token + decode-then-field-isolate** |
| **A14** | `post_fail` was surfaced on a shipper-emitted row — unobservable precisely when the POST path is the fault; `host_name` does not exist on a direct-POST channel; drop-count `n` had no denominator; the probe's exec bit and the `${VAR:?}` ban were unstated | **All corrected** in `## Observability` and ACs 9–15 |

## Architecture Decision (ADR/C4)

### ADR

**ADR-184 (ordinal settled at implementation time; the plan drafted it as 179) — "The registry host ships container logs with a self-contained
journald shipper, not a Vector agent."**

1. Container logs leave this host through a **purpose-built journald→ingest shipper** reusing the
   already-admitted `BETTERSTACK_LOGS_TOKEN` and the existing per-line direct-POST transport.
2. **The binding reason is payload destruction, not credentials** (finding A1). The shared
   `vector.toml` drops any top-level `message` key as an Art-9 user-content key; zerolog's log text
   *is* a top-level `message`. Shipping zot through the shared config would deliver rows with the
   message deleted. Supporting reasons, each sufficient on its own: `host_metrics` quota cost
   (~19.9k rows/day against a 25k/day threshold), a boot-time binary download on the sole pull path,
   a second config to hold in lockstep, and `user_data` budget. **The pepper/isolation-guard
   argument is explicitly retracted — do not re-derive it.**
3. **A direct host POST bypasses VRL redaction**, so the shipper owns its own sanitizer plus one
   `authorization:` backstop, asserted by fixtures against the **raw quoted** shape. This is
   ADR-172 §1's reasoning applied to a host-side emitter.
4. This is the registry host's **first `Restart=always` unit** — every existing unit is
   `Type=oneshot`. Recorded because it changes the host's failure surface and is why §5 exists.
5. **Resource governance is the only available containment.** With no in-place execution path there
   is no kill switch, so the unit must be incapable of needing one: `MemoryMax`, `CPUQuota`,
   `IOWeight`, explicit `RestartSec` and start-limit policy.
6. **Amendment to ADR-172 §8.** Its *"while the LUKS recut is unfired there is no safe provisioning
   event"* and its corollary that *"the read-only surface is currently the only instrumentable
   one"* were true when written and are no longer. §3's write-surface finding is undisturbed: this
   plan changes no `accessControl` and grants no `delete`. ADR-096's cloud-init-only posture is
   restated in one sentence here rather than amended separately.

**Ordinal is provisional, and this plan already got it wrong once.** An earlier draft chose 178 in
the same breath as warning that 177 was claimed on a pushed branch — then walked into the identical
trap. Measured across all 2,984 refs and the reachable object graph:

- `ADR-177` is claimed **twice** (`shared-bash-primitives-ship-in-plugin`,
  `test-runner-result-taxonomy-unresolved-is-not-failed`).
- `ADR-178-guard-contract-as-plan-time-deliverable.md` **exists** on an unmerged branch.
- Next free is **179**, in an actively contested space (171 and 175 are also each doubly claimed).

`scripts/check-adr-ordinals.sh` contains **no remote-ref logic**, so there is no existing gate behind
"quantify over all remote refs" — the plan must supply the command. Re-derive immediately before
merge; on renumber, sweep `knowledge-base/project/{plans,specs}/` so no AC names a nonexistent file.

### C4 views

All three model files were read. **An earlier draft of this section asserted that
`zotRegistry -> betterstack` did not exist. That was false, and the way it was false is worth
recording:** the probe was `grep -nE '^\s*[a-z_.]*registry[a-z_.]* +->'` — a lowercase-only
character class that cannot match the camelCase element name `zotRegistry`. The grep returned zero
and the zero was read as an absence. This is the same "my check certified something other than what
it named" class the plan cites elsewhere, committed by the plan's own research step.

| Element class | Enumerated | Already modeled? |
|---|---|---|
| External human actor | none participates in a log-shipping path | n/a |
| External system | `betterstack = system "Better Stack"` | **Yes** |
| Emitting element | `zotRegistry = system "Self-hosted zot registry"` | **Yes** |
| Container / data store | host journald; Logs source 2457081 | Journal is not a modeled element and need not be |
| **Access relationship that changes** | `zotRegistry -> betterstack` | **EXISTS at `model.c4:562`** — it already models the `SOLEUR_ZOT_DISK` + `SOLEUR_PRIVATE_NIC` self-reports |

**So the C4 task is an AMENDMENT of the existing edge, not an addition** — and adding a second
`zotRegistry -> betterstack` line, as the earlier draft prescribed, would have created a duplicate
relation. The real work is *inside* line 562, and it is load-bearing: that description currently
asserts

> `DO NOT LOOK FOR A HOST-SIDE SOLEUR_ZOT_INVENTORY EMITTER — THERE IS NONE. … the registry host is
> cloud-init-only (ADR-096), so adding any host-side emitter needs a host REPLACE, and a replace
> today opens /dev/mapper/registry against a still-plaintext ext4 volume (the LUKS recut is UNFIRED
> — #7287) and darks the sole pull path. CI-side emission is the entire near side of that deadlock
> (ADR-172 §8)`

That is **the same premise ADR-184 amends.** Left as-is, `model.c4` and the new ADR ship
contradicting each other. The amendment must add the container-log channel to the description and
retire the unfired-recut blocker clause.

**Two further earlier-draft claims were also false and are retracted:** the `SOLEUR_ZOT_DISK`
emission is *not* unmodeled (line 562 is exactly that writer, and the `betterstack` element
description names it), and the `SOLEUR_PRIVATE_NIC` attribution is *already* handled — line 521
carries "registry's SOLEUR_PRIVATE_NIC (this edge is the SECOND source of that event)" and line 528
says "unlike the registry's self-converging guard". Nothing to correct there.

**No `views.c4` change is required** — both endpoints are already in the `context` and `containers`
`include` lists, so the amended edge renders.

**One contradiction to resolve while in the file:** line 562 calls 2457081 "the isolated Logs
source" while line 503 states "Source 2457081 is NOT isolated to this node — the web hosts ship to
the SAME source". The latter is correct and is why this plan's discriminator is an in-message
`host=` token. Pick the accurate wording.

Run `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` after editing — an
undefined-element reference fails there, not at `tsc`.

### Sequencing

ADR-184 is authored now at `status: adopting`. Its flip to `accepted` is owned by the follow-through
probe on the dedicated tracker — which is also why finding A3 mattered: on a closed tracker a real
PASS produces no artifact, so nothing would ever have flipped it.

## Infrastructure (IaC)

### Terraform changes

**None — a deliberate design property.** The shipper lives entirely inside
`cloud-init-registry.yml`, which `hcloud_server.registry` already renders. ADR-172's *Alternatives
Considered* records that **any** new `.tf` resource on this surface has no scoped apply path,
because no registry dispatch target creates it and an untargeted apply carries the pending
`-/+ hcloud_server.registry` REPLACE in state. Zero-Terraform sidesteps that entirely. No new
provider, variable, or secret.

### Apply path

**(a) cloud-init-only — inert until the next provisioning event.**

- Delivery is the dispatch-only `registry-host-replace` target. Merging applies nothing.
- **This plan does not request a replace.** It rides #7287's ordered-path step 6. Firing a
  destructive replace is a separately-authorized prod-write
  (`hr-menu-option-ack-not-prod-write-auth`: a menu ack is not prod-write authorization).
- **Honest framing (finding from the panel):** this *is* a deferral of delivery, and an earlier
  draft's claim that there was "nothing to defer" was doing work to hide that. It is tracked
  explicitly: Phase 4.4 records the rider on #7287's ordered path, and the probe directive carries
  an escalation horizon so an indefinitely-undelivered change escalates instead of reporting
  TRANSIENT forever.
- Downtime from this change alone: **zero** — it applies nothing.

### Distinctness / drift safeguards

- `hcloud_server.registry` carries **no** `ignore_changes = [user_data]`; cloud-init content is live
  ForceNew input. Accepted: the change rides the next replace rather than triggering one.
- `random_password.registry_luks` must remain **absent** from `replace_triggered_by` (exactly
  `[random_password.zot_pull, random_password.zot_push]`). This plan does not touch
  `zot-registry.tf`; recorded in Risks rather than as an AC, since a file absent from the diff needs
  no post-condition.
- The 32,768 B cap is a hard gate: over-cap rejects the CREATE *after* the DESTROY.

### Vendor-tier reality check

No new vendor resource or tier gate. Better Stack Logs source 2457081 already receives this host's
markers; the change is additional row volume against an existing quota, budgeted with real numbers
in `## Observability`.

## Observability

The numeric contract lives here (not in the phases) so Phase 1 tests a specification rather than
inventing one.

```yaml
liveness_signal:
  what: "Envelope-stamped zot rows. Every line the shipper POSTs is prefixed
         `SOLEUR_ZOT_LOG shipper=zot-log-shipper host=<hostname> <sanitized zot line>`.
         Shipper liveness needs no dedicated canary: zot-liveness-heartbeat.timer GETs /v2/ every
         60s and zot logs every request at info, so envelope-stamped rows arrive continuously by
         construction. This control traverses the WHOLE path (zot -> journald -> match -> sanitize
         -> POST -> warehouse); a shipper-emitted canary would skip journald and the field match,
         which are the actual failure modes."
  cadence: "~1,440 rows/day floor from the 60s liveness GET alone, before real pull traffic"
  alert_target: "Better Stack Logs source 2457081; read by the follow-through probe"
  configured_in: "apps/web-platform/infra/cloud-init-registry.yml (zot-log-shipper block)"

payload_schema:
  wire: '{"message":"SOLEUR_ZOT_LOG shipper=zot-log-shipper host=<hostname> <sanitized line>"}'
  rationale: "One line per POST, mirroring the proven reporter transport (cloud-init-registry.yml's
              `post()` sends exactly one key, `message`). The envelope is the POSITIVE, host-isolated
              discriminator. NOTE the field name trap: `host_name` is a VECTOR-populated field and
              this channel has no Vector — a direct POST carries no `host_name` and no
              SYSLOG_IDENTIFIER at all, so the host token must live INSIDE the message string,
              exactly as the reporter embeds `host=$(hostname)` in its own line. Source 2457081 is
              explicitly NOT isolated to this host (the web hosts ship to the same source), so this
              in-message token is the only available isolation. Asserted from BOTH the shipper test
              and the probe fixture so the two sides cannot drift."
  query_safe_token: "`zotregistry.dev/zot/v2/pkg/api` — the zot-only substring the probe greps.
              It deliberately contains NO quotes and NO colon, because ClickHouse stores `raw`
              DOUBLE-ENCODED: real zot JSON is `\"caller\":\"zotregistry.dev/…\"` and the stored
              bytes are `\\\"caller\\\":\\\"zotregistry.dev`. A grep for `caller:zotregistry.dev`
              becomes `raw LIKE '%caller:zotregistry.dev%'` and matches NOTHING, EVER — the trap
              betterstack-query.sh's own header documents. Grep the encoding-safe substring, THEN
              decode (`jq 'fromjson? | .raw' | jq 'fromjson? | .message'`) and field-isolate on the
              decoded object rather than substring-matching the raw line."

rate_cap:
  budget: "5,000 rows/day steady-state cap. Floor is ~1,440/day (60s liveness) + ~288/day
           (heartbeat ping_rc) before real traffic; the cap leaves headroom for deploys without
           approaching the 25k/day threshold that host_metrics (~19.9k/day) already occupies."
  class_priority: "The four measured evidence classes — `executing gc`, `gc successfully completed`,
                   `garbage collected blobs`, `PatchBlobUpload` — are CAP-EXEMPT. Without this the
                   cap drops the diagnostic evidence preferentially during exactly the flood
                   (crash-loop / pull storm) that accompanies disk growth."
  drop_accounting: "Drops emit
                    `SOLEUR_ZOT_LOG_DROPPED n=<N> interval_s=<N> boot_id=<id> seq=<N> cum=<N>
                     reason=<rate_cap|cursor_invalidated>`.
                    `n` is scoped to THE INTERVAL THIS ROW CLOSES — an earlier draft asserted an
                    'exact count' against an undefined denominator, which a fixture would have
                    silently pinned to whatever the implementation happened to do. The extra fields
                    exist because three boundaries otherwise make `n` a lower bound with no marker
                    saying so: a host replace resets counters on the root fs to 0; a crash replay
                    re-counts re-shipped lines; and a line crossing the cap mid-interval is
                    attributable to either interval. `boot_id` + `seq` let a reader DETECT the
                    discontinuity, which is exactly the marker silent truncation lacks."

error_reporting:
  destination: "Better Stack Logs source 2457081 via the same per-line POST the reporter uses."
  fail_loud: "A POST failure retries once then breadcrumbs to journald, mirroring the reporter's
              `post || post || echo ... >&2`.
              CRITICAL — POST-failure telemetry does NOT ride the POST path. An earlier draft
              surfaced `post_fail` on a shipper-emitted row, which is unobservable in exactly the
              state it reports: when the POST path is the fault, the row carrying the counter never
              arrives. That is this plan's own cited learning
              (2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire).
              Instead the counter rides an INDEPENDENT WORKING PATH: the 5-min SOLEUR_ZOT_DISK
              reporter reads the shipper's state file and carries
              `log_shipper_post_fail=<N> log_shipper_last_ok_age_s=<N>` in its own line. That also
              gives the probe a `shipper_post_failing` reason that survives a dead egress."

failure_modes:
  - mode: "Never delivered (host not yet replaced)"
    detection: "IN-SURFACE: a one-shot boot marker `SOLEUR_ZOT_LOG_BOOT boot_id=<id>` fired once
                from runcmd, mirroring the existing precedent where both reporters fire once at
                boot. Absent boot marker + unchanged SOLEUR_ZOT_DISK boot_id = not delivered."
    alert_route: "probe exit 2, reason=not_delivered"
  - mode: "Delivered and dead (shipper crashed or start-limit latched)"
    detection: "Boot marker present OR SOLEUR_ZOT_DISK boot_id drifted past the value recorded at
                merge, AND zero envelope rows. This is the state that separates WAIT from ACT, and
                an earlier draft collapsed it into 'shipper_absent'."
    alert_route: "probe exit 2, reason=delivered_but_silent — escalates past the horizon"
  - mode: "Shipping but POSTs mostly or wholly failing"
    detection: "TWO independent signals, neither riding the failing path: (a) envelope rows present
                but far below the ~1,440/day floor implied by the 60s liveness GET — a computable
                expectation, so a shortfall is measurable rather than a judgement call; (b)
                `log_shipper_post_fail` / `log_shipper_last_ok_age_s` carried by the 5-min
                SOLEUR_ZOT_DISK reporter, which is the only signal that survives a TOTAL egress
                failure."
    alert_route: "probe exit 2, reason=below_expected_floor or reason=shipper_post_failing"
  - mode: "Runaway volume"
    detection: "`SOLEUR_ZOT_LOG_DROPPED n=<N>` rows climbing; cross-check SOLEUR_ZOT_DISK
                zot_restarts delta over the same window"
    alert_route: "the DROPPED rows are the signal; scripts/zot-restart-loop-alarm.sh owns the cause"
  - mode: "Cursor invalidated (journal rotated past the persisted cursor during a sink outage)"
    detection: "`--after-cursor` rejects the cursor; the shipper emits
                `SOLEUR_ZOT_LOG_DROPPED reason=cursor_invalidated` and restarts from the journal
                tail rather than gapping silently"
    alert_route: "the DROPPED row"
  - mode: "Redaction regression ships a credential off-box"
    detection: "Pre-merge fixtures per rule against the RAW QUOTED shape + a negative control.
                Post-delivery: a credential-shape query must return zero."
    alert_route: "pre-merge hard FAIL; post-delivery this is the ONE arm that exits 1 (see below)"
  - mode: "Feedback loop (shipper ships its own output)"
    detection: "The shipper matches CONTAINER_NAME=zot; its own lines carry
                SYSLOG_IDENTIFIER=zot-log-shipper and no CONTAINER_NAME, so they cannot match.
                Asserted pre-merge on both sides of the filter."
    alert_route: "pre-merge test failure"
  - mode: "Double-run (unit plus a boot-time invocation)"
    detection: "`flock -n` singleton, mirroring both cron siblings on this host"
    alert_route: "pre-merge test failure"
  - mode: "Journal retention too SHORT under flood (the inverse of the drafted risk)"
    detection: "Deliberate `SystemMaxUse=`/`RuntimeMaxUse=` sizing against the measured
                4.8-restarts/min flood rate, asserted by test. A percentage default gives a very
                short window under flood, shrinking the shipper's catch-up reach."
    alert_route: "pre-merge assertion; existing soleur-registry-disk-prd heartbeat for the disk"

logs:
  where: "Better Stack Logs source 2457081 (EU — Hetzner Falkenstein eu-fsn-3), which is SHARED by
          every host, so isolation is the envelope's in-message `host=soleur-registry` token, not a
          `host_name` field (that field is Vector-populated and this channel has no Vector).
          Observability layer 5 — host/container journald shipped to the Logs warehouse
          (hr-observability-layer-citation)."
  retention: "betterstack-query.sh queries hot + S3 archive BY DEFAULT; `--no-archive` opts DOWN to
              the ~40-minute hot window. An earlier draft stated this backwards. The probe's window
              is 30 min — entirely inside the hot keyhole — so it passes `--no-archive` deliberately:
              the default archive arm would add an S3 failure mode to a steady-state probe for no
              coverage. The sibling probe's header explicitly warns against copying flags between
              the days-old and seconds-old cases."

discoverability_test:
  command: "bash scripts/followthroughs/zot-log-channel-7440.sh"
  expected_output: "PASS: envelope rows observed (envelope=<N> control=<N> gc_start=<N> gc_done=<N>)"
  credentials_required: "BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} — read-only ClickHouse query
    credentials for Logs source 2457081. No unauthenticated substitute exists: the warehouse
    exposes no public read surface, and the property under test is 'a row reached this specific
    source', unverifiable from outside it."
```

### Soak follow-through enrollment (Phase 2.9.1)

- **Script:** `scripts/followthroughs/zot-log-channel-7440.sh`
- **Tracker: a DEDICATED issue, never #7440.** This is finding A3, and the template probe's own
  header states the rule: *"TRACKER: #7339 (dedicated). NOT #7278 — that issue is closed by the
  shipping PR and the sweeper lists `--state open`, whose reopen path fires only on exit 1, so a
  correct exit-2 probe hosted there would be a permanent silent no-op."* Traced in
  `scripts/sweep-followthroughs.sh`: on a **closed** issue `rc=0` → no action **and no comment**, so
  even the eventual real PASS would leave no artifact to flip ADR-184; `rc=2` → no action, no
  comment; and `CLOSED_LOOKBACK_DAYS=14` removes the issue from the candidate set entirely after two
  weeks. The PR still carries `Closes #7440`.
- **Directive** on the dedicated tracker, with the `follow-through` label:
  `<!-- soleur:followthrough script=scripts/followthroughs/zot-log-channel-7440.sh earliest=2026-08-12 secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->`
- **Secrets wiring: already present** — `scheduled-followthrough-sweeper.yml` already exports all
  three `BETTERSTACK_QUERY_*` names. No workflow edit; the AC asserts rather than adds.
- **Exit-code contract**, mirroring the sibling probe with one deliberate carve-out:
  - `0 = PASS` — envelope rows observed with the control present.
  - `2 = TRANSIENT` — not delivered, delivered-but-silent, below floor, `channel_dark`, or any
    auth/query/decode failure. Each prints a **distinct reason**; an unprovisioned credential must
    not read as "not yet delivered".
  - `1 = FAIL` — emitted **only** when a credential shape is found in the channel. This is the
    carve-out and it is deliberate: a leak is a regression, not a not-yet, and at
    `single-user incident` threshold it must reopen and comment. Everywhere else `exit 1` is
    forbidden because it reopens the tracker daily.
- **Escalation horizon.** The directive body records that TRANSIENT is expected until the replace,
  and that `delivered_but_silent` or an undelivered state persisting past **90 days** is an
  escalation rather than a steady state.
- **Known cost, stated rather than discovered:** on the open path the sweeper comments
  unconditionally before deciding, so a correctly-behaving exit-2 probe posts one comment per sweep
  until delivery. The tracker body says so, so the noise reads as designed.

## Encryption Posture

```yaml
at_rest:
  - store: "Host journald (root filesystem)"
    mechanism: "plaintext-exception"
    evidence: "The LUKS mapper /dev/mapper/registry backs /var/lib/zot (the data volume) only; no
               dm-crypt device fronts the root filesystem."
    defends_against: "nothing at rest — listed so the gap is explicit"
    does_not_defend: "offline disk acquisition, Hetzner-side snapshot access, or any read by a
                      process that gains root"
    disclosed_as: "internal host telemetry; not a user-data store"
    live_verification: "journald size caps asserted by the cloud-init test suite (Phase 1.1); host
                        disk state reported every 5 min by SOLEUR_ZOT_DISK"
  - store: "Shipper cursor + rate-cap state (/var/lib/zot-log-shipper/)"
    mechanism: "plaintext-exception"
    evidence: "Same root filesystem; deliberately NOT on the LUKS data volume so a fresh host
               starts from a fresh cursor rather than replaying a stale one."
    defends_against: "nothing at rest"
    does_not_defend: "same vectors as the journal"
    disclosed_as: "an opaque journald cursor string plus integer counters — no log content"
    live_verification: "asserted by the shipper unit test (path + content shape)"
  - store: "Better Stack Logs source 2457081"
    mechanism: "vendor-managed encryption at rest — PRE-EXISTING and unchanged by this plan"
    evidence: "EU region (eu-fsn-3), pinned and transfer-recorded in vector.toml per the #4293
               GDPR Art-44 transfer record. This plan adds row volume to an established
               sub-processor, not a new store."
    defends_against: "at-rest access to the vendor's storage layer"
    does_not_defend: "anything visible to an authenticated reader, including every holder of
                      BETTERSTACK_QUERY_* credentials"
    disclosed_as: "third-party log warehouse, already disclosed"
    live_verification: "vendor attestation only; not independently verifiable from this repo"

in_transit:
  - connection: "registry host -> https://s2457081.eu-fsn-3.betterstackdata.com/ (new log channel)"
    tls: "TLS 1.2+ via curl default"
    cert_verification: "on"
    does_not_defend: "a compromised host, or the token holder; TLS protects the hop, not the endpoints"
    disclosed_as: "existing egress path — the reporter already POSTs to this exact URI from this
                   exact host"

exception:
  - store: "Host journald + shipper cursor state (plaintext on the root filesystem)"
    justification: "Encrypting the registry host root filesystem is out of scope and materially
      riskier than the gap it closes: the host is cloud-init-only, so a root-fs encryption change is
      deliverable only by replacing the sole container-image pull path, and an unlock step on the
      root device adds a boot-time failure mode to exactly the host whose boot failure darks every
      deploy. The content at risk is our own service telemetry — internal 10.0.1.x addresses, our
      own service usernames, our own OCI repo names and digests — with no end-user personal data."
    tracking_issue: "filed in the same PR — 'Evaluate LUKS for the registry host root filesystem',
      labelled deferred-scope-out"
    reevaluate_when: "the host next carries any store beyond service telemetry, or a root-fs LUKS
      pattern is proven on a non-critical host first"
    expires_on: "2027-02-11"
```

## User-Brand Impact

**If this lands broken, the user experiences:** a failed deploy with no diagnosable cause. The
registry is the sole container-image pull path since the GHCR read PAT was revoked 2026-07-30, so a
shipper that consumes memory or IO enough to destabilise the container takes down every release and
every cold boot. This risk is concrete rather than theoretical: zot's cgroup cap is *derived* as
host RAM minus a 1024 MB reserve documented for "cron+doppler+sshd+OS", and this change adds three
permanently-resident processes to that line item. #6288 was a host-level OOM restart loop on this
same host. The user-visible artifact is a platform stuck on a stale image with a release workflow
that keeps failing.

**If this leaks, the user's data/workflow is exposed via:** log lines POSTed to a third-party
warehouse without VRL redaction. The concrete vector is the shipper's own sanitizer: a rule anchored
on the wrong shape ships `"Authorization":["Basic …"]` into Better Stack, readable by every holder of
`BETTERSTACK_QUERY_*` credentials. The registry's push credential protects the image supply chain,
so a leaked one is a supply-chain exposure, not a log-hygiene defect. Finding A2 is exactly this
risk realised at design time — the original rules would not have matched production.

**Brand-survival threshold:** `single-user incident`

One occurrence suffices in both directions: a single credential in a single shipped line is a
supply-chain exposure, and a single runaway shipper darks every deploy. Hence
`requires_cpo_signoff: true` and `user-impact-reviewer` at review time.

## Implementation Phases

### Phase 0 — Preconditions (measure; do not infer)

0.1 **Re-probe the delivery window (H0).** Read the current heartbeat and record `boot_id`,
   `zot_uptime_s`, `pcent`, `resize_ok`; re-read #7287's state. **Record the `boot_id` value** — it
   is the baseline the probe uses to discriminate "not delivered" from "delivered and dead". If the
   store is refilling or the ordered path regressed, **stop and re-scope**.

0.2 **Journald is a DECIDED design input, not a probe.** An earlier draft asked to "establish from
   `cloud-init-registry.yml`" whether the journal is persistent — a file cannot answer a host-state
   question, so that step had no possible command and left H3 UNKNOWN by its own terms. What the
   repo *does* answer: the file sets **no** `Storage=`, **no** `SystemMaxUse=` and **no**
   `/var/log/journal`, so behaviour is the base-image default. Ubuntu ships `Storage=auto` with no
   `/var/log/journal` present, which means **volatile** — the journal lives in `/run/log/journal`, a
   tmpfs, bounded by `RuntimeMaxUse` ≈ 10% of `/run`. On a 3,814 MB host where zot is capped at
   3,072 MB and the documented reserve is 1,024 MB, that is **RAM pressure on the host whose OOM
   history is why the cap exists**.

   **Decision: the shipper block sets `Storage=persistent`, `SystemMaxUse=` and `RuntimeMaxUse=`
   unconditionally**, moving the buffer off tmpfs and bounding it on both media. Size
   `SystemMaxUse=` against the measured 4.8-restarts/min flood rate, not against root exhaustion: a
   percentage default gives a very short retention window under flood, which is what P1-5/0.5 then
   convert into a gap. Confirm the image from `zot-registry.tf` to check the default assumption, but
   the bound is set either way — an unconditional literal is assertable by test, whereas a
   conditional one is not.

0.3 **Measure zot's RAW log shape** (finding A2) — the single most important precondition. Obtain an
   unstripped line: widen the reporter's trusted region by one field, or read `docker logs zot`
   output through a path that does not apply `tr -d '"\\'`. Record the exact key quoting
   (`"level":"info"` vs `level:info`), how `caller` is rendered, and how header values appear.
   **Every redaction rule and the probe's discriminator derive from this measurement.** Do not carry
   the quote-stripped sample forward.

0.4 **Resolve the long-running-unit-vs-cron differences.** Every existing `doppler run` caller here
   is a short-lived cron fire; this is the first long-running unit and the host's first
   `Restart=always` unit. Decide and record:
   - `DOPPLER_CONFIG_DIR` on a unit-owned `StateDirectory=` path, **not** `/tmp/.doppler`. A unit
     with `PrivateTmp=true` gets a private `/tmp`, so the cron convention resolves elsewhere — the
     #6536 class. Make the `PrivateTmp=` choice explicit either way.
   - An explicit `HOME=` — the cloud-init comment records that the Doppler CLI errors with
     `"$HOME is not defined"` even when `DOPPLER_CONFIG_DIR` is set, and a unit inherits no login
     environment.
   - `RestartSec=` and start-limit policy. Bare `Restart=always` inherits `RestartSec=100ms` with
     `StartLimitBurst=5` in `StartLimitIntervalSec=10s`, so a shipper that fails fast at boot
     (Doppler or network not yet up) **latches `failed` in under a second and stays dead until the
     next boot** — indistinguishable from "not provisioned". Precedent:
     `inngest-bootstrap.sh` (`RestartSec=5`), `cloud-init.yml` (`StartLimitIntervalSec=0`).
   - Note the token contract change: `doppler run` resolves the environment once at `ExecStart`, so
     a `BETTERSTACK_LOGS_TOKEN` rotation breaks a long-running shipper until restart, where a 5-min
     cron re-resolves every tick. A periodic self-restart (`RuntimeMaxSec=`) resolves it cheaply
     given a durable cursor.

0.5 **Cursor durability and cold start** (finding A5), both measured on systemd 259 rather than
   assumed:
   - The invocation form is **not** fabricated — `--cursor-file` is real, coexists with `--follow`,
     bare `CONTAINER_NAME=zot` is the correct match syntax for Docker's journald driver (non-trusted
     field, no leading underscore), and option-after-match ordering parses. Do not re-litigate these.
   - **Durability fails.** The cursor file's checksum was unchanged at t=4 s and t=8 s mid-follow —
     it is never written incrementally. SIGTERM writes it; **SIGKILL leaves it stale**. The man page
     explains why: *"At the end, write the cursor… Use this option to continually read the journal by
     sequentially calling journalctl"* — it is built for one-shot invocations, not a `Restart=always`
     daemon. So on OOM-kill or hard reboot the shipper resumes from the last **clean-exit** cursor
     and **re-ships everything since**, unbounded: the runaway-volume mode triggered by the very
     mechanism chosen to prevent gaps.
   - **Adopt:** keep `--follow`, but have the shipper persist the per-entry `__CURSOR` from the JSON
     it already parses, **after each successful POST**, with an atomic write. The cursor then means
     *delivered*, not *read*.
   - **Cold start is a separate decision.** With no cursor file, `--follow` implies `-n 10`, so a
     fresh host's shipper **discards the boot backlog** — the window persistence exists to preserve.
     Pass `--no-tail` (measured: with a seeded cursor the implied `-n 10` does not truncate the
     backlog, so `--no-tail` is the safe default in both states).
   - **Correct the alternatives-table wording**, which conflated "timer" with "`--since` windows".
     The sequential cursor form the flag is documented for is a legitimate third option and is not
     the window-arithmetic design that was rejected.

0.6 **Confirm the inline-script test-extraction precedent** and, critically, that the test **applies
   `local.registry_rationale_strip` before executing** the extracted program. The strip is a blanket
   whole-line comment removal (`"/(?m)^[ \t]*#([ \t][^\t\n]*)?\n/"` shape) that reaches inside
   heredocs, so an unstripped test exercises a different program than the host runs.
   `zot-liveness-heartbeat.test.sh`'s extraction is the right template but does not currently apply
   the strip.

0.7 **Read the sibling probe end to end** —
   `scripts/followthroughs/zot-inventory-marker-7278.sh`. Its **first eight lines** carry the
   dedicated-tracker rule that finding A3 turned on. Mirror the contract; do not re-derive it.

0.8 **Measure current Better Stack utilisation** for source 2457081 against its plan limit, so the
   5,000 rows/day cap is set against a real number rather than an assumed headroom.

### Phase 1 — RED: tests before the shipper exists

Per `cq-write-failing-tests-before`. Fixture values are synthesized
(`cq-test-fixtures-synthesized-only`); their **shape** comes from Phase 0.3.

1.1 `apps/web-platform/infra/zot-log-shipper.test.sh` (new), registered in `scripts/test-all.sh`:
   - **Post-strip execution.** Extract the shipper, apply the rationale strip, assert the result is
     valid bash (`bash -n`), and run every subsequent assertion against the **stripped** program.
   - **Field-match lockstep, both sides**, asserted on the executable anchor (the `journalctl`
     invocation) rather than a bare token, since a rationale comment mentioning
     `CONTAINER_NAME=zot` would otherwise satisfy it.
   - **Feedback-loop guard**: `SyslogIdentifier=zot-log-shipper` cannot satisfy `CONTAINER_NAME=zot`.
   - **Singleton**: `flock -n` present, mirroring both cron siblings.
   - **Resource governance**: `MemoryMax=`, `CPUQuota=`, `IOWeight=`, `RestartSec=`, start-limit,
     explicit `HOME=`, and a `DOPPLER_CONFIG_DIR` containing no `/tmp` component.
   - **Journald caps**: the chosen `SystemMaxUse=`/`RuntimeMaxUse=` literals are present.
   - **Sanitizer vs redaction, named separately.** Assert the `tr` pipeline (payload integrity —
     RFC 8259 validity) and, separately, the single `authorization:` backstop against the **raw
     quoted** shape, plus a negative control proving a clean diagnostic line survives byte-for-byte.
   - **Envelope schema**: every shipped line carries
     `SOLEUR_ZOT_LOG shipper=zot-log-shipper host=<hostname>` — the same assertion the probe fixture
     makes, so the two sides cannot drift.
   - **Rate cap**: exact drop count in `SOLEUR_ZOT_LOG_DROPPED n=<N>`, **and** that the four
     cap-exempt evidence classes survive a flood that drops ordinary rows.
   - **Cursor**: `__CURSOR` persisted per batch; `--after-cursor` resume; an invalidated cursor emits
     `reason=cursor_invalidated` rather than gapping silently.
   - **Bounded egress**: every network call carries `curl --max-time`; no unbounded call in a loop.

1.2 `tests/scripts/test-zot-log-channel-probe.sh` — fixtures modelling the real
   backslash-escaped ClickHouse `raw` shape:
   - control + envelope rows present → **exit 0**
   - boot marker/`boot_id` drift present, zero envelope rows → **exit 2**, `reason=delivered_but_silent`
   - no boot marker, `boot_id` unchanged → **exit 2**, `reason=not_delivered`
   - envelope rows far below the ~1,440/day floor → **exit 2**, `reason=below_expected_floor`
   - zero control rows **with** envelope rows present → **exit 2**, `reason=control_missing` — NOT
     `channel_dark`; the envelope proves the channel is live, and this state masks a dead heartbeat,
     a separate live incident
   - zero control **and** zero envelope → **exit 2**, `reason=channel_dark` (never `marker_absent`)
   - unset credential → **exit 2** with its **own distinct reason**, not collapsed into not-delivered
   - credential shape found in the channel → **exit 1** (the sole exit-1 arm)
   - **the false-green fixture**: a window containing only heartbeat-echo rows matching
     `zotregistry.dev` must **not** PASS. This is the highest-value assertion in the plan — it is the
     exact state production is in today, where a naive grep returns 53 rows.
   - **PASS-arm reachability**: a positive fixture proves exit 0 is attainable, so "never emits
     exit 1" cannot be satisfied by a probe that can never pass.

1.3 **Local integration rehearsal** — the surface fixtures cannot reach, and the production delivery
   event is a one-shot with no iteration path:
   - Start a throwaway container named `zot` locally with `--log-driver journald`, emit
     zot-shaped lines, and assert `journalctl CONTAINER_NAME=zot` matches. This is the only check
     that proves the field Docker writes equals the field the shipper matches.
   - Assert cursor persistence and resume across a **SIGKILL**, not only a clean stop.
   - Point the shipper at a mock ingest endpoint; assert envelope framing is accepted, a non-2xx
     breadcrumbs, and a hung endpoint does not wedge the shipper.
   - `systemd-analyze verify` the unit — syntax errors are otherwise found at boot, on the sole pull
     path.
   - Skip with a **stated reason** where Docker or journald is unavailable in CI, never vacuously.

### Phase 2 — GREEN: the shipper

2.1 Add the `zot-log-shipper` block to `cloud-init-registry.yml` implementing the
   `## Observability` contract: `journalctl CONTAINER_NAME=zot --output=json` with self-persisted
   `__CURSOR` + `--after-cursor`; wholesale admission (no selectivity filter) bounded by the
   5,000/day cap with the four cap-exempt evidence classes; the `tr` sanitizer plus one
   `authorization:` backstop anchored on the Phase 0.3 shape; per-line envelope-stamped POST
   mirroring the reporter's `post || post || breadcrumb`; `flock -n` singleton; the one-shot boot
   marker from `runcmd`; and the Phase 0.4 unit hardening in full. Set the journald size caps
   unconditionally.

2.2 Fix the stale `zot_last_err` rationale comment that says the liveness probe runs "every 5 min"
   (the timer says 60 s) — the plan's row-volume floor depends on the correct figure.

2.3 Re-run the userdata budget gate; record the delta against the 0.1 baseline, reading **stdout**.

### Phase 3 — The verification gate

3.1 Write `scripts/followthroughs/zot-log-channel-7440.sh`: a **≥30-minute** window (comfortably
   above the measured 17 s POST→queryable latency and holding ≥3 control rows at the 5-minute
   cadence); control-vs-envelope adjudication per the state table in 1.2; a **positive**,
   host-isolated envelope assertion plus a zot-only string within it; the four evidence-class counts
   printed (`gc_start`, `gc_done`, `gc_blobs`, `patch_upload`) so the gc start/complete **ratio** is
   readable as the candidate-(a) discriminator; and the credential-shape exit-1 arm. Print every
   count it decided on so the verdict is auditable.

3.2 **File the dedicated tracker**, apply the `follow-through` label, and add the directive with its
   escalation horizon and the expected-comment-noise note.

### Phase 4 — Decision records and downstream writes

4.1 Author `ADR-184` (`status: adopting`) with the corrected §2 reason, the first-`Restart=always`
   note, the containment rationale, and the ADR-172 §8 amendment. Include the retraction of the
   pepper argument explicitly.
4.2 Edit `model.c4`: add `zotRegistry -> betterstack`. Run `c4-code-syntax.test.ts` +
   `c4-render.test.ts`.
4.3 **Write into the downstream.** Comment on #7341 recording that the recut reset the store, that
   its attribution criterion as written is no longer satisfiable, and that the forward-looking
   criterion is the gc start/complete ratio plus `PatchBlobUpload` counts this channel makes
   readable. File a follow-up to build that discriminator once the channel is live.
4.4 **Record the rider** on #7287's ordered path: a pending cloud-init change wants its step-6
   replace. Without this the window can close unnoticed and the next event is unscheduled.
4.5 Edit `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` — the reader's
   actual entry point — documenting the envelope discriminator, the four evidence classes, the gc
   ratio, and **explicitly that the channel is live only after delivery**, so nobody follows it into
   a dark channel mid-incident.
4.6 File the deferred-scope-out issue for registry root-filesystem encryption.

**Phase 5 was cut.** Its runbook audit had a false premise: both registry runbooks already declare
no-SSH (`registry-luks-recut-6929.md`: *"There is no SSH in this runbook."*;
`zot-registry-revert.md`: *"All signals are Sentry/Better Stack events (no SSH…)"*), so the audit
would have found nothing to replace while pointing readers at a channel that is dark until delivery.
The genuine gap was one level up and is now Phase 4.5. The `hr-no-ssh-fallback-in-runbooks` framing
in the issue is satisfied: the runbooks were already SSH-free; what was missing was a queryable
channel and a documented query path.

### Phase 6 — Exit gate

`bash scripts/test-all.sh`.

## Acceptance Criteria

### Pre-merge (PR)

1. **The shipper suite actually ran, not merely that the runner was green.** `bash scripts/test-all.sh`
   gates its nested infra runner on the diff and on `TEST_GROUP`/`SOLEUR_INCIDENT_SKIP`, printing
   `SKIPPED (…)` as a **NOTE** while the run stays green — so a green `test-all.sh` is not evidence
   the suite executed. Therefore assert **both**: (a) `bash scripts/test-all.sh` green, and (b)
   `bash apps/web-platform/infra/run-registered-suites.sh` output contains
   `^PASS apps/web-platform/infra/zot-log-shipper.test.sh` and **zero** `^RED ` lines. Note the
   taxonomy: a failing infra suite prints `RED <path>`, not `FAIL`.
2. **The suite is registered where the runner actually looks:** a
   `run: bash apps/web-platform/infra/zot-log-shipper.test.sh` step exists in
   `.github/workflows/infra-validation.yml`, from which `run-registered-suites.sh` derives its list.
   Assert the derived list contains the suite — registration in `scripts/test-all.sh` alone would be
   an orphan.
3. The shipper test extracts the block, **applies the rationale strip**, asserts `bash -n` on the
   result, and runs its assertions against the stripped program.
4. **Field-match lockstep is a VALUE COMPARISON, not two existence checks.** Two independent greps
   cannot detect a mismatch, and both naive forms mis-fire: `grep -c 'CONTAINER_NAME=zot' >= 1` is
   satisfied by the rationale comment this plan mandates, and — the sharper trap —
   `grep -- '--name zot'` **matches `--name zot-log-shipper`**, a name this plan itself introduces.
   Extract both values and compare them:

   ```bash
   match=$(grep -oE 'CONTAINER_NAME=[A-Za-z0-9_.-]+' "$SHIPPER_BLOCK" | head -1 | cut -d= -f2)
   name=$(grep -oE -- '--name[[:space:]]+[A-Za-z0-9_.-]+' "$CI" | awk '{print $2}' | grep -x zot)
   [[ -n "$match" && "$match" == "$name" ]] || fail "journald match '$match' != docker --name '$name'"
   ```
5. Feedback-loop guard and `flock -n` singleton both asserted.
6. Unit hardening asserted in full: `MemoryMax=`, `CPUQuota=`, `IOWeight=`, `RestartSec=`,
   start-limit policy, explicit `HOME=`, and `DOPPLER_CONFIG_DIR` with no `/tmp` component.
7. Journald `Storage=persistent`, `SystemMaxUse=` and `RuntimeMaxUse=` literals present, set
   **unconditionally** so they are assertable.
8. Sanitizer and redaction asserted **separately**, with the `authorization:` backstop anchored on
   the **raw quoted** shape measured in Phase 0.3, plus a negative control.
9. Envelope schema asserted from **both** the shipper test and the probe fixture, including the
   in-message `host=soleur-registry` token (there is no `host_name` field on this channel).
10. Rate cap: `SOLEUR_ZOT_LOG_DROPPED` carries `n`, `interval_s`, `boot_id`, `seq`, `cum`, with `n`
    scoped to the interval the row closes; **and** the four cap-exempt evidence classes survive a
    flood that drops ordinary rows.
11. Cursor: `__CURSOR` persisted after each successful POST with an atomic write, resume verified
    across **SIGKILL** (not only a clean stop), `--no-tail` on cold start, and
    `reason=cursor_invalidated` on an unusable cursor.
12. **Userdata budget asserted on the JSON, not on a phrase the script never prints.** The script
    emits no `UNDER CAP` token: in `--json` mode stdout is only the object, and the over-cap verdict
    goes to **stderr** with exit 1. Use:

    ```bash
    out=$(bash apps/web-platform/infra/registry-userdata-budget.sh --json) \
      && jq -e '.stored_bytes < .cap and .headroom > 0' <<<"$out" >/dev/null \
      || fail "budget gate: $out"
    ```

    This also fails closed on the `SKIP` path, which produces no JSON. Record the `stored_bytes`
    figure. (Note the fail-open is **local-only**: in CI the script exits 2, fail-closed by design.)
13. The probe fixture suite passes all nine cases in 1.2, **including** the false-green fixture and
    the PASS-arm reachability fixture.
14. `zot-log-channel-7440.sh` contains **exactly one** executable `exit 1` — the credential-shape arm.
    Assert on an executable anchor, because prose legitimately contains the literal string:
    `[[ $(grep -cE '^[[:space:]]*exit[[:space:]]+1[[:space:]]*$' <script>) -eq 1 ]]`.
15. The probe is committed **`100755`** (`scripts/followthrough-exec-bit.test.sh` asserts the **index**
    mode via `git ls-files -s`, not `test -x`; a committed `100644` reds CI and the sweeper rejects it
    before exec), and uses `if [[ -z "${VAR:-}" ]]` guards rather than `${VAR:?msg}`, which
    `scripts/lint-followthrough-varq-ban.sh` hard-fails. Any non-zero exit from
    `betterstack-query.sh` maps to probe exit 2 (it exits **3** on unset credentials and **64** on an
    unknown flag).
16. **The follow-through tracker is a dedicated issue and is NOT the issue named in `Closes`.**
    Assert the directive's host issue ≠ 7440. The three `BETTERSTACK_QUERY_*` names already exist in
    `scheduled-followthrough-sweeper.yml`; assert their presence and add no workflow edit.
17. The directive carries the 90-day escalation horizon and the expected-comment-noise note.
18. `ADR-184` exists (`status: adopting`) with the corrected reason, the explicit retraction of the
    pepper argument, and the ADR-172 §8 amendment. **Ordinal re-derived across all refs and the
    reachable object graph immediately before merge** — 177 is doubly claimed and 178 is taken, and
    `scripts/check-adr-ordinals.sh` has no remote-ref logic, so the plan supplies the command. On
    collision the renumber sweeps `knowledge-base/project/{plans,specs}/`.
19. **`model.c4`'s existing `zotRegistry -> betterstack` edge is AMENDED, asserted on content rather
    than existence** — an existence assertion passes on `main` today, unmodified. Assert that the
    edge's description names the container-log channel **and** no longer asserts the unfired-recut
    blocker, and that exactly **one** `zotRegistry -> betterstack` line exists (no duplicate).
    `c4-code-syntax.test.ts` and `c4-render.test.ts` pass.
20. `betterstack-log-query.md` documents the envelope discriminator, the encoding-safe grep token,
    the four evidence classes, the gc ratio, and that the channel is live only after delivery.
21. #7341 carries the reframing comment; #7287 carries the rider note; the encryption
    deferred-scope-out issue and the downstream-discriminator follow-up both exist.
22. **Every cited path resolves, across all three citation forms** — the prefix-anchored regex alone
    certifies a set it cannot see. Run: (a) `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md'`;
    (b) a pass over bare learning filenames (`2026-[0-9-]+.*\.md`) resolved against
    `knowledge-base/project/learnings/`, since those are cited without the prefix; (c) globbed
    citations such as `ADR-172-*.md`, which the `*`-free character class silently skips.
23. Integration rehearsal (1.3) passes or skips with a stated reason — never vacuously.
24. PR body describes the downstream unblock as **date-anchored prose** with **no** sibling issue
    numbers imported as refs. Uses `Closes #7440`.

### Post-delivery (carried by #7287's step-6 replace — no new operator step)

25. `bash scripts/followthroughs/zot-log-channel-7440.sh` exits **0** with non-zero `envelope=` and
    `control=` counts. Before delivery it exits **2** with a discriminated reason; a
    `delivered_but_silent` reason, or any undelivered state persisting past the 90-day horizon, is
    an escalation rather than a steady state.
26. Re-running the falsification table returns a **non-zero genuine count** — asserted via the
    positive envelope plus the encoding-safe `zotregistry.dev/zot/v2/pkg/api` token, not the generic
    tokens that measured 0 on 2026-08-11.
27. Measured row volume is compared against the 5,000/day cap and the ~1,440/day floor. **Retuning
    the cap requires another cloud-init edit and therefore another provisioning event**, so the
    follow-up filed in 4.3 owns any retune rather than this AC implying a free adjustment.
28. ADR-184 flips `adopting → accepted` on the probe's first PASS.

## Alternative Approaches Considered

| Alternative | Verdict | Reason |
|---|---|---|
| **Install a Vector agent** (the issue's literal framing) | **Rejected** | `vector.toml:298` drops any top-level `message` key as an Art-9 user-content key, and zerolog's log text *is* a top-level `message` — a Vector-shipped zot line arrives with its message deleted. Supporting: `host_metrics` ~19.9k rows/day against a 25k/day threshold; a boot-time binary download on the sole pull path; a second config in lockstep; `user_data` budget. **The pepper/isolation-guard argument an earlier draft gave is retracted as false — Vector needs no fifth secret and its degraded arm still runs the full string scrub.** |
| **A trimmed registry-specific Vector config** | **Rejected** | Dodges the `message` deletion but keeps the boot-time download on the sole pull path and adds a second config to hold in lockstep with the shared one |
| **Widen the reporter's `zot_last_err` field** | **Rejected** | Stays a 5-minute sampler — the defect itself. A wider field raises the lower bound without producing a count, and stresses the `zot_last_err`-tail parse contract in `scripts/lib/zot-telemetry-parse.sh` |
| **Ship from CI, extending ADR-172's inventory lever** | **Rejected** | CI reaches only the read-only `/v2/` surface; container logs are unreachable from a runner |
| **Grant `delete` / edit `/etc/zot/config.json`** | **Rejected, out of scope** | The write-surface deadlock ADR-172 §3 declines to pretend around |
| **A timer-driven shipper with `journalctl --since <window>`** | **Rejected, but its rejection was corrected** | Boundary arithmetic double-ships or gaps. Note the original rejection cited `--cursor-file` continuity, which was **measured false under SIGKILL** — the actual resolution is self-persisted `__CURSOR` + `--after-cursor`, not the `--cursor-file` idiom, whose man page documents this very timer pattern |
| **A selectivity filter admitting named log classes** | **Rejected** | Duplicates the rate cap, suppresses the free 60s positive control, requires lockstep with zot's log vocabulary across version bumps, and creates a "filter admits nothing" mode needing its own detector. Wholesale admission + a class-prioritised cap is strictly simpler and admits `executing gc` — the denominator candidate (a) needs |
| **A dedicated `SOLEUR_ZOT_LOG_CANARY`** | **Rejected** | The 60s `/v2/` liveness GET already guarantees a genuine zot line every minute, traversing the whole path; a shipper-emitted canary skips journald ingestion and the field match — the two actual failure modes — so it would certify something other than what it claims |
| **Batched JSON-array POSTs** | **Rejected** | Adds flush-trigger ambiguity, partial-batch loss across restarts, an unbounded in-memory buffer under a sink outage, and a second JSON-escaping surface. The rate cap already bounds volume, and per-line POST is the proven transport |
| **Negative discriminator ("`raw` does not begin with the heartbeat prefix")** | **Rejected** | Fail-open: under any `raw`-encoding drift every echo row reclassifies as genuine and the probe auto-PASSes on the exact state it exists to reject. Its precedent uses the same literal *positively*, which fails visibly instead |
| **`create_before_destroy` on `hcloud_server.registry`** | **Rejected** | A Hetzner volume attaches to one server at a time, so two registry servers cannot coexist holding the same store; and it is a `.tf` change with no scoped apply path |
| **Rehearse on a throwaway Hetzner host** | **Rejected** | Documented stock volatility (`cx23` in `hel1` flipped availability twice in twelve days) adds a scheduling dependency without coverage the local rehearsal lacks |
| **Assert liveness in a pre-merge AC** | **Rejected** | Structurally impossible; any pre-merge "logs are queryable" claim is an inert-until-dispatched false green |
| **Request a host replace in this PR** | **Rejected** | A destructive replace of the sole pull path is separately authorized, and #7287 owns the ordered path. This change rides its step 6 |
| **Enroll the probe on #7440** | **Rejected — it would have been a silent no-op** | The sweeper lists `--state open`; on a closed issue `rc=0` and `rc=2` both take "no action, no comment", and `CLOSED_LOOKBACK_DAYS=14` drops it entirely after two weeks. Even a real PASS would leave nothing to flip ADR-184 |

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** Infrastructure and observability change on the highest-criticality host in the
estate. The architectural weight sits in four places, three of which only became visible under
adversarial review: the payload-destruction property that actually disqualifies the shared Vector
config; the log-shape correction, without which both the redaction and the discriminator would have
shipped inert; the enrollment-target rule, without which the verification would never have reported;
and resource governance as the sole containment available on a host with no kill switch. The
zero-Terraform property is a deliberate risk reduction that keeps the change clear of the
untargeted-apply hazard. Residual risks are volume control and sanitizer correctness, both pushed
into pre-merge fixtures because neither is observable post-merge until a provisioning event.

### Product/UX Gate

Not applicable. `## Files to Create` and `## Files to Edit` contain no path matching the UI-surface
term list or glob superset — no `components/**/*.tsx`, no `app/**/page.tsx`, no `app/**/layout.tsx`.
The mechanical override does not fire and the semantic sweep agrees. Product tier: **NONE**.

## Files to Create

| Path | Purpose |
|---|---|
| `apps/web-platform/infra/zot-log-shipper.test.sh` | Shipper invariants: post-strip execution, field-match lockstep, feedback-loop guard, singleton, unit hardening, journald caps, sanitizer vs redaction, envelope schema, rate cap + class exemption, cursor durability |
| `scripts/followthroughs/zot-log-channel-7440.sh` | The readback verification gate |
| `tests/scripts/test-zot-log-channel-probe.sh` | Probe fixture suite, including the false-green and PASS-reachability fixtures |
| `knowledge-base/engineering/architecture/decisions/ADR-184-registry-host-container-log-shipper.md` | Decision + ADR-172 §8 amendment (ordinal provisional — 178 is taken) |
| A **dedicated follow-through tracker issue** | Hosts the probe directive; must NOT be #7440 |

## Files to Edit

| Path | Change |
|---|---|
| `apps/web-platform/infra/cloud-init-registry.yml` | The `zot-log-shipper` block; `Storage=persistent` + `SystemMaxUse=` + `RuntimeMaxUse=`; the boot marker; the reporter's `log_shipper_post_fail` / `log_shipper_last_ok_age_s` fields; fix the stale "every 5 min" liveness comment |
| **`.github/workflows/infra-validation.yml`** | **Register `run: bash apps/web-platform/infra/zot-log-shipper.test.sh`.** This is the real registration point for an infra suite and an earlier draft omitted it entirely — see the note below |
| `scripts/test-all.sh` | Add the explicit `run_suite` line for `tests/scripts/test-zot-log-channel-probe.sh` **only** |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | **Amend** the existing `zotRegistry -> betterstack` edge at line 562 (add the container-log channel; retire the unfired-recut blocker clause; fix the "isolated source" contradiction) — do **not** add a second edge |
| `knowledge-base/engineering/architecture/decisions/ADR-172-ci-side-observability-emission-and-read-only-registry-inventory.md` | Amend §8 — the no-safe-provisioning-event premise no longer holds |
| `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` | Document the envelope discriminator, the encoding-safe grep token, evidence classes, gc ratio, and post-delivery-only liveness |

**The registration point is not `scripts/test-all.sh`, and getting this wrong ships a silent orphan
suite.** `test-all.sh` does not register `apps/web-platform/infra/*.test.sh` at all; it registers
`apps/web-platform/infra/run-registered-suites.sh` as a **nested** suite, and that runner **derives
its list from `.github/workflows/infra-validation.yml`** via
`grep -oE "run: bash <dir>/[A-Za-z0-9._-]+\.test\.sh"` — deliberately, so the runner and CI cannot
fork. There are 100 such steps today. A suite added only to `test-all.sh` would run in **zero**
runners: the #3366 orphan-suite class, silent and green.

**Deliberately NOT edited:** `.github/workflows/scheduled-followthrough-sweeper.yml` (all three
`BETTERSTACK_QUERY_*` names already present at lines 72–74 — verified, so the edit is a no-op),
`zot-registry.tf` (no Terraform change), `ADR-096` (restated in one ADR-184 sentence rather than
separately amended).

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The change never becomes live** | The probe on a dedicated tracker reports a discriminated reason every sweep, with a 90-day escalation horizon; the rider is recorded on #7287's ordered path so the window is not missed |
| **Resource exhaustion on the sole pull path** | Hard `MemoryMax`/`CPUQuota`/`IOWeight` caps — the only containment available with no in-place execution path — plus the reserve/cap interaction reviewed against #6288's OOM precedent |
| **Start-limit latch leaves the shipper permanently dead** | Explicit `RestartSec=`/start-limit policy; `delivered_but_silent` is a distinct probe state so this is detected rather than read as "not provisioned" |
| **Sanitizer anchored on the wrong shape ships a credential** | Phase 0.3 measures the raw shape first; one backstop rule plus a negative control; a post-delivery credential-shape query with its own exit-1 arm |
| **Silent gap under cursor loss or invalidation** | Self-persisted `__CURSOR` (SIGKILL-durable), `--after-cursor` resume, and an explicit `reason=cursor_invalidated` drop row |
| **Evidence dropped during the flood that matters most** | The four measured evidence classes are cap-exempt |
| **Quota pressure on a shared source** | 5,000/day cap against a measured floor of ~1,728/day; Phase 0.8 measures current utilisation before the cap is fixed |
| **Test/production drift via the comment strip** | The test applies the strip before executing and asserts the result is valid bash |
| **Feedback loop / double-run** | Structurally impossible via the `CONTAINER_NAME` match; `flock -n` singleton; both asserted |
| **`random_password.registry_luks` added to `replace_triggered_by`** | Documented footgun; this plan does not touch `zot-registry.tf`, so it is recorded here rather than as an AC on an unedited file |
| **The probe is inert-until-dispatched** | Multi-agent review of the probe **as an executing program** before merge, per the 2026-07-17 learning. Named false-green classes: does the pipe suppress an error; does the gate abort; is PASS reachable; is the discriminator fail-open |
| **H0 regresses between plan and implementation** | Phase 0.1 re-probes and stops rather than proceeding into an unsafe event |

## Sharp Edges

- **The heartbeat's `zot_last_err` is quote-stripped (`tr -d '"\\'`).** Any log shape read from it is
  the sampler's rendering, not zot's. zot emits quoted zerolog JSON. Deriving a regex or a query
  discriminator from the stripped form produces a mechanism that matches only the echo.
- **A discriminator built as a negation of a known prefix is fail-open.** The same literal used
  positively fails visibly under encoding drift; used negatively it reclassifies every echo as
  genuine and auto-PASSes.
- **A follow-through directive on the issue the PR closes is a permanent silent no-op.** The sweeper
  lists `--state open`; on a closed issue neither `rc=0` nor `rc=2` produces any artifact, and a
  14-day lookback then drops it entirely.
- **`--cursor-file` does not survive SIGKILL** (measured, systemd 259), and `--follow` then implies
  `--lines=10` — a boundary gap plus a replay. Persist `__CURSOR` from `--output=json` instead.
- **Bare `Restart=always` inherits a 100 ms/5-in-10 s start limit**, so a unit that fails fast at
  boot latches `failed` until the next boot — on a host with no in-place execution path.
- **`local.registry_rationale_strip` is a blanket whole-line comment strip that reaches inside
  heredocs.** A `#`-leading line in an embedded awk/sed/jq program is deleted from production while
  surviving in the file the test reads. A comment written `#like-this` (no space) is *not* stripped
  and does cost bytes.
- **`DOPPLER_CONFIG_DIR=/tmp/.doppler` plus `PrivateTmp=`** is a measured defect class on this
  estate; a unit must own its config dir outside `/tmp` and set `HOME` explicitly.
- **`registry-userdata-budget.sh` prints `SKIP` and exits 0 when `terraform` is absent.** Reading
  `$?` reports "under cap" for a measurement that never ran.
- **The ADR ordinal is a claim, not a reservation.** ADR-177 is claimed on a pushed branch invisible
  to `origin/main`. Quantify over all `origin/*` refs and re-probe before merge.
- **A case-sensitive character class turned an existing C4 edge into a phantom absence.** The probe
  `grep -nE '^\s*[a-z_.]*registry[a-z_.]* +->'` cannot match the camelCase element `zotRegistry`, so
  it returned zero and the zero was read as "the edge does not exist" — while
  `zotRegistry -> betterstack` sits at `model.c4:562`. When a grep's result will be read as an
  **absence**, make the pattern case-insensitive (`-i`) or match on the bare noun, and confirm the
  same pattern finds a known-present sibling before trusting the zero.
- **ClickHouse stores `raw` double-encoded, so a grep containing a quote or a colon-joined field name
  matches nothing, ever.** Real zot JSON is `"caller":"zotregistry.dev/…"`; the stored bytes are
  `\"caller\":\"zotregistry.dev`. Grep an encoding-safe substring
  (`zotregistry.dev/zot/v2/pkg/api`), then decode and field-isolate.
- **An infra `*.test.sh` registered only in `scripts/test-all.sh` runs in zero runners.**
  `test-all.sh` registers `run-registered-suites.sh` as a nested suite, and that runner derives its
  list from `.github/workflows/infra-validation.yml`. The registration point is the workflow.
- **A green `test-all.sh` is not evidence an infra suite ran** — the nested runner is diff-gated and
  prints `SKIPPED` as a NOTE while the run stays green. Also note the taxonomy: a failing infra suite
  prints `RED <path>`, not `FAIL`.
- **`grep -- '--name zot'` matches `--name zot-log-shipper`.** Anchor on `--name zot[[:space:]]` or
  compare extracted values; two existence checks are a union, not a lockstep.
- **`registry-userdata-budget.sh` never prints `UNDER CAP`.** In `--json` mode stdout is only the
  object; the over-cap verdict is on stderr with exit 1. Assert with `jq -e` on the JSON. Its
  `SKIP`-and-exit-0 fail-open is **local-only** — in CI it exits 2, fail-closed.
- **`--no-archive` opts DOWN to the ~40-minute hot window**; the default queries hot + S3 archive.
  It is easy to state backwards.
- **A follow-through probe must be committed `100755`** — the guard asserts the git **index** mode,
  not `test -x` — and must avoid `${VAR:?msg}`, which a dedicated linter hard-fails.
- **A counter surfaced on the channel it monitors is unobservable exactly when it is non-zero.**
  Route `post_fail` through an independent working path (here, the 5-min reporter).
- **A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan`
  Phase 4.6.** This plan's threshold is `single-user incident`, which escalates plan-review and
  invokes `user-impact-reviewer`.


---

## Addendum — 2026-08-12 (#7444 review round 2)

**Ordinal.** This plan drafted the ADR as `ADR-179`. That ordinal is taken on `origin/main` by
`ADR-179-bare-plugin-root-anchor-for-customer-facing-executables`, and the shipped decision is
**ADR-184**. Every reference in the body above has been swept to 182, including a deliverables row
that named `ADR-179-registry-host-container-log-shipper.md` — a file that has never existed and
would have resolved to an unrelated ADR.

**The mechanism changed after this plan was written.** A binding CTO ruling replaced the
`Restart=always` systemd daemon with a 5-minute `/etc/cron.d` one-shot. Where the body above
describes a unit, `MemoryMax`/`CPUQuota`/`IOWeight` caps, `StartLimitIntervalSec`, or "three
permanently-resident processes", read ADR-184 §4 instead — those are the artefacts of a shape that
was not shipped, and the containment the `## User-Brand Impact` section leans on was deleted with
the unit. The replacement containment is a bounded tick: `timeout 240` inside `flock -n`, on a
cron slot chosen for forward clearance.

**`error_reporting.fail_loud` is superseded.** It describes "retries once then breadcrumbs to
journald, mirroring the reporter's `post || post || echo`". The shipper POSTs **once** and breaks
at the first undelivered row; every shipper row is replayable from the cursor, so an immediate
second attempt buys nothing the five-minute gap does not. The breadcrumb reaches journald via
`logger -t` on the cron line, not via cron itself.

**`failure_modes` → "Delivered and dead" is superseded.** Its detection still reads `boot_id`
drift. Delivery is gated on the presence of the `log_shipper_post_fail=` key; drift is not
evidence on a host whose NIC guard reboots it as a convergence primitive (#7444 F-7).
