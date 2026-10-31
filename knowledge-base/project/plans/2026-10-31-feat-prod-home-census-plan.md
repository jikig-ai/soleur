---
title: "feat: counts-only production-HOME census mechanism (Ref #10455)"
date: 2026-10-31
slug: prod-home-census
branch: feat-one-shot-10455-prod-home-census
issue: 10455
type: feat
closes: none
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: counts-only production-HOME census mechanism

## Overview

Follow-on to the sandbox measurement merged on 2026-10-31 (PR #11689). The operator authorized a read-only, counts-only,
metadata-only census of the production shared HOME (recorded on #10455, comment 6546444433). This plan designs the mechanism that
performs it and carries it through build, review and merge. **Building and merging the mechanism does not run it.** The plan phase
writes the plan and the task list only; no product code is written here. Every PR and comment uses `Ref #10455`, never `Closes`.
(`lane: cross-domain` is the fail-closed default: this feature has no `spec.md`.)

**The mechanism (CTO-ruled twice, CLO-approved with conditions; all rows in
`knowledge-base/project/specs/feat-one-shot-10455-prod-home-census/decision-challenges.md`, whose "Plan-review round" rows supersede
earlier rows):** a new secret-gated, synchronous internal route `POST /api/internal/home-census` in the web-platform container. It scans
the container's HOME with `lstat` and `opendir`/`readdir` only, classifies entries in-loop by directory and never retains a name, and
emits ONE bucketed-counts object to the HTTP caller, one Sentry info event and one pino line (to Better Stack). Inngest is not used. The
route is passive: nothing arms it, so a deploy cannot run it. It has a sunset constant after which it returns 410.

**The finding that shaped the design.** `/home/soleur` is the container's writable layer (Dockerfile `useradd -m soleur` and
`USER soleur`; the prod `docker run` in `ci-deploy.sh` binds only `/mnt/data/workspaces` and mounts `/tmp` as tmpfs). Every container
start wipes it. So no zero-deploy path exists, the deploy that ships the census also wipes the HOME it measures, and a census sees only
sessions since the container started. A zero is therefore never "clean"; it is "counted in this container since its last start". The
design labels this in every response (`interpretation`, `evidence`, `uptime_bucket`).

## Research Insights

**Premise Validation (2026-10-31, origin/main ba483a9948).** Held: #10455 is OPEN; comment 6546444433 authorizes the census (read-only,
counts and metadata only, no content, no values, no real identifiers, no SSH fallback, existing monitoring) and says "The method still
needs the CLO's approval of the exact mechanism before it runs"; the purge is authorized in principle only and not sized; PR 2 is a
separate item with its own gates. The CLO determination and the ADR-075 addendum 2026-10-31 exist as described. Collision pre-check:
the only open PR naming #10455 is this run's own draft PR #11712. Newly found: (1) the HOME does not persist across container starts;
(2) no zero-deploy path exists; (3) the reminder primitive's handler posts every check result to a GitHub issue and the repository is
PUBLIC; (4) both mechanisms the brief named lose on measured facts (see Alternative Approaches).

**Property List.** P1: count entries per CLI-state class in the production shared HOME without opening a file. P2: nothing but bucket
labels, booleans and enum members can reach any sink. P3: merge and deploy do not run it; one authorized trigger runs it, at most twice
in total. P4: the result is readable through existing monitoring without SSH. P5: the mechanism is proven on a synthesized HOME and the
proof is mutation-tested. P6: a nonzero count in a prompt-text-bearing class has a written re-open procedure. P7: a young HOME is never
read as clean.

**Cut List.** Purge of persisted shared data and PR 2 (out of scope by the brief). A GitHub issue-comment sink (public, permanent). A
recurring cron monitor or alert rule (one-off; ADR-046 I3). Per-tenant, per-workspace, per-file breakdowns, byte sizes, mtime-age
buckets and exact timestamps (fingerprinting; the CLO does not need the age window). Content-based classification (forbidden).
`/workspaces`, `/tmp/.cs`, `CLAUDE_CONFIG_DIR`, web-2, the canary container and outer-wrap cohorts (outside the approved scope; recorded
as unmeasured, not safe). Server-side run-id ledger, cooldown and `confirm` token (plan review: false assurance, reset per container).

**Repo facts carried forward** (content anchors). `event-scheduled-reminder.ts`: `CHECK_REGISTRY` entries return `{verdict, body, close?}`
and the handler unconditionally posts `result.body` to an issue; its row in `execution-placement.ts` is `portable` and Guard 2 of
`test/server/inngest/execution-placement.test.ts` forbids host-local reads there. `server/logger.ts` builds pino with no `base: null`
(every line carries `pid` and `hostname`, the container id in Docker) and mirrors warn-and-above to Sentry breadcrumbs.
`server/observability.ts` `infoSilentFallback` logs `{ err, ... }`. `cron-workspace-gc.ts` is a counts-only precedent but emits a path
and uses `stat`: not to be copied. Class sources: `REQUIRED_HOME_STATE` / `OPTIONAL_HOME_STATE` (locals in
`test/sandbox-wrapped-command-runtime.test.ts`), `HOME_SESSION_DIRS` (non-exported const in `server/agent-outer-wrap.ts`),
`sessionTranscriptDirs` in `server/agent-runner-sandbox-config.ts`. Route precedent: `app/api/internal/schedule-reminder/route.ts`,
`lib/internal-auth.ts`, exact paths in `lib/routes.ts`. Script precedent: `plugins/soleur/skills/trigger-cron/scripts/trigger.sh`.
`server/c4-render.ts` keeps state on `globalThis[Symbol.for(...)]` because a server module is bundled twice into one process.
`scripts/test-all.sh` `SUITE_GLOBS` covers `apps/web-platform/scripts/*.test.sh`, not root `scripts/*.test.sh`. Functional overlap
check: none in community registries.

