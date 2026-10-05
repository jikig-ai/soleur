---
title: "Make the dedicated inngest host self-annunciating and its re-cutover safe"
date: 2026-08-11
slug: fix-inngest-dedicated-host-bind-failure
branch: feat-one-shot-7228-inngest-host-dark-bind-failure
lane: cross-domain
type: fix
issue: 7228
# Corrected at ship time: this plan is a necessary part of all three and the whole of
# none — #7228 needs the #7462 host restore before it can close. `closes:` over-claimed.
refs: [7228, 6617, 7308]
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

The dedicated inngest host (`soleur-inngest`, 10.0.1.40) boots and runs but never binds :8288, so
the web-platform container's dispatches fail with `connect ECONNREFUSED`. Twelve days passed
without anyone noticing.

Two framings were tried and both were refuted by measurement. They are recorded because the
refutations are the plan's foundation.

**Refuted #1 — "the host has no error channel."** It has an excellent one: eight staged
`SOLEUR_INNGEST_BOOT_STAGE` markers ending in `post-boot-health` and `net-health`, the latter
carrying `bind=`, `priv8288=` and `nft=` — this entire diagnosis in one row. It almost certainly
fired on 2026-07-30 and its evidence **expired**: sink retention is ~3 days against a 12-day-old
boot, and nothing alerts on a failure marker.

**Refuted #2 — "one monitor with two pushers, masked by the co-located host."** There is exactly
one `betteruptime_heartbeat` (`inngest.tf:302`), the dedicated host's dark-arm skip already ships
(`inngest-bootstrap.sh:277`, `#6617b`), and `inngest-host.tf:170` states it outright: *"The monitor
stayed green throughout only because the co-located host is the sole pusher."* The `paused = true`
alternative was checked too and also fails — `heartbeat-manifest.ts` records the live monitor,
self-pulled from `/api/v2/heartbeats`, as unpaused and up.

**The actual mechanism: no monitor anywhere asserts that :8288 is bound.** The pusher is
`exec curl -gfsS "$INNGEST_HEARTBEAT_URL"` — it proves a systemd timer fired, on either host. One
correctly-armed, correctly-scoped monitor stayed green for twelve days because it measures the
wrong thing. Splitting it would mint a second meaningless green.

The root cause of the bind failure is **UNKNOWN and is not guessed at here** — the deciding datum
was destroyed by retention. The plan's spine is therefore a **diagnostic boot**: a guard-permitted
boot against a non-prod backend, where `is_prod=false` takes the flip guard's ALLOW arm so the host
can actually attempt a bind and emit a discriminating `net-health` row, with zero double-scheduler
risk. That converts every UNKNOWN in `## Hypotheses` into a measurement, and it is what makes "fix
it properly" reachable rather than aspirational.

Alongside it, detection ships that does **not** depend on the broken host: a consumer-side probe on
the web host wrapping `inngest-registry-probe.sh`, which has been returning the exact diagnosis for
twelve days with nothing watching it. It needs no host replace, so it works the day it merges.

**Operator decisions, 2026-08-11.** The twelve days of failed dispatches are **accepted as lost** —
no replay or backfill path is in scope. `INNGEST_BASE_URL` is **not** repointed as an interim
restore; the dedicated host is fixed properly instead, accepting a few more hours against the twelve
days already elapsed.

## Research Insights

### Premise Validation (Phase 0.6)

Every premise carried in from the invocation was probed before research was dispatched. Most held;
two did not, and one of those changes the plan's shape.

| Premise as given | Probe | Verdict |
|---|---|---|
| #7228 / #6617 / #7308 open, not already closed | `gh issue view` ×3 — all `OPEN`, `closedByPullRequestsReferences` empty | HOLDS |
| PR #7301 merged 2026-08-06 | `gh pr view 7301` → `MERGED`, `mergedAt 2026-08-06T07:38:04Z` | HOLDS |
| ADR-100 is the cutover | `ADR-100-inngest-dedicated-single-host-singleton-control-plane.md`, `status: adopting` | HOLDS |
| **ADR-167 documents the rollback and needs superseding** | Not on `main`. Ordinals 164-166 and 168-176 exist; 167 is absent. Zero references repo-wide | **STALE — see below** |
| `inngest-boot-phone-home.sh` exists as an embedded `write_files` entry | `cloud-init-inngest.yml` `- path: /usr/local/bin/inngest-boot-phone-home.sh` | HOLDS |
| `inngest-server.service` already in the vector allowlist | `vector.toml` `[sources.inngest_journald]`, `include_units = ["inngest-server.service"]` | HOLDS |
| doppler `ln -sf` mitigation survives on main | `cloud-init-inngest.yml` `ln -sf /usr/local/bin/doppler /usr/bin/doppler` | HOLDS (present in source) |
| `inngest.tf` pins `v1.19.4`; upstream is `v1.41.1` | `inngest.tf` `inngest_cli_version = "v1.19.4"`; `gh api .../releases/latest` → `v1.41.1`, published 2026-08-05 | HOLDS |
| Dual-arch requires two checksums from one signed file | `releases/latest` assets include `checksums.txt` plus `linux_amd64` and `linux_arm64` tarballs | HOLDS — satisfiable from one file |
| Entropy stub is compressible | `registry-userdata-budget.sh` `doppler_token = join(".", …"STUBSTUB…")` | HOLDS — independently measured below |
| **Runner fail-open still live** | `run-registered-suites.sh` already carries the accounting gate | **ALREADY FIXED — no action** |

