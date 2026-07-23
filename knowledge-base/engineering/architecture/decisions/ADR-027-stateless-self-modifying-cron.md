---
title: Stateless self-modifying cron — plain Anthropic API, no claude-code-action wrapper
status: active
date: 2026-05-11
---

# ADR-027: Stateless self-modifying cron — plain Anthropic API, no claude-code-action wrapper

> Note: the v1 plan reserved "ADR-021" for this decision. Numbering was
> reused by `ADR-021-kb-binary-serving-pattern.md` before this ADR was
> drafted; this ADR is filed at the next available slot (027) to avoid
> renumbering shipped ADRs.

## Context

Issue #2720 (parent #2718; supersedes #421) introduces Layer 2 of the
self-healing-workflow design: a weekly cron that clusters
`knowledge-base/project/learnings/` and proposes skill or `AGENTS.core.md`
edits via draft PR. The architectural challenge is that the loop both
**consumes** workflow context (Anthropic API call to cluster learnings) and
**produces** workflow context (opens a PR, writes audit-log rows, applies a
diff). It is, by construction, a self-modifying CI loop.

The 5-agent plan-review panel (DHH, Kieran, Code Simplicity, Architecture,
SpecFlow re-validation) converged on a single architectural pivot from the v1
plan: drop the `claude-code-action` wrapper and call the Anthropic Messages
API directly via `curl`. The v1 plan used `claude-code-action@v1.0.101` and
dodged its post-step token revocation with a two-job split (`cluster` job →
`promote` matrix job), which forced four downstream complications:

1. **Matrix DOS** — the `cluster` job emitted a `clusters_json` output of
   unbounded length consumed as a matrix expansion by `promote`. A
   malformed or hostile clustering response could fan the matrix out
   indefinitely.
2. **Template injection** — every `matrix.cluster.*` field landed in a
   `run:` block. Kieran flagged 6 P1 injection vectors.
3. **Cluster-hash integrity gap** — the hash was trusted from the LLM's
   output and never re-derived against the source-learnings list it
   claimed to cover.
4. **Output handoff (Q1)** — the v1 plan never resolved how the
   `cluster` job would surface its JSON to `promote` given GitHub Actions
   `outputs:` 1MB string cap.

## Considered Options

- **Option A: Two-job split with `claude-code-action`.** v1 plan's
  approach. Token revocation forces the split; matrix expansion handles
  per-cluster PR opens. Pros: agent gets native Bash/Read tools; could
  read files at decision time. Cons: matrix DOS, template injection, hash
  integrity gap, unresolved output handoff. All four are architectural
  problems, not configuration choices.
- **Option B: Single-job + plain Anthropic API call (chosen).** No
  wrapper. Plain `curl https://api.anthropic.com/v1/messages` from the
  driver script. Single bash `while read` loop over clusters instead of a
  matrix. State derived entirely from `gh pr list --label
  self-healing/auto` queries — no `.github/promotion-*.json` state files.
  Pros: eliminates all four v1 problems; simpler arch; auditable; the
  prompt fits comfortably in one API call against the ~947-file corpus
  using path + first-10-lines summaries. Cons: loses the agent's general
  tool-use capability (no native Bash/Read); the agent sees the corpus as
  a single message and emits clustering JSON in its text response.
- **Option C: `peter-evans/create-pull-request`.** Off-the-shelf PR
  opener. Pros: no need to extend `bot-pr-with-synthetic-checks`. Cons:
  introduces a new third-party action dependency; no existing precedent
  in this repo; doesn't address the token-revocation problem (the
  Anthropic call would still need a wrapper or direct curl).

## Decision

**Option B.** The driver (`scripts/compound-promote.sh`) calls
`https://api.anthropic.com/v1/messages` directly. The workflow
(`.github/workflows/scheduled-compound-promote.yml`) is single-job and
iterates the clustering output via a bash `while read` loop, NOT a GitHub
Actions matrix.

State is derived stateless from the issue tracker:

- **Per-week cap** = `WEEK_CAP_DEFAULT - <open self-healing/auto PR count>`.
  Derived from `gh pr list --label self-healing/auto --state open --json
  number --jq length`. No `promotion-queue.json`.
- **Cooldown** = closed-PR count over last 30 days from the same `gh pr
  list` query family. No `promotion-cooldowns.json`.
- **Audit log** = append-only markdown table at
  `knowledge-base/project/learnings/promotion-log.md`. Live decision
  derived at read-time from `gh pr view --json state,merged` of the linked
  PR; rows are NEVER mutated (CLO non-repudiation requirement).

`.gitignore` defensively excludes any future `.github/promotion-*.json`
re-introduction.

Cluster-hash integrity is re-derived inside the workflow before PR creation:
`sha256(sorted(source_learnings))` computed locally, compared to the
LLM-supplied hash, and the cluster is refused on mismatch.

## Consequences

**Positive.**

- No template-injection surface in matrix expansions — there is no matrix.
- No state files means no recursion risk and no merge-conflict footgun
  when two operators interact with the loop simultaneously.
- Plain `curl` is auditable. The full HTTP request is visible in the
  driver script; the response shape is the documented Anthropic Messages
  API contract.
- Composite-action extension (`draft` / `skip-auto-merge` / `labels` inputs
  on `bot-pr-with-synthetic-checks`) lands as a backward-compatible
  addition usable by any future single-PR caller.

**Negative.**

- The clustering agent loses native tool use. It cannot grep the
  knowledge-base or read whole files at decision time. The driver
  pre-computes the summary corpus (path + first 10 lines) and passes it
  as a single message. If clustering quality drops below acceptable, the
  fallback is moving to Opus or switching to claude-code-action with the
  two-job split — and then revisiting the four v1 problems.
- The synthetic-checks step is duplicated between the workflow and
  `bot-pr-with-synthetic-checks` because the composite's branch-naming
  collides with the cluster-hash branch naming when the loop opens >1 PR
  per run. Acceptable duplication, documented in the workflow.

**Operationally neutral.**

- The Anthropic API call is gated by the existing `anthropic-preflight`
  composite, mirroring every other Anthropic-calling workflow in the
  repo. Monthly spend cap remains the same control point.

## Alternatives Considered (Rejected)

| Alternative | Rejected because |
|---|---|
| `claude-code-action` wrapper (two-job split) | Token revocation forces architectural contortions; matrix DOS, template injection, cluster-hash integrity, output handoff all become problems. Plain curl eliminates all four. |
| `peter-evans/create-pull-request` | No precedent in repo; doesn't address the wrapper problem (Anthropic call would still need direct curl or a separate wrapper). |
| Persistent state files (`promotion-queue.json`, `promotion-cooldowns.json`) | Workflow re-trigger risk; derivable from PR queries; single source of truth = the PRs themselves. |
| Push-to-main directly (constitution line 153 preference) | Brand-survival `single-user incident` threshold requires manual confirm. Draft PR + per-PR review is the load-bearing safety. |

## References

- Plan: `knowledge-base/project/plans/2026-05-11-feat-compound-promotion-loop-plan.md`
- Spec: `knowledge-base/project/specs/feat-compound-promotion-loop/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-11-compound-promotion-loop-brainstorm.md`
- Issue: #2720 (parent #2718; supersedes #421)
- Driver: `scripts/compound-promote.sh`
- Workflow: `.github/workflows/scheduled-compound-promote.yml`
- Operator runbook: `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md`
