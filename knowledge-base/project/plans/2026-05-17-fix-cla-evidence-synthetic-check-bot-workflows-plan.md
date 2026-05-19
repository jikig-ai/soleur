---
title: "fix(ci): add cla-evidence synthetic check to bot PR workflows + composite"
issue: 3923
related_issues: [3916, 3927]
related_prs: [3201, 3593]
branch: feat-one-shot-3923
lane: single-domain
type: bug
classification: standard
created: 2026-05-17
deepened: 2026-05-17
requires_cpo_signoff: false
---

# fix(ci): add `cla-evidence` synthetic check to bot PR workflows + composite

Closes #3923, #3916, #3927. Ref #3201 (cla-evidence introduction), #3593 (deferred composite extraction — re-evaluation trigger fires here).

## Enhancement Summary

**Deepened on:** 2026-05-17
**Sections enhanced:** 6 (Overview, Files to Edit, Implementation Phases, Acceptance Criteria, Sharp Edges, Risks)
**Verification done in deepen-pass:**

- Confirmed live `bash scripts/lint-bot-synthetic-completeness.sh` exit=0 on the feature branch (all 6 synthetics present on both inlined workflows).
- Confirmed actionlint exits 0 on both workflow files and the composite action.
- Confirmed `python3 -c "import yaml; yaml.safe_load(...)"` passes on all 3 edited YAML files.
- Resolved all cited PR/issue numbers live via `gh pr view` / `gh issue view`: #3201 MERGED, #3593 OPEN, #3916 OPEN, #3923 OPEN, #3927 OPEN, #3917 MERGED.
- Verified commit references reachable from main: `2093948f` ✓, `b98c2177` ✓.
- Verified all 5 issue labels exist (`priority/p2-medium`, `type/bug`, `domain/engineering`, `code-review`, `deferred-scope-out`).
- Verified the CLA Required ruleset on GitHub (id `13304872`) currently enforces only `cla-check` (NOT `cla-evidence`) — the immediate failure mode is the lint red, not a runtime merge deadlock.

### Key Improvements vs. plan v1

1. **Reconciled to actual on-disk state.** The fix was already applied as uncommitted local changes when the worktree was initialized. Plan v1 prescribed Phase 2/3 edits that were already done. Plan v2 reframes those phases as "verify the existing diff," dropping speculative work.
2. **Output text correction.** Plan v1 prescribed `output[title]=CLA evidence pre-recorded` / `output[summary]=github-actions[bot] evidence layer satisfied`. The actual on-disk diff uses `output[title]=CLA evidence not applicable` / `output[summary]=Bot-authored PR — no CLA-signed contributions to attest.` This is semantically more correct: bot-authored PRs have no human signer, so the evidence layer is not "pre-recorded" — it's not applicable. Adopt the on-disk text.
3. **Composite-action CHANGELOG.md update added to scope.** Plan v1 missed this. The composite carries a versioned CHANGELOG (per its design); a behavior change requires a CHANGELOG bump (v2 → v2.1) per its existing convention.
4. **Multi-issue close.** Plan v1 referenced only #3923. Three duplicate issues exist (#3916, #3923, #3927) — the fix closes all three. PR body should `Closes #3923 / Closes #3916 / Closes #3927`.
5. **#3593 re-evaluation trigger formally fires.** Trigger #2 ("a change to the synthetic check-run set requires editing both the parent composite AND the workflow's inlined copy in the same PR") fires here. Plan v2 prescribes a post-merge update to #3593 explicitly.

## Overview

PR #3201 added `cla-evidence` to `scripts/required-checks.txt` (the canonical source of truth for synthetic-check-run completeness). Three synthetic-posting sites were not updated:

1. `.github/workflows/scheduled-compound-promote.yml` — inline post (lines 250-281).
2. `.github/workflows/scheduled-content-publisher.yml` — inline post (lines 143-176).
3. `.github/actions/bot-pr-with-synthetic-checks/action.yml` — shared composite consumed by 6 workflows (lines 165-181).

