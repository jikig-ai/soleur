---
title: "fix(ci): propagate the signal shape through the two shell wrappers, and widen the orphan linter to a whole-repo walk"
date: 2026-08-13
slug: fix-killed-propagation-and-orphan-suite-globs
branch: feat-one-shot-7429-7402-killed-signal-and-orphan-globs
issue: 7429
closes: [7429, 7402, 7523]
lane: single-domain
type: bug
priority: p1-high
domain: engineering
brand_survival_threshold: none
---

# fix(ci): signal-shape propagation through the wrappers + whole-repo orphan walk

## Overview

Two gates currently report a colour over work they never did, and this PR closes both.
They are the same class and touch disjoint files, so one review cycle covers both.

**Scope A (#7429)** — `scripts/test-all.sh` classifies a signal-shaped child exit as
`[KILLED]` / exit 3 / UNRESOLVED. Two in-repo shell wrappers absorb that shape before
`run_suite` can see it, so a terminated suite behind either still renders `[FAIL]` — the
most alarming available reading, and a false one.

**Scope B (#7402, #7523)** — `scripts/lint-orphan-test-suites.sh` walks only
`scripts/*.test.sh` and `tests/commands/*.sh`. Six tracked suites run in **zero** runners,
four of them under `plugins/soleur/skills/linear-fetch/scripts/` including
`redact-linear-urls.test.sh`, a secret-redaction gate ADR-093 classifies as elevated-stakes.
The linter's own header already claims "EMPTY IS THE GOAL STATE"; this widens its domain to
match its claim.

Both scopes are guard work, and per this repo's history the danger in guard work is in the
guard. Every new check gets a mutation row that drives it RED, including a row against its
own dispatch.

## Premise Validation

Run before any research was dispatched. Five referenced artifacts, four corrections.

| Cited premise | Verified | Verdict |
| --- | --- | --- |
| #7429 open | `gh issue view` → OPEN | HOLDS |
| #7402 open | `gh issue view` → OPEN, p1-high | HOLDS |
| #7523 open (sibling) | `gh issue view` → OPEN | HOLDS |
| PR #7538 draft on this branch | `gh pr view` → OPEN, draft, head matches | HOLDS |
| #7537, #7498 (citations only) | OPEN | HOLDS — out of scope, not work targets |
| All four target files exist | `test -f` on each | HOLDS |
| **"ADR-175 — the taxonomy"** (#7429 body + Scope section) | ADR-175 is `preflight-probe-execution-boundary`; the taxonomy is **ADR-177** | **CORRECTED** |
| **"npm does not propagate 128+N"** (#7429 table row 3) | Re-measured against the real `test:ci` — see below | **REFUTED** |
| **`.claude/hooks/lib/` blind spot** (#7402, 2 of 7 orphans) | `test-all.sh:1205` already includes `.claude/hooks/lib/*.test.sh` (landed via #7409) | **ALREADY FIXED** |
| **`set-board-status.test.sh` "run by board-status-sync.yml"** (#7402 note) | That workflow runs `set-board-status.**sh**` (the script under test) at `:119`; the `.test.sh` appears only in a comment at `:5` | **REFUTED — it is a genuine orphan** |

### The npm row does not reproduce — struck

`#7429`'s table names the webplat registration as the consequential row and calls an OOM kill
of vitest/node "the single most plausible instance of the class". The brief required
re-verification against the **real** `npm run test:ci`, not the synthetic `package.json` the
prior probe used.

Measured on the operator box, 2026-08-13, using the exact registration wrapper from
`test-all.sh:1134-1135` and the real `apps/web-platform` package (`test:ci` = `vitest run`).
The nuance the synthetic probe missed: a kernel OOM kill targets the **largest-RSS** process,
which is the vitest main node — not npm, and not npm's `sh -c` shim. The real tree is:

```
bash -c → bash -c → npm(65MB) → sh -c(2MB) → node vitest(179MB) → 15 worker nodes(~100MB each)
```

Killing the **largest-RSS node** (the 179MB vitest main — the true OOM target):

| Case | Signal | Wrapper rc |
| --- | --- | --- |
| deep node/vitest, the OOM shape | SIGKILL | **137** |
| deep node/vitest | SIGTERM | **143** |
| npm's `sh -c vitest run` shim | SIGKILL | 137 |
| npm's `sh -c vitest run` shim | SIGTERM | 143 |

npm 11.12.1 / node v22.22.2 / bash 5.3.9. **npm propagates the signal shape through the full
chain.** The OOM case the issue calls most plausible already reaches `run_suite` signal-shaped
and already classifies `[KILLED]` today.

**Consequence:** the npm row is struck from the issue body (not carried as an assumption), and
Scope A reduces to the two shell wrappers. ADR-177's §Consequences paragraph naming the same
three wrappers is corrected by the same edit, and its proposed `exec node_modules/.bin/vitest`
remedy — plus the `test:ci` drift pin that remedy would have required — is **not built**,
because there is nothing left for it to fix.

**Recorded limit of this measurement.** A kernel OOM kill of one of the 15 vitest *workers*
(not the main) is a different case: vitest main survives and reports a test failure, so rc=1
and `[FAIL]` is the *correct* classification. This plan does not change that, and does not
claim to.

## Research Reconciliation — Issue Claims vs. Codebase

| Claim | Reality | Plan response |
| --- | --- | --- |
| 3 absorbing wrappers | 2. npm propagates (measured above) | Scope A covers the 2 shell wrappers; strike row 3 from #7429 and amend ADR-177 |
| 7 genuine orphans | **6**, and the set differs | Fix the one remaining glob blind spot + register 2 explicitly |
| `.claude/hooks/lib/` is a blind spot (2 orphans) | Already covered at `:1205`; and `.claude/hooks/lib/session-state.test.sh` **does not exist** (only `freeze-lock.test.sh`, which is covered) | No work needed; record as already-fixed |
| `set-board-status.test.sh` is covered by a dedicated workflow | It is **not** — genuine orphan | Register it explicitly |
| linter is "deliberately ~20 lines with NO companion .test.sh" (`:11-13`) | It is **396 lines**, ~20 checks, four floors, an `eval` de-reference, a derived counter | Rationale is stale; this PR creates the companion suite and rewrites the header |
| `scripts/followthroughs/*.test.sh` invisible to linter (#7523) | True, but all **7** are currently registered | Whole-repo walk subsumes #7523 with **zero** new orphans surfaced |
| exit 3 is top-level-only "per ADR-175 §Consequences" | ADR-**177** §Consequences, pinned by an executed row in `test-all-killed-classification.test.sh` | Decision preserved — see ADR section |

## Research Insights

### Property List (Phase 0.6b)

- **P1** — When a suite dies by signal behind a wrapper, the top-level runner reports
  `[KILLED]`/UNRESOLVED and exit 3, not `[FAIL]`.
- **P2** — That distinction survives an arbitrary number of wrapper layers between
  `run_suite` and the dying process.
- **P3** — A `*.test.sh` added anywhere in the repo and registered in no runner fails a gate.
- **P4** — The orphan gate cannot silently stop detecting (a widened linter that has stopped
  looking and a clean repo emit identical output).

### Cut List (Phase 0.6b)

| Mechanism the ask/ADR proposed | Property it buys | Cut, because |
| --- | --- | --- |
| `exec node_modules/.bin/vitest run` in the webplat registration + a `test:ci` drift pin (ADR-177 §Consequences) | P1 for the npm wrapper | **Measured unnecessary** — npm already propagates 137/143 through the real chain |
| A6 sideband `TEST_TIMING_LOG` KILLED channel (ADR-177 §Alternatives) | P1 **and** P2 | Deferred, not cut — see ADR section. P2 buys nothing today: with npm refuted, each remaining wrapper **already observes its children's raw rc** — `run-registered-suites.sh` via the `.meta` files it writes across `xargs`, `run-all.sh` by capturing the rc it currently discards. A layer that *cannot* observe rc is the case A6 exists for, and none remains in scope |
| Extracting the classifier to `scripts/lib/suite-exit-class.sh` | dedup | ADR-177 §A3 measured this **fatal** for `test-all.sh` — `test-all-infra-coverage-notice.test.sh` sandboxes via single-file `cp "$TARGET"`, so a sourced lib would be absent under test and every KILLED assertion would silently exercise the fallback |
| Naive basename grep against `test-all.sh` for orphan detection | P3 | #7402 records it reports **262** orphans and is wrong — an artifact of the glob loop |

### Anchors established

**`scripts/test-all.sh`**
- `suite_exit_class()` `:291-305` — three guards, all load-bearing: `rc > 128` (else 128
  classifies killed with name `EXIT`), `<= 192` (stated-domain, explicitly *not* load-bearing),
  and a **non-empty** `kill -l` name (else 160/161 render `= SIG` blank on glibc).
- `run_suite()` `:336-424` — rc via `"$@" || rc=$?` (a boolean `if !` was rejected because it
  discards *which* non-zero came back). `[KILLED]` rendered `:418` to stderr.
- Top-level exit `:1374-1378` — `failed>0 → 1`; else `killed>0 → 3`.
- **rc 124 (GNU `timeout`) is deliberately `failed`, not killed** — an attributed verdict.
- **rc 3 from a nested runner is `failed`** — pinned by an executed row.
- The glob loop `:1205` (9 patterns, verbatim in Phase B1 below).
- Linter self-registered `:780`.

**`scripts/lint-orphan-test-suites.sh`** (396 lines)
- Walks `scripts/*.test.sh` `:38-67` (non-recursive) and `tests/commands/*.sh` `:370-382`.
- Registration greps are **command-anchored**, not label-anchored (`:117`, `:124`, `:378`) —
  `:118-123` records the measured escape where keeping the label and swapping the command left
  the linter reporting `orphan test suites: none`.
- `EXCLUSIONS=()` `:30`, format `"name|reason"`, fail-closed at `:51-56`: reason must be
  non-blank **and** contain `#NNNN`.
- Four anti-vacuity floors: `scripts_seen < 1` `:69`, `REQUIRED_RUNNERS < 5` `:110`
  (hand-ratcheted literal), `RELEVANCE_ARRAYS < want` `:233-248` (derived from the runner),
  `cmd_seen < 1` `:387`.
- Invoked from `test-all.sh:780` and `ci.yml:177-178`. **No companion suite exists.**

**`apps/web-platform/infra/run-registered-suites.sh`** (481 lines)
- Derives suites by grepping `run: bash apps/web-platform/infra/*.test.sh` out of
  `infra-validation.yml` `:128-146` (98 today); zero-suite guard → `exit 2` `:150-154`.
- Runs them under `xargs -P "$JOBS"` `:333-341` and **already writes each child's raw rc** to
  `$SOLEUR_SUITE_LOGDIR/<key>.meta` field 1 (PR #7423), read back `:360`, rendered `:362`.
- Returns to its caller via a bare arithmetic command as the final statement `:481`:
  `(( RED == 0 && ${#UNACCOUNTED[@]} == 0 ))` → **0 or 1, never signal-shaped**.

**`.github/scripts/test/run-all.sh`** (56 lines)
- `if ! bash "$t"; then FAIL=1; fi` — **discards rc entirely**; exits 0 or 1.
- Carries a `MIN_SUITES=10` floor (#7068) for exactly the de-existability reason this plan
  applies to the orphan linter.

**ADR corpus**
- **ADR-177** is the taxonomy (not ADR-175). §Consequences: "`3` is a TOP-LEVEL contract only …
  Do **not** adopt exit 3 in a nested runner without revisiting this decision."
- ADR-177 §Alternatives **A6** records the sideband channel as "the one design that makes the
  taxonomy COMPOSITIONAL … survives npm, `xargs` and `if ! bash`", and says **"#7429 should spend
  that freedom deliberately rather than inherit it."** This plan is that deliberate spend.
- ADR-181 addendum: exit `4` = subagent refusal; exit `2` widened to missing relevance data.
- ADR-183: the full battery runs at `/ship`, not at implementation exit.

### Institutional learnings applied

| Learning | Applied as |
| --- | --- |
| `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` | Every guard gets a mutation matrix; the test is "cheapest edit that breaks the named property while leaving the guard GREEN" |
| `2026-07-20-i-fixed-three-unfailable-gates-and-shipped-eight-more.md` | The fix itself is mutation-tested — that session shipped 8 new vacuous gates while fixing 3 |
| `2026-08-09-the-shell-capture-trap-recurred-three-times-and-finally-earned-a-lint.md` | `grep -c` exits 1 on zero matches; guard every capture. `scripts/lint-shell-capture-exit.baseline.txt` already tracks 4 lines in `persist-safe-integration.test.sh` — one of the suites this PR turns on |
| `2026-07-27-the-subshell-bug-i-was-fixing-bit-me-three-more-times.md` | Do not compute killed-counts inside `$( )` or a pipeline subshell. **This plan's first draft violated the rule it cites**: it placed the killed count in the `:360` read loop, which is inside `dump_reds()`, called from a `{ … } 2>&1 \| sed` pipeline at `:442-465`. `run-registered-suites.sh` does **not** "already sidestep" this — it writes `.meta` files and reads them from inside that pipeline, which is safe only because nothing there needs to escape today. Phase A1 step 3 moves the count to the parent |
| `2026-05-18-test-all-tail-masking-and-monitor-exit-condition-tightness.md` | Never pipe a gate through `tail`; capture rc to a file. Governs how this plan's own verification runs |
| `2026-07-05-bash-return-contract-change-blast-radius-includes-subprocess-ts-suites.md` | Changing a runner's return contract has a blast radius of every consumer — enumerated in Phase A0 |
| `2026-07-16-five-documented-traps-recurred…` | SIGPIPE 141 under `pipefail` can invert a gate; relevant to any new pipeline in the widened linter |

### Locale finding (measurement hygiene)

Computing the orphan diff with `comm` requires `LC_ALL=C sort` on both sides. Under the default
locale `comm` emitted `file 1 is not in sorted order` and reported **48** orphans instead of 6 —
a false-positive class that would have made this plan chase 42 phantom orphans. The widened
linter MUST pin `LC_ALL=C` for any sort/comm it performs, and an AC asserts it.

## User-Brand Impact

**If this lands broken, the user experiences:** the repo's test gate either reports green over
suites it never ran (a widened linter that has stopped detecting is byte-identical to a clean
repo), or reports `[KILLED]` over ordinary assertion failures, training the reader to discount
the marker. Both degrade the signal used to decide whether to ship.

**If this leaks, the user's data/workflow/money is exposed via:** no new data surface. The
closest exposure is indirect and *reduced* by this PR — `redact-linear-urls.test.sh`, the
secret-redaction gate for `uploads.linear.app` URLs, currently runs in zero runners, so a
redaction regression can ship undetected. This PR turns it on.

**Brand-survival threshold:** `none` — internal CI tooling; no user-facing surface, no
persistent store, no external data movement. Sensitive-path scope-out: `threshold: none,
reason: the diff touches only test-runner and lint scripts plus one ADR; it creates no schema,
route, auth flow, or migration, and moves no user data.`

## Architecture Decision (ADR/C4)

ADR-177 explicitly delegated a decision to #7429 and this plan must spend it rather than inherit
it. Detection fires on "a reversal or extension of an existing ADR".

### ADR

**Create `ADR-187` — nested runners signal UNRESOLVED by exit-shape, not by a new contract.**
Extends ADR-177 (which stays authoritative for the taxonomy) and appends a two-line pointer
addendum to ADR-177 in the same commit, matching the precedent ADR-181 set there.

The three decisions ADR-187 records:

1. **A nested runner that observed a signal-killed child, and no assertion failure, exits with
   that child's signal-shaped rc (`128+N`).** `run_suite` then classifies it `[KILLED]` with no
   change to the classifier. This is *within* ADR-177's declared semantics, not a lie about the
   wrapper: ADR-177's own classification rule states "`$?` cannot distinguish a signal death
   from a deliberate one", and the rendered `[KILLED]` line already says "exit $rc is also what
   a suite calling exit($rc) reports". The marker means **signal-shaped**, never "was killed by".

2. **Exit 3 remains a TOP-LEVEL contract only — ADR-177's decision is preserved, not reversed.**
   The executed row pinning `3 → failed` in `test-all-killed-classification.test.sh` stands
   unchanged. Decision 1 is precisely *why* no reversal is needed: a nested runner never needs
   to emit 3, because it emits `128+N`. Recording this as a deliberate re-affirmation is the
   answer to the brief's "record the decision either way".

3. **A6 (the sideband `TEST_TIMING_LOG` KILLED channel) is considered and deferred, with the
   trigger named.** It is the only design that buys P2 (composition through arbitrary wrapper
   depth). P2 buys nothing today: npm is refuted, and each remaining wrapper **already observes
   its children's raw rc** — `run-registered-suites.sh` via the `.meta` files it writes across
   `xargs`, `run-all.sh` by capturing the rc it currently discards. A layer that *cannot* observe
   rc is the case A6 exists for, and none remains in scope. Its cost is real —
   `TEST_TIMING_LOG` becomes a CONTRACT rather than ad-hoc telemetry, and three files must be
   taught to write it. **Re-evaluation trigger:** the first wrapper that cannot know its
   children's rc (a runner shelling out through a tool that itself discards rc), or a third
   nesting level appearing between `run_suite` and a suite.

Per `wg-defer-only-after-inline-triage`, the per-wrapper WHY and the reader's conclusion:

| Wrapper | Can it propagate? | WHY / what the reader should conclude |
| --- | --- | --- |
| `run-registered-suites.sh` | **Yes** | Already records each child's raw rc in `<key>.meta` field 1. Nothing blocks it; it simply returns a boolean today |
| `.github/scripts/test/run-all.sh` | **Yes** | `if ! bash "$t"` discards rc by construction; capturing it is a 2-line change |
| webplat `npm run test:ci` | **Not applicable** | Measured to already propagate 137/143. A reader seeing `[FAIL]` on this suite should conclude a genuine assertion failure — **not** a swallowed kill |
| vitest **worker** OOM (sub-case) | **No, and correctly so** | vitest main survives and reports a test failure; rc=1 and `[FAIL]` is the accurate classification. A reader should not expect `[KILLED]` here |

**Ordinal is PROVISIONAL.** ADR-186 is the highest claimed across all 69 `origin/*` refs, so
ADR-187 is next-free as of 2026-08-13. `/ship`'s ADR-Ordinal Collision Gate re-verifies before
merge. On renumber, sweep this plan, `tasks.md`, and every AC naming the ordinal in the same
edit.

### C4 views

**No C4 impact.** Per the completeness mandate this is not a keyword grep — all three model
files were read (`model.c4` 688 lines, `views.c4` 74, `spec.c4` 54) and the four required
categories enumerated:

- **(a) External human actors** — `founder`, `emailSender`, `betaContact`, `contributor` are the
  four modelled. This change adds no correspondent, reviewer, or recipient. `contributor`'s
  description already covers PR-head test execution boundaries; this PR changes *which suites
  run*, not *whose code executes where* or under what isolation.
- **(b) External systems / vendors** — none added. npm/vitest/bash are build tooling and are not
  modelled as C4 elements; no inbound webhook, outbound API, or third-party store is introduced.
- **(c) Containers / data stores** — none touched. No new store, queue, or cache.
- **(d) Actor↔surface access relationships** — unchanged. No ownership, sharing, or tenancy
  boundary moves.

No element description is falsified by this change, so no correctness edit is required either.

## Guard Contract

Three guards ship. Each carries Property, Assembly (structural, not a member snapshot), and a
mutation matrix written **from the design, before the guard**.

### Guard 1 — whole-repo orphan-suite linter

**Property.** Every tracked `*.test.sh` in the repository is executed by at least one runner, or
carries an explicit exclusion naming a reason and a tracking issue.

**Assembly.** Not "the 339 files that exist today" — members drift with every commit. The
structural assembly is `git ls-files '*.test.sh'` (the producer of record) diffed against the
union of **five registration chokepoints**, every one of which must be enumerated or the guard
under-reports coverage and cries wolf:

1. explicit `run_suite … bash <path>` lines in `scripts/test-all.sh`
2. the glob patterns on `scripts/test-all.sh:1205` (expanded against the worktree)
3. `run: bash <path>.test.sh` steps in `.github/workflows/infra-validation.yml`
4. the per-app `main.test.sh` hook, `infra-validation.yml:357-364`
5. `run: bash <path>.test.sh` in every other `.github/workflows/*.yml`

There is more than one chokepoint, and that is the point: a guard scoped to only
`test-all.sh` would classify all 98 infra suites as orphans.

**Mutation matrix** (each must drive the linter RED; each run individually):

| # | Mutation | Must fail because |
| --- | --- | --- |
| M1 | Delete a registered suite's `run_suite` line from the sandbox `test-all.sh` | **verify-the-verifier** — re-introduces a *real* orphan into a tree copy |
| M2 | Add **two** new unregistered `*.test.sh` files under directories no glob covers, and assert **both** are named in the output | the walk must reach arbitrary paths, and must report the whole difference rather than stopping at the first member. Two orphans in one row is strictly stronger than a separate "second member" row, and unlike that row it stays meaningful under a set-difference implementation |
| M3 | Delete one `run: bash …test.sh` step from the sandbox `infra-validation.yml` | **surface 3 carries 98 of the ~339 tracked suites** — by an order of magnitude the largest contributor and the likeliest to silently under-match. Surfaces 1 and 2 were double-covered while this one had no row at all |
| M4 | Keep a `run_suite` label but swap its command to a different script | registration must stay **command**-anchored (the measured escape at `:118-123`). This is the row that closes the *silent* direction — a parser degrading toward a bare-path grep inflates the covered set and hides real orphans behind a green "none", which no floor can detect |
| M5 | Delete one glob pattern from `test-all.sh:1205` | the suites it covered become orphans — **only reds if the patterns are derived from the runner, never duplicated into the linter** (see Phase B1 step 2) |
| M6 | Neuter the walk so it enumerates zero files (**own dispatch**) | the anti-vacuity floor must fire — a guard reporting "0 checked" and exiting 0 is vacuous. This is the single most valuable row here: it is the only one covering the direction where failure is byte-identical to success |
| M7 | Add an exclusion with a reason but **no** `#NNNN` | fail-closed exclusion discipline preserved |

### Guard 2 — `run-registered-suites.sh` signal propagation

**Property.** When a derived infra suite is terminated by a signal and no suite failed an
assertion, `run_suite` renders `[KILLED]` and `test-all.sh` exits 3.

**Assembly.** The per-suite rc values in `$SOLEUR_SUITE_LOGDIR/<key>.meta` field 1 — **all** of
them, for every derived suite, not the first RED found. The classification chokepoint is the
`.meta` read loop at `:360`, and the exit chokepoint is the final arithmetic statement at `:481`.

**Mutation matrix:**

| # | Mutation | Must fail because |
| --- | --- | --- |
| M1 | A child dies by a **real signal** (`kill -KILL $$` inside the fixture suite — **not** `exit 137`), none fail → assert **end-to-end** `[KILLED]` in `test-all.sh` output **and** top-level exit 3 | the operator constraint: assert the classification is reached. A hardcoded `exit 137` tests the arithmetic, **not** the propagation chain — only a real signal proves rc survives `xargs`, the `.meta` write, and the read loop |
| M2 | One child 137 **and** one child 1 | failure dominates — must be exit 1, mirroring ADR-177's top-level contract |
| M3 | A child exits **124** (GNU `timeout`) | must stay `[FAIL]` — an attributed verdict, per `suite_exit_class` parity |
| M4 | A child exits 137 **and** a suite is UNACCOUNTED | unaccounted must keep forcing 1 |
| M5 | Revert the propagation to the bare `(( RED == 0 && … ))` | the end-to-end assertion must red |
| M6 | Two children killed by **different** signals (SIGKILL + SIGTERM) | must not stop at the first, and must apply the deterministic selection rule below |

**Deterministic selection rule (required).** With more than one killed child the runner MUST emit
a reproducible rc, or two runs of the same failure report different numbers. Rule: **the
signal-shaped rc of the lexicographically-first suite key among the killed set** — derived from
the already-sorted `.meta` iteration, so it needs no extra state. State it in the runner's header
and pin it with M6.

### Guard 3 — `.github/scripts/test/run-all.sh` signal propagation

**Property.** When a fixture suite is terminated by a signal and none failed an assertion, the
runner exits signal-shaped so `run_suite` renders `[KILLED]`.

**Assembly.** The rc of **every** iteration of the `for t in "$DIR"/test-*.sh` loop — captured,
not discarded by `if ! bash "$t"`. Chokepoints: the loop body and the terminal exit block.

**Mutation matrix:**

| # | Mutation | Must fail because |
| --- | --- | --- |
| M1 | A fixture suite dies by a **real signal** (`kill -KILL $$`, not `exit 137`) → assert end-to-end `[KILLED]` + exit 3 | same constraint as Guard 2 — a hardcoded exit tests arithmetic, not propagation |
| M2 | One killed **and** one failed | failure dominates → exit 1 |
| M3 | Restore `if ! bash "$t"` | the end-to-end assertion must red |
| M4 | Killed suite present **and** `RAN < MIN_SUITES` | the pre-existing floor must still dominate |
| M5 | Two killed suites, different signals | must not stop at the first; same deterministic rule as Guard 2 |

### The A6 tripwire — why the deferral in ADR-187 is safe rather than hopeful

Signal-shape mimicry is an **in-band** channel with no alarm of its own: its correctness depends
on every present *and future* layer propagating raw rc, and the failure mode is invisible, because
"no kills occurred" and "a kill was swallowed" render identically. ADR-187's stated re-evaluation
trigger ("the first wrapper that cannot know its children's rc") is phrased in terms nothing
automated checks — it fires only if a future author happens to remember it.

The **real-signal** M1 rows in Guards 2 and 3 are what convert that trigger from a memory into a
detection. The day a new absorbing layer is introduced anywhere between `run_suite` and a suite,
the canary reds and points at ADR-187. This is load-bearing: without it, decision 1 is a bet with
no tripwire. It is also why M1 must use `kill -KILL $$` and never `exit 137`.

## Implementation Phases

Phase order is load-bearing: **contract changes precede consumer changes**, and the ADR lands
with the code that makes it true.

### Phase A0 — blast-radius enumeration (no edits)

Changing a runner's return contract has a consumer blast radius. Enumerate before editing:

```bash
git grep -rn 'run-registered-suites\|scripts/test/run-all' -- \
  '*.sh' '*.yml' '*.ts' '*.md' | grep -v knowledge-base/project/
```

Record every consumer and whether it is binary zero/non-zero or reads a specific code.
ADR-177 measured every top-level consumer binary; re-confirm for these two nested runners —
notably `infra-validation.yml`'s invocation and `run-registered-suites.test.sh`.

**Two A0 questions are already answered at plan time; do not re-litigate them, verify they still hold:**

1. **Does `run-registered-suites.test.sh` sandbox via single-file `cp`?** **No.** It takes
   `SUT="${SUT:-apps/web-platform/infra/run-registered-suites.sh}"` (`:21`) and drives mutants as
   whole files via `SUT="$m"` (`:614`). So ADR-177 §A3's single-file-`cp` constraint — which is
   what forbids a sourced lib for `test-all.sh` — **does not bind this file**. The decision to
   inline the classifier here therefore rests on the cross-tree-dependency argument
   (`apps/web-platform/infra/` sourcing `scripts/lib/`) and on parity with `run-all.sh`, **not**
   on §A3. Record it that way rather than citing a constraint that does not apply.

2. **Does any CI layer special-case 137/143?** Measured: no auto-retry, no OOM annotation, no
   exit-code branching in `.github/workflows/*.yml` that would intercept a signal-shaped rc from
   these runners.

**Consumer drift found at plan time — must be fixed in this PR.**
`.github/workflows/main-health-monitor.yml:580` tells the operator, in the issue body it files
for a KILLED run, that "the six suites this runner starts via `bun`/`node` directly can surface
one". After this PR that set grows by **108** — 98 infra suites behind `run-registered-suites.sh`
plus 10 fixture suites behind `run-all.sh`. Left unedited, the guidance under-states the search
space on exactly the issue an operator reads when a suite is terminated.

### Phase A1 — `run-registered-suites.sh` propagation (RED first)

**Two defects in this plan's first draft were caught at plan-review and are corrected here. Both
were fatal; do not reintroduce either.**

> **D1 — `RED` already counts killed children, so a naive killed-branch is dead code.** The xargs
> child at `:339` emits `if (( rc == 0 )); then echo "PASS $s"; else echo "RED  $s"; fi`, and
> `:346` counts `RED=$(grep -c '^RED ' "$LOG")`. A SIGKILLed child has rc 137, which is non-zero,
> so **it already prints `RED`**. A precedence of `RED>0 → exit 1` therefore fires in every case
> where the killed branch would, and the killed branch can never execute.
>
> **D2 — the `.meta` read loop at `:360` lives inside a pipeline subshell.** It sits in
> `dump_reds()` (`:352`), which is called at `:442` inside a block that terminates
> `} 2>&1 | sed "s/^/${SENTINEL_PREFIX}/"` at `:465`. Any counter incremented there evaporates
> at `:466`. Counting killed suites in that loop is the `2026-07-27` subshell trap recurring
> inside the plan that cites it.

The corrected design keeps `RED` as the **superset** (total non-zero) and derives `killed` as a
subset, rather than re-partitioning `RED`. That choice is what preserves four things a
re-partition would have broken:

1. **Steps**

   1. Extend `run-registered-suites.test.sh` with Guard 2's mutation rows, including the
      **end-to-end** arm that drives the real `test-all.sh` `run_suite` over a sandboxed runner
      and asserts `[KILLED]` + exit 3. Confirm RED.
   2. Inline a classifier with **two** guards — `rc > 128` and a non-empty `kill -l $((rc-128))`.
      Do **not** copy the `<= 192` bound: ADR-177 states verbatim that it "is **NOT** load-bearing
      and no test pins it", so copying it propagates dead code to a new drift surface and invites
      the archaeology that sentence exists to prevent. Keep rc 124 → `failed`.
   3. **Count `killed` in the PARENT**, immediately after `RED=`/`PASS=` at `:346-347` — outside
      `dump_reds`, outside the `{ … } | sed` pipeline. Iterate `"$SOLEUR_SUITE_LOGDIR"/*.meta`,
      `read -r rc _ < "$m"`, classify, and record both the count and a deterministic `kill_rc`.
      Then `failed=$(( RED - killed ))`.
   4. Replace the terminal `(( RED == 0 && ${#UNACCOUNTED[@]} == 0 ))` at `:481` with:
      `failed>0 || UNACCOUNTED>0 → exit 1`; `killed>0 → exit "$kill_rc"`; else `exit 0`.
   5. Confirm GREEN, then re-run each mutation individually and confirm each reddens.

2. **What the superset choice preserves — verify each still holds after the edit**

   - **The child's emit shape is untouched.** `PASS <path>` / `RED  <path>` (two spaces) is
     byte-pinned by `run-registered-suites.test.sh:252` (T6b) and `:310` records it as the shape
     "every downstream consumer" reads. Adding a third emit class would break it. Do not.
   - **Logdir retention at `:469-470` needs no edit.** It keys on `RED == 0`, and `killed > 0`
     implies `RED > 0`, so a killed run already keeps its logs — which is exactly when they are
     most wanted. A re-partition of `RED` would have started deleting them.
   - **The summary line at `:480` stays BYTE-IDENTICAL.** It has **two exact-string consumers**:
     `run-registered-suites.test.sh:442` (`… 1 passed, 0 failed, 0 unaccounted (of 1) …`) and
     `plugins/soleur/test/main-health-monitor-workflow.test.sh:554,571`
     (`… 91 passed, 1 failed, 1 unaccounted (of 93) …`). Adding a fourth number breaks both.
   - **Report `killed` on a separate line gated on `killed > 0`**, mirroring `test-all.sh`'s own
     breakdown-line precedent (`:1317-1319`), which is emitted only when `killed > 0` precisely so
     clean output stays byte-identical. This is the established shape in this repo for exactly
     this problem; follow it rather than inventing a fourth column.

   Note the `${RED} failed` label on `:480` becomes imprecise when a suite was terminated
   (it counts killed suites among "failed"). Correcting the *label* would break both pinned
   consumers, so the gated breakdown line carries the precision instead, and a comment at `:480`
   records why the label is retained.

### Phase A2 — `.github/scripts/test/run-all.sh` propagation (RED first)

Same shape. Note this file has **no companion suite**; its Guard 3 arm lands in a dedicated
fixture suite whose home is decided in A2.1 by where the sandbox harness is cheapest, and which
is registered either way.

1. Write Guard 3's five mutation rows. Confirm RED.
2. Replace `if ! bash "$t"; then FAIL=1; fi` with rc capture + classification; keep the
   `MIN_SUITES` floor dominant.
3. Confirm GREEN; mutate each row individually.

**Constraint:** this file feeds `guard-script-fixture-tests`, a REQUIRED check with no path
filter that gates every PR. Its header mandates BASH-ONLY suites — the change must add no
external tooling.

### Phase A3 — ADR-187 + ADR-177 amendment + issue-body correction

1. Write `ADR-187`, recording the three decisions above.
2. Append a pointer addendum to ADR-177 and **correct its §Consequences wrapper list** — strike
   the npm row, cite the 2026-08-13 measurement, and remove the now-unnecessary
   `exec node_modules/.bin/vitest` remedy and its drift pin.
3. Strike the npm row from #7429's body (the brief's explicit instruction: strike, do not carry).

### Phase B1 — widen the orphan linter (RED first)

The nine current glob patterns at `test-all.sh:1205`, enumerated (never a basename grep):

```
plugins/soleur/test/*.test.sh
plugins/soleur/skills/*/test/*.test.sh
plugins/soleur/scripts/*.test.sh
.claude/hooks/*.test.sh
.claude/hooks/lib/*.test.sh          # already present — #7402's second blind spot is CLOSED
apps/cla-evidence/scripts/*.test.sh
apps/web-platform/scripts/*.test.sh
apps/web-platform/scripts/lib/*.test.sh
scripts/lib/*.test.sh
```

1. **Create `scripts/lint-orphan-test-suites.test.sh`** with Guard 1's seven mutation rows
   against a sandboxed tree copy. Confirm RED against the current linter.
2. Widen the linter to the whole-repo walk: `git ls-files '*.test.sh'` diffed against the
   five-surface union in Guard 1's Assembly. Pin `LC_ALL=C` for all sorting.
3. Preserve the `"name|reason"` + `#NNNN` fail-closed exclusion discipline verbatim.
4. **Re-key the anti-vacuity floors.** `scripts_seen < 1` `:69` is keyed on the old
   `scripts/*.test.sh` walk and becomes meaningless; replace with a floor on the whole-repo
   count **and** a floor on each of the five covered-set surfaces (a surface that silently stops
   contributing makes real suites look orphaned). Keep `cmd_seen` and `REQUIRED_RUNNERS`.
5. Rewrite the stale `:11-13` header rationale ("deliberately ~20 lines with NO companion
   .test.sh") — it is false at 396 lines and is cited as precedent by `scripts/lint-workflows.sh:25`.
   Update that citation too.
6. Register the new suite in `test-all.sh` (`scripts/*.test.sh` is hand-registered) and add it to
   the linter's own `REQUIRED_RUNNERS`.

### Phase B2 — close the remaining orphans to zero

| Orphan | Disposition |
| --- | --- |
| `plugins/soleur/skills/linear-fetch/scripts/assert-no-linear-telemetry.test.sh` | Add glob `plugins/soleur/skills/*/scripts/*.test.sh` to `:1205` |
| `…/linear-fetch/scripts/parity.test.sh` | same glob |
| `…/linear-fetch/scripts/persist-safe-integration.test.sh` | same glob |
| `…/linear-fetch/scripts/redact-linear-urls.test.sh` | same glob — **the ADR-093 elevated-stakes redaction gate** |
| `scripts/board/set-board-status.test.sh` | Explicit `run_suite` — `scripts/board/` is covered by no glob, and #7402's claim that `board-status-sync.yml` runs it is refuted |
| `apps/web-platform/test/__synthesized__/parse-gitleaks-allowlists.test.sh` | Explicit `run_suite` — tests the gitleaks allowlist parser |

**Before adding the new glob, verify it matches ≥1 real file and enumerate what it newly
sweeps in** — a `plugins/soleur/skills/*/scripts/*.test.sh` glob may pull in suites beyond the
four linear-fetch ones. Any newly-swept suite that is slow, needs credentials, or is not
CI-safe must be triaged in this PR (registered, or excluded with reason + issue), not
discovered at first CI run.

Then run the four turned-on linear-fetch suites and **fix or exclude** whatever they surface.
`scripts/lint-shell-capture-exit.baseline.txt:145-148` already records four S1 shell-capture
findings in `persist-safe-integration.test.sh`; a suite that has never run may not be green.

### Phase B3 — subsume #7523

The whole-repo walk reaches `scripts/followthroughs/*.test.sh` **by construction** — no
dedicated loop needed, unlike the `tests/commands/` case. Measured: all **7** followthrough
suites are currently registered, so widening surfaces **zero** new orphans there. That
retires #7523's stated worry ("widening may surface pre-existing orphans, which is its own
triage job") without a triage job.

State this explicitly rather than overlapping silently: **this PR closes #7523**, and its
checkbox item ("note the linter has a minimum-cardinality floor keyed on its resolved default
dir that will need adjusting") is discharged by Phase B1 step 4.

## Files to Edit

- `scripts/test-all.sh` — add one glob pattern `:1205`; two explicit `run_suite` lines; register the new linter suite
- `scripts/lint-orphan-test-suites.sh` — whole-repo walk, five-surface covered set, re-keyed floors, corrected header
- `apps/web-platform/infra/run-registered-suites.sh` — classify `.meta` rcs; signal-shaped exit at `:481`
- `apps/web-platform/infra/run-registered-suites.test.sh` — Guard 2 mutation rows + end-to-end arm
- `.github/scripts/test/run-all.sh` — rc capture, classification, signal-shaped exit
- `scripts/lint-workflows.sh` — update the stale `:25` precedent citation
- `.github/workflows/main-health-monitor.yml` — `:580` under-states which suites can surface a signal-shaped exit once both wrappers propagate (see Phase A0)
- `knowledge-base/engineering/architecture/decisions/ADR-177-…md` — addendum + corrected wrapper list

## Files to Create

- `scripts/lint-orphan-test-suites.test.sh` — Guard 1's seven mutation rows
- `knowledge-base/engineering/architecture/decisions/ADR-187-…md` — provisional ordinal
- a fixture suite for Guard 3 (home decided in A2.1)

## Open Code-Review Overlap

**None.** Queried 63 open `code-review` issues; none names any of the four target files.

## Observability

```yaml
liveness_signal:
  what: "scripts/lint-orphan-test-suites.sh terminal line — `orphan test suites: none` (exit 0) or `orphan test suites: <n>` (exit 1)"
  cadence: "every PR (ci.yml:177) and every local/CI full gate (test-all.sh:780)"
  alert_target: "the CI job's own red; main-health-monitor.yml for post-merge main"
  configured_in: ".github/workflows/ci.yml:177-178, scripts/test-all.sh:780"
error_reporting:
  destination: "CI job failure + test-all.sh [FAIL]/[KILLED] markers on stderr"
  fail_loud: true
failure_modes:
  - mode: "Linter silently stops detecting (walk enumerates nothing)"
    detection: "anti-vacuity floors — whole-repo count floor plus a per-surface floor on each of the five registration surfaces"
    alert_route: "linter exits 1 with an explicit floor message; CI red"
  - mode: "A registration surface stops contributing, so real suites read as orphans"
    detection: "per-surface floor (Guard 1 / Phase B1 step 4)"
    alert_route: "linter exits 1 naming the surface; CI red"
  - mode: "A suite is terminated by a signal behind a wrapper and reads as [FAIL]"
    detection: "run_suite renders [KILLED] with the decoded 128+N; top-level exit 3"
    alert_route: "main-health-monitor.yml anchors the exact (exit=N, signal-shaped 128+n = SIGNAME, Nms) shape"
  - mode: "A wrapper fabricates a signal shape over an ordinary assertion failure"
    detection: "Guard 2 M2/M3 and Guard 3 M2 — failure dominates, and rc 124 stays [FAIL]"
    alert_route: "mutation rows red in the suite"
logs:
  where: "TEST_TIMING_LOG rows (ok/KILLED/FAIL/skip) + CI job logs"
  retention: "CI log retention; TEST_TIMING_LOG is per-run local"
discoverability_test:
  command: "bash scripts/lint-orphan-test-suites.sh"
  expected_output: "orphan test suites: none"
```

## Acceptance Criteria

### Pre-merge (PR)

**Scope A**

- [ ] AC1 — `bash scripts/lint-orphan-test-suites.sh` prints `orphan test suites: none` and exits 0.
- [ ] AC2 — A sandboxed infra suite exiting 137 with no RED drives `run-registered-suites.sh` to exit 137, and the **real** `run_suite` renders `[KILLED]` with `test-all.sh` exiting **3**. Asserted end-to-end, not on the wrapper's rc alone.
- [ ] AC3 — One child 137 + one child 1 → `run-registered-suites.sh` exits **1** (failure dominates).
- [ ] AC4 — A child exiting **124** still renders `[FAIL]`, never `[KILLED]`.
- [ ] AC5 — A child 137 with a suite UNACCOUNTED → exit **1**.
- [ ] AC6 — Same end-to-end assertion as AC2 for `.github/scripts/test/run-all.sh`.
- [ ] AC7 — `run-all.sh` with a killed suite **and** `RAN < MIN_SUITES` still fails on the floor.
- [ ] AC8 — Every Guard 2 and Guard 3 mutation row, applied **individually**, drives its suite RED. Recorded as a row-by-row table in the PR body, not asserted in aggregate.
- [ ] AC9 — `test-all-killed-classification.test.sh`'s executed row pinning `3 → failed` is **unchanged**, proving exit 3 stayed top-level-only.

**Scope B**

- [ ] AC10 — `git ls-files '*.test.sh'` diffed (under `LC_ALL=C`) against the five-surface union returns **zero** orphans.
- [ ] AC11 — Each of the six named orphans is registered and executes: assert each appears in `TEST_TIMING_LOG` (or the runner's suite list) after a run, not merely that a `run_suite` line exists.
- [ ] AC12 — The four linear-fetch suites pass, or carry an exclusion with a reason and a `#NNNN`.
- [ ] AC13 — Every Guard 1 mutation row (M1–M7), applied **individually** to a tree copy, drives the linter RED. M1 and M6 are the load-bearing rows: M1 re-introduces a real orphan; M6 proves the guard cannot report "0 checked" and exit 0.
- [ ] AC14 — Adding an exclusion whose reason lacks `#NNNN` fails the linter (discipline preserved).
- [ ] AC15 — The new glob's newly-swept set is enumerated in the PR body, and every member is registered, passing, or excluded.
- [ ] AC16 — `scripts/lint-orphan-test-suites.test.sh` is itself registered in `test-all.sh` and listed in `REQUIRED_RUNNERS`.

**Cross-cutting**

- [ ] AC17 — ADR-187 exists, records all three decisions, and ADR-177 carries the pointer addendum with its wrapper list corrected (npm row struck, citing the measurement).
- [ ] AC18 — #7429's body no longer asserts the npm row; the measurement is recorded there.
- [ ] AC19 — No stale `ADR-175`-as-taxonomy citation remains in the touched files.
- [ ] AC20 — The ADR ordinal is re-verified free across all `origin/*` refs immediately before merge; on renumber, this plan, `tasks.md`, and every AC naming it are swept in the same edit.
- [ ] AC21 — PR body uses `Closes #7429`, `Closes #7402`, `Closes #7523`.
- [ ] AC22 — `main-health-monitor.yml:580`'s operator guidance no longer claims only "the six suites … via `bun`/`node` directly" can surface a signal-shaped exit; it names the widened set (both wrappers). Asserted by grepping the updated ACTIONS text, not by eyeballing.
- [ ] AC23 — Guard 2 M1 and Guard 3 M1 use a **real** signal (`kill -KILL $$`) and not `exit 137`, asserted by grepping the suites for the absence of a hardcoded `exit 137` in the E2E arms. This is the A6 tripwire; a simulated exit would make it vacuous.
- [ ] AC24 — With two children killed by different signals, the runner's rc is **reproducible across repeated runs** (deterministic selection rule), asserted by running the fixture twice and comparing.

### Post-merge

None. Every step runs in-session; nothing is handed off.

## Test Strategy

Convention is `.test.sh` with sandboxed tree copies — no new framework. `bats` is **not**
installed; do not introduce it.

**Contention discipline.** The box is 16 cores; resting load measured 3.99/7.04/9.35 from
Claude Code sessions alone, and 14.89 at the time of this plan's probes.

- Prefer the touched shards: `TEST_GROUP=scripts` for Scopes A2/B, `TEST_GROUP=infra` for A1.
- Run any long gate under `setsid nohup`, writing rc to a **file**; read the rc file, never a
  completion notification, and never pipe through `tail` (masks the exit).
- Before diagnosing a red, read the contention preamble and the `LOCK_`/`BANNER` lines
  (`SIBLING_RUN_DETECTED`, `SIBLING_SUITE_DETECTED`, `LOCK_CONTENDED_PROCEEDING`) — a red under
  contention is not automatically a defect in the diff.
- Per ADR-183 the full battery runs at `/ship`, not at implementation exit.
- Any probe that kills processes MUST scope every `pgrep`/`pkill` to its own `setsid` session
  id. A global `pkill -f 'node.*vitest'` would kill a concurrent session's suite — this plan's
  own npm probe was rewritten to enforce that before it was run.

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| The widened linter stops detecting and reads identical to a clean repo | Guard 1 M6 (own-dispatch row) + per-surface floors; AC13 requires individual mutation |
| A wrapper fabricates a signal shape over a genuine assertion failure | Failure dominates (AC3, AC6); rc 124 stays `[FAIL]` (AC4) |
| Classifier now duplicated in three files and drifts | Guard 2 M3 / Guard 3 pin the 124 rule in each copy; extraction to a shared lib is rejected by ADR-177 §A3 for the measured single-file-`cp` reason — re-confirm in Phase A0 |
| The new glob sweeps in suites that are slow or need credentials | Phase B2 enumerates the newly-swept set **before** adding it; AC15 gates on it |
| Turned-on suites fail — they have never run | Expected; Phase B2 budgets for fix-or-exclude, and the shell-capture baseline already flags four lines in one of them |
| `run-all.sh` gates every PR via a REQUIRED no-path-filter check | Change stays BASH-ONLY per its header; `MIN_SUITES` floor kept dominant (AC7) |
| ADR-187 ordinal collides mid-pipeline | Verified across all 69 `origin/*` refs; re-verified at ship (AC20) |
| Locale-dependent `comm`/`sort` produces phantom orphans | `LC_ALL=C` pinned in the linter; this plan's own measurement hit exactly this (48 vs 6) |

## Alternative Approaches Considered

| # | Alternative | Why rejected |
| --- | --- | --- |
| A1 | Adopt A6's sideband `TEST_TIMING_LOG` channel now | Buys P2, which nothing needs today once npm is refuted. Makes `TEST_TIMING_LOG` a contract and teaches three files to write it. Deferred in ADR-187 **with a named re-evaluation trigger** rather than dropped |
| A2 | Make exit 3 a nested contract too | Reverses ADR-177 with an executed row pinning it, and is unnecessary: `128+N` mimicry reaches `[KILLED]` through the existing classifier with no contract change |
| A3 | `exec node_modules/.bin/vitest run` in the webplat registration | Measured unnecessary — npm already propagates. Would also bypass the package's declared entry point and require a `test:ci` drift pin, for zero gain |
| A4 | Extract the classifier to `scripts/lib/suite-exit-class.sh` | ADR-177 §A3 measured this fatal for `test-all.sh` (single-file `cp` sandbox → silent fallback) |
| A5 | Naive basename grep for orphan detection | #7402 records it reports 262 orphans and is wrong |
| A6 | Add `scripts/followthroughs/*.test.sh` as its own loop (literal #7523 ask) | The whole-repo walk subsumes it structurally; a dedicated loop would be a second thing to keep in sync |

## Deferrals

- **A6 sideband channel** — deferred in ADR-187 with a named trigger. No new issue: the
  decision and its trigger live in the ADR, which is the durable record, and #7429 closes here.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. Product/UX Gate does not
fire: the mechanical UI-surface scan over `## Files to Edit` and `## Files to Create` matches no
UI path (no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`), and the change
creates no user-facing surface.
