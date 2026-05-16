---
date: 2026-05-06
problem_type: integration_issue
component: kb-concierge-pdf-extractor
severity: high
tags: [cap-coupling, adjacent-prs, pdf-extractor, silent-fallback, hypothesis-driven-fix]
related_prs: ["#3337", "#3338", "#3346", "#3353"]
related_sentry_event: 9e0a3888fd3849cd87cb83cdcecca199
synced_to: [plan]
---

# Cap-coupling between adjacent PRs needs cross-PR audit

## Problem

Two PRs merged 25 minutes apart on 2026-05-06:

- **#3337** (`f275007d`, 20:41 UTC) raised the KB PDF upload cap to 24 MB by introducing `MAX_AGENT_READABLE_PDF_SIZE` and applying it to `validate-files.ts`, `agent-runner.ts`, the upload route, and the presign route.
- **#3338** (`e2b032ca`, 20:17 UTC) introduced `apps/web-platform/server/pdf-text-extract.ts` for KB Concierge PDF text extraction with a hardcoded `INPUT_BUFFER_CAP_BYTES = 15 * 1024 * 1024`.

#3338's branch was cut **before** #3337 merged, so `MAX_AGENT_READABLE_PDF_SIZE` did not exist when the 15 MB literal was chosen. Each PR's diff was internally consistent. Within hours of both PRs merging, prod fired Sentry event `9e0a3888fd3849cd87cb83cdcecca199` (`extractPdfText returned null`) on the very PDF the user opened to test #3338's fix.

The failure shape: any PDF in the [15 MB, 24 MB] band passed the upload validator → landed in the user's KB → tripped `buffer.length > INPUT_BUFFER_CAP_BYTES` at extractor entry → returned `null` → caller fell through to `buildPdfGatedDirective` (the gated SDK Read path) → model emitted the `apt-get install poppler-utils` / `find` Bash modal cascade — exactly the user-visible bug #3338 was supposed to close.

Neither PR's review caught the mismatch because neither diff alone showed both caps. No preflight or `/ship` Phase 5.5 gate inspects "raised file-size cap → audit all readers of the same artifact class." The Sentry mirror existed (per `cq-silent-fallback-must-mirror-to-sentry`) and surfaced the regression — but only after a real user tripped it.

## Solution

Two fixes shipped together in #3353:

**1. Single source of truth for the cap.** The extractor now imports `MAX_AGENT_READABLE_PDF_SIZE` from `@/lib/attachment-constants` directly. The local `INPUT_BUFFER_CAP_BYTES` constant is gone. A drift-guard test reads `pdf-text-extract.ts` source and forbids ANY hand-rolled `<n> * 1024 * 1024` literal anywhere in the executable path:

```ts
// apps/web-platform/test/kb-pdf-cap-alignment.test.ts
const sourceWithoutComments = src
  .replace(/\/\*[\s\S]*?\*\//g, "")
  .replace(/(^|\s)\/\/[^\n]*/g, "$1");
expect(sourceWithoutComments).not.toMatch(/\d+\s*\*\s*1024\s*\*\s*1024/);
```

A reshadow as `25 * 1024 * 1024`, `0x1800000`, or any other hand-rolled byte literal fails the gate.

**2. Discriminated-union failure shape + content-grounded fallback.** The extractor returns `PdfTextExtractResult | { error: PdfExtractErrorClass }` covering six classes (`oversized_buffer | lazy_import_failed | encrypted | corrupted | parse_error | empty_text`). The runner's `buildPdfUnreadableDirective` picks class-specific user-facing copy with an exhaustive switch + `: never` rail. The gated Read directive (the apt-get-cascade anchor) is no longer reached on extractor failure — defense-in-depth alongside the SDK-level `disallowedTools: [Bash, Edit, Write]` block. Every failure class mirrors to Sentry with `extra.errorClass`, and `empty_text` gets a distinct `op: extractPdfText.empty_text` so Hypothesis B is filterable from Hypothesis A.

## Key Insight

**When two PRs change a size/format/encoding ceiling within hours of each other, every reader of the affected artifact class must be audited in lockstep.** Neither PR's isolated diff is sufficient. The validator-side and reader-side caps are coupled by the artifact's lifecycle (uploaded buffer becomes read buffer); a one-sided change leaves a silent gate that surfaces only when a user uploads in the band between the old and new caps.

The repeating pattern: a `MAX_*_SIZE` / `*_CAP_BYTES` / `MAX_*_LENGTH` constant change in one PR demands a grep across the codebase for sibling reader-side caps governing the same artifact (PDFs, images, attachments, request bodies). The fix is structural, not procedural — a single source of truth pinned by a test that forbids local literals.

## Prevention

**Structural** (already shipped in #3353):

- Extractor imports the shared constant — re-shadowing is impossible without failing the drift-guard test.
- Drift-guard pattern (`grep` for `<n> * 1024 * 1024` in the file) generalizes to any future cap-coupling site.

**Procedural** (planning-time):

- When `/plan` or `/deepen-plan` proposes a change to a `MAX_*_SIZE` / `*_CAP_BYTES` constant, the planner should grep all readers of the affected artifact class (`grep -rn '<artifact_class>' apps/<app>/server/`) and enumerate them in the plan — not just call sites of the constant itself, since reader-side caps are typically *literal*, not imported. The gap that produced this bug was that #3338's planner did not search for sibling caps because there were no callers of `MAX_AGENT_READABLE_PDF_SIZE` in the extractor's neighborhood.
- A `/preflight` check that compares numeric literals against known cap constants in any modified `apps/*/server/**/*.ts` file would catch most cases. Out of scope for this learning; tracked informally.

## Session Errors

- **Edit tool silently rewrote literal `U+2028` / `U+2029` chars to ASCII spaces** when matching a `  ` regex pattern in `soleur-go-runner.ts`. **Recovery:** split the Edit call into smaller diffs that did not include the regex line. **Prevention:** AGENTS.md `cq-regex-unicode-separators-escape-only` already covers this — discoverability exit applies (clear error, no new rule needed).
- **Local Node 21.7.3 incompatible with `pdfjs-dist@5.4.296`** (`process.getBuiltinModule is not a function`). All vitest / `tsc --noEmit` runs needed `PATH="/home/jean/.nvm/versions/node/v22.22.2/bin:$PATH"` prefix. CI uses Node 22 per `.github/workflows/ci.yml`. **Recovery:** explicit PATH prefix per command. **Prevention:** per-developer env concern — adding `.nvmrc` or `engines.node` to `apps/web-platform/package.json` would warn on `npm install`. Out of scope for this PR; not workflow-blocking.
- **16 MB Hypothesis-A regression test flaked under parallel pressure** with the default 5 s vitest timeout (passed solo at ~3.4 s). **Recovery:** added `{ timeout: 15_000 }` to the test. **Prevention:** when a test creates a `Buffer.alloc(>= 16 MB)` and feeds it to a parser, add an explicit timeout to handle parallel-run resource contention.
- **Sentry MCP and `SENTRY_AUTH_TOKEN` unavailable** in the Claude Code session and Doppler — plan Phase 0 (fetch event payload) was unreachable. **Recovery:** documented unreachability in plan addendum and PR body, proceeded on Hypothesis A per plan Sharp Edges. **Prevention:** anticipated by the plan's Sharp Edges section — not an error in workflow execution.

## See also

- `2026-04-23-render-time-scrub-sentinels-and-client-bundle-boundaries.md` — adjacent silent-fallback class (PDF-content scrubbing)
- AGENTS.md `cq-silent-fallback-must-mirror-to-sentry` — mirroring rule that surfaced this regression
