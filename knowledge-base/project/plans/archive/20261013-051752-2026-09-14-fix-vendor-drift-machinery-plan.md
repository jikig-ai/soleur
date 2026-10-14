---
title: "fix: vendor-drift machinery — dead re-vendor route, pin-position binding, dedup completeness, issue enrichment"
type: fix
date: 2026-09-14
slug: fix-vendor-drift-machinery
branch: feat-one-shot-8180-8181-8182-8183-vendor-drift-fixes
issue: 8180
closes: [8180, 8181, 8182, 8183]
domain: compliance
---

# fix: vendor-drift machinery — dead re-vendor route, pin-position binding, dedup completeness, issue enrichment

## Enhancement Summary

**Deepened on:** 2026-09-14
**Sections enhanced:** Proposed Solution (all four FRs), Guard Contract, Observability, References & Research
**Research agents used:** inline equivalents (no Task tool in this session) — premise validation against the live merge base, deleted-workflow archaeology, merge-mode/label/dependency audits, mechanical gate runs

### Key Improvements (deepen-pass findings folded in)

1. **Merge-base correction:** the issues describe the multi-bundle arm of the
   still-open PR #8120; this branch carries the single-bundle version.
   #8180/#8181/#8183 apply verbatim; #8182's named calls do not exist on
   main (its dedup is `total_count`-based, already complete) — the fix is
   reframed as pinning the completeness property plus the
   `fetchAllPages` helper for the post-#8120 enumeration shape.
2. **`no-changes` must be captured, not assumed away:** on main the
   `safeCommitAndPr` return is discarded; `status === "no-changes"` on this
   arm now reports unhealthy via `reportSilentFallback` (the
   `pr-route-no-artifact` equivalent already named in #8120).
3. **Reference implementation recovered:** the deleted
   `scheduled-content-vendor-drift.yml` (commit `804114883`, ancestor of
   main) contains the exact merge/NOTICE-rewrite/conflict-gate logic to
   port — including its assert-exactly-1-substitution fail-closed shape.
4. **Label gap found:** `needs-human-review` is referenced by runbook §2 but
   absent from the repo label set; AC-9 adds the one-time
   `gh label create`.
5. **Issue citation correction:** #8180 cites runbook "§2 Manual Re-vendor";
   the actual §2 is "Conflict-Marker Resolution" — the behavioral reference
   is the deleted workflow, noted in FR-1.

### Gate evaluation record

- 4.4 precedent-diff: canonical `fetchAllPages` precedent found and adopted
  (get-workstream-issue-options.ts:31-44); merge-file pattern precedent is
  the deleted workflow — both diffed against this plan's prescriptions.
- 4.5 network-outage: keyword `unreachable` matched — evaluated: it names an
  existing GitHub-API probe state inside the cron, not an SSH/firewall/
  provisioner surface (no Terraform touched); gate not applicable.
- 4.55 downtime: no reboot/migration/deploy change — not applicable.
- 4.6 user-brand: `## User-Brand Impact` present, threshold
  `single-user incident`.
- 4.7 observability: `## Observability` present, all five fields populated,
  probe verb `bash` allowlisted.
- 4.8 PAT-shape: clean (no token/variable patterns).
- 4.9 UI wireframe: no UI surface — skipped.
- 4.10 encryption: no new store/connection — section records not-required.
- 4.11 guard contract: `scripts/lint-guard-contract.py` PASS (3 guards).
- Citation audit: #4483 (MERGED), #7710 (CLOSED), #5111 (CLOSED), #3521
  (MERGED), #8120 (OPEN), #8180-#8183 verified via `gh`; `804114883`
  confirmed ancestor of `origin/main`; ADR-203 file exists; learning file
  verified present.

## Overview

Four findings filed from the PR #8120 review panel against the vendor pin /
drift machinery:

- **#8180** — classifier exit 13 (batched, low-severity drift) routes to
  `safeCommitAndPr` on a worktree that was reset to `origin/main` and never
  written to. The commit helper sees a clean tree, returns `no-changes`, and
  no re-vendor PR is opened. The lowest-severity drift class stays stale
  forever.
- **#8181** — `vendor-pin-integrity.sh --verify-upstream` checks
  `git/blobs/<sha>` HTTP-200 per NOTICE record. That proves the blob exists
  *somewhere* in the upstream object store; it does not prove the blob is
  the content at the declared `upstream-path` at the declared
  `pinned-commit`. A NOTICE pinning the wrong blob under a real path passes.
- **#8182** — the PR #8120 code enumerates open issues and open PR head refs
  for dedup with bounded first pages (`per_page: 20` search, `per_page: 100`
  pulls list). An existing open item beyond page one is invisible, so
  duplicate tracking items are filed.
- **#8183** — classifier exits 12/15/16 (archived/rollback/renamed) file a
  labeled issue but discard the upstream repository metadata the detect step
  already fetched (`full_name`, `archived`, `default_branch`), forcing the
  operator to re-fetch it during triage.

## Merge-base determination (read first)

The issues describe "the per-bundle arm" — the multi-bundle code that exists
only on the still-open **PR #8120** head (`a2269940…`, state OPEN/WIP as of
2026-09-14). This branch is cut from `main`, whose
`cron-content-vendor-drift.ts` is the **single-bundle** version
(`NOTICE_FILE_REL` constant, no `discoverBundles`). Premise validation result
per issue:

