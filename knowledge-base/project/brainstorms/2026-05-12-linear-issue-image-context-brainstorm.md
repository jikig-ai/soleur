---
title: Linear issue image context for /soleur:one-shot and /soleur:brainstorm
date: 2026-05-12
status: captured
brand_survival_threshold: single-user incident
related_pr: https://github.com/jikig-ai/soleur/pull/3631
worktree: .worktrees/feat-linear-issue-image-context
---

# Linear Issue Image Context

## What We're Building

A new skill `/soleur:linear-fetch` that detects Linear issue references (`SOL-39`, `LIN-12`, or `linear.app/.../issue/<ID>/...` URLs) in user input, fetches the issue via `mcp__linear-server__get_issue`, pulls images out of the description and the 10 most-recent comments via `mcp__linear-server__extract_images`, and surfaces them into the active conversation as visual context.

`/soleur:one-shot` and `/soleur:brainstorm` invoke this skill (via the Skill tool) at their respective input-parsing phases when a Linear reference is detected. The skill is auto-triggered — no `--linear` flag.

## Why This Approach

The user's bug reports, design issues, and customer-feedback tickets in Linear almost always carry screenshots in the description or follow-up comments. Today the agent gets a text issue ID like `SOL-39`, fetches the markdown description, and reasons about the bug *blind* — the screenshot that prompted the ticket never enters context. The agent then asks the user to describe what they see, or guesses, and the user has to re-paste the screenshot manually. That round-trip is the friction.

`mcp__linear-server__extract_images` is the load-bearing primitive. Its schema (verified at brainstorm time): accepts markdown content, returns viewable images directly to the model. No filesystem hop, no auth handling, no signed-URL exposure, no `/tmp` cache. The MCP server brokers Linear authentication on our behalf and streams image bytes into the active conversation. That collapses the design from "build a Linear image cache" to "wire up two MCP calls and a redaction rule."

A new skill (vs. inlining the logic in each SKILL.md or a shared markdown reference) is the user's pick because it's discoverable (`/soleur:linear-fetch` shows up in `/soleur:help`), reusable by any future Linear-aware workflow (plan, fix-issue, work, ship, …) without re-importing logic, and testable in isolation — the failure modes (token expired, 403, rate limit, no images) have one canonical handling site.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Where to put logic | New `/soleur:linear-fetch` skill | User selected. Discoverable + reusable + isolated failure-mode handling. |
| Trigger surface | Auto-detect via regex on user input | Friction of an explicit `--linear` flag defeats the compounding-workflow thesis. Regex `[A-Z]+-\d+` or `linear.app/.../issue/<ID>` is distinctive enough that false positives are rare. |
| Scan surface | Description + 10 most-recent comments | Linear screenshots often live in follow-up comments. Cap at N=10 bounds prompt size. |
| Image transport | `extract_images` MCP tool (model-direct) | Tool schema confirmed: returns viewable images directly to model. Zero filesystem footprint. |
| Failure mode | Warn and continue without images | Brainstorm/one-shot must remain runnable on stale tokens or offline. Issue ID stays in prompt as text. |
| Disclosure | One-line stdout on detection | `Detected SOL-39 — fetched issue + N images.` Avoids surprise without flag friction. |
| v1 callers | `/soleur:one-shot` and `/soleur:brainstorm` only | User's original ask. `/soleur:plan` and `/soleur:fix-issue` are v2 candidates. |
| Persisted-artifact guard | Hard redaction of `uploads.linear.app/*` URLs from any text written to `knowledge-base/`, PR bodies, learnings, or commit messages | Single non-negotiable safety rail. Keeps the "no new customer-data flow" argument defensible — see User-Brand Impact below. |

## User-Brand Impact

**Artifact named:** Linear issue images (screenshots, diagrams, customer support attachments) embedded in issue descriptions and comments.
**Vector named:** Cross-tenant data leak via persisted artifact. The Soleur repo is public on GitHub (`github.com/jikig-ai/soleur`). Linear issues are private workspace data. If a Linear image URL — particularly an `uploads.linear.app` signed URL, which is a bearer credential — lands in a committed brainstorm/spec/PR body/learnings doc, anyone with the public GitHub URL can fetch the underlying image until the URL expires.
**Threshold:** `single-user incident` — a single committed signed URL exposes one customer's screenshot to the public internet for the URL's validity window.

**Guard (single rule, non-negotiable):** The `/soleur:linear-fetch` skill MUST strip every `uploads.linear.app/[^\s)\]]+` URL from any text it returns to its caller for persistence. The skill returns two artifacts: (1) "agent context" (description + comments + images — model-visible only, not persisted) and (2) "persist-safe summary" (description with image URLs redacted to `[linear-image: <count> attached to context]`, used when any caller wants to write the issue body to a brainstorm/spec/PR/learning file).

