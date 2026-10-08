# decision-challenges.md — feat-one-shot-5862-bwrap-argv-reorder (#5862)

Headless-run decision challenges recorded at plan time (ADR-084 channel).
Each entry is a contested judgment a reviewer may dissent on.

## 2026-10-07

### 1. Dispatch wording vs. issue scope — which ordering does the fix require?

- **Decision:** implement the *property* — a parent-level `denyRead`
  (`workspacesRoot()`) whose `--tmpfs` precedes the workspace's surviving rw
  `--bind` — not the literal token reading ("move the *sibling* deny mounts
  before the workspace bind" while keeping per-sibling enumeration).
- **Why contested:** the dispatch argument reads per-sibling mounts; the issue
  body's scope item 3 says "revert to the simpler broad `denyRead:
  ["/workspaces"]`". A literal reading cannot close the TOCTOU (an
  unenumerated sibling has no mount to reorder), so the property reading is
  the only one consistent with the issue's stated end state.
- **Where recorded:** plan `## Overview` terminology note + `## Scope Check`
  Ask Mapping row 5.

### 2. Issue scope item 1 (dependency-patch mechanism) descoped

- **Decision:** no `patch-package`/vendored-binary-patch machinery is
  introduced. Binary inspection shows the vendored CLI 2.1.284 builder already
  emits deny-then-restore (`jV` restore branch —
  `Re-bound write path wiped by denyRead tmpfs`).
- **Why contested:** scope item 1 of the issue is an explicit prerequisite.
  The premise it rested on (the 0.2.85-era builder cannot express
  writable-within-deny) no longer holds at 0.3.284. Marked `descoped —
  justification: …` in Scope Check; contingency (bwrap-shim argv rewrite →
  re-plan) documented if the Phase-3 capture audit falsifies the premise.
- **Where recorded:** plan `## Research Reconciliation`, Cut List, `##
  Dependencies & Risks`.

### 3. Brand-survival threshold — `single-user incident`

- **Decision:** one tenant's workspace readable by another tenant's agent is a
  single-user-incident class harm (same tier as the #8752 sibling-hardening
  plan). `requires_cpo_signoff: true` set in frontmatter.
- **Why contested:** the shipped per-sibling mitigation already covers the
  common case; the residual is narrow (future-sibling, Bash-only, adversarial
  steering). Threshold set by the *harm class when the boundary fails*, not
  by residual probability — challengeable if a reviewer reads the tier as
  incident-likelihood rather than incident-impact.
- **Where recorded:** plan `## User-Brand Impact`.

### 4. Fixture-diff expectation corrected from "token-order-only"

- **Decision:** the dispatch predicted a token-order-only fixture diff; the
  plan documents that the diff is *additive* — a new `--tmpfs` landing on the
  (deterministic, non-placeholder) capture root plus a restore `--bind` — and
  that order-only would also be acceptable evidence.
- **Why contested:** if the captured argv is token-order-only, that would
  imply the deny lands on `${CANARY_WS}`'s parent as a different token shape;
  under the broad-deny config a covering `--tmpfs` token must appear, which is
  additive, not order-only. The acceptance gate is the ordering invariant +
  `verify_ok`, not diff shape.
- **Where recorded:** plan `## Proposed Solution` → Expected fixture diff.
