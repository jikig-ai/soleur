---
title: "Tasks — fix GitHub community-monitor collector data gaps"
issue: 6695
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-19-fix-github-collector-data-gaps-plan.md
date: 2026-07-19
---

# Tasks: #6695 GitHub collector data gaps

Derived from the finalized (post-review) v2 plan. Scope is **three defects**, not five —
plan review cut pagination (RC4) and the `days` change (RC5) as measured non-defects at the
production window. See the plan's Review Reconciliation before re-expanding scope.

Runner: `bash scripts/test-all.sh` (`TEST_GROUP=scripts`). New suite is auto-globbed —
no registration needed.

**Cite content anchors, not line numbers** (`cq-cite-content-anchor-not-line-number`).

## 1. Setup / Preconditions

- [ ] 1.1 Confirm `jq --version` ≥ 1.6 supports `--slurpfile` (verified `jq-1.8.1` at plan time).
- [ ] 1.2 **Read `resolveOutputAwareOk` end-to-end** in `cron-community-monitor.ts` and confirm
      it can express "digest contains a failure marker" (plan D5). This is the plan's one
      unread mechanism. If it cannot, fall back to an explicit `reportSilentFallback` call in
      the persistence step and record the deviation.
- [ ] 1.3 Re-establish the RED baseline: confirm `github activity 1` and `contributors 1` fail
      with "Argument list too long", and that the stargazer pipeline is poisonable by stderr.
- [ ] 1.4 Confirm the five unbounded `--argjson` bindings and the single multi-line stargazer
      defect site are where the plan says (AC2 / AC3 commands, both executed at plan time).

## 2. Test helper (blocking — the suite cannot be written without it)

- [ ] 2.1 Add `make_gh_api_stub` to `plugins/soleur/test/test-helpers.sh`. **Additive only** —
      the file is shared by ~21 suites. Existing `make_gh_stub` handles only `gh run list`
      and is unusable here.
- [ ] 2.2 Stub must: dispatch on `$1 == "api"` by URL substring; handle `auth status` → exit 0;
      support emitting stderr noise alongside valid stdout (for the RC2 case); support an
      error-body mode (for the RC3/D6 case).

## 3. RED — regression tests (`cq-write-failing-tests-before`)

Create `plugins/soleur/skills/community/test/github-community.test.sh`. Fixtures
**synthesized**, never captured (`cq-test-fixtures-synthesized-only`). Set `TMPDIR` to a
**private per-test directory** so cleanup assertions cannot false-fail on a shared `/tmp`.

- [ ] 3.1 **Large payload (RC1).** Single JSON argument > **131,072 B** (`MAX_ARG_STRLEN`, not
      `ARG_MAX`). Assert exit 0 and an exact item count. Fails today with E2BIG.
      Trailing `assert_file_not_exists` on the private `TMPDIR` (covers D7).
- [ ] 3.2 **stderr noise on the stargazer path (RC2).** Valid JSON on stdout + noise on stderr.
      Assert `repo-stats` parses **and** the diagnostic still carries the cause (D3).
      Fails today with `parse error`. Trailing cleanup assertion.
- [ ] 3.3 **No fabricated stat (RC3/D6).** Error body → assert non-zero exit and that **no
      numeric `stargazers_count`** is emitted.
- [ ] 3.4 Anchor every assertion on call-form / `^[[:space:]]*` (`cq-assert-anchor-not-bare-token`).
      Mutation-testing is deferred to 4.7 — there is no fix to break yet.

## 4. GREEN — script fixes (`plugins/soleur/skills/community/scripts/github-community.sh`)

- [ ] 4.1 (D1) Convert the **5 unbounded bindings** to tempfile + `--slurpfile`:
      `issues`+`prs` (`cmd_activity`), `commits`+`issues` (`cmd_contributors`),
      `stargazers` (`cmd_repo_stats`). Leave `repo_data` (7,013 B) and `days` as `--argjson`.
- [ ] 4.2 (D1) **Rewrite the jq programs for the array-wrapping shape.** `--slurpfile x f` makes
      `$x` = `[[…]]`. Every `$issues[]` / `$prs[]` / `$commits[]` / `$stargazers[]` reference
      must be updated. Getting this wrong silently emits `count: 1` with a green exit.
- [ ] 4.3 (D3) Fix the **stargazer fetch only**: separate stderr capture
      (`>"$out" 2>"$err"`), emit `GITHUB_COLLECTOR_CAUSE=` from `$err`.
      **Do NOT sweep `2>&1` globally** — see 4.4.
