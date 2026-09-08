---
title: "fix: preflight Check 10's suite-integrity parser cannot read a colour-coded bun summary"
date: 2026-09-08
slug: fix-check10-ansi-summary-parser
branch: feat-one-shot-7466-check10-ansi-summary-parser
issue: 7466
closes: 7466
lane: cross-domain
type: bug
priority: p2-medium
domain: engineering
brand_survival_threshold: aggregate pattern
---

## Enhancement Summary

**Deepened on:** 2026-09-08 · **Halt gates:** 4.6 pass, 4.7 pass, 4.8 pass, 4.9 skip (no UI
surface), 4.10 skip (no store or connection), 4.11 pass (`lint-guard-contract.py` green,
2 entries). **Reviewers:** DHH, code-simplicity, Kieran, spec-flow-analyzer,
architecture-strategist, plus a scoped strong-model consult and a CTO domain assessment.

**Key improvements from the deepen pass**

1. **The direct predecessor learning was missing and is now the anchor.** #7393 / PR #7397 —
   the work that built this file — supplies the question every mutation row answers ("what is
   the cheapest edit that breaks the property this guard NAMES, while leaving it GREEN?") and
   the deletion-direction, absolute-floor and apply-it-to-itself rules the matrix follows.
2. **The severity of D2 is now stated correctly.** The fail-open does not merely make one row
   untrustworthy — it un-does the specific mechanism #7397 added (counting `skip`/`todo` to
   close the suppression family *by measurement*), leaving only the source grep that the same
   learning documents as out-spellable.
3. **Every citation resolved live:** 5 AGENTS rule IDs all active (none retired or
   fabricated), 2 ADRs exist, issue #7466 OPEN with the cited title, every `knowledge-base/`
   path present.
4. **A fourth false negative caught and narrowed.** "Nothing greps this file's output" is
   false (a learning quotes one of its strings); restated as "no *executable* consumer".

**New considerations discovered**

