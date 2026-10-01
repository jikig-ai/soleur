---
title: "fix: zot upload-ceiling follow-through probe counts the wrong rows (#7556)"
date: 2026-10-01
slug: zot-upload-ceiling-probe-selector
branch: feat-one-shot-7556-zot-ceiling-probe-selector
issue: 7556
type: fix
priority: p1
domain: engineering
brand_survival_threshold: none
lane: cross-domain
closes: none
---

## Enhancement Summary

**Deepened on:** 2026-10-01
**Mode:** frugal, headless (operator preference: no external research, no full-agent fan-out; the four-reviewer
plan review already ran). Verification passes were done directly against the repo and the already-measured
Better Stack data.

### Gates run (deepen-plan Phase 4.x)

- 4.6 User-Brand Impact: present, threshold `none`, scope-out line present, no sensitive-path file in Files lists.
- 4.7 Observability: section added (the plan's Files are `.sh`, outside the pure-docs skip); the discoverability
  command was executed credential-free and prints `TRANSIENT`; first token `bash` is allowlisted
  (`probe-verb-gate.sh` rc 0); no shell-active characters; finishes in about 1 s.
- 4.8 PAT-shaped variable: no match. 4.9 UI wireframe: no UI surface. 4.10 Encryption posture: no store or new
  connection (read-only reads of an existing warehouse). 4.4 precedent-diff and 4.55 downtime: not triggered.
- 4.11 Guard Contract: `lint-guard-contract.py` green (2 entries); adequacy read: both Assemblies name the
  chokepoint (python3 classifier, `fetch` helper), not today's members; matrix rows derive from the design.
- 4.45 verify-the-negative: the only `MUST NOT` hit is the header-comment title "WHAT THIS PROBE MUST NOT DO",
  not a security claim.

### Verified live this pass

- Issues: #7556 OPEN, #7555 CLOSED, #9353 OPEN (draft), #8659 and #7942 OPEN, #7440 and #6288 CLOSED.
- Commits `abd29f4bcf` and `173f7889b0` resolve (`git cat-file -t` -> commit); ADR-096/184/190/192/193/197 exist;
  rules `cq-write-failing-tests-before`, `cq-test-fixtures-synthesized-only`,
  `hr-verify-repo-capability-claim-before-assert` are active in AGENTS.md; label `deferred-scope-out` exists.
- Every lint/script cited in Verification commands exists; `SCRIPTS_SHARD=1/7 bash scripts/test-all.sh
  --enumerate scripts` runs in about 9 s and reports `82 registration(s) assigned of 525 walked`, so AC17 is
  executable as written.
- The anchored PATCH regex matched 44 of 103 live rows; 1913 live DROPPED rows were all `rate_cap`; a live
  anchor read returned heartbeat rows inside the window (Research Insights).

### New considerations from this pass

- The Observability section and this summary were the only edits in this pass (AC17 was verified executable, not changed); no design change.
- The new probe's discoverability command intentionally verifies "runnable and emits a verdict", not production
  state; production state is the sweeper's job and the PR must not claim otherwise.

## Overview

Spec lacks valid lane: - defaulted to cross-domain (TR2 fail-closed). No `closes:` by design: PR body uses `Ref #7556` because the tracker closes itself when the probe passes.

The daily follow-through probe for #7556 reports a sample shortage on every sweep because its
sample-floor denominator selects a string that only appears on zot error lines and on a heartbeat
echo of a stale error, never on successful upload rows. Real upload traffic is present. This plan
re-selects the rows, field-isolates them, and keeps the probe from ever claiming a state it could
not establish.

## Research Insights

### Premise Validation (Phase 0.6)

- **#7556** is OPEN (labels `follow-through`, `priority/p1-high`); its directive still points at
  `scripts/followthroughs/zot-upload-ceiling-7556.sh`. **#7555** (the deadline raise, ADR-190) is
  CLOSED, delivered 2026-08-16. Draft PR **#9353** is open. Nothing cited is stale.
- The probe exists on `origin/main` (last touched by `173f7889b0`, #7552) and has never changed since.
- **ADR corpus check.** ADR-190 (the fix this probe grades; status `adopting` until the first PASS),
  ADR-192 (an empty read is three states), ADR-193 (anti-vacuity floors), ADR-197 (a zero from a log
  surface needs a coverage and an instrumentation assertion) and ADR-184 (the shipper) were read. None
  rejects the mechanism; ADR-197 is the governing frame (see Properties below).
- **Operator findings spot-checked and reproduced** against Better Stack on 2026-10-01 (read-only
  `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh`): `blobs/uploads` 7d =
  103 SOLEUR_ZOT_LOG rows (44 PATCH / 47 PUT / 12 POST); `PatchBlobUpload` 7d = 2 rows, both
  SOLEUR_ZOT_DISK heartbeats echoing the same stale `zot_last_err` (EOF, 2026-09-28T17:25:31Z).

### NEW findings this planning pass added (each measured, not reasoned)

1. **The old retention guard can never pass, independent of the selector.** The guard requires
   `last_dt - first_dt >= 168h` over rows fetched with `--since 7d`. Every row satisfies
   `dt >= now()-7d` and `dt <= now()`, so the span is `<= 168h` with equality only at the two
   endpoints. After the selector fix the probe would have moved from `too-few-samples` to
   `retention-shorter-than-window` forever (the PATCH rows span 155.4h today). It was invisible
   because the floor tripped first.
2. **The `PatchBlobUpload` error line is NOT cap-exempt in practice.** `is_cap_exempt` in
   `apps/web-platform/infra/cloud-init-registry.yml` keys on the zerolog `.message` prefix
   `PatchBlobUpload*`; the real error line is `message:unexpected error, removing .uploads/ files`
   with the handler name only in `func:`. Evidence: the 2026-09-28T17:25:31Z error appears in the
   heartbeat's `zot_last_err`, the paired `HTTP API` row is in the warehouse (PATCH, `statusCode:500`,
   `latency:5m55s`), and there is **no SOLEUR_ZOT_LOG error row** for it. So a numerator made only of
   error rows is structurally blind. The HTTP-API half of the pairing IS exempt
   (`is_upload_failure_evidence`: 5xx on `/v2/*/blobs/uploads/*`, sub-quota 8/tick) and survives.
3. **The shipper-drop caveat, quantified.** 7d of `SOLEUR_ZOT_LOG_DROPPED`: 1913 rows, **100%
   `reason=rate_cap`**, zero `exempt_cap` / `redact_failed` / `sanitized_empty` /
   `cursor_invalidated`. `rate_cap` drops hit the ordinary lane only (cap 17 rows per 5-min tick), which
   is where successful PATCH rows and the error line live; the exempt lane (failed-upload HTTP halves,
   gc, crash) was never overflowed. So the drop count (heartbeat `dropped_cum=1215`) does not weaken the
   exempt-lane evidence; it does mean the PATCH-row count is a lower bound and the error line is
   unreliable.
4. **The sample unit.** The 44 PATCH rows are 18 pushes (clusters split at a 30-minute gap; 1-6 rows
   each). The "~1 in 13" failure rate is per release, so an unfixed pipeline shows zero failures over 18
   pushes with probability (12/13)^18 ~ 24%. The absence half is a tripwire, not proof; the DELIVERY
   half (zot's own parsed config) is the causal evidence.
5. **Live coverage anchor works.** `--since 8d --until <now-7d+6h> --grep SOLEUR_ZOT_DISK --limit 20`
   returned 20 real heartbeat rows (2026-09-24 13:05 -> 14:40), so retention reaches the window start.

### Real row shapes (synthesize fixtures from these; values in fixtures are fabricated)

- Success/failure upload row (one decoded `.message`, shipper prefix + sanitized zerolog; `"` and `\`
  are stripped by the producer):
  `SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry {time:<ts>,level:info,message:HTTP API,module:http,username:zot-push,component:session,clientIP:<ip:port>,method:PATCH,path:/v2/<repo>/blobs/uploads/<uuid>,statusCode:202,latency:29s,bodySize:0,headers:{...User-Agent:[...]},caller:...session.go:92,func:...SessionLogger.func1.1,goroutine:N}`
- Error line: `{time:<ts>,level:error,message:unexpected error, removing .uploads/ files,error:<unexpected EOF | read tcp ...: i/o timeout>,caller:...routes.go:2078,func:zotregistry.dev/zot/v2/pkg/api.(*RouteHandler).PatchBlobUpload,goroutine:N}`
- Heartbeat: `SOLEUR_ZOT_DISK pcent=.. ... host=soleur-registry zot_last_err={<the error line above>}` (the
  echo is what the old denominator counted).
- Drop accounting: `SOLEUR_ZOT_LOG_DROPPED n=<k> interval_s=300 boot_id=<id> seq=<n> cum=<n> reason=<rate_cap|exempt_cap|redact_failed|sanitized_empty|cursor_invalidated>`
- Anchored PATCH regex validated against the live 7d set: matches exactly 44 of 103 rows.

### Property List and Cut List (Phase 0.6b)

Properties the ask buys:

- **P1** a sample floor that counts real upload traffic and nothing else (not heartbeat echoes, not
  webhook rows quoting the string);
- **P2** a failure numerator that cannot be fed by a heartbeat echo of a stale error;
- **P3** an absence claim that rests on evidence which survives the shipper's caps;
- **P4** a coverage claim (the warehouse reaches the window start) that can actually be satisfied;
- **P5** truncation and every unestablished state exit 2 with a distinct `reason=` (ADR-197).

Mechanisms considered and cut (each with what already covers it):

- A shared selector library in `scripts/lib/` -> the probe's own comment already defers extraction to
  the third caller; there is still one.
- Scoping the floor/absence rows to the newest boot -> would starve the floor (the newest boot is
  ~2 days old) and delivery is baked in `user_data`, so every boot since 2026-08-16 carries the value.
- Raising the window beyond 7d or the floor to a power-derived value -> unreachable at 18 pushes/week;
  the DELIVERY half is the causal evidence (see Decision D2).
- Counting PUT rows as the denominator -> monolithic uploads (POST+PUT) never traverse the PATCH
  handler this probe grades.
- Fixing the shipper's `is_cap_exempt` here -> a `cloud-init-registry.yml` change is a registry-host
  replace (ADR-096); out of scope, filed as a follow-up (see Deferrals).

### Learnings applied

- `2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md` and #6475: decode
  first, isolate on a structural position, fixtures in the real double-encoded shape.
- `2026-08-04-my-probe-passed-against-the-outage-it-was-built-to-detect.md` and
  `2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire.md`: a probe that
  cannot fire/pass is worse than none; drive the PASS path with a fixture.
- ADR-193 / `2026-08-13-i-wrote-two-guards-against-vacuity-and-both-guards-were-vacuous.md`: floor
  reports with `printf >&2` + `exit 1`, case counter at the call site, conservation check.
- `2026-09-20-my-probe-graded-itself-against-a-clock-its-grader-never-read.md`: probes run under
  `env -i` from the sweeper; nothing but the declared secrets reaches them.
- The sweeper posts probe stdout as a comment on a PUBLIC issue: print counts only, never row
  excerpts (rows carry internal IPs, repo names, usernames).

## Problem Statement

`scripts/followthroughs/zot-upload-ceiling-7556.sh` grades two things: DELIVERY (zot's boot
`configuration settings` line reports both deadlines at `1800000000000` ns) and ABSENCE (no deadline
cut over a 7-day window). Its exit code auto-closes #7556 and unblocks ADR-190 `adopting -> accepted`.
Since 2026-08-21 it has returned `TRANSIENT reason=too-few-samples patch_rows=2 min=12`.

Three independent defects sit on the path from "uploads happened" to a PASS. The brief names the
first; the other two were found while planning and would each have kept the probe from ever passing:

| # | Defect | Effect today | Effect after only fixing #1 |
|---|---|---|---|
| 1 | Denominator is `grep -c 'PatchBlobUpload'`, a handler **func name** that appears only on error lines and on the heartbeat's `zot_last_err` echo | `too-few-samples` forever (2 echoes) | fixed |
| 2 | Retention guard needs `span(rows) >= 168h` over rows fetched with `--since 7d`; that is unsatisfiable by construction | masked by #1 | `retention-shorter-than-window` forever |
| 3 | Numerator is error rows only, but the real error line is not in the shipper's cap-exempt classes; the 2026-09-28 EOF produced no SOLEUR_ZOT_LOG error row | absence claim rests on a channel measured to drop the thing it looks for | a PASS would assert absence off a blind numerator |

A fourth, smaller defect is fixed on the way because the new reads would trip it: the shared
`is_error_payload` helper greps the WHOLE raw output for `exception|syntax error|Code: N`, and the new
`blobs/uploads` selector pulls in GitHub-webhook rows that quote issue bodies, so one row quoting "syntax
error" would wedge the probe at `query-error-payload-*` for up to 7 days.

## Proposed Solution

One file changes behaviour (`scripts/followthroughs/zot-upload-ceiling-7556.sh`), one test file is
created, one registration line is added to `scripts/test-all.sh`. Query and verdict sequence after the
change (every step before PASS exits 2 with its own `reason=` unless noted). Plan review (below)
simplified the first draft: one `fetch` helper for all reads, one python3 classifier, no legacy-60 s
signature, no regex pre-compile step.

1. Unchanged preflight: query executable, python3, `window-too-short`.
2. Unchanged DELIVERY half (config line; `deadline-mismatch` is the existing exit 1), except it now reads
   through `fetch`.
3. **`fetch NAME LIMIT ARGS...`** is the one read helper used by every query. It runs the query, and exits 2
   with `query-failed-NAME` (nonzero rc; rc 3 keeps its credential-guard hint),
   `query-error-payload-NAME` (a STRUCTURAL check: every non-empty output line must parse as a JSON object
   carrying `dt` and `raw`; a text grep for "exception" over raw rows is how a webhook row quoting the word
   wedges the probe), or, when `LIMIT` is non-zero and the raw row count is `>= LIMIT`, `query-truncated-NAME`
   (reported AFTER classification, see step 6). `betterstack-query.sh` keeps the NEWEST `LIMIT` rows
   (`ORDER BY dt DESC LIMIT`, re-sorted ASC), so a full page silently loses the OLDEST part of the window.
4. **Uploads read**: `fetch log 5000 --since $WINDOW --grep 'blobs/uploads' --grep 'PatchBlobUpload'`
   (OR-combined; `_` and `%` are LIKE wildcards in every `--grep`, harmless because every row is prefix-pinned
   after decode, and said so in a comment).
5. **Classify in ONE python3 pass** over the decoded rows. The helper prints one fixed-shape line
   `patch=N n1=N n2=N other5xx=N unparse=N upload_any=N`; the shell validates it with a strict regex and
   exits 2 `classifier-failed` on any other output or nonzero rc, so a crashed helper can never fold to
   zero (the file's `|| true` / `${x:-0}` idiom would turn "helper died" into "no findings" -> PASS).
   Python also removes the grep-chain compile hazard: a bad regex raises (-> `classifier-failed`), so there
   is no separate pattern pre-check. Rules, all on rows pinned by the positive offset-0 envelope
   `SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry` (plus a trailing space) (a SOLEUR_ZOT_DISK heartbeat, a webhook
   row quoting the string, or another host cannot enter any count):
   - Cut the row at `,headers:{` first (client text lives after it).
   - **Upload row**: head matches `^<envelope>\{time:[^,]+,level:[a-z]+,message:HTTP API,` and then
     `,clientIP:[^,]+,method:([A-Z]+),path:/v2/[^,]+/blobs/uploads/[^,]*,statusCode:([0-9]{3}),latency:([^,]+),`.
     `method` directly after `clientIP` is a server-controlled position, so a crafted client path cannot supply
     it. `upload_any` counts upload rows of any method. **`patch`** counts those with `method=PATCH`: this is
     the sample. Validated against the live 7d set: 44 PATCH of 103 rows.
   - **n1** (error-row corroboration, as briefed, best-effort only): pinned row with `level:error` containing
     `PatchBlobUpload` and `i/o timeout`.
   - **n2** (the exempt HTTP half, the claim-bearing signal): an upload row of ANY method
     (PATCH/PUT/POST; the deadline is server-wide and the shipper's own predicate is "any 5xx on that path")
     with `statusCode` 5xx and `latency >= 95% of DEADLINE_NS` (1710 s). ADR-190's reproduction records that a
     deadline cut logs `statusCode:500` with `latency` at the deadline, which is the evidence that a cut is a
     5xx row. A 5xx at any other latency (the real 2026-09-28 EOF was `5m55s`) is `other5xx`: printed, not
     graded, because EOF is out of scope for #7555. A 5xx whose latency matches no Go-duration shape
     (`h`/`m`/`s`/`ms`/`us`/`µs`/`ns`) is `unparse`.
6. **Verdict order after classification** (presence findings first; a floor and every coverage guard only
   qualify an ABSENCE claim):
   1. `n1 + n2 > 0` -> **exit 1** `deadline-submode-present` (even on a truncated page: the newest N rows are
      still real rows, and even when `unparse > 0`).
   2. `unparse > 0` -> `latency-unparseable`.
   3. raw page was full -> `query-truncated-log`.
   4. `patch < MIN_SAMPLES` -> `too-few-samples patch_rows= upload_rows_any= min= window=`. `upload_rows_any`
      is printed so a future shape drift (many upload rows, zero PATCH matches, i.e. today's bug class) is
      readable from the verdict line alone.
7. **Exempt-lane drop guard**: `fetch dropped 20000 --since $WINDOW --grep SOLEUR_ZOT_LOG_DROPPED`. Rows are
   prefix-pinned (`SOLEUR_ZOT_LOG_DROPPED` (plus a trailing space)). `reason=rate_cap` is the only benign reason (it drops
   ordinary-lane rows only); any other reason, or a pinned row with no parseable reason, means an exempt-lane
   or pre-ship drop could have lost the failed-upload half -> `exempt-lane-dropped reasons=<r:n,...>`. Measured
   7d: 1913 rows (about 11% of the 20000 page), all `rate_cap`. Accepted trade-off, stated in a code comment:
   a single non-`rate_cap` drop in the window blocks PASS until the window rolls past it, and an allow-list of
   one is deliberate (a future drop reason must fail closed).
8. **Coverage anchor** (replaces the span guard): `fetch anchor 0 --since $WINDOW --until <window start + 6h as
   ISO-Z, computed in python3> --grep SOLEUR_ZOT_DISK --limit 20`. At least one decoded row must start with
   `SOLEUR_ZOT_DISK` (plus a trailing space) (offset-0 pin). Because `--since` is the window itself, a hit lies in
   `[start, start+6h]`, which proves the warehouse reaches the window start independent of upload timing; a
   heartbeat elsewhere in the window (or older than it) cannot satisfy it. Else `retention-shorter-than-window`.
   The 6 h slack is a constant (probes run under `env -i`, so a knob would never be set), commented with why.
9. **PASS** prints counts only (no row excerpts: the sweeper posts stdout to a public issue) as ONE verdict line
   first, then the D5 caveats as a fixed suffix block.

### Decisions

- **D1 - selector.** The denominator is the PATCH upload row above, not a string search. PUT is rejected
  as denominator (monolithic uploads never traverse the PATCH handler under test).
- **D2 - MIN_SAMPLES stays 12, window stays 7d, and the floor is restated honestly as a ROW count.** Data:
  44 PATCH rows / 7d (per-day 14, 3, 0, 2, 1, 7, 17; 18 pushes of 1-6 rows). 12 rows is 27% of the observed
  week, so it trips only on a real near-silent week and not on ordinary variance (a single quiet day is 0). The
  floor's job is the ADR-197 "the source actually emits" assertion, i.e. anti-vacuity; it is NOT a push count
  (12 rows can be 2 pushes) and NOT statistical power: at ~1-in-13 per release, 18 pushes leave
  (12/13)^18 ~ 24% chance an unfixed pipeline also looks clean, and ~37 pushes would be needed for 5%, about
  two weeks of traffic. Raising the floor cannot buy power the traffic does not have; lowering it is
  unjustified. The honest remedy is wording: the PASS text says the absence half is a tripwire and DELIVERY
  is the causal evidence. The PATCH count is also a lower bound (survivors of the 17-rows-per-tick ordinary
  cap). A distinct-days floor was considered and left to the operator (see `decision-challenges.md`).
- **D3 - shipper drops: disclosed AND guarded.** `dropped_cum=1215` vs `shipped_cum=178` overstates the risk
  to exempt-lane evidence (all measured drops are `rate_cap`) and understates it for the error line (not
  exempt). So: n2 carries the absence claim, the exempt-lane drop guard protects n2's loss mode, and the PASS
  text discloses that n1 is best-effort.
- **D4 - the retention guard is replaced, not patched.** Its span-of-rows measure cannot be satisfied
  (defect 2); the anchor asks the real question with a bounded read that cannot truncate, over a dense
  heartbeat series (5-minute cadence) instead of sparse upload rows.
- **D5 - PASS text caveats (all required):** (a) scope: deadline sub-mode only, `unexpected EOF` out of scope
  (kept); (b) the error line is not cap-exempt, so absence rests on n2 (5xx at deadline-shaped latency on any
  upload method) guarded by drop accounting; a cut that logs a different status or a latency far from the
  deadline would not be seen; (c) `patch_rows` is a lower bound and a clean week over ~N pushes is a tripwire,
  DELIVERY is the causal evidence.
- **D6 - explicit non-goals (no silent scope creep):** do not edit `cloud-init-registry.yml` (host replace),
  `scripts/followthroughs/zot-log-channel-7440.sh` (its `n_patch` counts `message:PatchBlobUpload`, which can
  never match the real message shape; informational there), `scripts/betterstack-query.sh`, the runbook, or any
  other probe. The shipper gap, the runbook correction and the 7440 counter go in one follow-up issue.
- **D7 - unexpected-crash exit code is unchanged and documented.** A `set -u` abort exits 1, which the sweeper
  reads as FAIL (and reopens a closed tracker). That is pre-existing; fixing it needs an EXIT-trap exit remap
  that cannot be driven red without a test-only seam, so it is recorded in the header comment and Sharp Edges
  rather than added untested.
- **Expected consequence for the operator (state in the PR body, do not hide):** on today's measured data the
  next scheduled sweep returns PASS (delivery verified; 44 PATCH rows; no deadline-shaped 5xx, one EOF-shaped
  500; drop reasons all `rate_cap`; anchor present) and auto-closes #7556 / lets ADR-190 flip to `accepted`.
  That is the contract working, but it is a closure on a tripwire-grade absence claim. Holding options for the
  operator, in the PR body: leave the PR in draft, or push the tracker directive's `earliest=` date out (the
  sweeper gates on it) before merging. `Ref #7556`, never `Closes`.

## Technical Considerations

- **Bash style.** `set -uo pipefail` (no `-e`), `${VAR:?}` banned (`scripts/lint-followthrough-varq-ban.sh`),
  every unestablished state `verdict "TRANSIENT reason=..." ; exit 2`. New env knobs follow the file's
  `ZOT_CEILING_*` pattern; only knobs a test needs are added (`ZOT_CEILING_QUERY` already exists).
  Temp files are registered on the existing EXIT trap (extend the list; do not replace an earlier trap).
- **No folding to zero.** The classifier's output and every `fetch` result are validated by shape; never
  `|| true` or `${x:-0}` a value that decides a verdict. Count with the python helper or `grep -c`, never
  with a negated `! grep -q`.
- **Decode.** Reuse the existing `decode()` (`.raw` then `.message`, both `fromjson?`). It is a deliberate
  copy of the 7440 probe's decoder; this PR does not add a third caller, so the `scripts/lib/` extraction
  stays deferred (note the trigger in the header: the third caller).
- **Go duration to seconds** lives in the python helper; accepted units `h`, `m`, `s`, `ms`, `us`/`µs`, `ns`;
  anything else is `unparse`. Only whether latency is >= 95% of the deadline matters.
- **Date arithmetic** for `--until` via python3 (already a hard prerequisite), not GNU `date -d`, so the probe
  stays portable to the sweeper's runner and to developer macOS.
- **Query count** rises from 2 to 4 per sweep (config, uploads, dropped, anchor). The sweeper has no per-probe
  timeout (`grep timeout scripts/sweep-followthroughs.sh` -> none).
- **Public output.** stdout is posted to a public issue: print counts, reasons, and enum values only.
- **Local runs.** A read-only local run against the live warehouse prints a verdict and posts nothing; closure
  is performed solely by `scheduled-followthrough-sweeper.yml`. Run it at most once for the AC below and do not
  paste row text from it.
- **Maintenance posture.** The harness encodes the real `betterstack-query.sh` contract in its stub (newest-N
  truncation, OR-combined LIKE over double-encoded `raw`, `--until` as `dt <=`); if that tool changes, the stub
  must change with it, and the header says so.

## Implementation Phases

**Phase 1 - RED tests first (`cq-write-failing-tests-before`).** Create
`scripts/followthroughs/zot-upload-ceiling-7556.test.sh` and run it against the UNCHANGED probe. Required
RED set before any probe edit: the regression case (44 PATCH rows + heartbeat echoes -> PASS), the
heartbeat-must-not-count cases, header/path forgery, truncation, exempt-lane drops, coverage anchor, n2
latency classification, FAIL-before-floor, webhook-row-quoting-"syntax error". Record the red count in the PR body.

**Phase 2 - probe.** Edit the probe in the order of steps 3-9 above, updating the header comment (exit
contract text, "WHAT THIS PROBE MUST NOT DO", replacing the stale retention comment with the anchor
rationale including the measured arithmetic of why the span guard was unsatisfiable, and the D7 note). Remove
the old span python block and the old `is_error_payload` rather than leaving them dead.

**Phase 3 - registration and local gates.** Add `run_suite "scripts/zot-upload-ceiling-7556" bash
scripts/followthroughs/zot-upload-ceiling-7556.test.sh` to `scripts/test-all.sh` beside the other
`zot-*` followthrough suites with the orphan-class comment (consumer: `scripts/lint-orphan-test-suites.sh`
and the CI scripts job that runs `test-all.sh`). Do NOT hand-edit `scripts/suite-shard-legs.tsv`: it is
generated by `regenerate-shard-manifest.py`, and an untabled label takes the documented hash fallback. This
branch's base carries a recent shard-parity fix (`abd29f4bcf`), so verify with the runner's own enumerate mode
rather than assuming (AC17).

**Phase 4 - mutation battery (self-run, results into the PR body).** Run the Guard Contract matrices
below against the finished probe; every row must turn the harness RED. Scripted batch run, targeted only.

**Phase 5 - follow-up issue and PR body.** File the deferral issue; PR body carries `Ref #7556`, the
expected-PASS-and-auto-close consequence with the holding options, the D2 power statement, and the
red-then-green evidence.

## Files to Edit

- `scripts/followthroughs/zot-upload-ceiling-7556.sh` - the probe (steps 3-9, header comment).
- `scripts/test-all.sh` - one `run_suite` line for the new harness (explicit registration: `scripts/followthroughs/*.test.sh` is not in `SUITE_GLOBS`).

## Files to Create

- `scripts/followthroughs/zot-upload-ceiling-7556.test.sh` - fixture-driven exit-code harness.

## Open Code-Review Overlap

Two open `code-review` issues touch `scripts/test-all.sh`; none touch the probe, the 7440 probe,
`betterstack-query.sh` or `cloud-init-registry.yml`.

- **#8659** (33 suites replace test-helpers' composed EXIT trap and leak the incident sandbox on direct
  runs): **Acknowledge.** The new harness does not source `test-helpers`; it owns one `mktemp -d` and one
  EXIT trap, so it neither adds to nor fixes that class. Rationale: different concern, own cycle.
- **#7942** (two `*.mutation.sh` batteries in `plugins/soleur/test/` run in no gate): **Acknowledge.**
  Unrelated files; this plan's mutation battery is self-run in Phase 4 and its results are recorded, not
  wired as a new gate.

## User-Brand Impact

- **If this lands broken, the user experiences:** a false PASS auto-closes P1 #7556 and flips ADR-190 to
  `accepted` while a zot upload deadline still cuts image pushes, so a release stalls at the mirror step
  with no open tracker to explain it; a false FAIL/TRANSIENT only keeps a noisy daily comment going.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no user data is read; the probe
  reads internal registry logs (internal IPs, repo names, service usernames) and its stdout is posted to a
  public issue, so any row excerpt in output would leak infrastructure topology. Mitigation: counts and enum
  values only (AC12).
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the touched files are a CI follow-through probe and its test harness; no end-user data path, auth surface or customer-visible behaviour changes.`

## Observability

The deliverable is itself an observability instrument (a daily follow-through probe), so this section
declares how the probe's own health is observed. No field is a placeholder; the discoverability command runs
with no credentials and no ssh.

```yaml
liveness_signal:
  what: the sweeper's daily verdict comment on tracker #7556 (one `zot-upload-ceiling[#7556]: <PASS|FAIL|TRANSIENT> reason=...` line per run)
  cadence: daily, per scheduled-followthrough-sweeper run
  alert_target: GitHub issue #7556 comment thread (FAIL leaves it open and comments; PASS closes it)
  configured_in: .github/workflows/scheduled-followthrough-sweeper.yml and the tracker's soleur:followthrough directive (earliest=2026-08-21)

error_reporting:
  destination: the verdict line and its reason= token in the sweeper comment; the Better Stack ClickHouse read path via scripts/betterstack-query.sh
  fail_loud: exit 2 with a distinct reason= for every unestablished state, exit 1 on a deadline finding; never exit 0 without all conditions in AC10

failure_modes:
  - mode: a read fails, returns a ClickHouse error payload, or returns a full page
    detection: reasons query-failed-NAME, query-error-payload-NAME, query-truncated-NAME on the verdict line
    alert_route: tracker #7556 daily comment
  - mode: the selector drifts (zot field order or message shape changes) and uploads stop matching
    detection: too-few-samples carries upload_rows_any= so rows-present-but-unmatched is readable from the line
    alert_route: tracker #7556 daily comment
  - mode: shipper drops exempt-lane or pre-ship rows in the window
    detection: reason exempt-lane-dropped with the reasons=<r:n> list
    alert_route: tracker #7556 daily comment
  - mode: warehouse retention does not reach the window start
    detection: reason retention-shorter-than-window
    alert_route: tracker #7556 daily comment

logs:
  where: Better Stack Logs source 2457081 (SOLEUR_ZOT_LOG, SOLEUR_ZOT_LOG_DROPPED, SOLEUR_ZOT_DISK), read via scripts/betterstack-query.sh
  retention: at least the 7-day window (asserted by the coverage anchor on every run)

discoverability_test:
  command: bash scripts/followthroughs/zot-upload-ceiling-7556.sh
  expected_output: TRANSIENT
```

The command was run without credentials (`env -i`, no Doppler): it exits 2 within a second and prints
`zot-upload-ceiling[#7556]: TRANSIENT reason=query-failed-config query_rc=3`, so an operator (or preflight
Check 10's sandbox) can confirm the probe is runnable and emits a verdict without SSH or secrets. It does not
read production state; the production readback is the sweeper's daily comment. No `credentials_required` is
declared on purpose (declaring one would move the `BASELINE_DECLARED_PROBES` ratchet in
`plugins/soleur/test/preflight-discoverability-test.test.ts`, out of this PR's scope).

## Guard Contract

### Guard 1 - the sample floor counts only genuine PATCH upload rows from SOLEUR_ZOT_LOG

**Property.** A row contributes to `patch_rows` (and to the n1/n2 numerators) only if it is a SOLEUR_ZOT_LOG
envelope whose server-controlled fields say `method:PATCH` (n2: any method) on `/v2/<repo>/blobs/uploads/`, and
no other emitter's text, and no helper failure, can add to or erase from those counts.

**Assembly.** The row sets that can reach the count: (a) the decoded uploads-read output, which mixes
SOLEUR_ZOT_LOG rows, SOLEUR_ZOT_DISK heartbeats (via the `PatchBlobUpload` echo), GitHub-webhook rows (the shared
source carries `caller:api` receipts quoting issue bodies) and any other host's rows; (b) within a pinned row,
the client-controlled regions (the `headers:{...}` block and the `path:` value); (c) the classifier's output
channel back into the shell. The single chokepoint is the python3 classifier: prefix pin, head cut, anchored
regex, applied once to every row and consumed by `patch`, `n1`, `n2`, `other5xx` and `upload_any` alike; there
is no second code path that counts rows from the unpinned decode, and the shell accepts only its fixed-shape
output line. Quantified over every emitter and every client-controlled field of a pinned row, not over the
shapes seen today.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert the denominator to `grep -c PatchBlobUpload` over the unpinned decode | RED (regression case and heartbeat-echo cases) |
| 2 | Drop the offset-0 envelope pin so a webhook-shaped row quoting a PATCH line counts | RED (webhook-quote case) |
| 3 | Add a SECOND forged member after a compliant first: a `GET` row whose `User-Agent` contains a full `,method:PATCH,path:/v2/x/blobs/uploads/y,statusCode:202,latency:1s,` AND a `GET` whose `path` contains the same text, both alongside 11 genuine rows | RED (count must stay 11, so TRANSIENT, not 13) |
| 4 | Count n1 from the unpinned decode so a heartbeat `zot_last_err` carrying `i/o timeout` fails the probe | RED (echo-with-timeout case) |
| 5 | Own dispatch: make the classifier step report `patch=0` while the probe exits 0, or print the PASS line without calling it | RED (PASS case asserts `patch_rows=44` on stdout, and every case asserts a branch marker) |
| 6 | Make the classifier exit nonzero or print an unrecognised line, with the or-true idiom restored around it | RED (must exit 2 `classifier-failed`, never 0) |
| 7 | Move the FAIL decision after the floor so a timeout with 3 PATCH rows reads TRANSIENT | RED (FAIL-before-floor case) |
| 8 | Evaluate `unparse` before FAIL so one unparseable 5xx hides a genuine 30m cut | RED (mixed case must exit 1) |

**Harness rows.** (H1) Neuter the suite's `fail()` to a no-op: the direct conservation check
(`passes + fails == cases`) must exit 1. (H2) Replace the stub query with one that returns nothing for every
call: the suite's own non-vacuity floor (derived case count) must exit 1 and the PASS case must go red. Must-PASS
inputs that are NOT the canonical: a PATCH row with a different repo path depth and `username` value; a PATCH
row at `latency:0s`; exactly 12 rows at the floor; a 5xx at `5m55s`.

**Anchor.** The stored values are `MIN_SAMPLES=12`, the 95% deadline fraction and the shipper prefix literal.
All live in the probe next to the code that uses them and in the harness as literals; a single diff can edit
both, so the guard proves consistency, not integrity. What must also move for a weakening to pass: the
exact-floor boundary cases (11 -> TRANSIENT, 12 -> PASS) and the latency table (`28m29s` not a cut, `28m31s`
a cut) are asserted against literals in the harness, and the decision record for the number is D2 in this plan
plus the PR body; changing the floor therefore needs a reviewed change to both files and the stated rationale.

### Guard 2 - an absence claim is only graded over a covered, untruncated, undropped window

**Property.** The probe exits 0 only if the warehouse demonstrably reaches the window start, no paged read was
truncated, and no non-`rate_cap` shipper drop occurred in the window.

**Assembly.** Four reads feed the verdict (config, uploads, dropped, anchor), all through the single `fetch`
chokepoint, which checks exit code, structural error payload and (for the two paged reads) truncation before
any row is used; the guard is quantified over all four reads, not over the one that motivated each check. The
drop-reason decision quantifies over every reason value the shipper can emit (`rate_cap`, `exempt_cap`,
`redact_failed`, `sanitized_empty`, `cursor_invalidated`) and any future one: benign is an allow-list of one.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore the old span-of-rows guard (`span >= MIN_WINDOW_DAYS*24`) | RED (a 155h-span PASS fixture with a valid anchor goes TRANSIENT) |
| 2 | Delete the truncation check on the uploads read | RED (exactly-5000-row fixture) |
| 3 | Second member: add a `reason=exempt_cap` DROPPED row after nine compliant `rate_cap` rows, and separately a never-seen `reason=new_cause` | RED for both (allow-list, not deny-list) |
| 4 | Own dispatch: make the anchor read a no-op returning rows regardless of `--until` | RED (stub asserts `--since $WINDOW`, `--until` after the window start by exactly the slack, and `--grep SOLEUR_ZOT_DISK`) |
| 5 | Accept an anchor row that lacks the `SOLEUR_ZOT_DISK` (plus a trailing space) prefix (a webhook row quoting it) | RED (contaminated-anchor case) |
| 6 | Treat the dropped-read error payload as zero rows, or drop `fetch`'s structural check for a text grep | RED (`query-error-payload-dropped` case; a webhook row quoting "syntax error" must still be graded) |
| 7 | Widen the anchor read back to `--since 8d` | RED (a heartbeat only at 7.5 d ago, nothing in `[start, start+6h]`, must give `retention-shorter-than-window`) |
| 8 | Delete the dropped-read truncation check, or its nonzero-exit arm, or the anchor's nonzero-exit arm | RED (one case each: 20000 rows, rc!=0 on dropped, rc!=0 on anchor) |

**Harness rows.** (H1) Make the stub ignore argv (return the same rows for every grep): the suite's argv
assertions must go red. (H2) Remove the `--limit` assertion in the stub: the truncation-boundary cases (4999 vs
5000 on uploads, 19999 vs 20000 on dropped) must still discriminate. Must-PASS non-canonical inputs: 4999 raw
rows (below the page limit); a DROPPED set containing only `rate_cap` with varying numeric `n`; an anchor row at
exactly `window start + 6h`.

**Anchor.** The stored values are the slack constant (6 h), the page limits (5000 / 20000) and the
benign-reason allow-list. Moving any of them in the probe alone leaves the harness literals (4999/5000
boundary, the `reason=` table, the anchor-at-slack case) red, and the live measurement that justifies them
(1913 rows, all `rate_cap`; anchor rows present at window start) is recorded in this plan's Research Insights,
not in the diff.

## Acceptance Criteria

- [ ] AC1: Phase 1 RED evidence recorded (harness run against the unchanged probe: the named cases fail; count in PR body).
- [ ] AC2: `bash scripts/followthroughs/zot-upload-ceiling-7556.test.sh` exits 0 against the edited probe; its output ends with a derived-floor line and the conservation line.
- [ ] AC3: The real-shape regression case passes: 44 synthesized PATCH rows plus two synthesized SOLEUR_ZOT_DISK heartbeat echoes of a `PatchBlobUpload` EOF error -> exit 0 with `patch_rows=44`; the heartbeats-only case -> exit 2 `reason=too-few-samples patch_rows=0`.
- [ ] AC4: A heartbeat echo carrying `i/o timeout` does not FAIL; a SOLEUR_ZOT_LOG `level:error` `PatchBlobUpload` `i/o timeout` row does (exit 1); the same text in a non-SOLEUR_ZOT_LOG row does not.
- [ ] AC5: n2 table passes: a 5xx at `30m0s`, `28m31s` or `1h0m0s` -> exit 1 (also for a PUT row); a 5xx at `5m55s`, `3m31s` or `28m29s` -> exit 0 with `other5xx` printed and the EOF scope text; a 5xx whose latency is unparseable -> exit 2 `latency-unparseable`; unparseable beside a genuine cut -> exit 1; a timeout finding with only 3 PATCH rows -> exit 1 (FAIL precedes the floor); a finding on a full (truncated) page -> exit 1.
- [ ] AC6: Floor boundary: 11 PATCH rows -> exit 2 `too-few-samples`; 12 -> exit 0.
- [ ] AC7: Truncation: 5000 raw rows on the uploads read with no finding -> exit 2 `query-truncated-log`; 4999 -> graded; same pair for the dropped read at 20000/19999.
- [ ] AC8: Drop guard: only `rate_cap` -> graded; any `exempt_cap`, `redact_failed`, `sanitized_empty`, `cursor_invalidated` or unknown reason -> exit 2 `exempt-lane-dropped`; a webhook row quoting `reason=exempt_cap` is ignored.
- [ ] AC9: Coverage: PATCH rows spanning only ~155h plus a valid anchor in `[start, start+6h]` -> exit 0; no anchor row, an anchor row without the heartbeat prefix, or a heartbeat only outside `[start, start+6h]` -> exit 2 `retention-shorter-than-window`; the stub asserts the anchor read's `--since`/`--until`/`--grep` argv.
- [ ] AC10: Every unestablished state exits 2 with a DISTINCT `reason=` (table in Test Scenarios); no code path reaches exit 0 without all of: delivery match, uploads read ok and untruncated, classifier output valid, floor met, n1=n2=0, unparse=0, dropped read ok/untruncated/benign, anchor present.
- [ ] AC11: Phase 4 mutation battery: every matrix row (Guard 1: 8, Guard 2: 8, plus the H rows) turns the harness RED; results recorded in the PR body as a table.
- [ ] AC12: Probe stdout contains no row excerpts: a harness case with a sentinel string inside a fixture row asserts the sentinel never appears in stdout/stderr of any verdict path.
- [ ] AC13: `bash scripts/lint-orphan-test-suites.sh`, `bash scripts/lint-followthrough-varq-ban.sh` and `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-01-fix-zot-upload-ceiling-probe-selector-plan.md` exit 0; `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` (the gate's own invocation, not a hand-listed path set) exits 0; `shellcheck` on the probe and harness reports nothing new.
- [ ] AC14: `git diff --name-only origin/main...HEAD` (three-dot, merge-base) is a subset of: the probe, the new harness, `scripts/test-all.sh`, files under `knowledge-base/project/{plans,specs}/` (plan, `tasks.md`, `session-state.md`, `decision-challenges.md`), and any pipeline-generated knowledge-base index file the pipeline rewrites; no other probe, no `cloud-init-registry.yml`, no `betterstack-query.sh`, no runbook, no tracker edit.
- [ ] AC15: PR body: `Ref #7556` (no `Closes`/`Fixes`/`Resolves`); states the expected next-sweep PASS and auto-close with the holding options, the D2 power statement, the four defects, and the follow-up issue number.
- [ ] AC16: One read-only local run of the edited probe against the live warehouse (credentials via `doppler run -p soleur -c prd_terraform`) printed its verdict; it posted nothing. Recorded as the verdict line only.
- [ ] AC17: Shard registration: for each leg `i` in 1..7, `SCRIPTS_SHARD=i/7 bash scripts/test-all.sh --enumerate scripts` is non-empty, and the new label appears in exactly one leg (enumerate only; no suite is run).

## Test Scenarios

Harness shape: mirror `scripts/followthroughs/zot-fill-rate-7341.test.sh` (`ZOT_CEILING_QUERY` stub, `cases`
counted at the call site and never inside `pass()/fail()`, floor and conservation reported with
`printf >&2` + `exit 1` per ADR-193, no increments inside `$( )`). The stub dispatches on `--grep` and
asserts its own argv before answering. It replays the REAL tool's contract, not the probe author's reading of
it (a fake written by the consumer's author hides the bug between the two): `betterstack-query.sh` returns rows
sorted `dt` ASC but keeps the NEWEST `--limit` rows when more match, treats `--grep` as OR-combined
`raw LIKE '%x%'` over the DOUBLE-ENCODED `raw` (so a grep containing a quote or a colon-joined field name matches
nothing; the probe's greps are quote-free), honours `--until` as `dt <= value`, and exits 3 on missing
credentials. Rows are production-shaped: `{"dt":..,"raw":<JSON string of {"message":..}>}`, i.e.
double-encoded, with fabricated values (documentation IPs, `00000000-...` uuids, `example-org/example-image`)
per `cq-test-fixtures-synthesized-only`. Time is real UTC now minus offsets (never `datetime.now()` local), as
the 7341 harness learned.

| Fixture knob | Meaning |
|---|---|
| `CFG` | boot config row (default: both deadlines `1800000000000`); variants: absent, one mismatched, unparseable |
| `PATCHES` | `n:status:latency` segments of synthesized PATCH upload rows (PUT/POST variants for n2) |
| `PUTS` / `POSTS` | other methods on `/blobs/uploads` (must never count toward the sample) |
| `ECHO` | SOLEUR_ZOT_DISK heartbeat echoing a `zot_last_err` (EOF or `i/o timeout`) |
| `ERRROW` | SOLEUR_ZOT_LOG `level:error` PatchBlobUpload row (`i/o timeout` or EOF) |
| `FORGE` | webhook-shaped quote (including one containing "syntax error"), header-forged GET, path-forged GET, other-host row |
| `DROPS` | `reason:count` segments (+ `n=unknown`, webhook quote of a reason) |
| `ANCHOR` | present in `[start, start+6h]` / absent / contaminated / at-slack-boundary / only outside the slack |
| `RAWN` | pad the raw row count to hit 4999 / 5000 (uploads) and 19999 / 20000 (dropped) |
| `*_RC`, `*_ERR` | per-query nonzero exit and ClickHouse-error payload on a zero exit |
| `CLASSIFIER_FAIL` | run with a failing `python3` shim ahead of the real one for the classifier call only |

Distinct-`reason=` table the harness must pin (each its own case; exit 2 unless noted):
`query-not-executable`, `no-python3` (skip if untestable, say so), `window-too-short`, `query-failed-config`,
`query-error-payload-config`, `no-config-line`, `deadlines-unparseable`, `deadline-mismatch` (exit 1),
`query-failed-log`, `query-error-payload-log`, `classifier-failed`, `deadline-submode-present` (exit 1, via n1
and via n2), `latency-unparseable`, `query-truncated-log`, `too-few-samples`, `query-failed-dropped`,
`query-error-payload-dropped`, `query-truncated-dropped`, `exempt-lane-dropped`, `query-failed-anchor`,
`query-error-payload-anchor`, `retention-shorter-than-window`. The old `span-underivable` reason is deleted with
the span guard; assert it is gone so a stale reference cannot linger.

Regression scenarios for the bug this fixes: (1) the exact current live state, synthesized (44 PATCH 202 rows,
one `500 5m55s`, 47 PUT, 12 POST, two heartbeat echoes of an EOF `zot_last_err`, rate_cap-only drops, anchor
present) -> exit 0 `patch_rows=44`; (2) the same input run against the OLD selector must have produced
`too-few-samples patch_rows=2` (the Phase 1 RED case documents it).

Verification commands (targeted only, per operator preference; the full battery is CI's job):

- `bash scripts/followthroughs/zot-upload-ceiling-7556.test.sh`
- `bash scripts/lint-orphan-test-suites.sh && bash scripts/lint-followthrough-varq-ban.sh`
- `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-01-fix-zot-upload-ceiling-probe-selector-plan.md`
- `SCRIPTS_SHARD=1/7 bash scripts/test-all.sh --enumerate scripts` (and legs 2-7)

## Deferrals

One follow-up issue, filed in Phase 5 (milestone from `knowledge-base/product/roadmap.md`, label
`deferred-scope-out`; re-evaluate when the next registry-host replace is scheduled, since the shipper change
rides it): **the zot log shipper's `is_cap_exempt` does not exempt the real `PatchBlobUpload` error line.**
Contents: the evidence (error at 2026-09-28T17:25:31Z present in the heartbeat's `zot_last_err`, paired `HTTP
API` 500 row present, no SOLEUR_ZOT_LOG error row), the proposed fix (classify on the parsed `func` field, not
the `message` prefix), the runbook correction now possible without a host replace (`betterstack-log-query.md`
four-evidence-classes table claims `PatchBlobUpload` rows are exempt), and the `zot-log-channel-7440.sh`
`n_patch` counter that cannot match (fix or delete). Blocker note: the shipper fix needs a registry-host
replace (ADR-096), not part of this PR.

Not deferred and not an issue: scoping the absence window to the newest boot (cut: starves the floor; see Cut
List), a statistical-power floor (cut: unreachable at current traffic; see D2), and an N3 signal from the
heartbeat's `zot_last_err` timestamp (recorded in `decision-challenges.md` for the operator).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected - infrastructure/tooling change confined to a CI follow-through probe and
its test harness (no UI surface, no regulated-data surface: the probe reads internal registry telemetry and
prints counts; no new infrastructure, store, connection, ADR-level decision or C4 element: the registry host,
shipper and warehouse topology are unchanged).

## Plan Review Disposition

Four reviewers (DHH, Kieran, code-simplicity per-mechanism, CTO devex). Applied as mechanical: one `fetch`
helper replacing per-query arm triplets; one python3 classifier with a validated fixed-shape output (replaces
the grep chain and the regex pre-compile check); structural `fetch` error-payload check; anchor read scoped to
`--since $WINDOW --until start+6h` (the 8d lookback let a heartbeat elsewhere satisfy it); FAIL before the
truncation, unparseable and floor arms; legacy-60 s signature cut; `ZOT_CEILING_COVERAGE_SLACK_H` knob cut;
anchor host-pin cut; simplified PATCH regex; n2 made method-agnostic and `statusCode` evidence cited to ADR-190;
dropped-read limit raised to 20000 with the wedge trade-off written down; D2 reworded so the floor is a row
count, not a push count; extra matrix rows (dropped truncation, nonzero exits, FAIL-before-floor,
classifier-failed, anchor hole, unparse-vs-FAIL); `--enumerate` shard check added. Not applied (operator or
taste decisions, appended to `knowledge-base/project/specs/feat-one-shot-7556-zot-ceiling-probe-selector/decision-challenges.md`):
heartbeat-echo N3 signal, distinct-days floor, a bounded-age drop guard, decoupling tracker closure from the
ADR flip, a docs-only runbook correction inside this PR, and keeping `unparse` as TRANSIENT (the CTO would fold
it into `other5xx`; folding it can hide a real cut, so the safe direction was kept).

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty or placeholder fails `deepen-plan` Phase 4.6; this one is filled
  (threshold `none` with the scope-out line).
- The probe's exit 0 auto-closes #7556 through the sweeper only; never run a "PASS path" step in CI or a
  workflow from this PR, and never paste a row from a local run (public-repo comment hazard).
- `betterstack-query.sh` keeps the NEWEST `LIMIT` rows. Any future reader who treats a full page as "all rows
  since `--since`" repeats the silent-short-window bug (#6288 class); the truncation arm exists to make that
  impossible here.
- The ordinary shipper cap is per 5-minute tick, so `patch_rows` is a lower bound that varies with burstiness
  (a push burst loses rows to `rate_cap`). Do not tune `MIN_SAMPLES` upward against a single week's count.
- A bash crash (for example a `set -u` abort) exits 1, which the sweeper reads as FAIL and reopens a closed
  tracker; pre-existing, documented in the probe header (D7), not changed here.
- Observability and IaC gates were evaluated and do not fire: no file under `apps/*/server|src|infra` or
  `plugins/*/scripts`, and no new infrastructure; the deliverable itself is the observability instrument.


## Addendum — 2026-10-01 (#9353): review-round amendments

Appended, not edited in place: the sections above record the plan as approved. Ten review seats (history,
pattern, architecture, security, performance, data-integrity, agent-native, code-quality, test-design,
structural enumeration) ran against SHA `6ff11a8165`. Their findings reduced to two structural causes, both fixed in
commit `4bb492e35f`:

1. **A decoded line is not necessarily one row from one emitter.** Fixed by one python decoder emitting exactly
   one sanitized line per row (line breaks neutralised), a DELIVERY read pinned to the registry envelope and the
   `message:configuration settings,params:{` shape, a count-once rule on `clientIP`/`method`/`statusCode`/`latency`
   (a repeated or unmatched upload row is TRANSIENT, never counted), exact-duplicate rows counted once, the floor
   counting PATCH **2xx** rows only, and decode accounting on the drop read (whose empty answer reads as clean).
2. **The window was not tied to the boot that carries the deadlines, and the trailing edge was unobserved.** Fixed by
   requiring every `configuration settings` start inside the window to carry the deadlines
   (`window-spans-pre-delivery-start` otherwise), a 30-day config lookback, a host-pinned heartbeat at the window
   start, and a heartbeat in the last 12 h (`heartbeat-stale`).

Changes to the contract above: reason `latency-unparseable` is now `upload-rows-unparseable` (it also covers
forged/unmatched rows); `span-arithmetic-failed` is now `anchor-bound-failed`; new reasons `window-spans-pre-delivery-start`,
`heartbeat-stale`, `dropped-undecodable`, `decoder-failed`; the `µs` unit is dropped (the shipper strips non-ASCII);
`jq` is no longer a dependency; the query tool's stderr is never printed. The live defect case now reads
`patch_rows=43` (44 PATCH rows, one of them the 500). Measured on the hardened probe against the live warehouse
(read-only): `config_starts=8` all at 1800 s, `patch_rows=37`, `long_ok=8` (uploads that outlived the old 60 s ceiling).

Verification: harness 135 cases; mutation battery 39/39 killed against a green control (one survivor, a fixture gap on
the row-shape check, closed by a User-Agent-forged config fixture and re-driven).

Not applied (recorded in `decision-challenges.md`): requiring `long_ok >= 1`; grading a 2xx at deadline latency
(ADR-190 Arm C; delivery parity is its guard); reading the heartbeat's `log_shipper_post_fail`; sharing the structural
validator and decoder through `scripts/lib/` (tracked with the shipper follow-up).

AC amendments from the review round (the ACs above are historical): **AC3** now reads `patch_rows=43` (the floor counts PATCH
2xx rows; the 500 row is not a sample). **AC14**'s file set also includes, by review disposition: a comment refresh in
`plugins/soleur/test/preflight-discoverability-test.test.ts`, the runbook row in
`knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`, and the event-grep probe
`scripts/followthroughs/zot-shipper-exempt-func-9353.sh` for the filed shipper follow-up. **AC10**'s PASS conjuncts gained
"every in-window zot start carries the deadlines" and "heartbeats at both ends of the window".
