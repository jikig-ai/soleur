---
title: "fix: kb-drift-walker workflow unable to resolve Doppler CLI action SHA"
type: bug-fix
classification: ci-workflow-fix
lane: single-domain
branch: feat-one-shot-fix-kb-drift-walker-doppler-sha
created: 2026-05-21
status: planned
requires_cpo_signoff: false
---

# fix: kb-drift-walker workflow unable to resolve Doppler CLI action SHA

## Overview

The `.github/workflows/kb-drift-walker.yml` nightly job has been failing during job setup (~2 s elapsed) because its `dopplerhq/cli-action` SHA pin does not exist in the upstream repo. GitHub Actions resolves action references at `Set up job` time; a bad SHA aborts the run before any step executes, including `Install Doppler CLI` itself.

The bad pin is `dopplerhq/cli-action@517441f1eaf80f64b34d0e4dca44c0aacb13a3a3 # v3` at line 43. The canonical v3 SHA, verified via `gh api repos/dopplerhq/cli-action/git/refs/tags/v3 --jq .object.sha`, is `014df23b1329b615816a38eb5f473bb9000700b1`. Six other call sites across `cla-evidence.yml`, `cla-evidence-timestamp.yml`, `web-platform-release.yml` (×3), `scheduled-realtime-probe.yml`, `scheduled-ux-audit.yml`, and `scheduled-community-monitor.yml` already use the canonical SHA, so the fix is to normalize the outlier.

