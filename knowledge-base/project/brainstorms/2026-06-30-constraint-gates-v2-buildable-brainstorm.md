---
date: 2026-06-30
topic: constraint-gates-v2-buildable
status: scoped
lane: cross-domain
brand_survival_threshold: single-user incident
parent_issue: 5765
scoped_issues: [5791, 5777]
deferred_issues: [5774, 5775, 5776, 5778]
---

# Brainstorm: Constraint-gates v2 — buildable follow-ups (#5791 + #5777)

## What We're Building

Two independent improvements to the shipped L1 constraint-gates suite (v1 = PR #5770, ADR-071),
selected from the six deferred children of parent #5765:

1. **#5791 — `/soleur fix constraints` recovery comment-dispatcher.** An `issue_comment`-triggered
   GitHub Actions workflow that, on a PR comment `/soleur fix constraints` from an authorized actor,
   dispatches the agent to fix-or-`--refresh-baseline` the tripped gate and push a clean commit to
   the PR's head branch. Today the gate's error messages instruct a stranded founder to comment that
   command, but **no handler exists** (wording is honestly marked "planned, not yet wired" across the
   `.cjs`, shared runner, both workflow copies, and ADR-071).

2. **#5777 — transitive client→helper→server-secret leak detection.** The shipped gate matches
   **direct** edges only; a `"use client"` module that imports a non-client helper which imports a
   server-secret module is a real bundle leak the current gate is blind to. Add a dependency-cruiser
   `to.reachable` rule and re-baseline once.

## Why This Approach

- **Both stand alone.** Premise-checking established that promotion of the gate to a **required**
  branch-protection check is blocked on **both** #5791 **and** the deferred #5778 (multi-stack /
  external-repo, criteria unmet until a 2nd product codebase exists). So #5791 is necessary-but-not-
  sufficient for promotion — neither item is being built "to turn the gate on." Each is justified on
  its own merits: #5791 makes a broken promise to non-technical founders true and removes the latent
  founder-deadlock; #5777 closes a real security blind spot in the shipped gate.
- **#5774 deferred** (not built): plan-review flagged the body-validation gate as a false-positive
  generator (the bare `.parse(` token collides with `JSON.parse(`/`Date.parse(`). A flaky contract
  gate erodes trust in the whole suite. Stays deferred until the schema-detection heuristic is robust.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Scope = #5791 + #5777 only | Two highest-value buildable items; #5774 deferred (fragile), #5775/#5776/#5778 stay deferred (criteria unmet) |
| 2 | **Two separate PRs**, not one | Different blast radii: #5791 is workflow YAML (security-sensitive review), #5777 is a `.cjs` rule + baseline-churn diff. Bundling buries the workflow review under baseline noise |
| 3 | Build order: #5791 first, then #5777 | No hard dependency; #5791 is the smaller, independent, higher-user-impact change |
| 4 | #5791 uses plain `issue_comment` + explicit `gh pr checkout` — **NOT `pull_request_target`** | A write-token + PR-head checkout under `pull_request_target` is the classic ACE exploit |
| 5 | #5791 author gate: `author_association in (OWNER, MEMBER, COLLABORATOR)` | Stricter than `cla.yml`'s allowlist because this workflow *pushes code* |
| 6 | #5777 `to.reachable` scoped `from` "use client" → `to` server-secret tree; exclude type-only imports | Bounds the re-baseline churn; `import type` is erased at build → would be a false positive |
| 7 | Fix the ADR citation in #5791's body (cites ADR-070; correct = **ADR-071**) | ADR-070 is L3 phase-tool-scoping; the constraint-gates ADR is ADR-071 |

## Verified Premises (no re-verification needed at plan time)

- **#5791 claim holds**: only `issue_comment` workflows on main are `cla.yml`, `cla-evidence.yml`,
  `merge-queue-cla-synthetics.yml` (all CLA). No `/soleur fix constraints` handler exists.
- **v1 honest**: PR #5770 (merged 2026-06-30T17:22:57Z) downgraded all recovery wording to "planned
  (#5791), not yet wired." No false capability claim is live.
- **Gate is informational**: `constraint-gates` is NOT in main's required-status contexts → the
  founder-deadlock is **latent, not live**.
- Parent #5765 is CLOSED. Plan doc and ADR-071 exist on main.

## #5791 Security Model (carry-forward — concrete guardrails)

- Trigger: `issue_comment`; job `if` requires `github.event.issue.pull_request` AND
  `github.event.comment.body == '/soleur fix constraints'` (exact, not `contains`).
- Author: `github.event.comment.author_association` in `('OWNER','MEMBER','COLLABORATOR')`.
- Head==base guard: skip when head repo differs (forks can't push; `GITHUB_TOKEN` read-only on fork PRs).
- Push target: the PR's **own head ref** via `gh pr checkout` — never base, never a side branch.
- `permissions: contents: write, pull-requests: write` only.
- `concurrency: group: fix-constraints-${{ github.event.issue.number }}`, `cancel-in-progress: false`.
- Pass all PR-derived strings via `env:`, never inline `${{ }}` in `run:`.

## #5777 Approach (carry-forward)

- dep-cruiser `to.reachable` from `"use client"` modules to the server-secret tree.
- Exclude type-only imports (`import type`) via `dependencyTypes`/type-only filtering — erased at build.
- Single `--refresh-baseline` after the rule lands; review the baseline diff for pre-existing transitive paths.

## Open Questions

- None blocking. Each item is independently specified; implement #5791, then #5777, each as its own PR.
- Both must merge before any future promotion-to-required PR (which also waits on #5778).

## User-Brand Impact

- **Artifact:** the `/soleur fix constraints` recovery dispatcher (#5791) and the client→server-secret
  import-boundary gate (#5777).
- **Vector:** a stranded non-technical founder hits a tripped gate whose error tells them to run a
  command that does nothing (founder-deadlock); or a server secret ships into the browser bundle via a
  transitive import the gate cannot see (silent credential exposure).
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Engineering (platform-strategist)

### Engineering

**Summary:** Confirmed the build/defer ranking (#5791 → #5777 → defer #5774) and supplied the concrete
`issue_comment` security model (author_association gating, head==base guard, no `pull_request_target`,
push to PR head). Flagged the #5777 re-baseline churn risk and the type-only-import false-positive class.
Recommended two separate PRs to keep the security-sensitive workflow review out of baseline-churn noise.
