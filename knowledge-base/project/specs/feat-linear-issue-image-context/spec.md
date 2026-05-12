---
title: Linear Issue Image Context Skill
status: draft
date: 2026-05-12
issue: "#3635"
related_pr: https://github.com/jikig-ai/soleur/pull/3631
brand_survival_threshold: single-user incident
worktree: .worktrees/feat-linear-issue-image-context/
brainstorm: knowledge-base/project/brainstorms/2026-05-12-linear-issue-image-context-brainstorm.md
---

## Problem Statement

When a user invokes `/soleur:one-shot` or `/soleur:brainstorm` with a Linear issue reference in their input (e.g., `fix SOL-39`, or pasting the Linear URL), the downstream agents receive only the issue ID as text. The screenshots, diagrams, and visual context that motivated the ticket — almost universally present in the description or follow-up comments — never enter the model's context. The agent either guesses at the visual layout, asks the user to re-paste the screenshot manually, or builds an off-target plan grounded in text-only inference.

This is observable today: the `feat-one-shot-sol-39-sidebar-misalignment` worktree's plan was authored from text inspection of a sidebar alignment bug. A screenshot of the misalignment lives in the Linear issue; the plan agent never saw it.

## Goals

1. **G1.** Detect Linear issue references in any text input to `/soleur:one-shot` and `/soleur:brainstorm`.
2. **G2.** Fetch each referenced issue's description and 10 most-recent comments via the Linear MCP server.
3. **G3.** Extract images from description + comments and surface them into the active model conversation as visual context.
4. **G4.** Prevent Linear CDN URLs (`uploads.linear.app/*`) from being persisted into any committed artifact — brainstorm doc, spec, plan, PR body, learnings, commit message.
5. **G5.** Fail soft on MCP errors so brainstorm/one-shot remain runnable offline or with stale tokens.

## Non-Goals

- Caching Linear images to disk. The `extract_images` MCP tool returns images directly to the model; no `/tmp` cache, no worktree storage.
- Bypassing the Linear MCP server's authentication. Tokens are managed by MCP; the skill never sees, prints, or logs them.
- Modifying `/soleur:plan`, `/soleur:fix-issue`, `/soleur:work`, or any other Linear-adjacent skill in v1. These are v2 candidates after usage data from one-shot + brainstorm.
- Building a GitHub-issue equivalent. GitHub's MCP server already returns issue text; if images become a friction there too, a separate `github-fetch` skill follows the same pattern.
- Vendor DPA registration for Linear. Scoped out of this PR under the redaction-guard condition; tracked separately if the guard fails review.

## Functional Requirements

- **FR1.** Skill name `linear-fetch`, registered at `plugins/soleur/skills/linear-fetch/SKILL.md`. Description must trigger on any text input containing a Linear issue identifier (regex below) so the harness routes correctly.
- **FR2.** Reference detection: identify substrings matching `[A-Z]{2,}-\d+` OR URLs of the form `linear\.app/[^/]+/issue/([A-Z]+-\d+)`. Deduplicate. First 5 matches per invocation; warn if more were found.
- **FR3.** For each matched identifier, invoke `mcp__linear-server__get_issue` with that ID. Read description from the response.
- **FR4.** For each matched identifier, invoke `mcp__linear-server__list_comments` and take the 10 most-recent by creation time. If `list_comments` lacks deterministic ordering, sort client-side by `createdAt` desc.
- **FR5.** Concatenate description + comment bodies into one markdown blob (clearly delimited per source). Pass to `mcp__linear-server__extract_images(markdown=<blob>)`. The MCP server resolves Linear-authenticated URLs and streams images into the active conversation.
- **FR6.** Emit a single disclosure line per matched issue:
  - Images present: `Detected <ID> — fetched issue + N images from description and M comments.`
  - Text-only: `Detected <ID> — text-only issue, no images.`
