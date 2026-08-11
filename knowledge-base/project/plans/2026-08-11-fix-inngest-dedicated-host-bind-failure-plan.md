---
title: "Make the dedicated inngest host self-annunciating and its re-cutover safe"
date: 2026-08-11
slug: fix-inngest-dedicated-host-bind-failure
branch: feat-one-shot-7228-inngest-host-dark-bind-failure
lane: cross-domain
type: fix
issue: 7228
closes: [7228, 6617, 7308]
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

The dedicated inngest host (`soleur-inngest`, 10.0.1.40) boots and runs but never binds :8288, so
the web-platform container's dispatches fail with `connect ECONNREFUSED`. Twelve days passed
without anyone noticing.

The initial framing — "the host is dark because it has no error channel" — did not survive
measurement. The host has an **excellent** boot-trace channel (eight staged
`SOLEUR_INNGEST_BOOT_STAGE` markers ending in `post-boot-health` and `net-health`, the latter
carrying `bind=`, `priv8288=` and `nft=`: this entire diagnosis in one row). That channel almost
certainly fired on 2026-07-30 and its evidence **expired**, because the sink's retention is ~3 days
and nothing alerts on a failure marker. Meanwhile the one monitor that should have screamed —
`betteruptime_heartbeat.inngest_prd` — is a single monitor with **two** pushers, and the still-alive
co-located scheduler held it green throughout.

So the defect is not an absent channel. It is a channel whose evidence has a 72-hour half-life, a
liveness monitor that cannot distinguish which host is answering, and a cutover state machine whose
terminal `done` outlives the host it describes. The root cause of the bind failure itself remains
**UNKNOWN and is not guessed at here** — the deciding datum was discarded by retention, and this
plan's first job is to guarantee the next boot produces one that survives.

Scope is deliberately bounded to what is safe to land in one PR: make the host self-annunciating,
make the re-cutover safe, and record the decisions. Executing the cutover and bumping the CLI are
sequenced into their own operator-gated windows (see `## Non-Goals`), because atomic cutover is
structurally unavailable and the version bump runs one-way Postgres migrations against a backend the
co-located host still shares.

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
| "There is no `inngest-boot-phone-home.sh` on main" | It exists as an embedded `write_files` entry in `cloud-init-inngest.yml`, emitting 8 staged markers | Do not build a channel. Make the existing one's evidence durable and its failure loud |
| "`inngest-server.service` journald is not in the vector allowlist" | Already present as Source 1 (`[sources.inngest_journald]`, `include_units`) | No change to the allowlist |
| "Ship the error channel before any reproduction" | The channel shipped; its **evidence expired** (retention ~3 days vs a 12-day-old boot) | Reframed: durability + annunciation, not construction |
| "ADR-167 documents the rollback and needs superseding" | ADR-167 is not on `main`; two unmerged branches each claim the ordinal | Record the reversal at **ADR-179** (re-derived across all 66 refs; 178 was taken mid-session) |
| "Make the cutover atomic" | Structurally unavailable — the two hosts sit on disjoint control planes | Accept a **gap**, never an overlap; quiesce-web precedes arm |
| "Bump the CLI pin in this change" | `inngest start` runs one-way goose migrations; the co-located host shares that Postgres at v1.19.4 | Deferred to its own window, sequenced after the cutover |
| Runner fail-open still live | Already closed on `main` | No action |
| "27 releases behind" / issue title says 22 | Neither reproduced | Compute at bump time; restate neither |

## Hypotheses

Per `hr-ssh-diagnosis-verify-firewall`, L3→L7 order, unverified layers first. **No verdict is recorded
where the discriminator is invisible** — the 2026-07-30 boot trace is destroyed by retention, so
boot-time causation is UNKNOWN for every hypothesis below, including those that feel refuted.

1. **L3 — firewall / nftables allowlist.** UNVERIFIED. The `net-health` marker captures the
   `inet soleur_inngest input` chain, but that row expired. Not diagnosable from the repo.
   Discriminator ships in Phase 1; verdict deferred to the first instrumented boot.
2. **L3 — private-network routing / NIC.** UNVERIFIED for the same reason (`nic=` field, expired).
   Partially constrained: the web host reaches 10.0.1.40 well enough to receive a TCP refusal
   rather than a timeout, which is consistent with the route being intact and nothing listening.
3. **L7 — TLS/proxy.** **Opt-out with artifact.** The symptom is plain HTTP over the private
   network (`http://10.0.1.40:8288`), with no CDN, proxy or TLS in path.
