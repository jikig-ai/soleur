---
title: "chore: lint-shell-capture-exit — flag dead `$?` reads after plain calls and `test && action` function tails"
type: chore
date: 2026-09-25
slug: chore-capture-exit-dead-rc-read
branch: feat-one-shot-8784-capture-exit-plain-call
issue: 8784
closes: 8784
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# lint-shell-capture-exit: cover the fn-arg-then-rc-$? errexit shape

## Overview

`scripts/lint-shell-capture-exit.py` gates the `x=$(cmd)` capture form of the
errexit class but not the plain-call form: a bare command or `x=$(cmd)` line
followed by an `rc=$?`-family read is unreachable-for-nonzero under `set -e`,
so the read only ever sees `0` (or the process has already aborted). The same
class has a tail variant — `(( n > 0 )) && echo ...` (or `[ ]`/`[[ ]]`/`test`)
as a function's last statement, where a normal "nothing to report" outcome
returns the test's non-zero status to a `set -e` caller. Extend the gate with
two new finding classes — S3 (dead status read after an unprotected command)
and S4 (status-leaking `test && action` at a function tail) — keyed into the
same baseline mechanism, plus the `set` line inline-comment fix the S3
calibration exposed. Scope-out from PR #8738; closes #8784.

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

## Problem Statement / Motivation

Issue #8784 records the gap left by PR #8738 (scratch reclamation): three call
sites in `tmp-classify.sh`/`soleur-tmp-purge.sh` needed
`if fn; then rc=0; else rc=$?; fi` because `fn "$x"` followed by `rc=$?` is
dead code under `set -e` — a plain call returning non-zero aborts the script
before `$?` is read. A fourth site had `(( skipped_odd > 0 )) && echo ...` as
`run_scan`'s last statement: with zero skips the arithmetic test exits 1, the
`&&` list returns 1, the function returns 1, and the `set -e` caller died
before the report printed — the silent mid-suite death the reclamation PR
debugged the hard way (`tests/scripts/test-tmp-purge.sh` truncated after its
header).

The existing gate only anchors on `x=$(cmd)` substitutions. The sibling gate
`scripts/lint-workflow-errexit-capture.py` already anchors on the *read* for
GitHub Actions `run:` blocks, and its docstring records the measurement that
motivates this work: 9 of its 17 calibration sites were bare commands followed
by `rc=$?`. In shell scripts the same dead-read shape exists — a quick census
of tracked `*.sh` finds `name=$?` assignments in 60+ files — and nothing
currently gates it.

Per ADR-166 the class has already recurred in disguises documentation failed
to stop; this is the mechanical gate catching up to the remaining disguises.

## Research Insights

### Premise Validation (Phase 0.6)

- Issue #8784 is `OPEN`, no closing PR — the premise is live, not stale.
- `scripts/lint-shell-capture-exit.py`, `.baseline.txt`, and `.test.sh` all
  exist on this branch; the gate is registered in `scripts/test-all.sh`
  (`run_suite` rows at the `lint-shell-capture-exit` / `-live` entries) and
  the live run is green: `1271 script(s) scanned, 0 new findings, 199
  baselined`.
- PR #8738 merged 2026-09-25 (`feat: ownership-keyed scratch reclamation…`),
  the deferral source is real.
- The cited learning
  `knowledge-base/project/learnings/logic-errors/2026-09-24-set-e-rc-capture-and-dollar-dollar-identity-traps.md`
  exists and names both shapes (items 1 and 2).
- Mechanism check vs ADR corpus: "a recurring defect class that documentation
  has failed to stop earns a `scripts/lint-*` gate" is ADR-166-adjacent and
  already endorsed by the existing gate's docstring; no ADR rejects a
  baseline-keyed lint extension. Nothing proposed sits in a rejected-alternatives
  table.

### Property List (Phase 0.6b)

- P1: a *new* `cmd` / `x=$(cmd)` statement followed by an `rc=$?`-family status
  read in a `set -e` region of a tracked `*.sh` fails the gate.
- P2: a *new* `(( expr ))`/`[ expr ]`/`[[ expr ]]`/`test expr` `&& action`
  appearing as the last statement of a function body in a `set -e` region
  fails the gate.
