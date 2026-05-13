---
title: Recover a user's pino stdout lines from a UUID
category: support
tags: [pino, userid, hash, observability, gdpr]
date: 2026-05-13
related_prs: [3701, 3731, 3751]
related_issues: [3698, 3710, 3711]
---

# Recover a user's pino stdout lines from a UUID

After PR #3701 (#3698 PR-A) shipped, every authenticated pino log line emits
`userIdHash` (HMAC-SHA256 over the raw user UUID with a Doppler-resident
`SENTRY_USERID_PEPPER`) instead of raw `userId`. Operators handling support
tickets receive a raw UUID and need to convert it to the corresponding hash
before grepping the Hetzner host's docker logs.

This runbook covers two operator flows:

1. **Recover a user's log lines from a UUID** — `hash-user-id` CLI + docker
   logs grep.
2. **Measure observed pino log volume for PA8 §(f) retention pin** — one-time
   measurement, repeated on re-verification triggers (see Article 30 register
   PA8 §(f)).

## Flow 1 — UUID → hash → docker logs

### Prerequisites

- Local Bun runtime (`bun --version` returns non-error). Same dependency the
  existing `apps/web-platform/scripts/verify-stripe-prices.ts` runner uses.
- Doppler CLI authenticated for the Soleur project (`doppler whoami` returns
  non-error).
- SSH access to the prod host (`135.181.45.178`). If `ssh` returns
  `kex_exchange_identification` or hangs, the operator IP is not in
  `ADMIN_IPS`; run `/soleur:admin-ip-refresh` first. If SSH still fails
  after the allowlist refresh, see `admin-ip-drift.md` and
  `ssh-fail2ban-unban.md`.

### Steps

1. Capture the user UUID from the support ticket (verbatim — do not trim
   or re-case; `hashUserId` does not normalise input shape).

   ```bash
   UUID="11111111-2222-3333-4444-555555555555"  # replace with ticket UUID
   ```

2. Compute the hash via the operator CLI. The CLI runs **on the operator
   machine**, not inside the prod container — the `tsx`/`bun` runtime is in
   `devDependencies` and would not be available under `docker exec`. The
   pepper enters the script via Doppler's env injection and never appears
   in shell history.

   First, pre-check that the Doppler context is the prd config (not dev) —
   a wrong-config invocation produces a syntactically-valid 64-hex hash
   under the dev pepper that will match zero lines in prod docker logs,
   which is indistinguishable from "user has no activity":

   ```bash
   doppler run -p soleur -c prd -- printenv DOPPLER_CONFIG | grep -qx prd \
     || { echo "Doppler context is not -c prd; aborting" >&2; exit 1; }
   ```

   Then compute the hash. The operator CLI must be invoked from
   `apps/web-platform/` (the repo root does not declare
   `workspaces:`, so `npm run -w apps/web-platform ...` from the root
   FAILS with "No workspaces found"). The explicit `--` separator
   between the npm-script name and the positional UUID is load-bearing
   — without it, npm's wrapper parses `$UUID` as a candidate flag
   rather than argv:

   ```bash
   cd apps/web-platform
   HASH=$(doppler run -p soleur -c prd -- \
     npm run --silent hash-user-id -- "$UUID")
   echo "$HASH" | grep -E '^[0-9a-f]{64}$' || {
     echo "hash-user-id failed or returned non-hex output" >&2
     exit 1
   }
   ```

   The `--silent` flag is bound to `npm run` (not to the script) and
   suppresses the wrapper banner so `$HASH` captures only the 64-hex
   string.

