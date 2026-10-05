---
title: "Tasks — move the full-suite gate to post-review (#7352)"
branch: feat-one-shot-7352-fullsuite-gate-post-review
issue: 7352
lane: cross-domain
plan: knowledge-base/project/plans/2026-08-11-chore-move-full-suite-gate-post-review-plan.md
---

# Tasks

Derived from the **post-review** plan. Infrastructure/docs tasks are exempt from RED/GREEN pairing.

> **Read first:** `decision-challenges.md` in this directory holds three surfaced decisions (UC1-UC3).
> **UC1 materially affects task 2.3** — whether the four project-agnostic lines are edited at all.
> Do not start Phase 2 without resolving it, or resolve it as "proceed as directed" and record that.

## Phase 0 — Preconditions (blocking)

- [x] **0.1** Re-derive the next free ADR ordinal across **all** `refs/remotes/origin/*` (not
      `origin/main`). Plan says `ADR-183`; it already moved once mid-session (181 → taken by
      `origin/feat-one-shot-test-pipeline-efficiency`). Record the value actually used.
- [x] **0.2** Check whether `plugins/soleur/test/fanout-suite-scope.test.sh` exists on `origin/main`.
      It is absent today and present on the sibling branch. If it has landed, read whether it asserts
      on §9 prose; if it does, add its assertions to Files-to-Edit **before** rewriting §9.
- [x] **0.3** Confirm ruleset 14145388 still requires `test` and still requires no infra context.
      The ADR's central claim depends on it.
- [x] **0.4** Resolve UC1 (see `decision-challenges.md`). This decides task 2.3's scope.

## Phase 1 — Guard test (regression lock; no RED phase)

- [x] **1.1** Write `plugins/soleur/test/fullsuite-merge-gate.test.ts` with **one** assertion: ship
      Phase 4 prescribes `bash scripts/test-all.sh` with no `TEST_GROUP` argument or prefix.
      Slice the Phase 4 section with the flag-based awk form, never `/A/,/B/`.
      *This assertion passes on `origin/main` today — it is a lock, not a RED. Do not dress it up.*
- [x] **1.2** Mutation-prove it: **shard** the ship command to `bash scripts/test-all.sh webplat`,
      confirm the guard reds, restore. Sharding, not deletion. Record the output for the PR body.
- [x] **1.3** Confirm the new suite is picked up by `bun test plugins/soleur/`
      (`scripts/test-all.sh:883`).

## Phase 2 — `work/SKILL.md`

- [x] **2.1** Retitle §9 and replace its prescription with the `TEST_GROUP` shard gate. Preserve
      `[skill-enforced: work Phase 2 exit]` at `:744` verbatim (hygiene — the linter coupling was
      mutation-disproved, so this is not load-bearing, but keep it).