- **#8180**: the defect exists verbatim on main — `route === "pr"` calls
  `safeCommitAndPr` (cron-content-vendor-drift.ts:1001-1034) with no write
  step in between. Fix lands on main's code.
- **#8181**: identical defect on main — `vendor-pin-integrity.sh:75` uses the
  `git/blobs/` existence call. Fix lands on main's code.
- **#8182**: **the named calls do not exist on main.** Both dedup sites on
  main are `GET /search/issues` existence checks that read `total_count > 0`
  (cron-content-vendor-drift.ts:952-958 and 1044-1050), which is
  pagination-complete by construction — `total_count` counts all matching
  results regardless of page size. The bounded-enumeration defect exists only
  in the #8120 head (`listOpenPrHeads` `per_page: 100` single page;
  issue-list filtering by bundle owner). This plan therefore fixes #8182
  **structurally**: any dedup path that *enumerates items* for filtering must
  page to completion, and a regression test pins that property so the
  post-#8120 shape cannot silently reintroduce a bounded scan. If #8120
  merges before this work lands, apply the helper to its `listOpenPrHeads`
  and issue-enumeration call sites instead of (or in addition to) the
  existence-check pinning.
- **#8183**: applies to main's issue arm (cron-content-vendor-drift.ts:1038-1085);
  the repo-metadata probe at :605-626 already fetches `full_name`/`archived`
  and discards them. Fix lands on main's code.

Each FR below includes a *post-#8120 port* note describing how the same
change applies per-bundle if the multi-bundle PR lands first — every fix here
is bundle-local, so porting is mechanical.

## Problem Statement / Motivation

- **#8180**: silent staleness of vendored compliance content. The re-vendor
  route has never produced a PR — the predecessor workflow's write logic
  (`git merge-file --diff3` + NOTICE bump, deleted in #4483) was never ported
  to the Inngest function, and the old `sed` for `last-verified` sat past an
  `exit 0` (cron-content-vendor-drift.ts:1013-1022 documents this). The
  runbook §2 still documents the `needs-human-review` contract that nothing
  currently produces.
- **#8181**: the PR-time provenance gate is weaker than the guarantee the
  NOTICE schema claims. `compliance-posture.md` §Vendored Code Provenance
  attests pinned upstream content; a path/commit/blind-blob mismatch passes
  CI while attesting content upstream never published at that path.
- **#8182**: duplicate issues/PRs scale with repo backlog — the failure grows
  exactly when the repo is busiest.
- **#8183**: rare-event operator toil; the data is already in hand at
  classification time. **Decision: option (a) — enrich the issue body** with
  the already-fetched metadata. Small diff, real toil reduction, and the
  probe's failure mode (`upstreamRepoState: "unreachable"`) is rendered
  honestly rather than as affirmative fields.

## Proposed Solution

### FR-1 (#8180): implement the route-pr re-vendor write

Location: `apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts`.

**Detect-step additions** (inside the existing `step.run("detect-drift")`,
all memoized, all read-only):

- Collect per-drifted-file records into `driftedFiles`:
  `{ liftedPath, upstreamPath, oldSha, newSha }`. `newSha` is the
  `currentSha` already fetched at :702. `liftedPath` comes from zip-pairing
  the parser's `lifted-files` output (`path:localSha` lines, repo-relative
  under `SKILL_PREFIX` — same positional pairing the old workflow's `paste`
  used) with `upstream-files`; assert equal lengths and throw on mismatch —
  a NOTICE whose two views disagree in cardinality is malformed, and
  misalignment would merge the wrong upstream bytes into the wrong file.
