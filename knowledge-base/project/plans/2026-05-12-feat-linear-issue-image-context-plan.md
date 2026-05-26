---
title: Linear Issue Image Context Skill
status: draft
date: 2026-05-12
issue: "#3635"
related_pr: "https://github.com/jikig-ai/soleur/pull/3631"
branch: feat-linear-issue-image-context
worktree: .worktrees/feat-linear-issue-image-context/
brainstorm: knowledge-base/project/brainstorms/2026-05-12-linear-issue-image-context-brainstorm.md
spec: knowledge-base/project/specs/feat-linear-issue-image-context/spec.md
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
labels:
  - domain/engineering
  - enhancement
  - priority/p2-medium
  - compliance/critical
---

# Linear Issue Image Context — Implementation Plan

## Overview

A new skill `plugins/soleur/skills/linear-fetch/` detects Linear issue references (`SOL-39`, `LIN-12`, or `linear.app/.../issue/<ID>/...` URLs) in caller input, fetches the issue body and the 10 most-recent comments via `mcp__linear-server__get_issue` + `mcp__linear-server__list_comments`, and pipes the combined markdown through `mcp__linear-server__extract_images` so Linear-hosted screenshots stream directly into the active model conversation as visual context.

`/soleur:one-shot` and `/soleur:brainstorm` invoke the skill at their respective intake points. Detection is auto (no `--linear` flag). The single non-negotiable safety rail is the **persist-safe redaction**: the skill returns a separate string with every `uploads.linear.app/*` URL rewritten to `[linear-image: <count> attached to context]`, used wherever any caller writes text to `knowledge-base/`, the PR body, a learning, or a commit message. A CI grep job on every PR diff is the durable backstop — it catches CDN URLs regardless of how the commit was authored (`git commit -am`, `--amend`, force-push, web UI, gh CLI).

The brainstorm framed the threshold at **single-user incident** (a leaked signed URL exposes one customer's screenshot to the public internet for the URL's validity window) which makes this a CPO-sign-off and `user-impact-reviewer`-eligible feature.

## Research Reconciliation — Spec vs. Codebase

The spec inherits three claims from the brainstorm that don't match the codebase as-is. They are reconciled here so the implementation phase doesn't pivot mid-build.

| Spec claim | Reality in this repo | Plan response |
|---|---|---|
| **TR1.** "Add `mcp__linear-server__*` to the `canUseTool` allowlist. No wildcard. Location TBD. Lesson `2026-04-06-mcp-tool-canusertool-scope-allowlist.md` governs the pattern." | `canUseTool` is a runtime callback inside `apps/web-platform/server/agent-runner-query-options.ts:67` — the **Soleur web-platform's SDK runner** (a separate sandbox that hosts user-facing agents). It does NOT govern the Claude Code session a developer runs `/soleur:one-shot` in. The Claude Code session's only allowlist is `.claude/settings.json` `permissions.allow` (currently Bash-only) and `enabledMcpjsonServers` (currently `["playwright"]`). Linear MCP is registered at the **user level** via `~/.claude/.credentials.json` `mcpOAuth.linear-server`. No project-level Linear MCP registration exists. The "no wildcard" framing is imported from an SDK-runtime concern that doesn't apply to the operator's session. | **Drop the wildcard-forbidden framing.** Demote to a single SKILL.md `preconditions:` line: `Linear MCP server is authenticated (mcp__linear-server__authenticate has been run)`. Phase 0 preflight surfaces a clear actionable message if the schema lookup for the three required tools fails. Plugin-level `mcpServers` registration is deferred — re-add when a second operator hits the auth-missing path. |
| **FR10.** "`/soleur:brainstorm` SKILL.md adds the same invocation at **Phase 1.1** (research) so domain leaders spawned in **Phase 0.5** have already seen the images." | Phase ordering contradicts itself: 0.5 fires before 1.1. Additionally, domain leaders are spawned via `Task` general-purpose subagents — their context is the **prompt string only**, not the parent's image content blocks (verified at Phase 0 of this plan via an explicit probe). | **Insert the linear-fetch invocation at a new Phase 0.4** (between Phase 0.1 User-Impact Framing and Phase 0.5 Domain Sweep). Leaders get the **persist-safe summary** embedded in their prompts (text only); the **brainstorm conversation itself** retains the live image content blocks for Phase 2 Synthesis and Phase 3 Capture. Rewrite FR10's "leaders have already seen the images" to "leaders' prompts contain the persist-safe summary; the brainstorm parent conversation retains the images." |
| **FR9.** "`/soleur:one-shot` adds a step in its argument-parsing phase: if input contains a Linear reference, invoke `Skill: soleur:linear-fetch` with the input as args before proceeding to plan." | One-shot's plan + deepen run inside a `Task general-purpose` subagent (one-shot SKILL.md `Steps 1-2: Plan + Deepen (Isolated Subagent)`). A fetch in the parent leaves the **subagent blind** to image content blocks (Task subagents inherit prompt text only — verified at Phase 0). The plan-writer doesn't strictly need images; the parent does (Steps 3+ work / review / ship). | **Single fetch in the parent at a new Step 0a** (before existing Step 0b worktree creation). Parent retains images for Steps 3+. The subagent prompt template substitutes `$ARGUMENTS` with `persist_safe_summary` (one substitution site, verified before edit via `grep -c '\$ARGUMENTS'`). No second fetch. |

