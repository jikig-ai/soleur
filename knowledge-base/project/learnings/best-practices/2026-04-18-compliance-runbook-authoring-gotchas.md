---
module: knowledge-base
date: 2026-04-18
problem_type: best_practice
component: documentation
symptoms:
  - "markdownlint --fix corrupted regex content inside inline-code within pipe-delimited markdown table cell"
  - "Table-cell \\| escapes copied verbatim into a non-table replacement format"
  - "jq 'del(.results[].path)' recommended for PII redaction without confirming JSON schema — breakdown dimension value IS the result key"
  - "Merge timestamp drift: plan quoted 19:16:02Z, actual commit is 19:16:01Z"
  - "gh api pulls/<N> returned null SHAs; local git log worked"
root_cause: inadequate_documentation
resolution_type: code_fix
severity: medium
tags: [compliance, runbook, markdown, markdownlint, pii, redaction, plausible, gdpr, jq, timestamps]
related_prs: [2577]
related_issues: [2507, 2508, 2462, 2503]
---

# Compliance-runbook authoring gotchas (Plausible PII erasure + dashboard filter audit)

Context: PR #2577 drained #2507 + #2508 (review-backlog against PR #2503, the
path-PII scrubber). Two new runbooks under
`knowledge-base/engineering/ops/runbooks/` (`plausible-pii-erasure.md` and
`plausible-dashboard-filter-audit.md`) plus a 4-line comment cross-link in
`apps/web-platform/app/api/analytics/track/sanitize.ts` above `SCRUB_PATTERNS`.
Multi-agent review caught five issues that a lone author would ship. The
common thread: **compliance docs look like prose, but they are executable
artefacts that future operators copy-paste under stress** — they must be
authored with the same rigor as code.

## 1. Never put unescaped `|` inside inline-code within a markdown table cell

**What happened:** I wrote a "Regex source of truth" table with three rows
like:

```text
| `[uuid]`  | `/[0-9a-f]{8}(?:-|%2d)[0-9a-f]{4}(?:-|%2d).../gi` | Any 8-4-4-4-12 hex |
```

After the mandatory `npx markdownlint-cli2 --fix` pass, the UUID row came
back mangled — the alternation `(?:-|%2d)` had been rewritten to
`[?:-|%2d](0-9a-f){4}` inside the inline-code span. Unescaped `|` inside
backticks inside a markdown table confuses the table parser; the fixer's
attempt to normalise column widths rewrites content instead of just
whitespace.

**Fix:** Drop the table entirely for regex content. Use a fenced `text` or
`regex` block that renders the strings literal:

```text
```text
[email]  /[^\s/@]+(?:@|%40)[^\s/@]+\.[^\s/@]+/gi
[uuid]   /[0-9a-f]{8}(?:-|%2d)[0-9a-f]{4}(?:-|%2d)...[0-9a-f]{12}/gi
[id]     /\d{6,}/g
```

```

A plain unordered list is acceptable when you only have 2-3 short items and
no `|` characters.

**Prevention:** Any time you need `|` inside a regex, a shell pipe, or a
union type inside markdown, use a **fenced code block**, not an inline-code
span inside a table row. Escaping with `\|` also works for tables, but
dropping the table is simpler and avoids step 2 below.

## 2. When removing table formatting, strip every `\|` escape

After hitting gotcha #1 I replaced the table with a list and carried the
`\|` escapes (`(?:@\|%40)`) verbatim, then added a footnote that said "the
`\|` is a markdown rendering artefact". code-quality-analyst correctly
flagged this as a copy-hazard: an operator pasting that regex into
ClickHouse `match()` retains the backslash and silently matches nothing.

**Fix:** When you change the enclosing context of a regex (table → list,
list → fenced block), audit every escape in the regex. The `\|` is a
table-cell requirement, **not** a regex requirement; outside a table it is
strictly harmful. This mirrors the Work-phase lesson for rAF sweeps and
fetch-mock sweeps — context-change requires a synchronous consumer sweep.

## 3. Verify the JSON schema before shipping a PII-redaction snippet

I wrote: "Attach counts only, or use `jq 'del(.results[].path)'` before the
paste." security-sentinel flagged that the Plausible Stats API v1
`breakdown` endpoint returns results **keyed on the dimension value**
(`event:props:path` in this case) — the path string IS the key, and the
sibling `visitors` / `pageviews` fields are keyed on it. `del(.results[].path)`
does nothing because there is no `.path` sub-field; it also cannot redact
the key itself. The guidance gave false assurance.

**Fix:** Replace with counts-only:

```bash
curl -sS ... | jq '.results | length'
```

Plus a paranoia check before any paste: `grep -E '@|[0-9a-f]{8}-|[0-9]{6,}'
<file>` must return empty.

