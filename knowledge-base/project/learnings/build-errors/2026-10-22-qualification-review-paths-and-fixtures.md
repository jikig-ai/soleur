---
title: Verify qualification review paths and fixture names before batching commands
date: 2026-10-22
category: build-errors
module: codex-qualification-review
---

## Problem

A review command guessed a top-level `agents/` directory and a nonexistent
`test_api_policy.py`; this checkout stores Soleur definitions under
`plugins/soleur/agents/` and the policy fixtures in `test_role_admission.py`.
An initial TLS regression also used literal spaces, which the request guard
correctly refused and the HTTP parser rejected before the proxy handler ran.
The shell lacked a standalone `ruff`, while the same lint succeeded through
`uvx --from ruff ruff`.

## Prevention

Resolve agent and test paths with `rg --files` before batching source reads.
Exercise HTTP request targets as valid origin-form wire values; use percent-
encoded input for path/query bytes and reserve malformed raw requests for
explicit refusal tests. When Ruff is absent from PATH, use the isolated `uvx`
invocation rather than changing project dependencies.