4. **L7 — application.** UNVERIFIED. The dedicated host's journal cannot be read off-box
   (`hr-no-ssh-fallback-in-runbooks`), and Source 1 has shipped **zero** rows from this host.
   Measured: of 1,839 rows naming `inngest-server.service` in 72h, 1,459 carry
   `host = soleur-web-platform` — the co-located unit. Absence of a lower-layer signal is itself a
   signal, and here it is contaminated by a sibling host, so field-isolation on `host` is mandatory.
5. **Bootstrap never installed or enabled the unit.** UNVERIFIED, and the leading candidate given
   that the creation timestamp is the outage onset. `bootstrap-exit-N` would decide it; expired.
6. **The FSM believed it was already finished.** MEASURED-PLAUSIBLE, mechanism confirmed in source:
   `inngest-cutover-flip.sh` sets `done` after a bare unit-start call that asserts no listener, and
   the flag lives in Doppler, which outlives the host. A host created 2026-07-30 reads `done` and
   takes the no-op arm forever. This explains why nothing self-healed; it does **not** by itself
   explain why the first start failed, and is not recorded as the root cause.
7. **Doppler `/usr/bin` symlink regression (status=203/EXEC).** Present in source
   (`ln -sf /usr/local/bin/doppler /usr/bin/doppler`). Source presence is not host presence — the
   image is the only delivery path — so this stays a hypothesis to falsify against the first
   instrumented boot, not a closed item.

## Scope Decision

**In scope (this PR).** Diagnosability and safety — everything that must be true *before* a
re-cutover is attempted, plus two independent fixes.

**Out of scope, sequenced.** Cutover execution and the v1.41.1 bump. Rationale and tracking in
`## Non-Goals`.

## Implementation Phases

### Phase 1 — Make the failure annunciate (the reason 12 days passed)

1.1 **Split the shared heartbeat.** `betteruptime_heartbeat.inngest_prd` is one monitor with two
pushers; a dedicated-host outage is masked by the co-located pusher. Add a distinct heartbeat owned
solely by the dedicated host, and scope the existing one to the web fleet. `inngest-host.tf` already
names this hazard in prose — the change makes the code agree with the comment.

1.2 **Promote `post-boot-health` from one-shot to recurring.** A `.timer` (60–300s) pushes
`host, boot_id, instance_id, uptime, inngest_cli_version, unit states, listener-on-:8288, cutover flag, redacted journal tail`.
This is a promotion of existing code, not a new pattern.

1.3 **Re-stage the sink token every boot.** Every write of `/run/inngest-bs-logs-token` lives in
`runcmd:` (first boot only) and `/run` is tmpfs. A systemd oneshot re-fetches it from Doppler each
boot — re-fetch, never a baked re-stamp, so no long-lived credential lands in userdata at rest.
`cloud-init-inngest.yml` already *claims* "re-fetched every boot"; this makes the comment true.

1.4 **Make the emitter's failure loud.** `[ -r "$tok_file" ] || exit 0` with
`curl >/dev/null 2>&1` is the silent fallback `cq-silent-fallback-must-mirror-to-sentry` forbids. A
missing token or a failed POST emits a `logger -t` line on an allowlisted `SYSLOG_IDENTIFIER`.

1.5 **Assert arrival before trusting silence.** A marker is pulled back from Better Stack,
field-isolated on `host`, and its absence fails the phase. An empty query is not evidence until the
signal is proven instrumented **and** retention proven to cover the window.

### Phase 2 — Make the re-cutover safe

2.1 **Move the catastrophe latch onto surviving storage.** `/var/lock/inngest-cutover-flip.state`
is tmpfs and dies on replace, while the Redis AOF volume survives — so a replace plus any flag
rewind re-runs `FLUSHALL` against a restored prod queue. Relocate the latch onto the durable volume.

2.2 **Correct the false durability claim.** `inngest-host.tf` asserts `DBSIZE==0` still guards a
spurious re-flush. `run_preflush_flip` reads DBSIZE *after* the flush, making it a post-condition,
not a guard. Fix the comment and add the real pre-flush assertion.

2.3 **Make `done` mean "it serves".** Before `flag_set done`, require in a bounded window:
`/health` 200; a **non-empty** registry via the `v0/gql` query `inngest-registry-probe.sh` already
sends; and the unit still active after a settle window. Any failure ⇒ `aborted` plus a loud marker.