**Institutional learnings applied.** One emitter and a strict allowlist whose test fails on any extra key
(`2026-05-12-client-side-pii-strip-when-server-pepper-cannot-ship.md`); one aggregate per run (`2026-05-13-mirror-with-debounce-vs-report-silent-fallback-for-high-cardinality-surfaces.md`);
a positive control so a dead scan cannot read zero (`2026-10-31-the-file-tool-hook-judged-one-path-field-and-a-new-export-broke-three-wholesale-mocks.md`);
count occurrences, exclude the instrument's own fixtures (`2026-07-17-an-instrument-commits-the-defect-it-measures.md`); the reviewer, not
the author, runs the mutation battery (`2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md`);
check census classes against the real CLI writer output (`2026-10-30-a-read-only-verifier-refused-the-store-its-producer-writes-and-its-census-was-a-lexer-arms-race.md`);
a registry that carries its own hash certifies itself (`2026-09-14-a-registry-that-carries-its-own-hash-certifies-itself.md`); never
write "clean" or "no exposure" (CLO determination wording constraints).

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "Mechanism candidates ... a self-armed Inngest oneshot (ADR-046) or the generic reminder primitive with a registered check" | The oneshot self-arm re-sends on every deploy and its `ts` is a clock, not an authorization; the reminder handler posts every check body to a PUBLIC issue and the function is `portable` | CTO ruled a third mechanism: a passive secret-gated synchronous internal route; both candidates recorded as rejected |
| "history.jsonl, debug/, todos/, tasks/ ... the production shared HOME" | The HOME is the container writable layer, wiped at every container start | 24 h maturity rule, `evidence`, `uptime_bucket`, mandatory `interpretation`; a zero is never "clean" |
| "the plan must name the exact command or trigger" | No existing trigger covers a non-cron host read (`trigger-cron` derives from `EXPECTED_CRON_FUNCTIONS`) | New committed script `apps/web-platform/scripts/home-census-trigger.sh` modeled on `trigger.sh`; command in "The production READ" |
| "reported through existing monitoring (Sentry / Better Stack)" | The shared pino logger adds `pid`/`hostname` and mirrors to Sentry; Sentry would attach request data | A dedicated `pino({ base: null })` instance and an isolation-scoped, processor-scrubbed Sentry event |
| "do NOT arm or run it ... unless the CLO has approved the exact mechanism" | CLO approved WITH CONDITIONS; C8 (re-read of the final diff, DISCHARGED) cannot be met before the diff exists and C9 needs 24 h of uptime | This run does not arm or run it; the real run is a tracked, later step (Phase 6) |

## Proposed Solution

### Files and boundaries

`apps/web-platform/server/home-census.ts` (scanner with an injected fs, class table, bucketing, allowlisted builder, emitter, `globalThis`
in-flight flag, positive control, sunset constant) and `app/api/internal/home-census/route.ts` (exports only `POST`, added as an exact
path in `lib/routes.ts`; `/api/internal` is never broadened). `apps/web-platform/scripts/home-census-trigger.sh` is the committed
trigger. No Inngest function, cron, flag, env var, Terraform or vector change.

### Request contract

`POST /api/internal/home-census`, `Authorization: Bearer <INNGEST_MANUAL_TRIGGER_SECRET>` (`readInternalBearerSecret` / `bearerMatches`,
constant-time, uniform 401/404, secret never logged). Body `{"run_id":<int>,"mode":"dry_run"|"real","expect_build_sha":"<hex>"}`.
Order: authenticate; sunset (410); parse; `mode`; for `real`: `expect_build_sha` must equal the server's own `build_sha` (409);
claim the in-flight flag (409 while a scan runs; held on `globalThis[Symbol.for("soleur.homeCensus.inflight")]`, tested with
`vi.resetModules()` and a re-import); positive control (503 `control_failed` on failure); scan.

- `mode` defaults to `dry_run`: it scans ONLY an in-memory synthetic HOME (`data_source:"synthetic"`), touches no real fs path (a spy on
  the real fs records zero calls), consumes no `run_id`, and still reports the REAL `uptime_bucket`, `build_sha` and `sunset_utc`, so a
  preflight can tell whether a deploy reset the container. `real` is explicit (`data_source:"container_home"`).
- Every response carries `Cache-Control: no-store`, sets no `Access-Control-*` header, and is built by the allowlisted builder.

### Scan design

- **Roots:** `process.env.HOME` (if absolute), `/home/soleur` and `/root`, labelled `env_home`, `home_soleur`, `root`, each with
  `root_present` and `root_listable`; a duplicate keeps the earliest label and `roots_distinct` is emitted. `os.homedir()` is wrapped in
  try/catch (`roots_note:"homedir_unavailable"`). The census code makes no fs call outside `lstat`/`opendir`/`readdir`.
  `CLAUDE_CONFIG_DIR` is NOT scanned (a new root would widen the approved scope): `claude_config_dir_set` (boolean) and constant
  `outer_wrap_cohorts:"unmeasured"` are emitted. Excluded: `/workspaces/*` and `/tmp/.cs`.
- **Fs calls:** `lstat` first; `opendir` only when the `lstat` result is a real directory, so a class directory that is itself a symlink
  is counted in `n_symlink` and never opened. One `lstat` per entry (mode bits need it), one in-flight fs op, `setImmediate` every 256
  entries so the libuv pool is not monopolised. Never `open`, `readFile`, `readlink`, `realpath`, `stat`, a stream or `child_process`.
- **Classes (closed enum, directory-level membership):** `history_jsonl`, `history_dir`, `debug`, `todos`, `tasks`, `projects`
  (children at depth 2), `sessions_json`, `sessions_key`, `shell_snapshots`, `account_state` (`.claude.json`), `backups`,
  `last_cleanup`, `statsig`, `file_history`, `other_under_claude`. A drift test (explicit dash-to-underscore id map; `HOME_SESSION_DIRS`
  exported from `agent-outer-wrap.ts` by a one-word edit; the `REQUIRED/OPTIONAL_HOME_STATE` locals parsed from the test file's source,
  with a count-above-zero positive control) fails when a class named there is missing from the table. Phase 0 confirms the directory
  layout against the vendored CLI's own writer code.
- **Per class, bucketed (`0`, `1-4`, `5-19`, `20-99`, `100-999`, `1000+`; zero is exact):** `n_entries`, `n_mode_bits_group_r`,
  `n_mode_bits_other_r`, `n_symlink`, `errors`; plus boolean `absent` (ENOENT is the per-class zero, not an error). Nothing else.
- **Caps:** 20,000 entries, 20 s, depth 3; a cap sets `truncated:true` and a `truncation_reason` enum, and a truncated result is final
  and reported as incomplete (raising a cap voids C8). No early exit before every class is visited. A stalled-fake-fs test proves the
  20 s cap fires.
- **Positive control:** the scanner takes an injected fs; before any real scan it runs against an in-memory fake fs with known per-class
  counts AND lists a known always-present directory on the real adapter (the canary), both folded into one `control` field. `real` is
  refused unless both passed; a canary failure never reads ok.

### The result object (hard allowlist; one emitter)

