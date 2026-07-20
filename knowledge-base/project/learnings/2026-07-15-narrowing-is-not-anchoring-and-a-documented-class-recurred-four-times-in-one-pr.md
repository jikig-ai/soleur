---
title: "Narrowing is not anchoring — and a documented failure class recurred 4× in one PR"
date: 2026-07-15
category: test-failures
module: sentry-alerts, review-skill, c4-model
issues: [6436, 6429, 6446, 6447]
pr: 6456
tags: [vacuous-assertion, mutation-testing, comment-rot, false-green, sast, review]
---

# Learning: narrowing is not anchoring

## Problem

PR #6456 exists to fix **rotted claims** — comments and citations that no longer match
the artifact they point at. While fixing them it **minted seven new ones**, four of which
were vacuous assertions of a class this repo had already documented **three times on the
same day** (`2026-07-15-comment-fix-pr-wrote-a-new-false-comment-and-vacuous-ac-classes`,
`-guard-gate-and-probe-must-pin-the-thing-they-name`,
`-a-guard-that-never-ran-…-block-scoping-swallows-siblings`).

That is the headline. **The class is documented and prose did not prevent it.** Every one
was caught by mutation testing, none by reading.

## The four instances

| # | Assertion | Why it passed vacuously |
|---|---|---|
| 1 | `expect(scoped).toMatch(/value\s*=\s*2/)` | Scope included the leading comment; my own prose read *"WHY value = 2 AND NOT 3"*. Reverting the config to `3` stayed **green**. |
| 2 | `expect(scoped).toContain("IssueOwners")` | An **in-body** comment reads *"IssueOwners has no ownership rule … falls through to ActiveMembers"*. Deleting the **entire `actions_v2` block** — so the rule fires and pages **nobody**, the exact outcome the test is *named* after — stayed **green**. |
| 3 | `expect(note).not.toMatch(/zot_…:\d+/)` | `indexOf` returned `-1`; `slice(-1)` yielded `"\n"`. A `.not` assertion against one newline always passes. |
| 4 | `! grep -qE 'cloud-init schema -c cloud-init\.yml' <workflow>` | My own comment quoted the deleted command, so the must-not-contain check tripped on the prose explaining the fix. |

Plus a fifth, structural: **`scopeResource` had no lower bound.** It terminated at the next
`\nresource ` header instead of the resource's own closing brace, so one rule's scope
swallowed the *next* rule's comment block. Deleting the real GROUPING paragraph left the
suite green because the *pointer* to it satisfied the regex. One helper bug made every
assertion using it potentially vacuous.

## Key Insight

**Narrowing the scope is not the fix. Anchoring on syntax is.**

My first correction to instance 1 was to narrow the slice (body-only, excluding the
leading comment). That was insufficient and I shipped instance 2 anyway — because
`issue-alerts.tf` puts explanatory comments **inside** resource bodies. There is no scope
that contains the config and excludes all prose.

The durable rule:

> Anchor on a construct **prose cannot produce**. `^\s*target_type\s*=\s*"IssueOwners"`
> cannot appear in a `#` comment; `IssueOwners` can. Every `toContain`/bare-substring of a
> word that also appears in a nearby comment is **guilty until mutation-tested**.

Corollaries that each cost a cycle here:

- **A slice helper is a shared failure mode.** Guard `indexOf` against `-1` (`slice(-1)`
  silently yields the last character) and give every scoper an explicit lower bound.
- **The mutation is the test of the test.** Every assertion that passed under its own
  mutation was one I had *read* and believed. Reading cannot find this class.
- **Count from the summary line, strip ANSI first.** `grep -cE '^\s+×'` over vitest output
  always returns `0` — the marker is colourised. My first mutation battery reported "0
  failing" for **every** mutation and I nearly believed the assertions were sound.
- **Commit before mutating; restore from a file copy.** `git checkout -- <file>` took my
  own uncommitted fix with the mutation. Second independent instance in this repo.

## The same shape, outside tests

The class is not test-specific — it is **"a claim whose verification can be satisfied by
the claim itself."** Same PR, same day, three non-test instances:

- **`review/SKILL.md` prescribed semgrep packs as `p/js + p/ts`.** Both 404 → semgrep
  **exits 7 having scanned nothing** and reports `findings: 0`, indistinguishable from a
  real clean. The skill contradicted its own reference file (`p/javascript`). Every
  reviewer following that line got a security gate that never ran.
  **Rule: assert the run was NON-VACUOUS before trusting a clean** — semgrep prints
  `Ran N rules on M files`; `N` must be non-zero for the language (a real TS scan is ~82).
  Bash corollary: OSS semgrep's tree-sitter bash parser matches ~0 rules, so `0 findings`
  on a `.sh`-only diff is *always* vacuous — use `shellcheck`.
- **The plan's AC2 named a vacuous gate.** It cited `c4-render.test.ts` +
  `c4-code-syntax.test.ts` as the gate for a C4 change; both mock `node:fs/promises`
  wholesale and never open a `.c4` file — a bogus element leaves 23/23 green. The real
  gate (`c4-model-freshness.test.sh`, a byte-diff against a pinned render) went unnamed,
  so **following the plan's own ACs would have shipped red CI**.
  **Rule: verify the AC's named gate actually observes the artifact before trusting green.**
- **A rendered-schema SKIP false-greened in CI.** With `cloud-init` off PATH and `CI=true`
  the suite exited 0 at "50/50 passed, OK" with the schema asserts silently gone. "Visible
  in a green advisory job's log" is not visible.
  **Rule: a guard that can silently disarm must FAIL in CI and SKIP only locally.**

## A gap is safer than a false assertion

