---
title: Agent security — three layers hardening epic
lane: cross-domain
brand_survival_threshold: single-user incident
branch: feat-agent-security-three-layers
issue: 9601
deferred: [9602, 9603]
pr: 9599
brainstorm: knowledge-base/project/brainstorms/2026-10-06-agent-security-three-layers-brainstorm.md
---

# Spec: Agent security — three layers hardening epic

## Problem Statement

An AlphaSignal article argues prompts are not a security boundary and agents need sandboxing, minimal runtimes and an egress proxy. Verified against Soleur: layers 1 and 3 are largely enforced for the web runtime, but (a) the customer's BYOK key and tokens are injected into the agent subprocess environment, (b) the customer-side plugin ships almost no destructive-action guard, (c) open-web egress (#9534) is scheduled ahead of the injection defense, approval queue and audit log the roadmap says must come first, and (d) the runtime image has no CVE scan.

## Goals

- G1: Remove or minimize secrets reachable from the agent process env.
- G2: Ship a minimal destructive-command guard to every plugin user.
- G3: Align egress sequencing with the roadmap's security-first principle.
- G4: Add image CVE scanning; record ADRs for per-session containers and Landlock.
- G5: Publish security/control claims only for controls that are shipped and measured.

## Non-Goals

- An LLM-judge payload-inspecting egress proxy (revisit after broker + audit log).
- Per-tenant ephemeral containers and Landlock implementation (ADR only).
- Playwright-MCP unwrapped-registration guard (#8286).

## Functional Requirements

- FR1: Withhold the owner's Anthropic credential from sandboxed Bash with the per-variable `sandbox.credentials` deny. `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` was verified and REJECTED (it strips the service tokens Connected Services needs; ADR-272 Decision 2). Service-token scoping moves to the credential broker (#9543).
- FR2: Port a minimal PreToolUse guard (rm -rf of ancestors, terraform destroy/apply, doppler secret writes, force-push to main) into `plugins/soleur/hooks/hooks.json`.
- FR3: Decide and record the sequencing of #9534 against #4671, #4672, #9545; update roadmap/issue dependencies (`--add-blocked-by`).
- FR4: Credential broker design (placeholder-and-swap) tracked with #9543.
- FR5: CVE scan of the runtime image as a CI gate.
- FR6: Security/control page copy drafted only after FR1-FR5 controls are measured; CLO review required.

## Technical Requirements

- TR1: Any new processing step over tenant content updates DPD §2.3, Art. 30 register and GDPR Policy in the same PR.
- TR2: Guard hooks must fail closed on their own error and be covered by tests in the repo's hook test suite.
- TR3: No secret values in logs; egress audit logs record metadata (host, verdict, rule id), not bodies.
