---
title: Plan-time grep ACs must exclude meta-docs; cited identifiers must come from source
date: 2026-05-20
category: best-practices
tags: [plan-quality, acceptance-criteria, deepen-plan, verification, grep, terraform]
issue: 4159
pr: 4160
---

# Plan-time grep ACs must exclude meta-docs; cited identifiers must come from source

## Problem

PR #4160 (a 4-line docs-fix swapping a wrong Inngest verification hostname `web-platform.soleur.ai` → `app.soleur.ai`) produced two distinct plan-quality regressions, both caught downstream of the plan/deepen phase:

1. **AC1 self-contradiction.** The plan asserted:
   ```
   AC1. grep -rE 'web-platform\.soleur\.ai' knowledge-base/ returns no lines (exit code 1).
   ```
   But the fix plan and `tasks.md` themselves mention the literal bad string ~10 times in prose describing the rename. Post-edit, the literal AC fails — the grep returns the meta-documentation. The work phase had to add an exclude-workaround in tasks.md; review (code-quality-analyst) flagged the residual contradiction in the plan; the inline review fix amended AC1 to:
   ```
   grep -rE 'web-platform\.soleur\.ai' knowledge-base/ \
     --exclude-dir=feat-one-shot-runbook-hostname-4159 \
     --exclude=2026-05-20-fix-runbook-inngest-hostname-app-soleur-ai-plan.md
   ```

2. **Misnamed Terraform identifier.** The plan cited the canonical hostname source as `apps/web-platform/infra/variables.tf:88` (`app_subdomain` default). The variable's actual name at lines 85-89 is `app_domain`. The wrong identifier propagated from the issue body (which contained the same typo) into 4 plan locations: Research Reconciliation row 2, Test Strategy paragraph, R3 risk row, and Plan-time verifications #1. Caught at review by git-history-analyzer AND code-quality-analyst independently.

Neither defect changed the *outcome* (hostname swap was still correct), but both eroded the plan's role as authoritative reference and required +1 commit at review.

## Root Cause

Both defects share a single cause: **plan-time prose copied claims from upstream (issue body, mental tally) without re-verifying against the source on disk**.

- For AC1: the deepen-pass added a Substring-Collision Audit and tightened AC4 with `git diff --name-only main...HEAD | sort`, but did NOT mentally run the AC1 grep against the as-written plan + tasks.md to notice the self-reference. The prose `## Implementation` block correctly described "no other text legitimately contains `web-platform.soleur.ai`" while the AC1 grep would clearly match the plan's own prose.
- For the variable name: the issue body cited `app_subdomain`. Plan-time verification step #1 said "Read `apps/web-platform/infra/variables.tf:88`" — but the writer apparently confirmed the *default value* (`app.soleur.ai`) without re-reading the variable's name on the same line.

## Solution

**Two complementary plan-time gates:**

### Gate 1: grep-AC scope must exclude meta-docs by construction

Any acceptance criterion that runs a grep over a scope that *contains the plan itself or its companion `tasks.md`* must include `--exclude-dir`/`--exclude` flags for those paths up front. The minimum form for any plan under `knowledge-base/project/plans/` with a paired spec under `knowledge-base/project/specs/feat-<name>/`:

```bash
grep -rE '<pattern>' knowledge-base/ \
  --exclude-dir=feat-<name> \
  --exclude=<plan-basename>.md
```

Apply this when the AC's scope contains markdown surfaces that quote the search pattern (string-rename ACs, doc-cleanup ACs, "no references to X" assertions). For surgical-source ACs that grep over `apps/` or `plugins/scripts/` only, the meta-doc exclusion is unnecessary — the meta-docs live elsewhere.

### Gate 2: identifier citations must come from the source file, not upstream prose

When the plan cites a code identifier (Terraform variable name, function name, schema column, env-var name, RPC name, etc.) and attributes it to a specific file:line, plan/deepen must:

1. Read the exact line range (e.g., `variables.tf:85-89`, not just `:88`).
2. Quote the declaration form (`variable "app_domain" { ... }`) — not the default value alone.
3. Treat any identifier name appearing in the issue body or upstream PR as a hypothesis to verify, not a fact to copy.

The deepen-pass is the natural enforcement point — it already does verification grep work; adding a "cited-identifier sweep" step (grep each backticked snake-case identifier in the plan against the file/line it cites) costs ~30 seconds.

## Session Errors

1. **Plan AC1 self-contradiction.** Plan said grep returns 0 lines, but plan + tasks.md retained the literal bad string. Recovery: tasks.md gained `--exclude-dir`/`--exclude` flags at work phase; plan AC1 amended at review phase to match. Prevention: deepen-plan should auto-add meta-doc exclusions for grep ACs whose scope contains the plan/spec directories.
2. **Plan misnamed Terraform variable as `app_subdomain` (canonical: `app_domain`).** 4 mentions across plan body. Caught at review by git-history-analyzer + code-quality-analyst. Recovery: 1-line review commit corrected all 4. Prevention: deepen-plan should treat issue-body-cited identifiers as hypotheses and re-verify against the source file's declaration form, not just the default value.

## Key Insight

Plan-time AC text is **executable prose**: if a future operator (or `/work`) runs the literal command in the AC, it must succeed. Plans that pass their own ACs only via an unwritten exclusion rule are self-inconsistent. Same class as `2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md`: plan-quoted numbers/strings/identifiers are preconditions to verify, not facts.

## Tags

category: best-practices
module: plan, deepen-plan
related: [[2026-05-10-handshake-schema-drift-and-stale-precondition-budgets]], [[2026-04-29-docs-fix-verification-greps-must-span-operator-surfaces]]
