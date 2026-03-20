---
title: "feat: Discord channel reorganization -- releases and blog channels"
type: feat
date: 2026-03-12
semver: patch
---

# feat: Discord channel reorganization -- releases and blog channels

## Enhancement Summary

**Deepened on:** 2026-03-12
**Sections enhanced:** 5
**Research sources:** 7 institutional learnings, codebase analysis (6 workflows, 3 scripts, 2 skills, 1 test file)

### Key Improvements
1. Concrete implementation snippets for every file change -- copy-paste ready
2. Identified that the workflow fallback must resolve the URL in the step script (not in env block) per the CI secrets learning
3. Added the `discord-setup.sh write-env` cleanup regex for the new variable names
4. Clarified that the `post_discord()` function in `content-publisher.sh` needs a parameter or resolved variable -- not a global change to `DISCORD_WEBHOOK_URL`

### New Considerations Discovered
- The `scheduled-content-publisher.yml` failure notification step should keep using `DISCORD_WEBHOOK_URL` (not the blog webhook) -- failure alerts are operational, not content
- The `discord-setup.sh write-env` function already uses `grep -v` to strip existing vars; the new vars need the same treatment

## Overview

Reorganize Discord channel structure by introducing two new channels and routing content to them:

1. **#releases** -- Dedicated channel for version release announcements (currently posted to #announcements)
2. **#blog** -- Dedicated channel for blog post distribution content (currently posted to the general webhook channel)

This requires new Discord webhooks per channel, new GitHub Actions secrets, and updating all workflows and scripts that post to Discord.

## Problem Statement / Motivation

