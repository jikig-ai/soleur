# Feature: Functional QA Skill (`/soleur:qa`)

## Problem Statement

The current `/test-browser` skill only tests page rendering and navigation. It does not verify that features actually work end-to-end -- form submissions, external service state, data integrity, or error path behavior. This gap was exposed during #1139 when browser testing caught a broken anchor link but missed that a Buttondown tag wasn't being assigned to subscribers.

Existing verification is ad hoc across the codebase (deploy health checks, token validation, drift detection) with no reusable, composable QA capability.

## Goals

- Provide end-to-end functional verification of features before merge
- Verify external service integration via generic, LLM-reasoned API calls
- Test error paths (network failures, invalid input, honeypot triggers)
- Validate data integrity across system boundaries
- Integrate into the one-shot pipeline as a pre-merge step
- Require zero manual configuration per feature (auto-derive from plan)

## Non-Goals

- Replacing `/test-browser` (rendering/navigation testing remains separate)
- Building service-specific adapters (Buttondown adapter, Plausible adapter, etc.)
- Post-deploy production monitoring or alerting
- Load testing or performance benchmarking
- Unit test generation or code coverage analysis

## Functional Requirements

### FR1: Plan-Derived Test Scenarios

Parse the plan's "Test Scenarios" section to generate verification steps automatically. Each scenario maps to one or more verification actions (browser interaction, API call, or both).

### FR2: Browser Flow Execution

Execute user flows end-to-end via Playwright MCP: fill forms, submit, verify success/error states in the UI. Handle page transitions, dialog confirmations, and dynamic content.

### FR3: External Service Verification

Verify data landed correctly in external services by constructing API calls dynamically. Use LLM reasoning to determine the right endpoint, method, and expected response based on the test scenario description.

### FR4: Error Path Testing

Simulate failure conditions using Playwright route interception (network failures), invalid input submission, and honeypot field population. Verify the application handles each gracefully.

### FR5: Data Integrity Validation

Confirm that tags, metadata, segmentation, and other structured data in external services match what was submitted through the UI. Cross-check with a second verification method when possible.

### FR6: Pass/Fail Evidence Report

Produce a structured report with each test scenario marked pass/fail, accompanied by evidence: screenshots, API response excerpts, and console output.

## Technical Requirements

### TR1: Skill + Scripts Architecture

SKILL.md for LLM orchestration (scenario parsing, API reasoning). Scripts directory for deterministic helpers: credential injection, report generation, environment detection.

### TR2: Doppler Integration

Use Doppler for all API credentials. Auto-detect environment: `dev` config for pre-merge (local), `prd` config for post-deploy (production). Access via `doppler secrets get <KEY> -c <config> --plain` or `doppler run -c <config> --`.

### TR3: Pipeline Integration

Insert as a step in the one-shot pipeline between review/resolve-todos (steps 5-6) and ship (step 7). The skill must be invocable via `Skill tool` with the plan path as context.

### TR4: Playwright MCP Usage

Use Playwright MCP tools (preferred per constitution.md) for browser interactions. Always pass absolute paths when in worktrees. Clean up browser sessions on completion.

### TR5: Failure Handling

Block the pipeline on any test failure. Produce actionable error output so the developer (or the work skill) can fix the issue and re-run QA.