2.4 **Scope `done` to the host instance.** Stamp the flag with the Hetzner instance/boot id; a
`done` bearing a foreign instance id is treated as `unset`. This one change makes a recreate
self-annunciating.

### Phase 3 — Record the decisions

3.1 Amend **ADR-100** in place (its established idiom): correct Decision 6a, whose gate is
`exit_code:0` on the same unasserted unit-start the code performs, and add an addendum stating the
cutover did not hold and the soak never started. Keep `status: adopting`; rewrite the blockquote
that implies a soak is running.

3.2 Create **ADR-179** for the extracted cross-cutting rule: *a terminal state asserting a live host
condition must be re-derived from a probe, and must not be stored in a medium whose lifetime exceeds
the thing it asserts.* Record the reversal of the co-location rollback here in prose (no
`supersedes:` key — ADR-167 is not on `main` and the pointer would dangle).

### Phase 4 — Independent fixes

4.1 **Pin-freshness monitoring** (#7308's actual ask — nothing watches the pin today). The bump
itself is deferred; the monitor is not.

4.2 **Entropy bound.** Port the assertion (not the file) so
`registry-userdata-budget.sh`'s compressible `STUBSTUB…` stub can no longer under-measure the
incompressible part of the render. A per-stub bound of `>= 0.75 × raw` rejects the stub (0.62) and
accepts real entropy (1.51).

## Files to Edit

- `apps/web-platform/infra/inngest.tf` — heartbeat split; `INNGEST_HEARTBEAT_URL` publication
- `apps/web-platform/infra/inngest-host.tf` — dedicated heartbeat resource; correct the false
  `DBSIZE` durability claim; correct the stale arm64/cax11 prose
- `apps/web-platform/infra/cloud-init-inngest.yml` — token re-stage unit; loud emitter
- `apps/web-platform/infra/inngest-bootstrap.sh` — recurring health timer install
- `apps/web-platform/infra/inngest-cutover-flip.sh` — completion criteria; instance-scoped `done`;
  latch relocation
- `apps/web-platform/infra/vector.toml` — allowlist the new `SYSLOG_IDENTIFIER`
- `apps/web-platform/infra/inngest-betterstack-token.tf` — stale header prose
- `apps/web-platform/infra/registry-userdata-budget.test.sh` — entropy bound
- `knowledge-base/engineering/architecture/decisions/ADR-100-*.md` — Decision 6a + addendum

## Files to Create

- `apps/web-platform/infra/inngest-host-health.timer` / `.service` — recurring state channel
- `apps/web-platform/infra/inngest-bs-token-restage.service` — per-boot token re-fetch
- `knowledge-base/engineering/architecture/decisions/ADR-179-terminal-state-must-be-rederived-from-a-live-probe.md`
- test suites for each behavioral change (RED before GREEN, `cq-write-failing-tests-before`)

## Acceptance Criteria

### Pre-merge (PR)

1. `betteruptime_heartbeat` resources: exactly one owned by the dedicated host, one scoped to the
   web fleet; `terraform validate` passes.
2. A dedicated-host heartbeat push is absent from any web-host code path (grep, field-isolated).
3. The recurring health `.timer` unit is installed by the bootstrap and its content asserts all of:
   unit states, listener on :8288, cutover flag, boot/instance id.
4. The token re-stage unit re-fetches from Doppler; no baked token value is written by it (grep for
   the template var name returns zero hits in the new unit).
5. The emitter emits a `logger -t` line on both the missing-token and failed-POST paths; the new
   `SYSLOG_IDENTIFIER` appears in `vector.toml`'s exact-match allowlist (assert the anchor, not a
   bare token).
6. The catastrophe latch path resolves onto the durable volume, not `/var/lock`.
7. `flag_set done` is unreachable without a 200 `/health`, a non-empty registry, and a
   post-settle active unit — asserted by a test that drives each failure arm to `aborted`.