- Fetch the new pinned commit: `GET /repos/{owner}/{repo}/commits/{branch}`
  where `branch` is `repoMeta.default_branch` (fall back to `"main"` only
  when the probe failed — in which case `upstreamRepoState` is `unreachable`
  and the route is `issue` anyway, so the value is unused on that arm).
  Store as `newPinnedCommit`.
- Consistency requirement: switch the per-file contents fetch at :699 from
  the hardcoded `ref: "main"` to the resolved default branch, so detection,
  the new pin, and the blobs merged all describe the same upstream head.
- Extend the detect result type (`drift: "detected"` arm) with
  `driftedFiles`, `newPinnedCommit`, and `repoMetaSummary`
  (`{ fullName, archived, defaultBranch }`, populated only when the probe
  succeeded — see FR-4).

**Write-and-commit step** — the write MUST live inside the existing
`step.run("safe-commit-pr")` at :1002, not in a new step. Per
`knowledge-base/project/learnings/2026-06-14-inngest-regenerate-cron-consolidate-write-and-commit-in-one-step.md`:
a filesystem write that is the only carrier of new content must execute in
the same step as the commit consuming it, or Inngest replay returns the
memoized detection result while the worktree is clean and the commit is a
silent no-op — the exact failure this fix exists to remove.

Inside that step, before `safeCommitAndPr`:

1. For each `driftedFiles[]` entry (reference implementation: the deleted
   workflow `scheduled-content-vendor-drift.yml`, recoverable at
   `git show 804114883:.github/workflows/scheduled-content-vendor-drift.yml`
   lines ~270-360):
   a. `GET /repos/{o}/{r}/git/blobs/<oldSha>` → decode base64 → temp file
      (merge base: the pinned upstream bytes).
   b. `GET /repos/{o}/{r}/git/blobs/<newSha>` → temp file (new upstream
      bytes). A 404 here is a genuine anomaly — the sha came from the
      contents endpoint minutes ago — **throw**, do not skip.
   c. `git merge-file -L <lifted-name> -L upstream-pinned -L upstream-new
      --diff3 <liftedAbsPath> <oldTmp> <newTmp>` via the existing `spawnGit`
      helper (`git merge-file` ships with git; the app image already
      installs it). Exit `0` = clean merge; `>0` = conflict count, file now
      carries `--diff3` markers — record the file as conflicted and
      continue; `<0` or spawn error = throw.
   d. `git hash-object --no-filters <liftedAbsPath>` → `newLocalSha`.
   e. Rewrite the NOTICE record: a `rewriteNoticeRecord` helper performs the
      block-anchored substitution the old workflow's Python heredoc did —
      locate the single `- path: <rel>` block plus its 4-space-indented
      sub-keys, substitute `local-blob-sha` → `newLocalSha` and
      `upstream-blob-sha` → `newSha`, and **assert exactly 1 block match, 1
      local substitution, 1 upstream substitution; throw otherwise** (the
      old implementation's `n_blocks != 1 or subs != 1` check — keep it
      verbatim in spirit).
2. Bump top-level `pinned-commit:` → `newPinnedCommit` and `last-verified:` →
   run-start date (line-anchored, assert exactly one replacement each).
   Rationale for advancing `last-verified` here and updating the prBody
   sentence at :1024 accordingly: after this write the records attest the
   newly-pinned content — verified-clean is exactly what the re-vendor
   produces. The #7710-era comment says the field advances "only on a
   verified-clean comparison"; a re-vendor PR that lands IS the
   verified-clean endpoint for the new pin — the field must not stay stale
   after merge or the gdpr-gate staleness banner fires on fresh content.
   Keep the attest-freshness step's clean-run writer untouched; this PR-path
   bump is scoped to the PR's own NOTICE diff.
