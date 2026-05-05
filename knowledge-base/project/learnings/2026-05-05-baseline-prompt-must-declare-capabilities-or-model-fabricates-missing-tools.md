---
title: "Baseline system prompts must declare tool capabilities — silence invites hallucinated missing tools"
date: 2026-05-05
category: integration-issues
issue: 3253
pr: 3278
related:
  - 2026-05-04-cc-soleur-go-cutover-dropped-document-context-and-stream-end.md
  - 2026-02-13-agent-prompt-sharp-edges-only.md
tags: [system-prompt, agent-sdk, prompt-engineering, cc-soleur-go]
---

# Baseline system prompts must declare tool capabilities

## Problem

A Command Center user reported the Concierge confidently refused to read a
PDF with "PDF Reader doesn't seem installed" — despite a previous session
in the same workspace successfully reading a different PDF.

Investigation: the literal string "PDF Reader" is **not in the codebase**.
There is no detection layer, no MCP server, no availability check. The
SDK's built-in `Read` tool natively supports PDFs. The string was
**model-emitted** — the agent fabricated a plausible-sounding refusal.

## Root cause

Both system-prompt builders (`buildSoleurGoSystemPrompt` and
`agent-runner.ts`'s leader baseline) had assertive PDF directives, but
**both were gated** on `documentKind === "pdf"` / `context.path.endsWith(".pdf")`.
When the user mentioned a PDF in chat with no "currently-viewing"
artifact, neither prompt mentioned PDF capability. Silence in the
baseline prompt invited the model to invent missing tooling.

This is the same root cause class as the gated-PDF context drop fixed
in PR #3213 (see related learning). The cc-soleur-go cutover replaced a
~200-line legacy `agent-runner.ts` system prompt with a ~5-line
`buildSoleurGoSystemPrompt` baseline; capability declarations that were
*implicit* in the legacy prose became *absent* in the new baseline.

## Solution

Promote a load-bearing `READ_TOOL_PDF_CAPABILITY_DIRECTIVE` constant to
the baseline of both builders, single source of truth in
`apps/web-platform/server/soleur-go-runner.ts`, imported by
`agent-runner.ts`. Wording is purely positive (declarative-then-imperative)
per 2026 prompt-engineering research — negation underperforms at scale
and re-primes the very phrase the bug emitted.

## Key insight

**A baseline system prompt's silence on a capability is an invitation
for the model to fabricate its absence.** When refactoring a thick
prompt to a thin one, capability declarations that were implicit in the
legacy prose must be made explicit — or the model fills the void with
plausible-but-wrong refusals.

Corollary: if a PDF/Edit/Write/etc. directive is **gated** on a "currently
viewing" artifact context, the baseline (no-artifact) path is one
self-misreport away from a brand-survival incident on first-touch.

## Prevention

- When a model self-misreport surfaces ("tool X doesn't seem installed"),
  the fix is a **baseline** directive, not a **gated** one. Gated
  directives only fire on the artifact-viewing path; the chat-mention
  path stays silent.
- New capability directives must be **purely positive** (declarative-then-
  imperative). Anti-priming guard tests (`expect(directive).not.toMatch(/\b(do not|never|not installed)\b/i)`)
  pin intent against future regressions.
- When adding a sibling capability directive (Edit, Write, Glob, Grep)
  later, **don't speculate** — wait for a measured incident. A negative
  list that grows by 5+ items becomes a budget tax that *describes* the
  tools rather than declaring capabilities.
- Sibling-baseline gap audit: if a third "tool X doesn't seem installed"
  report appears post-merge, sweep the legacy `agent-runner.ts` baseline
  vs the new Concierge baseline for other implicit-vs-absent capability
  statements.

## Session Errors

- **Bash CWD persistence ambiguity** — Ran `./node_modules/.bin/vitest run` once without leading `cd <abs-path> && …`. Recovery: re-prefixed. **Prevention:** AGENTS.md already covers this via the work skill's "chain `cd <abs-path> && <cmd>`" guidance; no new rule needed.
- **Pre-existing flake** — `test/cc-attachment-pipeline.test.ts` failed once in full-suite run, passed in isolation and on re-run. Unrelated to this PR. **Prevention:** out of scope here; would warrant a tracking issue if it recurs deterministically.
- **All 6 review agents rate-limited** — Expected fallback per review skill's all-failed gate. Inline review applied. **Prevention:** none — this is the documented graceful-degradation path.
