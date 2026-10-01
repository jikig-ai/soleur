---
date: 2026-09-23
issue: 8486
status: complete
brand_survival_threshold: single-user incident
lane: cross-domain
---

# Brainstorm: a human-presence guard for production-mutating operator scripts (#8486)

## What We're Building

A layered guard for the operator scripts that mutate Soleur's production.

**Step 1 (this PR)** stops the accidental agent, the one that "helpfully" pipes `yes` or passes
`--confirmed`. Four scripts change:

- `flag-delete/scripts/delete.sh`
- `flag-create/scripts/create.sh`
- `user-set-role/scripts/set-role.sh`
- `flag-set-role/scripts/flip.sh`

What changes:

- Each script's typed-yes prompt is replaced with the existing `soleur_op_ack_or_die`
  (`plugins/soleur/scripts/lib/operator-script.sh:415`). It requires a real TTY and has no skip
  variable.
- `flip.sh --confirmed` is removed.
- `--dry-run` stays runnable by the agent.
- Each skill prints the exact command for the operator to run in their own terminal (Warp). This
  is the `provision-hetzner.sh:229` precedent.
- A `prod-write-defer-gate.sh` entry for those script paths is the Claude-side backstop.

**Step 2 (tracked as #8652, not this PR)** stops the hijacked agent. It is a credential-custody
control, recorded in an ADR in this PR.

## Why This Approach

The agent runs as the operator's OS user, and its Doppler owner token can read
`FLAGSMITH_MANAGEMENT_API_KEY` (`soleur/cli_ops`) and the prd `SUPABASE_SERVICE_ROLE_KEY`. The
CTO measured this on 2026-09-23 (lengths 42/42/26). So the agent can `curl` Flagsmith or PostgREST
directly and skip the scripts and their WORM audit row. Every in-script or hook check is therefore
a speed bump against the accidental agent. A control against the hijacked agent has to hold the
credential where the agent cannot reach it.

The TTY ack is the only guard that works in every harness:

- Claude Code, Grok, Codex and local Devin all refuse, because a tool subprocess has no TTY.
- Devin cloud refuses outright, which is the right outcome.

An agent can still defeat it deliberately, with `script -qc` or by calling the API directly.

## Key Decisions

| # | Decision | Source |
|---|---|---|
| D1 | Threat model: both, layered. Step 1 covers the accidental agent now. Step 2 (credential custody) covers the hijacked agent. | Founder |
| D2 | Premise verified: the agent reads the prod-write credentials and can reach the APIs directly. In-script checks are speed bumps. | CTO (measured) |
| D3 | Guard set = production-mutating scripts, not user-invoked skills. It includes the model-invocable `flag-create` and `flag-set-role`. The plan must also check `audit-sentry-extra-text-references.sh --apply` and include it if it mutates prod. | #8486 triage; CTO (B) |
| D4 | **Step 1 = TTY ack plus a defer-gate backstop.** Reuse `soleur_op_ack_or_die`, remove `--confirmed`, and keep `--dry-run`. The skill prints the command for the operator's terminal. Rejected: the issue's hook plus UserPromptSubmit marker (Claude-only; new cross-event state; breaks `/soleur:go` routing to model-invocable skills; the marker lasts the whole turn). Also rejected: a nonce (defeats neither agent the TTY does not already stop). `hookify` was not adopted (stateless regex rules, Claude Code only). | Founder; CTO |
| D5 | **Step 2 goes to an ADR plus a tracked issue.** Design: a main-only workflow broker holding rotated keys (Flagsmith write key and the prd service-role key moved out of the operator's Doppler reach). It verifies a FIDO2 `sk` touch over its own nonce plus an operation digest, and it writes the approval evidence into the audit row. Named residual risks: a blind touch (the key has no display), the dashboard reached through shared browser cookies, and Doppler owner rights. Fully closing these needs agents on a separate OS user. | Founder; CTO |
| D6 | Approval evidence: in step 1 the audit row records `approval_method=tty-ack`. This is honest about being self-reported, because in-script evidence is the shell vouching for itself. Evidence the agent cannot forge arrives with the step 2 broker. | CLO; CTO |
| D7 | Per-harness coverage is stated in the ADR: the TTY ack covers every harness; the defer gate covers Claude Code and local Devin (Devin's `defer` behaviour is unmeasured, `devin-dispositions.tsv:51`); Codex registers only `guardrails.sh`; Devin cloud runs no hooks. | CTO (C) |

## Non-Goals

- Step 2's broker, key rotation and `sk` verification. Tracked as its own issue.
- Guarding the Flagsmith and Supabase dashboards. This is the named residual risk of D5.
- Running agents as a separate OS user. This is a workstation change, noted in the ADR as the
  only full closure.
- The `provision-{cloudflare,doppler,github}` prompts. They are attest barriers, not gates on a
  write.

## User-Brand Impact

- **Artifact:** the confirmation gates of the production-mutating operator scripts (`delete.sh`,
  `create.sh`, `set-role.sh`, `flip.sh`).
- **Vector:** an agent pipes `yes` or passes `--confirmed`. It then turns a feature off for a
  tenant, destroys a flag's segment overrides, or promotes a user to `dev`, which exposes
  unreleased features. The WORM audit row attributes the change to the operator.
- **Threshold:** single-user incident.

## Open Questions

None blocking. The plan should verify whether `audit-sentry-extra-text-references.sh --apply`
belongs in the guard set (D3).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering

**Summary:** The premise is measured: the Doppler owner token reads every prod-write key. Step 1
uses the existing TTY ack (`soleur_op_ack_or_die`) plus the `prod-write-defer-gate.sh` pattern.
Step 2 needs a broker that holds the credentials, because the local verifiers, environment
reviewers and a separate Doppler config are all defeated by the operator-owned tokens.

### Product

**Summary:** Only Soleur's operator uses these scripts, on Soleur's own production. Usage is rare
(about 11 commits in 3 months), so the TTY step's friction is acceptable. The real harms are a
feature vanishing for a tenant and unreleased features being exposed (`user-set-role` is
`{prd,dev}` only).

### Legal

**Summary:** Role changes are access control (GDPR Art. 5(2) and 32(1)(b)). Record the approval
method, not just the key owner. Step 1 records `tty-ack`, and step 2 brings evidence the agent
cannot forge.
