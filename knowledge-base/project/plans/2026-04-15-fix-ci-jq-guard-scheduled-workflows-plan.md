# fix(ci): apply `jq -e` guard to scheduled LinkedIn and Cloudflare token-check workflows

**Issue:** #2236
**Branch:** `feat-one-shot-2236-jq-guard-scheduled-workflows`
**Type:** bug (CI hygiene)
**Priority:** P2
**Milestone:** Phase 3: Make it Sticky
**Labels:** bug, domain/engineering, priority/p2-medium, code-review
**Date:** 2026-04-15
**Author:** Claude (one-shot pipeline)

## Enhancement Summary

**Deepened on:** 2026-04-15
**Sections enhanced:** 6 (Problem, Proposed Fix, Design Decisions, Test Scenarios, Risks, Research Findings)
**Research method:** inline (subagent Task tool unavailable in this harness — confined to high-signal direct research)
**Sources consulted:**

- `knowledge-base/project/learnings/bug-fixes/2026-04-15-signed-get-verify-step-tolerate-non-json-bodies.md` (canonical learning — edge-case matrix + rejected-alternatives rationale)
- `knowledge-base/project/learnings/runtime-errors/2026-02-13-bash-operator-precedence-ssh-deploy-fallback.md` (referenced by the learning — justification for keeping `bash -e`)
- PR #2226 commit `6e7b4181` diff (canonical pattern, exact token match)
- Full workflow grep for `jq -r` across `.github/workflows/*.yml` (latent-bug-class sweep)
- AGENTS.md rule `cq-ci-steps-polling-json-endpoints-under` (canonical rule text)

### Key Improvements Added to the Plan

