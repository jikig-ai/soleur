# Fix: Discord Blog URL Rendered Liquid Template Instead of Site URL

**Type:** bug
**Severity:** P1 (community-visible broken link in published announcement)
**Created:** 2026-04-17
**Branch:** `feat-fix-discord-blog-url-template`
**Worktree:** `.worktrees/feat-fix-discord-blog-url-template`

## Enhancement Summary

**Deepened on:** 2026-04-17
**Sections enhanced:** Phases 1-6, Test Scenarios, Files Affected, Sharp Edges
**Research inputs used:** institutional learnings (8 applicable), Doppler secret audit, lefthook glob semantics, Discord webhook API (v10), content-publisher code path review, existing test-convention probe

### Key Improvements

1. **Test convention confirmed**: `bats` is NOT installed — use `.test.sh` pattern under `plugins/soleur/test/` with shared `test-helpers.sh`. Plan now prescribes the correct path and file naming (matches learning `2026-04-14-plan-prescribed-test-framework-not-available.md`).
2. **Discord message-edit path hardened**: confirmed no `DISCORD_BOT_TOKEN` exists in any Doppler config. The only credentials are webhook URLs. Webhook POSTs that did not use `?wait=true` return no body (message ID is not stored) — we CANNOT retrieve the already-posted message ID via API. Plan now correctly sequences: (a) future posts MUST use `?wait=true` and persist the message ID, (b) for THIS specific incident, find the ID via Playwright MCP on Discord web (keeps session open per AGENTS.md `hr-when-playwright-mcp-hits-an-auth-wall`).
3. **Lefthook glob semantics corrected**: `gobwas` (Lefthook default) treats `**` as "1+ directories," not "0+". Content files sit flat directly in `distribution-content/` with no subdirectories — the glob MUST be `knowledge-base/marketing/distribution-content/*.md`, NOT `.../**/*.md` (otherwise the hook silently skips everything, per learning `2026-03-21-lefthook-gobwas-glob-double-star.md`).
4. **Lefthook keyword false-positive risk acknowledged**: the existing `pre-merge-rebase.sh` PreToolUse hook broadly matches keyword strings; our new Liquid-marker linter must NOT be enforced via PreToolUse on Bash tool — it must be a standard `lefthook` command running against staged files (per learning `2026-03-19-pre-merge-hook-false-positive-on-string-content.md`).
5. **`allowed_mentions: {parse: []}` must be preserved on edits**: confirmed in learning `2026-03-05-discord-allowed-mentions-for-webhook-sanitization.md` and already present in `post_discord()`. Phase 1.2 MUST include `allowed_mentions` in the PATCH payload too — otherwise an edit could retroactively trigger `@everyone` if the corrected content somehow contained it.
6. **Content-publisher stderr/temp-file hardening already in place**: learning `2026-04-02-content-publisher-stderr-hardening.md` shows `_TMPFILES`/`trap EXIT`/`make_tmp()` exist (lines 45-56 of `content-publisher.sh`). Plan's new validator must use `make_tmp` for any temp files and not introduce new bare `mktemp` calls.
7. **UTM parameter omission is an authoring-bug pattern, not just a markup bug**: learnings `2026-03-11-multi-platform-publisher-error-propagation.md` and `2026-03-14-content-publisher-channel-extension-pattern.md` both call out that authoring skills that skip steps create silent publisher failures. Phase 5.5 validation must catch BOTH Liquid markers AND missing UTMs (the latter via regex: `site\.url.*blog/.*[^&?]$` for links that have no UTM tail — TBD scope per phase 3.1 discussion).
8. **Defense-in-depth is the right model for community-visible pipelines**: matches learning `2026-03-27-skill-defense-in-depth-gate-pattern.md` — authoring gate (Phase 3) + publishing gate (Phase 2) + pre-commit gate (Phase 4) is the canonical three-layer pattern for content that ships to third parties. Do NOT reduce to a single gate.

### New Considerations Discovered

- **Webhook message edit is time-bounded for identity** but NOT for content. Per learning `2026-02-19-discord-bot-identity-and-webhook-behavior.md`, `PATCH /webhooks/{id}/{token}/messages/{msg_id}` works indefinitely for content changes. Identity (username/avatar) is frozen at post time. Phase 1.2 can safely PATCH the content even days after the original post.
- **Post-edit future incidents**: Phase 2 should ALSO modify `post_discord()` to POST with `?wait=true`, capture the response JSON, and persist `message.id` to a sidecar file (e.g., a new frontmatter field `post_message_ids:` or a parallel `.posted.json`) so future corrections do not require Playwright scraping. This is a small addition that pays for itself on the next incident.
- **LinkedIn Company Page edit capability**: per learning `2026-04-09-linkedin-org-access-token-for-company-page-posts.md`, posting requires `LINKEDIN_ORG_ACCESS_TOKEN` (not personal). Edits via `POST /rest/posts/<urn>` with PUT semantics require the same org scope. If the existing token has `w_organization_social` but not `r_organization_social`, we may not be able to read back the post URN to PATCH it — falls back to a correction comment.
- **Bluesky edit is impossible**: AT Protocol does not support post edits. For Bluesky, only delete-and-repost works (which loses engagement metrics). Phase 1.6 should verify the live post text before deciding; if broken, the cost/benefit of delete+repost is likely "accept the minor defect, learn forward."
- **The already-published file status MUST stay `published`**: editing the distribution content file after cron has already consumed it does not re-trigger the publisher (because the status changed from `scheduled` to `published`). Safe to correct the archival copy without risk of duplicate posting.

## Overview

The 2026-04-17 repo-connection launch announcement was posted to Discord (and X, Bluesky, LinkedIn Company) with the blog CTA showing a literal unrendered Liquid template instead of a real URL:

**Posted (broken):**