**ADR-167 is a contested, unmerged ordinal — there is nothing on `main` to supersede.** Two
different unmerged branches each claim it:

- `origin/feat-one-shot-resend-inbound-webhook-500` → `ADR-167-pause-adr-100-inngest-cutover-at-pre-repoint-operating-point.md` (the one the invocation means)
- `origin/feat-zot-primary-write-path` → `ADR-167-container-registry-write-path-stays-dual-push.md`

A `supersedes:` pointer at an ordinal that does not exist on `main` would dangle, and adopting 167
here would collide with a third claimant. The decision this plan records must therefore take the
next ordinal free across **all** `origin/*` refs (not just `main`), and state the reversal in prose
rather than through a `supersedes:` key aimed at an unmerged file. Re-derive the ordinal immediately
before merge — `main` moves under a long session, and this repo has seen the same ordinal claimed
twice inside one pipeline.

**Release-count discrepancy, unresolved:** the invocation says 27 releases behind, issue #7308's
title says 22. Neither was reproduced here (the repo carries 266 releases in total; the delta needs
a tag-ordered walk). The plan does not depend on the number — treat it as a claim to compute at
implementation time, not to restate.

### Measured live state (self-pulled 2026-08-11, `hr-no-dashboard-eyeball-pull-data-yourself`)

All of the following are first-hand measurements taken during planning, not inherited assertions.

**Fleet inventory** (`hcloud server list`):

| host | type | arch (derived) | created | private IP |
|---|---|---|---|---|
| `soleur-web-platform` | cx33 | amd64 | 2026-03-17 | 10.0.1.10 |
| `soleur-web-2` | cpx22 | amd64 | 2026-07-27 | 10.0.1.11 |
| `soleur-inngest` | cpx22 | **amd64** | **2026-07-30T15:13:06Z** | 10.0.1.40 |
| `soleur-registry` | cpx22 | amd64 | 2026-08-10 | 10.0.1.30 |

`soleur-inngest` is `running`. Its creation timestamp is the outage onset, as stated.
`local.inngest_arch = startswith(var.inngest_server_type, "cax") ? "arm64" : "amd64"` and
`var.inngest_server_type` defaults to `cpx22`, so **the live host is amd64** — the arm64 checksum is
currently the unused arm of the ternary. Note that `inngest-betterstack-token.tf`'s header prose
still describes "the dedicated **arm64** Inngest host (cax11, arm64, 10.0.1.40)"; that comment is
stale against the live type and should be corrected while in the file.

**The outage is live.** `ECONNREFUSED` against `10.0.1.40`: 3,334 rows in the last 6 hours, newest
`2026-08-11 11:04:59` — still firing at planning time.

**The Better Stack channel works, and its retention is the first half of the silence.** A control
query was run before drawing any conclusion from an empty result:

- Control: 394,282 rows in the last 72 h, oldest `2026-08-08 11:04:22`, newest `2026-08-11 11:04:17`. The pipeline and credentials are healthy.
- Archive depth: `min(dt) = 2026-08-08 10:44:08` across the whole `_s3` archive. **Retention is ~3 days.**
- The host booted **2026-07-30** — twelve days ago. **The first-boot trace is irrecoverable by construction.** No query can return it, so no amount of querying will diagnose the original boot.
- `SOLEUR_INNGEST_BOOT_STAGE` over 72 h: **zero rows** — a true measured absence, but only over a window that begins nine days after the boot in question.

**The dedicated host has never shipped a single row.** Grouping the last 24 h by `host`:

| host | rows |
|---|---|
| `soleur-web-platform` | 108,870 |
| *(empty)* | 23,611 |
| `soleur-inngest` | **0** |

And of the 1,839 rows in 72 h mentioning `soleur-inngest` or `inngest-server.service`, **1,459 carry
`host = soleur-web-platform`, `_SYSTEMD_UNIT = inngest-server.service`** — the co-located web-host
unit. Zero originate from the dedicated host. This matters beyond bookkeeping: a naive query for
"inngest-server logs" returns 1,459 healthy-looking rows **from the wrong host**, so the shared
source table actively manufactures a false all-clear. This is the same failure the #7228 title names
("health probe certified a different server"), reproduced one layer down in the telemetry.

**Live black-box read of the dedicated host, no SSH** (`/hooks/*`, HMAC + CF Access, from the web host):

- `/hooks/inngest-registry-probe` → **HTTP 500**: `FATAL /v0/gql functions query failed or non-array (errors=["__FETCH_FAILED__"]); is the dedicated inngest-server reachable at http://10.0.1.40:8288/v0/gql?` — independent confirmation, from inside the private network, that nothing serves :8288.
- `/hooks/inngest-liveness` → **HTTP 200** with a **full function registry** (`cron-daily-triage`, `cron-bug-fixer`, and dozens more).
- `/hooks/deploy-status` → `inngest_server = active`, `inngest_redis = active`, `vector = active`, `inngest_redis_dropin = 10-inngest-redis-doppler-token.conf`, `inngest_redis_result = Result=success NRestarts=0`, and an `inngest_journal_tail` showing live event processing at `2026-08-11T09:00:06` (`inngest/function.finished`).

Every one of those green fields describes **the web host**. `/hooks/*` is served by the deploy
webhook on the active web host, so `deploy-status` is structurally incapable of reporting on
10.0.1.40. PR #7301's redis drop-in fix is confirmed delivered — **to the web host**; whether it
reached the dedicated host is not observable through this surface.

