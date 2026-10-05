---
title: A blocking gate over shared dev must say who owns each row
date: 2026-09-23
category: workflow-patterns
tags: [dev-supabase, migrations, ledger, ci, per-ref, adr-061, mutation-testing]
pr: 8602
issues: [8520, 8521, 7964, 8605, 8606]
---

# Learning: a blocking gate over shared dev must say who owns each row

## Problem

On 2026-09-22 every push to main went red (runs 35732801080, 35736906203) on
`Missing-on-main: 139_openai_api_key_provider.sql`. That row had been legitimately applied by an
open PR, and main stayed red until that PR merged. The ledger drift probe had been made BLOCKING on
push by #7964, whose plan (§M2) assumed that "on push … there is no legitimate unmerged-migration
state". ADR-061's own Context already said the opposite: shared dev is the union of main plus every
open PR's applied-but-unmerged migrations. The alternative ADR-061 had rejected ("blocking
orphan-migration-drift probe on push:main") had been reintroduced, and its predicted failure came
true.

Separately, 26 ledger rows had content drift (same filename, different blob): PRs edited a
migration after their CI had applied it, and the runner never re-applies a ledgered filename (#8521).

## Solution

- **Main side (`dev-ledger-parity.sh classify-missing`, called by the drift probe):** a
  missing-on-main row is an in-flight warning only when a fresh (at most 30 whole days old),
  unmerged origin branch holds it among its top-level files that are *not on main*, matched by
  exact name, blob or slug, and its filename never appeared in main's history. An ownerless row,
  a stale-owned row, an in-history row or an unclassifiable row blocks. It is computed git-only in
  a bare blobless owner repo; no GitHub API is involved.
- **PR side (`dev-ledger-parity.sh check`, run pre-apply in `tenant-integration.yml`):** the owning
  PR goes red when it edited (A1), renamed (A2) or deleted (A4) a migration after CI applied it.
  The rule is that a migration applied to dev is immutable, merged or not.
- ADR-061 was amended (append-only). The repair procedure is in the 2026-05-21 dev-drift learning
  under §Content drift.

## Key Insight

A gate that reads **shared mutable state** has to say, for every row it flags, **which ref owns
it**. Without that it reds refs that cannot fix the row. An ownerless row belongs to main, and an
owned row belongs to its owner. A plan that promotes such a gate to blocking inherits every premise
of the plan it builds on, so check that premise against the ADR that governs the substrate: here,
#7964's premise was contradicted by the ADR it should have cited.

Two lessons from the test battery:

- A mutation that survives can point at **dead code**, not a weak test. N3 survived because the
  owner tier it targeted was unreachable, and the fix was to replace that tier with
  `holders_at_blob`.
- A workflow block that the suite runs for real can change the suite's own fixture. The check
  step's `git fetch --depth=1` turned the test clone shallow, and the later rows then measured a
  shallow history.

## Session Errors

1. **`gh issue create` blocked by a hook because its body file did not exist yet** (plan phase).
   Recovery: wrote the file, retried. **Prevention:** write the body file before the create call.
   The hook already enforces this.
2. **The issue filing was blocked for a missing classification label.** Recovery: added
   `--label meta/machinery`. **Prevention:** hook-enforced; pass the label at the first call.
3. **The harness blocked `sleep 30`.** Recovery: waited for the agent notifications instead.
   **Prevention:** already enforced; use notifications or Monitor.
4. **An apostrophe inside `${var:-…}` broke bash parsing.** Recovery: moved the text into a
   variable. **Prevention:** never put quoting characters inside a parameter-expansion default;
   bind the text to a variable first.
5. **The instrument self-test's intentional `FAIL:` leaked into the suite output.** Recovery:
   `>/dev/null` on the self-test drive. **Prevention:** silence self-test drives so that `FAIL:`
   in the log always means a real failure.
6. **`line_no` exited non-zero under `pipefail` on a no-match grep.** Recovery: `|| true`.
   **Prevention:** treat every grep inside a `$(…)` under pipefail as able to match nothing.
7. **The raw-echo regex false-matched `$fn` because the assertion scanned the whole file.**
   Recovery: scoped it to the extracted probe step. **Prevention:** scope the assertion's input
   to the region under test (`cq-assert-anchor-not-bare-token`).
8. **The A3 mutation survived because of a stub-fixture defect (a here-string's trailing empty
   line).** Recovery: fixed the stub, and the mutation was then killed. **Prevention:** when a
   mutation survives, check the fixture before the SUT.
9. **The new files moved four repo-global ratchets** (the vacuity floor, fixture-relative,
   fixture-dir-operand and capture-exit). Recovery: promoted the suite and used the canonical
   `assert_fixture_dir` and `|| true`. **Prevention:** already covered by the work skill's
   "file-selected suite set cannot see a repo-global ratchet" rule; run the census rows.
10. **`lint-diagnosis-claims` flagged the "not caused by this PR" wording** (ADR-166).
    Recovery: reworded to report only what was measured. **Prevention:** the lint caught it as
    designed; say what the job measured, never what it did not cause.
11. **The census runner broke on row names containing `/`.** Recovery: sanitized the names.
    **Prevention:** sanitize free-text names before using them as file paths.
12. **The `TEST_GROUP=scripts` shard was refused (rc=4) because of sibling full-gate runs.**
    Recovery: ran the 49 census rows directly. **Prevention:** by design; CI's required `test`
    check is authoritative.
13. **A nested `PY` heredoc terminator closed the outer heredoc.** Recovery: wrote the block
    with the Write tool. **Prevention:** see
    `2026-04-02-yaml-literal-block-heredoc-breakage.md`; never nest heredocs, write a file.
14. **Fixture dirs went missing: git doesn't track empty dirs, and `git rm` prunes emptied
    ones.** Recovery: `mkdir -p` in the fixture setup. **Prevention:** fixtures create every
    directory they rely on.
15. **The check step's `--depth=1` fetch made the test clone shallow.** Recovery: unshallow
    before the state rows. **Prevention:** see Key Insight: a driven workflow block can mutate
    the suite's fixture.
16. **shellcheck SC2015.** Recovery: rewrote it as `if`. **Prevention:** shellcheck runs in the
    gate.
17. **The N3 mutation survived because the tier it targeted was dead code.** Recovery: replaced
    it with `holders_at_blob`. **Prevention:** see Key Insight: read a survivor as a possible
    dead branch.
18. **A hook blocked an accidental `git stash list`.** Recovery: not repeated. **Prevention:**
    hook-enforced (`hr-never-git-stash-in-worktrees`).
19. **Widening the `lint-diagnosis-claims` DIRS surfaced 2 pre-existing claims.** Recovery:
    reverted the widening, and it is recorded for the PR body. **Prevention:** a lint widening
    is its own PR, with its baseline.
20. **`orphan-process-reaper-mutations` hit the local 300 s cap under load.** Recovery: left
    to CI (the diff doesn't touch it). **Prevention:** an environment limit; CI is
    authoritative.
21. **The ADR-061 amendment's prose claimed behaviour the code didn't have**, and review
    corrected it to match the code. Its root cause, #7964's premise, conflicted with ADR-061.
    **Prevention:** plan sharp-edge (added in this PR): a plan making a gate blocking over
    shared dev must classify rows by owning ref per ADR-061.
22. **CI's `test-scripts (1/3)` went red on `battery-tag-authorship-mutations`**. Five fixture
    `git fetch` calls in the new suite lacked `--no-tags`, which the repo-wide tag-authorship
    ratchet counts as undeclared tag-authoring. The 49 locally-run census rows did not include it.
    Recovery: added `--no-tags` (the fixtures use no tags); the subject then reported `offenders=0`.
    **Prevention:** a fixture `git fetch`/`clone` in a new suite takes `--no-tags`; the work skill's
    repo-global-ratchet rule already names this class, so select census rows by ratchet, not by
    reference to the changed files.

## Tags

category: workflow-patterns
module: apps/web-platform/scripts/dev-ledger-parity.sh, .github/actions/dev-migration-drift-probe

## Addendum — 2026-09-24 (#8605)

The Solution's "no GitHub API is involved" no longer holds. `classify-missing` now reads each fresh
owner branch's pull-request state through the GitHub API (`GET /repos/{repo}/pulls?head=…`, with the
job's `GITHUB_TOKEN` and `pull-requests: read`), plus one listing of open issues per run, so it can
tell `closed-grace`, `closed` and `closed-tracked` apart.

Why: nothing in git records PR state, so a branch whose PR closed unmerged and was never deleted
kept its rows in-flight forever (ADR-061 amendment for #8605/#8606, Context). The lookups stay
fail-closed: an API or rate-limit failure, a malformed response, a failed issue lookup or the 240 s
classify deadline makes the probe report UNCLASSIFIED (blocking), never an in-flight warning. A
row whose owner cannot be established must not pass as owned, which is this learning's point.
