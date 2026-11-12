---
title: "fix: route drain-prs, product-roadmap and the dequeue re-arm through the Review-Evidence arm check"
type: fix
date: 2026-11-12
slug: fix-arm-check-drain-prs-product-roadmap
branch: feat-one-shot-12656-arm-check-drain-prs-roadmap
issue: 12656
closes: 12656
pr: 12706
priority: p2
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix: route drain-prs, product-roadmap and the dequeue re-arm through the Review-Evidence arm check

## Overview

#12633 (squash 21202186df, v0.409.2, live since the 2026-11-12 19:58Z deploy) added a single-copy arm check to
`plugins/soleur/skills/review/references/review-evidence-comment.md` `## Arm check`. It arms only when the
latest `Review-Evidence:` comment says `coverage=full` and `unresolved-P1-P2=0`, and its `head=` is an
ancestor of the PR head with no non-merge commit between them on the first-parent line. Ship's arm, ship's
CI-fix re-arm and merge-pr's merge gate run it.

Two arm sites named in #12656 still queue auto-merge with a bare `gh pr merge --squash --auto`: drain-prs §4
and product-roadmap Phase 4 step 3. A CTO ruling (Items A-D below) added two more bare re-arms, the drain-prs §4
dequeue bullet and `ship/references/merge-queue-dequeue.md` step 3. It also added a static test so no site
drifts back to a bare arm.

drain-prs mostly arms other sessions' PRs, many of them bot PRs that never carry review evidence. So drain-prs
gets a narrow, mechanically checked exemption instead of an unconditional check.

> Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality (measured) | Plan response |
|---|---|---|
| "two arm sites still run a bare `gh pr merge --squash --auto`" | Four bare arms remain: drain-prs/SKILL.md:84 (§4 block), drain-prs/SKILL.md:89 (dequeue bullet), product-roadmap/SKILL.md:325+330 (both lock arms), ship/references/merge-queue-dequeue.md:30 (step 3 re-arm, followed by ship, merge-pr and drain-prs). Out of scope by ruling: schedule/SKILL.md:519, standing-delegation.md:155. | Fold in all four (CTO Item C). The two out-of-scope sites are recorded with reasons. Follow-up for the delegation grammar: #12712. |
| drain-prs arms "other sessions' PRs, and a fix-recipe commit lands after their evidence" | All 9 bot-authored PRs among the last 60 merged carry **zero** `Review-Evidence:` comments. 24 of 51 human-authored ones carry none. About 13 bot PRs are open now. | An unconditional check would refuse almost every bot PR. CTO Item A ruled A2: check where review is `soleur:review` or drain-prs pushed a commit; a narrow exemption otherwise. |
| Exempt bot PRs are low-risk content | #12691 (CIDR allowlist) and #12700/#12546 (inngest pin bumps) touch `apps/web-platform/infra/`. The gate text routes `infra/` to the CTO plus the infra and data seats. | The exemption excludes any PR touching a domain surface in review-evidence-comment.md `## The gate` (CTO dissent, confirmed here). |
| product-roadmap step 3 is "the lock-wrapped arm after soleur:ship opens the PR" | Ship already arms through the check (Phase 6.5) and polls to merged (Phase 7). Step 3 is either a redundant re-arm or the bare arm past ship's "Skip review" path (ship SKILL.md Phase 1.5 interactive). | B1: prepend the check to step 3's lock block. Deleting steps 3-5 is follow-up #12711. |

## Research Insights

**Premise Validation (Phase 0.6).**

- #12656 is OPEN with no closing PR. #12706 is this branch's own draft (collision pre-check: `SOLEUR_COLLISION exit=10 prs=12706`; the foreign `test-all.sh` pids belong to an unrelated kernel-patch worktree).
- #12619 is MERGED (2026-11-11T02:52Z). #12658 is OPEN (social thread gated on #12656 closing; not in this PR).
- The arm check exists on this branch's base (`review-evidence-comment.md` `## Arm check`, shipped by 21202186df).
- The four bare arm sites were confirmed with `grep -n -o 'gh pr merge[^`|;&)]*'` over the five files (output reproduced in Phase 4 below).
- Nothing cited was stale.

