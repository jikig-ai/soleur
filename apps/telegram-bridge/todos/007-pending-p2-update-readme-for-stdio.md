---
status: pending
priority: p2
issue_id: "007"
tags: [code-review, documentation]
dependencies: []
---

# Update README to reflect stdio architecture

## Problem Statement

README still shows WebSocket architecture diagram, references `WS_PORT`, and describes the old `--sdk-url` transport. The `.env.example` was updated but the README was not.

## Findings

- **architecture-strategist**: "documentation drift will confuse anyone setting up the bridge"

## Proposed Solutions

Update README.md:
- Architecture diagram: `stdin/stdout` instead of `WebSocket, localhost`
- Remove `WS_PORT` from env vars table
- Add `SOLEUR_PLUGIN_DIR`, `CLAUDE_MODEL`, `SKIP_PERMISSIONS`
- Update CLI spawn description

- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] No WebSocket references in README
- [ ] Architecture diagram shows stdin/stdout
- [ ] All current env vars documented
- [ ] Startup instructions accurate

## Work Log
- 2026-02-11: Identified during /soleur:review
