---
feature: constraint-gates-v2-buildable
date: 2026-06-30
lane: cross-domain
brand_survival_threshold: single-user incident
parent_issue: 5765
closes: [5791, 5777]
status: scoped
brainstorm: knowledge-base/project/brainstorms/2026-06-30-constraint-gates-v2-buildable-brainstorm.md
---

# Spec: Constraint-gates v2 — buildable follow-ups

## Problem Statement

The shipped L1 constraint-gates suite (PR #5770, ADR-071) has two gaps among its six deferred
children (parent #5765):

1. Its CI error messages instruct a stranded non-technical founder to comment `/soleur fix constraints`
   to recover a tripped gate, but **no `issue_comment` handler exists** for that command — a broken
   promise (latent founder-deadlock if the gate is ever promoted to required). (#5791)
2. The import-boundary gate matches **direct** client→server-secret edges only, so a transitive
   `"use client"` → helper → server-secret import ships a server secret into the browser bundle
   undetected. (#5777)

## Goals

- **G1** Wire a secure `issue_comment`-triggered `/soleur fix constraints` recovery dispatcher (#5791).
- **G2** Extend the import-boundary gate to catch transitive client→helper→server-secret leaks (#5777).
- **G3** Correct the ADR reference in #5791's body (ADR-070 → ADR-071).

## Non-Goals

- **NG1** Promotion of the gate to a required branch-protection check (also blocked on deferred #5778).
- **NG2** #5774 body-validation contract gate — deferred (false-positive fragility; bare `.parse(` token
  collides with `JSON.parse`/`Date.parse`).
- **NG3** #5775 naming validator, #5776 lefthook pre-commit, #5778 multi-stack — re-eval criteria unmet.
- **NG4** Single bundled PR — these ship as two separate PRs by design.

## Functional Requirements

### #5791 — recovery dispatcher (PR 1)

- **FR1** New `.github/workflows/fix-constraints.yml`: `issue_comment` trigger; job `if` requires
  `github.event.issue.pull_request` AND `github.event.comment.body == '/soleur fix constraints'` (exact match).
- **FR2** Author gate: `github.event.comment.author_association` in `('OWNER','MEMBER','COLLABORATOR')`.
- **FR3** Head==base guard: skip when the PR head repo differs from base (forks cannot push;
  `GITHUB_TOKEN` is read-only on fork PRs).
- **FR4** Dispatch the agent (claude-code-action wiring per `cla.yml` precedent) to fix the import or run
  `--refresh-baseline`, then push to the PR's **own head ref** (`gh pr checkout`), never base/side branch.
- **FR5** On completion, comment the outcome back on the PR.
- **FR6** Update #5791's body / any artifact that cites ADR-070 to ADR-071.

### #5777 — transitive leak detection (PR 2)

- **FR7** Add a dependency-cruiser `to.reachable` rule in `apps/web-platform/.dependency-cruiser.cjs`
  scoped `from` `"use client"` modules `to` the server-secret tree.
- **FR8** Exclude type-only imports (`import type`) from the rule (erased at build → false positives).
- **FR9** Run a single `--refresh-baseline`; review the baseline diff for pre-existing transitive paths.
- **FR10** Negative + positive fixtures: a transitive client→helper→secret chain MUST fail; a type-only
  transitive chain MUST pass.

## Technical Requirements

- **TR1** #5791 MUST use plain `issue_comment` + explicit `gh pr checkout` — **NOT `pull_request_target`**
  (write-token + PR-head checkout under `pull_request_target` is the classic ACE exploit).
- **TR2** `permissions: contents: write, pull-requests: write` only.
- **TR3** `concurrency: group: fix-constraints-${{ github.event.issue.number }}`, `cancel-in-progress: false`.
- **TR4** Pass all PR-derived strings via `env:`, never inline `${{ }}` in `run:` (injection safety).
- **TR5** #5777 MUST reuse the shared runner `apps/web-platform/scripts/constraint-gates.sh` and pin the
  dependency-cruiser version identically to v1.

## Sequencing

PR 1 (#5791) first — independent, higher user-impact. PR 2 (#5777) second — no hard dependency on PR 1.
Both must merge before any future promotion-to-required PR.