3. Conflict scan: grep each merged lifted file for `^<<<<<<<` (fresh-marker
   guard — `merge-file` output labels are controlled by `-L`, so match the
   emitted labels exactly). Any marker → `needsHumanReview = true`.
4. Call `safeCommitAndPr` with:
   - `mergeMode: needsHumanReview ? "none" : "direct"` — `"none"` is the
     documented create-only human-review arm
     (_cron-safe-commit.ts:790-792); a conflicted re-vendor must NOT
     auto-merge conflict markers into compliance content. (The app token's
     direct-merge is the CODEOWNERS-bypass residual per ADR-203; `"none"`
     removes it from the conflicted arm entirely, which is strictly safer.)
   - `prLabels: [...detectResult.labels, ...(needsHumanReview ?
     ["needs-human-review"] : [])]` — the runbook §2 contract.
   - `prBody`: append a per-file merge-status section (path → merged |
     conflicted) and the runbook §2 pointer; update the `last-verified`
     sentence to match step 2.
   - `allowedPaths` already covers `${SKILL_PREFIX}/NOTICE` and
     `${SKILL_PREFIX}/references/` (:1009) — unchanged.
5. Capture the `safeCommitAndPr` return (currently discarded at :1002). On
   this arm `status === "no-changes"` must be reported unhealthy — the write
   loop regressed if the tree is clean — via `reportSilentFallback` (Sentry,
   `op: "safe-commit-no-changes"` is the helper's own log line at
   _cron-safe-commit.ts:606) so a silent no-PR run cannot read green.
   Post-#8120 this is the `pr-route-no-artifact` reporting that PR already
   added — same obligation, already named there.

Pre-conditions that keep this honest:

- `driftedFiles` contains only records the detect loop verified drifted
  (`verdict === "drift"`); error-record files are excluded and untouched.
- The open-PR dedup stays in the detect step (a read — correctly separate);
  it already gates `route` before the write runs.
- One-time prerequisite: `gh label create needs-human-review` — the runbook
  references it but the label is absent from the repo label set (verified
  `gh label list`). `safeCommitAndPr`'s label application is advisory
  (_cron-safe-commit.ts:735-752), so without it the label silently never
  lands.

*Post-#8120 port:* same loop inside the per-bundle PR arm, parameterized by
the bundle's `NOTICE_FILE`/`SKILL_PREFIX`; `driftedFiles`/`newPinnedCommit`
per bundle descriptor.

### FR-2 (#8181): bind blob → path → pinned-commit in `--verify-upstream`

Location: `plugins/soleur/skills/gdpr-gate/scripts/vendor-pin-integrity.sh:70-85`.

- After the existing `OWNER_REPO` derivation, read
  `PINNED_COMMIT=$(bash "$PARSER" field pinned-commit)`; fail closed when
  empty or not 40-hex (`pinned-commit` is the ref being verified — a
  malformed ref must not silently degrade to a default-branch read).
- Per record, replace `gh api "repos/$OWNER_REPO/git/blobs/$upstream_sha"
  --silent` with:

  ```bash
  actual_sha=$(gh api "repos/$OWNER_REPO/contents/$upstream_path?ref=$PINNED_COMMIT" --jq '.sha' 2>/dev/null || true)
  if [[ "$actual_sha" != "$upstream_sha" ]]; then
    echo "vendor-pin-integrity: $upstream_path at $PINNED_COMMIT resolves to blob $actual_sha, NOTICE pins $upstream_sha — path/commit/blob binding failed" >&2
    fails=$((fails + 1))
  fi
  ```

- The single call subsumes the old existence check: a 404 (path absent at
  that commit) yields empty `actual_sha` → fail; a directory path yields a
  JSON array → `--jq '.sha'` null → fail. No `git/blobs/` call is retained
  in this mode (the issue's "keep if needed" clause — not needed for the
  binding check).
- Update the mode comment at :22-28 to describe the binding, not existence.
- No workflow edit needed on main: `.github/workflows/vendor-pin-verify.yml`
  invokes the script unparameterized and its `paths:` filter already covers
  the script.