Allowed values: bucket labels, booleans, members of closed enums, and these constants: `schema_version`, `run_id` (int), `mode`,
`data_source`, `build_sha` (hex), `control` (`passed`|`failed`), `evidence` (`young` when the exact uptime is under 24 h, else `mature`),
`uptime_bucket` (`lt_1h`|`lt_24h`|`lt_7d`|`ge_7d`; `process.uptime()` under-approximates container age, which errs toward `young`),
`sunset_utc`, `truncated`, `truncation_reason`, `snapshot:"non_atomic"`, `mode_bits_semantics:"file_mode_only_not_reachability"`,
`interpretation` (constant: "counted in this container since its last start; not a statement about earlier windows or other hosts";
required on every response including zero), `claude_config_dir_set`, `outer_wrap_cohorts`, `roots`, `roots_distinct`, `classes`, and on
failure `ok:false` with `error_class` (enum). **Never emitted:** names or anything name-derived, paths, HOME or root values, sizes,
inodes, uid/gid, nlink, any timestamp other than the constant `sunset_utc`, pids, hashes, hostnames, container ids, workspace or user ids,
caller IP or headers, error text, exact counts, exact uptime, per-tenant breakdowns. No field, tag or comment uses "readable",
"reachable", "exposed" or "private". Exact values are used internally (the evidence rule) and never emitted.

### Sinks

Allowed: the HTTP response; ONE Sentry info event; ONE pino line. The pino line goes through a dedicated `pino({ base: null, level })`
instance on the same stdout destination (the shared logger adds `pid`/`hostname` and mirrors to Sentry). The Sentry event uses
`Sentry.withIsolationScope(iso => { iso.clear(); Sentry.withScope(s => { s.addEventProcessor(strip); Sentry.captureMessage(CONSTANT) }) })`
with a processor that deletes `server_name`, `contexts`, `request`, `user`, `breadcrumbs`, `extra` and every non-allowlisted tag; run-level
tags only (`run_id`, `evidence`, `truncated`, `control`, `mode`). Forbidden: GitHub comments, Inngest, any path in a log, any raw fs error.
Only `err.code` is read; `.message` and `.stack` never; no rethrow; the route catches everything and returns the allowlisted `ok:false`
object; no retries. A `dry_run` emits the same single event with `mode:"dry_run"` so a smoke is distinguishable from a run.

### The production READ (exact command; names the trigger)

This is an **operator-authorized production READ**. The authorization is recorded on #10455 (comment 6546444433); the CLO approved the
method with conditions C1-C10 (2026-10-31). **Building and merging this mechanism does not run it**, and no part of this planning run
arms or runs it. The run happens in a later, tracked session (Phase 6) only when: C8 is DISCHARGED and recorded on #10455 naming the
reviewed commit, the deployed scanner/emitter/class-table paths equal the reviewed ones, the server reports mature uptime (C9), the run is
inside the sunset and the two-run cap, and comment 6546444433 is cited. The command:

```bash
bash apps/web-platform/scripts/home-census-trigger.sh --mode real --run-id <N> --discharged-sha <sha> --pr <PR>
```

Behaviour: reads `INNGEST_MANUAL_TRIGGER_SECRET` read-only (`doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET -p soleur -c prd --plain`;
empty or failing Doppler fails closed), passes it to curl on its stdin config (never in argv, never echoed, refuses shell tracing,
token-shape guard); `--mode` has no default; for `real` it (1) fetches `refs/pull/<PR>/head`, confirms it equals `--discharged-sha`, and
runs `git diff --quiet <discharged-sha> <served build_sha> -- <CENSUS_PATHS>` (one constant of directory/glob pathspecs covering
`home-census*`, the route directory and the logger instance, so a new file cannot slip past); (2) runs a `dry_run` first and requires a
200 carrying `schema_version`, `uptime_bucket` at or past `lt_24h` and `evidence:"mature"` (or an explicit `--c9-fallback`); (3) refuses
a `run_id` at or below the last `home-census run_id=` marker on #10455 or when two claims already exist, then posts a write-ahead claim
comment `home-census run_id=<N> claim` BEFORE the request (a failed run still consumes its claim; `gh` failure fails closed); (4) sends
`expect_build_sha` read from `/health`, uses `curl --max-time 60`, and re-compares the response `build_sha` after the POST. Distinct exit
codes cover Doppler failure, 401/404 (uniform), 403, 5xx/502/504 and timeout-after-scan; a timeout after the scan is ambiguous and is
never auto-retried (read Sentry and Better Stack first). It prints the allowlisted JSON and the HTTP status. The equivalent request:

```bash
printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" | curl --disable --noproxy '*' --max-time 60 -sS -K - -X POST https://app.soleur.ai/api/internal/home-census -H 'content-type: application/json' -d '{"run_id":1,"mode":"real","expect_build_sha":"<hex>"}' -w '\n%{http_code}\n'
```

The preflight is `--mode dry_run --run-id <N>`; all exit and notify text names only the preflight, never the real command. `curl` flags
verified against `curl --help all` (`-K, --config`, `-q, --disable`, `--noproxy`, `-w, --write-out`, `--max-time`) on 2026-10-31.
A second real run is allowed only after a recorded `young` result and only when the container is already 24 h old when the executor
starts it; a deliberate extra run, any widening, or a hold on deploys needs a fresh typed operator message naming it.

### Result handling and wording

1. **Owner:** the engineering session started on the tracker (`soleur:go #<tracker>`) after `earliest`; it reads the response and reports
   the bucketed object plus `interpretation` to the operator and the CLO the same day on #10455, recorded as `home-census run_id=N`.
2. Only the object as emitted may be pasted into the public tracker or the Art. 33(5) file; nothing from Sentry is added (CLO L4).
3. Never say: "clean", "no exposure", "secure", "isolated", "protected", "private", "not readable", "empty", "census complete" (when
   truncated or the control failed), "no prompt text", "found prompt text", "leaked". Young zero: "At the run, a young container (uptime
   bucket X) counted 0 in class C. Insufficient evidence, not a negative finding." Mature zero: "None counted in this container since
   its start. Earlier containers no longer exist and are not measured." Nonzero: "Entries (bucket) were counted in class C, which we
   presume from the CLI's writer behaviour to hold prompt text. No names or content were opened, and whether any sibling can read them
   is not established by the census."
4. Interim support rule (CPO): no ad-hoc replies about shared-host data; inquiries go to the operator and the CLO; holding line "we are
   reviewing how session state is scoped on our hosts and will update you", never "safe", "isolated", "no evidence of access" or "not a
   breach" (CLO approves the wording at C8). Lives in the runbook.
