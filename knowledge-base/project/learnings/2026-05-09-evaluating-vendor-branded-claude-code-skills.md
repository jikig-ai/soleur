---
date: 2026-05-09
category: best-practices
problem_type: integration_issue
component: brainstorm
severity: medium
tags: [skills, integration, mit-licensing, vendor-evaluation, brand-integrity, brainstorm-process]
related_artifacts:
  - knowledge-base/project/brainstorms/2026-05-09-gdpr-gate-skill-brainstorm.md
  - knowledge-base/project/specs/feat-compliance-skills-eval/spec.md
  - https://github.com/jikig-ai/soleur/issues/3502
  - https://github.com/jikig-ai/soleur/pull/3501
synced_to: [brainstorm]
---

# Evaluating Vendor-Branded Claude Code Skills for Integration

## Problem

When a third-party Claude Code skill is offered as a candidate for integration into Soleur, the question "should we vendor this?" usually gets framed as a feature/license question. Two failure modes are easy to fall into:

1. **Premature acceptance** — the repo is MIT, the README looks reasonable, the topic is in-scope, so we vendor it. We don't notice that the skill embeds vendor-marketing surface (utm-tagged links, vendor logos, "powered by" footers) inside agent output context, turning every invocation into uncompensated lead-gen for a third party and a hidden sub-processor relationship.
2. **Premature rejection or premature clean-room** — we reject the vendor framing and rebuild from scratch, re-writing 25+ language-neutral grep+fix catalogues that already exist in the candidate repo's clean files.

Concrete trigger: evaluation of `gosprinto/compliance-skills/pii-detector` (Sprinto, MIT, 2026-05-06, 69 stars). The repo has 15 files; only 2 contain Sprinto branding (`README.md` + `modes/repo-scan.md` footer). The other 13 are clean technical content.

## Solution

A four-step recon → leader → decision flow:

### 1. 30-second cheap recon BEFORE spawning agents

Use `gh api repos/<owner>/<repo>/contents/<path>` to enumerate the repo and read the entry-point SKILL.md, README, and license. Note: created date, last push, license, and explicit jurisdiction/regulation scope.

```bash
gh repo view <owner>/<repo> --json name,description,licenseInfo,pushedAt,createdAt,stargazerCount
gh api repos/<owner>/<repo>/contents --jq '.[] | "\(.type)\t\(.name)\t\(.size)"'
gh api repos/<owner>/<repo>/contents/<dir>/SKILL.md --jq '.content' | base64 -d
```

This costs 30 seconds and surfaces three decision-grade signals: (a) explicit jurisdiction/regulation scope, (b) repo age + activity (new repos = unstable contracts), (c) entry-point trigger phrases that hint at vendor framing.

### 2. Pre-leader summary

Before spawning expensive domain leaders (CPO/CLO/CTO/CMO), share concise findings from the cheap recon with the user. This shapes the brainstorm scope and prevents wasted leader context. Per AGENTS.md `wg-zero-agents-until-user-confirms`, this is the right cycle order anyway.

### 3. Domain-leader assessment for user-brand-critical scope

When the candidate touches credentials/auth/data/payments/legal posture, set `USER_BRAND_CRITICAL=true` and spawn CPO + CLO + CTO + CMO in parallel ahead of other specialists. Each leader gets a sharp, scoped prompt and 200-400 word budget. Plus a separate general-purpose agent doing a deep file-by-file inventory of the candidate repo (with explicit instructions to enumerate vendor-surface contamination per file, not just at the README level).

### 4. Decision matrix with three options, not two

Always present three approaches:

| Option | When it wins |
|---|---|
| **A) Inspiration only / clean room** | Candidate repo is heavily contaminated, US-only or otherwise jurisdiction-misaligned, OR <40% files are clean |
| **B) Lift specific files under MIT attribution** ⭐ usually wins | ≥80% files are clean technical content; vendor surface is localized to 1-3 files; license permits attribution |
| **C) Fork and extend** | Almost never wins for vendor-branded repos — pulls in recurring scrub debt on every upstream change |

For Option B, the attribution cost is one `NOTICE` file + a one-line header per lifted file: `<!-- Adapted from <upstream> (MIT) — see NOTICE -->`.

## Key Insights

1. **Vendor-surface contamination is usually localized.** In the Sprinto case, 13 of 15 files were clean. The marketing surface lived in the README and the repo-scan output footer. Don't reject the whole repo because of the README.

2. **Trigger-phrase + field-name + file-types in skill description is a clean pattern worth borrowing** even when the candidate skill is rejected. The shape (auto-trigger lexicon in frontmatter `description:`) is jurisdiction-neutral.