8. A `done` flag bearing a foreign instance id is treated as `unset` — asserted by test.
9. `ADR-179` exists, carries no `supersedes:` key, and no artifact in this feature's plan/spec set
   cites a different ordinal (`grep -rn 'ADR-17[0-9]'` over the feature's artifacts).
10. ADR-100 `status:` remains `adopting`; its blockquote no longer asserts a running soak.
11. The entropy bound rejects the current `STUBSTUB…` stub and accepts a real-entropy token —
    asserted by two cases in the same suite.
12. Full registered-suite run is green, with the run's commit named.

### Post-merge (automated)

13. `apply-web-platform-infra.yml` applies the Terraform delta; the heartbeat split is visible in
    the applied state.
14. Pin-freshness monitoring reports the live pin and the current upstream tag.

## User-Brand Impact

**If this lands broken, the user experiences:** inbound email that is silently never processed —
the #7228 symptom — or, if the heartbeat split is wrong, a fleet that looks healthy while a
scheduler is dead. In the worst arm, a re-cutover attempted on an unfixed latch wipes in-flight
Redis jobs, losing queued work the user has already paid for in time.

**If this leaks, the user's data is exposed via:** the phone-home POST, which bypasses Vector's PII
scrub by design. Every new field added to the recurring channel must route through
`inngest-redact.sh`; the journal tail is the highest-risk field.

**Brand-survival threshold:** single-user incident.

## Observability

```yaml
liveness_signal:
  what: dedicated-host heartbeat, pushed only by 10.0.1.40
  cadence: 60-300s
  alert_target: Better Stack heartbeat monitor (dedicated, not shared)
  configured_in: apps/web-platform/infra/inngest-host.tf
error_reporting:
  destination: Better Stack Logs (SOLEUR_INNGEST_BOOT_STAGE + the recurring health marker)
  fail_loud: true  # missing token and failed POST both emit an allowlisted logger line
failure_modes:
  - mode: inngest-server never binds :8288
    detection: recurring health marker, listener field, field-isolated on host
    alert_route: dedicated heartbeat goes silent
  - mode: boot-trace channel itself dies (token lost on reboot)
    detection: re-stage unit failure emits an allowlisted logger line
    alert_route: Better Stack log alert on the marker
  - mode: cutover FSM asserts done on a host that never served
    detection: instance-id mismatch treated as unset; aborted marker on failed completion criteria
    alert_route: Better Stack log alert on the aborted marker
logs:
  where: Better Stack source table t520508_soleur_inngest_vector_prd_3_logs
  retention: ~3 days measured — the reason this incident was undiagnosable; the recurring
    channel re-emits within every retention window, so a live failure is always in-window
discoverability_test:
  command: bash apps/web-platform/infra/inngest-host-health-probe.test.sh
  expected_output: "OK inngest-host-health: all assertions passed"
```

## Infrastructure (IaC)

### Terraform changes

`inngest.tf` (heartbeat scoping), `inngest-host.tf` (new dedicated heartbeat, corrected prose),
`inngest-betterstack-token.tf` (prose). No new provider or version pin. No new no-default variable,
so no mint is required and `hr-tf-variable-no-operator-mint-default` is not engaged.

### Apply path

cloud-init + immutable redeploy. Per `hr-prod-host-config-change-immutable-redeploy` the
cloud-init and bootstrap changes reach 10.0.1.40 only through a host replace via
`apply_target=inngest-host-replace` (the additive `inngest-host` dispatch aborts on the delete a
replace emits). Blast radius is nil today: the host serves nothing. `hcloud_volume.inngest_redis` is
preserved — and Phase 2.1 is what makes that preservation safe.

### Distinctness / drift safeguards

The dedicated host's secrets live in the isolated `soleur-inngest` project with no inheritance path
to `soleur/prd`. The heartbeat split must not reuse the existing monitor id.

### Vendor-tier reality check

Better Stack heartbeats are already provisioned on this tier; adding one more monitor is within the
existing plan and requires no tier gate.

## Architecture Decision (ADR/C4)

### ADR

- **Amend ADR-100** in place — correct Decision 6a's completion criteria; addendum recording that
  the cutover did not hold and the soak never began.
- **Create ADR-179** — terminal state must be re-derived from a live probe and must not outlive the
  thing it asserts. Records the reversal of the co-location rollback in prose.

### C4 views

Checked all three model files. The external actors and systems this change touches — Better Stack
(external monitoring system), Hetzner (external infrastructure), the Inngest scheduler container —
are already modeled, as is the dedicated-host container. **This change alters no element, no
relationship and no boundary**: it changes how an already-modeled container reports its own health,
and splits one already-modeled monitoring relationship into two instances of the same edge. No new
actor, system, container or data store is introduced. Enumerated and found already-modeled:
Better Stack, Hetzner, `soleur-inngest` host container, web-platform container, Supabase Postgres,
Redis volume.

### Sequencing

ADR-179 is authored now describing the target state. ADR-100 stays `adopting` because its decision
is still the operator's target; only its false soak claim is corrected.

## Encryption Posture

```yaml
at_rest:
  - store: /run/inngest-bs-logs-token (re-staged per boot)
    mechanism: tmpfs, mode 0600, root-owned
    evidence: cloud-init write + chmod; cleared on every reboot by construction
    defends_against: at-rest recovery from the block device
    does_not_defend: a root compromise on the live host
    disclosed_as: internal credential, not user data
    live_verification: the re-stage unit's own status field in the recurring health marker
  - store: hcloud_volume.inngest_redis (unchanged by this plan)
    mechanism: plaintext-exception
    evidence: pre-existing; this plan neither introduces nor changes it
    defends_against: nothing at rest
    does_not_defend: volume-snapshot recovery of in-flight job payloads
    disclosed_as: tracked separately as a known encryption-posture gap
    live_verification: n/a — no change in this PR
in_transit:
  - connection: host -> Better Stack ingest
    tls: true
    cert_verification: on
    does_not_defend: content already scrubbed client-side; a compromised host can ship anything
    disclosed_as: telemetry egress
exception:
  justification: the Redis volume's plaintext state is pre-existing and out of scope here;
    changing it would require a volume migration that conflicts with the preserve-on-replace
    requirement this plan depends on
  tracking_issue: "6894"
  reevaluate_when: the cutover completes and the volume can be migrated in its own window
  expires_on: 2026-11-30
```

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Identified the four findings that reshaped this plan: the dual-pusher heartbeat as
the actual masking mechanism (#6617); `done` as a host-outliving assertion over an unasserted
unit start; the catastrophe latch disarmed by the very replace being contemplated, with the
`DBSIZE` guard shown to be a post-condition; and atomicity as structurally unavailable across two
disjoint control planes. Ruled that the FSM must be parked at `rolled-back` rather than rewound,
because every rewind target that lets the FSM act also permits a prod-URI start. Ruled the version
bump must not share a window with the cutover, because `inngest start` runs one-way goose migrations
against a Postgres the co-located v1.19.4 host still shares.

### Product/UX Gate

Not applicable — no UI surface in `## Files to Edit` or `## Files to Create`; the mechanical
UI-surface override does not fire.

## Open Code-Review Overlap

None.

## Test Scenarios

1. Emitter with no token file emits an allowlisted logger line and does not exit 0 silently.
2. Emitter whose POST fails emits an allowlisted logger line.
3. Re-stage unit re-fetches on a simulated second boot with `/run` cleared.
4. `flag_set done` refused when `/health` is non-200.
5. `flag_set done` refused when the registry query returns empty.
6. `flag_set done` refused when the unit is inactive after the settle window.
7. A `done` flag with a foreign instance id is treated as `unset`.
8. Pre-flush latch resolves onto the durable volume and blocks a second flush.
9. Entropy bound rejects the compressible stub; accepts a real-entropy token.
10. `vector.toml` admits the new `SYSLOG_IDENTIFIER` (anchor assertion).

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Host replace re-runs FLUSHALL on the restored AOF queue | Phase 2.1 lands the latch relocation **before** any replace; the FSM is parked at `rolled-back` so the guard refuses a prod start |
| Heartbeat split leaves both monitors unwatched | AC2 asserts ownership per host; the dedicated monitor's first push is verified field-isolated |
| New recurring channel ships secrets | Every field routes through `inngest-redact.sh`; the journal tail is length-capped and redacted, as the existing marker already does |
| Recurring timer adds log volume/cost | 60–300s cadence on one host is ~300–1,400 rows/day, the same order as the existing heartbeat |
| ADR-179 ordinal collides before merge | Re-derived across all 66 refs immediately before merge; 178 was already lost once this session |

## Non-Goals

- **Executing the cutover.** Requires a maintenance window and the sequence quiesce-web → confirm
  quiesced → arm → verify, accepting a gap. Gated behind the `inngest-cutover` required-reviewer
  environment. Tracked as a follow-up issue.
- **Bumping `inngest_cli_version` to v1.41.1.** Hard-coupled to the cutover by one-way goose
  migrations on a shared Postgres. Needs a re-spike of ADR-100's three Phase-0 empirical findings at
  the new version, both arch checksums from one signed `checksums.txt`, and verification that
  `--postgres-max-open-conns` (a durable-detection sentinel) and the `signkey-prod-` strip still
  hold. Tracked as a follow-up issue.
- **Re-litigating zot health**, per the operator decision.
- **Repointing `INNGEST_BASE_URL`** away from 10.0.1.40, per the operator decision.
