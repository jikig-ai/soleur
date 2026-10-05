---
title: "docs: delete the hand-maintained sentry_alert rule count from the C4 sentry -> founder edge"
date: 2026-10-05
slug: delete-c4-sentry-alert-rule-count
branch: feat-one-shot-9312-c4-alert-rule-count
issue: 9312
closes: 9312
type: docs
lane: cross-domain
brand_survival_threshold: none
---

# docs: delete the hand-maintained sentry_alert rule count from the C4 sentry -> founder edge

## Enhancement Summary

**Deepened on:** 2026-10-05
**Sections enhanced:** 4 (Scope Check added, Phase 1 exact-text verification, gate results, tooling risk)
**Research agents used:** none spawned. The change is one description string in two files; a 40-agent fan-out has nothing to review, so the deepen pass was done as targeted local verification (greps, a unique-match probe of the edit target, the Phase 4.6-4.12 gates run by hand).

### Key Improvements

1. Added the mandatory `## Scope Check` (deepen-plan 4.12): nine asks mapped to plan items, two items declared `inferred` with justification, split assessment `single PR`.
2. Verified both Phase 1 substitution targets are present exactly once in `model.c4` (the long routing clause and the "by design there and a defect anywhere else" clause), so the Edit tool's uniqueness requirement will hold. Removed stray backslash-escaped backticks from the plan's quoted old text; the file contains plain backticks.
3. Confirmed no assertion pins the removed sentence: `c4-count-parity` rows are file-wide clause-anchored greps on other edges, and nothing in the three C4 suites mentions `sentry_alert`, `issue-alerts` or `NoOne`.

### New Considerations Discovered

- Gate results: 4.6 pass (concrete User-Brand Impact, threshold none, scope-out bullet present); 4.7 skip (pure docs); 4.8 pass (no PAT-shaped tokens); 4.9 skip (no UI surface); 4.10 skip (no store or connection; `.tf` files are cited, not edited); 4.11 skip (no guard is delivered, the operator explicitly declined the parity row); 4.12 pass.
- Re-measured live: 43 `sentry_alert` resources in `issue-alerts.tf`, 4 `fallthrough_type = "NoOne"`, 1 more in `cron-monitor-alerts.tf`; PR #9302 merged 2026-09-30T19:46:09Z; #9312 open.
- Issue #9312's body itself says the original count read "36 of the 38" and that PR #9263 would change it again; both are superseded by this deletion, and the number would have gone stale a third time without any test noticing.
- Risk: rendering needs network through `npx` with the pinned `--before` date. A failed render never overwrites the committed artifact, and CI `c4-model-freshness` is the backstop.

## Overview

The C4 model's `sentry -> founder` edge (`knowledge-base/engineering/architecture/diagrams/model.c4`,
line 815) carries a derived cardinality in prose: "40 of the 43 `sentry_alert` rules in
issue-alerts.tf; three deliberately set fallthrough_type NoOne" followed by a hand-enumerated list of
three rule names. It was wrong on arrival in PR #9302 (review decision-challenge DC-5, issue #9312):
`apps/web-platform/infra/sentry/issue-alerts.tf` has 43 `sentry_alert` resources and FOUR with
`fallthrough_type = "NoOne"` (the fourth, `auth_per_user_loop`, is unnamed in the text), so the
sentence should have read 39 of 43. Nothing checks it: `plugins/soleur/test/c4-count-parity.test.sh`
has no row for this count.

The operator already chose the resolution at the go-dispatch prompt: DELETE the number. Do not keep
it, do not add a parity row. The edit removes the "N of the M" count and the hand-enumerated NoOne
rule names from that one edge description, keeps the qualitative routing description, re-renders
`model.likec4.json`, and leaves the C4 freshness/parity tests green. Docs/diagram-only. No production
writes.

## Research Insights

**Premise Validation.** Checked: #9312 is OPEN with no closing PR; PR #9302 is MERGED
(2026-09-30T19:46:09Z), so the earlier caveat about an open PR changing the count again is resolved.
`model.c4:815` on this branch still carries the sentence (draft PR #9527 is OPEN, branch is clean and
current with origin/main for `diagrams/`). Counts re-measured on the worktree:
`grep -c '^resource "sentry_alert"'` = 43 in `issue-alerts.tf`, 1 in `cron-monitor-alerts.tf`;
`grep -c 'fallthrough_type *= *"NoOne"' issue-alerts.tf` = 4. The premise holds. No external premises
are stale. The proposed mechanism (delete prose) is not in any ADR's rejected-alternatives table.

**Property List.**

1. The C4 edge prose never states a derived count that nothing verifies.
2. A reader of the edge still learns the routing contract (email, `target_type issue_owners`,
   fallthrough `ActiveMembers`, a few rules set `NoOne`) and where the authoritative list
   lives (`issue-alerts.tf`).
