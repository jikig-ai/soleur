---
title: "fix: Use Cloudflare's documented Notifications endpoint"
type: fix
date: 2026-10-28
slug: fix-cloudflare-notifications-route
branch: feat-one-shot-11181-cf-notification-route
issue: 11181
closes: 11480
priority: p2-medium
domain: engineering
brand_survival_threshold: none
lane: single-domain
---

## Enhancement Summary

**Deepened on:** 2026-10-28
**Sections enhanced:** Research Insights, Implementation Phases, Guard Contract, Observability, Scope Check, Domain Review, Test Scenarios, Acceptance Criteria
**Research agents used:** None — OpenCode nesting depth is one; research and review were completed sequentially inline.
**Reviewed-Coverage:** sequential-fallback

### Key Improvements

1. Grounded the route and response shape in Cloudflare's official API reference and kept the existing fail-closed classifier as the only decision path.
2. Added exact URL-dispatch, authorized 200, 404, degraded-200, and existing-profile route regression scenarios.
3. Pinned the token/infra/cutover boundary and the byte-identical learning-file inclusion with its supplied digest.

### New Considerations Discovered

- Cloudflare's reference does not list a pagination query parameter for this operation; use the documented path without `?per_page=1`.
- The test's curl mock must move with the `DT_ROWS` route, or the fixture can continue to model the nonexistent path instead of the real dispatch.

# fix: Use Cloudflare's documented Notifications endpoint

## Overview

Correct the `cf-token-scope` default-token Notifications probe to use Cloudflare's documented Alerting API route and pin dispatch, successful response classification, fail-closed 404 handling, and unchanged sibling routes in the shell test suite. This is a focused follow-up on the non-cutover track; no Cloudflare permissions, tokens, Doppler values, or infrastructure are changed.

## Non-Goals

- No widening or other mutation of Cloudflare permissions or tokens; no Doppler write, infrastructure change, or workflow dispatch.
- No cutover action or web-2 LB change is authorized. No soak-gated close criterion is introduced by this fix; web-2 remains at weight 0 and structurally excluded until the existing cutover soak marker.
- No classifier relaxation, new profile, or unrelated route/permission coverage expansion.
- Do not close epic #11181: reference it as `Ref #11181` and leave it open while the operator hold and unanswered AC4 remain unchanged. Close only the duplicate route issue #11480 in this corrective PR.

## Artifact Lifecycle

- **Archival deferral:** Defer compound's pre-ship archival of this plan and spec directory until after `soleur:ship` Phase 6 has completed its live-path reads. Ship's Phase 6.45 archive step is the approved in-PR archival point; compound must not archive these artifacts before it.

## User-Brand Impact

- **If this lands broken, the user experiences:** a false-negative retained-scope baseline that blocks the Cloudflare LB follow-up from establishing whether Notifications remains authorized; web-2 remains excluded and at weight 0.
- **If this leaks, the user's workflow is exposed via:** the existing `CF_API_TOKEN` Authorization header used by the read-only probe. The fix preserves the private-fd header path and does not print or persist the bearer value or response body.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the change corrects a read-only URL and test fixture; the worst outcome is a failed probe and continued hold, not a user-data, production-write, or permission exposure.
- **Scope-out override:** `threshold: none, reason: this change does not alter credential handling or user-data processing; a regression fails the probe closed and keeps the cutover held.`

## Research Insights

### Premise Validation

