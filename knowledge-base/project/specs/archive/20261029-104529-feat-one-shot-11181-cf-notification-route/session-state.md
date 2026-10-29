# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-11181-cf-notification-route/knowledge-base/project/plans/archive/20261029-104529-2026-10-28-fix-cloudflare-notifications-route-plan.md
- Status: complete

### Errors
- A targeted review-ledger patch missed the current session-state section; no edits landed. Re-read and anchored the ledger before the next section marker.
- Two targeted-round record patches failed verification against stale long/wrapped contexts; no edits landed. Re-read the current text and use short, file-specific anchors for follow-up.
- Web search returned HTTP 404; the official Cloudflare API reference was fetched directly and verified.
- An incidental read of nonexistent `knowledge-base/project/project-nope.md` returned not-found; no repository files changed.
- One test patch failed verification because its hunks were out of order; no edits landed from that call, and the patch was reapplied in file order.
- Two `scripts/test-all.sh --print-selection` attempts exceeded their 30s and 120s bounds; they emitted only the local Bun-version warning and yielded no selection or test verdict.
- During review, relative-path reads resolved against the main checkout and returned stale test content / missing untracked plan artifacts. On ship resumption, an initial relative-path read of the plan/spec files returned not-found; later, an absolute Read reported 568 lines for the test file while `wc -l` in the same worktree returned 763. Shell reads verified the current file; no edits were based on stale output.
- A later patch context was already superseded; its verification failure was investigated by re-reading the worktree, and no change was lost.
- Two follow-up patches for the learning/session records failed verification because the expected text did not match the current recovery wording; neither failed attempt changed files. Re-read the exact text and reapplied with the matching context.
- Status checks against the old `chore-learning-cf-token-route` worktree failed because it no longer existed. `gh pr view 11479` confirmed the PR had merged; the source blob was verified through `origin/main` instead.
- A first post-merge `gh pr view` jq filter omitted the dot before `headRefName` and failed; corrected the object selector and verified the merged state.
- The first `pipeline-tally.sh show` on the new follow-up branch reported a missing ledger; initialized the branch tally before continuing.
- The first pre-push secret scan ran before a commit and reported `range=0 scanned=0`. It did not cover pending edits; rerun after commit and require a non-empty range.
- The first deploy-arm lookup used `scripts/deploy-arm.sh` instead of `plugins/soleur/scripts/deploy-arm.sh`; the corrected plugin path found the release arm.
- Two Phase 7 poll windows reached their 90-minute bounds while #11456 remained queued; a later re-armed canonical poll observed the merge.
- A double-quoted `gh issue comment` body expanded backticks as command substitutions and stripped several inline-code phrases. Inspected the comment and corrected it using a quoted body file and `gh api --input`.
- One absolute file read used stale line bounds after test edits (tool reported 568 lines; `wc -l` returned 763). Re-anchored with a shell read from the exact worktree.
- One GraphQL queue query requested unsupported `MergeQueueEntry.headRefOid` and `baseRefOid` fields. Removed those fields; queue state was read with the supported position/state/enqueuedAt/PR-number selection.
- One `ci-head-verdict.sh wait-ready-run` call returned `no-ready-event` because the PR had already transitioned to ready; the canonical verdict command located the full run in progress.
- Review fixes were committed before the final-panel dedup ledger was persisted. Reconciled all findings and recorded the ledger below before starting the targeted round; no more fixes will be dispatched without a durable ledger.
- Several combined plan/tasks/session-state patches failed verification because an expected count line belonged to another file or a long archive-path context was stale; no edits landed. Re-read each target and split updates by file.

### Decisions
- Use the documented `/accounts/{account_id}/alerting/v3/policies` route without a pagination suffix.
- Preserve array-shaped 200 classification, fail-closed 404 handling, and existing profile routes.
- Include the specified learning byte-identically by its SHA-256; leave its source copy untouched.
- Keep the epic open, web-2 excluded at weight 0, and all permission, token, Doppler, infrastructure, and workflow state unchanged.

### Components Invoked
Skills: `one-shot`, `plan`, `deepen-plan`, `spec-templates`, `work`, `review`, `qa`, `compound`, `compound-capture`. Agents: `general` for planning/compound, full review panel and targeted fix-round seats; no work implementation agents. Planning used `Reviewed-Coverage: sequential-fallback`; work used Tier C sequential execution.

