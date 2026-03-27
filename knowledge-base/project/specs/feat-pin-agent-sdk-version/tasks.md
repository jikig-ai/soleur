# Tasks: Pin Agent SDK to Exact Version

## Phase 1: Implementation

- [ ] 1.1 Edit `apps/web-platform/package.json` -- change `"@anthropic-ai/claude-agent-sdk": "^0.2.80"` to `"@anthropic-ai/claude-agent-sdk": "0.2.80"`
- [ ] 1.2 Run `npm install` from `apps/web-platform/` to regenerate `package-lock.json`

## Phase 2: Verification

- [ ] 2.1 Run `npm ls @anthropic-ai/claude-agent-sdk` from `apps/web-platform/` -- confirm resolves to exactly `0.2.80`
- [ ] 2.2 Verify lockfile diff only contains `@anthropic-ai/claude-agent-sdk` version changes (no unrelated dependency updates)
