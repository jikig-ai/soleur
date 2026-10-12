# Design: machine-enforce the heartbeat flip precondition (#9943)

Status: DESIGN ONLY (plan Phase 4.3, 2026-10-12). Nothing here was executed, dispatched or applied, and no
production system was read. Claims are anchored to a file and a content anchor read in this worktree, never a line
number. `verdict=liveness_unproven` does not exist anywhere in the repo today (the plan's premise check): this is a
build, not a fix.

Ruling applied (decision-challenges.md): CTO F6 (revised). A new dedicated read-only
`apps/web-platform/infra/git-data-liveness-precheck.sh` in its own step of `git-data-cutover.yml`, bound ONLY to
`secrets.DOPPLER_TOKEN` (Doppler `prd_terraform`), `mode=flip` only, after the flag precheck and before the freeze,
emitting `verdict=liveness_unproven`. Putting the check in `git-data-flag-precheck.sh` is rejected, and the reason
is read in that file and in the census below, not asserted.

## 1. The text being machine-enforced

- Runbook (`git-data-luks-cutover-5274.md`, "Preconditions for the flip", bullet "The host's own liveness
  heartbeat is armed and measured (#9438, hard)"): satisfied means the monitor `soleur-git-data-host-prd` was armed
  after a measured `up` transition on the CURRENT host, "and a re-read at the flip dispatch shows it `up` with a
  `state=ok` event under 15 minutes old and later than that host's `boot_complete`. A box ticked once goes stale at
  the next replace, so it is RE-READ, never remembered." It ends: "Until #9943 enforces it in the workflow, this
  item and its re-read are the only control." Section "Liveness heartbeat", "Order" step 9, gives the same re-read
  with the step-6 query bounded by `dt > now() - INTERVAL 15 MINUTE`.
- ADR-283 Decision 5: "Machine enforcement in the cutover workflow is deferred to #9943"; Consequences: "Until
  #9943 lands, the precondition is a runbook item with a re-read, not a workflow gate."
- What the feeder emits (`git-data-liveness.sh`): the host pings the monitor only when its own checks pass, and
  emits `stage=liveness` through `git-data-emit` with fields `state`, `code`, `root_pct`, `config` on every state or
  code change and as a `state=ok` summary every `OK_SUMMARY_S` = 600 s while healthy (`MISS_REEMIT_S` = 1800 s for a
  persistent miss). The monitor is `period = 60`, `grace = 300`, `paused = true` at birth with
  `ignore_changes = [paused]` (`git-data.tf`, `betteruptime_heartbeat.git_data_host_prd`).
- The plan's deepen note: the check "needs the git-data Better Stack table pin; the design must say which exact
  query it runs so the probe cannot read the shared default table (the runbook records that the default table
  returns zero rows for this host)". Section 4 does.

## 2. Why a dedicated script and step (read, not assumed)

- `git-data-flag-precheck.sh` header: it is "the only step bound to DOPPLER_TOKEN_PRD ... so the `prd` read token
  never reaches a process that handles host bytes". Better Stack query credentials and `BETTERSTACK_API_TOKEN_READONLY`
  live in `prd_terraform` (the per-host assertion step reads them through `secrets.DOPPLER_TOKEN`), a DIFFERENT
  credential. Folding a Better Stack read into the flag precheck would either hand it the `prd_terraform` token
  (breaking `AC9` in `git-data-cutover-access.test.sh`: the step's env is pinned to exactly
  `{DOPPLER_TOKEN: secrets.DOPPLER_TOKEN_PRD, FLAG_MODE}`) or hand the `prd` token to a process that reads vendor
  bytes.
- The workflow header: "Credentials, each bound in exactly one step's env (the credential census suite pins this)."
  A separate step binding only `secrets.DOPPLER_TOKEN` adds no secret to the referenced set (`WF9` stays
  `{DOPPLER_TOKEN, DOPPLER_TOKEN_GIT_DATA_FLAG, DOPPLER_TOKEN_GIT_DATA_ROOT, DOPPLER_TOKEN_INFRA_PRIVILEGED,
  DOPPLER_TOKEN_PRD, GITHUB_TOKEN, RESEND_API_KEY, SENTRY_ACTIONS_RO_TOKEN, SENTRY_API_HOST}`).
- A script (not YAML-embedded bash) is the house shape: `arm-heartbeats.sh`'s header explains why bash inside a
  YAML scalar cannot be asserted on, and `git-data-boot-signal-poll.sh` explains why the step logic lives in a
  sourced library the suite drives.

## 3. Placement and wiring

New step id `liveness_precheck` in job `cutover`, named for what it proves, positioned **immediately before the
`freeze` step, after `host_proof`**:

```yaml
      - name: Liveness precheck (git-data host heartbeat up and a fresh ok event, flip only)
        id: liveness_precheck
        if: steps.confirm.outputs.mode == 'flip'
        timeout-minutes: 10
        env:
          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}
        run: |
          set -euo pipefail
          case "$-" in *x*) echo "::error::xtrace refused on a credential-bearing step (#7797)"; exit 78;; esac
          bash apps/web-platform/infra/git-data-liveness-precheck.sh
```

Resolved forks (technical, `hr-technical-fork-is-not-an-operator-question`):

1. **After `host_proof`, not before the bridge.** The property is freshness. The read must sit as close as possible
   to the first write (the freeze) so the 15-minute bound is measured against the moment that matters; a dark host
   would already have failed the proof's access gate, so reaching this step means "the host answers ssh", and this
   step then asks the question the proof cannot: is the feeder healthy. A late failure costs one read-only bridge and
   writes nothing. The plan's constraint (after the flag precheck, before the freeze) holds.
2. **No skip on resume arms.** The `freeze` step is `if: mode == 'flip'` with no `resume` condition: arm B (flag
   already `true`) still freezes, so the precondition applies to it. Arm A (a `gh run rerun` of a flip that died
   mid-window) also passes through. A refusal on a re-run leaves a same-lineage sentinel from the first attempt
   untouched, and the finalizer (no `freeze_held`/`flag_written` marker on the fresh runner) reports "nothing to
   unwind", so the store stays frozen until the owner runs `mode=unfreeze`. The behaviour already exists for any
   pre-freeze failure of a re-run, but this check adds a new refusal at exactly that point, so a refusal text alone
   is not enough. **Design requirement (build PR): a refusal that may sit on top of an earlier attempt's freeze
   sentinel pages the owner and names the lever.** A `gh run rerun` keeps the run id, hence the lineage
   `cutover-<run id>`; a fresh dispatch has a new lineage and a foreign sentinel already refuses earlier, at
   `host_proof` (`cutover_frozen`). Two signals, the first preferred: (a) `host_proof` exports a step output when it
   tolerates a same-lineage sentinel (the script already evaluates it; nothing new is read from the host by the
   liveness step); (b) the conservative fallback `github.run_attempt > 1`. Either one makes `notify-failure` set
   `remedy_needed=1`, so its existing remedy text names `mode=unfreeze` with `lineage=cutover-<run id>`, instead of
   the generic "the run failed and its finalizer ran: it reported no stranded freeze" line. The refusal text also
   says: "if this is a re-run of a flip that died mid-window, read the sentinel first (mode=unfreeze, lineage
   cutover-<id of the run that wrote it>)". A test row drives the notify body with the signal set and asserts the
   unfreeze command appears.
3. **`timeout-minutes: 10`** bounds the step and is derived from section 5's wall-clock deadline (540 s) plus a
   60 s margin, not from the nominal read times. The job's 120-minute budget (about 84 minutes on the happy path,
   per the header derivation) is not re-priced by a few minutes, and the header's derivation sentence gains this
   step's bound.

Test census (`git-data-cutover-access.test.sh`): the step `order = [...]` list gains `"liveness_precheck"` between
`"host_proof"` and `"freeze"`; a new row pins the step's env to exactly `{DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}}`,
its `if` to exactly `steps.confirm.outputs.mode == 'flip'`, its run to call the script after the xtrace guard, and
requires `DOPPLER_TOKEN_PRD`, `DOPPLER_TOKEN_GIT_DATA_FLAG`, `DOPPLER_TOKEN_GIT_DATA_ROOT` and
`DOPPLER_TOKEN_INFRA_PRIVILEGED` to be absent from it. The workflow header's credential list gains the step on the
`secrets.DOPPLER_TOKEN` line. `AC9` and `WF9` are unchanged. The notify rows (`N-*` and the executed notify-body
rows) are NOT unchanged: the cutover job gains the output `liveness_reason` and notify-failure gains the mapping in
section 4, so the job-outputs pin and the notify-body rows each gain a row (a closed vocabulary, an unknown word
mapped to `unrecognized`, and the sentinel-signal remedy of section 3 fork 2).

## 4. What the script reads (three reads, one attempt)

Common: `set -euo pipefail`; refuse under xtrace (`exit 78`, as `git-data-flag-precheck.sh`); `LC_ALL=C`; source
`scripts/lib/betterstack-sources.sh` (`BS_GIT_DATA_TABLE`, `BS_GIT_DATA_TABLE_S3`), `scripts/lib/betterstack-absence.sh`
(`bs_absence_query_script`, `bs_absence_response_is_answer`) and `scripts/lib/betterstack-read-classify.sh`
(`bs_read_classify`), exactly the libraries `git-data-boot-signal-poll.sh` uses. Every Better Stack read is the
`git_data_served_empty_read` shape: `BS_TABLE="$BS_GIT_DATA_TABLE" BS_TABLE_S3="$BS_GIT_DATA_TABLE_S3"`, `timeout -k 5
45`, `doppler run -p soleur -c prd_terraform --only-secrets BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD
--no-exit-on-missing-only-secrets -- env -u DOPPLER_TOKEN -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u SHELLOPTS -u BASH_ENV -u BASHOPTS bash "$reader" "$sql"`,
stdout and stderr to SEPARATE files (an HTTP error body can carry the query username). **Design requirement: one scrub set for
every read.** All three reads (H, B, E) use `env -u DOPPLER_TOKEN -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u SHELLOPTS
-u BASH_ENV -u BASHOPTS`, so a reader call is never weaker than the heartbeat call (`SHELLOPTS`, `BASH_ENV` and
`BASHOPTS` are how a child shell is made to trace or source something). Every read also uses the `--only-secrets`
narrowed form: the unnarrowed `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh ...` form (the
one a flip report or a runbook paste may show) injects every `prd_terraform` secret (cloud and state keys, Doppler
tokens) into a process that reads vendor bytes, and is not an approved form for any read here. The Doppler shim row
asserts the exact secret list and the scrub set for each of the three calls, and a mutant that drops `--only-secrets`
or any `-u` goes RED. `--only-secrets` is what stops a
stray `BS_TABLE` key in `prd_terraform` from re-pointing the read; it is not a credential boundary, which is why
`env -u` strips the Doppler token. Table pin: the shared default source answers zero rows for this host forever
(runbook "The D6 rotate"), so the script never calls the reader without both pins, and a test row proves it.

**Read H, the monitor (Better Stack Uptime API, read scope).**
`timeout -k 5 30 doppler run -p soleur -c prd_terraform --only-secrets BETTERSTACK_API_TOKEN_READONLY --no-exit-on-missing-only-secrets -- env -u DOPPLER_TOKEN -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u SHELLOPTS -u BASH_ENV -u BASHOPTS bash --noprofile --norc -c 'BS_TOKEN="$BETTERSTACK_API_TOKEN_READONLY" exec bash apps/web-platform/infra/arm-heartbeats.sh --status soleur-git-data-host-prd'`
(the runbook's own step-7 form, so the token reaches the process by environment only and `arm-heartbeats.sh` puts the
bearer on curl's stdin config, ADR-280). `--status` has NO timeout of its own: it resolves the name over up to `ARM_LIST_MAX_PAGES=20` list pages at
`ARM_CURL_MAX_TIME_S=15` s each, up to about 300 s per call (its `--arm-one` header tells callers to allow at least
300 s), so Read H is wrapped in `timeout -k 5 30` (design requirement; section 5 prices it). A timeout there is
`reason=heartbeat_unreadable`, retried like `class=transport`. Reusing `--status` reuses its exact-name resolution over the whole
paginated list, its single-match requirement (exit 0 only when exactly one monitor carries that name), its
whitelisted output fields and its pagination refusals, instead of a second implementation. Parsed from its one line
`name= id= paused= status= period= grace=` with an anchored regex; anything else refuses.
Required: `paused=false`, `status=up`, and `period` and `grace` digits with `period <= 60` and `grace <= 300` (the
`git-data.tf` values; a monitor loosened to hours reads `up` for hours after the host died, so config drift refuses
as `heartbeat_config_drift`; tightening passes).

**Read B, the current host's boot.**

```sql
SELECT dt, toUnixTimestamp(dt) AS boot_epoch
FROM (SELECT dt, raw FROM remote($BS_TABLE)
      UNION ALL SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3) WHERE _row_type = 1)
WHERE JSONExtractString(raw,'stage') = 'boot_complete'
  AND JSONExtractString(raw,'host_name') = 'soleur-git-data'
ORDER BY dt DESC LIMIT 1 FORMAT JSONEachRow
```

The newest `boot_complete` of `host_name=soleur-git-data` is "the current host's" (the precedent is
`git_data_served_empty_sql`, which decides on the latest row). It starts with `dt` so `bs_absence_response_is_answer`
(every legitimate row begins `{"dt":`) rejects a bare mid-stream exception line as a partial answer. The archive arm
is required: a once-per-boot row leaves the roughly 40-minute hot window quickly. Rehearsal hosts report
`soleur-git-data-rehearsal-<run>` and never match.

**Read E, the freshest ok event. Always the LAST read of an attempt.**

```sql
SELECT dt, toUnixTimestamp(dt) AS ok_epoch, toUnixTimestamp(now()) AS now_epoch,
       JSONExtractString(raw,'code') AS code
FROM (SELECT dt, raw FROM remote($BS_TABLE)
      UNION ALL SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3) WHERE _row_type = 1)
WHERE dt > now() - INTERVAL 15 MINUTE
  AND JSONExtractString(raw,'stage')     = 'liveness'
  AND JSONExtractString(raw,'host_name') = 'soleur-git-data'
  AND JSONExtractString(raw,'config')    = 'prd_git_data'
  AND JSONExtractString(raw,'state')     = 'ok'
ORDER BY dt DESC LIMIT 1 FORMAT JSONEachRow
```

The predicates are the runbook step-6 predicates (`stage`, `host_name`, `config`) plus `state`. `config =
prd_git_data` keeps a rehearsal host's rows out (the feeder compares the config name by exact equality, not prefix).
`dt` and `now()` are both ClickHouse-side, so the age never depends on the runner's clock; `dt` is assigned by Better
Stack at ingest (the poll library's comment), the same clock as Read B's, so the ordering test below compares like
with like.

**Verdicts, all from the SAME attempt** (a pass is never stitched from reads of different attempts):

| Condition | Output (stdout, exit 5) |
|---|---|
| `DOPPLER_TOKEN` empty | `verdict=liveness_unproven reason=token_absent` (no call made) |
| a read exits 3 / the reader or `BETTERSTACK_API_TOKEN_READONLY` unset | `reason=credentials_absent` |
| H exits non-zero, 0 or more than one match, unparseable | `reason=heartbeat_unreadable` |
| `paused` is not `false` | `reason=heartbeat_paused` |
| `status` not `up` | `reason=heartbeat_not_up status=<whitelisted word>` |
| `period`/`grace` over the bounds, `null`, `INVALID` | `reason=heartbeat_config_drift` |
| B or E: non-zero rc, partial answer (`bs_absence_response_is_answer` false), timeout | `reason=boot_unreadable class=<bs_read_classify word>` / `reason=events_unreadable class=<word>` |
| B: zero rows | `reason=no_boot_complete` |
| E: zero rows (no `state=ok` event in 15 minutes) | `reason=no_ok_event` |
| `ok_epoch <= boot_epoch` | `reason=ok_event_predates_boot` |
| age at verdict time `< 0` or `> 900` | `reason=ok_event_future` / `reason=ok_event_stale` |

Pass line: `liveness=proven heartbeat_id=<digits> status=up boot_age_s=<n> ok_age_s=<n> ok_code=<ok|ok:last_good>`, exit
0. Age at verdict time = `now_epoch - ok_epoch` from Read E, plus the runner's monotonic seconds elapsed since E
returned. Output discipline: only fixed words, digits and values matched by an anchored whitelist
(`state`, `code` use the feeder's own shapes `^(ok|miss|ping_fail|url_unavailable|disarmed)$` and
`[a-z0-9_:.,-]{1,64}`); no raw row, no token, no vendor text. Each refusal also prints the `::error
title=git-data-liveness-precheck::` form the flag precheck uses.

**Design requirement: the `reason=` word must reach the notification, not only the step log.** Stdout and an
annotation are invisible to `notify-failure`, which would otherwise file a generic "FAILED, read the failing step"
issue for a pre-freeze refusal. The script, when `GITHUB_OUTPUT` is set, also writes `reason=<word>` (the closed
vocabulary of the table, never `class=` or vendor text) as a step output of `liveness_precheck`, and a one-line
`liveness_precheck: <verdict> reason=<word>` to `$GITHUB_STEP_SUMMARY`. The cutover job exports it as the job
output `liveness_reason`; `notify-failure` receives it through env, validates it with a `case` over the same closed
vocabulary (anything else becomes `unrecognized`, as the existing `MODE`/`RESULT` handling does), and adds
`LIVENESS_UNPROVEN reason=<word> (refused before the freeze; nothing was written; see the runbook Verdict map row)`
to the verdict words and `LIVENESS_UNPROVEN` to the subject, so the generic `FAILED` branch is not taken. The
reason vocabulary then exists in three places (script, notify `case`, runbook verdict map) and one test row asserts
they are the same set.

Resolved forks:

- **`ok:last_good` passes, with a `::warning`.** The runbook's flip-time wording is "a `state=ok` event"; the stricter
  rule ("the soak is not satisfied while `ok:last_good` appears") belongs to the owner's pre-arm soak read, which
  stays the owner's. The code is echoed so the owner sees it.
- **Freshness read last, computed against the server clock.** If Read E came first and Read B (the archive arm)
  were slow, an event could be 14 minutes old when read and 20 when the verdict forms. The order H, B, E plus the
  elapsed-since-E term makes the printed age the age at the moment of the verdict. A test row drives exactly that
  (section 6, M7).
- **Heartbeat reads reuse `arm-heartbeats.sh --status`**, not a new curl, for the reasons above.
- **The web-fed monitor `soleur-git-data-prd` is NOT read.** The runbook says it proves only that a web host can open
  a TCP connection, and the precondition names the host-originated monitor alone.
- **The manifest row (`arming_pending` in `plugins/soleur/lib/heartbeat-manifest.ts`) is not read.** A bash step
  does not parse TypeScript; the live `up` plus the event ordering is stronger evidence than a manifest field, and
  the reconcile suite already pins the manifest.

## 5. Retry and timing

Up to 3 attempts, 60 seconds apart, each attempt a FULL evaluation of H, B, E in that order. A pass requires one
attempt in which every read succeeded and every check held. Only reasons that depend on ingest timing or a
transient transport are retried: `no_ok_event`, `heartbeat_not_up` with status `pending`, and `class=transport`
(curl 6, 7, 28, 35, timeout 124 or 137, which includes Read H's own `timeout`). Everything else refuses at once:
`heartbeat_paused`, `heartbeat_not_up` with `down`, `heartbeat_config_drift`, `credentials_absent`, `token_absent`,
`no_boot_complete`, `ok_event_predates_boot`, a partial answer. The final verdict is the LAST attempt's reason.
Rationale for retrying at all: the feeder's ok cadence is 600 s against a 900 s bound, and the events reach Better
Stack through Vector in batches (the per-host assertion step's comment: "a single-shot read races ingest lag"), so a
healthy host can read as `no_ok_event` for a few minutes; a refusal costs a re-dispatch AND a fresh environment
approval. The retry never widens the 15-minute bound.

**Budget (design requirements; an earlier "three reads at 45 s, about 8 minutes" figure was wrong).** It priced
only the two Better Stack reads and ignored Read H, and `timeout -k 5 45` is up to 50 s, not 45. Read H is
`arm-heartbeats.sh --status`, which has no timeout of its own and can spend 20 pages x 15 s = 300 s per call, so the
unbounded worst case is 3 x (300 + 50 + 50) + 2 x 60 = 1,320 s against a 600 s step timeout. The runner would
cancel the step before it printed a verdict word, which is the "could not tell" state the poll library's own
`timeout` exists to avoid, and it costs a re-dispatch. Therefore:

1. Read H runs under `timeout -k 5 30` (at most 35 s); Reads B and E under `timeout -k 5 45` (at most 50 s each).
   One attempt is at most 135 s, the `timeout` wrapping the whole `doppler run`, so the Doppler fetch is inside it.
2. A monotonic wall-clock deadline of 540 s from script start is checked before EACH attempt and before EACH sleep:
   an attempt starts only if `elapsed + 135 <= 540`, and a 60 s sleep only if `elapsed + 60 + 135 <= 540`;
   otherwise the script refuses at once with the last attempt's reason. With every read at its cap, three attempts
   end by 135 + 60 + 135 + 60 + 135 = 525 s, so the script always prints its verdict by about 525 s whatever the
   vendor does, and the check (not the arithmetic) keeps that true if a cap is ever raised.
3. `timeout-minutes` is re-derived from that worst case: the 540 s deadline plus a 60 s margin is 10 minutes
   (600 s), and a test row pins the relation so that raising the deadline without the step timeout goes RED.
4. The monitor id is resolved ONCE. Attempt 1 resolves the name through `--status <name>` and keeps the parsed
   `id`; a retry re-reads that one monitor by id instead of re-listing up to 20 pages. `arm-heartbeats.sh` has no
   read-only by-id CLI mode today (its internal by-id fetch backs `--arm-one --id`), so the build PR either adds a
   `--status-id <id>` mode with its own suite rows or accepts re-running `--status <name>` per attempt, which the
   cap in item 1 already bounds. A retry still re-reads the heartbeat state (`paused`, `status`, `period`, `grace`);
   only the name-to-id resolution is cached, and a by-id read that returns a different name refuses as
   `heartbeat_unreadable`.
5. **Accepted trade-off: the retries run with the SSH bridge and the git-data root key live.** The step sits after
   `host_proof`, so the Cloudflare tunnel bridge and the root key fetched earlier in the job stay up through every
   attempt and sleep until the always-run teardown. On the degraded path that is up to about 9 minutes (the 540 s
   deadline) of extra exposure, versus roughly a minute for a healthy single-pass read. This is accepted because
   the step uses neither (it reads Better Stack only, bound to `secrets.DOPPLER_TOKEN`, with no key or bridge
   variable in its env), the exposure is time on an already-authorized job and not a new capability, and moving the
   step before the bridge was rejected in section 3 fork 1 for freshness. The deadline is what caps it; the step
   must not grow its own retry beyond it.

## 6. Tests (`git-data-liveness-precheck.test.sh`, registered by presence under `apps/web-platform/infra/`)

House shape of `git-data-flag-precheck.test.sh`: the instrument self-test (`pass`/`fail` read "1 1 1"), a per-name
Doppler shim on PATH that answers per project, config and secret and records its arguments, a stub reader through
the existing `BETTERSTACK_QUERY_SCRIPT` seam, a stub for `arm-heartbeats.sh` through a suite seam, a fake clock for
the retry sleep, every matrix row also run as a MUTANT through `mutate()` (copy, sed, assert the edit landed on the
expected diff-line count, require the NAMED row RED), and a mutant floor reported with printf and exit (the
`guard-vacuity-floor.test.sh` convention: a suite that runs zero mutants must fail).

Rows required by the plan: heartbeat down; heartbeat paused; no ok event; stale event (16 minutes); event older than
`boot_complete`; API error (reader rc 22, credentials rejected); query empty; happy path.
Added, each a distinct verdict word or a distinct bypass: heartbeat ambiguous (two matches) and unreadable
(`--status` rc 1); `pending` retried then refused; `heartbeat_config_drift` (`period=3600`); `no_boot_complete`;
event exactly equal to `boot_complete` (strict `>`); `ok:last_good` passes with the warning; a `miss` event inside
15 minutes does not satisfy; a rehearsal host's fresh `ok` (`host_name=soleur-git-data-rehearsal-1`, and
`config=prd_git_data_rehearsal`) does not satisfy; a partial answer (a bare exception line before a valid row)
refuses; table pin (the reader stub asserts `BS_TABLE` and `BS_TABLE_S3` equal the git-data pins, and a mutant that
drops either goes RED: the shared default table must never be read); `--only-secrets` narrowing (the Doppler shim
asserts the exact secret list and `--no-exit-on-missing-only-secrets`); no value printed (a sentinel token and a
sentinel in a `raw` body never appear on stdout or stderr); no stitching across attempts (attempt 1 heartbeat `up`
then attempt 2 heartbeat `down` plus a good event refuses); retry bound (a fourth attempt never runs); the clock
(runner clock set an hour off must not change the verdict).
Mutants: M1 drop the `INTERVAL 15 MINUTE` bound; M2 `>` to `>=`; M3 drop the `host_name` predicate; M4 drop the
`config` predicate; M5 drop the `state` predicate; M6 age from the runner clock instead of `now_epoch`; **M7 read E
before B (the plan's ordering mutation)**: the fake clock advances 6 minutes during B and E returned a 10-minute-old
event at its own time, so the verdict-time age is 16 minutes. The row expects a refusal (rc 5, any `liveness_unproven`
reason: the correct order reads E after B and sees `no_ok_event` or `ok_event_stale`), so the mutant that takes E first and
trusts its read-time age passes wrongly and the row goes RED; M8 treat
`status=pending` as up; M9 stitch a pass across attempts; M10 skip the heartbeat read on a missing token; M11
`|| true` on a reader rc.

Workflow census rows (in `git-data-cutover-access.test.sh`, section 3 above) and a mutant per row: remove the step, widen
its `if`, add `DOPPLER_TOKEN_PRD` to its env, move it after `freeze`, drop the xtrace guard.

## 7. What this does not prove

- It proves what two Better Stack-derived facts and one monitor status can: the monitor is live and `up`, and the
  host's feeder emitted a healthy summary in the last 15 minutes after the newest boot. It does not prove that a git
  operation or an Article 17 erasure succeeds on that host (the runbook says neither heartbeat does), and it does not
  replace the owner's pre-arm soak read (four ok rows at least 30 minutes apart).
- The root of trust is Better Stack ingest plus its API. A host able to write to the ingest token's source could
  forge a `liveness` row; the host-side check set in `git-data-liveness.sh` is what makes a healthy row mean
  something, and a compromised host is outside this check by definition.
- The predecessor window: a host replaced less than 15 minutes ago whose successor never reached `boot_complete`
  would present the destroyed predecessor's last ok event, which is newer than the predecessor's own
  `boot_complete`. This step cannot tell them apart without the Hetzner server identity. **This window is OPEN, and
  the flip's `d6_replace_stale` precondition does NOT close it today.** An earlier draft of this design said it did
  because "the latest rotate run must have concluded `success`". The reader does not do that (read in
  `git-data-cutover.yml`, precheck, the d6 loop): it walks the 40 newest `apply-web-platform-infra.yml` dispatch
  runs on `main`, `continue`s past every run whose `git_data_host_replace` job or whose step matching "rotate
  confirm token" did not conclude `success`, and stamps the FIRST older run that did. So a failed newest replace or
  rotate that already created the successor host is skipped (run 38140050880 is such a run: its job failed after
  the host work, and the reader would look past it), and the step it matches, "Validate dispatch inputs (rotate
  confirm token)", is unconditional and exits 0 with `rotate confirm: n/a` for any other target, so a plain
  replace reads as a rotate stamp (run 37846545572). Neither reading binds the stamp to THIS host generation, and
  the boot-signal poll is not part of the match at all.
  **Dependency, not a closure:** open issue #10166 (confirmed open: "decision: should the cutover's key-rotation
  check only accept a real rotate run?") is a blocker for treating `d6_replace_stale` as a control, and the
  predecessor window stays open until the d6 reader is hardened (the newest run, not the newest success, must be the
  one judged, and the match must be on the dispatch target rather than on a step that exits 0 by design).
  What the liveness precheck cannot supply, and the d6 reader must (or the owner must check by hand until it does):
  an independent proof that the ok event and the `boot_complete` come from the host that EXISTS now, namely that
  the newest replace run itself concluded `success` and that the live git-data host's Hetzner server id or creation
  time is later than the predecessor's last ok event. Until then the owner's runbook re-read, plus a look at the
  newest replace run's own conclusion, is the only control for this window; the build PR must not describe the
  window as closed.
- It is a point-in-time read before the freeze. The freeze window itself is bounded by the finalizer, not by this
  step.

## 8. Build PR checklist and authorization

Files: `apps/web-platform/infra/git-data-liveness-precheck.sh` and `.test.sh` (new); `.github/workflows/git-data-cutover.yml`
(the step, the header credential list and timing sentence); `apps/web-platform/infra/git-data-cutover-access.test.sh`
(order and the new rows); the runbook (precondition bullet reads "enforced by the `liveness_precheck` step of
`mode=flip`; this item is the record, the workflow is the control", plus a verdict-map row per `reason=` word and a
"read the sentinel first on a re-run" line); ADR-283 (Decision 5 and the Consequences sentence: #9943 delivered, an
amendment, not a rewrite of dated text); the workflow's job output `liveness_reason` and the `notify-failure` mapping of section 4 (closed `case`,
`LIVENESS_UNPROVEN` subject word, step-summary line, the vocabulary-parity row); the `host_proof` sentinel signal or
`github.run_attempt` fallback and the paging remedy of section 3 fork 2, with its notify-body test row; Read H's
`timeout -k 5 30`, the 540 s deadline and the `timeout-minutes` relation row of section 5; the single scrub set and
`--only-secrets` assertion on all three reads of section 4; and a repo-wide `git grep` for every consumer of the flag precheck's path
(`sandbox-hardening-contract.sh`, `encryption-posture-ledger.json`, `git-data-host-key-pin-shape-parity.test.ts` reference
`git-data-flag-precheck`) to confirm none needs a sibling entry.

The build PR edits `git-data-cutover.yml`, which carries the no-admin-merge restriction (the #9943 issue says so),
so it merges only on a green, reviewed PR. Nothing here is dispatched by an agent: the new step runs only inside an
owner-named `flip` dispatch behind the `web-platform-infra-apply` reviewer gate, and its first real exercise is that
flip. Until the step exists the runbook re-read is the control, so the owner keeps doing it; this design changes no
production state and no precondition today.
