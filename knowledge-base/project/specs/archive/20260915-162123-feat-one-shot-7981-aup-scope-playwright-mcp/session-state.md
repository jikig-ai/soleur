# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-09-15-chore-aup-scope-names-playwright-mcp-plan.md
- Status: complete

### Errors

- None blocking. The Playwright and GitHub plugin MCP servers failed to connect at session start; `gh` CLI covered GitHub.
- deepen-plan's full agent fan-out was scoped to the CLO, legal-compliance-auditor and three plan reviewers (a one-bullet notice-doc edit; the operator asked to keep it small). The mechanical deepen passes (user-brand impact, observability, PAT sweep, verify-the-negative, citation checks) all ran.

### Decisions

- AUP §2 bullet wording is the CLO ruling: "Browser automation via the agent-browser subsystem or a Playwright MCP server driven by Soleur agents or skills". It holds before and after #8156, makes no Web Platform or redaction claim.
- `TC_VERSION` is NOT engaged; the reasoning lives once in the plan's `## Domain Review` → `### Legal`.
- Last Updated moves in canonical body, mirror body, mirror header, canonical frontmatter, and the compliance-posture row + frontmatter; the SHA pin is refreshed last; doc, mirror and pin land in one commit.
- The #7980 CLO attestation's "#7981 lands" trigger is closed with an append-only dated note; no new attestation file.
- Plan review trimmed six redundant or unfalsifiable checks and added `probe-legal-corpus-truth.sh` and the three lint unit tests to the gate list.

### Components Invoked

- Skills: soleur:plan, soleur:plan-review, soleur:deepen-plan
- Agents: soleur:legal:clo, soleur:engineering:research:learnings-researcher, soleur:engineering:discovery:functional-discovery, soleur:engineering:review:dhh-rails-reviewer, soleur:engineering:review:kieran-rails-reviewer, soleur:engineering:review:code-simplicity-reviewer, soleur:legal:legal-compliance-auditor
