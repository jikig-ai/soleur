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
deepened: 2026-05-11
---

# Plan: anthropic-preflight credit-balance soft-skip (#3605)

## Enhancement Summary

**Deepened on:** 2026-05-11
**Sections enhanced:** Overview, Research Reconciliation, Implementation Phases, Risks
**Research:** Live `gh` verification of #3605 body, #2715 issue close-date, #2717 implementing-commit SHA, caller surface enumeration (18 workflows consuming the action), Phase 2 fixture sanity-run executed against the prescribed grep clause.

### Key Improvements

1. **Verbatim error-string verification.** Pulled the exact 400 body from `gh issue view 3605` — the prescribed substring `"credit balance is too low"` is a literal substring of the real message (`"Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits."`). No regex metachar surface.
2. **Phase 2 recipe pre-flighted live.** Ran the synthesized-fixture script from plan Phase 2 against the exact grep clause prescribed by TR1 — output matches the prescribed expectation (`MATCH / MATCH / NO MATCH`). The recipe is known-good; the implementer is just confirming the edit landed.
3. **Caller surface confirmed.** `rg -l "anthropic-preflight" .github/workflows/` returns 18 workflows. TR4 ("no workflow changes") has high blast-radius if violated — confirms why callers must continue to consume only `ok` output, not the warning string.
4. **Precedent commit pinned.** The original spend-cap soft-skip shipped via commit `02d42324` (PR #2717, merged 2026-04-21) closing issue #2715. The existing comment block in `action.yml:42` cites `#2715` correctly as the source issue.
5. **Empty draft-PR body identified.** PR #3606's body is the auto-generated placeholder `"Draft PR created automatically. Content will be added as work progresses."` — must be replaced before ready-for-review per `wg-use-closes-n-in-pr-body-not-title-to` AND to give reviewers context.

### Live verification artifacts

```bash
$ gh issue view 3605 --json title,state | jq -r .title
ci(anthropic-preflight): soft-skip on "credit balance is too low" — same class as spend-cap

$ gh issue view 2715 --json closedAt,state | jq -r '.state, .closedAt'
CLOSED
2026-04-21T15:24:47Z

$ git log --all --grep="#2715" --pretty=format:"%h %ad %s" --date=short
02d42324 2026-04-21 chore(ci): add Anthropic spend-cap preflight guard to Claude workflows (#2717)

$ rg -l "anthropic-preflight" .github/workflows/ | wc -l
18

$ # Phase 2 fixture run against the prescribed grep clause (executed at deepen time)
spend-cap -> MATCH (soft-skip)
credit-balance -> MATCH (soft-skip)
generic-400 -> NO MATCH (hard-fail)
```

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
| No workflow under `.github/workflows/` depends on the warning text | Verified at deepen time: 18 workflows `uses: ./.github/actions/anthropic-preflight` and all consume only the `ok` output (`if: steps.preflight.outputs.ok == 'true'` pattern). Warning text is logged-only. | No workflow edits — TR4 |
| Verbatim 400 body from issue #3605 contains `"credit balance is too low"` | Confirmed — full body: `{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits."},"request_id":"req_011Caw4H2tdGWrZaTgoG2CvX"}`. Literal substring match has zero regex-metachar surface. | Use `grep -qE "(specified API usage limits\|credit balance is too low)"` per TR1 — substring-only alternation. |

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

**Important.** Draft PR #3606's body is currently the auto-generated placeholder
`"Draft PR created automatically. Content will be added as work progresses."`
(verified at deepen time via `gh pr view 3606`). It MUST be replaced with a
real body containing `Closes #3605` before marking ready.

1. Author the PR body. Suggested content:

   ```bash
   cat > /tmp/pr-3606-body.md <<'EOF'
   ## Summary

   Extends the existing HTTP 400 soft-skip branch in
   `.github/actions/anthropic-preflight/action.yml` to match the
   "credit balance is too low" message in addition to the spend-cap message.
   Operationally identical class — API unavailable for billing reasons,
   identical handling (soft-skip + `::warning::`).

   One-line shell change: `grep -q "specified API usage limits"` →
   `grep -qE "(specified API usage limits|credit balance is too low)"`.
   Comment and warning text updated to cite both issues.

   ## Test plan

   - [x] Synthesized BODY_FILE fixtures (spend-cap, credit-balance,
     generic 400) verified against the new grep clause locally — output
     matches: MATCH / MATCH / NO MATCH.
   - [ ] CI required checks green on PR #3606.
   - [ ] Post-merge: confirm `::warning::` surfaces and `email-on-failure`
     does NOT fire on the next credit-low event.

   ## Source

   - Spec: `knowledge-base/project/specs/feat-preflight-credit-balance-3605/spec.md`
   - Plan: `knowledge-base/project/plans/2026-05-11-fix-preflight-credit-balance-soft-skip-plan.md`
   - Precedent: #2715 / commit 02d42324 (original spend-cap soft-skip, 2026-04-21)

   Closes #3605
   EOF
   gh pr edit 3606 --body-file /tmp/pr-3606-body.md
   ```

   `Closes #3605` is in the **body**, not the title — per
   `wg-use-closes-n-in-pr-body-not-title-to`.

2. Mark draft PR #3606 ready for review:
   `gh pr ready 3606`
3. Run preflight gates per `wg-after-marking-a-pr-ready-run-gh-pr-merge`:
   `gh pr checks 3606 --watch` and wait for required checks green.
4. Merge via `gh pr merge 3606 --squash --delete-branch` once all required
   checks pass.
5. Cleanup: from main, run `bun run plugins/soleur/scripts/cleanup-merged.ts`
   to drop the worktree.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `.github/actions/anthropic-preflight/action.yml` line 46 uses
  `grep -qE "(specified API usage limits|credit balance is too low)"` (TR1).
- [x] Line 48 warning text reads `"::warning::Anthropic API unavailable (spend cap or credit balance) — skipping Claude steps. Body: $BODY"` (TR2).
- [x] Comment block above the grep cites #2715 + #3605 and both literal strings (TR2).
- [x] No other files changed in the diff (verify via `git diff --name-only main..HEAD` — expect only `action.yml` plus the brainstorm/spec/plan/tasks docs already committed).
- [x] No new `inputs:` or `env:` keys on the composite action (TR3).
- [x] No `.github/workflows/*` files changed (TR4).
- [ ] PR body contains `Closes #3605` (NOT in title — `wg-use-closes-n-in-pr-body-not-title-to`).
- [x] Phase 2 fixture sanity-run printed the expected three-line output.
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
- `set -e` interaction is already addressed by the action: line 24 of
  `action.yml` explicitly omits `-e` (uses `set -uo pipefail`) so the
  `grep -qE` non-match exit-1 (the spend-cap-or-credit-balance branch's
  inverted decision) does NOT abort the step — branch selection is
  intentional via the `if/elif/else` chain. Do NOT add `set -e` to the
  `run:` block during editing, or the spend-cap path will short-circuit
  the step before its `::warning::` and `ok=false` output land. The plan's
  Phase 2 fixture run is a local sanity check that bypasses this concern
  (no `set -e` in the recipe).
- The `grep -qE` regex uses parentheses + `|` only — both standard ERE.
  Tested on the runner's GNU grep at deepen time; alternation works as
  expected. Do not switch to BRE (`grep -q "\(a\|b\)"`) — that's the
  inverted-escaping form and is harder to read.

## Source

- Issue: #3605 (closed by this PR)
- Spec: `knowledge-base/project/specs/feat-preflight-credit-balance-3605/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-11-preflight-credit-balance-bundle-brainstorm.md`
- Parent PR: #3559 (merged 2026-05-11)
- Sibling issue: #3604 (validation track, independent)
- Precedent: #2715 (original spend-cap soft-skip, 2026-04-21)
