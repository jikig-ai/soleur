---
title: "fix(inngest): inngest-redis crash-loops and its stderr reaches no telemetry, so the watchdog can only guess"
date: 2026-08-06
branch: feat-one-shot-7286-inngest-down-restart-exhausted
issue: 7286
type: bug
classification: incident-remediation
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: ADR-169 (PROVISIONAL — re-derive against origin/main at /ship)
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# fix(inngest): `inngest-redis` crash-loops and its stderr reaches no telemetry

## Enhancement Summary

**Deepened:** 2026-08-06 · **Panels:** CTO consult, observability-coverage-reviewer, spec-flow-analyzer, security-sentinel, learnings-researcher · **Gates run:** 4.5 (network — fired), 4.6, 4.7, 4.8, 4.9 (skipped, no UI), 4.10, 4.55 (downtime)

**Key improvements — each overturned something the first draft asserted:**

1. **The delivery mechanism is a scoped `terraform apply`, not "no Terraform."** `push-infra-config.sh` has exactly one caller: a `local-exec` provisioner on `terraform_data.deploy_pipeline_fix`. AC9 forbade the very thing Phase 1 depends on. Restated, plus Phase 0.7 as a blocking probe of whether #7273 spares the `-target`ed apply.
2. **The drop-in needs 7 registration surfaces, not 2.** A `FILE_MAP`+`DEST_SPEC`-only change writes two entries and delivers nothing.
3. **The leading hypothesis changed.** A CTO consult overturned this plan's own "dead Doppler token is REFUTED": `inngest-redis.service` is the only Doppler consumer without a token drop-in, so it and `inngest-server` read the same file to different effect. H7 is now leading, and the plan carries its (inert-if-unneeded) fix.
4. **The proposed structural fix was rejected and replaced.** A runtime SQLite fallback would have masked this regression for 15 h while silently dropping armed reminders. Phase 3 is now detect-and-fail-loud plus a class-closing invariant test.
5. **Two instruments were false greens.** `inngest_redis_dropin` measured disk instead of systemd's loaded `DropInPaths`; `inngest_redis_secret_len` was unobtainable and unsafe in every implementation and is dropped.
6. **AC7's gate could not fail.** `lint-infra-no-human-steps.py` cannot match `ssh root@` — verified live, exit 0 with all 7 lines present. The plan's central no-SSH promise was unverifiable; the linter fix + a proof-of-red are now in scope.
7. **Phase 6.6 prescribed three wrong edits.** `vector.toml` already allowlists `inngest-redis`; adding `redis-server` would be a dead exact-match entry *and* break a derived-set-equality fixture.

