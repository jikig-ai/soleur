---
title: Recover a user's pino stdout lines from a UUID
category: support
tags: [pino, userid, hash, observability, gdpr, betterstack, vector]
date: 2026-05-13
last_reviewed: 2026-09-06
related_prs: [3701, 3731, 3751, 4786, 7872]
related_issues: [3698, 3710, 3711, 7823]
---

# Recover a user's WARN+ pino records from a UUID

After PR #3701 (#3698 PR-A) shipped, every authenticated pino log line emits
`userIdHash` (HMAC-SHA256 over the raw user UUID with a Doppler-resident
`SENTRY_USERID_PEPPER`) instead of raw `userId`. Operators handling support
tickets receive a raw UUID and need to convert it to the corresponding hash
before querying for that user's records.

This runbook covers two operator flows:

1. **Recover a user's WARN+ records from a UUID** — `hash-user-id` CLI + a
   Better Stack query. No host access. Only `level >= 40` ships; see the
   coverage limit in Flow 1 step 3 before reading an empty result.
2. **Measure observed pino log volume for PA8 §(f) retention pin** — one-time
   measurement, repeated on re-verification triggers (see Article 30 register
   PA8 §(f)).

## Flow 1 — UUID → hash → Better Stack query

### Prerequisites

- Local Bun runtime (`bun --version` returns non-error). Same dependency the
  existing `apps/web-platform/scripts/verify-stripe-prices.ts` runner uses.
- Doppler CLI authenticated for the Soleur project (`doppler whoami` returns
  non-error).
- Doppler access to the `prd_terraform` config, which carries
  `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}`. These are the ClickHouse
  read credentials; `BETTERSTACK_LOGS_TOKEN` is ingest-only and
  `BETTERSTACK_API_TOKEN` covers source metadata but not log content, so
  neither can answer this query.
- **No host access is required, and none should be used.** This flow reads the
  copy Vector ships, not the container's local buffer.

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
   under the dev pepper that will match zero prod records,
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

