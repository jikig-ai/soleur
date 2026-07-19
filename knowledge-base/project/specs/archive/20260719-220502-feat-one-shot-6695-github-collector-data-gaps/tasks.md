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

- [x] 1.1 Confirm `jq --version` ≥ 1.6 supports `--slurpfile` (verified `jq-1.8.1` at plan time).
- [x] 1.2 ~~Read `resolveOutputAwareOk`.~~ **Resolved at deepen time — it CANNOT express the
      condition.** `verifyScheduledIssueCreated` (`_cron-shared.ts`) requests only
      `labels`/`since`/`sort`/`per_page` and returns `issues.some(i => updated_at >= sinceMs)`
      — a presence check that never reads the issue body. Both the fabrication path and the
      honest-failure path return GREEN through it. **D5 is now a collector-status sidecar
      (§4c).** Instead confirm: (a) the handler can read a file from `spawnCwd` before
      `teardownEphemeralWorkspace`; (b) the read is NOT placed behind
      `if (heartbeatOk && !spawnResult.abortedByTimeout)` (the `safe-commit-pr` gate), or it is
      unreachable on exactly the runs that matter.
- [x] 1.3 Re-establish the RED baseline: confirm `github activity 1` and `contributors 1` fail
      with "Argument list too long", and that the stargazer pipeline is poisonable by stderr.
- [x] 1.4 Confirm the five unbounded `--argjson` bindings and the single multi-line stargazer
      defect site are where the plan says (AC2 / AC3 commands, both executed at plan time).

## 2. Test helper (blocking — the suite cannot be written without it)

- [x] 2.1 Add `make_gh_api_stub` to `plugins/soleur/test/test-helpers.sh`. **Additive only** —
      the file is shared by ~21 suites. Existing `make_gh_stub` handles only `gh run list`
      and is unusable here.
- [x] 2.2 Stub must dispatch on `$1 == "api"` by URL substring, handle `auth status` → exit 0,
      and support **three modes**: (a) large valid payload (>131,072 B in one arg);
      (b) valid stdout **plus stderr noise**; (c) **exit 0 with an error JSON body**
      (`{"message":"Not Found"}`). Mode (c) is non-optional — it is the only way to test the
      "plausible 0" path (H3), which is otherwise unverifiable.

## 3. RED — regression tests (`cq-write-failing-tests-before`)

Create `plugins/soleur/skills/community/test/github-community.test.sh`. Fixtures
**synthesized**, never captured (`cq-test-fixtures-synthesized-only`). Set `TMPDIR` to a
**private per-test directory** so cleanup assertions cannot false-fail on a shared `/tmp`.

- [x] 3.1 **Large payload (RC1) — parametric over ALL THREE commands / FIVE bindings**
      (`issues`+`prs`, `commits`+`issues`, `stargazers`). Payload > **131,072 B** in one arg.
      Assert exit 0 **and `count == (items|length)`** for each — NOT merely "non-empty JSON",
      which passes on the defect. The silent shape is **partial** unwrapping (projection fixed,
      `length` left as-is → `{"count":1,"items":[…all…]}` at exit 0, verified). One-binding
      coverage misses e.g. `prs` wrong while `issues` right — a partially-correct digest that
      looks exactly like a quiet day.
- [x] 3.2 **stderr noise on the stargazer path (RC2).** Valid JSON on stdout + noise on stderr.
      Assert `repo-stats` parses **and** the diagnostic still carries the cause (D3).
      Fails today with `parse error`.
- [x] 3.3 **Exit-0-with-error-body (RC3/D6/H3).** Stub mode (c): exit 0 + `{"message":"Not Found"}`.
      Assert non-zero exit and that **no numeric `stargazers_count` / `new_stargazers_count`**
      is emitted. Without this the "0 new stargazers" fabrication path stays open.
- [x] 3.4 **Multi-tempfile cleanup on a FAILURE path (D7/M1).** Exercise a two-tempfile command
      (`activity` or `contributors`) with a forced mid-command failure; assert the private
      `TMPDIR` is empty. A single-tempfile test cannot detect the trap-replacement leak.
- [x] 3.5 **Sidecar records (D5).** With `SOLEUR_COLLECTOR_STATUS_DIR` set, assert one JSONL
      record with the real exit code for both a success and a failure run; with it unset,
      assert nothing is written.
