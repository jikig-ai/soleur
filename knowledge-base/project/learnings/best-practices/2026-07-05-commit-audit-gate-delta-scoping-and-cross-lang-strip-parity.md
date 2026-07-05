---
title: "Commit-audit PreToolUse gates must scope the diff to what the commit records; cross-language duplicate implementations need boundary fixtures"
date: 2026-07-05
category: best-practices
tags: [pretooluse-hook, git-argv, parity-test, fixtures, multi-agent-review, freshness]
issue: 5999
pr: 6017
adr: ADR-086
last_updated: 2026-07-05
review_cadence: quarterly
owner: founder
---

# Learning: commit-audit gate delta-scoping + cross-language strip parity

Two generalizable lessons from the `last_reviewed` freshness gate (#5999, ADR-086),
both surfaced by multi-agent review AFTER a green test suite (15/15 gate, 8/8 strip
parity) — i.e. tests the author wrote could not have caught them, but orthogonal
review agents converged on each.

## Problem 1 — a commit-audit gate that inspects the working tree must scope the delta to WHAT THE COMMIT ACTUALLY RECORDS

The gate (`context-reviewed-gate.sh`) denies a `git commit` that changes a
`last_reviewed:` line without a `Context-Reviewed:` trailer. To catch
`git commit -am` (which commits unstaged content the `--cached` diff can't see),
the first implementation UNIONed a blind `git diff -U0 -- '*.md'` (all markdown,
working tree vs index) whenever it detected an `-a`/`-o`/`.md`-pathspec flag.

Three orthogonal review agents (security-sentinel, user-impact-reviewer,
code-quality-analyst) independently found this is **both** a false-negative and a
false-positive:

- **False-negative:** a DIRECTORY pathspec (`git commit docs/`, `git commit knowledge-base/`)
  commits unstaged content but matched neither the flag branch nor the `.md`-suffix
  pathspec branch → the `--cached` delta was empty → an undeclared bump slipped
  through **with zero telemetry** (the exact ledger the design relies on never saw it).
- **False-positive:** the union diffed ALL markdown, so an unrelated unstaged
  `last_reviewed` edit ELSEWHERE (e.g. an in-progress `AGENTS.core.md` bump) false-
  denied a scoped commit that didn't include it. And the flag grep matched the WHOLE
  command string, so `git commit -m x && ls -la` (the `-la` contains `a`) flipped the
  gate into union mode.

### Fix

Parse the `git … commit` SEGMENT quote-aware and classify its mode, then scope the
diff to what the commit records:
- `-a`/`-am`/`--all` → `git diff HEAD -U0 -- '*.md'` (all tracked working-tree changes)
- `<pathspec…>` → `git diff HEAD -U0 -- <named paths>` (bare paths, `-o`/`--only`, post-`--`)
- neither → `git diff --cached -U0 -- '*.md'` (staged only)

Key parser rules: value-taking flags (`-m`/`-F`/`-C`/`-c` and `--message`/`--file`/…)
consume their argument so it is never mis-read as a pathspec; a chain operator
(`&&`/`||`/`;`/`|`) TOKEN ends the segment so a chained command cannot flip the mode;
parse the RAW `$CMD`, not the body-stripped SCAN (stripping blanks quoted flag values
and breaks value-flag skipping).

### Generalizable rule

**When a PreToolUse gate inspects repo state to decide about a `git commit`, the
delta it examines MUST equal what that specific commit will record — parse the
commit segment (mode + pathspec), don't approximate with a blind all-file
working-tree union.** A blind union over-reaches (false-deny on unrelated unstaged
edits) AND under-reaches (misses directory/pathspec commits of unstaged content).
Regression tests must cover: directory-pathspec deny, scoped-pathspec allow with an
unrelated unstaged edit elsewhere, and a chained non-commit segment carrying the
trigger flag.

## Problem 2 — two "byte-identical" implementations in different languages need EMPTY/BOUNDARY fixtures in the parity test, not just happy-path

The frontmatter-strip contract shipped two implementations (perl in `strip.sh`,
split/join in `strip.py`) pinned by a cross-check test with 3 hand-picked fixtures
(with-frontmatter, no-frontmatter, malformed-unterminated). The parity test passed
8/8 — but the perl regex `s/\A---\n(?:.*?\n---\n|.*\z)//s` DIVERGED from the python
on an EMPTY frontmatter block (`---\n---\nbody`): the opening `---\n` consumed the only
newline before the close, so `\n---\n` couldn't match → perl ate the whole file, python
correctly returned `body`. A pattern-recognition fuzz found **43 divergences over 2356
inputs, all sharing the `---\n---` prefix** — an entire input class the 3 fixtures never
exercised. `strip.sh` violated its own canonical SPEC while the parity test stayed green.

### Fix

`s/\A---\n(?:.*?^---\n|.*\z)//ms` — `^`-anchored close (via `/m`) instead of a mandatory
preceding `\n`, so an empty frontmatter block strips to the body. Added an
`empty-frontmatter-body.in` fixture that makes the parity assertion catch the drift.

### Generalizable rule

**A parity test between two implementations is only as strong as its fixture corpus —
a green "byte-identical" claim over 3 happy-path fixtures is not evidence of equivalence.**
For any duplicated-implementation contract (perl/python strip, TS/SQL normalizer, a
regex mirrored across languages), the fixtures MUST include the boundary/degenerate
inputs where dialect differences live: empty blocks, no-trailing-newline, adjacent
delimiters, single-line inputs. When in doubt, a quick fuzz (random inputs through both,
diff the outputs) surfaces the divergent class the hand-picked fixtures missed. Prefer
writing ONE algorithm in both languages (split-and-scan) over two regex dialects that
must be proven equivalent input-by-input.

## Session Errors

- **strip.sh↔strip.py empty-frontmatter divergence** — Recovery: `^`-anchored `/ms`
  regex + `empty-frontmatter-body.in` fixture. **Prevention:** parity-test fixture
  corpora for cross-language contracts must include empty/boundary inputs (this learning).
- **Gate delta over/under-scoping** — Recovery: quote-aware commit-segment parser +
  3 regression tests. **Prevention:** commit-audit gates scope the delta to the commit's
  recorded set (this learning).
- **ADR provisional-ordinal collision** — plan's provisional ADR-085 was taken by a
  sibling PR (#6007) before ship; renumbered to ADR-086 + swept 16 refs. Recovery:
  `git ls-tree origin/main` + `scripts/check-adr-ordinals.sh` (CI gate). **Prevention:**
  already codified — plans mark ADR ordinals provisional and re-verify at work/ship;
  `check-adr-ordinals.sh` is the mechanical CI backstop. One-off per this feature.
- **CWD persistence after `cd apps/web-platform`** — a later `git add` ran from that dir
  and failed `pathspec did not match`. Recovery: absolute `cd` to worktree root.
  **Prevention:** chain `cd <abs> && <cmd>` in one Bash call (existing guidance;
  one-off).
- **Self-caught dev bugs (over-strip subshell scope-loss; sentinel guard false-fire on
  fixtures lacking the sentinel; loader sourcing strip.sh from REPO_ROOT instead of
  hook-relative; ADR verbatim statement line-wrapped)** — all caught by the test-first
  RED/GREEN loop before review. **Prevention:** the process worked; noted for the record.
  The subshell scope-loss (a global set inside `$(...)` is lost) is an already-known
  class (review skill Sharp Edges) — restated here as a recurring bash foot-gun.
- **Enforcement-tags lint pre-existing red (11 unresolved tags on main)** — not this
  PR's regression; already tracked as #4622. **Prevention:** N/A (pre-existing, tracked).
