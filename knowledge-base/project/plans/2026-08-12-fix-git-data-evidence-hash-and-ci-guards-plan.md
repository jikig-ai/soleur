---
title: "fix: the rung-2 evidence hash aborts on a correct tree, the rehearsal misattributes a starved fixture, and the closure guard dies before it can reopen"
type: fix
date: 2026-08-12
slug: fix-git-data-evidence-hash-and-ci-guards
branch: feat-one-shot-7485-7501-7506-git-data-ci-guards
lane: cross-domain
issue: 7485
closes: [7485, 7501, 7506]
priority: p2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: three guards that report something other than what they measure

## Overview

Three defects, one pass. Each is a guard whose verdict is decoupled from the property it names:
a hash derivation that aborts on a correct tree, a rehearsal that blames the emitter for a
container that never started, and a closure guard that dies before the reopen that is its only
purpose.

The shape is the same in all three — **a signal exists and is being read, but it is not a
measurement of the stated property** — and it decides each fix. It also disciplines this plan:
a five-agent panel found that the first draft's own #7485 fix *reintroduced the class* one
contributor over, and that its #7506 test pinned the wrong shell. Both are corrected below,
with measurements.

No `spec.md` exists for this branch, so `lane:` defaulted to `cross-domain` (TR2 fail-closed).

## Problem Statement

### #7485 — the evidence hash aborts on an unmodified tree, and its only green is the fail-open

Measured on pristine `origin/main` (07cf8ebcb), sourcing the lib and calling with real paths:

```
git_data_rung2_user_data_sha256: ABORT — …/modules/git-data-userdata/main.tf contains 9
file(${path.module}/…) reference(s) but only 11 resolved into the hash input set.   rc=1
```

Four contributors feed the input set: the cloud-init template, the module's `main.tf`, **every
sibling `.tf` in the module directory**, and every payload the module references via the
`file()` family. Measured live: 9 payloads, 2 siblings, so `#_inputs` = 13. The check computes
`_n_resolved` as `#_inputs - 2`, discounting the template and `main.tf` but never the siblings,
giving 11 against 9 references.

**The floor is loose, not merely stale.** `#_inputs -lt 11` with two siblings means `4 + N < 11`,
so it fires only when `N < 7` — the shipped floor tolerates losing two of the nine payloads.

**And the shipped function's only passing configuration is the narrowed one.** Measured across
three module shapes:

| Module directory | Shipped `rc` |
|---|---|
| 2 siblings (as shipped) | **1** — the reported abort |
| 1 sibling unreadable | **1** |
| both siblings absent | **0**, hash `3a1d7198…` |

The accept region *is* the input set with the siblings missing. That is a stronger argument for
the fix than the issue makes, and it belongs in the PR body.

**Why the suite did not catch it.** The gate suite passes **58/58** — and 58/58 with the fix
applied (measured both directions). Its fixture builder writes only `main.tf` and has no path by
which a sibling can appear. The fixture shares the function's assumption, so it cannot falsify
it (`2026-08-11-my-fixture-shared-the-bug-so-the-test-could-not-see-it.md`).

**The same class, live, in the test file the plan edits.** `_r2_hash()` is a parallel
reimplementation of the input set whose comment claims it "*shares its extraction rule so the two
cannot drift*" — and it has already drifted twice: no sibling glob, and a bare `file\(` regex
where the lib matches the whole `file(base64|sha256|sha512|md5)?` family. Its output `R2_SHA`
feeds 20 sites. Repairing it is measured hash-neutral (see §Proposed Solution).

**Blast radius.** Fail-closed, so no wrong hash renders. But the derivation has two callers, not
one: the capture script, and `git_data_rung2_rehearsal_gate()` — **the birth interlock itself**.
And the live first interlock now reports **RELEASED** (measured: #6982 landed, the emitter is
wired), so the rung-2 hash is the interlock that would gate a birth, and it cannot run.

The capture script routes the abort into a branch labelled `TRANSIENT:` and exits 2. The
rehearsal workflow consumes 2 as "retry": a bounded poll of 20 attempts × 30 s. Since the
derivation runs *after* `boot_complete` is already observed, a correct rung-2 boot is currently
un-capturable — it re-runs an identical deterministic failure ~20 times, burns ~10 minutes of a
paid cpx22, and then reports TRANSIENT "do not simply re-dispatch". That poll is a real
money-burner and is **out of scope** (§Non-Goals) because changing a paid-host dispatch's retry
semantics deserves its own review; it is recorded here with its measurement.

### #7501 — a starved fixture is attributed to the emitter

One `docker run` produces three capture files. Three arms read them through `grep -c … || true`
over files the container may never have created, so **missing**, **empty** and **genuine
no-match** collapse into `0`.

**The defect is misattribution, not vacuity.** Two arms are positive assertions (`-ge 1`), so an
empty capture makes them *fail*; the R4 MUTATION arm already computes a liveness marker to stop
an empty capture passing for the wrong reason. Nothing reports a false green. What is reported
is a false *cause*: R3(3a) says "the emitter no longer leaks a literal path" and tells the reader
to go re-derive a guard's rationale — in response to a container that never started. This is
ADR-177's concern (a confident conclusion the evidence does not support), and the PR body must
say so rather than overclaim vacuity.

**A marker already exists; what is missing is a reader.** The driver already emits
`FIXTURE: capture server never bound :8099` and exits 2. The host side then does
`docker run … >"$TMP/r4out/stdout" 2>&1 || true`, discarding both the rc and any reason to open
the file — which is referenced only inside failure-message details. The EXIT trap removes the
tree unconditionally, so reproducing the incident required patching the trap.

Upstream of that, `apt-get update` / `install curl python3` carry no rc check under a driver that
runs `set -uo pipefail` with no `-e`, so a failed apt continues to start a capture server with no
`python3`. Measured: apt in `ubuntu:24.04` = **107.99 s** wall vs a **0.70 s** bare spin, and the
image ships neither `python3` nor `curl`.

**Correcting the first draft: apt already gates the merge today.** A dead container yields 0 for
all three arms → three `fail`s → the suite exits 1. The `|| true` swallows the *rc*, not the
*consequence*. This change does not add Ubuntu's mirrors to the merge gate; it relabels a
dependency already there, and the retries strictly reduce redness.

### #7506 — the closure guard dies before it can reopen, on every reopen

Two `printf` calls in the reopen-body group pass a format beginning with `-` without the `--`
guard, while four neighbours in the same group are guarded. The two are the `if` and `else` arms
of one conditional, so exactly one executes on every pass — **the guard is dead, not degraded.**

**Corrected shell premise.** The first draft pinned `bash --noprofile --norc -eo pipefail`. The
repo's own record contradicts that and is right: `scripts/lint-workflow-errexit-capture.py`
states a `run:` block declaring no `shell:` key is invoked as `/usr/bin/bash -e {0}`, and that
`shell: bash` is what maps to `--noprofile --norc -eo pipefail`. The step declares no `shell:`
key (verified), so the faithful harness is **`bash -e`**. Measured:

| Invocation | rc | reopen calls |
|---|---|---|
| `bash -e` (what Actions runs), current file | **2** | **0** |
| `bash --noprofile --norc -eo pipefail`, current file | 2 | 0 |
| `bash -e`, with `--` added | 0 | 1 |
| plain `bash` (no `-e`), current file | 0 | 1 |

The last row is why the test must carry `-e`: without it the defect is invisible and the test
pins nothing. Rows 1 and 2 agree today, so the first draft's error produced no false green — but
it inverted a mutation row, and it would supply a `pipefail` production does not have.
`scripts/marketplace-drift-check.test.sh` carries a comment asserting the wrong side of this;
it is corrected here, since it is what misled this plan.

**A latent defect this fix would activate — and its shape is not the obvious one.** The guard
selects `.[-1].body`, the *newest* comment rather than the closing one, and its own reopen body
prints each missing URL verbatim. The natural reading is "field 1 self-satisfies and the guard
goes quiet". Measured, it is worse. The reopen body renders fields 2 and 3 as the literal
templates `` `…/actions/runs/<id>` `` and `` `bytes: <N>` `` — no digits — so they fail
`actions/runs/[0-9]+` and `bytes:[[:space:]]*[0-9]+`:

| Newest comment | field 1 | field 2 | field 3 | reopens |
|---|---|---|---|---|
| human junk | miss | miss | miss | 1 |
| the guard's own reopen body | **match** | miss | miss | **1** |

So the guard reopens *again*, and every close re-triggers it: **an unbounded reopen-and-comment
loop on the issue**, not a silent pass. This has never been reachable because no reopen has ever
completed — the fix makes it live, which is why closing it is in scope rather than a follow-up.

