---
title: "inngest ExecStarts expanded live credentials inside an inner bash -c — a traced launch prints them to journald, which Vector ships off-box"
date: 2026-10-26
incident_pr: 11159
incident_window: "Latent since the doppler-run ExecStart shape was introduced — every `bash -x`/`SHELLOPTS=xtrace`/`BASH_ENV` launch of the redis or server units would have printed the resolved secret to stderr, which journald captures and Vector ships to Better Stack source 2457081. No traced launch is on record; the exposure is conditional, not confirmed-realized."
recovery_at: "Repo-side fix merged in PR #11159. Web hosts reconcile the new units + scripts at the next bootstrap/webhook cycle; the dedicated host (force-replace-only, SOLEUR-DEBT) picks it up at the sanctioned replace under the #10390 arc. Signing-key + password rotation stays operator-gated per #10382 — rotation, not the code change, is what expires any already-captured value."
suspected_change: "Latent since the units were authored — no single recent change caused it. `doppler run -- bash -c '... $SECRET ...'` put the credential inside a shell body that xtrace echoes verbatim; the corpus stage that guards expansion on Exec lines did not look inside `-c` bodies at all (the gap #11171 enumerates further)."
brand_survival_threshold: aggregate pattern
status: ongoing
triggers:
  - security (credential exposure path — conditional on a traced launch; shared Doppler-minted infra credentials, off-box third-party sink)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
# Classification rationale: the exposed values are machine credentials (redis password,
# signing key) minted by Terraform random_password — no personal data was exposed, accessed,
# altered, or lost, so GDPR Art. 33/34 do not apply (both false, rationale n/a). Threshold is
# `aggregate pattern` per the CTO ruling in decision-challenges.md: a realized leak exposes
# shared infra credentials to an off-box sink and a failed queue host stalls every user's
# scheduled/event-driven jobs — not a single-user incident.
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-destroy`.
- `human` — Operator did this directly.

# Incident Overview

Two doppler-wrapped `ExecStart`s expanded credentials inside an inner `bash -c` body:
`inngest-redis.service` resolved `$INNGEST_REDIS_PASSWORD` into `--requirepass` argv, and the
rendered `inngest-server.service` ran `bash -c '...'` whose `@@BACKEND_ENV@@` fragment carried
`$${INNGEST_REDIS_PASSWORD}` and the signing key. Under any traced launch — `bash -x`,
`SHELLOPTS=xtrace`, `BASH_ENV` — the expanded values print to stderr, journald captures them, and
Vector ships them to an off-box log sink. No traced launch is on record, so this is a latent
exposure path, not a confirmed leak — but the values it would expose are live production
credentials, and the residual on the dedicated host stays live until the sanctioned replace.

## Status

ongoing — the repo-side fix is merged in PR #11159; rotation of the potentially-exposed
credentials (signing key, redis password) is operator-gated (#10382) and the dedicated host's
residual closes at the sanctioned replace (#10390 arc).

## Symptom

None observable in production — the defect was found by review of the Exec directive shape, not
by an alert. The corpus guard (`doppler-injection-bound.test.sh`) flagged the two live sites on
the new inner-`-c` stage's first RED run.

## Incident Timeline

- **Start time (detected):** 2026-10-26 (issue #11103 filed)
- **End time (recovered):** pending — repo-side merge 2026-10-26; rotation + dedicated-host replace outstanding
- **Duration (MTTR):** repo-side fix same-day; full closure gated on #10382 / #10390

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-10-26 | Latent expansion defect reported as #11103. |
| agent | 2026-10-26 | Plan + deepen + work + review + qa pipeline; aclfile delivery and resolve-after-refusal launch script landed; corpus stage added; PR #11159 shipped. |

## Participants and Systems Involved

`inngest-redis.service`, rendered `inngest-server.service` + `inngest-server-launch.sh`,
`inngest-redis-bootstrap.sh` (acl writer), `doppler-injection-bound.test.sh` (inner-`-c` stage),
journald → Vector → Better Stack source 2457081 (the off-box sink that makes a traced launch an
exfiltration, not just a log line).

## Detection (+ MTTD)

- **How detected:** manual/code review — reported as issue #11103; confirmed by the new corpus stage flagging both live sites.
- **MTTD:** latent for the lifetime of the unit definitions (months); detected on inspection, not by a monitor — see Action Items for the corpus-stage closure of the detection gap.

## Triggered by

system — latent defect in unit definitions, no triggering event.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Inner `bash -c` bodies were outside every expansion guard's scan window | The wrapper stage covers `${!...}` indirection and `enumerate_all` surfaces Exec directives — neither extracted `-c` bodies; the new stage's first run flagged both live sites | — | confirmed |

## Resolution

Site 1 (redis): `ExecStart` is a plain `redis-server <conf>`; a bound `ExecStartPre`
(`--only-secrets INNGEST_REDIS_PASSWORD`) runs a refusal-first acl writer that atomically writes
the `aclfile` at 0600 (SHA256 `#` form). Site 2 (server): credentials resolve inside the rendered
`inngest-server-launch.sh` below an unconditional `case "$-"` xtrace refusal (exit 78); the
`@@BACKEND_FLAGS@@` sentinel stays on unit argv. Detection: new inner-`bash -c` corpus stage
(grammar + `@@SENTINEL@@` resolution + census floor + mutation battery).

