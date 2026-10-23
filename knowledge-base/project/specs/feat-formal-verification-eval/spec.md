---
feature: formal-verification-eval
lane: cross-domain
brand_survival_threshold: single-user incident
status: parked
issue: 10897
brainstorm: knowledge-base/project/brainstorms/2026-10-23-formal-verification-eval-brainstorm.md
---

# Spec: formal verification evaluation (parked)

## Problem Statement

Anthropic showed Claude proving binary-level properties of C/C++ libraries. Can Soleur apply formal verification per PR or on a schedule, and does it help Soleur or its users ship bug-free code?

## Goals

- Record the feasibility and cost assessment and the revisit triggers.

## Non-Goals

- Building any verification tier now.
- Any user-facing "verified" or "bug-free" claim.

## Functional Requirements

- None while parked. Candidate spike and revisit triggers are in tracking issue #10897 and the brainstorm.

## Technical Requirements

- If revisited, run as a scheduled job, never a PR gate.
- Keep specs and properties in human-reviewed files separate from agent-editable code (reward-hacking guard).
- Run the CLO and CMO gate before any external wording, and the gdpr-gate before any customer code reaches a third-party prover.

Brainstorm: knowledge-base/project/brainstorms/2026-10-23-formal-verification-eval-brainstorm.md
