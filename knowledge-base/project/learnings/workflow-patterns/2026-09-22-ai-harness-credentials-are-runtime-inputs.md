---
title: "AI harness credentials are runtime inputs, not global implementation blockers"
date: 2026-09-22
category: workflow-patterns
---

## Observation

The Codex rollout was incorrectly treated as blocked because no global OpenAI API
key was present in production. The intended design supplies API-key and managed
account credentials through authenticated Web settings for the relevant user or
workspace. The missing global secret therefore blocked only live qualification,
not implementation of credential selection, binding, and fail-closed execution.

## Rule

For every AI harness provider, classify credentials by scope before declaring a
blocker. Per-user or per-workspace settings credentials are runtime inputs. Their
absence blocks only the affected request or qualification. A new provider runtime,
launcher, egress boundary, or credential contract requires explicit CTO review;
CLO disposition remains the separate gate for customer-content processing.

## Evidence

The Codex adapter already models a mode-stable credential lease and the settings
path persists workspace engine/auth selection. The production Doppler probe found
no global `OPENAI_API_KEY`, while the Flagsmith feature remained default-off.
