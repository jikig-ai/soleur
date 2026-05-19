---
title: Button-stub title "Wires in PR-X" is not evidence PR-X wired the handler — verify before brainstorm scope
date: 2026-05-19
category: brainstorm-workflow
related:
  - 2026-04-17-brainstorm-verify-existing-artifacts-and-mount-sites.md
  - 2026-05-13-brainstorm-grep-cited-flag-symbol-against-main-before-spawning-leaders.md
  - 2026-05-15-brainstorm-enumerate-umbrella-child-prs-before-leader-spawn.md
tags:
  - brainstorm
  - premise-validation
  - stub-detection
---

# Button-stub title "Wires in PR-X" is not evidence PR-X wired the handler

## Pattern

During PR-H (trust-tier external classes) brainstorm, the operator's framing assumed PR-G (#3984, merged 2026-05-19) had wired the Send/Edit/Discard buttons on `today-card.tsx`. Evidence cited: PR-F's PR body said "PR-G (#3947) gates cohort exposure and wires the action-class flow" + the stub buttons in `today-card.tsx:48-73` carried `title="Wires in PR-G (#3947)"`.

Premise-validation by grep (Phase 1.0.5):

```bash
# Confirm handler files exist (operator's framing implies they do)
find apps/web-platform/app/api/dashboard/today -name "route.ts"
# Returns ONLY app/api/dashboard/today/route.ts (the GET-list route from PR-F).
# No app/api/dashboard/today/[id]/{send,edit,discard}/route.ts exist.

# Confirm buttons are wired
grep -n 'onClick\|formAction' apps/web-platform/components/dashboard/today-card.tsx
# Returns nothing. Buttons still carry disabled + aria-disabled + title="Wires in PR-G (#3947)".
```

PR-G shipped the scope-grants substrate, audit viewer, 3-radio UI, and ~30 files of legal/onboarding work — but did NOT ship the Send/Edit/Discard handlers despite the button-title claim. The stub-title was a *prediction* embedded by PR-F's review (`Review P2-2`) about where the wiring would land, not a *commitment* PR-G honored.

## Why it almost broke the brainstorm

If the brainstorm had accepted the operator's framing (PR-H = "extend registry to 2 deferred classes"), PR-H would have shipped a 12-entry action-class registry with no end-to-end demo path — the cohort would see drafts they cannot Send. A 30-second `find` at Phase 1.0.5 expanded PR-H scope to include the Send/Edit/Discard wiring + typed-confirm modal, which became the load-bearing demo path.

## Rule

**When a component carries a stub `title="Wires in PR-N"` or comment `// TODO: wire in PR-N` AND the brainstorm references the same PR-N as already-shipped, ALWAYS:**

1. Grep for the handler file/symbol the stub references.
2. Cross-check against `gh pr view N --files` for the merged-PR's actual file diff.
3. If the handler file is missing from the merged PR, treat the wiring as DEFERRED, not done. The stub title is reviewer-time speculation, not implementation evidence.

This pattern is distinct from (but stacks with):
- `2026-05-13-brainstorm-grep-cited-flag-symbol-against-main-before-spawning-leaders.md` (cited flag still present in main).
- `2026-05-15-brainstorm-enumerate-umbrella-child-prs-before-leader-spawn.md` (which umbrella children actually shipped).
- `2026-04-17-brainstorm-verify-existing-artifacts-and-mount-sites.md` (broader mount-site verification).

This learning is more specific: a UI stub embedded with a *future* PR reference is a different signal than a *past* PR reference. The forward reference is a prediction; only the past reference is evidence.

## Tactical addition for brainstorm skill

Phase 1.0.5 should add: "If the feature description's framing assumes prior-PR-X wired a UI handler (stub buttons, disabled controls, TODO-PR-X comments), grep main for the handler symbol BEFORE accepting the framing. PR-X may have shipped without honoring the forward-reference stub."

## Concrete failure mode this would catch

PR-G shipped the title `"Wires in PR-G (#3947)"` on `today-card.tsx` buttons via PR-F. PR-G's body did not retract the prediction. PR-G's merge closed #3947 but did not flip the button-disabled state. A brainstorm of PR-H that accepts the operator's "PR-G shipped audit viewer, 2 classes deferred" framing without checking the button state will scope PR-H to 4 of 5 classes when 5 of 5 are reachable end-to-end if Send/Edit/Discard wiring is included.

## Cost of catching late

Detection at Phase 1.0.5 (this session): 30 seconds of grep, ~5 minutes of triad re-prompt with the corrected scope.
Detection at Phase 5 (/work execution): full PR-H plan invalidates, 1-3 days of work re-scoped, draft PR's empty commit becomes the wrong baseline.
Detection at Phase 6 (PR review): 9-agent multi-agent review would catch it (`user-impact-reviewer` would flag "PR-H ships a registry the founder cannot exercise"), but the cost is a near-merge unwind.

Phase 1.0.5 is the right catch surface.
