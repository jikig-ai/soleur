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
  > **Amended 2026-10-07 (W2, #9601, PR #9653; [ADR-277](../../../engineering/architecture/decisions/ADR-277-plugin-destructive-command-guard.md)).** The line above is the original wording, kept as history; what shipped is narrower and is the set a reader should rely on. A PreToolUse hook on the Bash tool (`plugins/soleur/hooks/destructive-command-guard.sh`, matcher `^Bash$`) lexes each command and decides: **deny** a recursive `rm` of `/`, the home directory or an ancestor of it; **ask** a recursive `rm` of the working directory or an ancestor, `terraform|tofu destroy` and `apply -destroy`, and a force-push or deletion of a default branch (the locally-read `refs/remotes/<remote>/HEAD`, `main` and `master`), in every spelling bash reads as that command (quoting, `bash -c`, `eval`, `$(...)`, list operators, a `cd` earlier in the list, `sudo`/`env`/`timeout` and `doppler run --` wrappers). **Dropped from FR2: Doppler secret writes and a plain `terraform apply`.** Both are routine and ambiguous, so a prompt on them would spend the false-positive budget the unambiguous asks depend on; this repository's own sessions already defer a plain `terraform apply` through `prod-write-defer-gate.sh`. Also not decided: obfuscated command names, `xargs rm`/`find -delete`, SQL, MCP delete tools and any non-Bash tool (Devin's `exec` included); the guard is a seatbelt, not a boundary, and not a substitute for scoped credentials. It does not run in Soleur-hosted sessions (disabled through `AGENT_ENV_OVERRIDES`), so FR2 protects customer-machine plugin users, not hosted founders. Reasons, measurements and the open follow-ups are in ADR-277.
- FR3: Decide and record the sequencing of #9534 against #4671, #4672, #9545; update roadmap/issue dependencies (`--add-blocked-by`).
- FR4: Credential broker design (placeholder-and-swap) tracked with #9543.
- FR5: CVE scan of the runtime image as a CI gate.
- FR6: Security/control page copy drafted only after FR1-FR5 controls are measured; CLO review required.

## Technical Requirements

- TR1: Any new processing step over tenant content updates DPD §2.3, Art. 30 register and GDPR Policy in the same PR.
- TR2: Guard hooks must fail closed on their own error and be covered by tests in the repo's hook test suite.
  > **Amended 2026-10-07 (W2).** For the W2 guard, "fail closed" ships as *ask*, never deny: an unreadable envelope, a lexer failure or a bound trip asks. A missing `jq` or `perl` scans the raw envelope and asks on a hit; a raw-scan miss exits 0, a stated and tested residual (ADR-277 D6), because denying on a dependency failure would block its own repair. The guard has its own sandboxed suites under `plugins/soleur/test/`.
- TR3: No secret values in logs; egress audit logs record metadata (host, verdict, rule id), not bodies.
