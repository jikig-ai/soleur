---
title: Every execution-placement guard was narrower than its name, and my battery mutated only whole chokepoints
date: 2026-09-28
category: test-failures
tags: [guards, mutation-testing, review, inngest, placement, repo-wide-suites, merge-conflicts]
issue: 7230
pr: 9134
---

# Learning: every guard was narrower than its name, and my battery mutated only whole chokepoints

## Problem

PR #9134 (#7230) shipped a data-only Inngest execution-placement manifest plus four TS-AST
guards. The author ran a 15-row mutation battery that neutered each guard's chokepoint wholesale
(`return []` at the top of each helper) and got 15/15 KILLED. The 11-seat review then found:

- **Guard 4** ("one step-executing host") recognised only a binding named `serve` from a one-segment
  `inngest/<x>` path in `.ts`/`.tsx` files under `app/`, `server/`, `lib/`. `connect`
  (`inngest/connect`), `createServer`, `InngestCommHandler` (root `inngest`), `inngest/deno/fresh`,
  a `.js` route and root `middleware.ts` all passed green.
- **Guard 3** scanned `.ts`/`.mjs` only and matched whole string literals, so every computed name
  and non-TS module passed.
- **Guard 2**'s allowlisted-body scan missed `await import("node:child_process")`, `require`/`import =`
  bindings and `export { impl as X }` aliases; its anti-vacuity floor counted only `@/server/*`
  specifiers, which the ever-present `@/server/inngest/client` import always satisfied.
- **19 branch-level mutants** (e.g. `startsWith(".")` → `startsWith("./")`, `.every` → `.some` in the
  type-only elision) survived the whole-chokepoint battery.
- **CI red**: the suite reads the repo-root `.github/workflows/`, so `repo-wide-containment` required
  it in `REPO_WIDE_SUITES`; and Guard 2 hit 17.9 s against the 16 s per-test timeout from re-parsing
  each module ~21×.

## Solution

- One shared import-edge extractor (`moduleEdges` in `test/helpers/ts-import-graph.ts`) now feeds the
  walker and every guard, so an import form handled for one guard is handled for all.
- Widened each guard to the shapes enumerated by the structural seat, and recorded the rest as named
  known gaps in the ADR-033 amendment. Guards 3 and 4 are described as regression lints, not
  enforcement.
- One fixture per branch, and a 32-row BRANCH-level battery (each row deletes one branch, not a
  whole helper): 32/32 killed against a green control, tree restored byte-for-byte.
- Parse cache keyed by path AND source text (fixture filesystems reuse one path with different
  contents; a path-only key hands a guard a stale tree and a silent pass) plus a per-call scan memo:
  the file dropped from ~16 s to ~2 s.

## Key Insight

A battery that mutates each chokepoint wholesale proves each check can fire once. It says nothing
about the branches inside that check, and those branches are where the guard is narrower than its name.
Mutate per BRANCH, and ask the structural question up front — "enumerate every path to the sink and
say which the guard covers" — before writing fixtures.

## Session Errors

1. **Two `gh issue create` calls were blocked by filing hooks during planning.** Recovery: re-ran
   with an absolute `--body-file` and the required marker. **Prevention:** already hook-enforced;
   run `gh issue create` alone in its own Bash call with an absolute body path.
2. **No `spec.md` for the branch, so `lane:` defaulted to cross-domain.** Recovery: none needed.
   **Prevention:** one-off (one-shot entered from an issue, not a brainstorm).
3. **A background commit's notification read "exit 0" while HEAD had not moved; the lefthook affected
   gate was still running.** Recovery: `kill_mine test-all.sh`/`lefthook`, recommit with
   `LEFTHOOK_EXCLUDE=bun-test` (operator had ruled "rely on CI plus targeted ratchets").
   **Prevention:** existing rule — read `COMMIT_RC` and `git log -1`, never the notification.
4. **A `pgrep -f` in a compound Bash call was blocked, and the block took a Python patch in the same
   call down with it.** Recovery: re-ran the patch alone. **Prevention:** keep process probes in
   their own call; use `proc.sh list_runs`.
5. **Write refused to overwrite the suite (not Read in this context), wasting a full-file send.**
   Recovery: Read, then Write. **Prevention:** Read any file you are about to fully rewrite first.
6. **`git checkout --theirs model.c4` took main's WHOLE file and silently dropped this branch's
   non-conflicting edits (an edge re-source and edge prose).** Recovery: `git checkout -m <file>`
   recreated the markers; resolved only the conflicting hunk. **Prevention:** routed to
   `drain-prs/SKILL.md` (b) — never side-pick a hand-authored file; for the generated
   `model.likec4.json` use `resolve-regenerable-conflicts.sh`.
7. **`main` moved twice during review (GHCR minter retirement, then a host-key change).** Recovery:
   two merges; dropped the retired minter's manifest row and C4 edges. **Prevention:** existing rule
   — re-run `git merge-tree` against fresh `origin/main` before spawning the panel and before ship.
8. **The plan's 14-name allowlist was seeded from direct imports only; allowlisted bodies reached 4
   more pure exports.** Recovery: seeded them with a comment. **Prevention:** seed an allowlist by
   running the body scan, not by grepping import lines.
9. **The own-dispatch fixture row went red for the wrong reason after the floor fix (a relative
   import into `server/` now satisfied it).** Recovery: a resolver that drops every edge.
   **Prevention:** after changing a floor, re-derive every row that asserts it trips.
10. **A computed `process.env` key marker false-flagged 35 host-free functions (a generic secret
    reader).** Recovery: dropped the marker, recorded the gap. **Prevention:** run a widened guard
    on the real tree before writing its fixtures.
11. **The whole-chokepoint battery missed 19 branch-level mutants.** Recovery: per-branch fixtures
    and battery. **Prevention:** see Key Insight.
12. **The new suite was not registered in `REPO_WIDE_SUITES`; CI `test-webplat (2/2)` went red.**
    Recovery: registered it. **Prevention:** when a new test reads outside `apps/web-platform`, run
    `test/repo-wide-containment.test.ts` in the targeted local set.
13. **Guard 2 timed out once locally (17.9 s / 16 s).** Recovery: parse cache + scan memo.
    **Prevention:** give real-tree AST walks an explicit timeout and a parse cache from the start.
14. **A review seat detached HEAD in the shared worktree.** Recovery: the seat reattached; verified
    branch and SHA. **Prevention:** existing — give repo-touching seats a detached worktree.
15. **One reviewer overwrote another's file in the shared scratch `review/` dir.** Recovery: the
    affected seat moved its files. **Prevention:** existing — brief seat-unique file names.
16. **`tenant-integration` failed on a transient Supabase JWT-mint rate limit.** Recovery: re-run.
    **Prevention:** one-off (vendor rate limit; green on main).
17. **A brace glob (`ADR-0{100,...}`) missed four ADRs in a markdownlint run.** Recovery: linted them
    by full name. **Prevention:** lint the exact `git diff --name-only` list, never a hand glob.
18. **The history seat reported 57 manifest functions (actual 69).** Recovery: disregarded; verified
    against the leaf and Guard 1. **Prevention:** treat an agent's count as a claim to re-derive.
19. **Two pre-existing false ADR claims:** ADR-100 named #7230 as owner of its `accepted` flip (it is
    #6178), and a 2026-09-23 amendment stated a 15-minute TTL its own PR set to 2 h. Recovery:
    corrected with markers. **Prevention:** when an ADR cites the issue you are closing, grep for it
    and re-point the pointer.

## Tags

category: test-failures
module: apps/web-platform/test/server/inngest