3. The compiled artifact `model.likec4.json` matches the `.c4` source byte-for-byte (freshness gate).

**Cut List.**

- Add a `c4-count-parity` row for the rule count -> operator decision: delete, not verify (a parity row
  would also need a fourth-NoOne-aware derivation and re-pin on every alert PR; the number buys nothing
  the file reference does not).
- Keep the three NoOne rule names -> property 2 is served by "see issue-alerts.tf for the authoritative
  list"; the names are a second hand-maintained copy that already drifted (missed `auth_per_user_loop`).
- Edit ADR-031 amendments or the archived plans/specs that mention these rule names -> dated
  append-only records, deliberately untouched.

**Sweep results (repo-wide, non-archived).** Greps for `40 of the 43`, `of the 43`, `three deliberately`,
`sentry_alert rules`, `fallthrough_type`, `NoOne` across `knowledge-base/engineering`,
`plugins/soleur/test`, `plugins/soleur/scripts`, `scripts`, `apps/web-platform/test`:

- The removed sentence exists ONLY in `model.c4:815` and its compiled copy `model.likec4.json:2701`
  (a `title` string). No other file contains "40 of the 43" or "three deliberately".
- No assertion in `plugins/soleur/test/{c4-count-parity,c4-model-freshness,render-c4-model}.test.sh`
  references `sentry_alert`, `issue-alerts` or `NoOne` (grep returned zero hits), so nothing pins the
  removed sentence. `c4-count-parity` rows are clause-anchored to other edges.
- `ADR-031-sentry-as-iac.md` does not contain the count (its `43` hits are timestamps). ADR-198 line
  ~402 mentions `git_data_boot_warning` with `NoOne` as a dated historical record: do not edit.
- `apps/web-platform/test/sentry-*-op-contract.test.ts` assert `fallthrough_type` on the `.tf` source
  itself, not on the C4 prose: unaffected.
- Other `of the 43`/`of the 4x` hits (`run-report-exit-first-contact-8076.sh` digest counts, ADR-126,
  a post-mortem, `feat-context-engineering-audit/spec.md` byte counts) are unrelated numbers.
- One cross-reference inside the same description depends on the removed text: "a NoOne rule fires and
  pages nobody, by design there and a defect anywhere else". "there" refers to the enumerated rules.
  After the enumeration is gone this must be reworded or it dangles (see Implementation).

**Institutional learnings applied.** `cq-assert-anchor-not-bare-token` (no parity row: nothing to
anchor); `cq-cite-content-anchor-not-line-number` (cite `model.c4` edge by its `sentry -> founder`
anchor, line 815 is only a hint); #7160 / #7826 (embedded derived cardinalities in `model.c4` rot
silently; deleting the count is the cheapest end of that fix).

**Tooling note.** `likec4` is not on PATH here; `plugins/soleur/scripts/render-c4-model.sh` runs it via
`npx -y --ignore-scripts --before=<pinned date> likec4@<pinned version>` (needs network and
`jq`, `node`, `npx`). The work phase renders with that script; if the registry is unreachable the CI
`c4-model-freshness` test is the gate and the failure message names the regenerate command.

## Implementation Phases

### Phase 1 - Edit the edge description (one description, nothing else)

File: `knowledge-base/engineering/architecture/diagrams/model.c4`, the `sentry -> founder` edge
(anchor: `sentry -> founder "Pages the operator`). Edit in place with the Edit tool, in the worktree
only. Two substitutions inside that one description string, applied to the exact current text:

1. Replace
   `Issue alerts route to email → target_type issue owners with fallthrough_type ActiveMembers — 40 of the 43 `sentry_alert` rules in issue-alerts.tf; three deliberately set fallthrough_type NoOne — `byok_cap_exceeded`, `git_data_boot_warning` (the non-paging half of the git-data boot severity split) and `web_luks_boot_warning` (the non-paging half of the fresh-boot LUKS stage split, #6931).`
   with
   `Issue alerts route to email → target_type issue owners with fallthrough_type ActiveMembers; a few rules set fallthrough_type NoOne instead (issue-alerts.tf is the authoritative list).`
2. Replace `by design there and a defect anywhere else` with
   `by design only where issue-alerts.tf says so and a defect anywhere else`.

