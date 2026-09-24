---
title: "fix(7761): give the flip-rollout follow-through probe a post-cutover answer key"
date: 2026-09-24
slug: fix-7761-flip-rollout-probe-post-cutover-answer-key
branch: feat-one-shot-7761-flip-probe-post-cutover-answer-key
issue: 7761
closes: none  # Ref #7761 only — the follow-through sweeper closes it on a live PASS
type: bug
priority: p1
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix(7761): give the flip-rollout follow-through probe a post-cutover answer key

> Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-09-24. The plan went v1 → v2 (plan-time domain review) → v3 (four-seat plan
review, cuts) → v4 (this deepen pass).

**Agents:**
- **Plan-time:** repo-research-analyst, learnings-researcher, functional-discovery, CTO,
  spec-flow-analyzer, and a scoped advisor consult.
- **Plan-review:** DHH, Kieran, code-simplicity, and CTO (devex).
- **Deepen:** test-design-reviewer, security-sentinel, observability-coverage-reviewer,
  architecture-strategist, git-history-analyzer, and a verify-the-negative sweep.

### Key improvements (v4)

1. **Tag isolation.** The LUKS cutover FSM (`inngest-luks-cutover.sh` `emit_noop`) runs on the
   **same host** and emits the same `noop-*` reasons. Drift rows are now field-isolated on
   `SYSLOG_IDENTIFIER == inngest-cutover-flip` (F28). Without this, a LUKS `noop-aborted` would
   have read as flip drift.
2. **Public-comment hygiene.** Everything the probe prints lands in a public #7761 comment.
   - Findings are sanitised: `noop-unset` and `unexpected-exit(from=…)` embed the raw flag value.
   - `_mid` is truncated.
   - Output is capped at 20 rows.
   - The sidecar refuses symlinks and never echoes its value (F31–F33, F37).
3. **The sidecar cannot erase drift.** The boundary must precede the owning machine's first row
   (F29), so moving the sidecar past a drift event on the current machine is refused.
4. **Stuck non-verdicts age out.** Read-path TRANSIENTs exit 3 (CANNOT ESTABLISH) once a supplied
   boundary is over 7 days old (F34), instead of reading NOT YET forever.
5. **The harness cannot be vacuous.** Four self-checks: OR, newest-N order, `--since` shape, and
   quoted-term matching. Every fixture asserts its token anchored, with a negative assertion on the
   competing token. The mutation battery runs on copies, and a mutation counts only when the named
   fixture's own `FAIL:` line appears. F12b is repaired: string-shaped JSON rows now carry `_mid`.
6. **CI coverage.** The probe path is added to `infra-validation.yml` `paths` and to
   `test-affected-paths.sh`. Without that, a probe-only PR would skip the parity guard (#8079
   class).

### New considerations discovered

- Measured: ClickHouse session timezone is `UTC`. The off-flag greps return 0 rows since the
  boundary across all hosts and tags.
- **Attribution corrections:**
  - The derived-boundary arm and `TERMINAL_SAFE_FLAGS` shipped in PR #7887 (commit `235693e411`).
    #7695 is the **issue**, now closed.
  - The `#6178 EMITTER PARITY` block was introduced by PR #7647. `#6178` is its in-code label.
- Every call site of `betterstack-query.sh` passes `Nh`/`Nm`/`Nd` or a `%F %T` built with
  `date -u`. The ISO normalisation breaks no caller.

## Overview

The follow-through probe for #7761 (`scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh`)
was written while the dedicated Inngest host sat braked in a pre-cutover terminal state
(`rolled-back` / `aborted`). The cutover has since completed, so the host's legitimate steady state
is `done`. The probe cannot PASS today, and the tracker it gates (a P1 security issue) can never
close.

Measuring the live data for this plan found **two independent defects, not one**. Either alone
yields the observed `count=0`:

1. **The answer key is stale (the reported defect).** `TERMINAL_SAFE_FLAGS='["rolled-back","aborted"]'`
   excludes every `noop-done` row, the header calls `done` a condemnation, and the drift arm's
   `grep -qE 'flag=(flipping|flushed|done)'` would condemn the correct state.
2. **The probe has never decoded a live emit_state row (found here).** In the Better Stack
   warehouse the flip FSM's `message` is a parsed JSON **object** inside `raw`, not a JSON string.
   `mine()` emits it with `jq -r`, which pretty-prints an object over several lines. The downstream
   `fromjson?` then fails on every line. So `post_ok`, `post_oldrev`, the drift selector and the
   `armed` selector all read zero rows from real data, whatever the flag. The suite never noticed
   because its `row()` fixture builds `message` as a string. Measured: 2,743 of 2,743 emit_state rows
   in a 30h sample were object-shaped. A scratch run of the **unmodified** probe on the same two
   `noop-rolled-back` rows returned `PASS` in the string shape and `TRANSIENT count=0` in the live
   object shape.

A third, lower-severity defect in the same arm: the "24h" drift query greps the syslog tag with
`--limit 500`. The tag emits about 274 rows/hour, counting the Doppler stderr lines. Measured live,
the query covers **05:41→07:33 UTC, about 1.9h**, not 24h. The drift horizon the header states is
false.

This plan does four things:
- re-keys the probe for the post-cutover world, where the only PASSable state is `done` that the
  FSM re-earned on **this machine** after the boundary (D1, D3);
- fixes the shared reader, `betterstack-query.sh`, so it accepts an ISO `--since` (D5);
- fixes the decoder;
- redefines drift as positively observed FSM state changes over the whole since-boundary interval
  (D2);
- commits the authoritative boundary, so the sweeper reaches a real verdict (D4).

The answer key stays inline, never environment-supplied.

## Research Reconciliation — Spec vs. Codebase

| Claim (task brief / probe header) | Reality (measured 2026-09-24) | Plan response |
|---|---|---|
| "`FLIP_ROLLOUT_AFTER=…` → FAIL count=0 because TERMINAL_SAFE_FLAGS filters out noop-done" | True but incomplete. `mine()` also drops every object-shaped `message`. Fixing only the flag set still gives `count=0` live. | Fix both (Phase 1.1 decoder + Phase 1.2 key). RED fixtures use the live object shape. |
| Header: drift runs "over the WIDER window with its own narrow greps, so the limit is not binding" | The drift query greps the broad tag, not a narrow term. `--limit 500` binds, and the horizon is about 1.9h. | Replace it with a since-boundary transition query using narrow OR-greps (sparse, so the whole interval fits in one page), plus a truncation guard. |
| Test fixtures `row armed noop-armed`, `row flushed flip-flushed`, `row flipping …` | `emit_state` writes the **post-run** flag. `armed`, `flipping` and `flushed` never appear in a row's `flag` field. They show up only in outcome **reasons** (`flip-complete`, `refuse-rearm-after-done`, `flushed-resume-no-reflush`, …). Only `noop-unset` can carry a non-enum flag. | Keep the flag-based arms as defence in depth (the task explicitly requires the "mixed flipping rows" fixture). Add **reason-based** detection for the real vocabulary. The plan says openly that the flag-shaped fixtures model rows the current emitter does not produce. |
| Code comment at `AFTER_FILE`: "absent and untracked by design" vs header "else the committed `.after` sidecar" | The file is internally contradictory, and no `.after` has ever existed. | Commit the sidecar (Phase 2) and fix both comments. |
| Brief: `FLIP_ROLLOUT_AFTER=2026-09-23T19:36:32Z` is the natural `--since` for a since-boundary query | `betterstack-query.sh --since <ISO>` exits **rc 22** (curl 400); only `YYYY-MM-DD HH:MM:SS` works (measured) | Normalise with `date -u -d "$AFTER" '+%F %T'`; the stub rejects any other shape (D5) |
| Implicit: one replace, one resume | 30d history holds five done-entries on five machines (`flip-complete` 09-15, resumes 09-17/09-20/09-22/09-23) — replaces are routine | Ownership bound to `_MACHINE_ID`, not hostname (D3) |
| #7761 delivered by the 2026-09-23T19:36:32Z replace | The replaced boot `113ad362` was **already** stamping `guard:"7761"` (since at least 01:31Z on 09-23). The 19:36 replace kept the same digest (`sha256:e773fe5c…`). | The boundary still correctly identifies the host being measured, and delivery is proven by the guard stamp on that host's rows. The PR body states that the fix was delivered earlier. |

## Research Insights

**Premise Validation.**
- #7761 is OPEN, labels `priority/p1-high`, `type/bug`, `follow-through`. The directive is `script=…7761.sh earliest=2026-09-05 secrets=BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}`.
- Predecessor PRs #7768 and #7887 are merged. No open PR touches these files.
- Cited runs verified with `gh run view`:
  - apply 35910239344 job `inngest_host_replace` completed `2026-09-23T19:36:32Z`.
  - cutover 35910761741 (`op=resume`) ran 19:39:17Z → 19:42:32Z.
- Live rows (`betterstack-query.sh --since 30h --grep inngest-cutover-flip --limit 10000`, 8,240 rows):
  - Old boot `113ad362`: last row 19:35:23Z.
  - New boot `c127d0a4`: first row `start_ts` 19:37:57Z (`noop-done`, the inherited `done`; the flip guard refused the start). Then one `{"reason":"flushed-resume-no-reflush","flag":"done","guard":"7761","start_ts":"2026-09-23T19:42:45Z"}`, then `noop-done` every 30s.
  - The boundary `2026-09-23T19:36:32Z` cleanly separates the two boots' evidence.
