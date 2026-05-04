---
title: "fix: add actions/checkout to scheduled-oauth-probe so the notify-ops-email composite action resolves"
type: bug-fix
classification: ops-only-prod-write
issue: 3118
related_issues: [2997, 3030]
related_prs: [3030, 1420, 1578, 1674]
requires_cpo_signoff: false
date: 2026-05-04
deepened: 2026-05-04
---

## Enhancement Summary

**Deepened on:** 2026-05-04
**Sections enhanced:** Overview, Decision, Implementation Phase 2/4, Risks
**Research lanes used:** Context7 `actions/checkout` v4 docs (sparse-checkout syntax), live `gh api` verification of pin SHA `34e114876b0b11c390a56381ad16ebd13914f8d5` for `v4.3.1`, peer-workflow pin survey (64 sites consistent), git-history origin verification (composite action vs workflow-introducer separation), Phase 4.6 User-Brand Impact halt gate (passed).

### Key Improvements

1. **Origin precision corrected.** The composite action `notify-ops-email/action.yml` was added in PR #1420/#1578 (commit f14469e3, 2026-04-06), not in PR #3030. PR #3030 introduced the *consuming* workflow without a checkout step. Both the user's bug description and my initial plan conflated these — the bug was that PR #3030 added a consumer of an existing action without the required checkout.
2. **Pin SHA live-verified.** `gh api repos/actions/checkout/git/ref/tags/v4.3.1` returned `34e114876b0b11c390a56381ad16ebd13914f8d5` — exact match with the pin used by 64 sites across the workflow family. No drift; the plan's pin recommendation is canonical.
3. **Sparse-checkout syntax verified against actions/checkout v4 README.** The pattern `sparse-checkout: |\n  .github/actions` + `sparse-checkout-cone-mode: false` is the documented form for non-cone partial checkouts. Confirmed via Context7 `/actions/checkout` query.
4. **Acceptance grep tightened.** Original grep `grep -q 'actions/checkout' "$f"` would match a YAML comment too (false positive). Tightened to match the actual `uses:` line.

### New Considerations Discovered

- **Cone-mode default trap.** `sparse-checkout-cone-mode` defaults to `true`. With cone mode + `.github/actions` as a nested path, behavior depends on cone semantics (cone matches top-level dirs and their `.gitignore`-style descendants). The simpler, predictable form is `sparse-checkout-cone-mode: false` with the explicit subdirectory path. The plan's recommendation already disables cone mode; this section now records the rationale.
- **Two-comment-style pin variation.** Of the 64 peer pin sites, 62 use `# v4.3.1` and 2 use `# v4` (with the same SHA). Use `# v4.3.1` for the new sites — it survives a future `actions/checkout` v4.3.1 → v4.4.0 dependabot bump audit (the comment is the human-readable pin label).
- **Heartbeat workflow has a single `heartbeat` job** (line 29). Checkout step goes at the top of that job (above whatever the current first step is). No multi-job ambiguity.

## Overview

Run #25306473263 (2026-05-04 07:25 UTC) on `.github/workflows/scheduled-oauth-probe.yml` failed at the `Email notification (failure)` step with:

```text
##[error]Can't find 'action.yml', 'action.yaml' or 'Dockerfile' under
'/home/runner/work/soleur/soleur/.github/actions/notify-ops-email'.
Did you forget to run actions/checkout before running your local action?
```

The root cause is structural: the workflow references the local composite action `./.github/actions/notify-ops-email` but never runs `actions/checkout@v4` before it, so the runner's working tree is empty and the action's `action.yml` is not on disk.

The probe step itself, the `File or comment on tracking issue` step, and the `Auto-close stale issue` step all succeed without checkout because they only call `gh`/`curl` against external HTTP endpoints — the missing-checkout failure mode only surfaces when a step references a local-path action.

This bug shipped latent in PR #3030 (commit 67407444, merged 2026-04-29) — that PR introduced the *consuming workflow* without a checkout step. The composite action it consumes was added 23 days earlier in PR #1420/#1578 (commit f14469e3, 2026-04-06). The bug only fired today because 2026-05-04 07:25 UTC was the first real probe failure to enter the email branch. Until that branch executed, the missing-checkout was invisible.

