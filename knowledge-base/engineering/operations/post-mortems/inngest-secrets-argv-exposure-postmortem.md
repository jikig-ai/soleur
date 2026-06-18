---
title: Inngest durable secrets exposed in process argv (/proc/cmdline) on the prod host
date: 2026-06-18
incident_pr: "#5561"
brand_survival_threshold: single-user incident
gdpr_art33_notifiable: false
gdpr_art33_rationale: "Not a personal-data breach. The exposed values are infrastructure credentials (inngest Postgres/Redis connection URIs + inngest signing/event keys), not personal data. Exposure was LOCAL-only — readable via /proc/<pid>/cmdline (mode 0444) to a process on the single-tenant prod VM, never remotely. No evidence of access by any unauthorized party; surfaced during routine #5558 debugging. No Art. 33 personal-data-breach clock applies."
gdpr_art34_high_risk_to_individuals: false
gdpr_art34_rationale: "n/a — infrastructure-credential exposure, no personal-data subject impact."
incident: "#5560"
status: unresolved but ended
---

# PIR: Inngest durable secrets exposed in process argv

## Summary

The inngest-server systemd `ExecStart` (introduced by the #5450/#5459 durable-backend work, live on prod since ~2026-06-17) expanded four Doppler-injected secrets — `INNGEST_POSTGRES_URI`, `INNGEST_REDIS_PASSWORD`, `INNGEST_SIGNING_KEY`, `INNGEST_EVENT_KEY` — into the `inngest start` **argv** via `doppler run … bash -c '… --postgres-uri "$X" --signing-key "$Y" …'`. The resolved values were therefore world-readable through `/proc/<inngest-pid>/cmdline` (mode 0444) to any local user/process on the prod VM (`ps -eo args | grep inngest`).

## Status

`unresolved but ended` — the root cause (argv delivery) is fixed in code (PR #5561, merging); the live exposure ends when the env-delivery image deploys, and the exposed credentials are rotated. Both the deploy and the rotation are tracked in #5565.

## Symptom

A routine `ps -eo args | grep inngest` during #5558 debugging revealed the full Postgres connection string (with password) and the Redis password in cleartext on the prod host's process list.

## Detection (+ MTTD)

- **How detected:** incidentally, by a human, during #5558 inngest pg-pool debugging — NOT by an alert.
- **MTTD:** exposure was live from the #5450/#5459 durable-backend cutover (~2026-06-17) until noticed ~2026-06-18 (~1 day). No monitoring detects secrets-in-argv.

## Root cause

`inngest start` accepts its Postgres/Redis URIs and signing/event keys as either CLI flags OR environment variables (self-hosting docs). The durable-backend ExecStart used the **flag** form, expanding Doppler-injected secrets onto argv. argv (`/proc/<pid>/cmdline`, 0444) is world-readable; the inherited environment (`/proc/<pid>/environ`, 0400) is owner-only. The flag form was chosen without weighing the argv-exposure surface.

## Resolution

PR #5561 delivers all four secrets via the doppler-run **environment** instead of argv: `INNGEST_POSTGRES_URI`/`INNGEST_EVENT_KEY` read from the injected env by name, `INNGEST_REDIS_URI` constructed from `INNGEST_REDIS_PASSWORD`, `INNGEST_SIGNING_KEY` re-exported stripped. The ExecStart passes no secret flag and `exec`s inngest. Durable-backend detection re-keyed to the non-secret `--postgres-max-open-conns` sentinel. Codified as ADR-030 invariant I7.

## Recovery verification

- Code: `inngest.test.sh` security invariant asserts the ExecStart carries no secret flag (71/71 green).
- Live (post-deploy, tracked in #5565): `ps -eo args | grep inngest` shows no secret values; `/proc/<pid>/environ` carries the four secrets; `verify_inngest_health` durable gate passes.

## Impact

Bounded. Single-tenant alpha; local-only exposure (no remote read path). The credentials grant access to the dedicated inngest Supabase project (queue/run-state for crons + armed reminders) and the self-hosted Redis — so a local process on the prod host (including agent-executed workspace code, the realistic vector) could have harvested them. No evidence of actual access.

## 5 Whys

1. Why were secrets world-readable? → They were on the `inngest start` argv (`/proc/cmdline`, 0444).
2. Why on argv? → The durable-backend ExecStart used inngest's `--postgres-uri`/`--redis-uri`/`--signing-key`/`--event-key` flag form.
3. Why the flag form? → The argv-vs-environment exposure surface was not weighed when adding the flags; env-var support was not used.
4. Why not caught earlier? → No monitor detects secrets-in-argv, and no plan/review gate checked secret-delivery surface for the durable-backend PR.
5. Why no gate? → Secret-delivery-via-argv is a narrow class; ADR-030 now carries invariant I7 (secrets via env, never argv) + a build-time test asserting the ExecStart carries no secret flag.

## Action Items & Follow-ups

| Issue | Item | Owner |
|---|---|---|
| #5565 | Deploy the env-delivery image (pin bump), verify secret-free, then rotate the exposed `INNGEST_REDIS_PASSWORD` (terraform taint) + Supabase inngest-project Postgres password; redeploy; close #5560. | agent-with-ack |