## Work Phase

- Implementation and focused checks complete; feature implementation commit `d5688394f9` is present on the branch.
- RED: the pre-change route failed the exact URL, baseline-retention, 404, degraded-200, and wrong-shape assertions (pre-change control: 137 passed / 26 failed).
- GREEN: `bash plugins/soleur/test/cf-token-scope.test.sh` passed 163/163; `bash -n` and `git diff --check` passed.
- `cf-token-scope.sh --profile default-token --dry-run` printed the documented URL with no query suffix and no token value; the test confirms no curl call occurs in dry-run.
- Learning copy hash and source hash both match `871e2785b041342a0c4e9180c39b01545e7883d7646e5d6117f686d6ccd9e250`.
- `lint-ratchet.py auto` exited 0; `user-ruff` is not adopted and was not updated.
- Affected-suite gate returned rc 6 (`AFFECTED_GATE_BUDGET_DEFERRED`, selected runner, CI workflow `.github/workflows/ci.yml`); it waited in the sibling-run lock queue and ran no suites. The first foreground invocation was reaped without a marker; the detached bounded rerun produced the rc 6 marker. Do not report a local affected-gate pass; the required CI `test` check is authoritative.
- The infra/workflow diff is empty. No Cloudflare permissions, token values, Doppler values, workflow dispatch, cutover state, or web-2 state were changed.

## Review Phase

- Panel snapshot: `4fe6a0f962f2d3dbdcd5c37b9b4ddb7837ac316a`; PR #11456, draft.
- Classification: code; risk tier `none` (source: plan); design-risk: no. Eight panel seats ran, plus the separate code-simplicity review. ShellCheck 0.11.0 passed; the pre-push secret scan was CLEAN for the panel SHA.
- Review coverage: git-history, pattern-recognition, architecture, security, code-quality, agent-native, test-design, and structural-enumeration seats all returned. No issue was filed; the PR-introduced exact-URL gap was fixed inline.
- Structural-cause roll-up: one route-exactness gap spans the mock dispatch, live URL assertion, and dry-run recipe assertion; five seats independently identified it.
- Review fix: Notifications mock dispatch now matches a path-ending full URL; D1 pins the exact dry-run recipe, D2 pins all six live URLs as whole lines, and D3m/D3w exercise both invalid Notification 200 shapes alongside both baseline LB 403s.
- The `/alerting/v3/policies/extra` scratch mutation was killed by D1/D2 (144 passed / 26 failed). The focused suite passed 170/170 after the review fix; ShellCheck passed.
- The test-design suggestion to pin Tunnel/Access live URLs was addressed by the six-URL D2 assertion; no outstanding review recommendation remains.

### Dedup-before-fixing ledger

| raw finding | canonical defect key | reporting seat(s) | planned fix commit |
|---|---|---|---|
| Substring URL assertions and broad mock dispatch accept a suffixed route; dry-run route lacks an exact terminal assertion | `notifications-url-exactness` | `pattern-recognition-specialist`, `code-quality-analyst`, `test-design-reviewer`, `code-simplicity-reviewer`, `structural-enumeration` | `review: pin exact Notifications URL (P2)` |
| URL-log/mock evidence captured only the last curl argument; dry-run line count did not count URL arguments | `complete-url-argument-observation` | `test-design-reviewer`, `structural-enumeration` | `review: close Cloudflare URL assertion blind spots` |
| A widened Notifications mock matcher was not directly exercised with a suffixed path | `notifications-mock-suffix-boundary` | `test-design-reviewer`, `structural-enumeration` | `review: close Cloudflare URL assertion blind spots` |
| URL observation missed non-HTTPS and `--url=` operands; empty-object response shape lacked a negative fixture | `scheme-independent-url-operands-and-empty-object-shape` | `test-design-reviewer`, `structural-enumeration` | `review: enumerate curl URL operands` |
| Proxy settings were logged as request URLs; task artifact retained a stale final test count | `proxy-value-as-request-url-and-stale-test-count` | `pattern-recognition-specialist`, `architecture-strategist`, `code-quality-analyst`, `agent-native-reviewer` | `review: separate transfer URLs from proxy settings` |

## Targeted Fix-Review Round 1

