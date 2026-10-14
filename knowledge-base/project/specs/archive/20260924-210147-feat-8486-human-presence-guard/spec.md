---
issue: 8486
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-09-23-8486-human-presence-guard-brainstorm.md
---

# Spec: human-presence guard for production-mutating operator scripts (step 1)

## Problem Statement

An agent can drive the operator scripts that mutate Soleur's production, with no human involved.
Three scripts use a typed-yes `read -p` that accepts piped stdin: `delete.sh`, `create.sh` and
`set-role.sh`. The fourth, `flip.sh`, has a `--confirmed` flag that skips its prompt entirely.

## Goals

- An agent's tool subprocess cannot complete any production write through these scripts, in any
  harness.
- The operator can still run every script from their own terminal with a single confirmation.
- The layered design and its residual risk are recorded in an ADR.

## Non-Goals

- A control against a hijacked agent: the credential-custody broker. That is tracked separately in #8652
  as step 2.
- Guarding the dashboards.
- Running agents as a separate OS user.

## Functional Requirements

- **FR1.** `delete.sh`, `create.sh`, `set-role.sh` and `flip.sh` gate every production write on
  `soleur_op_ack_or_die` (`plugins/soleur/scripts/lib/operator-script.sh`). That gate requires a
  real TTY on stdin and has no environment-variable or flag bypass.
- **FR2.** `flip.sh --confirmed` is removed. The script rejects the flag with a clear error that
  names the terminal path.
- **FR3.** `--dry-run` (and any read-only mode) stays runnable without a TTY.
- **FR4.** Each affected SKILL.md tells the agent to print the exact command for the operator to
  run in their own terminal, never to run it itself. This follows the `provision-hetzner`
  precedent. Remove every SKILL.md or docs reference to `--confirmed` or agent-driven use.
- **FR5.** `.claude/hooks/prod-write-defer-gate.sh` gains entries for the four scripts'
  production-write invocations, excluding `--dry-run`. This is the Claude-side backstop.
- **FR6.** The WORM audit row records `approval_method=tty-ack`.
- **FR7.** Derive the guard set as "scripts that mutate production", not from a hand-kept list. The
  plan checks `audit-sentry-extra-text-references.sh --apply` and includes it if it writes to prod.
- **FR8.** An ADR records the layered decision (D1–D7 in the brainstorm). It covers per-harness
  coverage, the step-2 broker design, and the named residual risks: `script -qc`, direct `curl`
  with the Doppler owner token, the dashboards, and a blind touch.

## Technical Requirements

- **TR1.** Tests prove that piped stdin (`printf 'yes\n' | bash <script> …`) and `--confirmed` are
  refused before any network call. Use stubbed `doppler`/`curl` on PATH, with a sentinel file that
  records whether they were called.
- **TR2.** Tests prove that `--dry-run` still works without a TTY.
- **TR3.** A defer-gate test covers the new entries, and a `--dry-run` negative control stays
  allowed.
- **TR4.** No hand-kept list goes stale. Wherever a list is needed, a test derives it or pins it
  against the filesystem.
- **TR5.** Full review panel (security-sentinel, user-impact-reviewer and the rest); the threshold
  is a single-user incident.