Everything else in the description stays byte-identical (the "Every rule is a `sentry_alert`" sentence,
the FROZEN `auth_per_user_loop`/`sandbox_startup_failure` sentence, the live-fidelity script sentence,
the UI-managed high-priority rule / #7142, the `cron_monitor_failure` sentence). Do not reflow, do not
touch any other element or edge: draft PRs #9348 and #8626 also edit `model.c4` elsewhere and neither
touches this edge, so a single-description diff keeps their rebases trivial.

The new text states NO number and names NO rule, so there is nothing for a reviewer to re-count. Keep
the existing ASCII-vs-arrow characters (`→`, `—`) exactly as in the file.

### Phase 2 - Re-render the compiled artifact

```bash
bash plugins/soleur/scripts/render-c4-model.sh
```

This validates off-tree, canonicalizes, and publishes `model.likec4.json`. Expected diff: exactly the
one `title` line (~2701) that mirrors the edge description, plus no layout/order churn. Inspect with
`git diff --stat` (expect 2 files changed) and `git diff -U0 knowledge-base/engineering/architecture/diagrams/model.likec4.json`.

### Phase 3 - Run the C4 gates locally and sweep once more

```bash
bash plugins/soleur/test/c4-model-freshness.test.sh
bash plugins/soleur/test/c4-count-parity.test.sh
bash plugins/soleur/test/render-c4-model.test.sh
git grep -n "40 of the 43\|three deliberately\|of the 43 .sentry_alert" -- ':!**/archive/**' ':!knowledge-base/project/plans/2026-10-05-docs-delete-c4-sentry-alert-rule-count-plan.md' ':!knowledge-base/project/specs/feat-one-shot-9312-c4-alert-rule-count/**'
```

The final grep must return nothing outside archived records and this feature's own plan/tasks (they
cite the old sentence as a migration record, exactly like `**/archive/**`). Also run
`npx markdownlint-cli2` (or the repo's lint wrapper) on the changed `.md` files only if the work phase
adds any (the diff itself touches `.c4` and `.json`, not markdown, apart from plan/tasks, which must
have no doubled blank lines).

### Phase 4 - Ship

PR #9527 (draft) body MUST contain `Closes #9312` (in the body, not the title). No `.github/workflows`
or `.github/actions` edits, so admin merge on green CI is allowed. CI is the test gate; the known e2e
flake (#8785) clears with one `gh run rerun --failed`. Do not edit
`plugins/soleur/skills/review/SKILL.md` (about 45 bytes under its byte ceiling) and do not edit ADR-031
amendments.

## Files to Edit

- `knowledge-base/engineering/architecture/diagrams/model.c4` (the `sentry -> founder` edge description only)
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (re-rendered by the script, never hand-edited)

## Files to Create

- `knowledge-base/project/plans/2026-10-05-docs-delete-c4-sentry-alert-rule-count-plan.md` (this file)
- `knowledge-base/project/specs/feat-one-shot-9312-c4-alert-rule-count/tasks.md`

## Open Code-Review Overlap

Procedure run: `gh issue list --label code-review --state open --json number,title,body --limit 200`
then a `jq --arg path` body search for both edited paths (`model.c4`, `model.likec4.json`) is
delegated to the work phase's first command (the plan phase is read-mostly and the edit set is two
fixed files). Disposition rule: any match is acknowledged unless it concerns the `sentry -> founder`
edge description, in which case it folds into this PR. Recorded result at plan time: none known.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "DELETE the number, do not keep it and do not add a parity row" [brief] | Phase 1 (model.c4 edit); Test Scenarios negative row | mapped |
| 2 | "remove the "N of the M" count and the hand-enumerated NoOne rule names from the edge description" [brief] | Phase 1 substitution 1 | mapped |
| 3 | "keep the qualitative routing description" [brief] | Phase 1 replacement sentence | mapped |
| 4 | "re-render model.likec4.json via plugins/soleur/scripts/render-c4-model.sh and satisfy the C4 freshness/parity tests" [brief] | Phase 2, Phase 3 | mapped |
| 5 | "Sweep the subject repo-wide" [brief] | Research Insights sweep results; Phase 3 residual grep | mapped |
| 6 | "ADR-031 amendments are dated append-only records: do NOT edit them" [brief] | Cut List; Sharp Edges; Files to Edit omits ADR files | mapped |
| 7 | "check plugins/soleur/test and scripts for any assertion pinning the removed sentence" [brief] | Research Insights sweep results; Phase 3 | mapped |
| 8 | "the PR body must say "Closes #9312"" [brief] | Phase 4; Acceptance Criteria | mapped |
| 9 | "keep the edit to that one description" [brief] | Phase 1 constraint; Acceptance Criteria diff-scope row | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Files to Edit: model.c4 | "remove the "N of the M" count and the hand-enumerated NoOne rule names from the edge description" | asked |
| Files to Edit: model.likec4.json | "re-render model.likec4.json via plugins/soleur/scripts/render-c4-model.sh" | asked |
| Phase 1 substitution 2 (reword "by design there") | — | inferred — justification: the clause "by design there" refers to the enumerated rules being deleted, so leaving it makes the surviving description wrong |
| Phase 3 test runs and residual grep | "satisfy the C4 freshness/parity tests" | asked |
| Files to Create: this plan and tasks.md | — | inferred — justification: the soleur:plan pipeline contract requires the plan file and tasks.md as the hand-off to soleur:work |

### Split Assessment

- Subsystems touched: 1 - knowledge-base (plus plan/spec artifacts in the same root)
- Planned files: 4 | Estimated changed lines: 4
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] The `sentry -> founder` description in `model.c4` contains no "N of the M" count and none of the
      names `byok_cap_exceeded`, `git_data_boot_warning`, `web_luks_boot_warning` inside the routing
      sentence; it still states email, `target_type issue owners`, `fallthrough_type ActiveMembers`,
      that a few rules set `NoOne`, and points at `issue-alerts.tf` as the authoritative list.
      Verify: `git diff -U0 origin/main -- knowledge-base/engineering/architecture/diagrams/model.c4`
      shows one changed line and the removed text is gone.
