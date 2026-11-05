---
title: "chore(tests): make the local affected-test gate fast, observable and optional where CI already covers it"
date: 2026-11-05
slug: affected-gate-lock-chain
branch: feat-one-shot-12013-affected-gate-lock-chain
issue: 12013
type: chore
priority: p3-low
domain: engineering
brand_survival_threshold: none
closes: none (Ref #12013 only)
lane: cross-domain
---

## Overview

Spec lacks valid lane: - defaulted to cross-domain (TR2 fail-closed).

The parallel pool (width 4) and the live red line are merged, and the measurement they asked for is in the
ADR-242 amendment of 2026-11-04: the cold gate on a replayed single-feature diff took about 6522 s against the
600 s bar, because 78 percent of the suite phase ran at most one suite. This plan attacks the serial chain and the
masked red, in the order the CTO ruled (`specs/feat-one-shot-12013-affected-gate-lock-chain/decision-challenges.md`):

1. **Lever 4 first (correctness):** a budget kill (rc 124/137) must not hide a red the runner already reported.
2. **Lever 2a:** `_pj_fill` becomes conservative backfill, so token-free suites launch behind a blocked queue head.
3. **Lever 2b:** the three `ci-pr-affected-replay-{a,b,c}` arms stop serializing each other (explicit empty-token
   `lane_declare` overrides; the other ~56 `lock:test-all` holders keep the token).
4. **Measurement and the ADR-242 pricing-ledger entry**, with a same-session FIFO control.

Out of this PR by ruling: narrowing the replay arms' `^plugins/soleur/` selection edge (lever 1; follow-up blocked on
#12128) and the derive cache (lever 3; gated on a measured cold-derive share of at least 25 percent). The PR body says
`Ref #12013`; the 600 s goal is not claimed.

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 12013`: OPEN, p3, labels `type/chore`, `domain/engineering`, `meta/machinery`; the last comment carries
  the measurement and the four levers. Held.
- #12025 CLOSED (by the sibling PR #12103, merged as `4347c55df8`); #12106 OPEN (CI-timing pricing of `image-cve-verdict`
  and the webplat shard; separate scope); #12110 OPEN with fix PR #12128 OPEN (edits `scripts/lib/test-affected-paths.sh`
  and `scripts/ci-pr-affected-audit.accept.tsv`; no failing checks). **Do not duplicate #12128.** Held.
- Cited symbols confirmed on this branch (== `origin/main` `6d4b6e8a02` plus the empty init commit): `_pj_fill`
  (`scripts/test-all.sh` ~2283, strict FIFO, returns on the first non-launchable head), `_pj_launchable` (~2245; slot count
  plus token conflict against the LIVE set only), `_pj_fmt_done` (~2226), `lane_tokens_for` / `lane_tokens_conflict`
  (`scripts/lib/test-suite-lanes.sh`), the delegated arm rc mapping (`plugins/soleur/scripts/affected-tests.sh` ~560-610:
  `124|137` -> `finish 6 ... budget-deferred` whenever `AFFECTED_BUDGET_ACTIVE == 1`). Held; none stale.
- Mechanism vs ADR corpus: ADR-242 (decisions and the 2026-11-03/-04 amendments), ADR-133 (advisory lock),
  ADR-177 (signal-shaped rc is unresolved, not failed), ADR-196 D1/D7 (no lock re-entrancy), ADR-292
  (plugin-generic affected gate). A result cache and an unconditional CI-only skip are explicitly rejected there and are not
  proposed here. No proposed mechanism sits in a rejected-alternatives table. Held.
- Collision pre-check (`collision-precheck.sh 12013`): only this branch's own draft PR #12149 names the issue; the foreign
  `test-all.sh` processes belong to unrelated worktrees (10390, 10455, 9927). No duplicate.
- A claim in the brief corrected by measurement: it says the lock chain is "the self-SUT batteries"; 59 of the 160 selected
  suites (4625 s of 8671 s of suite time) hold `lock:test-all`, because `lane_tokens_for` derives the token from ANY textual
  mention of `test-all\.sh`. Of 178 holders enumerated, a rough static pass finds about 32 exec-shaped and about 144
  mention-only (reads/greps the file). Narrowing the derivation was ruled out (F2 option (a), below); the finding is
  carried so the follow-up has the number.

### Property List and Cut List (Phase 0.6b)

Properties the ask buys (each an observable outcome):

- P1. A suite whose tokens do not conflict with anything live or ahead of it starts as soon as a slot is free, even
  while the queue head is blocked.
- P2. Suites that conflict (shared token, or `*`) still never overlap and still start in registration order.
- P3. The three replay arms (sandboxed fixtures, distinct `mktemp -d` sandboxes) can run at the same time.
- P4. A red the runner printed before a budget kill is reported by the gate as a failure, not as a deferral.
- P5. The change is measured, with a control, and recorded where the repo records measured weights.

Mechanisms named in the ask and what already covers each property:

| Mechanism in the ask | Property | Already on main? |
|---|---|---|
| Let token-free suites launch behind a blocked head | P1, P2 | No: `_pj_fill` returns on the first blocked head. Built here (conservative rule). |
| Split the `lock:test-all` token of the self-SUT batteries | P3 | Partly: `lane_declare` overrides already replace a derived set wholesale (`scripts/lib/test-suite-lanes.sh`). Built as three overrides, no new mechanism. |
| Narrow the `^plugins/soleur/` edge | selection volume (not a P above) | Out of scope by ruling F3. |
| Derive cache | cold derive | Cut: below the 25 percent threshold (best modelled case 23 percent); re-measure trigger recorded. |
| Make a budget kill report a visible red | P4 | No: runner stderr is inherited and never inspected by the gate. Built as a sidecar. |

**Cut List.**

- New `glob-rate` subcommand or a measurement wrapper script -> P5 -> the existing `python3 -I scripts/ci-pr-affected-replay.py glob-rate --candidates <blank-entry file>` and the runner's `TEST_TIMING_LOG` already produce every number.
- Stderr tee in `affected-tests.sh` -> P4 -> a runner-written sidecar is a structured channel; the tee parses display text monitors also parse (F4).
- Narrowing the `lock:test-all` derivation for the ~144 mention-only suites -> P3 -> not needed for the arms; a false mention-only call becomes a deadlock of up to `TC_LOCK_TIMEOUT` (3600 s) (F2).
- A new `*.test.sh` for each guard -> all -> new arms in three existing suites; a new suite would need an edge block, accept-TSV rows and a durations row in files #12128 is rewriting.
- Raising `budget_seconds` -> none -> forbidden by the brief.

### Value-proposition measurement (Phase 0.6c)

The saving is the claim, so it is quantified at plan time, and the command that produced each number is named.

- Command: a discrete-event replay of the pool over the measured per-suite walls of the 160 selected suites
  (`knowledge-base/project/specs/archive/20261105-094951-feat-one-shot-12013-12025-affected-gate-reprice/measurements/gate-run-1.tsv`),
  in registration order from `bash scripts/test-all.sh --enumerate-commands`, tokens from
  `scripts/lib/test-suite-lanes.sh::lane_tokens_for`, width 4. The replay script is a scratch artifact of this planning
  session and is not committed (a planning aid, not a deliverable).
- Validation: the model reproduces the measured run (model suite phase 5925 s with 78 percent of it at most one suite live;
  measured 5960 s and 78 percent).
- Result (suite phase seconds, this one diff, loaded walls held fixed):

| Scenario | Suite phase | At most one live |
|---|---|---|
| Current (FIFO, current tokens) | 5925 s | 78% |
| Backfill only (F1) | 5008 s | 71% |
| Replay arms token-free, FIFO | about 4900 s | 71% |
| **Backfill + replay arms token-free (F1 + F2b, this PR)** | **about 3437 s** | 47% |
| Replay arms not selected at all, FIFO (the lever-1 prize) | 2644 s | 51% |
| Replay arms not selected, backfill | 1813 s | 20% |

- Reading, stated so it is not over-read: this PR's modelled gain is about 2500 s (42 percent) of the suite phase on this
  one diff; the lever-1 edge narrowing is worth another 1600 s and stays the largest remaining lever. Even the best case
  (1813 s plus 108 to 543 s of derive) misses 600 s on this loaded reading. The model holds walls fixed, so a less serial
  schedule will inflate real walls; the plan therefore requires a measured A/B, not the model, for any claim (F5).

### Plan-review revisions (2026-11-05; DHH, Kieran, code-simplicity; all mechanical, none drops requested scope)

Applied: one-pass backfill with a running skipped-token union instead of a restart-per-launch prefix scan; the sidecar append
moved out of the shared `_run_suite_verdict` into the pool reap writer plus the serial `run_suite` tail; epoch-stamped records
so a TERM-induced exit 1 after the deadline is not a red; the capability probe dropped; both branches of the delegated call get
the env var; `_pj_drain` fills until empty; `_lane_derive` split because the equality guard was vacuous against an overridden
label; the exec-shaped-runner regex dropped (the replay suite plants fixture bodies containing `bash scripts/test-all.sh`, so
the control would be red); mutation matrices trimmed (10/10/9 -> 9/5/10 rows with the duplicates of existing arms A4a/A4b
removed); the clock-based fill bound replaced by a conflict-call count; the knob's documentation and demotion dropped; ACs split
into deterministic gates and recorded observations; CI is not evidence for the backfill. Not applied: merging #12152 into
#12151 (distinct re-evaluation triggers and a blocked-by chain; kept as two); dropping the knob (CTO required it).

### Selection probe (edge evidence for the follow-up)

Command: `bash scripts/test-all.sh --print-selection --paths=plugins/soleur/skills/plan/SKILL.md` (cold derive, cache
`hits=0 misses=733`, no suite run). Result: `selected=276 not-affected=457 of 733`; all three
`ci-pr-affected-replay-{a,b,c}` rows are selected with class `edge:declared`. So a diff that touches one skill file and nothing
the replay suite names selects the three replay arms (3281 s of pool time in the measured run), which is the lever-1 prize; the exact token that mints `^plugins/soleur/`
is the F3 follow-up's first evidence-bar item (provenance), not established here.

### Institutional learnings applied

- `2026-11-05-a-new-tool-was-built-for-a-case-the-existing-one-already-handled-and-the-measurement-method-changed-the-mechanism.md`:
  the pool engages only while the run holds the advisory lock; never change lock timeouts to measure; run the existing
  `glob-rate` on the degenerate input before inventing a subcommand.
- `2026-10-05-registering-a-suite-is-itself-a-runner-edit.md`: any edit to `scripts/test-all.sh` or
  `scripts/lib/test-affected-paths.sh` degrades OUR OWN `--affected` gate to the full battery (`runner-changed`). Expected and
  acceptable (CI is the merge gate); the work phase must plan for a long local run and must not read it as a hang.
- `2026-08-19-the-budget-was-shorter-than-the-thing-it-was-waiting-for.md`: a budget or rc 124/137 handling must never expire
  into "proceed"; do not raise `budget_seconds`.
- `2026-08-13-a-lower-bound-cannot-tell-a-measurement-from-a-constant.md`: contention and timing assertions need both
  sides, asserted not commented.
- `2026-10-18-ratchet-guards-must-pin-the-scan-population-and-their-own-registrations.md` and
  `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`: every guard here carries a mutation
  matrix written before the code, with a row on the guard's own dispatch.
- `2026-10-14-my-stubs-checked-the-shape-of-argv-and-never-the-value-...md`: stubs must `exit 64` on contract violations.

### Open Code-Review Overlap

One open code-review issue names a file this plan edits: #7942 (two `*.mutation.sh` batteries in `plugins/soleur/test/` run in
no gate; names `scripts/test-all.sh`). **Acknowledge:** a different concern (registration of two batteries), not touched here;
it stays open.

### Research Reconciliation - Spec vs. Codebase

| Brief / tracker claim | Reality | Plan response |
|---|---|---|
| "split the `lock:test-all` token of the self-SUT batteries" | The token is derived from a text mention in 178 enumerated suites, 59 of them selected in the measured run; the self-SUT batteries are only a few of them | Scope F2 to the three replay arms (the dominant, measured cost); record the 59/178 number and leave the broader narrowing to a follow-up |
| "the strict FIFO queue idled the other slots" | Confirmed in source: `_pj_fill` returns when the head is not launchable. The model reproduces the 78 percent figure from this rule alone | Backfill, with the order-preserving rule |
| "runner rc 124/137 maps to rc 6 even after a provisional `done (rc=1` line" | Confirmed (`affected-tests.sh` ~599-603). Serial mode is affected too: its `[FAIL]` verdict prints at the suite's end and nothing is recorded for the gate | The sidecar is written at BOTH the pool reap site and the serial verdict site |
| "Narrowing that edge is the largest lever" | True by the model (another ~1600 s). The two wide prefixes are DERIVED edges (the printed row lists the declared entries last), so a declared array cannot shrink them; #12128 is concurrently editing the same file | Follow-up with a stated evidence bar (F3), filed with `Ref #12013` |
| "queue wait also counts against the budget" | Confirmed (`AFFECTED_DEADLINE` is set before the runner call; the advisory-lock wait is inside the runner) | Documented, no code change: the brief forbids raising `budget_seconds`, and with F4 a queued run that did print a red is no longer reported as a deferral |

## Problem Statement

The measured gate misses the 10-minute acceptance by 10.9x on one loaded reading. Three independent defects account for the
controllable part: (a) the queue is strict FIFO, so a blocked head idles free slots; (b) three sandboxed replay arms
(3281 s of pool time) serialize through a token meant for suites that take the real advisory lock; (c) a budget kill reports a
visible red as a deferral.

## Proposed Solution

### Phase 1 - F4: a budget kill reports a visible red (correctness, independent of timing)

- `plugins/soleur/scripts/affected-tests.sh` delegated arm: before the runner call, create a per-run sidecar with
  `affected_mktemp provisional` (registered for cleanup; the gate owns it, and the `124|137` read happens before the EXIT trap)
  and put its path on the runner call as `SOLEUR_PJ_PROVISIONAL_FILE` in BOTH branches of the call (the pool-width branch and
  the plain `else` branch, ~lines 584-588; the serial fallback is the usual path when the lock is not held or
  `SOLEUR_TEST_JOBS=1`). No capability probe: an environment variable a runner does not know is inert, so a customer runner is
  untouched without one.
- `scripts/test-all.sh`: when `SOLEUR_PJ_PROVISIONAL_FILE` names a writable regular file, append one line
  `<label><TAB><rc><TAB><epoch-seconds>` with a single `printf >> "$file"` (one short O_APPEND write is atomic), for rc in
  1..127 only, label scrubbed with `${label//[[:cntrl:]]/?}` (a tab or newline would corrupt the record). Exactly two append
  sites, one per run mode, so nothing is double-counted: `_pj_fmt_done` for the pool (the live reap line; the shared writer all
  three reap sites already call, including the torn-reap branch) and the serial tail of `run_suite` (the line after the
  `"$@"` / `tee` block, just before `_run_suite_verdict`, guarded by `_pj_mode == 0`). `_run_suite_verdict` itself is NOT a
  site: it is shared and the pool reaches it at drain, so appending there would double-count pool reds. Skip the append when
  `_pj_sig == 1` (an interrupted run).
- Kill-induced exits are not reds. `affected_timeout` (`common.sh` ~150-157) runs `timeout -k 10`, which signals the whole
  process group, and a worker that turns the TERM into exit 1 is reaped through `_pj_fmt_done` after the deadline. The gate
  therefore counts only records whose epoch is strictly before `AFFECTED_DEADLINE`; later records are ignored.
- Gate mapping at the `124|137` arm: any qualifying record (rc matches `^[0-9]+$`, parsed with `10#`, in 1..127, epoch before the
  deadline) -> `finish 1 "$_dmode" failed-before-budget runner ...`. Records with rc >= 128 are ignored (ADR-177: unresolved,
  not failed). Mixed -> 1. No qualifying record, a missing/empty/unreadable sidecar, malformed lines, or the variable unset ->
  unchanged `finish 6 ... budget-deferred`.
- Contract surface for the new reason `failed-before-budget` (rc stays 1): the header exit contract in `affected-tests.sh`
  (rc 1 bullet), the reason catalog in `plugins/soleur/scripts/lib/affected-tests/common.sh` (~line 304), and one row in the rc
  table of `plugins/soleur/skills/ship/references/affected-gate-contract.md`; rc 6 now means "no red was seen before the kill"
  (one line in the ADR-242 amendment). The consumers (`plugins/soleur/scripts/grok-pre-push-gate.sh`,
  `plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md`, `plugins/soleur/test/workflow-fidelity.test.ts`) already
  treat rc 1 as a hard fail; record that as one grep result in the PR body, not as a deliverable.

### Phase 2 - F1: conservative backfill in `_pj_fill`

Rule. A candidate may launch iff (i) a slot is free (`_pj_live_n < _pj_jobs`), (ii) its token set conflicts with no LIVE suite
(`_pj_launchable` as today), and (iii) it conflicts with nothing queued ahead of it. `*` conflicts with everything, so a queued
`*` blocks every later suite and a `*` candidate launches only when the pool is drained and nothing is queued before it.

Implementation shape (one pass, not a restart-per-launch prefix scan): walk the queue once in registration order carrying
`skipped_tokens` (the union of the token sets of earlier suites that stayed queued) and an `any_earlier_queued` flag. Check the
slot and live-set conditions first (cheap), then one `lane_tokens_conflict` call of the candidate against `skipped_tokens`, with
the flag standing in for the empty-set case (`lane_tokens_conflict "*" ""` returns 0, so a `*` candidate would otherwise be
blocked with an empty queue). A launched candidate changes the live set, so re-run the pass only when a launch happened, which
keeps the work near q per launch rather than q-squared per reap (`_pj_submit` blocks only when `live >= jobs`, so behind a live
`*` suite the queue can hold hundreds). Reuse `lane_tokens_conflict`; never re-implement the comparison (its `read -ra` form is
what keeps `*` from being globbed). The head is the first candidate of every pass, so a token-ready head is never delayed by an
independent stream.

- `_pj_drain` (`scripts/test-all.sh` ~2401): the single `_pj_fill` after the reap loop becomes a loop while anything is live or
  queued (with a no-progress guard), because the torn-reap branch of `_pj_reap` never calls `_pj_fill` and a launch from the last
  single fill would be marked UNACCOUNTED.
- Knob: `SOLEUR_PJ_FIFO=1` restores strict FIFO exactly. It is the measurement control (the A/B arm), read once in
  `_pj_resolve_run_mode`, documented in the runner header only. It is not demoted from suite environments (a nested runner that
  inherits it only runs FIFO, which is harmless). Plan to remove it once the measurement is recorded, unless the CTO re-rules.
- Cost check without a clock: the scheduler suite counts `lane_tokens_conflict` calls on a 730-entry synthetic queue and asserts
  a stated ceiling; no wall-clock bound.
- Output: unchanged. The drain renders in registration order regardless of start order (existing arm A3 pins it). `_pj_launch`
  already clears `_pj_solo` for every live suite when a second one starts; the solo attribution is observable only through the
  `tmp_delta=` field, so its arm needs a fixture suite that creates a tmp entry.
- Evidence note: CI sets `CI`, and `_pj_resolve_run_mode` goes serial whenever `CI` is set (~line 2178), so a green CI run is NO
  evidence for backfill. Only the scheduler suite and the local measurement count.

### Phase 3 - F2(b): the replay arms stop serializing each other

- `scripts/lib/test-suite-lanes.sh`: split the derivation out of `lane_tokens_for` into `_lane_derive <argv...>` (the part after
  the override lookup; `lane_tokens_for` calls it, behaviour unchanged), so a test can ask what the classifier derives without
  the override masking it. Three `lane_declare` entries for `plugins/soleur/test/ci-pr-affected-replay-a`, `-b`, `-c` with an
  EMPTY token set (their derived set is exactly `lock:test-all`; an override replaces the whole set), each with a `reason`
  citing: a distinct `mktemp -d` sandbox per arm (`ci-pr-affected-replay.test.sh` ~line 104), `test-all.sh` references that are
  planted fixture copies (~lines 694, 703, 1651) or reads of the real file (~lines 1958, 1997), and no `tc_acquire`.
- `scripts/lib/test-suite-lanes.test.sh`: (1) equality - for every registered label matching `ci-pr-affected-replay-`, the
  override equals `_lane_derive <argv from --enumerate-commands>` minus `lock:test-all`, with a control asserting today's derived
  set for these labels is exactly `lock:test-all` (so the comparison is not vacuous) and a non-empty floor on the label count;
  (2) the replay suite file contains no `tc_acquire` (clean today). The previously planned "no exec-shaped call of the real
  runner" regex is dropped: the suite plants fixture bodies that contain `bash scripts/test-all.sh` (~line 1651), so the
  unmutated control would be red, and the heuristic is the classifier the CTO rejected as rough. The runtime evidence for "the
  arms never take the real lock" is the concurrent-run audit below. (3) The existing census (every override names an emitted
  label, has a reason, no duplicates) stays green.
- Concurrent-run audit (a recorded observation in the measurement notes, not a gate: it depends on machine load): three
  concurrent runs of the three arms, no sandbox collision, no failures. Evidence that would flip F2: any arm touching the
  parent's lock, or any collision on a shared path.
- The other ~56 selected `lock:test-all` holders keep the token; the broader narrowing is #12152.

### Phase 4 - Measurement and the ADR-242 amendment

Protocol (F5). In a checkout with its own git-common-dir (the private clone method of the 2026-11-04 amendment: its own
advisory lock so the pool engages; never a ship path; no lock-timeout tweaks): replay the SAME pinned diff as the baseline
(pick `7af192071d`, base `8cc167c2e3`, 160 suites) at this PR's tree. At least 2 cold readings and 1 reading with
`SOLEUR_PJ_FIFO=1` in the same session as the A/B control. Record at each reading's start: loadavg and concurrent heavy
processes. Record per reading: suite-phase seconds, cold-derive seconds, per-suite walls, the "at most one live" percentage,
pass/fail counts. Rates for any edge-related number come from the existing
`python3 -I scripts/ci-pr-affected-replay.py glob-rate --candidates <blank-entry file> --commits 100 --base <sha> --out <dir>`.
Weights go in the ADR-242 pricing ledger, never in `suite-durations*.tsv`. Raw rows are committed under
`knowledge-base/project/specs/feat-one-shot-12013-affected-gate-lock-chain/measurements/`.

ADR-242 gets a new `## Amendment - <date> (#12013)`: the backfill rule and its knob, the F2 override and the reasoning against
the broader narrowing, the sidecar contract and the new reason, the measured table, the lever-3 re-evaluation (a measured
cold-derive share against the 25 percent line), and the follow-up pointers. The previous amendment's "Known limit" paragraph
is superseded by reference, not rewritten.

### Phase 5 - Follow-ups filed (deferral tracking)

- F3 edge-narrowing: filed as #12151 (blocked-by #12110 / PR #12128, milestone `Post-MVP / Later`), carrying the four-point evidence bar.
- Broader `lock:test-all` derivation narrowing (F2 option (a)): filed as #12152 (blocked-by #12151), re-evaluate after F3 is measured, carrying the 59-of-160 and
  32/144 numbers and the 3600 s deadlock risk of a false mention-only call.
- #12013 stays open at the measured gap. Lever 3 stays unbuilt; the trigger is recorded on #12013.

## Files to Edit

- `scripts/test-all.sh` - `_pj_fill` one-pass backfill and `SOLEUR_PJ_FIFO`, the `_pj_drain` fill loop, the two sidecar append
  sites (`_pj_fmt_done`, serial tail of `run_suite`), an `export -n SOLEUR_PJ_PROVISIONAL_FILE` demotion next to
  `SOLEUR_TEST_JOBS`, header docs. (Runner edit: our own gate degrades to the full battery.)
- `scripts/lib/test-suite-lanes.sh` - `_lane_derive` split, three empty-token overrides with reasons.
- `scripts/lib/test-suite-lanes.test.sh` - override-equality (against `_lane_derive`) and no-`tc_acquire` guards.
- `scripts/test-all-parallel-scheduler.test.sh` - new arms for backfill (order among conflicting suites, barrier, starvation,
  knob, replay/exit parity, solo attribution, torn-reap drain) and for the sidecar write (reap site, serial site, nested-runner
  isolation, kill-induced exit).
- `plugins/soleur/scripts/affected-tests.sh` - sidecar creation and hand-over in both branches of the delegated call, the
  `124|137` mapping, header exit contract.
- `plugins/soleur/scripts/lib/affected-tests/common.sh` - reason catalog line.
- `plugins/soleur/scripts/affected-tests.test.sh` - budget-kill arms (red before kill -> 1; signal-shaped only -> 6; mixed -> 1;
  post-deadline record ignored; stale file never read; env unset -> as today; malformed lines unresolved; leading-zero rc).
- `plugins/soleur/skills/ship/references/affected-gate-contract.md` - one rc-table row for `failed-before-budget`.
- `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md` - the amendment.
- Consumers `plugins/soleur/scripts/grok-pre-push-gate.sh`, `plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md`
  and `plugins/soleur/test/workflow-fidelity.test.ts` are checked by one grep and edited only if a consumer needs it.

Not edited (by ruling): `scripts/lib/test-affected-paths.sh`, `scripts/ci-pr-affected-audit.accept.tsv`,
`scripts/suite-durations*.tsv`, `.soleur-test-gate.json` (`budget_seconds` unchanged).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-12013-affected-gate-lock-chain/measurements/` - the measured readings (TSVs plus a
  short method note). The pool model is a planning aid and is not committed. No new `*.test.sh`, no new script.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Five technical forks (backfill rule, token split, edge narrowing, budget-kill channel, scope and acceptance) were
ruled by the CTO agent on 2026-11-05; the full rulings are rows in `decision-challenges.md`. The CTO could not verify whether
CI runs the same pool path as the local gate; plan review answered it from code: `_pj_resolve_run_mode` goes serial whenever
`CI` is set, so a green CI run is no evidence for the backfill and only the scheduler suite plus the local measurement count.

Product/UX Gate: not relevant (no user-facing surface; no file under `components/`, `app/`, or any UI-surface glob). No wireframe
is owed. Marketing, legal, finance, operations, sales, support: no implication (internal developer tooling).

## User-Brand Impact

- **If this lands broken, the user experiences:** no end-user artifact. An operator or agent sees a local gate that either
  starts a suite it should have held back (a flaky red in a sandboxed battery) or reports a deferral where a red was visible;
  CI's required `test` check remains the only merge gate, so a local mistake cannot merge a regression.
- **If this leaks, the user's data/workflow/money is exposed via:** nothing; no data, credential or network surface is touched.
  The sidecar is a 0600 file under the run's `TMPDIR` holding suite labels and exit codes.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none`, not `aggregate pattern` - a wrong local verdict is caught by the required CI check, and nothing here reaches a customer surface. threshold: none, reason: the touched paths (`scripts/`, `plugins/soleur/scripts/`) are developer-tooling and ship no customer-visible behaviour.

## Observability

```yaml
liveness_signal:
  what: the gate marker line `AFFECTED_GATE ... mode=... reason=... stack=... ci=...` on every verdict path, plus the runner's live `[run] <label> done (rc=N, Mms)` lines and the `[parallel] mode engaged - width=N` banner
  cadence: per gate run (each ship, work, review and pre-push invocation)
  alert_target: the invoking operator or agent terminal; ship Phase 4 and the pre-push gate parse the marker
  configured_in: plugins/soleur/scripts/affected-tests.sh (finish), scripts/test-all.sh (_pj_fmt_done)
error_reporting:
  destination: stderr of the gate and the runner; the exit code and the AFFECTED_GATE marker reason are the machine channel. No Sentry surface (developer tooling run on the operator's machine)
  fail_loud: exit 1 with reason=failed-before-budget when a red preceded a budget kill; exit 6 only when no red was seen
failure_modes:
  - mode: a budget kill after a visible red is reported as a deferral
    detection: affected-tests.test.sh arm drives the delegated arm with a stub runner that prints a provisional red into the sidecar and then exceeds the budget; expects rc 1 reason=failed-before-budget
    alert_route: the suite is registered in the local gate and the CI test shard; a red blocks the PR
  - mode: backfill launches a suite beside a conflicting earlier-queued suite
    detection: scripts/test-all-parallel-scheduler.test.sh arms A4a/A4b plus the new backfill arms (shared-token overlap and drain-barrier assertions)
    alert_route: same as above
  - mode: a replay-arm override drifts from the derived set
    detection: scripts/lib/test-suite-lanes.test.sh equality assertion
    alert_route: same as above
logs:
  where: the runner's durable per-suite logs under ${SOLEUR_SCRATCH_BASE:-/var/tmp}/soleur-test-all-logs and TEST_TIMING_LOG; the gate's stderr
  retention: 14 days (SOLEUR_TEST_ALL_LOG_GC_DAYS default, existing)
discoverability_test:
  command: grep -o failed-before-budget plugins/soleur/scripts/affected-tests.sh
  expected_output: failed-before-budget
```

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-242 (new `## Amendment - <work date> (#12013)`), via the `soleur:architecture` skill: decision (a) the pool's fill
policy is conservative backfill, default-on, `SOLEUR_PJ_FIFO=1` restores FIFO; (b) the three replay arms carry an empty
token set; (c) the gate/runner sidecar contract and the `failed-before-budget` reason; (d) the lever disposition (edge
narrowing and broader token narrowing deferred with evidence bars; derive cache gated on a measured share). Add to its
Alternatives Considered: unconditional skip-ahead (breaks `*` barrier semantics), stderr tee, narrowing the derivation to
exec-shaped references, default-off knob. No new ADR ordinal, so no ordinal-collision exposure.

### C4 views

No C4 impact. Checked against all three model files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`,
1079 + 148 + 54 lines): (a) external human actors - the only operator-side actor is `founder` ("Founder / Operator"), unchanged;
(b) external systems - GitHub Actions CI is unchanged and no vendor is added; (c) containers / data stores - the local test
runner and the affected gate are not modelled (a case-insensitive search of the three files for test-all, affected, local gate,
test runner, pre-push and vitest finds only unrelated prose in the hooks container description), and the sidecar is a
run-scoped tmp file, not a store; (d) actor-to-surface access relationships - none change. The derived cardinalities in edge
prose are untouched (no cron monitor, heartbeat or workflow is added); the work phase confirms with
`bash plugins/soleur/test/c4-count-parity.test.sh`.

### Sequencing

The ADR amendment is written in this PR, after the measurement, describing the as-measured state; nothing is postponed to a
separate issue.

## Guard Contract

### Guard 1 - Backfill ordering (scheduler)

**Property.** Under backfill, no two suites whose token sets conflict are ever in flight together or start out of registration
order, a `*` suite runs only with a drained pool and blocks every later suite, and an independent stream never delays a
token-ready head.

**Assembly.** Every path that starts a pool worker: `_pj_fill` is the only decision chokepoint and `_pj_launch` the only
launch site (reached only from `_pj_fill`); its callers `_pj_submit`, `_pj_reap` and `_pj_drain` (including the drain loop that
now fills until empty) and `_pj_launchable`. The guard quantifies over the fixture registrations of the scheduler suite, not the
real corpus. The knob arm (`SOLEUR_PJ_FIFO=1`) is the second member that must reproduce the old launch order exactly. Fixtures
order their suites by release files, never by sleeps.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the "conflicts with nothing queued ahead" clause so a candidate sharing a token with an earlier queued suite may launch | RED (shared-token arm) |
| 2 | Let a queued `*` suite stop blocking later token-free suites (skip-ahead past a barrier) | RED (barrier-ahead arm) |
| 3 | Let a `*` candidate launch while any suite is live or queued ahead | RED (drain-barrier arm, existing A4b plus a new case) |
| 4 | Try the head last instead of first, so an independent stream starves a token-ready head | RED (starvation arm) |
| 5 | Make `SOLEUR_PJ_FIFO=1` a no-op | RED (knob arm compares against a launch-order fixture recorded from `main`) |
| 6 | Guard's own dispatch: register zero fixture suites, or have the arm print "0 launched" and exit 0 | RED (nonzero launch count, `started` line count equals registration count, pass floor) |
| 7 | Second blocked member after a compliant first: head blocked on token T, two independent suites, then a second T holder that jumps its predecessor | RED (order-among-conflicting arm) |
| 8 | Leave `_pj_solo` set for the first suite when backfill starts a second | RED (solo-attribution arm, via a fixture suite that creates a tmp entry and the `tmp_delta=` field) |
| 9 | Make the single fill in `_pj_drain` single again, with a fixture that exercises the torn-reap branch | RED (no UNACCOUNTED suite) |

Slot cap and live-set conflict stay covered by the existing arms A4a/A4b; the plan does not duplicate them.

**Harness rows.** (H1) A must-PASS input that is not the canonical fixture: a queue whose head is blocked and whose independent
suites differ in count and order from the canonical (3 and 5); they must launch behind the head and finish with replay order and
exit code identical to the FIFO run. A guard that rejects every backfill case fails H1. (H2) Break the SUITE, not the
scheduler: make the fixture suites exit instantly and require the overlap arms to FAIL as vacuous rather than pass.

**Anchor.** The expected FIFO launch order is a frozen fixture recorded from the unchanged algorithm on `main`, not re-derived
from the code under test; changing the fixture and the algorithm in one diff shows up as two files in review.

### Guard 2 - Replay-arm override equals derived minus `lock:test-all`

**Property.** The explicit token override of each replay arm is always exactly the arm's currently derived token set with
`lock:test-all` removed, and the replay suite never mentions the advisory-lock entry point.

**Assembly.** The three override labels in `scripts/lib/test-suite-lanes.sh`, the new `_lane_derive` (the override-free
classifier), and the one suite file `plugins/soleur/test/ci-pr-affected-replay.test.sh` that backs all arms, so a derived token
gained by the file moves all three. The label list is derived from the registered labels matching `ci-pr-affected-replay-`,
not hard-coded.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `xargs -P` to the suite file (derives `cpu:pool`) while the override stays empty | RED (equality; calls `_lane_derive`, which the override cannot mask) |
| 2 | Change one arm's override back to `lock:test-all` | RED (equality for that label) |
| 3 | Guard's own dispatch: rename the arms so the label list is empty | RED (non-empty floor on the iterated label count) |
| 4 | Add a fourth registered arm `-d` with no override | RED (label-derived list finds it) |
| 5 | Add a `tc_acquire` mention to the suite file | RED (no-lock-entry-point check) |

**Harness rows.** (H1) Point the guard's classifier input at a nonexistent file and require RED, not a silent "nothing to
compare". (H2) A must-PASS fixture suite file that mentions `test-all.sh` only in a comment and as a planted fixture path.

**Anchor.** The override is compared with the live classifier's output (`_lane_derive`), not with a stored copy, so the stored
side and the thing it protects cannot both be weakened without the classifier disagreeing.

### Guard 3 - Budget kill reports a visible red

**Property.** When the delegated runner is killed by the budget (rc 124 or 137), the gate exits 1 with
`reason=failed-before-budget` if and only if the sidecar holds a record with a numeric rc in 1..127 stamped before the
deadline, and otherwise keeps exit 6.

**Assembly.** The two producer sites in the runner (`_pj_fmt_done` pool reap, the serial tail of `run_suite`), the env
hand-over in BOTH branches of the delegated runner call in `affected-tests.sh`, the `124|137` arm of the delegated mapping, and
the three environments a sidecar path could leak into (suite subprocesses, a nested sandboxed `test-all.sh`, later gate steps).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Map `124|137` to 6 unconditionally again (remove the sidecar read) | RED (red-before-kill arm) |
| 2 | Treat rc >= 128 records as red | RED (signal-shaped-only arm expects 6) |
| 3 | Count records stamped at or after the deadline | RED (kill-induced-exit arm: a worker that exits 1 on TERM after the deadline expects 6) |
| 4 | Stop appending at the serial tail of `run_suite` | RED (serial red-before-kill arm) |
| 5 | Stop appending in `_pj_fmt_done` | RED (pool red-before-kill arm) |
| 6 | Hand the path over in only one branch of the delegated call | RED (the other branch's arm) |
| 7 | Let a nested sandboxed runner inherit the variable | RED (nested-runner arm: a fixture suite runs a nested runner with a planted FAIL; the outer sidecar must stay empty) |
| 8 | Guard's own dispatch: stub runner never writes and the arm prints "0 records" and exits 0 | RED (control pair: a stub that writes a red must produce 1 and one that writes nothing must produce 6; both must run) |
| 9 | Second record after a compliant first: signal-shaped first, real red second, gate stops at the first | RED (mixed -> 1) |
| 10 | Read a stale sidecar left at a guessable path instead of the gate's own fresh mktemp | RED (stale-file arm pre-seeds a red and expects 6) |

**Harness rows.** (H1) Break the SUITE: point the arm at a gate copy with the mapping reverted and require the arm to FAIL.
(H2) A must-PASS non-canonical input: a sidecar record with a leading-zero rc (`08`), which must be parsed as decimal with
`10#` (an octal error in bash arithmetic would otherwise abort the gate) and treated as a real red.

**Anchor.** The expected exit/reason pairs are literals in the test, independent of the implementation; the contract header in
`affected-tests.sh` and the ship reference carry the same literals, and the existing header-vs-code parity checks in
`plugins/soleur/scripts/affected-tests.test.sh` extend to the new reason.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "speed up the local affected-test gate" | Phases 2 and 3 (backfill, replay-arm override) | mapped |
| 2 | "a typical single-feature PR must finish the local gate in under 10 minutes on a loaded machine" | Phase 4 measurement; the bar is not claimed (F5) | mapped - descoped from "met" to "measured" - justification: the model and the CTO agree the best case misses 600 s on the loaded reading; the brief itself says `Ref #12013`, not Closes, unless a measured run meets the bar |
| 3 | "Narrowing that edge is the largest lever." | Phase 5 follow-up filed with the evidence bar | descoped - justification: CTO ruling F3 (derived edges cannot be narrowed from a declared array, the file is concurrently edited by #12128); the brief makes this a CTO fork |
| 4 | "let token-free suites launch behind a blocked queue head (`_pj_fill` is strict FIFO)" | Phase 2 | mapped |
| 5 | "split the `lock:test-all` token of the self-SUT batteries" | Phase 3 (three arms) | mapped |
| 6 | "do NOT build it unless a new measurement crosses the threshold" (derive cache) | Phase 4 records the re-evaluation; nothing built | mapped |
| 7 | "runner rc 124 or 137 maps to rc 6 (deferred) even after a provisional `done (rc=1` line printed" | Phase 1 | mapped |
| 8 | "never remove a suite from the set selected by a diff touching its subject files" | No selection edge is changed; Guard 1 asserts order, not membership | mapped |
| 9 | "measured weights go in the ADR pricing ledger, never in suite-durations*.tsv" | Phase 4 | mapped |
| 10 | "use glob-rate with a blank-entry candidates file for existing selection rates (no new subcommand)" | Phase 4 protocol | mapped |
| 11 | "measure in a checkout with its own git-common-dir, never in a ship path" | Phase 4 protocol | mapped |
| 12 | "do not raise `budget_seconds` to fit a queued run" | `.soleur-test-gate.json` not edited | mapped |
| 13 | "PR body uses `Ref #12013`, not Closes" | Acceptance Criteria | mapped |
| 14 | "#12110 ... fix PR #12128 is open ... do not duplicate it" | Not touched; the F3 follow-up is blocked on it | mapped |
| 15 | "the private measurement clone ... must be deleted by the operator; list it under 'Needs you'" | decision-challenges.md row; final message | mapped |
| 16 | "never skip the legal-register lints" | The lints remain always-on; no selection change | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 1 sidecar and `failed-before-budget` | "runner rc 124 or 137 maps to rc 6 (deferred) even after a provisional `done (rc=1` line printed" | asked |
| Phase 2 backfill | "let token-free suites launch behind a blocked queue head" | asked |
| Phase 3 three overrides | "split the `lock:test-all` token of the self-SUT batteries" | asked |
| Phase 4 measurement and ADR-242 ledger | "measure in a checkout with its own git-common-dir"; "measured weights go in the ADR pricing ledger" | asked |
| Phase 5 follow-up issues | "Technical forks (edge narrowing, token split, FIFO fill) are for the CTO agent to rule" | asked |
| `SOLEUR_PJ_FIFO` knob | - | inferred - justification: it is the same-session control arm the measurement protocol needs (CTO F5), and the CTO required a one-cycle kill switch |
| `_lane_derive` split, equality guard | - | inferred - justification: without a classifier call the override cannot mask, the override outlives a derived token silently |
| Epoch stamp on sidecar records and the drain fill loop | - | inferred - justification: plan review showed a TERM-induced exit 1 after the deadline would turn a true deferral into a false failure, and a single drain fill marks late launches UNACCOUNTED |
| Test arms in the three existing suites | - | inferred - justification: each changed mechanism is a guard-adjacent scheduling or exit-contract rule and needs a driven-RED proof (`cq-write-failing-tests-before`) |

### Split Assessment

- Subsystems touched: 3 - `scripts/` (runner and lane table), `plugins/soleur/scripts/` (gate), `knowledge-base/` (ADR and
  measurements)
- Planned files: 9 edited plus the measurements directory | Estimated changed lines: about 450 including tests
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. Phases 1 to 3 are independently revertible commits so a review can drop one without the others.

## Acceptance Criteria

Deterministic, over synthetic fixtures (they cannot be flipped by a sibling process): AC1-AC8, AC10-AC12. Recorded
observations of a loaded machine (not gates): AC5 and AC9.

### Pre-merge (PR)

- [ ] AC1. `bash scripts/test-all-parallel-scheduler.test.sh` is green with the new arms: `SOLEUR_PJ_FIFO=1` reproduces the
  launch order recorded from `main` in a frozen fixture; the default runs conservative backfill. (CI sets `CI` and the pool goes
  serial there, so CI is not evidence for this AC; the suite's own sandboxed runner copies are.)
- [ ] AC2. Each of the 9 Guard 1 mutations, applied to a copy of the runner, turns the named arm RED; the unmutated control
  is green first (control green before any mutant row is read).
- [ ] AC3. Replay order and exit code are byte-identical between FIFO and backfill on the same fixture, including a planted
  FAIL and a signal-shaped exit; `_pj_solo` attribution is correct (arm asserts it through `tmp_delta=`).
- [ ] AC4. `scripts/lib/test-suite-lanes.sh` carries `_lane_derive` and three empty-token overrides, each with a reason; the
  equality (against `_lane_derive`, with the "today's derived set is exactly `lock:test-all`" control) and the no-`tc_acquire`
  checks are green, and each of the 5 Guard 2 mutations turns one RED.
- [ ] AC5. (Recorded observation.) Three concurrent runs of the three replay arms: no sandbox collision, no failures, with the
  load average, in the measurement notes. A collision is a finding that flips F2, not a flaky gate.
- [ ] AC6. `affected-tests.sh` delegated arm, in both branches of the runner call: a qualifying sidecar record plus rc 124 or
  137 exits 1 with `reason=failed-before-budget`; a signal-shaped-only sidecar, a post-deadline record, an
  empty/missing/stale/malformed sidecar, and the variable unset all keep exit 6; each of the 10 Guard 3 mutations turns one RED.
- [ ] AC7. The new reason is present in the header exit contract, the reason catalog in `lib/affected-tests/common.sh` and the
  ship `affected-gate-contract.md` rc table; the consumer grep (`grok-pre-push-gate.sh`, the review reference,
  `workflow-fidelity.test.ts`) result is stated in the PR body.
- [ ] AC8. No edit to `scripts/lib/test-affected-paths.sh`, `scripts/ci-pr-affected-audit.accept.tsv`,
  `scripts/suite-durations*.tsv` or `.soleur-test-gate.json` (`git diff --stat origin/main...HEAD -- <those>` is empty).
- [ ] AC9. (Recorded observation.) Measurement committed: at least 2 cold readings of the pinned diff plus 1
  `SOLEUR_PJ_FIFO=1` control in the same session, each with loadavg and concurrent heavy processes at start, suite-phase seconds,
  cold-derive seconds, per-suite walls, the at-most-one-live percentage and pass/fail counts. Each reading is about 1.8 hours on
  the baseline machine; a reading that is killed or fails is recorded as such, and the PR states the number of completed
  readings. A new failure that the control reading does not share is a stop-and-investigate finding.
- [ ] AC10. ADR-242 amendment written with the measured table, the lever-3 re-evaluation against the 25 percent line, and the
  follow-up pointers; weights are in the ADR ledger only.
- [ ] AC11. The PR's required CI `test` check is green on the PR head (the gate that matters; this PR's own local gate is the
  full battery because it edits the runner, and the PR records whether a local full run was made or deferred to CI per the gate
  contract). `bash plugins/soleur/test/c4-count-parity.test.sh` is green.
- [ ] AC12. The two follow-up issues #12151 (edge narrowing, blocked on #12110/PR #12128) and #12152 (broader token narrowing)
  exist with re-evaluation criteria and milestone (filed during planning); the PR body says `Ref #12013` (no `Closes`), reports
  the measured gap honestly and does not claim the 600 s goal.

### Post-merge

- [ ] AC13. #12013 receives a comment with the measured result and the remaining gap; it stays open. (No operator action;
  the agent posts it.)

## Test Scenarios

- Given a queue `[A(token T, live), B(token T), C(no token), D(no token)]` and width 4, then C and D start while B waits, and B
  starts the moment A is reaped, before any later independent suite.
- Given `[A(live), X(*), C(no token)]`, then C does not start while X is queued, and X starts only with a drained pool.
- Given a head blocked on T and a later second T holder, then the second T holder never starts before the first.
- Given `SOLEUR_PJ_FIFO=1`, then the launch order equals the frozen fixture recorded from `main`.
- Given a 730-entry synthetic queue with 60 percent token-free suites, then one fill pass makes at most a stated number of
  `lane_tokens_conflict` calls (a count, not a clock).
- Given a torn-reap fixture, then no suite is marked UNACCOUNTED because the drain fills until the queue is empty.
- Given a stub runner that writes a red into the sidecar and exceeds the budget, the gate exits 1 `failed-before-budget`; given
  only an rc-137 record, exit 6; given an rc-137 and an rc-1 record, exit 1; given a worker that exits 1 on TERM after the
  deadline, exit 6; given a pre-seeded stale file at a guessable path, exit 6; given an rc of `08`, a real red.
- Given a fixture suite that itself runs a nested sandboxed `test-all.sh` with a planted FAIL, then the outer sidecar stays empty.
- Given the replay suite file with an added `xargs -P` line, then the lane-equality guard is RED.
- Regression: every existing arm of `scripts/test-all-parallel-scheduler.test.sh`, `scripts/test-all-parallel-contention.test.sh`,
  `plugins/soleur/test/affected-tests-pool-default.test.sh` and `plugins/soleur/scripts/affected-tests.test.sh` stays green.

## Dependencies & Risks

- **#12128 (OPEN)** edits `scripts/lib/test-affected-paths.sh`; this PR does not touch that file, so there is no conflict, and
  the edge-narrowing follow-up is sequenced after it.
- **Wall inflation:** less serial schedules raise per-suite walls under load; the model's gain is an upper bound. Mitigation:
  a measured A/B with a same-session control, and no claim from the model.
- **Backfill races a suite assumed serial by accident:** a suite with no declared token but an undeclared shared resource
  was previously protected by FIFO order only when the resource holder was earlier in the queue and blocked. The conservative
  rule only reorders suites whose tokens do not conflict, which were already allowed to run side by side whenever a slot was
  free; backfill changes WHEN, not WHETHER. Residual risk is a load-sensitive real-git suite (the known `git-data-replication`
  F21 class) going red more often; the knob and ADR-242 decision 3 (re-run alone with `SOLEUR_TEST_JOBS=1` before treating a
  pool-only red as a regression) are the mitigation.
- **Replay arms concurrent:** CPU and I/O load of three heavy arms plus width 4 may exceed machine capacity; the pool width
  clamp (`nproc`, memory) already bounds the live count at 4.
- **Runner edit degrades our own gate to the full battery:** a long local run is expected; do not read it as a hang and do not
  raise `budget_seconds`.
- **Measurement clone:** needs a private checkout with its own git-common-dir; the operator-owned clone
  `/data/git-repositories/jikig-ai/measure-clone-r1` is NOT reused by this PR and is the operator's to delete.
- **CI is not evidence for the backfill:** `_pj_resolve_run_mode` goes serial whenever `CI` is set, so the required `test` check
  proves the rest of the diff, not the scheduler; the scheduler suite and the local measurement carry that burden.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this one carries
  `none` with the sensitive-path scope-out line.
- `lane_declare` with an empty token string: confirm `lane_tokens_for` prints an empty line and `lane_tokens_conflict` treats
  it as fully independent (it does by reading: `read -ra` of "" yields an empty array); the census must not reject an empty
  token field (it checks the reason only). Verify with a unit arm before relying on it.
- Backfill must not use `for x in $queue` word-splitting over token strings containing `*` (the measured bug the drain-barrier
  guard caught); reuse `lane_tokens_conflict`, never re-implement the comparison.
- `_pj_fmt_done` is also called from the torn-reap path in `_pj_reap`; the sidecar append belongs in that shared writer, not in
  one of the three reap sites, and never in `_run_suite_verdict` (the pool reaches it at drain; it would double-count).
- A budget kill signals the whole process group (`timeout -k 10`); a worker that turns the TERM into exit 1 is reaped after the
  deadline, so the sidecar records carry an epoch and the gate ignores records at or after the deadline.
- `lane_tokens_for` returns the override before deriving, so any test that calls it on a real overridden label sees only the
  override; the equality guard must call `_lane_derive`.
- `08` in bash arithmetic is an octal error: parse sidecar rc with `10#`.
- The sidecar must be appended with a single `printf >>` of a short line; a multi-write append can interleave with a concurrent
  reap and corrupt a record (malformed lines are treated as unresolved, which would hide the red).
- The `failed-before-budget` name is new text in a closed catalog; grep the catalog (`common.sh` ~304), the header, the ship
  reference and the tests for the sibling `runner-signal` before closing the phase (the type-widening sweep, three patterns).
