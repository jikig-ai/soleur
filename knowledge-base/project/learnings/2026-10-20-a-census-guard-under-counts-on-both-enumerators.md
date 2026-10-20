---
module: repo lint tooling (scripts/lint-feature-map-coverage.sh)
date: 2026-10-20
problem_type: logic_error
component: tooling
symptoms:
  - "git ls-files 'apps/web-platform/app/**/page.tsx' enumerates 31 files on git 2.56; prefix+grep enumerates 32 — the `/` route's own page.tsx silently absent from the census"
  - "a `- gotchas: see selectors:` prose line satisfied the completeness arm's bare-substring check for an entry that lacked the field"
  - "a `## \`/route\`` line inside a fenced code block counted as a real map entry for every line-anchored consumer"
root_cause: logic_error
resolution_type: code_fix
severity: medium
rule_id: hr-when-a-plan-specifies-relative-paths-e-g
related_issues: [10399]
related_prs: [10666]
tags: [git-pathspec, glob-zero-directories, line-anchored-parser, fenced-block, fail-closed-lint, verdict-channel, presence-not-conformance]
---

# A census guard under-counts on BOTH enumerators — the producer's glob and the consumer's parse

## Problem

#10399 shipped a drift guard (`scripts/lint-feature-map-coverage.sh`) that
compares two sets: the routes a tracked `page.tsx` tree produces, and the
routes `apps/web-platform/test/feature-map.md` claims to cover. Both sides
under-enumerated in ways a green run could not show: the producer's
prescribed pathspec silently dropped one route, and the consumer's parse
certified entries a conforming map never wrote.

## What Didn't Work

**The plan-prescribed producer:** `git ls-files 'apps/web-platform/app/**/page.tsx'`.
On git 2.56 the `**/` pathspec requires at least one intermediate
directory, so it matches `app/(dashboard)/x/page.tsx` but NOT
`app/page.tsx` — the `/` route itself. Measured on this tree: 31 files vs
the correct 32. A `**/` glob that returns ≥1 hit looks verified; the
deficit is only visible against an independent enumeration.

**The first consumer parse (caught by the structural-enumeration review
seat, P1, fixed in 620cfa39eb):** three non-conforming inputs all read as
conforming —

1. The completeness arm grepped the bare substrings `selectors:` /
   `expects:` inside each entry body. A prose mention
   (`- gotchas: see selectors:`) satisfied the check for an entry missing
   the field entirely — presence is not conformance.
2. Every consumer pattern is line-anchored (`^## \``, `^- \``), so a
   `## \`/route\`` line inside a fenced code block counted as a real entry
   heading and its fenced body as real fields — a fenced *example* of a
   non-conforming entry would certify the route it depicted.
3. Two verdict channels existed: `fails` for pre-consumer errors and a
   separately-enumerated ok-condition over the arm counters. A future arm
   that echoed findings but forgot to wire its counter into the
   ok-condition would report-and-pass.

## Solution

```bash
# Producer — enumerate the prefix, filter the suffix (never a `**/` glob):
git -C "$REPO_ROOT" ls-files "$APP_PREFIX" | grep -E '/page\.tsx$' | LC_ALL=C sort -u

# Consumer field check — anchor to the documented bullet shape, not the token:
#   before: if ($0 ~ /selectors:/) sel=1
#   after:  if ($0 ~ /^[[:space:]]*-[[:space:]]*selectors:/) sel=1

# Grammar arm — forbid the construct the convention doesn't need:
fenced=$(grep -cE '^(```|~~~)' "$MAP_PATH" || true)