- P3: pre-existing instances of P1/P2 do not fail the gate (baseline-keyed
  grandfathering, same fingerprint mechanism as S1/S2).
- P4: legitimate capture idioms — `cmd || rc=$?`, `rc=$?` inside an `if`/`||`
  condition, function-head reads of the caller's status, reads inside `$( )`
  subshell programs, reads in non-errexit regions — do not fire.

### Cut List (Phase 0.6b)

- **Sibling gate for the companion shape** → covers P2 → cut: the same file
  already owns the errexit-state tracking, comment/heredoc stripping,
  continuation folding, and the fingerprint/baseline machinery a sibling would
  re-implement; S3 also needs S1-dedupe awareness that is trivial inside one
  `scan()` and awkward across processes. Issue wording permits either ("or add
  a sibling rule"); same-file is strictly cheaper.
- **shellcheck** → nominally covers "exit status" classes → already rejected by
  the existing gate's `WHY NOT shellcheck` section: SC2312 is opt-in and models
  the opposite problem; it ran in CI and caught none of the #7332 instances.
- **Bare `$?`-in-argument reads** (`echo "rc=$?"`, `if [[ $? -ne 0 ]]`,
  `exit $?`) → adjacent class, not in the issue's ask → declined: the sibling
  gate flags them for `run:` blocks, but the shell-tree calibration is much
  noisier (`exit $?` end-of-script is idiomatic). Extending the read anchor
  later is a one-regex widening, not new machinery; scope-out only.

### Repo research (in-process — no Task tool on this harness)

- The existing `scan()` is single-pass over `join_continuations` output,
  tracking `errexit` via `SET_RE` + `errexit_after`. S3 needs the sibling's
  **two-pass** model instead: compute the errexit state *before* each logical
  line, then judge each read against the state at *its command's* line —
  otherwise the `cmd\nset +e\nrc=$?` mis-fix (the remediation text invites it)
  goes invisible. Mirror `lint-workflow-errexit-capture.py` `scan_body()`
  (lines 332–434): `READ_RE` anchor, `before`-text checks for the `||`/`&&`
  protection idiom, back-walk to the nearest non-`set` logical line,
  `is_protected` for control lines and `!`-negation, subshell `depth` so a
  `set +e` inside `( )` cannot disarm the model (fail-closed).
- **Measured S3 footprint (prototype, comment-aware errexit):** ~43 sites in
  15 files — overwhelmingly `.test.sh` capture helpers
  (`out=$(python3 "$SCRIPT" …)\nrc=$?`). Benign dead reads (the test aborts
  loudly anyway) plus fragile-but-working sites inside functions invoked only
  in `||`/`if` contexts (e.g. `apps/web-platform/infra/ci-deploy.sh:2390`,
  whose `run_faithful_sandbox_canary` is called as `… || true` at line 3587,
  so its `exec_rc=$?` is live). The rule flags all of them — the explicit
  `if cmd; then rc=0; else rc=$?; fi` rewrite is correct in *both* contexts —
  and the baseline absorbs the existing set. All are baseline candidates, not
  in-PR fixes.
- **Measured S4 footprint:** 14 raw candidates, ~4–6 after excluding
  `||`-armed tails and bare `[[ ]]` predicate tails (the `&&` must sit
  *outside* the test brackets — an early prototype counted `[[ a && b ]]`
  inside-bracket `&&`, which is not the leak). Remaining candidates are
  test-tail assertions and predicate helpers — all baseline candidates.
- **`errexit_after` inline-comment defect (found during calibration, affects
  S1/S2 today):** it tokenizes the raw `set` argument string, so
  `set -uo pipefail  # deliberately NOT -e` arms errexit in the model via the
  comment's `-e` token (`.claude/hooks/memory-backstop.sh:308`,
  `.claude/hooks/supabase-loopback-warn.sh:23`). The direction is fail-safe
  (over-arms, never disarms), but S3's ubiquity makes the over-flagging
  material: the prototype counted 57 hits before the fix, 43 after. Fix:
  strip the unquoted `#` tail from `set` args before tokenizing. The fix can
  only *remove* phantom-armed findings — it cannot hide real ones — so
  existing S1/S2 live output is unchanged or shrinks.
