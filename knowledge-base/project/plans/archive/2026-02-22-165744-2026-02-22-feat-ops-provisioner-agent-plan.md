---
title: "feat: Add ops-provisioner agent for guided SaaS tool setup"
type: feat
date: 2026-02-22
---

# feat: Add ops-provisioner agent for guided SaaS tool setup

## Overview

Add a new `ops-provisioner` agent to `agents/operations/` that guides users through SaaS account signup, payment, initial configuration, verification, and expense recording. This fills the gap between ops-research (tool evaluation) and ops-advisor (expense tracking).

## Problem Statement

After choosing a SaaS tool via ops-research, the actual account creation, plan purchase, initial configuration, and verification are fully manual. Issue #212 (Plausible Analytics) is a concrete example: the evaluation is done, legal docs are updated, but no account exists.

## Proposed Solution

A single agent file at `plugins/soleur/agents/operations/ops-provisioner.md` with a guided workflow using agent-browser to navigate signup flows generically (no per-tool recipes). Three sections: Setup, Configure, Verify + Record.

## Non-goals

- Per-tool signup recipes (the agent is generic -- no recipes directory)
- Automated payment (always manual -- agent never enters credentials or clicks purchase buttons)
- Tool evaluation or comparison (handled by ops-research)
- SSO/SAML/enterprise configuration
- Ongoing tool administration

## Technical Considerations

- **agent-browser dependency:** Check availability, degrade gracefully to URLs + manual instructions (one-liner, same as ops-research)
- **Safety model:** Follows ops-research precedent -- never enters credentials, never clicks payment buttons
- **ops-advisor integration:** After verification, invoke ops-advisor via Task tool to record the expense
- **Pause pattern:** One general rule for any user action outside the browser (payment, email verification, MFA): pause and ask the user to complete it

## Acceptance Criteria

- [x] Agent file exists at `plugins/soleur/agents/operations/ops-provisioner.md`
- [x] YAML frontmatter: name, description (with disambiguation against both siblings), model
- [x] Body uses topical sections (Setup, Configure, Verify + Record) matching sibling style
- [x] Safety rules: never enters credentials, never clicks payment buttons
- [x] Invokes ops-advisor to record expense after setup
- [x] Sibling agents updated with disambiguation mentioning ops-provisioner
- [x] Version bump: MINOR (new agent)

## Rollback

Revert the commit. The agent file is self-contained with no external state.

## Implementation

### Step 1: Create the agent file

Create `plugins/soleur/agents/operations/ops-provisioner.md` following the same structure as `ops-research.md`:

**Frontmatter:**

```yaml
---
name: ops-provisioner
description: "Use this agent when you need to set up a new SaaS tool account, purchase a plan, configure the tool, and verify the integration works. This agent guides through signup, pauses for manual payment, resumes for configuration and verification, then records the expense. Use ops-research for evaluating alternatives before choosing a tool; use ops-advisor for reading and updating the expense ledger directly."
model: inherit
---
```

**Body sections (topical, matching sibling style):**

- **Role statement:** "You are an operations provisioning agent that guides users through SaaS tool account setup."
- **Data files table:** Same as ops-research (expenses.md, domains.md)
- **Setup:** Accept tool name, purpose, signup URL. Check expenses.md for duplicates. Check agent-browser availability. If available: open signup URL, snapshot, fill non-sensitive fields, stop at payment. If unavailable: provide URLs and instructions.
- **Configure:** After user confirms payment/email verification, navigate to dashboard. Guide initial config using agent-browser. Make code changes if needed (edit templates, add env vars).
- **Verify + Record:** Browser screenshot of dashboard. Integration test if applicable. Invoke ops-advisor via Task tool to record expense. Summarize what was set up, the plan/cost, and dashboard URL.
- **Safety rules:** Same as ops-research. Never credentials, never payment buttons. When any step requires user action outside the browser, pause and ask.

### Step 2: Update sibling disambiguation

Update descriptions in both sibling agents to mention ops-provisioner:

- `ops-research.md`: Add "use ops-provisioner for guided account setup and configuration"
- `ops-advisor.md`: Add "use ops-provisioner for guided account setup and configuration"

### Step 3: Plugin infrastructure

1. Verify cumulative agent description word count under 2500
2. Update `plugins/soleur/README.md` agent count (45 -> 46)
3. Update `plugins/soleur/CHANGELOG.md` with `### Added` entry
4. Bump version in `plugins/soleur/.claude-plugin/plugin.json` (MINOR)
5. Update `plugins/soleur/.claude-plugin/plugin.json` description (agent count 45 -> 46)
6. Update root `README.md` version badge
7. Update `.github/ISSUE_TEMPLATE/bug_report.yml` version placeholder

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-22-ops-provisioner-brainstorm.md`
- Spec: `knowledge-base/specs/feat-ops-provisioner/spec.md`
- Sibling: `plugins/soleur/agents/operations/ops-research.md`
- Sibling: `plugins/soleur/agents/operations/ops-advisor.md`
- Pattern: `plugins/soleur/skills/community/SKILL.md` (Discord setup wizard)
- Issue: #212
