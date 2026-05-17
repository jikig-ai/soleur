---
title: "fix(ci): add cla-evidence synthetic check to bot PR workflows + composite"
issue: 3923
branch: feat-one-shot-3923
lane: single-domain
type: bug
classification: standard
created: 2026-05-17
requires_cpo_signoff: false
---

# fix(ci): add `cla-evidence` synthetic check to bot PR workflows + composite

Closes #3923. Ref #3201 (cla-evidence introduction), #3593 (deferred composite extraction — re-evaluation trigger fires here).

## Overview

PR #3201 added `cla-evidence` to `scripts/required-checks.txt` (the canonical source of truth for synthetic-check-run completeness). Two scheduled bot workflows that inline their synthetic check-run posts — `scheduled-compound-promote.yml` and `scheduled-content-publisher.yml` — were not updated. The `lint-bot-statuses` job in `.github/workflows/ci.yml` now fails on every push to `main` (verified on commit `2093948f`, run `25972384575`):

```
FAIL: .github/workflows/scheduled-compound-promote.yml is missing synthetic check-runs for: cla-evidence
FAIL: .github/workflows/scheduled-content-publisher.yml is missing synthetic check-runs for: cla-evidence
```

The fix is to add one `gh api .../check-runs -f name=cla-evidence ...` block per inlined synthetic-posting site, plus extend the shared composite action's `CHECK_NAMES` array to include `cla-evidence` (the lint silently skips composite consumers, but the same logical drift exists there and #3593's re-evaluation trigger #2 fires on this exact change).

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
| --- | --- | --- |
| "2 workflows missing synthetic check-runs for `cla-evidence`" | Confirmed. `scheduled-compound-promote.yml:249-281` and `scheduled-content-publisher.yml:142-176` both post 4-5 inline synthetics, neither includes `cla-evidence`. | Add the missing block to both. |
| "Pattern matches `scheduled-weekly-analytics.yml`" | `scheduled-weekly-analytics.yml:68` uses the composite action `bot-pr-with-synthetic-checks`, NOT inline posts. Its check-set is in `.github/actions/bot-pr-with-synthetic-checks/action.yml:165`. | The composite ALSO lacks `cla-evidence`. The lint skips composite consumers silently (covered by the action's `CHECK_NAMES` array), so this drift is invisible to `lint-bot-statuses` — but if `scripts/create-cla-required-ruleset.sh` is ever re-PUT (it defines `cla-evidence` as required), all 6 composite consumers would deadlock at merge. Fold composite update into this PR. |
| "Fix here would conflate unrelated concerns with PR #3917" | True — #3917 was a Next.js bump. This PR is the right scope to fold both inline + composite updates together (per #3593 re-evaluation trigger #2: a check-name addition requires editing both the parent composite AND any inlined copies in the same PR). | This plan touches: 2 workflows (inline), 1 composite (shared), 0 unrelated areas. |
| Ruleset state | The actual `CLA Required` GitHub ruleset (id `13304872`) currently enforces only `cla-check` — `cla-evidence` is in `required-checks.txt` (lint source) but not in the ruleset itself. So today's blast radius is "the lint job fails on `main` pushes," not "bot PRs deadlock at merge." | The lint failure is itself ship-blocking (it's a CI Required check). Fix it. The composite update is forward-compatible for whenever `scripts/create-cla-required-ruleset.sh` is re-PUT. |

## User-Brand Impact

**If this lands broken, the user experiences:** continued red `lint-bot-statuses` job on every PR to `main`, blocking auto-merge for all engineering work until manually overridden — the same failure mode that exists today.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A. No regulated-data surface; pure CI metadata change.

**Brand-survival threshold:** none — internal CI hygiene, no operator-facing data path.

**Threshold-none scope-out reason (per preflight Check 6):** no sensitive path touched. The diff is `.github/workflows/scheduled-*.yml` + `.github/actions/bot-pr-with-synthetic-checks/action.yml` only. No schema, no auth, no API route, no SQL.

## Files to Edit