- **Fingerprint design for S3:** the read line's text (`rc=$?`) is identical
  across hundreds of sites — keying the baseline on it would grandfather every
  future `rc=$?` in an already-baselined file. Key on the *command* text the
  read refers to (plus the read), matching the sibling's attribution at the
  command's line (`scan_body` line 432). S4 keys on the tail statement text,
  same as S1/S2.
- **Baseline mechanics:** `--write-baseline` rewrites the whole file from
  current findings, so the S3/S4 bootstrap is one regeneration run after
  implementing — the same mechanism the gate itself shipped with. The
  `test-all.sh` comment records "the baseline may shrink and must never grow"
  as *convention*; no mechanical growth-check exists (`.highwater` files
  belong to other gates). Regen grows the file to ~255 entries — a one-time,
  PR-visible, reviewable event, not a smell.
- **Function-tail detection (S4):** heuristic open/close tracking —
  `name() {`, `name()` then `{`, `function name` opens; a line whose stripped
  form is `}` closes. The last non-blank logical line before the `}` is the
  candidate tail. Documented limits: `}` sharing a line (`done; }`), one-line
  function bodies, nested `{ }` groups, and dynamic definitions are not
  tracked — misses fail silent, never loud.
- **Community/functional overlap:** no uncovered stacks (repo is
  bash/Python/TypeScript, all covered by built-in agents). The community
  answer is already on file — the docstring's `WHY NOT shellcheck` section;
  nothing new to install.
- **Advisor consult (Phase 4.5):** skipped — no Task tool in this harness;
  the riskiest decision (read-line vs command-line fingerprinting; the two
  context arms of S3) was resolved by measuring the real tree directly.

### Related issues / PRs

- #8784 (this), PR #8738 (deferral source, merged), #7332/PR #7336 (the
  original S1/S2 class), `lint-workflow-errexit-capture.py` (the read-anchored
  sibling whose `scan_body` is the design source for S3).
- Learnings:
  `knowledge-base/project/learnings/logic-errors/2026-09-24-set-e-rc-capture-and-dollar-dollar-identity-traps.md`
  (the two shapes), plus the gate's own test-header lessons (subsidiary
  capture inside `$( )` losing status — recorded in `run_lint`'s comment).

## Open Code-Review Overlap

Two open `code-review` issues mention `scripts/test-all.sh` in their bodies:
#8659 (test-suite EXIT-trap/sandbox leak) and #7942 (unregistered `*.mutation.sh`
batteries). **Disposition: acknowledge** — both concern other suites' harnesses;
this plan's only `test-all.sh` interaction is an optional comment touch-up
near existing rows, not a behavioural change. #8784 itself matched as the
self-reference.

## Proposed Solution

Extend `scripts/lint-shell-capture-exit.py` with two finding classes in the
same `scan()` pipeline, reusing its comment/heredoc stripping, continuation
folding, fingerprint, and baseline plumbing:

