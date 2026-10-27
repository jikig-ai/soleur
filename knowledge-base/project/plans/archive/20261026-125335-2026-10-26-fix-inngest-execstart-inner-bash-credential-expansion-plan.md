<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
---
title: "fix: inngest-redis + rendered inngest-server ExecStarts expand credentials in an inner bash -c (traced launch prints them to journald)"
type: fix
date: 2026-10-26
slug: fix-inngest-execstart-inner-bash-credential-expansion
branch: feat-one-shot-11103-execstart-cred-expansion
issue: 11103
closes: 11103
priority: p2-medium
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

# fix: inngest-redis + rendered inngest-server ExecStarts expand credentials in an inner bash -c (traced launch prints them to journald)

## Overview

Two doppler-wrapped systemd `ExecStart` sites still expand injected credentials inside an inner `bash -c` body: `inngest-redis.service` (`--requirepass "$INNGEST_REDIS_PASSWORD"`, `apps/web-platform/infra/inngest-redis.service:45`) and the rendered `inngest-server.service` written by `apps/web-platform/infra/inngest-bootstrap.sh` (`export INNGEST_SIGNING_KEY="$${INNGEST_SIGNING_KEY#signkey-prod-}"` at :1664, plus `INNGEST_REDIS_URI` construction from `$${INNGEST_REDIS_PASSWORD}` in the durable `BACKEND_ENV` arm at :1747). Under `SHELLOPTS=xtrace`, `BASH_ENV`, or `bash -x`, a traced launch prints the resolved value to stderr; journald ships it off-box to Better Stack (`SyslogIdentifier=inngest-redis` → vector.toml Source 4; Source 1 admits the whole `inngest-server.service` unit at ANY priority — vector.toml:109 `include_units`).

The wrapper stage of `doppler-injection-bound.test.sh` only matches the `${!VAR}` indirect-expansion spelling (`INDIRECT_RE` at :530) — the two plain-`$VAR`/`${VAR}` sites escaped it. Same defect class as #9639; residual of the #10363/#10093 argv-bearer pair (PR #11097, merged 2026-10-25).

## Problem Statement

The inner `bash -c` executes under the full `doppler run`-injected environment. `bash`'s xtrace writes each command **after expansion** to stderr, so one `SHELLOPTS=xtrace` launch (or a `BASH_ENV` that enables `set -x`) prints:

- `+ /usr/bin/redis-server /mnt/data/redis/inngest-redis.conf --requirepass <live-password>` — `inngest-redis.service`, tagged `inngest-redis` → Better Stack source 2457081.
- `+ export INNGEST_SIGNING_KEY=<live-hex>` and (durable arm) `+ export INNGEST_REDIS_URI=redis://:<live-password>@127.0.0.1:6379` — `inngest-server.service`, admitted to the same source at any priority.

A second exposure sits underneath site 1 even without tracing: `redis-server`'s argv carries the resolved password into `/proc/<pid>/cmdline` (mode 0444) for the window between `exec` and Redis's own proc-title rewrite, and `CONFIG GET requirepass` returns the cleartext to any authenticated loopback client. The issue asks for the #10637 shape — the ExecStart expands nothing and the target resolves the credential after an unconditional xtrace refusal — or, for Redis where `requirepass` must be an argv word, an aclfile/rename-command delivery that keeps the secret off argv entirely.

## Proposed Solution

