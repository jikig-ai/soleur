---
name: linear-fetch
description: "This skill should be used when a user input contains a Linear issue reference (e.g., SOL-39 or linear.app/.../issue/<ID>) and the downstream agent needs the screenshots embedded in the issue as visual context."
allowed-tools:
  - Bash
  - mcp__linear-server__get_issue
  - mcp__linear-server__list_comments
  - mcp__linear-server__extract_images
preconditions:
  - Linear MCP server is authenticated (mcp__linear-server__authenticate has been run for this session)
---

# Linear Issue Image Context

This skill detects Linear issue references in caller input, fetches the issue body and recent comments, and streams the embedded screenshots directly into the active model conversation. The caller (typically `/soleur:one-shot` Step 0a or `/soleur:brainstorm` Phase 0.4) receives two return artifacts and is responsible for choosing the right one for each downstream consumer.

## Caller Contract

This skill returns **two artifacts**. Mixing them up is the load-bearing failure mode the skill exists to prevent.

1. **Agent context** — the full markdown blob (description + comment bodies) with Linear image content blocks streamed into the active conversation by `mcp__linear-server__extract_images`. **Callers MUST NOT write this artifact to disk, a PR body, a commit message, or any file under `knowledge-base/`.** The Linear image URLs inside it (`uploads.linear.app/*`) are signed bearer credentials that grant public-internet read access for their validity window.
2. **Persist-safe summary** — the same text with every `uploads.linear.app/*` URL redacted to the literal token `[linear-image: REDACTED]`. **Callers MUST use this variant for any persistence**: writes to `knowledge-base/`, PR descriptions, commit messages, learning files, downstream subagent prompts.

The redaction primitive lives at [scripts/redact-linear-urls.sh](./scripts/redact-linear-urls.sh). It uses a **case-insensitive hostname match** (`[Hh][Tt][Tt][Pp][Ss]?://[Uu][Pp][Ll][Oo][Aa][Dd][Ss]\.[Ll][Ii][Nn][Ee][Aa][Rr]\.[Aa][Pp][Pp]/`) — DNS is case-insensitive and `https://Uploads.Linear.App/...` serves the same signed bearer credential as the lowercase form. The URL path uses a positive ASCII-only character class (RFC 3986 unreserved + reserved set), so Unicode separators (U+2028, U+2029, NBSP) and markdown/HTML terminators (`< > " ' ) ]`) all terminate the match cleanly. The full justification per character is inline in the script. The companion CI `pii-grep` job in `.github/workflows/pr-quality-guards.yml` mirrors the case-insensitive matching with `grep -iE`.

The repository is public on GitHub. A single leaked `uploads.linear.app` URL is a `single-user incident` brand-survival event per `knowledge-base/project/specs/feat-linear-issue-image-context/spec.md`.

## Phases

### Phase A — Reference detection

Scan the input string for substrings matching either:

- The identifier shape `[A-Z]{2,}-[0-9]+` (matches `SOL-39`, `LIN-12`, `ENG-100`, but also `PR-123`, `HTTP-200`, `CVE-2024` — false positives are handled in Phase B, not at the regex level), OR
- The URL shape `linear\.app/[^/]+/issue/([A-Z]+-[0-9]+)` — extract the captured identifier.

Uppercase each captured identifier and deduplicate (case-sensitive after uppercasing, exact-match on the number — `SOL-39` and `sol-39` collapse to one entry).

If more than 5 distinct identifiers match, use the `AskUserQuestion` tool to ask the user how to proceed before any MCP call:

- **Header:** "Linear cap"
- **Question:** "Found N Linear references; the default cap is 5 to bound prompt size and MCP cost. Process the first 5, all N, or abort?"
- **Options:** "Process first 5 (default)", "Process all (may bloat context)", "Abort". The "Other" escape is appended automatically by the runtime.

Take the user's choice as the working set for Phase B.

If 5 or fewer matches, proceed directly.

If zero matches, return immediately with no disclosure line — the skill is a no-op for inputs that do not reference Linear.

### Phase B — Fetch + comment scan

For each identifier in the working set:

1. Invoke `mcp__linear-server__get_issue(id=<identifier>)`. On a `404 Not Found` response, silently drop the identifier — this converts false-positive matches like `PR-123` or `CVE-2024` into no-ops with no user-visible failure. On any other failure (`403`, network error, token expired), emit the warning from Phase E and skip to the next identifier; do not abort.
2. Invoke `mcp__linear-server__list_comments(issueId=<identifier>, orderBy="createdAt", limit=250)`. The MCP schema (verified at Phase 0 of the plan) supports `orderBy: createdAt | updatedAt` and `limit` up to 250. The schema does NOT expose an order-direction parameter, so the response order is treated as ambiguous: parse each comment's `createdAt` field and sort client-side **descending**, then take the first 10 entries as "10 most-recent by creation time." If the response contains 10 or fewer comments, skip the sort.
3. Concatenate the issue description and the 10 most-recent comment bodies into a single markdown blob, delimited as `\n\n--- comment by <author.displayName> on <createdAt> ---\n\n` between each block.

