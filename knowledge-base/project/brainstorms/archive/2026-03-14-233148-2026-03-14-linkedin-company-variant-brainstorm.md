# Brainstorm: LinkedIn Company Page Variant + Playwright Setup

**Date:** 2026-03-14
**Issue:** #593
**Branch:** feat-linkedin-company-variant
**Status:** Complete
**Builds on:** `2026-03-13-linkedin-presence-brainstorm.md` (issue #138)

## What We're Building

Two capabilities that together clear the gate on issue #593:

1. **LinkedIn company page creation via Playwright MCP** — a guided workflow in `linkedin-setup.sh` that automates creating a LinkedIn company page. Playwright handles navigation and form filling; the human handles auth steps (login, MFA). The resulting company page URL is captured and written to `site.json` automatically.

2. **Second social-distribute LinkedIn variant** — a LinkedIn Company Page variant with official announcement tone, distinct from the existing personal profile variant (thought-leadership tone). Content-publisher gets two new channels: `linkedin-personal` and `linkedin-company`, each mapping to their own section heading.

## Why This Approach

The original brainstorm (#138) deferred company page creation as "manual browser action" and gated the second variant on having a company page + data showing content needs to differ. This brainstorm clears both gates:

- **Gate 1 (company page exists):** Playwright MCP automates creation, following the same semi-automated provisioning pattern proven with X/Twitter (learning: `2026-03-09-x-provisioning-playwright-automation.md`).
- **Gate 2 (content differs):** B2B best practice is clear — company pages use official announcement tone while personal profiles use thought-leadership/reflective tone. LinkedIn's algorithm treats them differently (company pages get 2-5% organic reach vs personal 10-15x more).

Sequential delivery in one PR keeps each commit coherent while avoiding two review cycles.

## Key Decisions

1. **linkedin-setup.sh hosts the Playwright workflow.** Adds to the existing stub planned in #589. Keeps all LinkedIn provisioning in one script alongside credential validation. Follows the ops-provisioner pattern but stays LinkedIn-specific.

2. **Channel names: `linkedin-personal` + `linkedin-company`.** Hyphenated compound names mapping to `## LinkedIn Personal` and `## LinkedIn Company Page` section headings. Explicit, no ambiguity.

3. **Rename + migrate existing content.** Existing `## LinkedIn` sections rename to `## LinkedIn Personal` via a one-time sed migration across content files. Clean break, no alias complexity in `channel_to_section()`.

4. **Full Playwright automation.** Script navigates to LinkedIn company page creation form, fills company details from `site.json`/brand-guide, pauses for human on auth/CAPTCHA steps, captures resulting URL back to `site.json`. Only genuinely manual steps are login credentials and potential CAPTCHA.

5. **Sequential delivery in one PR.** Four steps, each commit coherent:
   - Step 1: `linkedin-setup.sh` with Playwright MCP company page creation
   - Step 2: Migrate `## LinkedIn` → `## LinkedIn Personal` in existing content files
   - Step 3: Add `## LinkedIn Company Page` section to social-distribute + content template
   - Step 4: Wire `linkedin-personal` and `linkedin-company` into `channel_to_section()`

6. **Content tone differentiation:**
   - **LinkedIn Personal:** First-person founder voice, thought-leadership, reflective ("I've been building..."). ~1300 chars optimal.
   - **LinkedIn Company Page:** Third-person official voice, announcement framing, professional ("Soleur now supports..."). ~1300 chars optimal.

## Open Questions

1. **LinkedIn company page creation form fields** — what exactly does LinkedIn ask for during page creation? Need to verify via live Playwright navigation before implementing the automation.
2. **site.json field name** — where should the company page URL be stored? `linkedin.companyPageUrl`? `social.linkedin.company`? Need to check existing `site.json` structure.
3. **Content-publisher automation priority** — should `linkedin-personal` and `linkedin-company` be added to `channels` frontmatter immediately (requiring LinkedIn API automation from #590), or stay manual-only like the current LinkedIn variant?

## Domain Leader Assessments

### CMO Assessment

*(Spawned in background — assessment pending)*

## Scope Summary

### In Scope

- `linkedin-setup.sh` Playwright MCP workflow for company page creation
- `site.json` update with company page URL (auto-captured)
- `## LinkedIn` → `## LinkedIn Personal` migration in existing content files
- `social-distribute` Phase 5.7: LinkedIn Company Page variant
- `channel_to_section()` mappings for `linkedin-personal` and `linkedin-company`
- Content file template update with both LinkedIn sections
- Brand guide update with `### LinkedIn Company Page` Channel Notes

### Out of Scope

- LinkedIn API automation (#590 — separate issue)
- Content-publisher automated posting to LinkedIn (depends on #590)
- LinkedIn comment engagement
- Platform adapter interface refactor (#470)