**Additional codebase verifications performed during planning:**

- Zero existing skills `Read()` an image into model context mid-skill (confirmed in brainstorm Capability Gaps via repo-research-analyst); `/soleur:linear-fetch` is the first multimodal-MCP-passthrough skill.
- `grep -rn "mcp__linear" plugins/ .claude/` returned zero hits — no existing Linear MCP allowlist or usage in this repo.
- `grep -rn "uploads.linear.app"` returned only the brainstorm and spec themselves — confirms there is no historical CDN URL leak to scrub.
- No `.husky/`, no project-managed `.git/hooks/pre-commit` — the existing hook surface is Claude Code event hooks under `.claude/hooks/`. A Bash-PreToolUse "pre-commit" hook in this repo would have multiple bypass paths (`git commit -am` stages outside the `git diff --cached` window the hook would see; `--amend --no-edit`, `git push --force` of pre-existing CDN URLs, web UI commits, gh CLI commits all bypass entirely). The plan therefore relies on **in-skill redaction (layer 1) + CI grep on every PR diff (layer 2)** — two layers with no shared bypass.
- `bun test plugins/soleur/test/components.test.ts` passes (1029/1029), word-budget headroom is healthy. Target the new skill description at ≤30 words per the skill-creator convention.
- Code-review overlap check (`gh issue list --label code-review`) returned no open issues touching this plan's Files-to-Edit surface.
- Verified labels exist via `gh label list`: `domain/engineering`, `enhancement`, `priority/p2-medium`, `compliance/critical`.

## User-Brand Impact

**Artifact named:** Linear issue images (screenshots of bugs, customer support attachments, internal design diagrams, end-user PII) embedded in issue descriptions and comments.

**Vector named:** Cross-tenant data leak via persisted artifact. The Soleur repo is public on GitHub (`github.com/jikig-ai/soleur`). Linear issues are private workspace data. A single `uploads.linear.app` signed URL committed to `knowledge-base/`, a learning doc, the PR body, or a commit message becomes a bearer credential for whoever fetches the public GitHub URL — until Linear's signed-URL validity window expires.

**Brand-survival threshold:** `single-user incident` — one committed signed URL exposes one customer's image to the public internet.

**CPO sign-off required at plan time:** The brainstorm carried CPO assessment forward; the implementation step list below requires the user to confirm CPO sign-off (or invoke CPO via passive routing) before `/soleur:work` runs. `user-impact-reviewer` will fire at review-time per `plugins/soleur/skills/review/SKILL.md` conditional-agent block.

**Guard architecture (2 layers, no shared bypass):**

1. **In-skill redaction (load-bearing, single rule).** The skill returns two artifacts. `agent_context` is the live markdown + image blocks streamed into the calling conversation only. `persist_safe_summary` is the same text with `s#https?://uploads\.linear\.app/[^[:space:]<>"'\)\]]+#[linear-image: REDACTED]#g` applied. Callers MUST use `persist_safe_summary` for any write to disk, PR body, or commit message. The skill's contract documents this in a `## Caller Contract` section.
2. **CI grep job (durable backstop).** A small `pii-grep` job in `.github/workflows/` runs on `pull_request` (all paths, not path-filtered) and fails the PR if the diff between `base..head` contains a `uploads.linear.app` URL. This catches every commit author path that bypasses Claude Code (`git commit -am`, `--amend`, force-push that rewrites history, web UI commits, gh CLI commits).

A Bash-PreToolUse hook was considered and rejected: it would only fire inside Claude Code sessions, would miss `git commit -am` (stages outside the `git diff --cached` window), `git commit --amend --no-edit` (no new staged content), and any path involving `git push --force` or out-of-harness commit authors. Two layers with disjoint bypass profiles are stronger defense than three layers where two share the same bypass.

