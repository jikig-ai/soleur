---
title: "fix: close stale bot-filed issue #4221 — auto-approve-trusted-applies.yml already deleted by PR #4220"
date: 2026-05-21
type: bug-fix
classification: triage-cleanup
lane: procedural
status: draft
issue: 4221
related_prs: [4218, 4220]
related_workflows: []
related_iac: []
related_runbooks: []
requires_cpo_signoff: false
---

# fix: close stale bot-filed issue #4221 — auto-approve-trusted-applies.yml already deleted by PR #4220

## Enhancement Summary

**Deepened on:** 2026-05-21
**Plan author lens:** triage-cleanup / procedural lane — no source files edited, single learning file created, one GitHub issue closed.
**Gates passed:** Phase 4.6 (User-Brand Impact present, threshold `none`, no sensitive-path scope-out needed because `Files to Edit` contains no source files), Phase 4.7 (Observability skipped silently — pure docs-only per the trigger set), Phase 4.8 (no PAT-shape variables anywhere in the plan body).
**Research applied:** live `gh pr view 4218 4220` + `gh issue view 4221` for state/title verification; live `gh run list --workflow=auto-approve-trusted-applies.yml --limit 100` for the failure-vs-deletion timing claim; live `git ls-files .github/workflows/` to confirm the workflow file is absent; live `gh api repos/jikig-ai/soleur/actions/workflows` to confirm zero registration server-side; live `grep -E '\[id: ...\]' AGENTS*.md` to verify every cited rule ID; live `head -25` of `2026-04-22-triage-time-duplicate-detection-for-workflow-fixes.md` for prior-art alignment.

### Key Improvements over the initial draft

1. **Rule-ID typo corrected.** Initial draft cited the rule with the wrong prefix (`hr-...`) in the Sharp Edges block. Actual ID is `wg-block-pr-ready-on-undeferred-operator-steps` (`wg-`, not `hr-`; verified via `grep -E '\[id: wg-block-pr' AGENTS.md` returning line 67). Fixed inline at deepen time. Avoids the fabricated/retired-rule-ID failure mode documented in [llm-authored-plans-cite-fabricated-and-retired-rule-ids.md](../learnings/2026-05-09-llm-authored-plans-cite-fabricated-and-retired-rule-ids.md).
2. **Timing math re-verified live.** PR #4220 merged at `2026-05-21T08:34:57Z` per `gh pr view 4220 --json mergedAt`; issue #4221 was filed at `2026-05-21T08:35:59Z` per `gh issue view 4221 --json createdAt`. Delta = 62 seconds exactly (computed via Python `datetime` subtraction). Plan body's "62 seconds later" claim survives live re-verification.
3. **All 4 cited PR/issue numbers reconciled.** `gh pr view 4218 4220` confirm both are MERGED with the titles cited; `gh issue view 4221` confirms OPEN; #2519 and #2526 cited only inside the referenced prior-art learning (not the plan body) — the source learning's citations were not modified.
4. **Server-side registration absence captured.** `gh api repos/jikig-ai/soleur/actions/workflows --paginate` was inspected at deepen time: 74 workflows total, zero match `auto-approve|trusted` in name/path. AC1/AC5 phrasing retained; added the absence-from-API observation to the H1 evidence block in the original draft.
5. **Phase 4.6 sensitive-path regex pre-checked.** The plan's `Files to Edit` contains only a path under `knowledge-base/project/learnings/`, which does NOT match the canonical sensitive-path regex from preflight Check 6 Step 6.1. Threshold `none` is valid without a scope-out bullet. No `## Observability` section needed (Phase 4.7 trigger set explicitly excludes pure-docs plans).
6. **PR-vs-issue disambiguation note added to learning scope.** The Phase 1 learning's heuristic includes the symmetric `gh issue view N` probe per `2026-05-20-plan-time-pr-vs-issue-disambiguation-and-self-derived-counts.md` (unified-numbering disambiguation). This generalizes the heuristic so a future stale-issue catch handles bot-filed *issues* citing *PR* numbers (or vice versa).
7. **No fan-out warranted.** The deepen-pass classifier (procedural lane, docs-only, no Files-to-Edit under code/infra/skill paths, no domains relevant, no compliance surface, no IaC surface, no SDK calls, no user-facing copy) routes to zero parallel research/review subagents. Spawning 20+ agents on a 3-section close-the-issue plan would burn 30k+ tokens to produce zero net signal. The plan was authored against five live `gh`/`git` checks, all archived in this Research Insights block.

