# fix(ci): apply jq -e guard to web-platform-release.yml health-check loop

**Issue:** [#2286](https://github.com/jikig-ai/soleur/issues/2286)
**Branch:** `feat-one-shot-jq-guard-release-yml`
**Date:** 2026-04-17
**Type:** Bug fix (CI / shell hardening)
**Scope:** Single file, ~6 lines added
**Related:** #2214 (first instance), #2236 (scheduled-workflow sweep), #2283 (review that flagged this)

## Enhancement Summary

**Deepened on:** 2026-04-17
**Scope:** Targeted (trivial single-file 6-line fix; full agent fan-out is YAGNI here).
**Research surfaces consulted:**

- AGENTS.md rule `cq-ci-steps-polling-json-endpoints-under` (canonical pattern)
- `knowledge-base/project/learnings/bug-fixes/2026-04-15-jq-guard-placement-before-side-effects.md` (guard-placement nuance)
- `knowledge-base/project/learnings/bug-fixes/2026-04-15-signed-get-verify-step-tolerate-non-json-bodies.md` (original #2214 learning)
- Full-file `grep jq` sweep of `web-platform-release.yml` (confirm no missed sites)
- Cross-workflow `grep jq -r` sweep of `.github/workflows/*.yml` (confirm no new latent cases for this PR's scope)

### Key Validations from Research

1. **Guard placement is side-effect-aware (not just `jq -r`-adjacent).** Per the 2026-04-15 placement learning: place the guard before any code that trusts the body, not merely before the first `jq -r`. In this loop, the only side effect past the parse is `exit 0` on a successful version+supabase match at line 187 — reachable only via three successful `jq -r` calls, so placing the guard at the top of the `else` branch (before line 177) is correct and sufficient. No additional side effects (no `gh issue close`, no webhook writes, no state mutations) live in the `$HEALTH` success path.
2. **`continue` is correct for retry loops.** The placement learning explicitly says: "Prefer `exit 0` + `::warning::` over `continue` in single-shot workflows — retry loops mask vendor state." This IS a retry loop (30 attempts × 10s = 300s window), so `continue` is the right choice. The issue body's prescription matches.
3. **All four `jq -r` sites in the loop are covered by a single guard.** The guard placed at the top of the `else` branch (line 176) gates lines 177, 179, 181, and 190. No per-call guards needed.
4. **Other `jq .` sites in the file are already safe:**
   - Line 156 (`jq .` in default case of `Verify deploy script completion`): already gated by the upstream `jq -e .` at line 127.
   - Line 186 (`jq .` in success branch): only reachable after three successful `jq -r` parses — JSON-parseable by construction.
   - Line 195 (`jq . 2>/dev/null || echo "$HEALTH"`): self-guarded via `2>/dev/null` fallback.
5. **Cross-workflow sweep confirms this PR's scope is minimal.** `jq -r` grep across `.github/workflows/*.yml` shows guarded sites in `scheduled-cf-token-expiry-check.yml` (line 63 comment confirms guard), `scheduled-linkedin-token-check.yml` (line 94 comment confirms guard), and a handful of call sites in `codeql-to-issues.yml` and `reusable-release.yml`. Latter two are NOT in #2286's scope — if they need review, that's a separate audit ticket (per the retroactive-sweep pattern in the 2026-04-15 placement learning: "defer new finds via issues, don't balloon scope").
6. **No skill-based fan-out warranted.** No frontend, no Rails, no agent-native, no security surface. The rule-compliance check (`cq-ci-steps-polling-json-endpoints-under`) is the entire review surface and it's already satisfied.

### New Considerations Discovered

- **Add a comment cross-reference to the in-file twin guard (line 127).** Reviewers can diff the two blocks visually and confirm shape-identity in one eye movement. Added to acceptance criteria.
- **Acceptance criterion: guard must be at the top of the `else` branch, not per-`jq -r`-call.** Prevents a well-meaning implementer from adding four micro-guards (each before a specific `jq -r`) — more code, same behavior, diverges from the same-file pattern.
- **No risk of introducing a new shellcheck finding.** The guard pattern at lines 127-131 already passed shellcheck; the new block is byte-equivalent in shape.

## Overview

The `web-platform-release.yml` health-check retry loop (lines 172-201, targeted inner block 177-196) calls `jq -r` on `/health` response bodies under `bash -e` without the canonical `jq -e .` guard mandated by AGENTS.md rule `cq-ci-steps-polling-json-endpoints-under`. This is the third instance of the same bug class, discovered during the #2236 latent-bug-class sweep but scoped out because (a) #2236 named only the two scheduled workflows, (b) this path has retry-loop semantics (not single-shot), and (c) keeping PR #2283 scope tight.

The `curl -sf ... || echo ""` fallback correctly maps HTTP 4xx/5xx to an empty body (handled by the `[ -z "$HEALTH" ]` branch). But a **200-with-HTML** response — for example, a Cloudflare edge error page served through a healthy-looking upstream — passes through `-sf` unaltered and crashes `jq -r` via `set -e` before the retry loop can react.

**Fix:** Insert a `jq -e . >/dev/null 2>&1` pre-check inside the `else` branch (i.e., after we know `$HEALTH` is non-empty) that `continue`s the loop on non-JSON bodies with a clear warning. The canonical pattern already exists **in the same file** at lines 124-131 (Verify deploy script completion step) — this plan mirrors it verbatim.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| Bug lives at `web-platform-release.yml:177-190` | Confirmed: `jq -r '.status // empty'` at line 177, `jq -r '.version // empty'` at 179, `jq -r '.supabase // empty'` at 181, `jq -r '.uptime // "unknown"'` at 190. Also `jq .` at 186 (success log — inside the success branch, so non-JSON cannot reach it) and `jq . 2>/dev/null \|\| echo "$HEALTH"` at 195 (already guarded with `2>/dev/null`). | Guard covers all four `jq -r` sites. Lines 186 and 195 are already safe and need no guard. |
| Canonical pattern exists in same file at lines 117-131 | Confirmed: lines 124-131 show the exact `jq -e .` + `continue` + warning shape, with the rationale comment referencing #2214. | Plan mirrors this pattern byte-for-byte with its own comment referencing #2214, #2236, and the rule ID. |
| `actionlint` required to pass | Present in lefthook pre-push; also runs in CI via `.github/workflows/actionlint.yml`. | Add actionlint invocation to acceptance criteria. |

No spec/codebase divergences. The issue description is accurate.

## Implementation

### Files to modify

- `.github/workflows/web-platform-release.yml` (lines 172-201 — inject guard inside the existing retry loop)

### Files to create

- None.

### The Change

Inside the existing `else` branch (line 176, `else` of `if [ -z "$HEALTH" ]; then ... else ... fi`), **before** the first `jq -r` call at line 177, insert:

```bash
# Tolerate non-JSON 200-OK bodies (e.g., Cloudflare edge HTML served over a
# healthy upstream). Without this guard, jq's parse error under bash -e kills
# the step before the retry loop can react (#2214, #2236).
# AGENTS.md: cq-ci-steps-polling-json-endpoints-under.
# Mirrors the twin guard at lines 124-131 in the same file.
if ! echo "$HEALTH" | jq -e . >/dev/null 2>&1; then
  echo "Attempt $i/$HEALTH_POLL_MAX_ATTEMPTS: non-JSON body from /health, retrying"
  sleep "$HEALTH_POLL_INTERVAL_S"
  continue
fi
```

**Resulting control flow** inside the loop body:

1. `curl` fetch → `$HEALTH`
2. Empty-body branch (unchanged): log + fallthrough to `sleep` at line 198
3. Non-JSON branch (**new**): log + `continue` (the `sleep` runs inside the guard so the retry cadence is preserved)
4. JSON-parseable branch: existing `$STATUS` / `$DEPLOYED_VERSION` / `$SUPABASE_STATUS` / `$UPTIME` logic runs unchanged

### Why `continue` with an inline `sleep` (not fallthrough)

The existing empty-body branch falls through to the loop-tail `sleep "$HEALTH_POLL_INTERVAL_S"` at line 198. The new non-JSON guard uses an explicit `sleep + continue` so the guard block is self-contained and mirrors the same-file reference at lines 127-131. Both approaches preserve retry cadence; mirroring the established pattern minimizes reviewer cognitive load and matches what `cq-ci-steps-polling-json-endpoints-under` prescribes (`continue` on non-JSON, not exit).

### Why not `jq empty`

Per AGENTS.md rule `cq-ci-steps-polling-json-endpoints-under`: `jq empty` passes `null` through to field parsers. `jq -e .` is the mandated guard. Using `jq empty` here would be a rule violation caught in review.

### Why not drop `-e` from the step shell

Per the same rule: dropping `-e` (using `bash` instead of `bash -e` implicitly via the step shell) silences real failures elsewhere in the loop. The GitHub Actions default shell for `run:` is `bash -e`, which is correct — the guard is the right defense, not shell-option relaxation.

## Acceptance Criteria

- [x] `.github/workflows/web-platform-release.yml` has a `jq -e . >/dev/null 2>&1` guard placed at the **top of the `else` branch** (immediately after line 176's `else`), before the first `jq -r` call on `$HEALTH` at line 177.
- [x] Guard is a **single block** gating all four `jq -r` sites (lines 177, 179, 181, 190) — not four per-call guards.
- [x] Guard uses `continue` (retry loop semantics), not `exit 0` or `exit 1`. This matches the placement learning (`2026-04-15-jq-guard-placement-before-side-effects.md`): "Prefer `exit 0` + `::warning::` over `continue` in single-shot workflows — retry loops mask vendor state" — and this IS a retry loop.
- [x] Guard comment references `#2214`, `#2236`, AGENTS.md rule `cq-ci-steps-polling-json-endpoints-under`, **and the in-file twin at lines 124-131** so reviewers can diff them visually.
- [x] Guard emits a warning log that includes the attempt counter (`$i/$HEALTH_POLL_MAX_ATTEMPTS`) so a failing run is triage-able from the Actions log.
- [x] Guard block includes its own `sleep "$HEALTH_POLL_INTERVAL_S"` before `continue`, mirroring lines 127-131 of the same file.
- [x] `actionlint` passes (`actionlint .github/workflows/web-platform-release.yml`) with zero new findings.
- [x] `shellcheck` passes on the `run:` block (actionlint invokes shellcheck automatically).
- [x] No other lines in the step (165-201) are modified — scope is strictly the new guard block.
- [x] Side-effect audit: confirm the only code past the guard with an observable effect is `exit 0` at line 187 — reachable only via successful JSON parsing. No `gh`, no webhook, no state write is ungated by the guard.

## Test Scenarios

This is a CI/workflow change that runs only in GitHub Actions, so "tests" here are: (a) static lint of the workflow file, and (b) local shell-logic simulation of the three response shapes (empty, HTML, JSON). No unit-test-framework change is needed; no new dependency is introduced.

### Scenario 1: JSON 200-OK with correct version (success path unchanged)

- Given `$HEALTH` = `{"status":"ok","version":"1.2.3","supabase":"connected"}` and `$VERSION=1.2.3`
- When the loop iterates
- Then `jq -e .` succeeds → existing logic runs → `exit 0` fires on line 187

### Scenario 2: HTML 200-OK (new guard catches this)

- Given `$HEALTH` = `<html><body>Cloudflare edge error</body></html>` (the bug case)
- When the loop iterates under `bash -e`
- Then `jq -e .` fails (exit 1 from jq, captured by `if !`) → warning logged → `sleep` → `continue`
- **Without the fix:** `jq -r '.status // empty'` crashes with `parse error`, `bash -e` kills the step, retry loop never gets another attempt.

### Scenario 3: Empty body (existing branch unchanged)

- Given `$HEALTH` = `""` (curl `-sf` mapped 5xx to empty via `|| echo ""`)
- When the loop iterates
- Then `[ -z "$HEALTH" ]` is true → warning logged → falls through to loop-tail `sleep`
- The new guard is inside the `else` branch, so empty-body flow is unchanged.

### Scenario 4: JSON 200-OK with version mismatch (existing fallthrough unchanged)

- Given `$HEALTH` = `{"status":"ok","version":"1.2.2"}` and `$VERSION=1.2.3`
- Then `jq -e .` succeeds → `STATUS=ok` → `DEPLOYED_VERSION=1.2.2` ≠ `$VERSION` → uptime log → loop-tail `sleep`
- Unchanged behavior.

### Scenario 5: JSON 200-OK with `status!=ok` (existing `jq . 2>/dev/null` at line 195 unaffected)

- Given `$HEALTH` = `{"status":"starting"}` — parseable JSON
- Then `jq -e .` succeeds → `STATUS=starting` → line 195 runs `echo "$HEALTH" | jq . 2>/dev/null || echo "$HEALTH"` → loop-tail `sleep`
- Unchanged behavior. Line 195 is already tolerant via `2>/dev/null || echo "$HEALTH"`, so it needs no further guard.

### Local verification commands

```bash
# Static lint
actionlint .github/workflows/web-platform-release.yml

# Shell-logic smoke test (simulate Scenario 2 — the bug case)
HEALTH='<html>edge error</html>'
if ! echo "$HEALTH" | jq -e . >/dev/null 2>&1; then
  echo "non-JSON detected (expected)"
fi
# Expected output: "non-JSON detected (expected)"
# If jq parse error leaks, the guard is wrong.
```

## Rollback Plan

Single-commit, single-file change. Rollback = `git revert <sha>`. No database migrations, no infrastructure provisioning, no runtime config — purely a guard in a CI workflow `run:` block.

## Non-Goals / Out of Scope

- Refactoring the wider `web-platform-release.yml` health-check step (e.g., extracting to a composite action). The `cq-ci-steps-polling-json-endpoints-under` rule mandates the guard pattern inline.
- Auditing other `.github/workflows/*.yml` files for the same bug class. #2236 handled the scheduled workflows; any remaining instances would be new tickets, not part of this fix.
- Adding a unit-test framework for workflow shell logic. Out of scope; actionlint + shellcheck + the local smoke test above are sufficient for a 6-line change.

## Alternative Approaches Considered

| Approach | Pros | Cons | Verdict |
|---|---|---|---|
| **Mirror lines 124-131 pattern (chosen)** | Identical shape to same-file reference; reviewer cognitive load is zero; rule-compliant. | None. | Chosen. |
| Drop `bash -e` for this step only | 1-line change. | Silences all real failures in the loop; explicitly forbidden by `cq-ci-steps-polling-json-endpoints-under`. | Rejected. |
| Use `jq empty` instead of `jq -e .` | Slightly shorter. | Passes `null` to field parsers — explicitly forbidden by the rule. | Rejected. |
| Parse with `jq -r '.status // empty' 2>/dev/null` (per-call silencing) | Minimal diff. | 4 sites to guard; swallows legitimate errors; diverges from same-file pattern; still crashes `bash -e` because pipe status captures jq's exit. | Rejected. |
| Switch curl to `-f` without `-s` and inspect HTTP code | More informative logs. | Larger rewrite; unrelated to the bug; HTML-over-200 case still gets past `-f`. | Rejected (out of scope). |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is a 6-line CI workflow hardening that mirrors an already-accepted pattern in the same file. No product, marketing, legal, revenue, or customer-experience surface is touched. No new user-facing UI, no new dependency, no new environment variable, no new secret, no runtime behavior change in success or normal-failure paths.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Typo in the guard breaks `bash -e` parse | Very low | Step fails at next release | actionlint + shellcheck catch syntax errors pre-merge. |
| Guard misfires on legitimate JSON | Very low | Step retries unnecessarily, eventually times out with current message | `jq -e .` is conservative; legitimate JSON always parses. Worst case is one spurious retry cycle (`$HEALTH_POLL_INTERVAL_S` = 10s). |
| Guard masks a real upstream outage | Low | Deploy verification takes up to `MAX_ATTEMPTS * INTERVAL_S` = 300s before failing | Matches existing empty-body behavior (same failure window); final `::error::` message at line 200 names the symptom. |

## Implementation Steps

1. [x] Read `.github/workflows/web-platform-release.yml` lines 165-201 (context around the target step).
2. [x] Insert the guard block inside the `else` branch, before line 177's `jq -r`.
3. [x] Run `actionlint .github/workflows/web-platform-release.yml` locally — must exit 0.
4. [x] Run the local smoke test from "Test Scenarios → Local verification commands" — guard must catch the HTML body.
5. [ ] Commit with subject `fix(ci): apply jq -e guard to web-platform-release.yml health-check loop (#2286)`.
6. [ ] Push to `feat-one-shot-jq-guard-release-yml`.
7. [ ] Open PR with `Closes #2286` in the body; reference #2214, #2236, #2283 in the description.
8. [ ] Post-merge: the next release triggers `web-platform-release.yml` naturally — no manual `gh workflow run` needed, but monitor the first post-merge release run's "Verify deploy health and version" step to confirm the guard is visible in the run log.

## Pre-Submission Checklist

- [x] Title is searchable and descriptive: `fix(ci): apply jq -e guard to web-platform-release.yml health-check loop`
- [x] Acceptance criteria are measurable (6 concrete checks).
- [x] Test scenarios cover the bug case (Scenario 2) and all three unchanged branches (1, 3, 4, 5).
- [x] Rollback plan is trivial and documented.
- [x] Alternatives table shows rule-compliance reasoning.
- [x] No browser-automation steps (pure CI change, no UI).
- [x] No deferred items → no follow-up issues to file.
- [x] Links: #2286 (this issue), #2214 (rule origin), #2236 (prior sweep), #2283 (discovery PR).