The `lint-bot-statuses` job in `.github/workflows/ci.yml` fails on every push to `main` (verified on commit `2093948f`, run `25972384575`):

```
FAIL: .github/workflows/scheduled-compound-promote.yml is missing synthetic check-runs for: cla-evidence
FAIL: .github/workflows/scheduled-content-publisher.yml is missing synthetic check-runs for: cla-evidence
```

The lint silently skips composite consumers (see `scripts/lint-bot-synthetic-completeness.sh:184-186`), so the composite's drift is invisible to the lint — but if `scripts/create-cla-required-ruleset.sh` is re-PUT (it already defines `cla-evidence` as required), all 6 composite consumers would deadlock at merge. The composite update is forward-compat hardening for that future operator action; #3593's re-evaluation trigger #2 fires here, mandating dual-edit in the same PR.

### Research Insights

**Best practices for synthetic-check posting:**

- The `Checks API` (`/check-runs`), NOT the `Statuses API` (`/statuses`), is load-bearing for ruleset matching. Rulesets require Check Runs from `integration_id=15368` (github-actions[bot]); commit statuses do not satisfy them. The composite documents this at line 162-164. ([Source: scripts/required-checks.txt header])
- Multi-word check names (`"skill-security-scan PR gate"`) MUST be quoted in `-f name=...` and the lint's `grep -qE "-f name=\"<escaped>\""` form matches them only when quoted. See learning `2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md`.
- The `output[title]` and `output[summary]` strings are operator-visible in the PR check-run UI. Bot-PR fixtures use `Bot PR` / `<change-summary>`; CLA-specific synthetics use `CLA pre-approved` / `github-actions[bot] is in CLA allowlist` (existing `cla-check`) and now `CLA evidence not applicable` / `Bot-authored PR — no CLA-signed contributions to attest.` (new `cla-evidence`). The semantic distinction matters: bot PRs literally have no human contributor whose CLA signature could be recorded, so "not applicable" is the load-bearing framing.

**Edge cases:**

- The lint script uses `grep -qE "\-f name=cla-evidence([[:space:]]|$)"` AND `grep -qE "\-f name=\"cla-evidence\""`. Either form satisfies it. The on-disk diff uses unquoted form (no spaces in `cla-evidence`).
- YAML indentation differs by site: composite uses 8-space, content-publisher uses 10-space, compound-promote uses 12-space (inside `while` loop). The on-disk diff preserves each site's indent.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
| --- | --- | --- |
| "2 workflows missing synthetic check-runs for `cla-evidence`" | Confirmed at the time the three duplicate issues were filed. As of this deepen-pass, both workflows + the composite action already have the missing block applied as uncommitted local edits. | Plan v2 reframes Phase 2/3 as "commit and verify" rather than "edit and verify." |
| "Pattern matches `scheduled-weekly-analytics.yml`" | `scheduled-weekly-analytics.yml:68` uses the composite action `bot-pr-with-synthetic-checks`, NOT inline posts. The reference pattern is therefore the composite's check-set, not weekly-analytics' explicit shell. | The composite ALSO needs the update (it lacks `cla-evidence` pre-fix). On-disk diff confirms it is added. |
| "Fix here would conflate unrelated concerns with PR #3917" | True. This PR (feat-one-shot-3923) is the right scope — single-domain CI hygiene fix that folds three duplicate issues into one merge. | Close #3916, #3923, #3927 from this PR. |
| Three issues for one drift | #3916 filed first (most descriptive title), #3923 second (current branch target), #3927 third (newest). All three describe the same lint failure and the same fix. | PR body uses `Closes #3923` + `Closes #3916` + `Closes #3927` to close all three at merge. |
| Ruleset state | The actual `CLA Required` GitHub ruleset (id `13304872`) currently enforces only `cla-check` — `cla-evidence` is in `required-checks.txt` (lint source) but not in the GitHub ruleset itself. So today's blast radius is "the lint job fails on `main` pushes," not "bot PRs deadlock at merge." | The lint failure is itself ship-blocking (CI Required check). Fix it. The composite update is forward-compat for the future ruleset re-PUT. |