#6436 reported that the C4 had a **gap** (Sentry absent). The fix replaced it with an
**active falsehood**: *"Sentry holds the platform's whole paging surface … the ONLY exit
from the alerting plane"* — while `uptime-alerts.tf` states plainly that Better Stack
*"still pages"* if Sentry is degraded. Surviving a Sentry outage is the single most
load-bearing property of that design, and the model denied it existed. Someone could have
deleted the "redundant" second source on the model's authority.

> **A gap is detectable; a false assertion is not.** Adding a `whole` / `only` / `every`
> quantifier to an architecture document is a **claim**, and must be verified against the
> siblings it excludes — not just the subject it describes.

Verified counter-example in the same edge: *"Every issue alert routes → ActiveMembers"* —
21 of 22. `byok_cap_exceeded` sets `NoOne`, and since `IssueOwners` has no ownership rule
on this project, that rule fires and pages nobody.

## Prevention

1. **Mutation-test every new assertion before commit.** Not "when suspicious" — every one.
   The four vacuous assertions here were all confidently authored and read.
2. **Anchor on syntax prose cannot produce** (`^\s*key\s*=`), never a bare substring that
   a comment can contain.
3. **Prove the tool ran.** `Ran N rules`, an assert-count delta, a non-zero exit under a
   deliberate break. A clean result from a tool that scanned nothing looks exactly like a
   clean result.
4. **Commit before mutating.** Restore from `cp`, never `git checkout`.
5. **Strip ANSI before counting failures.**
6. **Give each parallel agent its own worktree.** `git add` + `git commit` are not atomic
   and there is one index per worktree — my commit swallowed a sibling agent's staged
   files and shipped its work under an unrelated message.
7. **`cd <abs-root> && <cmd>` per command.** Never relative `cd ..` back: it silently
   failed a `git add` (pathspec error) and a `cp` restore that left a 20-line mutant live
   in the tree.

## Session Errors

- **Planning subagent terminated on an Anthropic session limit** *(forwarded from
  session-state.md)* — Recovery: recovered the plan from on-disk artifacts rather than
  re-running plan (v2 was already review-hardened). — **Prevention:** the one-shot
  partial-artifact recovery path worked as designed; no change needed.
- **`git checkout -- issue-alerts.tf` during mutation testing destroyed the uncommitted
  Phase 3 fix** — Recovery: re-applied the edits from context. — **Prevention:** commit
  before mutating; restore from `cp`. Second instance in this repo; `review/SKILL.md`'s
  note should be strengthened from "cheapest prophylactic" to a hard ordering.
- **ANSI-coloured marker made the failure counter always read 0** — Recovery: counted from
  vitest's summary line after `sed -r 's/\x1b\[[0-9;]*m//g'`. — **Prevention:** never grep
  a colourised marker; use the summary line.
- **Four vacuous assertions shipped and were caught only by mutation** — Recovery: anchored
  each on syntax. — **Prevention:** see Key Insight.
- **Committed a SKILL.md edit with a failing test** (bare backtick reference where the
  skill mandates markdown links) — Recovery: fixed and amended. — **Prevention:** read the
  gate's output *before* committing, not after. `hr-when-a-command-exits-non-zero-or-prints`
  already covers this; the miss was mine.
- **Committed a broken file mid-rebase** (stray `<<<<<<< HEAD` left after resolving) —
  Recovery: removed the marker, verified the suite parsed. — **Prevention:** grep for
  `^(<<<<<<<|=======|>>>>>>>)` before `git add` during a conflict resolution.
- **CWD drift ×3** — Recovery: re-ran from the worktree root; restored a live mutant that a
  silently-failed `cp` had left in the tree. — **Prevention:** absolute `cd` per command.
- **`git stash list` hook denial** — Recovery: dropped the call (it was unnecessary). —
  **Prevention:** none needed; the hook did its job.
- **Broken PATH mask made a verification falsely pass** (filtered `/usr/bin`, which holds
  `cloud-init` *and* `bash`) — Recovery: built a symlink mask dir excluding only the target
  binary. — **Prevention:** when simulating a missing binary, verify the absence
  (`PATH=$MASK command -v <bin>` must fail) before trusting the run.
- **Sentry 403 disguised a rotted name** — the plan's `SENTRY_ISSUE_RO_TOKEN` 403s on the
  rules endpoint (scoped to issues, not alerts — the only one of five tokens that cannot do
  the read), *and* the first 403 was actually a stale project slug (`soleur-web-platform`,
  renamed to `web-platform` on the DE org in 2026-05). Sentry returns **403, not 404**, for
  an unknown slug. — **Prevention:** on a vendor 403, verify the resource NAME before
  concluding it is a scope problem.
- **Parallel agents shared one git index** — Recovery: none needed (content correct; repo
  squash-merges). — **Prevention:** `isolation: "worktree"` per agent, or serialize commits.
- **Merge conflict with `main` (#6452)** — Recovery: rebased, kept both helper sets. —
  **Prevention:** `git fetch origin main` at review time; `code-quality-analyst` caught this
  before CI did.

## Related

- `2026-07-15-comment-fix-pr-wrote-a-new-false-comment-and-vacuous-ac-classes.md` — the
  same class, same day. **This learning is its third recurrence; prose is not preventing it.**
- `2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name.md`
- `2026-07-15-a-guard-that-never-ran-has-more-than-one-reason-and-indexof-block-scoping-swallows-siblings.md`
- `test-failures/2026-06-17-grep-assertion-over-script-body-false-matches-own-comments.md` —
  the bash-side original. This extends it to TypeScript and adds the
  **narrowing-is-not-anchoring** corollary.
- `2026-06-15-id-shape-guard-test-fixture-blast-radius-and-syntactic-sast.md` — SAST
  vacuity, adjacent.