1. **Guard placement correction (load-bearing).** The LinkedIn guard must protect BOTH the `jq -r` call on line 93 AND the subsequent `gh issue close` on line 102. A non-JSON 2xx body would currently not only crash the step but would first incorrectly auto-close any open "token expired" issue as stale. Injection point moved from "between 92 and 93" to "between 90 and 91" — after the HTTP check, before everything that trusts the body content.
2. **Edge-case matrix adopted from the learning.** Replaced the hand-rolled shell sanity cases with the verified jq 1.8.1 / bash 5.x matrix from the learning file (7 rows including `{}`, `[]`, and `null` — the last is the key reason `jq empty` is forbidden).
3. **Bash-e behavior clarification.** Documented that LinkedIn workflow does NOT set `set -e` explicitly but still has strict-mode behavior via GitHub Actions' default `bash --noprofile --norc -eo pipefail {0}` shell. The bug applies to both files because of this default — not because of the explicit `set -euo pipefail` in the CF workflow.
4. **Alternatives-rejected section populated** from the learning file. Three rejected alternatives (drop `bash -e`, `set +e/-e` toggle, `jq empty`) now carry their actual rationale, including why `jq empty` is unsafe even under `// empty` defaults.
5. **Latent-bug-class sweep performed.** Grepped all 5 other `jq -r` sites in `.github/workflows/*.yml`. Three are confirmed safe (trusted `gh` CLI output, filtered internal pipeline, or already guarded by #2226). One — `web-platform-release.yml:177-190` health-check loop — is a legitimate follow-up candidate. Filed as a non-goal with a tracking-issue task in Deferrals.
6. **Empty-file and `$EXPIRES_AT` semantics cross-check.** Verified that the CF workflow's existing `[[ -z "$EXPIRES_AT" ]]` branch on line 69 continues to work correctly after the guard — the guard runs before `jq -r` sets `EXPIRES_AT`, so the branch semantics are preserved.

### New Considerations Discovered

- The learning's edge-case matrix shows `{}` and `[]` pass `jq -e .` (truthy output). For the LinkedIn workflow this is a non-issue because `jq -r '.name // "unknown"'` just prints "unknown". For the CF workflow, `.result[]` on `{}` yields empty (no rows), `EXPIRES_AT=""`, and the existing `[[ -z "$EXPIRES_AT" ]]` branch fires — correct behavior. No additional guard needed for these.
- Workflow-gap reminder surfaced by the learning (Session Errors §4): plan acceptance-criteria checkboxes should separate pre-merge from post-merge items. This plan already does (Phase 5 post-merge is in tasks.md under Phase 7), so no change needed — but worth flagging for the implementation phase that the acceptance criteria list here is pre-merge only.

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

**Location:** between line 90 (HTTP 2xx check passed, `fi`) and line 92 (`echo "LinkedIn token is valid"`).

**Placement rationale (load-bearing):** the guard must protect BOTH the `jq -r` call on line 93 AND the subsequent `gh issue close` block on lines 96-104. Without the guard, a non-JSON 2xx response would not only crash the step at the `jq -r` line — it would first execute the "close stale issue" block based on a body the workflow hasn't validated. Placing the guard *before* the "token is valid" echo ensures we don't act on a 2xx-with-garbage response at all.

```bash
# After HTTP 2xx check, validate that the body is JSON.
# LinkedIn can return HTML under edge incidents (rate limit, maintenance,
# Cloudflare fronting). jq -r under GitHub Actions' default strict shell
# (bash --noprofile --norc -eo pipefail) would crash the step AND the
# failure would follow the "token is valid" code path — closing any open
# "token expired" issue as if the body had been validated.
# See AGENTS.md `cq-ci-steps-polling-json-endpoints-under` (#2214, #2236).
if ! jq -e . /tmp/li-response.json >/dev/null 2>&1; then
  echo "::warning::LinkedIn API returned non-JSON body on HTTP $HTTP_CODE. Skipping this check -- will retry next cron."
  exit 0
fi

echo "LinkedIn token is valid (HTTP $HTTP_CODE)."
echo "Token holder: $(jq -r '.name // "unknown"' /tmp/li-response.json)"
```

Note on downstream `gh` calls: the `gh issue list --jq '.[0].number // empty'` on lines 96-98 runs against `gh`'s own structured output (not a vendor body). `gh` guarantees well-formed JSON or a non-zero exit — so that `--jq` filter does not need its own guard.

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

AGENTS.md explicitly forbids it: "too permissive — passes `null` through to field parsers." The learning file articulates this precisely:

> `jq empty` succeeds on any valid JSON including `null`. Combined with the existing `// -99` defaults, a `null` body would yield `EXIT_CODE=-99`, hit the `*)` fast-fail branch, and fail the release — worse than "retry until timeout with a clear non-ready message."

For the CF workflow specifically: a `null` body under `jq empty` would pass the guard, then `.result[]` on `null` would crash `jq -r` with exit 5 (iteration over null) — the exact failure we're trying to prevent. `jq -e .` catches `null` at exit 1 before it reaches the field parser.

### Why not drop `set -e` / `set -euo pipefail`?

The learning file has a pointed rationale:

> Disables defensive behavior for every other command (curl, cat, sleep, sed) in the loop. The current incident is scoped to jq; the fix should be too. See `2026-02-13-bash-operator-precedence-ssh-deploy-fallback.md` for why quiet failure-absorption in deploy-adjacent shell is a critical-severity anti-pattern.

AGENTS.md matches: "Do NOT drop `-e` from the step shell (silences real failures elsewhere in the loop)." `-e` catches legit failures in `curl`, `date -d`, and the HTTP validation block.

**Subtlety worth noting:** the LinkedIn workflow does NOT set `set -e` explicitly in its `run:` block — it relies on GitHub Actions' default shell `bash --noprofile --norc -eo pipefail {0}`. The CF workflow does set `set -euo pipefail` explicitly. The bug applies to **both** files because of the default — which is why neither can be "fixed" by inspecting the run block alone. Dropping `set -euo pipefail` from the CF file would still leave `-e` on via the default shell.

### Why not `set +e` / `set -e` toggling around each jq call?

Rejected in the learning:

> Brittle — any future maintainer editing the block has to preserve the toggle correctly. Mixes with `continue` semantics.

A single-line guard is maintainable; a toggle pair scattered across 5 lines is a maintenance hazard.

### Why not retry-loop both workflows to match the release-verify pattern?

The release workflow retries because deploys are inherently async — the endpoint is expected to be not-ready during cold-start. Scheduled health checks are instant queries; retrying would only mask the actual vendor-side state. The right behavior for a weekly cron is "try once, warn if weird, wait for next week." `exit 0 + ::warning::` achieves this without surface-area growth.

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

The learning file codifies the verified edge-case matrix against `jq 1.8.1 / bash 5.x`. Reuse it here exactly so the guard's semantics are pinned to known behavior.

| Input (written to `/tmp/t.json`) | `jq -e .` exit | Expected guard behavior |
|---|---|---|
| Valid JSON object (`{"name":"x"}` for LinkedIn shape; `{"result":[{"name":"x","expires_at":"..."}]}` for CF shape) | 0 | passes guard; proceeds to field parser |
| Valid JSON object missing key (`{"other":"x"}`) | 0 | passes guard; `.name // "unknown"` prints "unknown" / CF `EXPIRES_AT=""` falls through to existing `[[ -z ]]` branch |
| `null` literal | 1 | `::warning::`, `exit 0` (would crash without guard) |
| Non-JSON plaintext (`Hook not found`) | 5 | `::warning::`, `exit 0` |
| HTML error page (`<html>503</html>`) | 5 | `::warning::`, `exit 0` |
| Empty file | 5 | `::warning::`, `exit 0` |
| Empty JSON object `{}` | 0 | passes guard; LinkedIn prints "unknown"; CF falls through to `[[ -z "$EXPIRES_AT" ]]` branch (the `::warning::service token not found` path) |
| Empty JSON array `[]` | 0 | passes guard; same CF fall-through |

Runnable sanity script (copy-paste, no framework required):

```bash
set -e
check() {
  local label="$1" expected_exit="$2" input="$3"
  printf '%s' "$input" > /tmp/t.json
  if jq -e . /tmp/t.json >/dev/null 2>&1; then actual=0; else actual=$?; fi
  if [[ "$actual" == "$expected_exit" ]] || { [[ "$expected_exit" == "nonzero" ]] && [[ "$actual" != 0 ]]; }; then
    echo "pass: $label (exit $actual)"
  else
    echo "FAIL: $label (got exit $actual, expected $expected_exit)" >&2
    exit 1
  fi
}

check "valid JSON object"       0       '{"name":"x"}'
check "JSON missing key"        0       '{"other":"x"}'
check "null literal"            nonzero 'null'
check "plaintext"               nonzero 'Hook not found'
check "HTML"                    nonzero '<html>503</html>'
check "empty file"              nonzero ''
check "empty object"            0       '{}'
check "empty array"             0       '[]'
echo "All 8 cases pass."
```

All 8 rows must match the table. Any deviation indicates either a jq version mismatch or a plan-vs-reality drift worth investigating before proceeding.

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

- **Vendor happy-path regression**: the guard runs BEFORE the `jq -r` so if the vendor returns valid JSON (99.9% case), behavior is unchanged. Verified by shell unit test row 1.
- **Hiding real auth failures**: the guard only fires when HTTP is 2xx AND body is non-JSON. HTTP 401 (expired token) is still handled upstream — the LinkedIn workflow creates its issue on HTTP 401 before reaching the `jq -r` line. Non-2xx paths are unchanged.
- **Phantom-issue creation**: `exit 0` means a truly broken vendor would cause multiple successful-looking runs. Mitigation: the CF workflow's Terraform-managed notification policy is the primary alert; this workflow is the backup. For LinkedIn, the next weekly cron will retry. If the vendor stays broken for >1 week, the operator will notice the warning pile.
- **Silent downstream action (LinkedIn)**: without the corrected placement (between lines 90-91, not 92-93), a non-JSON 2xx body would execute the `gh issue close` block on lines 96-104 *before* the `jq -r` crash. This would auto-close any open "token expired" issue as "token is valid" based on unvalidated data. The corrected placement prevents this. Verified by code-path reading during deepen.
- **Edge-case drift**: `jq -e .` semantics are pinned to jq 1.8.1 (per learning). GitHub-hosted runners currently ship jq 1.7 as of 2026-04. The guard's behavior on `null`/empty/plaintext is stable across these versions; `{}` and `[]` passing the guard is also stable. If `ubuntu-latest` ever upgrades to a breaking jq release, the Phase 5 end-to-end dispatch catches it.

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
- **Not** changing the retry / single-shot semantics of either workflow.
- **Not** adding a test framework for GitHub Actions workflow steps. Out of scope; shell sanity cases + `actionlint` + end-to-end dispatch are sufficient for this bug class.
- **Not** touching `web-platform-release.yml:177-190` (the health-check loop). See Deferrals below.

## Latent-Bug-Class Sweep

Full grep of `jq -r` across `.github/workflows/*.yml`:

| File:Line | Context | Risk | Action |
|---|---|---|---|
| `web-platform-release.yml:132-134` | `exit_code`, `reason`, `tag` on `/hooks/deploy-status` body | protected by `jq -e` guard added in PR #2226 | none (already fixed) |
| `web-platform-release.yml:177-190` | `status`, `version`, `supabase`, `uptime` on `/health` body | **latent** — `curl -sf` with `\|\| echo ""` would pass through HTML-on-200 to `jq -r` | **follow-up** (see Deferrals) |
| `scheduled-linkedin-token-check.yml:93` | `.name` on `/v2/userinfo` body | **target of this plan** | fixed here |
| `scheduled-cf-token-expiry-check.yml:64-67` | `.result[].expires_at` on CF API body | **target of this plan** | fixed here |
| `codeql-to-issues.yml:41-50` | `number`, `rule_id`, etc. on `gh api --jq` output | safe — `gh` CLI output, not vendor API; `gh` guarantees well-formed JSON or non-zero exit | none |
| `reusable-release.yml:155-157` | `.title`, `.labels`, `.body` on `gh pr view --json` output | safe — same `gh` CLI guarantee | none |

## Deferrals

- **Follow-up issue:** apply `jq -e .` guard to `web-platform-release.yml:177-190` (the `Verify deploy health and version` step). The health-check loop reads `/health` via `curl -sf "https://app.soleur.ai/health"` with `|| echo ""` as the error fallback. `curl -sf` returns non-zero on HTTP 4xx/5xx (so errors become `""` and fall into the `[ -z "$HEALTH" ]` branch), **but** a 200-with-HTML body (Cloudflare edge page served on a healthy-looking upstream) would pass through `-sf` unaltered and then crash `jq -r` under the default strict shell. This is the same bug class as #2214 and #2236.

  **Re-evaluation criteria:** file the issue before merging this PR. Target milestone: Phase 3: Make it Sticky (matches #2236). Out of scope for this PR because (a) #2236 specifically named only the two scheduled workflows, (b) the health-check is inside a retry loop so behavior would shift from `continue` to `exit 0 -> step failure` and would need retry-loop-style handling (the PR #2226 pattern), and (c) keeping scope tight reduces review surface.

  **Action in tasks.md Phase 4:** create the follow-up issue with `gh issue create` before committing this PR, per AGENTS.md `wg-when-an-audit-identifies-pre-existing`. The issue reference then appears in this PR's commit message as a `Ref #<new>` follow-up marker.

## References

- Issue #2236 (this issue)
- Issue #2214 (original bug class)
- PR #2226 (canonical fix + rule codification; commit `6e7b4181`)
- AGENTS.md rule `cq-ci-steps-polling-json-endpoints-under`
- Learning `knowledge-base/project/learnings/bug-fixes/2026-04-15-signed-get-verify-step-tolerate-non-json-bodies.md`
- Failed release run `24411905995` (historical evidence)