- Hourly `SOLEUR_INNGEST_SERVER_PROBE` rows since the boundary read `http_code=200 server_active=active cutover_flag=done host_role=dedicated flush_latched=true`. This corroborates the conclusion; the plan does not add it as a mechanism (see Cut List).
- Both `--grep` forms match live: `'"reason":"flushed-resume-no-reflush"'` and the bare token each return 1 row since the boundary. The quoted form matches because `message` is an object inside `raw`.
- Running the current probe live:
  - Derived boundary: `TRANSIENT derived_boundary_stale_supply_authoritative_boundary`. The derived boundary is `2026-09-23T08:19:11Z`, on the **old** host, because that host already carried the pinned digest.
  - Supplied boundary: `FAIL insufficient_post_replace_markers_past_deadline count=0`.

**Property List (Phase 0.6b).**
- P1 (delivery): post-boundary rows from the host carry `guard=7761`. Rows without the stamp are a stale image.
- P2 (liveness): at least 2 post-boundary noop markers, so the 30s timer is cycling.
- P3 (no seam refusal): zero `SOLEUR_INNGEST_CUTOVER_SEAM_REFUSED` rows.
- P4 (done provenance): `done` counts only when the FSM re-earned it on this **machine** after the boundary, through the op=resume arm (`flushed-resume-no-reflush`). Rows emitted under an inherited `done` never count, and a resting `rolled-back`/`aborted` never PASSes post-cutover.
- P5 (no drift): between the boundary and now, this host emitted no FSM row other than the resume shape and its `noop-done` heartbeat.
- P6 (sweeper reaches a verdict): the probe has an authoritative boundary on the sweeper's channel, which has no env override.
- P7 (the key is not env-supplied): every answer-key member is an inline literal.
- P8 (the decoder reads what the warehouse returns): rows count in both `message` shapes (object and string).

**Cut List (Phase 0.6b).**
- Corroborating `done` from `SOLEUR_INNGEST_SERVER_PROBE` (`server_active=active cutover_flag=done`) → buys P4 → cut. The FSM's own `flushed-resume-no-reflush` row is the direct provenance the task names. A `INNGEST_DIAGNOSTIC_BOOT=1` start makes `server_active=active` a weaker signal.
- Reading `flush_latched=` from the server probe → buys "the latch is intact" → cut. It is not asked for, and P5's reason-based drift already observes the latch's guarantee.
- Doppler-flag-equals-steady-flag cross-check → buys a slice of P5 → cut. The Doppler arm is inert in the sweeper (no Doppler token), and the since-boundary query covers P5.
- Making `FLIP_ROLLOUT_HOST` / `_TAG` / `_STALE_AFTER_S` inline → cut. These are selectors or a deadline, not answer-key members. `STALE_AFTER_S` can only move FAIL↔TRANSIENT, never manufacture a PASS. They stay as test seams. `FLIP_ROLLOUT_EXPECTED_GUARD` is **not** cut: the guard is the P1 answer key, so P7 requires it inline.
- Retiring the dead `cutover_armed` arm (it keys on a flag value the emitter never writes) → cut from this PR. It is uncapped and harmless, and pinned by tests 7/D8. The plan records the finding instead.

- (v3, plan review) the v2 LIVE∪drift union, the STEADY-dependent grep set, the 3-tier severity ordering, `flag_changed`, `transition_row_unplaceable`, `steady_state_not_post_cutover`, `flag_in_flight`, the file-based page-count side channel, a duplicated parity extraction, and a copy-of-the-probe R3-M20 fixture → all cut; see `## Plan Review Disposition`.

**Relevant files.**
- Probe answer key: the `TERMINAL_SAFE_FLAGS=` / `EXPECTED_GUARD=` block.
- `mine()`: the `.message? // empty` selector.
- Drift arm: `DRIFT_ROWS="$(mine "$DRIFT_WINDOW" "$TAG")"`.
- Emitter vocabulary: `apps/web-platform/infra/inngest-cutover-flip.sh` (`run_flip()` case arms, `run_preflush_flip()`, `refuse_rearm_after_done()`, `verify_or_abort()`, `on_unexpected_exit()`).
- Canonical transition-reason OR-grep set, live-proven: `scripts/cutover-inngest.sh` `_flip_transition_dt()`.
- Its emitter-parity test: `apps/web-platform/infra/cutover-inngest-workflow.test.sh` (`#6178 EMITTER PARITY` block). Precedent for extraction and the negative control.
- Flip guard (why an inherited `done` never serves): `apps/web-platform/infra/inngest-server-flip-guard.sh` (`#7228 (3.7)` block).
- Sidecar lint coupling: `scripts/lint-followthrough-varq-ban.test.sh` R3-M20 binds its inverse to the 7761 probe's `# repo-path: runtime` annotation (its only live user). The suite floor is `MIN_ASSERTIONS=80`.
- Sweeper contract (`scripts/sweep-followthroughs.sh`):
  - runs probes from the repo root under `env -i` with only the directive's secrets;
  - exit 0 → comment + close; exit 1 → comment, leave open; other exits → comment (TRANSIENT);
  - it does not read sidecars itself.

**Institutional learnings applied.**
- `2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire.md` and `2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md`: fixtures must model the real warehouse shape. That is exactly defect 2.
- `2026-08-04-my-probe-passed-against-the-outage-it-was-built-to-detect.md`: ask "what would this report if the thing it verifies never happened?" An inherited, never-resumed `done` must not PASS, which motivates P4.
- `2026-09-20-my-probe-graded-itself-against-a-clock-its-grader-never-read.md`: the authority must live on the channel the grader reads, which motivates P6 and the committed sidecar.
- `2026-09-23-the-prose-stated-the-property-and-the-predicate-checked-a-subset.md`: ClickHouse `LIKE` treats `_` as a wildcard, and prose-vs-predicate subset checks matter. The new grep terms contain no `_`. The header's "24h drift" prose was the subset defect.
- `2026-05-04-vacuous-red-via-shared-fixture-and-toolchain-pinning.md`: each RED fixture must force its own branch.
- `2026-05-22-parity-tests-must-include-boundary-adjacent-fixtures.md`: parity needs a negative control.

**Plan-time review findings (folded into v2).**
- CTO (engineering domain leader):
  - ownership must bind to the machine, not the hostname (D3);
  - `--since` must use the `%F %T` form, which we then measured: ISO gives rc 22 (D5);
  - verify that archive rows match the quoted greps. Measured: rows back to 09-15 match;
  - the truncation guard must run before the ownership verdicts;
  - the refusal horizon must be at least since-boundary;
  - retract the "`cutover_armed` is the FLUSHALL alarm" claim.
- SpecFlow (13 gaps), folded into v2. The v3 plan review then **superseded** several of those fixes by deletion: the severity order, the empty-`STEADY` handling, `flag_in_flight` and the unknown-`start_ts` verdict are gone (see `## Plan Review Disposition`). Machine binding, flush-path-over-`stale_image`, the raw page count, the `--since` shape and "a resting `aborted` is not a PASS" all stand.
  - one reason-first classifier with a severity order;
  - an empty `STEADY` is defined;
  - flush-path outranks `stale_image`;
  - uncapped alarms run before any exit 2;
  - the truncation guard uses the raw page count;
  - `--since` shape is enforced;
  - a resting `aborted` post-cutover is not a PASS (D1);
  - machine binding;
  - a remediation message for a failed-then-fixed resume;
  - Doppler `flushed` gives `flag_in_flight`;
  - an unknown `start_ts` in LIVE.
- Advisor (scoped consult, ADR-083):
  - the riskiest phase is stub fidelity, so Phase 0.0 adds a live precondition run of the exact
    query;
  - unknown reasons fail safe to drift at runtime. This is only partly achievable, and D2's residuals say so: since the boundary, the parity test is the guard, not the runtime;
  - document the sidecar lifecycle (D4).

**Conventions.** Rule IDs cited: `cq-write-failing-tests-before` (RED first), `hr-no-ssh-fallback-in-runbooks`, `hr-no-dashboard-eyeball-pull-data-yourself` (every number above was self-pulled), `wg-use-closes-n-in-pr-body-not-title-to` (`Ref #7761`, never a closing keyword).

## Design Decision — the post-cutover answer key and how drift is defined now

*(v3, after a four-seat plan review: DHH, Kieran, code-simplicity, CTO. When both the
simplification and correctness panels flagged the same mechanism, it was deleted rather than
fixed. The ledger is in `## Plan Review Disposition`.)*

### D1. Only FSM-owned `done` passes

The cutover is permanent:
- The monotonic flush latch lives on `/mnt/data` and survives every replace.
- G3.7 refuses op=arm whenever a FLUSHALL is on record.
- The host reports `flush_latched=true`.

So the answer key has exactly one PASSable state, `done`. A `done` counts only when **this machine**
re-earned it after the boundary (D3).

A post-boundary `noop-rolled-back` or `noop-aborted` row is drift (D2), and drift is a FAIL. A host
resting in either state after the cutover is a dark scheduler. It must never read PASS, and it
must not read TRANSIENT forever either. That was the CTO's escalation point, and it removes the
v2 `steady_state_not_post_cutover` verdict. This inverts existing fixture D7 (`aborted` → PASS)
on purpose.

### D2. Drift: any non-exempt FSM row since the boundary, from ONE sparse query

**Source.** One query, and only one:
`mine "$AFTER" "$DRIFT_LIMIT" "${DRIFT_GREPS[@]}"`, where `--since` is the boundary.
`betterstack-query.sh` now normalises ISO itself (D5).

