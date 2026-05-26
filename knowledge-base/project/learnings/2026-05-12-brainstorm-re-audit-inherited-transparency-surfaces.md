---
title: Brainstorms inheriting transparency surfaces from an umbrella must re-audit the audience assumption
date: 2026-05-12
category: best-practices
tags: [brainstorm, yagni, scope-challenge, transparency, banner, threshold-carry-forward, pre-public]
ref-pr: 3653
ref-issues: [3603, 3659, 3660]
related-learnings:
  - 2026-05-11-runtime-advisory-banners-must-gate-on-judgment-relevance.md
  - 2026-03-20-ci-job-change-detection-yagni-when-path-filtered.md
  - 2026-05-11-bundle-brainstorm-deliberate-revert-and-fixture-source-record.md
---

# Brainstorm: re-audit inherited transparency surfaces when the umbrella shaped scope for a different audience

## Problem

The PR-B brainstorm for #3603 inherited a two-part scope from the umbrella brainstorm: an inline cohort marker AND a 30-day dismissible rollout banner. The umbrella authored both under USER_BRAND_CRITICAL with `brand_survival_threshold: single-user incident`, because PR-A's adjacent write-path stakes drove the framing.

Two of those inherited choices nearly shipped untested for PR-B's actual scope:

1. **Banner audience.** The rollout banner exists to disclose a recently-fixed bug to a user population that may have seen it. At PR-B brainstorm time (2026-05-12), Soleur had zero external users — the entire affected cohort was reachable by direct comms (Slack, email). A chat-surface banner is the wrong instrument for that audience: it is less honest than direct outreach, more impersonal, and adds permanent code surface (component, dismiss-persistence, sunset constant, regression test) for a 30-day affordance no one needs.

2. **Threshold inheritance.** USER_BRAND_CRITICAL was correct for PR-A1/A2 (write-path, cross-tenant blast radius, Art. 33 surface). PR-B is read-only SELECT on already-RLS'd rows with no new attack surface, no Art. 33 notifiable event, no cross-tenant risk. A botched marker is correctable within hours by a copy/style PR; a botched persistence layer is not. Mechanically carrying the umbrella's threshold would have triggered redundant GDPR-gate plumbing and a heavier review burden for code that does not warrant it.

The user surfaced both issues by asking the right one-line questions ("Do we really need a banner if we have no external users?"). The brainstorm initially proposed the inherited scope unchallenged — the CPO focused-refresh challenged the threshold (good) but kept the banner (miss).

## Solution

When a per-PR brainstorm inherits transparency/disclosure/UX surfaces from an umbrella brainstorm, treat the inherited scope as one prior approach among several — not as a default. Add two explicit re-audit prompts at Phase 0.5 or Phase 1.2:

1. **Audience re-audit (banner/disclosure surface).** "The umbrella prescribes a [banner/banner+marker/blast notification]. The audience for that disclosure surface is [X]. Is X reachable by a cheaper, more honest channel today (direct comms, in-product onboarding, a dedicated email)? If yes, the banner is YAGNI for this PR even if the umbrella spec listed it." This question MUST be asked when the brainstorm has an external-user count axis in its product context (pre-public vs post-launch).

