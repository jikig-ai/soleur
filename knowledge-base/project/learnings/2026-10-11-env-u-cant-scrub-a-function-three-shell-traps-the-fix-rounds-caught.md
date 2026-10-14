# Learning: `env -u` cannot scrub a shell function, `grep -q` loses to pipefail's SIGPIPE, and a `$'\x00'` class scrubs nothing — three shell traps the fix rounds caught in my own fixes

## Problem

#9956: the infra-privileged tier census's G4c guard diffed a PR against the moving
`origin/main` tip, so six resource blocks #9529 *added* on main read as orphans the PR
deleted. The fix itself (resolve `git merge-base HEAD refs/remotes/origin/main`, verbatim
`IPT_BASE_REF`, fail-closed tip fallback) was small and the design pass approved it. The
yield of the review was not in that design — it was in the three shells traps that lived in
the fix code and in my review-driven fixes, each caught at a different layer:

1. `env -u IPT_BASE_REF resolve_base_ref` returned rc 127 — `env` execs binaries, it cannot
   invoke a bash FUNCTION, so the scrub silently produced `ref=""` → `dest=""` → every
   fixture leg went 'base unavailable'. The suite caught it red, not green, only because
   the empty-ref path was already fail-closed.
2. A probe rewritten as `producer | grep -qE` failed on a REAL match: `grep -q` exits after
   its first hit, the upstream `grep -vE` died of SIGPIPE, and under `set -o pipefail` the
   pipeline reported 141. The failure was invisible until the probe actually ran.
3. `${var//[$'\x00-\x1f\x7f']/?}` — a "sanitization" a review seat had *recommended* — was a
   complete no-op. `$'\x00'` cannot embed a NUL in a bash word, so the class expanded to the
   literal `[]`, which matches nothing. A forged `FAIL <row>` splice survived it verbatim.
   Verified live with a `\n`-bearing ref: `[[:cntrl:]]` collapses it, the C0 class does not.
4. A `root=` diagnostic I added to name the failing root named the WRONG root for half the
   failure space: `show`/`floor` set the rc flag without `break`, so the `for` loop rebound
   `_r` to the second root before the top-of-loop check fired — a root-1 failure blamed
   root 2. Four separate seats derived the same trace.

## Solution

- Scrub env state for a function call with `unset` inside the command substitution —
  `x="$(unset VAR; fn)"`. `env -u` remains correct for the `GIT_DIR`/`GIT_INDEX_FILE`
  convention precisely because the callee there is the `git` binary.
- Never feed `grep -q` (or `head`) a pipeline under pipefail when the rc matters: capture
  the producer in `$( )` first, then `grep -qE <<<"$x"`. The early-exit consumer closes the
  pipe, the producer dies 141, and pipefail propagates the wrong verdict.
- Scrub control bytes with `[[:cntrl:]]` (+ `$'\u2028\u2029'` for renderer-level line
  separators). Any `\x00` inside a glob class is a dead pattern — a lintable shape.
- A flag-set-and-check-later loop attribute must snapshot the attribution variable AT the
  set site (`_wr="$_r"`) or break immediately — a `for` rebinding between set and read is
  the same race a signal handler would create.
- Every new failure arm needs a leg that DRIVES it, including arms added by review fixes:
  the per-root floor added in fix round 1 had no driver until the coverage consult named
  the missing leg (b9), and the marker it emitted had no assertion until a seat asked for
  the anchored grep.
- A fix made under review is new code with the same defect rate as the original diff —
  cap-2 rounds exist because of it, and the two P2s this PR's round 2 found (the dead
  scrub, the mis-attributing marker) were in lines written to satisfy round 1.

## Key Insight

The recurring shape across all three traps is *a construct that looks like it composes but
doesn't*: `env -u` + function, `grep -q` + pipefail, `\x00` + glob class, flag-set +
loop-rebind. Each is individually known; each slipped through because the surrounding code
was already reviewed-green and the new line read idiomatic. The antidote the process
provided was mechanical, not judgment: fail-closed plumbing so the wrong answer is always
RED (the env -u bug went red rather than green *because* `dest=""` was already the failure
path), per-arm driving legs, and a verifier pass over the fix diff itself. When you write a
sanitization, run the payload through it once — the $'\x00' scrub survived a seat's
recommendation and my implementation because nobody pasted a newline into it.

## Session Errors

1. **`env -u IPT_BASE_REF resolve_base_ref` rc 127 — env cannot exec a shell function.**
   Recovery: `unset` inside `$( )`; comment records why. **Prevention:** when the callee is
   a function, reach for `unset` inside the substitution, never `env -u`; test the scrub on
   a leg that would fail loudly if the var leaked.
2. **`grep -vE | grep -qE` under pipefail: upstream SIGPIPE → probe FAILed on a real match.**
   Recovery: `$( )`-capture + `grep -qE <<<"$x"`. **Prevention:** any `producer | grep -q`
   whose rc gates a verdict is a suspect under `set -o pipefail`; buffer the producer.
3. **`$'\x00-\x1f\x7f'` glob class expanded to `[]` — the scrub matched nothing.**
   Recovery: `[[:cntrl:]$'\u2028\u2029']`, measured live with a `\n`-bearing ref.
   **Prevention:** run the payload through the sanitizer once; `\x00` cannot live in a bash
   word so any class containing it is dead.
4. **`git rm` of a dir's last file removes the dir; the next `printf >` failed.** Recovery:
   `mkdir -p` before the write. **Prevention:** when a fixture step deletes a file whose
   dir the next line writes into, `mkdir -p` is not optional.
5. **`IPT_BASE_REF=x func` would persist into later legs — env-prefix on a function.**
   Caught in implementation; subshell/`$( )` containment applied. **Prevention:** env-prefix
   scoping is only subshell-safe for binaries; for functions use `( VAR=x; fn )` or `unset`.
6. **Materialize `root=` blamed the wrong root (for-loop rebinding between set and read).**
   Recovery: trailing `[ "$_rc" -eq 0 ] || break` inside the for-loop. **Prevention:** a
   diagnostic read of a loop variable must be taken inside the iteration that set it.
7. **Fixture-scan ratchet tripped on three new unasserted operand sites.** Resolved by
   adding `assert_fixture_dir` to all three helpers. **Prevention:** the operand/relative
   scans run on every new `git -C`/redirect site in fixture code — assert first.
8. **`VAR=x func` persistence trap repeated in b6's first spelling; probe regex missed
   `$1` (a digit operand); SC2155 combined decl+assign; markdownlint MD022/MD032.**
   All caught and fixed in-flight. **Prevention:** covered by the existing checks that
   caught them (fixture-scan, probe self-test, shellcheck, markdownlint).

## Prevention / Process Notes

- Deviation analyst: no hard-rule violations observed; every error above was caught by an
  existing check or a review seat. The recurring-vs-one-off split: items 1–3 and 5–6 are
  recurring bash classes documented above; 4, 7, 8 are one-offs already gated.
- Null-guardrail check: a lint for `\$'\\x00` inside a `[` glob class is feasible and would
  have caught #3 statically — candidate rule if the shape recurs; not wired here (single
  occurrence, learning captures the class).
- Cross-references: #9956 (issue), #10053 (this PR), #8904 (prior false-red), #7849
  (fixture-env chokepoint), ADR-282 (merge-base semantics), the fix-round cap contract in
  `plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md`.