`DRIFT_GREPS` is a **fixed** inline set:
- the 13 non-noop emitter reasons, as `'"reason":"<r>'`;
- `'"reason":"noop-unset"'`, `'"reason":"noop-rolled-back"'` and `'"reason":"noop-aborted"'`;
- `'"flag":"flipping"'` and `'"flag":"flushed"'`.

`noop-done` is deliberately **not** grepped. It is the steady heartbeat, so a healthy host returns
only its resume row(s). Measured live: exactly 1 row since the boundary.

**Filter.** A returned row is considered only if all of these hold:
- it is from this host (both identity fields);
- **its `SYSLOG_IDENTIFIER` is `inngest-cutover-flip`** (deepen: the LUKS cutover FSM, `inngest-luks-cutover.sh` `emit_noop`, runs on the **same host** and emits the same `noop-done`/`noop-rolled-back`/`noop-aborted`/`noop-unset` reasons. Without tag isolation, a LUKS `noop-aborted` reads as flip drift. `mine()` field-isolates the tag for every emit_state query. This is the `2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md` class);
- it decodes;
- its `start_ts` is ISO-shaped and `> AFTER` (Kieran 9: the stub ignores `--since`, and warehouse
  `dt` and `start_ts` can differ by seconds).

A drift row with a non-ISO `start_ts` is treated as a finding, not dropped. The query already
placed it after the boundary, and silently dropping a FAIL-direction row is the unsafe choice. An
`R` with a non-ISO `start_ts` is exempt, because it is not a finding, but it can never **own**
`done`. That is fixture F30.

**Exemption.** One row shape only: `reason == "flushed-resume-no-reflush"` with `flag == "done"`.
It is **not** conditioned on guard or machine; those are ownership questions (D3). This is Kieran
P0-1: conditioning the exemption on guard/`_mid` turned an unowned resume into a drift FAIL.

**Findings.** Every other considered row is a finding, and all findings are printed. The verdict is:
- `flush_path_transition_after_replace` ("the latch guarantee is broken"), if any finding has a
  reason in `FLUSH_PATH_REASONS = {flip-complete, flushall-failed, dbsize-nonzero}` **or** a flag in
  `FLUSH_PATH_FLAGS = {flipping, flushed}`. A row's class is the maximum over its reason and its
  flag (Kieran 8).
- `drift_after_replace` otherwise.

Both go through `verdict_fail`, because they are boundary-dependent. The findings arm runs before
`stale_image`, so a FLUSHALL is never masked by a missing guard stamp (SpecFlow 5).

**What a finding prints (deepen: security).** Everything printed ends up in a PUBLIC #7761 comment,
and runner masking does not apply there.
- `.flag` goes through `_flag_for_display`.
- `.reason` is printed only when it is a known emitter literal. `unexpected-exit(from=<x>)` keeps
  its prefix, and `<x>` goes through `_flag_for_display`. Anything else prints as
  `<non-enum reason, N chars>`. The reason is that `noop-unset` and `unexpected-exit(from=…)` embed
  the raw `INNGEST_CUTOVER_FLIP` value (fixture F31).
- `_mid` prints as an 8-hex prefix only. machine-id(5) calls the full value confidential.
- At most 20 rows print, followed by `(+N more)`. The sweeper keeps only the last 4000 bytes, so a
  longer list would push the `FAIL: reason=` line out of the comment. For the same reason, the
  `FAIL: reason=` line is printed **last** as well as first.

**Truncation.** Findings are positive observations, so they are valid on a truncated page. Only the
**absence** conclusions need a complete page: "no drift" and "no owning resume". So:
- findings → FAIL, even when the page is full;
- no findings and a full raw page → `TRANSIENT drift_query_truncated`, evaluated before ownership.
  A newest-first page drops the oldest row first, and the resume row is among the oldest (CTO);
- `mine()` reports "page full" as a trailing `__PAGE_FULL__` sentinel line, counted on the
  **pre-host-filter** page. It does not use a side-channel file (code-simplicity). Rows from
  another host can fill the page (SpecFlow 7).

**Why this definition.**
- *"A transition INTO flipping/flushed"* cannot be observed directly. Across the 20 `emit_state`
  calls the emitted flags are only `aborted`, `done`, `rolled-back` and `${flag:-unset}`, so the
  transition exists only as its outcome reason. The `flipping`/`flushed` flag greps stay because
  the task requires the "mixed flipping rows" fixture. They are commented inline as unreachable
  from today's emitter (CTO 11).
- *"Flag changes across the window"* is covered: the off-flag `noop-*` greps see a change over the
  whole since-boundary interval, not just the newest 500 rows.
- *"Presence of `done`"* made the probe unpassable. Adding `done` naively is unsafe the other way:
  a replaced host emits `noop-done` under an **inherited** `done` until op=resume runs, and that is
  handled by D3.
- **Stated residuals.**
  - A future emitter reason is not grepped, so it is invisible since the boundary. The runtime
    does not fail safe on it. The **parity test** (Phase 0.4) is the guard: it reds as soon as the
    emitter gains a reason the probe does not grep (DHH 3).
  - A transition row whose `message` reached the warehouse as a string would not match the quoted
    greps. Measured: 0 of 2,743.
  - After a long `aborted` rest, the `noop-aborted` rows could fill the page. That still reads
    FAIL, because a finding is present (Kieran 10 resolved by the findings-first order).

### D3. `done` ownership is bound to the MACHINE

The done-owner marker `/var/lib/inngest-cutover/done-owner` is on the root disk. It survives a
reboot and is destroyed by a replace. The hostname survives a replace. The row's journald
`_MACHINE_ID` has the marker's exact lifetime: it is present on 2,743 of 2,743 rows, and it changed
at the replace (`33c4d89f…` → `3cff04d3…`).

Replaces are routine. The last 30 days hold five done-entries on five machines: `flip-complete` on
09-15, then resumes on 09-17, 09-20, 09-22 and 09-23.

- `M` = the `_mid` of the newest post-boundary, guard-stamped `noop-done` row in LIVE (by
  `start_ts`).
- `done` is **owned** iff at least one exempt drift row has `guard == 7761` and `_mid == M`, where
  `M` is non-empty.
- `OWNED_SINCE` = the earliest such row's `start_ts`. A second resume on the same machine is
  harmless (F26).
- `post_ok` counts LIVE `noop-done` rows that are guard-stamped, have `_mid == M`, and have
  `start_ts > OWNED_SINCE`.
- Not owned → `done_not_resumed`:
  - TRANSIENT while the boundary is fresh;
  - past `STALE_AFTER_S` it becomes `done_not_resumed_past_deadline` via `verdict_fail`;
  - the message prints the boundary it used, names `cutover-inngest.yml op=resume`, and says "if
    the host was replaced after `<AFTER>`, the sidecar must move" (CTO 8).
- No stamped `noop-done` in LIVE at all → the existing insufficient-markers arms.
- **`stale_image` is computed before ownership, from raw stamping (deepen: test-design 11).**
  `post_stamped` counts post-boundary flip-tag `noop-done` rows that carry the guard, with no
  ownership condition. `post_oldrev` counts the same rows without the guard. `stale_image` fires iff
  `post_oldrev > 0 && post_stamped == 0`. So F16 (unstamped `R`, stamped noops) reaches ownership
  and reads `done_not_resumed`.
- **The boundary must precede machine `M`'s first row (deepen: security 3).** Moving the sidecar
  forward past a drift event would otherwise erase it, a false PASS on a P1 tracker. One bounded
  query checks this: `--since <AFTER − 1h> --until <AFTER> --grep inngest-cutover-flip`. If any
  flip-tag row in `[AFTER − 1h, AFTER]` has `_mid == M`, the verdict is
  `TRANSIENT boundary_inside_owning_machine_lifetime`, and it never PASSes.
  - A legitimate boundary (a real replace time) always precedes the new machine's first row. On
    09-23 the replace was at 19:36:32 and the first row at 19:37:57.
  - Drift on the **current** machine therefore cannot be erased by editing the sidecar. Moving the
    sidecar re-certifies only a **new** machine, so the v3 advice "re-certify a remediated transition
    by moving the sidecar" is withdrawn (fixture F29).
  - A drift remediation on the same machine needs human review, not a sidecar edit. The verdict
    table says so.

### D4. Boundary: the committed sidecar

Commit `scripts/followthroughs/inngest-cutover-flip-rollout-7761.after` containing
`2026-09-23T19:36:32Z`. The reasons:
- The derived boundary lands at `08:19:11Z`, on the **old** machine.
- It slides with its 24h derivation window. Once it passes the 19:42:45Z resume, D3 can never be
  satisfied, so the probe reads TRANSIENT forever.
- The sweeper runs probes under `env -i`, so `FLIP_ROLLOUT_AFTER` never reaches it. A committed file
  does.

The header already names the committed sidecar as the second boundary source, so no new mechanism
is involved.

**Sidecar read hardening (deepen: security 2).**
- `[[ -L "$AFTER_FILE" ]]` → `TRANSIENT sidecar_is_symlink`.
- A read over 64 bytes → `TRANSIENT sidecar_oversize`.
- `boundary_unparseable` prints only the value's **length**, never its contents. Today it echoes
  `value='${AFTER}'` into a public comment, so a symlink to `/proc/self/environ` would publish
  `BETTERSTACK_QUERY_PASSWORD` (fixtures F32, F33).
- AC6 requires git mode `100644`.

