---
title: "docs(audit): GitHub Code Quality baseline on main 30407a8597"
type: docs
date: 2026-10-15
slug: github-code-quality-baseline-audit
branch: feat-one-shot-code-quality-baseline
issue: 10331
lane: single-domain
---

# docs(audit): GitHub Code Quality baseline on main 30407a8597

Add the finished GitHub Code Quality baseline audit (22 rules, 169 open findings on `main` at `30407a8597`) to the knowledge base as one new markdown file. Docs-only. The draft is already written; this plan copies it verbatim and gates it through the repo's markdown and KB checks. PR body references the tracker as `Ref #10331` only, with no close keyword for any issue (the tracker stays open for the triage and linter-wiring work it describes). PR title: `docs(audit): GitHub Code Quality baseline on main 30407a8597`. Label `semver:patch`.

## Enhancement Summary

**Deepened on:** 2026-10-15 (proportionate pass; no agent fan-out, per the minimal-detail scope hint)
**Gates run:** User-Brand Impact (present, threshold `none`, no sensitive path), PAT-shaped variable sweep (no hits), Scope Check (one compliant section), Observability (pure-docs, skipped), Encryption Posture, Guard Contract, UI-wireframe, Downtime and ADR/C4 (not triggered: one new markdown file).

### Key Findings

- The draft already passes the pinned markdown lint: `markdownlint-cli2 --config .markdownlint.json <draft>` reported `0 issues in 0 files`, so a clean verbatim copy is the expected outcome and Phase 2 should be a verification, not an edit.
- Frontmatter keys in the draft (`title, date, type, issue, status, last_updated`) match the sibling `2026-07-20-cron-liveness-cohort-audit.md`; the draft omits the optional `adr:` key, which the sibling uses only when an ADR exists.
- The repo's own entry point for the lint is `scripts/markdown-lint.sh` (pinned binary, scope from `.markdownlintignore`); run that, not an unpinned `npx`.

## Research Insights

- **Premise validation.** #10331 is OPEN, no closing PR; commit `30407a8597` exists locally; draft file present (133 lines, 10756 bytes); sibling audits live in `knowledge-base/engineering/audits/` (latest: `2026-07-20-cron-liveness-cohort-audit.md`) with frontmatter keys `title, date, type: audit, issue, status, last_updated`, which the draft already carries. No external premises beyond these.
- **Property List.** (1) The baseline is findable in the KB audits directory. (2) It passes the repo markdown lint and KB frontmatter conventions. (3) The PR does not close #10331.
- **Cut List.** No mechanism proposed beyond a file copy; nothing to cut. No CI, Actions-settings, `ci.yml`, `CI_PUSH_DEDUPE` or `CI_DRAFT_LIGHT` change is in scope.
- **Lint surface.** `.markdownlint.json` (MD013/MD024/MD025/MD033/MD040/MD041 off), `scripts/markdown-lint.sh`. KB index regeneration is handled by existing `scripts/ensure-kb-index.sh` tooling if it objects.
- **Skipped on purpose.** Repo/learnings research fan-out, external research, community discovery, functional overlap, domain leaders: single new markdown file, no code, UI, infra or sensitive path. Domain Review below records `none`.

## Files to Create

- `knowledge-base/engineering/audits/2026-10-14-github-code-quality-baseline.md` (verbatim copy of the scratchpad draft `cq-baseline.md`)

## Files to Edit

None.

## Open Code-Review Overlap

None (the only file touched is new; no open code-review issue can reference it).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing; at worst a malformed internal audit page in the KB.
- **If this leaks, the user's data is exposed via:** no vector; the file lists rule names, counts and repo-relative paths from a public-facing code-scanning view, no secrets or user data.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** a docs-only internal audit touches no sensitive path and no user surface, so `none` rather than `aggregate pattern`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected; internal engineering audit document.

## Implementation Phases

1. Copy the draft verbatim to the target path (`cp`), then `diff` source and target to confirm byte equality.
2. Run `scripts/markdown-lint.sh` (or `npx markdownlint-cli2` on the file) and the KB frontmatter/index checks. If any check objects, change formatting only (blank lines, table pipes, trailing whitespace) and record exactly what changed. Do not edit findings, counts, or prose.
3. Confirm the diff is exactly one added file.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "copy it verbatim to knowledge-base/engineering/audits/2026-10-14-github-code-quality-baseline.md" | Files to Create, Phase 1 | mapped |
| 2 | "if a repo lint ... objects to the file, fix only the formatting and report what changed" | Phase 2 | mapped |
| 3 | "PR body says Ref #10331 only, no close keywords for any issue" | AC4 | mapped |
| 4 | "Nothing else in the diff" | Phase 3, AC3 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Copy draft to target path | "copy it verbatim to knowledge-base/engineering/audits/2026-10-14-github-code-quality-baseline.md" | asked |
| Format-only lint fixes | "fix only the formatting and report what changed" | asked |
| Single-file diff check | "Nothing else in the diff" | asked |

### Split Assessment

- Subsystems touched: 1 (knowledge-base/engineering/audits)
- Planned files: 1 | Estimated changed lines: 133
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1: `knowledge-base/engineering/audits/2026-10-14-github-code-quality-baseline.md` exists and `diff` against the scratchpad draft is empty, or differs only by formatting fixes listed in the PR body.
- [ ] AC2: `scripts/markdown-lint.sh` reports no errors for the file; frontmatter keys match sibling audits (`title, date, type, issue, status, last_updated`).
- [ ] AC3: `git diff --name-status origin/main...HEAD` shows only the new audit file plus this plan's own artifacts under `knowledge-base/project/{plans,specs}/`; no `ci.yml`, workflow, or Actions-settings change.
- [ ] AC4: PR title is `docs(audit): GitHub Code Quality baseline on main 30407a8597`, body contains `Ref #10331` and no `Closes`/`Fixes`/`Resolves` keyword, label `semver:patch`.
- [ ] AC5: The findings (22 rules, 169 findings) are unchanged from the draft.

## Test Scenarios

- Lint run on the new file exits 0.
- `diff` of source vs target shows no content change (formatting-only edits, if any, are enumerated).
- `grep -ciE '(close[sd]?|fix(e[sd])?|resolve[sd]?) #' ` on the PR body returns 0.
