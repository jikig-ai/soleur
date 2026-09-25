---
title: "fix(inngest-health): select dedicated-host probe rows by emitter plus a start-of-message anchor, in every consumer"
type: fix
date: 2026-09-25
slug: fix-inngest-probe-row-emitter-selection
branch: feat-one-shot-8846-inngest-probe-row-emitter
issue: 8846
closes: 8846
priority: p1
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

# fix(inngest-health): select dedicated-host probe rows by emitter, not by substring

## Enhancement Summary

**Deepened on:** 2026-09-25
**Agents used:**

- plan-review panel: DHH, Kieran and code-simplicity reviewers, plus the CTO on a devex lens;
- deepen pass: observability-coverage-reviewer, test-design-reviewer, and a verify-the-negative sweep;
- the Step 4.5 scoped advisor consult, on both the primary and fallback tiers.

### Key improvements

1. **Assertion floors.** Three exact floors would have gone red on every suite touched:
   - classify `EXPECTED_ASSERTIONS=104`
   - dark-gate `_FLOOR=282`
   - cutover `_EXACT_FLOOR=914`

   Four `-lt` floors would have gone stale. All seven are now updated in the Phase 1 commit.
2. **Fixture expectations corrected against the real suites:**
   - host-state now asserts `SERVING=yes` becoming `SERVING=no`, not `VERDICT SERVING`.
   - 8296 now expects `5 rollback_inversion` becoming `2 agree`.
   - 7761 now asserts that `boundary DERIVED` is absent, with competing reasons.
   - The execute-gate row gets its own `$EROWS`/`$HB` pair, with a dt that does not tie.
   - Two dark-gate rows built outside `bs_line` gain the emitter field.
3. **Selector-failure routing reaches a human.**
   - The watchdog writes `crash_reason` into the existing consumer-broken issue.
   - The no-live-scheduler step stops calling an unmeasured host "not serving".
   - The dark-gate lib refuses `unreadable` **before** G18. Otherwise a missing lib in the apply workflow would read as `followthrough_7674`, because that workflow sends the 7674 script's own stderr to /dev/null.
4. **`JQ_RC=0` before use.** Without it, `set -u` would crash the healthy path and start a new issue loop. A must-PASS row pins it.
5. **Guard precision.**
   - The emitter-parity reader binds to the `LOG_TAG=` nearest the logger line. The file has two `LOG_TAG`s.
   - The census takes an injectable file list, so the mutation rows never touch the git index.
   - A per-reader count covers the one file with two raw reads.
   - The Guard 2 caller rule now uses the real argument positions.

### New considerations discovered

- **6894 is retired.** Its header says "Nothing runs this file now". It gets the predicate but no harness.
- **Merging fires the web-platform push apply.** The edited suites live under `apps/web-platform/infra/**`. This is routine, and #8759 did the same. It is covered by AC13.
- **The class of bug has recurred three times.** The class-wide guard is filed as **#8875**. The `.tf` alert is deferred as **#8874**.

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

The dedicated-host watchdog decides whether the inngest host is healthy by reading "probe rows" (log lines the host writes about itself) from Better Stack. It keeps any row from the dedicated host that contains the probe marker as a substring. The inngest server also writes its own event log to the same place, under the journald identifier `doppler`. That event log quotes the marker whenever a GitHub issue, PR or comment about the probe is opened, labeled, edited, commented on or closed.

An event-log row can therefore be the newest row in the window. It has none of the probe fields, so a healthy host is graded `probe-unavailable`.

The loop feeds itself. The watchdog closes the issues when the host is healthy, and closing them fires webhooks that land in the event log. The next check reads one of those as its newest row. It has filed a new pair of P1 issues every hour:

- #8823 and #8824
- #8829 and #8830
- #8833 and #8834
- #8850 and #8851
- #8862 and #8863 (open when planning began; by the deepen pass the loop had closed them itself, ready to file the next pair)

The fix: every consumer selects probe rows by the program that wrote them (the emitter, `SYSLOG_IDENTIFIER == "inngest-server-probe"`) and requires the marker at the start of the message. The rule is defined once, in a sourced library, `scripts/lib/inngest-probe-row.sh`. Each consumer's suite gets a fixture that goes red on today's code. The same blind spot exists in the liveness counters in `scripts/cutover-inngest.sh`, where it fails open, so those counters now filter by emitter too.

## Research Reconciliation — Issue vs. Codebase