### Research Insights

**Live verification artifacts captured at deepen time (2026-05-21):**

```text
$ git ls-files .github/workflows/ | grep -i approve
(empty)

$ gh api repos/jikig-ai/soleur/actions/workflows --paginate | jq '.workflows[] | select(.path|test("auto-approve|trusted"))'
(empty)

$ gh run list --workflow=auto-approve-trusted-applies.yml --limit 100 --json conclusion,createdAt,event,headSha
[
  {createdAt: "2026-05-21T08:29:23Z", conclusion: failure, event: push, headSha: "f71b3288..."},
  {createdAt: "2026-05-21T08:25:27Z", conclusion: failure, event: push, headSha: "44286f80..."},
  {createdAt: "2026-05-21T08:23:21Z", conclusion: failure, event: push, headSha: "16f14e1b..."},
  {createdAt: "2026-05-21T08:18:59Z", conclusion: failure, event: push, headSha: "cd663e1e..."}
]
Total: 4 runs, all pre-deletion (<08:34:57Z).

$ gh pr view 4220 --json mergedAt -q .mergedAt
2026-05-21T08:34:57Z

$ gh issue view 4221 --json createdAt -q .createdAt
2026-05-21T08:35:59Z

$ # Latest post-deletion push:
$ gh run list --limit 50 --branch=main --json workflowName,createdAt | jq '[.[] | select(.workflowName | test("auto-approve|trusted"; "i"))]'
[]
```

**Prior-art consulted:**

- `knowledge-base/project/learnings/2026-04-22-triage-time-duplicate-detection-for-workflow-fixes.md` — directly applicable; the new Phase 1 learning extends this from "current value matches proposed fix" (file-exists case) to "file no longer exists" (deletion case).
- AGENTS.md `hr-before-asserting-github-issue-status` (active) — fires on assertions about state, not on triage start; the new heuristic plugs the gap at consumption time.
- AGENTS.md `hr-when-triaging-a-batch-of-issues-never` (active) — covers triage hygiene but not file-existence sub-check.
- AGENTS.md `wg-block-pr-ready-on-undeferred-operator-steps` (active, fixed typo from initial draft) — used in Sharp Edges to justify `Ref #4221` vs `Closes #4221` for the batched-delay case.

## Summary

Issue #4221 reports `.github/workflows/auto-approve-trusted-applies.yml` failing on every push to main. **The workflow file no longer exists in the repository as of 2026-05-21T08:34:57Z** — it was deleted by PR #4220 (`fix(ci): remove env-reviewer gates on apply-*-infra workflows; revert PR #4218`, commit `2c5ccc48`). Issue #4221 was filed **62 seconds later** at 08:35:59Z by a bot that observed the failure-streak but did not observe the deletion that had just merged.

The reported failures are real but already-remediated:

| Run timestamp (UTC) | conclusion | head SHA | status now |
|---|---|---|---|
| 2026-05-21T08:18:59Z | failure | cd663e1e | pre-deletion, will not recur |
| 2026-05-21T08:23:21Z | failure | 16f14e1b | pre-deletion, will not recur |
| 2026-05-21T08:25:27Z | failure | 44286f80 | pre-deletion, will not recur |
| 2026-05-21T08:29:23Z | failure | f71b3288 | pre-deletion, will not recur |

PR #4220 merged at 2026-05-21T08:34:57Z. There have been zero `auto-approve-trusted-applies.yml` runs since (the workflow file is no longer in `.github/workflows/`, and `gh api .../actions/workflows` shows no registration for it). The latest push to main (`e3502145`, 08:51:22Z, "fix(learnings): scrub real operator email …") does NOT spawn a new run for this workflow.

This plan is a triage cleanup: close #4221 with a referencing comment, and add one paragraph + one learning to harden triage-time duplicate detection so the next stale-bot-issue is caught at `/soleur:triage` boundary rather than burning a planning cycle.