**Lifecycle.** The sidecar belongs to #7761 and retires with the probe; the first PASS closes the
issue, and the sweeper stops running it. If the host is replaced while #7761 is still open, the
sidecar must move. The probe comment and the `done_not_resumed` message both say so.

The derived-boundary arm stays, unchanged apart from its window default. It is the fallback if the
sidecar is ever removed. Deleting it (DHH 6) is recorded as a Taste decision that is **not
applied**; see the disposition section.

### D4b. A non-verdict that persists is not "not yet" (deepen: observability P1)

The read-path non-verdicts (`drift_query_truncated`, `refusals_query_failed`, `query_failed`,
`row_decode_failed`, `drift_query_failed`) exit 2 today. The sweeper renders exit 2 as
**NOT YET**, every day, forever. That is the state this plan exists to end.

Once the supplied boundary is older than **7 days**, those non-verdicts exit **3** instead. The
sweeper renders exit 3 as **CANNOT ESTABLISH**, and the probe names what to fix. A derived boundary
keeps exit 2: an inferred boundary's age proves nothing.

`credentials_unprovisioned` keeps exit 2, because that one is an environment fact.

This uses the sweeper's existing vocabulary; no sweeper change is needed. The P1 tracker already
carries `needs-attention`. Fixture F34.

### D5. Measured query facts (these bind the implementation)

- **ISO `--since` fails today.** `betterstack-query.sh --since 2026-09-23T19:36:32Z` exits **rc 22**
  (curl 400). The `%F %T` form exits 0. The fix goes **at the source**, as the CTO recommended:
  - `betterstack-query.sh` normalises a `^YYYY-MM-DDTHH:MM:SSZ$` value to `YYYY-MM-DD HH:MM:SS`
    for both `--since` and `--until`;
  - a hermetic SQL-capture assertion is added to `tests/scripts/test-betterstack-query-archive.sh`;
  - the usage header already advertises `ISO`, so this makes the documentation true instead of
    teaching every probe the workaround.
- **Archive rows match the quoted greps.** A `--since 30d` query returned object-shaped transition
  rows back to 09-15, past the roughly 3-day hot window.
- **ClickHouse session timezone is UTC** (measured: `SELECT timezone()` → `UTC`), so dropping
  the `Z` in the `%F %T` form keeps UTC semantics (deepen: security 6).
- **The off-flag greps match nothing live since the boundary, across all hosts and tags**
  (measured: `noop-aborted`/`noop-rolled-back`/`noop-unset`/`flag:flipping`/`flag:flushed` since
  `2026-09-23 19:36:32` → 0 rows). The page cannot be flooded today.
- **`DRIFT_LIMIT` default 5000.** The measured healthy page is 1 row. 5000 leaves about 1.7 days of
  headroom even for a flood of 2,880 rows/day, and past that point findings already FAIL (D2).
  `FLIP_ROLLOUT_DRIFT_LIMIT` is a test seam. It must match `^[1-9][0-9]{0,5}$`; a leading zero is
  refused (deepen: security 7). Bash `-eq` on `08` errors and would silently skip the page-full
  check. It is not an answer-key member: shrinking
  it can only produce TRANSIENT, and growing it only makes the page more complete.

## Implementation Phases

### Phase 0 — RED (`inngest-cutover-flip-rollout-7761.test.sh`, `tests/scripts/test-betterstack-query-archive.sh`, `apps/web-platform/infra/cutover-inngest-workflow.test.sh`)

- 0.0 **Live precondition (read-only; advisor).** Run the exact `DRIFT_GREPS` query with
  `--since '2026-09-23 19:36:32' --limit 5000`. Expect 1 row: the 19:42:45Z resume, object-shaped,
  `_MACHINE_ID 3cff04d3…`, exit 0. Confirm the ISO form exits 22 against **unmodified**
  `betterstack-query.sh`. Record both results for the PR body. No live row is committed as a
  fixture (`cq-test-fixtures-synthesized-only`).
- 0.1 **Fixture shape.**
  - `row()` defaults to the live **object** shape and attaches `_MACHINE_ID` (default `MID_A`,
    overridable). `row_str()` produces the legacy string shape.
  - Large fixtures are generated in **one** `jq -n` range (CTO 10). They use strictly increasing,
    distinct `start_ts`, with the boundary moved to about -40 minutes for those fixtures (Kieran 14).
  - **One anchor epoch** `NOW` is captured once at suite start. Every timestamp derives from it: for
    the 600-row fixtures, AFTER=NOW−2700, R=NOW−2640, and noop *i* at NOW−2600+4*i*. A self-check
    asserts every value is distinct and inside (AFTER, NOW].
  - `run_probe` passes `FLIP_ROLLOUT_STALE_AFTER_S=3600` explicitly, so the fresh and deadline arms
    do not depend on suite runtime (deepen: test-design 12).
  - `row()` takes a `tag` argument (default `inngest-cutover-flip`). String-shaped rows (`row_str`)
    carry `_MACHINE_ID` in `raw` too.
- 0.2 **Stub fidelity.** It models ClickHouse `raw LIKE '%t%'`:
  - each line's **raw column text** is substring-matched against the OR-combined `--grep` terms;
  - lines that do not decode are matched on their literal text, so test 10's malformed line
    still reaches the probe (Kieran 13);
  - `--limit N` returns the newest N;
  - `--since` must be `Nh|Nm|Nd`, `%F %T` or ISO-Z, and anything else exits 22;
  - a missing `--grep` exits 64;
  - an optional `STUB_FAIL_ON_TERM` makes the query for one term fail, for F27.

  **Stub self-checks.** Each must be able to go red (deepen: test-design 4, 7). v3's claim that F1L
  and F10 cover these is withdrawn: an oldest-N stub leaves them green.
  - **OR.** Two terms return rows matching either one.
  - **Newest-N.** `--limit 2` over 5 rows returns the newest two, **in newest-first order**. The
    order is part of the contract F9 depends on.
  - **`--since` shape.** An ISO-Z value is accepted, and garbage exits 22.
  - **Quoted terms.** A quoted `'"reason":"x"'` matches an object-shaped row's raw text, and does
    not match a string-shaped row's escaped text (D2 residual).
- 0.2b **Test `TARGET` seam (deepen: test-design 9).** The suite honours `FLIP_ROLLOUT_TEST_TARGET`,
  defaulting to the tracked probe. The Phase 3.1 mutation battery then runs against **copies**, never
  the tracked file.
- 0.3 **`betterstack-query.sh` ISO normalisation.** In `test-betterstack-query-archive.sh`,
  `--since 2026-09-23T19:36:32Z` must produce `dt >= '2026-09-23 19:36:32'` in the captured SQL.
  Add the same assertion for `--until`, and a negative case: a non-ISO literal passes through
  unchanged.
