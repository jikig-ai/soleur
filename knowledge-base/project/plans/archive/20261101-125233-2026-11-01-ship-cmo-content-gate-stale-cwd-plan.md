---
title: "ship-cmo-content-gate: resolve PR head ref instead of HEAD for trailer/diff scope"
type: fix
date: 2026-11-01
slug: ship-cmo-content-gate-stale-cwd
branch: feat-one-shot-11682-cmo-gate-stale-cwd
issue: 11682
closes: 11682
---

# ship-cmo-content-gate: resolve PR head ref instead of HEAD for trailer/diff scope

`.claude/hooks/ship-cmo-content-gate.sh` scopes its trailer log and marketing diff
to `"${BASE_REF}..HEAD"` / `"${BASE_REF}...HEAD"` (lines 92/98). When the session
roots at the main checkout (`WORK_DIR` = the repo's main worktree), `HEAD` is
`main`, the range is empty, and a feat PR whose branch carries a valid
`Reviewed-By-CMO:` trailer is denied anyway. Reproduced against PR #11652 in the
issue: trailer commit `0d8713888f` exists; the hook denied from the main checkout
and passed from a worktree.

## User-Brand Impact

- **If this lands broken, the user experiences:** none — the hook gates Soleur's
  own ship flow; a wrong TIP resolution could only weaken one internal gate.
- **If this leaks, the user's [data / workflow / money] is exposed via:** n/a.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** hook/CI-gate machinery; blast radius is
  one internal deny verdict, not a user-facing surface.

*Scope-out override:* `threshold: none, reason: the diff touches a repo-internal
PreToolUse hook and its test only.`

## Observability

```yaml
liveness_signal:
  what:            the hook's own deny verdicts — a false deny is the failure
  cadence:         per `gh pr ready`/`gh pr merge` invocation
  alert_target:    the denied tool call's reason text (surfaced to the operator)
  configured_in:   .claude/hooks/ship-cmo-content-gate.sh

error_reporting:
  destination:     jq deny payload + emit_incident ledger
  fail_loud:       "has not run the Phase 5.5 CMO Content-Opportunity Gate" deny reason

failure_modes:
  - mode:          false deny — session rooted at main checkout (the #11682 bug)
    detection:     the test suite's new main-checkout row; a deny reason on a PR
                   whose branch carries the trailer
    alert_route:   the denied call itself

logs:
  where:           incidents ledger via emit_incident (hr-before-shipping rule)
  retention:       repo ledger file lifetime

discoverability_test:
  command:         bash .claude/hooks/ship-cmo-content-gate.test.sh
  expected_output: PASS=7 FAIL=0
```

## Research Insights

**Premise validation:** #11682 OPEN, no linked/closed-by PRs; the only body ref
(#11652) is the verified reproduction. `.claude/hooks/ship-cmo-content-gate.sh`
present at :92 (`git log BASE..HEAD` for `Reviewed-By-CMO`) and :98
(`git diff BASE...HEAD` for the marketing touch); `.claude/hooks/ship-cmo-content-gate.test.sh`
present (90 lines, gh-mock + scratch-repo harness).

**Mechanism:** the hook already resolves `PR_NUM` (:61-65) and `BASE_REF`
(:85-89). The fix adds a TIP resolution after `BASE_REF`: `gh pr view $PR_NUM
--json headRefName` → `origin/<headRef>` if it verifies, else
`refs/pull/<N>/head` if it verifies, else `HEAD` (current behavior preserved).
Both scoped reads then use `${TIP}`.

**Edge cases:** `headRefName` empty/`gh` unreachable → `origin/` never verifies
(`rev-parse` fails) → falls to `refs/pull/` → HEAD — the pre-fix behavior, no
worse. `refs/pull/N/head` not fetched locally → skipped (read-only; no network
fetch added to a PreToolUse hook). Same-named local branch shadowing is avoided
by using `origin/<name>` (the pushed ref is what the PR sees).

**Related:** the defect is the second occurrence of the stale-cwd class (the
issue was filed from the #11678 arc's own denied-then-diagnosed run).

## Implementation

### Step 1 — Hook fix

`.claude/hooks/ship-cmo-content-gate.sh`, after `BASE_REF` resolution (~:89):

```bash
# When the session roots at the main checkout, HEAD is main and the branch's
# trailer/diff never enter the range — resolve the PR's head ref instead.
PR_HEAD=$(gh pr view "$PR_NUM" --json headRefName --jq .headRefName 2>/dev/null || true)
TIP=""
if [[ -n "$PR_HEAD" ]] && git rev-parse --verify --quiet "origin/${PR_HEAD}" >/dev/null 2>&1; then
  TIP="origin/${PR_HEAD}"
elif git rev-parse --verify --quiet "refs/pull/${PR_NUM}/head" >/dev/null 2>&1; then
  TIP="refs/pull/${PR_NUM}/head"
else
  TIP="HEAD"
fi
```

Then substitute `${TIP}` for `HEAD` in the two scoped reads (:92, :98).

### Step 2 — Regression test

`.claude/hooks/ship-cmo-content-gate.test.sh`:

- mock `gh`: add a `*pr view 123 --json headRefName --jq .headRefName*` arm
  echoing `${MOCK_PR_HEAD:-feat-branch}`.
- new row: simulate the main-checkout session — after the trailer commit on
  `feat-branch`, `git update-ref refs/remotes/origin/feat-branch <tip>` and
  `git checkout main`; run the hook with cwd=WORKDIR (HEAD==main) → expect
  pass (empty output), where the pre-fix hook denied.
- keep the deny row as the counter-case: same fixture but no trailer → still deny.

## Files to Edit

- `.claude/hooks/ship-cmo-content-gate.sh` — +11 lines TIP resolution, 2 substitutions
- `.claude/hooks/ship-cmo-content-gate.test.sh` — mock arm + 2 rows (~15 lines)

## Files to Create

- none

## Open Code-Review Overlap

Probe against label `code-review` for the two file paths — recorded in
`decision-challenges.md`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "#11682 CMO-gate stale-cwd fix" | Steps 1–2 | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|-----------|------------------|---------|
| TIP resolution (Step 1) | "fix #11682 CMO-gate stale-cwd"; issue fix note: "resolve the PR's head ref via gh pr view --json headRefName" | asked |
| regression rows (Step 2) | issue AC: "the gate finds a Reviewed-By-CMO trailer on the PR head when the session root is the main checkout" | asked |

## Domain Review

Engineering-only (hook machinery). No product/marketing surface change — the
gate's semantics are unchanged; it now sees the same trailer the branch carries.

## Acceptance Criteria

- [ ] From a main-checkout cwd (HEAD==main), a feat PR whose `origin/<headRef>`
  carries `Reviewed-By-CMO:` is NOT denied (suite row green).
- [ ] The same fixture with no trailer still denies.
- [ ] `.claude/hooks/ship-cmo-content-gate.test.sh` reports `FAIL=0`.
- [ ] `Closes #11682` on the PR body.