- **FR7.** Return two artifacts to the caller:
  - **Agent context** — the full markdown blob (with Linear image markdown intact) **passed to the model only via the conversation**, never returned as a string to be persisted.
  - **Persist-safe summary** — the same description text with every `uploads\.linear\.app/[^\s)\]]+` URL replaced by the literal token `[linear-image: <count> attached to context]`. Callers (brainstorm, one-shot, plan) MUST use this variant for any write to `knowledge-base/`, PR body, commit message, or learnings file.
- **FR8.** On MCP failure (`get_issue` 404, 403, token-expired, network), print a one-line warning and continue: `Linear fetch failed for <ID>: <reason>. Continuing without image context.` The original issue ID remains in the parent skill's prompt.
- **FR9.** `/soleur:one-shot` SKILL.md adds a step in its argument-parsing phase: if input contains a Linear reference, invoke `Skill: soleur:linear-fetch` with the input as args before proceeding to plan.
- **FR10.** `/soleur:brainstorm` SKILL.md adds the same invocation at Phase 1.1 (research) so domain leaders spawned in Phase 0.5 have already seen the images.
- **FR11.** If `extract_images` returns zero images for an issue with `uploads.linear.app` URLs present in the markdown, log this as a soft anomaly (not a failure) and proceed.

## Technical Requirements

- **TR1.** MCP allowlist update: add `mcp__linear-server__get_issue`, `mcp__linear-server__list_comments`, `mcp__linear-server__extract_images` to the `canUseTool` configuration. **No wildcard** (`mcp__linear-server__*` forbidden). Location TBD during implementation; lesson `2026-04-06-mcp-tool-canusertool-scope-allowlist.md` governs the pattern.
- **TR2.** Pre-commit guard: add a hook (or extend an existing one) in `.claude/hooks/` that fails the commit if any staged file matches `grep -E "uploads\\.linear\\.app"`. Second-tier defense behind FR7's redaction.
- **TR3.** Regex anchoring: the identifier regex `[A-Z]{2,}-\d+` is greedy enough to false-positive on tokens like `PR-123`, `ENV-1`, `HTTP-200`. Mitigation: when `get_issue` returns 404, do not error — silently drop the match. This converts false positives into no-ops, not failures.
- **TR4.** Identifier dedup is case-sensitive on the prefix and exact-match on the number (`SOL-39` and `Sol-39` are the same; we uppercase before dedup).
- **TR5.** No filesystem writes for image data. The skill does not create directories under `/tmp`, `knowledge-base/`, or worktree paths to hold image bytes.
- **TR6.** No environment variable read for Linear tokens. The MCP server handles auth. The skill must not reference `LINEAR_API_TOKEN` or similar.
- **TR7.** Telemetry redaction: when emitting incident telemetry via `.claude/hooks/lib/incidents.sh`, the skill MUST NOT include the matched Linear identifier, the issue title, the image URL, or any signed URL fragment in the telemetry message. Use generic strings only (e.g., `linear-fetch applied`).

## Acceptance Criteria

- [ ] `plugins/soleur/skills/linear-fetch/SKILL.md` exists with description, trigger conditions, and phases.
- [ ] Skill is listed in `/soleur:help` output and in the plugin manifest.
- [ ] Running `/soleur:one-shot fix SOL-39 sidebar misalignment` invokes `/soleur:linear-fetch`, fetches the issue, extracts images, prints the disclosure line, and the downstream plan agent's conversation contains the image(s) (verified by spawning the plan agent with a screenshot-dependent prompt and checking it doesn't ask for visual context).
- [ ] Running `/soleur:brainstorm` with a prompt containing `SOL-39` triggers the fetch at Phase 1.1, before domain leaders spawn.
- [ ] `/soleur:linear-fetch` invoked on an issue without images prints `text-only issue, no images.` and returns the persist-safe summary unchanged.
- [ ] Persist-safe summary contains zero `uploads.linear.app` URLs. Verified by `grep -c "uploads.linear.app"` on the returned string == 0.
- [ ] Pre-commit hook rejects a test fixture containing `https://uploads.linear.app/test.png` with a clear error message.
- [ ] MCP allowlist contains the three specific tools, not a wildcard. Verified by `grep -n "mcp__linear-server" <allowlist-path>` showing exactly three lines.
- [ ] `get_issue` failure path (use an invalid ID `SOL-999999`) prints the warning and continues — does not abort the parent skill.
- [ ] Multi-issue input (e.g., `compare SOL-39 and SOL-42`) fetches both and emits two disclosure lines.
- [ ] Incident telemetry payloads from a `/soleur:linear-fetch` run contain zero Linear identifiers or URLs. Verified by inspecting `.claude/incidents/` after a test run.

