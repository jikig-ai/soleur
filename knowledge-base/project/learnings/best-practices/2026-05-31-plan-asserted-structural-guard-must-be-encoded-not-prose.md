# Learning: A plan-asserted "structurally prevented" safety invariant must be encoded in the executable guard, not left to prose interpretation

## Problem

PR (#4681) extended `/soleur:postmerge` Phase 3.6 to auto-resolve a stopped Sentry
issue via an HTTP PUT. The plan's `## User-Brand Impact` named the worst case —
false-resolving a *still-firing* issue hides a live production error — and the
Domain Review asserted the design "structurally prevented" it. The `/work`
implementation, however, encoded the guard as:

```bash
if [[ -n "$SENTRY_RW_TOKEN" && "$ISSUE_STATUS" != "resolved" ]]; then  # WRONG
```

This checks only token-present + not-already-resolved. It never compares
`lastSeen` to the deploy timestamp — the entire definition of "stopped firing."
A still-firing issue returns `status:"unresolved"` with a recent `lastSeen`, so
the guard fires and PUTs `resolved`. The "structural prevention" lived only in
the surrounding prose ("Auto-resolve runs in this branch only", "Never
auto-resolve in this branch"), not in the `if`. All four post-implementation
review agents (security-sentinel, pattern-recognition, code-quality,
git-history) independently flagged it as the top finding.

## Solution

Derive a mechanical boolean from the data and gate on it, so the dangerous
branch is structurally unreachable:

```bash
ISSUE_STOPPED=false
if [[ "$ISSUE_STATUS" == "resolved" || "$ISSUE_STATUS" == "ignored" ]]; then
  ISSUE_STOPPED=true
elif [[ -n "$ISSUE_LASTSEEN" && "$ISSUE_LASTSEEN" != "null" ]]; then
  LASTSEEN_EPOCH=$(date -d "$ISSUE_LASTSEEN" +%s 2>/dev/null || echo 9999999999)  # fail-safe far-future
  DEPLOY_EPOCH=$(date -d "$DEPLOY_TS" +%s 2>/dev/null || echo 0)
  (( LASTSEEN_EPOCH < DEPLOY_EPOCH )) && ISSUE_STOPPED=true
fi
# guard now requires the positive mechanical signal:
if [[ -n "$SENTRY_RW_TOKEN" && "$ISSUE_STOPPED" == "true" && "$ISSUE_STATUS" != "resolved" \
      && "$ISSUE_ID" =~ ^[A-Za-z0-9_-]+$ ]]; then
```

Fail-safe defaults (unparseable timestamp → far-future epoch → `ISSUE_STOPPED`
stays false) ensure ambiguous data never auto-resolves.

## Key Insight

When a plan claims a safety property is **structurally prevented**, that claim is
a binding requirement on the *executable* code, not on the prose around it. A
guard conditioned on a *proxy* (`status != "resolved"`) instead of the *actual
signal* (`lastSeen < deploy`) is correct only by coincidence — the still-firing
case satisfies the proxy. `/work` should treat every "structurally prevented" /
"never happens" assertion in a plan as: *which single computed boolean makes the
bad branch unreachable, and is it in the `if`?* If the determination is described
as a human-read interpretation of output (as the postmerge interpretation
bullets were), that is prose-gating, not structural prevention — encode it.

This is the same defect class as the review catalogue's "single-literal gate over
a multi-member union" and "prose safety contract not encoded in guard" — the fix
is always to bind the real signal to a variable and gate on it.

## Session Errors

1. **Plan-asserted structural invariant landed as prose-only guard (the main learning).** — Recovery: derived a mechanical `ISSUE_STOPPED` boolean from `lastSeen` vs deploy timestamp and gated the PUT on it; verified still-firing→skip, stopped→PUT, malformed-id→skip via `bash -n` + behavioral runs. — Prevention: `/work` and `/plan` should treat "structurally prevented" / "never auto-X" assertions as a directive to encode the determining signal in the executable guard; review-spawn prompts should name the safety invariant and ask "is it in the `if`, or only in the prose?"
2. **Write-boundary PreToolUse hook blocked the plan file** (contained `doppler secrets set` + a Sentry UI click-path). — Recovery: added the documented `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` opt-out, valid because the Sentry mint + Doppler write are genuinely operator-only. — Prevention: already hook-enforced + documented; no workflow change needed.
3. **Task subagent tool unavailable in the planning env** — the plan skill's parallel research/review agents could not spawn. — Recovery: ran research, premise validation, and gate checks inline. — Prevention: pre-existing environment constraint; plan skill already degrades gracefully.
4. **`sleep 30 && tail` to poll a background task was blocked by the harness.** — Recovery: used the Monitor tool with an `until` loop. — Prevention: already enforced by the harness block message + `hr-monitor-not-run-in-background-for-polling`; no change needed.

## Tags
category: best-practices
module: postmerge, work, review
issue: 4681