Mirror the sanctioned argv-bearer shape (PR #11097):

- **Site 1 (Redis): aclfile delivery.** A new `ExecStartPre` runs `doppler run --config ${DOPPLER_CONFIG} --only-secrets INNGEST_REDIS_PASSWORD -- /usr/local/bin/inngest-redis-acl.sh`; the script refuses unconditionally under xtrace (POSIX `case "$-"` → exit 78, value-free), then writes `user default on >"$INNGEST_REDIS_PASSWORD" ~* &* +@all` to `/mnt/data/redis/inngest-redis.acl` (0600, deploy:deploy, atomic tmp+mv). `inngest-redis.conf` gains `aclfile /mnt/data/redis/inngest-redis.acl`; `ExecStart` becomes plain `/usr/bin/redis-server /mnt/data/redis/inngest-redis.conf` — no `doppler run`, no `bash -c`, no expansion, no secret on argv. `SyslogIdentifier=inngest-redis` stays (stderr still ships via Source 4 — load-bearing, unchanged).
- **Site 2 (rendered `inngest-server.service`): resolve-after-refusal.** `inngest-bootstrap.sh` renders a new `/usr/local/bin/inngest-server-launch.sh` (heredoc, reconcile-always outside `SKIP_BINARY_INSTALL`, `chmod 0755` — the PROBESCRIPTEOF/HEARTBEATSCRIPTEOF precedent): unconditional `case "$-"` refusal first, then `export INNGEST_SIGNING_KEY="${INNGEST_SIGNING_KEY#signkey-prod-}"`, then the `@@BACKEND_ENV@@` fragment, then `exec /usr/local/bin/inngest start --host 0.0.0.0 --port 8288 --sqlite-dir /var/lib/inngest "$@"`. The unit's `ExecStart` becomes `doppler run --config @@DOPPLER_CONFIG@@ -- /usr/local/bin/inngest-server-launch.sh @@BACKEND_FLAGS@@ --poll-interval 60 --sdk-url @@SDK_URL@@` — the non-secret flag tail stays on argv so the `--postgres-max-open-conns` durable sentinel still reads from `systemctl show -p ExecStart`.
- **Corpus stage.** `doppler-injection-bound.test.sh` gains a stage flagging plain `$NAME`/`${NAME}`/`$${NAME}` expansions inside `bash -c` bodies in Exec directives of doppler-run units (resolving `@@NAME@@` sentinel fragments against same-file assignments), with a ratchet-only ack dict, census floor, identity pins, and mutation rows. `${!...}` stays the sibling wrapper stage's domain (no double-flagging; `web-git-data-probe.service` remains covered by its existing ack alone).

## Technical Approach

### Architecture

**Site 1 — `inngest-redis.service` (a file, not host-bound).** Assets ride the `soleur-inngest-bootstrap` OCI image → `/tmp` staging → `inngest-redis-bootstrap.sh` install on both co-located web hosts and the dedicated host. The acl-writer script is embedded as a heredoc inside `inngest-redis-bootstrap.sh` (the `inngest-redis-mount-guard.sh` install precedent at step 3.5 — no `STAGED` list or image-manifest edit needed). Ordering inside the unit: `ExecStartPre` mount-guard first (unchanged), then the acl writer — the writer needs `/mnt/data` mounted, so it must run after the guard that proves the mount. `--only-secrets INNGEST_REDIS_PASSWORD` bounds what the writer sees (the current unit injects the whole config into `redis-server`; after the change only the writer's ExecStartPre touches Doppler, and it sees exactly one name). An empty or whitespace/quoting-bearing password is refused (FATAL, unit fails — designed-loud, matching the mount-guard's posture). `redis://:<pw>@127.0.0.1:6379` client auth is unchanged — `AUTH <pw>` resolves to the `default` user either way.

**Site 2 — rendered `inngest-server.service` (rendered by `inngest-bootstrap.sh`, reconcile-always).** The `@@BACKEND_ENV@@` fragment's only consumer moves from the unit to the script, so the durable arm's spelling becomes single-`$` (`redis://:${INNGEST_REDIS_PASSWORD}@...`) — `$$` inside a `.sh` is the PID, not a systemd escape. The SQLite fail-safe arm (`unset INNGEST_POSTGRES_URI`) is preserved verbatim — #5560 requires actively suppressing the env var Doppler injects. `set -u` makes an absent signing key fail the launch loudly. The durable sentinel stays on the unit's argv: `ci-deploy.sh:4247` + `:5868`, `inngest-inventory.sh:438`, `inngest-wiped-volume-verify.sh:247`, and the cloud-init latch check (`cloud-init-inngest.yml:~1543`, `cat /etc/systemd/system/inngest-server.service` + grep) all keep working because `@@BACKEND_FLAGS@@` remains in the `ExecStart` line. Name chosen is `inngest-server-launch.sh` (not `-start`) because `inngest-server-start-REFUSED` is a live phone-home marker string (inngest-bootstrap.sh:1814, inngest.test.sh:2340) — a substring-colliding name would poison every grep anchor.

**Corpus stage.** The stage scans the same per-unit `execs` the wrapper stage iterates. For each Exec directive of a doppler-run unit it extracts `bash -c` bodies (both single-quoted forms — the literal `'...'` and the nested-escape `'\''...'\''`), resolves `@@NAME@@` sentinels inside them against `NAME='...'`/`NAME="..."` assignments in the same source file (so the `BACKEND_ENV` fragment's expansion is seen even though it is not literal in the directive), and flags every `\$+\{?[A-Z][A-Z0-9_]{2,}` expansion except `${!...}` (the wrapper stage's grammar — excluded so `web-git-data-probe.service` is not double-flagged; it stays covered by its existing `WRAPPER_ACK_REASONS` entry). `sh -c`/dash bodies are out of scope: the exploit class is bash-specific (`SHELLOPTS`, `BASH_ENV`, `bash -x` — dash honours none of them). Population today after fix: zero findings; `INNER_C_ACK_REASONS` starts empty with `INNER_C_ACK_CARDINALITY = 0`, ratchet-only downward as a convention note (an ack is added only with a written reason).

### Implementation Phases

#### Phase 1: Failing assertions (TDD)

- `doppler-injection-bound.test.sh`: add the inner-`-c` stage (scanner + `INNER_C_ACK_REASONS`/`INNER_C_ACK_CARDINALITY`/`MIN_INNER_C_UNITS` + census line + identity pins for `inngest-redis.service` and the rendered `inngest-server.service` heredoc) and the mutation rows below. Suite must go RED on the two live sites.
- `inngest.test.sh`: add the failing assertions for the new shape — a `SERVERLAUNCH_BLOCK` extraction (mirroring `SERVER_UNIT_BLOCK`), the refusal-first ordering assert, the `sh -x`/`bash -x` replay block (exit 78, no sentinel in output or logger sink, guard-removed positive control — mirror :439-463), and re-anchored assertions at :2434/:2464/:2497-2498/:2554-2574 pointing at the launch script where the literal moved.
- Success criteria: both suites RED, attributed to the two live sites.
- Estimated effort: ~200 lines of test.

#### Phase 2: Site 1 — `inngest-redis.service` + conf + acl writer

- `inngest-redis-bootstrap.sh`: new step (after 3.5) installing `/usr/local/bin/inngest-redis-acl.sh` via `install -m 0755 /dev/stdin ... <<'ACLEOF'`; refusal first, then validation, then atomic 0600 write.
- `inngest-redis.conf`: `aclfile /mnt/data/redis/inngest-redis.acl` + comment rewrite (the `requirepass` injection note is falsified by this change).
- `inngest-redis.service`: `ExecStartPre` for the acl writer after the mount-guard; `ExecStart` drops `doppler run` and `bash -c`; comment updates (the "literal `$INNGEST_REDIS_PASSWORD` appears in `ps`/journal" rationale is removed — nothing expands).
- Success criteria: `grep -c 'bash -c' inngest-redis.service` = 0; suite's inner-`-c` stage reports no finding for the unit.
- Estimated effort: ~120 lines.

#### Phase 3: Site 2 — rendered `inngest-server.service` + launch script

- `inngest-bootstrap.sh`: `SERVERLAUNCHEOF` heredoc + `chmod 0755` (reconcile-always, outside `SKIP_BINARY_INSTALL`, next to the unit write); `ExecStart` rewrite; `BACKEND_ENV` durable fragment re-spelled single-`$` and its `@@BACKEND_ENV@@` substitution retargeted from `unit_content` to the script content; comment updates at :1549-1587.
- Success criteria: rendered unit carries no `$`/`${` expansion of any Doppler-injected name; `@@BACKEND_FLAGS@@`/`@@SDK_URL@@`/`@@DOPPLER_CONFIG@@` substitution points unchanged; suite green.
- Estimated effort: ~80 lines.

#### Phase 4: Comments sweep + full green run

- `cat-deploy-state.sh:746-747` comment (names the old `doppler run -- bash -c` shape); `inngest.tf:166` comment ("inngest-server + inngest-redis ExecStart build" — the redis side now delivers via aclfile).
- Run `doppler-injection-bound.test.sh`, `inngest.test.sh`, `journald-config.test.sh`, `vector-admission.test.sh`, `cloud-init-inngest-bootstrap.test.sh`, `cloud-init-inngest-provision-unit.test.sh`, `cat-deploy-state.test.sh` green.
- Success criteria: all touched suites green; no other suite reds.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Keep `--requirepass` but move expansion into a `redis-server` wrapper script | Rejected — the password still lands on `redis-server`'s argv in `/proc/<pid>/cmdline` (0444) for the pre-proc-title window and stays `CONFIG GET`-readable; aclfile removes it from argv AND stores SHA256 in memory. |
| `include` a generated `requirepass.conf` fragment | Viable but strictly worse than aclfile: same file-delivery shape, keeps `CONFIG GET requirepass` returning cleartext to any authed loopback client; ACL stores hashes. Recorded as the fallback if aclfile hits a Redis-version wall (needs ≥6; Ubuntu 24.04 ships 7.x). |
| `rename-command` (e.g. `rename-command CONFIG ""`) as the delivery | Rejected as *delivery* — it does not deliver the password at all; orthogonal hardening the issue only mentions as an option alongside aclfile. |
| Move `@@BACKEND_FLAGS@@` into the launch script (unit argv carries nothing) | Rejected — `--postgres-max-open-conns` on the unit's ExecStart is the durable-detection sentinel for three runtime parsers + the cloud-init latch (`ci-deploy.sh:4247/:5868`, `inngest-inventory.sh:438`, `inngest-wiped-volume-verify.sh:247`, `cloud-init-inngest.yml:~1543`). Moving it falsifies every one. |
| `--only-secrets` bound on the rendered `inngest-server.service` ExecStart | Declined as scope — the launch script legitimately needs four env names and no seam makes it bound-required; a bound is a separate tightening, not part of this residual. |
| Flag expansions in `sh -c` (dash) bodies too | Declined — the exploit class (SHELLOPTS/BASH_ENV/`-x`) is bash-specific; the six outer `/bin/sh -c` units' `$D`/`$DOPPLER_TOKEN` expansions are not traceable by this vector. If the shell ever changes to bash, the stage's `sh -c` arm can be widened deliberately. |

## Research Insights

**Premise Validation (Phase 0.6).** Issue #11103 OPEN (`type/security`, `priority/p2-medium`, `domain/engineering`, `meta/machinery`), no closing PRs. Site 1 verified: `inngest-redis.service:45`. Site 2 verified: `inngest-bootstrap.sh:1664` + the `BACKEND_ENV` durable arm at :1747 (a second credential expansion inside the same inner `bash -c`). `SyslogIdentifier=inngest-redis` is in vector.toml's Source 4 tag set (:150/:218); Source 1 `include_units = ["inngest-server.service", ...]` (:109) admits the unit at any priority. Prior pair `fa3409760c` (PR #11097) merged 2026-10-25 with exactly the shape the issue suggests. `doppler-injection-bound.test.sh` wrapper stage confirmed bound to `INDIRECT_RE` (`\$\{!...}`) — the escape mechanism is real. Vinngest pin is now `v1.1.61` (two bumps past the cited v1.1.59 — ADR-232 bot). No stale premises.

**Property List (Phase 0.6b).**

1. P1 — A `SHELLOPTS=xtrace`/`BASH_ENV`/`-x` launch of `inngest-redis.service` never prints `INNGEST_REDIS_PASSWORD` to stderr/journald.
2. P2 — Same for `inngest-server.service`: `INNGEST_SIGNING_KEY` and `INNGEST_REDIS_PASSWORD` (inside `INNGEST_REDIS_URI`) never print.
3. P3 — The Redis password never sits on `redis-server`'s argv (`/proc/<pid>/cmdline` 0444) or `CONFIG GET` output.
4. P4 — The guard corpus catches a regression of this class (plain expansion inside an inner `bash -c` of a doppler-run Exec directive).
5. P5 — No invariant breaks: `--postgres-max-open-conns` sentinel stays on unit argv; `unset INNGEST_POSTGRES_URI` fail-safe; `SyslogIdentifier`/vector pairing; #5560 env-delivery.

**Cut List (Phase 0.6b).** Nothing cut — xtrace refusal + aclfile + corpus stage each buy a distinct property no existing mechanism covers. The closest existing mechanism (wrapper stage) covers `${!...}` only — the gap is the point of the issue.

**Relevant files.** `apps/web-platform/infra/inngest-redis.service:45`, `inngest-redis.conf`, `inngest-redis-bootstrap.sh` (mount-guard install precedent ~step 3.5), `inngest-bootstrap.sh:1664/:1747` (+ heredoc precedents at :184/:626), `doppler-injection-bound.test.sh` (INDIRECT_RE :530, wrapper stage :728-744, WRAPPER_ACK_REASONS :323, mutation battery :938-1421), `inngest.test.sh` (xtrace replay :439-463, ExecStart assertions :2417-2593), `vector.toml:109/:150/:218`, `cat-deploy-state.sh:746`, `inngest.tf:166`.

**Institutional learnings.**

- `2026-06-18-inngest-secrets-env-not-argv-and-detection-sentinel-swap.md` — env-not-argv delivery; the detection-sentinel swap (`--postgres-max-open-conns`) this plan must NOT break; `unset INNGEST_POSTGRES_URI` is load-bearing in the fail-safe arm.
- `specs/feat-one-shot-9757-argv-bearer-sweep-combined/decision-challenges.md` — C1 resolution: editing `inngest-bootstrap.sh` reddens `GuardA` in `cloud-init-inngest-bootstrap.test.sh` by design until a `vinngest-v*` tag propagates (ADR-232). Expected, non-required.
- `2026-09-04-i-shipped-the-defect-class-my-guard-existed-to-forbid.md` — the remediation's own text must not match the classifier (the suite's fixture writes are literal strings; the stage must not flag its own test heredocs — `.test.sh` files are already excluded by `enumerate_all` at :457).