If either layer fails review, the legal items scoped out in the brainstorm (Linear DPA register entry, sub-processor disclosure in `docs/legal/gdpr-policy.md`, privacy-policy legitimate-interest note, `/soleur:gdpr-gate` on PR #3631) automatically re-enter scope as PR-blocking — per the brainstorm CLO carry-forward.

**Out-of-scope artifacts (intentional, named by user-impact-reviewer at PR #3631 review-time):** The two-layer defense above is **image-URL-shaped only**. The following artifacts flow through the persist-safe summary path verbatim and are NOT redacted — operators selecting which Linear issues to invoke against `/soleur:one-shot` or `/soleur:brainstorm` are responsible for issue selection per the threat model. If any of the below is material, widen the redaction or use a different invocation pattern:

- **Comment / issue body text** is persisted unredacted. Customer PII pasted as prose into a Linear issue body (passwords, account numbers, free-text complaints) is NOT redacted by this skill. The redaction primitive operates only on `uploads.linear.app/*` URLs, not on prose content.
- **`comment.author.displayName`** is inlined in the comment delimiter (`--- comment by <author.displayName> on <createdAt> ---`) and persisted. Workspaces using `customer@domain.com` or full names as display names will have those identities persisted to PR bodies, brainstorm docs, and knowledge-base writes.
- **Operator-facing stdout** (Phase E failure warnings, Phase D disclosure lines) intentionally names the Linear identifier (`SOL-39`) so operators can take corrective action. Operators sharing their Claude Code transcripts publicly (Slack, Discord, GitHub issues) are out of scope of this guard.
- **Anthropic conversation retention** is the trust boundary for `agent_context` (the full markdown + image content blocks held in the parent conversation). Governed by Anthropic ToS; out of scope of this guard.

The `pii-grep` CI job is the durable backstop for the URL class only — it does NOT scan for comment-body prose, display names, or identifiers. The single-user incident threshold is bounded to **leaked signed bearer credentials**, not to prose PII or workspace identity leaks.

## Implementation Phases

### Phase 0 — Preflight, capability checks, and load-bearing assumption verification

Estimated effort: 45 min.

1. **MCP schema preflight.** Attempt a `ToolSearch` lookup for `select:mcp__linear-server__get_issue,mcp__linear-server__list_comments,mcp__linear-server__extract_images`. If any tool returns no schema, the developer must run `mcp__linear-server__authenticate` before continuing. Capture which tools were found and confirm whether `list_comments` accepts an `orderBy` parameter (Open Question #2 in spec — drives whether Phase 2 needs client-side sort).
2. **Task-subagent context-boundary probe (load-bearing).** Spawn a one-off `Task general-purpose` subagent with a parent prompt that contains an image content block (use a publicly-fetchable test image, NOT a Linear CDN URL). The subagent's instruction: "Return `image_blocks_received: true` if you see an image content block in your initial prompt, else `image_blocks_received: false`." Cite the result in `knowledge-base/project/learnings/best-practices/2026-05-12-task-subagent-prompt-text-only.md` so the assumption Phase 3 relies on is documented for the next plan that needs it. If the probe returns `true` (subagents DO inherit image blocks), revise Phase 3 to omit the persist-safe-summary substitution.
3. **Test baselines green.** `bun test plugins/soleur/test/components.test.ts` passes on HEAD; `command -v jq` succeeds (used in CI grep job parsing) — NB: even with the hook cut, `jq` remains a useful dep in adjacent hooks; do not assume it's free.
4. **Word-budget headroom.** `grep -h '^description:' plugins/soleur/skills/*/SKILL.md | wc -w` recorded so Phase 1's draft stays under the 1800-word cap.

**Exit criteria.** All three MCP tool schemas loaded; subagent probe completed with documented result; tests green; word-budget headroom > 30 words.

### Phase 1 — Skill scaffolding + redaction primitive

Estimated effort: 60 min.

Create `plugins/soleur/skills/linear-fetch/`:

```text
plugins/soleur/skills/linear-fetch/
├── SKILL.md
└── scripts/
    ├── redact-linear-urls.sh     # pure-Bash redaction primitive
    └── redact-linear-urls.test.sh
```

The 10 spec Test Scenarios live inline in SKILL.md as a `## Manual Test Runbook` section — no separate runbook file.

`SKILL.md` skeleton:

```markdown
---
name: linear-fetch
description: "This skill should be used when a user input contains a Linear issue reference (e.g., SOL-39 or linear.app/.../issue/<ID>) and the downstream agent needs the screenshots embedded in the issue as visual context."
allowed-tools:
  - Bash
  - mcp__linear-server__get_issue
  - mcp__linear-server__list_comments
  - mcp__linear-server__extract_images
preconditions:
  - Linear MCP server is authenticated (mcp__linear-server__authenticate has been run)
---

# Linear Issue Image Context

## Caller Contract

This skill returns TWO artifacts:

1. **Agent context** — markdown + image content blocks streamed into the active conversation. Callers MUST NOT write this to disk, a PR body, a commit message, or a learning file.
2. **Persist-safe summary** — same text with every `uploads.linear.app/*` URL redacted. Callers MUST use this variant for any persistence.

## Phases

### Phase A — Reference detection
(regex, dedup, cap=5 with AskUserQuestion for 6+)

### Phase B — Fetch + comment scan
(get_issue, list_comments, ordering, cap=10 most-recent)

### Phase C — Image passthrough
(concatenate, call extract_images, retain image content blocks)

### Phase D — Disclosure & dual-artifact return
(disclosure line, redaction, return contract, telemetry redaction per TR7)

### Phase E — Failure handling
(warn-and-continue per FR8)

## Manual Test Runbook
(10 spec scenarios inline)
```

`redact-linear-urls.sh`:

```bash
#!/usr/bin/env bash
# Reads stdin, writes redacted text to stdout, writes redaction count to stderr.
set -euo pipefail

# Extensible list of Linear-hosted CDN hostname patterns. Adding a new
# pattern (e.g., cdn.linear.app) is a one-line change with a test.
LINEAR_CDN_PATTERNS=(
  'https?://uploads\.linear\.app/[^[:space:]<>"\x27)\]]+'
)
# NB: character class excludes whitespace, <, >, ", ', ), ] — covers
# markdown autolinks <URL>, HTML attributes "URL"/'URL', markdown
# link-reference ](URL), markdown collection [URL]. Tested against:
# raw URL, `![alt](URL)`, `<img src="URL">`, `<URL>` autolink,
# `[caption](URL "alt")`, URL-encoded paths (%20, %2F).

input=$(cat -)
count=0
output="$input"
for pattern in "${LINEAR_CDN_PATTERNS[@]}"; do
  matches=$(printf '%s' "$output" | grep -oE "$pattern" | wc -l | tr -d ' ')
  count=$((count + matches))
  output=$(printf '%s' "$output" | sed -E "s#$pattern#[linear-image: REDACTED]#g")
done
printf '%s' "$output"
printf '%s' "$count" >&2
```

The character class `[^[:space:]<>"\x27)\]]+` (using `\x27` for single quote to avoid bash-quote escapes) is the chosen redaction class — every excluded character is justified in the inline comment. The same class is used for both `grep -oE` (count) and `sed -E` (substitution), so count and substitution cannot disagree.

**Verification at end of phase (automated):**

- `redact-linear-urls.test.sh` fixtures: raw URL, markdown image, HTML img tag, autolink `<URL>`, link with title `[alt](URL "title")`, URL-encoded path `https://uploads.linear.app/TEST-FIXTURE-NOT-REAL-foo%20bar.png`, 5 URLs across 3 lines (count = 5), zero URLs (count = 0), URL followed by `]` (`[![]](URL)]`), URL followed by `)`.
- Each fixture asserts both the substituted output AND the stderr count.
- Bash compat: tested on `bash 5.x` (Linux) AND `bash 3.2` (macOS default) — `[^[:space:]<>"\x27)\]]+` must parse identically on both.

### Phase 2 — MCP integration + reference-detection regex

Estimated effort: 90 min.

1. Phase A reference-detection logic in SKILL.md. Regex `[A-Z]{2,}-[0-9]+` AND URL form `linear\.app/[^/]+/issue/([A-Z]+-[0-9]+)`. Uppercase before dedup. If matches > 5, invoke `AskUserQuestion` with options: "Process first 5 (default)", "Process all (may bloat context)", "Abort". The user's pick gates Phase B.
2. Phase B fetch: for each matched ID, `mcp__linear-server__get_issue` then `mcp__linear-server__list_comments`. If `list_comments` returns more than 10 without `orderBy` support, sort client-side by `createdAt desc` (Phase 0 told us which). Take the 10 most-recent. **404 path:** silently drop (false-positive per spec TR3); no warning printed. **Other failures:** `Linear fetch failed for <ID>: <reason>. Continuing without image context.`
3. Phase C: concatenate description + each kept comment's body into one markdown blob with delimiters (`\n\n--- comment by <author> on <createdAt> ---\n\n`). Pass to `mcp__linear-server__extract_images(markdown=<blob>)`. The MCP server returns image content blocks directly into the conversation.
4. Phase D disclosure lines:
   - Images present: `Detected <ID> — fetched issue + N images from description and M comments.`
   - Text-only: `Detected <ID> — text-only issue, no images.`
   - URLs present but extract_images returned zero (FR11 soft anomaly): `Detected <ID> — N image URLs found but extraction returned 0 images (soft anomaly).`
5. Phase D return contract: emit two clearly labeled blocks. Caller consumes via the standard Skill tool return mechanism.

**Verification at end of phase.**

- Manual run against a known SOL-* issue with one description image: disclosure matches; image visible in conversation; `grep -c 'uploads.linear.app'` on the persist-safe summary == 0.
- `SOL-999999` (404): silent no-op, no warning, no abort.
- Multi-ID input `SOL-39 and SOL-42`: two disclosure lines.
- Six-ID input: `AskUserQuestion` fires before any MCP call.

### Phase 2.5 — Telemetry redaction (TR7)

Estimated effort: 30 min.

Spec TR7 mandates that incident telemetry emitted from this skill (via `.claude/hooks/lib/incidents.sh emit_incident`) MUST NOT contain Linear identifiers, issue titles, image URLs, or signed-URL fragments.

1. Audit every `emit_incident` call site in the new skill. The skill's only telemetry call is the rule-application emit for `hr-gdpr-gate-on-regulated-data-surfaces` if it fires; the rule does not fire for this skill (no regulated-data surface), so the audit confirms zero current call sites.
2. Add a Phase 1 unit-test extension: parse `redact-linear-urls.test.sh` outputs through a wrapper that asserts no emitted text contains `SOL-\d+`, no `uploads.linear.app`, no Linear API ID format (UUID-style). The wrapper is reusable for the integration test in Phase 5.
3. Document the constraint in SKILL.md Phase D: "When emitting any telemetry, the skill MUST use generic strings only (e.g., `linear-fetch applied`). Identifier, title, and URL are forbidden."
4. Acceptance Criterion (added below): `grep -rn 'emit_incident' plugins/soleur/skills/linear-fetch/` returns zero, OR every match passes the wrapper assertion.

### Phase 3 — Caller wiring (one-shot, brainstorm)

Estimated effort: 60 min.

**`/soleur:one-shot` SKILL.md** — add a new **Step 0a** before existing Step 0b. Before editing, verify with `grep -c '\$ARGUMENTS' plugins/soleur/skills/one-shot/SKILL.md` that there is exactly one substitution site in the subagent prompt template (so the substitution is unambiguous).

```markdown
**Step 0a: Linear context preflight.** Scan `$ARGUMENTS` for substrings matching `[A-Z]{2,}-[0-9]+` or `linear\.app/[^/]+/issue/`. If any match:

1. Invoke `Skill: soleur:linear-fetch` with `$ARGUMENTS` as args. Capture both `agent_context` (kept in the conversation) and `persist_safe_summary` (passed downstream as text).
2. When constructing the Task prompt for Steps 1-2 (Plan + Deepen), substitute the original `$ARGUMENTS` placeholder with `persist_safe_summary` in the `ARGUMENTS:` line of the prompt template. **Do NOT pass image URLs to the subagent.** The subagent's prompt remains text-only; the parent retains the images for Steps 3+ (work, review, ship).

If no match, proceed directly to Step 0b unchanged.
```

**`/soleur:brainstorm` SKILL.md** — add a new **Phase 0.4** between existing Phase 0.1 (User-Impact Framing) and Phase 0.5 (Domain Sweep):

```markdown
### Phase 0.4: Linear context preflight

Scan `$ARGUMENTS` for Linear issue references. If any match, invoke `Skill: soleur:linear-fetch` with `$ARGUMENTS` and capture both return artifacts. The brainstorm conversation retains `agent_context` for Phase 2 Synthesis and Phase 3 Capture. When spawning Phase 0.5 domain leaders via Task, embed `persist_safe_summary` in the leader prompt's context section. Domain leaders do not receive image content blocks (Task subagents inherit prompt text only — verified in Phase 0 of the plan).

Phase 0.4 must complete before Phase 0.5 spawns leaders; they are sequential despite Phase 0.5 internally parallelizing leaders.

If no match, continue to Phase 0.5 unchanged.
```

**Verification.**

- `grep -n 'Skill: soleur:linear-fetch' plugins/soleur/skills/one-shot/SKILL.md plugins/soleur/skills/brainstorm/SKILL.md` returns exactly two lines.
- Manual end-to-end: run `/soleur:brainstorm fix SOL-X bug` and confirm the disclosure line fires before any domain-leader Task spawn or `AskUserQuestion`.

### Phase 4 — CI grep (durable backstop)

Estimated effort: 30 min.

Add a small `pii-grep` job to a `pull_request`-triggered GitHub Actions workflow that runs on every PR (no path filter). Choose the host workflow at implementation time by auditing `.github/workflows/` for the highest-coverage `pull_request: {types: [opened, synchronize, reopened]}` workflow.

```yaml
pii-grep:
  runs-on: ubuntu-latest
  if: github.event_name == 'pull_request'
  steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 0
    - name: Scan PR diff for Linear CDN URLs
      run: |
        base="${{ github.event.pull_request.base.sha }}"
        head="${{ github.event.pull_request.head.sha }}"
        if git diff --no-color "$base".."$head" | grep -E 'uploads\.linear\.app'; then
          echo "::error::PR diff contains uploads.linear.app URL — see knowledge-base/project/specs/feat-linear-issue-image-context/spec.md FR7"
          exit 1
        fi
```

**Verification.**

- Synthesize a fixture PR (locally, no push) where a commit adds a file with `https://uploads.linear.app/TEST-FIXTURE-NOT-REAL.png` (or any non-fixture URL — the goal is to verify the gate fires; the TEST-FIXTURE-NOT-REAL token is allowlisted so use a real-shape URL for an actual gate-fires test). Run `git diff <base>..HEAD | grep -E 'https?://uploads\.linear\.app/'` and confirm the grep matches.
- Confirm the workflow runs on `pull_request` (not just `pull_request_target`) so it executes on forks too — fork PRs are uncommon for this private-development-context skill, but it's free to enable.

### Phase 5 — Tests (automated E2E for the load-bearing rail)

Estimated effort: 60 min.

The repo's test convention is `*.test.sh` for shell + `bun test` for TypeScript (confirmed via `ls .claude/hooks/*.test.sh`). No new test framework introduced.

**Unit test:**

- `plugins/soleur/skills/linear-fetch/scripts/redact-linear-urls.test.sh` — exercises the redaction primitive across the Phase 1 verification fixtures (10 cases including markdown, HTML, autolink, URL-encoded, edge characters).

**Automated E2E for the persist-safe rail (NEW, per Kieran P1.5):**

- `plugins/soleur/skills/linear-fetch/scripts/persist-safe-integration.test.sh` — synthesizes a Linear MCP response fixture (synthesized per `cq-test-fixtures-synthesized-only`, NOT a real API capture) containing a `uploads.linear.app` URL in description + two comments. Runs the redaction primitive against the concatenated markdown, then renders the resulting `persist_safe_summary` through both the one-shot Step 0a substitution template AND the brainstorm Phase 0.4 substitution template (template strings extracted to a tiny `scripts/render-caller-template.sh` helper that takes a template file and a summary string). Asserts:
  - Final rendered template strings contain zero `uploads.linear.app` matches.
  - Disclosure line shape matches the spec (`Detected <ID> — fetched issue + N images from description and M comments.`).
  - Telemetry wrapper (Phase 2.5) confirms no emitted text contains the synthesized Linear identifier or URL.

**Component-budget regression test:** Run `bun test plugins/soleur/test/components.test.ts` after adding the new skill description — must remain green.

**Manual integration tests (still required for the live MCP path):** The 10 spec Test Scenarios live in SKILL.md's `## Manual Test Runbook` section. Operators run them against a real Linear workspace before marking the smoke-test acceptance criteria done.

### Phase 6 — Documentation & ship handoff

Estimated effort: 20 min.

1. PR body uses `Ref #3635` (not `Closes`) — post-merge verification fires on the operator's first real Linear run before the issue closes.
2. PR body contains a `## Changelog` section per `plugins/soleur/AGENTS.md`. Semver label: `semver:minor` (new skill).
3. Close `#3635` manually with `gh issue close 3635 --comment "..."` after post-merge smoke tests pass (see Post-merge acceptance criteria).
4. **Deferred-capability tracking** per `wg-when-deferring-a-capability-create-a`: file two issues at plan-finalization time before `/work` begins:
   - **v1.1 follow-up: bot-comment filtering.** `Filter Linear comments by actor.isBot=false when extracting images so bot-authored comments don't crowd out human-authored screenshots in the 10-comment cap.` Labels: `domain/engineering`, `enhancement`, `priority/p3-low`.
   - **v2 follow-up: extend `/soleur:linear-fetch` to `/soleur:plan` and `/soleur:fix-issue`.** `After usage data from one-shot + brainstorm v1, evaluate adopting linear-fetch in /soleur:plan and /soleur:fix-issue.` Labels: `domain/engineering`, `enhancement`, `priority/p3-low`.

## Files to Create

| Path | Purpose |
|---|---|
| `plugins/soleur/skills/linear-fetch/SKILL.md` | The new skill (includes Manual Test Runbook section) |
| `plugins/soleur/skills/linear-fetch/scripts/redact-linear-urls.sh` | Pure-Bash redaction primitive |
| `plugins/soleur/skills/linear-fetch/scripts/redact-linear-urls.test.sh` | Unit test for redaction |
| `plugins/soleur/skills/linear-fetch/scripts/persist-safe-integration.test.sh` | E2E integration test for caller-template rail |
| `plugins/soleur/skills/linear-fetch/scripts/render-caller-template.sh` | Tiny helper used by E2E test |
| `knowledge-base/project/learnings/best-practices/2026-05-12-task-subagent-prompt-text-only.md` | Documents the Phase 0 probe result (load-bearing assumption for FR9/FR10) |

## Files to Edit

| Path | What changes |
|---|---|
| `plugins/soleur/skills/one-shot/SKILL.md` | Add Step 0a (Linear preflight); modify Task subagent prompt template to substitute `$ARGUMENTS` with `persist_safe_summary` (single substitution site, verified by `grep -c` before edit) |
| `plugins/soleur/skills/brainstorm/SKILL.md` | Add Phase 0.4 (Linear preflight); add note in Phase 0.5 to embed persist-safe summary in leader prompts |
| `.github/workflows/<target>.yml` | Add `pii-grep` job to the highest-coverage `pull_request`-triggered workflow (target chosen at implementation time after `ls .github/workflows/`) |

## Acceptance Criteria

### Pre-merge (PR)

- [x] `plugins/soleur/skills/linear-fetch/SKILL.md` exists with `Caller Contract`, five phases (A–E), `allowed-tools` listing the three Linear MCP tools explicitly, and `## Manual Test Runbook` inline.
- [x] `/soleur:help` output lists `linear-fetch` (auto-discovered via the existing Glob count; verify by running the help command).
- [x] `grep -h '^description:' plugins/soleur/skills/*/SKILL.md | wc -w` stays under 1800. `bun test plugins/soleur/test/components.test.ts` is green.
- [x] `grep -n 'Skill: soleur:linear-fetch' plugins/soleur/skills/one-shot/SKILL.md` returns exactly one line.
- [x] `grep -n 'Skill: soleur:linear-fetch' plugins/soleur/skills/brainstorm/SKILL.md` returns exactly one line.
- [x] `redact-linear-urls.test.sh` passes; all 10 fixtures (raw, markdown, HTML, autolink, URL-encoded, edge characters, multi-URL, zero-URL, trailing `]`, trailing `)`) green.
- [x] `persist-safe-integration.test.sh` passes; the rendered one-shot AND brainstorm template strings contain zero `uploads.linear.app` matches.
- [x] `knowledge-base/project/learnings/best-practices/2026-05-12-task-subagent-prompt-text-only.md` exists and cites the Phase 0 probe result.
- [x] Phase 2.5 telemetry assertion: `grep -rn 'emit_incident' plugins/soleur/skills/linear-fetch/` returns zero matches (no telemetry call sites added). If any match exists, it passes the telemetry wrapper assertion (no Linear identifiers / URLs).
- [x] TR5 explicit: `grep -rnE '/tmp|mkdir|mktemp' plugins/soleur/skills/linear-fetch/scripts/*.sh` returns zero non-test matches (test scripts may use `mktemp` for fixture isolation — verify each match is inside a `.test.sh` file).
- [x] TR6 explicit: `grep -rnE 'LINEAR.*TOKEN|LINEAR_API|LINEAR_TOKEN' plugins/soleur/skills/linear-fetch/` returns zero matches.
- [x] `.github/workflows/<chosen-workflow>.yml` contains the `pii-grep` job; the job runs on `pull_request`; fixture PR with `uploads.linear.app` content fails the job locally (`git diff base..head | grep` returns the line).
- [x] PR body contains a `## Changelog` section, `semver:minor` label applied, and uses `Ref #3635` (not `Closes`).
- [x] CPO sign-off captured (carry-forward from brainstorm Domain Assessment, surfaced in plan Domain Review section): PR comment from the user confirming sign-off, or a brainstorm-domain-config CPO carry-forward note in the PR description.
- [ ] `user-impact-reviewer` fired during `/soleur:review` and did not flag a new user-facing failure mode (`requires_cpo_signoff: true` triggers this).
- [x] No `uploads.linear.app` URL anywhere in the staged diff: `git diff --cached | grep uploads.linear.app | wc -l == 0` at PR finalization.
- [x] Two deferred-capability follow-up issues created (bot-comment filter v1.1; plan/fix-issue extension v2) with correct labels.

### Post-merge (operator)

- [ ] Manual smoke test: run `/soleur:one-shot fix SOL-<real-id>` against a real Linear issue with at least one image; confirm disclosure line fires, image visible in the parent conversation, plan subagent's plan document contains zero Linear CDN URLs.
- [ ] Manual smoke test: run `/soleur:brainstorm` against a text-only Linear issue (`text-only issue, no images.` line fires).
- [ ] Manual smoke test: open a synthetic PR (push a branch via raw `git`) containing a Linear CDN URL (non-fixture) in a staged file. Confirm the `pii-grep` CI job fails the PR with a clear annotation.
- [ ] Manual smoke test: 6-ID input (`SOL-39 SOL-40 SOL-41 SOL-42 SOL-43 SOL-44`) triggers `AskUserQuestion` before any MCP fetch.
- [ ] Close `#3635` with `gh issue close 3635 --comment "Verified post-merge: skill discoverable, image fetch works, redaction confirmed, CI gate active."` once all four smoke tests pass.
- [ ] If any of the four smoke tests fail post-merge: file a P1 follow-up issue, leave `#3635` open, and DO NOT mark the skill as production-ready until the failure is reproduced and fixed.

## Test Strategy

Two automated test files cover the load-bearing rails: `redact-linear-urls.test.sh` (the substitution primitive) and `persist-safe-integration.test.sh` (the caller-template render path). Both use synthesized fixtures per `cq-test-fixtures-synthesized-only` — no real Linear API captures, no real CDN URLs in test data (test fixtures use `https://uploads.linear.app/TEST-FIXTURE-NOT-REAL.png` as a clearly-fake but regex-matching string).

The 10 spec Test Scenarios live as a `## Manual Test Runbook` section inside SKILL.md so reviewers exercise them inline against a real workspace. The runbook is part of the PR body's checklist.

No new test framework. `*.test.sh` matches existing convention in `.claude/hooks/` and `plugins/soleur/test/`.

## Risks

- **R1. Redaction-guard breach via unknown CDN hostname.** If Linear introduces a new CDN domain (`cdn.linear.app`, `linear-assets.com`), the `LINEAR_CDN_PATTERNS` array misses it. **Mitigation:** the array structure is explicitly extensible (one-line add + one fixture). The CI grep job's regex must also be kept in sync — add a Phase 4 SKILL.md note pointing at both update sites.
- **R2. False-positive identifier match.** `PR-123`, `HTTP-200`, `CVE-2024` all match `[A-Z]{2,}-[0-9]+`. **Mitigation:** Phase 2 silently drops 404s — false positives become extra MCP round-trips, not user-visible failures.
- **R3. Context bloat from large issues.** A 10-comment issue with large screenshots may approach the model's context window. **Mitigation:** spec FR4 caps comments at 10 most-recent; deferred v1.1 follow-up issue tracks the `--no-images` escape hatch if usage data shows operators hit the cap.
- **R4. MCP tool unavailable at runtime.** **Mitigation:** Phase 0 schema preflight surfaces the auth-missing message clearly; `preconditions` in SKILL.md frontmatter documents the requirement; FR8 warn-and-continue means the parent skill is not aborted.
- **R5. Comment-ordering nondeterminism.** **Mitigation:** Phase 2 client-side `createdAt desc` sort is the hard fallback regardless of MCP-side ordering support.
- **R6. Cap-policy disagreement at >5 refs.** A user pasting 7 refs may not want the silent-drop-first-5 behavior. **Mitigation:** `AskUserQuestion` at Phase 2 step 1; the user picks. No silent failures of intent.
- **R7. CI grep job placement.** Placing `pii-grep` inside a path-filtered workflow would let docs-only PRs slip through. **Mitigation:** Phase 4 explicitly audits `.github/workflows/` for the highest-coverage `pull_request`-triggered workflow that runs on ALL paths.

## Sharp Edges

- **BSD sed compatibility.** The redaction script uses `sed -E '...'` with a POSIX character class. The chosen class `[^[:space:]<>"\x27)\]]+` must parse identically on both GNU sed (Linux) and BSD sed (macOS). Test on both before declaring Phase 1 done.
- **`jq` dependency.** The Phase 0 exit criteria asserts `command -v jq` succeeds. Several existing `.claude/hooks/` already depend on `jq` so this is not a new dependency, but the absence of `jq` would silently degrade the wrapper that parses the Phase 0 probe response.
- **Subagent prompt substitution count.** Before editing one-shot SKILL.md to substitute `$ARGUMENTS` with `persist_safe_summary`, run `grep -c '\$ARGUMENTS' plugins/soleur/skills/one-shot/SKILL.md` — there should be exactly one occurrence in the subagent prompt template. A global replace would mutate other `$ARGUMENTS` literals if any exist.
- **Phase 0.4 ordering in brainstorm.** Phase 0.4 must complete BEFORE Phase 0.5 spawns leaders; they are sequential even though Phase 0.5 internally parallelizes leaders. The brainstorm SKILL.md edit must say this explicitly so a future plan that introduces another Phase 0.x preflight doesn't accidentally reorder them.
- **CI grep regex must mirror redaction class.** If `LINEAR_CDN_PATTERNS` adds a new hostname, the workflow's grep must be updated in the same PR. Phase 4 documents both update sites; the architecture-strategist at review-time should verify the sync.

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open --json number,title,body --limit 200` and grepped each Files-to-Edit / Files-to-Create path. **None** — no open code-review scope-outs touch this plan's surface.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (CPO).

**Source:** Carried forward from the brainstorm's `## Domain Assessments` section. No new domain leaders spawned at plan time.

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** New skill is the right shape. `extract_images` MCP tool collapses the design — no filesystem cache, no auth handling. Cross-tenant artifact-leak is the highest-likelihood × highest-blast risk; the redaction guard on persisted text is the single load-bearing safety rail. Two-layer defense (in-skill + CI grep) is appropriate for `single-user incident` threshold — disjoint bypass profiles, no shared failure mode.

### Legal (CLO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Five GDPR items (Linear DPA register, sub-processor disclosure, `/soleur:gdpr-gate` on PR, privacy-policy legitimate-interest note, processing-activity entry) scoped out under the redaction-guard condition. **Re-enters scope as PR-blocking if either defense layer fails review.** `user-impact-reviewer` at PR time is the enforcement point.

### Product (CPO)

**Status:** reviewed (brainstorm carry-forward) + CPO sign-off required at plan time per `requires_cpo_signoff: true`
**Assessment:** Scope v1 to one-shot + brainstorm; defer plan + fix-issue to v2. Auto-detect over flag, cap at 10 most-recent comments, warn-and-continue on MCP failure. **No new user-facing UI surface** — operator-facing CLI/skill only. Product/UX Gate tier: **NONE** (no `app/**/page.tsx` or `components/**/*.tsx` files created).
**Sign-off captured:** brainstorm Domain Assessment for Product is the load-bearing CPO sign-off for this PR. The brainstorm's CPO summary (see `knowledge-base/project/brainstorms/2026-05-12-linear-issue-image-context-brainstorm.md` §Domain Assessments → Product) constrained scope to one-shot + brainstorm v1, auto-detect over flag, cap at 10 comments, warn-and-continue on MCP failure — all of which the implementation honors. No additional CPO sign-off PR comment is required; the brainstorm record IS the sign-off per `brand_survival_threshold: single-user incident` carry-forward.
**Brainstorm-recommended specialists:** none.

### Skipped specialists

None — no specialists were recommended by name in the brainstorm.

## GDPR / Compliance Gate

The plan does NOT touch the canonical regulated-data-surface regex (`hr-gdpr-gate-on-regulated-data-surfaces`): no schema changes, no migrations, no `.sql` files, no auth flows, no new API routes. `/soleur:gdpr-gate` is therefore not invoked at plan time. CLO carry-forward from brainstorm covers the data-flow concern; the 5 legal items are scope-out conditional on the redaction-guard holding.

## Hypotheses

Phase 1.4 network-outage trigger keywords (`SSH`, `connection reset`, `firewall`, etc.) — none match this plan. No `## Hypotheses` content required.
