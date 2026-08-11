---
title: "Fix the dedicated inngest host so it binds and serves :8288"
date: 2026-08-11
slug: fix-inngest-dedicated-host-bind-failure
branch: feat-one-shot-7228-inngest-host-dark-bind-failure
issue: 7228
---

## Overview

The dedicated inngest host (`soleur-inngest`, 10.0.1.40) boots and runs but never binds :8288, so
the web-platform container's dispatches fail with `connect ECONNREFUSED`. The host's boot-trace
error channel exists but has been silent, so the bind failure is currently undiagnosable off-box.
This plan proves why the trace vanishes, diagnoses the bind failure with evidence rather than
assumption, and then addresses the stale CLI version pin and its missing freshness monitoring.

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
