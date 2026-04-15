# fix(ci): apply `jq -e` guard to scheduled LinkedIn and Cloudflare token-check workflows

**Issue:** #2236
**Branch:** `feat-one-shot-2236-jq-guard-scheduled-workflows`
**Type:** bug (CI hygiene)
**Priority:** P2
**Milestone:** Phase 3: Make it Sticky
**Labels:** bug, domain/engineering, priority/p2-medium, code-review
**Date:** 2026-04-15
**Author:** Claude (one-shot pipeline)

## Summary

Two scheduled workflows call `jq -r` on vendor-API JSON responses under the GitHub Actions default `bash -e` without first validating that the response body is JSON. If the vendor (LinkedIn `/v2/userinfo`, Cloudflare `/accounts/.../access/service_tokens`) ever returns a non-JSON body — an edge error page, a rate-limit HTML payload, an auth challenge — `jq` exits non-zero inside `$(...)`, `bash -e` kills the step, and the scheduled job fails silently at 3am. This is the exact failure class fixed in PR #2226 (`#2214`).

This plan replicates the canonical guard already codified in AGENTS.md (`cq-ci-steps-polling-json-endpoints-under`) in both files.

## Problem

### Canonical failure mode (from #2214 / PR #2226)

Release run `24411905995` crashed when `/hooks/deploy-status` returned adnanh/webhook's plaintext `"Hook not found"`:

1. Step shell runs under `bash -e` (GitHub Actions default).
2. `BODY=$(curl ...)` returns a plaintext body (HTTP 200 or 4xx with non-JSON content).
3. `FIELD=$(echo "$BODY" | jq -r '.field')` — `jq` exits 5 because body is not JSON.
4. Non-zero exit inside `$(...)` propagates; `bash -e` kills the step.
5. Any retry/timeout logic further down is never reached.

The fix codified in AGENTS.md line 77:

> CI steps polling JSON endpoints under `bash -e` must precede every `jq -r` / `jq '.field'` call with a `jq -e . >/dev/null 2>&1` guard that `continue`s on non-JSON bodies. [...] Do NOT use `jq empty` (too permissive). Do NOT drop `-e` from the step shell (silences real failures elsewhere in the loop).

### Affected workflows (this issue)

The git-history analyst on PR #2226 identified two other workflows with the same latent bug:

#### 1. `.github/workflows/scheduled-linkedin-token-check.yml` (line 93)

Current code (after HTTP code check passes with 2xx):

```bash
echo "LinkedIn token is valid (HTTP $HTTP_CODE)."
echo "Token holder: $(jq -r '.name // "unknown"' /tmp/li-response.json)"
```

The `jq -r` runs inside `$(...)`. The step does not set `set -e` explicitly, but GitHub Actions runs each `run:` under `bash --noprofile --norc -eo pipefail {0}` by default — so `-e` is on.

**Failure scenario:** LinkedIn API returns HTTP 200 with an HTML edge page (incident, rate limit, maintenance redirect). `jq -r` exits 5, step fails. Scheduled Monday 09:00 UTC cron creates a noisy failure even though the token is actually valid.

**Current behavior on non-2xx:** The workflow already handles HTTP 401 (token expired → issue creation) and other non-2xx (warning + `exit 0`). The non-JSON risk lives only in the 2xx branch.

#### 2. `.github/workflows/scheduled-cf-token-expiry-check.yml` (lines 64-67)

Current code (after HTTP code check passes with 2xx):

```bash
EXPIRES_AT=$(jq -r \
  --arg name "$TOKEN_NAME" \
  '.result[] | select(.name == $name) | .expires_at // empty' \
  "$TMPFILE")
```

Step explicitly sets `set -euo pipefail`. If Cloudflare returns a non-JSON body on HTTP 200 (rare but observed under edge incidents), `jq -r` exits, `set -e` kills the step. Scheduled run fails, operator gets a false alarm that the CF token is in trouble.