### Research Insights

**Verified facts (live, this session):**

- `gh api repos/actions/checkout/git/ref/tags/v4.3.1` returns SHA `34e114876b0b11c390a56381ad16ebd13914f8d5`. The pin is current and matches `scheduled-terraform-drift.yml:37` and 62 other peer sites verbatim.
- `git log --diff-filter=A -- .github/actions/notify-ops-email/action.yml` returns commit `f14469e3` (PR #1420/#1578, 2026-04-06) — the composite action predates the oauth-probe workflow by 23 days.
- `grep -h 'actions/checkout@' .github/workflows/*.yml | sort | uniq -c` shows 64 total sites, 100% on the same SHA.
- Context7 `/actions/checkout` confirms `sparse-checkout-cone-mode: false` is the documented form for non-cone partial checkouts. README excerpt: `# Default: true` for cone mode; setting it to `false` enables single-file or non-top-level patterns.

**References:**

- actions/checkout README sparse-checkout section: <https://github.com/actions/checkout#sparse-checkout>
- GitHub Actions composite-action local-path semantics: requires the runner workspace to contain the action's directory at job-prepare time, which is what `actions/checkout` populates. Without checkout, `${GITHUB_WORKSPACE}` is empty.

## Research Reconciliation — Spec vs. Codebase

The user-supplied bug description contains one factual error that must be reconciled before implementation, and one secondary finding the description did not anticipate.

| Spec claim | Reality | Plan response |
|---|---|---|
| `.github/actions/notify-ops-email` does not exist (`ls .github/actions/` empty) | The composite action exists at `.github/actions/notify-ops-email/action.yml` on `main` and on this branch. PR #3030 created it; 22 other workflows already consume it (see Implementation Phase 1 for the inventory). The runner error is not a missing-file error — it is a missing-checkout error from the runner's empty working tree. | Reject the user's preferred fix (inline the Resend curl). Use the established pattern instead: add `actions/checkout@v4` before the email step. Rationale in §Decision below. |
| Only `scheduled-oauth-probe.yml` has this bug | `scheduled-cloud-task-heartbeat.yml` line 180 also calls `uses: ./.github/actions/notify-ops-email` AND has zero `actions/checkout` steps in the file (verified via `grep -L 'actions/checkout' .github/workflows/scheduled-*.yml`). It is a sibling latent bug in the same class, just one step removed from firing. | Fix both files in the same PR. Per AGENTS.md `wg-when-fixing-a-workflow-gates-detection` (retroactive gate application), bugs of the same class found during a fix go in the same PR, not deferred. |

## Decision: actions/checkout vs inline curl

The user's preferred fix is to inline the Resend curl call as a `run:` step using `secrets.RESEND_API_KEY`, citing PR #1420/#1578/#1674 (Resend standardization).

This plan rejects that approach in favor of adding `actions/checkout@v4` before the email step. The reasoning:

1. **22 peer workflows already use the composite action.** Inlining would create a one-off pattern in this single workflow, increasing surface area for drift (e.g., the next sender-domain change would need to be made in two places). The composite was introduced precisely to avoid copy-pasted curl-to-Resend blocks; bypassing it locally re-introduces the duplication that PR #1420/#1578/#1674 consolidated.
2. **The cited PRs are evidence FOR the composite, not against it.** PR #1420/#1578 standardized on Resend (vs Discord), and PR #1674 consolidated the Resend account onto a single sender domain. The composite action is the consolidation surface — that is its job.
3. **The actual root cause is missing checkout, not the action.** The user's diagnosis ("the local action does not exist") is inverted. The action exists; the runner working tree does not. The fix targets the actual cause.
4. **Cost is one-line.** `- uses: actions/checkout@<sha-pin> # v4.x.y` plus `with: { sparse-checkout: '.github/actions' }` (or unconditional) costs ~2 lines and ~2-3 seconds of runner time. The composite action is checkout-shaped; matching its precondition is cheaper than rewriting the call site.
5. **Sibling workflow consistency.** `scheduled-cloud-task-heartbeat.yml` has the same latent bug. If we fix oauth-probe by inlining, we'd either (a) leave the heartbeat broken, (b) inline both (doubling drift surface), or (c) inline oauth-probe and add checkout to heartbeat (split convention). Adding checkout to both is the only choice that holds the existing 22-workflow convention.

The user's "out of scope" note (don't change the probe shell script; don't touch cron cadence) is honored. The fix is purely additive to the workflow's step list.

## User-Brand Impact

**If this lands broken, the user experiences:** an actual prod auth-flow regression (a real user-facing sign-in outage) goes undetected for the operator inbox path — the issue-filing branch still runs, but the email-paging branch fails silently. Operators who rely on the email page (mobile, off-hours, away from GitHub) miss the alert window.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — this is a notification-pipeline reliability fix, not a credentials change. `secrets.RESEND_API_KEY` flow is unchanged; no new secrets enter scope.

**Brand-survival threshold:** none. The probe itself, issue-filing, and auto-close branches are unaffected; only the email side-channel is broken. Tracking issue #3118 still gets opened/commented on every failure (the current run did open it), so the on-GitHub paging path works. Email is the redundant channel, not the only channel.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `.github/workflows/scheduled-oauth-probe.yml` has an `actions/checkout` step before the `Email notification (failure)` step at line 204.
- [x] `.github/workflows/scheduled-cloud-task-heartbeat.yml` has an `actions/checkout` step before the `notify-ops-email` step at line 180 (sibling latent bug).
- [x] Both checkouts use the same SHA-pinned version as peer workflows (`actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1` per `scheduled-terraform-drift.yml:37`).
- [x] No other changes to either workflow file (probe shell unchanged, cron unchanged, subject/body content unchanged, masked secret usage unchanged).
- [ ] PR body includes `Closes #3118` (verified status: OPEN; the workflow auto-close branch will fire after the next green probe run, but the PR closing the GitHub issue at merge is independent — the runbook tracking issue is what #3118 represents).
- [ ] `Ref #2997` in PR body (parent design issue for the OAuth probe).
- [x] Verification grep (tightened to match the `uses:` line, not a stray comment):
    ```bash
    for f in .github/workflows/scheduled-oauth-probe.yml .github/workflows/scheduled-cloud-task-heartbeat.yml; do
      grep -qE '^\s*-?\s*uses:\s*actions/checkout@' "$f" \
        || { echo "MISSING checkout in $f"; exit 1; }
    done
    ```

### Post-merge (operator)

- [ ] Run `gh workflow run scheduled-oauth-probe.yml --ref main` (workflow_dispatch enabled per line 17).
- [ ] Poll `gh run list --workflow=scheduled-oauth-probe.yml --limit 1 --json databaseId,status,conclusion` until `status=completed`.
- [ ] If `conclusion=success`: probe is green, no email fires (the `if: steps.probe.outputs.failure_mode != ''` gate is false), and the auto-close branch fires on issue #3118. Verify with `gh issue view 3118 --json state` returns `CLOSED`.
- [ ] If `conclusion=failure` (probe genuinely fails again — transient network is plausible per the 07:25 UTC precedent): inspect the run; the `Email notification (failure)` step MUST now show `conclusion=success` (or `success` with `::warning::` from the composite action's HTTP-non-2xx branch — the composite never fails the step). The `Can't find 'action.yml'` error MUST NOT appear anywhere in the log.
- [ ] Run `gh workflow run scheduled-cloud-task-heartbeat.yml --ref main` to confirm the heartbeat workflow's notify path also dispatches cleanly (or, if it would page on success-path, confirm the workflow's `if: failure()` gate is unchanged).

## Implementation Phases

### Phase 1: Inventory (verification, no edits)

Confirm the two-file scope with the exact greps stated in the bug description and the reconciliation table:

```bash
# All consumers of the local composite action
grep -rln "uses: \./\.github/actions/notify-ops-email" .github/workflows/ | sort

# Of those, which are missing actions/checkout entirely
grep -L "actions/checkout" $(grep -rln "uses: \./\.github/actions/notify-ops-email" .github/workflows/) 2>&1
```

Expected output: exactly two files lacking checkout — `scheduled-oauth-probe.yml` and `scheduled-cloud-task-heartbeat.yml`. If a third file appears, expand the fix to cover it before opening the PR (do not defer — same-class bug, same PR per `wg-when-fixing-a-workflow-gates-detection`).

The SHA pin `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1` is verified against `scheduled-terraform-drift.yml:37` and is the canonical pin used by 7+ peer workflows in the same family.

### Phase 2: Edit `scheduled-oauth-probe.yml`

Insert a checkout step as the first step of the `probe` job (above line 32 `- id: probe`). Sparse-checkout is sufficient and minimizes runner I/O — the only path consumed is `.github/actions/`:

```yaml
    steps:
      - name: Checkout (for local composite action)
        uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
        with:
          sparse-checkout: |
            .github/actions
          sparse-checkout-cone-mode: false
      - id: probe
        env:
          ...
```

Rationale for sparse-checkout:

- The probe shell does not read any other repo files (only `curl` to external hosts and `gh` for issue ops).
- The issue-filing step uses `printf` heredocs and `gh issue` — no repo files.
- The auto-close step uses `gh issue list/close` only.
- Only the email step needs a repo path on disk: `.github/actions/notify-ops-email/action.yml`.

If a future step needs broader checkout, swap to a full checkout in that follow-up — do not pre-bloat now (YAGNI). Note the cone-mode disable: cone mode requires patterns to be directory globs and is overkill here.

### Phase 3: Edit `scheduled-cloud-task-heartbeat.yml`

Same pattern. Read the file first (Edit tool requires it). Insert the same checkout step as the first step of the job that contains the `notify-ops-email` call. If the job already has a non-checkout first step, the checkout goes above it.

If the heartbeat workflow has multiple jobs and only one references the composite action, only the consuming job needs the checkout. Verify by reading the file before writing.

### Phase 4: Local validation

```bash
# Static YAML validity (no runner needed)
for f in .github/workflows/scheduled-oauth-probe.yml .github/workflows/scheduled-cloud-task-heartbeat.yml; do
  python3 -c "import yaml; yaml.safe_load(open('$f'))" && echo "OK: $f"
done

# Acceptance grep (matches the uses: line specifically, not stray comments)
for f in .github/workflows/scheduled-oauth-probe.yml .github/workflows/scheduled-cloud-task-heartbeat.yml; do
  grep -qE '^\s*-?\s*uses:\s*actions/checkout@' "$f" \
    || { echo "MISSING checkout in $f"; exit 1; }
done && echo "All target workflows have checkout."

# Confirm SHA pin matches peer convention (no version drift)
grep -h 'actions/checkout@' .github/workflows/*.yml | sort -u
# Expected: a single pinned-SHA line; flag any v3 / unpinned tags as drift.
```

### Phase 5: PR + post-merge verification

Standard `/ship` flow. After merge, dispatch the workflow per the `### Post-merge (operator)` checklist above.

Issue #3118 will close via the workflow's own auto-close branch on the next green probe run (line 216-238). The PR's `Closes #3118` is the intent declaration; the runtime closure happens via the post-merge dispatched run. Both paths converge on the same closure, so a single `Closes #3118` in the PR body is correct (not `Ref #3118`) — the merge itself ships the fix that allows the auto-close to fire on the very next run, which we trigger via workflow_dispatch.

## Test Scenarios

This is an infrastructure-only change (CI workflow YAML). Per AGENTS.md `cq-write-failing-tests-before`, infrastructure-only tasks are exempt from the TDD gate. The verification path is dispatch-and-observe (Phase 5), not unit tests.

The empirical test exists: every probe failure since 2026-04-29 reproduces the bug, and the post-merge `gh workflow run` dispatch is the GREEN check.

## Risks

- **Sparse checkout pattern syntax.** `sparse-checkout` accepts newline-separated paths; `sparse-checkout-cone-mode: false` disables cone mode (default `true`). Verified against `actions/checkout` v4 README via Context7 query in this deepen pass. If a future maintainer adds a step that reads files outside `.github/actions/`, sparse mode will silently elide them — the new step would fail with `No such file or directory`, not a sparse-mode warning. Mitigation: a comment on the checkout step explaining why it's narrow (`# only need .github/actions for the local composite-action resolution at the email step`).
- **Cone-mode trap.** With cone mode left as default `true`, `.github/actions` (a nested path) may behave unpredictably across `actions/checkout` minor versions; the docs are explicit that non-cone patterns require `sparse-checkout-cone-mode: false`. The plan locks cone mode to false to be version-stable across future v4.x bumps.
- **Pin drift across the workflow family.** The 7-workflow sample showed `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1` consistently. If a different peer uses a different pin, the file we add to should match its closest sibling rather than introducing a third pin. Phase 4's `grep -h | sort -u` catches this.
- **Auto-close race.** The auto-close branch (lines 216-238) fires when `failure_mode == ''`. If the post-merge dispatch hits a transient network_error like 07:25 UTC, the issue stays open and the email branch becomes the test surface. That is fine — the email step is now the thing under test, and a clean dispatch (issue-filing succeeds, email succeeds, auto-close skipped) still proves the fix. Re-dispatch until a green run lands to also exercise the auto-close.
- **Underlying probe failure not addressed.** This plan does NOT fix the 07:25 UTC `network_error` reaching `api.soleur.ai/auth/v1/authorize?provider=google` from a GitHub runner. That was a transient (probe is green from local host now, per the bug description). If it recurs, the fix is in the auth surface or the GHA-to-Supabase network path, not in this PR. Tracking via #3118 (which auto-closes on next green) is the existing mechanism; if it fails to auto-close after this PR ships, the underlying transient escalated to a real outage and needs its own ticket.
- **GitHub Actions cron deprioritization** (~1h vs `*/15`) is explicitly out of scope per the user. Documented here only so a future reader doesn't assume this PR was meant to address it.

## Files to Edit

- `.github/workflows/scheduled-oauth-probe.yml` — add `actions/checkout@<pinned-sha>` step at the top of `jobs.probe.steps` (above line 32).
- `.github/workflows/scheduled-cloud-task-heartbeat.yml` — same pattern, in the job consuming `notify-ops-email` at line 180.

## Files to Create

None.

## Open Code-Review Overlap

None. Verified via `gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json` and `jq -r --arg path '.github/workflows/scheduled-oauth-probe.yml' '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"'` returning empty (and the same query for the heartbeat workflow returning empty).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. CI workflow file is not user-facing; no UI, no copy, no pricing, no compliance, no payments. The fix is mechanically scoped to "add a checkout step" and matches an established 22-workflow precedent.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. The section above is filled with concrete artifacts (`single-user sign-in regression goes unalerted via email`) and a non-`TBD` threshold (`none`).
- Sparse-checkout patterns are newline-separated; `sparse-checkout-cone-mode: false` is required if any pattern is a non-directory or partial path. The pattern `.github/actions` is directory-only so cone mode would also work, but explicit non-cone mode is more grep-able for future readers.
- The post-merge `gh workflow run` will succeed even on probe failure (since `Set up job` + probe + issue-comment + email-now-working = job conclusion success when the workflow uses `if: failure_mode != ''` rather than `if: failure()` for the email step). The actual GREEN signal for this PR is "no `Can't find 'action.yml'` error in the log," not "run conclusion success." Operator must read the log, not just the conclusion badge.
- Issue #3118's auto-close depends on the workflow's `Auto-close stale issue (probe green)` step at line 216-238. That step runs `gh issue close` — confirm `permissions.issues: write` (line 25) is preserved on the PR diff. The current diff is additive (adding a checkout step) so permissions are untouched, but a reviewer should verify.