**Split-brain, and it is the central finding.** The co-located web-host Inngest is alive, holds the
entire function registry, and is actively firing crons. The dedicated host serves nothing. The app
dispatches to the dedicated host. So internally-scheduled crons keep running (from the co-located
scheduler) while every app-originated event dispatch fails — which is exactly the #7228 symptom
(inbound-email dispatch dead) alongside a fleet that otherwise looks healthy.

**The flip guard is not the cause — refuted by running it against live values.** Rather than reason
about it, `inngest-server-flip-guard.sh` was executed with the real Doppler values through its own
documented fixture seams:

- `INNGEST_CUTOVER_FLIP = done`
- `INNGEST_POSTGRES_URI` contains the prod marker `pigsfuxruiopinouvjwy` → `is_prod = true` (URI never echoed; only the boolean)
- Guard verdict: **ALLOW**

The guard blocks only when a prod URI meets a flag outside `{armed, flipping, flushed, done}`. At
`done` it permits the start. **Scope limit, stated deliberately:** this refutes the guard as a cause
*now*; it says nothing about the flag's value at 15:13 on 2026-07-30, which is unrecoverable. The
honest disposition for boot-time causation remains UNKNOWN.

**Consequence nobody has stated: bringing the dedicated host up naively creates a double-scheduler.**
`INNGEST_CUTOVER_FLIP = done` with the prod Postgres URI armed means the flip guard will *not* stop a
second prod scheduler, while the co-located web-host scheduler is demonstrably still running the
registry. That is precisely the double-fire race ADR-100's P1-5 guard exists to prevent, and #6617's
"possible double-scheduler" title anticipates. Any fix that starts inngest on 10.0.1.40 without
atomically stopping the co-located one will double-fire every cron in the registry.

### Why the error channel is silent — two independent mechanisms, both evidenced

The invocation's strong lead (the staged Better Stack token as a single point of failure) is
directionally right, but the mechanism is sharper and worse than "the staging step failed".

1. **Retention (measured).** Archive floor is 2026-08-08; the boot was 2026-07-30. Even a perfectly
   working channel leaves nothing to read today. Any Phase-1 conclusion drawn from "the query is
   empty" is unfounded for the original boot.

2. **The token is staged on tmpfs, on first boot only (code-read, and the sharper defect).** Every
   write site of `/run/inngest-bs-logs-token` lives inside `runcmd:` — the `printf … > /run/…` line
   and the later doppler-fetch re-stage. `cloud-init` runs `runcmd` **only on first boot**, and
   `/run` is tmpfs, cleared on every reboot. No systemd unit re-stages it. The emitter opens with
   `[ -r "$tok_file" ] || exit 0`, and its `curl` is `>/dev/null 2>&1` under `set +e`. Therefore
   **after any reboot the entire boot-trace channel is permanently and silently dead** — it cannot
   fail loudly, by construction. A host that reboots once is dark forever with no signal that the
   channel died.

Together these explain twelve days of darkness without needing the staging step to have failed at
all. Hypothesis (e) from the invocation — "the marker never had a monitored allowlist path off-box" —
is separately refuted: the emitter POSTs directly to `https://s2457081.eu-fsn-3.betterstackdata.com/`,
the same source id that backs the default query table `t520508_soleur_inngest_vector_prd_3_logs`, so
markers would land in the table this plan queries.

### Entropy defect — independently re-measured, not inherited

Reproduced locally rather than carried over from the abandoned branch:

| stub | raw | `gzip -9` | ratio |
|---|---|---|---|
| main's `STUBSTUB…` (`registry-userdata-budget.sh`) | 43 | 27 | **0.62** |
| real high-entropy 43-char token | 39 | 59 | 1.51 |

The proposed `>= 0.75 × raw` bound correctly **rejects** main's stub and accepts real entropy. The
reference assertion on `origin/feat-one-shot-resend-inbound-webhook-500` uses a `tok_gz()` helper
over the extracted token body; main's test file has diverged (it is organised around
`registry_rationale_strip`) and carries **no** incompressibility assertion, so the assertion — not
the file — is what ports.

### Applicable institutional learnings

