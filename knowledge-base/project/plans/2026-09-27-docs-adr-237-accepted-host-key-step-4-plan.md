---
title: "docs: flip ADR-237 to accepted and tick host-key post-merge step 4"
date: 2026-09-27
slug: docs-adr-237-accepted-host-key-step-4
branch: feat-one-shot-adr-237-accepted
issue: 7226
closes: []
type: docs
lane: single-domain
priority: p2
domain: engineering
brand_survival_threshold: none
---

# docs: flip ADR-237 to `accepted` and tick host-key post-merge step 4

## Overview

ADR-237 (SSH host keys are pinned) is `adopting`. Its own Status section names the flip condition:
at post-merge step 4 of the runbook's host-key sequence, "a strict `git-data-cutover.yml` dry run
from `main` reads `role=git-data-auth verdict=ok` with both hops pinned. That flip happens in a docs
PR." That dry run happened: workflow run
[36119817656](https://github.com/jikig-ai/soleur/actions/runs/36119817656). This PR does the flip:

1. ADR-237 frontmatter `status: adopting` becomes `status: accepted`.
2. A dated `## Addendum — 2026-09-27` records the evidence. The original `## Status` text stays
   as written, because ADR records are append-only.
3. The runbook's "Step 4" checkbox under Preconditions is ticked and cites the run id.

It is docs-only: two markdown files, with no code, infra, workflow or test changes.

## Research Insights

### Premise Validation (Phase 0.6)

All checks below were run on 2026-09-27.

- **Run 36119817656** (`gh run view --json`): `event=workflow_dispatch`, `headBranch=main`,
  `headSha=51a5541a1a730d51b51436d9100657ed55d94dfd` (an ancestor of `origin/main`),
  `createdAt=2026-09-25T09:41:09Z`, `conclusion=failure`. Log lines, verbatim (`gh run view --log`):
  - `ssh-strict: true`
  - `write-known-hosts: pinned web-1 ecdsa-sha2-nistp256 SHA256:ARBTzhY4hCGXKwWZ2j9aOc4zZefBYgAxJncoVglvuok`
  - `write-known-hosts: pinned git-data ssh-ed25519 SHA256:4eErmLfOuKM17zzNd+2so+26zojG0tsv9NMVNCuXpCs`
  - `git_data_pin=present fp=SHA256:4eErmLfOuKM17zzNd+2so+26zojG0tsv9NMVNCuXpCs` (the pin from the
    flag precheck matches the git-data fingerprint that was pinned)
  - `role=web verdict=ok`, `role=git-data-jump verdict=ok`, `role=git-data-auth verdict=ok`
  - `probe=store-mounted verdict=ok`
  - `##[error]probe=store-not-cut-over verdict=already_cut_over`, then
    `Process completed with exit code 5`
  - `##[warning]TOFU_ARM present - the app still carries the unpinned git-data fallback (#5914); it must be deleted before GIT_DATA_STORE_ENABLED is ever set`
- **PR #8511** (the mechanism) was `MERGED` on 2026-09-22 (`0aa119838b`).
- **#7226** and **#8125** are `CLOSED`. **#5914** is `OPEN`, and that is expected: runbook step 6
  closes it. This PR must not close it.
- The run's failure comes from a store probe (`already_cut_over`: the store was cut over on
  2026-09-25) and has nothing to do with host keys. It is being fixed in a separate follow-up
  (git-data-cutover PR2, where proof reads `already_cut_over` as a pass). The ADR addendum says this
  plainly and does not claim the run passed.

### The one real question: is removing the TOFU fallback a precondition of `accepted`?

**Answer: no, so the flip goes ahead.** Every file that governs the flip puts the fallback's
deletion after step 4, and makes it a precondition of the **store flag flip**, not of ADR-237 being
`accepted`:

- ADR-237 `## Status`, which is the only flip condition written in the ADR:
  > It flips to `accepted` at post-merge step 4 of the runbook's host-key sequence … a strict
  > `git-data-cutover.yml` dry run from `main` reads `role=git-data-auth verdict=ok` with both hops
  > pinned. That flip happens in a docs PR.