## Recovery verification

`doppler-injection-bound.test.sh` 71/71 (mutation battery incl. both remediated sites RED on
re-introduction); `inngest.test.sh` 586/586 incl. `sh -x`/`bash -x`/`SHELLOPTS=xtrace`/`BASH_ENV`
replays (exit 78, sentinel absent) plus a guard-removed positive control that DOES trace;
`grep -c 'bash -c' inngest-redis.service` = 0; rendered ExecStart expansion-free (AC9).

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Credentials printed to journald on a traced launch → the Exec body expanded them inside `bash -c`.
2. Expansions inside `-c` bodies evaded the corpus guard → the stage scanned directive text, never extracted `-c` bodies.
3. The guard's window matched the pattern it was written against → no mutation row enumerated quoting/nesting spellings of `-c`.
4. Unit authoring pattern `doppler run -- bash -c '...'` was idiomatic before the xtrace-refusal convention → the precedent in `inngest-consumer-probe.sh` (refusal-first) was not applied to Exec bodies.

## Versions of Components

- **Version(s) that triggered the outage:** units as of `origin/main` before this merge (`bash -c` ExecStarts).
- **Version(s) that restored the service:** PR #11159 squash merge.

## Impact details

### Services Impacted

`inngest-redis.service`, `inngest-server.service` (restart per reconcile — same as today's unit-rewrite behavior); journald/Vector path unchanged (`SyslogIdentifier` pins verified).

### Customer Impact (by role)

- Prospect: none — no user-facing path reaches the defect.
- Authenticated app user: none realized; a failed inngest host would stall scheduled/event-driven jobs (hence `aggregate pattern`, per the 2026-09 ~16h-unnoticed precedent).
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None — conditional exposure path, no realized loss.

### Team Impact

Operator must still rotate the signing key + redis password (#10382) and run the sanctioned dedicated-host replace (#10390 arc) to retire the residual.

## Lessons Learned

### Where we got lucky

No traced launch is on record — the exposure stayed conditional. The sentinel-flag design kept `--postgres-max-open-conns` on argv, so the fix did not disturb the four sentinel consumers.

### What went well

The corpus-stage TDD shape (RED on both live sites, then the fix) plus QA's enumeration of the advisory-red SET caught a second stale census floor (GuardD) that the designed-advisory label had absorbed.

### What went wrong

The expansion guard's scan window stopped at directive text for the lifetime of the guard — the `-c` body was the exact site the defect class lived in. A suite-level cardinality floor (`GD_ALL == 10`) was left stale by the work phase because the suite's rc=1 was attributed wholly to the designed-advisory GuardA.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #10382 | Operator-gated rotation of INNGEST_SIGNING_KEY (+ redis password) — expires any value a historical traced launch may have captured | open |
| #10390 | Sanctioned dedicated-host replace — the residual `bash -c` ExecStart stays live there (force-replace-only) until this lands | open |
| #11171 | Widen the inner-`-c` stage grammar (double-quoted bodies, fused flag clusters, ANSI-C quoting, fragment producers outside the assignment grammar, `-c` inside target scripts) | open |