- Panel base: `4fe6a0f962f2d3dbdcd5c37b9b4ddb7837ac316a`; review head: `35afb1c4a154d28c3ada1211b8116d1ee326fa2f`.
- Six report-only seats returned: pattern-recognition, code-quality, test-design, code-simplicity, security, and structural-enumeration. Pattern, quality, and security reported no findings.
- Test-design and structural-enumeration identified incomplete test evidence: URL logging retained only the last URL argument, the dry-run count counted matching lines rather than URL occurrences, and matcher broadening was not directly driven. Those fixes landed in `fcc8647130` and were independently reviewed in targeted round 2.
- The code-simplicity suggestion to remove the five non-Notifications exact URL pins was not adopted: the full panel's test-design seat had specifically requested Tunnel/Access route pins, and the six-route assertion retains that requested coverage.
- The existing `cf-token-scope.test.sh` now passes 171/171. ShellCheck at warning severity passes. Full/style severity reports only SC2016 informational findings (baseline 6; current 4), so this fix adds none.
- Scratch mutations for a suffixed SUT route, broadened mock matcher, extra live `--url` argument, and extra dry-run URL were each killed; the clean scratch baseline passed 171/171.
- `scripts/test-all.sh --capacity` found two active sibling full-gate runs; no local affected gate was started. The earlier affected-gate result remains budget-deferred, not passed; required CI `test` remains authoritative.

## Targeted Fix-Review Round 2

- Panel base: `4fe6a0f962f2d3dbdcd5c37b9b4ddb7837ac316a`; review head: `fcc8647130eba0fa85b6b742061a7ea411187c81`.
- Test-design and structural-enumeration returned a P2: a `--url=http://...` operand was ignored by the HTTPS-only URL observer; structural enumeration reproduced the escape and noted the missing empty-object negative case. Security review independently confirmed the URL-operand bypass and found no live script, permission, token, or classifier change.
- The current fix parses positional, `--url`, and `--url=` operands regardless of scheme; pins the complete dry-run recipe; and adds an empty-object 200 rejection case. The focused suite passes 177/177; ShellCheck at warning severity passes.
- Scratch mutations for `--url=HTTP`, separated `--url HTTP`, `--proxy=HTTP`, an extra dry-run URL, and an empty-object-accepting classifier were each killed; the clean scratch baseline passed 177/177.
- Round 2 is the second and final targeted round. After committing and pushing this fix, run a full class panel over the cumulative fix range and exactly one verification pass; do not run a third targeted round.

## Full Class-Panel Escalation

- Cumulative fix range: `4fe6a0f962f2d3dbdcd5c37b9b4ddb7837ac316a..dfc47eeaa09c798c52c110e5373bb97ab9bea976`. Eight panel seats and the separate code-simplicity seat returned.
- Pattern-recognition, architecture, and code-quality independently reported that `--proxy=`/`--preproxy=` values were recorded and dispatched as transfer URLs; the agent-native seat found `tasks.md` still called 170/170 the final focused result. Security and code-simplicity reported no findings. Structural enumeration's other mapped paths were separate rulesets/non-Notifications recipe coverage, outside Guard 1's named Notifications property.
- Fix: ignore proxy-option values when recording transfer targets, add proxy-only fallback fixtures, reject proxy overrides in D-conf argv, and update the tasks artifact's final result. This changes tests/docs only; the production probe, token binding, and classifier remain unchanged.
- The single permitted verification pass found one P3 mismatch: plan row 8 named `--preproxy` and `-x`, while direct fixtures covered only `--proxy`. Added equals/separated `--proxy` and `--preproxy` cases plus separated/attached `-x` cases; no second verifier was spawned under the one-pass contract.
- Final focused suite: 183 passed, 0 failed; Bash syntax, warning-severity ShellCheck, and `git diff --check` pass. Scratch mutants for proxy-as-target, proxy override, and proxy-as-target with the real URL removed were killed; the `--preproxy` and `-x` parser mutants were killed too.

### Review-Execution Errors