Failed run for the record: [Actions run 26209907780](https://github.com/jikigai-ai/soleur/actions/runs/26209907780). Log header shows:

```text
##[error]Unable to resolve action `dopplerhq/cli-action@517441f1eaf80f64b34d0e4dca44c0aacb13a3a3`, unable to find version `517441f1eaf80f64b34d0e4dca44c0aacb13a3a3`
```

This is a 1-line edit. No behavior change beyond "the action resolves and the existing `prd_kb_drift_walker` Doppler flow runs again".

## User-Brand Impact

- **If this lands broken, the user experiences:** the user experiences no direct symptom — KB-drift walker is an internal nightly observability job (`scripts/kb-drift-walker.sh` → `POST /api/internal/kb-drift-ingest`). The operator-facing consequence is continued nightly green-checkmark-on-empty: drift detector reports nothing because the walker never ran. Brand-survival exposure is bounded by operator-only observability lag.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no leak vector. The fix replaces one hex string with another in a public workflow file; no secret movement, no schema change, no data egress.
- **Brand-survival threshold:** `none`, reason: internal observability job; no user-facing surface; no PII/billing/auth path touched by the fix. (Threshold-none + no sensitive-path touched per `preflight` Check 6 canonical regex — scope-out bullet not required.)

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| Bad SHA at `kb-drift-walker.yml:43` | Verified by `grep -rn 517441f1... .github/`: 1 occurrence | Edit that one line |
| Canonical SHA is `014df23b...` | Verified by `gh api repos/dopplerhq/cli-action/git/refs/tags/v3` | Use this SHA verbatim |
| Other call sites already use canonical SHA | Verified by `grep -rn 014df23b... .github/`: 8 occurrences across 7 files | No sibling files need editing |
| Failure mode is "action resolution at job-setup" | Confirmed via `gh run view 26209907780 --log-failed`: `Unable to resolve action` before any step ran | Fix is sufficient; no downstream change |
| Subsequent steps (auth, signing, ingest) work post-fix | Unverified — out of scope per source brief | Verify only "past Install Doppler CLI step"; further failures = separate issue |

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned no issue body referencing `.github/workflows/kb-drift-walker.yml`.

## Files to Edit

- `.github/workflows/kb-drift-walker.yml:43` — replace
  `uses: dopplerhq/cli-action@517441f1eaf80f64b34d0e4dca44c0aacb13a3a3 # v3`
  with
  `uses: dopplerhq/cli-action@014df23b1329b615816a38eb5f473bb9000700b1 # v3`

## Files to Create

None.

## Implementation Phases

### Phase 1 — Apply the SHA correction

1. Read `.github/workflows/kb-drift-walker.yml` line 43 (already read at plan time).
2. Edit line 43: replace bad SHA with canonical SHA. Preserve the `# v3` trailing comment and the leading indentation.
3. Confirm the resulting diff is exactly one changed line:

   ```bash
   git diff --stat .github/workflows/kb-drift-walker.yml
   # expect: 1 file changed, 1 insertion(+), 1 deletion(-)
   ```

4. Confirm no other file in the repo still references the bad SHA:

   ```bash
   grep -rn "517441f1eaf80f64b34d0e4dca44c0aacb13a3a3" .github/ || echo "BAD SHA fully removed"
   ```

5. Confirm the workflow YAML still parses (best-effort, non-blocking if `actionlint` not installed):

   ```bash
   command -v actionlint >/dev/null && actionlint .github/workflows/kb-drift-walker.yml || echo "actionlint not installed; skip"
   ```

### Phase 2 — Commit, push, open PR

1. `git add .github/workflows/kb-drift-walker.yml`
2. Commit message: `fix(ci): pin kb-drift-walker doppler action to canonical v3 SHA`
3. Push the branch.
4. Open PR. Body must reference the failed run (`Ref: Actions run 26209907780`) and explain the single-line nature of the fix. No `Closes #N` because no tracking issue was filed for this specific failure.

### Phase 3 — Post-merge verification (automated)

Trigger the workflow on `main` and confirm it gets past the `Install Doppler CLI` step. Subsequent failures (Doppler auth, signing key fetch, ingest POST) are out of scope per the source brief — they would be a separate issue.

```bash
# Wait for the merge commit to be on main (or pass --ref <merge-sha>)
gh workflow run kb-drift-walker.yml --ref main

# Poll for the most recent run of this workflow
RUN_ID=$(gh run list --workflow=kb-drift-walker.yml --limit 1 --json databaseId --jq '.[0].databaseId')

# Watch it to completion (will exit non-zero if any step fails; we re-classify below)
gh run watch "$RUN_ID" --exit-status || true

# Verify the "Install Doppler CLI" step has a recorded conclusion (any conclusion
# means the action resolved — success, failure, or skipped; the fix is for
# resolution, not for the step's body succeeding).
gh run view "$RUN_ID" --json jobs --jq '
  .jobs[].steps[]
  | select(.name == "Install Doppler CLI")
  | {name, conclusion, started_at}
'
```

Pass condition: the `Install Doppler CLI` step has a `started_at` timestamp AND a non-null `conclusion`. Any value of `conclusion` means the action resolved and ran — even `failure` here would indicate a different, out-of-scope bug.

Reject condition (the bug we are fixing): `gh run view` shows the run failed at `Set up job` with `Unable to resolve action` in the log AND the `Install Doppler CLI` step has no `started_at`.

This verification step is automatable end-to-end via `gh`; the operator is not required to click anything. It belongs in `/soleur:ship`'s post-merge verification (precedent: ship/SKILL.md:1177's `gh workflow run` for modified workflows).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `.github/workflows/kb-drift-walker.yml:43` reads `uses: dopplerhq/cli-action@014df23b1329b615816a38eb5f473bb9000700b1 # v3` verbatim (verify with `grep -n "dopplerhq/cli-action@" .github/workflows/kb-drift-walker.yml`).
- [ ] `grep -rn "517441f1eaf80f64b34d0e4dca44c0aacb13a3a3" .github/` returns empty (bad SHA fully removed).
- [ ] `git diff --stat origin/main..HEAD -- .github/workflows/kb-drift-walker.yml` shows exactly `1 file changed, 1 insertion(+), 1 deletion(-)`.
- [ ] No other workflow files modified (`git diff --stat origin/main..HEAD -- .github/workflows/` shows only `kb-drift-walker.yml`).
- [ ] PR body contains `Ref: Actions run 26209907780`.
- [ ] PR body contains a one-sentence statement that "subsequent step failures, if any, are out of scope of this PR".

### Post-merge (automated via /soleur:ship)