- `gh issue view 11181 --json state,title,closedByPullRequestsReferences` confirmed epic #11181 is OPEN with no closing PR references. The issue body identifies this as the non-cutover track and says web-2 remains structurally absent / weight 0 until the existing cutover marker; this plan does not create a soak-gated close criterion.
- The user-provided latest epic status remains the planning premise: the `CF_API_TOKEN` widen is still on operator hold, AC4 has no cutover-session answer, and the read-only default-token baseline returned 404/error 10404 only for Notifications. The plan does not attempt a widen or claim AC4 is satisfied.
- The active standing delegation does not authorize widening this token; it is irrelevant to this read-only code/test change.
- Commits `f91f91af54` (AC2 envelope) and `a90442394a` (default-token profile tooling) exist in this worktree. The profile's successful deploy and the read-only 200 from the documented Notifications endpoint are supplied pipeline context, not repeated live operations in this planning phase.
- Planning collision pre-check found this branch's draft PR and three foreign `test-all.sh` processes; it reported no other open PR at that time. At ship-time re-probe, open PR #11479 was found to contain only the same byte-identical learning file; overlap preflight returned the non-blocking shared-file notice, and no changes to that PR were made.
- Ship-time duplicate-issue search found #11480 OPEN with the same Notifications route defect. PR #11479 is a learning-only PR referenced from #11480; this code-fix PR closes #11480 while leaving epic #11181 open.
- `websearch` returned an HTTP 404 tool error; the official Cloudflare API reference was fetched directly and verified at [List Notification policies](https://developers.cloudflare.com/api/resources/alerting/subresources/policies/methods/list/).
- An initial lookup of `knowledge-base/INDEX.md` returned not-found; a follow-up glob confirmed this worktree has no `knowledge-base/**/INDEX.md`, so there is no index file to update.

### Repository Findings

- `plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh` defines `DT_ROWS`; the Notifications row currently points at the nonexistent `accounts/$ACCT/notification_policies` path. That same table feeds both `--dry-run` and the live default-token loop.
- The existing `check()` and `authorized_body()` path already requires HTTP 200, `success == true`, and the declared response type; an account-scheme 404 returns `denied (404, unverified — fail-closed)`. Every default-token row calls this path with `trust404=0`. Keep these rules unchanged.
- `plugins/soleur/test/cf-token-scope.test.sh` provides a stub curl dispatcher, URL logging, profile-wide checks, and back-compat coverage for the rulesets profile. Its Notifications mock currently matches the old route, so it must move with the script row.
- `plugins/soleur/skills/cf-token-scope/SKILL.md` repeats the old Notifications route in the default-token endpoint table; update that row to avoid shipping contradictory documentation.
- Existing learning `knowledge-base/project/learnings/2026-07-24-stubbed-uniform-fixture-hides-per-endpoint-response-shape.md` requires endpoint-specific fixtures and a non-uniform response-shape test. The Notifications endpoint is an account list and must use an array fixture.
- Existing learning `knowledge-base/project/learnings/2026-07-23-live-api-fail-closed-guard-counts-degraded-200-as-empty-and-control-probe-must-cover-every-scheme.md` reinforces that degraded 200 bodies are not authorization and 404 trust is scheme-specific; the Notification account row keeps the existing no-trust-404 behavior.
- The requested learning source is not present in this worktree. Include the source file byte-identically in the corrective PR at `knowledge-base/project/learnings/2026-10-28-cf-token-retained-probe-used-nonexistent-notification-route.md`, SHA-256 `871e2785b041342a0c4e9180c39b01545e7883d7646e5d6117f686d6ccd9e250`; leave the original main-checkout copy untouched.

### Official API Contract

Cloudflare documents `GET /accounts/{account_id}/alerting/v3/policies` as “List Notification policies.” Its accepted permissions include `Notifications Read`; its response contract includes `success: true` and an optional array-valued `result`, and the documented 200 example has an array of policy objects. The documentation page does not list a pagination query parameter, so use the exact documented path without retaining the unsupported `?per_page=1` suffix. The user-provided read-only live check returned 200 on this route. This research confirms endpoint choice only; it does not authorize token permission changes.

### Mechanism Minimality

**Property List**

1. The default-token Notifications retained row reaches Cloudflare's documented account Alerting API endpoint.
2. A Notification response is authorized only when the existing status/body-shape classifier sees an authorized 200 with an array result.
3. A Notification 404 remains a hard failure even while the two LB target rows are at their expected baseline 403.
4. The other default-token routes and the rulesets profile retain their existing dispatch and classification behavior.
5. The route-correction learning is included without changing its bytes or removing its source copy.

The existing `DT_ROWS` table, shared print/run loop, `check()` classifier, and shell test harness already buy properties 1–4. The smallest change is to correct the Notifications row's route URL and displayed label, update its mock dispatch and assertions, and keep the docs table aligned. The learning file is a separately requested artifact, not a new runtime mechanism.

**Cut List**

- New endpoint-specific 404 exception → unnecessary and unsafe; the existing account-scheme classifier already rejects 404 and that behavior is required.
- New profile, token binding, classifier, or permission test against a live credential → no property beyond the existing table/classifier provides; would expand the one-route fix and could confuse the operator hold.
- LB, Terraform, workflow, cutover, or weight changes → unrelated to route dispatch and explicitly out of scope.

### Discovery and Coverage

- Stack coverage: this is a Bash-script/test change, not an uncovered stack; no community agent installation is indicated.
- Functional overlap: inline repository review found the existing first-party `cf-token-scope` probe is the relevant mechanism; no new capability or dependency is proposed, so no community artifact is indicated for installation. External registry fan-out was not run because child sessions are forbidden.
- Domain sweep (all eight domains, assessed inline): Engineering is relevant because the change corrects an existing API probe and its tests. Marketing, Operations, Product, Legal, Sales, Finance, and Support have no deliverable or process change in this narrow fix. No user-facing surface or architecture decision is introduced.
- Research fan-out, domain review, and plan review were handled sequentially inline because OpenCode nesting depth is one and this task forbids child sessions. No independent reviewer/agent ran.
- Coverage includes local source/test/docs inspection, the applicable fixture-shape learning, official Cloudflare documentation, issue-state validation, and inline domain/overlap review. No independent agent/reviewer ran.

## Implementation Phases

### Phase 1: Correct the retained Notifications route

1. In `plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh`, change only the Notifications `DT_ROWS` row's URL and displayed label to `$API/accounts/$ACCT/alerting/v3/policies`; keep `retained`, the account scheme, array response type, and `trust404=0` semantics.
2. In `plugins/soleur/test/cf-token-scope.test.sh`, dispatch the Notification mock only for a documented path with one account-ID segment; directly assert that a suffixed path falls through, pin the complete dry-run Notification recipe as one exact line, and log positional, `--url`, and `--url=` curl targets across schemes while pinning all six default-token URLs exactly.
3. Add a Notifications-only 200 fixture with a synthesized policy object in an array; assert the Notification row says `authorized (200)`, the run exits 0, and the existing expected LB 403 rows remain neutral in baseline mode.
4. Add a Notifications-only 404 fixture with LB rows still 403; assert exit 3, the Notification row is `denied (404, unverified — fail-closed)`, and `PASS: no scope dropped` is absent.
5. Add Notification degraded-200 cases (`success: false` with an array result and `success: true` with an object result) that exit 3, pinning both classifier conditions on this endpoint.
6. Keep URL dispatch and classification checks for Tunnel, Access, DNS, account LB pools, and zone LB unchanged; run the existing rulesets profile compatibility cases unchanged.

### Phase 2: Align documentation and carry the learning

1. Update the Notifications row in `plugins/soleur/skills/cf-token-scope/SKILL.md` to the documented endpoint.
2. Add the specified learning file byte-identically at its repo path, verify its SHA-256 against the supplied digest, and do not remove or edit the source copy.
3. Do not touch `apps/web-platform/infra/`, any workflow, Cloudflare permissions or token values, Doppler state, LB configuration, or cutover state. Leave web-2 at weight 0 and structurally excluded until the existing cutover marker; this fix adds no soak-gated close criterion.

### Files to Edit

- `plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh` — the Notifications row's URL and displayed label only.
- `plugins/soleur/test/cf-token-scope.test.sh` — exact Notification mock dispatch, whole-line dry-run/live URL assertions for all six default-token rows, success/404/degraded/wrong-shape scenarios, and sibling-profile regressions.
- `plugins/soleur/skills/cf-token-scope/SKILL.md` — matching route in the documented endpoint table.

### Files to Create

- `knowledge-base/project/learnings/2026-10-28-cf-token-retained-probe-used-nonexistent-notification-route.md` — unchanged source bytes, SHA-256 as above.
- `knowledge-base/project/specs/feat-one-shot-11181-cf-notification-route/spec.md`, `tasks.md`, and `session-state.md` — branch-scoped planning and execution artifacts.
- `knowledge-base/project/plans/2026-10-28-fix-cloudflare-notifications-route-plan.md` — this plan.

## Guard Contract

### Guard 1 — Default-token Notifications route and fail-closed regression tests

**Property.** The default-token Notifications row displays and requests Cloudflare's documented account Alerting API path, and is green only when the existing classifier accepts an authorized array-shaped 200; every 404 remains a hard failure.

**Assembly.** `DT_ROWS` is the single source for dry-run output and the default-token runtime loop; `plugins/soleur/test/cf-token-scope.test.sh` requires all six live default-token URLs as whole lines while logging only actual positional, `--url`, and `--url=` transfer targets across schemes, pins the complete dry-run Notifications recipe as one exact line, directly proves suffixed and proxy-only values fall through the mock, rejects proxy overrides in captured argv, and checks retained-row verdicts and exit status. The rulesets branch is separate and remains covered by its existing C-series and D10 back-compat scenarios.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore `/accounts/$ACCT/notification_policies` in the Notifications `DT_ROWS` URL | RED: URL-log/dry-run assertions reject the old route and the 200 fixture no longer reaches its intended dispatch arm |
| 2 | Remove the Notifications row from `DT_ROWS` after a passing row | RED: the test's explicit documented-route assertion and expected default-token dispatch fail |
| 3 | Accept an object-shaped Notifications result, including an empty object, as authorized | RED: D3w and D3we require both non-empty and empty object results to fail the array contract |
| 4 | Make a retained Notification 404 neutral or print the success summary after it | RED: the Notification 404 scenario requires exit 3 and no `PASS: no scope dropped` |
| 5 | Append `/extra` to the Notifications `DT_ROWS` URL | RED: exact dry-run/runtime URL assertions fail and the URL falls through the Notifications mock |
| 6 | Broaden the Notifications mock matcher to accept arbitrary suffixes | RED: the direct mock-boundary fixture receives the wrong response for `/policies/extra` |
| 7 | Add a second URL through positional, `--url`, or `--url=` syntax before the canonical URL, including an `http://` target | RED: the URL-operand log and exact dry-run recipe detect the additional target |
| 8 | Treat a `--proxy`, `--preproxy`, or `-x` value as the Notifications transfer URL, or add a proxy override beside the real target | RED: proxy-only fixtures cannot dispatch as Notifications, and D-conf rejects proxy overrides in the captured argv |

**Harness rows:**

- Suite mutations that must be RED: (a) append `/extra` to the route in a scratch copy; exact dry-run/runtime URL assertions fail and the mock falls through; (b) broaden the mock matcher; its direct suffix fixture fails; (c) add a second URL using positional, `--url`, or `--url=` syntax, including a non-HTTPS scheme; URL-operand and exact-recipe assertions fail; (d) treat a proxy value as the transfer URL or add a proxy override; proxy-only fixtures and D-conf fail.
- Must-PASS non-canonical input: return `200: {"success":true,"result":[{"id":"synthetic-policy-id"}]}` for Notifications while the two LB rows return their expected baseline 403; the Notification row must still classify authorized.

**Anchor.** The expected route is grounded in Cloudflare's official List Notification policies reference, which is outside this commit. Keep its URL cited beside the test scenario so a coordinated code+fixture path change cannot be presented as independent evidence that a nonexistent route is valid.

## Observability

This is an operator-invoked, read-only CLI probe correction, not a server, workflow, or infrastructure change. Its existing synchronous output and exit code remain the signal; the included learning records the known route mismatch and its verified correction without storing a bearer token or raw response body.

```yaml
liveness_signal:
  what: Per-invocation default-token retained-scope rows and final PASS/FAIL exit status
  cadence: Explicit baseline or post-widen invocation; no scheduled probe is added
  alert_target: Invoking CLI session consumes stdout, stderr, and exit status synchronously
  configured_in: plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh

error_reporting:
  destination: Invoking shell stdout/stderr and the test runner log for regression cases
  fail_loud: Probe exits 3 and prints the denied/degraded route; it does not convert a 404 into success

failure_modes:
  - mode: Notifications endpoint returns 404
    detection: Exit 3 plus the Notification denied row, covered by the Layer 7 cli-stdout-artifact synchronous consumer and the committed route-correction learning
    alert_route: No paging for an explicit one-off probe; Layer 7 cli-stdout-artifact is the synchronous operator signal
  - mode: Notifications returns a degraded or wrong-shape 200
    detection: Exit 3 and the degraded row, covered by Layer 7 cli-stdout-artifact and the shell regression suite
    alert_route: No paging for an explicit one-off probe; Layer 7 cli-stdout-artifact is the synchronous operator signal
  - mode: A retained sibling route regresses
    detection: Existing per-row test cases fail, covered by the test runner log and Layer 7 cli-stdout-artifact at probe invocation
    alert_route: No paging for an explicit one-off probe; Layer 7 cli-stdout-artifact is the synchronous operator signal

logs:
  where: Invoking shell output and CI shell-test output; no additional persistent diagnostics service
  retention: Shell output is session-scoped; CI retention follows repository policy; the route-correction learning is committed

discoverability_test:
  command: bash plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh --profile default-token --dry-run
  expected_output: alerting/v3/policies
```

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned no issue whose body names the implementation, test, documentation, learning, or branch planning paths.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Fix the `cf-token-scope` default-token Notifications probe URL and its tests in a focused PR, as follow-up work on open epic #11181's non-cutover track." | FR1–FR3; Phases 1–2; script, test, and skill-doc files | mapped |
| 2 | "Use Cloudflare's official endpoint GET /accounts/{account_id}/alerting/v3/policies; preserve fail-closed classification." | FR1–FR2; Guard Contract; URL, 200, and 404 scenarios | mapped |
| 3 | "Do not widen or otherwise mutate Cloudflare permissions, tokens, Doppler, or infrastructure; do not dispatch workflows." | Non-Goals; Phase 2 scope boundary; AC6 | mapped |
| 4 | "The current main checkout contains an untracked learning at `/data/git-repositories/jikig-ai/soleur/knowledge-base/project/learnings/2026-10-28-cf-token-retained-probe-used-nonexistent-notification-route.md` (already read by the pipeline runner; SHA-256 871e2785b041342a0c4e9180c39b01545e7883d7646e5d6117f686d6ccd9e250). It is not present in this worktree. Plan to include that file in the corrective PR byte-identically, without removing the source copy." | FR4; Phase 2.2; learning-file create entry; AC5 | mapped |
| 5 | "No soak-gated close criterion is introduced; preserve web-2 weight 0 / structural exclusion until the existing cutover marker; no infrastructure actions in this fix." | Non-Goals; Phase 2.3; AC6 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| Notifications URL in `cf-token-scope.sh` | "Fix the `cf-token-scope` default-token Notifications probe URL" | asked |
| URL, 200, 404 and sibling-route tests in `cf-token-scope.test.sh` | "and its tests"; "Use Cloudflare's official endpoint GET /accounts/{account_id}/alerting/v3/policies; preserve fail-closed classification." | asked |
| endpoint row in `cf-token-scope/SKILL.md` | "Use Cloudflare's official endpoint GET /accounts/{account_id}/alerting/v3/policies" | asked |
| Byte-identical learning copy | "Plan to include that file in the corrective PR byte-identically, without removing the source copy." | asked |
| Plan, spec, and task artifacts | "Create only planning artifacts under `knowledge-base/project/plans/` and `knowledge-base/project/specs/` for this exact branch." | asked |
| web-2 / no-mutation boundary | "No soak-gated closure is introduced; preserve web-2 weight 0 / structural exclusion until the existing cutover marker; no infrastructure actions in this fix." | asked |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur`, `knowledge-base`
- Planned PR files: 8 (three implementation files, one learning, and four branch planning/execution artifacts) | Estimated changed lines: under 200, including the unchanged learning inclusion
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — one URL correction, its mock/test cases, matching skill documentation, and the explicitly requested unchanged learning artifact

## Acceptance Criteria

- [x] The `default-token` Notifications row dispatches `GET /accounts/{account_id}/alerting/v3/policies` through `DT_ROWS`; no old `/notification_policies` path remains in the source, test dispatch, or profile documentation.
- [x] The curl URL-log test records positional, `--url`, and `--url=` targets across schemes and proves all six complete default-token URLs and resolved IDs; the Notification route is exact and occurs once, dry-run matches the complete one-URL recipe, and a direct fixture proves the mock rejects a suffixed route.
- [x] Curl argv confinement requires no proxy override; proxy option values cannot satisfy the mock's transfer-URL assertion.
- [x] An authorized Notification 200 with `success: true` and array-valued `result` is reported as `authorized (200)` and can pass the default-token baseline when all retained rows authorize and LB 403 rows are at baseline.
- [x] A Notification 404 remains `denied (404, unverified — fail-closed)`, returns exit 3, and cannot be neutralized by the expected LB 403 rows; degraded/wrong-shape 200 responses also fail.
- [x] Existing Tunnel, Access, DNS, account LB pools, zone Load Balancers, and rulesets profile URL/classification regression cases remain green with their exact existing request URLs.
- [x] At the original #11456 merge, the learning file matched the supplied SHA-256; a later separately authorized follow-up redacted the current copy without rewriting that merge.
- [x] `bash plugins/soleur/test/cf-token-scope.test.sh` passes with zero failures.
- [x] No Cloudflare permissions/token, Doppler value, infrastructure, workflow, cutover, or web-2 weight/structural-exclusion state is changed; verify the infra/workflow diff is empty with `git diff --quiet origin/main...HEAD -- apps/web-platform/infra .github/workflows`; close duplicate issue #11480 while leaving epic #11181 open (`Closes #11480` and `Ref #11181`).

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** Inline review confirms this is a one-row endpoint correction within an existing API probe. Existing account-scheme authorization, private-fd token handling, and 404 fail-closed behavior remain the source of truth. No new infrastructure, trust boundary, architecture decision, or cutover work is proposed. A separate CTO agent was not invoked because the pipeline requires depth-one sequential fallback.

## Test Scenarios

Run the focused shell suite:

```bash
bash plugins/soleur/test/cf-token-scope.test.sh
```

- **unit — URL dispatch:** Given `--profile default-token`, when the stub curl URL log is captured, then positional, `--url`, and `--url=` targets are recorded across schemes and all six default-token request URLs match their expected complete lines and resolved IDs, including the Notification request `https://api.cloudflare.com/client/v4/accounts/acct9876543210fedcba/alerting/v3/policies` exactly once, with no query suffix; a direct mock fixture rejects a suffixed route.
- **unit — proxy separation:** Given a mock invocation whose only URL-looking value is supplied to `--proxy` in equals or separated form, then it is not recorded or dispatched as a transfer URL; D-conf rejects proxy overrides in the SUT argv.
- **unit — dry-run route:** Given `--profile default-token --dry-run`, then the sole Notifications recipe exactly matches the documented one-URL curl command ending at `https://api.cloudflare.com/client/v4/accounts/$ACCT/alerting/v3/policies`, with no query or extra path, and issues no curl request.
- **unit — successful Notification 200:** Given a Notification response of `200` with `success: true` and a non-empty array `result`, while both LB rows return baseline 403, when the default-token profile runs, then Notifications is `authorized (200)`, the process exits 0, and the LB rows remain `not-yet-widened` without masking retained-row failures.
- **unit — Notification 404 fail-closed:** Given the Notification URL returns 404 and the LB target rows return baseline 403, when the default-token profile runs, then it exits 3, reports `denied (404, unverified — fail-closed)`, and omits `PASS: no scope dropped`.
- **unit — degraded/wrong-shape Notification responses:** Given both LB rows return baseline 403 and a Notification 200 has `success: false` with an array result or `success: true` with an empty or non-empty object result, when the default-token profile runs, then it exits 3 and does not report Notifications authorized.
- **unit — default-token route regressions:** Given successful mock responses, when the profile runs, then Tunnel, Access, DNS, account LB pools, and zone Load Balancers each match their exact existing URL and resolved ID; the LB baseline-neutrality and `--expect-lb-scopes` cases keep their prior results.
- **unit — rulesets profile regression:** Given no profile flag or explicit `--profile rulesets`, when the existing rulesets scenarios run, then dry-run output remains identical and the C-series behavior remains unchanged.
- **unit — docs/profile parity:** Given the updated skill documentation, when reviewing the route table alongside the implementation, then both name `/accounts/{account_id}/alerting/v3/policies` and no stale Notifications path remains in the profile documentation.
- **artifact integrity at the original #11456 merge:** the learning copy's SHA-256 equaled `871e2785b041342a0c4e9180c39b01545e7883d7646e5d6117f686d6ccd9e250`; that merge-time copy was later redacted in a separately authorized follow-up, without rewriting published history.

## Final Review Addendum

- Expanded curl mock coverage to all proxy selectors accepted by the installed curl (`--proxy`, `--proxy1.0`, `--preproxy`, SOCKS4/4a/5/5-hostname, and `-x`), both alone and with a real transfer target; D-conf pins `--noproxy '*'` and rejects each selector.
- Added direct mock rejection for a Notifications query suffix and a fail-closed Notifications 201 fixture with an otherwise valid array response.
- Removed duplicate curl-mock sharp-edge guidance. The final focused suite passed 219/219; Bash syntax, warning-severity ShellCheck, and `git diff --check` passed.
- A separate P3 finding in the learning's session-anomaly prose was verified pre-existing on `origin/main` after PR #11479 merged. Per the user's authorization, the post-merge follow-up redacts that detail while preserving the general credential-correlation lesson; the already-published commit history remains unchanged.
- The follow-up targeted round pins exactly one `--noproxy '*'` per probe and rejects clustered `-sSx`; mixed-target fixtures now exercise each proxy selector in separated/equal/attached forms.
- Each mixed-target fixture asserts exactly one logged transfer target; the mock and D-conf also cover clustered short-form `-sSx` and duplicate/narrowed `--noproxy` mutations.