3. Query the shipped copy in Better Stack. Test each identity key explicitly
   against the decoded record, to avoid false-substring collisions with unrelated
   64-hex-shaped payloads (transaction IDs, request IDs, sha256 digests in
   error stacks):

   ```bash
   cd "$(git rev-parse --show-toplevel)"   # step 2 left you in apps/web-platform;
                                           # betterstack-query.sh is repo-root-relative
   doppler run -p soleur -c prd_terraform \
     --only-secrets BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD \
     -- scripts/betterstack-query.sh --since 24h --grep "$HASH" --limit 200 \
   | jq -r --arg h "$HASH" '
       .raw | fromjson
       | select(.CONTAINER_NAME == "soleur-web-platform")
       | (.message | if type == "string" then (fromjson? // empty) else . end)
       | select(type == "object")
       | select(.userIdHash == $h or .workspaceIdHash == $h or .worktreeIdHash == $h)
       | "\((.time/1000|todate))  level=\(.level)  \(.msg)"'
   ```

   **Three details are load-bearing, and each fails silently if you drop it.**
   `.message` arrives in **two shapes**: Better Stack auto-parses a JSON-valued
   `message` at ingest, so pino records land as an OBJECT, while fd-2 crash and
   plain lines stay STRINGS (measured 2026-09-06: 182 of 182 string-shaped
   app-container rows in 24h were non-JSON). The `if type == "string"` arm keeps
   the query correct if that ingest-side parse ever changes, and `fromjson? //
   empty` drops a crash line instead of aborting the whole run on it. The
   three-key test is spelled as an explicit `or` and **not** as
   `.a // .b // .c == $h`: jq's `//` is a falsy-default that short-circuits on
   the first non-null key, so a record carrying `userIdHash` for one actor and
   `workspaceIdHash` for the target would be silently skipped — the exact false
   negative the anti-collision contract below exists to prevent. And two more
   properties come from `betterstack-query.sh`'s own header. The `raw` column is **double-encoded JSON** — a JSON string
   containing a JSON document — so a `grep` for a field name against the raw
   line silently returns nothing; decode with `.raw | fromjson` first, as above.
   And mode-2 `--since` already unions the hot window with the `s3Cluster`
   archive: `remote()` alone is only ~40 minutes, so a support ticket about
   yesterday would get a silently short answer from a hot-only query. Do not
   reach for `--no-archive` to work around an archive error — the short answer
   is the bug. `--limit 200` truncates to the newest 200 matching rows: if you get
   exactly 200, raise it rather than reading the set as complete.

   **Coverage limit — read this before concluding a user has no lines.** Vector
   ships this container's stdout through `app_container_warn_filter`
   (`apps/web-platform/infra/vector.toml`), which keeps only pino
   **`level >= 40`** (WARN/ERROR/FATAL). `formatters.log` injects `userIdHash`
   at *every* level, so INFO and DEBUG records carrying the hash exist on the
   host and are **not** in Better Stack. An empty result therefore means "no
   WARN+ record for this user in the window", never "this user did nothing".
   The cut is a Better Stack quota measure and its own comment calls it
   "conservative headroom, not a hard necessity". Widening it is a quota
   decision rather than a technical barrier — but it is not a free one: the app
   container already ships ~100k rows/day *under* the cut, and
   `betterstack-quota-near-miss-postmortem.md` is `status: recurred` (2026-08-14,
   #7569), when ingest returned `HTTP 402 Quota exceeded` for two days. Read that
   before proposing a widening.

   **An empty result is three states, not one — get a positive control before
   you report absence.** `exit 0` with zero rows is returned identically by "no
   WARN+ record for this user", "the query could not run" (missing credentials
   exit 3 with empty stdout), and "the channel is dark" — which is not
   hypothetical: during the 2026-08-14 ingest outage the READ path kept answering
   200 while nothing was being written. Confirm the source is live before
   concluding anything:

   ```bash
   doppler run -p soleur -c prd_terraform -- scripts/betterstack-assert-absence.sh \
     --host soleur-web-platform --absence "$HASH" --since 24h
   # 0 clean (absence confirmed AND a positive control read back)
   # 1 present   2 unshipping (channel dark)   3 unknown (query did not answer)
   ```

   `clean` is that script's only exit 0 and is unreachable without a positive
   control, which is exactly the discrimination a bare query cannot make.

   **Anti-collision contract.** This used to be a double-grep narrowing on
   `userIdHash` alone, correct while that was the only 64-hex-shaped pino
   field emitted by `formatters.log()`
   (`apps/web-platform/server/userid-pseudonymize.ts`). It no longer is:
   #6982 added `workspaceIdHash` and `worktreeIdHash` in
   `apps/web-platform/server/git-data-replication.ts`.

   That broke the old form in BOTH directions, which is why the query above
   tests all three keys explicitly against the decoded record, rather than
   narrowing twice on substrings:

   - **False negatives.** A record carrying only `workspaceIdHash` or
     `worktreeIdHash` was skipped by `grep -F 'userIdHash'` entirely — and
     on this host those are recoverable identities too, because a repo is
     `<workspace_id>.git` and `workspace_id === user_id` (mig-053 N2), so
     `hashUserId(workspaceId)` yields the SAME digest as `userIdHash` for
     the same person.
   - **False positives.** A line carrying several hashed fields let the
     second `grep -F "$HASH"` match a DIFFERENT field's value on a line
     selected for containing the key name.

   Anchoring on `"<key>":"<hash>"` fixes both: it selects the record only
   when the hash is the value of one of the enumerated keys.

   If you add a new 64-hex pino emission, add its key to the `or` chain in the
   query above in the same PR — or give it a key prefix that cannot be confused
   with an identity field.

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
| Zero matches from the Better Stack query | **(a) the record was below WARN.** `app_container_warn_filter` keeps only pino `level >= 40`, and `formatters.log` injects `userIdHash` at every level — so INFO/DEBUG records for this user exist on the host and never shipped. This is not a fault. OR (b) the user has no WARN+ activity in the window. OR (c) wrong pepper config (`-c dev` vs `-c prd`). OR (d) `SENTRY_USERID_PEPPER` was rotated after the target line was written — the pre-rotation pepper is required to reproduce the historical hash. OR (e) **the channel was dark or the query never ran** — see the positive-control step above; an empty read cannot distinguish these from (b) on its own | For (a), widening the filter is a Better Stack quota decision, not a technical barrier — its own comment calls the cut "conservative headroom, not a hard necessity". For (c), re-run the Doppler pre-check (step 2) to confirm `-c prd`. For (d): `hashUserId(userId, pepper?)` (`apps/web-platform/server/observability.ts`) accepts an optional pepper override — at the first rotation, wire a `SENTRY_USERID_PEPPER_PREVIOUS` Doppler key and extend the CLI with a `--prior-pepper` opt; until then, pre-rotation lines are unmatchable by design. |

