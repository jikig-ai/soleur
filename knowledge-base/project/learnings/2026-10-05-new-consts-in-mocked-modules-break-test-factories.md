# Learning: a new export in a heavily-`vi.mock`ed module is undefined in every stubbed consumer

## Problem

Consolidating the SDK stale-resume literal
`"No conversation found with session ID"` into
`SDK_STALE_RESUME_SESSION_ID` in `server/error-sanitizer.ts` looked
safe — `agent-runner.ts` already imported that module. But ~11 test
files mock `../server/error-sanitizer` with factories that stub ONLY
`sanitizeErrorForClient`. In those tests the const resolved to
`undefined`, `err.message.includes(undefined)` threw, and six agent-runner
tests failed — the literal consolidation broke the test graph, not the
code.

## Solution

Moved the const to a leaf module `server/claude-error-signatures.ts`
(zero imports, single export) and pointed all three consumers at it.
Mock factories are unaffected — the mocks never stub the leaf because
no test mocks it.

## Key Insight

**Before exporting a NEW symbol from a module, grep
`vi.mock("<module>")` for its stub-factory consumers.** A mock factory
that whitelists exports (`() => ({ onlyThis })`) silently `undefined`s
any new export — the failure surfaces in the consuming module's tests,
not the host's. Shared constants and signatures belong in leaf modules
when the natural host is a mock-boundary module.

## Tags
category: testing
module: server/error-sanitizer.ts, server/claude-error-signatures.ts
