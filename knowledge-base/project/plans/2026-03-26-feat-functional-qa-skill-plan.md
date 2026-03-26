---
title: "feat: Add functional QA skill for end-to-end feature verification"
type: feat
date: 2026-03-26
---

# feat: Add functional QA skill (`/soleur:qa`)

[Updated 2026-03-26 — applied plan review feedback: simplified to single-file skill, deterministic scenarios, deferred error path testing]

## Overview

Add a new skill (`/soleur:qa`) that performs end-to-end functional verification of features before merge. Unlike `/test-browser` (visual rendering and navigation), this skill verifies that features actually work: forms submit correctly, external services receive the right data, and data integrity holds across system boundaries.

**Scope boundary with `/test-browser`:** `test-browser` = visual rendering, layout regressions, console errors (uses agent-browser CLI). `qa` = functional verification of user flows and external service state (uses Playwright MCP). They coexist in the pipeline — different tools, different concerns.

## Problem Statement / Motivation

The gap was exposed during #1139 (waitlist signup form): `/test-browser` caught a broken anchor link but missed that the `pricing-waitlist` tag wasn't being assigned to Buttondown subscribers. The form appeared to work in the browser, but the external service state was wrong — only discovered via manual API verification.

Existing verification is ad hoc — embedded in individual skills (deploy health checks, token validation, drift detection) with no reusable, composable QA capability.

## Proposed Solution

### Architecture: Single-File Skill

```text
plugins/soleur/skills/qa/
└── SKILL.md    # LLM orchestration with XML structure
```

No scripts, no references directory. Environment detection and report generation are inlined in SKILL.md (matching the pattern of 90%+ of existing skills). SKILL.md uses pure XML structure (`<objective>`, `<quick_start>`, `<success_criteria>`, etc.) per project convention.

### Deterministic Test Scenarios

Test scenarios in plans must include **explicit verification commands** — not prose descriptions for the LLM to interpret. The QA skill executes what the plan specifies; it does not infer API endpoints.

Example test scenario format in a plan:

```markdown
## Test Scenarios

- **Browser:** Navigate to /pricing, fill email with test+qa@example.com, submit form, verify "Thank you" message appears
- **API verify:** `doppler run -c dev -- curl -s -H "Authorization: Token $BUTTONDOWN_API_KEY" "https://api.buttondown.com/v1/subscribers?email=test+qa@example.com" | jq '.results[0].tags'` expects `["pricing-waitlist"]`
- **Cleanup:** `doppler run -c dev -- curl -s -X DELETE -H "Authorization: Token $BUTTONDOWN_API_KEY" "https://api.buttondown.com/v1/subscribers/test+qa@example.com"`
```

This is deterministic, reproducible, and debuggable. If a QA check fails, the curl command can be copy-pasted and run manually.

### Pipeline Integration

Insert QA as a new step in the one-shot pipeline between `resolve-todo-parallel` (step 5) and `compound` (step 6):

```text
Current pipeline:
3. work → 4. review → 5. resolve-todo-parallel → 6. compound → 7. ship → 8. test-browser → 9. feature-video → 10. promise

New pipeline:
3. work → 4. review → 5. resolve-todo-parallel → 5.5 QA → 6. compound → 7. ship → 8. test-browser → 9. feature-video → 10. promise
```

**Invocation:** `skill: soleur:qa, args: "<plan_file_path>"`

### Flow

Sequential execution:

1. Read the plan file (passed as argument)
2. Find the `## Test Scenarios` section
3. If no Test Scenarios section: warn "No test scenarios found in plan" and skip QA (do not block)
4. Detect environment: if `DEPLOY_URL` is set, use Doppler config `prd`; otherwise use `dev`
5. For each scenario, execute what it describes:
   - Browser steps via Playwright MCP (navigate, fill, submit, verify)
   - API verification steps via `doppler run` + `curl` (execute the exact command from the scenario)
   - Cleanup steps (delete test data from external services)
6. Wait a few seconds between browser actions and API verification for eventual consistency. If verification fails, retry up to 3 times before marking as failed.
7. Output a pass/fail report in markdown format with screenshots and API response evidence
8. If any scenario failed, block the pipeline with actionable error output

## Technical Considerations

### Playwright MCP Usage

Per constitution.md, use Playwright MCP tools for browser interactions. Key considerations:

- Always use absolute paths for screenshots when in worktrees (Playwright MCP resolves from repo root)
- Close browser sessions on completion to prevent resource leaks
- Available tools: `browser_navigate`, `browser_fill_form`, `browser_click`, `browser_snapshot`, `browser_take_screenshot`, `browser_console_messages`

### Doppler Integration

Environment auto-detection is a single conditional: if `DEPLOY_URL` is set, use `prd` config; otherwise use `dev`.

```bash
# Example usage in test scenarios
doppler secrets get BUTTONDOWN_API_KEY -c dev --plain
doppler run -c dev -- curl -s ...
```

Handle missing secrets gracefully: if a `doppler secrets get` fails, warn and skip that scenario.

### Test Data Cleanup

Test scenarios should include cleanup steps that remove test data from external services after verification. The QA skill executes cleanup steps regardless of pass/fail to avoid accumulating garbage data. Cleanup failures are warned but do not mark the scenario as failed.

### Eventual Consistency

Wait a few seconds after browser actions before running API verification. If API verification fails, retry up to 3 times before marking as failed. No formal backoff algorithm — the LLM adapts timing to context.

## Acceptance Criteria