## Flow 2 — PA8 §(f) retention pin (one-time measurement)

The Article 30 register PA8 §(f) claims **30 MB rolling per container**
(structural cap from `apps/web-platform/infra/cloud-init.yml` (the `"log-driver": "json-file"` daemon.json block)). There
is no MB → days conversion to record: a capacity-bounded ring buffer has no
envisaged time limit, because its duration is a function of instantaneous
emission rate. Art. 30 PA-8 §(f) records the **mechanism** rather than a
duration, and the sentinel this runbook used to direct the operator to fill
has been resolved to `NOT RECORDED` with that reasoning. The measurement
below remains available as a method if a figure is ever needed; it is no
longer an outstanding obligation.

### Re-verification triggers

**Triggers 3 and 4 have already fired, and this section records that rather
than leaving them in the future tense.** Both were discharged on 2026-09-06 by
the corrections above; the measurement they would have called for is the one
§Steps now declines to prescribe, so neither leaves an open action.

1. **Annual review** — cadence-based, next due 2027-05. *Not fired.*
2. **`apps/web-platform/infra/cloud-init.yml` change** — fires when the
   `daemon.json` block is edited (anchor on the `"log-driver": "json-file"`
   line, not a line number). *Not fired.*
3. **Off-host log shipper introduction** — fires when any of `promtail`,
   `vector`, `fluent`, `filebeat`, `rsyslog` is added to the infra.
   **FIRED 2026-06-02** — Vector, `[sources.app_container_journald]` (#4786).
   Discharged: Flow 1 is rebuilt on that path and Flow 2's "expect zero
   shippers" step is removed.
4. **Container restart-policy change affecting log path** — fires when
   `--restart`, `--log-driver`, or `--log-opt` changes on the `docker run`
   invocation. **FIRED** — the container moved to `--log-driver journald`
   (#4786 / #4773). Discharged: §Steps records that the `json-file` measurement
   is undefined for this container, and the wrong mechanism in PA-8 §(f) is
   named there for a register PR to correct.

The trigger list is **closed** — adding a fifth trigger requires updating
the PA8 §(f) row and this runbook in the same PR.

### Steps

**This flow is dormant, and it deliberately carries no executable steps.**
Art. 30 PA-8 §(f) is resolved to `NOT RECORDED` (see below), so there is no
obligation to discharge. What follows is the method of record, kept so a future
reader knows what *would* be measured and why it is not written as a runnable
procedure.

**Why there are no steps to run — the measurement is undefined for this
container, not merely unshippable.** The steps this flow used to carry measured
the `json-file` ring buffer: `HostConfig.LogConfig` for the driver, and `du -sb`
of `.[0].LogPath` for occupancy. **The app container stopped using that driver.**
`apps/web-platform/infra/cloud-init.yml` runs it with `--log-driver journald`
(PR #4786 / #4773), overriding the `json-file` daemon default in the same file.
Under the journald driver `LogPath` is the empty string and there is no
per-container ring buffer to size, so both old steps were already measuring
something that does not exist — and the deleted `LogConfig` drift check
(*"Expected: `{"Type":"json-file"}` … Any other Type → drift; file a
compliance/critical issue"*) was guaranteed to fire falsely on every run.

Better Stack cannot substitute. It receives only what Vector forwards, which for
this container is pino `level >= 40` *records* — so counting rows there measures
the WARN+ shipped subset, not buffer occupancy, and would answer a different
question while looking like the right one.

**This is not a re-wording to satisfy the SSH rule.** `hr-no-ssh-fallback-in-runbooks`
forbids `ssh` as a **PRIMARY** debug action and expressly sanctions an SSH-class
"Last-resort diagnosis" section, so a host-side procedure could legitimately have
been kept in that form. It is removed because it measures the wrong mechanism,
not because the rule forbids writing it down.

If a figure is ever genuinely needed, the enabling change is a host-side emitter —
`vector.toml` already runs `[sources.host_metrics]` with `disk` and `filesystem`
collectors, so the shape exists and the work is to emit the per-container size
alongside them. That is an infrastructure change and should be scoped as one.

**Correction, 2026-09-06 — a step this flow used to carry is now false.** It
previously instructed the operator to *"confirm no off-host shippers"* with
`systemctl list-units | grep -iE 'promtail|vector|fluent|filebeat|rsyslog'` and
**"Expected: zero matches."** That expectation no longer holds and has been
removed rather than re-worded, because acting on it would produce a false drift
report. Vector **is** deployed on this host: `[sources.app_container_journald]`
matches `CONTAINER_NAME = ["soleur-web-platform"]` and ships the WARN+ subset of
this very container's stdout to Better Stack. Flow 1 above now depends on exactly
that.

**PA-8 §(f)'s recorded mechanism is also wrong for this container, and that is
tracked rather than fixed here.** §(f) and this runbook both still describe a
"30 MB rolling per container" `json-file` cap (`max-size 10m` × `max-file 3`).
That cap governs the daemon default, not this container: under `--log-driver
journald` its retention is journald's `SystemMaxUse`/`SystemKeepFree`, shared
with every other unit on the host. §(f)'s *disposition* — `NOT RECORDED`, on the
ground that a capacity-bounded buffer has no envisaged time limit — survives the
correction, because journald is also capacity-bounded. The wrong mechanism is a
register edit, out of scope for a runbook PR.

### Post-measurement: the register is already resolved

**Do not open a PR to fill a sentinel — there is no longer one to fill.** Art. 30
PA-8 §(f) records effective time-retention as `NOT RECORDED`, on the ground that
Art. 30(1)(f) asks for an *envisaged time limit* and this surface has none. If a
measurement is taken for an operational reason, add it to §(f) as a dated
observation **beside** the mechanism, and do not replace the mechanism with it:
the mechanism is the durable record and a single day's rate is not.

After the follow-up PR merges:

```bash
gh issue close 3711 \
  --reason "completed" \
  --comment "Operator-side §(f) measurement complete; observed <X> MB/day → ~<Y> days. Follow-up PR #<M> applied the value."
```

## Cross-references

- `betterstack-log-query.md` — **owns this read path**: source ids, retention, and
  the ClickHouse connection re-mint procedure Flow 1 has no recovery for.
- `scripts/betterstack-query.sh` — the ClickHouse read path used by Flow 1; its
  header carries the double-encoding and hot-window/archive contracts.
- `scripts/betterstack-assert-absence.sh` — refuses to report absence without a
  positive control (`unknown` 3 / `unshipping` 2 / `present` 1 / `clean` 0).
- `apps/web-platform/infra/vector.toml` — `[sources.app_container_journald]` and
  `[transforms.app_container_warn_filter]`, which decide what Flow 1 can see.
- `apps/web-platform/scripts/hash-user-id.ts` — operator CLI source.
- `apps/web-platform/server/observability.ts` (`hashUserId`) — `hashUserId` canonical primitive.
- `apps/web-platform/infra/cloud-init.yml` (the `"log-driver": "json-file"` daemon.json block) — docker daemon.json source of truth.
- `knowledge-base/legal/article-30-register.md` PA8 §(f) — RoPA retention row.
- ADR-029 (rename-at-boundary) — pino formatters.log() rename contract.
- ADR-028 (DSAR / cross-tenant pseudonymisation) — distinct `hashUserIdForSentry` primitive.
