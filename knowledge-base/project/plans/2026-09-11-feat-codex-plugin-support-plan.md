---
title: Codex plugin distribution and repository setup
type: feat
date: 2026-09-11
---

# Codex plugin support

## Scope

The user requested installable Soleur support plus repository setup, matching
the existing multi-harness approach. Preserve canonical skills and agents.

## Domain assessment

Assessment performed sequentially against the CPO, CMO, and CTO definitions.

- CPO: one install path and the same company workflows; unsupported gates must
  be visible. The worst local failure is a skipped guard or misleading workflow
  completion, so discovery alone must not be described as full workflow parity.
- CMO: document Codex entry points and tested scope in installation/onboarding
  material. No public announcement or claim of complete parity.
- CTO: extend the existing adapter, use native manifests and hooks, and test
  installed paths. Avoid maintaining a second copy of 95 workflows or pinning
  Anthropic model names in Codex.

## Implementation and acceptance

- Native Codex marketplace install accepts a versionless manifest.
- Native discovery includes 95 canonical skills and three command wrappers.
- Every canonical agent ID resolves to its installed definition.
- Workflow routing preserves arguments and required successor phases.
- Session context carries the installed root and tool mappings.
- Repository setup loads the existing rule corpus and Bash guardrails after trust.
- Existing Claude/Grok adapter tests continue to pass.
- Document installation, cache refresh, hook trust, and unsupported surfaces.
- Record the architecture in ADR-215 and the C4 source.

## Observability

- **Failures:** missing skills, malformed manifests, hook parse failures, unknown
  agent IDs, and missing session context.
- **Layer:** local CLI output and model-visible hook context (installed plugin
  users have no Soleur server-side telemetry).
- **Signals:** native skill count, missing skill names, hook error count, explicit
  unknown-agent exceptions, and hook trust status.
- **Owner:** the invoking contributor or installed plugin user.
- **discoverability_test.command:** `node scripts/codex-plugin-smoke.mjs`.

## Non-goals

Automatic import of every repository Claude hook, per-file translation of
`apply_patch`, a native Claude Workflow interpreter, model-tier retargeting,
universal directory publication, and production deployment changes.
No inference-based claim that every autonomous workflow has completed on Codex.
