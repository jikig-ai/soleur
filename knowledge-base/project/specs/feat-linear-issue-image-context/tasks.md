---
title: Linear Issue Image Context — Tasks
status: ready
date: 2026-05-12
issue: "#3635"
plan: knowledge-base/project/plans/2026-05-12-feat-linear-issue-image-context-plan.md
branch: feat-linear-issue-image-context
worktree: .worktrees/feat-linear-issue-image-context/
---

# Tasks — feat-linear-issue-image-context

Derived from the plan. Use `Skill: soleur:work` to execute in order.

## Phase 0 — Preflight & load-bearing assumption verification

- [ ] 0.1 Run `ToolSearch` for `select:mcp__linear-server__get_issue,mcp__linear-server__list_comments,mcp__linear-server__extract_images`. Record which schemas loaded and whether `list_comments` accepts `orderBy`.
- [ ] 0.2 Spawn a one-off Task subagent with a parent prompt containing a public test image content block. Subagent returns `image_blocks_received: <bool>`. Document the result in `knowledge-base/project/learnings/best-practices/2026-05-12-task-subagent-prompt-text-only.md`.
- [ ] 0.3 If 0.2 returned `true` (subagents DO inherit image blocks), revise Phase 3 task wording — omit the persist-safe-summary substitution. Otherwise proceed.
- [ ] 0.4 `bun test plugins/soleur/test/components.test.ts` green on HEAD; `command -v jq` succeeds; record current word-budget headroom.

## Phase 1 — Skill scaffolding + redaction primitive

- [ ] 1.1 Create `plugins/soleur/skills/linear-fetch/` directory.
- [ ] 1.2 Write `plugins/soleur/skills/linear-fetch/scripts/redact-linear-urls.sh` with the `LINEAR_CDN_PATTERNS` array, character class `[^[:space:]<>"\x27)\]]+`, count-to-stderr behavior.
- [ ] 1.3 Write `plugins/soleur/skills/linear-fetch/scripts/redact-linear-urls.test.sh` with 10 fixtures: raw URL, markdown image `![](URL)`, HTML img tag `<img src="URL">`, autolink `<URL>`, link with title `[alt](URL "title")`, URL-encoded path, 5 URLs across 3 lines (count=5), zero URLs (count=0), URL followed by `]`, URL followed by `)`. Each asserts both substituted output AND stderr count.
- [ ] 1.4 Test the script on both bash 5.x (Linux) and bash 3.2 (macOS) — character class must parse identically.
- [ ] 1.5 Draft `plugins/soleur/skills/linear-fetch/SKILL.md` skeleton with frontmatter (`name`, third-person `description`, `allowed-tools`, `preconditions`), `## Caller Contract`, five phase headers (A–E), and `## Manual Test Runbook` (10 spec scenarios inline).

## Phase 2 — MCP integration + reference-detection regex

- [ ] 2.1 SKILL.md Phase A: reference-detection regex `[A-Z]{2,}-[0-9]+` AND URL form `linear\.app/[^/]+/issue/([A-Z]+-[0-9]+)`. Uppercase before dedup. Cap at 5; if matches > 5, invoke `AskUserQuestion` with three options (first 5, all, abort).
- [ ] 2.2 SKILL.md Phase B: for each matched ID, invoke `mcp__linear-server__get_issue` then `mcp__linear-server__list_comments`. Client-side sort by `createdAt desc` if MCP-side ordering unavailable (per Phase 0.1 finding). Take 10 most-recent. Silent 404 drop (false-positive); other failures emit `Linear fetch failed for <ID>: <reason>. Continuing without image context.`
- [ ] 2.3 SKILL.md Phase C: concatenate description + comment bodies with delimiter `\n\n--- comment by <author> on <createdAt> ---\n\n`. Pass to `mcp__linear-server__extract_images(markdown=<blob>)`.
- [ ] 2.4 SKILL.md Phase D: disclosure lines (images / text-only / soft anomaly), dual-artifact return contract, telemetry-redaction requirement.
- [ ] 2.5 SKILL.md Phase E: warn-and-continue on MCP failure.
- [ ] 2.6 Manual run against a real SOL-* issue with one description image: disclosure matches, image visible, persist-safe summary `grep -c uploads.linear.app == 0`.
- [ ] 2.7 Manual run with `SOL-999999`: silent no-op.
- [ ] 2.8 Manual run with six-ID input: `AskUserQuestion` fires before any MCP call.