## User-Brand Impact

**If this lands broken, the user experiences:** continued red `lint-bot-statuses` job on every PR to `main`, blocking auto-merge for all engineering work until manually overridden — the same failure mode that exists today.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A. No regulated-data surface; pure CI metadata change.

**Brand-survival threshold:** none — internal CI hygiene, no operator-facing data path.

**threshold: none, reason:** no sensitive path touched. The diff is `.github/workflows/scheduled-*.yml` + `.github/actions/bot-pr-with-synthetic-checks/{action.yml,CHANGELOG.md}` only. None match the canonical sensitive-path regex (no schema, no auth, no API route, no SQL, no `doppler*.yml`, no infra Terraform). Preflight Check 6 should record this scope-out unmodified.

## Files to Edit

All four files have changes already applied as uncommitted local edits. The deepen-pass verifies the diff is correct and ready to commit.

- **`.github/workflows/scheduled-compound-promote.yml`** — line ~282-288, 7-line block added after the `cla-check` post inside the cluster loop. Output text: `title=CLA evidence not applicable` / `summary=Bot-authored content PR — no CLA-signed contributions to attest.`
- **`.github/workflows/scheduled-content-publisher.yml`** — line ~177-184, 7-line block added after the `skill-security-scan PR gate` post, before `gh pr merge`. Output text: `title=CLA evidence not applicable` / `summary=Bot-authored content PR — no CLA-signed contributions to attest.`
- **`.github/actions/bot-pr-with-synthetic-checks/action.yml`** — line ~182-188, 7-line block added after the `cla-check` post in the composite. Output text: `title=CLA evidence not applicable` / `summary=Bot-authored PR — no CLA-signed contributions to attest.` Also line 40 doc-comment updated: `"and e2e synthetic checks. cla-check and cla-evidence use fixed summaries."`
- **`.github/actions/bot-pr-with-synthetic-checks/CHANGELOG.md`** — appended a `## v2.1 (2026-05-17)` section per the action's existing changelog convention. Documents the new synthetic, references all three closed issues (#3916/#3923/#3927), and confirms no input-contract change (forward-compat with v2 callers).

### Research Insights — Files to Edit

**Why CHANGELOG.md was added to scope:** the composite action carries a versioned CHANGELOG.md as part of its public contract (see `.github/actions/bot-pr-with-synthetic-checks/CHANGELOG.md` — distinct from the repo-level CHANGELOG). The action's design treats CHANGELOG as load-bearing: v2 documents the boolean-input normalization, v2.1 documents the `cla-evidence` addition. Skipping it would create a drift between code and documented contract.

**Why the composite's `description:` block-scalar was updated:** the doc-comment at line 40 enumerates the check-set semantic ("test, dependency-review, and e2e synthetic checks. cla-check uses a fixed allowlist summary"). Adding `cla-evidence` without updating this line would create a documentation-vs-behavior drift that a future maintainer would have to discover by reading code, not docs.

## Files to Create

None. No new test fixtures, no new scripts, no new docs. The existing `scripts/lint-bot-synthetic-completeness.sh` is the verification gate.

## Open Code-Review Overlap

Two open code-review issues touch these files:

- **#3593** (`review: extract post-synthetic-checks child composite (deferred per ADR-027)`) — touches both `.github/actions/bot-pr-with-synthetic-checks/action.yml` and `.github/workflows/scheduled-compound-promote.yml`. Re-evaluation trigger #2 fires on this PR: "A change to the synthetic check-run set (adding/removing a Required check name) requires editing both the parent composite AND the workflow's inlined copy in the same PR." **Disposition: acknowledge.** This PR honors the re-evaluation trigger by updating both surfaces in lock-step, but does NOT extract the child composite. Extraction remains a separate YAGNI-deferred refactor; doing it inline would expand scope beyond the immediate fix. Post-merge step adds a comment to #3593 noting the trigger fired.
- **#3595** (`review: bot-workflow enumeration — YAML-aware parser for audit/lint parity`) — touches `scripts/lint-bot-synthetic-completeness.sh`. **Disposition: defer.** This plan does not modify the lint script; #3595 is unrelated to the cla-evidence drift.