- Verified-negative sweep: the plan asserted four universal negatives; **four were wrong**
  (the "only" ANSI filter — five sites; "zero" sibling parsers — one; "no learning covers
  ANSI" — three; "nothing greps the output" — one prose hit). All corrected, and the pattern
  is recorded as a Sharp Edge.
- The corpus vacuity guard's `floor_lines_of` matches only `-lt`/`-le`/`-ge` threshold
  shapes, so the new boolean unmeasured FATAL is **not** covered by it — recorded rather than
  assumed.

## Overview

The suite-integrity gate that backstops preflight Check 10 reads its verdict out of
`bun test`'s printed summary. Four of its five counters anchor at start-of-line, which a
colour-coded summary line cannot satisfy because that line opens with an escape sequence
rather than whitespace. The fifth counter is unanchored and matches, so a run reports an
assertion total beside a zero test count. The failure-count arm then treats an unparsed
value as a measured zero and reports success on a measurement that never happened.

This plan makes the parse colour-blind, proves it with fixtures that must go red when the fix
is reverted, and makes every arm that reports on a counter refuse to report success on a count
it did not read.

No spec.md exists for this branch, so `lane:` defaulted to `cross-domain` (TR2 fail-closed).

## Problem

`plugins/soleur/test/preflight-check10-suite-integrity.test.sh` — the anti-vacuity gate over
Check 10's three regression suites — parses bun's summary at its five `n_*` assignments
(`grep -n 'n_pass=\$(grep -oE'` locates the block; four anchored at `^[[:space:]]*`, the
fifth unanchored).

Three defects, each measured on this branch:

**D1 — the anchors cannot cross an escape sequence.**

| input | `grep -cE '^[[:space:]]*([0-9]+) pass'` |
|---|---|
| `\e[0m\e[32m 122 pass\e[0m` | **0** |
| <code> 122 pass</code> | **1** |
| the coloured line after an ANSI strip | **1** |

`n_expect`'s pattern is unanchored, which is why a run reports an assertion total beside a
zero test count — one asymmetry, one cause.

**D2 — the failure-count arm is fail-open.** `n_fail` parses empty, the later
`: "${n_fail:=0}"` turns that into `0`, and the arm reads the default. Measured end to end:

```
[FAIL] could not parse bun's summary block — treating as UNMEASURED, not as zero
  (measured: pass=0 fail=0 skip=0 todo=0 expect=539)
[ok] bun's summary reports no failing tests
[ok] no tests skipped or todo'd at runtime
```

The skip/todo arm carries the identical mechanism on the adjacent line.

**What D2 actually costs.** The predecessor work (#7393 / PR #7397) added the `todo` and `skip`
counters for one stated reason: *"measure work, not source shape, wherever a measurement
exists"* — `describe.todoIf(true)` had removed four tests while the source-pattern grep stayed
green and the gate printed `no tests skipped at runtime`. Parsing bun's counts closed that whole
family **by measurement**, because the source grep "could always be out-spelled". When the parse
fails open, that measurement silently reverts to nothing and the out-spellable source grep is
the only surviving control — so D2 does not merely make one row untrustworthy, it un-does the
specific mechanism the predecessor added to close the suppression family.

**D3 — the unanchored counter reads non-summary text.** Measured:
`grep -coE '([0-9]+) expect\(\) calls'` returns **1** against
<code>  see 999 expect() calls in the docs</code>, and `tail -1` takes the last match. The anchored form
returns **0**. This is the latent instance of the same class, on the one counter the issue's
own fix does not touch.

**Why it survived.** CI is non-TTY and neither `.github/workflows/ci.yml` nor
`scripts/test-all.sh` sets a colour variable, so bun emits no colour there. The reachable
environments are agent harnesses and pty wrappers exporting `FORCE_COLOR` — the execution
path this repo's own pipeline runs on.

## The five measured facts the design turns on

Everything below was executed on this branch against bun 1.3.11, not reasoned about. Four of
the five were found only at plan-review, and each one invalidated an earlier draft.

**F1 — bun's summary omits a counter that is zero, and that includes `expect() calls`.**
Measured on an all-`.skip` suite:

```
 0 pass^[[0m
 ^[[0m^[[33m2 skip^[[0m
^[[0m^[[2m 0 fail^[[0m
Ran 2 tests across 1 file.
```

`grep -c 'expect() calls'` → **0**. Only `pass` and `fail` are unconditional. Consequence: a
"measured" predicate that requires `expect` would report the **all-skip run** — the one case
this gate exists to catch — as *"could not parse bun's summary block"* and never print
`coverage silently removed`. The predicate therefore reads `pass` and `fail` only.

**F2 — colour placement is value-dependent.** In the same capture: <code> 0 pass^[[0m</code> puts the
space **first**, <code> ^[[0m^[[33m2 skip^[[0m</code> puts space-then-ESC-then-digits, and
`^[[0m^[[2m 0 fail^[[0m` puts ESC first. A single coloured fixture cannot represent bun's
output; a plan that narrates one shape will produce a fixture bun never emits.

**F3 — a process substitution is a pipe, so a multi-read parser drains it.** Measured with
the identical fixture:

```
multi-read  <( ): r1=[122 pass] r2=[]
single-read <( ): r1=[122 pass] r2=[122 pass]
```

A parser that strips once **per counter** returns `122 - - - -` for every fixture while the
live path (a real, re-readable file) returns all five — the self-checks and the live run
would disagree in a way that looks exactly like the bug being fixed.

**F4 — a `-` sentinel at a numeric comparison is fail-OPEN, where an empty string was
fail-CLOSED.** Measured:

| value | `[[ "$v" -lt 131 ]]` | effect on a SUT floor |
|---|---|---|
| `""` | true | floor **fires** |
| `"-"` | `arithmetic syntax error` on stderr, returns **false** | floor **silently skipped** |

Introducing the sentinel therefore *flips the polarity* of every unguarded comparison. It
does not crash; it prints one stderr line nobody reads and the gate goes green.

**F5 — an SGR-only strip is not enough, and neither is a naive CSI class.** Parsed value
after each strip:

| input | narrow `\[[0-9;?]*[A-Za-z]` | ECMA-48 |
|---|---|---|
| `\033[0m\033[32m 122 pass` | 122 | 122 |
| `\033[38:2:0:255:0m 122 pass` (colon SGR) | **empty** | 122 |
| `\0337 122 pass` (DECSC, no `[`) | **empty** | 122 |
| `\033(B 122 pass` (charset) | **empty** | 122 |

Under the new fail-closed arms each survivor is a hard RED on a healthy tree — the
cries-wolf mode this file already warns gets a gate bypassed. The ECMA-48 form does **not**
over-strip: `at foo (/src/a.ts:10:5) expected [1;2] arr[0]a` passes through unchanged.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality on this branch | Plan response |
|---|---|---|
| Gate reports `10 passed, 2 failed`; suites are `122 pass / 514 expect` | Uncoloured: `=== 13 passed, 0 failed (13 checks) ===`, exit 0. `FORCE_COLOR=1`: `=== 11 passed, 1 failed (12 checks) ===` + `[FATAL] SUT floor`, exit 1. Real counts `132 pass / 539 expect`; `SUITES` holds **three** files. Floors: `MIN_TESTS=131 MIN_ASSERTIONS=537 MIN_MANIFEST_LINES=126 MIN_CHECKS=13` | Issue numbers are stale; the mechanism reproduces exactly. Re-measure every floor at /work |
| "the existing suite passes its own parse tests" | The file has **no** parser self-tests | The fixture work is net-new |
| bun 1.3.11 vs `.bun-version` 1.3.14 | Confirmed; `scripts/test-all.sh` itself banners `WARNING: Bun 1.3.11 installed, expected 1.3.14` | Not a contributing factor. Fixtures are synthesized, so self-checks are version-independent; bun's real format is policed by the live run |
| Colour appears in interactive environments | **Not reproducible without forcing it** — bun does not colour a redirected stream here. Reproduction needs `FORCE_COLOR=1` | The trigger is an ambient variable, not a TTY check on the redirected stream |
| Suggested strip `sed -e 's/\x1b\[[0-9;]*m//g'` | `\x1b` is a GNU sed extension (BSD sed silently no-ops), and SGR-only is insufficient — see F5 | Both corrected in D-1 |

## Research Insights

### Premise Validation

`gh issue view 7466` → `OPEN`, no closing PRs. The work target still carries the four
anchored greps. Every numeric claim was re-measured. ADR corpus grepped for the mechanism
(`grep -rlniE 'ansi|strip_ansi|escape sequence'` over the decisions directory) — no ADR
decides how this repo strips escape sequences, so it is not an ADR-rejected alternative.

### Property List

- **P1** — every counter bun's summary block prints for a test outcome (`pass`, `fail`,
  `skip`, `todo`, `expect() calls`) is read, whether or not the runner coloured it. Bun also
  prints `N error` on a module-load crash; that counter is **deliberately out of scope** —
  the existing `bun test exited N` row already fails that run — and the property is worded to
  say so rather than to be falsified by it.
- **P2** — no arm reports a passing verdict on a counter it did not read.
- **P3** — a regression that re-breaks the colour-blind parse is caught by an executed check.
- **P4** — a line that merely *mentions* a counter is not read as the summary.

### Cut List

Cut before research; ‡ cut or reversed at plan-review:

| Mechanism | Property | Disposition |
|---|---|---|
| A committed fixture file | P3 | Cut — inline `printf '\033…'` buys it with no new file and no editor silently de-colouring literal ESC bytes (`cq-test-fixtures-synthesized-only` satisfied by construction) |
| A `$LOG.plain` tempfile | P1 | Cut — a path-reading function buys it with no allocation, leaving `scripts/lint-trap-tempfile-ownership.py` (ADR-129) and the `cleanup()`/`KEEP_LOG` surface untouched |
| `NO_COLOR=1 bun test` **as the fix** | P1 only | Cut — controls the producer, buys nothing for P2/P3/P4 |
| A PATH-stubbed `bun` harness | P2 at arm level | Cut — the mutated-copy harness (Phase 3) drives the arms without shipping a bypass |
| ‡ A three-token verdict enum | none beyond a boolean | **Cut.** Two of three consumers collapsed two of the tokens, and the enum created its own fall-through fail-open (a mistyped token reaching `[ok]`) that then needed an exhaustive `case`, a `*) fail` default, a mutation row and a grep-shaped AC to police. Collapsing to a boolean dissolved all four |
| ‡ `parse(colour) == parse(plain)` equivalence | P3 | Cut — entailed by two checks already pinned to the same literal; no mutation reddens it alone |
| ‡ `tr '\r' '\n'` as CR *deletion* | P1 | Kept as a **translation** inside `strip_ansi`, not deleted: measured, bun's redirected output carries no CR, but a `\e[1G` rewrite is only recoverable by splitting the line, and the cost is one `tr` |
| ‡ A named `strip_ansi` wrapper | P1 | **Reversed.** An earlier draft inlined it as a one-liner. F5 grew it to a locale-pinned three-line pipeline with two rules, which warrants a name and makes "delete the strip" a one-line mutation |
| ‡ A `CHECK10_LOG_OVERRIDE` env seam to drive the arms over synthetic logs | P2 at arm level | **Rejected on security grounds.** It would let any environment hand this gate a synthetic green summary and skip running bun entirely — a bypass shipped into the very gate whose thesis is that a suite asserting nothing is indistinguishable from one that passed. Arm-level coverage comes from the mutated-copy harness instead |

### Verified repo mechanisms and blast radius

- **The GNU-only strip is repo-wide, not a one-off.** `git grep -n 's/\\x1b'` returns **five
  code sites**: the precedent at
  `plugins/soleur/skills/git-worktree/test/orphan-reaper-honest-count.test.sh` ›
  `strip_ansi()`, plus `apps/web-platform/infra/git-data-userdata-budget.sh` (×2) and
  `apps/web-platform/infra/registry-userdata-budget.sh` (×2) — all four infra sites carrying
  the same GNU-only, SGR-only form, in scripts that gate Terraform userdata budgets. An
  earlier draft of this plan claimed the precedent was the only such filter; that claim was
  false (the grep behind it was shell-mangled) and is corrected here. This plan does **not**
  widen its scope to fix them — they are out of scope, and the compound step records the
  class so the next reader of those files has the two facts. `scripts/lib/strip-log-injection.sh`
  › `strip_log_injection()` is broader but deletes newlines, so it cannot serve a
  line-anchored parser.
- **Blast radius for the EDIT is one file; the defect class has one sibling.**
  `plugins/soleur/test/git-fixture-env.mutation.sh` › the `calls=$(grep -oE '[0-9]+ expect\(\)
  calls' … | grep -oE '^[0-9]+' | tail -1)` line carries the **same two-stage bun-summary
  parse**. It is immune to D1/D2 (its stage one is unanchored, and it fails closed on an empty
  result) but carries **D3 verbatim** — a mid-log `see 999 expect() calls` matches and
  `tail -1` takes it. It is a `.mutation.sh`, so not auto-globbed, and `git grep` across
  `scripts/`, `.github/`, `lefthook.yml` and `package.json` finds no registration: a
  manually-run harness. An earlier draft claimed zero siblings; corrected. **Deliverable:**
  file a `code-review` follow-up issue for D3 in that file rather than widening this PR
  (`wg-when-deferring-a-capability-create-a`).
- **No executable consumer greps this file's output.** `git grep -lF` over each of
  `could not parse bun`, `measured: pass=`, `no tests skipped`, `suite integrity` and
  `bun's summary reports` returns no matcher outside the file itself; the single external hit
  is prose in the predecessor learning, not a matcher. So the output format is free to change
  — but this plan does not change it, to keep that true. (Stated as "no executable consumer"
  rather than "nothing greps": the broader negative is false.)
- **`scripts/guard-vacuity-floor.test.sh` already covers this file** (ADR-193 Decision #5 —
  the population is derived by shape). Baseline measured: `Total: 23 passed, 0 failed`,
  exit 0, `MIN_CONSERVING=33` against a current 43, so no ratchet there moves. Its **ARM 10d**
  classifies a function as a terminal verdict helper only if it moves a verdict counter in its
  own body; a wrapper that merely *calls* one "is the correct home for the case increment".
  Verified by running that classifier against a prototype: zero offenders. **Caveat carried
  forward:** its `floor_lines_of` matches only `-lt`/`-le`/`-ge` bracket tests, so the new
  unmeasured FATAL — a boolean branch, not a threshold — is **not** covered by that guard.
  Its own comment says a floor in an unmatched shape "is bounded by NOTHING here"; this plan
  records that rather than silently assuming coverage.
- **This file's FIRES classification hangs on a textual adjacency, and two of that guard's
  arms have ZERO slack.** Its `build_mutant` widens a floor's slice backward only over
  *contiguous* `NAME=value` lines, so `MIN_CHECKS=13` binds only because it sits on the line
  **immediately** above `if [[ "$cases" -lt "$MIN_CHECKS" ]]` (verified: lines 344–345, with
  the explanatory comment block *above* the assignment). Insert a blank line or a comment
  between them and the mutant dies at `MIN_CHECKS: unbound variable` → CONSTRUCTION →
  `classify_suite` falls through to the conservation candidate, which measures NO_FIRE → the
  corpus guard's **ARM 1 (`n_nofire -eq 0`, zero slack)** reddens, in a different file.
  **ARM 2** (`n_construct <= 15`) is also at 15/15. By contrast `MIN_FIRING_SUITES` (38 vs 79)
  and `MIN_CONSERVING` (33 vs 43) both have slack and do **not** move. Mutation M13 pins the
  adjacency.
- **Two more shape constraints in the same guard.** ARM 10d derives the case counter by
  grepping `if \[\[ \$\(\([^)]*\)\) -ne "?\$\{?…` — reindent or reformat
  `if [[ $((PASS + FAIL)) -ne "$cases" ]]` and extraction returns empty, the arm silently
  `continue`s, and this file drops out of that arm's coverage **with no arm reddening**. Keep
  that line byte-shaped and say why at the site.
- **Preflight Check 10 SKIPs this PR.** Check 10 is path-gated on `SENSITIVE_PATH_RE`
  (`plugins/soleur/skills/preflight/SKILL.md` › Check 10 Step 10.1). Measured: this diff's
  three paths match none of it (`grep -E` → rc 1). The `## Observability` block is therefore
  documentation, never an executed probe, for this diff — which also moots `bun` being absent
  from Check 10's sandbox `PATH`.
- **Invocation:** `scripts/test-all.sh` auto-globs `plugins/soleur/test/*.test.sh` and runs
  each as `run_suite "$f" bash "$f"` in the `scripts` shard. No shellcheck runs on this path.
- **Precedent for an instrument self-test:** `plugins/soleur/test/net-issue-flow.test.sh`
  verifies its own verdict helpers move their counters before trusting them.

### Institutional learnings this plan must honour

| Learning | Rule |
|---|---|
| `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` | **The direct predecessor** (#7393 / PR #7397 — the work that built this very file). Supplies the question every row of the Guard Contract below answers: *"what is the cheapest edit that breaks the property this guard NAMES, while leaving the guard GREEN?"* Also: **close the deletion direction** (every presence-style assertion stays green when the thing is deleted — hence M1, M7, M10, M12 and M14 are all deletions); **a floor indexed to its own input is not a floor**, and *"slack between a floor and the measured value is not padding — it is the budget an attacker spends"* (hence `MIN_CHECKS` ratchets to the measured value with none); and **an anti-vacuity control needs the same reasoning applied to itself** (hence the own-dispatch rows) |
| `knowledge-base/project/learnings/2026-08-05-every-green-signal-certified-something-other-than-what-it-claimed.md` | A guard whose default on a missing measurement is "pass" is fail-open; a comment asserting fail-closed does not make it so |
| `knowledge-base/project/learnings/2026-08-10-six-times-a-check-certified-something-other-than-what-it-named.md` | "A green suite is evidence about the fixture before it is evidence about the code." The revert-the-fix arm is the only proof a check *can* go red |
| `knowledge-base/project/learnings/best-practices/2026-07-03-pass-is-not-proof-three-vacuous-green-traps-in-infra-verification.md` | Ask "what would make this pass without the thing under test being true?" |
| `knowledge-base/project/learnings/2026-08-20-the-check-failed-because-the-thing-it-checked-for-was-there.md` | `producer \| grep -q` is unsafe under `pipefail`; capture first. A fixture must *make* the condition live |
| `knowledge-base/project/learnings/2026-07-29-every-guard-i-fixed-this-session-was-narrower-than-the-claim-it-carried.md` | Normalise the artifact **before** the oracle runs over it |
| `AGENTS.rules.md` `cq-assert-anchor-not-bare-token` | Anchor on syntax, never a bare token; mutation-test every new assertion |
| `AGENTS.rules.md` `cq-ac-must-not-depend-on-concurrent-sessions` | An AC a sibling worktree can flip measures the machine |
| `AGENTS.rules.md` `hr-never-git-stash-in-worktrees` | Mutations run against a **copy**, never by editing the tracked file |
| `knowledge-base/project/learnings/2026-05-11-tr-does-not-interpret-hex-escapes.md` | `tr` does not interpret `\xHH`; use octal `\NNN`. D-1's `tr '\r' '\n'` uses escapes `tr` *does* interpret, so it is safe — recorded so the next editor does not "modernise" it to `\x0d` |
| ADR-193 | Floors report `printf >&2` + `exit 1` directly; the case counter moves at the call site, never inside a terminal verdict helper, never inside `$( )` |

**The compound step corrects standing prescriptions rather than closing a gap.** An earlier
draft claimed no learning covered ANSI in shell parsing; that was false. Three do, and **all
three prescribe the exact GNU-only, SGR-only form this plan measured wrong** (F5):

- `2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr.md`
  — *"ANSI-coloured marker made the failure counter always read 0 … Prevention: never grep a
  colourised marker; use the summary line"*, prescribing `sed -r 's/\x1b\[[0-9;]*m//g'`.
- `2026-07-15-a-guard-that-never-ran-has-more-than-one-reason-and-indexof-block-scoping-swallows-siblings.md`
  — *"my first mutation battery's grep was defeated by vitest's ANSI codes and printed zero
  output for all four mutations; I nearly read the silence as success"*, same prescription.
- `test-failures/2026-06-30-vi-waitfor-floor-vs-component-rearm-race.md` — same form.

The first two are the same defect class as D1 on a different runner, and the second is a
near-miss of the *vacuous-RED* failure this plan's mutation matrix exists to prevent. The
compound deliverable is therefore to add the two facts this plan measured — `\x1b` is a GNU
sed extension, and an SGR-only strip is defeated by a non-SGR CSI — to those learnings, not to
write a fourth that repeats their advice.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --limit 200` returned 63 issues;
none names this file, `preflight-check10`, or `check10`.

## User-Brand Impact

**If this lands broken, the user experiences:** a preflight gate that either cries wolf on a
healthy tree — the shape that gets a gate bypassed — or keeps reporting `[ok]` while Check
10's three regression suites have been silenced, so a sandbox-boundary regression reaches the
operator's workstation behind a green pipeline.

**If this leaks, the user's workflow is exposed via:** nothing. One repo-private test script;
no secrets, no network path, nothing written outside `TMPDIR`.

**Brand-survival threshold:** `aggregate pattern`. A single degraded run is loud today; the
harm is a *class* of suppression regressions shipping undetected. No per-PR CPO sign-off at
this threshold. The diff touches no sensitive path, so preflight Check 6's `threshold: none`
scope-out bullet does not apply.

## Design

### D-1 — `strip_ansi`: POSIX ESC, ECMA-48 ranges, locale-pinned, read once

```
ESC=$(printf '\033')            # NOT the backslash-x escape — that form is a GNU sed
                                # extension; BSD sed matches the literal characters instead
strip_ansi() {                  # <path> -> stripped text on stdout
  LC_ALL=C tr '\r' '\n' < "$1" \
    | LC_ALL=C sed -e "s|${ESC}\[[0-?]*[ -/]*[@-~]||g" -e "s|${ESC}[ -/]*[0-~]||g"
}
```

- `[0-?]` / `[ -/]` / `[@-~]` are ECMA-48's parameter, intermediate and final byte ranges;
  the second rule catches every two-byte escape (`\0337`, `\033(B`). Verified against F5's
  table, including the no-over-strip control.
- `LC_ALL=C` is load-bearing: the ranges are locale-dependent without it.
- The `|` delimiter avoids the `/`-inside-bracket trap — an escaped `/` in a bracket
  expression was measured turning the class into `0x20-0x5C` and eating <code> 122 p</code>.
- `tr '\r' '\n'` **translates**, never deletes: deleting a CR concatenates overwritten text
  onto the summary line and the anchor fails again.
- OSC (`ESC ] … BEL`) is out of scope — bun emits none. A `\e[1G` rewrite with stale text
  *before* the escape is likewise not recoverable by stripping alone; both are stated in the
  comment rather than implied to be covered.

### D-2 — `parse_bun_summary`: pure, path in, one line out, **input read exactly once**

```
parse_bun_summary() {           # <path> -> "pass fail skip todo expect", '-' where unread
  local plain; plain="$(strip_ansi "$1")"   # ONCE. See F3.
  # …five two-stage greps over <<< "$plain"…
}
```

Takes a **path**, **echoes** five space-separated fields; the caller binds them with one
`read`. It assigns nothing in the caller's scope, and its internals are named `plain`/`one`/
`v` — never `n_*`. (`local plain` is required and correct; the constraint is only that the
function must not `local`-shadow or write the caller's `n_*` names.)

Three constraints, each pinned by a measurement:

- **Read the input exactly once (F3).** Fixtures arrive as process substitutions, which are
  pipes; a per-counter `strip_ansi "$1"` returns `122 - - - -` on every fixture while the live
  file path returns all five. Mutation M6 pins it.
- **Echo rather than assign.** A function assigning into the caller's scope must never be
  reached through a pipe — measured: `printf … | f` loses all five (subshell). The loss is
  silent and mimics the bug being fixed. Worse, the self-checks run before the live run, so a
  parse that failed to write would leave the **fixture** tuple standing and report it as a
  real measurement. Echoing removes the hazard by construction.
- **Every second-stage grep stays unanchored.** `n_expect`'s second stage is currently
  `grep -oE '^[0-9]+'`. Anchoring stage one makes it emit the leading whitespace, so stage
  two's `^` never matches — measured **empty** on a healthy `514 expect() calls`, a false RED
  on every green run.

`n_expect` gains the `^[[:space:]]*` first-stage anchor the other four already have (P4).
`-` is the placeholder for an unread field; an empty field would collapse under `read`'s
default IFS and shift every later field left.

### D-3 — `summary_measured <pass> <fail>`: a boolean over the two unconditional counters

```
summary_measured() {            # exit 0 iff $1 and $2 are both integers
```

**`expect` is not an input (F1).** Bun omits `expect() calls` when zero, so requiring it would
report the all-skip run — the flagship suppression case — as an unparseable summary and
suppress the `coverage silently removed` diagnosis it exists to print. `pass` and `fail` are
the only unconditional counters, and a genuinely unparsed log still has `pass=-`, so nothing
is lost.

All three reporting arms and both SUT floors sit inside `if summary_measured …; then … else
<all fail with an explicit *unmeasured* message> fi`. The `: "${n_*:=0}"` defaults are
**deleted**: correctness must not depend on statement order, and printing `pass=-` on an
unparsed run is more honest than `pass=0`.

### D-4 — normalise before comparing (F4)

First statements inside the measured branch, before any arithmetic:

```
# skip / todo / expect are omitted from bun's summary when zero, so '-' means 0 HERE — and
# only here. Outside this branch '-' means UNKNOWN. Nothing below may compare a '-'.
for v in n_skip n_todo n_expect; do [[ "${!v}" == "-" ]] && printf -v "$v" 0; done
```

Without it, `[[ "-" -gt 0 ]]` prints an arithmetic error to stderr and returns **false**, so
the skip/todo arm prints `[ok] no tests skipped` on a comparison that errored — on the
**happy path**, since bun omits both lines on a clean run. The same value at
`[[ "-" -lt 131 ]]` makes the SUT floor *silently stop firing*: F4 shows the sentinel is
fail-**open** where today's empty string was fail-**closed**. Check N1 asserts the counters
are integers at the point of comparison, and AC16 asserts the green run's stderr is empty —
so a leaked `-` reddens an executed check instead of printing a line nobody reads.

**The floors carry their own measurement gate, at the comparison.** Relying on the enclosing
branch places the predicate and the comparison in different statements, where a later edit can
separate them and nothing reddens. Each SUT floor therefore reads:

```
if ! [[ "$n_pass" =~ ^[0-9]+$ ]]; then      # UNMEASURED: never fall through to a comparison
  printf '\n[FATAL] SUT floor: test count UNMEASURED — an unparsed summary is not a zero.\n' >&2
  echo "=== $PASS passed, $FAIL failed ($cases checks) ==="; exit 1
elif [[ "$n_pass" -lt "$MIN_TESTS" ]]; then
  …the existing floor FATAL…
fi
```

so the predicate travels with the comparison and cannot be orphaned. Mutation M14 deletes the
`if !` arm and must still exit 1.

**Note for a future reader:** this new FATAL, like the two SUT floors and the manifest floor,
exits before the accounting-conservation check. That is compliant with ADR-193 Decision #4,
which orders conservation first only where a floor and conservation can fire on the *same*
fault — they cannot here, since the floor reads `cases` and conservation reads `PASS+FAIL`.
Say so at the site so nobody "fixes" the order.

### D-5 — self-check lane, symbol guard, and an unconditional parse row

A `--- 0. Parser self-test ---` section runs **before** the live run, so a broken parser is
**named** rather than surfacing only as a confusing "0 tests passed". It does **not**
short-circuit: `fail()` records a verdict and returns, so the live `bun test` still executes —
the section improves the diagnosis, not the runtime. (An early `exit 1` was considered and
rejected: it would skip the accounting-conservation check.) Immediately above it:

```
declare -F strip_ansi parse_bun_summary summary_measured >/dev/null \
  || { printf '\n[FATAL] parser symbols absent — a missing function would read as a wrong answer.\n' >&2; exit 1; }
```

so a `command not found` can never masquerade as a parse defect.

The existing "could not parse" row gains an `else` recording `pass "bun's summary block
parsed"`. That makes the check count deterministic (a green run scores 13 today, a coloured
run 12) and, under `FORCE_COLOR=1`, is the **only** per-check record that the strip worked on
real bun output — everything else asserting P1 is a fixture. The comment above that row
currently justifies the absence of an `else`; it must be rewritten, not left standing.

`cases` is incremented inside the `assert_*` wrappers, unconditionally, before the pass/fail
branch — the shape ARM 10d sanctions (verified by running its awk against the planned wrapper:
zero offenders), and the shape that keeps conservation non-tautological.

**Two placements are load-bearing for the corpus guard and must be commented as such:**
`MIN_CHECKS=<n>` stays on the line immediately above its `if` (no blank line, no comment
between — see Research Insights), and `if [[ $((PASS + FAIL)) -ne "$cases" ]]` keeps its exact
byte shape.

## Files to Edit

- `plugins/soleur/test/preflight-check10-suite-integrity.test.sh` — the whole change.
- `knowledge-base/project/plans/2026-09-08-fix-check10-ansi-summary-parser-plan.md`

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-7466-check10-ansi-summary-parser/tasks.md`
- A `code-review` follow-up issue for D3 in `plugins/soleur/test/git-fixture-env.mutation.sh`
  (the one sibling carrying the same two-stage parse), filed rather than fixed inline so this
  PR stays scoped (`wg-when-deferring-a-capability-create-a`).
- **Amendments** to the three existing learnings that prescribe the GNU-only, SGR-only strip
  (listed under Research Insights) — the compound step corrects standing prescriptions rather
  than adding a fourth that repeats them.

## Implementation Phases

### Phase 0 — Baseline and preconditions

1. Record the green terminal line both ways (`env -u FORCE_COLOR -u CLICOLOR_FORCE`, and
   `FORCE_COLOR=1`).
2. Capture bun's real coloured bytes for **both** shapes (F2) and paste them verbatim from
   `cat -v` into the comments beside the fixtures: a non-zero run and an all-`.skip` run.
3. **Precondition gate:** confirm on the pinned bun that `pass` and `fail` are printed
   unconditionally and that `skip`/`todo`/`expect() calls` are omitted when zero. D-3's
   predicate and D-4's normalisation both rest on that split. Verified on 1.3.11; re-verify
   on 1.3.14.
4. `bash scripts/guard-vacuity-floor.test.sh` — record the green line (baseline 23/23).

### Phase 1a — Scaffold, no behaviour change

Land `strip_ansi`, `parse_bun_summary` and `summary_measured` **carrying today's defective
behaviour**: `strip_ansi` is `cat`, `n_expect` stays unanchored, and `summary_measured`
ignores `fail`. The gate stays green at its current `MIN_CHECKS`.

Not optional bookkeeping: without it the Phase 1b checks fail with `command not found`, a RED
indistinguishable from a real defect — the vacuous-RED class this file exists to prevent.

### Phase 1b — RED

Add the self-test section. Against the Phase 1a scaffold the honest split is:

| id | fixture / call | expectation | vs scaffold |
|---|---|---|---|
| S1 | plain summary, deliberately **non-green**: `122 pass / 3 fail / 1 skip / 2 todo / 514 expect` | `122 3 1 2 514` | GREEN |
| S2a | bun's measured coloured **non-zero** shape (ESC-first `pass`/`fail`, uncoloured `expect`) | `132 0 - - 539` | RED |
| S2b | bun's measured coloured **all-skip** shape (<code> 0 pass^[[0m</code> space-first, space-ESC-digits `2 skip`, **no** `expect` line) | `0 0 2 - -` | RED |
| S3 | exotic escapes: colon-SGR, `\0337`, `\033(B` before a summary | `122 3 - - 514` | RED |
| S4 | decoy: no summary block, plus a mid-log <code>  see 999 expect() calls in the docs</code> | `- - - - -` | **RED** — today's unanchored `n_expect` reads `999` |
| V1 | `summary_measured - -` | false | GREEN |
| V2 | `summary_measured 122 -` — the exact #7466 shape | false | **RED** (scaffold ignores `fail`) |
| V3 | `summary_measured - 0` — isolates `pass` | false | GREEN |
| V4 | `summary_measured 122 0` | true | GREEN |
| N1 | on the live run, after normalisation | `n_skip`/`n_todo`/`n_expect` all match `^[0-9]+$` | RED |
| N2 | instrument self-test: `assert_parse` with a deliberately wrong expectation increments `FAIL` by exactly 1 | +1 | GREEN |

Publish that table in the PR — a *mixed* result is the point: it shows the harness
discriminates rather than reddening wholesale.

### Phase 2 — GREEN

Contract before consumers: (1) `strip_ansi` becomes real (D-1); (2) `parse_bun_summary` reads
once, anchors `n_expect`, keeps every second stage unanchored (D-2); (3) `summary_measured`
requires `pass` and `fail` to be integers (D-3); (4) rewrite the consumption block —
`read -r n_pass n_fail n_skip n_todo n_expect <<< "$(parse_bun_summary "$LOG")"`, normalise
inside the measured branch (D-4), hold every arithmetic comparison and both SUT floors there,
and fail all three arms in the `else` with an explicit *unmeasured* message. Delete the
`: "${n_*:=0}"` defaults and rewrite the now-false comment above the parse row.

### Phase 3 — Ratchet, mutate, verify

1. Re-run green and **read `MIN_CHECKS` off the run** — expected 25 (13 today, +1 for the
   unconditional parse row, +11 self-checks), but the contract is "ratcheted to the MEASURED
   green value, with no slack", so `<measured>` is what this plan writes everywhere else.
2. **Run every mutation against a copy, never the tracked file**
   (`hr-never-git-stash-in-worktrees`): `cp "$FILE" "$TMPDIR/mut.sh" && sed -i … && bash
   "$TMPDIR/mut.sh"`. The gate `cd`s to the repo root and uses repo-relative `SUITES`, so a
   copy in `$TMPDIR` runs correctly. This makes the matrix scriptable, reproducible in the PR
   body, and impossible to leave applied.
3. `bash scripts/guard-vacuity-floor.test.sh` green.

## Guard Contract

### Guard 1 — the parse is colour-blind

**Property.** Every counter bun's summary block prints for a test outcome — `pass`, `fail`,
`skip`, `todo`, `expect() calls` — is read regardless of the escape sequences the runner
interleaved. The `N error` counter bun prints on a module-load crash is explicitly out of
scope; the existing `bun test exited N` row fails that run.

**Assembly.** `parse_bun_summary` is the sole **producer** of counter values: it emits them on
stdout and one `read` binds them, so no counter can enter the gate by another path. The claim
is about that shape — one producer, one binder — not about today's five members; a sixth must
be added inside the function *and* to its output line or it reaches no consumer. The file has
no `source`, no `eval` and no other writeback.

**Mutation matrix.** Every row is run against a copy in `$TMPDIR`, never the tracked file.

| # | mutation (applied to a copy) | must go RED |
|---|---|---|
| M1 | make `strip_ansi` a `cat` | S2a, S2b, S3 RED; **S1 and S4 GREEN** — the GREEN half proves the RED came from colour, not a broken harness |
| M2 | revert **one** counter (e.g. `n_skip`) to a pre-fix read, leaving the other four fixed | S1 RED. The *second member after a compliant first*: a check stopping at `pass` cannot see it |
| M3 | re-anchor `n_expect`'s second stage to `^[0-9]+` | S1 and S2a RED — the false-RED trap is caught at author time, not in CI |
| M4 | narrow the strip's parameter class back to `[0-9;?]` | S3 RED (colon-SGR, DECSC and charset escapes survive) |
| M5 | drop the `n_expect` first-stage anchor | S4 RED (the decoy's `999` is read as the summary) |
| M6 | move `strip_ansi` inside the per-counter loop (read the input five times) | S1, S2a, S2b, S3 RED on every field but the first — the F3 trap |
| M7 *(own dispatch)* | delete the `--- 0. Parser self-test ---` block | `[FATAL] anti-vacuity floor: only <n> check(s) dispatched, floor is <measured>`, exit 1 |
| M13 *(own dispatch, cross-file)* | insert a blank line between `MIN_CHECKS=<n>` and its `if` | `bash scripts/guard-vacuity-floor.test.sh` reddens **naming this file** — its `build_mutant` can no longer bind the threshold, the suite reclassifies NO_FIRE, and that guard's zero-slack ARM 1 fails. This is the only proof AC18 is load-bearing rather than incidental |

**Harness rows.**

| # | edit to the SUITE | expected |
|---|---|---|
| H1 | change S2a's expected tuple to the broken output (`- - - - -`) | S2a **RED against the fixed code** — proves the expectation is load-bearing, not fitted to whatever the code emits |
| H2 | stub `assert_parse`'s comparator to always call `pass` | **N2 RED** — the instrument self-test is what makes a stubbed comparator observable; conservation alone cannot see it, since a stub still records one verdict per counted check |
| H3 *(must-PASS, non-canonical)* | S1's `122 3 1 2 514` is not the all-green canonical shape, and S2b's is an all-skip shape; both must PASS unchanged | GREEN |

### Guard 2 — an unmeasured count is not a zero

**Property.** No arm reports a passing verdict about a counter that was not read.

**Assembly.** `summary_measured` is the sole decision site; all three reporting arms and both
SUT floors sit inside its `if`. Structurally, an unread counter is literally `-` — the
defaults that used to manufacture a zero are deleted. **Superseded 2026-09-08 (review):** the
sentence continued "so a future arm added outside the branch cannot read a plausible number",
which is FALSE and was measured so — at `[[ "$v" -gt 0 \]\]` both `""` and `-` return false and
both print `[ok]`, so a misplaced arm is fail-open under either vocabulary. The sentinel buys
protection against a re-added `${x:=0}` default (M11), not against an out-of-branch arm. Arm-level behaviour is exercised by running mutated
**copies** end to end (M8, M10, M14), not by an injection seam.

**Mutation matrix.** Every row is run against a copy in `$TMPDIR`, never the tracked file.

| # | mutation (applied to a copy) | must go RED |
|---|---|---|
| M8 | make `summary_measured` ignore `fail` — the exact #7466 fail-open in the predicate | V2 RED. End to end on a copy with M1 also applied, the run prints `[ok] bun's summary reports no failing tests` — the regression reproduced |
| M9 | drop `pass` from the predicate, leaving `fail` (*second member after a compliant first*) | **V3 RED**, V1 and V2 GREEN — the asymmetry names which member was dropped. (V1 is `- -`, so it stays false under either single-member edit and cannot distinguish them; V3 is the sole detector for `pass`) |
| M10 | delete the `-`→0 normalisation | N1 RED, and **AC18 RED** — the run's stderr carries `arithmetic syntax error`. Without both, this mutation is invisible: the arm prints `[ok]` and the SUT floor silently stops firing (F4) |
| M11 | restore any one `: "${n_*:=0}"` default ahead of the measured branch | AC17 RED — the measured line under a strip-less copy reads `fail=0` instead of `fail=-` |
| M12 *(own dispatch)* | delete the four predicate self-checks | `MIN_CHECKS` FATAL, exit 1 |
| M14 | delete a SUT floor's own `if ! [[ … =~ ^[0-9]+$ ]]` arm, leaving only the `-lt` comparison | On a copy with M1 applied under `FORCE_COLOR=1`, the run must **still exit 1**. Today's upstream-guard-only design would score this GREEN: `[[ "-" -lt 131 ]]` errors, returns false, and control falls through to `pass "test count …"` — a green verdict on an unmeasured count, i.e. D2 re-introduced by the fix (F4) |

**Harness rows.**

| # | edit to the SUITE | expected |
|---|---|---|
| H4 | change V4's expectation from true to false | RED against the fixed code |
| H5 *(must-PASS, non-canonical)* | V4 (true) is not the canonical false and must PASS | GREEN — proves the predicate is not stuck returning one answer |

## Observability

```yaml
liveness_signal:
  what: the gate's terminal line, "=== N passed, 0 failed (N checks) ===", exit 0
  cadence: every CI run of the `scripts` shard, plus every direct developer invocation
  alert_target: the CI job `test-scripts` (a red gate fails the shard)
  configured_in: scripts/test-all.sh (SUITE_GLOBS entry 'plugins/soleur/test/*.test.sh')
error_reporting:
  destination: stdout/stderr of the shard, surfaced by the failing CI job; no Sentry — this
    is an operator-side CLI guard, observability layer 7 (self-hosted plugin CLI)
  fail_loud: true — every floor reports printf >&2 + exit 1 directly, never through the
    verdict helpers it polices (ADR-193 Decision #1)
failure_modes:
  - mode: bun's summary format changes so pass or fail stops parsing
    detection: summary_measured false -> all three arms FAIL and the unmeasured FATAL fires
    alert_route: red `scripts` shard. This, not the fixtures, is what notices real format
      drift — the fixtures only police the strip
  - mode: the ANSI strip regresses (an edit, a sed lacking the extension, a narrowed class)
    detection: self-checks S2a/S2b/S3 RED before the live run executes
    alert_route: red `scripts` shard; the fixture comment names sed portability first
  - mode: the '-' normalisation is removed, silently disabling an arm and a SUT floor
    detection: check N1 (integers at the point of comparison) plus AC18 (stderr must be empty)
    alert_route: red `scripts` shard
  - mode: the gate goes silent (checks deleted, verdict helpers neutered, comparator stubbed)
    detection: the MIN_CHECKS floor, the accounting-conservation check, and N2's instrument
      self-test — three distinct sentinels for three distinct faults
    alert_route: red `scripts` shard; also scripts/guard-vacuity-floor.test.sh, which derives
      its population and would name this file. NOTE: that guard's floor_lines_of matches only
      -lt/-le/-ge threshold shapes, so it does NOT cover the new boolean unmeasured FATAL
logs:
  where: stdout of the shard; the bun log is retained at $LOG whenever KEEP_LOG is set
  retention: CI job retention; local logs live in $TMPDIR until the EXIT trap removes them
discoverability_test:
  command: bash plugins/soleur/test/preflight-check10-suite-integrity.test.sh
  expected_output: ", 0 failed ("
```

`expected_output` is `, 0 failed (` rather than the bare `0 failed`, which is a substring of
`10 failed`. **No substring can do this job alone, and this block should not pretend otherwise.**
Measured over both failure shapes: a run whose failures are recorded VERDICTS prints a non-zero
count, so `, 0 failed (` rejects it but `[ok] assertion count` still matches (the run reaches the
end); a run with zero recorded failures that dies on a SUT floor prints
`=== 28 passed, 0 failed (28 checks) ===` and exits 1, which `, 0 failed (` matches and
`[ok] assertion count` rejects (the floor FATALs first). The two candidates are complementary and
each is blind where the other sees. **`$DT_RC == 0` is the authority**; the substring is a
secondary sanity check, and the tighter of the two on the common shape is kept. It carries no
count, so it survives the `MIN_CHECKS` ratchet — a
hardcoded count would be stale the next time a check is added, and the run is the authority
for the number. Check 10 is path-gated and **skips this diff** (measured), so this block is
documentation rather than an executed probe here.

## Acceptance Criteria

### Pre-merge (PR)

Every `grep -c` criterion is written as `[[ "$(grep -c … <file>)" -eq N ]]`: a zero-match
`grep -c` prints `0` and **exits 1**, so a bare "returns 0" aborts a checklist under `set -e`.

1. `env -u FORCE_COLOR -u CLICOLOR_FORCE bash <file>` exits 0 and prints
   `=== N passed, 0 failed (N checks) ===` where `N` equals the `MIN_CHECKS` value read from
   the file itself. (Scrubbing the variable is required: the plan's own Problem section says
   agent harnesses export it, and an inherited `FORCE_COLOR` would collapse AC1 into AC2.)
2. `FORCE_COLOR=1 bash <file>` exits 0 and prints the **same** line. This is the criterion the
   issue turns on, and it fails against today's code.
3. The measured lines from AC1 and AC2 are **byte-identical**, and both report `pass` ≥
   `MIN_TESTS` and `expect` ≥ `MIN_ASSERTIONS` with those literals read from the file's own
   floor bindings — not copied from this plan.
4. The AC2 run's log actually contained colour: `grep -qa "$(printf '\033')" "$LOG"`. Without
   this, AC2 goes green having tested nothing if a future bun stops honouring `FORCE_COLOR`.
5. `MIN_CHECKS` equals the value the green run prints, with no slack — read off the run.
6. **M1:** with `strip_ansi` reduced to `cat` on a copy, the gate goes RED naming S2a/S2b/S3,
   and S1 and S4 still pass. Both halves recorded in the PR body.
7. **M8:** with `summary_measured` ignoring `fail`, V2 goes RED.
8. **M9:** with `pass` dropped from the predicate, V3 goes RED while V1 and V2 stay GREEN.
9. **M10:** with the normalisation deleted, N1 goes RED and stderr carries
   `arithmetic syntax error`.
10. **M6:** with the strip moved inside the per-counter loop, S1/S2a/S2b/S3 go RED.
11. **M7/M12:** with either self-test block deleted, the run prints
    `[FATAL] anti-vacuity floor: only <n> check(s) dispatched` and exits 1.
12. **H2:** with `assert_parse`'s comparator stubbed to always pass, N2 goes RED.
13. Two assertions on the producer, not one: `[[ "$(grep -c 'n_pass=\|n_fail=\|n_skip=\|n_todo=\|n_expect=' <file>)" -eq 0 ]]`
    (the counters are never assigned by name outside the binder — the function's internals are
    named `plain`/`one`/`v`) **and**
    `[[ "$(grep -c '^[[:space:]]*read -r n_pass n_fail n_skip n_todo n_expect <<<' <file>)" -eq 1 ]]`
    (the one binder exists). The first alone is satisfied by deleting the parse entirely.
14. All five defaults are gone:
    `[[ "$(grep -cE ':[[:space:]]+"\$\{n_(pass|fail|skip|todo|expect):=' <file>)" -eq 0 ]]`.
15. The GNU-only escape is not **used**, anchored on the use rather than the token — the
    design comment legitimately contains the string `\x1b` while explaining why it is banned,
    so a bare `grep -c x1b` would redden correct code:
    `[[ "$(grep -cE 'sed[^|]*\\x1b' <file>)" -eq 0 ]]`.
16. The green run's **stderr is empty**: `bash <file> 2>err >/dev/null; [[ ! -s err ]]`. A `-`
    reaching any arithmetic comparison is otherwise invisible to AC1, which reads only the
    terminal line and the exit code.
17. With M1 applied to a copy, `FORCE_COLOR=1 bash "$TMPDIR/mut.sh"` prints the measured line
    as `pass=- fail=- …`, prints a FATAL whose text contains `unmeasured`, prints **no**
    `[ok] test count` or `[ok] assertion count` row, and exits 1. This is the criterion that
    pins D-3's guard; without it the guard is unpinned and its absence is green.
18. `bash scripts/guard-vacuity-floor.test.sh` exits 0, **and** `MIN_CHECKS=<n>` sits on the
    line immediately preceding `if [[ "$cases" -lt "$MIN_CHECKS" ]]` with no blank line or
    comment between them:
    `[[ "$(grep -n -A1 '^MIN_CHECKS=' <file> | sed -n '2p' | grep -c 'if \[\[ "\$cases" -lt')" -eq 1 ]]`.
    That guard's `build_mutant` binds a threshold only by contiguous backward widening; break
    the adjacency and this suite reclassifies NO_FIRE, tripping its zero-slack ARM 1.
19. **M13:** with a blank line inserted between `MIN_CHECKS=` and its `if`,
    `bash scripts/guard-vacuity-floor.test.sh` reddens and names this file.
20. **M14:** with a SUT floor's `if ! [[ … =~ ^[0-9]+$ ]]` arm deleted on a copy carrying M1,
    `FORCE_COLOR=1 bash "$TMPDIR/mut.sh"` still exits 1.
21. The two suites this change can affect are green when run **directly**: `<file>` and
    `scripts/guard-vacuity-floor.test.sh`. A whole-shard `bash scripts/test-all.sh scripts` is
    deliberately **not** an acceptance criterion — measured, the runner *refuses* to start
    while a sibling worktree holds a full-gate run (`ERROR: refusing a full-gate run — 1
    sibling full-gate run(s) already in flight`), so its result is a property of the machine
    rather than of the diff (`cq-ac-must-not-depend-on-concurrent-sessions`). Both ACs run
    with the file's own `TMPDIR="${TMPDIR:-/var/tmp}"` default in force, and a `mktemp`
    failure caused by tmpfs pressure is re-run once before being recorded. The full battery
    belongs to the ship-phase checkpoint.
22. `python3 scripts/lint-trap-tempfile-ownership.py <file>` reports no finding — the design
    allocates no new tempfile, so this holds by construction.
23. The comment above the parse row no longer claims the block has no `else`.
24. The PR body carries `Closes #7466`, the Phase 1b RED/GREEN table, and the observed verdict
    of every mutation row.

## Test Scenarios

Each is `mutation -> guard reddens`, not `command -> terminal output`.

1. Green tree, colour scrubbed → 0 failures, exit 0, empty stderr.
2. Green tree, `FORCE_COLOR=1` → byte-identical measured line. (RED before the fix.)
3. Clean summary with no `skip`/`todo`/`expect` lines → all three normalise to `0`; no
   arithmetic error; the arm's `[ok]` is earned.
4. **All-skip run** (`0 pass / 2 skip / 0 fail`, no `expect` line) → the summary is
   **measured**, the skip/todo arm reports `2 skipped … coverage silently removed`, and the
   `MIN_TESTS` floor fires. This is the case the gate exists to catch, and the case an
   `expect`-inclusive predicate would have misdiagnosed as an unparseable summary.
5. Unparseable summary → all three arms FAIL with an *unmeasured* message; the SUT-floor FATAL
   says unmeasured rather than "only 0 test(s) passed".
6. Decoy log → all five fields `-`, not 999.
7. Real failures → the failure-count arm FAILs with the count.
8. Module-load crash (`0 pass / 1 fail / 1 error`) → `bun test exited N` FAILs; the `N error`
   counter is documented as out of scope rather than silently ignored.
9. M1–M12 and H1–H5, each run against a copy and recorded with its observed verdict.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| **`NO_COLOR=1 bun test …`** as an extra hardening | *Contested.* The CTO consult recommended it for input determinism. **Position: do not add it.** The gate should read what the runner actually emits; normalising at the source removes the only end-to-end exercise of the strip in the environments where the bug bites, leaving it fixture-only — and "no coverage of the coloured shape anywhere" is what let this defect survive |
| A parser assigning five caller globals, with a comment banning the pipe form | Silent, mimics the bug being fixed, and — because self-checks run first — lets a stale fixture tuple be reported as a real measurement |
| A three-token verdict enum | Cut: two of three consumers collapse two tokens, and the enum created its own fall-through fail-open needing an exhaustive `case`, a `*) fail` default, a mutation row and a grep-shaped AC to police |
| Including `expect` in the measured predicate | **Rejected on measurement (F1):** it would report the all-skip run as an unparseable summary and suppress the one diagnosis this gate exists to print |
| A `CHECK10_LOG_OVERRIDE` seam for arm-level tests | Rejected: it would let any environment feed this gate a synthetic green summary and skip bun entirely — a bypass shipped into the gate whose thesis is that a suite asserting nothing is indistinguishable from one that passed. Mutated copies give the same coverage with no bypass |
| A committed colour fixture file | Literal ESC bytes in a tracked file are fragile to editors and filters |
| Bounding the parse to the region after bun's trailing `bun test v…` banner | Would close the decoy class rather than narrowing it, but makes the gate depend on a banner bun could stop printing — and that failure mode is a hard RED on a healthy tree. **Scoped out and documented in the comment**, so the next reader does not believe the anchor closed the class |
| Giving the self-checks their own counter and floor | DHH's suggestion, declined: `MIN_CHECKS` is an exact no-slack floor, so deleting any SUT check still drops the total below it. A second counter adds machinery without adding discrimination |
| Changing the terminal line to print `MIN_CHECKS` | Declined: nothing greps this file's output today and this plan keeps it that way. AC1 reads the floor from the file instead |

## Domain Review

**Domains relevant:** Engineering.

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Endorsed extracting the predicate — not for the revert-reddening argument but
because it has three consumers that drift independently when inlined, which *is* the measured
defect. Confirmed `n_expect` anchoring and fail-closing the skip/todo arm as **in-scope
completion of the same defect**, not creep, while naming `--reporter=junit`, the SUT floors
and the manifest block as out of scope. Contributed the `n_expect` stage-two `^[0-9]+`
false-RED trap and the GNU-only `\x1b`, both reproduced and folded into D-1/D-2. Concluded
**no ADR warranted**: a defect fix inside one gate file, no new service, boundary or data
model.

### Product/UX Gate

Not applicable. The mechanical UI-surface scan over `## Files to Edit` / `## Files to Create`
matches no UI path, and the semantic sweep finds no user-facing surface.

### Plan Review (5-agent panel)

**Decision:** reviewed. All five agents returned — DHH, code-simplicity, Kieran,
spec-flow-analyzer and architecture-strategist. Every applied finding was re-verified by
execution rather than accepted on assertion.

**Three of this plan's own claims were measurably FALSE and are corrected above** — each was
an assertion of a *negative* ("the only…", "zero besides…", "no learning covers…"), the shape
this repo's own Sharp Edges warn is a universal negative over a set nobody enumerated:

- "the only ANSI-strip filter in the repo" — there are **five** code sites, four of them
  carrying the same GNU-only defect in `apps/web-platform/infra/`. The grep behind the claim
  was shell-mangled and returned one hit.
- "zero other parsers besides this file" — `plugins/soleur/test/git-fixture-env.mutation.sh`
  carries the same two-stage parse and D3 verbatim.
- "no learning covers ANSI escape sequences in shell parsing" — **three** do, and all three
  prescribe the exact form F5 measured wrong.

**Applied — blocking, in order of severity:**

- **F1** (spec-flow): `expect() calls` is absent when zero, so an `expect`-inclusive predicate
  misdiagnoses the all-skip run — the flagship case. Predicate narrowed to `pass`/`fail`.
- **F4** (Kieran): the `-` sentinel is fail-**open** at a numeric comparison where the empty
  string was fail-**closed**, and it does not crash. D-4 plus checks N1 and AC16/AC18.
- **F3** (Kieran and spec-flow independently): a process substitution is a pipe, so the
  obvious per-counter strip returns `122 - - - -` for every fixture. Read-once pinned, M6
  added.
- **F5** (Kieran): the naive CSI class leaves colon-SGR, DECSC and charset escapes standing,
  each a hard RED on a healthy tree under the new arms. ECMA-48 ranges with `LC_ALL=C` and a
  `|` delimiter, verified against a no-over-strip control; M4 added.
- **F2** (spec-flow): colour placement is value-dependent, so one coloured fixture cannot
  represent bun. Split into S2a/S2b, both transcribed from `cat -v`.
- Phase 1's RED was `command not found` for every check. Phase 1a scaffold added, plus a
  `declare -F` symbol guard, and the honest RED/GREEN table published.
- Mutation expectations for the single-member predicate edits were inverted; V3 added as the
  sole detector for a dropped `pass`.
- **The corpus guard's classification of this file hangs on a textual adjacency**
  (architecture): `MIN_CHECKS=` must stay on the line immediately above its `if`, or
  `build_mutant` cannot bind the threshold and the suite reclassifies NO_FIRE, tripping a
  zero-slack arm in a different file. Pinned by AC18 and mutation M13.
- **Upstream-only guarding of the SUT floors was insufficient** (architecture): with the
  predicate in an enclosing branch rather than at the comparison, deleting the guard scores
  GREEN. Floors now carry their own `if ! [[ … =~ ^[0-9]+$ ]]` arm; M14 proves it.

**Applied — mechanical:** cut the three-token enum and the equivalence check; reversed the
earlier cut of a named `strip_ansi` once F5 grew it to three lines; rewrote AC9/AC10/AC11/AC12
(all four were green-compatible-with-false or guaranteed-false — AC12's bare `grep -c x1b`
reddened on correct code because the design comment names the token it bans); added
`env -u FORCE_COLOR` to AC1 and a colour-presence assertion to AC2; made every `grep -c`
criterion exit-safe; replaced hardcoded counts with values read from the file; added the
mutated-copy harness so no mutation can be left applied; scheduled the rewrite of the
now-false comment above the parse row.

**Declined, with reasoning recorded:** the `CHECK10_LOG_OVERRIDE` seam (ships a bypass into a
gate); a separate counter and floor for the self-checks; printing `MIN_CHECKS` in the terminal
line. See Alternatives.

**Tension acknowledged:** DHH argued the whole change should be roughly fifteen lines and
four checks. It has instead grown to eleven self-checks — but every addition after that review
was forced by a *measured* failure mode (F1–F5), not by design preference, and three of them
(F1, F3, F4) are cases where the earlier, smaller design was actively wrong. The proportionate
answer to "the defect is four regexes" is that four of the five facts the fix depends on were
invisible until someone executed them.

## Gates Not Triggered

- **2.7 GDPR** — no regulated-data surface; none of triggers (a)–(d) fire.
- **2.8 IaC** — no server, service, secret, vendor, DNS record or persistent process.
- **2.10 ADR/C4** — explicit skip clause: a bug fix on an existing surface. No ownership or
  tenancy move, no new substrate, no trust-boundary change, no divergence from a read ADR
  (ADR-129 honoured by allocating nothing; ADR-193's shape followed and this file's membership
  in `guard-vacuity-floor.test.sh` preserved).
- **2.11 Encryption Posture** — no persistent store, no new cross-component connection.
- **2.9.1 Soak enrolment** — no time-gated close criterion.
- **1.8 Skill-description budget** — no `SKILL.md` `description:` edited.
- **1.4 Network-outage checklist** — no trigger keyword, no SSH-dependent provisioner.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| An escape shape the strip misses becomes a hard RED on a healthy tree under the new arms | ECMA-48 ranges cover the four shapes measured in F5; S3 pins them; M4 proves S3 reddens when the class narrows. OSC and stale-text-before-`\e[1G` are documented as out of scope rather than claimed |
| A `-` reaching an arithmetic comparison silently disables an arm **and** a floor (F4) | D-4 normalises inside the measured branch; N1 asserts integers at the comparison; AC16 asserts empty stderr; M10 proves both reflect it |
| The fixture path and the live path disagree because of F3 | Read-once pinned in D-2 with the measurement beside it; M6 reddens the multi-read shape |
| A pinned bun that stops printing `0 fail` on a clean run would make the predicate a hard RED | Phase 0 step 3 is a precondition gate on the pinned version |
| Fixtures encode belief rather than bun's output | S2a/S2b are transcribed from `cat -v` captures with the version recorded beside them; and real format drift is caught by the **live** run going unmeasured, not by fixtures |
| The new unmeasured FATAL is not covered by the corpus vacuity guard | Recorded explicitly in Observability and Research Insights rather than assumed; the boolean shape is outside `floor_lines_of`'s `-lt`/`-le`/`-ge` matcher |
| A mutation is left applied to the tracked file | Every mutation runs against a copy in `$TMPDIR` (Phase 3 step 2) |
| `MIN_CHECKS` copied from this plan rather than measured | AC5 requires it read off the green run; the accounting-conservation check catches a miscount in both directions |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails
  `deepen-plan` Phase 4.6.
- **A process substitution is a pipe.** `f <(printf …)` can be read **once**. A function that
  re-reads `"$1"` per field returns the first field and empty for the rest — and against a
  real file path the same function works, so the fixture path and the live path disagree in a
  way that looks like the bug being fixed.
- **A non-numeric sentinel in `[[ … -lt … ]]` does not crash; it returns false.** It prints
  one stderr line and turns a floor into a no-op. An empty string, by contrast, evaluates as
  0 and *fires* the floor — so introducing a sentinel flips the polarity of every unguarded
  comparison from fail-closed to fail-open.
- **A runner omits a counter that is zero.** Before putting a counter in a "did we measure
  this?" predicate, check whether the producer prints it unconditionally — bun prints `pass`
  and `fail` always, and `skip`/`todo`/`expect() calls` only when non-zero.
- **Colour placement is value-dependent.** Bun colours <code> N pass</code> only when N > 0; <code> 0 pass</code>
  puts the space first. One coloured fixture cannot represent a runner's output — transcribe
  from `cat -v`, do not narrate.
- **A function that assigns into the caller's scope cannot be reached through a pipe.**
  Measured: `printf … | f` loses every assignment. Do not "simplify" an echoing parser back
  into an assigning one.
- **Anchoring a two-stage grep breaks the second stage.** Adding `^[[:space:]]*` to stage one
  makes it emit leading whitespace, so a stage-two `^[0-9]+` never matches.
- **`\x1b` in `sed` is a GNU extension**, and an SGR-only class misses colon-separated SGR,
  DECSC and charset designations. Use ECMA-48 ranges under `LC_ALL=C`, and a `|` delimiter —
  an escaped `/` inside a bracket expression was measured turning the class into `0x20-0x5C`.
- **A grep that bans a token cannot be a bare-token grep** when the file legitimately explains
  why the token is banned. Anchor on the use (`sed[^|]*\\x1b`), per
  `cq-assert-anchor-not-bare-token`.
- **`grep -c` prints `0` and exits 1** on no match, so "returns 0" aborts a checklist under
  `set -e`. Write `[[ "$(grep -c …)" -eq 0 ]]`.
- **Anchoring narrows the decoy class; it does not close it.** <code>  514 expect() calls</code> in
  mid-log still parses.
- **`cases` must never be incremented inside a terminal verdict helper** (ADR-193 Decision #2,
  ARM 10d). Inside an `assert_*` wrapper that *calls* `pass`/`fail` is the sanctioned shape —
  verified by running that classifier, not by reading its comment.
- **`scripts/test-all.sh` refuses to run while a sibling worktree holds a full-gate run**, so
  any AC phrased as "the full gate is green" is flippable by an unrelated session.
- **The issue body's numbers are stale.** It cites 122 pass / 514 expect and two suites; the
  branch carries three suites at 132 / 539.
- **`scripts/lint-guard-contract.py` counts mutation rows only inside the span following a
  literal `**Mutation matrix**` field.** A guard entry whose rows sit in a bare table under
  the Assembly paragraph scores **0 rows** and fails — and the failure message says "matrix
  has 0 row(s)" while the rows are plainly on screen. Encountered while editing this plan:
  a rewrite dropped the label and turned two valid matrices into a hard fail. Keep the label.
- **Three of this plan's own claims were false universal negatives** ("the only…", "zero
  besides…", "no learning covers…"), each from a grep that returned one hit or none. Before
  writing a negative about a *set*, run the grep in a form you have verified is not
  shell-mangled, and prefer counting to asserting absence.