- `2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md` (#6536) — the governing methodology here. A plan refuted a hypothesis by reasoning while writing that the deciding datum was discarded; the refuted hypothesis was the real cause. Its three tells are applied directly above: no verdict where the discriminator is invisible (boot-time causation stays UNKNOWN); a probe that ran elsewhere proves capability, not actuality (hence the guard was run against *live* values, and its verdict scoped to *now*); enumerate every writer before concluding two actors cannot interact (hence every write site of the token file was listed). Its concrete mechanism — a doppler unit failing on a root-owned `/tmp/.doppler` because it lacked the `PrivateTmp=true` its siblings had — is also the model for the unit-diff discipline below.
- `inngest-redis-credential-dropin-crashloop-postmortem.md` (PR #7301) — the closest prior art. Two compounding defects: a pinned credential with no re-delivery path, and a failing component that could not report. Its remedy was to add unit-state probe fields to `/hooks/deploy-status` so a crash-loop is decidable from one read. The same remedy is unavailable for 10.0.1.40 because that hook is web-host-only — which is exactly the gap this plan must close. Its methodological lesson: **a sweep that fixed a class missed a member, and nothing detected the miss.**
- `2026-07-08-inngest-cutover-authoring-review-and-observability-allowlist.md` — "rides the shipper" is a claim to verify against the Vector allowlist, never a fact. A `logger -t <tag>` with no matching `include_matches.SYSLOG_IDENTIFIER` entry never leaves the box.
- `2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md` — over a shared source, discriminate on the `SYSLOG_IDENTIFIER` field, never a bare payload substring. Directly relevant: the 1,459 web-host rows would contaminate any substring-matched assertion about the dedicated host.
- ADR-030 / ADR-100 — post-cutover Inngest cannot start without Supabase Postgres and Redis reachable; the in-memory fallback is gone. Both are therefore live bind-failure candidates that must be probed, not assumed.

### Load-bearing anchors

- `apps/web-platform/infra/cloud-init-inngest.yml` — phone-home emitter (`- path: /usr/local/bin/inngest-boot-phone-home.sh`), token staging inside `runcmd:`, doppler symlink (`ln -sf /usr/local/bin/doppler /usr/bin/doppler`), fail-closed isolation self-check, and the late `post-boot-health` / `net-health` markers carrying `lo8288=`, `priv8288=`, `bind=`, `nft=`.
- `apps/web-platform/infra/inngest-bootstrap.sh` — the unit writer: `ExecStart=/usr/bin/doppler run --config prd -- … inngest start --host 0.0.0.0 --port 8288 --sqlite-dir /var/lib/inngest …`, the `ExecStartPre` flip-guard line gated on the dedicated project, and the Redis-ready backend-flag substitution.
- `apps/web-platform/infra/inngest-server-flip-guard.sh` — `{armed, flipping, flushed, done}` allowlist; `GUARD_POSTGRES_URI` / `GUARD_FLIP_FLAG` fixture seams (used for the live refutation above).
- `apps/web-platform/infra/vector.toml` — `[sources.inngest_journald]`; the Source-4 exact-match `SYSLOG_IDENTIFIER` allowlist; the Better Stack sink URI and `BETTERSTACK_LOGS_TOKEN` auth.
- `apps/web-platform/infra/inngest.tf` — `inngest_cli_version`, `inngest_cli_sha256`, `inngest_cli_sha256_arm64`.
- `apps/web-platform/infra/inngest-host.tf` — `inngest_arch` derivation, the arch-selected checksum ternaries, `betterstack_logs_token` template var.
- `apps/web-platform/infra/hooks.json.tmpl` — `inngest-registry-probe` (the only hook that reaches 10.0.1.40), `inngest-liveness` and `deploy-status` (both loopback/web-host only).
- `apps/web-platform/infra/run-registered-suites.sh` — the accounting gate; already closed.
- `apps/web-platform/infra/registry-userdata-budget.sh` / `.test.sh` — the stub and the diverged test.

## Research Reconciliation — Spec vs. Codebase

| Claim as given | Reality | Plan response |
|---|---|---|
| "There is no `inngest-boot-phone-home.sh` on main" | Exists as a `write_files` entry in `cloud-init-inngest.yml`, 8 staged markers | Don't build a channel; make its evidence durable and its failure loud |
| "`inngest-server.service` journald is not in the vector allowlist" | Already Source 1 (`[sources.inngest_journald]`) | No allowlist change |
| "One monitor, two pushers" (inherited from a domain assessment) | **False.** One resource at `inngest.tf:302`; dedicated host dark-armed at `inngest-bootstrap.sh:277`; `inngest-host.tf:170` names the co-located host the sole pusher | Do **not** split. Gate the push on a listener instead |
| "The monitor may be paused" | **False.** `heartbeat-manifest.ts`: source `paused=true`, live `paused=false / up`, self-pulled | Rejected; arming is not the gap |
| "Ship the error channel before reproduction" | The channel shipped; its evidence expired | Reframed: durability, annunciation, and a boot that can actually be observed |
| "ADR-167 needs superseding" | Not on `main`; two unmerged branches claim it | Fold the rule into the ADR-100 amendment; mint no new ordinal |
| "Make the cutover atomic" | Structurally unavailable — disjoint control planes | Accept a **gap**; quiesce-web precedes arm |
| "Bump the CLI here" | One-way goose migrations on a Postgres the co-located v1.19.4 host shares | Deferred to its own window |
| Runner fail-open still live | Already closed on `main` | No action |
| "27 releases behind" / issue says 22 | Neither reproduced | Compute at bump time |
| A new health timer is needed | `inngest-server-probe.timer`/`.sh` already ships hourly with `http_code` on `127.0.0.1:8288/health`, `boot_id`, `image_ref`, and a Vector-independent fallback | Extend it by 4 fields; create no second timer |

## Hypotheses

Per `hr-ssh-diagnosis-verify-firewall`, L3→L7, unverified first. The 2026-07-30 trace is destroyed
by retention, so **no verdict is recorded where the discriminator is invisible**. Phase 2.1's
diagnostic boot is what makes every row below decidable — that is its purpose.

1. **L3 — firewall / nftables.** UNVERIFIED. `net-health` captures the `inet soleur_inngest input`
   chain; that row expired. Decided by the diagnostic boot.
2. **L3 — private-network routing / NIC.** UNVERIFIED. Partially constrained: the web host gets a
   TCP *refusal*, not a timeout, consistent with an intact route and nothing listening.
3. **L7 — TLS/proxy.** **Opt-out with artifact:** plain HTTP over the private network, no CDN, no
   proxy, no TLS in path.
4. **L7 — application.** UNVERIFIED. The host's journal is unreadable off-box
   (`hr-no-ssh-fallback-in-runbooks`) and Source 1 has shipped zero rows from it. Measured: 1,459
   of 1,839 rows naming `inngest-server.service` carry `host = soleur-web-platform`, so any
   assertion must field-isolate on `host`.
5. **Bootstrap never installed or enabled the unit.** UNVERIFIED, leading candidate given the
   creation timestamp is the outage onset. `bootstrap-exit-N` would decide it; expired.
6. **The FSM believed it was already finished.** MEASURED-PLAUSIBLE in source: `done` is set after
   a bare unit-start call that asserts no listener, and the flag lives in Doppler, which outlives
   the host. Explains why nothing self-healed; does **not** explain why the first start failed.
7. **Doppler `/usr/bin` symlink (status=203/EXEC).** Present in source. Source presence is not host
   presence — the image is the only delivery path — so it stays open until the diagnostic boot.

## Sequencing

Explicit because the review found Phase 1's delivery path unowned. Every step is either automated
or a numbered issue; none is an unowned operator step.

1. Merge → `apply-web-platform-infra.yml` applies the TF delta (consumer probe + its heartbeat).
   **Detection is live here, with no host replace.**
2. `apply_target=inngest-host-replace` — the only delivery path for cloud-init/bootstrap changes.
   Tracked by a numbered issue (AC9); preconditions asserted by Phase 3.1 landing first.
3. Diagnostic boot: the replaced host comes up on a non-prod backend, attempts a bind, and emits
   `net-health`. **This is the measurement that resolves `## Hypotheses`.**
4. Fix whatever the trace names. That fix is not pre-written here.
5. Cutover, in its own window: quiesce-web → confirm → arm → verify. Numbered issue.
6. CLI bump, in a separate window. Numbered issue.

## Implementation Phases

### Phase 1 — Detection that does not depend on the broken host

1.1 **Consumer-side probe.** Clone `web-zot-consumer-probe.{sh,timer}` (#6438) into
`inngest-consumer-probe.{sh,timer}` on the web host, wrapping the existing
`inngest-registry-probe.sh`. 200 + non-empty registry → ping a **new** heartbeat; every other
outcome suppresses so absence alarms. New `doppler_secret` resource for the URL — never a value
edit under `ignore_changes = [value]`. Arm on the `web-probe.tf:39-40` / ADR-117 pattern (PATCH
`paused=false` only after a real measured beat), never a UI step.

1.2 **Gate the existing dedicated pusher on a listener check.** ~5 lines inside the existing
`HEARTBEATSCRIPTEOF` heredoc: ping only on a local `/health` 200, using the classification
`web-zot-consumer-probe.sh` documents. Without this a green beat means "a timer fired". Its
disposition during the deferral window is stated explicitly: the dedicated host stays dark-armed
(no URL provisioned), so the beat is *absent*, not *falsely green*.

### Phase 2 — Make the host diagnosable and verifiable

2.1 **Diagnostic-boot path.** A non-prod `INNGEST_POSTGRES_URI` for the dedicated host so the flip
guard's prod detection yields `is_prod=false` and its ALLOW arm is taken while the FSM flag is
non-terminal. The host can then attempt a bind and emit `net-health` without any path to a second
prod scheduler. This is the plan's central mechanism.

2.2 **Extend the existing probe.** Add `instance_id`, `cli_version`, `cutover_flag` to
`inngest-server-probe.sh`. Keep its hourly cadence — the existing comment records why 60s was
rejected (~1,440 rows/day against a ~25k/day quota, the cost `#6617b` removed). No new timer, no
new `SYSLOG_IDENTIFIER`, no `vector.toml` quota decision. `journal_tail` stays on the boot marker
only, per `## User-Brand Impact`.

2.3 **Re-stage the sink token every boot.** Every write of `/run/inngest-bs-logs-token` is in
`runcmd:` (first boot only) and `/run` is tmpfs. A systemd oneshot re-fetches from Doppler each
boot — re-fetch, never a baked re-stamp. This is a precondition for 2.2 surviving a reboot, not an
independent fix.

2.4 **Make the emitter's failure loud.** `[ -r "$tok_file" ] || exit 0` with `curl >/dev/null 2>&1`
is the silent fallback `cq-silent-fallback-must-mirror-to-sentry` forbids. Both the missing-token
and failed-POST paths emit a `logger -t` line on an already-allowlisted identifier.

### Phase 3 — Make the re-cutover safe

3.1 **Monotonic latch on surviving storage.** The current slot is last-write-wins and `emit_state`
stamps it on every branch including terminal no-ops — so relocating it as-is would *persist an
erasure* and authorize a `FLUSHALL` against the preserved AOF volume. The latch becomes
append-only: "has `done` EVER been recorded". Paired, all three required:
`RequiresMountsFor=/mnt/data` on `inngest-cutover-flip.service`; the write becomes fatal rather
than `2>/dev/null || true`; and `cat-inngest-cutover-state.sh` is swept to the new path so the
no-SSH read surface does not report a false "no state".

3.2 **Correct the false durability claim.** `inngest-host.tf:229` asserts `DBSIZE==0` guards a
spurious re-flush; `run_preflush_flip` reads DBSIZE *after* the flush. Correct the comment. No new
pre-flush assertion — the monotonic latch is the guard, and a second guard on the same question is
how a `done`-shaped bug gets inside the guard.

3.3 **Probe-derived, instance-scoped `done`.** One change, not two: `done` is set only after a
bounded-window `/health` 200 **and** a non-empty registry from the `v0/gql` query
`inngest-registry-probe.sh` already sends; any failure ⇒ `aborted` plus a loud marker. The instance
stamp goes in a **separate** Doppler key, not appended to the flag value — so
`inngest-server-flip-guard.sh`'s exact `case` match on `done` is preserved and
`inngest-server-flip-guard.test.sh`'s `EXPECTED_START_SITES` derivation does not break. The guard
reads both keys and refuses a `done` whose instance stamp is foreign. Both files are in
`## Files to Edit` (`hr-type-widening-cross-consumer-grep`).

### Phase 4 — Record the decision

4.1 Amend **ADR-100** in place (its established idiom): correct Decision 6a, whose gate is
`exit_code:0` on the same unasserted unit-start the code performs; fold in the extracted rule — *a
terminal state asserting a live host condition must be re-derived from a probe and must not outlive
what it asserts*; add an addendum recording that the cutover did not hold and the soak never
started. Keep `status: adopting`; rewrite the blockquote implying a running soak. **No new ADR
ordinal** — the rule is a correction to this ADR, and 167/178 were both lost to contention already.

## Files to Edit

- `apps/web-platform/infra/inngest.tf` — new `doppler_secret` for the consumer-probe heartbeat URL
- `apps/web-platform/infra/inngest-host.tf` — correct the `DBSIZE` claim; correct stale arm64/cax11
  prose; diagnostic-backend variable
- `apps/web-platform/infra/server.tf` — install `inngest-consumer-probe.timer` on the web host
- `apps/web-platform/infra/inngest-bootstrap.sh` — listener gate in the heartbeat heredoc; extend
  `inngest-server-probe.sh`; token re-stage unit
- `apps/web-platform/infra/cloud-init-inngest.yml` — loud emitter; re-stage wiring
- `apps/web-platform/infra/inngest-cutover-flip.sh` — monotonic latch; probe-derived `done`
- `apps/web-platform/infra/inngest-cutover-flip.service` — `RequiresMountsFor=/mnt/data`
- `apps/web-platform/infra/inngest-server-flip-guard.sh` — instance-aware refusal
- `apps/web-platform/infra/inngest-server-flip-guard.test.sh` — lockstep re-review latch
- `apps/web-platform/infra/cat-inngest-cutover-state.sh` — latch path sweep
- `apps/web-platform/infra/outputs.tf` — heartbeat output consumer
- `scripts/cutover-inngest.sh` — `op=arm` URL source; `op=rollback` unconditional URL delete
- `.github/workflows/apply-web-platform-infra.yml` — `-target=` line for the new resources
- `.github/workflows/infra-validation.yml` — register every new suite (else they never run)
- `plugins/soleur/lib/heartbeat-manifest.ts` — row + `feeder` for the new heartbeat
- `knowledge-base/engineering/architecture/decisions/ADR-100-*.md` — Decision 6a, rule, addendum

## Files to Create

- `apps/web-platform/infra/inngest-consumer-probe.sh` / `.timer`
- `apps/web-platform/infra/inngest-consumer-probe.test.sh`
- `apps/web-platform/infra/inngest-cutover-latch.test.sh`
- `apps/web-platform/infra/inngest-boot-emitter.test.sh`

## Acceptance Criteria

### Pre-merge (PR)

1. `inngest-consumer-probe.sh` pings its heartbeat **only** on a 200 + non-empty registry; every
   other outcome suppresses — asserted per-arm by test, including the 500 the live host returns now.
2. The consumer probe's heartbeat is a **new** `betteruptime_heartbeat` and a **new**
   `doppler_secret` (named resource addresses, not a count), and `heartbeat-manifest.ts` carries its
   row with a `feeder` whose `evidence.pattern` resolves against `server.tf`.
3. Arming follows ADR-117: `paused = true` in source with a measured-beat PATCH path; no UI step
   appears in any artifact (`hr-never-label-any-step-as-manual-without`).
4. The dedicated pusher does not ping unless a local `/health` returns 200 — asserted by driving
   the non-200 arm.
5. The token re-stage unit re-fetches from Doppler; asserted over the **rendered** userdata, not
   the source template.
6. The emitter emits a `logger -t` line on both the missing-token and failed-POST paths.
7. The latch is append-only: a `rolled-back` no-op poll followed by `armed` **refuses** the flush —
   asserted by test. `inngest-cutover-flip.service` carries `RequiresMountsFor=/mnt/data`, the write
   is fatal, and `cat-inngest-cutover-state.sh` resolves the same path.
8. `flag_set done` is unreachable without a 200 `/health` **and** a non-empty registry; a foreign
   instance stamp makes the **guard** refuse the start — asserted against
   `inngest-server-flip-guard.sh`, not only the FSM. `inngest-server-flip-guard.test.sh` passes
   unmodified in its `EXPECTED_START_SITES` derivation.
9. Numbered, created issues exist for: the host replace, the cutover window, and the CLI bump —
   asserted by `gh issue view` on each, and each is cited in the PR body as `Ref`, not `Closes`.
10. Every new suite is registered in `infra-validation.yml` and appears in the
    `run-registered-suites.sh` derivation — asserted by the accounting gate's own count.
11. ADR-100 keeps `status: adopting`, its blockquote no longer asserts a running soak, and no new
    ADR ordinal is minted by this PR.
12. Full registered-suite run green, naming the commit it covered.

### Post-merge (automated)

13. The TF apply provisions the consumer probe + heartbeat; a real beat is measured and the
    monitor is PATCHed unpaused by the ADR-117 arm gate.

## User-Brand Impact

**If this lands broken, the user experiences:** app-originated event dispatch continuing to fail
silently. Corrected from the earlier draft: #7228 measured this as **fleet-wide**, not inbound-email
only — `engineering.pr_review_pending` was among the failures. Conversely the 53 registered crons
were **unaffected**, because execution is still pinned to web-1 (#7230). In the worst arm, a
re-cutover on a non-monotonic latch wipes in-flight Redis jobs.

**Recoverability of the outage to date:** the twelve days of failed dispatches are **accepted as
lost** by operator decision (2026-08-11). No replay, backfill or dead-letter path is in scope, and
none is deferred — this is a decision, not an omission.

**If this leaks, the user's data is exposed via:** the phone-home POST, which bypasses Vector's PII
scrub by design. Every field routes through `inngest-redact.sh`; `journal_tail` stays on the
once-per-boot marker rather than the recurring one, so the highest-risk field is not amplified.

- **Brand-survival threshold:** single-user incident

## Observability

```yaml
liveness_signal:
  what: consumer-side probe on the web host asserting a 200 + non-empty registry at 10.0.1.40:8288
  cadence: 60s
  alert_target: new dedicated Better Stack heartbeat, armed via the ADR-117 measured-beat PATCH
  configured_in: apps/web-platform/infra/inngest.tf + server.tf
error_reporting:
  destination: Better Stack Logs (SOLEUR_INNGEST_BOOT_STAGE + inngest-server-probe marker)
  fail_loud: true
failure_modes:
  - mode: inngest-server never binds :8288
    detection: consumer probe from the web host — independent of the dedicated host booting at all
    alert_route: consumer-probe heartbeat goes silent
  - mode: boot-trace channel dies on reboot (token lost from tmpfs)
    detection: re-stage unit failure emits an allowlisted logger line
    alert_route: Better Stack log alert on the marker
  - mode: cutover FSM asserts done on a host that never served
    detection: probe-derived done; foreign instance stamp refused by the guard
    alert_route: Better Stack log alert on the aborted marker
logs:
  where: Better Stack source table t520508_soleur_inngest_vector_prd_3_logs
  retention: ~3 days measured. The consumer probe re-emits every 60s from a host that is up, so a
    live failure is always in-window regardless of the dedicated host's state
discoverability_test:
  command: bash apps/web-platform/infra/inngest-consumer-probe.test.sh
  # Corrected at ship time by preflight Check 10, which EXECUTES this command instead of
  # trusting it. The original value ("OK inngest-consumer-probe: all assertions passed")
  # appears nowhere in the repo — it was copied by analogy from the sibling suite
  # inngest-boot-emitter.test.sh, which genuinely emits that shape. This suite ends with
  # `=== $PASS passed, $FAIL failed ===`. Matching on "0 failed" rather than the full line
  # so the expectation survives adding assertions.
  expected_output: "0 failed"
```

## Infrastructure (IaC)

### Terraform changes

`inngest.tf` (new heartbeat + new `doppler_secret`), `inngest-host.tf` (prose corrections,
diagnostic-backend variable), `server.tf` (web-host timer install), `outputs.tf`. No new provider.
No new no-default variable, so `hr-tf-variable-no-operator-mint-default` is not engaged.

### Apply path

Two distinct paths, and conflating them is what the review caught:

- **Merge-applied:** the consumer probe and its heartbeat live in files inside the per-merge
  `-target=` set, with the new `-target=` line added in the same PR. Detection ships on merge.
- **Replace-only:** cloud-init and bootstrap changes reach 10.0.1.40 **only** via
  `apply_target=inngest-host-replace` (`hr-prod-host-config-change-immutable-redeploy`). Sequenced
  at step 2 of `## Sequencing` and tracked by a numbered issue. Phase 3.1 must land first, because
  the replace is the operation that disarms the old latch.

### Distinctness / drift safeguards

`doppler_secret.inngest_heartbeat_url_prd` carries `ignore_changes = [value]`, so the new URL needs
a **new resource**, not a value edit — a value edit plans no change and applies nothing while the
ACs still pass. The dedicated host's secrets stay in the isolated `soleur-inngest` project.

### Vendor-tier reality check

One additional Better Stack heartbeat is within the existing tier; no tier gate needed.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-100 in place.** Correct Decision 6a's completion criteria; fold in the
terminal-state-must-be-re-derived rule; add the addendum recording that the cutover did not hold.
**No new ordinal is minted** — a one-sentence rule correcting this ADR does not warrant a separate
file, and the session already lost 167 and 178 to contention.

### C4 views

Read all three model files. Enumerated for this change: external human actors (none new), external
systems (Better Stack, Hetzner — both modeled), containers (`soleur-inngest` host, web-platform —
both modeled), data stores (Supabase Postgres, Redis volume — both modeled), and access
relationships. One relationship **does** change and gets a model line: the web-platform container
gains a monitoring probe edge to the dedicated host container. The earlier draft's claim of "no
relationship change" was overstated and is corrected here.

## Encryption Posture

```yaml
at_rest:
  - store: /run/inngest-bs-logs-token (re-staged per boot)
    mechanism: tmpfs, mode 0600, root-owned
    evidence: cloud-init write + chmod; cleared every reboot by construction
    defends_against: at-rest recovery from the block device
    does_not_defend: a root compromise on the live host
    disclosed_as: internal credential, not user data
    live_verification: the re-stage unit's status field on the probe marker
  - store: hcloud_volume.inngest_redis (unchanged)
    mechanism: plaintext-exception
    evidence: pre-existing; neither introduced nor changed here
    defends_against: nothing at rest
    does_not_defend: volume-snapshot recovery of in-flight job payloads
    disclosed_as: known encryption-posture gap
    live_verification: n/a — no change in this PR
in_transit:
  - connection: web host -> 10.0.1.40:8288 (consumer probe)
    tls: false
    cert_verification: off
    does_not_defend: private-network traffic is unencrypted by design on this segment
    disclosed_as: internal private-network probe, no user data in the request
  - connection: host -> Better Stack ingest
    tls: true
    cert_verification: on
    does_not_defend: content is scrubbed client-side; a compromised host can ship anything
    disclosed_as: telemetry egress
exception:
  justification: the Redis volume's plaintext state is pre-existing and out of scope; changing it
    needs a volume migration that conflicts with the preserve-on-replace requirement. The probe
    connection is plaintext because it rides the Hetzner private network and carries no user data.
  tracking_issue: "6894"
  reevaluate_when: the cutover completes and the volume can be migrated in its own window
  expires_on: 2026-11-30
```

## Domain Review

**Domains relevant:** engineering, product

### Engineering (CTO)

**Status:** reviewed (with one finding corrected downstream)
**Assessment:** Established that atomicity is structurally unavailable across two disjoint control
planes (accept a gap, never an overlap); that `done` is a host-outliving assertion over an
unasserted unit start; that the catastrophe latch is disarmed by the very replace being
contemplated, with the `DBSIZE` check shown to be a post-condition; and that the CLI bump must not
share a window with the cutover because of one-way goose migrations on a shared Postgres. **Its
dual-pusher heartbeat finding was subsequently refuted against source** (`inngest.tf:302`,
`inngest-host.tf:170`, `inngest-bootstrap.sh:277`) and is superseded by the corrected mechanism in
`## Overview`. Recorded rather than deleted, because propagating it unverified is what the review
had to undo.

### Product (CPO)

**Status:** reviewed — CHANGES-REQUESTED, all four resolved
**Assessment:** Required pricing the restoration deferral, answering recoverability, correcting the
blast radius, and asserting the heartbeat is *armed* rather than merely declared. Resolved by the
operator decisions in `## Overview` (restoration deferred deliberately; dispatches accepted as
lost), the corrected blast radius in `## User-Brand Impact`, and AC2/AC3.

### Product/UX Gate

Not applicable — no UI-surface path in `## Files to Edit` or `## Files to Create`.

## Open Code-Review Overlap

None.

## Test Scenarios

1. Consumer probe: 200 + non-empty registry → pings.
2. Consumer probe: HTTP 500 (the current live response) → suppresses.
3. Consumer probe: connection refused → suppresses.
4. Dedicated pusher: local `/health` non-200 → no ping.
5. Emitter: no token file → loud logger line, not a silent exit 0.
6. Emitter: POST fails → loud logger line.
7. Token re-stage: simulated second boot with `/run` cleared → token present.
8. Latch: `rolled-back` no-op poll, then `armed` → flush refused.
9. Latch: unwritable path → fatal, not silently swallowed.
10. `done` refused on non-200 `/health`; refused on empty registry.
11. Guard refuses a `done` whose instance stamp is foreign.
12. `inngest-server-flip-guard.test.sh` `EXPECTED_START_SITES` derivation still passes.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Replace re-runs FLUSHALL on the restored AOF volume | The **monotonic latch** (Phase 3.1) is the guard, and it lands before the replace. Corrected from the earlier draft, which wrongly credited the flip guard — that guard is an `ExecStartPre` on the server and never runs on the flush path |
| Replaced host can never bind because the FSM flag is non-terminal | Phase 2.1's diagnostic boot: a non-prod backend yields `is_prod=false` and the guard's ALLOW arm, with no path to a second prod scheduler |
| New heartbeat ships inert | AC3 forces the ADR-117 measured-beat arming path; #6537 is the 9-day precedent |
| Instance stamp breaks the guard's exact `case` match | The stamp lives in a separate Doppler key; the flag value is unchanged (AC8) |
| New suites never execute | AC10 registers them in `infra-validation.yml`, which is the derivation source |
| Heartbeat URL repoint silently no-ops | New `doppler_secret` resource, never a value edit under `ignore_changes = [value]` |

## Non-Goals

- **Replay/backfill of the 12 days of failed dispatches.** Accepted as lost by operator decision
  (2026-08-11). Not deferred — decided.
- **Interim `INNGEST_BASE_URL` repoint.** Declined by operator decision (2026-08-11): fix the
  dedicated host properly rather than return to the co-located operating point. Cost recorded —
  dispatch stays down until the cutover window.
- **Executing the cutover.** quiesce-web → confirm → arm → verify, accepting a gap. Numbered issue
  (AC9), gated behind the `inngest-cutover` required-reviewer environment.
- **Bumping to v1.41.1.** Hard-coupled to the cutover by one-way goose migrations on a shared
  Postgres; needs a re-spike of ADR-100's three Phase-0 findings, both arch checksums from one
  signed `checksums.txt`, and verification that `--postgres-max-open-conns` and the `signkey-prod-`
  strip still hold. Numbered issue (AC9).
- **Pin-freshness monitoring (#7308).** Moves to the bump window, where its remediation exists.
- **The entropy bound.** Unrelated subsystem (container-registry userdata budget); its own PR.
- **Re-litigating zot health.**
