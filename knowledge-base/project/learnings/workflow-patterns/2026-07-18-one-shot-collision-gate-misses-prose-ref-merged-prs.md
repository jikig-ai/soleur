---
title: one-shot collision gate misses merged PRs that referenced the issue via prose Ref (no formal link)
date: 2026-07-18
category: workflow-patterns
tags: [one-shot, collision-gate, github, dispatch-waste, premise-validation, deferred-automation]
---

# one-shot collision gate misses merged PRs that referenced the issue via prose `Ref #N`

## Context

`/soleur:go 6197` routed to `/soleur:one-shot` to "wire the arm64 Vector journal→Sentry
shipper on the dedicated Inngest host." The task was **already fully implemented and merged**
by **PR #6209** (`c890464ce`, 2026-07-07) — the same day #6197 was filed. Every line item was
verifiable on `main`: arch-parameterized Vector install off `VECTOR_CLI_ARCH`
(`inngest-bootstrap.sh:733-737`), the arm64 Vector SHA pinned (`vector.tf:22`
`vector_sha256_arm64`), and `BETTERSTACK_LOGS_TOKEN` provisioned into `soleur-inngest/prd`.
ADR-100:399 records it: **"Phase-1 caveat — RESOLVED (#6197)."** ("Sentry" in the title was
also stale — Vector ships to Better Stack Logs since #4273/#5526.)

The one-shot Step 0a.5 collision gate ran **clean** and did not flag any collision. The
worktree, the draft PR (#6674), and a full `/plan` planning subagent were all spun up before
`/plan` Phase 0.6 premise-validation surfaced the merged state.

## Why the gate missed it (distinct from the 2026-05-29 `--state all` fix)

The 2026-05-29 learning fixed a *state-filter* blind spot (MERGED PRs invisible to
`--state open`). This is a **different** blind spot that survives that fix:

- **PR #6209 referenced the issue via prose `Ref #6197`, not a `Closes`/`Fixes` keyword.**
  GitHub only creates a formal issue↔PR **link** from a closing keyword or a manual sidebar
  link. Prose (`Ref #N`, `Tracked-by #N`) creates no link.
- Consequently **both** gate probes returned empty:
  - Item 1 `closedByPullRequestsReferences` → `[]` (nothing *closed* the issue).
  - Item 3 `gh pr list --search "linked:issue #6197" --state all` → nothing (no formal link
    exists to match, even with the `--state all` fix applied).
- So an already-merged, scope-complete PR was **completely invisible** to a gate whose entire
  job is to catch already-done work. The issue stayed OPEN only because `Ref` (not `Closes`)
  left it un-auto-closed — a common pattern for `deferred-automation` tracker issues.

## Fix

Two-part, both landed in this PR:

1. **Gate hardening (`one-shot/SKILL.md` Step 0a.5 item 3).** For an OPEN issue, in addition
   to the `linked:issue` probe, run a **body-text** probe:
   `gh pr list --search "#<N> in:body is:merged"`. It over-matches (any merged PR that merely
   *cites* #N surfaces), so it is a **surface-for-verification** signal, not an auto-abort:
   interactive names the hits in the AskUserQuestion; headless logs them. The definitive
   discriminator is **scope** (read the surfaced PR's diff), not the link.
2. **Backstop is real and worked.** `/plan` Phase 0.6 premise-validation caught this after the
   gate passed. The premise-validation layer is the reliable defense; the gate probe is a
   cheap pre-worktree filter that should catch the *common* prose-`Ref` case, not the sole line
   of defense.

## Reconciliation action taken

No product-code PR for #6197 (re-implementing merged code = no-op or conflict). Instead:
**closed #6197** as `completed` with a comment citing PR #6209 + the code locations + ADR-100:399,
and explicitly handed the Phase-2 cutover runtime-activation residual to **#6178** (OPEN) +
ADR-100 §Phase-2 so nothing is dropped. #6197's Scope (the IaC wiring) was done; the Phase-2
cutover is a separate deliverable with its own tracker — keeping #6197 open only made its stale
`deferred-automation` title a re-trigger magnet (this run being the proof).

## Takeaway

- A gate that keys on GitHub's *link graph* (`linked:issue`, `closedByPullRequestsReferences`)
  is blind to prose references. When "already done" can be signalled by prose, add a **body-text**
  probe and treat it as surface-for-verification, never auto-abort.
- `Ref #N` (not `Closes #N`) on the implementing PR is the tell for a tracker issue that will
  linger OPEN after its work merges — a re-dispatch magnet. Reconcile (close + hand off residual)
  rather than leaving it to be re-picked.
- Premise-validation (`/plan` Phase 0.6) is the load-bearing backstop; verify a `#N` target's
  scope against `main` before trusting the dispatch, even when the collision gate is silent.

## Follow-up (2026-07-20) — the probe this learning added never fired

The body-text probe prescribed above shipped **broken** and silently open. It was specified as
`gh pr list --search "#<N> in:body is:merged"` with no `--state`, which returns zero rows for
**every** input. It did not fire once between the day it merged and 2026-07-20, when a
`/soleur:go 6608` dispatch hit the exact failure mode this learning describes — PR #6664 had
implemented all of #6608 under prose `Ref`, all three collision signals came back empty, and the
run burned a worktree, a dependency install, an empty draft PR, and a ~147k-token planning
subagent before `/plan` Phase 0.6 caught the stale premise. Fixed in #6786.

### The meta-lesson

**A probe added to close a blind spot must be proven to fire — demonstrated returning a non-empty
result against a known-positive case — before the PR that adds it merges.** An unverified probe is
worse than no probe: it manufactures false confidence and closes the issue that would otherwise
keep the gap visible. The reasoning in the body above is sound; only the query string was wrong,
and nothing in the authoring loop distinguished those two.

### The silent-open shape (the generalizable class)

Any probe whose "all clear" is an **empty result** cannot distinguish *no hits* from *malformed
query*, *auth failure*, *rate limit*, or *truncated page*. All four render identically as success.
Such probes need, at minimum: a positive control proving the query can return rows, explicit
non-zero-exit handling, and a page limit large enough that truncation is not mistaken for
completeness. The fix carries all three.

### The corrected mechanism (do not propagate the wrong diagnosis)

Issue #6786 originally diagnosed this as "GitHub's search tokenizer strips the leading `#`".
**That is false.** `gh search prs "#6608 in:body is:merged"` and `gh search prs "6608 in:body
is:merged"` return byte-identical results. The real mechanism: `gh pr list --search` appends its
default `--state open` filter unless it detects an in-query state qualifier, and a leading `#` on
the first token defeats that client-side detection — so `is:merged` AND an appended open filter is
a contradiction, yielding zero rows always. Dropping the `#` "works" only by letting `gh` sniff
`is:merged` successfully, i.e. by depending on the same undocumented behaviour that caused the
bug. The robust fix is an explicit `--state merged`.

### Repeat offence: this is the third instance, not the first

`2026-05-29-one-shot-collision-gate-must-probe-merged-prs.md` already fixed a `--state` blind spot
on the sibling `linked:issue` probe. The 2026-07-18 body probe reintroduced the same class at a new
call site, because that fix was a one-line patch rather than an enforced invariant. While fixing
this, a **third** live instance was found in `triage/SKILL.md` (hunting a *dismissing* — therefore
merged — PR with no `--state`), plus two more in `review/` and `ship/` that the issue's own
enumeration missed because they place `--label` between `list` and `--search`. So **four live
call sites** at the time of the fix; a fifth, the `linked:issue` probe, was the already-fixed
2026-05-29 instance. Review of the fix then found two more the first lint could not see: a
dedupe probe one directory deeper (`review/references/review-todo-structure.md`) and an
un-synced hook mirror (`.openhands/hooks/pre-merge-rebase.sh`, whose `.claude` twin had carried
both `--state all` and an exact-phrase fix since #2186). The lint added in #6786 asserts every
`gh pr|issue list --search` under `plugins/soleur/skills/**/*.md` carries an explicit `--state`,
and additionally rejects pinning state in both the query and a flag.

**Named residual:** the lint proves the probe is *well-formed*, not that it *works*. A GitHub or
`gh` semantic change would pass it. That is accepted — `/plan` Phase 0.6 premise-validation remains
the load-bearing backstop, exactly as the Takeaway above already concluded.

### Sharp edge: anchor a path-exclusion filter on the filename field

While auditing for offenders, a sweep using `grep -v 'knowledge-base/project/learnings/'` matched
that path **cited in the offending line's own prose** and silently filtered out the one real
violation, reporting a clean sweep. Exclusion filters must be anchored on the filename field
(`awk -F: '$1 !~ /pattern/'`), never matched against the whole grep output line. The same defect
class shows up in the lint itself: filtering raw SKILL.md *lines* for `--state` is vacuous, because
the mechanism note necessarily puts the literal `--state` in the same ~1,900-char line's prose —
so the lint extracts backtick command spans instead.

### Scope of the original claim

The body probe closes **body-text prose refs** only. Known-remaining escapes, now named in the
SKILL.md bullet: PR **title-only** references (`in:body` excludes titles) and **search-index lag**
of several minutes, which leaves a just-merged PR invisible to any search-based probe.
