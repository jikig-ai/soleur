# Feature: LinkedIn Company Page Variant + Playwright Setup

## Problem Statement

Issue #593 is gated on two conditions: (1) a LinkedIn company page must exist, and (2) real data must show company page content needs to differ from personal profile content. The existing social-distribute LinkedIn variant (shipped in #586) only supports personal profile content. Company page creation was marked as "manual browser action" — but Playwright MCP can automate most of the flow, following the pattern proven with X/Twitter provisioning.

## Goals

- Automate LinkedIn company page creation via Playwright MCP in `linkedin-setup.sh`
- Capture company page URL into `site.json` automatically
- Add a second LinkedIn variant (company page) to social-distribute with official announcement tone
- Wire `linkedin-personal` and `linkedin-company` as separate channels in content-publisher
- Migrate existing `## LinkedIn` sections to `## LinkedIn Personal`

## Non-Goals

- LinkedIn API automation for automated posting (tracked in #590)
- LinkedIn comment engagement
- Platform adapter interface refactor (#470)
- LinkedIn API App approval process

## Functional Requirements

### FR1: LinkedIn Company Page Creation (linkedin-setup.sh)

Playwright MCP guided workflow:
- Navigate to LinkedIn company page creation form
- Fill company details from `site.json` and brand guide (name, description, industry, logo)
- Pause for human on auth steps (login, MFA, CAPTCHA)
- Capture resulting company page URL
- Write URL to `site.json`

### FR2: Content Section Migration

One-time migration of existing content files:
- Rename `## LinkedIn` → `## LinkedIn Personal` across all files in `knowledge-base/marketing/distribution-content/`
- Update social-distribute SKILL.md section references

### FR3: LinkedIn Company Page Variant (social-distribute)

Add Phase 5.7 to social-distribute:
- Official announcement tone, third-person ("Soleur now supports...")
- ~1300 chars optimal, 3000 max
- UTM: `utm_source=linkedin-company&utm_medium=social&utm_campaign=<slug>`
- Section heading: `## LinkedIn Company Page`

### FR4: Content-Publisher Channel Mapping

Update `channel_to_section()` in `content-publisher.sh`:
- `linkedin-personal` → `"LinkedIn Personal"`
- `linkedin-company` → `"LinkedIn Company Page"`
- Remove old `linkedin` → `""` mapping
- Update tests to reflect new mappings

### FR5: Brand Guide Update

Add `### LinkedIn Company Page` Channel Notes:
- Official announcement tone
- Third-person company voice
- Product updates, feature announcements, milestones
- Cross-reference with `### LinkedIn` (personal) section

## Technical Requirements

### TR1: Playwright MCP Integration

Follow established patterns:
- Use absolute paths for all MCP file outputs (worktree-safe)
- Pause for human input on security-sensitive steps only
- Handle session timeouts and unexpected modals gracefully

### TR2: Sed Migration Safety

Content file migration must:
- Only replace `## LinkedIn` at line start (not mid-line references)
- Preserve all other content unchanged
- Be idempotent (running twice produces same result)

### TR3: Backward Compatibility

- `channel_to_section("linkedin")` should warn and map to `linkedin-personal` for any legacy references
- New content files use `linkedin-personal` and `linkedin-company` exclusively

### TR4: Error Handling (content-publisher)

Follow learning from `2026-03-11-multi-platform-publisher-error-propagation.md`:
- Return 0 for skips (missing credentials), 1 for failures
- Create fallback GitHub issues on failure
- Use exit code 2 for partial failure