3. **"Layer-loading on demand" via `references/` keeps SKILL.md small.** Sprinto's load-only-relevant-files-for-the-task model maps directly onto Soleur's `plugins/<plugin>/skills/<skill>/references/` convention. Lift the shape regardless of whether you lift the contents.

4. **"Weave, don't append"** is the highest-value design idea in Sprinto's repo: planning-mode output enriches the natural agent response rather than producing a standalone "compliance theater" appendix. Worth borrowing wholesale into any Soleur gate skill.

5. **MIT attribution overhead is trivial** — `NOTICE` file + 5 one-line headers — relative to 3-5 days of catalogue-writing. Don't let "we don't want a dependency" rhetoric force a clean-room rebuild that wastes engineer-days.

6. **Vendor-branded skills can create undisclosed sub-processor relationships.** When a skill includes utm-tagged links to vendor analytics, operator prompt context (potentially containing PII field names, schema fragments) could leak to the vendor. CLO/legal-audit must surface this as a DPA chain question, not just a brand-integrity question.

## Session Errors

1. **`git -C <worktree-path> status` failed** with "fatal: cannot change to '<path>': No such file or directory" — ran from inside the worktree, treating the absolute-from-bare path as relative-from-cwd. **Recovery:** verified `pwd` first. **Prevention:** when running `git -C` from a worktree, use absolute paths or just drop `-C` since the worktree is already the cwd.

2. **`gh milestone list --state open` failed** with "unknown command milestone for gh". **Recovery:** used `gh api repos/<owner>/<repo>/milestones --jq '.[] | "\(.number) | \(.title) | \(.state)"'` instead. **Prevention:** the `gh` CLI has no `milestone` subcommand — use the REST API. Worth a one-line addition to a skill cookbook.

3. **`AskUserQuestion` rejected first call** with "required parameter `questions` is missing" — sent without `questions` param. **Recovery:** retried with full schema. **Prevention:** harness-deferred tool schemas need to be loaded via `ToolSearch` before first call. Consider preloading `AskUserQuestion` schema at brainstorm Phase 0.

4. **CLO subagent reported a learning-file path that doesn't exist** — I cited `knowledge-base/project/learnings/best-practices/2026-04-18-compliance-runbook-authoring-gotchas.md` from a stale `find` listing, but the file isn't at that path. **Recovery:** subagent flagged for verification rather than guessing. **Prevention:** when citing learning paths to subagents, verify with `ls`/`test -f` first or pass a glob pattern (`find knowledge-base/project/learnings -iname '*compliance-runbook*'`) instead of an exact filename.

5. **Recurrence (2026-05-10, brainstorm of #2719):** CLO subagent reported THIS file (`2026-05-09-evaluating-vendor-branded-claude-code-skills.md`) does not exist on disk; the orchestrator propagated the claim into the brainstorm document; compound-time `ls` from the orchestrator's worktree-root verified the file exists. The subagent's CWD or path-resolution produced a false negative. **Recovery:** corrected brainstorm Q5 + workflow-gap section. **Prevention:** brainstorm SKILL.md Phase 1.1 verification rule extended (2026-05-10) to cover file-existence claims, not just symbol-mounted claims. Independent `ls <absolute-worktree-path>` is mandatory before propagating subagent file-existence negatives.

## Prevention

- **Brainstorm skill Phase 1.0 / 1.1:** when the feature description contains a URL to a third-party repo, run the 30-second `gh api` recon BEFORE spawning leaders. Surface jurisdiction scope + vendor-surface contamination explicitly to the user as part of the pre-leader summary. (See routing proposal below.)

- **Compound skill Phase 0.5:** the `AskUserQuestion`-schema-not-loaded class of error is recurrent. Worth a one-line note in the brainstorm SKILL.md Phase 1.2 reminding to `ToolSearch select:AskUserQuestion` before the first call if schema isn't already loaded.

- **General CLI cookbook:** add to a Soleur reference (or AGENTS.md `Reference & Feedback` section) that `gh milestone` does not exist; milestones are accessed via `gh api repos/<owner>/<repo>/milestones`.

## Cross-References

- Brainstorm doc that produced this learning: `knowledge-base/project/brainstorms/2026-05-09-gdpr-gate-skill-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-compliance-skills-eval/spec.md`
- Tracking issue: #3502
- Draft PR: #3501
- Related compliance posture: `knowledge-base/legal/compliance-posture.md`
- Related learnings:
  - `knowledge-base/project/learnings/2026-03-10-first-pii-collection-legal-update-pattern.md`
  - `knowledge-base/project/learnings/2026-02-21-gdpr-article-30-compliance-audit-pattern.md`
  - `knowledge-base/project/learnings/best-practices/2026-04-28-sentry-payload-pii-and-client-observability-shim.md`