- [ ] 4.4 (D3) Verify the non-defect `2>&1` sites survive: the two `validate_gh`
      `>/dev/null 2>&1` discard idioms, the `cmd_discussions` error-classification capture
      (its graceful "Discussions not enabled" path depends on it), and the five variable
      captures that are the error diagnostic.
- [ ] 4.5 (D2) Cap detection: when a fetch returns exactly `per_page` items, emit a truncation
      warning on stderr. ~3 lines. Not pagination.
- [ ] 4.6 (D6) Shape assertion on `$repo_data` — `(.stargazers_count | type) == "number"`
      before emit (precedent anchor `Shape validation BEFORE any` in `linkedin-community.sh`).
- [ ] 4.7 (D7) `trap 'rm -f …' EXIT` on every tempfile, **including the existing
      `cmd_fetch_interactions` leak** (`rm -f` on success paths only today).
      **`EXIT`, never `RETURN`** — a `RETURN` trap does not fire on `exit`, so the `exit 1`
      failure branches would leak the spool (per the 2026-06-18 learning).
- [ ] 4.8 **Do not write the literal tokens `--argjson` or `2>&1` in any comment in this file.**
      AC2/AC3 grep the script body; a comment describing the old form false-fails them. Say
      "the old per-page argjson accumulation" instead. (Prior occurrence:
      `learnings/test-failures/2026-06-17-grep-assertion-over-script-body-false-matches-own-comments.md`.)
- [ ] 4.9 Mutation-test the 3.x assertions: break each fix, confirm the test goes red.

## 4b. Correct the institutional record (deepen-plan finding)

- [ ] 4b.1 Fix the threshold model in
      `knowledge-base/project/learnings/integration-issues/2026-03-28-gh-api-paginate-argument-list-too-long.md`.
      It attributes the limit to `ARG_MAX` (~2 MB) and concludes the sibling `--argjson` sites are
      safe "because stargazers are small". The real ceiling is **`MAX_ARG_STRLEN` = 131,072 B per
      argument**. That error is precisely why the 2026-03-28 fix was applied to
      `cmd_fetch_interactions` only and never back-propagated to `cmd_activity`/`cmd_contributors`.
      Cross-reference the correct model already recorded in
      `learnings/bug-fixes/2026-06-18-sibling-script-shares-byte-identical-argv-accumulation-defect.md`.

## 5. Consumer wiring — `apps/web-platform/server/inngest/functions/cron-community-monitor.ts`

Contract (§4) must land before this.

- [ ] 5.1 (D4a) Add a GitHub collection-failure clause at anchor
      `The ## GitHub Activity section must include`, mirroring the working LinkedIn clause at
      anchor `To distinguish`. Require `collection failed: <reason>`; **forbid carry-forward
      from a prior digest**.
- [ ] 5.2 (D4b) Require `period_days` to be stated **from the collector JSON**, never inferred.
      (This — not a `days` change — is the real fix for the fabricated 41-day period.)
- [ ] 5.3 (D4c) **Amend the standing permission** at anchor
      `If any command in a batch fails, log the error and continue.` Appending 5.1 without
      amending this leaves two contradictory instructions; the vaguer one tends to win. Not optional.
- [ ] 5.4 (D5) Treat a digest containing `collection failed:` as a non-ok output condition so it
      mirrors to Sentry through the existing `reportSilentFallback` / `resolveOutputAwareOk`
      path under `SENTRY_MONITOR_SLUG`. Implement per the 1.2 finding.

## 6. Verify

- [ ] 6.1 Run all five subcommands against `jikig-ai/soleur` at `days=1`; each returns real,
      non-empty data (AC1).
- [ ] 6.2 Run the AC2 / AC3 verification commands verbatim from the plan; confirm the expected
      transitions (5→0 unbounded `--argjson`, 0→5 `--slurpfile`, 1→0 stderr-into-jq).
- [ ] 6.3 Confirm counter-assertions (AC3): `validate_gh` idioms intact, `cmd_discussions`
      graceful path still exits 0 (AC4).
- [ ] 6.4 `bash scripts/test-all.sh` (`TEST_GROUP=scripts`) green; new suite picked up.
- [ ] 6.5 PR body uses **`Ref #6695`**, not `Closes` (`wg-use-closes-n-in-pr-body-not-title-to`).

## 7. Follow-ups (file as separate issues — do not fold in)

- [ ] 7.1 `/tmp` leak in `apps/web-platform/infra/workspaces-luks-freeze.test.sh` — 9,470 leaked
      `mktemp` files (1.9 GB) observed during planning. Labels `bug`, `domain/engineering`,
      `priority/p2-medium` (all verified to exist).
- [ ] 7.2 Why the community-monitor cron produced no committed digest for 41 days (newest is
      `2026-06-08`). An availability question, not a collector bug.
