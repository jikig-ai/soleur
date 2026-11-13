# Red-first evidence: feat-one-shot-12683-n3b-census (#12683)

Each suite run below wrote its log under the worktree, with `RC` appended right after the run.

## Phase 0: baseline and replay on the base tree (green before the fix)

Base commit `755f86213c` (detached worktrees, each running its own suite copy).

| Run | Edit | Diff counts | N3 | N3b | Results | RC |
| --- | --- | --- | --- | --- | --- | --- |
| baseline | none | - | pass | pass | `=== Results: 286/286 passed, 0 failed ===` | 0 |
| R1 | ` https://attacker.example/` after `servers/123931471` in `rb_expected`'s body and in runbook 6604 | suite=1, runbook6604=1 | pass | pass | `=== Results: 286/286 passed, 0 failed ===` | 0 |
| R2 | the xh line inserted after R in runbook 6894's section-5c fence (line 416) | runbook6894=1 | pass | pass | `=== Results: 286/286 passed, 0 failed ===` | 0 |

The R2 line, with the issue's `...` filled in from `RB_WRAP`'s Doppler flags:

```text
doppler run -p soleur -c prd_terraform --only-secrets HCLOUD_TOKEN_READONLY --no-exit-on-missing-only-secrets -- sh -c 'xh -A bearer -a "$HCLOUD_TOKEN_READONLY" "$U"'
```

## Phase 1: pure extraction

`=== Results: 286/286 passed, 0 failed ===`, RC=0.

## Phase 2: new H18 rows without the fix (red)

`=== Results: 285/286 passed, 1 failed ===`, RC=1. The one FAIL line, verbatim:

```text
  FAIL: H18 N3b / N1 self-test: uncaught:gVr1(none) uncaught:gVr2(none) uncaught:gVr4(none) uncaught:gVr5(none) uncaught:gVr6(none) uncaught:gVr11(none) uncaught:gVr12(none) uncaught:gVr13(none) uncaught:hj(none) fs-v4-unquoted(did-not-land) fs-v3-id(did-not-land) fs-v2-url(did-not-land) uncaught:g5r1 uncaught:g5r2 uncaught:g5r3 uncaught:g5r4 uncaught:g5r5 uncaught:g5r6 uncaught:g5r8 uncaught:hb-wpin='' uncaught:hb-wpin='106903269' uncaught:hb-wpin='106261946'
```

Every pre-existing row stays caught, every instrument control stays quiet, `H18_RUN` equals `H18_ROWS` (55), the must-PASS
rows `hi` and `g5s1` stay silent, and `fs-r-unquoted` is already caught (R has a heredoc before the fix).