**Impact:** Both workflows create noisy failure pages on false positives. Neither is user-facing but both are ops-visible. LinkedIn runs weekly Mondays 09:00 UTC; CF runs on manual dispatch today (cron pending validation per the file's header comment).

## Proposed Fix

For each file, add a `jq -e . >/dev/null 2>&1` pre-check between the HTTP status validation and any `jq -r` / `jq '.field'` call. Because both workflows are **single-shot** (not retry loops), the action on non-JSON is `exit 0` with a `::warning::` so the scheduled run is marked successful but the anomaly is visible in the run log. Creating a phantom "token expired" issue off a transient non-JSON blip would be worse than a missed check — the next scheduled run will recover.

### 1. scheduled-linkedin-token-check.yml

**Location:** between line 92 (HTTP 2xx check passed) and line 93 (first `jq -r`).

```bash
# Before the first jq -r call, validate that the body is JSON.
# LinkedIn can return HTML under edge incidents; jq -r under bash -e
# would crash the step and hide the fact that the token is actually valid.
# See AGENTS.md `cq-ci-steps-polling-json-endpoints-under` (#2214, #2236).
if ! jq -e . /tmp/li-response.json >/dev/null 2>&1; then
  echo "::warning::LinkedIn API returned non-JSON body on HTTP $HTTP_CODE. Skipping this check -- will retry next cron."
  exit 0
fi

echo "LinkedIn token is valid (HTTP $HTTP_CODE)."
echo "Token holder: $(jq -r '.name // "unknown"' /tmp/li-response.json)"
```

The dead-stale-issue close block (lines 96-104) also calls `gh issue list --jq '.[0].number // empty'` — but that runs against `gh`'s own structured output, not a vendor API, so it is out of scope for this guard.

### 2. scheduled-cf-token-expiry-check.yml

**Location:** between line 61 (HTTP 2xx check passed) and line 64 (first `jq -r` on `$TMPFILE`).

```bash
# Validate body is JSON before any jq -r call. Cloudflare's API is
# normally reliable, but edge incidents and rate-limit HTML pages have
# been observed. Under set -euo pipefail, a jq parse error would crash
# this single-shot check and create a false operator signal.
# See AGENTS.md `cq-ci-steps-polling-json-endpoints-under` (#2214, #2236).
if ! jq -e . "$TMPFILE" >/dev/null 2>&1; then
  echo "::warning::Cloudflare API returned non-JSON body on HTTP $HTTP_CODE. Skipping this check -- will retry next cron."
  exit 0
fi

# Find the deploy token by name
EXPIRES_AT=$(jq -r \
  --arg name "$TOKEN_NAME" \
  '.result[] | select(.name == $name) | .expires_at // empty' \
  "$TMPFILE")
```

Note: the CF workflow's `gh issue list --jq` calls (lines 111, 133) are against `gh`'s own output — out of scope.

## Design Decisions

### Why `exit 0` and not `continue`?

The AGENTS.md rule example uses `continue` because the reference case (`web-platform-release.yml`) is a retry loop with a 120s timeout. Scheduled checks are single-shot — a loop would add surface area without value. `exit 0 + ::warning::` produces a successful scheduled run with a visible anomaly, which is the right behavior for a health check where the next cron will recover.

### Why `::warning::` and not `::error::`?

A non-JSON blip is not an error the operator needs to act on. If the vendor is genuinely down, the next cron run (or the Terraform-managed CF notification for the CF case) will catch it. Using `::error::` would page the operator on transient vendor edge conditions.

### Why not extend the HTTP-code check instead?

An HTTP 200 response with non-JSON body is precisely the case the HTTP check cannot catch — that is the whole reason the JSON guard exists. Checking `Content-Type` headers is brittle (vendors sometimes send `application/json` with HTML payload under incidents). `jq -e .` is the canonical, pattern-codified guard.

### Why not use `jq empty`?

AGENTS.md explicitly forbids it: "too permissive — passes `null` through to field parsers." `jq -e .` rejects `null` (exits 1) and non-JSON (exits 5). This matters for the LinkedIn case where the response is `"$BODY"` (not a file) and upstream `null` would silently flow into `.name // "unknown"`.

### Why not drop `set -e` / `set -euo pipefail` in the CF workflow?

AGENTS.md explicitly forbids: "Do NOT drop `-e` from the step shell (silences real failures elsewhere in the loop)." `-e` catches legit failures in `curl`, `date -d`, and the HTTP validation block. Dropping it to paper over the jq issue would be a regression.

## Files to Change

| File | Change |
|------|--------|
| `.github/workflows/scheduled-linkedin-token-check.yml` | Insert `jq -e .` guard between lines 92 and 93 |
| `.github/workflows/scheduled-cf-token-expiry-check.yml` | Insert `jq -e .` guard between lines 61 and 64 |

**No AGENTS.md update needed** — the rule `cq-ci-steps-polling-json-endpoints-under` is already codified (added in PR #2226). This plan is retroactive application of the existing rule to the two known-affected files, per the workflow gate `wg-when-fixing-a-workflow-gates-detection` ("gate fixed AND missed case remediated").

## Acceptance Criteria

- [ ] `.github/workflows/scheduled-linkedin-token-check.yml` has a `jq -e . /tmp/li-response.json >/dev/null 2>&1` guard before the `$(jq -r ...)` call on line 93.
- [ ] `.github/workflows/scheduled-cf-token-expiry-check.yml` has a `jq -e . "$TMPFILE" >/dev/null 2>&1` guard before the `jq -r` call on lines 64-67.
- [ ] Both guards log a clear `::warning::` message identifying the vendor and HTTP code so triage is easy.
- [ ] Both guards `exit 0` (not `continue` — single-shot workflows, not retry loops).
- [ ] `actionlint .github/workflows/scheduled-linkedin-token-check.yml` passes.
- [ ] `actionlint .github/workflows/scheduled-cf-token-expiry-check.yml` passes.
- [ ] `shellcheck` on the `run:` blocks (if pre-commit runs it) passes.
- [ ] Guards comment-reference AGENTS.md rule ID and issues `#2214, #2236` for future triage.
- [ ] Manual dispatch of both workflows on the feature branch succeeds end-to-end (the happy path — vendor returns valid JSON — must still work after the guard).

## Test Scenarios

Because the workflows execute only inside GitHub Actions with real vendor credentials, local TDD tests would need to mock `curl` and GitHub Actions' shell — high cost for low value on a 3-line guard. Instead, validate via:

### 1. Syntax / lint (local, pre-push)

```bash
cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-2236-jq-guard-scheduled-workflows
actionlint .github/workflows/scheduled-linkedin-token-check.yml \
           .github/workflows/scheduled-cf-token-expiry-check.yml
```

Must exit 0 with no findings.

### 2. Shell-level unit check (local, pre-push)

Extract the guard to a tiny shell sanity test — no test framework, just `bash -e`:

```bash
# Positive case: valid JSON should pass the guard
echo '{"result":[{"name":"x","expires_at":"2026-05-01T00:00:00Z"}]}' > /tmp/t.json
bash -euo pipefail -c 'jq -e . /tmp/t.json >/dev/null 2>&1 && echo "pass: valid JSON"'

# Negative case 1: HTML body (simulates CF edge page)
echo '<html>503 Service Unavailable</html>' > /tmp/t.json
bash -euo pipefail -c 'if ! jq -e . /tmp/t.json >/dev/null 2>&1; then echo "pass: HTML rejected"; fi'

# Negative case 2: plaintext (simulates adnanh/webhook 404-style body)
echo 'Hook not found' > /tmp/t.json
bash -euo pipefail -c 'if ! jq -e . /tmp/t.json >/dev/null 2>&1; then echo "pass: plaintext rejected"; fi'

# Negative case 3: literal null (the reason jq -e beats jq empty)
echo 'null' > /tmp/t.json
bash -euo pipefail -c 'if ! jq -e . /tmp/t.json >/dev/null 2>&1; then echo "pass: null rejected"; fi'

# Negative case 4: empty file
: > /tmp/t.json
bash -euo pipefail -c 'if ! jq -e . /tmp/t.json >/dev/null 2>&1; then echo "pass: empty rejected"; fi'
```

All five must print their pass message.

### 3. End-to-end manual dispatch (post-push, pre-merge)

After the branch is pushed:

```bash
gh workflow run scheduled-linkedin-token-check.yml --ref feat-one-shot-2236-jq-guard-scheduled-workflows
gh workflow run scheduled-cf-token-expiry-check.yml --ref feat-one-shot-2236-jq-guard-scheduled-workflows
```

Poll via Monitor tool until both runs complete. Both must:

- Succeed (conclusion: `success`).
- Log either "LinkedIn token is valid" / "Token is healthy" (happy path) OR the new `::warning::` line (if vendor happens to hiccup during the run).
- Not create spurious action-required issues.

Per AGENTS.md `wg-after-merging-a-pr-that-adds-or-modifies`, run the same dispatch again after merge to `main` to verify the merged state works.

## Risks

- **Vendor happy-path regression**: the guard runs BEFORE the `jq -r` so if the vendor returns valid JSON (99.9% case), behavior is unchanged. Verified by shell unit test case 1.
- **Hiding real auth failures**: the guard only fires when HTTP is 2xx AND body is non-JSON. HTTP 401 (expired token) is still handled upstream — the LinkedIn workflow creates its issue on HTTP 401 before reaching the `jq -r` line. Non-2xx paths are unchanged.
- **Phantom-issue creation**: `exit 0` means a truly broken vendor would cause multiple successful-looking runs. Mitigation: the CF workflow's Terraform-managed notification policy is the primary alert; this workflow is the backup. For LinkedIn, the next weekly cron will retry. If the vendor stays broken for >1 week, the operator will notice the warning pile.

## Rollback

If either guard causes unexpected behavior, revert the single commit. No migration, no external resources, no state.

## Research Findings

### Local research

- **Pattern source**: `.github/workflows/web-platform-release.yml` lines 117-131 — the canonical implementation codified in PR #2226 (commit `6e7b4181`).
- **Rule of record**: `AGENTS.md` line 77, rule `cq-ci-steps-polling-json-endpoints-under`. Forbids `jq empty` and dropping `-e`.
- **Bug-class learning**: `knowledge-base/project/learnings/bug-fixes/2026-04-15-signed-get-verify-step-tolerate-non-json-bodies.md` — comprehensive writeup of why `jq empty` fails for `null` and why `-e` must stay on.
- **Release failure reference**: Release run `24411905995` on `main` — the exact crash that motivated PR #2226.

### Consulted but not applicable

- `knowledge-base/project/plans/2026-03-18-fix-ci-pin-bun-version-scheduled-workflows-plan.md` — prior scheduled-workflow fix, different bug class (bun version pinning). Structural template reused for this plan.
- `knowledge-base/project/plans/2026-03-10-feat-scheduled-community-monitoring-workflow-plan.md` — scheduled workflow creation pattern. Not relevant to jq guard.

### External research

Skipped per Phase 1.6 decision: strong local pattern (PR #2226), codified rule (AGENTS.md), and a learning file make external research low-value. This is a mechanical retroactive fix.

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)

**Status:** reviewed (inline — no domain leader delegation needed)
**Assessment:** This is pure CI hygiene — retroactive application of a codified AGENTS.md rule to two known-affected workflow files. No architectural implications, no new dependencies, no public surface change. The fix is 3 lines per file, the pattern is canonical, and the mechanical escalation check (no new `.tsx` or `page.tsx` files) produces NONE tier. No delegation adds signal. The workflow gate `wg-when-fixing-a-workflow-gates-detection` explicitly requires this kind of retroactive sweep — this plan IS that sweep.

No other domains have signal:

- **Product / CPO**: no user-facing change. Tier NONE.
- **CMO, COO, CRO, Legal, Finance, Community**: no signal (internal CI).

**Brainstorm-recommended specialists:** none (no brainstorm for this scope — issue body itself is the spec).

## Implementation Steps

1. Read both workflow files in the worktree. (Already done during planning — the exact injection lines are known.)
2. Apply the guard in `scheduled-linkedin-token-check.yml` between lines 92-93 with a comment-referenced rule ID.
3. Apply the guard in `scheduled-cf-token-expiry-check.yml` between lines 61-64 with a comment-referenced rule ID.
4. Run `actionlint` on both files. Fix any findings.
5. Run the 5 shell sanity cases from Test Scenarios §2 locally.
6. Stage, run `skill: soleur:compound` (per AGENTS.md `wg-before-every-commit-run-compound-skill`), commit with message `fix(ci): guard jq -e on scheduled linkedin/cf token checks`.
7. Push branch.
8. Run `gh workflow run` on both workflows against the feature branch; poll with Monitor tool; verify green.
9. Proceed to review + QA + ship per the standard pipeline. PR body must include `Closes #2236`.
10. Post-merge (per `wg-after-merging-a-pr-that-adds-or-modifies`): dispatch both workflows on `main`; verify green.

## Non-Goals

- **Not** adding a generic `jq` wrapper helper script. Two files do not justify abstraction; the guard is 5 lines with explicit intent.
- **Not** touching the other `scheduled-*.yml` files. A full sweep across all scheduled workflows is tracked implicitly — if another file surfaces the same pattern during review (Sharp Edges §5), file it as a follow-up issue rather than scope-creep this fix.
- **Not** changing the retry / single-shot semantics of either workflow.
- **Not** adding a test framework for GitHub Actions workflow steps. Out of scope; shell sanity cases + `actionlint` + end-to-end dispatch are sufficient for this bug class.

## Deferrals

None. Scope is fully contained in this PR.

## References

- Issue #2236 (this issue)
- Issue #2214 (original bug class)
- PR #2226 (canonical fix + rule codification; commit `6e7b4181`)
- AGENTS.md rule `cq-ci-steps-polling-json-endpoints-under`
- Learning `knowledge-base/project/learnings/bug-fixes/2026-04-15-signed-get-verify-step-tolerate-non-json-bodies.md`
- Failed release run `24411905995` (historical evidence)