- Initial scratch mutation setup omitted the adjacent skill docs; a subsequent setup selected a mutated copy as its baseline. Rebuilt complete scratch trees with a pristine baseline; no product files were changed by these attempts.
- A scratch-mutation anchor was stale and a status banner used `printf` with a leading `--`; both commands failed before touching repository files and were corrected.
- The first URL-parser run shifted the mock's positional parameters before D-conf captured argv (176 passed / 1 failed). Moved argv capture before parsing and reran the suite (177/177).
- Scratch mutation assertions expected outdated failure labels on multiple runs; inspection showed each mutant had been killed under the updated diagnostic, and the expected output anchors were corrected.
- One read attempted a nonexistent `project-nope.md` path and returned not-found; this was read-only and no files changed.
- The related-docs search first used the parent directory of a learning and was corrected to the actual `integration-issues/` path.
- The plan's initial `knowledge-base/INDEX.md` lookup returned not-found; a repository-scoped glob confirmed the index is absent in this worktree.
- The first frontmatter check parsed the unquoted ISO date as a YAML date object; the learning now quotes it to satisfy the schema's string type.

## QA Phase

- Plan scenarios are unit-level Given/When/Then cases with no executable `Browser:` or `API verify:` steps; per QA skill, browser/dev-server/API automation was skipped. The focused suite covers them and passed 183/183 on the current test code.
- Work Phase 2 and ship Phase 4 affected-gate attempts both returned rc 6 (`budget-deferred`); no affected-gate pass is claimed. CI's required `test` check is authoritative.
- Epic #11181 was rechecked as `OPEN`. Infra/workflow diff is empty; permissions, tokens, Doppler, infrastructure, cutover, and web-2 were not changed.

## Ship Phase 4

- `battery-owed.sh` returned OWED because `origin/main` is not an ancestor of HEAD. The local `affected-tests.sh` attempt returned rc 6 with `ran=- of=-`; no local affected suites completed.
- CI run 40841150757 on draft head `1b2f5a3302` had `test` aggregate FAILURE only because `test-scripts`, `test-webplat`, and `test-scripts-heavy` were skipped by draft-light; `test-bun`, `web-platform-build`, and e2e succeeded. Its log says `draft: full battery owed at ready`. This is not a code-test failure; wait for the full required `test` run after PR-ready.
- The `scripts/lint-betterstack-emitter-read.sh` suite emitted pre-existing gawk `\.` escape warnings; verified that script is unchanged from `origin/main`. `agent-originality` also emitted its existing WARN threshold for functional-discovery/agent-finder; neither is a test failure in this PR.
- PR body now intentionally closes duplicate route issue #11480 and references epic #11181 without a close keyword; both issue states were verified OPEN before merge.

## Ship Phase 0: Resumption

- The required `cleanup-merged` session-start run skipped its temp sweep because `/home/jean/.local/state/soleur/tmp-guard.lock` was contended. `lslocks` and `fuser` showed no holder by the time it was investigated; no temp cleanup was attempted outside the lock.
- Hash verification initially looked for the learning source at the old `/data/.../soleur/knowledge-base/` checkout path and returned not-found; a broad recursive search timed out. A registered-worktree inventory scan found the source in `chore-learning-cf-token-route`; PR #11479 later merged the same blob to `origin/main` (SHA-256 still matches the feature copy).
- The final-review security finding flagged account-specific operational detail in the learning. PR #11479 was already merged to public `main`; the user authorized redaction. This post-merge follow-up applies it after #11456, avoiding an add/add conflict on the stale feature branch and leaving published Git history intact.
- A PR-body update command was interrupted before execution because its shell payload contained NUL sentinels. Live PR re-read confirmed the body and labels were unchanged; retry with `--body-file`.
- The PR has no `Review-Evidence:` comment yet; arming requires evidence for the final pushed head after all fix commits and the targeted review/verifier.
- Ship Phase 6.45 merge-mode overlap preflight exited 13 for the known shared learning with PR #11479; no changes were made to that PR. The plan and spec are archived under `knowledge-base/project/plans/archive/20261029-104529-2026-10-28-fix-cloudflare-notifications-route-plan.md` and `knowledge-base/project/specs/archive/20261029-104529-feat-one-shot-11181-cf-notification-route/`; the live-path reference sweep found no remaining references outside archives.

## Final Review Resumption

