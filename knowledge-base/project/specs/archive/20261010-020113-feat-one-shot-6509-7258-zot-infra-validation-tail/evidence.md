# Phase 2 evidence (#6509 fixture, F23a-F23e)

Measured 2026-10-10 on scratch copies; local terraform 1.9.8 (CI pins 1.10.5), `cloud-init` shimmed to a no-op so the
render arms run (the real schema step of F23a is CI-authoritative). The four shim-caused local reds
(F1-precondition, F2, F3, F7) all need real schema validation and are green in CI.

## Full sweeps (validator, real pair copied to an empty root)

| Mutation on the copy | n | Result |
|---|---|---|
| baseline | 1 | rc 0, `rendered+validated 1/1 file` |
| drop one template-referenced var's `.tf` map key | 16 | 16/16 rc 2, quoted key named |
| un-double one `$${TOKEN` | 28 | 28/28 rc 2 |
| un-double `%%{http_code}` | 1 | rc 2 |
| add `${undeclared_var}` | 1 | rc 2, `"undeclared_var"` named |
| remove `zot-registry.tf` | 1 | rc 4 |
| add an unused map key (must-PASS) | 1 | rc 0 |

## Edits that must redden the suite (control: 0 F23 failures)

| # | Edit | F23 arms that reddened |
|---|---|---|
| 1 | SUT: filter the registry template out of discovery | 17 (named-ok, counted, every drop/undouble arm) |
| 2 | SUT: derive keys from the template body, not the `.tf` map | 9 (all F23b) |
| 3 | SUT: render failure no longer takes the render-failure branch | 15 (rc 3 and missing message, F23b/c/d) |
| 4 | Suite: `reg_root` copies only the template | 19 (F23a rc 4 onward) |
| 5 | Harness: `terraform` shimmed to exit 0, empty output | 19 (F23a rc 3 onward) |

Restore check: pristine copies byte-identical after the battery. Axes NOT edited: assertion-helper dispatch (ok/bad),
anti-vacuity floor (the suite has none, same as F1-F22), derivation of the populations (a template whose var list
collapses is caught by `F23-populations-derived`, not mutation-tested here).

## Ratchets

`fixture-relative-assert` green with the baseline UNCHANGED (58 sites for this file): the plan expected a regeneration,
but routing the copy through python and binding the root under `$TMP` kept the row identical, which is the ratchet's
preferred outcome. `fixture-dir-operand-assert` green; `lint-shell-capture-exit` 0 new findings; shellcheck at
warning level clean (one pre-existing SC2016 info on the F19c printf).

## Review round (post-F23, 3 seats)

Floor proof: deleting the whole F23 block on a sandbox copy reports `[FATAL] anti-vacuity floor: only 47 assertions ran, expected >= 68` (exit 1); the control run is 64 pass / 4 shim reds = 68. `guard-vacuity-floor.test.sh` 23/23, `fixture-relative-assert` 62/62 (row unchanged), shellcheck warning level clean. Reviewer-run sweeps: 18/18 dropped keys (the 16 template vars plus `zot_asset_sha256`, `doppler_sha256`) and 28/28 un-doubled tokens, 0 survivors.

