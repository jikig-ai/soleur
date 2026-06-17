# Learning: inngest v1.19.4 `eventsV2` carries the payload in `raw` (not `data`) and its `from`/`until` filter bounds receivedAt, not fire-time

category: integration-issues
module: apps/web-platform/infra (inngest cutover orchestration, #5450)

## Problem

The #5450 cutover runbook's reminder-enumeration query selected `id name receivedAt` and assumed `eventsV2(filter:{from})` could select still-armed (future-dated) `reminder.scheduled` events server-side. Building the no-SSH enumeration script against that assumption would have produced **un-re-armable output** (no payload) and **missed every future-dated reminder** (the server filter does not see fire-time).

## Solution

Before writing the enumeration script, ran inngest **v1.19.4** (the exact prod pin) locally in Docker and introspected the `/v0/gql` schema. Pinned the verified shape in `knowledge-base/project/specs/feat-one-shot-inngest-cutover-no-ssh-5450/inngest-graphql-schema.md` and built the script against it:

- **Payload is `raw: String!`** — a JSON-string envelope (`{"data":{...},"id":...,"ts":...}`) that MUST be `JSON.parse`'d. There is NO `data`/`payload` field on `EventV2`. Producer payload = `JSON.parse(node.raw).data`; future fire epoch-ms = `.ts`.
- **`from`/`until` bound `receivedAt` (ingest time), NOT `occurredAt`/fire-time.** A future reminder cannot be selected server-side by fire-time. Strategy: fetch a WIDE receivedAt window (`from: 1970-01-01`) then **client-side filter** `raw.ts > now`.
- **`node.runs[].status`** terminal set `{COMPLETED,CANCELLED,FAILED,SKIPPED}` = already fired (drop); empty `runs: []` = armed-unfired.
- No auth on loopback `/v0/gql` in `start` mode.
- Image gotcha: `inngest/inngest:v1.19.4` has `ENTRYPOINT=null`, `CMD=["inngest"]` → must invoke `docker run … inngest/inngest:v1.19.4 inngest start …`.

## Key Insight

**A plan's quoted external-API query shape is a hypothesis, not a fact — when a plan defers the shape to "/work will live-probe", actually run the pinned version and capture the real schema before coding.** The runbook query was authored from the conceptual narrative; the live probe falsified two load-bearing assumptions (payload field name + what the server filter bounds). This is the same class as `2026-06-16-external-api-shape-ac-must-land-captured-fixture-not-probed-claim.md`. The captured schema becomes the test fixture's source of truth.

Secondary insights from the same PR:
- **No-SSH host-op delivery is a 4-file lockstep per script** (`push-infra-config.sh` payload + `hooks.json.tmpl` pass-environment + `infra-config-apply.sh` FILE_MAP + `infra-config-install.sh` DEST_SPEC), guarded by a FILE_MAP↔DEST_SPEC cardinality parity test. A missing DEST_SPEC entry is a silent rc=3 non-install. Bump the parity-test count in the same commit.
- **Classify a self-armed sentinel by an UNFORGEABLE signal, not an operator-suppliable one.** The wiped-volume verify's emptiness gate first excluded the throwaway by `reminder_id` prefix (operator-suppliable → a spoofed-prefix real reminder could dodge the wipe abort). Corrected to classify by `action.check == "__cutover-verify-noop__"` (a real named-check must resolve in `CHECK_REGISTRY`, so a real reminder can never carry it; and a reminder that does is itself harmless — unregistered → no-op at fire). Security-review P3.
- **adnanh/webhook does not pipe the request body to the command's stdin** — a hook script that `cat`s stdin would hang. Self-source instead (the re-arm hook self-enumerates on the host); add `include-command-output-in-response-on-error: true` so a script's loud abort reaches the workflow log, not just host journald.

## Session Errors

1. **IaC-routing hook blocked the plan Write twice** (`ssh`/`systemctl` strings in a plan about *removing* SSH). Recovery: documented `<!-- iac-routing-ack: ... -->` opt-out + `## Infrastructure (IaC)` section. Prevention: a plan that removes SSH still trips the gate — lead with the ack comment.
2. **A plan Write resolved to the bare-root mirror** instead of the worktree. Recovery: re-issued at the absolute worktree path. Prevention: already worktree-guard-hook-enforced.
3. **enumerate test hardcoded an epoch→date string** that mismatched the `date`-derived `fire_at`. Recovery: derive the expected value from the same constant. Prevention: never hardcode a date string that the SUT computes from an epoch — derive both from one source.
4. **`grep -c … || echo 0` emitted "0\n0"** (grep -c already prints 0 on no-match AND exits 1). Recovery: `grep -c … ) || true`, no `echo 0`. Prevention: `grep -c` self-prints 0; never pair with `|| echo 0`.
5. **Mock `curl` returned the HTTP code on a no-`-o` body-on-stdout call** (`/v1/functions`). Recovery: branch the mock on whether `-o` was passed. Prevention: when a script mixes `curl -o … -w '%{http_code}'` (code-on-stdout) and bare `curl url` (body-on-stdout), the mock must emit the right thing per call style.
6. **SC2016 on jq query/filter single-quotes** (3 scripts). One-off: `$first`/`$p`/`$c` are GraphQL/jq variables, not shell expansions — `# shellcheck disable=SC2016` is the correct idiom.
7. **ADR Edit failed "file not read yet"** (I'd read it via Bash `tail`, not the Read tool). Recovery: Read then Edit. Prevention: the harness tracks reads via the Read tool only.
8. **First hardening used `prefix OR check`** which reintroduced the spoofed-prefix dodge. Recovery: switched to check-signal-only. Prevention: when hardening a forgeable classifier, replace the forgeable signal — don't OR it with the unforgeable one.

## Tags
category: integration-issues
module: inngest, infra, webhook-hooks, #5450
related: [[2026-06-16-external-api-shape-ac-must-land-captured-fixture-not-probed-claim]]