- `.github/workflows/scheduled-compound-promote.yml` — add `gh api .../check-runs -f name=cla-evidence ...` block after the existing `cla-check` posting at lines 270-277. Preserve the literal-name shape per the WHY-comment at line 244 ("scripts/lint-bot-synthetic-completeness.sh — literal grep, not bash-aware").
- `.github/workflows/scheduled-content-publisher.yml` — add the same block after the `skill-security-scan PR gate` posting at lines 170-176, before the `gh pr merge` call at line 178.
- `.github/actions/bot-pr-with-synthetic-checks/action.yml` — append `cla-evidence` to the explicit `gh api` enumeration. Two options inside the file's current shape:
  - **Option A (chosen):** add a second standalone `gh api` block mirroring the existing `cla-check` block at lines 175-181, with `name=cla-evidence`, `output[title]=CLA evidence pre-recorded`, `output[summary]=github-actions[bot] evidence layer satisfied`. Keeps the bot-PR-vs-real-PR distinction clear (bot PRs have no human signer so the evidence layer is a no-op).
  - **Option B (rejected):** add `cla-evidence` to the `CHECK_NAMES` array. Rejected because that array uses a generic `Bot PR / ${CHANGE_SUMMARY}` title-summary pair, and cla-evidence semantically belongs to the CLA cluster (different output text per #3201's design).
- Update the `description:` block-scalar at line 1-10 if it enumerates the check names (verify: it does not, only line 40 mentions "test, dependency-review, and e2e synthetic checks. cla-check uses a fixed allowlist summary" — extend to "test, dependency-review, e2e, and skill-security-scan PR gate; cla-check and cla-evidence use fixed allowlist summaries").

## Files to Create

None. No new test fixtures, no new scripts, no new docs. Existing `scripts/lint-bot-synthetic-completeness.sh` is the verification gate.

## Open Code-Review Overlap

Two open code-review issues touch these files:

- **#3593** (`review: extract post-synthetic-checks child composite (deferred per ADR-027)`) — touches both `.github/actions/bot-pr-with-synthetic-checks/action.yml` and `.github/workflows/scheduled-compound-promote.yml`. Re-evaluation trigger #2 fires on this PR: "A change to the synthetic check-run set (adding/removing a Required check name) requires editing both the parent composite AND the workflow's inlined copy in the same PR." **Disposition: acknowledge.** This PR honors the re-evaluation trigger by updating both surfaces in lock-step, but does NOT extract the child composite. Extraction remains a separate YAGNI-deferred refactor; doing it inline would expand scope beyond the immediate fix. Update #3593 with a comment noting the trigger fired and the dual-edit was performed in PR #<n>; the scope-out remains open against the next trigger or the next caller.
- **#3595** (`review: bot-workflow enumeration — YAML-aware parser for audit/lint parity`) — touches `scripts/lint-bot-synthetic-completeness.sh`. **Disposition: defer.** This plan does not modify the lint script; #3595 is unrelated to the cla-evidence drift.

## Implementation Phases

### Phase 1 — RED: extend the lint test surface

The lint script `scripts/lint-bot-synthetic-completeness.sh` already covers all 6 required names from `scripts/required-checks.txt` including `cla-evidence` (it loads them via `while IFS= read`). The "RED" state is already live on `main`: `bash scripts/lint-bot-synthetic-completeness.sh` exits 1 with the two FAIL lines from the issue body.

Verification step (local, ~3 seconds):

```bash
bash scripts/lint-bot-synthetic-completeness.sh
# Expected: exit 1, 2 FAIL lines naming the two scheduled workflows for cla-evidence.
```

No test-file edits required — the lint script reads `required-checks.txt` directly and the loop covers every entry.

### Phase 2 — GREEN: inline workflow edits

**2.1 — `scheduled-content-publisher.yml`.** Append the `cla-evidence` block to the existing 5-block inline post (after `skill-security-scan PR gate`, before `gh pr merge`):

```yaml
          gh api "repos/${{ github.repository }}/check-runs" \
            -f name=cla-evidence \
            -f head_sha="$COMMIT_SHA" \
            -f status=completed \
            -f conclusion=success \
            -f "output[title]=CLA evidence pre-recorded" \
            -f "output[summary]=github-actions[bot] evidence layer satisfied"
```

**2.2 — `scheduled-compound-promote.yml`.** Append the same block to the inline post in the `while` loop (after `cla-check` at line 277, before the closing `git checkout main`):

```yaml
            gh api "repos/${REPO}/check-runs" \
              -f name=cla-evidence \
              -f head_sha="$COMMIT_SHA" \
              -f status=completed \
              -f conclusion=success \
              -f "output[title]=CLA evidence pre-recorded" \
              -f "output[summary]=self-healing/auto promotion — evidence layer satisfied"
```

Note: compound-promote uses 4-space-deeper indentation inside its `while` loop; preserve exactly. Use Edit tool with full surrounding context, not heuristic insertion.

**2.3 — Local re-run.** `bash scripts/lint-bot-synthetic-completeness.sh` → expect exit 0 (all 6 synthetics present on both files).

### Phase 3 — Composite action update

**3.1 — Add `cla-evidence` block.** Edit `.github/actions/bot-pr-with-synthetic-checks/action.yml`. Append a second standalone `gh api` block after the existing `cla-check` block at lines 175-181:

```yaml
        gh api "repos/${REPO}/check-runs" \
          -f name=cla-evidence \
          -f head_sha="$COMMIT_SHA" \
          -f status=completed \
          -f conclusion=success \
          -f "output[title]=CLA evidence pre-recorded" \
          -f "output[summary]=github-actions[bot] evidence layer satisfied"
```

**3.2 — Update the action's `description:` doc-comment** at line 40 (the documentation refers to the synthetic check set):

Before:
```
      and e2e synthetic checks. cla-check uses a fixed allowlist summary.
```

After:
```
      and e2e synthetic checks. cla-check and cla-evidence use fixed
      allowlist summaries.
```

**3.3 — Sanity check.** `bash scripts/lint-bot-synthetic-completeness.sh` still exits 0 (composite consumers are silently skipped; this edit is forward-compat hardening, not a lint-driven fix).

### Phase 4 — Push and observe CI

Push the branch. The `lint-bot-statuses` job inside `.github/workflows/ci.yml` should go green on this PR. The CodeQL / test / e2e / dependency-review / skill-security-scan PR gate checks are unchanged (workflow files only, no script changes).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bash scripts/lint-bot-synthetic-completeness.sh` exits 0 locally on the feature branch. The output line for both edited workflows reads `ok: <file> (all 6 synthetics present)`.
- [ ] `grep -nE '\-f name=cla-evidence' .github/workflows/scheduled-compound-promote.yml` returns exactly 1 match (the new block inside the cluster loop).
- [ ] `grep -nE '\-f name=cla-evidence' .github/workflows/scheduled-content-publisher.yml` returns exactly 1 match (the new block before `gh pr merge`).
- [ ] `grep -nE '\-f name=cla-evidence' .github/actions/bot-pr-with-synthetic-checks/action.yml` returns exactly 1 match (the new block after `cla-check`).
- [ ] The PR's `lint-bot-statuses` check is green in the GitHub UI.
- [ ] The PR body uses `Closes #3923` (issue closes on merge — this is a single-merge fix, not an ops-remediation, so `Closes` is correct per `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] PR body references #3593 with the re-evaluation note: "trigger #2 fired; both inline and composite updated in lock-step; extraction remains deferred."
- [ ] All other CI Required checks (`test`, `dependency-review`, `e2e`, `skill-security-scan PR gate`, `CodeQL`) pass.

### Post-merge (operator)

- [ ] After merge, monitor the next scheduled tick of either workflow (whichever fires first; `scheduled-content-publisher.yml` runs more frequently). Confirm the auto-generated PR's `cla-evidence` check is posted as `success` by `github-actions[bot]` (visible in the PR's check-rollup).
  - **Automation feasibility:** automatable via `gh pr view <next-bot-pr> --json statusCheckRollup`. Bake into the next session's verification rather than asking the operator to eyeball. If no bot tick fires within 7 days (cron interval), invoke the workflow manually with `gh workflow run scheduled-content-publisher.yml`.