## Risks

- **R1. Redaction-guard breach.** If FR7's persist-safe summary leaks a signed URL into a committed artifact, it's a single-user incident the moment the PR is pushed. Mitigation: TR2 pre-commit hook + a code-review checklist item. Tier-up to PR-blocking: legal items (Linear DPA, sub-processor disclosure) re-enter scope if the guard is breached in review.
- **R2. False-positive identifier match.** `PR-123` or `HTTP-200` matches the regex. Mitigation: TR3 — convert 404s to silent no-ops. Worst case: extra MCP roundtrip with no user-visible impact.
- **R3. Context bloat.** A Linear issue with 10 large screenshots in comments may overflow the model's context window. Mitigation: cap N=10 most-recent comments (FR4) and document an escape hatch in the skill (`--no-images` flag for v1.1 if users hit limits).
- **R4. MCP tool unavailable.** If the Linear MCP server is not registered (developer hasn't authenticated), `mcp__linear-server__get_issue` is not in the deferred-tool list and the skill can't load its schema. Mitigation: FR8 warn-and-continue + a skill prerequisite check that surfaces "Linear MCP not registered — run `mcp__linear-server__authenticate`" instead of a cryptic error.
- **R5. Comment ordering nondeterminism.** If `list_comments` returns in arbitrary order, "10 most recent" is meaningless. Mitigation: client-side sort by `createdAt` desc as a hard fallback (FR4).

## Test Scenarios

1. **Happy path — single-issue, description-only image.** Input: `fix SOL-X`. Issue description contains one `![](uploads.linear.app/...png)`. Expected: disclosure prints `fetched issue + 1 images from description and 0 comments`; downstream agent has the image in context; persist-safe summary has the URL redacted.
2. **Happy path — comments-only image.** Description text-only, one comment has an attachment. Expected: `fetched issue + 1 images from description and 1 comments`.
3. **Text-only issue.** No images anywhere. Expected: `text-only issue, no images.`
4. **Multi-issue input.** Input mentions `SOL-39 and SOL-42`. Expected: two disclosure lines, both issues' images in context.
5. **404 issue.** Input `SOL-999999`. Expected: warning printed, parent skill continues.
6. **False-positive identifier.** Input `the PR-123 we shipped`. Expected: silent no-op (404 dropped). No warning printed for false positives that 404.
7. **Comments cap.** Issue with 50 comments containing images. Expected: only 10 most-recent processed; one anomaly log.
8. **Persist-safe round-trip.** Brainstorm doc written after a Linear fetch. `grep "uploads.linear.app" <brainstorm.md>` returns zero lines.
9. **Pre-commit hook fires.** Stage a file containing `https://uploads.linear.app/x.png`. Expected: commit rejected with clear error.
10. **Telemetry redaction.** Run any skill that emits telemetry while in a session with linear-fetch context. Inspect `.claude/incidents/` payloads — zero Linear identifiers, zero URLs.

## Open Questions

- Where exactly does the `canUseTool` allowlist live? Implementation phase must locate it before TR1 can be marked done.
- Does `list_comments` accept an `orderBy` parameter? Schema we loaded didn't include comments tool — needs `ToolSearch` at implementation time.
- Should the disclosure line include the issue title, or just the identifier? Title gives more context but increases the chance of titles containing PII bleeding into transcripts. Default: identifier only for v1.
