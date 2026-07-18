---
title: "A test certifies placement, not correctness — and a class documented one day earlier recurred 6× the next"
date: 2026-07-16
category: test-failures
module: zot-soak-6122 / cloud-init beacon / follow-through gates
tags: [vacuous-test, mutation-testing, anchor-on-syntax, body-grep-comments, discriminator-direction, false-pass, irreversible-gate, verify-the-verifier, git-checkout-clobber]
related_prs: [6479]
related_issues: [6462, 6500, 6505, 6510]
related_learnings:
  - 2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr.md
  - 2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name.md
  - 2026-04-18-red-verification-must-distinguish-gated-from-ungated.md
---

# Learning: a test certifies placement, not correctness — and a documented class recurred anyway

## Problem

PR #6479 gave `scripts/followthroughs/zot-soak-6122.sh` — the gate authorizing ADR-096 5.3–5.5, which **rotate AND revoke** the GHCR PAT (irreversible, no rollback) — a fresh-boot denominator. It went through a 6-agent plan panel, a deepen pass, careful TDD, and a 6-agent code review. Review still found **three live false-PASS routes** to `exit 0` on a GHCR-served fleet, none caught by the eleven prior passes:

1. **The beacon's discriminator direction was unpinned.** The emit is `if [ "$REF" = "$IMAGE_REF" ]; then _emit … "app_ghcr_served" …; else _emit … "app_zot" …; fi`. Two tests pinned the beacon's *position* (`indexOf` ordering with `-1` guards), one pinned its *existence*, ~40 lines of comments explained its *semantics* — and inverting `=`→`!=` **passed all 39 tests**. Inverted, an all-GHCR fleet reports `app_zot>0 / app_ghcr_served=0`: the denominator looks satisfied, the FAIL set stays silent, and the gate PASSes on a fully GHCR-served fleet.

2. **"CLOSED" ≠ "fixed".** A blocker arm read issue #6500's `state` via `gh`. A careless close (closed-as-not-planned, autonomous backlog tidy) returns `CLOSED` and authorized the revoke. Worse, the reasoning I used to *justify* leaving it as prose ("a repo-local grep can only test half the close condition") was refuted by #6500's own filed evidence, which greps for both halves.

3. **`gh issue view` had no `--repo`.** Security review **reproduced it live**: `GH_REPO=microsoft/vscode` flipped the gate from `FAIL(blocked)` to `exit 0 "Safe to retire GHCR"`, because that repo's #6500 is closed.

And when the fix for (2) added a code-corroboration grep, that grep was **bypassable by two comment lines** — the same "body-grep sees comments" class documented in `2026-07-15-narrowing-is-not-anchoring-…`, recurred inside the guard written to close a different bypass.

## Root cause

**Every miss was a check that certified the wrong property.** The tests were rigorous about *where* code sat and *that* it existed, and silent about *what it does*. A test that pins placement passes identically for a correct and an inverted implementation — it is vacuous with respect to the behavior the feature exists to provide. The reviewers' one-line diagnosis: *the rigor was aimed at the design, not at the verification.*

The comment-satisfies-my-grep instances share a mechanism: a body-grep (or `indexOf`) sees comments, and the moment a task requires both "assert X in the file" and "document X in a comment", the two collide. This is `AGENTS.md`'s standing rule — *"narrowing the scope is not the fix — anchor on syntax"* — and it recurred **four times in this one PR** (beacon comment quoting `IMAGE_REF="$REF"`; the `APP_ZOT == 0` comment; the runbook triage list; the corroboration grep), the day after it was documented from a *different* PR that hit it four times.

## Solution

- **Pin the behavior, not the position.** AC1c asserts the whole literal condition (`if [ "$REF" = "$IMAGE_REF" ]; then _emit … app_ghcr_served …; else … app_zot …`). Mutation-tested both ways: invert the operator → RED; swap the branches → RED.
- **Mutation-test every guard that claims to prevent a false PASS.** For the soak that was 12 harness arms, each proven load-bearing by deleting the guard and watching the suite redden. A guard whose deletion leaves the suite green pins nothing — and the AC9 arm was exactly that until review (a global HTTP-500 was caught at an *earlier* guard, so the arm named for the `APP_ZOT` guard never reached it).
- **Corroborate issue-state against the code, and AND the two** (they fail in opposite directions: state fails on a careless close; grep fails when code looks right but the mirror is empty). Gate on `stateReason == COMPLETED`, and grep on **syntax anchors** (`^\s*IREF=.*$ZURL`, `^\s*soleur-boot-emit `) a comment line can never produce.
- **Pin the host, not just owner/repo:** `--repo github.com/jikig-ai/soleur` — `GH_HOST` is a second ambient resolver.