| Issue claim | Reality (measured 2026-09-25) | Plan response |
|---|---|---|
| `apply-web-platform-infra.yml` is a consumer to fix | It has **no inline row selection**. Guard 2 runs `--grep <marker> --limit 500` into `$ROWS`, hands the file to `inngest_host_dark_gate` (in `tests/scripts/lib/inngest-host-dark-gate.sh`), and runs `inngest-host-not-serving-7674.sh` for G18. | Fixed **through** the lib and the 7674 script, with **zero bytes changed** in the workflow (488,582 B, near GitHub's 512 KB limit). #8831's changes cannot conflict with it by construction. `git merge-tree` against #8831's head is clean at plan time and is re-run at work time against #8831's then-current file list. |
| `scripts/inngest-dedicated-host-classify.sh` is a consumer | It is a **pure classifier** with no row selection. Selection lives in the workflow step that sources it. | Audited, no change. Its only mention of the marker is in comments. |
| `scripts/cutover-inngest.sh` registry/liveness gates read these rows | The registry gate and the 2.0 gate grade probe rows **through the dark-gate lib**. The op=resume G3, op=arm G3.7 and LUKS G3 **liveness counters** read `inngest-cutover-flip` / `inngest-luks-cutover` rows through `_current_instance_row_counts`, which checks only host+host_name. | Probe half: fixed via the lib. Liveness half: a required emitter-tag argument. Live data shows 22 and 17 `doppler` rows per 24h under those two `--grep` terms. |
| `scripts/inngest-host-state.sh` already anchors | It anchors on `m.startswith("SOLEUR_INNGEST_SERVER_PROBE")`, but with **no trailing space and no emitter check**. | Moved to the same rule as every other consumer. |
| `inngest-luks-cutover-6894.sh` is a live consumer | Its header says **"RETIRED 2026-09-21 (#8296) … Nothing runs this file now."** It has no suite. It is kept only because deleting it would edit a plugin baseline, which triggers a plugin release. | The predicate is changed, as the operator listed it, so the file is not left as a copy of the bad rule. **No new harness**: there is no suite to put a fixture in, and nothing runs it. Recorded in `decision-challenges.md`. |
| The listed consumer set is complete | Grep also finds `tests/scripts/lib/inngest-host-dark-gate.sh` (anchored, no emitter check, plus an inline `wrong_host` copy of the check) and `apps/web-platform/infra/betterstack-logs-alerts.tf` (SQL `position(...)=1`, no emitter check). | Dark-gate lib fixed and its duplicate removed. The `.tf` alert is deferred to **#8874**. |
| The event-log row "quotes the marker" | All 41 live `doppler` rows in 6h begin `{"caller":"api",…}` and quote the marker mid-string. | The **live-shape** fixture (a) reproduces the incident and reds the substring consumers. A **forged** anchored fixture (b) is the only shape that reds the consumers that already anchor. It is labelled as forged in each suite. |

## Research Insights

**Premise Validation (Phase 0.6).**

- #8846 is OPEN.
- #8833/#8834 are CLOSED (`completed`). They are not reopened.
- PR #8831 is OPEN. Its file list at plan time: the apply workflow, `destroy-guard-filter-web-platform.jq`, the `inngest-host-replace`, `inngest-host-shape` and `registry-host-replace` gate libs and their tests, `guard-vacuity-floor.test.sh`, `lint-legal-registers.sh`, `inngest-host.tf`, `inngest-host.test.sh`, and ADRs/runbooks. None overlaps this plan. The list moves, so it is re-listed at work time.
- PR #8835 touches `inngest-soak-6178.sh`, which does not contain the marker, so it is not a consumer.
- `git merge-tree --write-tree HEAD refs/remotes/pr/8831` is clean.

**Live measurement** (read-only, `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh`):

| Query | Rows by host / emitter |
|---|---|
| `--since 6h --grep SOLEUR_INNGEST_SERVER_PROBE --limit 200` (53 rows) | 6 × `soleur-inngest` / `inngest-server-probe` (`http_code=200 server_active=active`); 6 × `soleur-web-platform` / `inngest-server-probe`; 41 × `soleur-inngest` / `doppler` |
| `--since 24h --grep inngest-cutover-flip --limit 5000` | 4976 × `inngest-cutover-flip`; 22 × `doppler`; 2 boot-stage rows with a null identifier and no `host_name` (already excluded) |
| `--since 24h --grep inngest-luks-cutover --limit 5000` | 4981 × `inngest-luks-cutover`; 17 × `doppler` |

- Every row's decoded `.raw` carries `SYSLOG_IDENTIFIER`.
- The event-log rows come in bursts of up to 7 in 17 minutes.
- The emitter tags in source match the live values:
  - `apps/web-platform/infra/inngest-bootstrap.sh`: `LOG_TAG="inngest-server-probe"`, `logger -t "$LOG_TAG" "SOLEUR_INNGEST_SERVER_PROBE …"`
  - `apps/web-platform/infra/inngest-cutover-flip.sh`: `readonly LOG_TAG="inngest-cutover-flip"`
  - `apps/web-platform/infra/inngest-luks-cutover.sh`: `readonly LOG_TAG="inngest-luks-cutover"`
- The jq `def` was verified on jq 1.8.2:
  - `==` binds tighter than `and`, and `and` short-circuits, so a string, null or object-valued `message` returns `false` rather than an error.
  - `select($d | inngest_probe_row)` works with a top-level `def`.
  - It uses only `type`, `==`, `startswith` and `and`, all of which exist since jq 1.5.

**Reader contract.**

- `--grep` is a server-side `LIKE '%term%'`, and multiple terms are OR-combined.
- The reader returns the NEWEST `--limit` rows, re-sorted `dt ASC`.
- `.raw` is double-encoded.
- The `betterstack-query.sh` header already says to field-isolate on `SYSLOG_IDENTIFIER` (#6475).

**Per-consumer selection today:**

- **Watchdog** (`scheduled-inngest-health.yml`, step "Dedicated inngest host probe consumer (#7674)"): `select(.host …and .host_name …) | .message // empty' … | grep -F 'SOLEUR_INNGEST_SERVER_PROBE'` → `tail -1`, with `--limit 50` over `3h`. The live 3h density is about 75 event-log rows plus 12 probe rows, which already fills 50.
- **7674** (`mine=`): substring match. PASS if ANY row has `server_active=active`, `http_code=200` and `registry_fns=[1-9][0-9]*( |$)`. **Fails open**: G18 and the #7674-class trackers.
- **7761** (`mine_dt()`): host pair only. It parses `image_ref=` tokens, so a quoted line derives a false boundary.
- **6894** (`ON_MAPPER=`): unanchored `test(...)`. **Fails open**, but the script is retired.
- **8296**: anchored `startswith($pm)` with `pm="$PROBE_MARKER "`. No emitter check.
- **inngest-host-state.sh** (python): anchored, no trailing space. No emitter check.
- **Dark-gate lib**: `_IHDG_SELECT` uses `test("^SOLEUR_INNGEST_SERVER_PROBE ")` with no emitter check. It is used by `_ihdg_rows`, `_ihdg_newest_dt`, `_ihdg_row_count` and `_ihdg_tied_newest`. The `wrong_host_rows` jq keeps an inline copy. `_erg_hb_newest` already checks `$d.SYSLOG_IDENTIFIER == "inngest-cutover-flip"`, which is the precedent this plan follows.
- **cutover-inngest.sh** `_current_instance_row_counts`: host pair plus clocks, no emitter. **Fails open** ("audible").
- **confirm_flip_state / confirm_luks_state**: `grep '"flag":"done"'` over `jq -r .raw`. In `doppler` rows the quoted JSON is escaped (`\"flag\":\"done\"`), so it cannot match. Not changed.

**Institutional learnings applied:**

- `knowledge-base/project/learnings/2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md` (#6475): the same class of bug. Isolate the journald field, and model fixtures on the real escaped JSONEachRow shape. This is the third time it has happened, and the class-wide guard is now tracked as **#8875**.
- `knowledge-base/project/learnings/2026-07-17-host-name-create-time-render-drift-web1-mislabel.md` (#6616): keep the host+host_name conjunction. The emitter check is added alongside it and does not replace it.
- `knowledge-base/project/learnings/2026-09-19-a-sibling-merge-took-the-apply-workflow-over-githubs-byte-limit-and-nothing-in-repo-said-so.md`: zero bytes are added to the apply workflow.
- `knowledge-base/project/learnings/test-failures/2026-07-20-a-fixture-seam-above-the-code-under-test-makes-the-default-path-untestable.md`: fixtures enter through the stubbed reader, below the selection code.
- `knowledge-base/project/learnings/2026-06-05-followthrough-pr-body-prose-closes-keyword-autocloses-tracker.md`: only `Closes #8846` appears in the PR body. Every other issue is referenced with `Ref`.

**Scoped advisor consult (Step 4.5).** Both the primary and the fallback consult returned. Applied:

- **No `jq -L` module.** It depends on the working directory and search path, and a compile failure is swallowed as "no rows". Instead, a sourced shell variable holds the jq `def` (the `_IHDG_SELECT` precedent).
- **Every consumer checks jq's exit code**, so a selector that cannot run never reads as silence.
- The watchdog's `--limit` goes to 500.
- The `wrong_host` copy is removed.
- The liveness tag is required.

**Plan review (DHH, Kieran, code-simplicity, CTO).** See `## Plan Review Revisions` at the end.

**Property List (Phase 0.6b).**

- **P1.** A consumer's probe-row set contains only rows with emitter `inngest-server-probe` whose message begins with the marker followed by a space. Any other row on the same host is excluded, including one whose message begins with the marker.
- **P2.** The watchdog reads a healthy dedicated host as `healthy` when marker-quoting event-log rows are the newest in the window, and when they outnumber the old 50-row limit.
- **P3.** No fail-open gate is satisfied by an event-log row. The fail-open gates are: 7674 PASS / G18, dark-gate `dark`, and G3 / G3.7 / LUKS-G3 "audible".
- **P4.** A future reader of the marker cannot skip the shared rule without CI noticing. The rule's literals cannot drift from the emitters' `LOG_TAG`s.
- **P5.** No file in PR #8831 is edited, and `apply-web-platform-infra.yml` stays byte-identical.
- **P6.** A selector that cannot run never reads as "host silent", "healthy", `dark` or PASS.

**Cut List.**

- `jq -L` module → P1/P4 → covered by the sourced `def`.
- Server-side emitter `--grep` → P2 → covered by `--limit 500`. It would also change the argv that about 6 suites pin, and it depends on `LIKE` escaping nobody has measured.
- Per-consumer runtime self-test → P6 → covered by explicit `source … ||` arms plus the jq exit-code check.
- Saturation DETAIL text → no property → the existing DETAIL gains `returned=<n>/500`.
- Census set identity (exactly N) → no property → the unclassified bucket catches a reader that stops sourcing.
- Positional "the event-log row is last" harness rows → no property → AC1 (RED at the tests-only commit) proves each fixture matters.
- `run_suite` line for the new suite → no property → `scripts/test-all.sh` `SUITE_GLOBS` already contains `'scripts/lib/*.test.sh'`.
- A 6894 harness → the script is retired and nothing runs it.
- `confirm_*_state` edits → no property (the JSON is escaped).
- `apply-web-platform-infra.yml`, `inngest-dedicated-host-classify.sh`, `betterstack-logs-alerts.tf` edits → P5, no selection logic, #8874 respectively.

## Problem Statement

Seven readers pick the dedicated host's probe row, each with its own predicate. None of them checks which program wrote the row:

- Three match the marker as an unanchored substring, and the watchdog is one of them.
- Two of the substring readers fail open, so a quoted row can close trackers or clear a destroy guard.
- The FSM liveness counters behind op=resume's G3 have the same blind spot for `inngest-cutover-flip` rows, and they also fail open.

The trigger is ordinary GitHub traffic that quotes a marker, and the watchdog creates that traffic itself.

## Proposed Solution

### 1. One definition, sourced

`scripts/lib/inngest-probe-row.sh` defines:

- `INNGEST_PROBE_EMITTER="inngest-server-probe"` and `INNGEST_PROBE_MARKER="SOLEUR_INNGEST_SERVER_PROBE"`.
- `INNGEST_PROBE_ROW_JQ`, **built from those two variables** so the literals exist once:

  ```bash
  INNGEST_PROBE_ROW_JQ="def inngest_probe_row: type == \"object\" and .SYSLOG_IDENTIFIER == \"${INNGEST_PROBE_EMITTER}\" and ((.message | type) == \"string\") and (.message | startswith(\"${INNGEST_PROBE_MARKER} \"));"
  ```

- `inngest_probe_row_selftest`. It compiles the def with stderr visible and checks one positive row and three negative rows:
  - an event-log row that quotes the marker mid-string,
  - an event-log row whose message begins with the marker,
  - a probe-emitter row whose message does not begin with the marker.
- An executed mode, `bash scripts/lib/inngest-probe-row.sh --selftest`, which prints `inngest-probe-row selftest: ok` or exits 1. This is the discoverability probe.

The file is sourceable under `set -u`, sets no shell options, and its executed mode is guarded by `[[ "${BASH_SOURCE[0]}" == "$0" ]]`.

**How consumers find it.** Consumers resolve the path as `${INNGEST_PROBE_ROW_LIB:-<repo-relative path>}`. The override exists for test sandboxes that copy a SUT to a temp directory.

**Rules for consumers:**

- Use `"$INNGEST_PROBE_ROW_JQ"` directly, never `${…:-}`, so an unset value aborts under `set -u`.
- Guard every `source` with `|| <selector-unavailable arm>`.
- Capture the jq exit code before any `|| true`.

**The python consumer** reads `INNGEST_PROBE_EMITTER` and `INNGEST_PROBE_MARKER` from `os.environ[...]`. A missing variable raises `KeyError`, which fails loudly.

### 2. Every consumer

Each consumer sources the lib and adds `select(… inngest_probe_row)` on the decoded object. On a failed `source` or a non-zero jq exit, each takes the arm below:

| Consumer | Failure arm |
|---|---|
| Watchdog | Write `crash_reason=selector_unavailable lib=<path>` or `crash_reason=jq_rc=<n>` to `$GITHUB_OUTPUT`, then `::error::`, then **exit 1**. The existing "Dedicated-host consumer crashed (#7674)" step then files `[ci/inngest-dedicated-host] Dedicated-host probe consumer is broken`, and its body now includes `steps.dedicated.outputs.crash_reason`. That issue names a broken reader, not a host outage (CTO #7, deepen obs F6). |
| 7674 | `TRANSIENT: reason=selector_unavailable lib=<path>`, exit 2. Never `channel_dark`, never PASS. In production its only caller is apply-workflow G18, which throws away its stdout and stderr (`>/dev/null 2>&1`). The dark-gate lib's own refusal below is therefore what surfaces this case in that run (deepen obs F1). |
| 7761 | The existing `__DECODE_FAILED__` path. The tracker is closed and no workflow runs the script, so only tests reach this arm. |
| 8296 | A dedicated line, `CANNOT ESTABLISH: reason=selector_unavailable lib=<path>`, exit 3. It must not reuse `no_rows`, whose text says "no row from the dedicated host" (deepen obs F7). The `source` sits **after** `trap on_exit EXIT`, because the suite pins the trap as the first top-level statement after the xtrace refusal. |
| host-state | The existing exit-6 read-failure class. |
| Dark-gate lib | Both entry points refuse with the existing `unreadable` token **as their first check, before G1 and G18**. The message naming the lib path goes to **stderr**. stdout stays the bare token only, because callers read it with `tail -1` and `$(…)` (CTO #8, deepen obs F1/F3). |

- The watchdog also raises `--limit 50` to `500`. Its existing DETAIL gains `returned=${LINES}/500`.
- 6894 gets the same predicate, and a missing lib there exits 2 as TRANSIENT.

### 3. Liveness counters

- `_current_instance_row_counts <floor> <tag>` selects `.r.SYSLOG_IDENTIFIER == $tag`.
- `_generation_scoped_count <floor> <label> <tag>` validates that the tag is non-empty. An empty tag produces its own `::warning::` **on stderr** ("liveness counter called without an emitter tag — a defect in cutover-inngest.sh, not a host state") and returns `__UNREADABLE__` (Kieran #12, deepen obs F3). The tag is argument **2** of `_current_instance_row_counts` and argument **3** of `_generation_scoped_count`.
- `_flip_liveness_count` passes `inngest-cutover-flip`, and `_luks_liveness_count` passes `inngest-luks-cutover`.

### 4. Census + parity

These live in the new suite `scripts/lib/inngest-probe-row.test.sh` and are specified under Guard 1 and Guard 2.

## Implementation Phases

Phases run in dependency order: the lib (the contract) comes before its consumers, and within each consumer the RED test comes before the fix (`cq-write-failing-tests-before`).

### Phase 0 — Preconditions (no code)

- 0.1 Fetch origin/main and #8831's head. List #8831's files with `gh pr view 8831 --json files`, and confirm that no file in Files to Edit/Create is among them. Then run `git merge-tree --write-tree HEAD <8831-head>`, which must be clean. Re-run all three after the last commit.
- 0.2 Re-measure the emitter values live with the three queries in Research Insights, and put the counts in the PR body.
- 0.3 Capture one real `doppler` row and one real probe row as a shape model: keep `host`, `host_name` and `SYSLOG_IDENTIFIER`, plus a 120-character message prefix with the issue text redacted. Fixtures are synthesized to that shape, never pasted (`cq-test-fixtures-synthesized-only`).

### Phase 1 — RED fixtures (commit: tests only, expected red)

Fixture shapes, all on `soleur-inngest`/`soleur-inngest-prd`, placed **LAST** (newest `dt`):

- **(a) LIVE shape.** Emitter `doppler`. The message is `{"caller":"api","event":{"data":{"action":"closed",…,"body":"…quoted probe line…"}}}`.
- **(b) FORGED shape** (labelled in a comment: not observed live; journald splits multi-line stdout into one entry per line, so this is the adversarial shape). Emitter `doppler`. The message *begins* with the marker, a space, and fields.

A quoted line must carry the exact tokens the consumer parses, each followed by a space or end of line, so that the RED is certain. The exact messages are in the table.

**Harness changes that ship in this Phase 1 commit, not Phase 3** (deepen test-design #10). The RED cases depend on them.

- `inngest-dedicated-host-classify.test.sh`:
  - Add `"SYSLOG_IDENTIFIER":"inngest-server-probe"` to each `R_*` literal. They are literals, not builders.
  - The stub reader appends its argv to a log.
  - `run_arm` runs `unset INNGEST_PROBE_ROW_LIB`, copies the lib into `$ws/scripts/lib/` unless a case opts out, and returns the step's exit code and `detail=` next to `verdict=`. `arm_case`'s string compare and its canary must keep working.
- Two dark-gate rows skip `bs_line`: "outer-envelope host_name must not launder" (a `jq -cn` row) and "[I2] an EMBEDDED NEWLINE" (a python `json.dumps` row). Add `SYSLOG_IDENTIFIER:"inngest-server-probe"` to both. Without it they read `silent` after the fix, instead of `wrong_host` / `unreadable`.
- `inngest-host-state.test.sh`: its existing `rawBody` case passes `doppler` explicitly, so it keeps modelling the live shape.
- **Every exact assertion-count floor** is updated to the measured count, with an itemised comment in the style of the cutover suite. The exact floors are classify `EXPECTED_ASSERTIONS=104`, dark-gate `_FLOOR=282` (`-ne`) and cutover `_EXACT_FLOOR=914`. The `-lt` floors that would otherwise go stale are 7674 `FLOOR=14`, 7761 `MIN_ASSERTIONS=307`, 8296 `MIN_PASSES=114` and host-state `_min_cases=25`. The new suite is under `scripts/guard-vacuity-floor.test.sh`'s `COVERED_DIRS`, so if it has a floor, that floor must be able to fail.

| Suite | Case (rows oldest → newest) | Current → | Fixed → |
|---|---|---|---|
| `apps/web-platform/infra/inngest-dedicated-host-classify.test.sh` | `R_OK`, then (a) whose quoted text has **no** `server_active=` / `http_code=` token | `probe-unavailable` (the incident) | `healthy`, step exit 0 |
| same | `R_OK`, then (a) quoting `http_code=000 server_active=inactive cutover_flag=done` | `not-serving` | `healthy` |
| same | (a) only | `probe-unavailable` | `probe-unavailable` (control) |
| same | web-1 row, `R_OK`, then (a) (non-canonical; RED at Phase 1) | `probe-unavailable` | `healthy` |
| same | `R_OK` alone (must-PASS: guards an unset `JQ_RC` under `set -u`, deepen obs F4) | `healthy` | `healthy`, step exit 0 |
| same | stub argv log contains `--limit 500` | RED (`50`) | GREEN |
| same | `R_OK`, with the lib **not** copied into `$ws` | `healthy` | step exit ≠ 0, `crash_reason=selector_unavailable` in `$GITHUB_OUTPUT`, no `verdict=` |
| `scripts/followthroughs/inngest-host-not-serving-7674.test.sh` | real probe `server_active=inactive http_code=000`, then (a) quoting `http_code=200 server_active=active registry_fns=9 cutover_flag=done` | **PASS, exit 0** (fails open) | `TRANSIENT reason=not_serving`, exit 2 |
| same | (a) only | PASS, exit 0 | `TRANSIENT reason=channel_dark`, exit 2 |
| same | real serving probe, `INNGEST_PROBE_ROW_LIB=/nonexistent` | PASS | `TRANSIENT reason=selector_unavailable`, exit 2 |
| `scripts/followthroughs/inngest-cutover-flip-rollout-7761.test.sh` (derive arm) | probe rows with an old digest, then (a) quoting `image_ref=<pinned digest>`, with a space before and after it. Derivation takes the EARLIEST match, so placement does not matter. | derives, and prints `boundary DERIVED from telemetry` | `TRANSIENT boundary_underivable`; assert `! grep -qF 'boundary DERIVED from telemetry'`, and pass `probe_channel_dark row_decode_failed` to `expect` as competing reasons |
| same | `INNGEST_PROBE_ROW_LIB=/nonexistent` | derives | `row_decode_failed` |
| `scripts/followthroughs/inngest-luks-property-8296.test.sh` | real dedicated LUKS row, then (b): `SOLEUR_INNGEST_SERVER_PROBE http_code=200 host_role=dedicated data_mount_src=/dev/sdb data_mount_devid=scsi-0HC_Volume_<n> …` with dt `DT_NEWEST` | `5 rollback_inversion` | `2 agree` |
| same | the lib is not copied by `run_probe` | grades | exit 3, `reason=selector_unavailable` |
| `scripts/inngest-host-state.test.sh` | `DEDICATED_MSG` with `http_code=000 server_active=activating`, then (b) = the serving `DEDICATED_MSG` **unchanged except for the `doppler` emitter**, LAST in the file (`rows[-1]` is file order) | `SERVING=yes` | `SERVING=no` (assert this token: `SERVING` is a substring of `NOT SERVING`) |
| same | `INNGEST_PROBE_ROW_LIB=/nonexistent` | a verdict | rc 6 |
| `tests/scripts/test-inngest-host-dark-gate.sh` (`bs_line … doppler`) | the recut gate's canonical dark pair (`$ROWS` + `$FIN`), then (b) serving | not `dark` | `dark` |
| same | (b) from the web-1 host only | `wrong_host` | `silent` |
| same, `inngest_execute_registry_gate` | the execute gate's canonical pair (`$EROWS` + `$HB`, `EBID` envelope), then (b) built with `erows`, emitter `doppler`, dt strictly between 10:00 and `NOW`. A tie trips `_ihdg_tied_newest` and gives `unreadable`, which is RED for the wrong reason. | not `dark` | `dark` |
| same | subshell with `INNGEST_PROBE_ROW_LIB=/nonexistent`, both entry points, including `--followthrough-rc 2` | `dark` / `followthrough_7674` | `unreadable`, rc 1; the path is named on stderr |
| same | canary: an unmutated copy of the gate run from `$TMP` with `INNGEST_PROBE_ROW_LIB` exported | — | the control token (proves the mutants load the lib) |
| `apps/web-platform/infra/cutover-inngest-workflow.test.sh` | flip harness `lv_rows eventlog`: 2 current-generation `doppler` rows | `'2'` (audible, fails open) | `'0'` |
| same | flip `eventlog+2cur` | `'4'` | `'2'` |
| same | LUKS harness, the same two modes | `'2'` / `'4'` | `'0'` / `'2'` |
| same | `_generation_scoped_count` with an empty tag | a count | `__UNREADABLE__`, and the missing-tag warning on stderr |

Run each suite and record which cases are RED at this commit. **A new case that is not RED here is a fixture defect.** Exceptions are the rows marked control, must-PASS or canary.

### Phase 2 — The shared lib and its suite

- 2.1 Create `scripts/lib/inngest-probe-row.sh` as in Proposed Solution §1.
- 2.2 Create `scripts/lib/inngest-probe-row.test.sh`, following the repo's `*.test.sh` conventions (`test-helpers.sh`; the EXIT trap that owns temp files is set before `source`, per `lint-trap-tempfile-ownership`). It covers:
  - unit rows: the 4 self-test rows, plus an object-valued message, the marker with no trailing space (`SOLEUR_INNGEST_SERVER_PROBEX`), a missing `SYSLOG_IDENTIFIER`, and a web-1 row that must still be accepted, because host isolation is the caller's job;
  - `--selftest`: prints the literal, and a tampered copy (emitter clause removed) exits 1;
  - the Guard 1 census;
  - the Guard 1 and Guard 2 parity rows;
  - the Guard 2 caller census.
- 2.3 Registration: `SUITE_GLOBS` already contains `'scripts/lib/*.test.sh'` (`scripts/test-all.sh`), so add **no** `run_suite` line. Add one `scripts/suite-shard-legs.tsv` row, shaped like the existing `scripts/lib/legal-base-ref.test.sh<TAB>5` row, and pick the leg per that manifest's convention.
- 2.4 Add `scripts/lib/inngest-probe-row.sh` to the **pull_request** `paths:` list of `.github/workflows/infra-validation.yml`, next to the `tests/scripts/lib/inngest-host-dark-gate.sh` entry. The push list is deliberately narrower, as its own header says (Kieran #7). This list is read by GitHub's path filter for that workflow, which runs `inngest-dedicated-host-classify.test.sh` and `cutover-inngest-workflow.test.sh`, and both execute the lib.

### Phase 3 — GREEN: probe consumers

Order: dark-gate lib, watchdog, 7674, 7761, 8296, host-state, 6894.

- 3.1 `tests/scripts/lib/inngest-host-dark-gate.sh`
  - Source `"${INNGEST_PROBE_ROW_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/scripts/lib/inngest-probe-row.sh}"`. On failure, set a flag. Both entry points check the flag **first**, before G1 and before any other refusal, including `followthrough_7674`. If set, they print the path to stderr and refuse `unreadable`, with the bare token as the only stdout line.
  - Add `_IHDG_PROBE='| select($d | inngest_probe_row)'`, and set `_IHDG_SELECT="$_IHDG_IDENT$_IHDG_PROBE"`.
  - Prefix the def to every program that embeds `_IHDG_SELECT` or `_IHDG_PROBE`. Rewrite `wrong_host_rows` as decode + `$_IHDG_PROBE` + host negation, which removes its inline marker copy.
  - Suite, `tests/scripts/test-inngest-host-dark-gate.sh`:
    - Export `INNGEST_PROBE_ROW_LIB`, so the `mutate()` copies under `$TMP` load the lib (Kieran P0 #1). Add the canary row.
    - Keep the "host conjunction appears exactly once" guard.
    - Add a row: the marker literal appears 0 times outside comments in the lib.
    - `bs_line` already defaults to `inngest-server-probe`.
- 3.2 `.github/workflows/scheduled-inngest-health.yml`. Three steps change.
  - **The "Dedicated inngest host probe consumer (#7674)" step:**
    - Source the lib with `|| { echo "crash_reason=selector_unavailable lib=<path>" >> "$GITHUB_OUTPUT"; echo "::error::…"; exit 1; }`, and use `--limit 500`.
    - Initialize the rc before use. Without that, `set -u` fails the healthy path and re-creates an issue loop (deepen obs F4).

      ```bash
      JQ_RC=0
      MINE="$(printf '%s\n' "$ROWS" | jq -R -r "$INNGEST_PROBE_ROW_JQ"' fromjson? | .raw? | fromjson? | select(.host == env.DEDICATED_HOST and .host_name == env.DEDICATED_HOST_NAME) | select(inngest_probe_row) | .message')" || JQ_RC=$?
      ```

    - A non-zero `JQ_RC` writes `crash_reason=jq_rc=${JQ_RC}`, then `::error::`, then exit 1.
    - Set `LINES` to the count of non-empty lines in `ROWS`, and append `returned=${LINES}/500` to the `*)` DETAIL.
    - Update the comment block to cite #8846, and keep `strip_log_injection` on every echoed field.
  - **The "Dedicated-host consumer crashed (#7674)" step:** its issue body adds the line `cause: ${{ steps.dedicated.outputs.crash_reason || 'unknown' }}`, passed through `env:`, never by inline interpolation into shell. `$GITHUB_OUTPUT` lines written before a step fails are still exported. Verify this in the classify test, which executes the arm body and can read `$GITHUB_OUTPUT`, and with `actionlint`.
  - **The "No live scheduler check (#8077)" step (deepen obs F5):** when `DEDICATED_VERDICT` is empty, the detail says `dedicated host NOT MEASURED — the dedicated-host consumer failed; see the [ci/inngest-dedicated-host] consumer-broken issue`. The step still fails closed. Only the wording changes, because an unmeasured host must not be described as "not serving".
  - The classify-test harness changes are in Phase 1 (Kieran #9, deepen test-design #10). The extraction `awk` range (from `Dedicated inngest host probe consumer` to `Note the known brake`) is unchanged, so `run_arm` still extracts the step.
- 3.3 `scripts/followthroughs/inngest-host-not-serving-7674.sh`:
  - Source the lib with the `selector_unavailable` arm.
  - Put the def and `select(inngest_probe_row)` in the `mine=` jq, and drop `| grep -F "$MARKER"`.
  - Capture jq's exit code.
  - The 7674 test's `row()` builder gains `ident="${4:-inngest-server-probe}"`.
- 3.4 7761 `mine_dt`:
  - Prefix the def and add `| select($m | inngest_probe_row)`. A failed source or failed jq routes to `__DECODE_FAILED__`.
  - The lib path honours `INNGEST_PROBE_ROW_LIB`, because the `FLIP_ROLLOUT_TEST_TARGET` seam runs **copies** of the probe. The suite exports the variable so those copies still find the lib (deepen test-design #5).
  - `probe_row` already carries the emitter.
- 3.5 8296:
  - The def replaces `select(startswith($pm))`, and `--arg pm` is dropped if it is no longer used.
  - `source` goes after `trap on_exit EXIT`.
  - The test's `run_probe` sandbox also copies the lib to `$root/scripts/lib/` (Kieran #2). A case-level flag skips the copy for the lib-missing row.
  - The `row()` builder gains an emitter parameter defaulting to `inngest-server-probe`.
- 3.6 `scripts/inngest-host-state.sh`:
  - Source the lib, and export the two variables into the first `python3 -c` process's environment.
  - The probe loop checks `r.get("SYSLOG_IDENTIFIER") != os.environ["INNGEST_PROBE_EMITTER"]` and `m.startswith(os.environ["INNGEST_PROBE_MARKER"] + " ")`.
  - The error-scan loop, which excludes marker rows, is unchanged.
  - The test's python `row()` builder gains an emitter argument with a default.
- 3.7 `scripts/followthroughs/inngest-luks-cutover-6894.sh` (retired): source the lib from `$REPO_ROOT`, with a TRANSIENT exit 2 on failure, and add `select(inngest_probe_row)` in the `ON_MAPPER` jq. No harness (see Research Reconciliation). The census checks that it uses the def.

### Phase 4 — GREEN: liveness counters

- 4.1 `scripts/cutover-inngest.sh`:
  - Add the tag arguments per Proposed Solution §3.
  - Update every caller from `git grep -n '_generation_scoped_count\|_current_instance_row_counts' scripts/` in the same commit.
  - Update the six-counter header comment: host_pair now means host-pair rows **from the emitter `<tag>`**.
  - Keep the functions' "always return 0 and print the token" contract, because the script runs under `set -e` and the functions are called inside `$(…)`.
- 4.2 `apps/web-platform/infra/cutover-inngest-workflow.test.sh` (Kieran #3):
  - `fix_row` gains a fifth argument, the tag.
  - The top-level `FIX_*` rows are built as separate `_FLIP` and `_LUKS` sets (or lazily inside `lv_rows <mode> <tag>`), never through `${LV_TAG:?}` at load time.
  - `FIX_REORDER` gains the emitter field.
  - Add the `eventlog` and `eventlog+2cur` modes.
  - The existing extraction non-vacuity rows are unchanged.

### Phase 5 — Verification (targeted only; the machine is contended)

- 5.1 Run `bash <suite>` for each of the 7 suites in the Phase 1 table, plus `bash scripts/lib/inngest-probe-row.test.sh`. Do **not** run `scripts/test-all.sh --full` or `run-registered-suites.sh`.
- 5.2 Run `shellcheck` on every edited `.sh`, and `actionlint` on the two edited workflows.
- 5.3 Run `bash scripts/lib/inngest-probe-row.sh --selftest`.
- 5.4 Commit with `LEFTHOOK_EXCLUDE=bun-test`. CI's required `test` context runs the full battery.
- 5.5 Re-run the Phase 0.1 checks, plus the AC4 diff.
- 5.6 Run `npx markdownlint-cli2` on the plan and on `tasks.md`.

## Files to Edit

- `.github/workflows/scheduled-inngest-health.yml`: three steps only. The dedicated-host consumer step, the consumer-crashed step (its body gains `cause:`), and the no-live-scheduler step (the empty-verdict wording).
- `.github/workflows/infra-validation.yml`: one entry in the pull_request `paths:`.
- `tests/scripts/lib/inngest-host-dark-gate.sh`
- `tests/scripts/test-inngest-host-dark-gate.sh`
- `scripts/followthroughs/inngest-host-not-serving-7674.sh`
- `scripts/followthroughs/inngest-host-not-serving-7674.test.sh`
- `scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh`
- `scripts/followthroughs/inngest-cutover-flip-rollout-7761.test.sh`
- `scripts/followthroughs/inngest-luks-cutover-6894.sh`
- `scripts/followthroughs/inngest-luks-property-8296.sh`
- `scripts/followthroughs/inngest-luks-property-8296.test.sh`
- `scripts/inngest-host-state.sh`
- `scripts/inngest-host-state.test.sh`
- `scripts/cutover-inngest.sh`: only the four liveness functions.
- `apps/web-platform/infra/cutover-inngest-workflow.test.sh`
- `apps/web-platform/infra/inngest-dedicated-host-classify.test.sh`
- `scripts/suite-shard-legs.tsv`: one row.

## Files to Create

- `scripts/lib/inngest-probe-row.sh`
- `scripts/lib/inngest-probe-row.test.sh`

## Files NOT to touch (asserted by AC4)

- `.github/workflows/apply-web-platform-infra.yml`
- `apps/web-platform/infra/inngest-host.tf` and every other file in PR #8831
- `scripts/followthroughs/inngest-soak-6178.sh` (PR #8835)
- `apps/web-platform/infra/betterstack-logs-alerts.tf` (#8874)
- `scripts/inngest-dedicated-host-classify.sh`
- `scripts/test-all.sh`

## Open Code-Review Overlap

Four open code-review issues mention files this plan edits:

- **#8593** is about the #6793 unbounded-`gh` gate; its table names `scheduled-inngest-health.yml`'s issue-close loops. **Acknowledge.** It is about `gh issue list` bounds in loops this plan does not touch, so it stays open.
- **#8735**, **#8487** and **#7942** concern `infra-validation.yml` jobs. **Acknowledge.** This plan only adds one `paths:` entry and does not touch those jobs.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Inline the two-clause predicate in each consumer and use a census to pin the copies | Rejected. Inline copies are how today's drift happened (three consumers anchored, three not). The census stays, to catch new readers. |
| `scripts/lib/inngest-probe-row.jq` loaded with `jq -L` + `include` | Rejected (advisor). It depends on the working directory, and a compile failure reads as "no rows". |
| Server-side selection (`--grep` on the escaped `SYSLOG_IDENTIFIER` literal) | Rejected for this PR. About 6 suites pin the argv, and `LIKE` escaping has not been measured. |
| Edit `apply-web-platform-infra.yml` inline | Rejected. It has no selection logic, and P5 rules it out. |
| Put the selector in `inngest-dedicated-host-classify.sh` | Rejected. That would couple six unrelated readers to a watchdog classifier. |
| Name the lib for the class (`betterstack-emitter-row.sh`, generic `bs_emitter_row($tag; $prefix)`) | Deferred to **#8875** (the class-wide guard). Recorded as a Taste item in `decision-challenges.md`. |

## Non-Goals

- The `betterstack-logs-alerts.tf` alert SQL predicate, tracked in **#8874**. It is already anchored with `position(...)=1`, none of the 41 live event-log rows starts with the marker, and changing it needs a Terraform apply on the root #8831 is in flight on.
- A repo-wide guard requiring every Better Stack reader to check the emitter, tracked in **#8875**.
- `confirm_flip_state` / `confirm_luks_state` (see the Cut List).

## User-Brand Impact

- **If this lands broken, the user experiences:** one of two failures.
  - The watchdog stays blind to a real outage of the host that fires every user's crons and reminders, reading `probe-unavailable` or, in the worst case, `healthy`.
  - The op=resume or op=arm gates refuse a legitimate cutover because a liveness counter reads zero. That delays restoring cron and reminder delivery.
- **If this leaks, the user's data is exposed via:** no new vector. The change only alters how rows already in Better Stack are selected. It adds no sink, and it echoes no new field. The watchdog still passes echoed fields through `strip_log_injection`.
- **Brand-survival threshold:** `aggregate pattern`. A missed outage of the shared scheduler host affects all users' scheduled work at once, and no single user's data is involved.

## Observability

```yaml
liveness_signal:
  what: "the dedicated-host arm of scheduled-inngest-health.yml prints '#7674 dedicated host: rows=N server_active=... http_code=... cutover_flag=... -> <verdict>' and files or closes the [ci/inngest-dedicated-host] and [ci/inngest-no-live-scheduler] issue classes"
  cadence: "every 15 minutes (the workflow's schedule); workflow_dispatch also available"
  alert_target: "GitHub issue [ci/inngest-dedicated-host] (host verdicts) and '[ci/inngest-dedicated-host] Dedicated-host probe consumer is broken' (reader faults), both filed by the workflow"
  configured_in: ".github/workflows/scheduled-inngest-health.yml (steps 'Dedicated inngest host probe consumer (#7674)' and 'Dedicated-host consumer crashed (#7674)')"

error_reporting:
  destination: "the GitHub issue channel above plus the workflow run log; follow-through verdicts as issue comments by scheduled-followthrough-sweeper.yml"
  fail_loud: "a selector that cannot run fails the watchdog step (routed to the consumer-broken issue), prints 'TRANSIENT: reason=selector_unavailable' in 7674, refuses 'unreadable' naming the lib path in the dark-gate lib, and returns __UNREADABLE__ with a named ::warning:: from the liveness counters"

failure_modes:
  - mode: "marker-quoting event-log rows are newest in the window"
    detection: "layer 6 (GitHub Actions run log): '#7674 dedicated host: rows=N ... -> healthy', where rows= counts only emitter-selected probe rows"
    alert_route: "none needed; the verdict is correct"
  - mode: "shared lib missing or jq fails"
    detection: "layer 6 (GitHub Actions run log): the watchdog step's ::error:: plus crash_reason=selector_unavailable|jq_rc=<n>; the dark-gate lib's lib-path message on stderr before its unreadable token in the apply and cutover run logs. 7674's own TRANSIENT line is discarded by its only production caller (G18 runs it with output sent to /dev/null), so the dark-gate refusal is what surfaces this case there"
    alert_route: "layer 5 (GitHub issue): '[ci/inngest-dedicated-host] Dedicated-host probe consumer is broken' with a cause: line; the apply/cutover run fails closed with verdict=unreadable"
  - mode: "window holds more non-probe rows than --limit"
    detection: "layer 6 (GitHub Actions run log) and layer 5 (issue body): DETAIL carries returned=<n>/500 beside rows=<probe rows>"
    alert_route: "layer 5 (GitHub issue): the [ci/inngest-dedicated-host] issue body"
  - mode: "emitter LOG_TAG renamed in inngest-bootstrap.sh, inngest-cutover-flip.sh or inngest-luks-cutover.sh"
    detection: "layer 6 (GitHub Actions run log of the required test check): parity rows in scripts/lib/inngest-probe-row.test.sh go RED"
    alert_route: "PR check failure on the required test context"
  - mode: "a new file reads the marker without the shared predicate"
    detection: "layer 6 (GitHub Actions run log of the required test check): the census's unclassified bucket goes RED"
    alert_route: "PR check failure on the required test context"

logs:
  where: "GitHub Actions run logs for scheduled-inngest-health.yml, cutover-inngest.yml, apply-web-platform-infra.yml and scheduled-followthrough-sweeper.yml; source rows in Better Stack (hot window plus S3 archive, read with scripts/betterstack-query.sh)"
  retention: "GitHub Actions repository log retention (default 90 days); Better Stack per the source's retention setting"

discoverability_test:
  command: "bash scripts/lib/inngest-probe-row.sh --selftest"
  expected_output: "inngest-probe-row selftest: ok"
```

## Guard Contract

### Guard 1 — probe-row selector: census and emitter parity

**Property.** Every tracked file that reads the dedicated host's probe rows selects them only through the shared emitter-plus-anchor predicate, and that predicate's literals equal the probe emitter's own `LOG_TAG` and marker.

**Assembly.**

- **Discovery is structural, never a hand-written list.** Take `git ls-files`, excluding `knowledge-base/`, `*.md`, `*.test.sh`, `*.test.ts`, `tests/scripts/test-*.sh` and the lib itself. Keep every file that names the marker. At plan time that is exactly 14 files (verified by the deepen sweep). The census function takes an **injectable file list and root** (`census <root> <file-list>`). Production passes the `git ls-files` result. Mutation rows #4, #5 and #7 pass a temp fixture tree, so they never touch the git index (deepen test-design #9).
- **Per-reader granularity for the one multi-reader file.** A `source` of the dark-gate lib satisfies the rule for the file, and `scripts/cutover-inngest.sh` has two raw `_bs_query_rows … SOLEUR_INNGEST_SERVER_PROBE` reads. So the census also asserts that the number of `_bs_query_rows … SOLEUR_INNGEST_SERVER_PROBE` call lines in that file equals the number of `inngest_execute_registry_gate --rows-file` call lines. At plan time both are 2. A third raw read with no gate call goes RED.
- **One rule per discovered file** (DHH #2, simplicity):
  - (i) On a non-comment line, the file either contains `inngest_probe_row` as a whole word (`grep -E 'inngest_probe_row([^_[:alnum:]]|$)'`, so `inngest_probe_row_selftest` does not count, per Kieran #4) or `os.environ["INNGEST_PROBE_EMITTER"]`, **or** it has a `source` / `.` line naming `tests/scripts/lib/inngest-host-dark-gate.sh`. Both spellings must match: the bare relative form in `cutover-inngest.sh` and the `"${GITHUB_WORKSPACE}/…"` form in the apply workflow (CTO #6).
  - (ii) Otherwise, the file is on the in-suite allowlist with a reason. At plan time the allowlist is: `apps/web-platform/infra/inngest-bootstrap.sh` (the emitter), `scripts/encryption-posture-ledger.json` (prose), `scripts/test-all.sh` (comment), `scripts/inngest-dedicated-host-classify.sh` (comment-only), and `apps/web-platform/infra/betterstack-logs-alerts.tf` (deferred, #8874).
  - Anything else is RED.
- **Parity anchor.** `inngest-bootstrap.sh` has **two** `LOG_TAG=` assignments: `inngest-heartbeat` and `inngest-server-probe`. A first-match read takes the wrong one (deepen test-design #8). The parity reader locates the `logger -t "$LOG_TAG" "SOLEUR_INNGEST_SERVER_PROBE` line and binds to the **nearest preceding** `LOG_TAG=` assignment. `INNGEST_PROBE_EMITTER` must equal that assignment's value, and `INNGEST_PROBE_MARKER` must equal the first token of the logger payload.
- **The behavioural half** is the Phase 1 fixture rows. The census proves the wiring, and the fixtures prove the effect.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the `SYSLOG_IDENTIFIER` clause from `INNGEST_PROBE_ROW_JQ` | RED: lib unit (event-log anchored row); anchored suites' (b) cases |
| 2 | Remove the `startswith` clause, keep the emitter clause | RED: lib unit (probe-emitter row whose message does not begin with the marker) |
| 3 | Break the guard's own discovery regex so it finds 0 files | RED: discovery floor (≥ 12 files, and the allowlisted emitter file must be among them) |
| 4 | A second member: add a new `scripts/foo.sh` that runs `--grep SOLEUR_INNGEST_SERVER_PROBE`, after the compliant ones | RED: unclassified |
| 5 | A consumer sources the lib and calls only `inngest_probe_row_selftest`, but its jq never selects with the def (precondition holds, property fails) | RED: the word-boundary rule |
| 6 | `LOG_TAG` in `inngest-bootstrap.sh` renamed | RED: parity |
| 7 | Harness: an allowlist entry whose file no longer exists | RED: every allowlist entry must be discovered (no stale exemptions) |
| 8 | Must-PASS, non-canonical: `apply-web-platform-infra.yml`'s quoted `"${GITHUB_WORKSPACE}/tests/scripts/lib/inngest-host-dark-gate.sh"` source form | PASS |

**Anchor.** The emitter's `LOG_TAG` line, outside both the lib and the test. The allowlist lives in the test file, so weakening it is a visible diff in review.

### Guard 2 — FSM liveness counters scoped by emitter

**Property.** `_flip_liveness_count` and `_luks_liveness_count` count only rows whose decoded `SYSLOG_IDENTIFIER` equals their FSM's tag, and every call path into the counter carries a literal tag equal to that FSM's `LOG_TAG`.

**Assembly.**

- The single chokepoint is `_current_instance_row_counts`, reached only through `_generation_scoped_count` in `scripts/cutover-inngest.sh`.
- Callers are discovered **repo-wide** with `git grep -n '_generation_scoped_count' -- ':!*.test.sh' ':!knowledge-base'` (Kieran #12), with comment lines stripped. Every **call** of `_generation_scoped_count`, other than its definition, must pass a **third** argument that is a literal in `{inngest-cutover-flip, inngest-luks-cutover}`. `_current_instance_row_counts` is called only from inside `_generation_scoped_count`, and it forwards the tag as its **second** argument through a variable (`"$tag"`). That inner call is asserted to be exactly one, and it is exempt from the literal rule (deepen test-design #9).
- The suite extracts the real functions (the existing `GEN_FN` / `FLV_FN` extraction).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `.r.SYSLOG_IDENTIFIER == $tag` from the jq | RED: `eventlog` reads `'2'` |
| 2 | `_flip_liveness_count` passes `inngest-luks-cutover` | RED: the flip `rows` mode reads `'0'` |
| 3 | Omit the tag, or default it | RED: the empty-tag row expects `__UNREADABLE__` and the warning |
| 4 | `LOG_TAG` renamed in `inngest-cutover-flip.sh` | RED: tag parity |
| 5 | A second member: a new caller of `_generation_scoped_count` with no tag, after the two compliant ones | RED: caller census |

**Anchor.** The `readonly LOG_TAG=` lines in the two FSM scripts.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** The Phase 1 tests-only commit exists. At that commit every new case goes RED (except those marked control, must-PASS or canary). The PR body records the RED counts per suite. The commit also carries the updated floors: at that commit the only failing assertions are the new cases, not a stale floor.
- [ ] **AC2** At HEAD, each of the 7 Phase 1 suites and `scripts/lib/inngest-probe-row.test.sh` exits 0 when run standalone with `bash <suite>`.
- [ ] **AC3** `bash scripts/lib/inngest-probe-row.sh --selftest` prints `inngest-probe-row selftest: ok` and exits 0.
- [ ] **AC4** `git diff --quiet origin/main...HEAD -- .github/workflows/apply-web-platform-infra.yml apps/web-platform/infra/inngest-host.tf apps/web-platform/infra/betterstack-logs-alerts.tf scripts/followthroughs/inngest-soak-6178.sh scripts/inngest-dedicated-host-classify.sh scripts/test-all.sh` exits 0.
- [ ] **AC5** At the last commit:
  - #8831's current file list, read live, does not intersect this PR's diff;
  - `git merge-tree --write-tree HEAD <8831-head>` exits 0.
- [ ] **AC6** The Guard 1 census reports 0 unclassified. The watchdog step's selection contains no `grep -F`: the census's word-boundary rule plus the watchdog (a) fixture prove this.
- [ ] **AC7** The watchdog's recorded stub argv contains `--limit 500`.
- [ ] **AC8** The liveness counters read `'0'` for `eventlog` in both the flip and LUKS harnesses. `_generation_scoped_count` with an empty tag returns `__UNREADABLE__`.
- [ ] **AC9** `shellcheck` is clean on every edited `.sh`. `actionlint` is clean on both edited workflows.
- [ ] **AC10** Registration:
  - `scripts/suite-shard-legs.tsv` has one row for `scripts/lib/inngest-probe-row.test.sh`;
  - `grep -c 'inngest-probe-row' scripts/test-all.sh` is 0, because the glob registers the suite;
  - the pull_request `paths:` of `infra-validation.yml` lists `scripts/lib/inngest-probe-row.sh`.
- [ ] **AC11** The PR body has `Closes #8846`. #8833, #8834, #8862, #8863, #8874 and #8875 appear only with `Ref`.
- [ ] **AC12** The diff is a subset of Files to Edit + Files to Create, plus the pipeline artifacts: this plan, `knowledge-base/project/specs/feat-one-shot-8846-inngest-probe-row-emitter/*`, any generated `knowledge-base/INDEX.md`, and the compound learning.

### Post-merge (automated in soleur:ship / postmerge; no operator step)

- [ ] **AC13** The merge fires the push-triggered `apply-web-platform-infra.yml`, because the edited suites live under `apps/web-platform/infra/**`. That run, for the merge SHA, concludes `success`: `gh run list --workflow apply-web-platform-infra.yml --event push --json headSha,conclusion`. Recent push applies that touched the same test file (#8759) concluded `success`.
- [ ] **AC14** Deterministic contaminated-window check (CTO #1):
  1. After merge, read Better Stack with `--since 3h --grep SOLEUR_INNGEST_SERVER_PROBE --limit 500`, and wait until the **newest** `soleur-inngest` row in the window has emitter `doppler`. This PR's own merge `closed` webhook quotes the marker and normally supplies that row. Poll with a Monitor until-loop bounded at 30 minutes.
  2. Run `gh workflow run scheduled-inngest-health.yml`.
  3. That run's log line `#7674 dedicated host:` ends `-> healthy`.
  4. Its `rows=` equals the number of rows the lib's own selector returns over the same read.
- [ ] **AC15** The open false pair (#8862/#8863, or whichever pair is open at merge) is closed by a healthy tick. Then, for 2 consecutive scheduled ticks, no new `[ci/inngest-dedicated-host] Dedicated inngest host is not serving` or `[ci/inngest-no-live-scheduler]` issue is filed. Wait with a Monitor until-loop bounded at 90 minutes (`hr-monitor-not-run-in-background-for-polling`). **If a new pair is filed, reopen #8846 with the run URL.**
- [ ] **AC16** #8833 and #8834 each get one evidence comment and stay closed. Each comment states:
  - the issue was a false positive, with the root cause (substring selection);
  - the live row breakdown;
  - the fixing PR;
  - the AC14 run URL and verdict;
  - the sibling pairs from the same loop.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed (planner + advisor consult + plan-review panel incl. CTO devex lens)
**Assessment:** This changes internal observability and gate machinery.

- No new infrastructure, store or connection, and no Terraform, so Phases 2.8 and 2.11 skip. The `.tf` alert is deferred to #8874.
- No architectural decision: this applies the existing `_erg_hb_newest` emitter-check precedent to its siblings, so ADR/C4 (Phase 2.10) skips.
- The GDPR gate skips: no regulated-data surface, and the rows are already ingested.
- No UI surface, so the Product/UX tier is NONE.

## Test Scenarios

- Given a healthy dedicated host and an event-log row quoting the marker as the newest row, when the watchdog runs, then the verdict is `healthy` and no host issue is filed.
- Given a real probe row that is not serving and an event-log row quoting a serving line, when 7674 runs, then it exits 2 with `not_serving`, never PASS.
- Given only event-log rows under `--grep inngest-cutover-flip`, when op=resume's G3 counts liveness, then the count is 0 and G3 refuses.
- Given the shared lib is missing, when any consumer runs, then it takes its selector-unavailable arm. It never reports healthy, PASS or `dark`, and the watchdog files the consumer-broken issue, not a host outage.
- Regression: every existing case in the 7 suites stays green, using the builders' emitter defaults and the edited `R_*` literals.

## Risks & Sharp Edges

- **Test sandboxes that copy a SUT.** The classify test (`$ws/scripts/`), the 8296 test (`$WORK/root/scripts/followthroughs/`) and the dark-gate mutation battery (`$TMP/mut-*.sh`) must all see the lib, either by copying it or through `INNGEST_PROBE_ROW_LIB`. Otherwise every case silently exercises the selector-failure path, and the dark-gate battery would score **vacuous kills**. The canary row guards that. Before assuming there are no other copies, grep every Phase 1 suite for `cp "` and `mktemp -d`.
- **Seams that run copies of the SUT.** 7761's `FLIP_ROLLOUT_TEST_TARGET` and the dark-gate `mutate()` both do this. Each needs `INNGEST_PROBE_ROW_LIB` exported by its suite. A copy that cannot find the lib reads `row_decode_failed` or `unreadable` on every case. The dark-gate canary catches this, and the 7761 derive cases name their competing reasons. `apps/web-platform/infra/inngest-host-state-workflow-guard.test.sh` writes a **stub** `inngest-host-state.sh`, not a copy, so it is unaffected (verify-the-negative #7).
- **Assertion floors.** Every suite in the Phase 1 table carries a count floor, some exact (`-ne`) and some minimum (`-lt`). Update them in the same commit as the new cases.
- **Top-level fixture construction under `set -euo pipefail`** in `cutover-inngest-workflow.test.sh`. Never use `${VAR:?}` in a builder that runs at load time.
- **`set -e` in `cutover-inngest.sh`.** The liveness functions keep "always return 0, print the token".
- **jq 1.7 on runners, 1.8 locally.** The def uses only constructs that exist since jq 1.5. CI runs the suites on the runner's jq.
- **This PR's own body quotes the marker.** Every push emits `synchronize` rows. That is harmless after merge, and AC14 uses them deliberately.
- **Merging triggers the web-platform push apply** (AC13). It is routine for `apps/web-platform/infra/**` test edits, and the diff has no `.tf` change.
- `## User-Brand Impact` is filled in. `deepen-plan` Phase 4.6 halts on an empty one.

## Plan Review Revisions

Panel: DHH, Kieran, code-simplicity, and CTO (devex lens).

**Applied as Mechanical:**

- Kieran P0 #1: lib path override plus a canary, so the dark-gate mutation battery cannot score vacuous kills.
- Kieran #2: the 8296 sandbox copies the lib.
- Kieran #3: liveness fixtures built per tag, not through a load-time `${LV_TAG:?}`; `FIX_REORDER` gains the emitter.
- Kieran #4: word-boundary SOURCED rule.
- Kieran #5: 6894 is retired, so no harness.
- Kieran #6 and simplicity: no `run_suite` line; the glob registers the suite.
- Kieran #7: pull_request `paths:` only.
- Kieran #8: exact fixture messages per suite; (a) where substring, (b) where anchored.
- Kieran #9: `R_*` literals are edited, and `run_arm` returns the exit code and detail.
- Kieran #10: AC6 re-expressed.
- Kieran #11 and DHH #4: def built from the variables.
- Kieran #12: tag validation with its own warning; repo-wide caller census.
- DHH #1 and simplicity: no runtime self-test in consumers; source guards plus jq exit code instead.
- DHH #2 and simplicity: a single census rule, no set identity.
- DHH #3 and simplicity: forged (b) only in anchored consumers; positional rows cut.
- DHH #5: the tag check is non-empty only.
- DHH #6 and simplicity: no saturation branch; `returned=<n>/500` instead.
- DHH #7: matrices trimmed to rows the fixture table does not already cover.
- CTO #1: deterministic AC14.
- CTO #2: bounded AC15 with a failure action.
- CTO #3: AC13 for the push apply; #8831's file list read live.
- CTO #4: class-wide guard filed as #8875.
- CTO #6: both source spellings, plus a must-PASS row.
- CTO #7: selector failure goes to the existing consumer-broken step.
- CTO #8: refusals name the lib path.

**Not applied:**

- DHH #8 (move the 6894 harness into its own suite): moot, since 6894 is retired and gets no harness.
- DHH #9 (drop the AC16 comments): not applied. The operator explicitly asked to close #8833/#8834 as false positives with evidence. The comment is kept, and made concise.
- CTO #5 (rename the lib for the class): recorded as Taste in `decision-challenges.md`, and folded into #8875.