- [x] **2.2** Retain **all six** reading-discipline passages across `:748-770` under an explicit
      "reading a `test-all.sh` run" sub-heading. §9 ends at **770**, not 768. The six are the four
      originally listed plus `:750-760` (#7376) and `:770` (#5192).
- [x] **2.3** Rewrite the full-suite prescriptions at `:243`, `:337`, `:668`, `:818`.
      **Scope depends on UC1.** `:668` is the largest cost line in the file.
- [x] **2.4** Re-point the stale "the full-suite exit gate catches it" citations at `:589`, `:642`,
      `:649`, `:768` to the shard that covers each.
- [ ] **2.5** Re-scope Sharp Edges `:1080`, `:1081`, `:1083` from "the Phase 2 gate" to "whenever you
      run the full battery".
- [x] **2.6** Add the `LEFTHOOK=0` clause: if any branch commit bypassed lefthook, run the
      corresponding linters explicitly before exiting Phase 2.

## Phase 3 — `ship/SKILL.md` and `plan/SKILL.md`

- [x] **3.1** ship `:326-333` — name **CI's required `test` context** as the merge gate; name Phase 4
      as the last local fail-fast checkpoint and the sole enforcing gate for registered
      `apps/web-platform/infra/` suites. **Never write that the local run is the merge gate.**
- [x] **3.2** ship `:326-333` — state that a reaped Phase 4 is UNRESOLVED per the three-way split
      (`work/SKILL.md:764`) and must be re-run, never shipped on. This replaces the redundancy the
      removed Phase-2 run used to provide.
- [x] **3.3** ship `:338-339` — upgrade the informal `work/SKILL.md` contention reference to a
      markdown link.
- [x] **3.4** ship `:369` — Phase 5 checklist line (`:365` is blank).
- [x] **3.5** plan `:1092` and `:1076` — stop telling planners that these classes are caught at the
      work Phase 2 exit gate.

## Phase 4 — ADR

- [x] **4.1** Write the ADR at the ordinal from task 0.1. Decision line, the two surviving ceilings,
      the corrected R1-R6 table, the **weakened** P3 statement, and three
      `## Alternatives Considered` rows: drop the pre-review gate entirely; add a second run at ship
      Phase 5.5; **let ship Phase 4 shard for speed (rejected — deletes the only enforcing gate the
      registered infra suites have)**.
- [x] **4.2** Note that the pin/re-run mechanism was considered and cut, and why — so a future
      reader does not reinvent it.
- [x] **4.3** One line on the tripwire: if this bites, put the unconditional Phase-2 run back.

## Phase 5 — Verification

- [x] **5.1** `bun test plugins/soleur/` green; `lefthook run pre-commit` passes on the staged set.
- [x] **5.2** AC3 — all six "do not weaken" substrings plus both coverage-NOTE polarity strings
      present.
- [x] **5.3** AC4 — banner-grep byte-identity via `git diff`, not a prefix `grep -F`.
- [ ] **5.4** Full battery at ship Phase 4: `TEST_GROUP=all bash scripts/test-all.sh`, rc from the
      rc file, terminal marker present, epilogue NOTE + contention banners read.
- [ ] **5.5** Re-run task 0.1's ordinal probe immediately before merge; if it moved, sweep
      `knowledge-base/project/{plans,specs}/` for the old ordinal **in the same edit**.

## Phase 6 — Follow-ups

- [ ] **6.1** File the ruleset issue: promote `infra-validation.yml`'s `infra-validate-required`
      into `scripts/required-checks.txt`,
      `scripts/ci-required-ruleset-canonical-required-status-checks.json`, and
      `infra/github/ruleset-ci-required.tf`. This is the real fix for the R5 gap and is a
      branch-protection change — it must not ride inside this PR.
- [ ] **6.2** PR body: `Closes #7352`; the AC2 mutation output; and either the AC12-style measurement
      or a plain statement that the cost case is carried from PRs #7344/#7343 and was not re-measured.
- [ ] **6.3** Ensure `decision-challenges.md` is rendered into the PR body and filed as an
      `action-required` issue.

## Deviations from the plan (recorded at /work time, 2026-08-12)

The plan is authoritative for intent, never for line numbers or exact sets. Five departures:

1. **Task 2.5 is a NO-OP, deliberately.** The plan listed `work/SKILL.md:1080/1081/1083` as Sharp
   Edges needing a re-scope "from *the Phase 2 gate*". Re-read at their current positions
   (`:1126/1127/1129`): none of the three actually references the Phase 2 gate. All three are about
   *reading* a full-battery run — infra coverage, the background-wrapper exit code, ownership of a
   `ps` hit — and remain true verbatim at the ship position. Rewriting three long paragraphs to say
   what they already say would be restatement, which the token-discipline rule forbids. The new §9
   sub-heading ("applies at BOTH positions — this gate and the `/ship` Phase 4 merge gate") carries
   the scope statement once.

2. **Every plan-quoted line number had drifted ~+12** because PR #7441 merged at 17:27 UTC on
   2026-08-11, between plan-time and /work. Content anchors were used throughout: §9 is at `:755`
   not `:742`, the four project-agnostic sites at `:245/349/680/865` not `:243/337/668/818`, and
   `plan/SKILL.md` at `:1098/1114` not `:1076/1092`.

3. **The guard asserts UNSHARDEDNESS, not the absence of a `TEST_GROUP` token.** The plan's Phase 1
   worded assertion 1 as "prescribes `bash scripts/test-all.sh` with no `TEST_GROUP` argument or
   prefix", which contradicts its own AC9 (`TEST_GROUP=all bash scripts/test-all.sh`) — that literal
   assertion would red on the command AC9 mandates. Implemented the intent: accept the two spellings
   of the full run, reject the four shard names in either env-prefix or positional form. Both
   sharding routes are mutation-proven (M1, M2).

4. **Five assertions, not "exactly one".** The plan's count predates OD1, whose AC11/AC12 require the
   fail-safe polarity to be pinned. Added: the ship INFRA_REASON sentence, the C1 conditional, the
   fail-safe default clause (plus its inverted form as a named negative), and a >= 4 count of the
   project-agnostic pointers. All five are mutation-proven; none was added without a mutation that
   reds it.

5. **ADR-183 confirmed free at /work time, not assumed.** `main` tops out at ADR-181; ADR-182 is
   claimed by the open branch `feat-one-shot-7440-zot-log-shipping`. Re-probe before merge per 5.5.

### Mutation matrix — ROUND 1 (SUPERSEDED 2026-08-12; see Round 2 below)

> **Superseded.** The claim below — "No surviving mutants" — was FALSE. All six mutants were
> deletion-or-in-place-inversion, the class chosen *because* it reds. Multi-agent review then
> found **13 surviving mutants** across five axes the battery never touched. Retained verbatim as
> the record of what the first battery actually measured.

| # | Mutation | Result |
|---|---|---|
| M0 | baseline | rc=0, 5 pass |
| M1 | shard ship Phase 4 via env prefix (`TEST_GROUP=webplat`) | rc=1 |
| M2 | shard ship Phase 4 via positional arg (`test-all.sh webplat`) | rc=1 |
| M3 | reword the INFRA_REASON sentence | rc=1 |
| M4 | invert the fail-safe default to the relaxed branch | rc=1 |
| M5 | drop one of the four project-agnostic pointers (4→3) | rc=1 |
| M6 | delete the C1 conditional | rc=1 |
| M7 | post-restore baseline | rc=0, 5 pass |

No surviving mutants **among the six mutations imagined** — which is a much weaker property than it reads as. See Round 2.


### Mutation matrix — ROUND 2 (2026-08-12, post-review) — 13/13 RED

Round 1 had **two axes**, not six: "shard the ship command in a shape my regex parses" and "delete a
literal my `includes()` names". Review supplied the axes it could not reach. Control green before and
after; every mutation asserted LANDED against a pristine backup; both files restored byte-identical.

| # | Axis | Mutation | rc |
|---|---|---|---|
| — | control | unmutated | 0 |
| A1 | ceiling / demotion | rewrite Phase 4's prose to "SKIP this run if Phase 2 ran shards", fence untouched | 1 |
| A2 | ceiling / unparseable shard | `TEST_GROUP=webplat,bun` | 1 |
| A3 | ceiling / spelling | `env TEST_GROUP=webplat …` | 1 |
| A4 | ceiling / spelling | `TMPDIR=/var/tmp TEST_GROUP=webplat …` | 1 |
| A5 | ceiling / computed | `TEST_GROUP=$(bash scripts/derive-shard.sh)` | 1 |
| A6 | ceiling / indentation | two-space indent | 1 |
| A7 | slice / region widening | retitle the terminator heading | 1 |
| A8 | ceiling / rationale | reword the infra reason | 1 |
| B1 | **floor** | revert §9 to an unsharded battery — the PR's own thesis | 1 |
| C1 | OD1 polarity | invert the fail-safe default | 1 |
| C2 | OD1 | delete the C1 conditional | 1 |
| C3 | OD1 identity | strip the pointer from one real prescription site | 1 |
| C4 | OD1 ladder | delete the "each rung ends in an action" rule | 1 |

A3-A6 matter disproportionately: `env …` and `TMPDIR=… ` are **this repo's own documented invocation
idioms** (`work/SKILL.md` prescribes `setsid nohup env TMPDIR=/var/tmp bash -c …`), so an author
sharding for speed would have evaded the Round-1 guard by following the skill's own guidance.

**Known remaining gap, stated rather than papered over.** The OD1 assertion is per-site over a
committed list of six known prescriptions. Adding a *seventh* project-agnostic relaxation with no
pointer is NOT caught — a derived-set assertion would be needed, and deriving "is this line a
prescription?" from prose is not reliable. The compensating control is that the six sites are
enumerated in the test, so deleting or renaming one reds.

### Dispatch floor (added post-review)

`fullsuite-merge-gate.test.ts` is auto-discovered by `bun test plugins/soleur/`, and `bun` exits 0
for a file whose tests are all `test.skip` — so before this change, deleting or skipping the guard
was a green build, and nothing in the repo detected it. It is now enrolled in
`preflight-check10-suite-integrity.test.sh`'s `SUITES` manifest (a `.test.sh` in the `scripts` shard,
so it runs whether or not the bun suites do). Floors ratcheted to the measured values with no slack,
per that file's own contract: `MIN_TESTS` 122→131, `MIN_ASSERTIONS` 514→537, `MIN_MANIFEST_LINES`
117→126. Non-vacuity verified: `perl -pi -e 's/^(\s*)test\(/$1test.skip(/'` on the guard reds the
floor with three distinct `[FAIL]` lines.


