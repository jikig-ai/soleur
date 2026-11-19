# By-hand mutation record (#12849, plan G5)

Each mutation was applied once to a pristine copy, the suites were run, and the copy was restored.
Committed mutation rows (G1-10, G1-11a/b/c, G3-1a/b, G3-2, G3-3a/b, G3-4, G3-4b1-4, G3-4c/d/e, G3-5/5b,
G4-3/3b) live in `lb-weight-gate.test.sh` and run on every suite run.

| Mutation | Row(s) that went RED |
|---|---|
| G1-1 workspaces floor line deleted | `WORKSPACES_LUKS_SOAK_DAYS=1 (4-day markers) refuses ..._below_floor` |
| G1-2 git-data floor line deleted | `GIT_DATA_LUKS_SOAK_DAYS=1 (4-day markers) refuses B_luks_soak_days_below_floor` |
| G1-3 `SOAK_FLOOR_DAYS=1` | rows for 1 and 2, `F8/G8 parity` |
| G1-4 `-gt` for `-ge` | `...=3 with 4-day markers passes`, both kinds |
| G1-5 floor check before the regex | `WORKSPACES_LUKS_SOAK_DAYS='0' refuses ..._invalid` |
| G1-6 default `:-1` | `unset with a 2-day marker refuses ..._not_elapsed` |
| G1-7 regex `^[0-9]+$` | `'010' refuses B_luks_soak_days_invalid` |
| G1-8 regex `^[1-9][0-9]*$` | `'1000'`, `'200000000000000'` refuse `..._invalid` |
| G1-9 `: "${SOAK_FLOOR_DAYS:=3}"` | with-marker `scn_allow_parity` |
| G1-12 floor loop never runs | section row-count guard; `MIN_CASES` floor |
| G2-1 `fail()` emits only for git_data | every workspaces refusal evidence row |
| G2-2 workspaces pass emit deleted | `G2: full pass prints exactly two evidence lines` |
| G2-3a `EV_KIND` not cleared after B.10 | SURVIVED, equivalent: nothing after B.10 calls `fail()` or emits |
| G2-3b `EV_KIND=git_data` at init | Condition A / B.1 / TOP "ZERO evidence lines" rows |
| G2-4 `verdict=pass` on the fail path | every refusal `verdict=fail` row |
| G2-5 workspaces `age_s` from the git-data marker | `per-kind age` row |
| G2-6 `source=env` always | the `source=default` rows |
| G2-7 raw marker text printed | the `+02:00` rebuild row, the space-separator row |
| G2-8 raw soak value printed | `'1 verdict=pass': exactly one verdict= token` |
| G2-9 `source=` optional in `SOAK_EV_RE` | G4 negative fixture (missing field) |
| G3-4c composite refuse branch returns 0 | `sse_gate_chain_check with rc=1 returns 1` |
| G3-6 rc 2 mapped to 0 | `grader rc 2 -> return 1`, G12 rows |
| G3-7 rc 78 passes | `grader rc 78 -> return 1` |
| G3-8 `SOLEUR_FT_EARLIEST=` dropped | ambient `SOLEUR_FT_EARLIEST` row, G10 env set |
| G3-9 `env -i` dropped | G10 env set, decoy-value row |
| G3-10 return 0 before calling the grader | `grader rc 0 -> stub called exactly once` |
| G4-4 anti-vacuity checks only git_data | `a pass with no workspaces_luks line refuses` |
| G4-5a floor check removed from the re-check | `a pass line with required_s=86400 refuses` |
| G4-5b re-check accepts `none` | `a pass line with none fields refuses` |
| G4-6 host not compared | `pass lines for a different host refuse` |
| G4-7 mirror grep unguarded | zero-line Condition A refusal row, wrapper id `none` row |
| G4-8 summary evidence write skipped when non-empty | pass fence, refusal fence, F11 rows |
| A1 `EV_KIND` init deleted | absent `SOLEUR_GATED_HOST` rows, TOP refusal row |

## Review round (2026-11-19, PR #12934 panel)

The panel's test-design seat ran its own battery against f5ce2fa8bd and found mutants that left the suites green; each is now a committed row or an executed row (all RED against its mutant, measured in `lb-weight-gate.test.sh` 643/643 on the fixed tree):

| Mutant | Now caught by |
|---|---|
| `srow` reports PASS for `0` (with the workspaces floor deleted: 613/0 before) | `§SK instrument` row, graded outside `srow` (re-run in a sandbox: 642/1, the instrument row RED) |
| `set +o errexit` + `exit 0` in the grader step | exact-body allowlist in `sk_grader_ok` (committed mutant) |
| `set +o errexit` before the gate step's re-check | `sk_gate_ok` errexit-escape refusal (committed mutant) |
| `if: always()` on Terraform apply | `sk_downstream_if_ok` (committed mutant) |
| `trap 'exit 0' ERR` before `sse_instance_soak`; a second trap / `shell:` on the gate step | R7 rows (committed mutants) |
| inner env without `-u BASH_ENV -u ENV` | R4 rows here and in `workspaces-luks-verify-workflow.test.sh` (committed mutants) |
| rc 0 with empty or non-PASS text; rc 3 with a `PASS:` line | R1 executed rows |
| `has_gate_fail` / `ski_line_ok` always true | negative rows |

## Fix round (2026-11-19, range f5ce2fa8bd..68ec375482 + fixes)

| Mutant (fix-round seat) | Now caught by |
|---|---|
| `exit "0"` / `exit 00` after `set -euo pipefail` in the gate step | exact-body snapshot in `sk_gate_ok` (committed mutant) |
| `- if: always()` as the apply step's first key | `sk_downstream_if_ok` reads both spellings (committed mutant) |
| inner env / health shell without `-u SHELLOPTS -u BASHOPTS -u PS4` | R4-class rows (two committed mutants) |
| helper knob renamed from the grader's `W2L_REQUIRE_BOOT_JOIN` | R2 parity row |
| probe prints two lines of one kind; first instance line shown; gate_fail-only run passed over | probe rows (per kind, last wins, gate_fail hit) |