*Post-#8120 port:* the #8120 workflow iterates schema-conforming NOTICE
files; the script's `NOTICE_FILE` env override (header :33-34) is the
existing parameterization — per-record `pinned-commit` must come from the
NOTICE file under test, not a shared constant.

### FR-3 (#8182): dedup completeness — pin the property, close the gap where it exists

Location: `apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts`.

On this merge base the two dedup sites (:952-958, :1044-1050) are
`total_count > 0` existence checks — already complete. The fix therefore has
two parts:

1. **Pin the invariant on main.** Add a short comment at each site stating
   the decision reads `total_count` (complete) and must never be converted
   to a bounded `items` scan; cover it with a unit test that returns
   `{ total_count: 1, items: [] }` from the mock and asserts suppression —
   an `items`-based scan would pass that fixture as "no match" and file a
   duplicate.
2. **Provide the pagination-complete helper for enumeration paths.** Add a
   local `fetchAllPages` helper mirroring the established pattern at
   `apps/web-platform/server/workstream/get-workstream-issue-options.ts:31-44`
   (`per_page: 100`, loop until a short page, defensive cap of 20 pages —
   the octokit client here is bare `@octokit/core`, no `paginate` plugin is
   installed, and adding a dependency for this is heavier than the helper).
   If PR #8120 has merged by implementation time — re-check with
   `gh pr view 8120 --json state` — apply it to `listOpenPrHeads` and the
   issue-enumeration call sites in the multi-bundle arm instead, with the
   same semantics; a matching item on page ≥2 must suppress filing.

*Post-#8120 port:* the helper is the whole fix — `listOpenPrHeads` and the
per-bundle issue scan become `fetchAllPages` calls.

### FR-4 (#8183): enrich lifecycle-event issues with already-fetched metadata

Location: `apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts`.

- In the detect step's repo probe (:605-626), capture `repoMetaSummary:
  { fullName, archived, defaultBranch }` alongside `upstreamRepoState`
  (null/absent when the probe threw — `unreachable` must not render as
  affirmative values). Return it on the detect result.
- In the issue arm (:1059-1075), add an "Upstream repository metadata"
  section rendering `full_name`, `archived`, `default_branch`, and the
  observed `upstreamRepoState` (with a `?` line for `unreachable` — the
  probe failed, not "repo is healthy"). Applies to every issue-route exit
  (12/15/16 and unknown-code), not just lifecycle exits — the metadata is
  free and useful triage context on all of them.
- Keep the rest of the body unchanged: classifier rc, labels, the
  issue-vs-PR rationale, the runbook §2–§5 pointer.

*Post-#8120 port:* per-bundle `repoMetaSummary` on the bundle descriptor;
the issue body gains a bundle column/key in the same section.

## Technical Considerations

- **Replay safety (load-bearing).** The re-vendor write is a filesystem side
  effect consumed by `safeCommitAndPr` in the same `step.run`. Splitting it
  into its own step reintroduces the #8180 failure as a replay no-op
  (memoized detect + clean worktree + memoized write = `no-changes` again).
  The blob fetches inside the write step are keyed by immutable blob SHA, so
  a resumed step re-derives identical bytes.
- **Security boundary.** Exit-13 auto-PR exists precisely because the
  classifier vetted the diff as non-security (the emit-all-added-lines
  convention at :746-769 is load-bearing — do not change it). The merge
  writes upstream bytes only into paths already declared in NOTICE; on any
  conflict the PR goes to `mergeMode: "none"` + `needs-human-review` so no
  unreviewed upstream text merges.
- **No new secrets/connections.** All API calls reuse the existing GitHub
  App installation token octokit client; `git merge-file`/`hash-object` are
  in the app image's git package.
- **NFR:** reliability (the cron becomes honest about producing artifacts —
  `pr-route-no-artifact` becomes genuinely unreachable rather than a
  standing red), auditability (PR body records per-file merge status).
- **Ordering risk:** if #8120 merges mid-work, rebase and apply each FR's
  port note; if this lands first, #8120 absorbs the per-bundle version of
  the same helpers.

## User-Brand Impact

- **If this lands broken, the user experiences:** a user running
  `/soleur:gdpr-gate` on regulated output gets advisory findings from stale
  (un-re-vendored) upstream detection rules — or, worst case, conflict-marked
  rule text if a conflicted PR were merged. Both degrade a compliance
  artifact users rely on.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  new exposure — this machinery reads public upstream content and writes
  repo files; the provenance-chain weakening (#8181) is the exposure the fix
  *closes*.
- **Brand-survival threshold:** `single-user incident` — a bad re-vendor or
  a silently stale ruleset changes what one user's gate run reports.

## Observability

```yaml
liveness_signal:
  what: Sentry cron monitor for the weekly run + the handler's own heartbeat line
  cadence: weekly cron (plus manual-trigger)
  alert_target: Sentry issue (monitor slug scheduled-content-vendor-drift) + vendor/cron-failure GitHub issue on run failure
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf (slug scheduled-content-vendor-drift); handler heartbeat in cron-content-vendor-drift.ts