**Dry run at plan time** (the arm check's first statement only, from a scratch script, after `git fetch origin pull/<N>/head`):

- #12619 refuses: `EV=0127b5dc45 H=7d20e7c1a61a… unreviewed=7d20e7c1a61aa99ff7cdaaae66919ca19f51e50b`.
- #12518 passes (EV = H = 1af1ec063d).
- #12633 passes (EV = H = ee92097453).

Phase 6 re-runs these through the composed blocks as they will appear in each skill.

**Property List (Phase 0.6b).**

1. P1. No skill arms or re-arms auto-merge on a PR head that a passing `Review-Evidence:` comment does not cover, except under a recorded, checkable exemption.
2. P2. A commit that drain-prs itself writes onto a PR is never armed without a fresh `soleur:review`.
3. P3. At arm time, an exempt arm is bound to the head whose diff and predicates were read. A push after arming is a residual (#12715) shared with the checked arm; the canonical file already says `--match-head-commit` is not a substitute for `--disable-auto` before a later push.
4. P4. A future edit that reintroduces a bare arm at any of the five sites fails a test.
5. P5. The check's text stays a single copy.

**Cut List.**

- "drain-prs posts its own evidence after a fix" (A4): P2 is already bought by `soleur:review` posting evidence. A self-posted comment would forge the attestation. Cut.
- "Exempt drain-prs entirely" (A3): buys none of P1/P2. Cut.
- "Delete product-roadmap steps 3-5": cleaner, but it rests on an unverified claim, and P1 is bought by B1 at lower risk. Deferred to #12711.
- "Copy the check statement into each site": violates P5. Sites link to `#arm-check`, as ship and merge-pr do.
- A new lock block for drain-prs: drain-prs arms unlocked today, and concurrent-ship.test.sh deliberately excludes it. This PR does not change lock scope.

**Value proposition (0.6c).** No cost-saving claim. The exemption avoids a paid `soleur:review` per bot PR, about 13 open now, with the scope measured above.

**Relevant files.**

- `plugins/soleur/skills/review/references/review-evidence-comment.md`: `## The gate` (domain surfaces), `## The comment`, `## Arm check`.
- `plugins/soleur/skills/drain-prs/SKILL.md`: §4 lines 79-90, §5 lines 92-96, §6 fix-recipes, line 131 (sharp edge).
- `plugins/soleur/skills/product-roadmap/SKILL.md`: Phase 4 step 3 lines 319-342.
- `plugins/soleur/skills/ship/references/merge-queue-dequeue.md`: step 3 line 30.
- `plugins/soleur/skills/ship/SKILL.md`: prose at :473, :1616, :1635. The compliant lock block is at :2184-2196.
- `plugins/soleur/skills/merge-pr/SKILL.md`: compliant, :336-349.
- Tests that read these files:
  - `plugins/soleur/test/concurrent-ship.test.sh` T1/T1b/T1c pin product-roadmap's single `bash "$SS_LIB" with_lock merge-main`, the `reason=running-unlocked` marker and the session-state anchor.
  - `plugins/soleur/test/ci-head-verdict.test.sh` row L2 pins drain-prs' `K=… ready-count <N> && gh pr ready <N> && … wait-ready-run <N> --before-count "$K"` chain.
  - `plugins/soleur/test/pr-merge-poll.test.ts:213` pins drain-prs' "Armed on a merge-queue repo, not yet enqueued: leave it alone … kind=queue_wait".
  - `plugins/soleur/test/drain-prs.test.sh:217` (tier count).

- Suite registration: `scripts/test-all.sh:97` globs `plugins/soleur/test/*.test.sh`. Weight rows are in `scripts/suite-durations.tsv` and `scripts/suite-shard-legs.tsv`. Regen: `python3 scripts/regenerate-shard-manifest.py --incremental --write`. The gate is `scripts/test-all-corpus-weight-budget.test.sh`.

**Institutional learnings applied.**

- `2026-11-11-a-deferred-battery-and-a-draft-light-ci-left-the-repo-wide-guards-for-the-ready-run.md`: select the latest comment and then test it. Keep the check as its own statement ending `|| { …; exit 1; }`, and gate the arm on `${H:?}`.
- `2026-11-03-arming-prerequisite-prs-from-a-sibling-worktree-hits-three-gates-that-measure-the-wrong-branch.md`: drain-prs acts on PRs that are not checked out. The check reads the PR's own head via `gh`, and the head object must be fetched (`git fetch origin "pull/<N>/head"`) or the check fails closed for the wrong reason.
- `2026-05-12-cross-session-lock-lease-bash-primitives.md`: `with_lock … -- gh pr merge` hides the command from anchored hook regexes. The test's occurrence scan must match after ` -- ` too.
- `2026-09-24-my-own-push-cancelled-the-green-certificate-and-the-hook-moved-the-head.md`: `pre-merge-rebase.sh` can move the head on a behind branch. drain-prs runs from its own worktree, so the hook skips auto-sync for a foreign PR (hook: "is not PR #N's checkout … skipped"). `--match-head-commit` makes any head move refuse rather than merge.
- `2026-10-29-a-queued-prs-branch-cannot-be-pushed-to-wait-for-the-dequeue.md`: a dequeue fix push happens after the dequeue, so the re-arm after it is the post-evidence case the check exists for.

**CLAUDE.md / AGENTS conventions.**

- `cq-write-failing-tests-before`: the test lands RED first.
- `cq-assert-anchor-not-bare-token`: pin the link anchor `review-evidence-comment.md#arm-check` and the `--match-head-commit "${H:?` form, not bare tokens.
- `cq-cite-content-anchor-not-line-number`: new prose cites section names.
- `hr-technical-fork-is-not-an-operator-question`: the CTO ruled, and nothing goes to the operator.
- `hr-menu-option-ack-not-prod-write-auth`: the dry run arms nothing. `gh pr merge` is stubbed.

**Step 4.5 scoped advisor consult (fable, curated Overview + Phases).**

- Kept: A1-noH, A1-exempt (`${EXEMPT_HEAD:?`, counted), fail-closed mechanical exemption predicates, and a stated route for a dequeued exempt PR.
- Its A1-span was cut at plan review (below).
- Not applied: its content-path allow-list for (v), which would narrow the binding CTO exemption.

**Plan review v1 → v2 (headless; DHH, Kieran, code-simplicity, CTO devex lens). All findings below are Mechanical and auto-applied, except the CTO amendment.**

- AC2 contradicted the exempt arm. AC, test and dry-run ranges were stale. Fixed.
- Predicate (iii) filtered out merge commits, so an earlier session's conflict-resolving merge passed (DHH, Kieran, CTO). Every commit now counts, merges included.
- (iii) failed open on a null author: `// ""` yields an empty line, so `[ -z ]` passes (simplicity; reproduced with jq at plan time). It now uses `// "?"`.
- `DOMAIN_SURFACE_RE` lived outside its fenced block and was a second copy of the gate list (DHH, CTO, simplicity). It now has one copy in review-evidence-comment.md `## The gate`, which the exempt block reads at run time with `${DOMAIN_SURFACE_RE:?}`.
- The exempt predicates were evaluated twice and against the live head, not the read head (DHH, CTO). They now run once, in the read call, on the head that call captured. A head-unchanged re-read sits before the pinned arm.
- The read call's diff was unbounded (Kieran). It is now `--stat` plus a diff capped at 1500 lines, and a truncated diff routes to the checked arm.
- A1-span false-REDs on `# comment` lines inside fenced blocks (Kieran: ship :2190, merge-pr :347). DHH and simplicity would also cut it, and both panels firing means delete. A1-span, A1-order, M9 and M13 are cut. A1-noH plus the runtime `${H:?}` abort (D6) carry the property.
- Self-dispatch `EXPECTED_PASS` literal, H2, D5, D10, D12, the canonical **Why:** dry-run append and the product-roadmap :342 rewording are cut. H4 is replaced with a real near-miss, and D8 is merged into D11.
- Phase 5 adds `components.test.ts`, `admin-merge-ready-wiring.test.sh`, `monitor-lock.test.sh` and `sync-pr-behind.test.sh` (Kieran).
- D1 now expects the refusal line only. A separate read-only rev-list proves `7d20e7c1a6` (Kieran).
- product-roadmap step 3's "no-op" claim is replaced with the real non-99 outcome (Kieran).
- CTO devex finding 4 was marked "ruling change" by the CTO itself. It is recorded as amended ruling A-amend: dependency manifests, lockfiles, `Dockerfile*`, `.env*`, `cloud-init*`, `middleware.ts`, `*.tfvars` and `*.hcl` join the deny regex.
- CTO finding 2 (login equality) is not applied. Measured: #12694's commit author `github-actions[bot]` differs from its PR author `app/soleur-ai`, and no workflow runs drain-prs headless.
- CTO finding 3's push-after-arm question is filed as #12715.

**External research:** skipped. This is internal skill prose with strong local patterns (ship and merge-pr already compose the check).
**Community / functional-overlap discovery:** skipped. No new stack or capability; it extends an existing in-repo gate to more call sites.

## CTO Rulings (binding — full text in `knowledge-base/project/specs/feat-one-shot-12656-arm-check-drain-prs-roadmap/decision-challenges.md`)

- **Item A (drain-prs semantics):** Ruled by CTO agent, 2026-11-12: A2, with the sub-question ruled strictly.
  - The check is required for every PR routed to `soleur:review` and every PR that drain-prs pushed any non-sync commit to (lockfile regen, conflict-resolving merge, any other commit).
  - On refusal, run `soleur:review`, then the check again. If it still refuses, report "unarmed: no evidence covers the head" and skip.
  - A PR is exempt only when it is bot-authored, §5 routes it to the inline diff read, and drain-prs pushed nothing to it. The exempt arm pins the read head with `--match-head-commit`.
  - Dissent, confirmed: infra/workflow-touching bot PRs belong on the `soleur:review` route.
  - **Amended (A-amend), Ruled by CTO agent, 2026-11-12:** dependency manifests, lockfiles and build surfaces are domain surfaces for the exemption, so a bot dependency bump takes the checked arm.

- **Item B (product-roadmap):** Ruled by CTO agent, 2026-11-12: B1. The check's first statement, then the existing lock block, in one Bash call. Both arms use `--match-head-commit "${H:?run the arm check in this call}"`, and the rc=99 read stays.
- **Item C (scope):** Ruled by CTO agent, 2026-11-12: fold in the merge-queue-dequeue.md step 3 and drain-prs dequeue re-arms. schedule/SKILL.md:519 and standing-delegation.md stay out (follow-up #12712).
- **Item D (guard):** Ruled by CTO agent, 2026-11-12: a static test `plugins/soleur/test/arm-check-sites.test.sh` with mutation rows, no allow-list. Prose that names the arm is reworded.

## Implementation Phases

### Phase 0 — RED: the static test first (`plugins/soleur/test/arm-check-sites.test.sh`)

Write the suite before any site edit. Run it. It must fail on drain-prs, product-roadmap, merge-queue-dequeue and
the ship/drain-prs prose, and pass on merge-pr and on ship's lock block. Record the RED run in the commit message.

- **Sites** (`SITES` array, exact paths):
  - `plugins/soleur/skills/ship/SKILL.md`
  - `plugins/soleur/skills/merge-pr/SKILL.md`
  - `plugins/soleur/skills/drain-prs/SKILL.md`
  - `plugins/soleur/skills/product-roadmap/SKILL.md`
  - `plugins/soleur/skills/ship/references/merge-queue-dequeue.md`

  A missing site file is a FAIL, never a skip.

- **Occurrence scanner** (python3 heredoc, `python3 -I`):
  - Join backslash-continued lines first.
  - Find every `gh pr merge` token, including after `with_lock … --` and after `rtk`.
  - The span runs to the end of the joined line or the next unescaped backtick, whichever comes first.
  - A span is an **arm** when it contains `--auto` as a whole flag (not `--disable-auto`).

- **A1:** every arm span carries `--match-head-commit "${H:?` or, under A1-exempt only, `--match-head-commit "${EXEMPT_HEAD:?`.
- **A1-floor (set identity):** each site file has at least one arm span. The per-file floor is 1, not today's exact counts, so a harmless edit stays green.
- **A1-noH (only the canonical statement sets `H`):** no site file matches `(^|[^A-Za-z_])H=`, or `(^|[^A-Za-z_])(read|declare|export|local)[[:space:]]+(-[a-z]+[[:space:]]+)*H([[:space:]=]|$)`. Plan-time count: 0 in all five.

  Shell state does not cross Bash calls, so an arm reached without the check in its own call aborts on `${H:?…}` (D6). That runtime abort, plus this assertion, is what replaced the cut A1-order and A1-span.
- **A1-exempt:** `${EXEMPT_HEAD:?` appears in exactly one arm span in drain-prs/SKILL.md and in zero arm spans elsewhere. This is a per-file count, not an allow-list.
- **A2:** each site file contains the link anchor `review-evidence-comment.md#arm-check`.
- **A2b (single copy):** `grep -rlF 'ARM_CHECK refused' plugins/soleur/skills/` returns exactly `plugins/soleur/skills/review/references/review-evidence-comment.md`.
- **A3:** the canonical file contains:
  - the `|| { echo "ARM_CHECK refused: no passing evidence covers the PR head"; exit 1; }` statement;
  - the `--match-head-commit "${H:?run the arm check in this call}"` arm line;
  - exactly one `DOMAIN_SURFACE_RE='` definition line.
- **A4 (domain regex single copy and behaviour):**
  - `grep -rlF "DOMAIN_SURFACE_RE='" plugins/soleur/skills/` returns only the canonical file.
  - The regex extracted from it, the same way drain-prs extracts it, matches every path in a synthesized MUST-MATCH fixture list:

    ```text
    apps/web-platform/infra/x.tf
    .github/workflows/a.yml
    supabase/migrations/1.sql
    docs/legal/terms.md
    apps/web-platform/lib/auth/x.ts
    apps/web-platform/package.json
    apps/web-platform/package-lock.json
    bun.lock
    Dockerfile
    .env.example
    apps/web-platform/middleware.ts
    a.tfvars
    .terraform.lock.hcl
    ```

  - It matches none of the MUST-NOT-MATCH list:

    ```text
    knowledge-base/support/community/2026-11-12-digest.md
    knowledge-base/marketing/campaign-calendar.md
    knowledge-base/project/weakness-digest.md
    plugins/soleur/skills/legal-generate/NOTICE
    ```

- **Exit:** non-zero when any assertion fails, when the scanner found zero arm spans in total, or when any mutation row stays GREEN.
- **Mutation and harness rows:** run inside the suite against temp copies (`## Guard Contract`).

### Phase 1 — drain-prs §4 and §5 (`plugins/soleur/skills/drain-prs/SKILL.md`)

1. **§4 opening paragraph.** "then arm it" becomes "then arm it through the arm check (or the exempt arm below)". The `K=… ready-count <N> && gh pr ready <N> && … wait-ready-run <N> --before-count "$K"` chain stays byte-identical, because ci-head-verdict.test.sh L2 pins it.

2. **Checked arm.** Replace the bare block (line 84). The lead sentence says to run the arm check's first statement from [review-evidence-comment.md](${CLAUDE_PLUGIN_ROOT}/skills/review/references/review-evidence-comment.md#arm-check) with `PR_NUMBER=<N>`, after the fetch, then the arm, all in one Bash call:

   ```bash
   git fetch -q origin "pull/<N>/head" || { echo "fetch of PR <N>'s head failed: not armed"; exit 1; }
   # here: the arm check's first statement, PR_NUMBER=<N> (linked above); it exits 1 on refusal
   gh pr merge <N> --squash --auto --match-head-commit "${H:?run the arm check in this call}"
   ```

3. **Route rule.**
   - The checked arm is used for:
     - every PR whose §5 route is `soleur:review`;
     - every PR that is not exempt under item 4;
     - every PR that this or an earlier drain session pushed any commit to: fix-recipe (a) lockfile regen, (b) a conflict-resolving merge, (c) any edit.
   - On `ARM_CHECK refused`, run `soleur:review` on the PR (it posts fresh evidence), then the same call again.
   - If it still refuses, report `unarmed: ARM_CHECK refused` on the drain report and skip the PR. Never arm around it.

4. **Exempt arm.** This is the only other arm. A PR is exempt only when every predicate holds:
   - (i) it is bot-authored;
   - (ii) §5 routes it to the inline diff read;
   - (iii) every commit on it, **merge commits included**, is authored by a login ending in `[bot]`, and a null login counts as non-bot;
   - (iv) its tier is not `needs-conflict-resolution` or `broken`;
   - (v) no changed file matches `DOMAIN_SURFACE_RE`;
   - (vi) the `--stat` and the capped diff were read in full, not truncated.

   (iii) makes "drain-prs pushed nothing" checkable across sessions: a drain session's commits, including a hand-resolved merge, are authored by the operator. As a cost, a person's `update-branch` on a bot PR also removes the exemption, and that PR costs one `soleur:review`.

   (i), (iii) and (v) run mechanically in the read call, against the head that call captured. (ii), (iv) and (vi) are the agent's reading of that output.

   - **Read call.** One Bash call. Every capture is `X=$(…) &&`, so a failed `gh`, `git` or `sed` short-circuits to the refusal rather than yielding an empty, passing string:

     ```bash
     DOMAIN_SURFACE_RE=$(sed -n "s/^DOMAIN_SURFACE_RE='\(.*\)'\$/\1/p" "${CLAUDE_PLUGIN_ROOT}/skills/review/references/review-evidence-comment.md") \
       && EXEMPT_HEAD=$(gh pr view <N> --json headRefOid --jq .headRefOid) \
       && git fetch -q origin main "pull/<N>/head" \
       && B=$(gh pr view <N> --json author --jq .author.is_bot) && [ "$B" = true ] \
       && A=$(gh api "repos/{owner}/{repo}/pulls/<N>/commits" --paginate --jq '.[] | (.author.login // "?") | select(endswith("[bot]")|not)') && [ -z "$A" ] \
       && BASE=$(git merge-base origin/main "$EXEMPT_HEAD") \
       && F=$(git diff --name-only "$BASE" "$EXEMPT_HEAD") && [ -n "$F" ] \
       && [ "$(printf '%s\n' "$F" | grep -cE "${DOMAIN_SURFACE_RE:?domain-surface regex not read}")" = 0 ] \
       && NOW=$(gh pr view <N> --json headRefOid --jq .headRefOid) && [ "$NOW" = "$EXEMPT_HEAD" ] \
       || { echo "EXEMPT_ARM refused: PR <N> is not exempt (or a read failed); use the checked arm"; exit 1; }
     echo "EXEMPT_READ head=$EXEMPT_HEAD"
     git diff --stat "$BASE" "$EXEMPT_HEAD"
     git diff "$BASE" "$EXEMPT_HEAD" | head -n 1500
     [ "$(git diff "$BASE" "$EXEMPT_HEAD" | wc -l)" -le 1500 ] || echo "EXEMPT_READ truncated: use the checked arm"
     ```

   - **Arm call.** Run it only after `EXEMPT_READ head=<sha>` and an untruncated read. A push after the read changes the head and the arm refuses with a clear line:

     ```bash
     EXEMPT_HEAD=<the sha EXEMPT_READ printed>
     NOW=$(gh pr view <N> --json headRefOid --jq .headRefOid) && [ "$NOW" = "$EXEMPT_HEAD" ] || { echo "EXEMPT_ARM refused: head moved since the read"; exit 1; }
     gh pr merge <N> --squash --auto --match-head-commit "${EXEMPT_HEAD:?set EXEMPT_HEAD to the sha EXEMPT_READ printed}"
     ```

   - Record the exemption on the drain report line: `exempt: bot-authored, bot-only commits, no domain surface, read at <sha>`.
   - Two calls rather than the CTO's literal "same call": an agent cannot judge a diff inside the call that arms. The mechanical predicates are tied to the captured head, and the arm re-checks that head before pinning it. That delivers the ruling's property.

5. **Dequeue bullet** (line 89). "re-arm `gh pr merge <N> --squash --auto` only when `autoMergeRequest` is `null`" becomes: re-arm only when `autoMergeRequest` is `null`, through [merge-queue-dequeue.md](${CLAUDE_PLUGIN_ROOT}/skills/ship/references/merge-queue-dequeue.md) step 3.
   - A dequeued exempt PR has no evidence, so the recipe's check would always refuse it. It re-arms through the exempt read and arm calls instead, and the read call's (iii) re-runs.
   - A push in the recipe's step 2 removes the exemption: `soleur:review`, then the checked arm. If that still refuses, report and skip.
   - "Cap it at ONE re-enqueue" stays.

6. **Prose rewording**, so A1 sees no bare arm span.
   - Line 88: "`gh pr merge <N> --squash --auto` **enqueues** the PR" becomes "arming **enqueues** the PR".
   - Line 131: "**`gh pr merge --squash --auto` cannot bypass …**" becomes "**Arming auto-merge cannot bypass …**".
   - The rest of both sentences is unchanged. admin-merge-ready-wiring.test.sh scans this neighbourhood, so run it.

7. **§5.**
   - Add one bullet: bot-authored scheduled content PRs (community digests, campaign calendar, content-distribution promotes, weakness digests) take the inline diff read, the same route as single-file `priority/p3-low` bot-fixes. A PR that fails the exempt arm's predicates goes to `soleur:review`.
   - "Merge only if it passes" on the feature-PR bullet becomes "Merge only if it passes, then arm through the arm check".

### Phase 2 — product-roadmap Phase 4 step 3 (`plugins/soleur/skills/product-roadmap/SKILL.md`)

1. **Step 3 lead.** Arm only through the arm check in [review-evidence-comment.md](${CLAUDE_PLUGIN_ROOT}/skills/review/references/review-evidence-comment.md#arm-check): its first statement with `PR_NUMBER=<number>`, then the lock block below, in one Bash call. The check's `exit 1` stops the call before the lock.
   - On `ARM_CHECK refused`, run `soleur:review`, then the call again. Never arm around it.
   - By step 3, ship Phase 6.5/7 may already have armed, queued or merged the PR. A non-zero `rc` other than 99 therefore means "read `gh pr view <number> --json state,autoMergeRequest` and report". A merged or already-armed PR is not a failure.
2. **Both lock arms** (lines 325 and 330): `gh pr merge <number> --squash --auto --match-head-commit "${H:?run the arm check in this call}"`.
3. **Byte-identical**, because concurrent-ship.test.sh T1/T1b/T1c pin them:
   - `SS_LIB="${CLAUDE_PLUGIN_ROOT}/scripts/lib/session-state.sh"`
   - the single `bash "$SS_LIB" with_lock merge-main 600 -- \` line
   - the `reason=running-unlocked` echo
   - the rc=99 branch

### Phase 3 — merge-queue-dequeue step 3 (`plugins/soleur/skills/ship/references/merge-queue-dequeue.md`)

Step 3 becomes: re-arm once, only when `autoMergeRequest` prints `null`, and only through the arm check in [review-evidence-comment.md](${CLAUDE_PLUGIN_ROOT}/skills/review/references/review-evidence-comment.md#arm-check). Run its first statement (with `PR_NUMBER="$N"`), then `gh pr merge "$N" --squash --auto --match-head-commit "${H:?run the arm check in this call}"`, in one Bash call.

- Step 2's fix push needs `soleur:review` first. A refusal after that review is reported, never armed around.
- drain-prs' exempt PRs re-arm through drain-prs §4's exempt calls instead.
- "When it is armed, do not re-arm. Either way, re-run the Phase 7 poll and wait." is unchanged.
- Match the file's existing `${CLAUDE_PLUGIN_ROOT}` link style.

### Phase 4 — remaining prose and the canonical file

1. **`plugins/soleur/skills/ship/SKILL.md` prose** (wording only):
   - :473 "so nothing here stops `gh pr merge --auto`" becomes "so nothing here stops the auto-merge arm".
   - :1616 "Before queueing `gh pr merge --squash --auto` (Phase 6.5's CI Status Check below)" becomes "Before arming auto-merge (Phase 6.5's CI Status Check below)".
   - :1635 "BEFORE `gh pr merge --squash --auto` is queued" becomes "BEFORE auto-merge is armed".

   Re-grep before editing: `` grep -n -o 'gh pr merge[^`|;&)]*' <file> | grep -- --auto | grep -v -- --disable-auto ``. Plan-time output: ship :473 :1616 :1635 :2187 :2192; merge-pr :344 :349; drain-prs :84 :88 :89 :131; product-roadmap :325 :330; dequeue :30.
2. **`review-evidence-comment.md`:**
   - The header line "linked from the arm steps of `soleur:ship` and `soleur:merge-pr`" adds drain-prs, product-roadmap and merge-queue-dequeue.
   - **`## The gate`** gains a short paragraph and a fenced `text` block with one line: the single copy of the drain-prs exemption's path regex (A-amend). Every later edit to the gate's surface list updates this line in the same change:

     ```text
     DOMAIN_SURFACE_RE='(^|/)infra/|\.tf$|\.tfvars$|\.hcl$|(^|/)migrations/|\.sql$|^\.github/|(^|/)legal/|(^|/)o?auth[^/]*(/|\.)|(^|/)secrets?(/|\.|-)|doppler|(^|/)package(-lock)?\.json$|(^|/)bun\.lockb?$|\.lock$|(^|/)Dockerfile|(^|/)\.env|cloud-init|(^|/)middleware\.ts$'
     ```

     The prose says the regex is a floor, not the whole gate. Code classes it cannot name, such as input validation or auth helpers under other names, still route to `soleur:review` on the agent's read: in doubt, checked arm.
   - The `## Arm check` first sentence lists the same sites and adds: "drain-prs' exempt arm (bot-authored, bot-only commits, no `DOMAIN_SURFACE_RE` path) is the one recorded exemption; it pins the head it read (drain-prs §4)."
   - The check's fenced statement is unchanged byte for byte. Diff it against 21202186df.

   No dry-run append: the PR body carries the proof.

### Phase 5 — registration and the existing guards

1. **Weight rows:** `python3 scripts/regenerate-shard-manifest.py --incremental --write`, plus a `measured` row in `scripts/suite-durations.tsv` timed with one local run.
2. **Run, and read each output:**
   - `bash plugins/soleur/test/arm-check-sites.test.sh` (now GREEN);
   - `bash plugins/soleur/test/concurrent-ship.test.sh`;
   - `bash plugins/soleur/test/drain-prs.test.sh`;
   - `bash plugins/soleur/test/ci-head-verdict.test.sh`;
   - `bash plugins/soleur/test/admin-merge-ready-wiring.test.sh`;
   - `bash plugins/soleur/test/monitor-lock.test.sh`;
   - `bash plugins/soleur/test/sync-pr-behind.test.sh`;
   - `bun test plugins/soleur/test/pr-merge-poll.test.ts plugins/soleur/test/components.test.ts`. The #8593 unbounded-enumeration detector reads the new `gh api` calls, which carry `--paginate`.
   - `bash scripts/lint-orphan-test-suites.sh`;
   - `bash scripts/test-all-corpus-weight-budget.test.sh`;
   - `bash plugins/soleur/test/scripts-shard-manifest.test.sh`;
   - `bash plugins/soleur/test/regenerate-shard-manifest.test.sh`;
   - `npx markdownlint-cli2` on every edited `.md`.

### Phase 6 — dry-run proof (arms nothing)

- A PATH shim in the session scratchpad, never in the repo, wraps `gh`: every call is forwarded to the real `gh` except `pr merge`, which prints `WOULD-ARM <args>` and exits 0.
- Each composed block is pasted **verbatim from the edited file** into one `bash` call with the shim first on PATH, and `CLAUDE_PLUGIN_ROOT` exported to the worktree's `plugins/soleur`.
- Every PR used is already merged, so every call is read-only.

| # | Block | PR | Expected |
|---|---|---|---|
| D1 | drain-prs checked arm | #12619 | `ARM_CHECK refused: no passing evidence covers the PR head`, exit 1, no `WOULD-ARM`. A separate read-only `git rev-list --first-parent --no-merges 0127b5dc45..7d20e7c1a6` prints `7d20e7c1a6…` |
| D2 | drain-prs checked arm | #12518 | `WOULD-ARM 12518 --squash --auto --match-head-commit 1af1ec063da6…` |
| D3 | product-roadmap locked arm | #12619 | refused before the lock (no `with_lock` output), no `WOULD-ARM` |
| D4 | product-roadmap locked arm | #12633 | `WOULD-ARM … --match-head-commit ee92097453ac…`, rc 0 |
| D6 | product-roadmap lock block alone, no check | #12633 | `H: run the arm check in this call` abort, no `WOULD-ARM` (the runtime half of A1-noH) |
| D7 | drain-prs exempt read call, then the arm call | #12694 (bot digest; the commit is by `github-actions[bot]`) | `EXEMPT_READ head=<sha>`, an untruncated diff, then `WOULD-ARM … --match-head-commit <that sha>` |
| D9 | merge-queue-dequeue step 3 | #12619 | `ARM_CHECK refused…`, no `WOULD-ARM` |
| D11 | drain-prs exempt read call | #12700 (bot, cloud-init under `apps/web-platform/infra/`) | `EXEMPT_ARM refused…` (regex hits), no `EXEMPT_READ` line |
| D13 | drain-prs exempt read call | #12633 (human author, human merge commits) | `EXEMPT_ARM refused…` at (i) |

Record the table with each case's last output line in the PR body under `## Dry-run proof`.

## Files to Edit

- `plugins/soleur/skills/drain-prs/SKILL.md`:
  - §4: the checked arm, the exempt read and arm calls, the route rule, the dequeue bullet, and the prose at :88 and :131;
  - §5: the bot-content bullet.
- `plugins/soleur/skills/product-roadmap/SKILL.md`: the Phase 4 step 3 lead and both lock arms.
- `plugins/soleur/skills/ship/references/merge-queue-dequeue.md`: step 3.
- `plugins/soleur/skills/ship/SKILL.md`: prose at :473, :1616 and :1635 only.
- `plugins/soleur/skills/review/references/review-evidence-comment.md`:
  - the header line;
  - `## The gate` `DOMAIN_SURFACE_RE` single copy;
  - the `## Arm check` site list and exemption sentence.
- `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`: one row each.

## Files to Create

- `plugins/soleur/test/arm-check-sites.test.sh`

## Open Code-Review Overlap

None. The bodies of `gh issue list --label code-review --state open --limit 200` were matched against every path above.

## User-Brand Impact

- **If this lands broken, the user experiences** one of two failures:
  - drain-prs or product-roadmap refuses to arm a PR that should merge. The operator sees `unarmed: ARM_CHECK refused` or `EXEMPT_ARM refused` on a drain report, or a refused roadmap PR, and one `soleur:review` resolves it.
  - A bare arm survives, and a PR merges with commits no review saw (the #12619 class). Unreviewed code reaches the operator's `main`.
- **If this leaks, the user's workflow is exposed via:** a merge of unreviewed code into the operator's repository. No user data, credentials or money path is touched. The diff is skill prose and a static test.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the change narrows when an agent may arm auto-merge in the operator's own repo, and it fails closed. Its worst failure is the existing bare-arm behaviour persisting. Required CI still gates every merge server-side, and no path in the diff matches the preflight Check 6 sensitive-path regex.

## Guard Contract

### Guard 1 — arm-check-sites (`plugins/soleur/test/arm-check-sites.test.sh`)

**Property.** At every skill site that arms or re-arms auto-merge, each arm is bound to a head set by the arm check: `--match-head-commit "${H:?…}"`, with `H` assigned nowhere but the canonical statement. The one exception is drain-prs' single exempt arm, which is bound to the head it read (`${EXEMPT_HEAD:?…}`). The exemption's path regex exists once, in the canonical file, and behaves on the gate's path classes.

**Assembly.**

- **Chokepoint:** every textual `gh pr merge … --auto` span an agent can copy out of the five site files, fenced or inline. That includes spans after `with_lock … --`, after `rtk`, and across backslash continuations.
- **Site set:** the `SITES` array, checked as set identity: each file present, each with at least one arm span.
- **Canonical copy:** `review-evidence-comment.md`, checked for presence (A3) and for uniqueness across `plugins/soleur/skills/` (A2b, A4).
- **Not in the assembly, by ruling:**
  - `schedule/SKILL.md` (a workflow template);
  - `standing-delegation.md` (#12712);
  - a new arm site in a sixth file. That is the residual. Its re-evaluation trigger is #12656's own: any PR found merged past its evidence head.

**Mutation matrix.**

| # | Mutation (temp copy) | Expected |
|---|---|---|
| M1 | strip `--match-head-commit "${H:?…}"` from drain-prs' checked arm | RED (A1) |
| M2 | append a second bare `gh pr merge <number> --squash --auto` after product-roadmap's compliant locked arm | RED (A1, second member) |
| M3 | split a bare arm across a continuation in merge-queue-dequeue: `gh pr merge <N> \`, newline, an indented `--squash --auto` | RED (A1, join) |
| M4 | wrap a bare arm as `bash "$SS_LIB" with_lock merge-main 600 -- gh pr merge 7 --squash --auto` in ship | RED (A1, after ` -- `) |
| M5 | delete the `review-evidence-comment.md#arm-check` link from merge-queue-dequeue.md | RED (A2) |
| M6 | paste the `ARM_CHECK refused` statement into drain-prs/SKILL.md | RED (A2b) |
| M7 | delete the `ARM_CHECK refused` line from the canonical copy | RED (A3) |
| M8 | point one `SITES` entry at a nonexistent path; separately, strip every arm span from one site | RED (missing file; A1-floor) |
| M10 | insert `H=$(gh pr view <number> --json headRefOid --jq .headRefOid)` above product-roadmap's lock block; separately, `read H` | RED (A1-noH, both spellings) |
| M11 | copy drain-prs' exempt arm line (`${EXEMPT_HEAD:?`) into product-roadmap; separately, add a second one in drain-prs | RED (A1-exempt: zero elsewhere, exactly one in drain-prs) |
| M14 | paste a second `DOMAIN_SURFACE_RE='…'` definition into drain-prs; separately, delete `\.lock$` from the canonical regex | RED (A4 single copy; A4 MUST-MATCH on `bun.lock`) |

**Harness rows.**

| # | Harness edit / input | Expected |
|---|---|---|
| H1 | stub the scanner's span regex to match nothing | RED (zero arm spans in total) |
| H3 | must-PASS, non-canonical: `gh pr merge 7 --disable-auto` plus a compliant `gh pr merge "$N" --auto --squash --match-head-commit "${H:?x}"` (different flag order and placeholder) | GREEN |
| H4 | must-PASS near-miss: a `` `gh pr merge` unlocked `` span with no `--auto`, and an inline `` `gh pr merge <N> --squash` `` | GREEN (not an arm span) |
| H5 | must-PASS: a `# comment` line between the link sentence and a compliant arm inside a fenced block | GREEN (no assertion depends on markdown headings) |

**Anchor.** There is no stored hash or count. The per-file floor is 1, and A2b/A4 are set identities over the tree, not counts. The anchor outside the commit is `soleur:review` of this PR.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "plugins/soleur/skills/drain-prs/SKILL.md §4 \"ensure green, then merge\". It arms other sessions' PRs, and a fix-recipe commit lands after their evidence." [issue #12656] | Phase 1 | mapped |
| 2 | "plugins/soleur/skills/product-roadmap/SKILL.md step 3, the lock-wrapped arm after soleur:ship opens the PR." [issue #12656] | Phase 2 | mapped |
| 3 | "each site either runs the arm check (without its last line, then its own arm or lock block, and only on exit 0), or records why the site is exempt." [issue #12656] | Phase 1.2-1.4, Phase 2.1-2.2, Phase 4.2 | mapped |
| 4 | "Changing drain-prs' merge semantics is a technical fork: spawn soleur:engineering:cto for a BINDING ruling and record it as \"Ruled by CTO agent\"." [brief] | CTO Rulings; decision-challenges.md (5 rows) | mapped |
| 5 | "Include a dry-run proof like the original PR's: a PR merged past its evidence head (7d20e7c1a6 after evidence head 0127b5dc45) must refuse, and a covered PR must arm." [brief] | Phase 6 D1, D2 (plus per-site D3-D13) | mapped |
| 6 | "Run soleur:postmerge after the merge." [brief] | AC10 | mapped |
| 7 | "Follow-on ... #12658 ... not in this PR" [brief] | none | descoped — justification: the brief assigns it to the calling session after merge |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| drain-prs checked arm and exempt arm | "each site either runs the arm check ... or records why the site is exempt" | asked |
| product-roadmap B1 | "the lock-wrapped arm after soleur:ship opens the PR" | asked |
| merge-queue-dequeue step 3 and drain-prs dequeue bullet | — | inferred — justification: binding CTO Item C, the same post-evidence-commit bypass |
| arm-check-sites.test.sh | — | inferred — justification: binding CTO Item D; #12633 shipped no test and bare arms survived it |
| `DOMAIN_SURFACE_RE` single copy in `## The gate` and the A-amend surfaces | — | inferred — justification: binding CTO amendment A-amend, plus plan-review single-copy findings |
| ship SKILL.md prose rewording (3 lines) | — | inferred — justification: Item D's no-allow-list ruling (A1 scans inline spans) |
| follow-up issues #12711, #12712, #12715 | — | inferred — justification: CTO dissents and the plan-review residual; a deferral needs a tracking issue |

### Split Assessment

- Subsystems touched: 2 (`plugins/soleur/` skills and test; `scripts/` weight rows)
- Planned files: 8 | Estimated changed lines: about 230 (test about 160, prose about 70)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `bash plugins/soleur/test/arm-check-sites.test.sh` exits 0. A1, A1-floor, A1-noH, A1-exempt, A2, A2b, A3 and A4 hold. M1-M8, M10, M11 and M14 each turn RED; H1 turns RED; H3, H4 and H5 stay GREEN. The suite's first commit records a RED run against the unedited sites.
- [ ] AC2 — over the five site files, `` grep -n -o 'gh pr merge[^`|;&)]*' <site> | grep -- --auto | grep -v -- --disable-auto `` prints only lines carrying `--match-head-commit "${H:?` or `--match-head-commit "${EXEMPT_HEAD:?`. Exactly one carries `${EXEMPT_HEAD:?`, and it is in drain-prs/SKILL.md.
- [ ] AC3 — `grep -rlF 'ARM_CHECK refused' plugins/soleur/skills/` and `grep -rlF "DOMAIN_SURFACE_RE='" plugins/soleur/skills/` each print exactly `plugins/soleur/skills/review/references/review-evidence-comment.md`. `git diff 21202186df -- plugins/soleur/skills/review/references/review-evidence-comment.md` shows no change inside the arm check's fenced block.
- [ ] AC4 — drain-prs §4 carries the checked arm, the route rule, the exempt read call with (i)/(iii)/(v) mechanical and `${DOMAIN_SURFACE_RE:?`, and the head-rechecking pinned arm call. §5 names the bot scheduled content PRs.
- [ ] AC5 — product-roadmap step 3 links `#arm-check`, and both lock arms pin `${H:?run the arm check in this call}`. `bash plugins/soleur/test/concurrent-ship.test.sh` passes with that suite unedited.
- [ ] AC6 — each Phase 5 suite exits 0: ci-head-verdict, drain-prs, admin-merge-ready-wiring, monitor-lock, sync-pr-behind, plus `bun test` over pr-merge-poll and components.
- [ ] AC7 — `bash scripts/lint-orphan-test-suites.sh` and `bash scripts/test-all-corpus-weight-budget.test.sh` exit 0 with the new rows.
- [ ] AC8 — dry runs D1, D2, D3, D4, D6, D7, D9, D11 and D13 print exactly the tabled last lines. They are recorded in the PR body under `## Dry-run proof`. The only `gh pr merge` that ran was the shim (`WOULD-ARM`).
- [ ] AC9 — `technical-ruling-gate.sh --branch` passes on decision-challenges.md (5 rows). The PR body links #12711, #12712 and #12715, and says `Closes #12656` in the body, not the title.

### Post-merge (operator-free)

- [ ] AC10 — `soleur:postmerge` runs on the merge sha and reports no deploy for plugin-only paths. `gh release list --limit 1` shows a release tagged after the merge, on the PR's semver label.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO Rule interface (one batched ruling spawn, Items A-D) plus the plan-review devex advisory, which produced amendment A-amend. No product or UX surface: no UI files, and the mechanical UI-surface override did not fire. Legal, finance, marketing, sales, support and operations have no implications: this is internal skill prose plus a test. #12658, the marketing thread, is gated on this issue and handled by the calling session.

## Infrastructure / Observability / Architecture gates

- **IaC (2.8):** none.
- **Observability (2.9):** skipped. There is no code-class file under `apps/*/server|src|infra/` or `plugins/*/scripts/`, and no new runtime surface. The suite runs in the existing `test-all.sh` scripts shard.
- **ADR/C4 (2.10):** none. This extends #12633's existing gate to more call sites. It moves no ownership, trust or substrate boundary, and the exemption is a site rule recorded in the canonical file. There is no C4 actor, system, container or relationship change, and a test suite is not a counted component for `c4-count-parity.test.sh`.
- **Encryption (2.11), GDPR (2.7), Task design (2.9.3):** do not fire.

## Test Scenarios

- T1: the static suite is RED on the unedited tree. It names drain-prs :84/:88/:89/:131, product-roadmap :325/:330, dequeue :30 and ship :473/:1616/:1635, and A3/A4 fail on the missing `DOMAIN_SURFACE_RE` line.
- T2: the same suite is GREEN after Phases 1-4.
- T3: the in-suite mutation rows M1-M8, M10, M11 and M14 turn RED. H1 turns RED. H3, H4 and H5 stay GREEN.
- T4: dry runs D1, D2, D3, D4, D6, D7, D9, D11 and D13 (Phase 6).
- T5: the existing suites stay green unedited (Phase 5 list).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6. It is filled above.
- The canonical check's fenced statement must not change. Edit only the prose around it and add the `## The gate` regex block. A reworded jq or rev-list line silently changes every site.
- drain-prs must fetch `pull/<N>/head` before the check. Otherwise `merge-base` fails on a missing object and the PR reads as "no evidence".
- The ci-head-verdict L2 chain and the concurrent-ship lock lines must stay byte-identical.
- To the new suite, a `--auto` inside a backticked `gh pr merge` span in any of the five files is an arm. New prose says "arm" instead of quoting a command.
- Never run Phase 6 blocks without the shim first on PATH.
- In `X=$(cmd) && [ test ]`, a failed `cmd` short-circuits to the refusal. `[ -z "$(cmd)" ]` alone would pass on a failure. Keep every capture in the first form, and keep `// "?"` (never `// ""`) for null logins.
- Residual (#12715): `--match-head-commit` binds at arm time. Whether a later push to an armed PR merges the new head is unmeasured, for both arms.