## Review round (2026-08-12) — 8-agent panel, report-only

20 findings closed inline; net issue flow **0** (closing #7352, filing #7492).

Panel: `pr-test-analyzer`, `security-sentinel`, `code-simplicity-reviewer`, `architecture-strategist`,
`pattern-recognition-specialist`, `code-quality-analyst` (stalled at 600 s on a wide read, resumed
from transcript with a narrowed scope), `git-history-analyzer`, `user-impact-reviewer` (fired by the
`single-user incident` threshold). Deterministic: semgrep 79 rules / 1 file / 0 findings — rule count
checked, because an invalid `--config` exits 7 and still prints `findings: 0`.

Spawned **report-only**: with 8 concurrent agents the fix-inline default contaminates the shared
worktree, and agents then read each other's uncommitted edits as defects. All fixes applied by the
lead from the pinned SHA `94b258420`.

**Convergence (not lone-agent P1s):** pointer cardinality — 3 agents; the dead `INVERTED_DEFAULT` —
3 agents; the ladder fail-open — 2 agents; the "SOLE gate" overstatement — 2 agents.

**Clean, verified rather than assumed:** provenance (ADR ordinal across all refs, #7441 ancestry and
its two pinned literals, measurement attribution, no auto-close hazard) returned zero findings; the
central "nothing changes for `main`" claim verified — the shard partition is exhaustive, all 155
`run_suite`/`skip_suite` call sites sit in exactly one `want_*` block; and the security-suite
intersection is empty except for `apps/web-platform/infra/`, which has its own required-context gap.

### Deferred, deliberately (recorded rather than silently dropped)

- **§9 restates ~7 claims from ADR-183.** Real token-discipline debt in a file agents read every
  turn. Not trimmed this round: the prose is operationally useful at the point of use, the ADR link
  is present, and a further prose pass on an already-large diff risks a fourth review round for P3
  value. Worth a follow-up pass, not a follow-up issue.
- **A SEVENTH project-agnostic relaxation with no pointer is not caught** — see the Round-2 known
  gap above.
- **`required-checks.txt` bot-PR synthetic `test` green** (pre-existing) and **repo-root `infra/**`
  outside `_infra_in_diff`** (pre-existing) — both out of scope, neither exacerbated by this diff.