## Implementation Phases

### Phase 1 — RED state verification (historical)

When the three duplicate issues were filed (post-#3201 merge), `bash scripts/lint-bot-synthetic-completeness.sh` exited 1 with:

```
FAIL: .github/workflows/scheduled-compound-promote.yml is missing synthetic check-runs for: cla-evidence
FAIL: .github/workflows/scheduled-content-publisher.yml is missing synthetic check-runs for: cla-evidence

2 of 2 workflow(s) are missing synthetic check-runs.
```

This is the RED reference state. The composite-action consumers are silently exempt by the lint and were not flagged — but the composite's drift was identified during this deepen-pass via direct grep (`grep -nE "cla-evidence" .github/actions/bot-pr-with-synthetic-checks/action.yml` → 0 matches pre-fix).

### Phase 2 — GREEN state verification (current on-disk)

The fix is already applied. Verify the on-disk diff:

```bash
git diff --stat .github/workflows/scheduled-compound-promote.yml \
                .github/workflows/scheduled-content-publisher.yml \
                .github/actions/bot-pr-with-synthetic-checks/action.yml \
                .github/actions/bot-pr-with-synthetic-checks/CHANGELOG.md
# Expected: 4 files changed, ~50 insertions(+), ~2 deletions(-)
```

Then verify each invariant:

1. **Lint green:** `bash scripts/lint-bot-synthetic-completeness.sh` exits 0. Output line for each inlined file reads `ok: <file> (all 6 synthetics present)`. Verified live in deepen-pass — exit=0, both workflows green.
2. **One match per site:** `grep -cE '\-f name=cla-evidence' <file>` returns exactly 1 for each of the three YAML edits. Verified.
3. **Composite changelog bumped:** `head -25 .github/actions/bot-pr-with-synthetic-checks/CHANGELOG.md` shows a `## v2.1` heading dated `2026-05-17` referencing issues #3916/#3923/#3927.
4. **YAML parse green:** `python3 -c "import yaml; yaml.safe_load(open('<file>'))"` exits 0 for all three edited YAML files. Verified.
5. **actionlint green:** `actionlint .github/workflows/scheduled-compound-promote.yml .github/workflows/scheduled-content-publisher.yml` exits 0. Verified.

### Phase 3 — Commit and push

Single commit with all four files. Suggested commit message:

```
fix(ci): add cla-evidence synthetic check to bot PR workflows + composite

PR #3201 added cla-evidence to scripts/required-checks.txt but missed
three synthetic-posting sites:

- .github/workflows/scheduled-compound-promote.yml (inline)
- .github/workflows/scheduled-content-publisher.yml (inline)
- .github/actions/bot-pr-with-synthetic-checks/action.yml (composite,
  consumed by 6 bot workflows)

Adds the missing block at each site with output text "CLA evidence not
applicable" (bot-authored PRs have no human signer, so the evidence
layer is semantically not-applicable, not "pre-recorded").

Bumps the composite action to v2.1 per its CHANGELOG convention.
No input-contract change.

#3593 re-evaluation trigger #2 fires here (synthetic check-set change
requires dual-edit of parent composite + inlined copy). Extraction
remains deferred per ADR-027.

Closes #3916
Closes #3923
Closes #3927
Ref #3593
```

Push, mark PR ready, monitor CI.

### Phase 4 — Post-merge verification

1. **Composite consumers (5 workflows).** On the next firing of each of (`scheduled-skill-freshness`, `scheduled-weekly-analytics`, `rule-metrics-aggregate`, `scheduled-content-vendor-drift`, `scheduled-rule-prune`), confirm the bot PR carries a `cla-evidence` check posted as `success` by `github-actions[bot]`. Automatable via `gh pr view <next-bot-pr> --json statusCheckRollup`; bake into the next session.
2. **Inlined workflows (2).** On the next firing of `scheduled-compound-promote` or `scheduled-content-publisher`, same verification.
3. **Update #3593.** Comment: "Re-evaluation trigger #2 fired on PR #<n>; inline + composite updated in lock-step per ADR-027 carry-forward. Extraction remains deferred until a second multi-PR-per-run caller motivates the refactor." Automatable via `gh issue comment 3593 --body-file <path>`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bash scripts/lint-bot-synthetic-completeness.sh` exits 0. Output line for both inlined workflows reads `ok: <file> (all 6 synthetics present)`.
- [ ] `grep -cE '\-f name=cla-evidence' .github/workflows/scheduled-compound-promote.yml` returns `1`.
- [ ] `grep -cE '\-f name=cla-evidence' .github/workflows/scheduled-content-publisher.yml` returns `1`.
- [ ] `grep -cE '\-f name=cla-evidence' .github/actions/bot-pr-with-synthetic-checks/action.yml` returns `1`.
- [ ] `head -25 .github/actions/bot-pr-with-synthetic-checks/CHANGELOG.md` includes `## v2.1` heading dated `2026-05-17` and references #3916/#3923/#3927.
- [ ] `python3 -c "import yaml; yaml.safe_load(open('<file>'))"` exits 0 on all three edited YAML files.
- [ ] `actionlint .github/workflows/scheduled-compound-promote.yml .github/workflows/scheduled-content-publisher.yml` exits 0.
- [ ] The PR's `lint-bot-statuses` check is green in the GitHub UI.
- [ ] PR body uses `Closes #3923` AND `Closes #3916` AND `Closes #3927` (three duplicates, single fix).
- [ ] PR body references #3593 with the re-evaluation note: "trigger #2 fired; both inline and composite updated in lock-step; extraction remains deferred."
- [ ] All other CI Required checks (`test`, `dependency-review`, `e2e`, `skill-security-scan PR gate`, `CodeQL`) pass.

### Post-merge (operator)

- [ ] On the next firing of `scheduled-content-publisher.yml` OR `scheduled-compound-promote.yml`, the bot PR's check-rollup shows `cla-evidence` posted as `success` by `github-actions[bot]`. Automatable via `gh pr view <next-bot-pr> --json statusCheckRollup`. If no bot tick fires within 7 days, invoke manually with `gh workflow run scheduled-content-publisher.yml`.
- [ ] On the next firing of any composite consumer (`scheduled-skill-freshness`, `scheduled-weekly-analytics`, `rule-metrics-aggregate`, `scheduled-content-vendor-drift`, `scheduled-rule-prune`), same `cla-evidence=success` verification.
- [ ] `gh issue comment 3593 --body "Re-evaluation trigger #2 fired on PR #<n>; inline + composite updated in lock-step per ADR-027 carry-forward. Extraction remains deferred until a second multi-PR-per-run caller motivates the refactor."` — fire post-merge via `gh issue comment` from the next session.

## Test Scenarios

The lint script itself is the test harness. Three scenarios:

1. **Negative (pre-fix `main` state, historical):** `bash scripts/lint-bot-synthetic-completeness.sh` exits 1 with FAIL lines naming the two inlined workflows for `cla-evidence`. The composite drift is silently exempt by the lint (composite consumers are skipped).
2. **Positive (post-fix, feature branch):** same command exits 0 with `ok:` for both edited files. Verified live in deepen-pass.
3. **Forward-compat (composite consumers, post-merge):** when the 5 composite-consuming workflows fire next, their bot PRs post 6 synthetics including `cla-evidence`. No automated assertion in this PR; record in operator verification step.

## Sharp Edges

- **Literal `-f name=` form is load-bearing.** The lint uses `grep -qE "\-f name=cla-evidence([[:space:]]|$)"`. Do not refactor to a bash `for` loop over `CHECK_NAMES` in either inlined workflow — the lint is content-grep, not bash-aware (per `scripts/lint-bot-synthetic-completeness.sh:191-197` and the WHY-comment at `scheduled-compound-promote.yml:243-249`).
- **Composite action consumers are silently skipped by the lint** (`lint-bot-synthetic-completeness.sh:184-186`: "Composite-action consumers do not post synthetics inline — coverage is provided by .github/actions/bot-pr-with-synthetic-checks/action.yml. Skip silently"). Adding `cla-evidence` to the composite is therefore NOT detected by the lint — it is forward-compat hardening. The reviewer should confirm the composite edit by reading the diff, not by waiting for a red lint.
- **YAML indentation differs by call site.** `scheduled-compound-promote.yml`'s inline post lives inside a `while IFS= read -r cluster; do ... done` loop — base indent is 12 spaces. `scheduled-content-publisher.yml` uses 10 spaces. The composite uses 8 spaces. A mismatched indent silently breaks YAML parsing — verified via `python3 yaml.safe_load` and `actionlint` in deepen-pass.
- **Output text precision: "not applicable", not "pre-recorded".** Bot-authored PRs have no human contributor whose CLA signature could be recorded. The first-draft of plan v1 prescribed `output[title]=CLA evidence pre-recorded` which would be a future-maintainer surprise ("which previously-recorded evidence?"). On-disk text `output[title]=CLA evidence not applicable` + `output[summary]=Bot-authored PR — no CLA-signed contributions to attest.` is the semantically correct framing.
- **The CLA Required ruleset (id 13304872) currently enforces only `cla-check`, not `cla-evidence`.** Today's failure is purely "lint job red" on main, not "bot PRs deadlock at merge." If `scripts/create-cla-required-ruleset.sh` is re-PUT in a future operation, all bot PRs would need the synthetic — this PR is the forward-compat layer for that operator action.
- **Three duplicate issues for one fix.** #3916 / #3923 / #3927 all describe the same drift. The PR body MUST close all three with explicit `Closes #N` lines (per `wg-use-closes-n-in-pr-body-not-title-to`). Closing only the branch-target (#3923) would leave #3916 and #3927 dangling.
- **`Closes` form is correct here** (not `Ref`) — this is a single-merge bug fix with no post-merge operator-write phase that could create a false-resolved window. The post-merge verification is observational, not corrective.
- **#3593 re-evaluation trigger #2 fires.** The composite + inlined copy must be edited in lock-step per the trigger; this PR does so. Extraction itself remains deferred (ADR-027 carry-forward).
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** Filled here: threshold `none` with explicit scope-out reason per preflight Check 6.

## Risks

- **Risk: a future ruleset re-PUT pins `integration_id` (like CodeQL does today), silently breaking the synthetic posting.** Per `scripts/required-checks.txt:18-31`, this would silently regress synthetics. Mitigation: out of scope here — covered by the empirical-audit pattern documented for CodeQL (`scripts/audit-bot-codeql-coverage.sh`). File a follow-up only if the ruleset is ever pinned to a specific integration_id.
- **Risk: extracting the composite (#3593) is the "right" long-term move, and updating both surfaces inline reinforces the duplication.** Mitigation: explicitly acknowledged in the Code-Review Overlap section. ADR-027 still applies (single multi-PR-per-run caller); deferring extraction is the correct YAGNI default. Post-merge step updates #3593 with the trigger-fired note so the next reviewer sees the receipt.
- **Risk: indentation drift in the inline edits breaks YAML parsing at runtime, surfacing only on the next scheduled tick.** Mitigation: `python3 yaml.safe_load` + `actionlint` both pass in deepen-pass. The verification is mechanical.
- **Risk: the on-disk diff (already-applied uncommitted changes) drifts from this plan during /work.** Mitigation: Phase 2 prescribes verifying the diff against the plan's Files-to-Edit list before commit. If any file has unexpected changes (e.g., the description doc-comment line 40 was edited differently), reconcile before push.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal CI hygiene change touching three workflow/action files plus one CHANGELOG. No user-facing surface, no data path, no schema, no docs-site change, no skill/agent change. The four 8 brainstorm domains (CMO/CRO/CPO/CTO/CLO/COO/CFO/CHRO) are not engaged.

(GDPR / compliance gate per Phase 2.7: not triggered — none of the canonical regex surfaces (schemas, migrations, auth flows, API routes, `.sql`) are touched, and none of the (a)-(d) expansion triggers fire: no LLM-mediated processing on operator-session data, threshold is `none`, no cron added that reads from learnings/specs, no artifact distribution surface change. Skipped silently per plan SKILL §2.7.)

## CLI-Verification Gate

All shell commands prescribed in this plan reference already-installed tools (`bash`, `grep`, `gh`, `python3`, `git`, `actionlint`) with standard flags. Two non-trivial invocations:

- `gh api "repos/${REPO}/check-runs" -f name=<n> ...` — verified pattern, present in 6 existing workflows. No new flags introduced. Form documented at `.github/actions/bot-pr-with-synthetic-checks/action.yml:167-181`.
- `bash scripts/lint-bot-synthetic-completeness.sh` — local execution; the script exists at `scripts/lint-bot-synthetic-completeness.sh` (verified `ls -l`). No subcommand. Exit-code semantics: 0 = green, 1 = at least one workflow missing a required synthetic.

No CLI invocations are landing in user-facing docs; the gate is satisfied by reuse of existing precedent.

## References

- Issues: #3923 (branch target), #3916 (first-filed duplicate), #3927 (third duplicate)
- Origin PR (introduced `cla-evidence` in `required-checks.txt`): #3201, commit `b98c2177`
- Failed CI run: https://github.com/jikig-ai/soleur/actions/runs/25972384575/job/76346571044
- Runbook: `knowledge-base/engineering/ops/runbooks/lint-bot-statuses.md`
- ADR: `knowledge-base/engineering/architecture/decisions/ADR-027-stateless-self-modifying-cron.md` (the deliberate-duplication carry-forward this PR honors)
- Re-evaluation-triggered scope-out: #3593
- Canonical source of truth: `scripts/required-checks.txt`
- Composite action: `.github/actions/bot-pr-with-synthetic-checks/action.yml` + `CHANGELOG.md`
- Lint script: `scripts/lint-bot-synthetic-completeness.sh`
- Multi-word check-name learning: `knowledge-base/project/learnings/2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md`
- Scope-out bundling learning: `knowledge-base/project/learnings/2026-05-11-scope-out-bundling-hides-cheap-inline-fixes.md`

## Quality Check Receipts (deepen-pass)

Per `deepen-plan/SKILL.md` quality checks, each load-bearing claim verified live:

- **PR/issue state:** All cited numbers resolved via `gh pr view` / `gh issue view`. #3201 MERGED, #3593 OPEN, #3916 OPEN, #3923 OPEN, #3927 OPEN, #3917 MERGED. No unresolved citations.
- **Commit reachability:** `git merge-base --is-ancestor <hash> main` for `2093948f` and `b98c2177` — both reachable.
- **Label existence:** `gh label list --limit 200` confirms `priority/p2-medium`, `type/bug`, `domain/engineering`, `code-review`, `deferred-scope-out` all exist.
- **AGENTS.md rule citations:** `wg-use-closes-n-in-pr-body-not-title-to` verified active via `grep -qE '\[id: wg-use-closes-n-in-pr-body-not-title-to\]' AGENTS.md` — present. `hr-autonomous-loop-skill-api-budget-disclosure` present. No retired/fabricated rule IDs cited.
- **Lint green proof:** `bash scripts/lint-bot-synthetic-completeness.sh` exit=0, output line `All 2 GITHUB_TOKEN workflow(s) post complete synthetic check-runs.`
- **YAML/actionlint proof:** all three edited YAML files pass `python3 yaml.safe_load` and `actionlint`.
- **Loader-class fit:** N/A — no AGENTS.md rule demotion proposed.
- **Pathspec→regex translation:** N/A — no glob/regex translation proposed.
