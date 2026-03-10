---
title: "feat: add public surface parity checks after provisioning"
type: feat
date: 2026-03-10
semver: patch
---

# feat: add public surface parity checks after provisioning

## Overview

When a new user-facing integration is provisioned (e.g., X account via #474), the ops-provisioner completes successfully but nothing flags that the docs site and brand guide need updating with links to the new platform. This was caught manually post-merge (#480). The fix adds lightweight parity checks at two levels: a community skill-specific check for social platforms, and a broader ops-provisioner check for any SaaS with public-facing presence.

## Problem Statement / Motivation

This is a class of miss, not a one-off. Any SaaS/API with public-facing presence (social links, analytics badges, integration pages) will have the same gap. The provisioning workflow currently ends at "API verified + expense recorded" but never asks "does the website know about this?"

**Discovered from:** Post-merge review of #474 (X provisioning). Filed #480 for the immediate X website gap.

## Proposed Solution

Two complementary checklist additions -- no new scripts, no new agents, no new skills.

### 1. Community skill: platform parity check

In `plugins/soleur/skills/community/SKILL.md`, add a "Platform Surface Check" section that runs after a new platform is added via setup scripts. It verifies:

- `plugins/soleur/docs/_data/site.json` has a URL entry for the platform
- `plugins/soleur/docs/pages/community.njk` has a card for the platform in the Connect section
- `knowledge-base/overview/brand-guide.md` mentions the platform handle

If any are missing, output a warning listing the specific files to update. Optionally suggest creating a follow-up issue.

### 2. Ops-provisioner: post-provisioning surface check

In `plugins/soleur/agents/operations/ops-provisioner.md`, after the "Verify + Record" phase, add a new phase:

> **Public Surface Check:** Does this tool have a user-visible presence (social links, badges, embeds, landing page mentions)? If yes, check whether `plugins/soleur/docs/_data/site.json` and relevant docs pages reference it. If not, file a follow-up issue for the docs update.

This catches non-community integrations too (e.g., Plausible analytics badge, Cloudflare status page link).

## Technical Considerations

- **No new code:** Both changes are markdown instruction additions to existing files
- **No new agents or skills:** This is adding checklist steps, not orchestration
- **File paths must use `plugins/soleur/docs/`**: The issue references `docs/_data/site.json` but the actual path is `plugins/soleur/docs/_data/site.json` -- the plan corrects this
- **Constitution principle alignment:** "Prefer inline instructions over Task agents for deterministic checks" (constitution.md) -- these are simple file-existence checks, not LLM analysis tasks
- **Agent prompt principle:** "Agent prompts must contain only instructions the LLM would get wrong without them" (constitution.md) -- the surface check is a reasonable addition because provisioning agents would not spontaneously check the docs site

## Acceptance Criteria

- [ ] `plugins/soleur/skills/community/SKILL.md` includes a "Platform Surface Check" section listing the three files to verify after platform setup
- [ ] `plugins/soleur/agents/operations/ops-provisioner.md` includes a "Public Surface Check" phase after "Verify + Record"
- [ ] Both checks list the correct file paths (`plugins/soleur/docs/_data/site.json`, `plugins/soleur/docs/pages/community.njk`, `knowledge-base/overview/brand-guide.md`)
- [ ] Ops-provisioner check is generic (not hard-coded to social platforms) and suggests filing a follow-up issue when gaps are found
- [ ] Community skill check is scoped to social/community platforms specifically
- [ ] Neither check blocks the provisioning workflow -- warnings only

## Test Scenarios

- Given a new social platform was just set up via community skill, when the platform surface check runs, then it warns if `site.json` lacks the platform URL
- Given a new SaaS tool was provisioned via ops-provisioner, when the public surface check runs and the tool has user-visible presence, then it warns if docs pages don't reference it
- Given a new SaaS tool was provisioned that has NO public-facing presence (e.g., internal monitoring), when the public surface check runs, then no warning is emitted
- Given all three surface files already reference the platform, when the checks run, then no warnings are emitted (clean pass)

## Non-Goals

- Not implementing automated file modification (the checks warn, they don't fix)
- Not creating a new agent or skill for surface checking
- Not adding shell scripts for programmatic file scanning
- Not resolving #480 (the actual X website updates) -- that is a separate PR

## Success Metrics

- Next provisioning of a user-facing tool triggers the surface check warning before the workflow completes
- Zero post-merge "forgot to update the website" issues after this lands

## Dependencies & Risks

- **Dependency on #480:** The X-specific website updates (#480) should land separately. This plan prevents future misses; #480 fixes the current one.
- **Risk: path drift.** If docs site structure changes (e.g., `site.json` moves), the hardcoded paths in the checks become stale. Mitigated by the fact that path changes are rare and would surface during normal review.

## References & Research

### Internal References

- `plugins/soleur/skills/community/SKILL.md` -- community skill entry point (platform detection, sub-commands)
- `plugins/soleur/agents/operations/ops-provisioner.md` -- provisioning agent (Setup, Configure, Verify+Record phases)
- `plugins/soleur/docs/_data/site.json` -- site metadata including social links (currently has `github` and `discord`, no X)
- `plugins/soleur/docs/pages/community.njk` -- community page with Connect cards (currently Discord and GitHub only)
- `knowledge-base/overview/brand-guide.md` -- brand identity, voice, channel notes

### Related Issues

- #481 -- This issue (add public surface parity checks)
- #480 -- Immediate fix: add X/Twitter links to website and brand guide
- #474 -- X provisioning PR that exposed the gap

### Relevant Learnings

- `knowledge-base/learnings/2026-02-22-ops-provisioner-worktree-gap.md` -- ops-provisioner previously had no branch safety check; similar class of "missing guardrail"
- `knowledge-base/learnings/2026-02-12-brand-guide-contract-and-inline-validation.md` -- inline validation beats separate agents for single-document checks
- `knowledge-base/learnings/2026-03-09-x-provisioning-playwright-automation.md` -- X provisioning context