Two more selector defects sit in the same three lines. The fetch is **unpaginated**, so on an
issue with more than 30 comments `.[-1]` is comment #30, not the newest — the guard validates an
unrelated historical comment. And when no comment qualifies, the step falls back to the **issue
body**, which is authored by whoever opened the issue; excluding bot comments *widens* that path,
and a callback-URL follow-through issue's body legitimately contains the three URLs (verified on
#1784). The fix must therefore be an identity filter plus a reopen-on-no-qualifying-comment, not
merely a filter.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality on 07cf8ebcb | Plan response |
|---|---|---|
| `_n_resolved`, the glob, the floor at 352 / 302 / 333 | Confirmed | Cite by content anchor (`cq-cite-content-anchor-not-line-number`) |
| Module ships three `.tf` → glob contributes 2 | Confirmed | Fix removes the need to count siblings |
| 9 payload references | Confirmed | Floor becomes a payload floor of 9 |
| The `-lt 11` floor is a second stale literal | True **and understated** — it tolerates losing 2 of 9 | Recorded as a tightening |
| "33/33 green" | Suite is **58/58**; 33 is the capture-script suite's floor | Floor bump 58 → 68 |
| **Only production caller is the capture script** | **False** — `git_data_rung2_rehearsal_gate()` is a second caller, and it is the birth interlock | Both callers swept |
| The suite never touches the live file | **False** — it already reads it as a non-asserting NOTE | That precedent justifies A1 |
| Header's countdown-timer premise (#6982 pending) | **#6982 is CLOSED and the live gate now reports RELEASED** | Header amended; A1's stakes raised |
| "an empty capture reads as a substantive finding" | Confirmed as **misattribution**, not vacuity | Framing corrected throughout |
| Rehearsal floor 44, one real top-level EXIT trap | Confirmed (4 more `trap … EXIT` lines are heredoc/table text) | AC anchor must be heredoc-aware |
| Lines 130/135 unguarded | Confirmed; they are the two arms of one conditional | — |
| Sweep finds only those two | Confirmed with `[[:space:]]` (not `\s`, a GNU ERE extension) | Bounds documented |
| Actions runs `run:` as `--noprofile --norc -eo pipefail` | **False for a step with no `shell:` key** — it is `bash -e {0}` | Harness pinned to `bash -e`; a repo comment corrected |
| #7485: "the discount and the glob were written in different changes" | **False** — `git log -S` puts both in the same commit, `be7b5a5ee` (#7066, 2026-07-30) | The arithmetic was wrong on arrival, not drifted. The same PR wrote the blind fixture, which is why nothing caught it |
| #7506: the oracle is a self-satisfying green | **False** — measured, the guard reopens *again*; the defect is an unbounded reopen loop | Hazard restated; C-arms redesigned around reopen **count** and **content** |
| The comment fetch selects the closing comment | **False** — `gh api` is unpaginated (30/page), so `.[-1]` is comment #30 on a long thread | `--paginate --slurp` is part of the fix |
| A new `scripts/*.test.sh` is auto-discovered | It is not; the glob covers `scripts/lib/*.test.sh` | Explicit registration is a deliverable |
| Commit ordering makes the revert clean | **False** — 200/200 recent `main` commits have one parent; a merged PR is one commit | Claim withdrawn; DC-1 restated honestly |
| #6977 context only, OPEN | Confirmed | Not targeted |

## Proposed Solution

### #7485 — abort where the drop happens, on both loops

The counting check existed to *detect, by counting*, a drop happening one loop earlier: a payload
is appended only if readable and discarded silently otherwise. Abort inside that loop and the
counting has nothing left to detect.

The first draft stopped there — and a measured review found that **it left the identical silent
drop on the sibling glob while deleting the only arithmetic that responded to sibling
composition.** Measured against the first draft's shape:

| Case | Draft-1 fix | Corrected fix |
|---|---|---|
| baseline | rc=0 `bd87e1d3…` | rc=0 `bd87e1d3…` |
| one sibling unreadable | **rc=0 `43b6a7f7…`** (fail-open) | **rc=1**, naming the file |
| sibling renamed `variables.tf.json` (valid Terraform) | **rc=0 `cb33868e…`** (fail-open) | rc=0, and it is **hashed** |
| a payload unreadable | rc=1, naming it | rc=1, naming it |
| module shrunk to 4 payloads | rc=1, floor | rc=1, floor |

So the fix is:

- **payload loop** — abort on the first reference that does not resolve, naming it (the current
  message cannot); increment `_n_payloads` for each that does. Retain the `-n "$_f"` guard: written
  as a bare `-r` test, an empty `_f` yields `-r "${module_dir}/"`, which is *true* for a directory.
- **sibling glob** — abort on a `.tf` that is present but unreadable, and extend the glob to
  `*.tf.json`, which Terraform loads and the current glob misses. This is a completeness fix, not
  a literal.

  **The absent-vs-unreadable discrimination is load-bearing and must be written explicitly.** The
  lib sets no `nullglob`, so a pattern that matches nothing yields the literal string. The live
  module has no `.tf.json` at all, so adding that pattern means the real tree iterates once on an
  unexpanded literal — and a naive `[[ -r "$_f" ]] || abort` would then **abort on `main`**, which
  is the very defect being fixed, reintroduced at the new contributor. The correct guard tests
  whether the glob matched a real directory entry before testing readability:

  | Candidate | `-e` | `-L` | Verdict |
  |---|---|---|---|
  | unexpanded literal (`*.tf.json`, no matches) | false | false | **skip** |
  | present, readable | true | — | hash it |
  | present, unreadable | true | — | **abort** |
  | dangling symlink | false | **true** | **abort** |

  So: `[[ -e "$_f" || -L "$_f" ]] || continue`, then `[[ -r "$_f" ]] || abort`. Testing only `-e`
  would silently skip a dangling symlink — a file Terraform would fail on but the hash would
  quietly exclude.
- **no sibling floor.** A deleted sibling is a real directory change the hash correctly reflects,
  and a floor would be exactly the literal this fix removes — it would break the first time
  `variables.tf` is legitimately folded into `main.tf`.
- **payload floor** on `_n_payloads` (`-lt 9`), and the referenced-vs-resolved block, `_n_resolved`
  and both literals deleted.

The floor and the per-reference abort are orthogonal and both stay: deleting five bindings leaves
every remaining reference resolving while the hash binds fewer files than ship.

**The floor literal is honestly a literal.** The first draft claimed "no arithmetic that can go
stale"; that is one literal instead of two, not immunity. When a tenth payload lands the floor
goes *loose* by one — it does not abort. There is no automatic trigger. The plan's answer is to
say so: the abort message names the floor's provenance, a code comment states where the literal
must move when the payload set grows, and §Non-Goals records the looseness as accepted.

**Repair the mirror, and then stop it being a mirror.** `_r2_hash()` gains the sibling glob and
the `file()` family regex, making its comment true. Measured: `R2_SHA` is byte-identical before
and after and the suite stays 58/58, because no current fixture has a sibling or a `filebase64`
binding — so the repair is hash-neutral and breaks nothing.

A one-time byte-identity measurement is not a guard, though, and leaving a hand-maintained
reimplementation with nothing preventing a third drift would repeat the class this plan exists to
close. Both hashers emit the same `<digest>  <basename>` line shape over the same fixture, so an
**equivalence arm** is available today: `_r2_hash "$R2"` must equal
`git_data_rung2_user_data_sha256 "$R2/ci.yml"`. That makes drift unshippable rather than merely
measured, and it is the arm that replaces the byte-identity check. The new sibling arms are
nevertheless built on a **separate copied tree**, calling the function directly rather than
through `r2check`/`R2_SHA`, so they stay independent of the mirror.

**Fixture unreadability must not be `chmod 000`.** Root bypasses DAC read checks, so `[[ -r ]]`
is *true* for a mode-000 file under uid 0 — in any root container the arms that catch the
draft-1 fail-open would silently go green against the unfixed code. A **dangling symlink** is
unreadable for every uid (measured: `-r` false, `-L` true), so it is the environment-independent
mechanism for both the payload and the sibling arms.

**Message-only correction to the capture script's `TRANSIENT:` arm**, with `exit 2` unchanged
(the 0/1/2 verdict contract is consumed by the rehearsal workflow, and no consumer greps the
literal). Note honestly: that text reaches the step *log* and the capture-log artifact, **not**
`$GITHUB_STEP_SUMMARY`, whose rc=2 branch is hardcoded by the workflow. The Observability block
says so rather than claiming a surface the change does not reach.

### #7501 — make starvation nameable; keep it a failure

Five changes. The first draft's sixth — a third `inconclusive` counter — is **cut**: with the
verdict exiting non-zero either way, its mechanical delta against `fail()` is zero (same total,
same floor, same exit status, and no consumer parses the summary line), and it dragged an ADR
amendment, a decision challenge, an AC and two mutation rows behind it. The file already has the
idiom — explicit `fail` calls purely for cardinality parity. What #7501 actually asks for is that
the message stop accusing the emitter; that is a string and a precondition.

1. **Fail loudly inside the container.** rc-check `apt-get update` and `install`, plus
   `command -v python3` / `command -v curl`, each emitting a distinct `FIXTURE-FAIL: <cause>`
   before a non-zero exit. Five causes are new; the sixth is the existing bind marker, **renamed**
   from `FIXTURE:` so it matches the nested runner's failure-marker regex.
2. **Bound apt.** `-o Acquire::Retries=3` on update plus a bounded backoff around install, scoped
   to the R4 driver. The first draft's retrying image pre-pull is **cut**: R4's `docker run` is the
   sixth `ubuntu:24.04` invocation in the file, so the image is already local, and a pre-pull would
   introduce a new all-suite dependency at a site the plan scopes out.
3. **Stop discarding the container's verdict.** Capture the `docker run` rc, and emit a tail of the
   container stdout **on its own lines at column 0**, anchored on the `FIXTURE-FAIL:` line — not
   interpolated into a detail string, where the leading-whitespace anchor fails and the cause is
   lost in exactly the blind tail this design exists to avoid.