- 0.4 **Emitter parity. Extend the existing block; do not duplicate it.** The `#6178 EMITTER
  PARITY` block in `apps/web-platform/infra/cutover-inngest-workflow.test.sh` already extracts the
  non-noop reason set. (The block is labelled `#6178` in the code; PR #7647 introduced it.) Add one
  loop that asserts each extracted reason also appears in the 7761 probe as a `'"reason":"<r>`
  literal. After this, one extraction pins both `_flip_transition_dt()` and the probe (CTO 2,
  code-simplicity).
  - **Anchor on the `DRIFT_GREPS=( … )` block only.** Read it with a flag-based `awk`, not the
    whole file, because a comment or the verdict table would otherwise satisfy the loop (deepen:
    test-design 8, `cq-assert-anchor-not-bare-token`).
  - **Negative control:** a copy of the block with one term deleted must red.
  - **When the probe file is absent,** the loop prints `probe retired (#7761 closed) — parity loop
    has no subject` and skips. The PR that retires the probe deletes the loop (deepen:
    architecture 6).
- 0.5 **Verdict-reason table parity (CTO 7).** In the 7761 suite, every verdict token the probe
  can print must appear in the header's verdict table. Add a negative control.
  - **Extract from code lines only:** the first token of `verdict_fail`'s `$1`, and the
    `reason=<token>` in `echo "TRANSIENT|FAIL: …"` lines.
  - **Read the table only from inside the header block**, so the table cannot satisfy itself
    (deepen: test-design 3).
- 0.6 **Fixtures.** Unless stated otherwise, rows are post-boundary, carry guard 7761, are
  object-shaped, and come from `MID_A`. `R` is the resume row. Each `TEST:` line is descriptive and
  carries its F-id as a tag (CTO 9).

| # | Scenario | Expect |
|---|---|---|
| F1 | `R`, then 2 `noop-done` | exit 0 `PASS … owned since` |
| F1L | **live shape**: `R`, then 600 `noop-done` (so `R` is outside the 500-row LIVE page, and only the drift query finds it) | exit 0 |
| F2 | 2 `noop-done`, no `R`, fresh boundary | exit 2 `done_not_resumed`, printing the boundary and the sidecar advice |
| F2b | F2 with `OLD_BOUNDARY` | exit 1 `done_not_resumed_past_deadline` |
| F3 | **REORDER**: `R` at `PRE_A` (pre-boundary), then 2 post-boundary `noop-done` | exit 2 `done_not_resumed` |
| F4 | **REORDER**: 2 `noop-done`, then `R`, with no noop after it | exit 2 `insufficient_post_replace_markers` |
| F5 | `R` + 2 `noop-done`, all unstamped | exit 1 `stale_image` |
| F7 | `R` + 2 `noop-done` + a `flag:"flipping"` row whose reason is `noop-flipping` (outside every reason grep and `FLUSH_PATH_REASONS`, so only the flag grep and flag class can catch it) ("mixed flipping rows") | exit 1 `flush_path_transition_after_replace` |
| F8 | `R` + 2 `noop-done` + `flip-complete` | exit 1 flush-path, naming `flip-complete` |
| F9 | second finding after a compliant first: `R` + `noop-done` + `refuse-rearm-after-done`, run **twice**, with the finding newest and then oldest in page order | exit 1 `drift_after_replace` both times |
| F10 | **horizon**: early `flip-complete`, `R`, then 600 `noop-done` | exit 1 flush-path |
| F11 | **direct-write drift**: `R`, 3 early `noop-aborted`, then 600 `noop-done` | exit 1 `drift_after_replace` |
| F12b | object `R` + 2 stamped **string-shaped** `noop-done` (with `_MACHINE_ID` in raw) | exit 0 (string rows decode and carry `_mid`) |
| F13 | F1 + Doppler stub `done` | exit 0 `doppler corroborates: done` |
| F13a | Doppler stub `aborted` (no rows needed: the Doppler arm exits first) | exit 1 (a non-`done` Doppler value blocks PASS; Kieran 7) |
| F14 | **must-PASS, non-canonical**: F1 + a pre-boundary `flip-complete` + 2 non-JSON Doppler-stderr rows under the tag + a `web-1` `R` | exit 0 |
| F16 | unstamped `R`, then 2 stamped `noop-done` | exit 2 `done_not_resumed` |
| F18 | `FLIP_ROLLOUT_DRIFT_LIMIT=1`, 2 `R` rows, then 2 stamped `noop-done` after both, no findings (dropping the guard would PASS) | exit 2 `drift_query_truncated` |
| F21 | F5 + an unstamped `flip-complete` | exit 1 flush-path (outranks `stale_image`) |
| F23 | `DRIFT_LIMIT=3`: 3 newer `web-1` `refuse-rearm-after-done` rows over one `soleur-inngest` `refuse-rearm-after-done` | exit 2 `drift_query_truncated` (raw page count) |
| F24 | 2 stamped `noop-aborted` (existing D7, **inverted**) | exit 1 `drift_after_replace` |
| F25 | **machine binding**: `R` on `MID_A`, 2 `noop-done` on `MID_B` | exit 2 `done_not_resumed` |
| F26 | `R`, `noop-done`, a second `R`, `noop-done` on the same machine | exit 0 |
| F27 | F1 + the refusal query fails (`STUB_FAIL_ON_TERM`) | exit 2 `refusals_query_failed` (never PASS; Kieran 5) |
| F28 | F1 + a same-host `inngest-luks-cutover`-tagged `noop-aborted` (a LUKS FSM row) | exit 0 (tag isolation) |
| F29 | F1 on `MID_A`, plus a flip-tag `MID_A` row inside `[AFTER−1h, AFTER]` (a sidecar moved past the machine's boot) | exit 2 `boundary_inside_owning_machine_lifetime` |
| F30 | F1 with `R.start_ts:"unknown"` | exit 2 `done_not_resumed` (an unplaceable `R` cannot own) |
| F31 | a stamped `noop-unset` row whose flag is a non-enum string `s3cr3t-value` | exit 1 `drift_after_replace`, and the probe output does **not** contain `s3cr3t-value` |
| F32 | sidecar is a symlink (via `FLIP_ROLLOUT_AFTER_FILE` pointing at a symlink to a file containing `LEAKME`) | exit 2 `sidecar_is_symlink`, and the output does not contain `LEAKME` |
| F33 | sidecar contains `LEAKME-not-a-date` | exit 2 `boundary_unparseable`, printing the length and not `LEAKME` |
| F34 | F18's page-full shape with `OLD_BOUNDARY` (supplied, older than 7 days) | exit 3 `drift_query_truncated` (CANNOT ESTABLISH) |
| F35 | a stamped `noop-aborted` with `start_ts:"unknown"` | exit 1 `drift_after_replace` (non-ISO drift row is a finding) |
| F36 | 500 `web-1` rows only in LIVE (the page is full of foreign rows) | exit 2 `channel_dark` (the sentinel is stripped before the empty check; deepen: test-design 13) |
| F37 | 25 findings | exit 1; exactly 20 rows plus `(+5 more)` printed; `FAIL: reason=` is the last line |

- 0.6b **Every fixture asserts an anchored `reason=<token>` or verdict token positively, and the
  competing token negatively.** For example, F18 asserts `drift_query_truncated` and asserts the
  absence of `done_not_resumed`, `PASS` and `stale_image`. An exit code alone cannot discriminate
  F7, F18, F21 or F23 from their mutants (deepen: test-design 6).
- 0.7 **Re-base the existing fixtures to the post-cutover key.**
  - Tests 3, 3b, 10, 12, 13, D1 and D6 PASS on `R` + `noop-done` (or, for 12, carry the refusal on
    that base).
  - 4, 5, 7b and 8 keep their failure shape, carried on `noop-done`.
  - 6 becomes F7's sibling (a `flushed` flag).
  - 7 and D8 keep the `armed` shape. It is unreachable from today's emitter, so it gets an inline
    comment (CTO 11).
  - D7 becomes F24.
- 0.8 **RED commit.** Run the suite against the unmodified probe and the unmodified
  `betterstack-query.sh`. The suite and the 0.3 assertion must be red overall; record the output.
  Do **not** claim that each fixture is red for its own reason at this point, because the decoder
  defect fires first in most of them (Kieran 3). Each fixture's discriminating power is proven
  after GREEN, by the Guard mutation matrices.

### Phase 1 — GREEN

- 1.1 **`scripts/betterstack-query.sh`.** Before building the `WHERE` clause, normalise an ISO-Z
  value for `--since` and `--until`:
  `[[ "$SINCE" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2}:[0-9]{2}:[0-9]{2})Z$ ]] && SINCE="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"`.
  Update the comment at the `--since accepts …` line accordingly, and remove the now-false "its
  ClickHouse cast rejects the ISO `T…Z` form" note in `scripts/cutover-inngest.sh` (the
  `confirm_flip_state` comment; deepen: architecture 3). The normalisation must run **before**
  `sql_quote` and before the `--until` concatenation (deepen: security 5).
- 1.2 **`mine <since> <limit> <term>...`** (and an optional `--until` pass-through for the F29
  boundary check).
  - `limit` must be digits, or the call dies loudly (CTO).
  - It selects `.host == $h and .host_name == $hn and .SYSLOG_IDENTIFIER == $tag`, where `$tag`
    is the flip tag, for emit_state queries (D2). The refusal query keeps its current selector,
    because refusal lines are raw strings under the same tag.
  - It decodes the message: an object is used as is; a string is tried with `fromjson?`, and if
    that yields an object it is used, otherwise the raw string passes through. A decoded object is
    emitted as `(. + {_mid: $row._MACHINE_ID}) | tojson`, one compact row per line. Kieran 11:
    `// empty | tojson` would double-encode strings. Test-design 1: string-shaped JSON rows must
    carry `_mid` too.
  - It appends `__PAGE_FULL__` when the raw page line count (`grep -c .`, never `wc -l`, so an empty
    page counts 0) equals `limit`.
  - Callers strip the sentinel **before** any emptiness check (`channel_dark`; deepen:
    test-design 13).
  - The existing single-term callers (LIVE, derivation-adjacent) keep their behaviour.
- 1.3 **Inline answer key.**
  - `POST_CUTOVER_FLAG="done"`, `DONE_ENTRY_REASON="flushed-resume-no-reflush"`
  - `FLUSH_PATH_REASONS`, `FLUSH_PATH_FLAGS`, `DRIFT_GREPS` (D2)
  - `EXPECTED_GUARD="7761"` (the `FLIP_ROLLOUT_EXPECTED_GUARD` override is dropped)
  - `MIN_MARKERS=2`
  - Delete `EXPECTED_FLAG`, `TERMINAL_SAFE_FLAGS` and `DRIFT_WINDOW`.
  - `DERIVE_WINDOW` gets its own `24h` default, or `set -u` kills the derived path (Kieran 12).
- 1.4 **Order.** It stays the existing structure, with the new arms slotted in and no general
  reordering (DHH 8):
  1. the Doppler arm;
  2. credentials and jq;
  3. derivation (unchanged);
  4. LIVE;
  5. `armed` over LIVE, uncapped, with an inline "unreachable from the current emitter; kept as
     defence in depth" comment;
  6. the `channel_dark` arms;
  7. the **drift query** → findings FAIL;
  8. **refusals** since the boundary, uncapped. A query failure gives
     `TRANSIENT refusals_query_failed` (Kieran 5);
  9. truncation TRANSIENT;
  10. `stale_image`;
  11. ownership and liveness;
  12. PASS.
- 1.5 **Implementation traps (Kieran 11).**
  - Findings are collected into a variable from a single `jq` call and not assembled in a piped
    `while` loop. Otherwise the loop runs in a subshell, and `verdict_fail`'s `exit` and the
    collected rows are lost.
  - Use the herestring `grep -q` form, not a pipe, under `pipefail`.
  - Use no jq builtins newer than 1.7.0, and keep the `(expr?) as $v` form (existing D9 guard).
- 1.5b **Output hygiene (deepen: security 1, 4, 9; observability 8).**
  - Findings print through `_flag_for_display` and the reason allowlist.
  - `_mid` prints as an 8-hex prefix.
  - At most 20 rows print, followed by `(+N more)`.
  - The `FAIL:` line repeats as the last line.
  - `boundary_unparseable` prints a length, never the value.
  - The sidecar read refuses symlinks and oversize content.
- 1.5c **Seam disclosure (deepen: security 8).** The PASS line ends with `seams=default` when no
  `FLIP_ROLLOUT_*` variable is set. Otherwise it ends with `seams=overridden:<names>`. Phase 3.3
  runs under `env -u` for every `FLIP_ROLLOUT_*` and AC10 requires `seams=default`. Under the
  sweeper's `env -i` it is always `default`.
- 1.5d **Non-verdict aging (D4b).** The read-path TRANSIENTs go through one helper, `non_verdict`.
  It exits 3 when the boundary is supplied and more than 604800 s old, and exits 2 otherwise.
- 1.6 **Doppler arm.** It accepts `done` and prints "corroborates". Any other value, including
  `rolled-back` and `aborted`, FAILs as it does today (Kieran 7). The "braked and serving nothing"
  wording is replaced. The arm stays inert in the sweeper, which has no Doppler token.
- 1.7 **Header.** Rewrite it smaller, one line per finding (DHH 12), and add the verdict table.
  - The table lists each `reason=` with its meaning and the action to take.
  - `drift_after_replace` / `flush_path_*` → read the printed rows; a remediated transition is
    re-certified by moving the sidecar.
  - `done_not_resumed*` → op=resume, or move the sidecar if the host was replaced.
  - `drift_query_truncated` / `*_query_failed` → re-run. Past 7 days these exit 3 (CANNOT
    ESTABLISH): fix the read path.
  - `boundary_inside_owning_machine_lifetime` → the sidecar was moved past the current machine's
    boot. Drift on this machine needs human review, not a sidecar edit.
  - `sidecar_is_symlink` / `sidecar_oversize` → restore the one-line regular file.
  - Retract the "24h drift window" claim and the claim that `cutover_armed` is "the FLUSHALL alarm
    on the one channel CI has". The FLUSHALL alarm is now `flush_path_transition_after_replace`.
  - Record the object-shape decode fact beside `mine()`.

### Phase 2 — the authoritative boundary

- 2.1 Create the `.after` sidecar containing exactly `2026-09-23T19:36:32Z\n`. Provenance goes in
  the commit message and in the `AFTER_FILE` comment, together with the lifecycle (D4):
  - apply run 35910239344, job `inngest_host_replace`, `completedAt`;
  - old machine's last row at 19:35:23Z;
  - new machine's first `start_ts` at 19:37:57Z;
  - resume at 19:42:45Z.
- 2.2 Drop `# repo-path: runtime` from the `AFTER_FILE` line.
- 2.3 In `scripts/lint-followthrough-varq-ban.test.sh`, R3-M20 loses its only live user. Re-point
  its inverse at a small **synthetic** probe file carrying an annotated line that refers to an
  untracked path. Do not use a copy of the 600-line probe (code-simplicity). The fixture stays green
  with the annotation and reds without it. The live-tree must-PASS stays. The assertion count rises
  by 1 (Kieran 14) and stays above the floor of 80.

- 2.4 **CI path coverage (deepen: architecture 4, 5).** Add
  `scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh` to `.github/workflows/infra-validation.yml`
  `pull_request.paths`, with a comment naming #7761 and the parity loop. Add it to
  `AFFECTED_INFRA_RUNNER_PATHS` in `scripts/lib/test-affected-paths.sh` too. Without this, a PR
  that edits only the probe, for example by dropping a `DRIFT_GREPS` term, skips the parity guard.
  This is the #8079 class the workflow's own comments record.

### Phase 3 — verification

- 3.1 Run the 7761 suite, then raise `MIN_ASSERTIONS` to the measured count. Then run the **Guard
  mutation matrices** against **copies**, via `FLIP_ROLLOUT_TEST_TARGET`.
  - Do a pristine-copy run first; it must exit 0.
  - A mutation counts as caught only if two things hold: the suite exits 1, **and** the named
    F-id's own `FAIL:` line appears. A different fixture going red proves nothing about the named
    row (deepen: test-design 9).
  - Record the per-row results in the PR body. This is where "each fixture discriminates its own
    reason" is proven.
- 3.2 Run the checks and lints:
  - `tests/scripts/test-betterstack-query-archive.sh` and `apps/web-platform/infra/cutover-inngest-workflow.test.sh`;
  - `scripts/lint-followthrough-varq-ban.sh` and its test;
  - `scripts/followthrough-exec-bit.test.sh`;
  - `plugins/soleur/test/fixture-relative-assert.test.sh`, regenerating with `--write-baseline` in
    the same commit only if a row changed;
  - `shellcheck` on every edited script.
- 3.3 **Pre-merge live read.** With the sidecar in the tree and no env boundary, run
  `doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh`.
  Expected: `PASS: #7761 delivered … owned since 2026-09-23T19:42:45Z`. Record the output in the PR
  body.
- 3.4 **Post-merge (pipeline).** Re-run 3.3 from merged `main` and post the verdict line on #7761
  with `gh issue comment 7761`. On PASS, the next scheduled sweep closes #7761; confirm with
  `gh issue view 7761 --json state` after that sweep.

## Files to Edit

- `scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh`: decoder, answer key, drift query
  and findings, ownership, refusals horizon and failure, Doppler arm, header and verdict table.
- `scripts/followthroughs/inngest-cutover-flip-rollout-7761.test.sh`: stub fidelity, fixtures,
  re-base, verdict-table parity, floor.
- `scripts/betterstack-query.sh`: ISO-Z normalisation for `--since`/`--until`.
- `tests/scripts/test-betterstack-query-archive.sh`: the ISO normalisation assertions.
- `apps/web-platform/infra/cutover-inngest-workflow.test.sh`: the `#6178` parity extraction extended
  to the probe.
- `scripts/lint-followthrough-varq-ban.test.sh`: R3-M20 inverse re-pointed at a synthetic fixture.
- `scripts/cutover-inngest.sh`: comment only. Remove the now-false "rejects the ISO `T…Z` form"
  note in the `confirm_flip_state` header.
- `.github/workflows/infra-validation.yml`: add the probe path to `pull_request.paths`.
- `scripts/lib/test-affected-paths.sh`: add the probe path to `AFFECTED_INFRA_RUNNER_PATHS`.
- `plugins/soleur/test/fixture-relative-assert.baseline.txt`: only if 3.2 reports a changed row.

## Files to Create

- `scripts/followthroughs/inngest-cutover-flip-rollout-7761.after`: the authoritative boundary.

## Open Code-Review Overlap

I queried the 76 open `code-review` issues against every path above.
- **#8435** (gsc-indexing-drain-8332 probe evidence) mentions `lint-followthrough-varq-ban` only as
  a check it ran. **Acknowledge**: different probe, no shared concern.
- None touch `betterstack-query.sh`, `test-betterstack-query-archive.sh` or
  `cutover-inngest-workflow.test.sh` (re-checked for v3).

## Guard Contract

### Guard 1 — done provenance (D1, D3)

**Property.** PASS requires this host's newest post-boundary, stamped `noop-done` machine `M` to
have a post-boundary, stamped `flushed-resume-no-reflush` on `M`, followed by at least 2 stamped
`noop-done` on `M` after it. A resting `rolled-back`/`aborted` never PASSes.

**Assembly.**
- One producer of the owning-resume set: the drift query (Phase 1.4 step 7), decoded and
  `_mid`-augmented by `mine()`, the single decode site.
- One producer of `M` and of the liveness rows: LIVE.
- One counter: the `post_ok` selector.
- No second `noop-` counting site may exist.

**Mutation matrix.**

| Mutation | Must go RED via |
|---|---|
| Delete the `start_ts > OWNED_SINCE` clause | F4 |
| REORDER: drop the `start_ts > AFTER` filter on `R` | F3 |
| Drop the `_mid == M` binding (hostname-only ownership) | F25 |
| Drop the guard check on the owning `R` | F16 |
| Take the owning `R` from LIVE instead of the drift query | F1L |
| Remove `flushed-resume-no-reflush` from `DRIFT_GREPS` | F1L, plus parity |
| Re-admit `aborted` as a PASS state (drop `noop-aborted` from `DRIFT_GREPS`) | F24, plus F11 |
| Drop the boundary-precedes-machine check | F29 |
| Let an `R` with a non-ISO `start_ts` own `done` | F30 |

**Harness rows.**
- Revert the stub to last-`--grep`-wins: the 0.2 OR self-check reds. (v3 relied on F1L here, but
  that depended on the term's position, so the reliance is withdrawn.)
- Make the stub oldest-N: the 0.2 newest-N self-check reds.
- Drop `_MACHINE_ID` from `row()`: F1 reds.
- Must-PASS, non-canonical: F14, F26.

**Anchor.** The emitter file (`inngest-cutover-flip.sh`, not edited in this PR) feeds the parity
block. The live read (3.3/3.4) runs against warehouse data that no diff controls.

### Guard 2 — since-boundary drift (D2)

**Property.** Any post-boundary FSM row from this host, other than the resume shape, is a FAIL,
over the whole since-boundary interval. A FLUSHALL is reported as such regardless of guard stamp or
row order. An absence conclusion is never drawn from a truncated page.

**Assembly.**
- `emit_state` is the single emitter, and every call takes a literal reason. The parity block pins
  those literals to `DRIFT_GREPS`.
- One detection source: the drift query.
- One findings computation: a single `jq` call.
- One truncation signal: the `__PAGE_FULL__` sentinel, computed before the host filter.

**Mutation matrix.**

| Mutation | Must go RED via |
|---|---|
| Restore the old newest-500 tag query as the drift source | F10, F11 |
| Revert the ISO normalisation in `betterstack-query.sh` | 0.3 assertion |
| Classify only the first returned row | F9 (both page orders) |
| Class = reason only (ignore flag) | F7 |
| Run `stale_image` before findings | F21 |
| Condition the exemption on guard/`_mid` | F16 (turns into drift FAIL) |
| Drop the `start_ts > AFTER` filter | F14 |
| Drop the truncation guard | F18 |
| Count page-full after the host filter | F23 |
| Swallow a refusal-query failure | F27 |
| Drop the `SYSLOG_IDENTIFIER` field isolation | F28 |
| Drop the non-ISO-drift-row-is-a-finding rule | F35 |
| Print the raw `.flag`/`.reason` of a finding | F31 |
| Remove the 7-day non-verdict aging | F34 |
| Check emptiness before stripping the sentinel | F36 |
| Drop the 20-row cap / trailing `FAIL:` line | F37 |

**Harness rows.**
- Make the stub ignore `--limit`: F10, F11 and F18 stop discriminating.
- Make the stub accept any `--since`: the 0.2 self-check reds.
- Must-PASS: F14.

**Anchor.** The parity block reads the emitter, which is outside this diff. The live read runs the
real query.

### Guard 3 — shape-agnostic decode (P8)

**Property.** Every row returned for this host decodes, whether its `message` is an object (the
emit_state live shape) or a string (refusal rows, legacy rows). Object rows carry `_MACHINE_ID`.

**Assembly.** `mine()` is the single decode site. `mine_dt()` reads string key=value probe rows
and is out of scope.

**Mutation matrix.**

| Mutation | Must go RED via |
|---|---|
| Revert to `.message? // empty` | F1 |
| Use `tojson` unconditionally (double-encodes string rows) | F12b (test 12 alone cannot catch it, because a quoted refusal string still contains the marker) |
| Attach `_mid` to object rows only | F12b |
| Use `// empty \| tojson` (double-encodes strings) | F12b |
| Drop the `_mid` augmentation | F1, F25 |

**Harness rows.** Revert `row()` to string-only: F1 and F25 lose their object coverage.

**Anchor.** The live read.

## Plan Review Disposition

The panel had four seats: DHH, Kieran, code-simplicity, and CTO (devex). The eng panel was
correctness plus simplification. Brand-survival threshold is `none`, so the 3+1 baseline applies.

**Mechanical, applied** (in v3 above):

| Finding | Source | Where it landed |
|---|---|---|
| Exemption must not depend on guard/`_mid` | Kieran P0-1 | D2 |
| F23 was unpassable | Kieran P0-2 | F23 re-shaped |
| RED column wrong | Kieran 3 | 0.8, 3.1 |
| Live PASS shape uncovered | Kieran 4 | F1L |
| Failed refusal query → PASS | Kieran 5 | F27 |
| Doppler non-`done` → PASS | Kieran 7 | F13a |
| Class = max(reason, flag) | Kieran 8 | D2 |
| Source of `M`, and the `start_ts > AFTER` filter | Kieran 9 | D2, D3 |
| jq/bash traps | Kieran 11 | 1.2, 1.5 |
| `DERIVE_WINDOW` default | Kieran 12 | 1.3 |
| Stub must be `LIKE`-faithful | Kieran 13 | 0.2 |
| Guard/AC claims, timestamps | Kieran 14 | Guard 1, 0.1, 2.3 |
| One classifier source, no union | code-simplicity | D2 |
| Fixed off-flag greps, no STEADY | code-simplicity | D2 |
| Sentinel, not side-channel file | code-simplicity | D2, 1.2 |
| Cut `transition_row_unplaceable`, `flag_in_flight`, `steady_state_not_post_cutover`, `flag_changed`, severity ordering | code-simplicity, DHH 2/9/10 | D1, D2 |
| Extend the existing parity block | code-simplicity, CTO 2 | 0.4 |
| Synthetic R3-M20 fixture | code-simplicity | 2.3 |
| Cut v2 F6b/F11b/F12/F13b/F15/F17/F19/F20/F22 | DHH 11, code-simplicity | 0.6 |
| Unknown-reason fail-safe claim was false since-boundary | DHH 3 | D2 residuals |
| No general arm reordering | DHH 8 | 1.4 |
| Header smaller | DHH 12 | 1.7 |
| Fix `--since` at the source | CTO 1 | D5, 1.1 |
| Resting `aborted` escalates | CTO 5/6 | D1 |
| Verdict table + parity | CTO 7 | 0.5, 1.7 |
| Sidecar advice in the message | CTO 8 | D3 |
| Descriptive `TEST:` lines | CTO 9 | 0.6 |
| One-pass bulk fixtures | CTO 10 | 0.1 |
| Inline unreachable comments | CTO 11 | 1.4, D2 |

**Not applied, with reasons:**
- **DHH 4** (cut the truncation guard). Kieran and the CTO showed a full page drops the oldest row,
  which is the resume, and that would turn truncation into a false `done_not_resumed` FAIL. When
  the panels conflict, correctness wins. The guard is kept, but simplified to a sentinel.
- **DHH 1 / 11** (about 9 fixtures). v3 has 24 new fixtures, down from 30. Each remaining one is
  named by a Guard mutation row (Phase 3.1), and that is the cut criterion.
- **Code-simplicity: cut the stub's rc-22 `--since` gate; and DHH on the same stub gate.** Kept as
  one self-check. The stub's `--since` looseness is exactly how v1 of this plan would have shipped
  a probe that never works live.

**Taste, not applied (persisted to `knowledge-base/project/specs/feat-one-shot-7761-flip-probe-post-cutover-answer-key/decision-challenges.md`):**
- **DHH 6.** Delete the derived-boundary arm (about 130 lines). The committed sidecar does make it
  dead for this probe's life. But deleting it widens this diff, removes the fallback the header
  documents, and deletes about 12 tests that pin the #7695 provenance cap (shipped in PR #7887). Recorded for the operator.

**Deferred with tracking issues:**
- **CTO 3.** One shared `betterstack-query.sh` fake: #8697.
- **CTO 4.** A shared object-shaped `message` decoder: #8698.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. The probe is a read-only
  warehouse query. A false PASS would close the #7761 security tracker on wrong evidence. A false
  FAIL/TRANSIENT leaves it open, as today. The scheduler and every user's jobs are untouched either
  way.
- **If this leaks, the user's data is exposed via:** no new vector. The probe reads Better Stack with
  the existing `BETTERSTACK_QUERY_*` credential. Everything it prints lands in a public issue
  comment, so the output is constrained:
  - flags go through `_flag_for_display`;
  - reasons are allowlisted, because `noop-unset` and `unexpected-exit(from=…)` embed the raw flag;
  - machine-ids print as 8-hex prefixes;
  - the sidecar value never echoes;
  - output is capped at 20 rows.

  Fixtures F31–F33 and F37 pin this. It adds no secrets and no new query surface.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the diff is a read-only follow-through probe, its tests, a timestamp sidecar, the operator-side betterstack-query.sh reader, a comment in cutover-inngest.sh, two test files (one under apps/web-platform/infra/ that only greps sources), and a one-line pull_request.paths addition to infra-validation.yml that only widens when an existing validation job runs; none of it executes on a production host or handles user data.`

## Observability

```yaml
liveness_signal:
  what: "the daily follow-through sweep runs this probe and posts its verdict line (PASS / FAIL reason= / TRANSIENT reason=) as a comment on #7761"
  cadence: "daily (scheduled-followthrough-sweeper.yml) plus on-demand local runs"
  alert_target: "GitHub issue #7761 comment thread (follow-through + needs-attention labels)"
  configured_in: ".github/workflows/scheduled-followthrough-sweeper.yml (directive in the #7761 body: script=scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh)"
error_reporting:
  destination: "the probe's stderr verdict line, relayed into the #7761 comment by scripts/sweep-followthroughs.sh"
  fail_loud: "exit 1 with 'FAIL: reason=<token>'; every non-verdict (query/decode/truncation) is exit 2 'TRANSIENT: reason=<token>', never a silent pass"
failure_modes:
  # Every detection runs on layer 3 (vector host_scripts_journald, allowlist apps/web-platform/infra/vector.toml -> Better Stack, tag inngest-cutover-flip)
  # Every alert_route is layer 6 (scheduled-followthrough-sweeper.yml run log -> #7761 comment)
  - mode: "a FLUSHALL or flush attempt on the host after the replace"
    detection: "since-boundary transition query matches flip-complete / flushall-failed / dbsize-nonzero"
    alert_route: "FAIL reason=flush_path_transition_after_replace on #7761"
  - mode: "replaced host inherited done and op=resume never ran (scheduler dark)"
    detection: "no post-boundary guard-stamped flushed-resume-no-reflush on the machine (_MACHINE_ID) emitting the newest noop-done"
    alert_route: "FAIL reason=done_not_resumed_past_deadline on #7761"
  - mode: "host rests in rolled-back/aborted, or any other FSM transition, after the cutover"
    detection: "since-boundary drift query returns a non-exempt row (noop-aborted/noop-rolled-back/transition reason)"
    alert_route: "FAIL reason=drift_after_replace on #7761"
  - mode: "the replace kept the pre-#7761 image"
    detection: "post-boundary flip-tag noop-done rows carry no guard=7761 stamp (layer 3)"
    alert_route: "FAIL reason=stale_image on #7761 (layer 6)"
  - mode: "a Doppler secret name collided with a fixture seam on the live host (#7761 itself)"
    detection: "SOLEUR_INNGEST_CUTOVER_SEAM_REFUSED rows since the boundary (layer 3)"
    alert_route: "FAIL reason=seam_refused on #7761 (layer 6)"
  - mode: "the flip timer stopped emitting"
    detection: "zero flip-tag rows from this host in the 2h LIVE window (layer 3)"
    alert_route: "TRANSIENT channel_dark, FAIL channel_dark_past_deadline on #7761 (layer 6)"
  - mode: "the sidecar was moved past the owning machine's boot, or is not a regular one-line file"
    detection: "flip-tag row with _mid == M inside [AFTER-1h, AFTER]; symlink/oversize sidecar"
    alert_route: "TRANSIENT boundary_inside_owning_machine_lifetime / sidecar_is_symlink / sidecar_oversize on #7761 (layer 6)"
  - mode: "decoder or read path cannot see rows (drift_query_truncated, drift_query_failed, refusals_query_failed, query_failed, row_decode_failed)"
    detection: "query rc != 0, jq failure, or a full drift page with no finding (layer 3 read path)"
    alert_route: "TRANSIENT (exit 2) on #7761; exit 3 CANNOT ESTABLISH once a supplied boundary is over 7 days old, so a stuck non-verdict never reads NOT YET forever (layer 6)"
logs:
  where: "Better Stack source soleur-inngest-vector-prd (journald tag inngest-cutover-flip, host=soleur-inngest) read through scripts/betterstack-query.sh"
  retention: "Better Stack hot window plus s3 archive arm (union-queried by betterstack-query.sh mode 2)"
discoverability_test:
  command: "bash scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh"
  expected_output: "PASS: #7761 delivered"
  credentials_required: "BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} from Doppler soleur/prd_terraform — the evidence is the host's journald rows in the Better Stack ClickHouse warehouse, which has no unauthenticated read path; the host has no inbound SSH and no public status endpoint for the FSM"
```

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** The CTO found the drift definition and reason set sound: every `emit_state` literal
was checked. The sidecar is the right boundary mechanism: it is supplied provenance, it is read on
the sweeper's `env -i` channel, and an inline literal would merge the boundary into the answer key.
It is low risk. The decoder fix is medium risk because of the `--since` format and archive rows;
both have since been measured and resolved (D5). The one HIGH finding was ownership bound to the
hostname, not the machine; it is fixed in D3 and pinned by F25. Needs no ADR: this is a bug fix on
an existing surface, with no architectural decision. There are no hot-path database writes. The
complexity is medium, mostly the fixture harness.

## Test Scenarios

The fixture table in Phase 0.6 (F1–F37) is the scenario list, together with the 0.2 stub
self-checks, the 0.3 ISO assertions and the 0.4/0.5 parity loops.

- **RED commit (0.8):** the suite is red overall against the unmodified code. Most fixtures are red
  because of the decoder defect, not their own reason.
- **After GREEN (3.1):** each fixture's discriminating power is proven by the Guard mutation
  battery, run against copies. A mutation counts only when the named fixture's own `FAIL:` line
  appears.

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1: The RED commit lands first (`cq-write-failing-tests-before`) and carries:
  - the stub-fidelity changes (0.2) and the object-shaped, `_MACHINE_ID`-carrying `row()` (0.1);
  - fixtures F1–F37 and the re-based existing tests (0.6, 0.7), each with anchored positive and
    negative token assertions (0.6b);
  - the stub self-checks and the `FLIP_ROLLOUT_TEST_TARGET` seam (0.2, 0.2b);
  - the ISO assertion in `test-betterstack-query-archive.sh` (0.3);
  - the probe-parity loop in `cutover-inngest-workflow.test.sh` (0.4);
  - the verdict-table parity check (0.5).

  Its recorded output shows the 7761 suite, the 0.3 assertion and the 0.4 loop red against the
  unmodified probe and `betterstack-query.sh`.
- [x] AC2: `bash scripts/followthroughs/inngest-cutover-flip-rollout-7761.test.sh` exits 0, with
  `MIN_ASSERTIONS` raised to the measured count. Every F-id in 0.6 appears as a tag in a `TEST:`
  line.
- [x] AC3: The Phase 3.1 mutation battery ran against copies via `FLIP_ROLLOUT_TEST_TARGET`, after
  a pristine-copy run that exited 0. For **every** row of Guards 1–3 the suite exited 1, and the
  named F-id's own `FAIL:` line appeared. The per-row result is recorded in the PR body.
- [x] AC4: The answer key is inline.
  `grep -nE '^[^#]*FLIP_ROLLOUT_(EXPECTED_GUARD|EXPECTED_FLAG|MIN_MARKERS|TERMINAL)' scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh`
  returns nothing, and `grep -cE '^[^#]*(TERMINAL_SAFE_FLAGS|EXPECTED_FLAG=|DRIFT_WINDOW=)'`
  returns 0 on the same file.
- [x] AC5: `bash tests/scripts/test-betterstack-query-archive.sh` and
  `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` exit 0. The first shows the ISO
  normalisation assertions and the second shows the probe-parity loop, each with its negative
  control.
- [x] AC6: `scripts/followthroughs/inngest-cutover-flip-rollout-7761.after` is tracked with git
  mode `100644` (`git ls-files -s` shows a regular file, not `120000`). Its content matches
  `^2026-09-23T19:36:32Z$`. The `AFTER_FILE` line carries no `# repo-path: runtime`.
  The comment beside it states the sidecar lifecycle.
- [x] AC7: `bash scripts/lint-followthrough-varq-ban.sh` exits 0, and
  `bash scripts/lint-followthrough-varq-ban.test.sh` exits 0 with a count one above today's 88. Its
  R3-M20 inverse runs against a synthetic fixture: green with the annotation, red without it.
- [x] AC8: `bash scripts/followthrough-exec-bit.test.sh` and
  `bash plugins/soleur/test/fixture-relative-assert.test.sh` exit 0; the baseline changes only if a
  row changed. `shellcheck` is clean on every edited script.
- [x] AC9: The Phase 0.0 live precondition is recorded in the PR body: 1 row since the boundary
  (the 19:42:45Z resume, object-shaped, `_MACHINE_ID 3cff04d3…`), and ISO `--since` rc 22 on the
  unmodified reader.
- [x] AC10: The Phase 3.3 pre-merge live read runs with every `FLIP_ROLLOUT_*` unset. It prints a
  line beginning `PASS: #7761 delivered`, naming `owned since 2026-09-23T19:42:45Z` and ending
  `seams=default`. That line is pasted into the PR body. A non-PASS is
  investigated before merge and leaves this AC unticked.
- [x] AC11: The PR body uses `Ref #7761` and no closing keyword. It states that the fix had already
  been delivered by earlier replaces, with guard-stamped transition rows since at least 09-15, and
  that this PR changes nothing on any host. It also references #8697 and #8698 as the deferred
  follow-ups.

- [x] AC11b: `.github/workflows/infra-validation.yml` `pull_request.paths` and
  `AFFECTED_INFRA_RUNNER_PATHS` in `scripts/lib/test-affected-paths.sh` both list
  `scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh`. The `scripts/cutover-inngest.sh`
  note claiming ISO is rejected is gone:
  `grep -c 'rejects the ISO' scripts/cutover-inngest.sh` returns 0.


### Amendments (2026-09-24, review round on PR #8690)

- **AC2/AC3:** after the nine-seat review the suite is 307/0 (`MIN_ASSERTIONS=307`, was 223). The mutation battery was re-run on the post-review head: 53/53 rows caught with the named fixture's own `FAIL:` line, 0 survivors, pristine control 307/0.
- **AC10:** the PASS verdict is now three lines rather than one; the review asked for the long line to be split. Line 1 begins `PASS: #7761 delivered` and names `owned since 2026-09-23T19:42:45Z`. Line 3 is `seams=default`. The live read on the post-review head matches.
- **AC11b:** the `AFFECTED_INFRA_RUNNER_PATHS` half was dropped in review. `scripts/test-all.sh` runs the infra runner only on `_infra_in_diff`, so that entry never selected anything for a probe-only diff. The `infra-validation.yml` `pull_request.paths` half stands, and the parity block runs in `deploy-script-tests`.
- **D2/D3 (superseded in part):**
  - Drift now considers every row the `dt`-bounded query returns. A run that started before the boundary but emitted after it is a finding (F38).
  - The boundary check queries machine M's own `_MACHINE_ID` over 30 days, where it used to look back 1h (F29b).
  - More than one `_MACHINE_ID` since the boundary is `multiple_machines_since_boundary` (F25, F39).
  - Any unstamped post-boundary heartbeat is `stale_image` (F40, F41).
  - String-shaped flip rows refuse a PASS (F12b, F48, F49).
  - Liveness counts distinct heartbeats, requires the newest to be recent, and measures its deadline from the resume (F42, F43, F44).
  - The rationale lives in the probe header and in the review commit `da45d1b89d`.

### Post-merge (pipeline)

- [ ] AC12: The probe is re-run from merged `main` (3.4), and its verdict line is posted on #7761
  via `gh issue comment 7761`.
- [ ] AC13: If AC12 is PASS, the next scheduled sweep closes #7761; confirm with
  `gh issue view 7761 --json state` after that sweep. If AC12 is not PASS, #7761 stays open and the
  comment names the reason.
