# Mutation battery — #4781 (Guard 1)

Harness: trimmed copy of `tests/scripts/test-sentry-alert-live-fidelity.sh` running rows
F1, F13, F10, F22, G4-6, F35, F36. The probe is mutated in place and restored with
`git checkout` after each row; the md5 of the restored probe is checked against HEAD.

| # | red rows | note |
|---|---|---|
| M0 (unmutated control) | none, rc=0 | baseline valid |
| M1 frozen arm removed | F35 | |
| M1b frozen arm → silent drop | F35 | |
| M1c frozen predicate always true | F10, F22, F36 | |
| M2 backticks un-escaped | F10, F22, F36 | F36 via the bash-error guard |
| M2b M2 + F10's `def excluded` check deleted | F10, F22, F36 | the guard alone reds F10 |
| M3 no UNMANAGED lines emitted | F10, F22, F36 | plan predicted F35 as collateral; it correctly stays green (it asserts only the ABSENCE of UNMANAGED for frozen names) |
| M4 F35 dropped from the call list | harness count (`ran 6, expected 7`) | |
| M5 frozen arm applied to the first frozen name only | F35 | |
| M6 classifier moved above the frozen-name derivation | every row (F1, F13, F10, F22, G4-6, F35, F36) | `set -u` abort (`frozen_names_json: unbound variable`), caught by the bash-error guard |
| M7 revert to the bash `keys[] \| read` loop without `safe` | F36 | a `::error::spoofed` line, a fragment impersonating the frozen rule, and no scrubbed whole-name line |
| M8 `safe` dropped from the jq classifier (whole-key match kept) | F36 | [no scrubbed whole-name UNMANAGED line] |
| H1 (suite edit) F35 selector pointed at a non-existent name | F35 | `_mutant` reports NOOP |

H2: F1, F13 and G4-6 stayed green on the unmutated tree (M0) and in the full run (69/0).
No surviving mutants. Axes NOT exercised: bidi/zero-width characters in names (deferred), a refusal before the verdict (accepted trade, see plan Sharp Edges).

H1b (plan-predicted "guard keeps matching without LC_ALL=C") is FALSE: bash translates the `line N:` prefix (measured at review under LANGUAGE=de/fr), so `LC_ALL=C` is load-bearing.

## Round 2 — guards added during review (trimmed harness, 13 rows + both self-tests)

| # | red rows |
|---|---|
| C0 (unmutated control) | none, rc=0 |
| bidi ranges removed from `SAFE_JQ` | F41 |
| FROZEN ID MISMATCH arm disabled | F42 |
| LEFT printed via printf (not counted as a finding) | F37 |
| backticks un-escaped | F10, F22, F36, F38, F41 (all but F10 through the central bash-error guard) |
| `$k \| safe` dropped in DRIFT detail | F43 (after widening its check to indented lines; first run SURVIVED) |
| display-altered flag disabled | F38, F41 |
| live id dropped from UNMANAGED | F10, F38, F41 |
| frozen-derivation parity check disabled | F40 |
| central guard disabled + backticks un-escaped | F10 only (the guard is what reds the other four) |
| `BASH_ERR_RE` typo | suite FATAL rc=2 (guard self-test) |
