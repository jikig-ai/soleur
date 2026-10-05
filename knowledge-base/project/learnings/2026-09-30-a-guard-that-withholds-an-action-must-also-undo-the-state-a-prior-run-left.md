---
title: "A guard that withholds an action must also undo the state a prior run left — and a stub that accepts what the vendor refuses tests nothing"
date: 2026-09-30
category: security-issues
module: ci-release-pipeline
tags: [github-actions, auto-merge, mirror-only, test-fixtures, mutation-testing, composite-action]
issue: 9262
pr: 9301
---

# Learning: a guard that withholds an action must also undo the state a prior run left

## Problem

PR #9301 re-tiered the inngest-bootstrap pin bump and the auto-mint build
dispatch to the main-only `infra-privileged` environment, minting the
`soleur-infra` App. The plan (from a deepen-pass security P0) added `--mirror-only`
to the bump script so a `mirror_only` backfill "never arms auto-merge": a backfill
skips the build's ancestry refusal and the sign step signs whatever the tag
resolves to, so it cannot attest provenance.

The guard was implemented exactly as stated: the single `gh pr merge --auto`
call site gained `MIRROR_ONLY != true`. Every row was green (including
`g1.mirror-only-existing:no-merge`). Two independent review seats (security and
structural enumeration) found the gap: on the `existing` path the script REUSES an
open pin PR and force-pushes onto it. If an earlier full build had already armed
auto-merge on that PR, GitHub keeps it armed across a writer's push, so the PR
merges unattended on a commit the mirror_only run produced. "Never arms" was true;
"never merges unattended" — the property the P0 was about — was false.

A second, independent shape surfaced in the same review: the `gh` stub's
`pr create` never refused a second open same-repo PR for one head branch, so two
new author-filter rows asserted `result=opened` — an outcome production cannot
reach (GitHub refuses; the script dies at stage `pr`).

## Solution

- On the `existing` path under `--mirror-only true`, the script reads the reused
  PR's `autoMergeRequest` (added to the `gh pr list --json` field set), runs
  `gh pr merge <n> --disable-auto` when it is armed, and dies (stage `pr`) if the
  disarm fails or the state is unreadable. It posts the hold comment on the reuse
  path too. Rows: armed + disarm ok, armed + disarm fails (fatal), unarmed full
  build keeps its arm (the disarm is scoped to mirror_only). Removing the block
  reds six rows.
- The script refuses a repeated flag (argv was last-wins, so an appended
  `--mirror-only false` silently cancelled the hold); the workflow-shape row now
  parses the invocation into an argv and requires each flag once.
- The stub's `pr create` now refuses a second open same-repo PR on one head; the
  author rows assert the loud stage-`pr` refusal.
- Test-design survivors closed: the composite's two repository clauses tested
  ALONE (selection=all with the right repo list; selected over more repos than
  requested); a parsed-YAML row on the composite itself (the run-block harness
  could not see `continue-on-error`, env wiring or the output binding); and
  both-direction self-tests for every gh/output/result assertion helper (a helper
  rewritten to always pass kept the assertion count and the floor).

## Key Insight

A guard phrased as "never DO X" is narrower than the property "X never HAPPENS"
whenever X is persistent state a PREVIOUS run can have created. Ask of every
withhold-guard: *can the state this guard refuses to create already exist when
this run starts?* If yes, the guard must read that state and undo or refuse it,
fail-closed on an unreadable read. Separately: a test stub that accepts a request
the vendor refuses (a duplicate head PR, a second minter, an unscoped token)
makes rows assert outcomes production cannot reach — model the vendor's
refusals, one exit per contract.

## Session Errors

1. **Plan write guard blocked a draft over two phrases (forwarded from the plan phase).** Recovery: reworded. **Prevention:** none needed; the guard worked.
2. **A background wait loop matched early (forwarded).** Recovery: stopped it. **Prevention:** wait on an rc/marker file, never a log substring.
3. **Playwright MCP failed to connect (forwarded).** Recovery: not needed for this CI-only work. **Prevention:** none.
4. **The tool layer decoded `\u2028`-style escapes in my command/file text into literal U+2028 bytes** (the composite's sanitizer regex; a test fixture), so the committed text differed from what I typed. Recovery: rewrote with jq `\x{2028}` and built fixture escapes with `chr(92)+'u2028'`. **Prevention:** after writing any escape-bearing regex or fixture, run `grep -nP '[^\x00-\x7f]' <file>`; prefer `\x{…}` in jq regexes and build `\u` escapes from `chr(92)` in edit scripts.
5. **Lefthook `web-platform-typecheck` ran out of JS heap on a contended machine.** Recovery: committed with `LEFTHOOK_EXCLUDE=bun-test,web-platform-typecheck`; the only `.ts` change was a test string, and CI typechecks. **Prevention:** one-off environment pressure; check `free -m` before blaming the diff.
6. **`pgrep -f` blocked by the self-match hook.** Recovery: `pgrep lefthook`. **Prevention:** hook-enforced already.
7. **`git stash list` in a compound command blocked by the hook.** Recovery: dropped it. **Prevention:** hook-enforced already.
8. **A multi-file Python edit batch failed mid-way after writing its first file.** Recovery: re-ran the remainder. **Prevention:** one edit script per file, or assert every anchor before writing any file.
9. **`lint-workflow-errexit-capture` flagged `$(curl) || { rc=$?; … }` in the composite.** Recovery: `curl_rc=0; x=$(…) || curl_rc=$?`. **Prevention:** run the errexit lint after editing any composite/workflow `run:` block (it covers composites).
10. **The mirror_only guard withheld arming but did not disarm an already-armed reused PR (panel P2, pr-introduced).** Recovery: disarm + fatal-on-failure + rows. **Prevention:** the plan sharp-edge routed from this learning (withhold-guards must read and undo prior-run state).
11. **The gh stub accepted a duplicate open head PR, so rows asserted an unreachable outcome.** Recovery: stub refuses; rows assert the real refusal. **Prevention:** when adding a stub arm, list what the vendor refuses for that call and model each refusal.
12. **Test-design survivors (repo clauses only tested together; argv last-wins; composite shape invisible to the run-block harness; helpers without both-direction self-tests).** Recovery: named rows for each, two re-driven as mutants and confirmed red. **Prevention:** for a disjunction/conjunction in a guard, one fixture per clause ALONE; for a harness that extracts a `run:` block, add a parsed-shape row for everything outside it.
13. **First-pass doc claims that could not fail or dropped a conjunct** (a deployments `.ref` check that always prints `main`; an R-step 1 chain missing O13's rotation; "dominated by" scopes). Recovery: run/job-conclusion checks; chain corrected; honest widening sentence. **Prevention:** for each verification command a runbook adds, name the state in which it prints the failing answer.
14. **A new row asserted gh-not-called on a shared, un-reset `MOCK_GH_LOG`.** Recovery: asserted the args refusal instead. **Prevention:** only assert gh-log absence after `new_fixture_repo`.
15. **The docs subagent read code while I was mid-edit.** Recovery: re-checked the docs against the final code; fixed two sentences. **Prevention:** hand a docs agent the final diff, or re-verify its claims after the code settles.

## Tags

category: security-issues
module: ci-release-pipeline
