---
date: 2026-07-17
issue: 6589
pr: 6582
tags: [postmerge, verification, acceptance-criteria, closes-after-apply, silent-drop]
category: workflow-patterns
---

# On a "Closes-after-apply" issue, verify every AC line-item against live state — the PR's own issue-flow summary can silently drop AC items

## The situation

`/soleur:go 6589` routed to `soleur:postmerge`, not `fix`/`implement`: #6589's
implementation (PR #6582) had already merged, and the issue was deliberately held
OPEN on a **Closes-after-apply** gate (*"stays open until the post-merge apply
proves the destroy green"*). The gating `apply-sentry-infra` run was green, so the
naive move is: gate satisfied → close.

## The trap

PR #6582's own body summarized its issue flow as *"Closing 1 (#6589, post-apply),
filing 4"*. Taken at face value, that reads as "#6589 is fully done." It was not.

#6589 **AC5** named **four** monitors to destroy. Checking each against **live
Sentry**, not against the PR's prose:

- `ghcr-token-minter` → destroyed by the full-root apply ✅ (the proof-of-work)
- uptime `1422253` → operator re-ruled **keep + import** → split to #6606 ✅
- `scheduled-ux-audit` → **still live, still in `cron-monitors.tf`, no follow-up** ❌
- `scheduled-architecture-diagram-sync` → **same** ❌

Two of four AC destroys were silently dropped. The PR's "filing 4" list covered
finance/tooling/uptime-import/drift-coverage — none of them these two. Nothing in
the merge, the CI, or the PR summary flagged the gap; only reconciling **each AC
bullet against the live monitors API** surfaced it.

## The fix / the rule

Post-merge verification of a Closes-after-apply issue must **enumerate the linked
issue's acceptance criteria and check each against live/observable state** —
treat the PR author's "what I closed / what I filed" summary as a *claim to
verify*, exactly like `hr-verify-repo-capability-claim-before-assert` and the
"issue-archaeology is a claim" learning. A green gating apply proves the
*mechanism*; it does not prove every AC line-item was exercised.

Concretely, before closing:
1. Pull the AC list from the issue body.
2. For each item, read the **live** source of truth (Sentry API, billing API,
   file on `main`), not the PR narrative.
3. Any AC not met and not tracked by an open follow-up → **file the follow-up
   first** (#6618 here), then close. Never let a green gate paper over a dropped
   AC.

Outcome: #6589 closed correctly (all load-bearing ACs green — cap $75 live,
footgun fixed + proven, drift-guard preserved, ledger corrected), with the two
dropped destroys tracked in #6618 instead of vanishing.

## See also

- `knowledge-base/project/learnings/2026-07-16-issue-archaeology-is-a-claim-verify-against-the-pr-that-made-the-state.md`
- `hr-verify-repo-capability-claim-before-assert`