```text
Blog post with full details: <{{ site.url }}blog/your-ai-team-works-from-your-actual-codebase/>
```

**Expected:**

```text
Blog post with full details: https://soleur.ai/blog/your-ai-team-works-from-your-actual-codebase/
```

### Root cause

`soleur:social-distribute` Phase 3 instructs the LLM to build an article URL from `site.url + path` and Phase 5 says *"Every variant must contain resolved numbers, not template syntax like `{{ stats.agents }}`"*. In this run, the LLM authored content that left `{{ site.url }}` **in the distribution content file itself** (`knowledge-base/marketing/distribution-content/2026-04-17-repo-connection-launch.md`) — 5 occurrences across Discord, X/Twitter, LinkedIn Personal, LinkedIn Company, and Hacker News sections.

The cron-driven publisher (`scripts/content-publisher.sh`) then extracts those sections verbatim and posts them to Discord/X/LinkedIn/Bluesky via webhook/API. There is no intermediate template-rendering pass and no validation that content is free of Liquid/Jinja markup — so "LLM forgot to substitute" becomes "broken link in the community channel."

This is a **content pipeline** bug, not an Eleventy bug. `{{ site.url }}` is valid **only** inside files processed by the Eleventy build (`plugins/soleur/docs/**`). Distribution content files are NOT Eleventy templates — they are raw posts piped to third-party APIs.

### Scope of damage (already posted)

The announcement has already been sent to:

- **Discord #blog** (2026-04-17 cron run) — broken `{{ site.url }}` in message body
- **X/Twitter thread** — final tweet has `<{{ site.url }}blog/...>` (thread is a chain, cannot be edited, can only be deleted or a correction replied)
- **LinkedIn Company Page** — broken URL in body
- **Bluesky** — section uses the bare blog URL without `{{ site.url }}` wrapper (inspection shows Bluesky section already in plain prose, may be unaffected — verify)
- **LinkedIn Personal** and **Hacker News** sections are manual-posting-only per the skill design; check whether they were manually posted before correcting

The file's status is `published` and `pr_reference: "#1257"` — the cron has already run successfully and rewritten `status: scheduled` → `status: published`.

## Research Reconciliation — Spec vs. Codebase

| Spec/Description claim | Codebase reality | Plan response |
|---|---|---|
| "Discord announcement is generated by `soleur:social-distribute`" | Confirmed: `plugins/soleur/skills/social-distribute/SKILL.md` Phase 5.1. LLM authors content at Phase 5; there is no deterministic template substitution. | Fix validation in BOTH the authoring skill (catch at generation time) and the posting pipeline (hard gate — catches stale files too). |
| "The `{{ site.url }}` pattern is an Eleventy/11ty template variable" | Confirmed: `plugins/soleur/docs/_data/site.json` defines `url: "https://soleur.ai"`. Eleventy processes `plugins/soleur/docs/**` only. Distribution content in `knowledge-base/marketing/distribution-content/` is NOT Eleventy-processed. | The fix is not "add template rendering to the pipeline" — it is "reject Liquid markers as a bug." The content file must contain pre-resolved URLs. |
| "CI workflow posts to Discord" | Confirmed: `.github/workflows/scheduled-content-publisher.yml` runs `scripts/content-publisher.sh` on daily 14:00 UTC cron. Discord posting is `post_discord()` in that script (lines 149-185). | Add a validation function in `content-publisher.sh` that runs before extracting sections — fail the file with a fallback issue if any section contains Liquid/Jinja markers. |
| "retro-edit the already-posted Discord message if possible via bot/webhook" | Discord webhook messages CAN be edited via `PATCH /webhooks/{webhook.id}/{webhook.token}/messages/{message.id}` — but only if we captured the message ID. `post_discord()` does NOT capture/store message IDs (the `curl` call discards the response body in favor of the HTTP code). | Two-path remediation: (a) attempt to find the message ID via Discord API `GET /channels/{channel.id}/messages` using a bot token if available, then PATCH; (b) if no message ID path, post a brief correction reply in #blog with the working URL. Both paths are scripted, not manual. |

## Goals

1. **Fix the already-posted Discord message** — ideally via webhook edit (PATCH); fall back to a correction follow-up post.
2. **Correct the archived distribution content file** so future re-reads of `knowledge-base/marketing/distribution-content/2026-04-17-repo-connection-launch.md` show the resolved URL (consistency with reality, not rewriting history).
3. **Add a hard gate in `content-publisher.sh`** that rejects any section containing Liquid/Jinja markers (`{{`, `}}`, `{%`, `%}`) before posting — fallback issue is created, no post goes out.
4. **Add a gate in `social-distribute` skill (Phase 5.5 — new)** that greps the generated content for the same markers and refuses to write the content file if found, forcing the LLM to regenerate with resolved values.
5. **Add a pre-commit lint** (`lefthook` glob `knowledge-base/marketing/distribution-content/**/*.md`) that blocks commits of content files containing Liquid markers — defense in depth for manually-authored files.
6. **Audit remaining distribution content** — one-time sweep for stale `{{`/`}}`/`{%`/`%}` in the other 14 files to prevent repeat incidents when older content is rescheduled.

## Non-Goals

- **Do NOT add a Liquid/Jinja rendering step to the content pipeline.** The content files are raw API payloads, not templates. Resolving `{{ site.url }}` automatically would hide the root-cause bug (LLM failed to resolve during authoring) and create a new class of failures (Liquid syntax errors, undefined variables, etc.).
- Do NOT alter the posting behavior for non-Liquid issues (rate-limit retries, partial-thread fallback, etc.) — out of scope.
- Do NOT delete the already-posted X thread. Thread chain cannot be restructured; a correction reply preserves social proof on the hook tweet.
- Do NOT retro-edit the LinkedIn Company Page post if the LinkedIn API does not support edit-within-window without losing engagement metrics — a correction comment is the path. (Verify during implementation.)