**New considerations discovered:** the first `/hooks/infra-config` push after adding a file is a **deterministic red** (#4804) and must not be read as channel failure; the probe and the fix land through *different* activation paths, so the diagnostic survives even if the fix is blocked; and no AC executed a job end-to-end, so every post-merge check could have gone green with the user's stated symptom unchanged (AC15b closes this).

Full disposition of all 23 P0/P1 findings: § Deepen-Pass Review Findings.

> **IaC routing ack.** Phase 2.8 reviewed. This plan prescribes **zero** operator SSH and **zero** manual provisioning: every change lands through the existing `/hooks/infra-config` allowlisted-file channel or a digest-pinned OCI bootstrap-image release (§ Infrastructure (IaC)). Host-login command strings appear in this document **only** as citations of runbook lines that Phase 5 **deletes** — they are the defect being removed, not a step being prescribed.

> **Lane note.** `knowledge-base/project/specs/feat-one-shot-7286-inngest-down-restart-exhausted/spec.md` does not exist (this branch was created by the one-shot pipeline with no preceding spec). Per the plan skill's TR2 fail-closed rule, `lane:` defaults to `cross-domain`.

## Overview

`inngest-server.service` on prod host `hetzner-123931471` has been crash-looping since **2026-08-05 06:34:07 UTC** — ~15 hours at plan time and still going. The watchdog detected it at 07:17, auto-dispatched `restart-inngest-server.yml`, the restart failed, and the 45-minute age gate suppressed further restarts at 10:06 with `ci/inngest-restart-exhausted`.

The proximate cause is **measured**:

- `inngest-server` reaches Postgres fine, then dies on Redis: `{"level":"INFO","msg":"using external redis","url":" redis://:xxxxx@127.0.0.1:6379"}` → `error creating redis client: dial tcp 127.0.0.1:6379: connect: connection refused`, every ~9 s.
- Redis is absent because `inngest-redis.service` is itself failing every ~5 s: `inngest-redis.service: Failed with result 'exit-code'.`

So the issue body's hypothesis ("the durable backend likely lost its Redis") is **right in shape**. Both of its proposed remedies are wrong for this failure (§ Premise Validation), and the underlying defect is not what the issue guessed.

**Why `redis-server` exits non-zero is UNKNOWN, and it is unknowable from any remote surface that exists today.** Fifteen hours of a P1 outage produced exactly one bit of information about the failing component: *it exited non-zero.* Every hypothesis in § Hypotheses is therefore marked `UNKNOWN` — including the two this plan's first draft wrongly marked REFUTED, and which a CTO consult overturned (§ Consult Corrections). That is the plan-skill sharp edge in action: a hypothesis table may not read CONFIRMED or REFUTED while the plan's own text says the discriminator is invisible.

The plan's shape follows from that. **Phase 1 is a diagnostic instrument that also carries one bounded, inert-if-unneeded fix**, and it ships first. Nothing downstream commits to a cause until Phase 1's payload names one.

### Consult Corrections (what a second pass overturned)

| Draft claim | Correction | Effect |
|---|---|---|
| "Dead Doppler token is REFUTED — `inngest-redis.service` and `inngest-server.service` share `EnvironmentFile=/etc/default/inngest-server`, and inngest-server's `doppler run` succeeds." | **Wrong, and wrong in the most dangerous direction.** `inngest-server.service` has a **drop-in** (`10-inngest-server-doppler-token.conf` → `EnvironmentFile=-/etc/default/soleur-doppler-token`) that systemd merges **after** the unit body, so it **overrides** the pinned token. `inngest-redis.service` has **no such drop-in** — `infra-config-apply.sh` `FILE_MAP` delivers drop-ins for exactly three units (`vector.service.d/`, `inngest-heartbeat.service.d/`, `inngest-server.service.d/`). Same file, different effective token. The two facts are fully consistent with a dead token killing **only** redis. | Becomes **H7**, now the leading hypothesis, and the reason Phase 1 carries a fix. |
| "The `inngest-redis` telemetry channel is dark — proven." | **Over-claimed.** The positive control proves the *sink* and *several* Source-4 tags are live. It does **not** prove the `inngest-redis` allowlist entry is live **on web-1**: `vector.toml` is baked into the OCI bootstrap image and is **not** in `FILE_MAP`, so web-1's running config may predate the entry. Zero rows is then a pipeline artifact, not a fact about redis. | E7/E8 softened; the deciding read becomes Phase 1's **local** `journalctl`, which bypasses the shipper entirely. |
| "Phase 3 = a start-time SQLite fallback arm." | **Rejected.** A SQLite fallback would have *masked* this regression for 15 h while silently dropping armed reminders — converting a diagnosable crash-loop into an undiagnosable data-loss event. Strictly worse than #5542, not a mitigation of it. | Phase 3 becomes **detect-and-fail-loud** plus a class-closing invariant test. The ADR records the reversal. |
| "Phase 4 adds an AOF quarantine verb." | **Deferred.** If the cause is credential, there is no corrupt AOF, and adding a MOVE verb to the root-run allowlisted `ci-deploy.sh` surface expands privileged surface for an unestablished cause. | Gated on Phase 1 evidence naming the AOF. |

---

## Premise Validation (Phase 0.6)

| Premise cited | Verified how | Verdict |
|---|---|---|
| Issue **#7286** open, needs human root-cause | `gh issue view 7286` → `OPEN`; labels `priority/p1-high`, `ci/inngest-down`, `ci/inngest-restart-exhausted` | **HOLDS** |
| Run log `actions/runs/30984447882` | `gh run view` → "Scheduled: Inngest Health Watchdog", `probe` job, 3/3 attempts `inngest_down` | **HOLDS** |
| Prior incident **#5542** ("the runbook cites it") | `gh issue view 5542` → CLOSED 2026-06-18, titled *"no-SSH FALLBACK re-arm self-enumerates the post-deploy EMPTY server → loses all armed reminders on the first SQLite→Postgres cutover"* | **STALE AS PRECEDENT.** #5542 is a **cutover reminder-preservation** bug, not a Redis crash-loop. Its one transferable fact: the armed-reminder queue lives in **Redis**, so any remedy that resets the AOF silently drops reminders. It is **not** precedent for "re-stage the redis assets." |
| Runbook `knowledge-base/engineering/operations/runbooks/inngest-server.md` | 1278 lines; exists | **HOLDS** — but has no Redis-down procedure and 7 host-login instructions (§ Research Reconciliation) |
| Issue-body remedy A: "the deploy must re-stage the redis assets" | Redis assets reach a host only via the OCI image (`ci-deploy.sh:3205-3209`), gated at `inngest-bootstrap.sh:633`. The unit **is present and executing** — systemd restarts it every 5 s. | **REFUTED.** Re-staging fixes an *absent* unit; this unit exists and runs. |
| Issue-body remedy B: "roll the ExecStart back to SQLite-only" | Restores availability; silently drops the Redis-resident armed-reminder queue. Would have hidden this regression for 15 h. | **REJECTED** (§ Consult Corrections). |
| Mechanism vs ADR corpus | `inngestRedis` + `inngest -> inngestRedis` already modelled (`model.c4:196,483`); durability decided by #5450 / ADR-030 / ADR-100 | **HOLDS** — no rejected-alternative collision. The new decision (detect-and-fail-loud, never degrade) *extends and partly reverses* the implicit bootstrap-only fail-safe, so it needs its own ADR. |
| Own capability claim: "`/hooks/deploy-status` cannot report redis" | Read `cat-deploy-state.sh` and the live payload key list — `services.{inngest_heartbeat,inngest_server,vector,inngest_journal_tail,vector_journal_tail}`, **no** `inngest_redis*` | **HOLDS** (`hr-verify-repo-capability-claim-before-assert`) |
| Own capability claim: "the fix can ship without `terraform apply`" | `infra-config-apply.sh:223` carries `CAT_DEPLOY_STATE_SH_B64\|/usr/local/bin/cat-deploy-state.sh\|755\|root:root`; `infra-config-install.sh` `DEST_SPEC` line 64 allowlists that dest | **HOLDS** |

---

## Evidence Ledger

Every row was pulled by this planning session from the observability layer. No operator action, no dashboard eyeballing (`hr-no-dashboard-eyeball-pull-data-yourself`), no host login.

| # | Fact | Source (layer + citation) |
|---|---|---|
| **E1** | Last healthy probe **2026-08-05 04:28:50 UTC**: `Inngest healthy on attempt 1/3: functions=68`. Host-side corroboration: `liveness: functions=68 durability=durable mode=liveness_only`. | GH Actions run `30975240263`; Better Stack source 2457081, `SYSLOG_IDENTIFIER=inngest-inventory` |
| **E2** | First failure **2026-08-05 06:34:07.877 UTC**, from the still-running inngest-server: `error scanning partition: could not peek global partitions: error peeking partition items: dial tcp 127.0.0.1:6379: connect: connection refused` | Better Stack, `SYSLOG_IDENTIFIER=doppler` (inngest-server's rows wear the `doppler` tag — its `ExecStart` is `doppler run …`) |
| **E3** | `inngest-redis.service: Failed with result 'exit-code'.` — first row **06:34:09.668**, then every ~5.0-5.5 s continuously through 22:04 (10,239 systemd rows matching `redis` in 3 days). | Better Stack, `UNIT=inngest-redis.service`, `SYSLOG_IDENTIFIER=systemd`, `_SYSTEMD_UNIT=init.scope`, `PRIORITY=4` |
| **E4** | inngest-server's crash-loop is a **pure consequence**: journal tail live at 22:03 cycles `initialized database (postgres)` → `ran database migrations (postgres)` → `using external redis` → `error creating redis client: … connection refused`, ~9 s period. **Postgres is healthy.** | `GET /hooks/deploy-status` → `.services.inngest_journal_tail` |
| **E5** | Live host state 22:03 UTC: `host_id=hetzner-123931471`, `component=inngest`, `exit_code=1`, `reason=inngest_health_failed`, `services.inngest_server="activating"`, `services.vector="active"`, `services.inngest_heartbeat="inactive"`, `oom_journal_tail=""` (**no kernel OOM kill**), `journald_storage.root_avail="52G"`. | `/hooks/deploy-status` |
| **E6** | **No reboot.** Single `_BOOT_ID=8c86d4135e0346de9c73dabec64c096e` spanning `2026-08-02 22:08:03` → `2026-08-05 22:07:59` (320,971 rows). Not a boot, host replace, or volume re-attach. | Better Stack, `GROUP BY _BOOT_ID` over hot+archive |
| **E7** | Over 3 days, `SYSLOG_IDENTIFIER='inngest-redis'` returns **0 rows**, while sibling Source-4 tags on the same host in the same window return `ci-deploy`=242, `inngest-inventory`=174, `infra-config-apply`=164, `infra-config-install`=76, `luks-monitor`=7. `inngest-heartbeat`=**0** as well. **Interpretation is bounded:** the sink and those tags are live; this does **not** establish that web-1's *running* `vector.toml` carries the `inngest-redis` entry (see E8). | Better Stack, `GROUP BY SYSLOG_IDENTIFIER` over hot+archive UNION |
| **E8** | The repo's `inngest-redis.service:26` carries `SyslogIdentifier=inngest-redis`, and `vector.toml` Source 4 allowlists that tag. **But `vector.toml` is baked into the OCI bootstrap image and is NOT in `infra-config-apply.sh` `FILE_MAP`** — so web-1's running config may predate the pairing, and E7's zero may be a shipper artifact rather than redis silence. Both readings stay open; **only a local `journalctl` settles it**, which is exactly what Phase 1 reads. | `apps/web-platform/infra/inngest-redis.service:26`; `vector.toml` Source 4; `infra-config-apply.sh` `FILE_MAP` |
| **E9** | Disk is not the cause. `luks-monitor` at `07:23:58`: `SOLEUR_WORKSPACES_READYZ ready=true writable=true populated=true workspace_count=8 expected=8 capacity=use=6%,mount=rw`; `OK: /mnt/data is LUKS-backed (device_type=crypto_LUKS mount_source=/dev/mapper/workspaces escrow=ok header=readable)`. | Better Stack, `SYSLOG_IDENTIFIER=luks-monitor` |
| **E10** | The LUKS cutover is not the trigger. `/mnt/data` was already `crypto_LUKS` at `2026-08-04 12:11:34` and `13:23:08`, while Redis was healthy through 08-05 04:28 (E1). | Better Stack, `luks-monitor` ASC |
| **E11** | `INNGEST_REDIS_PASSWORD` present in Doppler `soleur/prd`, 48 chars. **This does NOT establish that the value reached the unit's environment** — that step is unobserved, and it is precisely where H5/H7 live. | `doppler secrets get … -p soleur -c prd` |
| **E12** | The restart lever works and reported honestly: `ci-deploy` at `07:18:28` → `ACCEPTED: restart inngest`, then `INNGEST_HEALTH: attempt 1..10/10 — connection failed or empty response`, `INNGEST_HEALTH: healthy=false after 10 attempts`. A restart cannot conjure a Redis. | Better Stack, `SYSLOG_IDENTIFIER=ci-deploy`; GH run `30984479189` (`failure`) |
| **E13** | The watchdog surfaces **no host state at all**. `grep -n "journalctl\|systemctl status\|systemctl show\|is-active"` over `scheduled-inngest-health.yml`, `restart-inngest-server.yml`, `inngest-liveness-classify.sh`, `inngest-restart-age-gate.sh` → **zero matches**. Its "RESTARTS EXHAUSTED" comment prints a hard-coded guess: *"likely a lost `inngest-redis.service`… or a config regression."* | `.github/workflows/scheduled-inngest-health.yml` |
| **E14** | `/hooks/deploy-status` already returns `services.inngest_server`, `services.inngest_journal_tail`, `services.vector_journal_tail` — and **no** `inngest_redis` field. The decisive evidence for inngest-server sat one already-authenticated GET away and the watchdog never fetched it. | `apps/web-platform/infra/cat-deploy-state.sh:372-467`; live payload |
| **E15** | `durability_state` **flaps**: three probes 8 s apart at 07:17 reported `degraded`, `degraded`, `durable`. `derive_durability_state` samples `systemctl is-active inngest-redis.service` on a unit oscillating every 5 s — a coin flip, not a verdict. | Better Stack, `SOLEUR_INNGEST_LIVENESS_VERDICT` at `07:17:38`, `07:17:47`, `07:17:54` |
| **E16** | `inngest-redis.service` is the **only** Doppler-consuming unit on web-1 with **no** `soleur-doppler-token` drop-in. `FILE_MAP` delivers exactly `vector.service.d/`, `inngest-heartbeat.service.d/`, `inngest-server.service.d/`. Redis resolves its token solely from `EnvironmentFile=/etc/default/inngest-server` — the grep-extracted copy that `10-inngest-server-doppler-token.conf`'s own header calls pinned forever and self-healing never. Its `ExecStart` runs `doppler run --config prd` **unconditionally**, with no `[ -n "$DOPPLER_TOKEN" ]` gate, under `Restart=on-failure`/`RestartSec=5`. | `apps/web-platform/infra/infra-config-apply.sh` `FILE_MAP`; `apps/web-platform/infra/inngest-redis.service:26,31`; `apps/web-platform/infra/10-inngest-server-doppler-token.conf:3-23` |
| **E17** | Timeline consistent with E16: **#7241** ("per-config Doppler read tokens restore the token-drift scan to 13 of 13") merged **2026-08-04 16:18 UTC**; onset **2026-08-05 06:34 UTC**. A config-scoped token errors `rc=1` on a wrong `-c`, and redis hardcodes `--config prd`. Also explains the exact 5 s period: `RestartSec=5` against systemd's default `StartLimitIntervalSec=10s`/`StartLimitBurst=5` **never latches `failed`** — it loops forever. | `git log --format='%h %cI %s'`; systemd defaults; E3 |
| **E18** | Adjacent, **pre-existing**, out of scope: the app container logged `[Inngest] error - TypeError: fetch failed` / `connect ECONNREFUSED 10.0.1.40:8288` at 06:32 — **before** this outage began. That is the dedicated host never binding :8288, tracked by **#7228** / **#7230**. | Better Stack, `CONTAINER_NAME=soleur-web-platform` |

### Retention & channel discipline

Better Stack retention on source 2457081 is **3 days** (`knowledge-base/engineering/operations/runbooks/betterstack-log-query.md:85`); `remote()` alone is a **~40-minute hot window**. Every query above used the `remote() UNION ALL s3Cluster(primary, …_s3)` archive arm, so the incident (≈15 h before the query) is fully inside retention. E7's zero is therefore not a retention artifact — but per E8 it is also not proof about redis, and the plan does not treat it as such.

---

## Hypotheses — why does `redis-server` exit non-zero?

**Every row is UNKNOWN.** The deciding datum is redis's own local journal, and no remote surface exposes it. Rows record what each hypothesis *predicts*, so Phase 1's single payload adjudicates all seven at once.

| ID | Hypothesis | Status | Discriminator Phase 1 surfaces |
|---|---|---|---|
| **H7** | **Dead/rotated Doppler token, reaching only redis.** Redis is the one Doppler consumer without the `soleur-doppler-token` drop-in (E16), so it still resolves the pinned copy in `/etc/default/inngest-server` while inngest-server's drop-in overrides it. `doppler run` exits non-zero → `Restart=on-failure` loops at 5 s forever without latching `failed` (E17). Explains every measured fact with no new mechanism, and explains why **only** redis broke. | **UNKNOWN (leading)** | `inngest_redis_journal_tail` containing a Doppler auth error (`Invalid Auth`, `Doppler Error`, rc=1); `ExecMainStatus`; whether the drop-in is present on-host |
| **H1** | AOF / `appendonlydir` corruption — every restart re-reads the same bad file, so restarts are structurally useless. Fits "restart-invariant for 15 h." | **UNKNOWN** | `Bad file format reading the append only file` / `Unrecoverable error reading the append only file` in the tail |
| **H2** | Memory: `MemoryMax=384M` vs `maxmemory 256mb`; AOF load or an `auto-aof-rewrite` fork exceeded the cgroup cap. `oom_journal_tail` is empty (E5) so a *kernel* OOM kill is unlikely, but redis's own `Out Of Memory allocating …` → `exit(1)` presents as `exit-code`. | **UNKNOWN** | `Out Of Memory` in the tail; `MemoryPeak` from `systemctl show` |
| **H3** | `/mnt/data/redis` missing or re-owned (needs `deploy:deploy`, `ReadWritePaths=/mnt/data/redis`). `/mnt/data` is healthy and was already LUKS-backed while redis worked (E9/E10) — but a later sweep could have removed or re-owned the subtree. | **UNKNOWN** | `/mnt/data/redis` presence + `stat` owner/mode; `Can't chdir to '/mnt/data/redis'` in the tail |
| **H4** | Package churn — an unattended `apt` upgrade of `redis-server` near 06:34 (plausible at that hour with **no reboot**, E6) replaced the binary, unmasked the distro unit, or changed a directive's arity. | **UNKNOWN** | `redis-server --version`; `Bad directive or wrong number of arguments` in the tail |
| **H5** | Empty `--requirepass` — if `$INNGEST_REDIS_PASSWORD` expanded empty, `redis-server … --requirepass` with no value fails to parse. A downstream consequence of H7 if the token is dead. | **UNKNOWN** | `wrong number of arguments` in the tail; a **length-only** env-presence field |
| **H6** | Port 6379 already bound by a stray/unmasked distro `redis-server`. `inngest-redis-bootstrap.sh` masks the distro unit at install time only; nothing re-asserts it. | **UNKNOWN** | `Could not create server TCP listening socket 127.0.0.1:6379: bind: Address already in use`; `systemctl is-enabled redis-server` |

**What is REFUTED, and by what evidence:** re-staging absent Redis assets (the unit exists and executes — § Premise Validation); the workspaces LUKS cutover (E10); disk exhaustion (E9); reboot / host replace / volume re-attach (E6); kernel OOM kill (E5); the Inngest RLS lockdown apply (it ran at 06:40, **6 minutes after** onset, and its own `postgres-liveness PASS: owner can read public.events` gate passed — GH run `30982160385`).

**Explicitly NOT refuted:** "the Doppler secret exists" (E11) refutes *nothing* about whether the value reached the process. That inference error is what § Consult Corrections corrects.

---

## Research Reconciliation — issue body / runbook vs codebase reality

| Claim | Reality | Plan response |
|---|---|---|
| "`inngest-redis.service` **missing** → crash-loop" | The unit is present and executing; systemd restarts it every 5 s (E3). "Missing" reads `Unit not found`, not `Failed with result 'exit-code'`. | Phase 4 rewrites the watchdog comment to state measured unit state instead of asserting a cause it cannot see. |
| "the deploy must re-stage the redis assets" | The bootstrap's asset gate (`inngest-bootstrap.sh:633`) already passed — the unit exists. | Dropped as a diagnosis; survives only as a Phase 6 fallback. |
| "OR roll the ExecStart back to SQLite-only" | Would have masked this regression for 15 h while silently dropping Redis-resident armed reminders. | **Rejected**; Phase 3 is detect-and-fail-loud instead, recorded in the ADR. |
| Runbook cites #5542 as this failure's pattern | #5542 is a cutover reminder-preservation bug. The runbook has **no** Redis-down procedure — `grep '^##'` shows `§ Durable backend` documents design and cutover only. | Phase 5 adds a real Redis-down section and corrects the cross-reference to #7286. |
| Runbook is the operator's no-SSH entry point | It carries **7** host-login instructions (lines **84, 89, 93, 184, 260, 338, 378**) plus a `### Last-resort (host login)` heading at **179**. Line 184 is literally this failure's instruction — read inngest-server's journal by logging into the box. | Violates `hr-no-ssh-fallback-in-runbooks`. Phase 5 deletes all 7 and the heading, replacing each with a `/hooks/deploy-status` recipe. **No delivery dependency — ships in the Phase-1 PR.** |
| `hetzner-123931471` is "the Inngest host" | It is **web-1 / `soleur-web-platform`**, the co-located arm (`scripts/cutover-inngest.sh:642`: *"server id 123931471 = soleur-web-platform"*; Better Stack rows carry `host_name=soleur-web-platform`). The dedicated `soleur-inngest` node is `10.0.1.40` and is separately ECONNREFUSED (E18). | Scope every fix to **web-1**. Do not touch the dedicated-host cutover; #7228/#7230 own it. |
| A prod host config change goes through an immutable redeploy | True, and two no-SSH immutable levers exist: `/hooks/infra-config` (allowlisted `DEST_SPEC`) and `deploy-inngest-image.yml` (digest-pinned OCI → re-stage → re-bootstrap). `cat-deploy-state.sh` is already in the allowlist (`infra-config-apply.sh:223`; `infra-config-install.sh` `DEST_SPEC:64`). | Phase 1 rides `/hooks/infra-config`. No TF apply, no host replace, no SSH. |
| `terraform apply` is available | **It is not.** #7273: `web-platform` TF apply has failed on **every** merge since 2026-08-03 (`doppler_service_account.token_drift` unapplyable on UPDATE). | **Hard constraint.** No phase may depend on it; AC9 enforces mechanically. |
| The infra-config channel activates what it delivers | Only since **2026-08-05 21:45** (#7298 granted the handler's `daemon-reload`). #7296 (verify activation) is open, and #7297 records that follow-through PASSing while its defect persists. | Phase 1.4 accepts on a **read-back of the new field**, never on the channel's own success code. |
| `/hooks/deploy-status` answers from the host we think it does | Not guaranteed. `scheduled-inngest-health.yml` documents (#6425) that with >1 tunnel connector the route answers from **whichever host CF's colo selects** — 16 h of false inngest-down alarms came from exactly that. | Every Phase-1/4 read **must** assert `.host_id == "hetzner-123931471"` before believing any field. AC11/AC13. |
| `vector.toml` is deliverable via infra-config | **No** — it is baked into the OCI image and is absent from `FILE_MAP`. | Any Vector allowlist change requires a bootstrap-image release, not an infra-config push. Sequenced accordingly (Phase 6), and Phase 1 deliberately does not depend on it. |

---

## User-Brand Impact

**If this lands broken, the user experiences:** every scheduled and event-driven background job silently stops. For a Soleur operator: inbound-email triage never dispatches, `cron/*` workflows (roadmap review, daily triage, drift alerts, content generation) never fire, `step.sleep` reminders never wake, and the Command Center accepts input and produces nothing. There is no user-visible error — the app answers 200 while the work never happens. That is the current 15-hour outage.

**If this leaks, the user's data is exposed via:** the new `inngest_redis_journal_tail` field on `/hooks/deploy-status`. Redis log lines can echo config directives, and `inngest-redis.service`'s `ExecStart` interpolates `$INNGEST_REDIS_PASSWORD`; a Doppler auth error (H7) can echo token fragments. A naive dump could put the Redis password, a Doppler token, or queued job payloads into an HTTP response body. Mandatory mitigations: reuse `cat-deploy-state.sh`'s existing `service_journal_tail()` scrubber **verbatim** (never a fresh regex), extend its ban-list with `requirepass`, `redis://` credential forms, and `dp.` token prefixes, cap the tail at the existing byte budget, keep the endpoint behind its existing HMAC + Cloudflare Access gate, and emit **length only, never value** for any secret-presence field.

**Brand-survival threshold:** `single-user incident`. One operator losing their entire background-job substrate for 15 hours with no actionable signal is the incident, and it already happened.

**CPO sign-off required at plan time before `/work` begins.** No brainstorm ran (one-shot path), so there is no carry-forward. `user-impact-reviewer` is invoked at review time per `plugins/soleur/skills/review/SKILL.md`.

---

## Implementation Phases

### Phase 0 — Preconditions (verify, do not assume)

0.1 Confirm the outage is live and confirm **which host answered**: `GET /hooks/deploy-status`, assert `.host_id == "hetzner-123931471"`, then `services.inngest_server != "active"` and the journal tail still showing the Redis refusal. If it self-healed, re-scope: Phases 1/3/4/5 still ship (the blind channel is the durable defect); Phase 6 becomes moot.
0.2 Read the delivery chain end-to-end: `infra-config-apply.sh` (`FILE_MAP`, `RESTART_MAP`, **and the #4804 chicken-and-egg note at `:399`** — adding a new `FILE_MAP` member in the same push as the handler that must deliver it is a known freeze), `infra-config-install.sh` (`DEST_SPEC`), `hooks.json.tmpl` (`infra-config` + `deploy-status`).
0.3 Read `cat-deploy-state.sh` in full — `service_status()` (`:71`), `service_journal_tail()` (`:91`) and its scrubber (`:98-102`), and the JSON assembly (`:460-470`). New fields join the **existing** `jq` object, not a second one.
0.4 Read `10-inngest-server-doppler-token.conf` and `10-inngest-heartbeat-doppler-token.conf` in full. The heartbeat drop-in already states the invariant Phase 3 will enforce: *no secret may be copied into a second host file without the copy inheriting the original's re-delivery path.*
0.5 Baseline the suites: `bash apps/web-platform/infra/cat-deploy-state.test.sh`, `bash apps/web-platform/test/infra/vector-pii-scrub.test.sh`, `bash apps/web-platform/infra/infra-config-install.test.sh`, `bash apps/web-platform/infra/journald-config.test.sh`.
0.6 Re-derive the next free ADR ordinal against freshly-fetched `origin/main` (`ADR-169` is provisional; `ADR-168` is the highest at plan time and siblings claim ordinals mid-pipeline).

0.7 **BLOCKING PROBE — does the scoped apply survive #7273?** Every phase's delivery runs through `terraform apply -target=terraform_data.deploy_pipeline_fix`. If #7273 blocks it, this plan has **no delivery path at all** and needs a different spine, so this is established empirically before anything is built on it. Run a **plan-only, no-apply** probe:

```bash
cd apps/web-platform/infra
export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
terraform init -input=false
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform plan -target=terraform_data.deploy_pipeline_fix -input=false
```

**Expected:** a clean plan whose resource set excludes `doppler_service_account.token_drift` (`-target` selects a resource and its **dependencies, never its dependents** — `token-drift-read-tokens.tf:79`). **If the plan errors or the target graph pulls in `token_drift`, STOP** — Phase 1 cannot deliver, and the fallback spine is a bootstrap-image release (`deploy-inngest-image.yml`), which reaches `inngest-redis.service`/`vector.toml` but **not** `cat-deploy-state.sh` or the drop-in. Record the verdict verbatim in the PR body; do not proceed on a reasoned expectation.

0.8 Capture the AC2 baseline that Phase 0.5 does not: `grep -c 'journalctl' apps/web-platform/infra/cat-deploy-state.sh` (AC2 compares against this number, and 0.5 baselines test suites only).

### Phase 1 — Make `inngest-redis` self-report, and carry one inert-if-unneeded fix (SHIPS FIRST)

**Why probe-first, and why not probe-only.** Probe-first is not caution: `journalctl` reads the **local** journal and so bypasses the vector → Better Stack pipeline, which is itself a suspect (E8). That makes Phase 1 the only read that can settle the question. But probe-*only* would spend a full delivery cycle on a channel whose activation is unverified (#7296/#7297/#7298) at hour 15+ of a user-facing outage, and possibly learn nothing. So Phase 1 also carries the H7 fix, which is bounded, inert if unneeded, and rides the same allowlist.

**Stated tradeoff:** probe-then-fix buys certainty about *which* cause it is, at the cost of one more cycle through an unverified channel during an active outage. Probe-**and**-fix risks a null fix if the cause is not credential — and loses nothing, because the probe lands in the same push and tells us either way.

1.1 **Extend `apps/web-platform/infra/cat-deploy-state.sh`** with a `services.inngest_redis*` group mirroring the existing inngest-server fields:
  - `inngest_redis` — `service_status inngest-redis.service`
  - `inngest_redis_journal_tail` — `service_journal_tail inngest-redis.service` (**reuses the existing scrubber**)
  - `inngest_redis_result` — `systemctl show --value -p Result,ExecMainStatus,ExecMainCode,NRestarts,MemoryPeak,ExecMainStartTimestamp,ActiveEnterTimestamp inngest-redis.service`, joined compactly. **`NRestarts` + the two timestamps are load-bearing**: on a 5 s loop `is-active` is a coin flip, and only these distinguish "still looping" from "recently fixed."
  - `inngest_redis_dropin` — **`systemctl show -p DropInPaths,EnvironmentFiles inngest-redis.service`**, i.e. what systemd actually **LOADED**, emitting basenames only (never drop-in content — the shape gate legitimately permits `Environment=`, so echoing content would put an env value in the response body). **A filesystem-presence check here would be a false green** and was the plan's first-draft spec: after Phase 1.2 the file is on disk whether or not `daemon-reload` merged it, so "fix landed and working" and "fix landed inert" would be byte-identical. `DropInPaths` is the only version of this field that adjudicates **H7** rather than restating the push. (Precedent: `apply-deploy-pipeline-fix.yml:743` already asserts `DropInPaths` preconditions.)
  - `inngest_redis_credfile` — presence + mtime + **byte length (never value)** of `/etc/default/soleur-doppler-token`. Load-bearing for **H7**: the `-` prefix makes the drop-in *silently inert* when this file is absent, so without this field "fix delivered" and "fix delivered inert" are indistinguishable. Also adjudicates whether the shared credential is itself stale (its writer is the same `terraform apply` path — see § Infrastructure).
  - `inngest_redis_datadir` — `/mnt/data/redis` presence + `stat -c '%U:%G %a'` + `df` used-percent for `/mnt/data` (**H3**). `lstat` and refuse symlinks before any read — a list-then-read on an HTTP surface is a file-disclosure primitive.
  - `inngest_redis_binary` — version + distro-unit state (**H4**, **H6**). Use the **absolute** `/usr/bin/redis-server` (matching `inngest-redis.service:31`), not a `PATH` lookup, wrapped in `timeout 5`; `systemctl is-enabled redis-server` exits non-zero when masked/disabled, so it needs `|| true` under the file's `set -euo pipefail`.
  - `inngest_redis_tail_status` — enum `ok | empty | no-journalctl | unit-unknown`. `service_journal_tail()` collapses four distinct states to the same empty string; without this, an empty tail is an unreachable error path and § Risks 2's mitigation is uncheckable.
  - `vector_config_identity` — sha256 + mtime of `/etc/vector/vector.toml`. Settles E8 (**"shipper artifact vs redis silence"**) **from the payload** instead of by inference, and decides whether Phase 6.6 is needed at all.

  **`inngest_redis_secret_len` is DROPPED** (it was in the first draft). Two independent reviews established it is unobtainable as specified and unsafe in every implementation: `doppler run` materialises `INNGEST_REDIS_PASSWORD` inside the process at exec time, so systemd never holds it (`systemctl show -p Environment` reports configured `Environment=`, never `EnvironmentFile` contents or a child's runtime env), and the unit is dead ~100% of the time on a 5 s loop. The only implementations are (a) running `doppler run … printenv` from `cat-deploy-state.sh` — converting a documented read-only reporter into a credential-fetching vendor client with unbounded latency on the one endpoint this plan depends on, whose own stderr is the token-echoing text of H7; or (b) reading `/proc/<pid>/environ` of a PID that changes every 5 s, where any slip prints the value. It also buys nothing: H5 is a downstream consequence of H7, already adjudicated by `inngest_redis_dropin` + `inngest_redis_credfile` + the tail's `wrong number of arguments` marker.

  **Scrubber: EXTEND the shared one, do not add a second, and do not reuse it unchanged.** An earlier draft said "reuse verbatim" in two places while § User-Brand Impact said "extend the ban-list" — a contradiction an implementer resolves in favour of the literal instruction, shipping the unextended scrubber. The resolution is: **extend `service_journal_tail()`'s sed stage at `cat-deploy-state.sh:104-105`** (line-oriented, so the new patterns must precede the `tr '\n' '|'` at `:106`), which correctly hardens all five existing tails too. It currently scrubs only `signkey-…` and the Better Stack heartbeat path token. Required additions: `requirepass\s+\S+`, `redis://[^@]*@`, `dp\.(st|sa|pt|ct)\.[A-Za-z0-9._-]+`, `AUTH\s+\S+`, `masterauth\s+\S+`. **This is load-bearing, not hygiene:** on a config-parse failure redis prints `*** FATAL CONFIG FILE ERROR *** … >>> 'requirepass <value>' … Bad directive or wrong number of arguments`, echoing the argument verbatim — and that is the predicted tail content for **two of seven hypotheses** (H4, H5). Note that Vector's `pii_scrub_string` already carries `requirepass\s+\S+` and a `scheme://user:pass@` rule, but that covers the **log-shipping** path only; the **HTTP response body** is a separate path with its own scrubber, and it is the one this plan newly exposes.

  Every field is enum/short-string per the `#5503` purity convention, and every one is best-effort: a missing `systemctl`/`redis-server` yields empty, never a non-zero exit. **`systemctl show` parsing: drop `--value` and parse `KEY=VALUE` by key** — with `--value`, systemd returns properties in its own canonical order (not the caller's) and emits a blank line for an unsupported property (`MemoryPeak` needs systemd ≥ 253), so a positional parse misaligns silently.

  **Also add `"include-command-output-in-response-on-error": true` to the `deploy-status` hook** (`hooks.json.tmpl:116-119`). It is currently the only hook of six without it — `inngest-liveness`, `inngest-inventory`, and three siblings all have it, and `inngest-liveness`'s own `__comment` explains why. Without it, if the newly-extended `cat-deploy-state.sh` ever exits non-zero on prod, the sole in-surface channel answers with an **empty body** — in the same PR that deletes the runbook's last-resort host login.

1.2 **Carry the H7 fix: deliver `inngest-redis.service.d/10-inngest-redis-doppler-token.conf`.** Body is one stanza, mirroring the three siblings:

  ```ini
  [Service]
  EnvironmentFile=-/etc/default/soleur-doppler-token
  ```

  The `-` prefix makes it **inert** until `/etc/default/soleur-doppler-token` exists, and systemd merges drop-ins after the unit body so a live credential file wins over the pinned copy. It cannot make anything worse.

  **The delivery chain is SEVEN surfaces, not two — and its trigger is a scoped `terraform apply`.** The plan's first draft named only `FILE_MAP` + `DEST_SPEC`, which would have written two entries and delivered nothing. Verified live against the real files (the "hidden bridge" class, `knowledge-base/project/learnings/best-practices/2026-06-18-infra-config-delivery-chain-has-a-hidden-bridge-surface-and-count-blast-radius.md`):

  | # | Surface | File | Entry to add |
  |---|---|---|---|
  | 1 | The file itself | `apps/web-platform/infra/10-inngest-redis-doppler-token.conf` | new file |
  | 2 | **CI payload producer** | `apps/web-platform/infra/push-infra-config.sh:96` | `"inngest_redis_doppler_token_conf_b64": "$(base64 -w0 < "${INFRA_DIR}/10-inngest-redis-doppler-token.conf")"` |
  | 3 | **`pass-file-to-command` bridge** | `apps/web-platform/infra/hooks.json.tmpl` (`infra-config` hook) | `{ "source": "payload", "name": "inngest_redis_doppler_token_conf_b64", "envname": "INNGEST_REDIS_DOPPLER_TOKEN_CONF_B64", "base64decode": true }` |
  | 4 | Handler `FILE_MAP` | `apps/web-platform/infra/infra-config-apply.sh` (after `:252`) | `"INNGEST_REDIS_DOPPLER_TOKEN_CONF_B64\|/etc/systemd/system/inngest-redis.service.d/10-inngest-redis-doppler-token.conf\|644\|root:root"` |
  | 5 | Installer `DEST_SPEC` | `apps/web-platform/infra/infra-config-install.sh` (after `:84`) | `["/etc/systemd/system/inngest-redis.service.d/10-inngest-redis-doppler-token.conf"]="644 root:root"` |
  | 6 | **`server.tf` `triggers_replace`** | `apps/web-platform/infra/server.tf:1554-1556` | `file("${path.module}/10-inngest-redis-doppler-token.conf")` — its own comment: *"registering them here is what makes a body-only edit re-fire the push and actually reach the host"* |
  | 7 | **Auto-apply `paths:` filter** | `.github/workflows/apply-deploy-pipeline-fix.yml:65+` | `- "apps/web-platform/infra/10-inngest-redis-doppler-token.conf"` (siblings `10-vector-…` and `10-inngest-heartbeat-…` are already listed) |

  Surfaces 2, 3, 6, 7 are what a `FILE_MAP`-only reading misses, and they are exactly where "delivered nothing while reporting success" comes from.

  **⚠ Correction to this plan's own earlier claim: the delivery mechanism IS a `terraform apply`.** `push-infra-config.sh` has exactly one caller — a `local-exec` provisioner on `terraform_data.deploy_pipeline_fix` (`server.tf:1567-1584`) — fired by `apply-deploy-pipeline-fix.yml:352`:

  ```
  terraform apply -target=terraform_data.deploy_pipeline_fix …
  ```

  An earlier draft of this plan asserted "no `.tf` edits, no `terraform apply`, enforced by AC9." **That was wrong**, and it is the same inference error as the H7 case: a true statement about the *unscoped* apply (#7273 blocks it) was over-generalised into a false statement about *all* applies. The corrected constraint is in § Infrastructure (IaC) and AC9.

  **Why the scoped apply is expected — but not assumed — to survive #7273:** `-target` selects a resource and its **DEPENDENCIES, never its DEPENDENTS** (stated in-repo at `token-drift-read-tokens.tf:79`). `terraform_data.deploy_pipeline_fix`'s dependency set is the webhook secret, the CF Access vars, the app domain, `local.hooks_json`, and the Doppler token env — `doppler_service_account.token_drift` (#7273's blocker) is not among them. That is a *hypothesis about the graph*, not a measurement. **Phase 0.7 probes it before anything is built on it.**

  **Consequence: Phase 1.2 requires TWO pushes, and the FIRST will legitimately report `exit_code=1`.** This is the #4804 chicken-and-egg, and the handler documents it verbatim at `infra-config-apply.sh:396-404`:

  > *"the chicken-and-egg freeze (#4804): when a new file was added to FILE_MAP + hooks.json env-passing atomically, the host's stale hooks.json could not pass the new key, leaving its env var empty… Per-file accounting lets the remaining good files (crucially the new hooks.json) land while the absent one is recorded as a failure and surfaces a loud exit_code=1 to the CI verify gate."*

  `hooks.json` is itself delivered through this channel (`hooks_json_b64` → `/etc/webhook/hooks.json`), so **push 1** lands the new `hooks.json` (with the surface-3 bridge) and records the drop-in as `missing_env`; **push 2**, against the now-current `hooks.json`, delivers the drop-in. `/work` MUST NOT read push 1's `exit_code=1` as a broken channel and pivot — it is the designed behavior. Verify by field, not by exit code: `services.inngest_redis_dropin` is absent after push 1 and present after push 2.

  **Shape gate: VERIFIED, not assumed.** `infra-config-install.sh:248-250` gates by **dest pattern**, not by an enumerated dest list:

  ```bash
  if [[ "$dest_canonical" == /etc/systemd/system/*.service.d/*.conf ]]; then
    dropin_bad_lines="$(grep -cvE '^[[:space:]]*($|#|;|\[Service\][[:space:]]*$|Environment=|EnvironmentFile=)' "$tmp" || true)"
    [[ "$dropin_bad_lines" == "0" ]] || reject "dropin_shape:bad_lines=$dropin_bad_lines"
  ```

  A **new** drop-in dest is therefore already covered — no gate change is needed, and the proposed body (`[Service]` + `EnvironmentFile=-…`) passes the allow-list. This discharges the `model.c4:456` invariant ("every content gate ships before the grant that makes its file class adoptable") for this file, rather than merely restating it.

  **No restart grant needed, but the activation chain is `daemon-reload`, not the restart loop.** systemd serves the *loaded* unit until a `daemon-reload`, so the crash-loop alone does **not** pick up a new drop-in. The chain is: `infra-config-install` writes the file → the handler runs `systemctl daemon-reload` (the grant #7298 added 2026-08-05 21:45; the sudoers alias carries `daemon-reload` alongside `try-restart`) → the unit's **next** 5 s restart loads the merged unit. So `RESTART_MAP` stays unextended (it currently carries only `vector.service`, `infra-config-apply.sh:309-311`) and the root-restart grant is not widened.

  **This is the plan's most important sequencing consequence, and it is a feature, not a risk:** if `daemon-reload` is still broken (#7296 is open and #7297 records that follow-through PASSing while its defect persists), the drop-in sits inert and Phase 1.2's fix silently does nothing — **while Phase 1.1's probe still lands and still answers the question**, because `cat-deploy-state.sh` is exec'd per-request by the webhook and needs no unit reload. Carrying both in one push is therefore strictly dominant: the diagnostic cannot be blocked by the same failure that could block the fix. AC12 (field read-back) and AC4' (drop-in present on-host, read from `inngest_redis_dropin`) fail independently, so the payload tells us *which* of the two landed.

1.3 **Delete the runbook's 7 host-login instructions** (lines 84, 89, 93, 184, 260, 338, 378) and the `### Last-resort (host login)` heading at 179, replacing each with the equivalent hook call. This has **zero delivery dependency** and closes an `hr-no-ssh-fallback-in-runbooks` violation, so it ships here rather than waiting on evidence. The *Redis triage procedure* is deliberately deferred to Phase 5 — writing procedure before Phase 1 returns is writing procedure against a guess.

1.4 **Deliver, then verify by read-back.** Merge → dispatch `/hooks/infra-config` → `GET /hooks/deploy-status`, assert `.host_id == "hetzner-123931471"` (the #6425 connector coin-flip makes this mandatory), then assert the new keys exist with non-placeholder values. **Delivery is not activation** (ADR-161/#7103; #7297 is a live example of a follow-through PASSing while its defect persists): the acceptance signal is the field in the payload, never the channel's report.

1.5 **Record the verdict.** Write the adjudicating payload excerpt into the PR body and resolve the § Hypotheses row. This artifact is what lets Phases 3-6 be chosen against evidence instead of a guess.

### Phase 1b — Escape hatch: what happens when Phase 1 adjudicates nothing

A plan whose only path forward is "the probe will tell us" deadlocks if the probe comes back benign. AC13 blocks Phase 6 arm selection on an unresolved hypothesis table, and Phase 6 is the only thing that can satisfy AC14-AC16 — so "all seven discriminators empty" is a **dead end with no owner and no timebox** unless it is named now.

**Trigger:** the Phase-1 payload returns `dropin` loaded, `credfile` present and fresh, `datadir` ok, `binary` ok, distro unit masked, tail **empty**, and `Result=exit-code ExecMainStatus=1` — i.e. redis exits 1 having printed nothing, and no hypothesis is named.

1b.1 **Timebox: one watchdog tick (≤15 min) after AC12 passes.** Do not iterate on the same instrument hoping for different output.
1b.2 **Next instrument, in order of cost:** (a) raise the tail depth and drop the PRIORITY floor — `journalctl -u inngest-redis.service -n 300 --output=verbose` surfaces `_EXIT_STATUS`/`EXIT_CODE` structured fields that `--output=cat` discards; (b) add `systemd-analyze verify inngest-redis.service`, which reports load-time errors a runtime tail never shows; (c) add a one-shot `ExecStartPre=/bin/sh -c 'exec 2>&1; …'` diagnostic wrapper delivered by bootstrap-image release, capturing the pre-exec environment shape (names only, never values).
1b.3 **Owner:** the same PR, not a follow-up issue. A deadlock discovered at hour 16 of a P1 does not get deferred.
1b.4 If 1b.2 also comes back empty, the honest disposition is a **loud UNKNOWN**: file the finding, keep the detector (Phase 3) which is valuable regardless, and escalate the availability decision explicitly rather than reaching for a silent SQLite fallback (§ Alternatives, ADR rejected-alternative (b)).

### Phase 2 — Watchdog attaches the evidence it already has

Today the `[ci/inngest-down]` issue carries a mode token, a 400-char truncated probe body, and a hard-coded guess (E13), while the unit's own journal sits one authenticated GET away (E14).

2.1 In `.github/workflows/scheduled-inngest-health.yml`, on the `inngest_down` / `inngest_unhealthy` path, call `/hooks/deploy-status` with the HMAC + CF-Access headers the workflow **already** holds (`WEBHOOK_DEPLOY_SECRET`, `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET` — the same secrets `restart-inngest-server.yml` uses), and fold `host_id`, `services.inngest_server`, `services.inngest_redis`, `services.inngest_redis_result`, `services.inngest_redis_dropin`, and bounded tails of both journals into the issue body/comment inside a `<details>` block.
2.2 Delete the unconditional hypothesis sentence. A guess printed as prose is worse than silence — it anchors the next responder on the wrong branch, which is exactly what happened here.
2.3 Degrade safely **and keep the body**: `curl -o /tmp/deploy-status-body -w '%{http_code}'`; on non-2xx, `cat` the body, run it through the workflow's existing `strip_log_injection`, and echo the CR/LF-stripped head into **both** the issue comment and an `::error::`. Do not print only `deploy-status unreachable: HTTP <code>` — on a 403 (HMAC/CF-Access drift) versus a 500 (script fault) the body is the only thing that says which, and discarding it is the #5492 class. This also matches the pattern already in the same file at `scheduled-inngest-health.yml:95-102`. The evidence fetch must never convert a page into a workflow failure.
2.4 **Gate on the field existing.** Phase 2 hard-depends on Phase 1 being **landed and activated**, not merely merged. Reading `services.inngest_redis` before the field exists on-host replaces a wrong hypothesis with an empty one — a regression in signal quality. Emit an explicit fallback string when the key is absent.
2.5 De-flap `durability_state` (E15): `derive_durability_state` in `inngest-inventory.sh` must not read one instantaneous `is-active` on a unit restarting every 5 s. Report the systemd `Result` + `NRestarts` alongside, or sample twice. A signal that answers `degraded, degraded, durable` in 16 seconds is not a signal.

### Phase 3 — Structural: detect and fail loud, never degrade silently

The `#5542`/`#5547` SQLite fail-safe exists **only at bootstrap time** (`REDIS_READY`, `inngest-bootstrap.sh:843-851`). There is no runtime arm, so a Redis that dies later wedges inngest-server forever, and `verify_inngest_health` (`ci-deploy.sh:2205`) correctly **fails the deploy** rather than degrading — so even the redeploy path cannot recover it.

The first draft proposed a runtime SQLite fallback. **That is rejected** (§ Consult Corrections): it would have masked this credential regression for 15 h while silently dropping armed reminders, converting a diagnosable crash-loop into an undiagnosable data-loss event. The invariant to establish instead:

> **A Redis outage under Inngest is DETECTED within minutes and FAILS LOUD. It is never silently degraded to SQLite, and never left indefinitely wedged without an alarm naming the cause.**

3.1 **Detector, not degraded arm.** The runtime "arm" is Phase 1's field plus a watchdog assertion on it (Phase 2) — redis-down becomes visible within one `*/15` tick with its reason attached. No `ExecStart` rewriting.
3.2 **Close the class with an invariant test**, not just this instance. The invariant is already written in `10-inngest-heartbeat-doppler-token.conf` and simply unenforced: *no secret may be copied into a second host file without the copy inheriting the original's re-delivery path.* Add an assertion (≈20 lines, in `apps/web-platform/infra/inngest.test.sh` or the nearest registered suite): **every unit carrying `EnvironmentFile=/etc/default/inngest-server` must have a matching drop-in in `infra-config-apply.sh` `FILE_MAP`.** `inngest-redis.service` is the standing violation; the test fails today and passes after Phase 1.2. Prove it can fail before you make it pass.
3.3 **If a degrade arm is ever genuinely wanted**, its contract is fail-loud-and-refuse: reject new reminder scheduling with a user-visible error, never accept-and-drop. Record this as the ADR's constraint on any future degrade, not as work in this plan.
3.4 Guard the `StartLimitBurst` interaction: `RestartSec=5` against systemd's default `StartLimitIntervalSec=10s`/`StartLimitBurst=5` **never latches `failed`** (E17) — which is why this looped for 15 h instead of stopping. Any change to restart parameters must state which behavior it is choosing: loop-forever-and-alarm, or latch-failed-and-alarm. Silence on this point is how the current shape happened.

### Phase 4 — Watchdog message honesty (folds into Phase 2's PR)

4.1 Replace the "RESTARTS EXHAUSTED" guess with measured state, and cite **#7286** rather than #5542 as the Redis-crash-loop precedent (§ Premise Validation).
4.2 Keep the `ci/inngest-restart-exhausted` semantics unchanged — the age gate behaved correctly. It suppressed a restart that provably could not help (E12). The defect was never the gate; it was that exhaustion produced no evidence.

### Phase 5 — Runbook (evidence-shaped, after Phase 1 returns)

5.1 Add `## inngest-redis down / crash-looping (`[ci/inngest-down]` with Postgres healthy)` with this incident's measured signature: inngest-server logging `initialized database` then `error creating redis client: … connection refused`, plus `inngest-redis.service: Failed with result 'exit-code'` at a 5 s cadence with `NRestarts` climbing and no `failed` latch.
5.2 First triage step is the no-SSH `/hooks/deploy-status` curl (HMAC + CF-Access, creds from Doppler `prd_terraform`), **including the `.host_id` assertion** so a peer-connector answer is not mistaken for this host's state.
5.3 Add a decision table mapping each `inngest_redis_*` field pattern to its remedy — the H1..H7 discriminators become the operator's branch table.
5.4 Correct the #5542 cross-reference and document the Phase-3 invariant: what "detected and failing loud" means, what is at risk while Redis is down, and why there is deliberately no silent SQLite fallback.

### Phase 6 — Remedy + restore production (scope chosen by Phase 1's verdict)

Build only the arm Phase 1 names. Do not pre-build all of them.

6.1 **H7 (credential):** already delivered by Phase 1.2. Verification is Phase 6.5.
6.2 **H3 (data dir):** make `/mnt/data/redis` creation + `deploy:deploy 0750` idempotent on **every** bootstrap in `inngest-redis-bootstrap.sh`, not install-only. Delivered by a bootstrap-image release.
6.3 **H2 (memory):** adjust `MemoryMax` / `maxmemory` in `inngest-redis.service` / `inngest-redis.conf`. Bootstrap-image release.
6.4 **H4/H6 (package/port):** re-assert the distro-unit mask on every bootstrap; pin or verify the `redis-server` version. Bootstrap-image release.
6.5 **H1 (AOF corruption) — DEFERRED unless Phase 1 names the AOF.** A MOVE verb on the root-run allowlisted `ci-deploy.sh` surface is privileged-surface expansion for an unestablished cause. If Phase 1 does name it: add `repair inngest-redis` running `redis-check-aof --fix`, and on failure **move** the AOF directory to a timestamped path — **never `rm`**. Log the quarantine path and the reminder count enumerated beforehand. #5542's whole lesson is that armed reminders are irrecoverable once gone and invisible in Postgres.
6.6 **Vector channel (E8) — REWRITTEN; the first draft prescribed three edits that are wrong.** Verified against the live files: `vector.toml:220` **already** allowlists `"inngest-redis"`, `inngest-redis.service:26` already sets `SyslogIdentifier=inngest-redis`, and `journald-config.test.sh:286-295` already pins both sides. **The repo pairing is already correct**, so the two `vector.toml` / fixture rows in an earlier § Files to Edit were no-ops that read as coverage. Adding `"redis-server"` would be actively wrong on two counts: Source 4 matches `SYSLOG_IDENTIFIER` by **exact value**, so it would be a permanently-dead entry (`vector.toml`'s own #6617 comment names this exact anti-pattern — *"a permanently-dead no-op that reads like coverage"*), and it would **break CI**, because `vector-pii-scrub.test.sh` AC3 asserts set **equality** against an `EXPECTED_TAGS` that is *derived* by grepping `SyslogIdentifier=` out of `infra/*.service` — "add it to EXPECTED_TAGS" is not an available action.

  **Therefore the only possible defect is that web-1's image-baked `vector.toml` predates the pairing**, and the only remedy is a **bootstrap-image re-stage with ZERO repo edits** to `vector.toml`, the fixture, or `journald-config.test.sh`. `vector_config_identity` (Phase 1.1) decides whether even that is needed — the on-host sha256 either matches the repo file or it does not, settling E8 from the payload instead of by inference.

  Corroborating evidence that the running config differs from the repo file, noted here because it is independent of the above: E3's rows arrive with `SYSLOG_IDENTIFIER=systemd`, `_SYSTEMD_UNIT=init.scope`, `PRIORITY=4`, but the repo's Source 2 admits `PRIORITY 0-2` only and no source allowlists `systemd`. The running config is therefore already known to admit rows the repo config would drop.

  Credential scrubbing on this channel is **already covered upstream** — cite, do not re-add: `pii_scrub_string` carries a `requirepass\s+\S+` rule and a `scheme://user:pass@` DSN rule. That covers the log-shipping path; the HTTP-response path is separately covered by Phase 1.1's `cat-deploy-state.sh` scrubber extension.
6.7 **Verify against source-of-truth state, not a success code:**
  - `/hooks/deploy-status` → `.host_id == "hetzner-123931471"` **and** `services.inngest_redis == "active"` **and** `services.inngest_server == "active"` **and** `NRestarts` stable across two reads ≥60 s apart
  - `GET /hooks/inngest-liveness` → HTTP **200** with a **non-empty** functions array, `functions >= 68` (last-known-good, E1)
  - `SOLEUR_INNGEST_LIVENESS_VERDICT mode=healthy … durability=durable` in Better Stack, stable across **≥3 consecutive** `*/15` ticks (E15: one sample is a coin flip)
  - `[ci/inngest-down]` #7286 auto-closes on the watchdog's own healthy path
6.8 Enumerate armed reminders after recovery (`/hooks/inngest-enumerate-reminders`) and record the count in the PR body, so any loss is stated rather than discovered later.

---

## Files to Edit

| Path | Phase | Change |
|---|---|---|
| `apps/web-platform/infra/cat-deploy-state.sh` | 1.1 | Add the `services.inngest_redis*` field group to the existing `jq` object; reuse `service_journal_tail()`'s scrubber verbatim |
| `apps/web-platform/infra/cat-deploy-state.test.sh` | 1.1 | Assert each new key by name; scrubbing; missing-unit → empty + exit 0 |
| `apps/web-platform/infra/push-infra-config.sh` | 1.2 | **Surface 2** — payload key `inngest_redis_doppler_token_conf_b64` (after `:96`) |
| `apps/web-platform/infra/hooks.json.tmpl` | 1.2 | **Surface 3** — `pass-file-to-command` bridge entry on the `infra-config` hook |
| `apps/web-platform/infra/infra-config-apply.sh` | 1.2 | **Surface 4** — `FILE_MAP` entry (after `:252`); heed the #4804 note at `:396-404` |
| `apps/web-platform/infra/infra-config-install.sh` | 1.2 | **Surface 5** — lockstep `DEST_SPEC` entry for the same dest |
| `apps/web-platform/infra/infra-config-install.test.sh` | 1.2 | Pin the `FILE_MAP` ↔ `DEST_SPEC` pair |
| `apps/web-platform/infra/infra-config-apply.test.sh` | 1.2 | **Five-surface parity assertion** — every `FILE_MAP` env var has a matching `hooks.json.tmpl` bridge entry AND a `push-infra-config.sh` payload key. This is the test that would have caught the two-surface gap. |
| `knowledge-base/engineering/operations/runbooks/inngest-server.md` | 1.3, 5 | Delete 7 host-login instructions (84, 89, 93, 184, 260, 338, 378) + the heading at 179; then add the Redis-down section, decision table, and #5542 correction |
| `.github/workflows/scheduled-inngest-health.yml` | 2, 4 | Fetch `/hooks/deploy-status` on the down path; embed `host_id` + unit states + tails; delete the hard-coded hypothesis |
| `apps/web-platform/infra/inngest-inventory.sh` | 2.5 | De-flap `derive_durability_state`; report `Result` + `NRestarts` alongside `is-active` |
| `apps/web-platform/infra/inngest.test.sh` (or nearest registered suite) | 3.2 | Invariant: every unit with `EnvironmentFile=/etc/default/inngest-server` has a `FILE_MAP` drop-in |
| `apps/web-platform/infra/inngest-redis-bootstrap.sh` | 6.2/6.4 | Only if H3/H4/H6 selects it — idempotent datadir + mask re-assert |
| `apps/web-platform/infra/inngest-redis.service` | 6.3/6.4 | Only if H2/H4 selects it |
| `apps/web-platform/infra/inngest-redis.conf` | 6.3 | Only if H2 selects it |
| `apps/web-platform/infra/server.tf` | 1.2 | **Surface 6** — add `file("${path.module}/10-inngest-redis-doppler-token.conf")` to `terraform_data.deploy_pipeline_fix` `triggers_replace` (`:1554-1556`). **This is the only permitted `.tf` change** (AC9). |
| `.github/workflows/apply-deploy-pipeline-fix.yml` | 1.2 | **Surface 7** — add the drop-in to the `paths:` filter (`:65+`); parity is pinned by `ship-deploy-pipeline-fix-gate.test.ts` |
| `apps/web-platform/infra/hooks.json.tmpl` | 1.1, 1.2 | Surface 3 bridge entry **and** `"include-command-output-in-response-on-error": true` on the `deploy-status` hook (`:116-119` — the only hook of six lacking it) |
| `scripts/lint-infra-no-human-steps.py` | 1.3 | Extend the SSH pattern (`:93`, `:161`) with `\bssh\s+\S*@` — it currently cannot match `ssh root@`, so AC7's gate is toothless (see AC7) |
| ~~`apps/web-platform/infra/vector.toml`~~ | — | **REMOVED.** `:220` already allowlists `inngest-redis`; adding `redis-server` would be a dead exact-match entry AND break the derived-set-equality fixture. See Phase 6.6. |
| ~~`apps/web-platform/test/infra/vector-pii-scrub.test.sh`~~ | — | **REMOVED.** `EXPECTED_TAGS` is *derived* from `SyslogIdentifier=` in `infra/*.service`, not an editable list. |
| ~~`apps/web-platform/infra/journald-config.test.sh`~~ | — | **REMOVED.** `:286-295` already pins the redis unit↔allowlist join. |
| `apps/web-platform/infra/ci-deploy.sh` | 6.5 | **Deferred** — only if Phase 1 names the AOF |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | ADR | Correct two falsified descriptions (§ Architecture Decision) |

## Files to Create

| Path | Phase | Purpose |
|---|---|---|
| `apps/web-platform/infra/10-inngest-redis-doppler-token.conf` | 1.2 | The missing drop-in; `EnvironmentFile=-/etc/default/soleur-doppler-token` |
| `knowledge-base/engineering/architecture/decisions/ADR-169-inngest-redis-outage-detect-fail-loud.md` | 3 | Detect-and-fail-loud invariant (ordinal PROVISIONAL) |
| `scripts/followthroughs/inngest-redis-durable-7286.sh` | Observability | Soak probe for the ≥3-tick durability AC |
| `knowledge-base/project/specs/feat-one-shot-7286-inngest-down-restart-exhausted/tasks.md` | — | Task breakdown derived from this plan |

---

## Observability

```yaml
liveness_signal:
  what: "services.inngest_redis + services.inngest_redis_result.NRestarts + services.inngest_server on GET /hooks/deploy-status (host_id-asserted); SOLEUR_INNGEST_LIVENESS_VERDICT in Better Stack"
  cadence: "*/15 (scheduled-inngest-health.yml) + on demand"
  alert_target: "[ci/inngest-down] GitHub issue + Sentry cron check-in (both existing)"
  configured_in: ".github/workflows/scheduled-inngest-health.yml; apps/web-platform/infra/cat-deploy-state.sh"

error_reporting:
  destination: "GitHub issue body via /hooks/deploy-status (primary — bypasses the shipper, which is itself a suspect per E8); Better Stack Logs source 2457081 via Vector Source 4 (secondary, Phase 6.6)"
  fail_loud: true   # Phase 1 exists precisely because the current path fails silent

failure_modes:
  - mode: "inngest-redis exits non-zero (dead Doppler token / AOF corrupt / OOM / missing datadir / bad directive / port bound)"
    detection: "services.inngest_redis != active AND services.inngest_redis_journal_tail carries the reason AND services.inngest_redis_dropin says whether the credential drop-in is present — an IN-SURFACE read of the unit's own journal, not a host-side liveness inference. The structured fields discriminate ALL SEVEN hypotheses in ONE event: dropin→H7, tail-text→H1/H2/H4/H5/H6, datadir→H3."
    alert_route: "[ci/inngest-down] issue body (Phase 2)"
  - mode: "inngest-server wedged on an unreachable Redis"
    detection: "services.inngest_server == activating WITH services.inngest_redis != active — the pair discriminates 'redis is the cause' from 'inngest-server is the cause' in one event"
    alert_route: "same issue"
  - mode: "restart loop that never latches failed (the 15h shape)"
    detection: "SINGLE-READ decidable: ActiveEnterTimestamp within the last 60s AND NRestarts > 0 AND ActiveState != failed. Both fields ship in inngest_redis_result. (A two-read NRestarts delta was the first draft; nothing persists the prior value between */15 ticks, so it was a declared-observable that could not fire.)"
    alert_route: "[ci/inngest-down] issue body; the existing 45-min age gate already suppresses futile restarts"
  - mode: "H7 fix delivered but INERT (drop-in on disk, never loaded, or credential file absent)"
    detection: "inngest_redis_dropin (systemd's LOADED DropInPaths) empty while the file shipped, OR inngest_redis_credfile absent — the `-` prefix makes the drop-in silently inert, so disk-presence alone cannot distinguish working from no-op"
    alert_route: "AC12c fails independently of AC12; recorded in the PR body"
  - mode: "the diagnostic endpoint itself fails"
    detection: "GET /hooks/deploy-status non-2xx WITH a body (requires include-command-output-in-response-on-error on the deploy-status hook — currently the only hook of six lacking it)"
    alert_route: "watchdog echoes the sanitized body into the issue + ::error:: (Phase 2.3)"
  - mode: "the redis telemetry channel is dark (or the allowlist entry is not live on-host)"
    detection: "scripts/betterstack-assert-absence.sh --absence '<redis start marker>' --control SOLEUR_INNGEST_SERVER_PROBE — refuses to report clean without a positive control; unshipping(2) is distinct from clean(0)"
    alert_route: "follow-through probe; Phase 6.6 closes it if Phase 1 shows redis does emit"

logs:
  where: "Better Stack Logs source 2457081 (t520508_soleur_inngest_vector_prd_3_logs + _s3 archive); host journald /var/log/journal, read remotely via /hooks/deploy-status"
  retention: "3 days (Better Stack free tier); remote() hot window ~40 min — every query MUST include the s3Cluster archive arm"

discoverability_test:
  command: |
    eval "$(doppler secrets download -p soleur -c prd_terraform --no-file --format env | grep -E '^(WEBHOOK_DEPLOY_SECRET|CF_ACCESS_CLIENT_ID|CF_ACCESS_CLIENT_SECRET)=')"
    SIG=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_DEPLOY_SECRET" | sed 's/.*= //')
    curl -sS --max-time 40 -H "X-Signature-256: sha256=$SIG" \
      -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
      https://deploy.soleur.ai/hooks/deploy-status \
      | jq -e '.host_id == "hetzner-123931471"' >/dev/null && echo "host OK"
    # then:
    #   | jq '{inngest_server:.services.inngest_server, inngest_redis:.services.inngest_redis,
    #          result:.services.inngest_redis_result, dropin:.services.inngest_redis_dropin,
    #          datadir:.services.inngest_redis_datadir}'
  # MEASURED, not described (#7286 review). The first draft wrote a POSITIONAL shape
  # (`"success 0 0 <NRestarts> …"`) — exactly the form the implementation deliberately rejects,
  # because systemctl returns properties in its own canonical order and blanks unsupported ones.
  # Since this block is AC12's gate, an operator comparing against the described shape would
  # have seen a false mismatch on a correct payload. Captured from a real run:
  expected_output: |
    host OK; then:
    {
      "inngest_redis": "activating",
      "inngest_redis_result": "Result=exit-code ExecMainStatus=1 ExecMainCode=1 NRestarts=11704 MemoryPeak= ExecMainStartTimestamp=Wed 2026-08-05 22:39:35 UTC ActiveEnterTimestamp= LoadState=loaded ActiveState=activating SyslogIdentifier=inngest-redis",
      "inngest_redis_dropin": "10-inngest-redis-doppler-token.conf",
      "inngest_redis_credfile": "present mtime=<epoch> bytes=<n>",
      "inngest_redis_datadir": "present deploy:deploy 750 use=<pct>%",
      "inngest_redis_binary": "Redis server v=<ver> … distro_unit=masked",
      "inngest_redis_tail_status": "ok",
      "vector_config_identity": "redis_allowlisted=yes sha256=<64hex> mtime=<epoch>"
    }
    HEALTHY is: inngest_redis=active, ActiveState=active, NRestarts stable across two reads,
    redis_allowlisted=yes, SyslogIdentifier=inngest-redis.
```

### Soak Follow-Through Enrollment

Phase 6.7's AC — *`durability=durable` stable across ≥3 consecutive watchdog ticks* — is time-gated, so it enrols a follow-through rather than relying on memory:

- Script `scripts/followthroughs/inngest-redis-durable-7286.sh` — exit 0 only when the last 3 `SOLEUR_INNGEST_LIVENESS_VERDICT` rows all read `mode=healthy durability=durable`, `start=` pinned strictly after the remediation deploy. Mirror `scripts/followthroughs/reconcile-ff-only-sentry-4977.sh`.
- Tracker directive `<!-- soleur:followthrough script=scripts/followthroughs/inngest-redis-durable-7286.sh earliest=<deploy+1d> secrets=BETTERSTACK_QUERY_* -->` plus the `follow-through` label.
- No new `secrets=` wiring in `.github/workflows/scheduled-followthrough-sweeper.yml` — `BETTERSTACK_QUERY_*` is already carried. **Verify** rather than assume, per the sweeper's own contract.

---

## Infrastructure (IaC)

### Terraform changes

**None, by design.** #7273 has blocked `web-platform` `terraform apply` on every merge since 2026-08-03 (`doppler_service_account.token_drift` unapplyable on UPDATE), so any TF-dependent phase would be dead on arrival. If a `.tf` edit becomes unavoidable at `/work`, it must be inert-if-unapplied and split into a follow-up PR gated on #7273. AC9 enforces this mechanically.

### Apply path

**(b) idempotent delivery to a running host — no re-provision, no host login.** Two existing channels, chosen per file class:

| File class | Channel | Mechanism |
|---|---|---|
| `cat-deploy-state.sh`, the new `inngest-redis.service.d/` drop-in, `hooks.json`, `ci-deploy.sh` | `POST /hooks/infra-config` | `infra-config-apply.sh` `FILE_MAP` → `sudo infra-config-install` (payload on **stdin**, `DEST_SPEC`-allowlisted, atomic same-fs rename) |
| `inngest-redis.service`, `inngest-redis.conf`, `inngest-redis-bootstrap.sh`, `inngest-bootstrap.sh`, `vector.toml` | `deploy-inngest-image.yml` | tag → `build-inngest-bootstrap-image.yml` → digest-pinned OCI → `docker cp` re-stage → `inngest-bootstrap.sh` re-run |

Expected downtime: **none beyond the existing outage.** Blast radius is web-1's inngest arm only; the web-platform container is untouched by both channels. The drop-in needs no restart grant — the 5 s crash-loop picks it up on its next cycle.

### Distinctness / drift safeguards

- `hcloud_server.web` carries `lifecycle { ignore_changes = [user_data] }` — a `cloud-init.yml` edit does **not** reach a booted host. Nothing here may rely on cloud-init for the running host.
- **`vector.toml` is NOT in `FILE_MAP`** (E8) — it is image-baked. Vector changes require a bootstrap-image release; Phase 1 deliberately does not depend on one.
- **Delivery ≠ activation** (ADR-161/#7103). #7298 landed the handler's `daemon-reload` grant 2026-08-05 21:45; #7296 and #7297 are both open. Phase 1.4's acceptance is a read-back of the new field.
- **The `/hooks/*` route can answer from a peer** (#6425, 16 h of false alarms). Every read asserts `.host_id`.
- **Drop-in shape gate before adoptability** (`model.c4:456`): `infra-config-install.sh`'s drop-in validation must already cover this file class. Verify before adding the `FILE_MAP` entry — every content gate ships before the grant that makes its file class adoptable.
- The dedicated `soleur-inngest` node (10.0.1.40) is untouched; its :8288 problem is #7228/#7230.

### Vendor-tier reality check

No new vendor resources. Better Stack stays on the free tier (3 GB/mo, 3-day retention); Phase 6.6's optional `redis-server` tag emits near-zero at steady state and only becomes chatty during the failure it exists to report.

---

## Encryption Posture

```yaml
at_rest:
  - store: "inngest-redis AOF on web-1 (/mnt/data/redis)"
    mechanism: "LUKS2 (dm-crypt) — /mnt/data is /dev/mapper/workspaces"
    evidence: "luks-monitor 2026-08-05 07:23:58 — 'OK: /mnt/data is LUKS-backed (device_type=crypto_LUKS mount_source=/dev/mapper/workspaces escrow=ok header=readable)'"
    defends_against: "disk seizure, Hetzner volume snapshot exfiltration, decommissioned-media recovery"
    does_not_defend: "any read by a process on the running host (the mapper is open); root compromise; the AOF quarantine copy Phase 6.5 may create, which lands on the same volume and inherits the same posture — no weaker, no stronger"
    disclosed_as: "encryption-posture-ledger.json (see exception for the DEDICATED-host sibling)"
    live_verification: "SOLEUR_WORKSPACES_READYZ + the LUKS-backed line in Better Stack, scheduled per #7196"
in_transit:
  - connection: "inngest-server → redis (127.0.0.1:6379)"
    tls: "none — loopback only, `bind 127.0.0.1 -::1`, `protected-mode yes`, requirepass injected from Doppler at runtime"
    cert_verification: "n/a (no TLS)"
    does_not_defend: "a co-resident process on web-1 that can reach loopback and holds the password"
    disclosed_as: "unchanged by this plan"
  - connection: "CI → /hooks/deploy-status (carrying the new redis fields)"
    tls: "TLS 1.3 via Cloudflare"
    cert_verification: "on"
    does_not_defend: "anyone holding BOTH the CF Access service token AND WEBHOOK_DEPLOY_SECRET — which is why the journal tail must be scrubbed BEFORE it enters the response body, not merely transport-protected. H7 makes this sharper: a Doppler auth error can echo token fragments."
    disclosed_as: "transport unchanged; the NEW disclosure is field content, covered by § User-Brand Impact"
exception:
  - store: "inngest-redis AOF on the DEDICATED soleur-inngest host (hcloud_volume.inngest_redis)"
    justification: "PLAINTEXT ext4, no LUKS apparatus (inngest-host.tf, format = \"ext4\"). Pre-existing; not introduced here and not on the affected host."
    tracking_issue: "#6894"
    reevaluate_when: "the dedicated host's guest-side LUKS cutover lands"
    expires_on: "carried by #6894 — this plan neither extends nor renews it"
```

---

## Architecture Decision (ADR/C4)

### ADR

**Create `ADR-169-inngest-redis-outage-detect-fail-loud.md`** (ordinal **PROVISIONAL**). Derived live at deepen time against a freshly-fetched `origin/main`, not the branch base:

```
$ git fetch origin main --quiet
$ git ls-tree -r --name-only origin/main knowledge-base/engineering/architecture/decisions/ \
    | grep -oE 'ADR-[0-9]+' | sort -t- -k2 -n | tail -3
ADR-165
ADR-166
ADR-168
```

→ next free is **ADR-169**. It stays provisional: `/ship`'s ADR-Ordinal Collision Gate re-verifies against `origin/main` before merge and after every Phase 7 sync, because a sibling PR can claim the ordinal mid-pipeline (they only surface together post-squash). **If it moves, sweep the whole feature artifact set in the same edit** — `grep -rn 'ADR-169' knowledge-base/project/{plans,specs}/feat-one-shot-7286-*/` — so no AC ends up asserting a nonexistent file.

Decision: **a Redis outage under Inngest is detected within minutes and fails loud; it is never silently degraded to SQLite, and never left indefinitely wedged without an alarm naming the cause.** Second, narrower decision: **no secret may be copied into a second host file without the copy inheriting the original's re-delivery path** — promoted from prose in `10-inngest-heartbeat-doppler-token.conf` to a test-enforced invariant (Phase 3.2).

This extends #5450 / ADR-030 / ADR-100, which made durability a *bootstrap-time* gate (`REDIS_READY`) and left the runtime case unspecified. Fifteen hours wedged with no fallback and no signal is what "unspecified" cost.

Alternatives to record:
- (a) **status quo** — wedge indefinitely, no alarm, no evidence. This incident.
- (b) **runtime SQLite fallback** — availability restored, armed reminders silently dropped; would have masked a credential regression for 15 h and turned a diagnosable crash-loop into an undiagnosable data-loss event. **Explicitly rejected**, and rejected *after* this plan's own first draft proposed it — record the reversal so a future plan does not re-propose it.
- (c) **hard `Requires=inngest-redis.service`** — makes the coupling explicit but still yields an indefinite wedge.
- (d) **chosen** — in-surface detection with discriminating fields, loud alarm carrying the cause, plus the class-closing drop-in invariant. Any future degrade arm must be fail-loud-and-refuse (reject new reminder scheduling with a user-visible error), never accept-and-drop.

### C4 views

`inngestRedis` (`model.c4:196`), `inngest -> inngestRedis "Durable queue + run-state"` (`model.c4:483`), and the `views.c4:33` include line all already exist, so **no new element and no new view line is required**. Per the C4 completeness mandate, that conclusion rests on an enumeration read against all three of `model.c4`, `views.c4`, `spec.c4` — not a keyword grep for the feature's own noun:

- **External human actors:** none added. This change is operator/CI-facing only.
- **External systems / vendors:** Better Stack (`betterstack`, `model.c4:297`) and GHCR/zot are already modelled with the log-shipping and image-pull edges this plan uses. No new vendor.
- **Containers / data stores touched:** `inngest`, `inngestRedis`, `inngestPostgres`, `hetzner`, `tunnel` — all modelled.
- **Access relationships changed:** none. Phase 1 adds fields to the existing `tunnel → hetzner` route (`model.c4:456`, already described as carrying `deploy-status`); it creates no new edge.

**Two descriptions the measurements falsify must still be corrected** — a C4 review is for correctness, not only completeness:

1. `inngestRedis` (`model.c4:196-198`) asserts *"AT REST: PLAINTEXT ext4 (`hcloud_volume.inngest_redis`, `format = \"ext4\"`, no LUKS apparatus — inngest-host.tf)"*. True of the **dedicated** host's volume; **false for the web-1 co-located arm**, whose AOF sits on `/mnt/data` = `/dev/mapper/workspaces`, measured LUKS-backed 2026-08-04 and 2026-08-05 (E9/E10). The description must distinguish the two arms.
2. `hetzner -> inngest` (`model.c4:486`) reads *"Hosts (dedicated single-host node, private-net 10.0.1.40; removed from web cloud-init — ADR-100, #6178)"*, implying the dedicated node is the live scheduler. Measured: the **web-1** co-located inngest-server serves the 68 functions and is what the watchdog probes, while 10.0.1.40 is ECONNREFUSED (E18). Annotate the residual co-located arm and cite **#7228/#7230** as owning the resolution. This plan does not resolve that split and must not silently inherit a model asserting it does not exist.

Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after editing — a `view … include` referencing an undefined element fails there, not at `tsc`.

### Sequencing

The ADR is authored in the same PR as Phase 3 (`status: accepted`), not deferred to a follow-up issue (`wg-architecture-decision-is-a-plan-deliverable`).

---

## Network-Outage Deep-Dive

The deepen-plan network gate fired (the plan body matches `unreachable`, `timeout`, `connection refused`, and `ssh` — the latter only as citations of runbook lines being deleted). Per `hr-ssh-diagnosis-verify-firewall` and `plan-network-outage-checklist.md`, the L3→L7 layers are answered **before** any service-layer hypothesis is trusted. There are **two distinct paths** here and conflating them is the trap this gate exists to prevent.

### Path A — the failing connection: `inngest-server → 127.0.0.1:6379` (loopback)

| Layer | Verified? | Artifact / reasoning |
|---|---|---|
| L3 firewall allow-list | **N/A — structurally not in path** | The connection never leaves the host. `inngest-redis.conf` pins `bind 127.0.0.1 -::1` and `protected-mode yes`; `hcloud_firewall.inngest`/web firewall rules govern the public NIC only. A firewall change cannot produce a loopback `ECONNREFUSED`. |
| L3 DNS / routing | **N/A — structurally not in path** | The literal `127.0.0.1` is used; no resolution step exists. |
| L7 TLS / proxy | **N/A — no TLS on this hop** | Plaintext loopback by design (§ Encryption Posture, `in_transit`). |
| L7 application | **VERIFIED — and it is decisive** | `ECONNREFUSED` on loopback means *no process is listening on the port* — the kernel refuses immediately with RST. It is not a drop, not a timeout, not a filter. Corroborated independently by `inngest-redis.service: Failed with result 'exit-code'.` at a 5 s cadence (E3). Redis is not unreachable; **redis is not running.** |

**Ordering discipline honoured, and it inverts the usual conclusion.** The checklist exists because L7 hypotheses get trusted while an L3 layer silently drops packets. Here the L3/L7 network layers are *provably* not in the path, so the service-layer hypothesis is not a premature conclusion — it is the only surviving one. What remains unknown is *why the service exited*, which is a process question, not a network question (§ Hypotheses).

### Path B — the diagnostic/management path: CI or operator → `deploy.soleur.ai/hooks/*`

This path is how every remedy and every verification in this plan is delivered and read, so its layers were verified live during planning.

| Layer | Verified? | Artifact |
|---|---|---|
| L3 firewall / access control | **VERIFIED** | An unauthenticated request from the planning workstation returned **HTTP 403** with a Cloudflare Access interstitial (`App AUD: b149d111…`, `Your IP address: 82.67.29.121`). The same request with the `CF-Access-Client-Id`/`CF-Access-Client-Secret` service token from Doppler `prd_terraform` returned **HTTP 200** with a full JSON payload. Access control is *working as designed* — this is not admin-IP drift (contrast #2681 / `admin-ip-drift.md`). |
| L3 DNS / routing | **VERIFIED implicitly** | `deploy.soleur.ai` resolved and the Cloudflare edge answered (`Ray ID: a26913a6c8838c76`) on the 403, and the origin answered on the 200. Both terminated at the edge, so no route-level drop. |
| L7 TLS / proxy | **VERIFIED** | TLS terminated by Cloudflare; the tunnel ingress is origin-relative to `10.0.1.10` since #6594/PR-A. The 200 response carried `host_id: hetzner-123931471`, confirming the intended origin. |
| L7 application | **VERIFIED** | `webhook.service` executed `cat-deploy-state.sh` and returned a well-formed payload including a live journal tail timestamped within seconds of the request. The management plane is healthy; only the workload is down. |

**Standing hazard on Path B (#6425).** `scheduled-inngest-health.yml` documents that with more than one tunnel connector, `/hooks/*` answers from **whichever host CF's colo selects** — the cause of 16 h of false inngest-down alarms. Origin-relative ingress (`model.c4:456`) makes this deterministic *by construction* now, but the plan does not rely on that: **every read asserts `.host_id == "hetzner-123931471"` first** (Phase 0.1, Phase 1.4, AC11). A redis-healthy answer from a peer is otherwise indistinguishable from a fix.

**Conclusion:** no network-layer defect. The `ssh` tokens the gate matched are exclusively citations of runbook lines Phase 1.3 **deletes**; this plan prescribes no host login on any path.

---

## Downtime & Cutover

The downtime gate is evaluated because Phase 6 may issue a bootstrap-image release that restarts `inngest-server.service`.

**Offline-inducing operation:** `deploy-inngest-image.yml` → `inngest-bootstrap.sh` → `systemctl restart inngest-server.service` on web-1.

**Surface affected:** the Inngest scheduler/executor on web-1 (background jobs). **Not** the web-platform container, **not** `app.soleur.ai`, **not** the tunnel, **not** the workspaces volume — all untouched by both delivery channels (§ Infrastructure (IaC)).

**Zero-downtime evaluation, and why it is moot here:**

- The affected surface is **already 100% down** and has been for ~15 hours (E3/E4). Restarting a unit that is crash-looping in `activating` cannot subtract availability — there is none to subtract. The change's downtime delta is **zero by construction**.
- Phase 1 (the only phase that ships before a cause is known) rides `/hooks/infra-config`, which **writes files and runs `daemon-reload`** — it restarts no serving unit and touches no serving surface. Downtime delta: **zero**.
- No `hcloud_server`, volume, or attachment is modified; no `-/+` replace is possible (§ Infrastructure — zero `.tf` edits, enforced by AC9). No reboot/replace class operation exists in this plan.
- No database migration, no lock-taking DDL, no backfill. No database-lock class operation exists.
- The web-platform container is never swapped, so no in-flight HTTP requests are dropped. No deploy/router class operation affects a *serving* surface.

**Residual downtime accepted:** none, because none is introduced. No maintenance window is required and no operator sign-off is needed for availability.

**Rollback per stage:** Phase 1.1 (probe fields) — additive to a JSON payload; rollback is redeploying the prior `cat-deploy-state.sh` through the same channel. Phase 1.2 (drop-in) — `EnvironmentFile=-` is inert if the credential file is absent, so rollback is deleting the drop-in and reloading; it cannot leave the unit worse than its current crash-loop. Phase 6 (bootstrap-image release) — pinned by digest, so rollback is redeploying the prior tag, and `verify_inngest_health` (`ci-deploy.sh:2205`) already fails the deploy loudly rather than leaving a half-applied state.

**The one genuine availability risk is the opposite of downtime:** a remedy that appears to restore `inngest-server` while Redis is still absent would restore *availability without durability*, silently dropping armed reminders. That is why AC14-AC16 assert `services.inngest_redis == "active"` and `durability=durable` across ≥3 ticks, not merely that inngest-server answers.

---

## Domain Review

**Domains relevant:** Engineering, Operations

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The consult materially changed the plan. It (a) identified the missing `inngest-redis.service.d/` Doppler-token drop-in as the leading hypothesis (H7/E16/E17) and overturned this plan's own "dead token is refuted" verdict, (b) rejected the proposed runtime SQLite fallback as strictly worse than the outage it would mask, (c) named the single-point-of-failure the first draft did not: **every non-doc phase depends on one unverified delivery channel**, with `terraform apply` blocked (#7273) and no stated behavior for "the push lands but does not activate", and (d) flagged three concrete instrument gaps now folded in — missing `NRestarts`/`ExecMainStartTimestamp`/`ActiveEnterTimestamp`, the `vector.toml`-is-image-baked caveat that softens E7 to non-proof, and the #6425 connector coin-flip that makes a `.host_id` assertion mandatory on every read. It also flagged the #4804 `FILE_MAP` chicken-and-egg freeze (`infra-config-apply.sh:399`) as a pre-push check, and recommended deferring the AOF quarantine verb. All folded into the phases, risks, and ACs above.

### Operations (COO)

**Status:** reviewed (inline)
**Assessment:** A P1 background-job outage whose only operator-visible artifact is a bot comment restating a guess is an operations failure as much as an engineering one. Phase 2 (attach real evidence) and Phase 1.3 + Phase 5 (a runbook with no host-login last resort) are the operations deliverables and are non-optional. The recurring theme across #7250 / #7267 / #7270 / #7296 / #7297 — a channel reporting success while its defect persists — is exactly why Phase 1.4 accepts on a read-back rather than a status code.

### Product/UX Gate

Skipped. The mechanical UI-surface scan over § Files to Edit and § Files to Create matches no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or any other UI-surface glob — this is infrastructure and observability only. Product tier: **NONE**.

**Brainstorm-recommended specialists:** none (no brainstorm ran — one-shot path).
**Skipped specialists:** `ux-design-lead` — N/A, no UI surface.
**Pencil available:** N/A (no UI surface).

---

## Open Code-Review Overlap

**None.** All 64 open `code-review` issues (`gh issue list --label code-review --state open --limit 200 --json number,title,body`) were checked against every path in § Files to Edit and § Files to Create via a standalone `jq --arg path … | contains($path)`. Zero matches.

---

## Acceptance Criteria

### Pre-merge (PR) — Phase 1 PR

- [ ] **AC1** `cat-deploy-state.sh` emits all seven `services.inngest_redis*` fields, and `inngest_redis_result` includes `NRestarts`, `ExecMainStartTimestamp`, and `ActiveEnterTimestamp`. Verify: `bash apps/web-platform/infra/cat-deploy-state.test.sh` exits 0 with per-key assertions.
- [ ] **AC2** The redis journal tail routes through the **existing** scrubber. Verify: `grep -c 'service_journal_tail inngest-redis.service' apps/web-platform/infra/cat-deploy-state.sh` == 1, and the file's total `journalctl` invocation count is unchanged from the Phase-0.5 baseline (no new standalone call).
- [ ] **AC3** No secret can enter the payload. Verify: a test feeds a **synthesized** tail containing `--requirepass hunter2`, `redis://:hunter2@127.0.0.1:6379`, and `dp.st.prd.SYNTHETIC`, and asserts none survives; `inngest_redis_secret_len` is numeric-or-empty and never alphanumeric. Fixtures are synthesized only (`cq-test-fixtures-synthesized-only`).
- [ ] **AC4** The drop-in is wired across **all five** delivery surfaces, not two. Verify mechanically rather than by inspection:
  ```bash
  grep -c 'inngest_redis_doppler_token_conf_b64'   apps/web-platform/infra/push-infra-config.sh   # 1
  grep -c 'INNGEST_REDIS_DOPPLER_TOKEN_CONF_B64'   apps/web-platform/infra/hooks.json.tmpl        # 1
  grep -c 'INNGEST_REDIS_DOPPLER_TOKEN_CONF_B64'   apps/web-platform/infra/infra-config-apply.sh  # 1
  grep -c 'inngest-redis.service.d/10-inngest-redis-doppler-token.conf' \
                                                   apps/web-platform/infra/infra-config-install.sh # 1
  test -f apps/web-platform/infra/10-inngest-redis-doppler-token.conf
  ```
  All five must be non-zero. The drop-in body contains `EnvironmentFile=-/etc/default/soleur-doppler-token` — the `-` prefix is load-bearing (it keeps the file inert until the credential lands).
- [ ] **AC4b** The five-surface invariant is **enforced for the next file too**, not just this one. Verify: `bash apps/web-platform/infra/infra-config-apply.test.sh` exits 0, and the new parity assertion FAILS when any one surface is removed (prove it can fail — `cq-write-failing-tests-before`). This closes the class that the plan's own first draft fell into.
- [ ] **AC4c** `bash apps/web-platform/infra/infra-config-install.test.sh` exits 0 with the `FILE_MAP` ↔ `DEST_SPEC` pair pinned.
- [ ] **AC5** The class-closing invariant test exists and **was proven able to fail**: assert every unit with `EnvironmentFile=/etc/default/inngest-server` has a `FILE_MAP` drop-in. Verify: the test FAILS on `origin/main` (where `inngest-redis.service` is the violation) and PASSES on the branch. A test that only ever passed proves nothing (`cq-write-failing-tests-before`).
- [ ] **AC6** The probe cannot take the endpoint down. Verify: with `systemctl` and `redis-server` absent from `PATH`, `cat-deploy-state.sh` exits 0 and emits valid JSON (`jq -e . >/dev/null`).
<!-- lint-infra-ignore start — #7286: the lines below QUOTE the `ssh root@` runbook instructions this PR DELETES, and the acceptance command that counts them. They are citations of a defect being removed, not prescribed steps. Without this region the no-SSH linter (correctly, now that #7286 taught it to see fenced/user@host forms) flags the AC that proves the deletion happened. -->

- [ ] **AC7** All 7 runbook host-login instructions and the last-resort heading are gone. **⚠ The obvious gate does NOT work and must be fixed first.** Verified live during deepen: `python3 scripts/lint-infra-no-human-steps.py knowledge-base/engineering/operations/runbooks/inngest-server.md` returns `OK: no human-run infra steps`, **exit 0**, with all 7 lines still present — its SSH pattern (`scripts/lint-infra-no-human-steps.py:93`, mirrored `:161`) is `\bssh(?:\s+into|\s+onto|\s+to|\s+-i)\b`, which matches the *prose* form ("ssh into the host") and never `ssh root@`. A synthetic fenced `ssh root@<host> '…'` also passes. So AC7 as first drafted would have exited 0 both before and after Phase 1.3 — **the plan's central no-SSH promise was not verifiable at all.** Required fix, in this PR: extend the linter with `\bssh\s+\S*@` **and ship a proof-of-red** — the extended linter must FAIL on `origin/main`'s runbook before it passes on the branch (`cq-write-failing-tests-before` applies to the gate, not only to AC5's invariant test). Then verify with the gate's own invocation: `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.
- [ ] **AC7b** Phase 1.3's deletions are complete and do not leave dangling continuations. Verify: `grep -c 'ssh root@' knowledge-base/engineering/operations/runbooks/inngest-server.md` == 0 **and** `grep -c 'Last-resort (host login)'` == 0 **and** the file still parses as valid Markdown with no orphaned fenced block. Line 378 is the head of a 3-line fenced command (`… && \`), so deleting the cited line alone leaves a dangling continuation.
- [ ] **AC7c** Verb-completeness, not just deletion. Three of the seven lines are host **mutations** with no existing webhook verb — `:260` (`systemctl restart soleur-web-platform inngest-server.service`), `:338` (`systemctl restart soleur-web-platform`), `:378-380` (`systemctl stop … && sqlite3 … VACUUM && systemctl start`). `ci-deploy.sh:2346` accepts only `deploy|restart|quiesce|enable`, and `restart` rejects every component but `inngest` (`:2354-2362`). `/hooks/deploy-status` is read-only, so "replace each with a deploy-status recipe" cannot hold for these three. For **each** of the 7 lines the PR must record one of: the existing verb it maps to, the verb + pinned sudoers grant added in this PR, or an explicit statement that the procedure is retired and why. Deleting operator capability silently is not an acceptable resolution of an SSH-fallback finding.

<!-- lint-infra-ignore end -->

- [ ] **AC8** Full suite green: the repo's registered runner exits 0 with no newly-failing suite versus the Phase-0.5 baseline.
- [ ] **AC9** *(restated — the first draft's version asserted the opposite of how the channel works)* **No UNSCOPED `terraform apply`.** `server.tf` **is** modified, but only its `terraform_data.deploy_pipeline_fix` `triggers_replace` list, and delivery runs through the existing scoped `terraform apply -target=terraform_data.deploy_pipeline_fix` in `apply-deploy-pipeline-fix.yml:352`. Verify:
  ```bash
  n=$(git diff --name-only origin/main...HEAD -- '*.tf' | wc -l); test "$n" -le 1
  git diff origin/main...HEAD -- apps/web-platform/infra/server.tf \
    | grep -E '^\+' | grep -vcE 'triggers_replace|10-inngest-redis-doppler-token\.conf|^\+\+\+' # expect 0
  ```
  (Note the `test`-on-a-count form: a bare `grep -c … == 0` returns `0` **with exit status 1** on no match, which fails the assertion under `pipefail` exactly when it should pass.)
- [ ] **AC10** PR body uses `Ref #7286`, **not** `Closes #7286` — remediation runs post-merge, so auto-closing at merge would assert a false-resolved state (`wg-use-closes-n-in-pr-body-not-title-to`, ops-remediation carve-out).

### Post-merge (automated, in-workflow — no operator steps)

- [ ] **AC11** The read is attributed to the right host **before** any field is believed: `/hooks/deploy-status` → `.host_id == "hetzner-123931471"`. A peer-connector answer (#6425) invalidates every downstream assertion.
- [ ] **AC12** The new keys exist on-host with non-placeholder values. Verify: the § Observability `discoverability_test`. **This is the delivery-vs-activation gate — a `/hooks/infra-config` success code does not satisfy it.**
- [ ] **AC12b** The two-push #4804 sequence completed. Verify: push 1 may report `exit_code=1` with the drop-in recorded `missing_env` (**expected, not a failure** — the stale on-host `hooks.json` cannot pass a key its own bridge does not yet declare); push 2 reports the drop-in written, and `services.inngest_redis_dropin` names `10-inngest-redis-doppler-token.conf`. An `exit_code=1` on push 1 MUST NOT be read as a broken channel — verify by field, never by exit code.
- [ ] **AC12c** Probe and fix land **independently**, and the payload says which. Verify: `services.inngest_redis` (probe, Phase 1.1) is present even if `services.inngest_redis_dropin` (fix, Phase 1.2) is absent. The probe rides the per-request webhook exec and needs no `daemon-reload`; the drop-in does. If the `daemon-reload` grant (#7298) is still broken, this AC is what tells us so — and the diagnosis still lands.
- [ ] **AC13** The Phase-1 payload adjudicates § Hypotheses. Verify: the resolved hypothesis and the verbatim adjudicating payload excerpt are recorded in the PR body and in § Hypotheses. An unresolved table **blocks** Phase 6 arm selection.
- [ ] **AC14** `services.inngest_redis == "active"` **and** `services.inngest_server == "active"`, with `NRestarts` unchanged across two reads ≥60 s apart (a single `is-active` on a 5 s loop is a coin flip).
- [ ] **AC15** `GET /hooks/inngest-liveness` returns HTTP **200** with a real non-empty functions array, `functions >= 68`, **and the response names `host_id=hetzner-123931471`**. Verify: `jq -e '.functions | type == "array" and length >= 68'` plus a `host_id` assertion on the same response. **A 200 alone does not satisfy this** — the empty-registry cold-start case also returns 200 and is classified `cold_start` by `scheduled-inngest-health.yml`. **The `host_id` clause is not optional:** §Risks 5 makes `.host_id` mandatory "on every read", and an earlier draft scoped it only to `/hooks/deploy-status` — leaving the route that actually closes #7286 unguarded against the #6425 connector coin-flip.
- [ ] **AC15b** *(end-to-end, closes the E18 gap)* At least one Inngest function **executes** post-restore — not merely registers. Verify: fire an allowlisted event via `/api/internal/trigger-cron` (per the runbook's on-demand trigger) and confirm a `function.finished` event for it in Better Stack within 5 minutes. Registry count is a *proxy*; execution is the invariant § User-Brand Impact actually claims ("every scheduled and event-driven background job silently stops"). Without this AC, every other post-merge AC can go green while the user's stated symptom is unchanged — because the app dispatches to `10.0.1.40:8288`, which E18 shows was already ECONNREFUSED before this outage. If AC15b fails while AC13-AC15 pass, the residual is #7228/#7230 and must be stated as such in the PR body rather than silently inherited.
- [ ] **AC16** `SOLEUR_INNGEST_LIVENESS_VERDICT mode=healthy … durability=durable` appears for **≥3 consecutive** `*/15` ticks. Verify via `scripts/betterstack-query.sh` **including the `s3Cluster` archive arm** — `remote()` alone answers a multi-hour question with ~40 minutes of data.
- [ ] **AC17** *(rewritten — the first draft was near-tautological)* Redis's error channel is settled **from the payload, not from an absence query**. Verify: `services.vector_config_identity` (Phase 1.1) matches the repo `vector.toml` sha256 → the `inngest-redis` allowlist entry (already at `vector.toml:220`) is live on-host and E8 is closed; if it does **not** match, Phase 6.6's bootstrap-image re-stage is required and must not be skipped. **Why the absence-query form was dropped:** it accepted both `clean(0)` and `present(1)`, leaving only `unshipping(2)` as a fail; its `--absence` marker was an unresolved placeholder that cannot exist if redis never starts successfully (→ `clean(0)`, green, channel still dark); and `--control SOLEUR_INNGEST_SERVER_PROBE` controls the **sink**, which E7 already proves live — it does not control the one open question, which is whether web-1's running `vector.toml` carries the tag entry. A hash comparison answers that question directly.
- [ ] **AC17b** Once redis starts, its own rows are actually present. Verify: `scripts/betterstack-query.sh` over hot+archive returns ≥1 row with `SYSLOG_IDENTIFIER='inngest-redis'` dated after the remediation deploy. This is the positive form of E7's zero and the only proof the channel carries real traffic.
- [ ] **AC18** #7286 closes on the watchdog's own healthy path (`gh issue view 7286 --json state` → `CLOSED`), driven by the auto-close step rather than a manual `gh issue close`.
- [ ] **AC19** *(fail-closed — the first draft had no failure condition)* Armed reminders are **preserved**, not merely counted. Verify: (a) a **pre**-recovery baseline is captured via `/hooks/inngest-enumerate-reminders` before any remedy runs (Phase 6 must capture it; "versus pre-incident" otherwise has no baseline), and (b) the post-recovery count is **≥** the baseline. A negative delta **FAILS** this AC and must be escalated, not merely written down. As first drafted, total loss of every armed reminder satisfied AC19 provided it was recorded — which inverts §Risks 7 and #5542 verdict 0.2 (*irrecoverable once gone, invisible in Postgres*).
- [ ] **AC20** The watchdog's next `inngest_down` occurrence carries real evidence. Verify **statically** (time-bounded, unlike the first draft's "a dry-run or the next real firing", which was unbounded and might never occur if the fix works): `grep -c 'likely a lost' .github/workflows/scheduled-inngest-health.yml` == 0, **and** the workflow's evidence step is exercised by T8/T9/T10 against stubbed 200 / 503 / key-absent responses. If a real firing occurs before merge, attach its issue body.
- [ ] **AC21** ADR-169 exists, `status: accepted`, and its ordinal was re-derived against freshly-fetched `origin/main` immediately before merge. Verify: the file exists at the sweep-checked path and `grep -rn 'ADR-169' knowledge-base/project/{plans,specs}/feat-one-shot-7286-*/` shows no stale ordinal after any renumber.
- [ ] **AC22** Both C4 corrections landed and render. Verify: `model.c4` `inngestRedis` distinguishes the LUKS-backed web-1 arm from the plaintext dedicated-host volume; `hetzner -> inngest` annotates the residual co-located arm and cites #7228/#7230; `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` pass.
- [ ] **AC23** If any Phase-6 arm requires a bootstrap-image release, the tag is cut **in-workflow**, not by an operator. Verify: the release is triggered by `build-inngest-bootstrap-image.yml` from a pushed `vinngest-v*` tag created by CI, and `deploy-inngest-image.yml` reports success. `hr-tagged-build-workflow-needs-initial-tag-push` applies; an operator tag push would be an undeferred operator step and would block PR-ready (`wg-block-pr-ready-on-undeferred-operator-steps`).

---

## PR Boundaries

The phase numbers are logical, not chronological. Three PRs:

| PR | Contains | Gated by |
|---|---|---|
| **PR-1 (ships first, alone)** | Phase 0 (all probes incl. 0.7), Phase 1.1 (probe fields + scrubber extension + `deploy-status` on-error flag), Phase 1.2 (7-surface drop-in), Phase 1.3 (runbook SSH deletions + `lint-infra-no-human-steps.py` fix + proof-of-red), Phase 3.2 (the class-closing invariant test) | AC1-AC10, AC11-AC12c |
| **PR-2** | Phase 1b (if triggered), Phase 2 (+ Phase 4 — the watchdog message honesty folds into the same PR), Phase 2.5 de-flap, ADR-169, the two C4 corrections | AC20, AC21, AC22; T8-T13 |
| **PR-3** | Phase 5 (runbook Redis-down section + decision table), Phase 6 (the arm Phase 1 named) + restore | AC13-AC19 |

Phase 3.1 ("detector, not degraded arm") **is** Phase 2 — it is not separate work. Phase 3.2 ships in PR-1 because it is the test that would have caught H7. The ADR lands in PR-2, with the detector it describes.

## Deepen-Pass Review Findings — disposition

Three review panels (observability-coverage, spec-flow, security-sentinel) plus a CTO consult ran against the plan. Every P0/P1 finding and its disposition:

| # | Finding | Disposition |
|---|---|---|
| P0 | **Delivery IS a `terraform apply`** — `push-infra-config.sh` has one caller, a `local-exec` on `terraform_data.deploy_pipeline_fix` fired by `apply-deploy-pipeline-fix.yml:352`. AC9 forbade it. | **FIXED.** Phase 1.2 correction block; AC9 restated to "no *unscoped* apply"; Phase 0.7 added as a blocking probe. |
| P0 | **Drop-in registered on 2 of 7 surfaces** — missing `push-infra-config.sh`, `hooks.json.tmpl`, `server.tf` `triggers_replace`, `apply-deploy-pipeline-fix.yml` `paths:`. | **FIXED.** 7-surface table; AC4/AC4b; § Files to Edit. |
| P0 | **AC4 was a proxy** — `infra-config-install.test.sh` asserts FILE_MAP↔DEST_SPEC cardinality only; it cannot see the bridge or payload, so it goes green on a never-transmitted file. | **FIXED.** AC4 is now a direct 5-grep check; AC4b adds a parity test proven able to fail. |
| P0 | **`inngest_redis_dropin` measured disk, not systemd** — a false green on the very field gating H7; `Restart=` never re-parses drop-ins, only `daemon-reload` does. | **FIXED.** Field now reads `systemctl show -p DropInPaths,EnvironmentFiles`; Phase 1.2's "crash-loop is the delivery mechanism" claim corrected to name `daemon-reload`. |
| P0 | **AC15/AC18 read a route with no `host_id` guard** — a peer-connector answer (#6425) could close #7286 on a still-broken host. | **FIXED.** AC15 now asserts `host_id`. |
| P0 | **No escape if all discriminators come back empty** — AC13 blocks Phase 6, Phase 6 is the only path to AC14-AC16 → deadlock with no owner or timebox. | **FIXED.** Phase 1b added, timeboxed to one watchdog tick, owned by the same PR. |
| P0 | **AC17 near-tautological** — accepted both `clean(0)` and `present(1)`; unresolved absence marker; control exercised the sink, not the open question. | **FIXED.** Replaced with a `vector_config_identity` hash comparison + AC17b positive-presence check. |
| P0 | **Scrubber misses `requirepass`** — redis echoes the argument verbatim on a config-parse failure, which is the predicted tail for H4 **and** H5, into an HTTP response body. Plan also self-contradicted ("reuse verbatim" vs "extend the ban-list"). | **FIXED.** Phase 1.1 now says *extend the shared scrubber*, names the five patterns and the exact sed stage, and explains why Vector's rules do not cover this path. |
| P1 | **`inngest_redis_secret_len` unobtainable and unsafe** — no readable source; both implementations are unacceptable. | **DROPPED**, with the rationale recorded so it is not re-proposed. |
| P1 | **`/etc/default/soleur-doppler-token` unmeasured** — H7's mechanism needs it fresher than the pinned copy, and its writer is the same TF path. | **FIXED.** `inngest_redis_credfile` field added (presence + mtime + length, never value). |
| P1 | **AC7's linter cannot match `ssh root@`** — verified live: exit 0 with all 7 lines present. The plan's central promise was unverifiable. | **FIXED.** AC7 now requires extending `lint-infra-no-human-steps.py` with a proof-of-red; AC7b adds a direct grep. |
| P1 | **Three SSH lines are mutations with no webhook verb** — deleting them removes operator capability silently. | **FIXED.** AC7c requires a per-line verb inventory. |
| P1 | **`deploy-status` hook lacks `include-command-output-in-response-on-error`** — an empty body on error, in the PR that deletes the last-resort login. | **FIXED.** Added to Phase 1.1 and § Files to Edit. |
| P1 | **Phase 6.6 prescribed three wrong edits** — `vector.toml:220` already allowlists `inngest-redis`; adding `redis-server` would be dead AND break the derived-set-equality fixture. | **FIXED.** Phase 6.6 rewritten; three § Files to Edit rows struck through with reasons. |
| P1 | **Phase 2.3 discards the response body on non-2xx** — the #5492 class, and a regression against the same file's existing `-o /tmp/health-body` pattern. | **FIXED** in Phase 2.3 (below). |
| P1 | **`failure_modes[2]` needs two reads that nothing performs.** | **FIXED.** Made single-read decidable (`ActiveEnterTimestamp` recent AND `NRestarts > 0`). |
| P1 | **E18 vs § User-Brand Impact contradiction** — every post-merge AC can go green with the user's symptom unchanged; no AC executes a job end-to-end. | **FIXED.** AC15b added (end-to-end execution), with an explicit residual statement if it fails while the others pass. |
| P1 | **AC5's invariant encodes the same 2-surface model.** | **FIXED.** AC5 extended to the full lockstep via AC4b's parity assertion. |
| P1 | **AC19 had no failure condition** and no pre-recovery baseline. | **FIXED.** Now fail-closed on a negative delta, with a mandated baseline capture. |
| P1 | **Phases not in execution order; ADR's PR undetermined.** | **FIXED.** § PR Boundaries added above. |
| P1 | **No AC gates the ADR or the two C4 corrections.** | **FIXED.** AC21/AC22 added. |
| P1 | **No phase cuts the bootstrap-image tag** that four arms and the AC12 fallback require. | **FIXED.** AC23 added; owned by PR-3, never an operator step. |
| P1 | **Self-healing between Phase 0 and Phase 1.4 leaves AC13 unsatisfiable.** | **FIXED.** Phase 1b.4 covers the loud-UNKNOWN disposition; Phase 0.1 already handles the pre-start case. |
| P2 | Systemd `show --value` positional parse; `redis-server` PATH lookup + timeout; symlink refusal; AC2 baseline; AC9 pipefail; `include-command-output` — all folded into Phase 1.1 / AC9 / Phase 0.8. | **FIXED.** |
| — | **Shape gate already covers a new drop-in dest** (`infra-config-install.sh:248-250`, path-pattern-keyed). Risk 10 satisfied. | **CONFIRMED, no action** beyond moving two now-stale comments (`:208`, `:236`) in the same PR. |
| — | **Deferring `repair inngest-redis` is correct.** If Phase 1 does name the AOF: server-side-constructed quarantine path only, `lstat`-refuse symlinks, copy-then-fix (`redis-check-aof --fix` mutates in place), never `rm`. | **CONFIRMED**, constraints recorded in Phase 6.5. |

## Research Insights — applicable institutional learnings

Searched `knowledge-base/project/learnings/`; these apply and are folded into the phases above.

| Learning | Key insight (quoted) | Folded into |
|---|---|---|
| [`best-practices/2026-06-18-infra-config-delivery-chain-has-a-hidden-bridge-surface-and-count-blast-radius.md`](../../../knowledge-base/project/learnings/best-practices/2026-06-18-infra-config-delivery-chain-has-a-hidden-bridge-surface-and-count-blast-radius.md) | *"the delivery CHAIN is: push payload key → pass-environment-to-command bridge → handler FILE_MAP env var → install DEST_SPEC → on-disk path. Every link must carry the new file… the parity TEST is the proof"* | **Phase 1.2 five-surface table + AC4/AC4b.** This is the single highest-value catch of the deepen pass — the plan's first draft named 2 of 5 surfaces and would have delivered nothing while reporting success. |
| [`2026-07-18-rca-code-level-root-cause-licenses-fix-when-host-discriminator-unavailable.md`](../../../knowledge-base/project/learnings/2026-07-18-rca-code-level-root-cause-licenses-fix-when-host-discriminator-unavailable.md) | *"Separate the two questions: Which host? (mark UNKNOWN where unavailable, do not reason from surrounding facts). What is the root cause? (answerable at code level, independent of which host was probed)"* | **§ Hypotheses + Phase 1.2.** Licenses carrying the H7 fix while every hypothesis stays UNKNOWN: the missing drop-in is a *code-level* fact provable by grep against `FILE_MAP`, independent of the unreadable host journal. |
| [`2026-08-03-the-verification-i-shipped-could-not-fail-and-my-instrument-measured-the-wrong-machine.md`](../../../knowledge-base/project/learnings/2026-08-03-the-verification-i-shipped-could-not-fail-and-my-instrument-measured-the-wrong-machine.md) | *"Asserting `final_cg == scope` afterwards re-asserts the branch's entry condition. It cannot fail."* | **AC5, AC4b, T5/T6.** Every new guard must be proven RED before GREEN; and AC11's `.host_id` assertion exists because an instrument pointed at the wrong machine reports confidently about nothing. |
| [`integration-issues/no-ssh-cutover-verb-by-verb-audit-inngest-quiesce-20260712.md`](../../../knowledge-base/project/learnings/integration-issues/no-ssh-cutover-verb-by-verb-audit-inngest-quiesce-20260712.md) | *"`systemctl restart` never touches the `[Install] WantedBy` symlink"* | **Phase 5.3.** The runbook's decision table must map each remedy to the *correct verb* — a restart does not re-enable a disabled unit, and the Redis-down branch must say so rather than implying restart is universal. |
| [`best-practices/2026-07-13-watchdog-excluded-mode-shares-issue-class-untruthful-comment.md`](../../../knowledge-base/project/learnings/best-practices/2026-07-13-watchdog-excluded-mode-shares-issue-class-untruthful-comment.md) | *"Any downstream branch that assumes the variable is a boolean will post an untruthful comment"* | **Phase 2.4 + T10.** The watchdog's new evidence block must branch on the field being *present*, not on it being truthy — an absent `services.inngest_redis` must render an explicit fallback, never an empty value presented as a finding. |
| [`2026-05-19-inngest-substrate-five-bug-cascade.md`](../../../knowledge-base/project/learnings/2026-05-19-inngest-substrate-five-bug-cascade.md) | *"The substrate was a half-installed pipeline waiting for an operator click that never came"* | **Phase 6.7.** Post-restore verification must check the *registry* (`functions >= 68`), not merely that the process is up — a running inngest with an empty registry is the same silent failure in a different costume. |
| [`best-practices/2026-06-18-systemd-execstart-conditional-branch-via-sentinel-substitution.md`](../../../knowledge-base/project/learnings/best-practices/2026-06-18-systemd-execstart-conditional-branch-via-sentinel-substitution.md) | *"Keep the heredoc single-quoted; put a literal sentinel on the ExecStart line, then substitute it AFTER the heredoc is written"* | **Phase 3 (rejected-alternative rationale).** Documents the mechanism a runtime SQLite fallback would have used — recorded so the ADR's rejection is concrete about what was declined, not vague. |
| [`integration-issues/2026-04-03-doppler-not-installed-env-fallback-outage.md`](../../../knowledge-base/project/learnings/integration-issues/2026-04-03-doppler-not-installed-env-fallback-outage.md) | *"systemd services do NOT source `/etc/environment`… `resolve_env_file()` silently fell back to the stale `.env` file with no error logging"* | **§ Hypotheses H7 + Phase 3.2.** Same failure family: a credential path that degrades to a stale copy with no signal. The Phase 3.2 invariant test is the generalised fix. |
| [`best-practices/2026-05-28-infra-observability-parity-state-write-guards-and-ci-verification.md`](../../../knowledge-base/project/learnings/best-practices/2026-05-28-infra-observability-parity-state-write-guards-and-ci-verification.md) | *"per-file error handling, SHA256 per written file, persistent state file, EXIT trap with `.final` sentinel… CI verification step polling the new endpoint"* | **Phase 1.4 + AC12.** The read-back-the-endpoint pattern is precedent, not invention. |
| [`best-practices/2026-07-07-deploy-status-tag-reader-resolve-running-version-from-health.md`](../../../knowledge-base/project/learnings/best-practices/2026-07-07-deploy-status-tag-reader-resolve-running-version-from-health.md) | *"Resolve the running tag from the resource's own authoritative endpoint… no writer-contention surface, no component literal to get wrong"* | **Phase 1.1.** The new redis fields read the unit's own state directly; they must not be routed through the shared last-write-wins deploy-state slot. |

---

## Risks & Sharp Edges

1. **Single point of failure the first draft did not name: every non-doc phase rides one unverified delivery channel.** `/hooks/infra-config` activation is unverified (#7296/#7297/#7298 landed hours before this plan), and `terraform apply` is blocked (#7273). The plan must state its behavior for *"the push lands but does not activate"*: AC12 fails, and the fallback is a **bootstrap-image release** (`deploy-inngest-image.yml`), which reaches the same files by a different path. Do not discover this at hour 20.
2. **Phase 1 could ship and still tell us nothing.** If redis exits before writing a byte (a `203/EXEC` or `226/NAMESPACE`-class failure), the tail is empty. Mitigation: `inngest_redis_result` carries systemd-populated fields regardless of process output, and `dropin`/`datadir`/`binary` discriminate H7/H3/H4/H6 with no process output at all. **Never ship Phase 1 with the journal tail as its only new field.**
3. **`systemctl is-active` on a 5 s crash loop is a coin flip.** This already produced `degraded, degraded, durable` in 16 seconds (E15). `NRestarts` + `ActiveEnterTimestamp` are the fields that distinguish "still looping" from "recently fixed"; any AC keyed on a single `is-active` sample asserts a proxy, not the invariant.
4. **"Redis emits nothing" may be a pipeline artifact, not a fact about redis.** `vector.toml` is image-baked and absent from `FILE_MAP` (E8), so web-1's running config may predate the `inngest-redis` allowlist entry — in which case zero rows says nothing about redis, and the sibling tags that *do* return rows may simply be older entries. Do not carry "redis is silent" forward as a premise. Phase 1's local `journalctl` is what settles it.
5. **`/hooks/*` can answer from a peer host (#6425).** That coin flip produced 16 h of false inngest-down alarms once already. Every read asserts `.host_id`; a redis-healthy response from a peer is otherwise indistinguishable from a fix.
6. **The SQLite degrade is a durability decision wearing an availability costume.** It would have masked this regression for 15 h. If plan-review or the panel re-proposes making it the default recovery, that is a **User-Challenge**, not guidance to apply — the ADR records the reversal precisely so it is not re-litigated silently.
7. **Never `rm` the AOF.** Phase 6.5 must move-and-timestamp. Armed reminders are irrecoverable once the queue is gone and are invisible in Postgres (#5542 verdict 0.2).
8. **A plan premise is only true for the values the implementation picks.** Phase 3.4's restart-parameter choice must be re-checked against systemd's default `StartLimitIntervalSec=10s`/`StartLimitBurst=5`: with `RestartSec=5` the unit **never latches `failed`** (E17), which is why this looped for 15 h. Whatever `/work` picks must state which behavior it is choosing.
9. **#4804 `FILE_MAP` chicken-and-egg** (`infra-config-apply.sh:399`): adding a new `FILE_MAP` member in the same push as the handler that must deliver it can freeze. Check the note before pushing the drop-in entry.
10. **Content gate before adoptability** (`model.c4:456`): `infra-config-install.sh`'s drop-in shape gate must already cover this file class. systemd merges drop-ins after the unit body, so an unvalidated `*.service.d/*.conf` on a root-restart-capable route is arbitrary execution. Verify the gate covers it; do not assume.
11. **`inngest-heartbeat` is dark too** (E7: 0 rows in 3 days; E5: `inactive`). Same class, different unit. In scope only insofar as Phase 1's fields make it visible; a full heartbeat fix is a separate issue and should be **filed**, not absorbed.
12. **The watchdog's evidence fetch must never page on its own failure** (Phase 2.3). Converting a diagnostic enrichment into a hard failure would suppress the very page it enriches.
13. **Positive control before any absence claim.** Every "no logs for X" statement here is backed by same-window sibling counts and is explicitly bounded by E8. Any new absence claim at `/work` must use `betterstack-assert-absence.sh` with a `--control` and the `s3Cluster` arm.
14. **The dedicated-host split (E18) stays out of scope.** `10.0.1.40:8288` is ECONNREFUSED and the app dispatches there; it predates this outage by ≥3 days and is #7228/#7230. Folding it in would make a 15-hour P1 wait on a cutover decision. Record it in the C4 correction and move on.

---

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | `cat-deploy-state.sh` with `inngest-redis.service` active | `services.inngest_redis == "active"`; result string parses; `NRestarts` numeric; datadir reports owner/mode |
| T2 | Unit absent (synthesized) | Empty strings, exit 0, valid JSON — no crash, no `null` key |
| T3 | Tail containing `--requirepass hunter2`, `redis://:hunter2@host:6379`, `dp.st.prd.SYNTHETIC` | None survives; scrub marker present |
| T4 | Tail exceeding the byte cap | Truncated to the existing budget; JSON stays valid |
| T5 | Drop-in invariant test on `origin/main` | **FAILS** (`inngest-redis.service` is the violation) — proves the guard can fire |
| T6 | Drop-in invariant test on the branch | PASSES |
| T7 | `systemctl` and `redis-server` absent from `PATH` | Exit 0, valid JSON, empty fields |
| T8 | Watchdog `inngest_down` with `/hooks/deploy-status` → 200 | Issue body contains `host_id`, both unit states, both tails in `<details>`; no "likely a lost" string |
| T9 | Watchdog `inngest_down` with `/hooks/deploy-status` → 503 | Body says `deploy-status unreachable: HTTP 503`; workflow still files/comments and does not fail |
| T10 | Watchdog when `services.inngest_redis` key is **absent** (pre-activation) | Explicit fallback string, not an empty value presented as a finding |
| T11 | `/hooks/deploy-status` answering with a peer `host_id` | Verification FAILS closed rather than reporting healthy |
| T12 | `lint-infra-no-human-steps.py --changed --base origin/main` over the runbook edit | Exit 0 |
| T13 | C4 syntax + render after the description corrections | `c4-code-syntax.test.ts` and `c4-render.test.ts` pass |

---

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| **Remediate blindly first, instrument later** | Fastest path to `active`, but it destroys the pre-mutation state and guarantees the *next* occurrence is equally blind. Fifteen hours of outage bought one bit of information; a blind fix buys zero more. The tradeoff is real — Phase 1 costs one merge cycle of continued outage — and it is mitigated rather than paid in full by carrying the bounded, inert-if-unneeded H7 fix in the same push. |
| **Probe only, fix in a second PR** | Cleanest separation, but spends a full cycle on a channel whose activation is unverified (#7296/#7297/#7298) at hour 15+ of a user-facing outage, possibly learning nothing. The drop-in is inert if unneeded and cannot make anything worse, so the marginal risk of carrying it is near zero while the marginal upside is ending the outage a cycle earlier. |
| **Runtime SQLite fallback arm** (the first draft's Phase 3, and the issue body's remedy B) | Would have masked this regression for 15 h while silently dropping armed reminders — a diagnosable crash-loop becomes an undiagnosable data-loss event. Strictly worse than #5542, not a mitigation of it. Recorded as the ADR's rejected alternative (b) so it is not re-proposed. |
| **Re-stage the redis assets** (issue body remedy A) | Refuted: the unit exists and executes (E3). Re-staging addresses an absent unit. |
| **Hard `Requires=inngest-redis.service` on inngest-server** | Makes the coupling explicit and honest, but still yields an indefinite wedge with no alarm. Detection is what was missing, not dependency declaration. ADR alternative (c). |
| **Replace web-1 entirely (immutable host redeploy)** | Destroys the co-located inngest arm, the workspaces LUKS volume, and the tunnel connector to fix one unit — on a host already carrying an in-flight LUKS migration, and behind `ignore_changes = [user_data]` so it is a genuine destroy/create. Wildly disproportionate. |
| **Add host-login diagnostics to the runbook** | Violates `hr-no-ssh-fallback-in-runbooks`, and the capability already exists on an authenticated HTTP surface that merely lacks the field. Phase 1.3 removes the 7 existing instructions rather than adding a lint-exempt eighth. |
| **A native Better Stack alert on redis rows** | Cannot work while the channel's liveness is indeterminate (E8) — you cannot alert on rows that may never arrive. Also counter to ADR-096 (log-content recurrence alarms are in-repo GH-cron pollers). |
| **Fold in the dedicated-host `10.0.1.40` split (#7228/#7230)** | Real and serious, but a separate root cause with a separate remediation. Coupling them makes a 15-hour P1 wait on a cutover decision. |