**Prevention:** For any PII-redaction `jq` / `awk` / `sed` snippet in a
compliance doc, fetch the real response shape once (with a read-only
credential) and verify the redaction against the real shape before writing
the runbook. If the shape cannot be verified, recommend **counts-only**
export rather than attempting surgical redaction.

## 4. Re-verify git timestamps at write time

The plan frontmatter quoted `2026-04-17T19:16:02Z` for the PR #2503 merge
commit. The actual author date is `2026-04-17T19:16:01Z` — off by one
second. Compliance docs citing merge timestamps may be quoted verbatim in
erasure responses; second-precision matters.

**Fix:** Always re-derive via `git log -1 --format="%cI" <sha>` (or
`%ci %H` for the human-readable form) at the moment you write the doc.
Never trust a plan's quoted timestamp without a live re-read.

## 5. `gh api repos/.../pulls/<N>` can return null SHAs

Session-state forwarded this error from the plan phase: the `gh api pulls`
endpoint returned null for merge/base/head SHAs under our current token.
The plan agent worked around it via `git log --all --grep="<issue-number>"`
— the merge commit message includes the issue reference, so grep resolves
the SHA authoritatively against the local refs.

**Prevention:** For SHA / merge-commit resolution, prefer local git over
`gh api pulls/<N>`. The `gh api` endpoint has token-scoping edge cases;
local refs are unambiguous once `cleanup-merged` has fetched main.

## 6. PR body wiring: `Closes #N` must be in the body, not the title

The draft PR created by the `worktree-manager.sh draft-pr` helper opens a
PR with a stock placeholder body. The Work phase's first commit did not
update the PR body. code-quality-analyst caught that `Closes #2507` /
`Closes #2508` were missing — merging would have left the issues open.

The workflow gate `wg-use-closes-n-in-pr-body-not-title-to` already encodes
this, but the draft-PR helper does not trigger it. `/soleur:ship` Phase 5.5
Review-Findings Exit Gate would catch this, but the cheaper fix is to
update the body explicitly during review-fix, which is what I did via `gh
pr edit <N> --body-file <path>` with `Closes #2507` / `Closes #2508` on
separate lines.

## Session Errors

1. **markdownlint-fix mangled regex in pipe-delimited table cell** — Recovery: switched to list then to fenced `text` block. **Prevention:** never put unescaped `|` inside inline-code within a markdown table cell; use a fenced block.
2. **Carried `\|` escapes from abandoned table format into replacement format** — Recovery: stripped during review-fix. **Prevention:** when changing the enclosing context of a regex, audit every escape — strip those that were context-specific.
3. **Recommended `jq 'del(.results[].path)'` for PII redaction without confirming JSON schema** — Recovery: replaced with counts-only `jq '.results | length'` + grep-based paranoia check. **Prevention:** for any PII-redaction snippet, verify the target API's response shape against live output before shipping.
4. **Merge timestamp drift (`19:16:02Z` vs `19:16:01Z`)** — Recovery: corrected in both runbooks during review-fix. **Prevention:** re-derive timestamps via `git log -1 --format=%cI <sha>` at write time; never copy from plan frontmatter unverified.
5. **`gh api pulls/<N>` returned null SHAs** (forwarded from plan phase) — Recovery: used `git log --all --grep=<issue-number>`. **Prevention:** prefer local git refs for SHA resolution; `gh api pulls` has token-scoping edge cases.
6. **Draft PR body was stock placeholder — `Closes #2507` / `Closes #2508` initially absent** — Recovery: `gh pr edit --body-file` during review-fix. **Prevention:** the `worktree-manager.sh draft-pr` helper could stamp the PR body with the plan's PR body template; /ship Phase 5.5 Review-Findings Exit Gate is the backstop but not the cheapest place to fail.
7. **Bash tool CWD not persistent across calls** — after `cd apps/web-platform && vitest` a follow-up grep with a relative path failed. Recovery: prepend `cd <worktree-path> && …` in a single call. **Prevention:** use absolute paths or `cd <abs-path> && <cmd>` pattern per `cq-for-local-verification-of-apps-doppler`.

## Key Insight

Compliance runbooks are executable artefacts, not prose. They must survive:
(a) an on-call under stress copy-pasting at 3am; (b) future markdownlint
passes by other agents; (c) schema drift in the systems they query. Three
practical corollaries:

1. **Use fenced blocks for anything with metacharacters** (`|`, `&`, `<`,
   `>`, `$`). Tables are for human-readable content only.
2. **Verify every snippet against a live response shape** before shipping —
   especially for redaction snippets where "the default will be trusted"
   is a safety-critical assumption.
3. **Multi-agent review is worth the cost on docs-only PRs.** Four agents
   found five issues in a 400-line, two-file PR that a lone author's own
   `npx markdownlint-cli2 --fix` did not catch. The house-style agent
   caught the `\|` carry-over; security-sentinel caught the jq redaction
   gap; code-quality-analyst caught the PR body wiring and the timestamp
   drift; git-history-analyzer confirmed the regex fidelity.
