---
name: Fabricated CLI commands slip past docs review
description: Plans can prescribe unverified CLI invocations that pattern-match as plausible; neither typecheck nor review catches them, so first-touch users hit immediate failure.
type: learning
category: content-quality
tags: [docs, cli, content-audit, review-gap]
---

# Fabricated CLI commands in docs slip past review

## Problem

PR #1810 (2026-04-10) shipped `ollama launch claude --model gemma4:31b-cloud` as "the specific command" to run Soleur via Ollama on the `/getting-started/` install page. Every token was fabricated:

- Ollama has no `launch` subcommand (documented commands: `serve`, `create`, `show`, `run`, `stop`, `pull`, `push`, `list`, `ps`, `cp`, `rm`, `help`).
- No `claude` model exists in the Ollama registry (Anthropic-proprietary).
- `gemma4:31b-cloud` is not a published tag (Gemma 2 exists; no Gemma 4; `:cloud` suffix is fabricated).

The command reached three shipped surfaces (site FAQ callout, plugin README, repo README) plus the embedded JSON-LD `FAQPage` schema. A first-touch user copy-pasting it hit an immediate failure on the highest-intent URL in the funnel. Caught 8 days later by the 2026-04-18 content audit (finding R5 / #2549).

## Root cause

The content flowed through plan → work → review → merge without any step that verified the CLI invocation against reality:

- `soleur:plan` treated the unverified string as authoritative (see `knowledge-base/project/specs/feat-docs-ollama-instructions/session-state.md` — explicitly names the fabricated command as the spec's payload).
- `soleur:work` implemented the plan verbatim (correct behavior for planned content).
- `soleur:review` caught no issue — `pattern-recognition-specialist` checks DOM/markup patterns, not CLI validity; `security-sentinel` checks code-execution paths, not content accuracy.
- Eleventy build passed (fabricated strings parse as valid HTML/JSON).

Pipeline mode assumes the plan is trustworthy. For CLI docs, that assumption is load-bearing but not checked.

## Solution (this PR #2563)

Per audit R5: removal, not replacement. Shipping `ollama run gemma2:27b` as a "verified" substitute still fails two steps later (Soleur has no documented Claude-Code → Ollama endpoint wiring). Silence beats invalid.

- Deleted the callout from `getting-started.njk` (visible HTML + FAQ `<details>` + JSON-LD mirror).
- Deleted matching lines from `plugins/soleur/README.md` and root `README.md`.
- Preserved knowledge-base references as audit trail.

## Prevention

Filed #2566 to add a CLI-verification gate. Until then, when prescribing a CLI invocation in a plan or doc:

1. **Run the actual command.** `<tool> --help` and confirm the subcommand exists. For registry-hosted models/tags, `curl` the registry.
2. **Cite the source.** Link to the tool's documented command list (e.g., <https://github.com/ollama/ollama/blob/main/docs/cli.md>) in the plan's Research Insights section.
3. **When in doubt, omit.** A deleted callout is strictly better than an invalid one on a trust-bearing page.

## Related

- #1810 (introducing PR) → #2549 (parent audit) → #2550 (P0 fix ticket) → #2563 (this PR) → #2566 (systemic gate).
- Precedent: `2026-03-26-case-study-three-location-citation-consistency.md` (same class of three-location sync discipline).
- Root-cause spec: `knowledge-base/project/specs/feat-docs-ollama-instructions/session-state.md`.