4. **One run-level liveness gate, not three per-arm preconditions.** There is one container and one
   capture path, so "the fixture was starved" is a run-level fact. After the bind poll the driver
   self-POSTs a sentinel and polls until it observes it in the capture log; the host then checks
   `docker rc == 0 && sentinel observed` **once**, and on failure all three arms report the fixture
   cause and make no emitter claim. The first draft's per-arm non-emptiness conjunct is **dropped**:
   it contradicted the plan's own semantics, since an empty capture *after* a proven round trip is
   precisely the emitter finding the arm exists to make.

   **The sentinel must land in a durable artifact, not in `capture.log`.** The driver truncates
   `/out/capture.log` three times — once before each of the A/B/C orderings — so a sentinel written
   there is wiped long before the host reads anything. The driver observes the round trip in
   `capture.log` (which is fine; that happens first) and then `touch /out/sentinel.ok`; the host
   checks for that file. Written the other way, the gate reddens every healthy run.

   **The gate must emit an explicit `pass` on the healthy path, and the floor moves 44 → 45.** A
   gate contributing zero assertions when it succeeds is one a future inversion-to-always-pass
   leaves undetectable — the floor of 44 would still be met. Counting it is the whole point of the
   instrument.

   **And the gate must be structural, not grep-verified.** An assembly grep counts call sites, so
   an arm routed *around* the gate leaves the count unchanged and the check green — cardinality
   standing in for discrimination, the exact anti-pattern this plan cites elsewhere. On failure the
   gate reports all three arms and skips past them, so bypassing it is a deletion the count does
   see.
5. **Preserve forensics.** Modify the existing EXIT trap in place — never add a second, since bash
   keeps only the last handler — to retain the tree and print its path **whenever the suite exits
   non-zero**, not keyed on counters: the suite has hard `exit 1` setup paths with `fails == 0`,
   and those are where forensics matter most. Retention is also reachable via a named opt-in
   variable, `GIT_DATA_REHEARSAL_KEEP_TMP`. Add an age-reaper mirroring the sibling runner's, which
   records the measured cost of omitting one (414 dirs / 23 MB).

**Honest scope statement.** Five other apt-bearing container sites keep unchecked apt and `|| true`,
so under a single apt outage the suite will carry two verdict regimes: R4 naming the fixture while
T5/S1/R1 still report emitter-shaped findings. That is a real limit on how much a starved run
improves, and the PR body must say so rather than imply the class is closed.

### #7506 — two characters, a faithful harness, and three selector defects

Add `--` to the two calls. Then repair the closing-comment selector, which carries three defects
that the `printf` fix would activate together:

- **Paginate.** `gh api … --paginate --slurp --jq '[.[][]] | …'`. A bare `--paginate --jq` emits
  one document per page and would return the last comment *of every page* — a different wrong
  answer, so the flag combination is part of the prescription.
- **Filter on identity, never on content.** `select(.user.login != "github-actions[bot]")`. A
  login is not registrable by a human (GitHub logins are alphanumeric-plus-hyphen, so `[bot]`
  cannot be spelled), whereas a body-content predicate such as "skip comments containing
  `## Closure gate`" is a one-line bypass for anyone who can comment.