**S3 — dead status read.** Anchor on the *read* (`name=$?`, `name="$?"`,
`name='${?}'`, indexed/attributed forms `declare -i rc=$?`, `local rc=$?`, and
`${PIPESTATUS[n]}`/`$PIPESTATUS` reads), mirroring `lint-workflow-errexit-capture.py`'s
semantics: split the read line at the anchor; `||`/`&&` anywhere in `before`
means the read is a protection idiom's right operand → skip; a trailing
separator (`;`, `|`, `&`) in `before` puts the command on this line; otherwise
walk back to the previous non-`set` logical line. Judge errexit at the
*command's* line (two-pass). Additional shell-specific exclusions beyond the
sibling's: the resolved command is a function opener (`name() {`/`function name`),
a bare `{`/`}`/`fi`/`done`/`esac`/case-arm head (composite-status or
caller-status reads — `local rc=$?` first in a function reads the *caller's*
status legitimately, e.g. `gdpr-override.sh`'s trap handler), or the read sits
inside an unclosed `$( )`/`( )` group (carry-status-out idiom, e.g.
`.claude/hooks/lib/hook-input.sh:249`; track a `depth` counter in pass 1).
Skip an S3 when the resolved command line already emitted S1/S2 (same defect,
one report). Report at the read's line; fingerprint the command's normalized
text plus the read's.

**S4 — status-leaking test tail.** While inside a tracked function body, if the
last logical line before the closing `}` is `(( expr )) && rest` or
`[ expr ]`/`[[ expr ]]`/`test expr` `&& rest` — the `&&` strictly *outside* the
test's brackets — and the line carries no `||` arm, and the action's first word
is not `return`/`exit`/`break`/`continue` (explicit status flow), and the
function name does not match a predicate pattern (`is_*`, `has_*`, `check_*`,
`assert_*`, `can_*`, `should_*`, `need_*`, `*_ok`, `same_*`, `valid*`) → flag.
The function returns the test's non-zero status on the false arm — a normal
"nothing to do" outcome masquerading as failure to a `set -e` caller.

**`errexit_after` fix.** Strip the unquoted `#`-comment tail from `set` args
before tokenizing (`set -uo pipefail  # deliberately NOT -e` must not arm
errexit). Same-direction fix (fewer phantom-armed findings), required for S3's
calibration to be honest.

**Baseline.** One `--write-baseline` run after implementing, committing the
regenerated `scripts/lint-shell-capture-exit.baseline.txt` (~40–50 new keys
on top of 199). Triage the emitted list first: every entry must be benign
(dead-but-loud test helpers, `||`-context capture idioms, predicate tails) —
if any entry looks like a live bug the PR fixes it instead of baselining.

## Technical Considerations

- **Two context arms of S3, one fix.** `cmd\nrc=$?` is dead when the enclosing
  code runs under plain `set -e`, and *fragile* when the enclosing function is
  only ever invoked in a condition/`||` context (errexit is suppressed for the
  whole call tree). The rewrite `if cmd; then rc=0; else rc=$?; fi` is correct
  in both, so flagging unconditionally is honest — the docstring must say both
  arms plainly or a reviewer will re-derive the "condition-context false
  positive" objection from scratch.
- **`cmd && rc=$?` is out of scope** — the `&&` short-circuits the read on
  failure and does not abort (non-final `&&` operand is errexit-exempt), so
  the read is skipped-not-dead. Different class; documenting it as deliberate
  exclusion keeps it out of the FP debate.
- **`errexit_after` fix direction:** stripping comments can only disarm a
  phantom-armed region; a real `set -e` still arms. Verify live-run output is
  byte-identical before and after on the real tree (it is — the phantom-armed
  files have no S1/S2 findings), and let the fixture suite pin the semantics.
- **Fingerprint stability:** normalised text, no line numbers — same
  trade-off as S1/S2 (an identical new line in a baselined file is
  grandfathered; accepted there, inherited here deliberately).
- **NFR:** the linter stays a single `git ls-files` pass in Python — runtime
  unchanged at ~2s over 1271 scripts. No new dependencies.
- **Security:** the linter reads repo files only; the `errexit_after` fix
  removes a false-positive source in hooks that guard write paths — no
  security surface change.

## Implementation Phases

### Phase 1: errexit-model fix + S3 (dead status read)

- In `scripts/lint-shell-capture-exit.py`: strip unquoted `#` tail in
  `errexit_after`'s arg handling; restructure `scan()` to the two-pass model
  (state-before-each-line + `depth`); add the `READ_RE`/before/back-walk/
  `is_protected` machinery (ported semantics, not imported code — the sibling
  is a separate script with workflow-specific concerns); add S3 reporting with
  command-text fingerprint and S1/S2 dedupe.
- Fixtures in `scripts/lint-shell-capture-exit.test.sh`:
  - must-fire: `fn "$x"` then `rc=$?`; `out=$(cmd)` then `rc=$?`; `cmd; rc=$?`
    same-line; `local rc=$?` mid-function; `rc=${PIPESTATUS[0]}`; the
    `cmd \n set +e \n rc=$?` mis-fix (command ran armed); `declare -i rc=$?`.
  - must-not-fire (each with the mixed-fixture positive control coverage):
    `cmd || rc=$?`; `rc=$?` as an `if`/`while` condition's read inside the
    protected operand; function-head `local rc=$?` (caller-status idiom);
    `name=$?` inside `$( … )` (carry-out idiom); reads in a `set +e` region;
    `set -uo pipefail # deliberately NOT -e` then `cmd;rc=$?` (the comment-fix
    fixture); `cmd && rc=$?` (documented exclusion); no `set -e` at all.
- Raise `MIN_ASSERTIONS` to the new count (floor is load-bearing anti-vacuity).

### Phase 2: S4 (status-leaking test tail)

- Function-boundary tracking in `scan()` (open/close heuristic above); flag
  `test-builtin && action` tails per the exclusion set.
- Fixtures: `(( skipped > 0 )) && echo` at tail fires; `[[ -f f ]] && grep -q`
  tail fires; bare `[[ cond ]]` tail silent (predicate idiom); `test && act
  || fallback` silent (`||` arm decides); `is_ready() { [[ c ]] && notify; }`
  silent (predicate-named); `[[ c ]] && return 1` silent; tail `(( c )) && e`
  inside a function in a `set +e` file silent.
- Docstring: new `THE RULE` paragraphs for S3/S4, the two-context-arms note,
  the `cmd && rc=$?` exclusion, heuristic limits (single-line `}`, `$( )`
  depth tracking, function-boundary heuristic).

### Phase 3: baseline regeneration + triage + registration comment

- Run `python3 scripts/lint-shell-capture-exit.py --baseline
  scripts/lint-shell-capture-exit.baseline.txt --write-baseline` and diff the
  file: assert every new key is `S3` or `S4`, all prior `S1`/`S2` keys persist.
- Triage the new entries one by one (list printed pre-write): benign idiom →
  keep baselined; suspected live bug → fix in this PR instead of baselining.
  Expected: all benign (verified on the prototype census).
- Optionally touch up the `test-all.sh` registration comment to name the new
  classes (comment-only; registration rows unchanged).

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Sibling `scripts/lint-shell-dead-status-read.py` | Re-implements errexit tracking, fingerprint, baseline plumbing; S3 needs S1-dedupe that one `scan()` gives for free. Issue permits either; same-file is cheaper. |
| Widening the workflow gate to also scan `*.sh` | The docstring already records why the anchors invert between surfaces; mixing both targets in one gate recreates the blind-spot problem. |
| shellcheck SC2312 | Opt-in, opposite problem, already rejected by this gate's `WHY NOT shellcheck` section. |
| Flag bare `$?`-in-argument reads too (`echo "rc=$?"`) | Real but noisier class; `exit $?` is idiomatic. Scope-out, one-regex widening later if needed. |
| Call-context analysis (only flag when the enclosing function is invoked plainly) | Cross-function call-graph + dynamic dispatch in bash is unboundedly fuzzy; flagging is honest anyway because the explicit rewrite is correct in both contexts. |

## User-Brand Impact

- **If this lands broken, the user experiences:** a wrong lint verdict —
  either a false `[REJECT]` blocking an unrelated PR's `test-all.sh` run, or a
  silently-missed new dead-read. Both are developer-facing friction in CI,
  never end-user-facing.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  nothing — the linter reads tracked shell files and prints findings; no data
  surfaces.
- **Brand-survival threshold:** `none`

## Guard Contract

### Guard 1 — S3 dead status read

**Property.** In a `set -e` region of a tracked `*.sh`, no command whose
failure would abort the process is immediately followed by a read of its exit
status — the read is dead code.

**Assembly.** Every tracked `*.sh` file enumerated by `git ls-files '*.sh'`
(the chokepoint — `collect_targets`), every logical line after continuation
folding, and every status-read anchor (`name=$?`/`"${?}"`/`${PIPESTATUS[…]}`)
that resolves to an unprotected preceding command under the two-pass errexit
model. The protection exemptions are the `before`-text `||`/`&&` forms, the
function-head/composite-read exclusions, and `depth > 0` (inside `$( )`/`( )`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `fn "$x"` + `rc=$?` to a fresh fixture under `set -e` | RED — S3 fires |
| 2 | Neuter the `READ_RE` anchor so no status read ever matches | RED — every must-fire fixture fails (dispatch/vacuity row) |
| 3 | Add a *second* `cmd`+`rc=$?` pair after a compliant first command | RED — both sites named, not just the first (multi-member row) |
| 4 | Move `set +e` from *before* `cmd` to *after* `cmd` (`cmd\nset +e\nrc=$?`) | RED — the command ran armed; judging state at the read's line is the mis-fix this row exists for (order/lifetime row) |
| 5 | Weaken `before`-text protection to substring-match `||` anywhere in the command | RED — `cmd || rc=$?` fixture must stay silent; a substring rule flags it |
| 6 | (Harness) stub the linter to always exit 0 | RED — must-fire fixtures fail |
| 7 | (Must-PASS, non-canonical) `out=$(cmd) 2>&1` then `rc=$?` in a `set +e` file | stays silent — legitimate non-errexit capture |

**Anchor.** The baseline (`scripts/lint-shell-capture-exit.baseline.txt`) is a
stored value keyed on `path + class + normalized command text`; weakening the
rule while keeping the file green requires editing that file in the same diff —
review-visible, and the `-live` `run_suite` row recomputes findings over the
real tree on every run so an un-baselined finding cannot hide.

### Guard 2 — S4 status-leaking test tail

**Property.** A function's last statement must not be `test-builtin && action`
with no `||` arm — the test's false arm makes a normal outcome a non-zero
return to a `set -e` caller.

**Assembly.** Function bodies in tracked `*.sh` located by the
open/close heuristic (`name() {`…`}`); the quantified set is the last
non-blank logical line before each closing `}` in an errexit-armed region,
restricted to `(( ))`, `[ ]`, `[[ ]]`, `test` left-operands of `&&`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Append `(( n > 0 )) && echo done` as a function tail under `set -e` | RED — S4 fires |
| 2 | Drop the function-boundary tracking so tails are never resolved | RED — every S4 must-fire fixture fails (dispatch/vacuity row) |
| 3 | Add a second `test && action` tail in a second function after a compliant first | RED — both named (multi-member row) |
| 4 | Match `&&` *inside* `[[ a && b ]]` | RED — the bare-predicate fixture must stay silent; inside-bracket `&&` is not the leak |
| 5 | (Harness) stub the linter to always exit 0 | RED — must-fire fixtures fail |
| 6 | (Must-PASS, non-canonical) `is_ready() { [[ -f f ]] && notify; }` | stays silent — predicate-named function exemption |

**Anchor.** Same baseline mechanism and `-live` row as Guard 1.

## Files to Edit

- `scripts/lint-shell-capture-exit.py` — new S3/S4 classes, two-pass errexit,
  `errexit_after` comment fix, docstring.
- `scripts/lint-shell-capture-exit.test.sh` — new fixtures, `MIN_ASSERTIONS`
  bump.
- `scripts/lint-shell-capture-exit.baseline.txt` — one regeneration.
- `scripts/test-all.sh` — optional comment touch-up naming the new classes
  (no registration change needed).
- `knowledge-base/project/specs/feat-one-shot-8784-capture-exit-plain-call/tasks.md` — this feature's tasks.

## Files to Create

- none

## Acceptance Criteria

- [ ] `scripts/lint-shell-capture-exit.py` flags a new `fn "$x"` + `rc=$?`
  fixture as `S3` and a new `(( n > 0 )) && echo` function-tail fixture as
  `S4`, at the read/tail line respectively, keyed by the command text.
- [ ] The protection idioms stay silent: `cmd || rc=$?`, function-head
  `local rc=$?`, reads inside `$( )`, `set +e` regions, bare `[[ cond ]]` and
  `||`-armed tails, predicate-named functions.
- [ ] `set -uo pipefail # deliberately NOT -e` no longer arms the errexit
  model (fixture), and the pre-fix/post-fix live output on the real tree is
  identical.
- [ ] `bash scripts/lint-shell-capture-exit.test.sh` → `ALL TESTS PASSED` with
  the raised `MIN_ASSERTIONS` floor.
- [ ] `python3 scripts/lint-shell-capture-exit.py --baseline
  scripts/lint-shell-capture-exit.baseline.txt` → `[OK]`, with the regenerated
  baseline committed and every new key triaged benign or fixed (none left
  unfixed-and-unbaselined).
- [ ] New baseline keys are exclusively `S3`/`S4`; all prior `S1`/`S2` keys
  persist (verified by diffing the regenerated file).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — lint tooling change confined to
`scripts/`.

## Test Scenarios

- Given `set -e` and `fn "$x"` then `rc=$?`, when the linter runs, then it
  prints `:N: [S3]` at the read's line and exits 1.
- Given `set -e` and `cmd` then `set +e` then `rc=$?`, when the linter runs,
  then the S3 finding still fires (the command ran armed) — the mis-fix shape.
- Given `set -uo pipefail # deliberately NOT -e` then `cmd; rc=$?`, when the
  linter runs, then nothing fires (comment tokens do not arm the model).
- Given `set -e`, `f() {`, `local rc=$?`, `}`, when the linter runs, then
  nothing fires (caller-status idiom at function head).
- Given `set -e` and `run() { (( c > 0 )) && echo x; }`, when the linter runs,
  then `:N: [S4]` at the tail line.
- Given `set -e` and `check() { [[ -f f ]] && grep -q x f || true; }`, when the
  linter runs, then nothing fires (`||` arm decides the status).
- Integration: `bash scripts/lint-shell-capture-exit.test.sh` prints
  `ALL TESTS PASSED`; `python3 scripts/lint-shell-capture-exit.py --baseline
  scripts/lint-shell-capture-exit.baseline.txt` prints `[OK]` and exits 0.

## Success Metrics

- The two documented defect shapes from #8784 are reproducible as RED
  fixtures; the live run over 1271 tracked scripts stays `[OK]` via the
  baseline.
- Zero new findings land un-baselined after the regeneration commit.
- Suite assertion count rises by the fixture delta and the floor is raised to
  match (no silent fixture skipping).

## Dependencies & Risks

- **Risk — baseline growth is convention-gated, not mechanically gated:**
  mitigated by the triage task listing every new key in the PR-visible diff
  and by the AC requiring all prior keys persist.
- **Risk — heuristic function-boundary tracking misses `}` sharing a line:**
  bounded, documented in the docstring; misses fail silent on new code only
  in shapes the heuristic can't see — acceptable v1, enumerated.
- **Risk — `depth` tracking for `$( )` is quote-naive:** a `)` inside a
  string literal can miscount; the counter clamps at 0 and the direction is
  fail-safe (over-skip inside groups, never over-flag).
- **Risk — S3 dedupe hides a distinct defect:** the dedupe only suppresses an
  S3 when the *same command line* already produced S1/S2 — the defect is still
  reported, once.
- **Dependency:** none beyond python3 + git, same as today.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
  It is filled above.
- The `--write-baseline` run must happen **after** the fixtures are green —
  regenerating early would bake un-fixed findings into the baseline.
- `lint-guard-contract.py` quantifies over EVERY `### Guard` entry — both
  entries above carry Property/Assembly/≥3 matrix rows.
- Do not widen the read anchor to bare `$?`-in-argument reads in this PR —
  the calibration is unmeasured; the Cut List records it as declined.

## References & Research

- Issue: #8784; deferral source PR #8738; original class #7332/PR #7336.
- Design source: `scripts/lint-workflow-errexit-capture.py` `scan_body()`
  (read-anchor, two-pass state, `is_protected`, `||`-idiom ordering —
  including the measured `before`-vs-whole-command false-positive story).
- Learning:
  `knowledge-base/project/learnings/logic-errors/2026-09-24-set-e-rc-capture-and-dollar-dollar-identity-traps.md`.
- Fixture-suite conventions (positive controls, anti-vacuity floor,
  `LINT_RC` non-substitution capture): `scripts/lint-shell-capture-exit.test.sh`
  header and `run_lint` comment.
- ADR-166 (lint-gate-earning precedent), via the gate's own docstring.