- ADR-237 `## Residuals`, "The transitional app arm (#5914)":
  > deleting the arm (the #5914 follow-up PR) is a hard precondition for that flag flip. The cutover
  > precheck's `TOFU_ARM` line is a reminder read from the dispatched source tree on every dry run;
  > the enforcing control is the resolver's throw on an absent pin while the store flag is on.
- Runbook "Host-key pinning post-merge sequence", step 4 contains no TOFU clause:
  > 4. **Strict dry run.** Dispatch `git-data-cutover.yml` from `main`. It must read
  > `role=git-data-auth verdict=ok` with both hops pinned. Then tick the #7226 item under
  > Preconditions and flip ADR-237 to `accepted` in a docs PR.
- The deletion is a separate, later step (step 6):
  > 6. **The #5914 follow-up PR.** It deletes the app's unpinned fallback arm … It must merge before
  > any `GIT_DATA_STORE_ENABLED` flip.
- The runbook's Preconditions list scopes the `TOFU_ARM` reminder to the flag flip, not to the ADR:
  > **Flag-flip precondition (hard):** `GIT_DATA_STORE_ENABLED` is never set until the pin is present
  > in `prd`, #5914 is closed, **and** #8211 pages … Only `TOFU_ARM absent` satisfies the reminder.
- The run's own warning names the same gate: "it must be deleted before GIT_DATA_STORE_ENABLED is
  ever set".
- Linked ADRs key off ADR-237 reaching `accepted` at step 4, with no TOFU clause. ADR-220's
  amendment log says D4's first residual is "closed by ADR-237, effective at post-merge step 4". The
  ADR-068 2026-09-21 amendment says "this gate is discharged when ADR-237 reaches `accepted` (its
  post-merge step 4)".

The `TOFU_ARM present` warning is therefore expected at this stage and does not block the flip.
The addendum records it as still open, owned by step 6 and #5914.

### Consumers of ADR-237's status and the runbook checkbox text

Checked with `git grep`, excluding `knowledge-base/project/{plans,specs}`:

- `ADR-237` appears in 51 files. None of them is a test or lint that reads ADR-237's `status:`
  value. The `*.test.sh` / `*.test.ts` hits (for example `terraform-target-parity.test.ts`,
  `web-1-host-key-local.test.sh`, `guard-vacuity-floor.test.sh`) cite ADR-237 in comments or as
  mechanism provenance.
- No lint or test in `scripts/`, `tests/`, `plugins/soleur/test/` or `.github/` pins ADR status
  values in general. The only `accepted` string match is `scripts/followthroughs/workspaces-luks-soak-6604.sh`,
  which checks ADR-119, not ADR-237. There is no ADR index or README that lists statuses.
- The runbook step text (`Step 4 — the strict dry run reads`, `then tick this item`) appears only in
  the runbook itself (line 35).
- Prose that depends on the status, all of it conditional ("when ADR-237 reaches `accepted`"), so
  none needs an edit:
  - ADR-220 amendment log (D4 residuals; the D5 table row "D2–D3 credential and lifetime")
  - ADR-068's 2026-09-21 amendment
  - `model.c4` line 811, which describes the pin and the transitional fallback and does not state
    the ADR status
  - `knowledge-base/legal/audits/2026-09-counsel-review-7226.md`, which contains no `adopting`,
    `accepted` or `step 4` text and is not edited

### Property List (Phase 0.6b)

- P1: A reader of ADR-237 can see that it is `accepted`, and when, and on what evidence.
- P2: The original flip condition stays readable as written (append-only).
- P3: The runbook's host-key tracker shows step 4 done, with evidence a reader can re-verify.
- P4: Nobody can read the flip as "the whole dry run passed" or as "the TOFU fallback is gone".

### Cut List

- Amendments to ADR-220 and ADR-068: cut. P1 is already met there, because their conditional text
  ("closed by ADR-237, effective at post-merge step 4") resolves once ADR-237 is `accepted`.
- Ticking runbook steps 1–3, or refreshing the "(pending merge at the time of writing)" line: cut.
  The operator scoped this PR to step 4. Ticking the others would need its own evidence gathering
  (see Non-Goals).
- A CI test that pins ADR-237's status: cut. No such gate exists, and a status flip does not need
  a new one.

