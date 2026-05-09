---
date: 2026-05-09
issue: "#3489"
type: docs-cleanup
classification: docs-only
requires_cpo_signoff: false
related_pr: "#3486"
related_learning: "knowledge-base/project/learnings/2026-05-09-llm-authored-plans-cite-fabricated-and-retired-rule-ids.md"
---

# Fix: Retired-rule-id sweep for `cq-gh-issue-label-verify-name`

## Overview

The AGENTS.md rule `cq-gh-issue-label-verify-name` was retired on 2026-04-23 (per `scripts/retired-rule-ids.txt`: "gh rejects invalid --label with clear error before issue creation"). Five active citations remain in skill, command, and runbook files that still treat it as if it were a live AGENTS.md rule. The convention the rule encoded (verify GitHub labels exist before citing) is still valid — it now lives in the planning skills as Sharp Edges and as `deepen-plan` AC items. PR #3486 established the inline-fix pattern on `deepen-plan/SKILL.md:556`. This plan sweeps the remaining four active files using the same pattern.

A separate finding surfaced during planning: the runbook line that contains the target citation also contains **four other retired rule IDs** (`cq-ci-steps-polling-json-endpoints-under`, `cq-workflow-pattern-duplication-bug-propagation`, `hr-in-github-actions-run-blocks-never-use`, `hr-github-actions-workflow-notifications`). Folding them into the same edit is the right call (same line, same fabrication class, same fix shape — see Open Code-Review Overlap below).

Historical citations under `knowledge-base/project/{learnings,plans}/**` are out of scope and remain as-of-their-date accurate.

## User-Brand Impact

**If this lands broken, the user experiences:** No user-facing impact — these are operator-facing skill, command, and runbook files. Worst case is a broken-link-style citation in an internal doc the operator may grep.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — no user data, auth, or payment surfaces touched. Pure documentation cleanup.

**Brand-survival threshold:** none

**Reason (threshold=none + sensitive-path scan):** Edits are restricted to `plugins/soleur/{commands,skills}/*.md` and `knowledge-base/engineering/ops/runbooks/*.md`. No `apps/`, no auth/payment paths, no schema. Sensitive-path regex from preflight Check 6 does not match.

## Research Reconciliation — Spec vs. Codebase