**Secondary guard:** Add `**/uploads.linear.app/**` and the literal regex `uploads\.linear\.app` to a pre-commit grep that fails the commit if any staged file contains a Linear CDN URL. Belt-and-suspenders behind the in-skill redaction.

**Explicitly scoped out of this PR (user's call):** Linear added to vendor DPA register, sub-processor disclosure update in `docs/legal/gdpr-policy.md`, `/soleur:gdpr-gate` run on PR #3631, privacy-policy legitimate-interest note. CLO flagged these as pre-merge items; user determined that under the redaction guard above, this feature does not create a materially new sub-processor data flow (Linear is already a vendor; the operator already views these images in the Linear UI; `extract_images` does not persist images to disk). If the redaction guard is breached in code review, these legal items become PR-blocking.

## Open Questions

- **v2 caller scope.** Should `/soleur:plan` and `/soleur:fix-issue` adopt `/soleur:linear-fetch` after v1 lands? Plan already has a Linear branch for issue *creation*; teaching it to consume Linear context for *reading* mirrors the GitHub `#N` intake symmetry. Defer until we have usage data from one-shot + brainstorm.
- **Linear MCP allowlist.** The repo's `canUseTool` allowlist (`2026-04-06-mcp-tool-canusertool-scope-allowlist.md`) should add `mcp__linear-server__get_issue`, `mcp__linear-server__list_comments`, `mcp__linear-server__extract_images` explicitly — not a `mcp__linear-server__*` wildcard. Where exactly does this allowlist live? Implementation phase must locate it.
- **Comment ordering.** `list_comments` ordering by `created` desc isn't documented in the schema we loaded. The 10-most-recent cap assumes desc ordering — verify at implementation time and add explicit `orderBy` if the schema supports it.
- **Identifier patterns beyond `SOL-`.** Other Linear workspaces use different prefixes (e.g., `LIN-`, `ENG-`). The regex `[A-Z]+-\d+` is generic enough but will false-positive on GitHub issue refs like `PR-123` if anyone writes them. Risk-accept for v1; the `get_issue` failure path warns and continues.
- **Empty-result detection.** If `extract_images` returns zero images (issue is text-only), the disclosure line should say `Detected SOL-39 — text-only issue, no images.` not `fetched N images.` Confirms to the user that the fetch ran.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** New skill is the right shape; the `extract_images` MCP tool collapses the design — no filesystem cache, no auth handling needed. Cross-tenant artifact-leak is the highest-likelihood × highest-blast risk; the redaction guard on persisted text is the single load-bearing safety rail.

### Legal (CLO)

**Summary:** Linear images frequently carry end-user PII; the public-GitHub repo makes any persisted Linear URL a credential leak (signed URLs are bearer credentials). Flagged 5 pre-merge items (vendor DPA register, sub-processor disclosure, GDPR-gate, privacy policy note, processing-activity entry). User opted to scope these out under the redaction-guard condition; legal items convert to PR-blocking if the guard is breached in review.

### Product (CPO)

**Summary:** Scope v1 to one-shot + brainstorm only (per user ask); defer plan + fix-issue to v2. Auto-detect over flag, scan description + comments capped at 10 images, warn-and-continue on MCP failure. No blocking roadmap dependency — Linear is dev tooling, not product surface.

## Capability Gaps

- **Linear MCP allowlist entry.** Engineering domain. The repo's MCP `canUseTool` allowlist currently has zero entries for `mcp__linear-server__*` (verified via `grep -rn "mcp__linear" /home/harry/Documents/Stage/Soleur/soleur/plugins/` — no output). The implementation phase must add the three specific tools (`get_issue`, `list_comments`, `extract_images`) without a wildcard, per the lesson in `2026-04-06-mcp-tool-canusertool-scope-allowlist.md`.

- **Pre-commit guard for Linear CDN URLs.** Engineering / ship domain. No existing pre-commit hook scans staged content for `uploads.linear.app` URLs (verified via `grep -rn "uploads.linear.app\|linear.cdn" /home/harry/Documents/Stage/Soleur/soleur/.claude/hooks/` — no output). Implementation must add this as a second-tier guard behind the in-skill redaction.

- **No precedent for image-as-prompt-context.** Engineering domain. The repo's image flows today (`feature-video`, `ux-audit`, `reproduce-bug`, `frontend-design`) all capture-and-upload but none `Read` an image into multimodal context mid-skill (verified by repo-research-analyst: 18 skill `scripts/` dirs scanned, zero `Read("foo.png")`-style invocations). `/soleur:linear-fetch` is the first skill to use MCP-direct image passthrough, so the SKILL.md must explicitly document the pattern for the next skill that needs it.
