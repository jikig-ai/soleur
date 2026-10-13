---
title: "AEO audit rubric reconciliation (#2679) and #2615 closure"
issue: 2679
closes_issues: [2679, 2615]
source_brainstorm: knowledge-base/project/brainstorms/2026-04-22-aeo-rubric-reconcile-2679-brainstorm.md
source_spec: knowledge-base/project/specs/feat-aeo-rubric-reconcile-2679/spec.md
type: chore
priority: P1
domain: marketing
created: 2026-04-22
status: planned
---

# AEO audit rubric reconciliation plan

## Overview

Pin a **dual-rubric AEO audit template** (SAP headline + 8-component AEO diagnostic) in BOTH `.github/workflows/scheduled-growth-audit.yml` Step 2 prompt AND `plugins/soleur/agents/marketing/growth-strategist.md` GEO/AEO Content Audit section. Update the re-audit runbook (`knowledge-base/project/plans/2026-04-19-chore-aeo-presence-reaudit-after-pr-2596-plan.md`) Phase 2 bash parser to handle the new score format. Close #2615 by citing the 2026-04-21 audit (Presence `20/25` = 80%, above the ≥55% threshold).

## Context

### Why the plan exists

Three consecutive AEO audits used three different scorecard shapes:

| Date | Rubric | Presence row | Overall |
|---|---|---|---|
| 2026-04-18 | SAP, 5% weight, bare 0–100 score | `40/F` | 72 |
| 2026-04-19 | 8-component AEO (no Presence row) | *absent* | 81/B |
| 2026-04-21 | SAP, 25% weight, `<n>/<weight>` score | `20/25 (80%)` | 78/B+ |

Neither the workflow Step 2 prompt (*"produce a structured scoring table"*) nor the `growth-strategist.md` GEO/AEO Content Audit section pins weights, grading scale, or column format. The agent freelances a different table shape each run.

### Threshold translation (worked example)

The `#2615` exit criterion `≥55` normalizes cleanly to percentage-of-category across both rubric eras:

- **Old format** (`PRESENCE_LINE = "| Presence & Third-Party Mentions | 40 | F | 5% | 2.0 |"`): Score column is already a bare 0–100 integer. `PRESENCE_PCT = 40`. `40 < 55` → FAIL (historical; the pre-PR-#2596 baseline).
- **New format** (`PRESENCE_LINE = "| **Presence** | 25 | 20/25 | 20 | ... |"`): Score column is `<n>/<weight>`. `PRESENCE_PCT = (20 / 25) * 100 = 80`. `80 ≥ 55` → PASS. This is the 2026-04-21 audit that verifies #2615.

Both interpretations measure the same thing: *what fraction of the rubric's Presence-category maximum did the audit award?* The issue's literal `≥55` threshold applies without reinterpretation.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (verified) | Plan response |
|---|---|---|
| Runbook grep anchors on `"^\| Presence & Third-Party Mentions"` | Confirmed at `knowledge-base/project/plans/2026-04-19-chore-aeo-presence-reaudit-after-pr-2596-plan.md:246`. 2026-04-21 audit uses `"**Presence**"`. | Update grep to match both labels; require `NF >= 5` to exclude legend/footer rows. |
| Score cell format changed | Confirmed: old `40`, new `20/25`. Whitespace can land as `20 / 25` after markdownlint reflow. | Parser accepts both; trims whitespace before matching. |
| Weight changed from 5% to 25% | Confirmed (04-18 vs 04-21 audit). | Pin weight=25 in new template. |
| 2026-04-21 audit proves #2615 exit criterion | Confirmed: Presence `20/25 (80%)` ≥ 55. | Close #2615 by citing this audit; no new audit run required. |

## Open Code-Review Overlap

Ran at plan-write time (2026-04-22) against the three target files — **no open code-review issues match**.

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for path in ".github/workflows/scheduled-growth-audit.yml" \
            "plugins/soleur/agents/marketing/growth-strategist.md" \
            "knowledge-base/project/plans/2026-04-19-chore-aeo-presence-reaudit-after-pr-2596-plan.md"; do
  jq -r --arg path "$path" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

## Acceptance Criteria

### Pre-merge (PR)

- [x] `growth-strategist.md` GEO/AEO Content Audit section contains BOTH template skeletons (SAP with weights 40/35/25 + grading scale; 8-component AEO diagnostic with weights summing to 100). Narrative sub-signal guidance under each SAP dimension is preserved below the table skeleton.
- [x] `scheduled-growth-audit.yml` Step 2 prompt inlines the identical templates, indented inside the `prompt: |` block (no column-0 lines, no heredocs — `hr-in-github-actions-run-blocks-never-use`).
- [x] Re-audit runbook Phase 2 bash parser: (a) grep matches both `"Presence & Third-Party Mentions"` and `"**Presence**"` labels and requires `NF >= 5` to exclude legend rows; (b) score parser trims whitespace and accepts both `40` (bare integer) and `20/25` (fraction); (c) error messages include `$PRESENCE_LINE` when parsing fails. A worked-example comment block documents the threshold translation for both rubric eras.
- [ ] PR body includes `Closes #2679` and `Closes #2615` on their own lines (`wg-use-closes-n-in-pr-body-not-title-to`), with a short verification paragraph for #2615 that backtick-wraps all `#NNNN` references to avoid `cq-prose-issue-ref-line-start`.

### Post-merge (operator)

- [ ] `gh workflow run scheduled-growth-audit.yml` triggered (`wg-after-merging-a-pr-that-adds-or-modifies`); poll to completion.
- [ ] Deterministic validator passes against the new audit file:

  ```bash
  AUDIT=$(ls -1 knowledge-base/marketing/audits/soleur-ai/*-aeo-audit.md | sort | tail -n 1)
  grep -qE "^\| \*\*Structure\*\* +\| 40 +\|" "$AUDIT" || { echo "FAIL: Structure row missing"; exit 1; }
  grep -qE "^\| \*\*Authority\*\* +\| 35 +\|" "$AUDIT" || { echo "FAIL: Authority row missing"; exit 1; }
  grep -qE "^\| \*\*Presence\*\*  +\| 25 +\|" "$AUDIT" || { echo "FAIL: Presence row missing"; exit 1; }
  n=$(grep -cE "^\| (FAQ structure|Answer density|Statistics|Source citations|Conversational|Entity clarity|Authority / E-E-A-T|Citation-friendly)" "$AUDIT")
  [[ "$n" == "8" ]] || { echo "FAIL: 8-component diagnostic has $n/8 rows"; exit 1; }
  echo "OK: pinned template held"
  ```

- [ ] If the validator fails: file a P1 follow-up (`priority/p1-high`, `type/chore`, `domain/marketing`) titled `chore(aeo): pinned prompt dropped — investigate agent compliance`. Do NOT silently accept the drift.
- [ ] `#2679` and `#2615` are both CLOSED.

## Implementation Phases

### Phase 1 — Agent doc update

Edit `plugins/soleur/agents/marketing/growth-strategist.md` GEO/AEO Content Audit section (lines ~45-120). Add a preamble mandating both tables, then embed the two skeletons below. Keep the existing narrative sub-signal guidance for each SAP dimension as rubric commentary beneath the skeletons.

**SAP scorecard template:**

```markdown
| Dimension       | Weight | Score   | Weighted | Notes |
|-----------------|--------|---------|----------|-------|
| **Structure**   | 40     | <n>/40  | <n>      | ...   |
| **Authority**   | 35     | <n>/35  | <n>      | ...   |
| **Presence**    | 25     | <n>/25  | <n>      | ...   |
| **Total**       | 100    |         | <n>      | <letter grade> |
```

Grading scale: `A ≥90, B 80-89, B+ 75-79, C 60-74, D <60`.

**8-component AEO diagnostic template:**

```markdown
| Component                       | Weight | Score  | Notes |
|---------------------------------|--------|--------|-------|
| FAQ structure & FAQPage schema  | 20     | <n>/20 | ...   |
| Answer density / extractability | 15     | <n>/15 | ...   |
| Statistics & specificity        | 15     | <n>/15 | ...   |
| Source citations                | 15     | <n>/15 | ...   |
| Conversational readiness        | 10     | <n>/10 | ...   |
| Entity clarity                  | 10     | <n>/10 | ...   |
| Authority / E-E-A-T             | 10     | <n>/10 | ...   |
| Citation-friendly structure     | 5      | <n>/5  | ...   |
| **Total**                       | 100    |        | <n>/100 |
```

**Why pin in the agent doc:** manual `/soleur:growth aeo` invocations use the agent doc, not the workflow prompt. Workflow-only pinning leaves ad-hoc runs free to drift.

### Phase 2 — Workflow prompt update

Edit `.github/workflows/scheduled-growth-audit.yml` Step 2 (lines ~98-109). Stay inside `prompt: |` with 12-space base indentation. Replace the open-ended `"produce a structured scoring table"` with explicit template text enumerating both tables, weights, the grading scale, and a directive that both tables are mandatory. Prompt text may mirror the tables in Phase 1 but expressed as natural-language requirements (avoid embedding raw markdown skeletons; the workflow prompt is Task input, not a table to copy).

Constraint: the prompt is YAML text, not a shell `run:` block. `hr-in-github-actions-run-blocks-never-use` addresses heredocs in `run:` blocks; a YAML `prompt: |` scalar with consistent indentation is fine.

### Phase 3 — Runbook parser update

Edit `knowledge-base/project/plans/2026-04-19-chore-aeo-presence-reaudit-after-pr-2596-plan.md` Phase 2 extraction block.

1. **Label match:** replace single-pattern grep with alternation that also requires `NF >= 5` columns (excludes legend rows):

   ```bash
   PRESENCE_LINE=$(awk -F'|' 'NF >= 5 && $2 ~ /^ *(\*\*)?Presence(\*\*)?( & Third-Party Mentions)? *$/ { print; exit }' "$LATEST")
   ```

2. **Score parsing:** trim whitespace, accept both bare and fraction forms, include line in error:

   ```bash
   SCORE_CELL=$(echo "$PRESENCE_LINE" | awk -F'|' -v c="$SCORE_COL" '{ gsub(/^[ \t]+|[ \t]+$/, "", $c); print $c }')
   SCORE_CELL="${SCORE_CELL// /}"  # strip inline whitespace (handles "20 / 25" after markdownlint reflow)
   if [[ "$SCORE_CELL" =~ ^([0-9]+)/([0-9]+)$ ]]; then
     NUM="${BASH_REMATCH[1]}"; DEN="${BASH_REMATCH[2]}"
     PRESENCE_PCT=$(awk "BEGIN { printf \"%.0f\", ($NUM / $DEN) * 100 }")
   elif [[ "$SCORE_CELL" =~ ^[0-9]+$ ]]; then
     PRESENCE_PCT="$SCORE_CELL"  # old rubric: bare 0-100
   else
     echo "ERROR: unrecognized Presence score format: '$SCORE_CELL' in line: $PRESENCE_LINE" >&2
     exit 6
   fi
   ```

3. **Threshold check:** PASS/PARTIAL/FAIL branching compares `PRESENCE_PCT` (not `PRESENCE_SCORE`) against 55; re-run band is `52 <= PRESENCE_PCT <= 58`.

4. **Documentation header** at top of Phase 2:

   > Score extraction normalizes to percentage-of-category across rubric eras. Old format: bare `40` → `PRESENCE_PCT=40`. New format: `20/25` → `PRESENCE_PCT=80`. The issue's `≥55` threshold applies uniformly.

5. **Test Scenarios row:** *"Historical audit with `20/25` format → `PRESENCE_PCT=80` → PASS."*

### Phase 4 — Post-merge verification (single step)

After merge, run:

```bash
gh workflow run scheduled-growth-audit.yml
# Poll until the audit PR merges, then run the Acceptance Criteria validator above.
```

If the validator passes, done. If it fails, file the P1 follow-up per Acceptance Criteria.

## Files to edit

- `plugins/soleur/agents/marketing/growth-strategist.md` — GEO/AEO Content Audit section.
- `.github/workflows/scheduled-growth-audit.yml` — Step 2 prompt block.
- `knowledge-base/project/plans/2026-04-19-chore-aeo-presence-reaudit-after-pr-2596-plan.md` — Phase 2 extraction and Test Scenarios.

## Files to create

None.

## Test Scenarios

Infrastructure-only change (prompt engineering + markdown). `cq-write-failing-tests-before` is exempt. Verification is the post-merge deterministic validator (see Acceptance Criteria post-merge block).

| Scenario | Expected |
|---|---|
| Post-merge audit run produces both tables | Validator passes |
| Post-merge audit drops a table | Validator fails; P1 follow-up filed |
| Runbook parser against 2026-04-21 audit | `PRESENCE_PCT=80`, PASS branch |
| Runbook parser against 2026-04-18 audit | `PRESENCE_PCT=40`, FAIL branch (historical) |

## Risks

- **Agent non-compliance.** LLMs aren't fully deterministic; the pinned prompt may still be dropped. Mitigation: deterministic validator in Phase 4 surfaces drift immediately. Two failures within two runs → escalate to moving audit generation out of agent-prose (future work).
- **Threshold interpretation is load-bearing.** The `≥55` translation assumes both rubric eras measure percentage-of-category. Documented with worked example (Context section) so the comparison survives future audit-format changes. If a future rubric abandons per-category scoring entirely, this plan's verification approach no longer applies and the runbook needs a wider rewrite.

## Non-Goals

- New audit workflow or sub-command.
- Retroactive re-scoring of audits before 2026-04-22.
- Changes to `seo-aeo-analyst.md` (separate agent, out of scope).
- Off-site Presence work (tracked in #2599, #2600, #2601, #2602, #2603, #2604).
- Changing SAP weights or grading scale cutoffs.
- Moving audit generation out of agent-prose into a deterministic template-filler (future work if drift recurs).

## Domain Review

**Domains relevant:** Marketing (CMO — carried forward from brainstorm)

### Marketing (CMO)

**Status:** carried forward from `knowledge-base/project/brainstorms/2026-04-22-aeo-rubric-reconcile-2679-brainstorm.md` Domain Assessments.

**Assessment:** Rubric pinning is a CMO operational concern (content audit determinism). SAP remains the canonical public-facing framework; the 8-component rubric is the diagnostic layer. Dual-template matches how the auditor already produced both framings. No brand-guide implications. No user-facing copy.

**Specialists:** none recommended in brainstorm.

**No Product/UX Gate:** no new user-facing pages, no new components, no new flows. Agent-facing prompt engineering only.

## Out of Scope

- Code changes (no production paths touched).
- Database migrations, Terraform, infrastructure.
- New automated tests.
- Non-Marketing domain agents.

## Definition of Done

- Three files edited per specification.
- PR is open, CI green, review signed off.
- PR body includes `Closes #2679` + `Closes #2615` + verification paragraph citing `knowledge-base/marketing/audits/soleur-ai/2026-04-21-aeo-audit.md` and the Presence `20/25 (80%)` numerical proof.
- Post-merge validator (Acceptance Criteria block) passes against the next scheduled-growth-audit run; otherwise P1 follow-up filed.
- `#2679` and `#2615` both CLOSED.

## How to resume / hand off

1. Read this plan top-to-bottom.
2. Read the brainstorm at `knowledge-base/project/brainstorms/2026-04-22-aeo-rubric-reconcile-2679-brainstorm.md`.
3. Run `skill: soleur:work knowledge-base/project/plans/2026-04-22-chore-aeo-rubric-reconcile-plan.md` to execute Phases 1–3.
4. Run `skill: soleur:ship` to open/mark-ready the PR and execute Phase 4 post-merge.