### Phase C — Image passthrough

For each issue's combined markdown blob from Phase B, invoke `mcp__linear-server__extract_images(markdown=<blob>)`. The MCP server resolves Linear-authenticated CDN URLs server-side and streams the underlying image bytes back into the active conversation as image content blocks. The skill never sees the bytes, never writes them to disk, never re-fetches them.

Count the image content blocks returned per issue (call this `N_images_total`), and count how many were extracted from comment bodies specifically (call this `M_comments_with_images`). The MCP response shape should make this distinguishable; if not, infer from the per-source split by passing description and comments through `extract_images` separately.

### Phase D — Disclosure & dual-artifact return

For each issue, emit exactly one disclosure line to stdout based on the Phase C counts:

| Condition | Disclosure line |
|---|---|
| Images present | `Detected <ID> — fetched issue + N_images_total images from description and M_comments_with_images comments.` |
| Text-only (description and comments had zero `uploads.linear.app` references and `extract_images` returned zero images) | `Detected <ID> — text-only issue, no images.` |
| Soft anomaly (description or comments contained `uploads.linear.app` URLs but `extract_images` returned zero images) | `Detected <ID> — N image URLs found but extraction returned 0 images (soft anomaly).` |
| Comment cap hit (`list_comments` returned exactly 250 — Linear MCP's per-call limit, may have more comments past the cap) | append ` (comment cap hit — may be missing newer comments)` to the appropriate line above. The skill takes the 10 most-recent from the 250-window, so very high-volume issues may miss comments past position 250. Cursor pagination is a v1.1 follow-up (issue filed at plan finalization). |

Construct the two return artifacts:

- **agent_context** — emit the full markdown blob inline in the conversation, so the parent's message history holds both the text and the image content blocks from `extract_images`. The parent retains these for downstream phases (one-shot Steps 3+, brainstorm Phase 2 Synthesis, brainstorm Phase 3 Capture). Per `2026-05-12-task-subagent-prompt-text-only.md`, image content blocks do NOT propagate to Task subagents — design accordingly.
- **persist_safe_summary** — produce by piping the full markdown blob through `bash ./scripts/redact-linear-urls.sh`. The redacted text is the only artifact callers may persist. Return it as a fenced text block clearly labeled `PERSIST-SAFE SUMMARY (use this for any write to disk):` so the parent skill cannot confuse it with the agent_context.

**Telemetry redaction (TR7).** This skill MUST NOT include the matched Linear identifier, the issue title, any image URL, or any signed-URL fragment in incident telemetry (`.claude/hooks/lib/incidents.sh emit_incident`). If telemetry is ever emitted from inside this skill, use generic strings only (e.g., `linear-fetch applied`). The current implementation has zero `emit_incident` call sites; a future maintainer adding one must pass the [assert-no-linear-telemetry.sh](./scripts/assert-no-linear-telemetry.sh) assertion or extend the assertion to cover the new emission shape.

### Phase E — Failure handling

For any MCP failure that is NOT a benign 404 false-positive:

- Emit a one-line warning to stdout: `Linear fetch failed for <ID>: <reason>. Continuing without image context.`
- Do NOT abort the parent skill. The original identifier text remains in `$ARGUMENTS`; the downstream agent can still reason about the issue from prose alone.
- Do NOT include the matched identifier in any telemetry emission per TR7. The warning above is operator-facing stdout, not telemetry — the identifier is permitted in the warning so the operator can take corrective action.

The most common reasons (and what they mean):

| Reason | What it usually means |
|---|---|
| `MCP tool not found` | Linear MCP server is not registered for this session. Run `mcp__linear-server__authenticate`. |
| `403 Forbidden` | Token is valid but lacks access to the issue's workspace. Confirm Linear workspace membership. |
| `Network timeout` | Linear API unreachable. Try again, or work offline from prose only. |
| `Token expired` | OAuth token rotation needed. Re-run `mcp__linear-server__authenticate`. |

## Caller invocation contract

This skill is invoked via the `Skill` tool from inside another skill (not directly by the operator). Two known callers as of v1:

- `/soleur:one-shot` Step 0a — parent fetches once, retains images for Steps 3+, substitutes `persist_safe_summary` into the Steps 1-2 Task subagent's prompt template.
- `/soleur:brainstorm` Phase 0.4 — parent fetches once, retains images for Phase 2 Synthesis and Phase 3 Capture, embeds `persist_safe_summary` in Phase 0.5 domain-leader prompts.

The skill does NOT modify `/soleur:plan`, `/soleur:fix-issue`, or `/soleur:work` in v1. Those are tracked as a v2 follow-up issue at plan-finalization time.

## Manual Test Runbook

The 10 spec acceptance-test scenarios. Operators run these against a real Linear workspace before marking the post-merge acceptance criteria done. Each step lists: input to type into Claude Code, expected disclosure, and post-condition to verify.

1. **Happy path — single-issue, description-only image.** Pick a real `SOL-*` issue whose description contains one Linear-CDN-hosted image (markdown shape `![](URL)`). Type `fix <ID>` into a `/soleur:one-shot`-routed prompt. Expected: disclosure `Detected <ID> — fetched issue + 1 images from description and 0 comments.` Visual check: the image is rendered inline in the current conversation. Persist check: the plan subagent's plan document at `knowledge-base/project/plans/...` contains zero `uploads.linear.app` matches (`grep -c` returns 0).
2. **Happy path — comments-only image.** Pick an issue with a text-only description and one image attached in a comment. Same invocation. Expected: `fetched issue + 1 images from description and 1 comments.`
3. **Text-only issue.** Pick an issue with no images anywhere. Expected: `text-only issue, no images.`
4. **Multi-issue input.** Type `compare <ID-1> and <ID-2>`. Expected: two disclosure lines, one per issue.
5. **404 issue.** Type `fix SOL-999999` (or any non-existent identifier). Expected: silent no-op, no warning printed (false-positive path).
6. **False-positive identifier.** Type `the PR-123 we shipped`. Expected: silent no-op for `PR-123` (404 → silently dropped). No warning, no MCP error surfacing to the operator.
7. **Comments cap.** Pick an issue with 15+ comments, several of which contain images. Expected: only 10 most-recent processed; the disclosure's `M_comments_with_images` count is at most 10.
8. **Persist-safe round-trip.** After a `/soleur:brainstorm` invocation that triggered the skill, run `grep -c 'uploads.linear.app' knowledge-base/project/brainstorms/<latest>.md`. Expected: `0`.
9. **CI grep gate fires.** Create a fixture branch outside Claude Code, manually `git add` and `git commit` a file containing `https://uploads.linear.app/TEST-FIXTURE-NOT-REAL.png`, push, and open a PR. Expected: the `pii-grep` CI job fails the PR with a clear `::error::` annotation pointing at `knowledge-base/project/specs/feat-linear-issue-image-context/spec.md`.
10. **Telemetry redaction.** Run any skill that emits incident telemetry while the conversation has linear-fetch context. Inspect `.claude/incidents/*.jsonl` after the test run. Expected: zero lines contain a Linear identifier (`SOL-\d+` or similar) or `uploads.linear.app`.

If any scenario fails post-merge, file a P1 follow-up issue, leave `#3635` open, and do not mark the skill production-ready until the failure is reproduced and fixed.

## Sharp Edges

- The `LINEAR_CDN_PATTERNS` array in [scripts/redact-linear-urls.sh](./scripts/redact-linear-urls.sh) is intentionally extensible (currently one pattern: `uploads.linear.app`). If Linear introduces a new CDN hostname (`cdn.linear.app`, `linear-assets.com`), add a new pattern to the array AND update the CI `pii-grep` workflow regex in the same PR. The redaction primitive's unit-test fixtures must also gain a matching fixture per new pattern.
- The character class excludes single quote via the bash `$'\x27'` ANSI-C escape (so the regex literal contains `'`). This works on bash 5.x (Linux) and bash 3.2 (macOS) but the test runbook explicitly tests on both before declaring the script production-ready.
- `list_comments` `orderBy` direction is not exposed in the MCP schema; client-side `createdAt desc` sort + take-10 is the hard fallback to remain order-independent. Do not assume server-side direction.
- The skill must be invoked via the `Skill` tool, not run as a CLI. The `Skill` invocation places the image content blocks from `extract_images` into the caller's conversation; a standalone CLI run would lose the images entirely.
- `extract_images` may return zero images for an issue whose markdown contains `uploads.linear.app` URLs (e.g., an upstream Linear bug, transient CDN failure, expired URL inside the issue). The Phase D soft-anomaly disclosure exists precisely so this case is operator-visible and not silent.