- [ ] Skill created at `plugins/soleur/skills/qa/SKILL.md` with XML structure and valid frontmatter
- [ ] SKILL.md parses plan's Test Scenarios section and executes deterministic verification commands
- [ ] Browser flows execute via Playwright MCP; API verification via Doppler + curl
- [ ] Pass/fail report generated inline with screenshots and API response evidence
- [ ] Pipeline blocks on any test failure with actionable error output
- [ ] One-shot pipeline updated with QA step (step 5.5) between resolve-todo-parallel and compound
- [ ] `/soleur:plan` SKILL.md updated to generate deterministic Test Scenarios with explicit verification commands
- [ ] Cumulative skill description word count stays under 1,800 words (`bun test` passes)
- [ ] README.md component counts updated

## Test Scenarios

### Happy Path

- Given a plan with deterministic browser + API test scenarios, when QA skill runs, then it executes browser flow via Playwright MCP, runs the exact curl command from the scenario, compares output, runs cleanup, and produces a PASS report
- Given a plan with only API verification scenarios (no browser steps), when QA skill runs, then it executes curl commands with Doppler credentials and verifies responses

### Edge Cases

- Given a plan with no Test Scenarios section, when QA skill runs, then it warns "No test scenarios found" and skips QA without blocking the pipeline
- Given a Doppler secret that doesn't exist for the service being tested, when QA skill tries to run the curl command, then it warns "Doppler secret unavailable" and skips that scenario
- Given Playwright MCP is not available, when QA skill encounters a browser scenario, then it warns "Playwright MCP unavailable" and skips browser scenarios (API-only scenarios still run)
- Given the local dev server is not running, when QA skill tries to navigate, then it fails the scenario with "Server not reachable"

### Failure Handling

- Given a scenario where the API response doesn't match expectations, when QA skill verifies, then it marks the scenario as FAIL with expected vs actual values
- Given a scenario where the browser flow fails (element not found, timeout), when QA skill runs, then it captures a screenshot and marks the scenario as FAIL

## Domain Review

**Domains relevant:** Engineering, Product, Marketing

### Engineering (CTO)

**Status:** reviewed (carried from brainstorm)
**Assessment:** Playwright MCP path resolution in worktrees (use absolute paths), Doppler auto-detection well-established, pipeline insertion between resolve-todos and compound is correct. Single-file architecture approved — no scripts needed.

### Product/UX Gate

**Tier:** NONE
**Decision:** auto-accepted (pipeline)

No user-facing pages or UI components. Internal engineering capability.

### Marketing (CMO)

**Status:** reviewed (carried from brainstorm)
**Assessment:** New skill adds to plugin capability count (semver:minor). Landing page stats update automatically via data files.

## Dependencies & Risks

### Dependencies

- Playwright MCP server must be available for browser scenarios
- Doppler CLI must be installed and configured for API verification
- Local dev server must be running for browser scenarios
- **Plan skill must be updated** to generate deterministic Test Scenarios with explicit verification commands (upstream prerequisite)

### Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Plan authors write vague test scenarios | QA can't execute | Plan skill generates explicit commands with Doppler + curl templates |
| Eventual consistency causes false failures | Pipeline blocks unnecessarily | Retry up to 3 times before failing |
| Playwright MCP not installed | QA skipped for browser scenarios | Graceful degradation with clear warning |
| Test data not cleaned up | Garbage accumulates in external services | Cleanup steps in test scenarios, executed regardless of pass/fail |

## References & Research

### Internal References

- Existing browser testing: `plugins/soleur/skills/test-browser/SKILL.md`
- One-shot pipeline: `plugins/soleur/skills/one-shot/SKILL.md:98-113`
- Skill compliance: `plugins/soleur/AGENTS.md` (Skill Compliance Checklist)

### Learnings Applied

- Negative-space testing (CSRF learning): test for absence of expected state
- Verification commands can lie (KB migration learning): cross-check with second method
- Playwright path resolution (screenshots learning): absolute paths in worktrees
- External platform verification (distribution strategy learning): live API > code inspection

### Related Issues

- #1146: Original feature request
- #1139: Waitlist signup gap that motivated this feature
- #1143: CSP header gap found during #1139 review

## Implementation Phases

### Phase 1: Create SKILL.md

**File to create:** `plugins/soleur/skills/qa/SKILL.md`

- YAML frontmatter: `name: qa`, third-person description
- XML body structure: `<objective>`, `<quick_start>`, `<workflow>`, `<success_criteria>`
- Workflow sections: plan parsing, environment detection, scenario execution, report generation
- Graceful degradation for missing prerequisites
- Inline report template (no script)

### Phase 2: Update Plan Skill + Pipeline

**Files to modify:**

- `plugins/soleur/skills/plan/SKILL.md` or `plugins/soleur/skills/plan/references/plan-issue-templates.md` — update Test Scenarios section format to include explicit verification commands (curl + jq + cleanup)
- `plugins/soleur/skills/one-shot/SKILL.md` — insert QA step between resolve-todo-parallel and compound

### Phase 3: Compliance + Documentation

- Update README.md skill count
- Run `bun test plugins/soleur/test/components.test.ts` — verify description word count
- Verify SKILL.md uses XML structure (no markdown headings in body)

### Deferred (Phase 2 — future iteration)

- Error path testing via Playwright route interception (separate concern from happy-path verification)
- `references/qa-scenario-format.md` (add if scenario parsing proves unreliable)
- Sub-agent parallelism (add if QA latency becomes a problem)
