# Verification record

## RED before the prose fix (commit 9df7938e32)

17b and 17c were GREEN on both blocks against the unchanged fences. The only failures were the 4 prose pins, which makes 17b/17c executable proof of the diagnosis: the delivered fence already resolves the root with the variable unset or pointing at a decoy.

## Guard Contract mutation battery (pristine-copy restore, verified per row)

| Row | Mutation | Result | Control (stays GREEN) |
|---|---|---|---|
| M1 | ship binding reads `$CLAUDE_PLUGIN_ROOT` | RED: 17b:ship, 17c:ship, 17-subst:ship | scenario 9 (2/2), 13c (4/4) |
| M2 | same in merge-pr mirror | RED: parity token, 17b/17c:merge-pr, 17-subst:merge-pr | ship rows, 9, 13c |
| M3 | ship binding prefixed `: "${CLAUDE_PLUGIN_ROOT:?}";` | RED: 17c:ship (and 13b:ship) | 17b:ship, 9, 13c |
| M4 | token unquoted in ship binding | RED: 17b:ship, 17c:ship, 17-subst:ship | 9 (unspaced root), 13c |
| M5 | ship notice loses its `using that path…` clause | RED: 17-prose:ship export pin | merge-pr pins |
| M6 | merge-pr pointer sentence deleted | RED: both 17-prose:merge-pr pins | ship pins |
| M7 | 17c:merge-pr call dropped | RED: MIN_VERDICTS floor (rc 1, 0 row FAILs) | — |
| H1 | substitution helper matches nothing | RED: 17-subst landing asserts, 17b/17c | 9, 13c |
| H2 | EVIL_ROOT emptied before 17b | RED: EVIL_ROOT guard aborts | — |

Fixture suite after fix: 420 pass, 0 fail (floor raised 380 → 420, the exact total).

## Other checks

- Both phase-7-poll-block fences byte-identical to origin/main.
- ship/SKILL.md +761 bytes (cap 800); `lint-skill-body-budget.py --base origin/main` OK.
- `plugin-root-anchoring.test.ts` 47/47; `plugin-root-anchor-debt.sh` anchor-debt-files=0.
- `harness-parity` + `components` bun tests 1449/0; markdownlint 0 issues; shellcheck clean.
- Ratchets run directly: fixture-relative-assert 62/0, fixture-dir-operand-assert 71/0, lint-shell-capture-exit (baseline), lint-trap-tempfile-ownership, lint-shell-trace-credential-refusal, guard-vacuity-floor — all rc 0.
- `test-all.sh --affected` was queued behind sibling worktrees' runs (ticket 26), so it was stopped. The substitute set above was chosen by shape; CI's full battery is the merge gate.