5. The PR body and tracker comments say the census "will" run until it has (C10) and state that web-2, `/workspaces`, `/tmp/.cs`,
   outer-wrap cohorts and the canary container are unmeasured, not safe.

### C9 terminal state (CLO)

At most two real runs in total. The default terminal state is "unmeasured at maturity": the census stops after the first `young` result
with no later mature window before the sunset, or at the sunset. "Planned deploy" means the executor runs the census as a pre-merge step
of the next merge PR that touches `apps/web-platform` (that PR must not change the scanner, class table, fields or sinks, and its body
records the run). Holding non-security deploys is not authorized without a fresh typed operator message; security fixes are never held.

### Sunset and removal (C7)

`SUNSET_UTC` = merge date + 30 days, set when the PR is marked ready and corrected before merge if the merge slips; the route returns
410 afterwards and the sunset date is shown in `dry_run`. The route is disabled at the earlier of (last authorized real run + 30 days)
and the sunset. One extension of at most 15 days is allowed, from a PR that touches only that constant, reason recorded on #10455; total
standing time is under 60 days from the merge deploy. The sunset is the hard-disable; #11714 tracks deleting the dead code (route,
module, script, tests, the `lib/routes.ts` entry, and the Bearer secret use for this route).

<!-- lint-infra-ignore start: the re-open procedure records a legal determination sequence; it prescribes no infrastructure step -->
### The CLO re-open procedure (ask (e); summary, the canonical text is the runbook)