**External.** Redis `aclfile` directive (Redis ≥6; Ubuntu 24.04 `redis-server` is 7.0.x): `aclfile /path` in redis.conf, file lines `user default on >pass ~* &* +@all`; mutually exclusive with inline `user` lines in the conf (none present); ACL stores SHA256 (`ACL LIST`/`GETUSER` never return cleartext — strictly better than `CONFIG GET requirepass`). Inngest connects `redis://:pw@` → `AUTH` → default user — unchanged. If the aclfile is absent at start, Redis fails loud (consistent with the unit's designed-loud posture).

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Reality | Plan response |
|---|---|---|
| "vinngest pin v1.1.59" | Pin is `v1.1.61` on main (two bumps since) | Cosmetic — cite current pin; the ADR-232 bump mechanics are unchanged |
| Two live sites | Two live sites plus a second credential inside site 2 (`BACKEND_ENV` builds `INNGEST_REDIS_URI` from `$${INNGEST_REDIS_PASSWORD}` — same inner `bash -c`) | Fix covers all three expansions; the corpus stage resolves `@@` fragments so the fragment-borne expansion is guarded too |
| "`inngest-redis.service` is not host-bound" | Correct — it is OCI-image-staged + bootstrap-installed; `inngest-server.service` renders reconcile-always but the dedicated host is force-replace-only (SOLEUR-DEBT note at `inngest-bootstrap.sh:60`) | Site-2 fix lands repo-side now, takes effect on web hosts at next bootstrap and on the dedicated host at the sanctioned replace |

## User-Brand Impact

- **If this lands broken, the user experiences:** stalled background work — `inngest-redis.service` failing (bad aclfile/writer) or `inngest-server` crash-looping (launch-script defect) kills every scheduled and event-driven Inngest job; users see reminders/cron tasks silently not fire. The #7286 precedent showed this shape running ~16h before anyone noticed.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the pre-fix residual already described — a Doppler-minted Redis password + signing key in Better Stack logs (off-box third party, operator-visible); a forged-event scenario could inject work on behalf of users. The fix removes the vector; a botched fix that *silently* re-adds an expansion is the worst outcome (the corpus stage exists precisely to detect it).
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** both failure directions are fleet-wide, not single-user — an outage stalls every user's background jobs, and a credential leak exposes shared infrastructure secrets, not one user's record.

## Observability

```yaml
liveness_signal:
  what: "inngest-server-probe fields `redis_active`/`server_active` + the web-1-fed `betteruptime_heartbeat.inngest_consumer` beat (dies in ~4 min when the server stops serving); the corpus stage itself is the pre-merge regression detector"
  cadence: "probe on its timer; beat continuous; suite per-PR"
  alert_target: "Better Stack monitor -> Slack/founder (existing wiring, unchanged)"
  configured_in: "apps/web-platform/infra/inngest.tf; apps/web-platform/infra/vector.toml (Sources 1/4); apps/web-platform/infra/inngest-server-probe.sh"
error_reporting:
  destination: "journald -> Vector -> Better Stack source 2457081 (SyslogIdentifier=inngest-redis via Source 4; inngest-server.service via Source 1)"
  fail_loud: "`inngest-redis.service: Failed with result 'exit-code'` restart-loop rows (the #7286 signature) and `[FATAL] refusing to run under xtrace` refusal rows; missing-ping on the consumer beat"
failure_modes:
  - mode: "acl file missing/unwritable or password empty/malformed -> ExecStartPre fails -> unit restart-loops"
    detection: "Better Stack journald rows on tag inngest-redis + probe `redis_active=inactive` field"
    alert_route: "Better Stack monitor (existing)"
  - mode: "INNGEST_SIGNING_KEY absent -> launch script aborts under set -u -> inngest-server fails to start"
    detection: "Source 1 journald rows + consumer beat silence"
    alert_route: "Better Stack monitor (existing)"
  - mode: "a future edit re-introduces a plain expansion inside a doppler-run bash -c body"
    detection: "doppler-injection-bound.test.sh inner-`-c` stage FINDING at CI (pre-merge)"
    alert_route: "red CI leg (deploy-script-tests)"
logs:
  where: "journald -> Vector -> Better Stack source 2457081"
  retention: "per Better Stack plan; unchanged"
discoverability_test:
  command: "grep -c 'bash -c' apps/web-platform/infra/inngest-redis.service"
  expected_output: "0"
```

## Encryption Posture

```yaml
at_rest:
  - store: "/mnt/data/redis/inngest-redis.acl (new: generated credential file on the AOF volume)"
    mechanism: "luks — dedicated host: hcloud_volume.inngest_redis_luks opened as /dev/mapper/inngest-redis (inngest-redis-luks.tf, cloud-init-inngest.yml LUKS stage); co-located web host: the workspaces LUKS volume (ADR-119). 0600 deploy:deploy inside a 0750 dir"
    evidence: "apps/web-platform/infra/inngest-redis-luks.tf; apps/web-platform/infra/cloud-init-inngest.yml; the mount-guard refuses to run Redis on an unmounted/ephemeral /mnt/data"
    defends_against: "a raw volume snapshot or detached-disk read exposing the password file"
    does_not_defend: "a root or deploy-group process on the running host; a Doppler token holder (who reads the same value); the journald/xtrace vector this fix removes at the delivery layer"
    disclosed_as: "not-publicly-claimed"
    live_verification: "available: the existing mount-guard asserts /mnt/data is the LUKS store before Redis starts (ExecStartPre ordering keeps that proof ahead of the acl write)"
in_transit:
  - connection: "Doppler API -> host (acl writer's `doppler run`)"
    enforced_at: "apps/web-platform/infra/inngest-redis.service ExecStartPre; Doppler CLI"
    tls: "HTTPS, TLS >= 1.2 (Doppler API)"
    cert_verification: "on"
    does_not_defend: "a host-side env scrape by a deploy-group process; off-box journald shipping (the defect this plan fixes)"
    disclosed_as: "not-publicly-claimed"
  - connection: "host journald -> Better Stack (Vector)"
    enforced_at: "apps/web-platform/infra/vector.toml Sources 1/4"
    tls: "HTTPS to ingest endpoint"
    cert_verification: "on"
    does_not_defend: "credential CONTENT reaching the sink once shipped — exactly the leak vector; mitigation is not emitting it (this fix), not transport"
    disclosed_as: "not-publicly-claimed"
```

## Infrastructure (IaC)

### Terraform changes

None new — no new TF resources, provisioners, or secrets. `inngest.tf` gets a comment-only edit (:166, the "ExecStart build" clause). `INNGEST_REDIS_PASSWORD` stays Doppler-managed; on the dedicated host it is `random_password.inngest_redis_password_dedicated` into `soleur-inngest/prd` (inngest-host.test.sh:41), on co-located hosts the `soleur/prd` copy (inngest.tf:168-186) — the acl writer reads whichever the unit's `doppler run` injects, host-agnostic by construction.

### Apply path

(c) cloud-init + idempotent bootstrap — the established delivery, no new mechanism: `inngest-redis.{service,conf}` and `inngest-redis-bootstrap.sh` ride the `soleur-inngest-bootstrap` OCI image to `/tmp` staging and install via the existing bootstrap on existing hosts (webhook.service path) and via cloud-init `docker cp` on fresh hosts (cloud-init.yml:735-736, cloud-init-inngest.yml:983 `STAGED` list — unchanged, the acl script is heredoc-internal to the bootstrap). `inngest-bootstrap.sh` edits fire the ADR-232 `vinngest-v*` publish flow — `GuardA` in `cloud-init-inngest-bootstrap.test.sh` is designed-advisory red (non-required) until the tag propagates, the same posture the argv-bearer pair documented. The rendered `inngest-server.service` + launch script are reconcile-always: web hosts pick them up at the next bootstrap run; the dedicated host is force-replace-only (SOLEUR-DEBT, inngest-bootstrap.sh:60) so it picks them up at the sanctioned replace — matches the issue's host-bound residual note. Blast radius: a redis restart and an inngest-server restart per reconcile; identical to today's unit-rewrite behavior.

### Host fan-out

No new `terraform_data` SSH provisioner is added, so the twin/role-only/birth-covered classification has no new member. Both artifacts reach every host that runs them through the shared bootstrap channel (web hosts + dedicated host), not a per-host dialer.

### Distinctness / drift safeguards

`dev` unaffected (durable Inngest is prd-only). The acl file is generated at start on every host — no per-host secret material is committed or baked into the image. `ignore_changes`/state notes unchanged.

### Vendor-tier reality check

None — no new vendor resource.

## Architecture Decision (ADR/C4)

No new ADR: this applies the already-decided #10637/#10363 resolve-after-refusal pattern and the #5560 env-delivery posture to two residual sites; the aclfile choice is a mechanism swap inside the existing Doppler→unit→process credential boundary, not a new boundary. Enumeration per the C4 completeness mandate (all three files read): no new external human actor; no new external system or vendor (Redis is already `inngestRedis`, Better Stack `betterstack`); no new container/data store (the acl file lives inside the already-modeled `inngestRedis` container); no actor↔surface relationship change (the `inngest -> betterstack` journald edge at model.c4:792 is the channel being *fixed*, and stays accurately described). No `.c4` edit required; `inngestRedis`'s description makes no auth-delivery claim this change falsifies.

## Guard Contract

### Guard 1 — inner `bash -c` expansion stage (doppler-injection-bound.test.sh)

**Property.** No Exec directive of a doppler-run unit expands a Doppler-injected name inside a `bash -c` body — plain `$NAME`, `${NAME}`, or systemd-escaped `$${NAME}` all count — whether the expansion is literal in the directive or arrives through a `@@NAME@@` sentinel fragment; `${!...}` indirect expansions remain the existing wrapper stage's domain.

**Assembly.** The per-unit `execs` list the scanner already builds (`.service` files, `.sh`/`.tf` heredoc bodies, cloud-init `content:` blocks, and `Exec*=`-injected shell assignments — the five surfaces enumerated at `enumerate_all`), for every unit with a `doppler run` directive, PLUS the `@@SENTINEL@@`-substituted fragments assigned in the same source file. There are two chokepoints, stated deliberately: the Exec directive itself, and the render-fragment a directive interpolates.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore `--requirepass "$INNGEST_REDIS_PASSWORD"` inner `bash -c` in `inngest-redis.service` | RED (inner-`-c` FINDING, attributed to the unit) |
| 2 | Delete the stage's per-unit counter (a stage that examines nothing) | RED via the `inner_c_units_checked` census floor (own dispatch) |
| 3 | A second fixture unit adds a `bash -c` expansion after a compliant first member | RED (a check that stops at the first member is the defect) |
| 4 | Re-introduce a secret-bearing `@@FRAGMENT@@` (`BACKEND_ENV='export X="$${SECRET}"'`) inside a `-c` body while the directive text carries only the sentinel | RED (the sentinel-resolution arm, not literal-text matching) |
| 5 | Scanner-side: neuter the inner-`-c` regex so it never matches | RED via identity pins (the two fixed units must be *seen* clean — a scanner that sees nothing reports no findings and must not pass) |
| 6 | A `sh -c` (dash) body expands `$DOPPLER_TOKEN` | GREEN (must-PASS, non-canonical: dash honours neither SHELLOPTS nor BASH_ENV — out of the exploit class by design; widening is a deliberate later edit) |
| 7 | `web-git-data-probe.service`'s inner `${!GIT_DATA_HEARTBEAT_URL_KEY}` expansion | GREEN under the new stage (still flagged by the existing wrapper stage and covered by its ack — the stages must not double-flag) |

**Anchor.** `INNER_C_ACK_CARDINALITY` pins the escape-hatch size (ratchet-down only); the census floor on examined units is non-zero and derived (`MIN_INNER_C_UNITS`); identity pins name the two remediated units so a scanner whose enumeration silently loses a surface reds on the pin, not on a count.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "the ExecStart expands nothing and the target resolves the credential after an unconditional xtrace refusal" | Phase 3 (FR-3, FR-4) / `inngest-bootstrap.sh` + rendered launch script | mapped |
| 2 | "or, for redis where `requirepass` must be an argv word, an aclfile/rename-command delivery that keeps the secret off argv entirely" | Phase 2 (FR-1, FR-2) / `inngest-redis.service` + `inngest-redis.conf` + `inngest-redis-bootstrap.sh` | mapped |
| 3 | "the corpus likely needs a stage for inner `bash -c` expansion" | Phase 1 (FR-5) / `doppler-injection-bound.test.sh` | mapped |
| 4 | "TDD: infra suites are `*.test.sh` — write the failing assertions first" | Phase 1 ordering | mapped |
| 5 | "`apps/web-platform/infra/**` edits fire the production apply on merge (GuardA designed-advisory red is expected per ADR-232 until the pin propagates — non-required)" | `## Infrastructure (IaC)` Apply path | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| aclfile delivery + acl-writer script | "an aclfile/rename-command delivery that keeps the secret off argv entirely" | asked |
| launch script + refusal + resolve-after-refusal | "the ExecStart expands nothing and the target resolves the credential after an unconditional xtrace refusal" | asked |
| `--only-secrets INNGEST_REDIS_PASSWORD` on the writer's ExecStartPre | — | inferred — justification: the wrapper injects the whole config today; bounding the one name the writer reads is the same #7761 hygiene the host's own guard prescribes and costs one flag |
| corpus stage + ack + census + mutation rows | "the corpus likely needs a stage for inner `bash -c` expansion" | asked |
| `@@SENTINEL@@` fragment resolution inside the stage | — | inferred — justification: without it the stage sees `@@BACKEND_ENV@@` as text and the durable arm's `$${INNGEST_REDIS_PASSWORD}` expansion escapes — the guard would certify the site it was built to catch |
| `inngest.test.sh` re-anchoring + xtrace replay | "TDD: infra suites are `*.test.sh`" | asked |
| comment edits (`cat-deploy-state.sh`, `inngest.tf`, unit headers) | — | inferred — justification: comments that describe the removed shape falsify the mechanism they annotate (the repo's own `#6536`-class rule) |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform` (all files under `apps/web-platform/infra/`)
- Planned files: ~8 | Estimated changed lines: ~450 (≈200 test, ≈250 source+comments)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Infrastructure security hardening on the inngest host/fleet arc. CTO-leader spawn was unavailable in this harness (no Task/subagent tool); the orchestrator assessed inline: the change is mechanism-preserving (same delivery channels, same env-not-argv posture), the durable-detection sentinel contract is the load-bearing constraint and is preserved by keeping `@@BACKEND_FLAGS@@` on the unit argv, and the aclfile choice removes a cleartext surface (`CONFIG GET requirepass`) as a side benefit. No architectural novelty beyond the documented residual class.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies contain none of the planned paths (checked 2026-10-26).

## Acceptance Criteria

- [ ] **AC1** — `inngest-redis.service` `ExecStart` is `ExecStart=/usr/bin/redis-server /mnt/data/redis/inngest-redis.conf` (no `doppler run`, no `bash -c`, no `$`/`${` expansion of any injected name); a new `ExecStartPre=/usr/bin/doppler run --config ${DOPPLER_CONFIG} --only-secrets INNGEST_REDIS_PASSWORD -- /usr/local/bin/inngest-redis-acl.sh` runs AFTER the mount-guard `ExecStartPre`; `SyslogIdentifier=inngest-redis` unchanged.
- [ ] **AC2** — `inngest-redis.conf` declares `aclfile /mnt/data/redis/inngest-redis.acl` and no `user`/`requirepass` directives; `inngest-redis-bootstrap.sh` installs `/usr/local/bin/inngest-redis-acl.sh` (heredoc, `install -m 0755`, reconcile-always); the script's first executable statement is the unconditional `case "$-"` xtrace refusal (exit 78, value-free), after which it validates `INNGEST_REDIS_PASSWORD` (non-empty, no whitespace/quote/control bytes — FATAL exit otherwise) and atomically writes `user default on >"$INNGEST_REDIS_PASSWORD" ~* &* +@all` at 0600 deploy:deploy.
- [ ] **AC3** — The rendered `inngest-server.service` `ExecStart` is `ExecStart=/usr/bin/doppler run --config @@DOPPLER_CONFIG@@ -- /usr/local/bin/inngest-server-launch.sh @@BACKEND_FLAGS@@ --poll-interval 60 --sdk-url @@SDK_URL@@`: no `bash -c`, no `$`/`${`/`$${` expansion; `@@BACKEND_FLAGS@@` (with `--postgres-max-open-conns` FIRST in the durable arm) stays on the unit argv so `systemctl show -p ExecStart` still yields the sentinel for `ci-deploy.sh`, `inngest-inventory.sh`, `inngest-wiped-volume-verify.sh`, and the cloud-init latch check.
- [ ] **AC4** — The rendered `/usr/local/bin/inngest-server-launch.sh` carries, in order: unconditional `case "$-"` refusal (exit 78); `set -u`; `export INNGEST_SIGNING_KEY="${INNGEST_SIGNING_KEY#signkey-prod-}"`; the `@@BACKEND_ENV@@` sentinel (substituted into the SCRIPT — durable `export INNGEST_REDIS_URI="redis://:${INNGEST_REDIS_PASSWORD}@127.0.0.1:6379"` / fail-safe `unset INNGEST_POSTGRES_URI`, verbatim semantics); `exec /usr/local/bin/inngest start --host 0.0.0.0 --port 8288 --sqlite-dir /var/lib/inngest "$@"`. Install is reconcile-always (outside `SKIP_BINARY_INSTALL`) + `chmod 0755`.
- [ ] **AC5** — `doppler-injection-bound.test.sh` gains the inner-`-c` stage: flags plain `$NAME`/`${NAME}`/`$${NAME}` expansions inside `bash -c` bodies (all quoting/nesting spellings) of Exec directives in doppler-run units; resolves `@@NAME@@` sentinels against same-file `NAME='...'`/`"..."` assignments; excludes `${!...}` (wrapper stage's domain); `INNER_C_ACK_REASONS` (empty, `INNER_C_ACK_CARDINALITY = 0`, ratchet-only); `inner_c_units_checked` census floor; identity pins on `inngest-redis.service` + the rendered `inngest-server.service`; the mutation-matrix rows all fire; `MIN_ASSERTIONS` raised to the measured green count.
- [ ] **AC6** — `inngest.test.sh` (or a sibling suite) replays the REAL rendered launch script AND the acl writer under `sh -x`/`bash -x` and `SHELLOPTS=xtrace`/`BASH_ENV`: exit 78, refusal text on a non-trace line, sentinel value absent from output and any sink — plus a guard-removed positive control that DOES trace the sentinel.
- [ ] **AC7** — No `vector.toml` change; `journald-config.test.sh` and `vector-admission.test.sh` stay green (SyslogIdentifier/tag pairing unchanged).
- [ ] **AC8** — Post-fix, `doppler-injection-bound.test.sh`, `inngest.test.sh`, `cloud-init-inngest-bootstrap.test.sh`, `cloud-init-inngest-provision-unit.test.sh`, `cat-deploy-state.test.sh`, `inngest-cutover-flip.test.sh` all pass; no other registered suite reds.
- [ ] **AC9** — `grep -c 'bash -c' apps/web-platform/infra/inngest-redis.service` prints `0` and the rendered `inngest-server.service` ExecStart carries no `$`/`${`/`$${` expansion — the two sites carry zero expansions.

## Deepen-Plan Verification (Phase 4.x gates)

Run 2026-10-26 (headless subagent; research phases executed inline — no Task/subagent tool exists on this harness):

- **4.5 network-outage / 4.55 downtime-cutover:** skipped — no SSH keyword trigger, no `terraform apply` against provisioner-bearing resources, no new offline-inducing operation (reconcile restarts are ordinary deploy behavior; the dedicated host lands the rendered fix at the already-sanctioned replace).
- **4.6 user-brand impact:** PASS — section present, all three required lines, threshold `aggregate pattern` (no scope-out needed).
- **4.7 observability:** PASS — 5-field schema; discoverability `grep -c 'bash -c' …` is an allowlisted verb, <15s, literal `expected_output: "0"`, no `ssh `.
- **4.8 PAT-shaped variables:** PASS — none introduced.
- **4.9 UI wireframe:** skip — no UI-surface files in the edit lists.
- **4.10 encryption posture:** PASS — at_rest/in_transit fields all non-placeholder; the new acl file's LUKS mechanism is evidenced (inngest-redis-luks.tf + mount-guard ordering); `does_not_defend` named per row.
- **4.11 guard contract:** PASS — one `### Guard` entry, structural Assembly (the `execs` chokepoint + the `@@SENTINEL@@` fragment chokepoint, not a member list), 7 mutation rows incl. own-dispatch (#2), second-member (#3), suite-side (#5), and must-PASS non-canonical rows (#6, #7); Anchor names what outside the diff must move.
- **4.12 scope check:** PASS — exactly one unfenced `## Scope Check`; every ask mapped; inferred items carry justifications; single-PR recommendation (1 subsystem, ~8 files, ~450 lines).
- **4.13 task design:** skip — no new autonomous-task surface (a rendered script + a test stage are not registered checks/timers/workflows).
- **Deepen reconciliation added:** `web-git-data-probe.service` is a third inner-`bash -c` member (expands `${!GIT_DATA_HEARTBEAT_URL_KEY}`) — already acked under the indirect wrapper stage; the new stage's `${!...}` exclusion avoids double-flagging (mutation row #7 pins this).
- **ExecStartPre semantics verified:** without a `+` prefix the writer runs as `User=deploy`, so it can only write inside `ReadWritePaths=/mnt/data/redis`; ordering after the mount-guard guarantees the acl file lands on the proven mount.
- **No load-bearing plan corrections** → `tasks.md` unchanged in this pass.

## Test Scenarios

- Given a doppler-run unit whose `ExecStart` is `doppler run -- bash -c '... --requirepass "$SECRET"'`, when the corpus stage runs, then a FINDING names the unit and the expansion (pre-fix live row → post-fix fixture row). `unit`
- Given the rendered `inngest-server-launch.sh` under `SHELLOPTS=xtrace`/`BASH_ENV`/`bash -x`, when launched, then exit 78 before any expansion evaluates and the sentinel never reaches stderr. `unit`
- Given the same script with the `case "$-"` block deleted, when launched under `-x`, then the sentinel IS traced (positive control — the refusal rows can see a leak). `unit`
- Given `INNGEST_REDIS_PASSWORD` empty or carrying whitespace/`"`/`#`, when the acl writer runs, then FATAL non-zero, no file write. `unit`
- Given the durable arm, when the launch script is rendered, then `export INNGEST_REDIS_URI="redis://:${INNGEST_REDIS_PASSWORD}@127.0.0.1:6379"` appears; given the fail-safe arm, `unset INNGEST_POSTGRES_URI` appears. `unit`
- Given `systemctl show -p ExecStart inngest-server.service` on a durable host, then `--postgres-max-open-conns` is present (sentinel contract). `integration`
- Given `AUTH <pw>` on `redis-cli -h 127.0.0.1`, then the default user authenticates (inngest `redis://:pw@` compat). `integration`

## Success Metrics

- `bash apps/web-platform/infra/doppler-injection-bound.test.sh` green with the new stage active and zero findings.
- `grep -c 'bash -c' inngest-redis.service` = 0; rendered server unit carries no `$`/`${` expansion.
- No regression in sentinel parsers (all `--postgres-max-open-conns` consumers unchanged and still satisfied).

## Dependencies & Risks

- **Risk:** `GuardA` (`cloud-init-inngest-bootstrap.test.sh`) designed-advisory red while the `vinngest-v*` pin propagates — expected per ADR-232, non-required; the publish workflow authors the bump.
- **Risk:** site-2 fix is inert on the dedicated host until the sanctioned replace (force-replace-only); residual stays live there in the interim — acceptable per the issue (rotation is operator-gated anyway).
- **Risk:** aclfile + `requirepass` interplay — none: no `requirepass`/`user` line remains in the conf.
- **Dependency:** Redis ≥6 (`aclfile`) — Ubuntu 24.04 `redis-server` is 7.x; a fallback to generated-`requirepass`-include exists if a host ever runs older.

## References & Research

- Prior pair: `fa3409760c` (PR #11097, #10363/#10093) — xtrace refusals + resolve-after-refusal in `inngest-consumer-probe.sh`, POSIX refusal in rendered heartbeat bodies.
- `apps/web-platform/infra/doppler-injection-bound.test.sh` — Guard 2 (#7761) + wrapper stage (#9639).
- `apps/web-platform/infra/inngest-consumer-probe.sh:13-15` — the canonical refusal block.
- `knowledge-base/project/learnings/2026-06-18-inngest-secrets-env-not-argv-and-detection-sentinel-swap.md`.
- Redis ACL docs: `aclfile` directive + `user default on >pass` rule syntax (redis.io ACL reference).
- Related: #11103 (this fix), #9639, #10363, #10093, #7761, #5560, #10382 (operator-gated signing-key rotation), #10390 (host-replacement arc).