## Phase 2.5 — Telemetry redaction (TR7)

- [ ] 2.5.1 Audit `emit_incident` call sites added by this skill (should be zero).
- [ ] 2.5.2 Add a telemetry-wrapper helper script `scripts/assert-no-linear-telemetry.sh` reusable for tests; asserts no `SOL-\d+`, no `uploads.linear.app`, no UUID-style Linear IDs.
- [ ] 2.5.3 Document the telemetry constraint in SKILL.md Phase D.

## Phase 3 — Caller wiring

- [ ] 3.1 `grep -c '\$ARGUMENTS' plugins/soleur/skills/one-shot/SKILL.md` returns exactly 1 (verify before edit).
- [ ] 3.2 Edit `plugins/soleur/skills/one-shot/SKILL.md`: insert new Step 0a before Step 0b; modify subagent prompt template to substitute the `$ARGUMENTS` placeholder with `persist_safe_summary`.
- [ ] 3.3 Edit `plugins/soleur/skills/brainstorm/SKILL.md`: insert new Phase 0.4 between Phase 0.1 and Phase 0.5; add note in Phase 0.5 that persist-safe summary is embedded in leader prompts.
- [ ] 3.4 `grep -n 'Skill: soleur:linear-fetch'` on both files returns exactly 1 line each.

## Phase 4 — CI grep job

- [ ] 4.1 Audit `.github/workflows/` for the highest-coverage `pull_request`-triggered workflow with no path filter.
- [ ] 4.2 Add `pii-grep` job to that workflow; greps `git diff base..head` for `uploads\.linear\.app`; fails PR with `::error::` annotation pointing at the spec.
- [ ] 4.3 Local verify: synthesize a fixture commit with `https://uploads.linear.app/TEST-FIXTURE-NOT-REAL.png`; confirm `git diff base..HEAD | grep` matches.

## Phase 5 — Automated tests

- [ ] 5.1 Write `plugins/soleur/skills/linear-fetch/scripts/render-caller-template.sh` (helper).
- [ ] 5.2 Write `plugins/soleur/skills/linear-fetch/scripts/persist-safe-integration.test.sh`: synthesized Linear MCP fixture (uses `TEST-FIXTURE-NOT-REAL.png`), runs redaction, renders through both caller templates, asserts zero `uploads.linear.app` matches in final rendered prompts, disclosure-line shape matches spec, telemetry wrapper assertion passes.
- [ ] 5.3 `bun test plugins/soleur/test/components.test.ts` green.
- [ ] 5.4 Update SKILL.md `## Manual Test Runbook` with the 10 spec scenarios.

## Phase 6 — Documentation & ship handoff

- [ ] 6.1 Draft PR body with `## Changelog` section and `Ref #3635`.
- [ ] 6.2 Apply `semver:minor` label.
- [ ] 6.3 File v1.1 follow-up issue: bot-comment filtering. Labels: `domain/engineering`, `enhancement`, `priority/p3-low`.
- [ ] 6.4 File v2 follow-up issue: extend `/soleur:linear-fetch` to `/soleur:plan` and `/soleur:fix-issue`. Labels: `domain/engineering`, `enhancement`, `priority/p3-low`.
- [ ] 6.5 Request CPO sign-off via PR comment (per `requires_cpo_signoff: true`).
- [ ] 6.6 Run `/soleur:review` and confirm `user-impact-reviewer` fires.

## Post-merge (operator)

- [ ] PM.1 Real-issue smoke: `/soleur:one-shot fix SOL-<real-id>` with image — disclosure fires, image visible, plan contains zero CDN URLs.
- [ ] PM.2 Text-only smoke: `/soleur:brainstorm` against a text-only Linear issue — `text-only issue, no images.` line fires.
- [ ] PM.3 CI gate smoke: push a branch via raw `git` with `https://uploads.linear.app/x.png` in a staged file; confirm the `pii-grep` CI job fails the PR.
- [ ] PM.4 Cap-prompt smoke: six-ID input triggers `AskUserQuestion`.
- [ ] PM.5 Close `#3635` with `gh issue close 3635 --comment "..."` after PM.1–4 pass.