## Implementation Phases

Phases are ordered so that remediation (urgent, community-visible) ships first, then prevention.

### Phase 1 — Remediation of the posted announcement

1.1 **Fix the archived distribution content file.** Hand-edit `knowledge-base/marketing/distribution-content/2026-04-17-repo-connection-launch.md`: replace every `{{ site.url }}` with the resolved `https://soleur.ai/` in the 5 occurrences (Discord, X/Twitter, LinkedIn Personal, LinkedIn Company, Hacker News sections). Keep the UTM suffixes (the current strings do not have them — verify against the UTM table in `social-distribute` SKILL.md Phase 3 and apply `?utm_source=discord&utm_medium=community&utm_campaign=your-ai-team-works-from-your-actual-codebase` etc. to each platform-specific URL).

1.2 **Attempt Discord message edit.** Write a one-shot script `scripts/discord-edit-message.sh` that:

- Loads `DISCORD_BLOG_WEBHOOK_URL` from Doppler (`doppler secrets get DISCORD_BLOG_WEBHOOK_URL -p soleur -c prd --plain`).
- **No `DISCORD_BOT_TOKEN` is available** — verified via `doppler secrets --project soleur --config prd --only-names | grep -i discord`. Available: `DISCORD_OPS_WEBHOOK_URL`, `DISCORD_BLOG_WEBHOOK_URL`, `DISCORD_WEBHOOK_URL`. Without a bot token, the Discord REST API cannot list channel messages (webhooks alone cannot read a channel's message history).
- The only automated path to retrieve the message ID is **Playwright MCP** — navigate to `https://discord.com/channels/<guild-id>/<blog-channel-id>`, wait for auth, scrape the DOM for the Sol bot message matching "Your AI team now operates on your actual codebase" and extract the `data-list-item-id` / `data-message-id` attribute. Per AGENTS.md `[id: hr-when-playwright-mcp-hits-an-auth-wall]`, keep the session open at the login wall and prompt the user to authenticate — do not close the browser and hand off a URL.
- Given the message ID, PATCH the content: `PATCH https://discord.com/api/webhooks/{webhook.id}/{webhook.token}/messages/{message.id}` with JSON body `{"content": "<fixed content>", "allowed_mentions": {"parse": []}}`. The `allowed_mentions` field is MANDATORY on edits too — per learning `2026-03-05-discord-allowed-mentions-for-webhook-sanitization.md`, Discord re-parses mentions on PATCH, not just POST. Omitting it could retroactively ping @everyone if the corrected content contained such syntax (it doesn't in this case, but defense in depth).
- If the PATCH succeeds (HTTP 200), print `[ok] Discord message edited`.
- If the PATCH fails (404 = message too old or not owned by this webhook, 403 = webhook lacks permission, 429 = rate limit), fall back to Phase 1.3.

### Research Insights (Phase 1.2)

**Discord webhook API behavior:**

- `POST /webhooks/{id}/{token}` with NO `?wait=true` query param returns HTTP 204 with an empty body. Our current `post_discord()` in `content-publisher.sh` does NOT use `?wait=true` (line 169-172 — just captures the status code). **This is why we have no message ID for the 2026-04-17 post** — it was discarded at post time.
- `POST /webhooks/{id}/{token}?wait=true` returns HTTP 200 with the full message JSON including `id`. Phase 2 MUST change `post_discord()` to use `?wait=true` and persist the returned message ID alongside the content file. Sidecar format: write `.posted.json` next to the `.md` file with `{"discord": {"message_id": "...", "posted_at": "..."}}`.
- `PATCH /webhooks/{id}/{token}/messages/{message.id}` works indefinitely for content. Identity (username/avatar) is frozen at original post time. Preservation confirmed in learning `2026-02-19-discord-bot-identity-and-webhook-behavior.md`.
- **Rate limit:** Discord webhooks are limited to 30 requests per 60 seconds per channel; a single PATCH is well under. The `post_discord_warning` call on stale content (content-publisher.sh:580) shares the same bucket — avoid back-to-back corrections in rapid succession.
- **Content length:** Edits are subject to the same 2000-char limit. The corrected content must fit. Original message was ~1100 chars; adding a UTM suffix (~60 chars) stays well under.

**Playwright MCP for Discord scraping:**

- The MCP `mcp__playwright__browser_navigate` works but Discord detects headless signatures on some paths. Using `--isolated` mode (per AGENTS.md `[id: cq-playwright-mcp-uses-isolated-mode-mcp]`) should bypass.
- DOM selectors: message list items have `data-list-item-id` like `chat-messages___<message-id>` — parse with a regex after locating by text content.
- Before calling `browser_close`, confirm the message ID was captured. Per `[id: cq-after-completing-a-playwright-task-call]`, close the session after extraction.

**References:**

- Discord Developer Docs — Execute Webhook: <https://discord.com/developers/docs/resources/webhook#execute-webhook>
- Discord Developer Docs — Edit Webhook Message: <https://discord.com/developers/docs/resources/webhook#edit-webhook-message>

1.3 **Fallback: post a brief correction.** If edit is not possible, post a short correction message via the same webhook:

```text
Small correction — the blog link in the prior message rendered as template syntax. Fixed link: https://soleur.ai/blog/your-ai-team-works-from-your-actual-codebase/?utm_source=discord&utm_medium=community&utm_campaign=your-ai-team-works-from-your-actual-codebase
```

1.4 **X/Twitter correction.** Reply to the last tweet in the 2026-04-17 thread (the one containing the broken URL) with a correction reply. Use the existing `plugins/soleur/skills/community/scripts/x-community.sh post-tweet --reply-to <thread-tail-id>` interface. Find the tail ID by reading the scheduled-content-publisher CI run logs from 2026-04-17 (workflow_run API); the log prints `[ok] Tweet N/M posted: https://x.com/soleur_ai/status/<id>` for each tweet. Pick the last one.

1.5 **LinkedIn Company Page correction.** Invoke `plugins/soleur/skills/community/scripts/linkedin-community.sh` to either (a) delete + repost if within the edit window, or (b) post a short comment with the fixed URL. The skill may not currently expose edit/comment — if not, add a `post-comment` sub-command as part of this phase (small, scoped addition).

1.6 **Bluesky inspection.** Verify Bluesky post does NOT contain `{{ site.url }}`. If it does, delete via AT Protocol `com.atproto.repo.deleteRecord` and repost. Inspection of the archived file shows the Bluesky section uses plain prose without the blog URL — likely unaffected — but verify the live post.

### Phase 2 — Hard gate in content-publisher.sh (prevents future posts)

2.1 **Add `validate_no_liquid_markers()` helper** in `scripts/content-publisher.sh` after `parse_frontmatter()`. Signature: accepts a file path, greps for `{{`, `}}`, `{%`, `%}` across the extracted content sections (not frontmatter — frontmatter may legitimately contain URL paths). Returns 0 if clean, 1 if any marker is found; when non-zero, prints the first 3 offending lines with context to stderr.

2.2 **Call the validator in the main publish loop** before the `channel_to_section` dispatch (around line 605 of current `content-publisher.sh`): if validation fails for this file, create a `create_liquid_marker_fallback_issue()` (new helper), skip all channels for this file, treat as `file_failures++`. This gate intentionally refuses to post even if only one section is affected — all-or-nothing is safer than partial posts that the community has to reconcile.

2.3 **Add a test fixture** `scripts/test/fixtures/content-publisher/liquid-markers.md` with a sample containing `{{ site.url }}` and a sibling "clean" fixture, and a new `scripts/test/content-publisher.test.sh` (bats-style or plain bash asserts, following the repo's existing convention — check whether `bats` is installed first; if not, use the `.test.sh` pattern used by other scripts/test/*.sh). Tests: (a) clean file passes validator; (b) dirty file triggers validator; (c) dirty file creates fallback issue and does NOT call `post_discord`.

2.4 **Add the fallback issue creator**: `create_liquid_marker_fallback_issue()` follows the pattern of `create_discord_fallback_issue()`. Title: `[Content Publisher] Unrendered Liquid markers in <slug> — post blocked`. Body: lists offending lines with file path and line numbers, suggests fix (resolve templates in the authoring skill output), labels `action-required,content-publisher`. Milestone: default `Post-MVP / Later`.

2.5 **Add `?wait=true` and persist message IDs in `post_discord()`**. Change the `curl` invocation to append `?wait=true` to the webhook URL, capture the JSON response body, extract `message.id` via `jq -r .id`, and write a sidecar file `<content-file>.posted.json` with `{"discord": {"message_id": "<id>", "posted_at": "<ISO8601>"}}`. If the sidecar exists, append (merge) rather than overwrite — the file may already have `x`, `linkedin`, etc. IDs from other publishers. This unlocks future corrections without Playwright scraping. **Cost:** ~12 lines of bash + a `jq` merge. **Benefit:** next Liquid-marker incident (or any content fix) is a one-line API call.

### Research Insights (Phase 2)

**Content-publisher existing patterns (must match):**

- Per learning `2026-04-02-content-publisher-stderr-hardening.md`, the script uses `_TMPFILES` array + `trap EXIT` + `make_tmp()` helper. New temp files in the validator MUST use `make_tmp` — no bare `mktemp`.
- Per learning `2026-03-26-truncate-api-error-responses-in-bash-scripts.md`, any stderr content embedded in fallback issues must be truncated (e.g., `head -c 1000` or `${var:0:1000}`) to avoid oversize issue bodies.
- Per learning `2026-03-20-stale-content-publisher-duplicate-warnings.md`, the stale-content branch already marks files `status: stale` to prevent duplicate warnings — the new Liquid-marker branch should similarly mark the offending file (e.g., `status: blocked-liquid-markers`) so subsequent cron runs do not spam fallback issues. Alternatively, `create_dedup_issue()` already deduplicates by title — verify the dedup title includes the slug so repeated scans produce one issue, not N.

**Awk/sed gotchas for frontmatter scoping:**

- Per learning `2026-03-05-awk-scoping-yaml-frontmatter-shell.md`, the canonical pattern is `awk '/^---$/{c++; next} c==1'` for frontmatter and `awk '/^---$/{c++; next} c==2'` for body. Use the body-only pattern in `validate_no_liquid_markers()` to avoid false positives on frontmatter URLs (already accounted for in the plan — this insight confirms the approach).
- Per learning `2026-03-31-awk-split-defaults-to-fs-not-whitespace.md`, if regex matching is used, anchor on literal `{{` with `index()` or `~/\\{\\{/` — do NOT use `split` for detection.

**Test dependency guard:**

- Per learning `2026-03-20-test-dependency-guard-pattern.md`, `scripts/test-all.sh` should gate-call the new `content-publisher.test.sh` only if `jq` is available (the validator also needs `jq`). `test-all.sh` already loops over `plugins/soleur/test/*.test.sh` — adding a file there wires it automatically.

**References:**

- Existing pattern in `content-publisher.sh` lines 501-523 (`create_dedup_issue`) — reuse, do not duplicate.
- jq merge pattern for sidecar: `jq -n --slurpfile a file1 --slurpfile b file2 '$a[0] * $b[0]'` or `jq --argjson new "$NEW" '. + $new' existing.json`.

### Phase 3 — Gate in social-distribute skill (catches at authoring time)

3.1 **Amend `plugins/soleur/skills/social-distribute/SKILL.md`** with a new Phase 5.5 between Phase 5 (Generate All Variants) and Phase 6 (Present All Variants):

```markdown
### Phase 5.5: Marker Validation

Before presenting variants (Phase 6), scan ALL generated sections for unresolved Liquid/Jinja markers:

- `{{`, `}}`, `{%`, `%}`

If any marker is found, do NOT proceed to Phase 6. Instead:

1. Print the offending section name and the offending substring.
2. Regenerate that section with explicit substitution of `site.url` (from `plugins/soleur/docs/_data/site.json`) and any `{{ stats.* }}` placeholders using the values from Phase 2.
3. Re-run marker validation. If it still fails after one regeneration, STOP and surface to the user: "Auto-regeneration did not resolve Liquid markers — manual intervention required." This prevents infinite loops.

The validation is mechanical — the LLM may not shortcut it. Template markers in distribution content files are always a bug: Eleventy is not in the pipeline between the content file and the Discord webhook.
```

3.2 **Amend SKILL.md Phase 9 Step 4** ("Write the content file") with a pre-write assertion: run the same marker scan on the fully-assembled file content one final time before writing to disk. Belt-and-suspenders — catches case where Phase 5.5 was somehow bypassed.

3.3 **Document in SKILL.md Important Guidelines** the rationale: "Distribution content files are raw API payloads (Discord webhook content field, X tweet text, LinkedIn share text), NOT Eleventy templates. Liquid/Jinja markers in these files will be posted verbatim to third parties — a `{{ site.url }}` becomes a literal `{{ site.url }}` in the Discord message."

### Research Insights (Phase 3)

**Skill defense-in-depth gate pattern:**

- Per learning `2026-03-27-skill-defense-in-depth-gate-pattern.md`, the established pattern for output-critical skills is: (a) inline validation before presentation, (b) re-validation at file-write, (c) pipeline-stage validation at the consumer. This plan implements all three (Phases 3.1, 3.2, 2.1).
- Per learning `2026-03-16-linearize-multi-step-llm-prompts.md`, a single re-generation attempt (not a loop) is the correct balance. Phase 3.1 caps at one regeneration then escalates to the user — this prevents LLM-cost blow-up on pathological cases.

**Template substitution — LLM vs deterministic:**

- The skill currently relies on the LLM to substitute `{{ site.url }}`. A stronger design (scope-out for this plan, but file as follow-up issue) is DETERMINISTIC substitution: read `plugins/soleur/docs/_data/site.json` in Phase 2 (already being read for stats), pass the resolved URL as an explicit prompt variable, and instruct the LLM to use that string literal. This eliminates the class of bug entirely. Tracked issue: file post-merge with milestone "Post-MVP / Later", title "Deterministic URL substitution in social-distribute Phase 5".
- Per learning `2026-03-12-llm-as-script-pattern-for-ci-file-generation.md`, LLM-authored files in CI pipelines need mechanical post-conditions, not just prompt instructions. Phase 3.1 IS that mechanical post-condition.

**References:**

- `plugins/soleur/skills/social-distribute/SKILL.md` Phase 3 (article URL construction — the LLM already has `site.url` in context, it just failed to substitute)
- `plugins/soleur/docs/_data/site.json` — source of truth for `site.url` (`https://soleur.ai`)

### Phase 4 — Pre-commit lint (defense in depth)

4.1 **Add a `lefthook` pre-commit command** in `lefthook.yml`. CRITICAL: use a single `*` (not `**`) because the distribution content files are flat — no subdirectories. Per learning `2026-03-21-lefthook-gobwas-glob-double-star.md`, gobwas (Lefthook's default glob matcher) requires `**` to match 1+ directory levels, meaning `distribution-content/**/*.md` silently skips every file when they're flat. Verified the layout: `ls knowledge-base/marketing/distribution-content/` shows 15 flat `.md` files, no subdirectories.

```yaml
distribution-content-liquid-guard:
  priority: 11
  glob: "knowledge-base/marketing/distribution-content/*.md"
  run: bash scripts/lint-distribution-content.sh {staged_files}
```

If the directory ever adds subdirectories, update to the array form: `glob: ["knowledge-base/marketing/distribution-content/*.md", "knowledge-base/marketing/distribution-content/**/*.md"]` (Lefthook 1.10.10+).

4.2 **Create `scripts/lint-distribution-content.sh`** that:

- Accepts one or more file paths as args.
- For each file, reads everything between the frontmatter fences (skip the fences themselves). Use the canonical awk pattern from `content-publisher.sh`: `awk '/^---$/{c++; next} c==2' "$file"` selects body only.
- If content contains `{{`, `}}`, `{%`, or `%}`, print `<path>:<line>: unrendered Liquid marker: <matching line>` and exit 1 at the end.
- Frontmatter fields like `blog_url: "/blog/slug/"` are NOT Liquid and must NOT match — scope the grep to the body section only (lines after the second `---`).
- Use `grep -nE` with a pattern anchored on literal `{{|}}|{%|%}` (escape the braces per `grep -E`) — do NOT use `awk` split, per learning `2026-03-31-awk-split-defaults-to-fs-not-whitespace.md`.
- Exit codes: 0 = clean, 1 = found markers. NOT 2+ — lefthook treats any nonzero as failure, but tests assert 1 specifically.

4.3 **Test the hook glob immediately after editing `lefthook.yml`**: run `lefthook run pre-commit --files knowledge-base/marketing/distribution-content/2026-04-17-repo-connection-launch.md` and verify the hook fires. Per learning `2026-03-21-lefthook-gobwas-glob-double-star.md`, silent "skip: no files for inspection" means the glob didn't match — catch it here, not in a PR review round-trip.

4.4 **Validate against the existing corpus**: run the new lint against all 15 files in `knowledge-base/marketing/distribution-content/` before landing the hook — any pre-existing offenders must be fixed in Phase 5 (Audit).

### Research Insights (Phase 4)

**Lefthook gotchas (from institutional learnings):**

- `2026-03-21-lefthook-gobwas-glob-double-star.md`: `**` ≠ `*` in gobwas. Always test the glob with a realistic file path BEFORE shipping the hook.
- `2026-03-19-pre-merge-hook-false-positive-on-string-content.md`: PreToolUse hooks that do keyword matching on Bash command content produce false positives. Our linter is a pre-commit hook on FILES, not a PreToolUse hook — no risk of the same pattern. But be aware: if a linter's error message gets echoed inside a subsequent `git commit -m "..."` as a string containing `{{`, a naïve implementation could loop. The linter must only scan file contents, never commit messages.

**Grep pattern robustness:**

- Literal braces in `grep -E`: `{{|}}` requires escaping — use `grep -nE '\{\{|\}\}|\{%|%\}'` or the simpler `grep -nF` with multiple `-e` args: `grep -nF -e '{{' -e '}}' -e '{%' -e '%}'`. The `-F` form is safer (fixed strings, no regex surprises).
- `grep` exits 1 if nothing matches, 0 if matches found — invert in the script: a match means FAIL, no match means PASS. Wrap with `if grep ... ; then exit 1; else exit 0; fi`.

**References:**

- `lefthook.yml` (existing commands for pattern — see `markdown-lint`, `kb-structure-guard`, `plugin-component-test`)
- `scripts/lint-rule-ids.py` — existing per-file linter in the repo; mirror its CLI contract (multiple paths as positional args, exit 1 on any failure).

### Phase 5 — One-time audit of remaining distribution content

5.1 **Run** `bash scripts/lint-distribution-content.sh knowledge-base/marketing/distribution-content/*.md` locally (once the script is in place). Anything that fails is a latent bug — either it was posted with broken URLs and nobody noticed (check `status: published` files for Discord links) or it is still `draft`/`scheduled` and will break on the next cron run.

5.2 **For each failure:**

- If `status: published`: fix the file, decide whether remediation (a correction post) is warranted based on visibility. Add a note in the plan outcome if any other file had been posted broken.
- If `status: draft` or `status: scheduled`: fix the file in place.
- If `status: stale`: fix the file and leave it stale (not rescheduled unless the user wants it).

5.3 **Commit all audit fixes in one commit** with message `fix(distribution-content): resolve unrendered Liquid markers in <N> files`.

### Phase 6 — Close the loop

6.1 **Open a GitHub issue** if the audit in Phase 5 finds additional posted-broken files, tracking correction posts or decisions to leave them.

6.2 **Add a learning file** `knowledge-base/project/learnings/bug-fixes/2026-04-17-distribution-content-liquid-marker-leak.md` via `/soleur:compound`. Pattern: "Mechanical validation at every pipeline seam, not just authoring." This is a classic authoring-vs-publishing contract bug — the publisher trusts the author, and the author trusts the LLM.

## Acceptance Criteria

- [ ] The live Discord #blog message from 2026-04-17 is either edited to show the resolved URL (preferred) OR a correction reply is posted immediately after, linking to the blog post.
- [ ] The X/Twitter thread has a correction reply appended with the resolved URL.
- [ ] The LinkedIn Company Page post has a correction comment OR the post itself is edited, depending on API capability.
- [ ] `knowledge-base/marketing/distribution-content/2026-04-17-repo-connection-launch.md` contains zero `{{`/`}}`/`{%`/`%}` markers in its body sections. UTM-tracked URLs are present on platform-specific sections per the social-distribute skill UTM mapping.
- [ ] `scripts/content-publisher.sh` refuses to post any file containing Liquid markers and creates a fallback issue instead. Verified by unit test `scripts/test/content-publisher.test.sh`.
- [ ] `plugins/soleur/skills/social-distribute/SKILL.md` has Phase 5.5 marker validation and a final-write assertion in Phase 9 Step 4.
- [ ] `lefthook.yml` has a `distribution-content-liquid-guard` pre-commit command that blocks commits of content files containing Liquid markers. Verified by committing a test file with `{{ site.url }}` → commit is refused.
- [ ] `scripts/lint-distribution-content.sh` exists, is executable, and has at least one test case.
- [ ] One-time audit of all 15 existing distribution-content files is green under the new linter.
- [ ] Learning file committed.

## Test Scenarios

### T1 — content-publisher.sh rejects Liquid markers (RED first)

Given a fixture file `liquid-markers.md` in `plugins/soleur/test/fixtures/content-publisher/` with frontmatter `status: scheduled`, `publish_date: <today>`, `channels: discord` and a `## Discord` section containing `Blog post: <{{ site.url }}blog/test/>`,
When the new test `plugins/soleur/test/content-publisher.test.sh` sources `content-publisher.sh` (guarded by `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` — line 689), mocks `post_discord` with a recording shim, and invokes the validator,
Then `validate_no_liquid_markers` MUST return 1 AND the recorded invocation list MUST NOT contain `post_discord` AND the fallback issue creator MUST be invoked once.

**Convention:** Use `plugins/soleur/test/*.test.sh` (not `scripts/test/*.bats`) — confirmed via `command -v bats` (not installed) and `ls plugins/soleur/test/*.test.sh` (existing convention). Shared helpers at `plugins/soleur/test/test-helpers.sh`. Auto-wired into `scripts/test-all.sh`. Per learning `2026-04-14-plan-prescribed-test-framework-not-available.md`.

### T2 — content-publisher.sh passes clean file

Given a fixture `clean.md` with the same frontmatter and a `## Discord` section `Blog: https://soleur.ai/blog/clean/?utm_source=discord`,
When the same invocation runs,
Then the script MUST call `post_discord()` (or whichever channel was declared) AND MUST NOT call `create_liquid_marker_fallback_issue()`.

### T3 — lint-distribution-content.sh blocks Liquid markers

Given a staged file `knowledge-base/marketing/distribution-content/test-liquid.md` with `## Discord\n\nBlog: <{{ site.url }}blog/x/>`,
When `bash scripts/lint-distribution-content.sh <that file>` is run,
Then exit code MUST be 1 AND stderr MUST contain the file path and the offending line.

### T4 — lint-distribution-content.sh allows frontmatter URL paths

Given a file with frontmatter `blog_url: "/blog/x/"` and body `## Discord\n\nPlain prose, no URL`,
When the linter runs,
Then exit code MUST be 0 (frontmatter `blog_url` is a relative path, not a Liquid marker, and the linter must scope to body only).

### T5 — social-distribute skill Phase 5.5 (manual verification)

Given a manually-staged generation where the LLM produced a Discord variant containing `{{ site.url }}blog/foo/`,
When Phase 5.5 runs,
Then the skill MUST regenerate the offending section with a resolved URL AND MUST re-run validation before presenting variants. This is a prompt-level assertion verified by running `/soleur:social-distribute` against a crafted blog post and inspecting the generated content file.

### T6 — Discord edit end-to-end

Given the live #blog message from 2026-04-17 and the bot has message edit permission,
When `scripts/discord-edit-message.sh <message-id>` is run,
Then the message content MUST be replaced with the fixed content AND the Discord API MUST return 200 OK.

### T7 — Audit pass

Given all 15 distribution content files as they currently exist,
When the linter runs against all of them,
Then it MUST report zero failures after Phase 5 audit edits.

## Domain Review

**Domains relevant:** Marketing (CMO), Engineering (CTO)

### Marketing (CMO)

**Status:** reviewed (plan-author assessment in pipeline mode)
**Assessment:** This is a visible-to-community defect in a launch announcement. The CMO's relevant concerns: (a) how quickly the correction reaches the same audience; (b) whether the correction preserves the value of the announcement or reads as noise. Recommendation: prefer in-place edit over a follow-up post wherever technically possible (Discord webhook edit, LinkedIn edit-window). For X/Twitter where the thread is immutable, a single concise correction reply is the minimum intrusion. Do NOT repost the full announcement — that signals greater disruption than the actual bug.

### Engineering (CTO)

**Status:** reviewed (plan-author assessment)
**Assessment:** Classic pipeline-seam bug. The fix belongs at the seam — validation in `content-publisher.sh` is the hard gate (belts), validation in the authoring skill is suspenders, the pre-commit lint is defense in depth against manually-authored files. Resist the temptation to add Liquid rendering to the pipeline — it would hide future authoring bugs. Cost is ~50 lines of shell and a new lefthook entry; no architectural change.

### Product/UX Gate

**Tier:** NONE — no user-facing UI changes. Changes are: shell scripts, a skill instruction file, a lefthook entry, and a content file edit.

## Files Affected

### New files

- `scripts/lint-distribution-content.sh` — pre-commit + manual linter
- `scripts/discord-edit-message.sh` — one-shot remediation script (keep in repo for future incidents)
- `plugins/soleur/test/content-publisher.test.sh` — publisher unit tests (CONFIRMED convention: `.test.sh` via shared `test-helpers.sh`, per learning `2026-04-14-plan-prescribed-test-framework-not-available.md` — bats not installed)
- `plugins/soleur/test/lint-distribution-content.test.sh` — linter unit tests (same convention)
- `plugins/soleur/test/fixtures/content-publisher/liquid-markers.md` — dirty fixture
- `plugins/soleur/test/fixtures/content-publisher/clean.md` — clean fixture
- `knowledge-base/project/learnings/bug-fixes/2026-04-17-distribution-content-liquid-marker-leak.md` — learning (Phase 6)

### Modified files

- `knowledge-base/marketing/distribution-content/2026-04-17-repo-connection-launch.md` — resolve 5 Liquid markers, add UTM parameters where the skill's UTM table prescribes them
- `knowledge-base/marketing/distribution-content/*.md` — any additional files flagged by Phase 5 audit
- `scripts/content-publisher.sh` — add `validate_no_liquid_markers()`, `create_liquid_marker_fallback_issue()`, invoke validator in main loop
- `plugins/soleur/skills/social-distribute/SKILL.md` — add Phase 5.5 and Phase 9 assertion, update Important Guidelines
- `lefthook.yml` — add `distribution-content-liquid-guard` pre-commit command
- `plugins/soleur/skills/community/scripts/linkedin-community.sh` — add `post-comment` sub-command IF needed for Phase 1.5 (verify LinkedIn API capability first)

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| Add Liquid rendering step to `content-publisher.sh` (e.g., `sed 's|{{ site.url }}|https://soleur.ai|g'` or a minimal template engine) | Fixes the symptom for this specific variable | Hides the root cause (LLM authored broken content). New failure modes (undefined variables, escaping bugs). Doesn't cover `{% %}` tag forms. Encourages broken authoring. | Rejected. |
| Only fix at authoring time (social-distribute skill), skip publisher gate | Smaller change | Doesn't cover manually-authored content files. Doesn't cover files authored before the fix shipped. No defense for cron-time regressions if the skill changes. | Rejected — belts AND suspenders is the right model for a published-to-community pipeline. |
| Only add pre-commit lint, skip runtime gate | Simpler | Doesn't catch files authored via bot workflows (GitHub Actions may skip local hooks), doesn't catch LLM-generated files that bypass pre-commit (some flows write direct). | Rejected — the publisher is the last line of defense and MUST validate. |
| Delete the Discord message and repost | Clean final state | Loses engagement (reactions, replies). Repost has a different message ID, breaks any external references. | Rejected — prefer edit, fall back to reply. |
| Repost the entire announcement on X as a new thread | Canonical correction | Looks worse than a brief reply. Doubles the timeline noise. | Rejected — single correction reply. |

## Sharp Edges and Gotchas

- **Do not grep frontmatter for Liquid markers.** The frontmatter may contain `blog_url: "/blog/slug/"` which is a legitimate relative path, and future frontmatter keys may legitimately contain braces (e.g., a JSON-encoded value). Scope the grep to **content body only** — the bytes after the second `---` line.
- **The `jq -n --arg content` payload build in `post_discord()` already JSON-escapes braces correctly.** The bug is not in Discord's rendering — it is in the source content. Discord faithfully rendered the literal string `{{ site.url }}`. Nothing about the webhook payload needs to change.
- **X thread reply ID retrieval.** The GH Actions workflow run log from 2026-04-17 is the source of truth for the last tweet ID. Use `gh run view <run-id> --log` and grep for `Tweet N/N posted`. Do NOT attempt to use the X API to search for the thread by content — X's search index may not have it yet or may not surface it cleanly.
- **LinkedIn edit window.** LinkedIn allows post editing for a short period after posting. If the 2026-04-17 post is outside the window, `post-comment` is the only option. Check the LinkedIn REST API before assuming edit works.
- **Discord webhook `MESSAGES_HISTORY` permission.** Even with the webhook token, the webhook may not have permission to list channel messages. The reliable path to finding the message ID is via the Discord client with developer mode enabled (right-click → Copy Message ID). Use Playwright MCP to navigate Discord web and scrape the DOM, per `hr-when-playwright-mcp-hits-an-auth-wall` if auth is required keep the session open.
- **Bluesky URL verification.** The live Bluesky post may differ from the file content if the content file was edited post-publish. Fetch the live AT Protocol record via `com.atproto.repo.listRecords` to confirm.
- **UTM parameters were ALSO dropped.** The skill's Phase 3 specifies UTM tracking URLs per platform. The current content file has bare `{{ site.url }}blog/slug/` — no UTMs. Phase 1.1 must add UTMs, not just resolve the template. This is a secondary fix for the same incident.
- **The skill currently relies on the LLM to substitute templates.** The new Phase 5.5 marker validation is necessary but not sufficient — consider whether a future improvement (out of scope here, file as issue) should have the skill DETERMINISTICALLY substitute `site.url` by reading `plugins/soleur/docs/_data/site.json` and injecting the resolved URL into the prompt context with explicit "use this value, not `{{ site.url }}`" instruction.

## Rollout and Verification

1. Implement phases in order 1 → 2 → 3 → 4 → 5 → 6.
2. Phase 1 (remediation) SHOULD ship as a separate commit/PR from Phases 2-6 (prevention) — urgency differs. Acceptable to bundle if review is fast.
3. After Phase 2 ships, verify in CI by triggering `scheduled-content-publisher.yml` manually (`gh workflow run scheduled-content-publisher.yml`) against a dry run — may require a `--dry-run` flag addition or a test fixture directory.
4. After Phase 4 ships, verify the pre-commit hook by staging a dirty file locally and attempting to commit → expect rejection.
5. After Phase 5 completes, run `gh workflow run scheduled-content-publisher.yml` once against main (no scheduled content for today → expect no-op) to confirm the new validator does not break clean runs.

## Open Questions (resolved during deepen)

- ~~Does the LinkedIn API (via `linkedin-community.sh`) support editing an existing post or commenting on one?~~ **Partially resolved:** the existing `linkedin-community.sh` only exposes `post-content` (no edit/comment sub-command). Adding `post-comment` is a Phase 1.5 sub-task if/when LinkedIn API supports it. Per learning `2026-04-09-linkedin-org-access-token-for-company-page-posts.md`, company-page operations require `LINKEDIN_ORG_ACCESS_TOKEN` with `w_organization_social` scope — verify the token has this scope before Phase 1.5. Fallback: accept the minor defect on LinkedIn (the broken URL is visible but the intent is clear).
- ~~Does the repo use `bats` or `.test.sh`?~~ **Resolved: `.test.sh`**. `bats` is not installed (`command -v bats; echo $?` returns 1). Existing convention: `plugins/soleur/test/*.test.sh` + shared `test-helpers.sh`, auto-discovered by `scripts/test-all.sh`.
- ~~Is there a `DISCORD_BOT_TOKEN` in Doppler?~~ **Resolved: NO.** Only `DISCORD_OPS_WEBHOOK_URL`, `DISCORD_BLOG_WEBHOOK_URL`, `DISCORD_WEBHOOK_URL` exist. Phase 1.2 must use Playwright MCP for message ID extraction. Phase 2.5 adds `?wait=true` to future posts so this is a one-time Playwright step.

## Remaining Open Questions

- Will the 2026-04-17 Discord message still be editable by the time this plan lands? Discord does NOT impose a time limit on webhook message edits (confirmed via API docs), but the message must still exist in the channel (not deleted by a moderator). Verify during Phase 1.2 by first fetching the message, not just assuming it's there.
- Are the X thread tweets still visible? If the thread was deleted (accidentally or intentionally), the correction reply has no anchor. Verify before Phase 1.4.

## References

- `plugins/soleur/skills/social-distribute/SKILL.md` — authoring skill (Phases 3, 5, 9)
- `scripts/content-publisher.sh` — runtime publisher (lines 149-185 for Discord, 58-69 for frontmatter parsing, 90-120 for section extraction)
- `.github/workflows/scheduled-content-publisher.yml` — daily cron wiring
- `knowledge-base/marketing/distribution-content/2026-04-17-repo-connection-launch.md` — the broken content file
- `plugins/soleur/docs/_data/site.json` — `site.url` source of truth (`https://soleur.ai`)
- `lefthook.yml` — pre-commit hook registry
- AGENTS.md rule `[id: cq-silent-fallback-must-mirror-to-sentry]` — if the new fallback issue creator for Liquid markers ever catches an issue, consider also mirroring to Sentry since content publishers run in CI (pino → Sentry not applicable for bash scripts; Sentry CLI is optional)