3. Grep the docker logs on the prod host. Use the **hardened double-grep**
   pattern to anchor on the `userIdHash` key prefix and avoid
   false-substring collisions with unrelated 64-hex-shaped payloads
   (transaction IDs, request IDs, sha256 digests in error stacks):

   ```bash
   ssh root@135.181.45.178 "docker logs soleur-web-platform 2>&1 \
     | grep -F 'userIdHash' \
     | grep -F \"$HASH\""
   ```

   `grep -F` (fixed string) prevents accidental regex-metachar
   interpretation of the hex hash and is faster than `grep -E` on tail
   files. The first grep narrows to lines emitted by `formatters.log()`;
   the second narrows to the operator's specific user.

   **Anti-collision contract:** the double-grep is correct because
   `userIdHash` is currently the only 64-hex-shaped pino field emitted by
   `formatters.log()` (`apps/web-platform/server/userid-pseudonymize.ts`).
   Any future pino-emitted 64-hex field (a content digest, bundle SHA,
   request hash, etc.) must carry its own unique JSON-key prefix or this
   runbook's grep target must be tightened to anchor on
   `"userIdHash":"<hash>"` (full key-value pair). If you add a new
   64-hex emission, update this section in the same PR.

### Load-bearing primitive distinction

The CLI uses `hashUserId` (HMAC-SHA256 keyed by `SENTRY_USERID_PEPPER`) —
the same primitive the pino `formatters.log()` hook calls. Do **NOT**
substitute `hashUserIdForSentry` (DSAR / cross-tenant primitive, salt-keyed
by `SOLEUR_SENTRY_PII_SALT`) — that hash is in a different domain and will
not match any pino stdout line. See ADR-029 §I10 for the deliberate
two-primitive separation.

### Common failures

| Symptom | Cause | Recovery |
|---|---|---|
| `usage: bun scripts/hash-user-id.ts <uuid>` to stderr | Missing argv | Pass the UUID as the only positional. |
| `pepper not set: SENTRY_USERID_PEPPER env var required` | Operator forgot to wrap in `doppler run -p soleur -c prd` | Re-run inside `doppler run`. Never `export SENTRY_USERID_PEPPER=` outside doppler. |
| `hash-user-id: contract drift detected` | A future change to `hashUserId` widened the return shape (e.g., added a prefix) | File a P0 issue against `apps/web-platform/server/observability.ts` — the operator boundary contract is broken. |
| Zero matches from `docker logs … grep` | (a) User has no pino activity in the rolling window (see PA8 §(f) — 30 MB rolling cap), OR (b) wrong pepper config (`-c dev` vs `-c prd`), OR (c) `SENTRY_USERID_PEPPER` was rotated after the target log line was written — the pre-rotation pepper is required to reproduce the historical hash | Re-run the Doppler pre-check (step 2 above) to confirm `-c prd`; confirm the user authenticated recently. For (c): `hashUserId(userId, pepper?)` (`apps/web-platform/server/observability.ts`) accepts an optional pepper override — at the first rotation, wire a `SENTRY_USERID_PEPPER_PREVIOUS` Doppler key and extend the CLI with a `--prior-pepper` opt; until then, pre-rotation lines are un-grep-able by design (acceptable trade-off — the hash window aligns with the 30 MB rolling cap anyway). Check rotated log files via `docker inspect soleur-web-platform \| jq '.[0].LogPath'`. |
| `kex_exchange_identification` on SSH | Operator IP not in `ADMIN_IPS` | Run `/soleur:admin-ip-refresh`; if still failing, see `admin-ip-drift.md`. |

## Flow 2 — PA8 §(f) retention pin (one-time measurement)

The Article 30 register PA8 §(f) claims **30 MB rolling per container**
(structural cap from `apps/web-platform/infra/cloud-init.yml:303-310`). To
convert MB → days, the operator runs one round of measurement and updates
the register sentinel `__TBD_OBSERVED_VOLUME__` via a follow-up PR.

### Re-verification triggers

This measurement is **not** a recurring cron. Re-run it on any of:

1. **Annual review** — cadence-based, next due 2027-05.
2. **`apps/web-platform/infra/cloud-init.yml` change** — fires when the
   `daemon.json` block (currently lines 303-310) is edited.
3. **Off-host log shipper introduction** — fires when any of `promtail`,
   `vector`, `fluent`, `filebeat`, `rsyslog` is added to the infra.
