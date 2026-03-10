---
title: "feat: add public surface parity checks after provisioning"
type: feat
date: 2026-03-10
semver: patch
---

# feat: add public surface parity checks after provisioning

## Enhancement Summary

**Deepened on:** 2026-03-10
**Sections enhanced:** 5 (Proposed Solution, Technical Considerations, Acceptance Criteria, Test Scenarios, Dependencies & Risks)
**Research sources:** agent-native-architecture principles, code-simplicity patterns, institutional learnings (5 applied), existing file structure analysis

### Key Improvements

1. Refined trigger timing -- community check fires inside each sub-command that calls setup scripts, not as a separate phase
2. Added concrete markdown examples for both instruction additions showing exact placement and wording
3. Identified a fourth surface to check: `plugins/soleur/docs/_includes/base.njk` footer (social icon links)
4. Clarified ops-provisioner check should be a semantic question to the LLM, not a file-scanning script

### New Considerations Discovered

- The community skill check must NOT add `$()` shell expansions to SKILL.md (constitution.md: "Never use shell variable expansion in skill .md files")
- The ops-provisioner already has a precedent for post-action checks (the branch safety check in Setup was added via the same "missing guardrail" pattern)
- The check should use the AskUserQuestion tool pattern for issue filing, not auto-create issues

## Overview

