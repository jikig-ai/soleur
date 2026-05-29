---
title: "Flipping a globally-referenced constant requires grepping CONSUMERS that ASSERT the old value, not just declaration sites"
date: 2026-05-29
category: best-practices
tags: [seo, sweep-class, ci-gate, cross-consumer, plan-quality, eleventy, canonical-host]
branch: feat-one-shot-gsc-coverage-indexing
pr: 4573
---

# Learning: canonical-constant flips have ASSERTING consumers outside the declaration scope

## Problem

PR #4573 flipped the soleur.ai docs canonical host `https://www.soleur.ai` → bare apex
`https://soleur.ai` (live infra had inverted to www→apex; GitHub Pages enforces the CNAME
apex). The plan's AC12 scoped the `www.soleur.ai` sweep to `plugins/soleur/docs` +
`eleventy.config.js` — the **declaration/emission** sites. That sweep was complete and
correct for what it covered.

But a globally-referenced constant has two kinds of references:
1. **Emission sites** — code that *produces* the value (site.json `url`, robots.txt Sitemap
   line, feed base, the APEX_RE rewriter). The plan enumerated these.
2. **Asserting consumers** — code that *checks for / depends on* the OLD value. The plan did
   NOT enumerate these, and three of them only surfaced at /work and /review:
   - **`.github/workflows/deploy-docs.yml` "Apex-host canonical gate"** — a CI step that
     **failed the build if rendered output contained _apex_ host refs** (added by #3296 when
     www was canonical). After the flip every page uses apex, so this gate would have failed
     the post-merge deploy 100%. It had to be *inverted* (now fails on www leaks), not just
     left alone. Caught at /work by reading the workflow.
   - **`plugins/soleur/test/marketing-content-drift.test.ts`** — asserted JSON-LD `@id` ==
     `https://www.soleur.ai/#organization`. These derive from `site.url`, so the build now
     emits apex and the test failed. Caught at /work by the full-suite exit gate.
   - **`apps/web-platform/infra/seo-rulesets.tf` + `sentry/uptime-monitors.tf`** — Cloudflare
     IaC still encoding www-canonical (9 redirect rules + uptime probe). Pre-existing drift,
     scoped out as #4577. Caught at /review by 3 independent agents.

## Root Cause

A plan that flips a constant naturally enumerates the *emission* sites (where you change the
value) because those are what the author edits. The *asserting consumers* (CI gates, tests,
IaC, downstream services that hardcode or check the old value) are invisible to a
declaration-scoped grep and to plan-time reasoning, because they live in unrelated
directories and frame the value as a precondition rather than a definition.

The `deploy-docs.yml` gate is the sharpest instance: a CI gate that asserts the OLD value
will *pass on main* (old value still live) and *fail only after the flip merges* — i.e., it
fails the deploy, not the PR. The full-suite exit gate caught the test; reading the workflow
caught the gate; multi-agent review caught the IaC.

## Solution / Generalizable Rule

When flipping a globally-referenced constant (canonical host, env var name, enum value,
taxonomy ID, API base URL), run a **whole-repo grep for the OLD value** — NOT scoped to the
declaration directory — and triage every hit into:
- **emission site** → flip it (the plan's sweep);
- **asserting consumer** (CI gate `if grep ... <old>`, test `expect(...).toBe(<old>)`, IaC
  encoding `<old>`, downstream hardcode) → flip the ASSERTION direction, or scope-out with a
  tracking issue if it's a separate (e.g. infra-apply) surface;
- **third-party / unrelated** (`www.flagsmith.com`, `docs.github.com`) → leave.

Cheapest gate at /work-start: `git grep -n "<old-value>" -- ':!_site' ':!*/node_modules/*'`
across the WHOLE repo, then for any CI-workflow or `*.test.*` hit, ask "does this assert the
old value?" The full-suite exit gate (`test-all.sh`) reliably catches asserting *tests*; it
does NOT catch asserting *CI gates* (they only run post-merge) or *IaC* (never executed in
CI) — those need an explicit read of `.github/workflows/**` and `infra/**` for the old value.

## Key Insight

"The sweep is complete" must mean complete over CONSUMERS, not over declaration sites. A
constant's most dangerous reference is a gate that asserts its OLD value: it stays green
until the flip lands, then fails the thing the flip was supposed to fix.

## Session Errors

1. **Planning subagent returned 529 Overloaded twice (0 tool uses)** — Recovery: retried; 3rd attempt succeeded after the prior attempts' ~200s each elapsed. Prevention: transient server-side overload; retry-on-529 is the correct behavior, no workflow change warranted.
2. **`git stash list` denied by the stash-block hook during work Phase 0.5 pre-flight** — Recovery: re-ran the pre-flight checks without `git stash list`. Prevention: the `work` skill's Phase 0.5 step 4 prescribes `git stash list`, but `hr-never-git-stash-in-worktrees` is enforced by a hook that denies even the read-only `list` subcommand. The work skill should use a non-`stash` probe (e.g., check for `refs/stash` via `git rev-parse --verify --quiet refs/stash`) or drop the check in worktrees.
3. **Foreground `sleep 90` blocked by the chained-sleep guard** — Recovery: retried the agent directly. Prevention: wait on background tasks via run_in_background + completion notification, never a foreground sleep.
4. **`ZSH_VERSION: unbound variable` from the review classification predicate under `set -uo pipefail`** — Recovery: read the changed-file list directly (source files were unambiguous) and classified manually as `code`. Prevention: the predicate's `set -u` trips on the shell snapshot; guard with `${ZSH_VERSION:-}` or run the predicate in a clean subshell.
5. **Edit rejected "File has not been read yet" on validate-seo.sh** — Recovery: used the Read tool then Edit. Prevention: reading a file via Bash/sed does not satisfy the Edit tool's read-gate; always use the Read tool before Edit.
6. **`gh issue create` blocked for missing `--milestone`** — Recovery: re-ran with `--milestone "Post-MVP / Later"`. Prevention: the require-milestone guardrail is mandatory; default operational issues to "Post-MVP / Later".
7. **Edit "File has been modified since read" on tasks.md** (after a prior `sed -i` mutation) — Recovery: re-read then edited. Prevention: after mutating a file with `sed -i`, re-Read before using the Edit tool on it.

## Tags
category: best-practices
module: seo-aeo / eleventy-docs / ci-gates