error_reporting:
  destination: Sentry web-platform via SENTRY_DSN (reportSilentFallback / safe-commit failure ops)
  fail_loud: "throw inside safe-commit-pr step -> Inngest run failure -> Sentry monitor miss + vendor/cron-failure issue; conflicted merges surface as an open PR carrying needs-human-review"

failure_modes:
  - mode: upstream git/blobs fetch 404 mid-write
    detection: thrown error fails the Inngest step; Sentry captures the exception
    alert_route: Sentry issue + cron monitor miss
  - mode: conflicted merge labeled and parked unmerged
    detection: open PR with needs-human-review; label is visible in `gh pr list --label needs-human-review`
    alert_route: needs-human-review PR sits in review queue; stale-PR watchdog (safe-commit stale window, _cron-safe-commit.ts)
  - mode: dedup regression reintroduces bounded scan (post-#8120 shape)
    detection: unit test fixture {total_count:1, items:[]} fails
    alert_route: CI failure pre-merge
  - mode: NOTICE rewrite asserts (n_blocks/subs != 1) trip
    detection: thrown error -> step failure -> Sentry
    alert_route: Sentry issue

logs:
  where: Inngest run logs (step-level) + pino logger lines shipped via Vector to Better Stack (soleur-inngest-vector-prd source)
  retention: Better Stack 90d for the shared source; Inngest run history per queue retention

discoverability_test:
  command: bash plugins/soleur/test/vendor-pin-integrity.test.sh
  expected_output: all test cases PASS (local pin check + fixture assertions)
```

## Encryption Posture

Not required — the plan introduces no persistent store and no new
cross-component connection; all traffic is the existing octokit→GitHub API
and git→repo edges already in place.

## Guard Contract

### Guard 1 — upstream binding check (`--verify-upstream`, #8181)

**Property.** Every NOTICE `upstream-blob-sha` equals the blob SHA the
contents endpoint reports for `upstream-path` at `pinned-commit` — path AND
commit AND blob bound in one call.

**Assembly.** Every `lifted-files` record in every schema-conforming NOTICE
file iterated by `vendor-pin-verify.yml`; the chokepoint is the
`--verify-upstream` loop in vendor-pin-integrity.sh (single call site —
the only place NOTICE records are checked against upstream).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Point a record's `upstream-blob-sha` at a real blob that exists elsewhere in the repo (different path) | RED — contents endpoint returns the path's actual sha ≠ pinned |
| 2 | Revert the call to `git/blobs/<sha>` existence check | RED — harness fixture asserting the `contents?ref=` URL and sha-comparison fails |
| 3 | Point `pinned-commit` at a commit predating the file's addition | RED — 404 → empty sha → mismatch |
| 4 | Second record with a bad sha after a compliant first | RED — loop must check every record, not stop at first pass |

### Guard 2 — re-vendor write completeness + conflict gate (#8180)

**Property.** When `route === "pr"` reaches `safeCommitAndPr`, every
detected-drifted lifted file has been merged and every NOTICE field
consistent — or the step has failed loudly; a conflicted merge is labeled
and create-only.

**Assembly.** The `driftedFiles` list from detect (chokepoint: the single
write loop inside `safe-commit-pr`); NOTICE rewrite asserts; the
conflict-marker scan over merged files.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Delete the write loop, leaving `safeCommitAndPr` on a clean tree | RED — test asserts upstream bytes landed in the lifted file + NOTICE fields bumped; also `no-changes` must not be returned |
| 2 | Write loop iterates only `driftedFiles[0]` | RED — multi-file fixture: second drifted file remains old bytes |
| 3 | Conflict-marker scan dropped / `mergeMode` forced `"direct"` | RED — fixture inducing a merge conflict asserts `mergeMode: "none"` + `needs-human-review` label and markers present in the file |
| 4 | NOTICE rewrite without the n_blocks/subs assert | RED — fixture NOTICE missing the target block must throw, not silently no-op |

### Guard 3 — dedup completeness (#8182)

**Property.** An existing open matching item suppresses filing regardless of
how many unrelated open items precede it in the listing.

**Assembly.** Every dedup read in the cron's route arms (issue dedup, PR
dedup; post-#8120: per-bundle issue enumeration + `listOpenPrHeads`).
Chokepoint: the detect/issue-arm call sites — on main, `total_count`
existence reads; post-#8120, the `fetchAllPages` enumeration.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Match exists only as `total_count` (empty items page) and code scans `items` | RED — fixture asserts suppression |
| 2 | Match on page 2 of a paginated enumeration | RED — multi-page fixture suppresses duplicate |
| 3 | `per_page` bump to 100 without a page loop (post-#8120 shape) | RED — >100-item fixture still finds the match |

## Acceptance Criteria

- [ ] **AC-1 (#8180):** a batched-drift run produces a real PR: each drifted
  lifted file contains the merged upstream bytes (clean merge) or diff3
  conflict markers (conflicted), `local-blob-sha`/`upstream-blob-sha`/
  `pinned-commit`/`last-verified` in NOTICE are updated, and
  `safeCommitAndPr` never returns `no-changes` on this arm.
- [ ] **AC-2 (#8180):** the write executes inside `step.run("safe-commit-pr")`
  — verified by a test asserting a resumed step re-derives the writes (or by
  code inspection + a replay-shaped test where detect is memoized and the
  worktree is clean).
- [ ] **AC-3 (#8180):** a fixture inducing a merge conflict yields
  `mergeMode: "none"`, label `needs-human-review`, markers in the file, and
  the PR body names the conflicted paths.
- [ ] **AC-4 (#8180):** a multi-file drift fixture merges every drifted file
  and bumps every NOTICE record; a non-drifted record is byte-identical.
- [ ] **AC-5 (#8181):** `--verify-upstream` passes a correct
  path/commit/blob tuple and fails (a) a real blob not at the declared
  path, (b) the correct path at a different commit, (c) a missing path —
  each with a distinct fixture in `vendor-pin-integrity.test.sh`.
- [ ] **AC-6 (#8182):** unit test proves suppression via `total_count` with
  an empty first page (main shape); if the post-#8120 enumeration shape is
  present, a page-2 match suppresses filing for both issue and PR dedup.
- [ ] **AC-7 (#8183):** issue bodies for exits 12/15/16 include the
  `full_name`/`archived`/`default_branch` probe values; an `unreachable`
  probe renders an explicit probe-failed line, never affirmative values.
- [ ] **AC-8:** all existing tests in
  `apps/web-platform/test/server/inngest/cron-content-vendor-drift.test.ts`,
  `plugins/soleur/test/vendor-pin-integrity.test.sh`, and
  `plugins/soleur/test/vendor-drift-workflow.test.sh` still pass.
- [ ] **AC-9:** `gh label create needs-human-review` executed (or label
  confirmed present) before merge.

## Test Scenarios

- Given a NOTICE with two drifted files and classifier exit 13, when the
  route-pr arm runs, then both lifted files contain merged upstream bytes,
  both NOTICE records are rewritten, `pinned-commit` equals the fetched
  upstream head SHA, and a PR is created (mock octokit records the calls).
- Given detect memoized and a clean worktree (replay shape), when the
  `safe-commit-pr` step executes, then it re-fetches blobs by SHA and the
  worktree is dirty before `safeCommitAndPr` runs.
- Given a lifted file whose local edits overlap the upstream diff, when the
  merge runs, then `--diff3` markers are written, the PR is created with
  `mergeMode: "none"` and `needs-human-review`, and the run does not fail.
- Given a NOTICE block missing its target `- path:` entry, when the rewrite
  helper runs, then it throws (assert exactly-1) rather than silently
  writing a NOTICE that no longer matches the corpus.
- Given `--verify-upstream` against a fixture NOTICE pinning a blob that
  exists in upstream history but not at `upstream-path@pinned-commit`, when
  the loop runs, then exit 1 with the binding-mismatch message.
- Given an open drift issue whose existence is visible only in
  `total_count` (items page empty), when the dedup check runs, then no new
  issue is filed.
- Given `upstreamRepoState: "unreachable"`, when the issue body renders,
  then it contains the probe-failed line and no `full_name`/`default_branch`
  values.

## Success Metrics

- The next real batched-drift event produces an open `ci/content-vendor-drift-*`
  PR instead of a `no-changes` / `pr-route-no-artifact` outcome.
- `vendor-pin-verify.yml` fails any NOTICE whose declared path at
  `pinned-commit` does not resolve to the pinned blob.
- Zero duplicate `vendor/pin-drift` issues/PRs filed across weeks with >N
  open items.

## Dependencies & Risks

- **PR #8120 ordering** — still open at planning time; each FR carries a port
  note. Re-check `gh pr view 8120 --json state` at implementation start.
- **`git merge-file` availability** — part of the git package already in the
  app image; verify with `git merge-file --help` in the container if in doubt.
- **`needs-human-review` label absent** — one-time `gh label create`; the
  advisory label path would otherwise silently drop it.
- **`ref: "main"` → `default_branch` change** in detection: semantically
  required for pin consistency; flagged here because it widens the diff by
  one line beyond the four issues' letter.
- **Search-API `total_count` trust** — GitHub search can lag indexing by
  seconds; dedup races a same-minute duplicate at worst (pre-existing
  property, unchanged by this fix).

## References & Research

- Reference implementation (deleted workflow, port source):
  `git show 804114883:.github/workflows/scheduled-content-vendor-drift.yml`
  — merge loop ~:270-360, NOTICE rewrite heredoc ~:296-330, conflict gate
  ~:336-349.
- Replay-safety learning (mandates same-step write+commit):
  `knowledge-base/project/learnings/2026-06-14-inngest-regenerate-cron-consolidate-write-and-commit-in-one-step.md`
- Runbook contract being restored:
  `knowledge-base/engineering/operations/runbooks/vendor-pin-drift-resolution.md`
  §2 (conflict-marker resolution, `needs-human-review`).
- Pagination precedent: `apps/web-platform/server/workstream/get-workstream-issue-options.ts:31-44`
  (`fetchAllPages`, per_page:100 + short-page termination + cap 20).
- `safeCommitAndPr` merge modes + advisory labels:
  `apps/web-platform/server/inngest/functions/_cron-safe-commit.ts:104-134,
  735-752, 790-836`.
- Detect/arm call sites on main:
  `apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts`
  :594-626 (repo probe), :661-805 (per-file compare + aggDiff), :945-980
  (exit-13 dedup + route), :1001-1034 (safe-commit-pr), :1038-1085 (issue arm).
- Tests: `apps/web-platform/test/server/inngest/cron-content-vendor-drift.test.ts`,
  `plugins/soleur/test/vendor-pin-integrity.test.sh`,
  `plugins/soleur/test/vendor-drift-workflow.test.sh`.
- Domain gates run: user-brand review (threshold set above), GDPR gate —
  vendored-compliance provenance machinery, fixes *strengthen* the
  provenance claim; IaC — none (no TF changes; the one-time label is a repo
  label, not IaC-managed — `github_issue_label` grep over infra/ is empty);
  ADR/C4 — no new external system or container (the `api -> github` edge and
  Inngest substrate are already modeled); encryption — no new
  store/connection.
- Code-review overlap (Phase 1.7.5): 65 open `code-review` issues scanned;
  none reference any planned file.
- Functional-overlap check: N/A — repo-internal machinery; no community
  artifact applies.