- [x] 3.4 Anchor every assertion on call-form / `^[[:space:]]*` (`cq-assert-anchor-not-bare-token`).
      Mutation-testing is deferred to 4.7 — there is no fix to break yet.

## 4. GREEN — script fixes (`plugins/soleur/skills/community/scripts/github-community.sh`)

- [x] 4.1 (D1) Convert the **5 unbounded bindings** to tempfile + `--slurpfile`:
      `issues`+`prs` (`cmd_activity`), `commits`+`issues` (`cmd_contributors`),
      `stargazers` (`cmd_repo_stats`). Leave `repo_data` (7,013 B) and `days` as `--argjson`.
- [x] 4.2 (D1) **Rewrite the jq programs for the array-wrapping shape.** `--slurpfile x f` makes
      `$x` = `[[…]]`. Every `$issues[]` / `$prs[]` / `$commits[]` / `$stargazers[]` reference
      must be updated. Getting this wrong silently emits `count: 1` with a green exit.
- [x] 4.3 (D3) Fix the **stargazer fetch only**: separate stderr capture
      (`>"$out" 2>"$err"`), emit `GITHUB_COLLECTOR_CAUSE=` from `$err`.
      **Do NOT sweep `2>&1` globally** — see 4.4.
- [x] 4.4 (D3) Verify the non-defect `2>&1` sites survive: the two `validate_gh`
      `>/dev/null 2>&1` discard idioms, the `cmd_discussions` error-classification capture
      (its graceful "Discussions not enabled" path depends on it), and the five variable
      captures that are the error diagnostic.
- [x] 4.5 (D2) Cap detection: when a fetch returns exactly `per_page` items, emit a truncation
      warning on stderr. ~3 lines. Not pagination.
- [x] 4.6 (D6) Shape assertion at **every fetch site**, not just `$repo_data`. Add
      `check_array_response()` rejecting any non-array payload (precedent anchor
      `Shape validation BEFORE any` in `linkedin-community.sh`). **Why it must be every site:**
      a 404/403/410 body reaches jq as an object, `check_rate_limit` matches only `rate limit`,
      and an unguarded `$stargazers` renders `new_stargazers_count: 0` — indistinguishable from
      a quiet day. Keep the `(.stargazers_count | type) == "number"` check on `$repo_data`.
- [x] 4.7 (D7) **ONE** `trap 'rm -f "$a" "$b"' EXIT` listing every tempfile — **not one trap per
      file.** EXIT traps are global and singular; a second `trap` REPLACES the first, silently
      leaking all but the last on every run (verified: naive two-trap → 1 leaked; single trap →
      0). Do **not** use a `_mktemp()` helper that appends to an array and returns via `$( )`
      — the append is lost in the subshell (verified: array size 0, 2 leaked).
      **`EXIT`, never `RETURN`** — `RETURN` does not fire on `exit`, leaking on the `exit 1`
      branches (verified: RETURN leaked 1, EXIT leaked 0).
      Fix the existing `cmd_fetch_interactions` leak (`rm -f` on success paths only) too.
- [x] 4.8 **Do not write the literal tokens `--argjson` or `2>&1` in any comment in this file.**
      AC2/AC3 grep the script body; a comment describing the old form false-fails them. Say
      "the old per-page argjson accumulation" instead. (Prior occurrence:
      `learnings/test-failures/2026-06-17-grep-assertion-over-script-body-false-matches-own-comments.md`.)
- [x] 4.9 Mutation-test the 3.x assertions: break each fix, confirm the test goes red.

## 4c. Collector-status sidecar — the deterministic signal (v3, replaces old D5)

Without this, the PR **relocates** the silent-fallback hole instead of closing it: a collector
failure stays invisible to Sentry because `resolveOutputAwareOk` returns GREEN for both the
fabrication and the honest-failure path (see 1.2).

- [x] 4c.1 In `github-community.sh`, add `_record_status()` appending one JSONL record per
      dispatch (**success and failure**) to `$SOLEUR_COLLECTOR_STATUS_DIR/collector-status.jsonl`:
      `{collector,command,exit,cause}`. No-op when the env var is unset.
