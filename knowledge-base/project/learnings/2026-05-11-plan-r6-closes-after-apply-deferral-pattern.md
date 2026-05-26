---
title: When a plan's Risks section names a Closes-after-apply deferral, default commit + PR body to Ref-not-Closes
date: 2026-05-11
category: best-practices
tags: [workflow, github, plan-fidelity, pr-body, auto-close]
related_issues: [3060, 3049, 3185]
related_prs: [3551]
---

# Plan §R6 "Closes-after-apply" deferral: commits + PR body default to `Ref #N`

## Problem

PR #3551's plan §R6 specified:

> use `Ref #3060` in PR body and run `gh issue close 3060` manually after PM1 confirms success.

The reasoning: #3060's acceptance criterion is "after first scheduled run completes successfully, link the run and close." Auto-closing on merge fires the closure BEFORE the first nightly run proves green — a `Closes #N` keyword anywhere in the PR title/body triggers GitHub's auto-closer at merge time, decoupled from whether the closure-condition is actually met.

In the initial work-phase commit I wrote `Closes #3060` on a standalone body line. Strictly speaking that does NOT violate `wg-use-closes-n-in-pr-body-not-title-to` (the rule permits `Closes #N` on its own body line for *intentional* closure), but it violated the plan's explicit R6 conservatism. Caught pre-push during a self-audit of the commit message against R6; amended to `Ref #3060` + "Manual close after PM1 confirms first green run".

## Solution

When a plan's `## Risks` section names an explicit "Closes-after-apply" deferral pattern — issue stays open until post-merge PM verification (workflow trigger, manual run, deploy green, etc.) confirms the closure-condition — the work-phase commit-message AND the PR body should default to:

```
Ref #N — <one-line description; manual close after PM<X> confirms <event>>
```

The reader sees the intent (this PR addresses #N) without firing GitHub's auto-closer. Manual `gh issue close N --comment "<run URL>"` follows after PM verification.

Promotion path from `Ref` → `Closes`:
- Only after the PM step in the plan's Acceptance Criteria fires green.
- Always done as a separate `gh issue close` invocation, never by editing the PR body post-merge.

## Why this generalizes

Most plans don't carry an R6-like clause. The default for issues this PR fully resolves is `Closes #N` on a body line (per `wg-use-closes-n-in-pr-body-not-title-to`). The R6 pattern is reserved for issues where the merge-event ≠ the closure-event:

- CI workflow PRs where the first scheduled run is the proof artifact.
- Infrastructure PRs that need terraform-apply / deploy verification before being safely "done."
- Migration PRs where the post-deploy data-integrity check is the closure signal.
- Ops-remediation PRs where the live-system check (curl probe, dashboard query) is load-bearing.

The cost of getting it wrong is one of: (a) an issue auto-closed before the proof artifact lands, leaving an invisible gap if the proof step actually fails; (b) a closed issue resurrected via re-open after the failure is detected, polluting the issue history and obscuring whether the closure actually meant "verified" or "wishfully linked."

## Detection heuristic for `soleur:work`

When `soleur:work` composes commit messages from a plan, scan the plan's `## Risks` (or `## Sharp Edges`) section for the phrases:
- `Closes-after-apply`
- `manual close after`
- `Ref #N` + `close manually`
- `wg-use-closes-n-in-pr-body-not-title-to` (the rule that triggers it)
- `ops-remediation` plan type with explicit per-PM closure-link

If any match, default the commit body's issue references to `Ref #N` and emit a one-line WARN: "Plan §R<X> defers closure pending PM verification — using `Ref #N` instead of `Closes #N`. Manually close post-merge." The author can override explicitly with `--closes-now` on the work-phase commit prompt.

Equivalently in `soleur:ship`'s PR-body composition: scan the plan for the same triggers before promoting `Ref` to `Closes` in the auto-generated PR body.

## Related

- Rule `wg-use-closes-n-in-pr-body-not-title-to` — the underlying auto-close-keyword scanner; this learning is the conservative subset.
- Issue #3185 — the precedent: same issue auto-closed twice in 3 days from title + body checkbox keywords; this is the milder cousin (correct keyword, wrong timing).
- Learning `2026-04-24-pr-body-ref-not-closes-for-ops-remediation` — ops-remediation pattern that anchors R6's conservatism.

## Session Errors

- **Initial commit message used `Closes #3060` instead of `Ref #3060`.** The plan §R6 explicitly directed the deferral but the commit-message draft used the more common `Closes` form. **Recovery:** caught during a final pre-push read-through of the commit message against the plan; `git commit --amend` with corrected wording before pushing. **Prevention:** the soleur:work skill should detect the R6 pattern in plan §Risks and default to `Ref #N` in commit messages, requiring explicit override to promote to `Closes`. Proposed as a soleur:work Sharp Edges item; route via compound's Route Learning to Definition.

- **PreToolUse Write hook blocked first workflow write with generic security advisory.** The advisory listed `github.event.*` injection risks, but the workflow consumes no such inputs. **Recovery:** retried Write with identical content; second attempt succeeded. **Prevention:** the hook is correct-by-design — advisory + first-write-block forces the agent to re-read the security guidance and validate the workflow is safe. Behavior is working as intended; no rule change warranted.