- [ ] Update #3593 with a comment: "Re-evaluation trigger #2 fired on PR #<n>; inline + composite updated in lock-step per ADR-027 carry-forward. Extraction remains deferred until a second multi-PR-per-run caller motivates the refactor."
  - **Automation feasibility:** automatable via `gh issue comment 3593 --body-file <path>` from a post-merge step. Not in scope for this PR; record as a one-line manual step in the PR description's checklist.

## Test Scenarios

The lint script itself is the test harness. Three scenarios:

1. **Negative (current `main` state):** `bash scripts/lint-bot-synthetic-completeness.sh` exits 1 with `FAIL: .github/workflows/scheduled-compound-promote.yml is missing synthetic check-runs for: cla-evidence` and the same for content-publisher. Verified locally before edits.
2. **Positive (post-edit, feature branch):** same command exits 0 with `ok:` for both edited files.
3. **Forward-compat (composite consumers, post-edit):** scheduled-skill-freshness / scheduled-weekly-analytics / scheduled-content-vendor-drift / scheduled-rule-prune / rule-metrics-aggregate / scheduled-compound-promote — when their next tick fires post-merge, the bot PRs they create should now post 6 synthetics including `cla-evidence`. No automated assertion in this PR; record in operator verification step.

## Sharp Edges

