# Brainstorm: Functional QA Skill (`/soleur:qa`)

**Date:** 2026-03-26
**Issue:** #1146
**Branch:** feat-functional-qa

## What We're Building

A new skill (`/soleur:qa`) that performs end-to-end functional verification of features before merge. Unlike `/test-browser` (which tests page rendering and navigation), this skill verifies that features actually work: forms submit correctly, external services receive the right data, error paths behave as expected, and data integrity holds across system boundaries.

The skill is **generic** -- not tied to any specific external service. It uses LLM reasoning to determine what API calls to make based on the plan's Test Scenarios section, and Doppler for credential injection.

## Why This Approach

The gap was exposed during #1139 (waitlist signup form): `/test-browser` caught a broken anchor link but missed that the `pricing-waitlist` tag wasn't being assigned to unactivated Buttondown subscribers. The form appeared to work in the browser, but the external service state was wrong. This was only discovered via manual API verification.

Existing verification in the codebase is ad hoc -- embedded in individual skills (deploy health checks, community token validation, Terraform drift detection) rather than centralized. A reusable QA skill closes this gap.

## Key Decisions

### 1. Architecture: Skill + Scripts

- **SKILL.md** handles orchestration and LLM reasoning (parsing test scenarios, deciding what to verify, constructing API calls)
- **scripts/** directory for deterministic helpers: credential injection, report generation, environment detection
- Follows the deploy skill pattern (SKILL.md + scripts/)
- Sub-agents deferred -- can be added later if parallelism is needed

### 2. Test Source: Auto-derived from Plan

- The plan skill already produces a "Test Scenarios" section
- The QA skill parses this section and generates verification steps automatically
- Zero manual configuration per feature
- No manifest files, no adapter registry

### 3. External Service Verification: LLM-Reasoned API Calls

- The agent reads test scenarios and infers which external APIs to call
- Constructs `curl` commands dynamically using Doppler-injected credentials
- No predefined service adapters -- any service with an API is testable
- Example: plan says "verify subscriber exists in Buttondown with tag X" -> agent calls Buttondown API with the right endpoint and checks the response

### 4. Pipeline Position: Pre-merge (before `/ship`)

- Runs after `/review` and before `/ship` in the one-shot pipeline
- Tests against local/dev instances
- Catches integration bugs before they reach main
- Position: between current steps 5 (resolve-todo-parallel) and 7 (ship)

### 5. Doppler Config: Auto-detect from Context

- If running pre-merge (local dev server): use `dev` config
- If running post-deploy (production URL): use `prd` config
- Detection via presence of `DEPLOY_URL` env var or localhost URL in test context

### 6. Output: Pass/Fail with Evidence

- Structured report: each test scenario as pass/fail
- Evidence includes: screenshots (Playwright), API responses, console output
- Pipeline blocks on any failure
- Report format TBD during implementation (markdown vs structured data)

### 7. Browser Tool: Playwright MCP (preferred)

- Per constitution.md, default to Playwright MCP tools
- Handles form filling, submission, state transitions
- Absolute paths required when in worktrees (known limitation)
- Fallback to agent-browser CLI only if MCP tools are unavailable

## Five Capabilities (from #1146)

1. **Execute user flows end-to-end** -- Fill forms, submit, verify success/error states in the UI via Playwright MCP
2. **Verify external service integration** -- Call APIs (any service) to confirm data landed correctly. Doppler provides credentials.
3. **Test error paths** -- Simulate network failures via Playwright route interception, test invalid input, honeypot triggers
4. **Validate data integrity** -- Confirm tags, metadata, segmentation in external services match what was submitted
5. **Run as pipeline step** -- Invoked by `/one-shot` between review and ship, using Playwright MCP for browser and `curl` for API verification

## Open Questions

- How should the report be rendered? Markdown file in the worktree? PR comment? Both?
- Should failed QA create P1 todo files (like test-browser does) or just block the pipeline?
- How to handle services that require write-then-read verification with eventual consistency (e.g., Buttondown might not immediately reflect a new subscriber)?
- Should the skill clean up test data it creates in external services (e.g., delete test subscribers)?

## Learnings Applied

- **Negative-space testing** (from CSRF learning): Test for absence of expected state, not just presence
- **Verification commands can lie** (from KB migration learning): Cross-check API responses with a second method
- **Playwright path resolution** (from screenshots learning): Always use absolute paths in worktrees
- **External platform verification** (from distribution strategy learning): Live API fetch > assumption from code inspection
- **Silent logic errors** (from Supabase auth learning): Test dual-purpose APIs that silently do the wrong thing
- **Timer/session cleanup** (from Bun segfault learning): Proper teardown for browser sessions

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** New skill (`/soleur:qa`) using Playwright MCP is the right approach — clean separation from `test-browser` (which uses agent-browser CLI for rendering). Route interception via `browser_run_code` (not `browser_evaluate`) for error paths. Doppler auto-detection well-established. Two browser tool stacks coexist intentionally (different purposes). Skill token budget is a real constraint — description must be minimal.

### Product (CPO)

**Summary:** Internal developer tooling — no business validation needed. The #1139 incident is the validation. Roadmap note: #1146 is in Phase 2 milestone but not listed in roadmap.md Phase 2 table — needs reconciliation. Plan-derived scenarios are the natural fit. Block on functional failures, report on environmental. Option A (new skill) recommended over enhancing test-browser.

### Marketing (CMO)

**Summary:** New skill is direct evidence for existing "verification gates at every stage" marketing claim. The #1139 origin story is compelling for dogfooding narrative. "Replaces your QA team" claim becomes concrete. Pipeline complexity concern: frame as "the system does this automatically" not "8th step." Skill count inconsistency across brand guide/homepage/content strategy should be reconciled.