## Key insight

**A prose learning did not stop the class it documented.** `2026-07-15-narrowing-is-not-anchoring` existed before this session and the class recurred six times anyway (four grep, two placement-vs-semantics). Documentation that lives one `grep` away from the point of use is not where the author is looking when they write the assertion. The repo's own history says this out loud: *every PreToolUse hook was added after a prose rule failed.* The disposition for a **recurring documented** class is not another learning — it is a mechanical gate:

- a static check that any body-grep/`indexOf` assertion over a source file anchors on `^\s*` or a call-form, never a bare token that also appears in a comment; and
- for `file:NNN` citations (which rotted **inside the commit that wrote them**, 35 lines onto a decoy that falsely confirmed), a CI check that resolves cited coordinates in changed files against the post-diff tree.

The generalization beyond this PR: **when a test or gate names a property (placement, existence, "X is fixed"), ask what a *malicious or careless* diff that satisfies the test while violating the property looks like — then make the test fail on it.** That question is what "adversarially verify" means at the assertion level, and it is cheap: it is one mutation per guard.

## Session Errors

1. **`git checkout -- <file>` destroyed my own uncommitted tests.** A forced-budget revert discarded the AC1/AC1b tests written in the same file. — Recovery: rewrote from context; committed before re-touching. — **Prevention:** already in `review/SKILL.md` Sharp Edges ("cp <file> /tmp/<file>.bak BEFORE the mutation loop"); I did not follow it the first time. Follow it every time a mutation targets a file with uncommitted sibling edits.

2. **A concurrent review agent's `git checkout --` wiped my uncommitted comment fix (×3).** — Recovery: a verified `cp` backup preserved it; committed immediately thereafter. — **Prevention:** never hold uncommitted edits in a file while mutation-verifying agents run against the same worktree; commit or back up first. Reinforces the existing rule.

3. **Misattributed the reverts to the test-design agent** in user-facing text; the architecture agent later admitted it ran them. — Recovery: corrected in the next message. — **Prevention:** attribute a worktree mutation only after `git log`/agent-report evidence names the actor; "an agent did X" is a hypothesis until traced.

4. **Mutation-test backup `cp` to a stale scratchpad path silently no-op'd,** so three mutations accumulated and corrupted the working soak. — Recovery: `git checkout HEAD -- <file>`, re-applied fixes with a `test -f`-verified backup. — **Prevention:** assert the backup exists (`cp … && test -f …`) before the first mutation; restore-then-verify-green after each.

5. **False "vacuous test" verdict.** My mutation replaced one of two greps, leaving the other anchored to catch the fixture — I concluded the arm was vacuous before proving it load-bearing with the *full* mutation. — **Prevention:** a "still green" mutation result is only trustworthy when the mutation is complete; verify the mutation actually changed the property under test (here: confirm BOTH conjuncts were weakened) before declaring vacuity.

6. **Five imprecise verification probes** — `grep -c` without `-F` treating `$BLOCKER`/`$ZURL` as regex ($-anchors → 0 matches); an `awk` range returning 0 `tagged_event`; `grep -A11` truncating a 12-line block. Each reported a problem where the code was fine. — **Prevention:** when a self-check contradicts a change you believe landed, suspect the check before the code; use `grep -F` for literals containing `$`/`*`, and prefer the authoritative derived assertion (the op-contract's `alarmFilterSet()`) over an ad-hoc `awk` range.

7. **Rotted my own `:NNN` citations** — cited `:151`/`:159` in a comment my own PR then shifted 35 lines onto a decoy. — Recovery: name-anchored all of them; swept my own review fixes for the same. — **Prevention:** the mechanical gate proposed in Key Insight; until then, cite names, never coordinates, in any comment in a file the same PR edits.

8. **Wrote a false remedy** ("pin the soak's `START`") into the alarm mute carve-out — a fabricated causal mechanism (`START` has no path to a Sentry rule). — Recovery: replaced with the real levers. — **Prevention:** before writing "to fix X, do Y" in a comment, trace Y to X in the code; a remedy is a claim to verify, not prose to assert. Same class as the false-comment learnings of 2026-07-15.

9. **`git stash list` denied by a guardrail hook** inside a verification command, taking the whole call down. — Recovery: re-ran without it. — **Prevention:** the block is correct (no stash in worktrees); use `git show <commit>:<path>` to inspect, and don't reach for stash-family commands in worktrees even read-only.