| Issue body claim | Reality | Plan response |
|---|---|---|
| 5 active citations across 4 files | Verified — `grep -rEn "cq-gh-issue-label-verify-name"` in `plugins/`, `knowledge-base/engineering/` returns exactly 5 hits (after excluding the already-fixed `deepen-plan/SKILL.md:556` from PR #3486). | Use the issue's enumerated list verbatim. |
| Pattern to follow: PR #3486 inline fix on `deepen-plan/SKILL.md:556` | Verified — `Read deepen-plan/SKILL.md:556` shows: dropped attribution, parenthetical noting retirement, **Why** still cites the canonical PR. | Replicate this shape per site. |
| Historical citations in `knowledge-base/project/{learnings,plans}/**` predate retirement, leave alone | Verified by inspection — these are point-in-time records of what an AGENTS.md rule said when the plan/learning was authored. | Out of scope, no edits to these directories. |
| Issue lists 1 retired rule on `cloud-scheduled-tasks.md:375` | **Reality is wider** — same line contains 4 other retired rule IDs (`cq-ci-steps-polling-json-endpoints-under`, `cq-workflow-pattern-duplication-bug-propagation`, `hr-in-github-actions-run-blocks-never-use`, `hr-github-actions-workflow-notifications`). All retired 2026-04-23 / 2026-04-24. The runbook is the same fabrication class on the same physical line. | Fold the 4 sibling retirements into the same edit. Document in Open Code-Review Overlap section. Replace each with its canonical replacement (skill / reference file) or drop the citation if it's now domain-scoped. |

## Files to Edit

1. `plugins/soleur/commands/go.md` — line 40 (1 citation)
2. `plugins/soleur/skills/drain-labeled-backlog/SKILL.md` — lines 30 and 64 (2 citations)
3. `plugins/soleur/skills/plan/SKILL.md` — line 721 (1 citation, inside a Sharp Edges entry)
4. `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` — line 375 (5 retired rule IDs on the same line)

## Files to Create

None.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --json number,title,body --limit 200` and grepped each planned file path against issue bodies.

- **#3489 (this issue)** explicitly names all four files. Self-referential — closes on merge.
- No other open `code-review` issues touch these paths. The `cloud-scheduled-tasks.md` widening (4 sibling retired IDs) is a fold-in decision, not a separate scope-out — it's the same fabrication class on the same line, and review of this PR would flag it anyway. Not filing a separate issue: the cost of folding in is one extra edit; the cost of deferring is a second PR for the same line.

**Disposition:** **Fold in** — extend scope to include the 4 sibling retired rule IDs on `cloud-scheduled-tasks.md:375`. Same line, same retirement window (2026-04-23 / 2026-04-24), same fix shape.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `plugins/soleur/commands/go.md:40` — `cq-gh-issue-label-verify-name` citation removed; rationale inlined ("verified via `gh label list`") or replaced with a pointer to the convention's living home in the planning skills. No AGENTS.md attribution remains.
- [ ] `plugins/soleur/skills/drain-labeled-backlog/SKILL.md:30` and `:64` — both citations removed. Replace with inline rationale referencing `gh label list` validation. The drain-labeled-backlog skill now owns this convention; no upstream attribution needed.
- [ ] `plugins/soleur/skills/plan/SKILL.md:721` — the `Cited rule: cq-gh-issue-label-verify-name (...)` parenthetical is rewritten to drop the retired ID. Add a brief note that the convention now lives in the deepen-plan AC (line 556). The `**Why:** PR #3378` block is preserved verbatim.
- [ ] `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md:375` — all 5 retired rule IDs removed from the `AGENTS.md rules:` enumeration. Each replaced with a pointer to its canonical owner per `scripts/retired-rule-ids.txt`:
  - `hr-in-github-actions-run-blocks-never-use` → `plugins/soleur/skills/ship/references/ci-workflow-authoring.md`
  - `hr-github-actions-workflow-notifications` → same reference
  - `cq-ci-steps-polling-json-endpoints-under` → same reference
  - `cq-workflow-pattern-duplication-bug-propagation` → same reference
  - `cq-gh-issue-label-verify-name` → drop AGENTS.md attribution; convention now lives in `plan/SKILL.md` Sharp Edges + `deepen-plan/SKILL.md:556` AC.
- [ ] Verification grep passes: `grep -rEn "cq-gh-issue-label-verify-name" --include="*.md" plugins/ knowledge-base/engineering/` returns zero hits after the sweep. (Citations under `knowledge-base/project/{learnings,plans}/**` are out of scope and remain.)
- [ ] Sibling-retired-ID verification grep passes for the runbook line: `grep -E "(cq-ci-steps-polling-json-endpoints-under|cq-workflow-pattern-duplication-bug-propagation|hr-in-github-actions-run-blocks-never-use|hr-github-actions-workflow-notifications)" knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` returns zero hits.
- [ ] `lefthook run pre-commit` passes (covers `lint-rule-ids.py`, markdown lint, etc.).
- [ ] PR body uses `Closes #3489` on its own body line. No auto-close keywords elsewhere in title or body. (Per `wg-use-closes-n-in-pr-body-not-title-to`.)

### Post-merge (operator)

None — this is a docs-only PR with no operator actions, terraform applies, or external service syncs.

## Test Strategy

No new tests added. The verification path is the two grep commands in Acceptance Criteria — they prove the absence of every retired ID at the file scope. The `lint-rule-ids.py` lefthook hook covers AGENTS.md immutability invariants on the rule registry side; this PR does not modify AGENTS.md or `scripts/retired-rule-ids.txt`.

The existing convention is preserved by the deepen-plan rule-ID verification AC (`deepen-plan/SKILL.md:557`) — any future plan citing a retired ID will be caught at deepen-plan time.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is a documentation-only sweep correcting retired-ID citations in skill, command, and runbook files. No product, marketing, legal, finance, sales, support, or operations decisions involved. CTO-domain implications are nil because no architecture, code, schema, or runtime behavior changes.

## Risks

- **Low — wording drift across the 4 sites.** Mitigation: each replacement uses the same shape (drop AGENTS.md attribution, point to the convention's living home, preserve any PR/learning citation). Reviewer can compare the four edits side-by-side.
- **Low — sibling retired IDs in `cloud-scheduled-tasks.md` not in original issue scope.** Mitigation: documented in Research Reconciliation table and Open Code-Review Overlap section. Folding in is justified by the cost calculus (one edit vs. a future second PR for the same line).
- **None for blast radius.** Files touched are operator-facing only; no production code, no auth, no schema.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's threshold is `none` with an explicit reason — meets the gate.
- When dropping an AGENTS.md rule citation, do not silently delete the surrounding rationale. The cited behavior is still load-bearing for the reader; rewrite the prose so the rationale stands without the citation. Pattern from PR #3486: drop the `(rule cq-...)` parenthetical, inline a one-clause justification, and (where helpful) point to where the convention now lives.
- The runbook citation includes 4 retired sibling rules from the GitHub Actions / CI domain (`hr-in-github-actions-...`, `cq-ci-steps-polling-...`, etc.). Their canonical replacement is `plugins/soleur/skills/ship/references/ci-workflow-authoring.md` — verify that file still exists and still encodes the conventions before replacing the citation.
- Do not extend scope to `knowledge-base/project/{learnings,plans}/**` even if a grep pulls in matches. Those are point-in-time historical records and editing them rewrites the past — a different anti-pattern.

## Implementation Notes

The four edits are mechanical and independent. Suggested order (lightest first to warm up the pattern, runbook last because it has the most replacements):

1. `plugins/soleur/commands/go.md:40` — single occurrence, simplest case.
2. `plugins/soleur/skills/drain-labeled-backlog/SKILL.md:30, 64` — two occurrences in same file.
3. `plugins/soleur/skills/plan/SKILL.md:721` — single occurrence inside a Sharp Edges entry; preserve the surrounding **Why** block verbatim.
4. `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md:375` — 5 retired IDs on one line; replace each with its canonical owner pointer.

Each edit is small enough to fit in one `Edit` tool call. Total expected diff: ~40-60 lines changed across 4 files.