- **No qualifying comment must reopen, not fall back to the issue body.** That body is authored by
  whoever opened the issue, and a callback-URL follow-through body legitimately contains all three
  URLs (verified on #1784) — so the fallback lets an issue satisfy its own gate, and excluding bot
  comments makes that path *more* reachable rather than less.

Then a regression suite that executes the shipped step body **as a child process** under `bash -e`
with a `gh` stub recording argv. Child, not sourced: the body registers its own `trap … EXIT`
(which would clobber the suite's) and `exit 0`s on the complete-fixture path (which would end the
suite early with rc=0 — a vacuous PASS the floor cannot catch, because the floor line never runs).
The stub must evaluate the body's own `--jq` expression through real `jq` rather than returning
canned JSON, or `comment_body` becomes a serialized array, every `grep -Fq` matches, and the
selector under test is never exercised. Keep a standing class sweep, trimmed.

## Implementation Phases

Commits are grouped by issue for readability. **No revert claim is attached**: `main` is
squash-merged (200/200 recent commits have a single parent), so a merged PR is one commit and
in-branch ordering does not survive. The revert story is a genuine cost of the single-PR shape and
is recorded in DC-1 for the operator, not argued away.

### Phase 0 — Preconditions (no product edits)

- Re-run the #7485 reproduction on a fresh `origin/main` extract; confirm rc=1 and the 9-vs-11 text.
- Confirm `python3 -c 'import yaml'`; the new suite hard-exits 2 without it.
- Confirm the closure-guard step still declares **no** `shell:` key. If one has appeared, the
  faithful invocation becomes `bash --noprofile --norc -eo pipefail` and the harness must change
  with it — the premise is directional, and the first draft got the direction wrong.
- Re-run the assembly grep over the rehearsal file. It returns **four** call sites, not three: the
  fourth is the R4 MUTATION arm's own liveness marker, which must be **excluded**, not folded in.
- Read `scripts/lint-shell-capture-exit.baseline.txt`: it carries 7 grandfathered findings for the
  rehearsal file and the gate blocks new occurrences. This change adds `x=$(…)` captures; plan for
  the baseline to stay unchanged or shrink, never grow.
- Record floors: gate suite 58, rehearsal 44, capture-script suite 33.

### Phase 1 — RED (tests first, `cq-write-failing-tests-before`)

- Gate suite: arms A1–A11 on a **separate copied tree**, plus the `_r2_hash` repair. A1, A2 and
  the sibling-unreadable arm must be RED first.
- Capture-script suite: one executing arm for the derivation-fault path (rc=2 and the corrected
  text), replacing the first draft's grep. Bump its floor 33 → 34.
- New closure-guard suite C1–C10.
- Rehearsal: the run-level gate, container markers, apt retries, rc capture and forensics. RED
  evidence is **fault injection**, never a natural flake (`cq-ac-must-not-depend-on-concurrent-sessions`).

### Phase 2 — GREEN

- `git-data-birth-readiness-gate.sh`: both loops abort; `*.tf.json` in the glob; payload floor;
  delete the counting block and both literals; re-word both abort messages; update the extraction
  comment that justifies the family regex by reference to the now-deleted check.
- `git-data-rung2-evidence-capture.sh`: the `TRANSIENT:` label; `exit 2` unchanged.
- `follow-through-closure-guard.yml`: `--` on the two calls; bot-authored comments excluded from
  the selector.
- `marketplace-drift-check.test.sh`: correct the default-shell comment.
- `test-all.sh`: `run_suite` for the new suite in `want_scripts`.
- Floors: gate 58 → 68, capture-script 33 → 34, rehearsal 44 → 45, new closure-guard suite
  exactly 15 (C1–C15). (This line carried the pre-deepen figures — 63, and "rehearsal unchanged" — until
  #7485's implementation reconciled it against §Test Scenarios, which is authoritative.)

### Phase 3 — Mutation verification and record

Execute every row of **all four** guard matrices and record the observed colour in the PR body,
with Guard 3's last three rows labelled as controls so a green battery is not misread as mutations
caught. A row that does not redden is a defect in the test, not a note. Then `bash scripts/test-all.sh`, plus the rehearsal
suite on a machine with docker.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| #7485: fix the discount to `- 4`, re-derive the floor to 13 | Reproduces the class — two literals from one assumption. |
| #7485: derive the sibling count and subtract it | Prototyped and measured green, but preserves the coupling to `_inputs` composition that broke. |
| #7485: abort on the payload loop only (first draft) | **Measured fail-open**: a sibling made unreadable or renamed `.tf.json` returns rc=0 over a narrower set. Corrected. |
| #7485: add a sibling floor | Another literal, and it breaks the first time a sibling is legitimately folded into `main.tf`. Abort-on-unreadable plus `.tf.json` coverage is the principled form. |
| #7485: drop the sibling glob | Load-bearing: `variables.tf` carries render-var defaults that decide what boots. |
| #7485: a committed payload manifest | A second place to update on every payload add, for a naming benefit the per-reference abort already gives. |
| #7501: a third `inconclusive` counter | Mechanical delta against `fail()` is zero once it exits non-zero; it dragged an ADR amendment, a DC, an AC and two mutation rows. **Cut** — flagged independently by both simplification reviewers. |
| #7501: treat an empty capture as a pass or skip | Laundered to `PASS` by the nested runner, which dumps diagnostics only on RED. See DC-2. |
| #7501: per-arm liveness preconditions | Three copies of one run-level fact, and the non-emptiness conjunct suppressed the very emitter finding the arms exist to make. |
| #7501: retrying image pre-pull | The image is already local by R4; the helper's only invocation site is in scoped-out code. Cut by all three reviewers who examined it. |
| #7501: raise the bind-poll budget | apt is unbounded and runs before the poll; apt *failure* starves the container and only an rc check sees it. |
| #7501: pre-bake the image | Scoped out with a measurement — §Non-Goals. |
| #7506: pin `--noprofile --norc -eo pipefail` (first draft) | Wrong for a step with no `shell:` key; supplies a `pipefail` production lacks. Corrected to `bash -e`. |
| #7506: grep the workflow source instead of executing it | A grep pins spelling, not behaviour, and the tell is answerable: the line could sit in an unreached branch. |
| #7506: leave the `.[-1]` selector alone | Ships a guard that half-disarms itself on first use — the fix is what makes the oracle live. |
| An ADR amendment for the verdict taxonomy | Dissolves with the counter; and its substantive point already exists verbatim in ADR-177. |
| Split into three PRs | Recommended by the consult and by review. The operator's stated deliverable is one PR; recorded as DC-1 **without** the revert-cleanliness argument, which does not survive squash-merge. |

## User-Brand Impact

- **If this lands broken, the user experiences:** a git-data host that boots unverified payloads.
  The evidence hash makes the rung-2 boot evidence attest *the template being dispatched*; a fix
  that narrowed the input set would produce a well-formed hash over fewer files than ship, so a
  birth would release on evidence that does not describe what boots. That host is the shared store
  for every connected user's source code. **The first draft of this fix had exactly that defect,
  measured** — which is why the sibling arms and Guard 1 rows 2 and 7 exist.
- **If this leaks, the user's source code is exposed via:** no new vector — no credential,
  endpoint, permission or egress is added. The indirect vector is the one above.
- **If the #7506 arm lands broken, the user experiences:** nothing directly; that guard reopens an
  internal follow-through issue. Included at this threshold because it shares the PR.
- **Brand-survival threshold:** `single-user incident`

The host is unprovisioned and no evidence file exists, so realised blast radius today is zero
users. The threshold reflects the guard's purpose — and the first interlock now reports RELEASED,
so this is the interlock that would gate the birth #6977 tracks.

## Observability

```yaml
liveness_signal:
  what: "each suite's verdict line and anti-vacuity floor — the gate suite's `=== N passed, M failed ===` (floor 69), the capture-script suite (floor 34), the rehearsal's `N passed, M failed (T assertions)` (floor 45), and the new closure-guard suite's count line (exactly 15)"
  cadence: "per-run: ci.yml `test-scripts` on every push; infra-validation.yml on every infra-touching diff"
  alert_target: "the workflow run log of the failing job; on push to main, infra-validation.yml's notify-main-failure"
  configured_in: "scripts/test-all.sh (run_suite registrations), .github/workflows/ci.yml (test-scripts job), .github/workflows/infra-validation.yml (the rehearsal step)"

error_reporting:
  destination: "GitHub Actions workflow run log (layer 6, `::error::` / step failure); the closure guard also emits `::warning::` on the reopen path"
  fail_loud: true

failure_modes:
  - mode: "the evidence-hash derivation aborts again, or binds a narrowed set (a module change re-breaks resolution, a sibling becomes unreadable, or the payload set shrinks)"
    detection: "the gate suite's live-tree and sibling arms redden in the ci.yml test-scripts workflow run log, and the abort names the specific unresolved payload, the unreadable .tf, or the payload count"
    alert_route: "workflow run log — the required `test` check blocks merge"
  - mode: "a rung-2 capture hits the derivation fault in production"
    detection: "the capture script's corrected derivation-fault text in the rung-2 rehearsal workflow's STEP LOG and its `git-data-rung2-capture-log` artifact. Explicitly NOT the step summary: that workflow hardcodes its own rc=2 summary text, which this change does not edit"
    alert_route: "workflow run log + the capture-log artifact"
  - mode: "the rehearsal container starves (apt update or install fails, python3 or curl absent, never binds, never round-trips)"
    detection: "an in-surface `FIXTURE-FAIL: <cause>` marker emitted from inside the container, surfaced on its own column-0 lines in the suite's stderr. Six causes discriminate every competing starvation hypothesis in one line. On the CI path the suite is a DIRECT step in infra-validation.yml, so the whole step log is visible; the column-0 marker shape matters on the LOCAL nested-runner path, where selection is marker-anchored and capped"
    alert_route: "workflow run log — the suite exits non-zero, the infra job reddens, and on a push to main notify-main-failure fires (on a pull_request the signal is the red check, not the notification)"
  - mode: "an arm reports about the emitter when the fixture was starved"
    detection: "structurally prevented by a single run-level gate evaluated before any emitter claim; a regression shows as emitter-worded text alongside a fixture-cause line in the same run log"
    alert_route: "workflow run log; Guard 2's rows are the standing proof"
  - mode: "the closure guard dies before reopening, or reopens when it should not"
    detection: "the new suite executes the shipped step body under `bash -e` and asserts rc=0 with exactly one recorded `gh issue reopen` on the incomplete fixture, zero on the complete one, and zero when the newest comment is the guard's own reopen body. In production the same failure is a red step in that workflow's run log"
    alert_route: "workflow run log — required `test` check pre-merge; `::error::` on the live workflow post-merge"
  - mode: "an unguarded `printf '-…'` returns anywhere in the repo"
    detection: "the standing sweep arm greps the call form `^[[:space:]]*printf[[:space:]]+'-` across .github/, scripts/, plugins/, tests/ and apps/, asserts a non-zero scanned-file count, and is proven fireable against a planted violation"
    alert_route: "workflow run log — required `test` check"

logs:
  where: "GitHub Actions run logs for ci.yml and infra-validation.yml. On a LOCAL run only, the retained forensics directory whose path the rehearsal prints on any non-zero exit — infra-validation.yml has no upload-artifact step, so the tree does not survive CI and must not be relied on there"
  retention: "Actions default log retention; the local forensics tree is age-reaped after 12 hours by the same mechanism the sibling runner uses"

discoverability_test:
  command: "bash tests/scripts/test-git-data-birth-readiness-gate.sh && bash scripts/follow-through-closure-guard.test.sh"
  expected_output: "the gate suite prints `=== 69 passed, 0 failed ===`; the closure-guard suite exits 0 reporting exactly 15 assertions"
```

Both commands are local, credential-free, contact no network, and start with an allowlisted probe
verb. The rehearsal suite is excluded: it needs a docker daemon and minutes of wall-clock.

## Architecture Decision (ADR/C4)

**No ADR.** The first draft proposed amending ADR-177 for the arm-level verdict class; that class
is cut, and the amendment's one substantive point — that a nested runner must not adopt a distinct
exit code — **already exists verbatim** in ADR-177 under "`3` is a TOP-LEVEL contract only". An
amendment restating an ADR is a no-op. The constraint is cited where it is used, in DC-2.

**No C4 impact.** All three model files were read in full and enumerated on four axes.
**(i) External human actors** — three exist; none gains or loses a capability, and no trigger or
permission is added. **(ii) External systems** — 20 checked; only `github` is implicated, described
as "Source control, CI/CD, issue tracking, and releases", and restoring a reopen it already
describes adds no capability. **(iii) Containers / data stores** — `gitDataStore` is the only
element referencing this artifact; its assertions (host unprovisioned, evidence file absent,
hash-of-hashes self-invalidating on any edit) all remain true, and this change creates no evidence
file. **(iv) Actor ↔ surface access** — all edges of the four actors checked; no new access path,
credential or dispatch route. Recorded so it is not mistaken for an omission: the model has no
element for an individual CI workflow or the test-side bash tree, and `spec.c4` offers no element
kind at that altitude.

## Guard Contract

### Guard 1 — the rung-2 user_data hash input set

**Property.** The hash covers exactly the cloud-init template, every Terraform file in the render
module directory (`*.tf` and `*.tf.json`), and every payload the module references through a
**single-line literal** `file*("${path.module}/…")` form — and the function refuses, rather than
returning a hash, whenever any of those is present-but-unresolvable or the module binds fewer
payloads than ship.

The "single-line literal" bound is deliberate and is the honest limit of the extraction: a
multi-line `file(\n "…"\n)`, an indirected `file(local.p)`, and a *second* `templatefile()` are
all invisible to the regex, and each would render into `user_data` while the nine literal payloads
still resolve and the floor still passes. Deleting the counting check does not cause this — that
check called the same extractor on both sides and was already blind to it — but the Property must
not claim completeness the mechanism cannot deliver. Recorded in §Non-Goals.

**Assembly.** `git-data-birth-readiness-gate.sh` › `git_data_rung2_user_data_sha256()`. Four
contributors feed `_inputs`, and **two of them are loops that append conditionally** — the sibling
glob and the payload-reference loop. Both are chokepoints and both must abort rather than drop;
the first draft fixed one and left the other, which is the defect this matrix exists to catch. The
only derived quantity is `_n_payloads`, read by one check. Downstream, the basename-uniqueness
check is the sole detector of a module referencing one of its own siblings and must survive the
deletion. Two callers, not one: the capture script and `git_data_rung2_rehearsal_gate()`.

**Mutation matrix:**

Unreadability is injected with a **dangling symlink**, never `chmod 000` — root bypasses the mode
check and would silently disarm rows 1, 2 and 9.

| # | Mutation | Expected |
|---|---|---|
| 1 | Make one referenced payload unreadable (dangling symlink) | RED — abort names that payload |
| 2 | Make one sibling `.tf` unreadable (dangling symlink) | RED — abort names that file. *(Measured RED on the corrected shape, rc=0 on the first draft.)* |
| 3 | Delete a referenced payload outright, so the reference resolves to nothing | RED — the deleted counting check was the only detector of "references a payload not on disk"; the abort must inherit that job |
| 4 | Write the sibling guard as a bare `[[ -r ]] || abort`, dropping the matched-entry test (the guard's own dispatch) | RED — the live tree aborts on the unexpanded `*.tf.json` literal, which A1 must catch |
| 5 | Write the sibling guard as `[[ -e ]] || continue`, dropping the `-L` arm | RED — a dangling-symlink sibling is silently skipped instead of aborting |
| 6 | Shrink a fixture module to bind 2 payloads with siblings present | RED — floor fires, message names the payload count |
| 7 | Remove the floor, then delete five payload bindings | RED — proving the floor is load-bearing beside the per-reference abort |
| 8 | Rename a sibling to `variables.tf.json` | GREEN **and the file is in the hash** — the digest must differ from the digest with that file absent |
| 9 | Make a `.tf.json` sibling unreadable | RED — the abort must attach to **both** glob patterns, not just the first |
| 10 | Replace `_n_payloads` with a fixed literal (the guard's own dispatch) | RED — the shrunken-module arm stops reddening |
| 11 | Drift `_r2_hash()` away from the lib (drop its sibling glob again) | RED — the equivalence arm fires; this is what stops a third drift |

Two rows were **cut** from the first draft as carrying no information: "add a second sibling to a
fixture that already has one" (pre-fix, *one* sibling already reddens, so the second changes
nothing) and "restore the counting check" (it makes the function strictly more refusing, so it
violates no stated property — it is a regression shape already covered by the sibling arms).

### Guard 2 — the rehearsal's run-level fixture-liveness gate

**Property.** No arm of the rehearsal suite makes a claim about the emitter unless the capture path
was proven live end-to-end for that container run.

**Assembly.** `git-data-runcmd-rehearsal.test.sh`. One host-side chokepoint — the single `docker run`
producing the capture directory — and one run-level gate below it (`docker rc == 0` and sentinel
observed) through which all three emitter-claiming arms must pass. The assembly is enumerated by the
call form `grep -c … "$TMP/r4out/capture-*.log"`, which returns **four** sites; the fourth is the R4
MUTATION arm's own liveness marker and is **excluded by name**, because it is not an emitter claim.
Container-side, every step that can leave the capture path dead must emit a distinct `FIXTURE-FAIL:`
marker and exit non-zero. Explicitly **not** in this assembly: the five other container sites, whose
arms keep their current behaviour (§Non-Goals).

**Mutation matrix:**

Rows 3–6 require driving the suite from **outside itself** with faults injected. That outer
harness is a deliverable, not an assumption: a small `--inject <cause>` env hook the suite honours,
so a mutation row costs one container run rather than a hand edit. Name it in Phase 1 or the rows
are unexecutable.

| # | Mutation | Expected |
|---|---|---|
| 1 | Force the container's `apt-get install` to fail past its retries | RED naming `FIXTURE-FAIL: apt-get install`, with no emitter-worded text in any of the three arms |
| 2 | Point the capture server at a port nothing binds, so the sentinel never round-trips | RED naming the round trip; all three arms fixture-attributed |
| 3 | Write the sentinel into `capture.log` instead of a durable artifact (the draft-1 shape) | RED on a **healthy** run — the driver truncates `capture.log` three times, so the host can never observe it |
| 4 | Invert the run-level gate to always-pass | RED — the gate's own `pass` disappears and the total drops below the floor of 45 |
| 5 | Emit the container stdout tail interpolated into a detail string instead of on its own column-0 lines (the guard's own dispatch) | RED — the marker-shape assertion runs against the suite's **rendered output**, not the marker literal |
| 6 | Make the suite exit 0 with a fixture-attributed failure | RED — a fixture failure must not be laundered to `PASS` by the nested runner |
| 7 | Delete the sentinel check while leaving the rc check | RED — an rc-zero container with a dead capture path must still be caught |

The first draft's "route one arm around the gate → the assembly grep reports it" row is **cut**:
routing around the gate leaves the call-site count unchanged, so the grep cannot see it. Row 4
replaces it by making the gate structural — its own `pass` is the thing that goes missing.

### Guard 3 — the closure guard reaches its reopen, and only when it should

**Property.** When the closing comment is missing any required field, the step body runs to
completion under the shell Actions actually uses and invokes `gh issue reopen` exactly once; when
all fields are present, or when the only newer comment is the guard's own reopen body, it exits 0
and invokes it zero times.

**Assembly.** `follow-through-closure-guard.yml` › the "Check closing comment for required fields"
step's `run:` body, extracted by name and executed. The property quantifies over the **whole body**:
any shell abort above the reopen has the same effect, which is why the test executes rather than
greps. Two premises are asserted, not assumed — that the step declares no `shell:` key (which is
what makes `bash -e` faithful) and that the body carries no `${{ }}` interpolation. Step-name match
is asserted to select exactly one step. The comment **selector** is part of the assembly: the guard
must not read its own output.

**Mutation matrix:**

Rows 5–7 are **controls**, not mutations — labelled so a green battery is not misread as seven
mutations caught.

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert `--` on the first `printf` (the missing-URLs arm) | RED — rc=2, zero reopens |
| 2 | Revert `--` on the second `printf` (the URLs-present arm) | RED — both arms need their own fixture; one fixture exercises only one |
| 3 | Run the extracted body under plain `bash` (no `-e`) | RED — the guard's own dispatch; the mutation that would make every other arm vacuous |
| 4 | `source` the body instead of running it as a child | RED — its `exit 0` on the complete fixture ends the suite early with rc=0, and the floor line never runs to catch it |
| 5 | Revert the selector to `.[-1]` with no identity filter | RED — with a bot body newest and a **complete human comment beneath it**, the reopen count goes 0 → 1 |
| 6 | Replace the identity filter with a body-content predicate | RED — a human comment carrying the guard's own heading must NOT be excluded |
| 7 | Drop `--paginate --slurp` | RED — a 31-comment fixture selects comment #30 instead of the newest |
| 8 | Restore the issue-body fallback when no comment qualifies | RED — an issue whose body carries the three URLs must not satisfy its own gate |
| 9 | Return canned JSON from the `gh` stub instead of evaluating `--jq` (the harness's own dispatch) | RED — `comment_body` becomes a serialized array, every `grep -Fq` matches, and rows 5–8 all go vacuously green |
| C1 | Add `shell: bash` to the step | RED — the premise arm fires; the faithful invocation becomes `--noprofile --norc -eo pipefail` and the harness's `bash -e` is now stale |
| C2 | Feed a complete closing comment | GREEN, zero reopens — without this control an unconditionally-reopening mutant passes |
| C3 | Rename the step so the extractor matches zero steps | RED — cardinality fires rather than silently testing an empty body |

The first draft's row 6 ("newest comment is the guard's own reopen body → zero reopens") was
**wrong** and is replaced by row 5. Measured: against the *unfixed* selector that fixture reopens
**once**, because the bot body satisfies field 1 but not fields 2 or 3 — so "zero reopens" is not
the pre-fix behaviour and the row could never have reddened. The discriminating fixture puts a
**complete human comment beneath** the bot comment, where the reopen count genuinely moves.

### Guard 4 — the standing `printf '-` sweep

**Property.** No shell call site in the repository invokes `printf` with a single-quoted format
beginning with `-` and no `--` guard.

**Assembly.** `^[[:space:]]*printf[[:space:]]+'-` (POSIX classes, not `\s`, which is a GNU ERE
extension) over `.github/`, `scripts/`, `plugins/`, `tests/` and `apps/`, excluding
`knowledge-base/project/{plans,specs}/**` and `**/archive/**`. Anchored on the call form so prose
describing the hazard neither satisfies nor trips it. **Three bounds are documented in the suite**
rather than left for a reader to find: single-quote-only (which correctly excludes awk program text,
where `printf "- …"` parses no options), no mid-line `&& printf '-`, and no double-quoted shell
form — so this is a floor on the class, not a proof of absence. Recorded alongside: the repo's bar
for minting a `scripts/lint-*` gate was six occurrences across six files; this class has two in one
file, so it stays an assertion rather than a lint.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Plant a `printf '- x\n'` line in a synthesized fixture tree | RED — the sweep must be shown to fire before its zero over the real repo is evidence |
| 2 | Point the sweep at a directory that does not exist (its own dispatch) | RED — the non-zero scanned-file assertion fires |
| 3 | Write the hazard in prose inside a comment | GREEN — the call-form anchor must not trip on documentation |

## Acceptance Criteria

### #7485

- [ ] **AC1** — On a clean extract of the merge commit, `git_data_rung2_user_data_sha256` against
      the live cloud-init returns 0 and prints a 64-hex digest. Behaviour when the live file is
      absent is defined and does not silently drop the arm below the floor.
- [ ] **AC2** — Each of these aborts naming the offending file: an unresolvable payload reference, a
      **deleted** payload reference, an unreadable `.tf` sibling, and an unreadable `.tf.json`
      sibling. A readable `.tf.json` sibling is hashed rather than skipped (digest differs from the
      digest with that file absent). Unreadability is injected with a dangling symlink, never
      `chmod 000` — root bypasses the mode check and would disarm these arms silently.
- [ ] **AC3** — The floor applies to the payload count, its message names that count and where the
      literal must move when the payload set grows; removing the floor while deleting five bindings
      is shown to go undetected without it.
- [ ] **AC4** — Sibling-count independence: fixtures with zero, two and three siblings all return 0;
      and the live tree (which has no `.tf.json` at all) returns 0 rather than aborting on the
      unexpanded glob literal.
- [ ] **AC5** — `_r2_hash()` carries the sibling glob and the `file()` family regex, `R2_SHA` is
      byte-identical to its pre-change value, and an **equivalence arm** asserts
      `_r2_hash "$R2"` == `git_data_rung2_user_data_sha256 "$R2/ci.yml"` — so its comment's
      non-drift claim is enforced rather than merely measured once.
- [ ] **AC6** — The counting check is gone: no `_n_resolved`, no `${#_inputs[@]} - 2`, no `-lt 11`;
      and the extraction comment that justified the family regex by reference to that check is
      updated rather than left describing a check that no longer exists.
- [ ] **AC7** — `bash tests/scripts/test-git-data-birth-readiness-gate.sh` prints
      `=== 69 passed, 0 failed ===`, and the existing arms pinning the `ABORT`/`drifted` needles
      still pass. **AMENDED at implementation (DC-3):** this AC originally required the suite's
      internal anti-vacuity check to become an exact equality "matching the suite's existing
      form". That justification is false — the existing form is a **floor** (`-lt 58`), carrying
      an explicit in-file rationale against equality, and both sibling suites use a floor too.
      The floor is raised 58 → 69 and left a floor; the `69 passed, 0 failed` line above is
      asserted directly and is unaffected. See DC-3.
- [ ] **AC8** — The capture script's derivation-fault arm no longer reads as transient and still
      exits 2 — asserted by an **executing arm** in the capture-script suite (floor 33 → 34), not a
      grep, since a grep is satisfied whether or not the branch is reachable.

### #7501

- [ ] **AC9** — The R4 `docker run` no longer ends in `|| true`; its rc feeds the run-level gate.
- [ ] **AC10** — A single run-level gate (`docker rc == 0` and a **durable** `sentinel.ok` artifact,
      not a `capture.log` line the driver later truncates) precedes all three
      emitter-claiming arms. Verified by the assembly grep, whose fourth call site — the R4 MUTATION
      liveness marker — is excluded by name.
- [ ] **AC11** — Six container-side causes each emit a distinct `FIXTURE-FAIL:` marker and exit
      non-zero, including the existing bind marker renamed from `FIXTURE:`.
- [ ] **AC12** — The container stdout tail is emitted on its own column-0 lines anchored on the
      `FIXTURE-FAIL:` line. Asserted against the suite's **rendered output** matching the nested
      runner's failure-marker regex — not against the marker literal.
- [ ] **AC13** — With apt forced to fail past its retries, all three arms attribute the fixture, no
      arm renders emitter-worded text, and the suite exits non-zero. With a healthy container the
      three arms produce their normal verdicts, the gate emits its own `pass`, and the total is 45.
      A named fault-injection hook drives these without hand edits.
- [ ] **AC14** — The forensics tree is retained and its path printed on **any** non-zero exit,
      including the hard `exit 1` setup paths where `fails == 0`; retention is also reachable via
      `GIT_DATA_REHEARSAL_KEEP_TMP`; and an age-reaper — exercised with a `touch -d` back-dated
      fixture, never by waiting, and glob-bounded so it cannot reap a concurrent run — removes old
      trees while retaining a fresh one.
- [ ] **AC15** — Exactly one *executable* top-level `trap … EXIT` remains, asserted with a
      heredoc-aware anchor (a naive `^trap .* EXIT` count returns 4 on this file).
- [ ] **AC16** — `scripts/lint-shell-capture-exit` passes with its baseline unchanged or smaller.

### #7506

- [ ] **AC17** — Both `printf` calls carry `--`, and the repo-wide sweep returns zero.
- [ ] **AC18** — The suite extracts the step body (via `yaml.safe_load`) by name with a one-step
      cardinality check and executes it **as a child process** under **`bash -e`** — never sourced,
      since the body carries its own `trap … EXIT` and an `exit 0` that would end the suite with a
      vacuous rc=0 the floor cannot catch. It asserts the step declares no `shell:` key, that every
      `$VAR` the body reads is declared in its `env:`, and that the body carries no `${{ }}`; it
      hard-exits 2 without PyYAML and registers an EXIT trap for its `mktemp` allocations.
- [ ] **AC19** — An incomplete closing comment yields rc=0 and exactly one `gh issue reopen`, and
      the rendered body contains the checklist line the defect prevented. **Both** conditional arms
      are exercised by fixtures whose URLs are derived from the workflow's own `required_urls`
      array, so a URL drift cannot silently collapse both fixtures onto one arm.
- [ ] **AC20** — The selector is repaired on all three axes, each pinned by its own arm: it
      paginates (`--paginate --slurp`, verified against a 31-comment fixture); it excludes bot
      comments by **login identity**, not body content (verified by a human comment carrying the
      guard's own heading, which must NOT be excluded); and when no non-bot comment qualifies it
      **reopens** rather than falling back to the attacker-authored issue body. A complete comment
      yields zero reopens; a bot body above a complete human comment yields zero; a bot body above
      an incomplete human comment yields exactly one whose rendered body lists the missing URLs.
- [ ] **AC21** — The sweep is proven fireable against a planted violation, asserts a non-zero
      scanned-file count, and documents its three bounds.
- [ ] **AC22** — The suite asserts an exact assertion count of 13 (not `-ge`), its failure output
      names which arm failed, its failure marker is column-0 `FAIL`-shaped, and the `gh` stub is
      verified to be what `command -v gh` resolves to before the body runs — with sentinel
      `GH_REPO`/`ISSUE_NUM`, an empty `GH_TOKEN` and a temp `GH_CONFIG_DIR`, so a real `gh` could
      not mutate anything.
- [ ] **AC23** — `scripts/marketplace-drift-check.test.sh`'s default-shell comment is corrected.

### Cross-cutting

- [ ] **AC24** — `scripts/test-all.sh` registers the new suite in `want_scripts`, and
      `bash scripts/lint-orphan-test-suites.sh` reports it registered.
- [ ] **AC25** — `bash scripts/test-all.sh` exits 0, and on a machine without a docker daemon the
      rehearsal emits a declared skip whose **reason** is asserted — not merely an exit code, which
      the nested runner would launder to `PASS`.
- [ ] **AC26** — Every row of **all four** guard matrices was executed and the observed colour
      matches the Expected column; results recorded in the PR body, with controls labelled as
      controls so a green battery is not misread as mutations caught.
- [ ] **AC27** — `python3 scripts/lint-guard-contract.py` and
      `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` both pass, each
      invoked with the gate's own argument form rather than a hand-enumerated path list.

### Post-merge

- [ ] **AC28** — The closure-guard workflow was modified, so per
      `wg-after-merging-a-pr-that-adds-or-modifies` its behaviour is confirmed on `main`. It carries
      no `workflow_dispatch`, so confirmation is by re-running the new suite against the merged
      `main` file — the executing test is the verification surface.

## Test Scenarios

### A — gate suite, 10 new arms (floor 58 → 69)

Built on a **separate copied tree**, calling the function directly — never through
`r2check`/`R2_SHA`, whose mirror the same commit repairs. Fixture siblings must not share a
basename with any payload, or the basename-uniqueness check reddens them for the wrong reason.
Unreadability is injected with a **dangling symlink**, never `chmod 000` — root bypasses the mode
check, and A4/A5/A7 are exactly the arms that would silently disarm.

- **A1** Given the committed tree at real paths, the function returns 0 and prints a 64-hex digest.
  *(RED before the fix. Also the arm that catches an over-broad sibling abort firing on the
  unexpanded `*.tf.json` literal, so its abort message must name the sibling loop.)*
- **A2** Given a fixture with two sibling `.tf` files, returns 0. *(RED before the fix.)*
- **A3** Given a fixture with **three** siblings, returns 0 — sibling-count independence.
- **A4** Given a fixture with one `.tf` sibling as a dangling symlink, returns 1 naming that file.
  *(RED against the first draft's shape — measured rc=0.)*
- **A5** Given a fixture with a `.tf.json` sibling as a dangling symlink, returns 1 naming it — the
  abort attaches to **both** glob patterns, not just the first.
- **A6** Given a fixture with a readable `.tf.json` sibling, returns 0 **and** its digest differs
  from the same fixture with that file absent.
- **A7** Given a fixture with a referenced payload as a dangling symlink, returns 1 naming it.
- **A8** Given a fixture with a referenced payload **deleted outright**, returns 1 naming it — the
  job the deleted counting check used to do, and the one an `-r`-only guard could lose.
- **A9** Given a fixture whose module binds only 2 payloads with siblings present, returns 1 naming
  the drifted extraction and the payload count.
- **A10** Given the `$R2` fixture, `_r2_hash "$R2"` equals
  `git_data_rung2_user_data_sha256 "$R2/ci.yml"` — the equivalence arm that makes a third mirror
  drift unshippable, replacing the first draft's one-time byte-identity measurement.

Floor moves 58 → 69, and stays a **floor** — see DC-3. (This line previously read "asserted as
exact equality, matching the suite's existing form"; the suite's existing form is a floor, so
the stated justification did not hold.)

### B — rehearsal suite (floor 44 → 45)

RED evidence is **fault injection**, never a natural flake.

- **B1** apt install forced to fail past its retries → all three arms fixture-attributed naming
  `FIXTURE-FAIL: apt-get install`, container stdout tail present on its own lines, no emitter-worded
  text, suite exits non-zero.
- **B2** Capture server pointed at an unbound port → sentinel not observed, same attribution.
- **B3** The sentinel written into `capture.log` rather than a durable artifact → reddens on a
  **healthy** run, because the driver truncates that file three times. *(This replaces the first
  draft's "container exits 0 with a dead capture path", which had no reachable middle: dead before
  the sentinel is B2, and dead after a proven round trip is a genuine emitter finding per §Edge
  cases.)*
- **B4** B1's condition → forensics path printed and the tree exists after exit; likewise on a hard
  `exit 1` setup path where `fails == 0`.
- **B5** Healthy container → three arms produce normal verdicts, the run-level gate emits its own
  `pass`, and the total is 45.
- **B6** `apt-get` shadowed on `PATH` to fail on first call and succeed on retry → the suite
  completes normally **and** a retry marker is observed. Without the marker the arm is satisfied by
  a run where the retry loop was deleted and apt simply worked.
- **B7** The age-reaper removes a forensics tree back-dated with `touch -d` and retains a fresh one
  — asserted by fabricated mtimes, never by waiting, and its glob bounded so it cannot reap a
  concurrent run's tree.

Floor moves 44 → 45 (the gate's own `pass`).

### C — closure-guard suite, 15 arms (exact count 15)

Fixtures derive their URLs from the workflow's own `required_urls` array, so a URL drift cannot
silently collapse two fixtures onto one arm. The `gh` stub evaluates the body's real `--jq`
expression through `jq`, `exit 99`s on any unrecognised argv, lives in a per-run `mktemp -d`, and
is asserted to be what `command -v gh` resolves to **before** the body runs. `GH_REPO` is an
unroutable sentinel, `ISSUE_NUM=0`, `GH_TOKEN` empty, `GH_CONFIG_DIR` a temp dir — so a real `gh`
that somehow ran could not mutate anything.

- **C1** Incomplete closing comment under `bash -e`, executed as a **child process** → rc=0.
- **C2** …exactly one `gh issue reopen` (counted with an explicit delimiter, since the body passes a
  multi-line `--comment` and a line-based argv log would miscount).
- **C3** …the rendered body contains the checklist line the defect prevented — driven once with URLs
  missing and once with URLs present but the byte count missing, so both `printf` arms execute.
- **C4** Complete closing comment → rc=0, zero reopens.
- **C5** A bot reopen body newest with a **complete human comment beneath it** → zero reopens.
  *(Against the unfixed selector this reopens once — the arm that discriminates on count.)*
- **C6** A bot reopen body newest with an **incomplete human comment beneath it** → exactly one
  reopen whose rendered body still lists the missing URLs. *(Both versions reopen once here, so
  this arm discriminates on content.)*
- **C7** A **human** comment carrying the guard's own `## Closure gate` heading → NOT excluded,
  proving the filter is identity-based and not content-based.
- **C8** A 31-comment fixture → the newest comment is selected, not comment #30.
- **C9** No qualifying non-bot comment, and an issue body carrying all three URLs → reopens rather
  than satisfying itself from the body.
- **C10** Exactly one step matches the step name.
- **C11** That step declares no `shell:` key, and every `$VAR` the body reads is declared in its
  `env:` block.
- **C12** The body carries no `${{ }}` expression.
- **C13** The repo-wide sweep returns zero over the scoped directories having scanned a non-zero
  number of files; a planted violation in a synthesized fixture tree makes it return ≥ 1; and a
  violation planted inside an **excluded** path is not reported.

### Edge cases

- A module directory with zero siblings (every existing fixture) must keep returning 0.
- A capture file that exists but is zero bytes **after a proven round trip** is a genuine emitter
  finding and must NOT be fixture-attributed.
- A closing comment that is entirely absent (the step falls back to the issue body) must still reach
  the reopen path.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **A wrong fix narrows the input set** — measured as a real defect in this plan's own first draft, where an unreadable or `.tf.json`-renamed sibling returned rc=0 over a narrower set. | Both conditional loops now abort; Guard 1 rows 1, 2, 5, 6, 7 and 8 span both, and A3 is the arm that catches the draft-1 shape. |
| **The floor literal `9` goes loose** when a tenth payload lands — it does not abort, it tolerates losing one. | Stated rather than papered over: recorded in §Non-Goals, named in the abort message, and carried in a code comment. No automatic trigger exists and the plan does not claim one. |
| **The live-tree arm appears to contradict the gate suite's header.** | The header forbids asserting the *gate's verdict* on the live template; the suite already reads the live file as a non-asserting NOTE, and that verdict is now RELEASED. A1 asserts a different function's self-consistency, invariant under the emitter landing. Header amended in the same edit. |
| **A1 makes the `test-scripts` shard depend on infra composition** — a legitimate payload consolidation reds `test` with a message about a hash. | The abort message names the floor's provenance so the fix is obvious from the failure text alone. |
| **Only three of ~eight docker-dependent verdicts get the new treatment**, so one apt outage produces two verdict regimes in one run. | Stated in §Non-Goals and required in the PR body. The alternative — reworking all six container sites — is a different change. |
| **The `FIXTURE-FAIL:` cause is crowded out of the nested runner's capped, marker-anchored excerpt** when earlier container arms fail first. | On the CI path the suite is a direct step, so the whole log is visible. On the local nested path the cap is real; the tail is anchored on the marker line, and the limit is recorded rather than claimed away. |
| **Forensics are unreachable in CI** — infra-validation.yml has no `upload-artifact` step. | `logs.where` says so explicitly; the tree is a local-only aid, and the CI signal is the run log. |
| **A second `trap … EXIT`** would silently discard the forensics handler. | AC15, with a heredoc-aware anchor because a naive count returns 4. |
| **New `x=$(…)` captures grow the `lint-shell-capture-exit` baseline.** | Phase 0 reads the baseline; AC16 requires it unchanged or smaller. |
| **The `bash -e` premise rots** if a `shell:` key is added. | C7 asserts it and Guard 3 row 4 proves the arm fires — in the correct direction this time. |
| **The reopen's own comment self-satisfies field 1.** | The selector excludes bot-authored comments; C5 and Guard 3 row 6 pin it. |
| **Three defects, one PR, one squashed commit** — a revert takes all three. | Not argued away: this is a genuine cost, recorded in DC-1 for the operator, who owns the deliverable shape. Files are disjoint, which makes a manual follow-up revert straightforward but not automatic. |
| **A `gh issue reopen` failure kills the step before its `::warning::`** under `-e`. | Pre-existing and out of scope; recorded so it is not read as introduced here. |

## Non-Goals

- **Pre-baking the rehearsal container image.** Measured: apt = 107.99 s vs a 0.70 s bare spin,
  across six apt-bearing sites. Scoped out — it touches all six, invalidates the recorded rationale
  for not using `--network none`, and is not a small change. Follow-up trigger: **any R3/R4 arm
  reports a fixture-starvation failure in a CI run after this lands.**
- **The rehearsal workflow's bounded retry on a non-clearable `rc=2`.** Corrected at review: the
  bound is `deadline=$(( SECONDS + 16 * 60 ))`, not 20 × 30 s, and the rc=2 step-summary is not
  hardcoded — it interpolates the observed rc. The residual, stated accurately: on a derivation
  fault the summary still reads `TRANSIENT (no verdict)` while the corrected step log reads
  `DERIVATION FAULT (deterministic, NOT transient)`. Measured cost: up to ~16 minutes
  of a paid cpx22 per occurrence, re-running a deterministic failure, after `boot_complete` was
  already observed. The workflow already carries the right pattern (a fast-fail on repeated wrapper
  failures). Out of scope because changing a paid-host dispatch's retry semantics deserves its own
  review; filed with the measurement so the follow-up does not re-derive it.
- **The rehearsal workflow's hardcoded rc=2 step-summary text**, which sends the reader to Better
  Stack and Sentry for a repo-side derivation fault. Same follow-up.
- **Reworking the other container sites (T5/T17, S1, R1).** Guard 2's assembly is scoped to the R4
  capture files. Phase 0 re-runs the grep; a sibling site is folded in only if it reads *those*
  files.
- **Fixing `run-registered-suites.sh`'s PASS-for-skip laundering.** Real, documented in its own
  header, and the reason DC-2 resolves as it does — a separate surface with its own consumers.
- **Payload forms the extraction regex cannot see.** (A `.tf` in a SUBDIRECTORY of the module
  directory is NOT one of them, contrary to three review findings: Terraform does not recurse,
  and the module declares no `module {}` block, so such a file is inert and the digest is
  correctly unmoved. Withdrawn at review.) A multi-line `file(` call, an indirected
  `file(local.p)`, and a *second* `templatefile()` are all invisible to the single-line literal
  predicate, and each would render into `user_data` while the nine literal payloads still resolve.
  This is a pre-existing bound, not something the fix introduces — the deleted counting check
  called the same extractor on both sides and was equally blind. Recorded because Guard 1's
  Property must not claim completeness the mechanism cannot deliver. One cheap tightening remains
  available: assert `main.tf` contains exactly one `templatefile(`.
- **Path-containment hardening on the hash inputs.** (Symlink FOLLOWING is not part of this:
  Terraform's own `file()` follows symlinks, so hashing the target's content is the correct
  binding, not a gap. Withdrawn at review.) `sha256sum` follows symlinks and
  payload paths traverse `../../` with no canonicalisation, so a crafted `main.tf` could hash a
  file outside the infra tree, and a symlinked module directory would silently relocate all nine
  payloads. Fail-loud today (the paths would not exist) and orthogonal to the reported defect;
  filed with the `realpath` containment assertion so it is not re-derived.
- **Two closure-guard field weaknesses that predate this fix.** Field 2 accepts *any* green run in
  the repo — it checks `conclusion` but neither `workflowName` nor `createdAt`, while the reopen
  body promises both — and the `if:` job filter admits any issue whose title matches, so anyone can
  spin the workflow. Both are properties of the guard's design rather than the `printf` defect;
  filed together so the guard's promises and its mechanism are reconciled in one pass.
- **Closing #6977.** Context only. This removes one blocker; it opens no birth route and creates no
  evidence file.
- **Changing the capture script's exit codes.** The 0/1/2 contract is consumed by the workflow.

## Files to Edit

- `tests/scripts/lib/git-data-birth-readiness-gate.sh` — abort in both conditional loops; `*.tf.json`
  in the glob; payload floor; delete the counting block and both literals; re-word both abort
  messages; update the orphaned extraction comment.
- `tests/scripts/test-git-data-birth-readiness-gate.sh` — arms A1–A11 on a separate copied tree; the
  `_r2_hash` mirror repair and its equivalence arm; the header amendment; floor 58 → 69.
- `tests/scripts/test-git-data-rung2-evidence-capture.sh` — one executing arm for the
  derivation-fault path; floor 33 → 34.
- `scripts/followthroughs/git-data-rung2-evidence-capture.sh` — the `TRANSIENT:` label; exit code
  unchanged.
- `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` — container `FIXTURE-FAIL:` markers
  (five new, one renamed), bounded apt retries, the round-trip sentinel and context-managed write,
  the `docker run` rc capture, the run-level liveness gate (with its own `pass`, floor 44 → 45),
  the durable `sentinel.ok` artifact, the column-0 stdout tail, a named fault-injection hook for
  the mutation rows, the suite's exit expression, and the in-place EXIT-trap change with a reaper.
- `.github/workflows/follow-through-closure-guard.yml` — `--` on the two `printf` calls, plus the
  three selector repairs: `--paginate --slurp`, a `.user.login` identity filter, and reopening
  rather than falling back to the issue body when no comment qualifies.
- `scripts/marketplace-drift-check.test.sh` — correct the default-shell comment.
- `scripts/test-all.sh` — `run_suite` registration in `want_scripts`.

## Files to Create

- `scripts/follow-through-closure-guard.test.sh` — the executing regression suite (C1–C10), modelled
  on the house PyYAML step-extraction plus stubbed-binary pattern, with the argv-recording stub shape
  from `scripts/sweep-followthroughs.test.sh`, the `shell:`-key premise assertion from
  `scripts/prod-version-drift-check.test.sh` (whose statement of the default shell is the correct
  one), and the cardinality and no-`${{ }}` assertions from `scripts/digest-oracle-guard.test.sh`.

## Open Code-Review Overlap

None. All 64 open `code-review` issues were queried; none names any file this plan touches or creates.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** A devex consult plus a five-agent panel (DHH, Kieran, code-simplicity,
architecture-strategist, spec-flow) reviewed the first draft. Their material findings are folded in
above: a measured fail-open the draft's own #7485 fix introduced on the sibling glob; the wrong
default shell for a `run:` block with no `shell:` key; a latent self-satisfying oracle the #7506 fix
would activate; a parallel hash mirror that had already drifted twice; three mechanisms cut by two
reviewers independently (the `inconclusive` counter, the ADR amendment, the image pre-pull); and the
withdrawal of a revert-cleanliness claim that squash-merge falsifies. No new service, schema,
credential, vendor, persistent store or user-facing surface.

### Product/UX Gate

Not applicable. No path in `## Files to Edit` or `## Files to Create` matches any UI-surface term or
glob, so the mechanical override does not fire and the tier is NONE.

## Research Insights

### Premise validation

Checked against `origin/main` = 07cf8ebcb. #7485, #7501, #7506 all OPEN, none closed by a merged PR;
#6977 OPEN, context only. All cited paths exist. Both reported defects reproduce byte-for-byte.

Six premises were **corrected**: the "33/33 green" figure (the suite is 58/58); the claim that the
gate suite never touches the live file (it does, as a NOTE); the countdown-timer premise (#6982 is
CLOSED and the live gate now reports RELEASED); "only production caller is the capture script" (the
birth interlock is a second caller); the default shell for a `run:` block with no `shell:` key; and
the revert-cleanliness claim (squash-merge).

### Property list

1. The rung-2 evidence hash can be computed on a correct tree, and refuses on a drifted one.
2. The hash binds every file that decides what boots — no more, no fewer.
3. A rehearsal arm never attributes to the emitter a condition its evidence cannot support.
4. A starved rehearsal fixture is distinguishable from a real finding, by a reader who was not present.
5. The closure guard reaches its reopen whenever a required field is missing — and only then.
6. The `printf '-` class cannot return.

### Cut list

- *Correcting the discount arithmetic* (incl. the measured sibling-count variant) → buys 1 but keeps
  the coupling. Superseded by the per-reference abort.
- *Aborting on the payload loop only* → **measured fail-open** on property 2. Superseded by aborting
  on both loops plus `.tf.json` coverage.
- *A sibling floor* → reintroduces the literal it removes and breaks a legitimate consolidation.
- *A committed payload manifest* → a second place to update, for a benefit the abort already gives.
- *A third `inconclusive` counter* → zero mechanical delta against `fail()`; cut by two reviewers.
- *An ADR-177 amendment* → its substantive point already exists verbatim in ADR-177.
- *Per-arm liveness preconditions* → three copies of one run-level fact; the non-emptiness conjunct
  contradicted property 3.
- *A retrying image pre-pull* → the image is already local by R4; its only site is scoped-out code.
- *Raising the bind-poll budget* → apt runs before the poll and is unbounded.
- *A distinct exit code for a fixture failure* → ADR-177 records that a nested runner flattens it.
- *A grep over the workflow source for #7506* → pins spelling, not behaviour.
- *Changing the capture script's exit code* → only the label misdescribes.

### Value-proposition measurement

The pre-bake is the only cost-shaped claim. Measured: apt update + install of `curl python3` in
`ubuntu:24.04` = **107.99 s**; bare container spin = **0.70 s**; the image ships neither binary; six
apt-bearing sites exist. Real and large, but not the correctness fix and not a small change.

### Applicable institutional learnings

- `2026-08-11-my-fixture-shared-the-bug-so-the-test-could-not-see-it.md` — the diagnosis of the 58/58
  green, and of `_r2_hash`'s drift.
- `2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md` — prove the
  check can fail first; every mutation matrix discharges this.
- `2026-07-24-count-vs-floor-guard-single-value-fixtures-cannot-discriminate-operator.md` — fixtures
  at `(N, N-1)` cannot discriminate `<` from `!=` from a constant; why the A-arms span three sibling
  counts, two payload counts and both unreadable directions.
- `best-practices/2026-07-08-verify-sentinel-hardcoded-count-breaks-on-new-counted-object.md` — a
  hardcoded count over a widenable set must be derived or removed; why the floor's residual
  looseness is stated rather than claimed away.
- `2026-07-30-four-ways-a-green-guard-asserted-nothing-rung2-route.md` — on this subsystem:
  cardinality is not discrimination.
- `best-practices/2026-07-03-enforcement-probe-must-discriminate-exit-codes-not-any-failure-as-safe.md`
  — never collapse "measured negative" and "could not measure"; the structural fix for #7501.
- `2026-07-05-content-starvation-absence-of-work-is-not-an-error.md` — starvation needs its own signal.
- `2026-08-12-every-fix-i-shipped-reintroduced-the-class-it-closed.md` — the most load-bearing here:
  the first draft's #7485 fix reintroduced its own class one contributor over.
- `best-practices/2026-07-02-gha-run-default-shell-has-pipefail-guard-grep-substitutions.md` and
  `ADR-170` — a `run:` block dies mid-block under the inherited `-e`.
- `2026-07-27-my-assertion-pinned-the-text-not-the-shell-that-runs-it.md` — why the #7506 test
  executes the body.
- `ADR-177` / `ADR-181` — the result taxonomy, and the exit-code constraint that made the amendment
  unnecessary.
- `ADR-180` — the guard contract as a plan-time deliverable.
- `ADR-149` — the git-data birth route and readiness interlock.

### Conventions carried from AGENTS.rules.md

`cq-write-failing-tests-before`; `cq-assert-anchor-not-bare-token` (every new grep anchors on a call
form and is mutation-tested); `cq-cite-content-anchor-not-line-number`;
`cq-ac-must-not-depend-on-concurrent-sessions` (fixture failures are injected, never awaited);
`wg-use-closes-n-in-pr-body-not-title-to`; `wg-after-merging-a-pr-that-adds-or-modifies` (AC28);
`wg-defer-only-after-inline-triage` (the pre-bake and the retry-poll deferrals ran the triple test);
`rf-review-finding-default-fix-inline` (the mirror repair, the oracle and the shell-comment
correction are folded in, not filed); `hr-observability-as-plan-quality-gate` and
`hr-observability-layer-citation` (every failure mode names layer 6 and the in-surface markers).

### Toolchain facts verified at plan time

- A `run:` block with no `shell:` key is invoked `bash -e {0}`; `shell: bash` maps to
  `--noprofile --norc -eo pipefail`. The repo carries both statements in different files; the linter's
  is correct and the other is corrected here.
- `yq` is not installed and is declined repo-wide; PyYAML 6.0.3 is the house standard.
- Nothing auto-discovers `scripts/*.test.sh`; `scripts/lint-orphan-test-suites.sh` is the safety net.
- `main` is squash-merged: 200/200 recent commits have a single parent.
- The nested runner prints `PASS` for any suite exiting 0, and on RED dumps a capped, marker-anchored
  excerpt admitting the `[A-Z][A-Z0-9]*-FAIL` shape. On the CI path the rehearsal is a direct step,
  so that selection does not apply there.
- `infra-validation.yml` has no `upload-artifact` step — CI forensics do not survive.
- Do not depend on docker for anything under `tests/scripts/`.
