# Tasks: Correct the Cloudflare Notifications probe route

## Phase 1: Setup

- [x] 1.1 Confirm the implementation scope stays limited to `cf-token-scope.sh`, its existing shell test, and the skill endpoint table; preserve the no-token-write/no-infrastructure/no-dispatch boundary.

## Phase 2: Core Implementation

- [x] 2.1 RED(unit): Extend `plugins/soleur/test/cf-token-scope.test.sh` first with exact Notifications URL dispatch, authorized array-shaped 200, Notification 404 fail-closed, degraded and wrong-shape 200 cases, and existing default-token/rulesets route regression cases; run it to establish RED before changing the script.
  - RED recorded: exit 1, 137 passed / 23 failed. New route/source/docs assertions fail, and the old route falls through the stub to an object-shaped response, causing dependent default-token checks to fail closed.
  - The additional Notification wrong-shape and degraded-200 assertions also fail against an isolated pre-change SUT (137 passed / 26 failed); both cases reach the new mock arm only on the corrected route.
- [x] 2.2 GREEN: Update the Notifications URL and displayed row label in `plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh` to `/accounts/$ACCT/alerting/v3/policies`, preserving the account-array row and `trust404=0` behavior. Blocked by 2.1 RED.
  - Initial GREEN verified: the focused shell suite passed 170/170 after the route correction and exact-route review fix; the classifier was unchanged. The final review-hardened suite result is recorded in Phase 3.
- [x] 2.3 Documentation: Update the Notifications route in `plugins/soleur/skills/cf-token-scope/SKILL.md` to match the official endpoint.
  - The route-table parity assertions pass and the old endpoint is absent from the profile documentation.
- [x] 2.4 Artifact: Copy `knowledge-base/project/learnings/2026-10-28-cf-token-retained-probe-used-nonexistent-notification-route.md` into the feature worktree byte-identically; verify SHA-256 `871e2785b041342a0c4e9180c39b01545e7883d7646e5d6117f686d6ccd9e250` and leave the source copy untouched.
  - Source and PR-copy hashes both equal `871e2785b041342a0c4e9180c39b01545e7883d7646e5d6117f686d6ccd9e250`.

## Phase 3: Testing

- [x] 3.1 Run `bash plugins/soleur/test/cf-token-scope.test.sh` and require zero failures, including the rulesets back-compat cases.
  - Initial focused checkpoint: 170 passed, 0 failed. Final review-hardened focused run: 183 passed, 0 failed.
- [x] 3.2 Verify the probe dry-run prints `alerting/v3/policies` and does not expose a token or make a request.
  - Dry-run prints the exact account Alerting URL without a pagination suffix; the test asserts no curl is issued and no token value is printed.
- [x] 3.3 Verify the feature diff is empty under `apps/web-platform/infra/` and `.github/workflows/`; confirm no permissions, token values, Doppler values, workflow dispatches, cutover state, or web-2 weight/structural-exclusion state changed.
  - The infra/workflow diff is empty; this session performed no Cloudflare permission/token/Doppler mutation, workflow dispatch, cutover action, or web-2 state change.
- [x] 3.4 Run the work Phase 2 affected-suite gate once and record its terminal status.
  - `AFFECTED_GATE` returned rc 6 (`budget-deferred`) after sibling-run lock contention; no local affected suites ran. The required CI `test` check remains authoritative.
- [x] 3.5 Re-run the ship Phase 4 affected gate on the committed final test tree.
  - `battery-owed.sh` returned OWED because main was not an ancestor; `affected-tests.sh` then returned rc 6 (`budget-deferred`, `ran=- of=-`). CI run 40841150757's draft-light aggregate failure was due to skipped shards, not a failing test; the full required `test` run after ready is authoritative.

## Review Fixes

- [x] 4.1 Fix the deduped P2 URL-exactness finding: path-end mock dispatch; exact dry-run Notification recipe; exact live URLs for all six default-token rows; include both baseline LB 403 rows in degraded/wrong-shape Notification cases.
  - Appended-route mutation `/alerting/v3/policies/extra` was killed by D1/D2; the first review-hardened suite passed 170/170.
- [x] 4.2 Fix targeted review findings: log actual URL operands across schemes, directly test suffix rejection, pin the full dry-run recipe, and reject empty-object Notification responses.
  - Scratch mutants for widened mock matching, extra HTTP/FTP `--url` operands, extra dry-run URLs, and empty-object authorization were killed; the focused suite passed 177/177 before full-panel hardening.
- [x] 4.3 Fix full-panel findings: distinguish transfer URLs from proxy settings and refresh the final test count in this task artifact.
  - Proxy-only equals/separated `--proxy`/`--preproxy` and short `-x` fixtures return the generic response without logging a request URL; D-conf rejects proxy overrides. Final focused suite passed 183/183.