4. **Container restart-policy change affecting log path** — fires when
   `--restart`, `--log-driver`, or `--log-opt` flags are added/changed on
   the `docker run` invocation (currently `cloud-init.yml:412-421`).

The trigger list is **closed** — adding a fifth trigger requires updating
the PA8 §(f) row and this runbook in the same PR.

### Steps

1. **Refresh ADMIN_IPS allowlist** if SSH is failing.

   ```bash
   /soleur:admin-ip-refresh
   ```

2. **SSH to prod and confirm runtime driver matches the cloud-init pin.**

   ```bash
   ssh root@135.181.45.178
   docker inspect soleur-web-platform | jq '.[0].HostConfig.LogConfig'
   # Expected: {"Type":"json-file","Config":{}}
   # Any other Type → drift; file a compliance/critical issue and stop.
   ```

3. **Measure observed daily volume.** Capture three samples 8 hours apart
   on a representative weekday. The on-disk byte counts vary across the
   rotation cycle (`max-file=3` means up to three numbered log files); the
   3-sample average smooths rotation timing.

   ```bash
   LOG_PATH=$(docker inspect soleur-web-platform | jq -r '.[0].LogPath')
   # T+0h:
   du -sb "$LOG_PATH"
   # T+8h:
   du -sb "$LOG_PATH"
   # T+16h:
   du -sb "$LOG_PATH"
   # Compute average; convert: <avg-bytes-per-8h> × 3 = <bytes/day>
   # → effective retention (days) ≈ 30 MB / (bytes-per-day / 1_048_576)
   ```

   **Agent execution note:** an agent invoked once cannot block for 16
   hours between the three samples. Schedule the T+8h and T+16h captures
   via `ScheduleWakeup` (delaySeconds=28800 each) or the equivalent cron
   primitive; a human operator runs them inline. Each wake-up is a
   single `du -sb` invocation — the agent reads the prior captures from
   conversation state on resume.

4. **Confirm no off-host shippers.**

   ```bash
   systemctl list-units --type=service | grep -iE 'promtail|vector|fluent|filebeat|rsyslog'
   # Expected: zero matches.
   ```

5. **Verify daemon.json structural pin (defense against operator hand-edits).**

   ```bash
   grep -F '"log-driver": "json-file"' /etc/docker/daemon.json \
     && grep -F '"max-size": "10m"' /etc/docker/daemon.json \
     && grep -F '"max-file": "3"' /etc/docker/daemon.json \
     && echo "daemon.json structural pin OK"
   # Any failure → drift; file a compliance/critical issue.
   ```

### Post-measurement: update the register

Open a follow-up PR replacing the `__TBD_OBSERVED_VOLUME__` sentinel in
`knowledge-base/legal/article-30-register.md` PA8 §(f) row with the
measured value:

```diff
- Observed daily log volume: __TBD_OBSERVED_VOLUME__ (post-merge operator measurement; …)
+ Observed daily log volume: ~<X> MB/day at <YYYY-MM-DD>, yielding ~<Y> days effective time retention (…)
```

After the follow-up PR merges:

```bash
gh issue close 3711 \
  --reason "completed" \
  --comment "Operator-side §(f) measurement complete; observed <X> MB/day → ~<Y> days. Follow-up PR #<M> applied the value."
```

## Cross-references

- `admin-ip-drift.md` — IP allowlist drift recovery.
- `ssh-fail2ban-unban.md` — when SSH is locked out post-multiple-failures.
- `apps/web-platform/scripts/hash-user-id.ts` — operator CLI source.
- `apps/web-platform/server/observability.ts:36` — `hashUserId` canonical primitive.
- `apps/web-platform/infra/cloud-init.yml:303-310` — docker daemon.json source of truth.
- `knowledge-base/legal/article-30-register.md` PA8 §(f) — RoPA retention row.
- ADR-029 (rename-at-boundary) — pino formatters.log() rename contract.
- ADR-028 (DSAR / cross-tenant pseudonymisation) — distinct `hashUserIdForSentry` primitive.
