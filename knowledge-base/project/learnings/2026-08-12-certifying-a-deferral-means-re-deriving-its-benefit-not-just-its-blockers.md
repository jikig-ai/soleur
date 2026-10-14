---
title: Certifying a deferral means re-deriving its BENEFIT, not just its blockers
date: 2026-08-12
category: workflow-patterns
module: brainstorm
issue: 7493
pr: 7504
tags: [adr, deferral, premise-validation, terraform, github-rulesets, brainstorm]
---

# Learning: certifying a deferral means re-deriving its benefit, not just its blockers

## Problem

ADR-182 recorded two deferred alternatives for protecting `jikig-ai/soleur-marketplace`, each
with named blockers. #7493 was filed as the prevention half and repeated the ADR's framing.

The existing brainstorm guidance ("A governing ADR already contains the design — re-verify each
*deferral trigger* against LIVE state") covers exactly one half of a deferral record. Both of
ADR-182's blockers resolved cleanly against the live GitHub API:

- "the App needs `contents: write` on that repo" → the `soleur-ai` App carries `contents: write`
  **and** `administration: write` at `repository_selection: all`.
- "an untested ruleset could lock the sole maintainer out" → both sibling rulesets already carry
  `OrganizationAdmin` (`actor_id 0`) and `RepositoryRole 5` bypass actors; the sole maintainer
  holds `admin: true`.

Blockers clear → ship it. That is where the reasoning would normally stop.

## Root cause

**The deferral's stated BENEFIT was false, and nothing in the workflow re-checks it.**

ADR-182 justified `github_repository_file` with: *"drift would be auto-reconciled by the next
apply instead of surfacing as an issue up to 24 h later."* But `apply-github-infra.yml` has **no
`schedule:`** — it fires only on `push: main` touching `infra/github/*.tf`,
`infra/github/.terraform.lock.hcl`, or `tests/scripts/lib/destroy-guard-filter.jq`, plus
`workflow_dispatch`. An out-of-band manifest edit therefore sits unreconciled until somebody
happens to edit the infra root, which could be weeks. The *daily* drift check is the faster
signal.

Shipping on cleared blockers alone would have bought **ownership without timeliness**, while the
ADR and the issue both asserted timeliness as the reason to ship.

The asymmetry is what makes this a durable trap: a blocker is written as a *risk* and reads as
something to check, while a benefit is written as a *fact* and reads as the settled reason the
option is worth doing. A reader inherits the benefit as the premise for the whole decision, and
it is the half nothing re-derives.

## Solution

Certify **both halves** of a deferral record. For every deferred alternative, name the command
that falsifies its claimed benefit and run it — the same discipline already applied to blockers:

```bash
# The claim: "auto-reconciled by the next apply"
# The falsifier: does that apply have a trigger that fires without a human edit?
grep -n "^on:" -A20 .github/workflows/apply-github-infra.yml
# No `schedule:` → the benefit does not hold as stated.
```

Two more findings from the same brainstorm, both cheap to miss:

**Two independently-safe controls can deadlock at apply time.** A ruleset requiring PRs on the
target repo blocks the same App's `github_repository_file` write, and the failure lands *inside
the unattended apply pipeline* — the exact failure ADR-182 refused to risk. When a brainstorm
proposes a write-path control and a write-path automation on the same resource, check whether
the control's bypass set must name the automation's identity. For a GitHub App ruleset bypass
that is `actor_type = "Integration"` with the **App ID** (`3261325`), not the installation id
(`122213433`) — a distinction that only fails at apply.

**A `paths:` trigger glob is a silent-no-op surface.** `infra/github/*.tf` does not match a
`.json` sibling in the same directory. A source-of-truth file added there would never publish
itself, and nothing would report it — the apply simply never runs.

## Key insight

A deferral record has two halves, and the workflow only re-derives one. Blockers are re-checked
because they read as risk; the benefit is inherited because it reads as fact. **Re-verify the
reason to ship, not only the reasons not to** — a stale benefit ships the wrong scope with every
blocker honestly cleared.

## Prevention

- `plugins/soleur/skills/brainstorm/SKILL.md` §1.0.5 — extended the existing deferral-trigger
  bullet to cover the deferred option's stated benefit.
- Generalizes the existing premise-validation family: `2026-07-03` (re-verify ADR deferral
  triggers against live state) covers blockers; this covers the other half.

## Session Errors

1. **`gh pr view 7471` exited non-zero** (`Could not resolve to a PullRequest`) — #7471 is an
   issue, not a PR. — Recovery: fell back to `gh issue list --state all --search`, which
   resolved it as CLOSED. — Prevention: none needed; `go.md`'s PR-vs-issue resolution
   deliberately prescribes probing `gh pr view` first and falling back, so the non-zero is the
   documented control flow rather than a mistake.
2. **`SOLEUR_GIT_BARE_POISON` emitted on both `worktree-manager.sh` invocations** — pre-existing
   diagnostic marker describing the bare-repo layout, not a fault introduced by this session.
   — Prevention: n/a; the marker is the intended forensic output.

## Related

- ADR-182 — `knowledge-base/engineering/architecture/decisions/ADR-182-keyless-manifests-and-a-dedicated-marketplace-source.md`
- `knowledge-base/project/learnings/2026-07-03-brainstorm-re-verify-adr-deferral-triggers-against-live-state.md`
- Brainstorm — `knowledge-base/project/brainstorms/2026-08-12-marketplace-repo-protection-brainstorm.md`
- Spec — `knowledge-base/project/specs/feat-marketplace-repo-protection/spec.md`