- CI run 40875526334's `affected-index-ratchet` red was reproduced on a clean `origin/main` worktree (`stale-line`, 1513 live vs 1514 baseline). The job is advisory/non-required; existing issue #10861 tracks baseline deletion and #10448 tracks the wider S4 decision. No baseline, infra, or web-2 state was changed.
- Final-head panel at `20fe76bd0c5244e0399481eedadccf015bbda5d3`: eight seats returned. Findings: P2 proxy-selector coverage; P3 mixed proxy/target, query-suffix, HTTP-201, and duplicate-guidance gaps; P3 token-inventory detail was verified pre-existing on `origin/main` after #11479 merged.
- Fixed the test/design findings: mock and D-conf cover all supported curl proxy selectors, `--noproxy '*'` is exact, mixed-target and query-suffix controls exist, and 201 is denied. Removed duplicate sharp-edge guidance.
- Focused suite passed 200/200; `bash -n`, warning-severity ShellCheck, and `git diff --check` pass. No affected full-gate pass is claimed; capacity remains contended and CI's required `test` is authoritative.
- User authorized redaction of the pre-existing learning detail; this follow-up applies it after #11456 merged, avoiding an add/add conflict. No already-published commit history is rewritten.

## Post-Merge Verification and Redaction Follow-Up

- PR #11456 merged as `c5fd25cb4f430e12c7063e9e3315f5e37cd60ec7`. Main CI run `40918403358` passed.
- Deploy arm `40919197619` completed its deploy successfully; `deploy-arm.sh find` returned `MATCH=exact DEPLOY=success CI=success`, and `served` returned `CONTAINS BUILD_SHA=c5fd25cb4f430e12c7063e9e3315f5e37cd60ec7`. `/health` returned status `ok`, Supabase `connected`, and the same build SHA.
- Post-merge observability: no open `ci/inngest-down` issue; no Sentry or Better Stack read-only token was present in environment, so those vendor checks were skipped without accessing Doppler. No Sentry issue was identified for error-delta measurement.
- Live verification, browser verification, and sole-copy read-back were skipped because the PR changed no UI or triggering infra paths. KB archival read-back was clean: all added plan/spec artifacts were under `archive/`. Feature-tweet was ineligible because the PR is a fix.
- Closed duplicate #11480 and posted the post-merge verification result. The stale merge-queue alert #11537 was closed as a false positive after confirming #11456 remained queued at position 2 and merge-group run `40907797551` was in progress.
- The route learning had been byte-identical at the time #11456 merged. Per explicit user authorization, this follow-up redacts its account-specific operational detail while preserving the general credential-correlation lesson; the prior published commit history is unchanged.
- Compound session-error inventory and recurring/one-off triage were completed before editing. The test-failure learning now records the resumed ship/post-merge and follow-up tooling errors with prevention guidance; total Session Errors: 36.
- The pinned markdown-lint runner reported these knowledge-base files are excluded by `.markdownlintignore`; no markdownlint verdict is claimed. `git diff --check` passed. The current diff is documentation-only.

### Final-review dedup-before-fixing ledger

| raw finding | canonical defect key | reporting seat(s) | fix disposition |
|---|---|---|---|
| Curl proxy deny check and mock parser omitted valid selectors (`--proxy1.0`, SOCKS4/4a/5/5-hostname) and did not pin the `--noproxy` value | `curl-proxy-selector-parity` | `pattern-recognition-specialist`, `structural-enumeration` | `7c91fe2d1c` |
| Proxy-only fixtures did not prove a real transfer target remains the only logged URL beside a proxy operand | `proxy-selector-with-real-target` | `test-design-reviewer`, `structural-enumeration` | `7c91fe2d1c` |
| Direct mock boundary fixture rejected a path suffix but not a query suffix | `notifications-query-suffix-boundary` | `structural-enumeration` | `7c91fe2d1c` |
| No Notification 2xx fixture proved that a valid array on HTTP 201 remains denied | `notifications-non200-2xx-status` | `structural-enumeration` | `7c91fe2d1c` |
| Two identical curl-mock guidance bullets were present | `duplicate-curl-mock-guidance` | `git-history-analyzer`, `pattern-recognition-specialist`, `architecture-strategist`, `code-quality-analyst` | `7c91fe2d1c` |
| Account-specific operational detail in the learning is on public `main` via merged #11479 | `token-inventory-learning-disclosure` | `security-sentinel` | This authorized post-merge redaction follow-up; no history rewrite |

## Targeted Fix-Review Round 1

