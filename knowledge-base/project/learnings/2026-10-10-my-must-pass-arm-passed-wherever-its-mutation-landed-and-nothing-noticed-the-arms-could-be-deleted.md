# Learning: a must-PASS arm that passes wherever its mutation lands, and a suite whose arms can all be deleted

## Problem

#6509 asked for the registry cloud-init template to be rendered by the infra-validation gate. Premise
checking showed the validator already discovered and rendered it (keys derived from the `.tf` call
site), so the PR added only a regression fixture: arms F23a-F23e in
`.github/scripts/test/fixtures-validate-infra-templates.sh`, which copy the REAL
`cloud-init-registry.yml` + `zot-registry.tf` into a mktemp root, mutate the copy, and run the real
gate. The author's own 5-row battery killed every row. A three-seat review then found, on axes the
battery never edited:

- **No anti-vacuity floor.** Deleting the whole F23 block left the FAIL set identical to the control
  (PASS 63 to 43), so with real `cloud-init` in CI the suite exited 0 having asserted nothing.
- **The must-PASS arm (F23e, "an unused extra map key is tolerated") passed wherever the key landed.**
  Appending the key at EOF of the `.tf`, or as a comment line, also returned rc 0, so the arm could
  not distinguish "tolerated inside the map" from "never reached the map". The no-op guard only proves
  the file changed, not where.
- **The real call site's `replace(...)` render strip was unpinned** (the one fixture shape that
  carries it is exactly the real pair), so skipping the strip left every F23 arm green.

## Solution

- Floor: `MIN_ASSERTIONS=68`, literal directly above the `if`, reported by `printf` + `exit 1`
  (never through `bad()`), accepted by `scripts/guard-vacuity-floor.test.sh`. Verified by deleting the
  F23 block on a sandbox copy: `only 47 assertions ran, expected >= 68`, exit 1.
- The extra-key mutation writes only when the call line ends with the map's opening `{`; otherwise it
  leaves the copy untouched so the existing no-op guard names the failure.
- `F23a-render-strip-applied` pins the strip message the validator already prints.
- The fixture-relative-assert baseline stayed unchanged: the plan expected a regeneration, but doing
  the copy through python and binding the root under `$TMP` kept the row at 58 sites.

## Key Insight

"The mutation landed" and "the mutation landed where the property lives" are different assertions.
A byte-changed copy satisfies the first; a must-PASS arm needs the second, because an arm that passes
for every placement certifies nothing and reads as the control that makes the reds meaningful. Same
family as the floor rule: any arm whose deletion leaves the suite exit 0 is documentation.

## Session Errors

1. **Plan expected a baseline regeneration; implementation avoided it** — Recovery: python copy + root bound under `$TMP` — Prevention: when a plan says "expect to regenerate a ratchet baseline", first try to keep the row identical; the ratchet's preferred outcome is the code change, not the baseline edit.
2. **A new `cp` with a call-derived source operand moved the P1b ratchet 58 to 59** — Recovery: moved the copy into the python helper — Prevention: run `fixture-relative-assert.test.sh` right after adding any write/copy to a tracked fixture, before the first commit.
3. **Extra-key must-PASS arm passed vacuously** — Recovery: landing-region check in the helper — Prevention: for every must-PASS "tolerated" arm, name a placement that satisfies it while the key never reaches the construct under test.
4. **No floor on a fixture suite that gains an arm block** — Recovery: floor + sandbox deletion proof — Prevention: add the floor in the same commit as the first new arm block, and prove it fires by deleting the block.
5. **`git stash list` blocked by the stash hook** — Recovery: none needed — Prevention: use `git rev-parse --verify --quiet refs/stash` (already in work Phase 0.5); one-off.
6. **My own plan-edit script asserted a tight text offset and aborted before writing** — Recovery: loosened the offset and re-ran — Prevention: after any scripted edit, `git status --short <file>` or read the line back; a raised assert leaves the tree untouched and the next measurement is the baseline.
7. **Local no-op `cloud-init` shim produced four expected reds (F1, F2, F3, F7)** — Recovery: recorded as shim-caused in evidence.md — Prevention: when a suite needs a tool absent locally, state the expected-red set in the evidence file so a later reader does not read them as regressions.

## Tags
category: test-failures
module: infra-validation
