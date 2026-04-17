---
date: 2026-04-17
category: bug-fixes
module: content-publisher, social-distribute, lefthook
problem_type: authoring_publishing_contract
severity: P1
pr_reference: "#2491"
---

# Distribution content Liquid markers leaked to Discord/X/LinkedIn (2026-04-17)

## Problem

The 2026-04-17 launch announcement for the repo-connection feature was posted to Discord (and X, Bluesky, LinkedIn Company) with the blog CTA showing a literal unrendered Liquid template:

```text
Blog post with full details: <{{ site.url }}blog/your-ai-team-works-from-your-actual-codebase/>
```

Instead of:

```text
Blog post with full details: https://soleur.ai/blog/your-ai-team-works-from-your-actual-codebase/
```

The same broken markup appeared in 5 section variants of `knowledge-base/marketing/distribution-content/2026-04-17-repo-connection-launch.md` and was posted verbatim to four third-party APIs on the daily cron run.

## Root Cause

**Authoring-to-publishing contract bug.** Three layers of trust, zero mechanical verification:

1. `soleur:social-distribute` Phase 5 prompts the LLM to substitute `site.url` when assembling each platform variant. The LLM forgot / didn't, and left `{{ site.url }}` in the generated file.
2. The cron-driven `scripts/content-publisher.sh` extracts sections verbatim and pipes them to Discord/X/LinkedIn/Bluesky webhooks. It had no sanity check that content was free of Liquid/Jinja markup.
3. `lefthook` pre-commit had no guard on `knowledge-base/marketing/distribution-content/**/*.md` either, so a manually-authored file with markers would also slip through.

Distribution content files are **NOT** Eleventy templates — they're raw third-party API payloads. There is no `site.url` render step in the pipeline between the file and the Discord webhook. `{{ site.url }}` is only valid in files under `plugins/soleur/docs/**`.

## Solution

**Three-layer defense-in-depth.** Matching the established pattern in `2026-03-27-skill-defense-in-depth-gate-pattern.md`:

1. **Publishing-time gate (hard)** — `scripts/content-publisher.sh` now calls `validate_no_liquid_markers()` per file before channel dispatch. On any match it files a `create_liquid_marker_fallback_issue()` and leaves the file's `status: scheduled` so it retries on the next cron run once fixed. Body-only grep (post-frontmatter) via `awk '/^---$/{c++; next} c==2'`. File-relative line numbers reported via offset computed from second fence.

2. **Pre-commit lint (manual authoring)** — `scripts/lint-distribution-content.sh` wired into `lefthook.yml` with glob `knowledge-base/marketing/distribution-content/*.md` (single-star; content files are flat and gobwas's `**` requires 1+ directory levels per `2026-03-21-lefthook-gobwas-glob-double-star.md`).

3. **Authoring-time gate (skill-level)** — `plugins/soleur/skills/social-distribute/SKILL.md` Phase 5.5 and Phase 9 Step 5 now require the LLM to shell out to `scripts/lint-distribution-content.sh` against a temp-file copy of each variant before presenting to the user and before writing to disk. Explicit "do NOT rely on visual inspection" instruction.

Both validators also strip C0/C1 control bytes and U+2028/U+2029 before echoing matched content (terminal escape injection defense) and redact `(token|secret|key|password|api_key)` patterns before embedding offender lines in a public GitHub issue body.

**Remediation on the archive file:** the posted file was edited in-place to show resolved URLs with per-platform UTM tails per the social-distribute UTM mapping. The live Discord/X/LinkedIn messages were not retroactively edited (deferred — no `DISCORD_BOT_TOKEN` in Doppler; webhook edits require a message ID that `post_discord()` didn't capture because it POSTed without `?wait=true`).

## Key Insight

**Every pipeline seam between "LLM authored" and "third-party posted" must have mechanical validation.** The rule that covers this in general — `wg-when-a-workflow-gap-causes-a-mistake-fix` — was satisfied by fixing three definition files (skill, hook, publisher) in the same PR rather than just writing a learning. "LLM will remember" is not a control.

Additional insight: persisting a **message ID sidecar** at post time (append `?wait=true` to the Discord webhook POST, capture `response.id`, write a `.posted.json` next to the `.md`) converts a future "we need to edit the broken post" incident from a Playwright scrape into a one-line `PATCH /webhooks/{id}/{token}/messages/{id}`. Not in scope for this PR; filed as a follow-up consideration.

## Session Errors

- **Lefthook `--files` (plural) CLI flag** — used `lefthook run pre-commit --files <path>` while verifying the new hook's glob fired. The flag is `--file` (singular, repeatable). Recovery: `lefthook run --help` revealed the correct flag. **Prevention:** Already covered by `hr-when-a-command-exits-non-zero-or-prints` (investigate before proceeding); no new rule needed — the failure was caught and resolved in under a minute.
- **Shell redirect ordering bug in test harness** — wrote `2>&1 >/dev/null` in a bun test body intending to capture stderr only. Redirects are order-sensitive: `2>&1` points stderr to the *current* stdout (original), then `>/dev/null` points stdout to `/dev/null`. Intended capture silently produced no stderr. Recovery: removed the `>/dev/null` and captured `result.stderr` directly. **Prevention:** When capturing stderr-only in a bash snippet under a test runner, prefer `2>&1 | ...` with a single direction, or capture both streams and assert on `decode(result.stderr)` without cross-stream redirection.
- **`sleep 5` in publisher main() blocked integration test** — bun test timed out because `main()` sleeps 5s between files (intentional rate-limit buffer). Recovery: stub `sleep() { :; }` in the test wrapper. **Prevention:** When integration-testing long-loop shell functions, stub `sleep` in the test harness alongside other mocks like `post_discord`. Added to the test file for future iterations.

No workflow changes warranted: all three errors were (a) self-correcting within the session, (b) already covered by existing hard rules, or (c) specific to test-harness ergonomics that don't recur outside this file.

## Cross-references

- `knowledge-base/project/learnings/2026-03-27-skill-defense-in-depth-gate-pattern.md` — the canonical three-layer pattern.
- `knowledge-base/project/learnings/2026-03-21-lefthook-gobwas-glob-double-star.md` — why the glob uses single-`*`.
- `knowledge-base/project/learnings/2026-02-19-discord-bot-identity-and-webhook-behavior.md` — webhook edit semantics (indefinite for content, frozen identity).
- `knowledge-base/project/learnings/2026-03-05-discord-allowed-mentions-for-webhook-sanitization.md` — `allowed_mentions` must be preserved on PATCH edits too.
- PR #2491 — implementation.