- At head `32b6d51c803bc8a5e3034862ea90e86aebd6871b`, 9 reviewer seats returned plus ShellCheck. The new findings were: exact `--noproxy` cardinality/value was not pinned (P2); clustered `-sSx` was not denied (P3); mixed-target fixtures covered only `--proxy` (P3).
- Fix commit under review: add exact option-token/value counts, reject any short-option cluster containing `x`, and test every proxy selector and operand form both alone and beside a real transfer target.
- The focused suite now passes 219/219; `bash -n`, warning-severity ShellCheck, and `git diff --check` pass. The capacity probe still reports sibling-run contention; no affected/full local gate is claimed.

### Targeted Round 1 Dedup Ledger

| raw finding | canonical defect key | reporting seat(s) | round-2 fix |
|---|---|---|---|
| `--noproxy` check counted matching lines and accepted duplicate or narrowed operands | `noproxy-option-cardinality-and-value` | `architecture-strategist`, `security-sentinel` | Count exact option tokens and exact `*` operands |
| D-conf did not reject clustered `-sSx` proxy syntax | `clustered-x-proxy-option` | `security-sentinel` | Reject short-option clusters containing `x` |
| Mixed-target fixtures covered only `--proxy` while docs claimed all selectors | `mixed-proxy-selector-target-coverage` | `pattern-recognition-specialist`, `architecture-strategist`, `security-sentinel`, `code-quality-analyst`, `test-design-reviewer`, `structural-enumeration` | Exercise every selector/form beside a real transfer target |

## Targeted Fix-Review Round 2

- At HEAD `f6e88ea782f73f656c7afde11aa0903c0407d4ff`, eight reviewer agents returned and ShellCheck passed. Findings: aggregate `--noproxy` counts could hide per-probe imbalance or `--noproxy=` overrides (P2); the short-option deny regex missed standalone/attached `-x` (P2); `tasks.md` described 200/200 without marking it as an earlier checkpoint (P3).
- Commit `3710d4f9c1` fixed the D-conf escapes; the single fresh-eyes verifier reviewed `f6e88ea782..3710d4f9c1` and returned no findings. Focused suite remains 219/219; the `Reviewed-Fix-Round` trailer and final-head PR comment are pending.
- Fixes are now applied locally: D-conf validates each argv record, requires one separated `--noproxy '*'`, rejects equals overrides, and catches standalone/attached/clustered `-x`. The task artifact labels 200/200 as an intermediate checkpoint and 219/219 as latest. Focused suite: 219/219; one fresh-eyes verifier remains.

### Round 2 Dedup-before-fixing ledger

| raw finding | canonical defect key | reporting seat(s) | fix commit |
|---|---|---|---|
| D-conf aggregates `--noproxy` and wildcard counts across probes and ignores the equals form | `dconf-proxy-policy-not-per-invocation` | `architecture-strategist`, `security-sentinel`, `test-design-reviewer`, `pattern-recognition-specialist`, `structural-enumeration` | `3710d4f9c1` |
| Short-option regex misses `-x`, `-x<proxy>`, and clusters with `x` | `dconf-short-x-proxy-deny` | `security-sentinel`, `pattern-recognition-specialist`, `structural-enumeration` | `3710d4f9c1` |
| Task artifact presents the 200/200 intermediate result as the final run | `final-test-count-currentness` | `test-design-reviewer` | `3710d4f9c1` |
- Fix `3710d4f9c1` validates `--noproxy` count/value separately on every curl argv record, rejects `--noproxy=`, and catches standalone, attached, and clustered `-x`. The fresh-eyes verifier at the same HEAD returned no findings; focused suite 219/219.

## Compound Phase

- Created `knowledge-base/project/learnings/test-failures/2026-10-29-curl-mock-confused-proxy-targets.md`; frontmatter enums/types validated and all 27 Session Errors have Prevention lines.
- Added one domain-scoped sharp-edge to `plugins/soleur/skills/work/references/work-test-harness-sharp-edges.md`; learning `synced_to: [work]` records the route. The related 2026-10-28 route learning and its main-checkout source copy remain byte-identical; the new learning links to it.
- No project-level constitution/component/README proposals were warranted. The worktree plan explicitly defers plan/spec archival until after ship Phase 6; compound did not archive them.
- Rule-budget linter returned `[WARN] B_ALWAYS=44390` and exit 0; no AGENTS rules were added. Token-efficiency report skipped because the diff was below its minimum size.
- The local rule-metrics aggregator warned that 77 malformed incident-log lines were excluded from the aggregate. Its source shows malformed rows are filtered during aggregation; rotation is opt-in and did not run. The metrics cache is not committed.
