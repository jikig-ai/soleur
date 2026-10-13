# Tasks: fix pencil I() positional insert clear error

## Phase 1: Setup

- [ ] 1.1 Read current `pencil-mcp-adapter.mjs` to understand existing `enrichErrorMessage()` patterns
- [ ] 1.2 Verify existing test infrastructure for the adapter

## Phase 2: Core Implementation

- [ ] 2.1 Add `/id missing required property` pattern to `enrichErrorMessage()`
  - [ ] 2.1.1 Add conditional check in `enrichErrorMessage()` function
  - [ ] 2.1.2 Append hint about positional insertion, `M()` workaround, and `#1117` reference

## Phase 3: Testing

- [ ] 3.1 Test that `/id missing required property` error returns enriched message with `M()` hint
- [ ] 3.2 Test that existing `alignSelf` enrichment still works (no regression)
- [ ] 3.3 Test that existing `padding` enrichment still works (no regression)
- [ ] 3.4 Test normal `I(parent, {props})` still passes through without enrichment