Prompt-text-bearing classes for re-open purposes (presumptive, by the CLI's writer behaviour; no content is read): `history_jsonl`,
`debug`, `todos`, `tasks`. `projects` is not a trigger (the G2 test did not find transcripts from the sibling's mount view; a nonzero is
informational and used for purge sizing). `shell_snapshots`, `account_state` and `sessions_*` are already conceded reachability classes;
a nonzero in `other_under_claude` is a flag to the CLO, not a trigger. **Trigger:** any nonzero bucket in one of the four classes, at
young or mature evidence. A zero never triggers. **Ordered steps:**

1. Anchor = the Sentry event timestamp (conservative), cross-checked with the Better Stack row time and the HTTP `Date` header; record it as the fresh awareness anchor.
2. Append a dated re-open addendum to `knowledge-base/legal/audits/2026-10-31-clo-determination-10455-shared-home-sibling-read-art-4-12.md` and amend the provisional breach-register row in-cell with the E1 result, marking each superseded sentence. The Art. 33 clock still starts only on second-limb evidence (a demonstrated sibling read).
3. Freeze every user statement about data isolation or safety and all public legal-document edits; support answers go through the CLO.
4. Run a G2-style repository test (synthetic tenants only) of whether the sibling's mount view reaches those four classes: the real reachability measurement.
5. Evidence preservation: no content snapshot or volume copy (it would create a second copy of prompt text); deploys are not held for evidence; a security-critical deploy proceeds; a counts-only repeat needs a fresh typed operator message.
6. Engage external counsel with the audit record and the bucketed counts only.
7. Art. 33(2): a nonzero alone does not trigger processor-to-controller notice; it is owed without a risk threshold on evidence of a sibling read. Check the tenant DPA's own notification clause (`knowledge-base/legal/data-processing-agreement-template.md`) first.
8. The CLO sizes the purge from the `n_entries` buckets (a later targeted census needs its own go-ahead); the purge is irreversible, needs a per-command operator go-ahead, and is NOT part of this work.
9. The ADR-075 relocation trigger "the census finding readable prompt text in the production HOME" is presumptively met; the CLO advises the CTO to relocate, because a purge without relocation recurs.

A zero or young result obliges nothing to users and no statement. After a mature zero no scheduled repeat is owed; repeat on a CLI
version bump or when the class list changes.
<!-- lint-infra-ignore end -->

## Alternative Approaches Considered

| Option | Verdict | Why |
|---|---|---|
| A. Self-armed Inngest oneshot (ADR-046) | Rejected (CTO) | The boot self-arm re-sends on every deploy and its `ts` is a clock, not an authorization; a gate would be a flag or env write; Inngest persists step outputs and event data |
| B. `named-check` in `CHECK_REGISTRY` via `schedule-reminder` | Rejected (CTO) | The handler posts `result.body` to a PUBLIC issue unconditionally; the function is `portable` (Guard 2 forbids host-local reads); `retries: 1` can double-scan |
| C. Cron-manifest manual trigger | Rejected (CTO) | Allowlist derived from `EXPECTED_CRON_FUNCTIONS`; a cron function brings a Sentry monitor and drift tests and recurs |
| D. New event-triggered Inngest function | Rejected (CTO) | Inngest persists whatever a step returns or throws; needs a placement row and a count bump |
| E/F. Secret-gated synchronous internal route | **Chosen (CTO)** | Passive, so "merge and deploy do not run it" is structurally true; none of the Inngest leak vectors |
| Host timer / SSH to the host | Rejected | `hr-no-ssh-fallback-in-runbooks`; needs an infra apply |
| Sizes, per-tenant breakdowns, timestamps | Rejected (CLO) | Fingerprinting; the purge is sized separately |

## Implementation Phases

Tests are written before their code (cq-write-failing-tests-before). Checklist: `knowledge-base/project/specs/feat-one-shot-10455-prod-home-census/tasks.md`.

- **Phase 0 (read-only).** Read `server/agent-outer-wrap.ts` and `server/agent-runner-sandbox-config.ts` to confirm where the CLI writes under the production posture (`outer_wrap=false`, shared HOME); confirm the class directory layout against the vendored CLI's writer code; confirm the isolation-scoped Sentry scrub with a real `Sentry.init` and capturing transport (SDK `@sentry/nextjs` 10.59.0); confirm `/health` reports `build_sha` without credentials. Stop and re-plan if the roots miss the real HOME.
- **Phase 1 (RED).** Failing tests: allowlist over REAL serialized output, fs-call unit tests, synthesized-HOME known answers, gate matrix, positive control, drift test, route registration, trigger-script tests.
- **Phase 2 (GREEN).** `server/home-census.ts`; the dedicated pino instance; the Sentry emitter.
- **Phase 3.** The route, `lib/routes.ts`, csrf-coverage and middleware rows (including a negative row that `/api/internal/home-census-x` is not public), the one-word `HOME_SESSION_DIRS` export.
- **Phase 4.** `apps/web-platform/scripts/home-census-trigger.sh` with `--self-check` and its test; the runbook `knowledge-base/engineering/operations/runbooks/home-census.md` (the canonical command, decode table, result handling, holding line, the canonical re-open procedure, retention, "uptime means since last container start", sunset); the minimal notify-only follow-through probe.
- **Phase 5.** The reviewer-run mutation battery for Guards 1 and 4 (below). The reviewer, not the author, runs it.
- **Phase 6 (deferred, tracked; the merge does not run it).** After merge: C8 DISCHARGED recorded on #10455 with the reviewed commit; verify the deploy and run the `dry_run` smoke; file the follow-through tracker (checklist: C8 DISCHARGED with sha, preflight `uptime_bucket` past `lt_24h`, next unused `run_id`, result recorded as `home-census run_id=N`); the later session runs the one real run under C9; reports; re-opens per the procedure if a trigger class is nonzero; the sunset disables the route and #11714 deletes it.
- **Records.** ADR-075 dated addendum (placed by date; notes the `lib/routes.ts` entry is removed with #11714); `compliance-posture.md` dated entry; the CLO audit record `knowledge-base/legal/audits/2026-10-31-clo-ruling-10455-census-method.md` carries only the C8 DISCHARGED entry and cites `decision-challenges.md` for C1-C10; PR body in future tense. The learning is deferred to compound.

## Open Code-Review Overlap

None of the planned files is named by an open `code-review` issue, except `apps/web-platform/server/observability.ts` (#3739), which this plan reads but does not edit. Disposition: acknowledge, different concern; it stays open.

## Files to Create

- `apps/web-platform/server/home-census.ts` (asks 1, 4, 6, 13)
- `apps/web-platform/app/api/internal/home-census/route.ts` (asks 1, 12)
- `apps/web-platform/test/server/home-census.test.ts` and `apps/web-platform/test/server/internal/home-census-route.test.ts` (asks 13, 14)
- `apps/web-platform/scripts/home-census-trigger.sh` and `home-census-trigger.test.sh` (ask 12)
- `apps/web-platform/scripts/home-census-mutations.test.sh`: the reviewer-run battery for Guards 1 and 4 (ask 14)
- `scripts/followthroughs/home-census-run-10455.sh` and its test: minimal notify-only probe (inferred; rule `wg-pm-class-followthrough-for-operator-dogfood`)
- `knowledge-base/engineering/operations/runbooks/home-census.md` (asks 11, 15)
- `knowledge-base/legal/audits/2026-10-31-clo-ruling-10455-census-method.md` (ask 10)

## Files to Edit

- `apps/web-platform/lib/routes.ts`: exact path `/api/internal/home-census`
- `apps/web-platform/lib/auth/csrf-coverage.test.ts` and `apps/web-platform/test/middleware.test.ts`
- `apps/web-platform/server/agent-outer-wrap.ts`: export `HOME_SESSION_DIRS` (one word; under the C8 re-read)
- `knowledge-base/engineering/architecture/decisions/ADR-075-agent-sandbox-tenant-read-isolation.md`: dated addendum
- `knowledge-base/legal/compliance-posture.md`: dated entry (CLO L4)

Deliberately unchanged: Inngest `app/api/inngest/route.ts`, `server/index.ts`, `function-registry-count.test.ts`, `execution-placement.ts`, `cron-manifest.ts`, `vector.toml`, `test/repo-wide-suites.ts` (app-local suites are not listed there), the shared `server/logger.ts` and the global Sentry `beforeSend`.

## User-Brand Impact

- **If this lands broken, the user experiences:** a result misread as clean (a young-container zero pasted into an issue or a support reply without its context) and later quoted to a user as a statement about their data; or the route emitting an identifier into Sentry or Better Stack.
- **If this leaks, the user's data is exposed via:** a workspace slug, user-equal workspace id, pid, hostname, container id, path or file name reaching a Sentry event, a pino line to Better Stack, an Inngest-persisted value or a public GitHub comment (for a solo workspace the workspace id equals the user id: pseudonymous personal data).
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one pseudonymous identifier in a public-adjacent sink, or one unqualified "0" quoted to a user while the history sits in a class the CLO calls unmeasured, is a single-user trust incident; no aggregate is needed.

`soleur:engineering:review:user-impact-reviewer` runs at review time. CPO sign-off 2026-10-31: APPROVE WITH CONDITIONS; the conditions are carried (mandatory `interpretation`, result handling with a named owner and same-day report, holding line, future-tense PR body, this section).

## Observability

```yaml
liveness_signal:
  what: one Sentry info event with the constant message "home-census result" plus one pino line (docker journald, vector, Better Stack) per run, and the HTTP 200 body returned to the caller
  cadence: per run; event-driven, no schedule (a one-off read with a sunset)
  alert_target: none for a successful run by design, the caller reads the response; a failed control or a failed scan returns 5xx and emits a Sentry error event reaching the existing Sentry issue-alert email
  configured_in: apps/web-platform/server/home-census.ts (the single emitter) and apps/web-platform/app/api/internal/home-census/route.ts

error_reporting:
  destination: Sentry (existing web-platform project, SENTRY_DSN); error-level event with a constant message and enum tags only
  fail_loud: non-2xx status with {"ok":false,"error_class":<enum>} (401/404 uniform, 409 busy or build mismatch, 410 sunset, 503 control_failed)

failure_modes:
  - mode: positive control failed (scanner or canary cannot enumerate a known answer)
    detection: response 503 control_failed plus a Sentry error event tagged control=failed, emitted from inside the container
    alert_route: Sentry issue-alert email
  - mode: scan truncated by a cap (entries, time or depth)
    detection: truncated=true and truncation_reason in the response, the Sentry tags and the pino line
    alert_route: reported in the result handling; "census complete" is forbidden wording
  - mode: young container (uptime under 24 h)
    detection: evidence=young tag in Sentry and in the response, with uptime_bucket
    alert_route: the follow-through tracker; at most one repeat (C9)
  - mode: allowlist violation at emit time (a value outside the closed set)
    detection: the builder throws, the route returns 500 and emits a constant-message Sentry error with no value
    alert_route: Sentry issue-alert email
  - mode: route left standing past the sunset
    detection: the route returns 410 after the sunset constant; sunset_utc is shown by dry_run
    alert_route: GitHub issue #11714 (deletion tracker)

logs:
  where: Sentry event plus pino line to Better Stack (docker journald, vector, existing app_container_journald source); read with scripts/betterstack-query.sh
  retention: existing and unchanged (Sentry plan-level; Better Stack per knowledge-base/engineering/operations/runbooks/betterstack-log-query.md); no extension (CLO L4)

discoverability_test:
  command: bash apps/web-platform/scripts/home-census-trigger.sh --self-check
  expected_output: HOME_CENSUS_TRIGGER_SELF_CHECK_OK
```

The self-check is offline (no network, no secret, no HOME read): it asserts the script builds the exact request, keeps the token out of argv,
refuses under shell tracing and refuses a malformed token. It verifies the trigger, not the signal; the signal is read after the real run
with `scripts/betterstack-query.sh` (credentials required, documented in the runbook). Layer citation (hr-observability-layer-citation):
the emitter runs inside the container, the blind execution surface, so each detection is an in-surface probe; the single event carries
`control`, `truncated`, `evidence` and `uptime_bucket`, which discriminate a dead scan, a capped scan and a young container in one event.

## Architecture Decision (ADR/C4)

### ADR

No new ADR (CTO). A dated addendum to ADR-075 ("Addendum - 2026-10-31 (#10455, census mechanism)") records: the mechanism and why the
Inngest candidates were rejected, the container-ephemeral HOME fact and its consequence, the closed class table and allowlist, the CLO
conditions C1-C10 by reference, and the sunset. ADR-046 is unchanged (not a oneshot).

### C4 views

No C4 change. Checked against all three model files (`knowledge-base/engineering/architecture/diagrams/model.c4`, `views.c4`, `spec.c4`):
(a) external human actor: the operator is already `founder`, no new actor; (b) external systems: Sentry (`webapp -> sentry`), Better Stack
(the `hetzner -> betterstack` journald edge for the web container) and Doppler are modeled and no vendor or edge is added; (c)
containers and stores: the route lives inside the existing web-platform container, and the HOME it reads is the container's writable
layer, which the model does not represent as a store and this change does not create one; (d) actor-to-surface access: the same shared
secret as `trigger-cron` and `schedule-reminder`, neither of which has a C4 element. Cardinalities embedded in edge prose are guarded by
`plugins/soleur/test/c4-count-parity.test.sh`, which must stay green (AC).

### Sequencing

Single PR; the ADR addendum describes the target state and lands with the code.

## Guard Contract

### Guard 1 - Emit allowlist (nothing but bucket labels, booleans and closed-enum members reaches any sink)

**Property.** No value outside the closed allowlist can reach the HTTP response, the Sentry event (message, tags, extra, contexts, `server_name`, request, user, breadcrumbs) or the pino line (including base fields).

**Assembly.** One chokepoint: the allowlisted builder and the single emitter in `server/home-census.ts`. Exactly three sinks (the response, the Sentry event captured by a real `Sentry.init` with a capturing transport, the pino bytes captured through a stream), plus every refusal and error response (401/404, 409, 410, 500, 503) built by the same builder. The test asserts the captured sink set has three members before it checks content; a response built outside the builder is a second chokepoint and is the defect.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a string field holding a synthesized path or file name | RED |
| 2 | Emit an unbucketed integer count or a size | RED |
| 3 | After a compliant class entry, add a second class entry carrying an extra key | RED |
| 4 | Build the error response from `err.message` outside the builder | RED |
| 5 | Route the pino line through the shared logger (restores `pid`, `hostname`) | RED |
| 6 | Drop the Sentry event processor (restores `server_name`, request data) | RED |
| 7 | Capture only two of the three sinks (the dispatch floor) | RED |
| 8 | Drop `interpretation` from a zero result | RED |

**Harness rows.** Edit the suite: replace the capturing transport with a spy on `captureMessage`; the "real event keys" assertion must go RED. Must-PASS inputs that are not the canonical: an all-zero result, a truncated result, classes in a permuted order, a `young` result, a `dry_run` result.

**Anchor.** One diff can weaken the allowlist and its test together. The outside anchor is the CLO C8 DISCHARGED record on #10455 naming the reviewed commit, and the trigger script's `git diff --quiet <discharged-sha> <served build_sha> -- <CENSUS_PATHS>` check, which refuses a real run if the census paths changed after the discharge; any later change to the class table, fields or sinks voids the approval.

### Guard 2 - Filesystem-call limit (the scanner can only `lstat` and `opendir`/`readdir`) - ordinary unit tests

**Property.** The census code cannot open, read, resolve, stat through symlinks or spawn.

**Assembly.** The injected-fs interface (it admits only `lstat` and `opendir`), the real adapter, and every import form that reaches the fs or a process in `server/home-census.ts` and its repository imports (`node:fs`, `fs`, `fs/promises`, dynamic `import()`, `child_process`). A small import-form test plus a zero-call spy on the real fs in `dry_run`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Import `readFile` in the scanner | RED |
| 2 | Replace `lstat` with `stat` | RED |
| 3 | After a compliant `lstat` import, add `readlink` (second member) | RED |
| 4 | Replace `lstat`-then-`opendir` with a bare `opendir` against a symlinked class directory fixture | RED |
| 5 | The import test scans an empty file list | RED (floor: at least one module scanned) |

**Harness rows.** Point the test at a nonexistent module path; it must fail. Must-PASS: a module that merely mentions `readFile` in a comment.

**Anchor.** The permitted set lives in the test and module together; the outside anchor is the C8 re-read by the CLO of the final diff.

### Guard 3 - Run gate (no real scan unless every condition holds) - ordinary unit tests

**Property.** A real scan happens only when the Bearer is valid, `mode` is explicitly `real`, `expect_build_sha` matches, the control passed, the sunset has not passed, and no other scan is in flight; two overlapping requests never both scan.

**Assembly.** The route handler and the `globalThis` in-flight flag. The check order is authenticate, sunset, parse, mode, build match, claim the in-flight flag BEFORE the scan, control, scan: a property of ORDER and LIFETIME.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Default `mode` flipped to `real` | RED |
| 2 | REORDER: set the in-flight flag after the scan instead of before | RED (needs the concurrent case) |
| 3 | A second concurrent request after a compliant first (second member) | RED |
| 4 | Scan although `control` failed | RED |
| 5 | Run after the sunset constant | RED |
| 6 | Revert the flag to a module-local variable | RED (`vi.resetModules()` re-import case) |

**Harness rows.** A case that observes INSIDE the window: two real requests with a blocking scanner stub; the second must be refused 409 while the first is mid-scan. Must-PASS: a real request after the first completes, and a `dry_run` while a real scan runs.

**Anchor.** State is process-local by design; the independent anchors are the Bearer secret in Doppler, the script-side claim ledger on #10455, and the C9 conditions.

### Guard 4 - Positive control and canary (a dead scan cannot report zero)

**Property.** If the scanner cannot enumerate a known tree, the run is refused; a scan that visited no class is never reported as zero evidence.

**Assembly.** The control (in-memory fake fs with known per-class counts), the real-adapter canary, and the per-class visited marker; all flow through the one builder into the single `control` field.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | The scanner stubbed to return all zeros | RED (control mismatch, `real` refused) |
| 2 | Remove the control call | RED |
| 3 | Early-exit after the first class (second class never visited) | RED (visited-all-classes floor) |
| 4 | Canary hard-coded true (a fake fs with an empty known directory) | RED |
| 5 | Disable the entry cap or the `truncated` marker | RED |
| 6 | Count lines instead of occurrences, or count the instrument's own fixture directory | RED |

**Harness rows.** Zero the known-answer fixture counts; the control test must go RED. Must-PASS: a fixture with a different class mix, including a symlink and an EACCES directory.

**Anchor.** The known answers live in the test and module; the outside anchor is the reviewer running the battery and deleting the control to confirm RED (learning 2026-07-19).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Build the production-HOME census the operator authorized (recorded on #10455, comment 6546444433)." | Proposed Solution; Phases 1-5 | mapped |
| 2 | "PLAN and BUILD the census mechanism through review and merge; do NOT arm or run it against production in this run" | The production READ; Phase 6 (deferred) | mapped |
| 3 | "counts-only, metadata-only, read-only over the production shared HOME" | Scan design; Guard 2 | mapped |
| 4 | "no file content opened, no values or real identifiers reproduced, no SSH fallback" | Guards 1 and 2; Sinks | mapped |
| 5 | "reported through existing monitoring (Sentry / Better Stack) as aggregate counts only" | Sinks; Observability | mapped |
| 6 | "Mechanism candidates to evaluate, do not assume" | Alternative Approaches | mapped |
| 7 | "any purge of already-persisted shared data is NOT part of this work" | Non-Goals | mapped |
| 8 | "PR 2 (promote the deploy SDK-Bash smoke to blocking) is NOT part of this work" | Non-Goals | mapped |
| 9 | "the CLO must rule on the exact census mechanism (technical forks go to the CTO, never to the operator)" | decision-challenges.md | mapped |
| 10 | "Both rulings must be recorded in decision-challenges.md before the plan is final." | decision-challenges.md | mapped |
| 11 | "(b) The plan must name the exact command or trigger that would run the census in production" | The production READ | mapped |
| 12 | "(c) ... a hard allowlist of emitted fields and a test that fails if any path, file name, identifier, size distribution that could fingerprint a user, or content byte can reach the sink" | The result object; Guard 1 | mapped |
| 13 | "(d) Plan a dry-run/fixture mode proven against a synthesized HOME tree (no real data), mutation-tested." | `dry_run` mode; Phases 1 and 5; Guards 1-4 | mapped |
| 14 | "(e) Include the CLO determination re-open procedure if any class returns a nonzero count for prompt-text-bearing files." | The CLO re-open procedure | mapped |
| 15 | "(f) Produce the plan and tasks only; do not write product code." | This run's output is the plan and tasks.md | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `server/home-census.ts`, the route, `lib/routes.ts` | "Build the production-HOME census" | asked |
| `home-census-trigger.sh` | "name the exact command or trigger" | asked |
| Allowlist tests and the mutation battery | "mutation-tested" | asked |
| Runbook and the CLO method-ruling record | "the CLO must rule on the exact census mechanism" | asked |
| ADR-075 addendum | "ADR-075 addendum 2026-10-31 for the method constraints and relocation triggers" | asked |
| csrf-coverage and middleware rows, `HOME_SESSION_DIRS` export | "Build the production-HOME census" | inferred - justification: the route-registration contracts fail CI for an unregistered internal route; the drift test needs the class source importable |
| `compliance-posture.md` entry | "the CLO must rule on the exact census mechanism" | inferred - justification: CLO ruling L4 requires a dated entry |
| Follow-through probe and tracker | "do NOT arm or run it against production in this run" | inferred - justification: CLO C9 sets a 24 h window and rule `wg-pm-class-followthrough-for-operator-dogfood` requires a committed probe for an operator-only route |
| Sunset constant and #11714 | "the CLO must rule on the exact census mechanism" | inferred - justification: CLO C7 forbids a standing scanner |
| `interpretation`, holding line, result handling | "Brand-survival threshold is single-user incident" | inferred - justification: CPO sign-off conditions |

### Split Assessment

- Subsystems touched: 3 - `apps/web-platform`, `scripts`, `knowledge-base`
- Planned files: 18 | Estimated changed lines: about 1500, mostly tests and records
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the lines threshold is exceeded only by tests and records. The seam would be {follow-through probe} versus the rest; declined, because the CLO re-reads one diff (C8) and a split would separate the route from its allowlist proof.

## GDPR / Compliance Gate

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

Phase 2.7 gate (advisory; fired because the plan creates `apps/web-platform/app/api/internal/home-census/route.ts` and the threshold is `single-user incident`). The CLO already ruled on the legal method; this pass adds nothing that contradicts it. Column names only.

| check_id | Result | Note |
|---|---|---|
| GDPR-Art-6, Art-5e, Art-17, Art-17-caller | not applicable | No schema, migration, table or FK |
| GDPR-Chapter-V | not applicable | No new vendor or SDK; Sentry and Better Stack are existing processors |
| GDPR-Art-9 | no finding | No special-category column; directory metadata only |
| AP-01, AP-04 | covered | Response only through the allowlisted builder; aggregates only |
| AP-02 | not applicable | No per-user object |
| AP-05 | covered | Errno enum and `error_class` only; uniform 401/404 |
| AP-06 rate limiting | Suggestion | Bearer guesses are possible at the same rate as `trigger-cron`; acknowledged (constant-time compare, long secret, same class); AC: same edge protections |
| AP-07 CORS | Suggestion | AC: no `Access-Control-*` header |
| Art. 5(1)(c), 25, 32(1)(d) | covered by CLO ruling | Bucketing, no names retained, transient scan |

No Critical finding. The CLO-required `compliance-posture.md` entry is a planned edit.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `POST /api/internal/home-census` exists, exports only `POST`; the exact path is in `lib/routes.ts`, the csrf-coverage list and the middleware test, with a negative row that `/api/internal/home-census-x` is not public; `/api/internal` is not broadened.
- [ ] `dry_run` is the default; it records zero calls on the real fs (spy), scans only an in-memory synthetic HOME (`data_source:"synthetic"`), consumes no `run_id`, and reports the real `uptime_bucket`, `build_sha` and `sunset_utc`.
- [ ] The result matches the closed allowlist; a test over the REAL serialized outputs of the three sinks (response, Sentry event via a real `Sentry.init` with a capturing transport, pino bytes via a stream) fails on any extra key, free string, unbucketed count, `pid`, `hostname`, `server_name` or request data, and asserts three sinks were captured.
- [ ] A synthesized HOME (in-memory fake fs and an on-disk tmp tree with canary names and contents, no real data) yields exactly the expected bucketed counts per class, including a symlink, a symlinked class directory, an EACCES directory, an over-cap case and an empty tree; the canaries never appear in any sink.
- [ ] A raw fs error with a path in its message never reaches a sink; only the enum does.
- [ ] A stalled fake fs proves the 20 s cap fires and returns `truncated`.
- [ ] The gate matrix passes: uniform 401/404, 503 missing secret, default `dry_run`, 409 concurrent real (blocking stub, observed inside the window), 409 build mismatch, 410 after the sunset, 503 `control_failed`, `Cache-Control: no-store`, no `Access-Control-*`; the in-flight flag survives `vi.resetModules()`.
- [ ] The class drift test passes and fails when a class is removed from the table.
- [ ] The reviewer ran every Guard 1 and Guard 4 mutation and recorded each as RED in the PR; the baseline is green; a battery applying zero mutations fails.
- [ ] `bash apps/web-platform/scripts/home-census-trigger.sh --self-check` prints `HOME_CENSUS_TRIGGER_SELF_CHECK_OK`; its test covers xtrace refusal, token-shape refusal, token absent from argv, `--mode` required, claim-ledger refusal, and the discharged-sha path check.
- [ ] `plugins/soleur/test/c4-count-parity.test.sh` and the C4 validation tests stay green; the route inherits the same edge protections as `trigger-cron`.
- [ ] ADR-075 addendum, `compliance-posture.md` entry, the runbook (command, holding line, re-open procedure, uptime meaning) and the CLO record are committed; the PR body uses the future tense, says `Ref #10455` (no `Closes`), states the unmeasured list, and contains no real identifier, pid, hostname or container id.
- [ ] No Inngest file, `server/index.ts`, `execution-placement.ts`, `cron-manifest.ts`, `vector.toml`, shared `server/logger.ts` or `test/repo-wide-suites.ts` is changed; the `SUNSET_UTC` constant equals the ready date plus 30 days.

### Post-merge (tracked; not run by the merge)

- [ ] C8 DISCHARGED is recorded on #10455 naming the reviewed commit.
- [ ] The deploy is served and the `dry_run` smoke succeeds.
- [ ] The follow-through tracker exists with `earliest` = the shipping deploy + 24 h.
- [ ] The real run happens under C9 and the bucketed result is reported the same day; a nonzero in `history_jsonl`, `debug`, `todos` or `tasks` starts the re-open procedure.
- [ ] #11714 is closed by the deletion PR after the sunset.

## Domain Review

**Domains relevant:** Engineering, Legal, Product (sign-off only)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Ruled the mechanism, gate, sinks, scan design, timing and architecture record, then ruled the plan-review forks (gate state, matrix scope, result surface, sinks, binding, follow-through, sunset, docs). See decision-challenges.md.

### Legal (CLO)

**Status:** reviewed
**Assessment:** APPROVED WITH CONDITIONS C1-C10; then ruled the C9 terminal state, the field cuts, the sunset bound and the executor. See decision-challenges.md.

### Product (CPO)

**Status:** reviewed
**Assessment:** CPO sign-off 2026-10-31: APPROVE WITH CONDITIONS, all carried above. No UI surface; no wireframe or copy review applies.

## Test Scenarios

1. Synthesized HOME with history, debug, todos, tasks, projects (3 slugs), sessions, snapshots and canary-named files: exact bucketed counts; canary strings absent from all sinks.
2. A directory name and a file content containing a synthesized path and id: neither appears anywhere.
3. `lstat` throws an error whose message embeds a path: only the enum is emitted.
4. A symlink to a directory with entries, and a class directory that is itself a symlink: counted in `n_symlink`, never opened.
5. Over-cap tree: `truncated:true`, every class visited. Stalled fake fs: the 20 s cap fires.
6. Empty fake fs: control passes, all classes `0`, `evidence` is `young`, `interpretation` present.
7. Control or canary failure: `real` refused with 503; no scan.
8. Two concurrent real requests: the second gets 409 while the first is mid-scan; the flag survives a module reset.
9. Build mismatch: 409. After the sunset: 410. Wrong or absent Bearer: uniform 401/404 before body parse.
10. Drift: a class added to `HOME_SESSION_DIRS` but not the census table fails.

## Non-Goals / Deferrals

- The purge of already-persisted shared data: NOT part of this work; the CLO sizes it after the census; it needs a per-command operator go-ahead.
- PR 2 (promote the deploy SDK-Bash smoke to blocking): NOT part of this work; its own gates.
- `/workspaces`, `/tmp/.cs`, `CLAUDE_CONFIG_DIR`, web-2, the canary container and outer-wrap cohorts: unmeasured, not safe; adding any needs a fresh operator message.
- Relocation of CLI state (`CLAUDE_CONFIG_DIR`): only on a CLO re-open (ADR-075 trigger); the CTO decides then.
- Deleting the dead route code after the sunset: tracked in #11714.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this plan fills it.
- Do not restore a seconds-resolution uptime field, an exact count, an age bucket or a `confirm` token: the rulings are bucketed everywhere and the evidence thresholds stay internal.
- The shared `server/logger.ts` adds `pid` and `hostname`; the census pino line must use its own `base: null` instance and must not carry an `err` key.
- Sentry `server_name` is set before a scope processor runs only in some paths; the test must use a real `Sentry.init` and a capturing transport, never a spy on `captureMessage`.
- The real run must not be started by the merge, the deploy or this pipeline's ship step; the only authorized start is Phase 6 after C8 and C9.
- `usedRunIds`, the cooldown and the server-side ledger were cut on purpose (per-container, reset on deploy); the ledger that counts is the claim comment on #10455.