- [ ] `gh workflow run kb-drift-walker.yml --ref main` succeeds (HTTP 204).
- [ ] The triggered run's `Install Doppler CLI` step has a non-null `conclusion` (any value — success/failure/skipped — proves the action resolved).
- [ ] The triggered run does NOT have `Unable to resolve action` in its `Set up job` log:

  ```bash
  ! gh run view "$RUN_ID" --log 2>&1 | grep -q "Unable to resolve action.*dopplerhq/cli-action"
  ```

## Risks

- **Risk: canonical SHA gets retagged upstream.** Low — `dopplerhq/cli-action` v3 tag is the only one in the repo and has been stable; sibling workflows have used `014df23b...` without churn. Mitigation: not a fix-scope concern; if upstream ever retags, it affects all 7 sibling workflows uniformly and is a separate problem.
- **Risk: subsequent step fails (Doppler auth, signing key fetch, ingest 4xx/5xx).** Explicitly out of scope per the source brief. If observed post-merge, file a new issue — do NOT widen this PR. Multi-agent review at PR time may surface latent bugs in `scripts/kb-drift-walker.sh` or the ingest route; defer to follow-ups.
- **Risk: `actionlint` is not installed in the dev environment.** Phase 1 step 5 is gated on `command -v actionlint` and is best-effort. CI runs no actionlint job for this file today; the fix's pre-merge correctness rests on the grep checks above.

## Out of Scope

- Refactoring the workflow (job structure, secret threading, env injection pattern).
- Changing how the signing key flows from Doppler into the Python HMAC call.
- Diagnosing or fixing any post-Doppler-resolution failure (auth, ingest 4xx/5xx, walker script errors).
- Upgrading `dopplerhq/cli-action` past v3.
- Adding a CI guard that prevents future bad-SHA pins for `dopplerhq/cli-action` specifically (would be a useful follow-up; not in this scope).

## Sharp Edges

- This file's other action pins (`actions/checkout@11bd71...`) are intentionally NOT being audited or changed. If a sibling pin is also stale, it would surface independently — surfacing it in this PR widens scope past the source brief.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Filled above with `threshold: none` plus the explicit "internal observability job, no user-facing surface" reason.
- `gh workflow run kb-drift-walker.yml --ref main` will fail with HTTP 404 if the modified workflow file is not yet on `main` at the time of the call. `/soleur:ship` orders verification AFTER merge precisely for this reason.
- The "any conclusion" verification rule deliberately treats `failure` on `Install Doppler CLI` as a PASS for this PR's scope, because the failure mode being fixed is `Unable to resolve action` (pre-step) — NOT the step's body. A reviewer who sees a red checkmark on the post-merge run should `grep` the log for `Unable to resolve action` before re-opening this issue.

## Observability

This is a workflow YAML edit only — no code paths under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, `plugins/*/scripts/`, and no new infrastructure surface is introduced. Per the Observability Quality Gate skip conditions ("Plan is pure-docs (no Files-to-Edit under code/infra paths above)" — and a `.github/workflows/*.yml` SHA pin is the workflow-config analogue), this section intentionally documents the skip rationale instead of providing the 5-field schema. The workflow's own observability (run logs, KB-drift ingest endpoint) is unchanged by this PR.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — single-line CI workflow SHA correction. No new infrastructure (Phase 2.8 skip), no regulated-data surface (Phase 2.7 skip), no observability surface introduced (Phase 2.9 skip), no product/UX impact (Phase 2.5 skip).

## Test Strategy

No test code added. The fix is verified by:
1. Pre-merge: literal grep assertions over the file content (see Pre-merge AC).
2. Post-merge: live `gh workflow run` + step-conclusion probe (see Post-merge AC).

No unit/integration/e2e tests are appropriate for a SHA-pin correction — the verification surface IS the live workflow resolution against GitHub Actions infrastructure.

## Resume Prompt (copy-paste after /clear)

```text
/soleur:work knowledge-base/project/plans/2026-05-21-fix-kb-drift-walker-doppler-action-sha-plan.md.
Branch: feat-one-shot-fix-kb-drift-walker-doppler-sha.
Worktree: .worktrees/feat-one-shot-fix-kb-drift-walker-doppler-sha/.
PR: not yet opened. Issue: none filed.
Single-line SHA fix to .github/workflows/kb-drift-walker.yml:43. Plan complete; implementation next.
```
