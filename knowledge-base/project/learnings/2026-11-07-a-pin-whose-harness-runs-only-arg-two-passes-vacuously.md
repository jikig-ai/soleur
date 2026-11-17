---
title: "A pin whose harness runs only `$2` passes vacuously — and nested bash -c quoting hides inside the vacuous pass"
date: 2026-11-07
status: active
category: testing
tags: [guard-shaped-pr, vacuous-assertion, test-harness, review-fix-round]
related: [10859, 12329]
---

## The defect

Review found `oracle-review-required`'s job `if:` unpinned (structural-enumeration P1). The fix added five `chk "label" bash -c 'grep … <<<"$_wf"'` pins to `scripts/ci-oracle-review.test.sh`. Every one passed — and evaluated **nothing**: that suite's `chk` was the two-arg contract `chk <label> <fn>` running `"$fn"` only, so `chk label bash -c prog` executed bare `bash` (stdin EOF, exit 0, pass). The subsequent fix round caught it — a green suite where the fix's central deliverable did not execute.

Two independent defects stacked: (a) the harness contract made multi-word predicates silently vacuous; (b) once `chk` was made variadic, the nested `\\\\|` escaping I had written for `grep -E` collapsed to a literal backslash + alternator — so even correctly-invoked, the pin's pattern could never match. Either defect alone kept the suite green.

## The rule

- A `chk`/assert helper that runs `"$2"` accepts `bash -c prog` call sites that LOOK exercised and are not. Make test-harness predicates take the whole argv (`shift; "$@"`) or write row functions — never pass interpreters as arguments to a two-arg contract.
- Mutate-probe every new pin: delete the thing it pins and watch it go red. The fix-round seat did this and instantly found all five vacuous pins.
- Nested `bash -c "…grep -qE \"\\\\|\\\\|\"…"` quoting is unauditable at sight. Pass patterns through helper functions (`_wf_has "literal"`) or `grep -qF` fixed strings — if a pin needs more than one level of escaping, restructure it instead.
- The same class earlier in the session: a same-line grep `grep path | grep -q 'AFFECTED_.*_PATHS='` could never fire on multi-line array blocks, and an awk `{f=1;next}` skipped decl-line elements (a live decl+first-element instance existed). Three vacuous-guard instances in one PR, all in "new" assertion code written for the fix itself — review fixes are the least-audited surface; the fix-round is what caught them.

## Evidence

PR #12329 fix commits `46ea4d9d69` (pins added — vacuous), `87a3af2614` (variadic chk + helper restructure — pins fire, verified by mutation-probe), `8904206ade` (decl-line extraction + `-s` floor).