When a new user-facing integration is provisioned (e.g., X account via #474), the ops-provisioner completes successfully but nothing flags that the docs site and brand guide need updating with links to the new platform. This was caught manually post-merge (#480). The fix adds lightweight parity checks at two levels: a community skill-specific check for social platforms, and a broader ops-provisioner check for any SaaS with public-facing presence.

## Problem Statement / Motivation

This is a class of miss, not a one-off. Any SaaS/API with public-facing presence (social links, analytics badges, integration pages) will have the same gap. The provisioning workflow currently ends at "API verified + expense recorded" but never asks "does the website know about this?"

**Discovered from:** Post-merge review of #474 (X provisioning). Filed #480 for the immediate X website gap.

## Proposed Solution

Two complementary checklist additions -- no new scripts, no new agents, no new skills.

### 1. Community skill: platform parity check

In `plugins/soleur/skills/community/SKILL.md`, add a "Platform Surface Check" section that fires after any setup script completes successfully. It verifies:

- `plugins/soleur/docs/_data/site.json` has a URL entry for the platform (currently has `github` and `discord` keys)
- `plugins/soleur/docs/pages/community.njk` has a card for the platform in the Connect section
- `knowledge-base/overview/brand-guide.md` mentions the platform handle
- `plugins/soleur/docs/_includes/base.njk` footer includes a link to the platform (if social icon links exist there)

If any are missing, output a warning listing the specific files to update. Suggest filing a follow-up issue via `gh issue create`.

#### Research Insights: Placement and Trigger

The community SKILL.md currently has no setup-related sub-commands -- setup scripts are called directly from the command line. The parity check section should be added as a standalone section titled `## Platform Surface Check` placed after `## Important Guidelines`. It should instruct: "After confirming a new platform's setup script completed successfully (via platforms sub-command showing [enabled]), read the following files and verify the platform is referenced."

This keeps the check as a read-only verification step, not an automated fix. Per the inline-validation learning: inline checks beat separate agents for single-document concerns.

#### Concrete Instruction Text

The section added to SKILL.md should follow this structure:

```text
## Platform Surface Check

After a new platform is set up and verified via its setup script, check whether the
platform has been added to all public-facing surfaces. Read each file and verify:

| File | What to look for |
|------|------------------|
| plugins/soleur/docs/_data/site.json | URL entry for the platform |
| plugins/soleur/docs/pages/community.njk | Card in the Connect section |
| knowledge-base/overview/brand-guide.md | Platform handle mention |

If any surface is missing, output a warning:

"[WARNING] Platform <platform-name> is missing from: <list of files>.
These files need updating before the integration is complete.
Consider filing: gh issue create --title 'feat(docs): add <platform> to website and brand guide'"

This check does not block provisioning -- it is advisory only.
```

**Important:** No `$()` or shell variable expansion in the SKILL.md text. Use angle-bracket placeholders per constitution.md convention.

### 2. Ops-provisioner: post-provisioning surface check

In `plugins/soleur/agents/operations/ops-provisioner.md`, after the "Verify + Record" section and before "Safety Rules", add a new `## Public Surface Check` section.

#### Research Insights: Semantic Question vs. File Scan

Per the agent-prompt-sharp-edges-only learning, agent instructions should contain only what the model would get wrong without them. The LLM already knows how to check file contents -- what it lacks is the prompt to do so. The check should be framed as a semantic question, not a file-scanning procedure:

> Does this tool have a user-visible presence (social links, badges, embeds, landing page mentions)?

This lets the LLM use its judgment about what constitutes "user-visible presence" rather than maintaining a brittle enumeration of surface types.

#### Concrete Instruction Text

```text
## Public Surface Check

After recording the expense, assess whether the newly provisioned tool has any
user-visible presence -- social links, analytics badges, embeds, status page links,
or landing page mentions.

If the tool has user-visible presence:

1. Read plugins/soleur/docs/_data/site.json and check if the tool's URL is listed
2. Search plugins/soleur/docs/pages/ for references to the tool
3. Check knowledge-base/overview/brand-guide.md for the tool's handle or name

If any reference is missing, warn the user:

"This tool has public-facing presence but the docs site does not reference it yet.
Missing from: [list files]. Consider filing an issue to update the website."

If the tool has no public-facing presence (e.g., internal monitoring, CI tooling),
skip this check.
```

#### Research Insights: Precedent

The ops-provisioner already follows this exact pattern for branch safety checks (added via the worktree-gap learning). That check was added to the Setup section as a defensive guardrail. This surface check follows the same "add a check where the gap was discovered" pattern, placed in the workflow where it naturally fits -- after provisioning completes.

## Technical Considerations

- **No new code:** Both changes are markdown instruction additions to existing files
- **No new agents or skills:** This is adding checklist steps, not orchestration
- **File paths must use `plugins/soleur/docs/`**: The issue references `docs/_data/site.json` but the actual path is `plugins/soleur/docs/_data/site.json` -- the plan corrects this
- **Constitution principle alignment:** "Prefer inline instructions over Task agents for deterministic checks" (constitution.md) -- these are simple file-existence checks, not LLM analysis tasks
- **Agent prompt principle:** "Agent prompts must contain only instructions the LLM would get wrong without them" (constitution.md) -- the surface check is a reasonable addition because provisioning agents would not spontaneously check the docs site
- **No shell expansion in SKILL.md:** Constitution.md prohibits `$()`, `$VAR`, and `${VAR}` in skill markdown files. Use angle-bracket placeholders (`<platform-name>`) instead
- **site.json structure:** The current `site.json` uses flat top-level keys (`github`, `discord`). A new platform entry would follow the same pattern (e.g., `"x": "https://x.com/soleur_ai"`)
- **community.njk structure:** The Connect section uses `<a>` cards with `{{ site.<key> }}` Nunjucks template variables. A new card follows the existing Discord/GitHub pattern

### Research Insights: Simplicity Check

Per code-simplicity and YAGNI principles:
- The plan does NOT create a new validation framework -- it adds two prose sections to existing files
- The plan does NOT auto-fix missing surfaces -- it warns and suggests filing an issue
- The plan does NOT enumerate all possible surface types in the ops-provisioner -- it asks a semantic question and lets the LLM judge
- The plan avoids the "redundant validation phase" anti-pattern (learning: plan-review-catches-redundant-validation-gates) -- the check runs once after provisioning, not as a separate validation pass

## Acceptance Criteria

- [ ] `plugins/soleur/skills/community/SKILL.md` includes a "Platform Surface Check" section listing the surface files to verify after platform setup
- [ ] `plugins/soleur/agents/operations/ops-provisioner.md` includes a "Public Surface Check" phase after "Verify + Record" and before "Safety Rules"
- [ ] Both checks list correct file paths (`plugins/soleur/docs/_data/site.json`, `plugins/soleur/docs/pages/community.njk`, `knowledge-base/overview/brand-guide.md`)
- [ ] Ops-provisioner check is generic (uses a semantic question, not hard-coded to social platforms) and suggests filing a follow-up issue when gaps are found
- [ ] Community skill check is scoped to social/community platforms specifically
- [ ] Neither check blocks the provisioning workflow -- warnings only
- [ ] No `$()` or shell variable expansion in the SKILL.md additions (use angle-bracket placeholders)
- [ ] Ops-provisioner section placement is between "Verify + Record" and "Safety Rules" (maintains the Setup > Configure > Verify+Record > Surface Check > Safety flow)

## Test Scenarios

- Given a new social platform was just set up via community skill, when the platform surface check runs, then it warns if `site.json` lacks the platform URL
- Given a new SaaS tool was provisioned via ops-provisioner, when the public surface check runs and the tool has user-visible presence (e.g., analytics badge on the site), then it warns if docs pages don't reference it
- Given a new SaaS tool was provisioned that has NO public-facing presence (e.g., internal monitoring, CI tooling), when the public surface check runs, then no warning is emitted
- Given all surface files already reference the platform, when the checks run, then no warnings are emitted (clean pass)
- Given the community skill check finds missing surfaces, when it suggests filing an issue, then the suggested command uses the correct `gh issue create` syntax with a descriptive title

### Research Insights: Edge Cases

- **Partial coverage:** A platform might be in `site.json` but missing from `community.njk` (or vice versa). Each surface should be checked independently, not as an all-or-nothing gate.
- **Non-social tools in community skill:** If someone runs the community `platforms` sub-command for a non-social tool, the surface check should only fire for platforms in the community skill's platform detection table (Discord, GitHub, X/Twitter), not arbitrary SaaS tools.
- **Worktree path resolution:** The file paths in the check instructions are relative to the repo root. Since ops-provisioner already has a branch check, the paths will resolve correctly in worktrees.

## Non-Goals

- Not implementing automated file modification (the checks warn, they don't fix)
- Not creating a new agent or skill for surface checking
- Not adding shell scripts for programmatic file scanning
- Not resolving #480 (the actual X website updates) -- that is a separate PR
- Not adding the check to the `social-distribute` skill (different ownership boundary)

## Success Metrics

- Next provisioning of a user-facing tool triggers the surface check warning before the workflow completes
- Zero post-merge "forgot to update the website" issues after this lands

## Dependencies & Risks

- **Dependency on #480:** The X-specific website updates (#480) should land separately. This plan prevents future misses; #480 fixes the current one.
- **Risk: path drift.** If docs site structure changes (e.g., `site.json` moves), the hardcoded paths in the checks become stale. Mitigated by the fact that path changes are rare and would surface during normal review.
- **Risk: check fatigue.** If the warning fires too often (e.g., for every `platforms` sub-command even when no new platform was added), users will learn to ignore it. Mitigation: scope the community check to fire only after a setup script confirms a new platform is enabled, not on every sub-command invocation.

### Research Insights: Risk Mitigation

- **Path drift mitigation (enhanced):** The surface file paths exist in two places after this change (community SKILL.md and ops-provisioner.md). If a path changes, both need updating. Consider adding a comment in each file referencing the other: "Also checked in ops-provisioner.md / community SKILL.md". This is lightweight and prevents one file from going stale while the other is updated.
- **Staleness detection:** Constitution.md already mandates that "when modifying agent instructions, also update any skill Task prompts that reference the agent with hardcoded check lists." This existing rule covers the dual-update case.

## References & Research

### Internal References

- `plugins/soleur/skills/community/SKILL.md` -- community skill entry point (platform detection, sub-commands)
- `plugins/soleur/agents/operations/ops-provisioner.md` -- provisioning agent (Setup, Configure, Verify+Record phases)
- `plugins/soleur/docs/_data/site.json` -- site metadata including social links (currently has `github` and `discord`, no X)
- `plugins/soleur/docs/pages/community.njk` -- community page with Connect cards (currently Discord and GitHub only)
- `knowledge-base/overview/brand-guide.md` -- brand identity, voice, channel notes
- `plugins/soleur/docs/_includes/base.njk` -- site layout template (potential footer social links)

### Related Issues

- #481 -- This issue (add public surface parity checks)
- #480 -- Immediate fix: add X/Twitter links to website and brand guide
- #474 -- X provisioning PR that exposed the gap

### Relevant Learnings

- `knowledge-base/learnings/2026-02-22-ops-provisioner-worktree-gap.md` -- ops-provisioner previously had no branch safety check; same "missing guardrail" pattern applied here
- `knowledge-base/learnings/2026-02-12-brand-guide-contract-and-inline-validation.md` -- inline validation beats separate agents for single-document checks; supports the inline checklist approach
- `knowledge-base/learnings/2026-03-09-x-provisioning-playwright-automation.md` -- X provisioning context that exposed the gap
- `knowledge-base/learnings/2026-02-13-agent-prompt-sharp-edges-only.md` -- agent prompts should contain only what the model would get wrong without them; surface check qualifies because the model would not spontaneously check docs site
- `knowledge-base/learnings/2026-02-19-plan-review-catches-redundant-validation-gates.md` -- warns against adding redundant validation phases; this plan's checks are single-pass, not redundant