- **Literal `-f name=` form is load-bearing.** The lint uses `grep -qE "\-f name=cla-evidence([[:space:]]|$)"`. Do not change to a bash loop over `CHECK_NAMES` in either workflow — the lint is content-grep, not bash-aware (per `scripts/lint-bot-synthetic-completeness.sh:191-197` and the WHY-comment at `scheduled-compound-promote.yml:244`). Two scheduled workflows already document this gotcha inline.
- **Composite action consumers are silently skipped by the lint** (line 184-186 of `lint-bot-synthetic-completeness.sh`: "Composite-action consumers do not post synthetics inline — coverage is provided by .github/actions/bot-pr-with-synthetic-checks/action.yml. Skip silently"). Adding `cla-evidence` to the composite is therefore NOT detected by the lint — it is forward-compat hardening. The reviewer should confirm the composite edit by reading the diff, not by waiting for a red lint.
- **YAML indentation differs by call site.** `scheduled-compound-promote.yml`'s inline post lives inside a `while IFS= read -r cluster; do ... done` loop — base indent is 12 spaces, deeper than `scheduled-content-publisher.yml`'s 10 spaces and the composite action's 8 spaces. Edit with full surrounding context (Edit tool, not sed); a mismatched indent silently breaks YAML parsing.
- **The CLA Required ruleset (id 13304872) currently enforces only `cla-check`, not `cla-evidence`.** This means today's failure is purely "lint job red," not "bot PRs deadlock at merge." If `scripts/create-cla-required-ruleset.sh` is re-PUT in a future operation, all bot PRs created after that point would need the synthetic — this PR is the forward-compat layer for that operator action.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Filled here:** threshold `none` with explicit scope-out reason per preflight Check 6.
- **`Closes #3923` form is correct** — this is a single-merge bug fix, not an ops-remediation; the issue closes at merge with no post-merge operator-write phase that could create a false-resolved window (per `wg-use-closes-n-in-pr-body-not-title-to`).

## Risks

- **Risk: composite action consumers fail at runtime due to indentation drift.** Mitigation: Edit tool with exact surrounding context; run a YAML lint (`actionlint` if available, otherwise `python3 -c "import yaml; yaml.safe_load(open('<file>'))"`) on all 3 edited files before push.
- **Risk: `cla-evidence` synthetic posting fails at bot-PR runtime due to a future ruleset change that pins `integration_id` (like CodeQL does today).** Per `scripts/required-checks.txt:18-31`, this would silently regress synthetics. Mitigation: out of scope here — covered by the empirical-audit pattern documented for CodeQL (`scripts/audit-bot-codeql-coverage.sh`). File a follow-up only if the ruleset is ever pinned to a specific integration_id.
- **Risk: extracting the composite (#3593) is the "right" long-term move, and updating both surfaces inline reinforces the duplication.** Mitigation: explicitly acknowledged in the Code-Review Overlap section. ADR-027 still applies (single multi-PR-per-run caller); deferring extraction is the correct YAGNI default.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal CI hygiene change touching three workflow/action files. No user-facing surface, no data path, no schema, no docs site change, no skill/agent change.

(GDPR / compliance gate per Phase 2.7: not triggered — none of the canonical regex surfaces (schemas, migrations, auth flows, API routes, `.sql`) are touched, and none of the (a)-(d) expansion triggers fire (no LLM-mediated processing, threshold is `none`, no cron added that reads from learnings/specs, no artifact distribution surface change).)

## CLI-Verification Gate

All shell commands prescribed in this plan reference already-installed tools (`bash`, `grep`, `gh`, `python3`, `git`) with standard flags. Two non-trivial invocations:

- `gh api "repos/${REPO}/check-runs" -f name=<n> ...` — verified pattern, present in 6 existing workflows (`scheduled-weekly-analytics`, `scheduled-content-publisher`, `scheduled-compound-promote`, etc.). No new flags introduced.
- `bash scripts/lint-bot-synthetic-completeness.sh` — local execution; the script exists at `scripts/lint-bot-synthetic-completeness.sh` (verified `ls -l`). No subcommand.

No CLI invocations are landing in user-facing docs; the gate is satisfied by reuse of existing precedent.

## References

- Issue: #3923
- Origin PR (introduced `cla-evidence` in `required-checks.txt`): #3201, commit `b98c2177`
- Failed CI run: https://github.com/jikig-ai/soleur/actions/runs/25972384575/job/76346571044
- Runbook: `knowledge-base/engineering/ops/runbooks/lint-bot-statuses.md`
- ADR: `knowledge-base/engineering/architecture/decisions/ADR-027-stateless-self-modifying-cron.md` (the deliberate-duplication carry-forward this PR honors)
- Re-evaluation-triggered scope-out: #3593
- Canonical source of truth: `scripts/required-checks.txt`
- Canonical reference workflow (uses composite): `.github/workflows/scheduled-weekly-analytics.yml`
- Shared composite: `.github/actions/bot-pr-with-synthetic-checks/action.yml`
- Lint script: `scripts/lint-bot-synthetic-completeness.sh`