# Verdict — ONE channel: every arm's counter aggregates into `fails`,
# and `fails > 0` is the only thing the exit gate reads:
fails=$((fails + uncovered + tombstone + contra + incomplete + malformed_n + fenced))
```

The battery gained rows driving each defect red (prose-mention fields,
fenced entry, FENCED-BLOCK arm); sentinel + battery run 16/16 green.

## Why This Works

1. **`git ls-files '<dir>'` as a bare pathspec enumerates the tree
   recursively**; the `grep` keeps the one suffix that defines a page.
   The set is built by enumeration-then-filter, so no glob semantics stand
   between the census and the tree. This is the fourth documented
   instance of the `**/` zero-directory trap in this KB (see Related
   Issues) — the prior fixes were the same shape: drop the `**/`, use a
   prefix pathspec plus a content filter.
2. **Anchoring the field check to `- selectors:`** ties conformance to
   the entry convention the map documents, so only the real field bullet
   satisfies it. The general rule: a conformance grep must match the
   *shape* the document prescribes, not a substring that prose can
   produce — the same bare-token family already documented for comments
   and header prose.
3. **Forbidding fenced blocks outright is cheaper than lexing them.** The
   "a line scanner is not a lexer" lesson (Related Issues) prescribes a
   tokenizer when the input language is out of your control. Here the
   document's own convention is under the guard's control and needs no
   fences — the map uses inline backticks — so the grammar arm bans the
   construct instead of teaching three parsers to skip fence ranges.
   Fail closed on the fence itself; when you own the convention, the
   smallest lexer is a prohibition.
4. **One verdict channel** (`fails` accumulates every arm, the exit gate
   reads only `fails`) makes "reports findings but doesn't fail"
   unreachable for future arms — the ok-condition cannot drift from the
   set of arms by omission.

Convention notes (followed existing rules, no new rule needed):

- **Findings go to stdout, not `>&2`** — they are the operator-protection
  signal (the routes a contributor must map), and several agent runtimes
  swallow stderr. Constitution: "any CLI tool emitting an
  operator-protection signal emits to stdout"; the sibling
  `lint-integration-env-gates.sh` `>&2` precedent is diagnostics, a
  different class.
- **A dedicated fixture seam name** (`SOLEUR_FEATURE_MAP_ROOT`, distinct
  from `SOLEUR_LINT_GATES_ROOT`) keeps a session mid-debug on one
  sentinel from cross-driving another — matches the repo's per-guard
  seam-naming convention.

## Session Errors

1. **Plan prescribed `git ls-files 'apps/web-platform/app/**/page.tsx'`
   (tasks.md 2.2), which silently under-enumerates on git 2.56.**
   - **Recovery:** measured the glob against prefix+grep before
     implementing; the shipped producer uses the measured form.
   - **Prevention:** the existing
     `hr-when-a-plan-specifies-relative-paths-e-g` gate verifies a
     prescribed glob matches ≥1 file — that check CANNOT see partial
     coverage (31 hits reads as verified). For a pathspec that builds a
     SET, compare `git ls-files '<glob>' | wc -l` against
     `git ls-files '<prefix>' | grep -E '<suffix>$' | wc -l`, or
     prescribe the prefix+filter form directly. Routed to
     plan-sharp-edges.
2. **Guard's consumer parse certified non-conforming entries (3 defects:
   bare-substring fields, fenced-block blindness, dual verdict
   channel).**
   - **Recovery:** structural-enumeration seat found all three at review;
     fixed inline in 620cfa39eb with battery rows driving each red.
   - **Prevention:** routed a construction-check entry to
     review/SKILL.md's guard-shaped-diff list; author-side, the litmus is
     "name an input that satisfies the check while violating the
     property."
3. **tasks.md item 2.2 still records the prescribed (wrong) glob, not the
   shipped form.**
   - **Recovery:** none needed; the spec dir is a live ship input and
     archives at ship Phase 6.45.
   - **Prevention:** when a measurement mid-work supersedes a prescribed
     command, correct the spec line in the same commit (or the archived
     record teaches the trap it caught).
4. **Review P2s: new suite labels had no committed weight rows; a battery
   PATHS comment claimed the verdict moves with the real map.**
   - **Recovery:** committed honest weights and corrected the comment in
     3848c59eed.
   - **Prevention:** suite-weight bookkeeping is a same-PR step, and a
     comment asserting what a fixture moves must name the fixture's own
     scope, not the production tree's.

## Related Issues

- `2026-05-19-cache-llm-outputs-flag-for-rerunnable-benches.md` — same
  `**/` zero-directory pathspec trap (Bug 3); its fix was the same
  prefix-pathspec-plus-filter shape.
- `2026-05-19-retrieval-diagnostic-findings.md` §3 — same trap, `**/*.md`
  matched only files in subdirs (27% of corpus searched).
- `2026-03-21-lefthook-gobwas-glob-double-star.md` — the original
  documented instance (lefthook globs).
- `2026-09-24-a-line-scanner-is-not-a-lexer-and-my-guard-fixture-hid-the-suite.md`
  — the general "lex, don't scan" lesson; this guard's fenced-block arm is
  the cheaper dual when the document convention is yours to constrain.
- `knowledge-base/project/specs/archive/20261020-171633-feat-one-shot-10399-webplat-feature-map/decision-challenges.md`
  — CTO rulings on map format, gate scope, bidirectionality, and the
  in-map exemption registry.