### Conventions

- The ADR addendum style follows ADR-023: `## Addendum — YYYY-MM-DD (#N): <subject>`, placed after
  the body sections and before the references section.
- The PR body uses `Ref #7226` / `Ref #5914`, never `Closes` (#5914 stays open until step 6;
  `wg-use-closes-n-in-pr-body-not-title-to`).

## Files to Edit

- `knowledge-base/engineering/architecture/decisions/ADR-237-ssh-host-keys-are-pinned.md`
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`

## Files to Create

None. The plan and tasks artifacts are the only additions.

## Open Code-Review Overlap

None. Neither file is referenced by an open `code-review` issue. Verify at work time with
`gh issue list --label code-review --state open --json number,body` piped to `jq` with a
`contains($path)` filter.

## Implementation Phases

### Phase 1: ADR-237

1. Frontmatter: `status: adopting` becomes `status: accepted`. Leave every other key unchanged.
2. Leave `## Status` exactly as it is.
3. Insert the section below between `## Alternatives considered` (and its trailing "Also rejected"
   paragraph) and `## References`:

   ```markdown
   ## Addendum — 2026-09-27 (#7226): accepted at post-merge step 4

   ADR-237 is `accepted`. The condition in Status is met: `git-data-cutover.yml` run
   [36119817656](https://github.com/jikig-ai/soleur/actions/runs/36119817656), dispatched from
   `main` at `51a5541a1a` on 2026-09-25, ran with `ssh-strict: true`, pinned both hops
   (`write-known-hosts: pinned web-1 ecdsa-sha2-nistp256 SHA256:ARBTzhY4hCGXKwWZ2j9aOc4zZefBYgAxJncoVglvuok`,
   `write-known-hosts: pinned git-data ssh-ed25519 SHA256:4eErmLfOuKM17zzNd+2so+26zojG0tsv9NMVNCuXpCs`),
   and read `role=web verdict=ok`, `role=git-data-jump verdict=ok` and
   `role=git-data-auth verdict=ok`. The git-data fingerprint equals the published pin
   (`git_data_pin=present fp=SHA256:4eErmLfOuKM17zzNd+2so+26zojG0tsv9NMVNCuXpCs`).

   **The run as a whole failed, and not on a host key.** It exited 5 on
   `probe=store-not-cut-over verdict=already_cut_over`, because the store had already been cut over
   on 2026-09-25. That is a store-probe verdict and was read after all three SSH roles had passed.
   Making the proof read `already_cut_over` as a pass is a separate follow-up (git-data-cutover
   PR2). This addendum relies only on the three `role=` lines and the two `pinned` lines. It does
   not claim the run passed.

   **Still open, and not conditions of `accepted`:**
   - The same run warned `TOFU_ARM present`. The app still carries the unpinned fallback arm
     (Residuals, "The transitional app arm"). Deleting it is runbook step 6 (#5914), which is a hard
     precondition for setting `GIT_DATA_STORE_ENABLED`. It was never a condition of this flip.
   - Runbook step 5 (discharging erasures left pending by the pin window) is not done by this run,
     which stopped before the `store_not_empty` probe.

   Effects elsewhere, already written conditionally and not rewritten here: ADR-220 D4's first
   residual and the 2026-09-15 "Store-probe evidence is unauthenticated until #7226" residual close
   (as to host identity; a pinned key authenticates the host, not its answers). ADR-068's host-key
   gate is discharged.
   ```

### Phase 2: Runbook

In `## Preconditions for the real cutover`, under the #7226 / #5914 item, change only the Step 4
line:

```markdown
  - [x] Step 4 — the strict dry run reads `role=git-data-auth verdict=ok`; then tick this item and flip
    ADR-237 to `accepted` in a docs PR. Done: `git-data-cutover.yml` run
    [36119817656](https://github.com/jikig-ai/soleur/actions/runs/36119817656) (from `main`,
    2026-09-25) read `role=git-data-auth verdict=ok` with both hops pinned. The run exited 5 on
    `verdict=already_cut_over`, a store probe and not a host key. ADR-237 is `accepted` (addendum
    2026-09-27).
```

