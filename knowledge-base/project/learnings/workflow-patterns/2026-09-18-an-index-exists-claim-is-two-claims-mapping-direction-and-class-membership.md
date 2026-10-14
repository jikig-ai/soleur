# Learning: an "index exists" claim is two claims — mapping direction and class membership

## Problem

Issue #8322 proposed deriving an "affected suites" set "from the registration surfaces, not from
grep — `lint-orphan-test-suites.sh` already maintains six registration surfaces covering all 465
suites — the index exists." It also prescribed a fixed list of 8 always-on "repo-global ratchets."

Both framings were half-true in ways that would have silently mis-shaped the design:

1. **Mapping direction.** The six registration surfaces answer "which suites exist/run" — a
   *reverse* mapping (suite → registration). The feature needs the *forward* mapping (changed
   file → suites that can break). No such index exists; it must be built from argv literals,
   `source`/`import` closure, name-stem conventions, and prefix rules. Accepting "the index
   exists" would have produced a plan that assumes the hard part is done.
2. **Class membership.** The "8 ratchets" hand list under-enumerated the real class ~3×: ~24
   `-live` repo-scanners, the legal-corpus gates, credential lints, runner-SUT suites, and
   `repo-wide+component` all satisfy the same predicate (a verdict over the whole tree that no
   changed file references). A literal list rots on the next registration; the fix is a
   *declared classification with a census*, not a longer list.

## Solution

Before committing to the issue's architecture, the brainstorm verified the premise claims
against the code: read the linter's producer (what domain it enumerates — `git ls-files
'*.test.sh'`, the *file* domain) vs. what the feature consumes (the *registration* domain via
`--enumerate-commands`), and enumerated the actual membership of the "whole-tree property"
class by grepping `test-all.sh` registrations rather than trusting the issue's enumeration.

The corrected design (adopted): an `--affected` flag at the registration chokepoint consuming
a declared edge index + a census-enforced always-on classification, with unclassified
registrations defaulting to always-run (fail toward coverage).

## Key Insight

When an issue says "the index/index-of-X already exists," verify **two** things independently:

- **Direction:** does the existing structure map the way the feature needs (file→suite vs
  suite→file, producer→consumer vs consumer→producer)? A complete index in the wrong direction
  is zero coverage of the need, and its existence makes the gap harder to see.
- **Membership:** for any "the N things in class C" enumeration, re-derive the class from its
  predicate before accepting N. The author's list is the members they *remembered*, not the
  members the predicate *admits* — and in this repo the predicate-admitting set is what a guard
  must cover, because a missed member is a silent hole, not a visible one.

This is the same shape as "no consumer is a producer-consumer contract mismatch" and the
data-source granularity check, one level more general: existence claims decompose into
direction and membership.

## Session Errors

- **Pre-existing orphan worktree `.worktrees/feat-one-shot-supabase-bind-loopback` unremovable
  (EACCES)** — `cleanup-merged` self-reported `SOLEUR_ORPHAN_UNREMOVABLE` with a remediation
  hint; not created by this session and not blocking. **Prevention:** none needed — the tool
  already fails visibly; a partially-deleted orphan is an operator-side `sudo`/perms fix per
  git-worktree SKILL.md §Sharp Edges.

## Tags

category: workflow-patterns
module: brainstorm
refs: [8322, 7494, 8023, 8092, 8177]