2. **Threshold re-audit (USER_BRAND carry-forward).** "The umbrella set `brand_survival_threshold: [X]`. The umbrella's choice was driven by [vector Y]. Does vector Y apply to THIS PR's surface (read-only vs write, new persistence vs render-only, new compliance surface vs existing)? If no, downgrade one tier and document the rationale." This is already implied by the rule at `hr-weigh-every-decision-against-target-user-impact`, but the brainstorm-time enforcement should be explicit at the focused-refresh prompt sent to the relevant domain leader (CPO in PR-B's case).

Both questions are zero-cost: they're a single sentence in the leader's prompt. The downside of mechanically carrying inherited scope is real (one extra component shipped, redundant GDPR-gate cycles); the downside of asking the question and confirming inheritance is one extra paragraph in the leader's response.

For PR-B specifically, the audit produced: banner dropped (DEC1 in the brainstorm), threshold downgraded to `high-confidence-correctable` (DEC2). Both decisions were documented as deferred-scope-out issues with concrete re-evaluation criteria (#3659 banner — revisit when external-user count > 0; #3660 rail-level affordance — same trigger).

## Key Insight

**An umbrella brainstorm's scope is a hypothesis for each child PR, not a directive.** The umbrella optimizes for the highest-stakes PR in the sequence (in #3603, that was PR-A's write path). Carrying that framing mechanically into a downstream PR over-engineers the downstream PR and dilutes the umbrella's signal. The brainstorm-time question "does this still apply at THIS PR's scope?" is cheaper than the alternative: discovering during plan/work/review that an inherited rule made the PR too heavy and unwinding it.

The companion pattern from `2026-05-11-runtime-advisory-banners-must-gate-on-judgment-relevance.md` is structural cousin: "fire the banner only when the gate is actually judging the regulated path." Both patterns reduce to the same principle — *signal-relevance gating*. A signal that fires when irrelevant trains the receiver to ignore it; a scope decision that fires when irrelevant trains the team to ignore the scope process.

## Tags

category: best-practices
module: brainstorm-skill, umbrella-to-prB-inheritance, threshold-carry-forward

## Session Errors

- **Initial CWD confusion when reading the umbrella brainstorm.** A prior `cd` into the PR-A2 worktree carried over my shell state; I attempted to read the umbrella brainstorm via a bare-relative path from `/home/jean/git-repositories/jikig-ai/soleur` (the bare repo root, which has no working tree). The Read failed with "File does not exist." **Recovery:** read via the PR-A2 worktree's absolute path. **Prevention:** before reading working-tree files at session start, explicitly `pwd` and prefix all Read paths with the worktree absolute path — bare relative reads are the silent failure mode for `hr-when-in-a-worktree-never-read-from-bare`.

- **Local main was stale at session start.** I ran `git worktree list` and `git log main` without first fetching. The local main pointer was at PR-A1's merge commit and did NOT reflect PR-A2's merge that had landed 2.5 hours earlier. Had the user not corrected me ("PR-A2 just merged, can you recheck"), I would have proposed a brainstorm-only worktree from stale main, missing PR-A2's helpers. **Recovery:** ran `git fetch origin main` and re-read `origin/main`. **Prevention:** the session-start preamble at `wg-at-session-start-run-bash-plugins-soleur` runs `worktree-manager.sh cleanup-merged` but does NOT `git fetch origin main` for the bare repo. Adding `git fetch origin --quiet` to the session-start preamble (or to brainstorm Phase 0) would have closed this gap. Filed as workflow proposal below.

- **CPO agent first invocation hit a transient rate-limit.** The first Task spawn returned `API Error: Server is temporarily limiting requests · Rate limited` within 2 seconds, with zero tokens consumed. **Recovery:** retried the same prompt 30 seconds later; second invocation succeeded. **Prevention:** transient and not workflow-related; document as a known-flake. Brainstorm skill could note this pattern in Sharp Edges so future runs do not interpret a 2-second zero-token agent failure as a real-content rejection.

- **Date-math interpretation error in initial agent prompts.** When drafting the spec-flow-analyzer + CPO prompts, I quoted the rollout banner window as 2026-05-05 → 2026-06-04 (anchored to PR #3286's merge date). The correct window per the user's brief was 30 days from PR-A1's (#3602) merge: 2026-05-12 → 2026-06-11. Agents proceeded with the wrong window in their initial pass. **Recovery:** caught during the user dialogue; the banner was subsequently dropped entirely so the date error became moot. **Prevention:** when a brainstorm crosses multiple PR merge dates, capture the relevant date math in a single explicit table at the top of the brainstorm before spawning leader prompts — agents inherit my quoted dates verbatim and won't catch my arithmetic errors.

## Workflow Proposal (feed to Deviation Analyst / Constitution Promotion)

Propose a one-line addition to the brainstorm skill Phase 0 preamble:

```
After cleanup-merged, run `git fetch origin main --quiet` so that subsequent
`git log main` / `git show main:<path>` reads reflect concurrent merges that
happened after the last local fetch. Skip silently on network failure.
```

Rationale: PR-B's session is a normal pattern (multiple PRs landing same day in a feature stream). The session-start preamble pulls cleanup but not refresh — the gap is exactly where parallel-session merges hide. One additional fetch call closes the window with no side effects.
