---
name: anthropic-preflight credit-balance soft-skip
date: 2026-05-11
issues: [3605]
parent_pr: 3559
branch: feat-preflight-credit-balance-3605
draft_pr: 3606
brainstorm: knowledge-base/project/brainstorms/2026-05-11-preflight-credit-balance-bundle-brainstorm.md
spec: knowledge-base/project/specs/feat-preflight-credit-balance-3605/spec.md
status: ready
detail_level: MINIMAL
type: fix
requires_cpo_signoff: false
---

# Plan: anthropic-preflight credit-balance soft-skip (#3605)

## Overview

One-line fix to `.github/actions/anthropic-preflight/action.yml`. Extends the
existing HTTP 400 soft-skip branch from matching only the spend-cap message
(`specified API usage limits`, source #2715) to also match the credit-balance
message (`credit balance is too low`, source #3605). Operationally identical
class — API unavailable for billing reasons, action is identical (soft-skip +
`::warning::`).

Spec is fully specified (FR1-3, TR1-4, V-B1-3). This plan is thin by design:
the brainstorm + spec are the source of truth; the plan adds only execution
ordering and the synthesized-fixture verification recipe.

Track A (#3604 manual workflow_dispatch validation) is **not in this PR**.
Dispatch is already in flight on `main` as workflow run `25688627107`; tracks
are independent per the brainstorm's Key Decisions table.

## User-Brand Impact

- **If this lands broken, the user experiences:** every Anthropic-using
  workflow continues to go red on credit-low days (unchanged from today's
  hard-fail behavior), and `email-on-failure` keeps firing alert noise.
  Worst-case for the fix itself: if the grep over-matches a genuine outage
  whose 400 body coincidentally contains one of the two literal strings, the
  loop silently decays for one tick until the next preflight succeeds.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A
  — composite action runs on `RUNNER_TEMP`, body is truncated to 500B and
  `sk-*` redacted before logging, no user-data path is touched.
- **Brand-survival threshold:** none — operator-facing CI hygiene, no
  end-user surface. `USER_BRAND_CRITICAL=false` per brainstorm Phase 0.1.
  Sensitive-path scope-out: threshold none, reason: composite action
  `.github/actions/anthropic-preflight/action.yml` is operator-tooling-only,
  not a user-data surface; no GDPR/auth/secrets handling beyond existing
  `sk-*` redaction (unchanged).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|------------|---------|---------------|
| `grep -q "specified API usage limits"` on line 46 | Confirmed verbatim at `.github/actions/anthropic-preflight/action.yml:46` | Replace with `grep -qE "(specified API usage limits\|credit balance is too low)"` per TR1 |
| Warning text on line 48 covers only spend-cap | Confirmed: `"::warning::Anthropic spend cap exhausted — skipping Claude steps. Body: $BODY"` | Replace per TR2 with both-class wording |
| Source comment block above line 46 cites only #2715 | Confirmed at lines 41-42 | Update to cite #2715 (spend-cap) + #3605 (credit-balance) and both literal strings per TR2 |
| Composite action exposes `ok` output, exits 1 on unexpected | Confirmed at lines 9-12, line 57 | No change — TR3 |
| No workflow under `.github/workflows/` depends on the warning text | Verified: callers consume `ok` output only, not the warning string | No workflow edits — TR4 |

## Files to Edit

- `.github/actions/anthropic-preflight/action.yml` — lines 41-48 region (one
  comment block + one grep clause + one warning string)

## Files to Create

None.

## Open Code-Review Overlap

None. Composite action is a 1-line bug fix on a single file with no open
code-review issues touching it.

## Implementation Phases

### Phase 1 — Edit (single commit)

1. Update the source-comment block above line 46 to cite both issues and both
   literal strings (TR2). Suggested wording:

   ```bash
   # Verbatim error bodies from Anthropic API when API is unavailable for
   # billing reasons — source: #2715 (2026-04-21, "specified API usage limits")
   # and #3605 (2026-05-11, "credit balance is too low"). Both are soft-skips
   # by design — operationally identical class (API unreachable, not a payload
   # bug). See brainstorm 2026-05-11-preflight-credit-balance-bundle.
   ```

2. Replace line 46's grep clause (TR1):

   ```bash
   elif [[ "$HTTP_CODE" == "400" ]] && grep -qE "(specified API usage limits|credit balance is too low)" "$BODY_FILE"; then
   ```

3. Replace line 48's warning text (TR2):

   ```bash
   echo "::warning::Anthropic API unavailable (spend cap or credit balance) — skipping Claude steps. Body: $BODY"
   ```

4. Commit message: `fix(ci): soft-skip anthropic-preflight on credit-balance 400 (#3605)`

### Phase 2 — Verify (V-B1, local sanity)

Synthesize three `BODY_FILE` fixtures (per `cq-test-fixtures-synthesized-only`
— do NOT paste real API response bodies) and confirm the grep clause decides
correctly:

```bash
# Run from the worktree root.
set -e
TMP=$(mktemp -d)

# Fixture 1: spend-cap (must match → soft-skip)
printf '%s\n' '{"type":"error","error":{"type":"invalid_request_error","message":"Your account has reached the specified API usage limits for this month."}}' > "$TMP/spend-cap.json"

# Fixture 2: credit-balance (must match → soft-skip)
printf '%s\n' '{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the API. Please go to Plans & Billing to upgrade or purchase credits."}}' > "$TMP/credit-balance.json"

# Fixture 3: generic 400 (must NOT match → hard-fail preserved per FR2)
printf '%s\n' '{"type":"error","error":{"type":"invalid_request_error","message":"messages: at least one message is required"}}' > "$TMP/generic-400.json"

for f in spend-cap credit-balance generic-400; do
  if grep -qE "(specified API usage limits|credit balance is too low)" "$TMP/$f.json"; then
    echo "$f → MATCH (soft-skip)"
  else
    echo "$f → NO MATCH (hard-fail)"
  fi
done

rm -rf "$TMP"
```

Expected output:

```
spend-cap → MATCH (soft-skip)
credit-balance → MATCH (soft-skip)
generic-400 → NO MATCH (hard-fail)
```

If any line disagrees, abort and re-read the grep clause for a literal-string
typo. Do NOT proceed to Phase 3.

### Phase 3 — Ship

1. Mark draft PR #3606 ready for review:
   `gh pr ready 3606`
2. Confirm PR body includes `Closes #3605` (NOT in the title — `wg-use-closes-n-in-pr-body-not-title-to`).
   If missing, edit via `gh pr edit 3606 --body-file <body.md>`.
3. Run preflight gates per `wg-after-marking-a-pr-ready-run-gh-pr-merge`:
   `gh pr checks 3606 --watch` and wait for required checks green.
4. Merge via `gh pr merge 3606 --squash --delete-branch` once all required
   checks pass.
5. Cleanup: from main, run `bun run plugins/soleur/scripts/cleanup-merged.ts`
   to drop the worktree.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `.github/actions/anthropic-preflight/action.yml` line 46 uses
  `grep -qE "(specified API usage limits|credit balance is too low)"` (TR1).
- [ ] Line 48 warning text reads `"::warning::Anthropic API unavailable (spend cap or credit balance) — skipping Claude steps. Body: $BODY"` (TR2).
- [ ] Comment block above the grep cites #2715 + #3605 and both literal strings (TR2).
- [ ] No other files changed in the diff (verify via `git diff --name-only main..HEAD` — expect only `action.yml` plus the brainstorm/spec/plan/tasks docs already committed).
- [ ] No new `inputs:` or `env:` keys on the composite action (TR3).
- [ ] No `.github/workflows/*` files changed (TR4).
- [ ] PR body contains `Closes #3605` (NOT in title — `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] Phase 2 fixture sanity-run printed the expected three-line output.
- [ ] Required CI checks green.

### Post-merge

- [ ] Next time credit balance triggers the message in production, confirm
  `email-on-failure` does NOT fire and `::warning::` surfaces in the run UI (V-B3).
- [ ] Issue #3605 auto-closes on merge via `Closes #3605` link in PR body.

## Test Strategy

Verification is local-only via synthesized fixtures (Phase 2). No new test
harness is added — the composite action is exercised in production by every
scheduled cron tick, and the synthesized fixtures cover all three decision
branches the diff touches (spend-cap match, credit-balance match, generic
no-match). Per `cq-test-fixtures-synthesized-only`, no real API response
bodies are committed.

`tsc`/`bun test` are not relevant — the change is shell inside a YAML
composite action. The `bash -c '<snippet>'` form was considered for a syntax
check but rejected: GNU `grep -qE` is portable, the regex contains no
metachars (`(a|b)` is the only construct), and Phase 2's fixture run
exercises the exact form on real input.

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Over-match: genuine API-outage 400 contains one of the literal strings | Very low | Both strings are operator-billing English specific to Anthropic's billing surface — would not appear in upstream gateway/network 4xx bodies. Literal substring match, no metachars. |
| Under-match: Anthropic changes the exact wording of the credit-balance message | Low | If wording drifts, hard-fail returns and operator gets the same alert noise we have today. Re-fix is a 1-line update. Accept. |
| Workflow consumers depend on the warning text | None | Verified — callers consume `ok` output only (see Research Reconciliation). |
| Synthesized fixture in Phase 2 is wrong shape | Low | The grep clause only reads `BODY_FILE` as text; the action does not parse the JSON. Any string containing the two literal substrings reproduces the decision. The fixtures use JSON shape merely for realism. |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — operator-facing CI composite-action
shell change touching no user-data path, no auth surface, no schema, no API
route. `USER_BRAND_CRITICAL=false` was set explicitly in brainstorm Phase 0.1.

## Sharp Edges

- The grep clause uses `-qE` (extended regex). The only regex construct is
  `(a|b)` alternation — no `.`, `*`, `[`, `?`, etc. If a future change adds a
  third pattern containing regex metachars, escape them or split into
  separate `grep -q` branches; the literal-substring property is load-bearing
  for the over-match risk analysis above.
- Phase 2's fixture verification is a manual local sanity check, not a
  committed test. If the fixture run is skipped, the PR loses its only
  pre-merge functional verification — the diff is too small for any other
  gate to catch a typo. Do NOT skip Phase 2.
- PR #3606 already exists as a draft with commit `1f3cee58` (brainstorm +
  spec). The implementation commit goes on top of that — do NOT create a
  new PR; do NOT amend `1f3cee58`.
- `Closes #3605` belongs in the PR body, not the title
  (`wg-use-closes-n-in-pr-body-not-title-to`). The title should follow
  the existing commit-message convention (e.g.,
  `fix(ci): soft-skip anthropic-preflight on credit-balance 400`).
- Track A (#3604) is **not** coupled to this PR. The compound-promote
  workflow_dispatch already fired on main as run `25688627107`. Do not
  bundle the #3604 close into this PR — independent tracks per brainstorm.

## Source

- Issue: #3605 (closed by this PR)
- Spec: `knowledge-base/project/specs/feat-preflight-credit-balance-3605/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-11-preflight-credit-balance-bundle-brainstorm.md`
- Parent PR: #3559 (merged 2026-05-11)
- Sibling issue: #3604 (validation track, independent)
- Precedent: #2715 (original spend-cap soft-skip, 2026-04-21)
