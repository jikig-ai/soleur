# ADR-215: Codex plugin reuses canonical Soleur components

- **Date:** 2026-09-11

## Status

Accepted.

## Context

The March Codex portability inventory predates Codex lifecycle hooks and the
current plugin loader. Soleur already has Claude and Grok adapters. Adding a
third harness must preserve one source of workflow and domain instructions.

## Decision

1. Add a Codex compatibility manifest beside the Claude manifest in the same
   plugin subtree, with a repository Codex marketplace pointing to that subtree.
2. Explicitly register the canonical skill directory and a second directory of
   thin wrappers for the three existing commands. The native 0.154.0 loader
   accepts multiple roots and names skills `soleur:<name>`.
3. Extend the existing harness adapter. Codex loads skills and delegates with
   canonical agent definition paths, inheriting its session model.
4. Reuse compatible bundled hook protocols. A Codex-only SessionStart hook
   provides tool mappings and the installed root. Repository configuration
   separately opts into rule loading and Bash guardrails.
5. Keep manifests versionless under repository policy. Native install accepts
   this and labels local installs `local`; reinstall refreshes the local cache.
6. Verify real discovery through Codex's app-server API without model calls.
   Unit tests cover routes, every agent ID, metadata parity, and installed paths.

## Consequences

Claude/Grok components and counts remain canonical. Codex exposes 98 skills
(95 canonical skills plus three command wrappers). MCP metadata is parity
tested rather than assumed.

Hook trust is explicit and cannot be conferred by installing the plugin.
The repository's Claude per-file Write/Edit gates are not imported into Codex:
`apply_patch` has a different payload. This initial repository setup is not
full hook parity. Generated custom agent definitions, automatic model-tier
translation, and a Claude Workflow interpreter are outside this change.
Revisit those when a concrete Codex workflow requires them.

> **Amended 2026-09-17 (#8233, ADR-224).** The replace-default semantics this
> ADR's §Verification records hold for **Codex** and not for Claude Code, whose
> `skills` key is additive to the default `skills/` scan. This ADR's own text is
> unchanged and its measurements stand; the qualification is added because the
> unqualified reading — "declaring a skills root replaces the default" — is false
> on two of the four harnesses this plugin now ships to. The harness-qualified
> placement rule and its guard live in ADR-224.

## Verification

The native smoke test checks the installed cache, not just source JSON.
It caught a real failure: a single custom skill root hid the canonical skills.
All 98 skills and six bundled hooks are discoverable with both roots declared.
This verifies discovery, not completion of all 95 workflows.