Currently, all automated Discord content flows through a single `DISCORD_WEBHOOK_URL` secret that targets one channel (likely #announcements or #general). This creates two problems:

1. **Signal-to-noise** -- Release notifications, blog posts, case study content, failure alerts, and community digests all land in the same channel. Users who care about releases but not blog posts cannot selectively follow.
2. **Channel purpose clarity** -- Discord best practice is to give channels clear, single purposes. Mixing content types makes channels harder to scan and reduces engagement.

The user wants:
- **#releases** for version release announcements (currently in the `version-bump-and-release.yml` workflow's "Post to Discord" step)
- **#blog** for blog post distribution (currently in the `content-publisher.sh` Discord posting and the `social-distribute` skill)

## Proposed Solution

### New Secrets

Add two new GitHub repository secrets:

| Secret | Target Channel | Used By |
|--------|---------------|---------|
| `DISCORD_RELEASES_WEBHOOK_URL` | #releases | `version-bump-and-release.yml` |
| `DISCORD_BLOG_WEBHOOK_URL` | #blog | `content-publisher.sh`, `social-distribute` skill |

The existing `DISCORD_WEBHOOK_URL` remains as the **default/general** webhook for:
- CI failure notifications (all workflows)
- Community digest posting
- Bot-fix monitor notifications
- `discord-content` skill (general community posts)

### Channel Creation (Manual)

Discord channels and webhooks must be created manually in the Discord server admin panel -- there is no automated way to do this safely:

1. Create #releases channel in the server (under an appropriate category)
2. Create a webhook in #releases, save the URL as `DISCORD_RELEASES_WEBHOOK_URL` repo secret
3. Create #blog channel in the server
4. Create a webhook in #blog, save the URL as `DISCORD_BLOG_WEBHOOK_URL` repo secret

### Research Insights: Webhook Creation

**Best Practice:** Name each webhook "Sol" and set the avatar to `logo-mark-512.png` at creation time. While the code always overrides these with `username` and `avatar_url` in the payload, setting them at the webhook level provides a fallback if any future code omits these fields. (Source: `2026-02-19-discord-bot-identity-and-webhook-behavior.md`)

### Code Changes

#### 1. `version-bump-and-release.yml` -- Route releases to #releases

- Change the "Post to Discord" step to use `DISCORD_RELEASES_WEBHOOK_URL` instead of `DISCORD_WEBHOOK_URL`
- Add fallback: if `DISCORD_RELEASES_WEBHOOK_URL` is not set, fall back to `DISCORD_WEBHOOK_URL` (graceful degradation for environments without the new secret)

**File:** `.github/workflows/version-bump-and-release.yml` (lines 239-278)

**Implementation detail:** The fallback must be resolved inside the `run:` script, not in the `env:` block. GitHub Actions `secrets.*` cannot be tested in job-level `if` conditions because they are masked before evaluation. (Source: `2026-02-12-ci-for-notifications-and-infrastructure-setup.md`)

```yaml
# version-bump-and-release.yml "Post to Discord" step
- name: Post to Discord
  if: steps.check_plugin.outputs.changed == 'true' && steps.idempotency.outputs.exists == 'false'
  env:
    DISCORD_RELEASES_WEBHOOK_URL: ${{ secrets.DISCORD_RELEASES_WEBHOOK_URL }}
    DISCORD_WEBHOOK_URL: ${{ secrets.DISCORD_WEBHOOK_URL }}
    TAG: ${{ steps.version.outputs.tag }}
    RELEASE_NOTES_FILE: ${{ steps.tmpfiles.outputs.release_notes }}
  run: |
    # Prefer releases channel, fall back to general
    WEBHOOK="${DISCORD_RELEASES_WEBHOOK_URL:-$DISCORD_WEBHOOK_URL}"
    if [ -z "$WEBHOOK" ]; then
      echo "No Discord webhook URL configured, skipping Discord notification"
      exit 0
    fi

    BODY=$(cat "$RELEASE_NOTES_FILE")
    REPO_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}"
    RELEASE_URL="${REPO_URL}/releases/tag/${TAG}"

    # Truncate body to 1900 chars for Discord's 2000 char limit
    if [ ${#BODY} -gt 1900 ]; then
      BODY="${BODY:0:1897}..."
    fi

    MESSAGE=$(printf '**Soleur %s released!**\n\n%s\n\nFull release notes: %s' \
      "$TAG" "$BODY" "$RELEASE_URL")

    PAYLOAD=$(jq -n \
      --arg content "$MESSAGE" \
      --arg username "Sol" \
      --arg avatar_url "https://raw.githubusercontent.com/jikig-ai/soleur/main/plugins/soleur/docs/images/logo-mark-512.png" \
      '{content: $content, username: $username, avatar_url: $avatar_url, allowed_mentions: {parse: []}}')

    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" \
      "$WEBHOOK")

    if [[ "$HTTP_CODE" =~ ^2 ]]; then
      echo "Discord notification sent (HTTP $HTTP_CODE)"
    else
      echo "::warning::Discord notification failed (HTTP $HTTP_CODE)"
    fi
```

#### 2. `content-publisher.sh` -- Route blog content to #blog

- Add support for `DISCORD_BLOG_WEBHOOK_URL` environment variable
- In `post_discord()`, prefer `DISCORD_BLOG_WEBHOOK_URL` over `DISCORD_WEBHOOK_URL`
- Add fallback: if `DISCORD_BLOG_WEBHOOK_URL` is not set, fall back to `DISCORD_WEBHOOK_URL`
- Update the `create_discord_fallback_issue()` function to mention the correct channel

**File:** `scripts/content-publisher.sh` (lines 126-153)

**Implementation detail:** The `post_discord()` function must resolve the webhook URL at the top using the same fallback pattern. The function currently checks `${DISCORD_WEBHOOK_URL:-}` -- change it to check the resolved variable. Keep the function signature unchanged (it still takes `content` as `$1`) since the webhook URL is an environment concern, not a parameter.

```bash
# content-publisher.sh -- updated post_discord()
post_discord() {
  local content="$1"

  # Prefer blog channel, fall back to general
  local webhook_url="${DISCORD_BLOG_WEBHOOK_URL:-${DISCORD_WEBHOOK_URL:-}}"

  if [[ -z "$webhook_url" ]]; then
    echo "Warning: No Discord webhook URL set (checked DISCORD_BLOG_WEBHOOK_URL, DISCORD_WEBHOOK_URL). Skipping Discord posting." >&2
    return 0
  fi

  local payload
  payload=$(jq -n \
    --arg content "$content" \
    --arg username "Sol" \
    --arg avatar_url "$AVATAR_URL" \
    '{content: $content, username: $username, avatar_url: $avatar_url, allowed_mentions: {parse: []}}')

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$webhook_url")

  if [[ "$http_code" =~ ^2 ]]; then
    echo "[ok] Discord message posted (HTTP $http_code)."
  else
    echo "Error: Discord webhook returned HTTP $http_code." >&2
    return 1
  fi
}
```

Also update the env var comment at the top of the file:

```bash
# Environment variables:
#   DISCORD_BLOG_WEBHOOK_URL   - Discord webhook for #blog channel (preferred; optional)
#   DISCORD_WEBHOOK_URL        - Discord webhook fallback (optional; skips if neither set)
```

**Error propagation note:** The `create_discord_fallback_issue()` function (line 192-196) should keep working as-is. It creates an issue when Discord posting fails -- the fallback issue text does not reference a specific channel, just "Discord channel". No change needed there. (Source: `2026-03-11-multi-platform-publisher-error-propagation.md`)

#### 3. `scheduled-content-publisher.yml` -- Pass new secret

- Add `DISCORD_BLOG_WEBHOOK_URL: ${{ secrets.DISCORD_BLOG_WEBHOOK_URL }}` to the "Publish content" step's env block
- The failure notification step continues using `DISCORD_WEBHOOK_URL` (operational alerts stay on the general channel)

**File:** `.github/workflows/scheduled-content-publisher.yml` (line 60)

```yaml
# Add to the "Publish content" step env block (after DISCORD_WEBHOOK_URL line):
DISCORD_BLOG_WEBHOOK_URL: ${{ secrets.DISCORD_BLOG_WEBHOOK_URL }}
```

#### 4. `social-distribute` skill -- Reference new env var

- Update the Discord webhook prerequisite check to mention `DISCORD_BLOG_WEBHOOK_URL` as the preferred env var
- Update webhook posting instructions to prefer `DISCORD_BLOG_WEBHOOK_URL`

**File:** `plugins/soleur/skills/social-distribute/SKILL.md` (prerequisite section)

Update the prerequisite check text:

```markdown
### 3. Discord Webhook URL (soft)

Check if `DISCORD_BLOG_WEBHOOK_URL` or `DISCORD_WEBHOOK_URL` environment variable is set.

**If both missing:**
> Neither `DISCORD_BLOG_WEBHOOK_URL` nor `DISCORD_WEBHOOK_URL` is set. Discord posting will be skipped (manual output only).
> To configure: Server Settings > Integrations > Webhooks > Copy URL from the #blog channel > `export DISCORD_BLOG_WEBHOOK_URL="..."`

Continue execution -- Discord becomes manual output like the other platforms.
```

Update the webhook posting to use `printenv DISCORD_BLOG_WEBHOOK_URL || printenv DISCORD_WEBHOOK_URL` for the URL.

#### 5. `discord-content` skill -- No changes needed

The `discord-content` skill is for general community content, not releases or blog posts. It correctly uses `DISCORD_WEBHOOK_URL` for the default/general channel.

#### 6. `discord-setup.sh` -- Update `write-env` to include new vars

- Add `DISCORD_RELEASES_WEBHOOK_URL` and `DISCORD_BLOG_WEBHOOK_URL` as optional variables in the `cmd_write_env()` function
- Update usage docs to mention the new variables

**File:** `plugins/soleur/skills/community/scripts/discord-setup.sh` (lines 204-236)

**Implementation detail:** The `cmd_write_env()` function uses `grep -v` to strip existing Discord vars before re-writing. The new variables need the same treatment:

```bash
# discord-setup.sh cmd_write_env() -- add grep -v lines for new vars
if [[ -f "$env_file" ]]; then
  local tmp
  tmp=$(mktemp) || { echo "Error: Failed to create temp file." >&2; exit 1; }
  grep -v '^DISCORD_BOT_TOKEN=' "$env_file" | \
    grep -v '^DISCORD_GUILD_ID=' | \
    grep -v '^DISCORD_WEBHOOK_URL=' | \
    grep -v '^DISCORD_RELEASES_WEBHOOK_URL=' | \
    grep -v '^DISCORD_BLOG_WEBHOOK_URL=' > "$tmp" || true
  mv "$tmp" "$env_file"
fi
```

The new vars are written after the existing three only if environment variables are provided. Since these are optional (only needed for local development), pass them via additional env vars:

```bash
# Optional: write channel-specific webhooks if provided
if [[ -n "${DISCORD_RELEASES_WEBHOOK_URL_INPUT:-}" ]]; then
  echo "DISCORD_RELEASES_WEBHOOK_URL=${DISCORD_RELEASES_WEBHOOK_URL_INPUT}" >> "$env_file"
fi
if [[ -n "${DISCORD_BLOG_WEBHOOK_URL_INPUT:-}" ]]; then
  echo "DISCORD_BLOG_WEBHOOK_URL=${DISCORD_BLOG_WEBHOOK_URL_INPUT}" >> "$env_file"
fi
```

#### 7. Documentation updates

- Update the learning at `knowledge-base/project/learnings/2026-02-19-discord-bot-identity-and-webhook-behavior.md` to reference the multi-webhook channel architecture
- Update `knowledge-base/overview/constitution.md` if any new conventions emerge (e.g., webhook naming pattern)

## Technical Considerations

### Webhook per channel architecture

Discord webhooks are channel-scoped -- each webhook posts to exactly one channel. The project already has this pattern (the learning doc mentions separate community and release webhooks). This change formalizes it with distinct secret names.

### Research Insights: Webhook URL Naming Convention

The naming pattern `DISCORD_<PURPOSE>_WEBHOOK_URL` is consistent and discoverable:
- `DISCORD_WEBHOOK_URL` -- general/default (existing)
- `DISCORD_RELEASES_WEBHOOK_URL` -- releases channel
- `DISCORD_BLOG_WEBHOOK_URL` -- blog channel

This pattern scales if more channels are added later (e.g., `DISCORD_STATUS_WEBHOOK_URL` for an ops channel).

### Backward compatibility

All changes use fallback patterns: `${DISCORD_RELEASES_WEBHOOK_URL:-$DISCORD_WEBHOOK_URL}`. Environments that have not created the new secrets continue to work unchanged -- all content goes to the existing channel.

### Research Insights: Fallback Pattern Robustness

The bash parameter expansion `${VAR1:-${VAR2:-}}` handles three states correctly:
1. `VAR1` set and non-empty -- uses `VAR1` (new channel-specific webhook)
2. `VAR1` unset/empty, `VAR2` set -- uses `VAR2` (fallback to general)
3. Both unset -- expands to empty string, caught by the `-z` check

**Gotcha from institutional learning:** GitHub Actions `secrets.*` are always "set" in the env block (they expand to empty string, not unset). The `:-` operator handles this correctly because it treats empty strings the same as unset. The simpler `${VAR1-$VAR2}` (without colon) would NOT work because empty-string secrets would be "set". (Source: `2026-02-12-ci-for-notifications-and-infrastructure-setup.md`)

### Secret management

The new secrets (`DISCORD_RELEASES_WEBHOOK_URL`, `DISCORD_BLOG_WEBHOOK_URL`) are GitHub repository secrets set via Settings > Secrets > Actions. No `.env` file changes are needed for CI. Local development (via `discord-setup.sh write-env`) optionally supports the new variables.

### Identity consistency

All webhook payloads already include explicit `username: "Sol"` and `avatar_url` fields per constitution.md rule. This ensures consistent identity across all three webhooks/channels.

### Research Insights: Identity Across Channels

Each new webhook is an independent identity record in Discord. Even though the code always sends `username` and `avatar_url` in the payload (overriding defaults), the webhook's own default identity matters in two edge cases:
1. **Discord audit log** -- shows the webhook's registered name, not the payload override
2. **Webhook list view** -- Server Settings > Integrations shows all webhooks with their default names

Name all three webhooks "Sol" at creation time for audit log consistency. (Source: `2026-02-19-discord-bot-identity-and-webhook-behavior.md`)

## Non-Goals

- Creating the Discord channels (manual admin task)
- Changing the structure of posted messages (format stays the same)
- Adding rich embeds or interactive components
- Reorganizing other channels (e.g., #general, #help)
- Creating a channel for CI failure notifications (they stay on the default webhook)

## Acceptance Criteria

- [x] `version-bump-and-release.yml` posts release announcements to `DISCORD_RELEASES_WEBHOOK_URL` when set, falls back to `DISCORD_WEBHOOK_URL` when not set
- [x] `content-publisher.sh` posts blog/case-study content to `DISCORD_BLOG_WEBHOOK_URL` when set, falls back to `DISCORD_WEBHOOK_URL` when not set
- [x] `scheduled-content-publisher.yml` passes the new `DISCORD_BLOG_WEBHOOK_URL` secret to the publish step
- [x] `social-distribute` skill documentation references `DISCORD_BLOG_WEBHOOK_URL`
- [x] All existing CI workflows that use `DISCORD_WEBHOOK_URL` for failure notifications continue to work unchanged
- [x] All webhook payloads continue to include `username`, `avatar_url`, and `allowed_mentions: {parse: []}` fields
- [x] `discord-setup.sh write-env` supports the new optional webhook variables
- [x] The fallback pattern is tested: workflows work correctly when only `DISCORD_WEBHOOK_URL` is set

## Test Scenarios

- Given `DISCORD_RELEASES_WEBHOOK_URL` is set, when a release is created, then the release announcement is posted to the releases webhook URL
- Given `DISCORD_RELEASES_WEBHOOK_URL` is NOT set but `DISCORD_WEBHOOK_URL` is, when a release is created, then the release announcement falls back to the default webhook URL
- Given `DISCORD_BLOG_WEBHOOK_URL` is set, when `content-publisher.sh` posts Discord content, then the content is posted to the blog webhook URL
- Given `DISCORD_BLOG_WEBHOOK_URL` is NOT set but `DISCORD_WEBHOOK_URL` is, when `content-publisher.sh` posts Discord content, then the content falls back to the default webhook URL
- Given neither `DISCORD_RELEASES_WEBHOOK_URL` nor `DISCORD_WEBHOOK_URL` is set, when a release is created, then the Discord step is skipped with a warning
- Given the new channels exist in Discord with webhooks configured, when all three webhook secrets are set, then releases go to #releases, blog posts go to #blog, and failure notifications go to the default channel

### Research Insights: Test Implementation

The existing `test/content-publisher.test.ts` uses a `runFunction()` helper that sources the script and calls individual functions with controlled env vars. The new tests should follow this pattern:

```typescript
// test/content-publisher.test.ts -- new tests for webhook fallback
describe("post_discord webhook URL resolution", () => {
  test("uses DISCORD_BLOG_WEBHOOK_URL when set", () => {
    // Mock a local HTTP server or check the resolved URL via a wrapper
    const result = runFunction(`
      # Override curl to capture the URL
      curl() { echo "URL=$4"; return 0; }
      export -f curl
      DISCORD_BLOG_WEBHOOK_URL="https://blog-webhook"
      DISCORD_WEBHOOK_URL="https://general-webhook"
      post_discord "test content"
    `, {
      DISCORD_BLOG_WEBHOOK_URL: "https://blog-webhook",
      DISCORD_WEBHOOK_URL: "https://general-webhook",
    });
    expect(result.stdout).toContain("https://blog-webhook");
  });

  test("falls back to DISCORD_WEBHOOK_URL when blog URL not set", () => {
    const result = runFunction(`
      curl() { echo "URL=$4"; return 0; }
      export -f curl
      post_discord "test content"
    `, {
      DISCORD_WEBHOOK_URL: "https://general-webhook",
    });
    expect(result.stdout).toContain("https://general-webhook");
  });

  test("skips posting when no webhook URLs set", () => {
    const result = runFunction(`post_discord "test content"`);
    expect(result.exitCode).toBe(0);
    expect(result.stderr).toContain("No Discord webhook URL set");
  });
});
```

**Note:** The `curl` mock approach above may need refinement since `runFunction` runs in a subshell. An alternative is to extract the URL resolution into a testable function (e.g., `resolve_discord_webhook_url()`) that can be tested independently.

## Dependencies & Risks

### Dependencies

- Manual Discord admin action: create #releases and #blog channels plus webhooks
- GitHub repo admin action: add `DISCORD_RELEASES_WEBHOOK_URL` and `DISCORD_BLOG_WEBHOOK_URL` secrets

### Risks

- **Low risk**: Fallback pattern ensures no breakage if secrets are not yet configured
- **Low risk**: Webhook URL format is the same as existing -- no new API patterns

### Research Insights: Deployment Sequencing

The code changes can merge before the Discord channels and secrets are created. The fallback pattern ensures everything continues to work with just `DISCORD_WEBHOOK_URL`. The recommended deployment sequence:

1. Merge code changes (fallback ensures no disruption)
2. Create Discord channels and webhooks (manual admin task)
3. Add new repository secrets in GitHub
4. Verify by triggering a test release or content publish

This ordering avoids any window where the code expects secrets that don't exist yet.

## Files to Modify

| File | Change |
|------|--------|
| `.github/workflows/version-bump-and-release.yml` | Use `DISCORD_RELEASES_WEBHOOK_URL` with fallback |
| `scripts/content-publisher.sh` | Use `DISCORD_BLOG_WEBHOOK_URL` with fallback |
| `.github/workflows/scheduled-content-publisher.yml` | Pass `DISCORD_BLOG_WEBHOOK_URL` secret |
| `plugins/soleur/skills/social-distribute/SKILL.md` | Reference `DISCORD_BLOG_WEBHOOK_URL` |
| `plugins/soleur/skills/community/scripts/discord-setup.sh` | Optional new vars in `write-env` |
| `knowledge-base/project/learnings/2026-02-19-discord-bot-identity-and-webhook-behavior.md` | Document multi-webhook pattern |
| `test/content-publisher.test.ts` | Add tests for new env var fallback logic |

## References

- `knowledge-base/project/learnings/2026-02-19-discord-bot-identity-and-webhook-behavior.md` -- Existing webhook identity patterns
- `knowledge-base/project/learnings/2026-03-05-discord-allowed-mentions-for-webhook-sanitization.md` -- Webhook payload security
- `knowledge-base/project/learnings/implementation-patterns/2026-02-12-ci-for-notifications-and-infrastructure-setup.md` -- CI secrets cannot be tested in job-level `if` conditions
- `knowledge-base/project/learnings/2026-03-11-multi-platform-publisher-error-propagation.md` -- Error propagation and fallback issue patterns
- `knowledge-base/project/learnings/2026-03-09-shell-api-wrapper-hardening-patterns.md` -- Shell API wrapper patterns (already applied)
- Constitution rule: "All Discord webhook payloads must include explicit `username`, `avatar_url`, and `allowed_mentions: {parse: []}` fields"
