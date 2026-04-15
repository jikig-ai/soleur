---
title: "Custom leader names as @mention handles"
date: 2026-04-14
issue: 2170
status: complete
---

# Custom Leader Names as @mention Handles

## Problem Statement

When users rename domain leaders via team settings, the @mention dropdown correctly shows custom names but always inserts the raw leader ID (`@cto`) into the chat text. Users expect `@Oleg (CTO)` to appear when they select their renamed leader.

## Goals

- G1: Selecting a leader from the @mention dropdown inserts the custom display name
- G2: Custom names are single-word to maintain compatibility with the `/@(\w+)/g` mention parser
- G3: Manual typing of `@cto` (leader ID) continues to work for backward compatibility

## Non-Goals

- Multi-word custom name support (requires regex/parser changes)
- Rich @mention rendering (styled chips in textarea)
- @mention support outside the chat input

## Functional Requirements

- FR1: When a leader has a custom name, `onSelect` inserts `@CustomName (RoleName)` (e.g., `@Oleg (CTO)`)
- FR2: When a leader has no custom name, `onSelect` inserts `@RoleName` (e.g., `@CTO`)
- FR3: The team names API rejects custom names containing whitespace with a 400 response
- FR4: The team settings UI shows an inline validation error when spaces are entered

## Technical Requirements

- TR1: No changes to server-side `parseAtMentions` regex — custom name resolution already works via reverse-lookup
- TR2: No changes to WebSocket message protocol — messages are sent as plain text containing `@word` tokens
- TR3: Single-word validation uses `/^[a-zA-Z0-9]+$/` pattern (alphanumeric only, no spaces or special characters)

## Acceptance Criteria

- [x] Selecting a renamed leader from dropdown inserts `@CustomName (RoleName)` into chat text
- [x] Selecting a non-renamed leader from dropdown inserts `@RoleName` into chat text
- [x] Server correctly routes messages containing `@CustomName` to the right leader
- [x] Setting a custom name with spaces returns 400 from the API
- [x] Setting a custom name with spaces shows inline error in the UI
- [x] Typing `@cto` manually still routes correctly (backward compatibility)