- [x] 4c.2 Include `{"warn":"truncated_at_per_page"}` on the record for the D2 cap case —
      **this is D2's only real consumer.** If 4c is descoped, cut D2 (task 4.5) and its
      Observability entry with it; a stderr-only warning has no reader.
- [x] 4c.3 In the handler, read the sidecar from `spawnCwd` **before** teardown. Any record with
      `exit != 0` → `reportSilentFallback` **and** force `heartbeatOk = false`.
- [x] 4c.4 (M4) Emit `reportSilentFallback` **unconditionally** on a non-zero record and set
      `heartbeatOk` independently of `resolveOutputAwareOk`'s return — its `catch` branch
      returns `spawnOk` (fail-open, #5139) and would otherwise mask the new signal.
- [x] 4c.5 (D5b) **Fabrication detector:** collector recorded `repo-stats exit != 0` AND the
      digest contains a Repository Stats number → `reportSilentFallback` + heartbeat RED.
      This is the *only* deterministic control on RC3 — the §5 prompt edits are a probability
      shift, not enforcement. Must NOT fire on an honest `collection failed:` digest.

## 4b. Correct the institutional record (deepen-plan finding)

- [x] 4b.1 Fix the threshold model in
      `knowledge-base/project/learnings/integration-issues/2026-03-28-gh-api-paginate-argument-list-too-long.md`.
      It attributes the limit to `ARG_MAX` (~2 MB) and concludes the sibling `--argjson` sites are
      safe "because stargazers are small". The real ceiling is **`MAX_ARG_STRLEN` = 131,072 B per
      argument**. That error is precisely why the 2026-03-28 fix was applied to
      `cmd_fetch_interactions` only and never back-propagated to `cmd_activity`/`cmd_contributors`.
      Cross-reference the correct model already recorded in
      `learnings/bug-fixes/2026-06-18-sibling-script-shares-byte-identical-argv-accumulation-defect.md`.

## 5. Consumer wiring — `apps/web-platform/server/inngest/functions/cron-community-monitor.ts`

Contract (§4) must land before this.

- [x] 5.1 (D4a) Add a GitHub collection-failure clause at anchor
      `The ## GitHub Activity section must include`, mirroring the working LinkedIn clause at
      anchor `To distinguish`. Require `collection failed: <reason>`; **forbid carry-forward
      from a prior digest**.
- [x] 5.2 (D4b) Require `period_days` to be stated **from the collector JSON**, never inferred.
      (This — not a `days` change — is the real fix for the fabricated 41-day period.)
- [x] 5.3 (D4c) **Amend the standing permission** at anchor
      `If any command in a batch fails, log the error and continue.` Appending 5.1 without
      amending this leaves two contradictory instructions; the vaguer one tends to win. Not optional.
- [x] 5.4 (D5) Treat a digest containing `collection failed:` as a non-ok output condition so it
      mirrors to Sentry through the existing `reportSilentFallback` / `resolveOutputAwareOk`
      path under `SENTRY_MONITOR_SLUG`. Implement per the 1.2 finding.

## 6. Verify

- [x] 6.1 Run all five subcommands against `jikig-ai/soleur` at `days=1`; each returns real,
      non-empty data (AC1).
- [x] 6.2 Run the AC2 / AC3 verification commands verbatim from the plan; confirm the expected
      transitions (5→0 unbounded `--argjson`, 0→5 `--slurpfile`, 1→0 stderr-into-jq).
- [x] 6.3 Confirm counter-assertions (AC3): `validate_gh` idioms intact, `cmd_discussions`
      graceful path still exits 0 (AC4).
- [x] 6.4 `bash scripts/test-all.sh` (`TEST_GROUP=scripts`) green; new suite picked up.
- [x] 6.5 PR body uses **`Ref #6695`**, not `Closes` (`wg-use-closes-n-in-pr-body-not-title-to`).

## 7. Follow-ups (file as separate issues — do not fold in)

- [x] 7.1 `/tmp` leak in `apps/web-platform/infra/workspaces-luks-freeze.test.sh` — 9,470 leaked
      `mktemp` files (1.9 GB) observed during planning. Labels `bug`, `domain/engineering`,
      `priority/p2-medium` (all verified to exist).
- [x] 7.2 Why the community-monitor cron produced no committed digest for 41 days (newest is
      `2026-06-08`). An availability question, not a collector bug.
