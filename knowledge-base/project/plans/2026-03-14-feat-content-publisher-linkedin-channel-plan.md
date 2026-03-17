---
title: "feat: Content-publisher LinkedIn channel automation"
type: feat
date: 2026-03-14
---

# feat: Content-publisher LinkedIn channel automation

Add LinkedIn as an automated publishing channel in `content-publisher.sh`, following the X/Twitter posting pattern. The LinkedIn API scripts (`linkedin-community.sh`) are now merged (#608), unblocking this work.

## Context

Issue #590. The initial LinkedIn presence PR (#586) shipped LinkedIn as manual-only in `social-distribute`. The API scripts landed in #608. This issue wires the content-publisher to call `linkedin-community.sh post-content` when a distribution content file declares `linkedin` in its `channels` frontmatter.

The scope is narrow: one new case in `channel_to_section()`, one new `post_linkedin()` function, one fallback issue creator, test updates, and CI workflow env var additions. The `social-distribute` skill already generates `## LinkedIn` sections and supports `linkedin` in the channels frontmatter field -- no changes needed there.

## Proposed Solution

Follow the X/Twitter posting pattern in `content-publisher.sh`:

1. **`channel_to_section()`** -- add `linkedin` mapping to `"LinkedIn"` section heading
2. **`post_linkedin()`** -- extract `## LinkedIn` section content, call `linkedin-community.sh post-content --text "$content"`, handle errors
3. **`create_linkedin_fallback_issue()`** -- create a dedup GitHub issue on posting failure with the LinkedIn content for manual posting
4. **Main dispatch** -- add `linkedin)` case in the channel loop alongside `discord)` and `x)`
5. **Test updates** -- change the "unknown channel" assertion (line 314) from `linkedin` to a genuinely unknown channel, add positive test for `linkedin` mapping, add `post_linkedin` tests
6. **CI workflow** -- add `LINKEDIN_ACCESS_TOKEN` and `LINKEDIN_PERSON_URN` secrets to `scheduled-content-publisher.yml`

## Non-Goals

- Dual-variant posting (company page vs personal profile) -- deferred to #591
- LinkedIn analytics/monitoring in content-publisher -- separate concern owned by community-manager
- Changes to `social-distribute` -- it already generates LinkedIn content sections
- Content-publisher scheduling constraints (Tuesday-Thursday) -- guideline only, not programmatic enforcement

## Acceptance Criteria

- [x] `channel_to_section "linkedin"` returns `"LinkedIn"` (`scripts/content-publisher.sh`)
- [x] `post_linkedin()` calls `linkedin-community.sh post-content --text` with extracted `## LinkedIn` section content, returns 1 on failure (not 0)
- [x] `post_linkedin()` skips gracefully (return 0) when `LINKEDIN_ACCESS_TOKEN` is unset
- [x] `create_linkedin_fallback_issue()` creates a dedup GitHub issue on posting failure
- [x] Main channel dispatch loop handles `linkedin)` case
- [x] `main()` validates `LINKEDIN_SCRIPT` exists when `LINKEDIN_ACCESS_TOKEN` is set (matches X pattern)
- [x] `scheduled-content-publisher.yml` passes `LINKEDIN_ACCESS_TOKEN` and `LINKEDIN_PERSON_URN` secrets
- [x] `scheduled-content-publisher.yml` header comment updated to mention LinkedIn
- [x] Test: `channel_to_section "linkedin"` returns `"LinkedIn"`
- [x] Test: `extract_section` correctly extracts `## LinkedIn` section content
- [x] Test: unknown channel test uses a genuinely unknown channel name (not `linkedin`)
- [x] Existing tests pass unchanged (`bun test test/content-publisher.test.ts`)

## Test Scenarios

- Given `channel_to_section "linkedin"`, when called, then returns `"LinkedIn"`
- Given `channel_to_section "unknown_channel"`, when called, then returns empty string
- Given a content file with `channels: discord, x, linkedin` and `publish_date: today`, when content-publisher runs with `LINKEDIN_ACCESS_TOKEN` unset, then LinkedIn is skipped gracefully and Discord/X proceed normally
- Given a content file with `channels: linkedin` and valid credentials, when `linkedin-community.sh post-content` fails, then a fallback GitHub issue is created AND `post_linkedin` returns 1
- Given a content file with a `## LinkedIn` section containing post content, when `post_linkedin` is called, then it extracts the section and passes it as `--text` to `linkedin-community.sh post-content`

## Technical Considerations

- **Error propagation**: per constitution rule and learning `2026-03-13-platform-integration-scope-calibration.md`, `post_linkedin()` must return 1 on failure (not 0). Only return 0 for genuine skips (missing credentials).
- **LinkedIn content is single-post** (not a thread like X): extraction is simpler -- just `extract_section "$file" "LinkedIn"` and pass the full text. No tweet splitting needed.
- **Character limit**: `linkedin-community.sh` enforces the 3000-char limit internally. The content-publisher does not need to re-validate.
- **Credential check pattern**: match X's pattern -- check `LINKEDIN_ACCESS_TOKEN` at the start of `post_linkedin()`, skip with warning if unset.
- **`LINKEDIN_PERSON_URN`**: also needed by `linkedin-community.sh` but validated there, not in content-publisher. Content-publisher only needs to check `LINKEDIN_ACCESS_TOKEN` as the gate variable.

## MVP

### scripts/content-publisher.sh

```bash
# In channel_to_section():
linkedin) echo "LinkedIn" ;;

# New function:
post_linkedin() {
  local file="$1"
  if [[ -z "${LINKEDIN_ACCESS_TOKEN:-}" ]]; then
    echo "Warning: LINKEDIN_ACCESS_TOKEN not set. Skipping LinkedIn posting." >&2
    return 0
  fi
  local content
  content=$(extract_section "$file" "LinkedIn")
  if [[ -z "$content" ]]; then
    echo "Warning: No LinkedIn content found in $(basename "$file"). Skipping." >&2
    return 0
  fi
  bash "$LINKEDIN_SCRIPT" post-content --text "$content" || {
    echo "Error: LinkedIn posting failed. Creating fallback issue." >&2
    create_linkedin_fallback_issue "$file"
    return 1
  }
  echo "[ok] LinkedIn post published."
}
```

### test/content-publisher.test.ts

```typescript
// Update line ~314: change "linkedin" to a genuinely unknown channel
test("returns empty for unknown channel", () => {
  const result = runFunction(`channel_to_section "mastodon"`);
  expect(result.exitCode).toBe(0);
  expect(result.stdout).toBe("");
});

// Add positive test
test("maps linkedin to LinkedIn", () => {
  const result = runFunction(`channel_to_section "linkedin"`);
  expect(result.exitCode).toBe(0);
  expect(result.stdout).toBe("LinkedIn");
});
```

### .github/workflows/scheduled-content-publisher.yml

```yaml
# Add to publish step env:
LINKEDIN_ACCESS_TOKEN: ${{ secrets.LINKEDIN_ACCESS_TOKEN }}
LINKEDIN_PERSON_URN: ${{ secrets.LINKEDIN_PERSON_URN }}
```

## References

- Pattern: `scripts/content-publisher.sh` X/Twitter posting logic (lines 222-302)
- Pattern: `plugins/soleur/skills/community/scripts/linkedin-community.sh` post-content command (lines 223-278)
- Learning: `knowledge-base/learnings/2026-03-13-platform-integration-scope-calibration.md`
- Parent issue: #590 (Content-publisher LinkedIn channel automation)
- Prerequisite: #608 (LinkedIn API scripts -- merged 2026-03-14)
- Related: #586 (LinkedIn manual-only -- merged 2026-03-13)
- Related: #591 (LinkedIn company page variant -- separate PR)
- Semver: `semver:patch` -- extends existing functionality with a new channel