Leave the numbered step 4 in "Host-key pinning post-merge sequence" and steps 1–3, 5 and 6
unchanged.

### Phase 3: Commit and ship

- Stage **exact paths only**: the two files above plus the plan and tasks. Never use `git add -A`
  or `git add .`. The worktree has an unrelated modified file,
  `knowledge-base/legal/data-processing-agreements/openai.md`, and several deleted spec files that
  belong to other work. Neither may enter this PR (operator: do not edit the legal audit files for
  the 8634 series).
- Commit with `LEFTHOOK_EXCLUDE=bun-test,plugin-component-test`. Do not run the local test battery
  (the operator's direction, because the machine is contended). CI's required checks are the gate.
- Merge only after the required checks pass by name on the exact head SHA, through
  `admin-merge-ready.sh` and `gh pr merge --admin --match-head-commit <sha>` (the operator
  authorized this). If a sync with `main` conflicts on `PROMOTED_FILES`, resolve it as a union, and
  re-derive floors after any merge.

## Non-Goals

- Ticking runbook steps 1–3, or updating the Mechanism line's "(pending merge at the time of
  writing)". This is stale bookkeeping and out of this PR's operator-set scope. The step-3 outcome
  is implied by `git_data_pin=present`, but step 3 has its own criterion (the pin-redeploy run and
  the startup line), which this PR does not verify.
- Changing git-data-cutover proof semantics (`already_cut_over` as a pass). That is PR2, next in the
  queue.
- Deleting the TOFU arm (#5914, step 6), and issue #8760.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly. This changes documentation
status only, and no runtime behaviour reads ADR status. The worst case is a misleading record: a
future operator reads `accepted` as "the TOFU fallback is gone" and flips the store flag too early.
Two things prevent that: the addendum's explicit "Still open" bullets, and the app resolver's throw
on an absent pin while the flag is on.

**If this leaks, the user's data is exposed via:** no new vector. The fingerprints quoted are public
host-key fingerprints, already committed in ADR-237 and the runbook.

**Brand-survival threshold:** none. Reason: a docs-only status flip with no code, infra or
data-path change, and no change to any sensitive path.

## Acceptance Criteria

- [ ] AC1: `awk 'NR==1{next} /^---/{exit} /^status:/{print $2}'` on ADR-237 prints `accepted`.
- [ ] AC2: `git diff origin/main -- <ADR-237>` shows only additions apart from the one `status:`
  line. The `## Status` paragraph, starting "`adopting`. Implemented by PR #8511", is byte-identical.
- [ ] AC3: ADR-237 has exactly one `## Addendum — 2026-09-27` heading, and it sits before
  `## References`. It contains `36119817656`, `already_cut_over`, `TOFU_ARM present` and `#5914`,
  and does not contain a claim that the run passed. It must use "exited 5" or "failed" wording.
- [ ] AC4: the runbook's Preconditions Step 4 line starts `- [x] Step 4` and contains
  `36119817656`. `git diff` on the runbook touches only that list item.
- [ ] AC5: the PR diff (`git diff --name-only origin/main...HEAD`) contains only the two edited
  files plus this plan and its `tasks.md`. It contains no `knowledge-base/legal/**` path.
- [ ] AC6: the PR body references #7226 and #5914 with `Ref`, not `Closes`/`Fixes`/`Resolves`.
- [ ] AC7: every required check passes on the exact head SHA before the admin merge.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: this is an engineering-records change. A Legal check found
that the counsel-review audit for #7226 has no status-dependent text, and legal files are out of
scope.

## Test Scenarios

No code changes, so there are no new tests. Verification is AC1–AC6 (grep and diff) plus CI's
docs and markdown lint checks.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits
  the threshold will fail `deepen-plan` Phase 4.6. It is filled above.
- The worktree carries an unrelated modified legal file and unrelated deleted spec files. A
  directory-level or `-A` add would sweep them in. Stage by exact path.
- The run's `conclusion` is `failure`. Anyone re-verifying the evidence must read the `role=` lines,
  not the conclusion. The addendum names the exit-5 cause so the discrepancy is explained where it
  is read.
- ADR-220 and ADR-068 must not be rewritten. Their conditional text becomes effective without an
  edit, and rewriting them would break append-only.