## User-Brand Impact

**If this lands broken, the user experiences:** zero impact. The workflow is already gone; the bot-filed issue is the only artifact. Worst case if we do NOTHING: the issue sits open in the backlog forever, polluting `gh issue list` triage.
**If this leaks, the user's [data / workflow / money] is exposed via:** no exposure path — pure issue-state hygiene. No code, no infrastructure, no secrets, no UI.
**Brand-survival threshold:** none (procedural cleanup of a stale issue).

## Hypotheses

### H1 (CONFIRMED): The reported workflow no longer exists; failures stopped when PR #4220 merged.

Evidence:

1. `git ls-files .github/workflows/ | grep -i approve` returns empty.
2. `gh api repos/jikig-ai/soleur/actions/workflows --paginate` lists 74 workflows; none match `auto-approve` or `trusted` in name/path.
3. `gh run list --workflow=auto-approve-trusted-applies.yml --limit 100` returns exactly 4 runs (the ones in the issue body), all with `createdAt < 08:34:57Z` (PR #4220 merge time). Zero runs after the merge.
4. The post-#4220 push (`e3502145` at 08:51:22Z) triggered 6 workflows; `auto-approve-trusted-applies` is NOT in the list (verified via `gh run list --limit=50 --branch=main`).

### H2 (CONFIRMED): The bot that filed #4221 lacked visibility that PR #4220 had just merged.

Evidence:

1. Issue #4221 was filed at 2026-05-21T08:35:59Z (timestamp on `gh issue view 4221 --json createdAt`).
2. PR #4220 merged at 2026-05-21T08:34:57Z (`gh pr view 4220 --json mergedAt`).
3. The bot's automated fix-attempt comment (08:50:55Z) cites the original workflow path (`.github/workflows/auto-approve-trusted-applies.yml`) as the file it would need to modify, then refuses on the basis of the `fix-issue` skill's "no infrastructure changes" rule. The comment was generated against a stale issue-body view of the repo state.
4. This matches the duplicate-detection learning from 2026-04-22 (`triage-time-duplicate-detection-for-workflow-fixes.md`), where issue #2526 was filed 7 minutes after #2519 was closed and burned a full planning cycle before a planner caught the staleness.

### H3 (ROOT CAUSE of the original failures — for the record): GitHub fires workflows on every `push` to main even when their `on:` block declares only `deployment_review`.

This was the actual mechanism behind the 4 pre-deletion failures. Per PR #4220's commit message, the deeper finding was that the *design* of #4218 was unworkable: GitHub rejects GitHub Apps as `environment: required_reviewers` (HTTP 422 "App is not a possible value"). The Oct 2023 Apps-in-deployment-reviews announcement refers to the separate `deployment_protection_rule` mechanism. Without a valid reviewer registration, every push to main spawned an `auto-approve-trusted-applies.yml` run that GitHub recorded as `failure` with empty `jobs:[]` and `event: push` — exactly the symptom in the issue body.

This hypothesis is **not actionable** in this plan — PR #4220 already resolved it by deleting the workflow and switching strategies. Documenting it here so the learning file can carry the substrate observation.

## Research Reconciliation — Spec vs. Codebase

| Issue body claim | Codebase reality | Plan response |
|---|---|---|
| "workflow `.github/workflows/auto-approve-trusted-applies.yml` is failing on every push to main" | The file does not exist; deleted by PR #4220 at 08:34:57Z | The claim was true at 08:18-08:29Z (4 documented failures), false from 08:34:57Z onward. Issue is stale. |
| "The runs have `event: push`" | Confirmed via `gh run list --workflow=auto-approve-trusted-applies.yml --json event` | Real symptom; root cause documented in H3. Not actionable — workflow deleted. |
| "The workflow YAML declares only `on: deployment_review:`" | True at the time of the failures (verified via `git show 16f14e1b -- .github/workflows/auto-approve-trusted-applies.yml`) | Real observation; mechanism captured in learning, no fix needed. |
| Suggested fix Options A/B/C all touch the workflow file | Workflow file is gone | All three options are moot. Issue should be closed, not fixed. |

## Files to Edit

None. The original workflow file no longer exists; no code change is needed.

## Files to Create

1. `knowledge-base/project/learnings/2026-05-21-bot-filed-issue-races-prior-resolution-pr.md` — codify the timing-race detection at triage boundary.

## Implementation Phases

### Phase 0 — Pre-merge verification (already complete in plan-write)

This work is fully verified at plan-write time. Phase 0 evidence captured above in Hypotheses and Research Reconciliation. No /work-time verification needed beyond re-running the four greps if the operator wants belt-and-braces:

```bash
# Confirm file is still absent
git ls-files .github/workflows/ | grep -i approve   # must be empty
# Confirm zero registered workflow
gh api repos/jikig-ai/soleur/actions/workflows --paginate \
  | jq '.workflows[] | select(.path|test("auto-approve|trusted"))'   # must be empty
# Confirm no new runs since the deletion
gh run list --workflow=auto-approve-trusted-applies.yml --limit 100 --json createdAt \
  | jq '[.[] | select(.createdAt > "2026-05-21T08:34:57Z")] | length'   # must be 0
# Confirm latest push to main does NOT fire this workflow
gh run list --limit 50 --branch=main --json workflowName,createdAt \
  | jq '[.[] | select(.workflowName | test("auto-approve|trusted"; "i"))]'   # must be empty array
```

### Phase 1 — Write the learning file

Create `knowledge-base/project/learnings/2026-05-21-bot-filed-issue-races-prior-resolution-pr.md`. Required content (one-page learning):

- **Frontmatter**: `title`, `date: 2026-05-21`, `category: engineering`, `tags: [triage, bot, stale-issue, duplicate-detection, race-condition]`.
- **Problem**: Bot-filed issue #4221 referenced `auto-approve-trusted-applies.yml` 62 seconds after PR #4220 deleted that workflow. Bot was working from a stale snapshot of the repo state.
- **Why existing rules missed it**: The 2026-04-22 triage-time-duplicate-detection learning prescribed greping the file the issue body cites — but assumed the file still EXISTS. When the resolution is a *deletion*, the grep returns empty (file gone) instead of "current value matches proposed fix". The empty result needs to be classified as "issue is stale (file deleted)" rather than "file not yet touched (proceed with fix)".
- **Heuristic to add to `/soleur:triage` Step 0 and `/soleur:one-shot` Step 0**:
  1. Extract the file path(s) from the issue body.
  2. **If the path no longer exists** (`git ls-files <path>` empty), search merged PRs in the window `[issue_created_at - 1h, issue_created_at]` for any PR that deleted that path:
     ```bash
     gh pr list --state merged --search "<path> merged:>=<issue_created_at_minus_1h>" \
       --json number,title,mergedAt,files \
       | jq '.[] | select(.files[]?.path == "<path>") | {number,title,mergedAt}'
     ```
     If any match: close the issue as duplicate, citing the PR that removed the file.
  3. **Belt-and-braces for workflow files specifically**: cross-check `gh api repos/<owner>/<repo>/actions/workflows` for the workflow registration. Workflows persist in the API for a short window after deletion; absence is the canonical signal.
- **Sharp edge**: A bot that races a prior-resolution PR by N seconds is indistinguishable at issue-filing time from a real new failure. The detection MUST run at triage *consumption* (when `/soleur:triage` reads the issue), not at issue-filing (we cannot control the bot). The cost of one extra `git ls-files` + `gh pr list --search` at consumption time is ~1 second; the cost of a full planning cycle on a stale issue is hours of clock and ~30k tokens.
- **References**: link back to `2026-04-22-triage-time-duplicate-detection-for-workflow-fixes.md` (prior art for value-matches-fix detection), AGENTS.md `hr-before-asserting-github-issue-status`, AGENTS.md `hr-when-triaging-a-batch-of-issues-never`.

### Phase 2 — Close issue #4221 with a referencing comment

Post a comment on #4221 explaining the timing race, then close it as `not planned` (since there is no work to do):

```bash
gh issue comment 4221 --body "$(cat <<'EOF'
Closing as already-resolved: the workflow file `.github/workflows/auto-approve-trusted-applies.yml`
was deleted by PR #4220 (`fix(ci): remove env-reviewer gates on apply-*-infra workflows; revert PR #4218`),
which merged at 2026-05-21T08:34:57Z — exactly 62 seconds before this issue was filed at
2026-05-21T08:35:59Z. The 4 reported failures (08:18Z, 08:23Z, 08:25Z, 08:29Z) all predate the deletion.

Verified:
- `git ls-files .github/workflows/ | grep -i approve` → empty
- `gh api repos/jikig-ai/soleur/actions/workflows` → no entry for this workflow
- `gh run list --workflow=auto-approve-trusted-applies.yml --limit 100` → 4 historical runs only,
  zero after the deletion (no run for the next push `e3502145`)

Root-cause of the original failures (for the record, not actionable): PR #4218's design was
unworkable. GitHub rejects Apps as `environment: required_reviewers` (HTTP 422 "App is not a
possible value"). The Oct 2023 Apps-in-deployment-reviews announcement refers to the separate
`deployment_protection_rule` mechanism, which requires a webhook receiver. PR #4220 captured
this and pivoted to the simpler structural fix (remove the `environment:` gate entirely from
the two apply-*-infra workflows, since the PR-merge IS the human authorization per
`hr-menu-option-ack-not-prod-write-auth`).

Bot-filing race classified and codified in
`knowledge-base/project/learnings/2026-05-21-bot-filed-issue-races-prior-resolution-pr.md`
so the next `/soleur:triage` consumption catches this class at the issue-read boundary
rather than spinning a planning cycle.
EOF
)"
gh issue close 4221 --reason "not planned"
```

### Phase 3 — Verify (post-PR-merge or post-direct-commit)

```bash
gh issue view 4221 --json state | jq -r .state   # must be CLOSED
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: The plan file at `knowledge-base/project/plans/2026-05-21-fix-stale-issue-auto-approve-trusted-applies-4221-plan.md` exists and is reachable (`test -f`).
- [ ] AC2: The learning file at `knowledge-base/project/learnings/2026-05-21-bot-filed-issue-races-prior-resolution-pr.md` exists with valid YAML frontmatter (date 2026-05-21, category engineering, ≥5 tags including `triage`, `bot`, `stale-issue`).
- [ ] AC3: The learning body cross-references `2026-04-22-triage-time-duplicate-detection-for-workflow-fixes.md`: `grep -q '2026-04-22-triage-time-duplicate-detection-for-workflow-fixes' knowledge-base/project/learnings/2026-05-21-bot-filed-issue-races-prior-resolution-pr.md`.
- [ ] AC4: The plan body's `Files to Edit` section names no source files — this PR is docs-only.
  Verify: `! awk '/^## Files to Edit/,/^## /' knowledge-base/project/plans/2026-05-21-fix-stale-issue-auto-approve-trusted-applies-4221-plan.md | grep -qE '^[0-9]+\.'` (exits 0 only when the section contains no numbered entries; non-zero exit indicates a Files-to-Edit entry was added and AC fails).
- [ ] AC5: `git ls-files .github/workflows/ | grep -i approve` returns empty (workflow is and remains gone).
- [ ] AC6: `gh run list --workflow=auto-approve-trusted-applies.yml --limit 100 --json createdAt | jq '[.[] | select(.createdAt > "2026-05-21T08:34:57Z")] | length'` returns `0`.

### Post-merge (operator)

- [ ] AC7: `gh issue view 4221 --json state | jq -r .state` returns `CLOSED`. (Auto-closed by `Closes #4221` in the PR body, or run `gh issue close 4221 --reason "not planned"` from Phase 2.)
- [ ] AC8: `gh issue view 4221 --json comments | jq '[.comments[] | select(.body | test("PR #4220"))] | length'` returns ≥ 1 (the referencing comment is present).

## Domain Review

**Domains relevant:** none.

This is a triage-cleanup PR with no user-facing impact, no code change, no infrastructure change, no schema change, no compliance surface, no security surface. The only artifact is a learning file in `knowledge-base/project/learnings/`. Cross-domain leaders would have nothing to assess.

## Open Code-Review Overlap

None. Verified via:

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
jq -r --arg path "knowledge-base/project/learnings/" '
  .[] | select(.body // "" | contains($path))
  | "#\(.number): \(.title)"
' /tmp/open-review-issues.json
```

No open code-review issues touch the learnings directory. (Plan touches no source files.)

## Observability

**Skip silently** — pure docs-only plan. No new code path, no new infrastructure surface, no liveness signal needed. The `## Observability` field-set is unnecessary per the Phase 2.9 skip condition ("plan is pure-docs (no Files-to-Edit under code/infra paths above)").

## Test Strategy

No code change to test. Verification is via the AC greps above:

- File-existence (`test -f` on the plan and learning files).
- Repo-state assertions (`git ls-files`, `gh run list`).
- Issue-state assertion (`gh issue view 4221 --json state`).

No new test framework needed; bash + `gh` + `jq` are the entire toolset.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| (A) Restore the workflow + add `if: github.event_name == 'deployment_review'` per Option A in the issue body | The workflow's *design* is unworkable (GitHub Apps cannot be env-reviewers — HTTP 422). Restoring it would re-introduce the broken design that PR #4220 just removed. |
| (B) Leave the issue open with a comment | Pollutes triage. The bot's "no infrastructure changes" refusal is itself stale; the underlying issue is also stale. Closing-with-comment is the cheaper hygiene. |
| (C) Just close without writing a learning | Wastes the substrate signal. The bot-races-prior-PR class will recur (any future bot that observes failures inside a tight resolution window). One-page learning at the consumption boundary prevents the next planning cycle. |
| (D) Write a `/soleur:triage` skill patch instead of a learning | Out of scope for this plan and a larger surface to verify. The learning carries the heuristic; a follow-up issue can route it into the skill body if the pattern recurs (defer per the next-cycle option). |

## Sharp Edges

- **Do not** restore the workflow file. PR #4220's commit message captures three independent reasons the design fails (HTTP 422 on App-as-reviewer; the `deployment_protection_rule` alternative requires a webhook receiver; the env-reviewer click was already duplicative with CODEOWNERS+branch-protection at the PR gate). Reverting #4220 would re-spawn the failures.
- **Do not** add a `Closes #4221` to a non-immediate PR. If this plan is rolled into a larger triage batch with delayed merge, prefer `Ref #4221` in the PR body and close explicitly via `gh issue close 4221 --reason "not planned"` post-merge per `wg-block-pr-ready-on-undeferred-operator-steps`. For a single-PR direct execution the `Closes #4221` is fine — the issue auto-closes on merge.
- **The learning's heuristic MUST run at triage *consumption* time**, not at issue-filing. Bots will continue to file race-condition issues; the catch is at the boundary where a human or `/soleur:one-shot` decides to start work. Adding a 1-second `git ls-files <path>` check there is cheap; trying to block the bot from filing is a different (harder) problem.
- **Timestamp arithmetic** — when checking "did a PR delete this path right before the issue was filed", widen the window to ~1 hour. PR merge timestamps and issue-filing timestamps come from independent clocks; a 5-minute window risks false negatives if either side rounds.
- **Workflow registrations linger** — GitHub's `actions/workflows` API can show a workflow as `disabled_inactivity` or `deleted` for a short window after the file is removed from the default branch. The canonical "is the workflow gone" check is `git ls-files`, NOT the API. The API check is belt-and-braces.

## PR body reminder

```
Closes #4221

Triage cleanup: issue #4221 reported a failing workflow that PR #4220 deleted
62 seconds before the issue was filed. No code change needed; the only artifact
is a learning file (`2026-05-21-bot-filed-issue-races-prior-resolution-pr.md`)
that codifies the bot-races-prior-PR detection so `/soleur:triage` catches the
class at issue-read time instead of spinning a planning cycle.

Cross-references:
- PR #4220 (`fix(ci): remove env-reviewer gates on apply-*-infra workflows; revert PR #4218`)
- PR #4218 (`feat(ci): auto-approve infra-apply deployments from merged-PR main pushes`)
- Prior art: `knowledge-base/project/learnings/2026-04-22-triage-time-duplicate-detection-for-workflow-fixes.md`
```
