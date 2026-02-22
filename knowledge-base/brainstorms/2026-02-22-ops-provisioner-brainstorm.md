# Brainstorm: Operations Provisioner Agent

**Date:** 2026-02-22
**Status:** Active
**Related:** #212 (Plausible Analytics setup)

## What We're Building

A generic operations agent (`ops-provisioner`) that guides users through SaaS account setup and plan purchase for any tool. It uses agent-browser to navigate signup flows, fills non-sensitive fields, pauses for manual payment, then resumes for configuration and verification.

This fills the gap between "we decided to use tool X" (ops-research) and "tool X is tracked in expenses" (ops-advisor). Currently this middle step -- signup, payment, initial config, verification -- is fully manual.

## Why This Approach

**Pure generic agent over tool-specific recipes or scripts because:**

- Agent-browser snapshots let the agent adapt to any signup page dynamically
- No per-tool maintenance burden (unlike Discord setup's bash script approach)
- Aligns with the ops-research pattern of browser navigation with safety gates
- First use case (Plausible) is simple enough to validate the generic approach

**Post-decision scope only:**

- Tool evaluation belongs to ops-research (already handles it)
- This agent assumes the tool is already chosen
- Keeps the agent focused: setup + configure + verify + record

## Key Decisions

1. **Agent type:** New operations agent at `agents/operations/ops-provisioner.md` (not a skill, not extending existing agents)
2. **Payment boundary:** Agent fills non-sensitive signup fields (email, org name, plan selection) using agent-browser. Stops at payment fields. User completes payment manually.
3. **Verification:** Browser screenshot of dashboard + integration test (e.g., visit site, check analytics dashboard shows the hit). No API verification required.
4. **Expense recording:** After setup is verified, invoke ops-advisor to record the expense in `knowledge-base/ops/expenses.md`.
5. **No tool-specific recipes:** Agent relies entirely on agent-browser snapshots to navigate any signup flow.

## 5-Phase Workflow

| Phase | Name | Description |
|-------|------|-------------|
| 1 | Context | Read tool name + purpose from user. Check expenses.md for duplicates. Gather signup URL. |
| 2 | Navigate | Open signup page with agent-browser. Fill non-sensitive fields. Select plan. Stop at payment. |
| 3 | Pause | Announce "Complete payment manually." Wait for user confirmation that payment is done. |
| 4 | Configure | Resume in tool dashboard. Guide through initial config using agent-browser (add site, copy snippet, set options). Update codebase if needed (e.g., update script tag). |
| 5 | Verify + Record | Browser screenshot of working dashboard. Integration test if applicable. Invoke ops-advisor to record expense. |

## Existing Patterns to Follow

- **Discord setup wizard** (community skill): 4-phase guided flow with manual steps between automated ones
- **ops-research agent**: Browser navigation with safety gates (never clicks purchase buttons)
- **infra-security agent**: Cloudflare API verification after setup
- **GitHub Pages wiring workflow** (learnings): 10-step autonomous sequence with verification polling

## Safety Constraints

- Never enter credentials, passwords, or payment information
- Never click purchase/payment/submit-order buttons
- All sensitive fields are left for the user
- Token/API key handling follows existing patterns (env vars, not CLI args)
- Screenshot dashboard state as proof of setup

## Resolved Questions

- **Code changes during Configure phase?** Yes. Agent reads the tool's setup instructions and makes corresponding code changes (update script tags, add env vars, etc.).
- **Email verification loops?** Pause and wait, same pattern as the payment pause. Agent says "Check your email and verify, then tell me when done."
- **Dry run mode?** Not in v1. Keep it simple.