- [ ] The "by design there" back-reference is reworded so it does not dangle.
- [ ] `git diff --stat origin/main` lists exactly the two diagram files plus this plan and tasks.md
      (no other `.c4` line changed; no `.github/` file changed).
- [ ] `bash plugins/soleur/test/c4-model-freshness.test.sh`, `c4-count-parity.test.sh` and
      `render-c4-model.test.sh` all pass (each prints its pass count and exits 0).
- [ ] No test or script pins the removed sentence: the Phase 3 `git grep` returns no non-archive hit.
- [ ] PR #9527 body contains `Closes #9312`.
- [ ] CI green (`test`, `c4`-related shards, markdown lint). If only the e2e job (#8785 flake) is red,
      one `gh run rerun --failed`.

### Post-merge (operator)

- None. Docs/diagram-only; no deploy, no production write.

## Test Scenarios

- Mutation check (manual, local, not committed): re-insert `40 of the 43` into `model.c4` without
  re-rendering -> `c4-model-freshness.test.sh` must go RED (proves the artifact gate sees the edge).
- Idempotence: run `render-c4-model.sh` twice -> second run produces no diff.
- Negative: confirm `git grep -c "sentry_alert" plugins/soleur/test/c4-count-parity.test.sh` is 0
  before and after (no parity row added, per the operator decision).

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing. The worst case is a stale or
failing C4 viewer artifact in the Knowledge Base (the web viewer renders `model.likec4.json`), which
the freshness test catches before merge.

**If this leaks, the user's data is exposed via:** no vector. The change deletes a numeric claim and
rule names from internal architecture prose; it adds no data, no credentials, no endpoints.

**Brand-survival threshold:** none.

- threshold: none, reason: documentation-only edit to an internal architecture diagram description; touches no schema, migration, auth, API route or `.sql` file.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected - documentation change to an existing C4 edge description.

## Architecture Decision (ADR/C4)

No new architectural decision is made, so no ADR is created or amended (ADR-031 amendments are dated
append-only records and stay untouched). The C4 model IS edited, as an in-scope task of this plan.

### ADR

None. The change removes an unverified derived number; it reverses no ADR Decision.

### C4 views

Model file edited directly (no follow-up issue): `model.c4`, edge `sentry -> founder` (Container-level
relationship, rendered in the existing views; no `views.c4` change because no element or relationship
is added or removed, only the edge's description text). Read for the completeness check: `model.c4`,
`views.c4`, `spec.c4`. Enumeration against the change: (a) external human actor `founder` - already
modeled, unchanged; (b) external system `sentry` - already modeled, unchanged; (c) containers/data
stores touched - none; (d) actor-surface access relationships - the `sentry -> founder` paging
relationship is unchanged, only its description loses a count. Derived cardinalities: this edge held
one unverified count; it is deleted rather than added to `c4-count-parity`. The other counts on this
and neighboring edges are already gated by `c4-count-parity.test.sh` rows C1-C9, and the green run of
that suite in Phase 3 is the evidence nothing else moved.

### Sequencing

Single slice; the ADR/C4 state is correct as soon as the PR merges.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder text fails `deepen-plan` Phase
  4.6; this one carries concrete artifacts and an explicit `none` threshold with a reason.
- Removing the enumeration leaves "by design there" dangling: the Phase 1 substitution 2 is part of
  the same edit, not optional polish.
- `model.likec4.json` is canonicalized line-per-value; never hand-edit it. Only
  `render-c4-model.sh` publishes it (the freshness test also gates canonical format, #8542).
- `likec4` is not installed in this checkout; the renderer fetches the pinned version through `npx`
  and needs network. A render that fails at `npx` leaves the committed artifact untouched (the script
  refuses to overwrite on any non-zero export), so a failed render is safe to retry.
- Edit in the worktree only; the Edit tool is blocked in the primary checkout while worktrees exist.
- This plan and its tasks.md cite the old sentence as a migration record: exclude them (like
  `**/archive/**`) from the residual-zero grep AC.
- Do not add `lane:`-style or progress keys beyond the frontmatter above; ship derives the PR body.
