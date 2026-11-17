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

> **Superseded in part 2026-11-13 (CTO rulings R1-R4, decision-challenges.md):** the drain-prs exempt arm, its read call, `DOMAIN_SURFACE_RE` and dry-run rows D7, D7b, D11 and D13-D15 were deleted (R1, R3). The admin-merge hatch was added as a site (R4). The text below is the plan as written on 2026-11-12; read the exempt-arm parts as history.

## Enhancement Summary

**Deepened on:** 2026-11-12 (soleur:deepen-plan, after plan-review v2).

**Sections enhanced:** 9. They are Phase 0, Phase 1 item 4, a new Phase 3b, Phase 4.2, Phase 5, Phase 6, the Guard Contract, a new `## Observability` section, and the Scope Check/ACs/Test Scenarios/Sharp Edges.

**Agents used:**

- general-purpose (sonnet), twice: the verify-the-negative pass and the post-edit self-audit pass;
- `soleur:engineering:review:security-sentinel`;
- `soleur:engineering:review:test-design-reviewer`.

Gates 4.6-4.13 were run mechanically. The learnings sweep and the CTO ruling ran at plan time and were not repeated.

### Key improvements

1. **Exempt read call hardened against four reproduced bypasses** (security):
   - a rename out of `.github/` was invisible to `--name-only`;
   - a non-ASCII path was quoted past the regex anchors;
   - the exempt regex did not cover the agent-instruction files, including the canonical file that defines it;
   - the sha was pasted by hand between the read call and the arm call.

   Each predicate is now a named fail-closed statement, and the head passes through a git-dir file. A deepen-time run on real merged PRs gave the expected verdict for each of the 9 PRs named, plus a 17-PR bot census.
2. **(iii) now honours CTO Item A's carve-out.** A conflict-free `update-branch` merge is accepted as a clean sync: `git merge-tree --write-tree` equals the commit tree. A hand edit is refused. This was proven on #12489's two real sync merges and on a synthesized amended merge. The plan had previously refused every synced bot PR, which was stricter than the ruling (self-audit).
3. **Sixth bare re-arm found and folded in under Item C:** `sync-pr-behind.sh`'s `kind=dequeued` recovery text (verify-the-negative). It adds A5 and M15, plus two pin edits.
4. **Guard suite made falsifiable** (test-design):
   - span terminators, so arms cannot borrow pins;
   - a broadened A1-noH, with 0 false hits on the five sites;
   - statement-form A2b and anchored A4, so the plan's own prose cannot false-RED;
   - a per-alternative M14 loop over all 28 regex alternatives, each with a unique fixture checked at deepen time;
   - a self-dispatch ledger with a control row, and exactly-one `edit()`.
5. **Dry run made evidential:** a read-only allowlist shim with a refusal log, blocks composed by anchor with their sha256 recorded, full 40-hex SHAs, and new rows D7b, D14 and D15.

### New considerations discovered

- Evidence comments are accepted from any commenter, a residual that would edit the byte-identical canonical block. Filed as #12721.
- concurrent-ship T1b/T1c do not pin the rc=99 branch, so it is kept by review. admin-merge-ready-wiring does not read the reworded sentence. The #8593 detector does not see the new `gh` calls. Each claim is corrected in the body.
- The deepen-plan Phase 4.7 Observability gate fires on skill/test edits, so a layer-7 `## Observability` section was added.
- #12700 is open, so D11 moved to the merged #12691.

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
  - `plugins/soleur/test/pr-merge-poll.test.ts:214` pins drain-prs' "Armed on a merge-queue repo, not yet enqueued: leave it alone … kind=queue_wait".
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
  - *Deepen application, not a new ruling:* "drain-prs pushed nothing to it" is checked as (iii): every commit bot-written, or a clean sync of main. That keeps the ruling's conflict-free-sync carve-out and refuses drain-session edits. A-amend's surface classes gain the agent-instruction and CI-execution paths (security P1-2) under the same principle.

- **Item B (product-roadmap):** Ruled by CTO agent, 2026-11-12: B1. The check's first statement, then the existing lock block, in one Bash call. Both arms use `--match-head-commit "${H:?run the arm check in this call}"`, and the rc=99 read stays.
- **Item C (scope):** Ruled by CTO agent, 2026-11-12: fold in the merge-queue-dequeue.md step 3 and drain-prs dequeue re-arms. schedule/SKILL.md:519 and standing-delegation.md stay out (follow-up #12712).
- **Item D (guard):** Ruled by CTO agent, 2026-11-12: a static test `plugins/soleur/test/arm-check-sites.test.sh` with mutation rows, no allow-list. Prose that names the arm is reworded.

## Implementation Phases

### Phase 0 — RED: the static test first (`plugins/soleur/test/arm-check-sites.test.sh`)

Write the suite before any site edit, then run it. It must fail on drain-prs, product-roadmap, merge-queue-dequeue,
the ship/drain-prs prose and sync-pr-behind's dequeue message. It must pass on merge-pr and on ship's lock block.
Record the RED run in the commit message.

- **Sites** (`SITES` array, exact paths):
  - `plugins/soleur/skills/ship/SKILL.md`
  - `plugins/soleur/skills/merge-pr/SKILL.md`
  - `plugins/soleur/skills/drain-prs/SKILL.md`
  - `plugins/soleur/skills/product-roadmap/SKILL.md`
  - `plugins/soleur/skills/ship/references/merge-queue-dequeue.md`

  A missing site file is a FAIL, never a skip.

- **Occurrence scanner** (a python3 heredoc run with `python3 -I`; a function of `--root <dir>` and an optional `SPAN_RE` override, so the suite can re-run itself on a copy):
  - Join backslash-continued lines first.
  - Find every `gh pr merge` token, including after `with_lock … --` and after `rtk`.
  - A span runs from its token to the first of: the next `gh pr merge` token, an unquoted `;`, `&&`, `||`, `|`, `)`, an unescaped backtick, or the end of the joined line. This stops a bare arm from borrowing a later arm's pin on the same line (deepen, test-design).
  - A span is an **arm** when it contains `--auto` as a whole flag (not `--disable-auto`).
  - AC2's grep uses the same terminators.

- **A1:** every arm span carries `--match-head-commit "${H:?`. Under A1-exempt only, it may carry `--match-head-commit "${EXEMPT_HEAD:?` instead.
- **A1-floor (set identity):** each site file has at least one arm span. The floor is 1 per file, not today's exact counts, so a harmless edit stays green.
- **A1-noH (only the canonical statement sets `H`):** no site file matches this pattern (deepen, test-design; 0 matches in all five files at deepen time):

  ```text
  (^|[^A-Za-z0-9_-])H(\+?=|\[[^]]*\]=)|\$\{H:?=|(read|declare|typeset|export|local|readonly|mapfile|readarray|for)([[:space:]]+[^;&|]*)?[[:space:]]H([[:space:]=;]|$)|printf[[:space:]]+-v[[:space:]]*H
  ```

  The `-` in the first class keeps `gh api -H=…` from false-REDing (H7).

  Shell state does not cross Bash calls, so an arm reached without the check in its own call aborts on `${H:?…}` (D6). That runtime abort plus this assertion replaced the cut A1-order and A1-span.
- **A1-exempt:** `${EXEMPT_HEAD:?` appears in exactly one arm span in drain-prs/SKILL.md and in no arm span anywhere else. This is a per-file count, not an allow-list.
- **A2:** each site file contains the link anchor `review-evidence-comment.md#arm-check`.
- **A2b (single copy):** `grep -rlF 'echo "ARM_CHECK refused:' plugins/soleur/skills/` returns exactly `plugins/soleur/skills/review/references/review-evidence-comment.md`. Matching the statement form, not the bare phrase, means prose that names a refusal cannot false-RED. Site prose still says "a refusal from the arm check" rather than quoting the literal.
- **A3:** the canonical file contains:
  - the `|| { echo "ARM_CHECK refused: no passing evidence covers the PR head"; exit 1; }` statement;
  - the `--match-head-commit "${H:?run the arm check in this call}"` arm line;
  - exactly one line matching `^DOMAIN_SURFACE_RE='`, at column 0. drain-prs' `sed` extraction is anchored the same way.
- **A4 (domain regex: single copy and behaviour):**
  - `grep -rlE "^DOMAIN_SURFACE_RE='" plugins/soleur/skills/` returns only the canonical file. The anchor keeps drain-prs' `sed -n "s/^DOMAIN_SURFACE_RE=…"` line out of the match.
  - The regex is extracted from the canonical file the same way drain-prs extracts it. It must match every path in the synthesized MUST-MATCH list below. For each of the 28 top-level alternatives, the list holds at least one path that **only** that alternative matches; this was checked at deepen time, with 0 alternatives lacking one. That is what lets the M14 loop go RED on every deletion:

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
    Cargo.lock
    .claude/settings.json
    AGENTS.rules.md
    plugins/soleur/hooks/x.sh
    plugins/soleur/skills/drain-prs/SKILL.md
    plugins/soleur/skills/review/references/review-evidence-comment.md
    scripts/test-all.sh
    .gitmodules
    infra/main.yml
    main.tf
    x.hcl
    db/migrations/x.rb
    db/seed.sql
    .github/CODEOWNERS
    lib/auth/x.yml
    config/secrets.yml
    x/doppler.yaml
    bun.lockb
    ops/cloud-init.yml
    CLAUDE.md
    plugins/soleur/hooks/x.yml
    .claude-plugin/plugin.yml
    scripts/x.yml
    bunfig.toml
    vitest.config.ts
    ```

  - It must match none of the MUST-NOT-MATCH list. These are real exempt bot PR paths from #12694, #12692, #12406 and #12482:

    ```text
    knowledge-base/support/community/2026-11-12-digest.md
    knowledge-base/marketing/campaign-calendar.md
    knowledge-base/project/weakness-digest.md
    plugins/soleur/skills/legal-generate/NOTICE
    ```

- **A5 (sync-pr-behind's dequeue recovery):** `plugins/soleur/scripts/sync-pr-behind.sh` has no `gh pr merge` span carrying `--auto`, and its `kind=dequeued` message names both `merge-queue-dequeue.md` and `review-evidence-comment.md#arm-check`. The message is an agent-facing re-arm instruction in the same bypass class as Item C (deepen, verify-the-negative).
- **Self-dispatch and exit.** These rules make H1 and every mutation row meaningful (deepen, test-design):
  - The suite runs its assertions with `bash "$0" --root <dir>`. Each assertion appends its ID to a ledger.
  - A run exits 0 only when the ledger is exactly `{A1, A1-floor, A1-noH, A1-exempt, A2, A2b, A3, A4, A5}` and nothing failed.
  - A run exits 1 when any assertion fails, or with `ZERO-SPANS` when the scanner found no arm span at all.
  - A run exits 2 when the instrument itself broke, such as a missing ledger ID or a python error.
  - Before any row runs, a control dispatch on an untouched copy must exit 0.
  - A row counts as caught only on exit 1 that names its expected assertion ID. Exit 2 or higher is an instrument failure, never a pass.
- **Mutation discipline.** Every row edits through an `edit()` helper that requires exactly one replacement and is FATAL otherwise, as in `admin-merge-ready-wiring.test.sh`. Rows share one read-only base copy of the six files and copy only the file each row mutates.

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
     - every PR carrying a commit that is neither bot-written nor a clean sync of main. That covers a drain session's fix-recipe (a) lockfile regen, (b) conflict-resolving merge and (c) any edit, and (iii) checks it mechanically.
   - On a refusal from the arm check, run `soleur:review` on the PR (it posts fresh evidence), then the same call again.
   - If it still refuses, report `unarmed: no evidence covers the head` on the drain report and skip the PR. Never arm around it.
   - Skill prose refers to the refusal without quoting the canonical literal (A2b).

4. **Exempt arm.** This is the only other arm. A PR is exempt only when every predicate holds:
   - (i) a first-party bot opened it from this repository: the author is `app/soleur-ai` or `app/soleur-infra`, and `isCrossRepository` is `false`. Measured at deepen time, those are the only two bot authors in the last 200 PRs. Bot PRs never come from forks: 0 of 37;
   - (ii) §5 routes it to the inline diff read;
   - (iii) every commit is either **bot-written** or a **clean sync of main**:
     - Bot-written means both the author and the committer login are one of `github-actions[bot]`, `soleur-ai[bot]` or `soleur-infra[bot]`.
     - A clean sync is a merge commit whose second parent is on `origin/main` and whose tree equals `git merge-tree --write-tree` of its parents, so it carries no hand edit.
     - A null login counts as non-bot. The PR must have at most 250 commits, the API's page ceiling.
   - (iv) its tier is not `needs-conflict-resolution` or `broken`;
   - (v) no changed path matches `DOMAIN_SURFACE_RE`, with renames split into delete plus add, and no quoted (control-character), symlink, submodule or binary path in the diff;
   - (vi) the diff is at most 1500 lines and the agent read all of it.

   (iii) is how "drain-prs pushed nothing to it" is checked across sessions:
   - A drain session's lockfile regen, hand-resolved merge or edit is operator-authored and is not a clean sync, so (iii) refuses it.
   - A conflict-free `gh pr update-branch` or `git merge origin/main` is a clean sync, so it keeps the exemption. That is exactly CTO Item A's carve-out.
   - Measured at deepen time: #12489 carries two operator-authored `update-branch` merges, committed by GitHub. Both pass the clean-sync test, so its refusal comes from (v), not (iii).
   - A synthesized merge amended with an extra edit fails the test.

   Residual (deepen, security): a write-access actor can forge both author and committer emails, so (iii) is a tripwire for drain and sync commits, not an identity proof. Signature verification would refuse 100% of today's unsigned bot commits. (v), (vi) and the full diff read are the controls against a forged commit.

   (i), (iii), (v) and (vi) run mechanically in the read call, against the head that call captured. (ii) and (iv) are the agent's reading of the drain report, together with its reading of the printed diff.

   - **Read call.** One Bash call. Each predicate is its own fail-closed statement that names itself on refusal. The head goes to a file in the git dir only after every predicate passes, so the agent never pastes a sha (deepen, security P2-2):

     ```bash
     G=$(git rev-parse --git-dir) && rm -f "$G/soleur-exempt-<N>.head" || { echo "EXEMPT_ARM refused (setup): no git dir"; exit 1; }
     DOMAIN_SURFACE_RE=$(sed -n "s/^DOMAIN_SURFACE_RE='\(.*\)'\$/\1/p" "${CLAUDE_PLUGIN_ROOT:?}/skills/review/references/review-evidence-comment.md") && [ -n "$DOMAIN_SURFACE_RE" ] || { echo "EXEMPT_ARM refused (setup): domain-surface regex not read"; exit 1; }
     EXEMPT_HEAD=$(gh pr view <N> --json headRefOid --jq .headRefOid) && git fetch -q origin main "pull/<N>/head" && BASE=$(git merge-base origin/main "$EXEMPT_HEAD") || { echo "EXEMPT_ARM refused (setup): head, fetch or merge-base read failed"; exit 1; }
     PA=$(gh pr view <N> --json author,isCrossRepository --jq '"\(.author.login) \(.isCrossRepository)"') && case "$PA" in "app/soleur-ai false"|"app/soleur-infra false") ;; *) false ;; esac || { echo "EXEMPT_ARM refused (i): author and fork are $PA"; exit 1; }
     NC=$(gh api "repos/{owner}/{repo}/pulls/<N>" --jq .commits) && [ "$NC" -le 250 ] \
       && NB=$(gh api "repos/{owner}/{repo}/pulls/<N>/commits" --paginate --jq '.[] | select("\(.author.login // "?") \(.committer.login // "?")" | test("^(github-actions|soleur-ai|soleur-infra)\\[bot\\] (github-actions|soleur-ai|soleur-infra)\\[bot\\]$") | not) | .sha') \
       || { echo "EXEMPT_ARM refused (iii): commit list not read, or over 250 commits"; exit 1; }
     for C in $NB; do
       P2=$(git rev-parse -q --verify "$C^2") && git merge-base --is-ancestor "$P2" origin/main \
         && [ "$(git merge-tree --write-tree "$C^1" "$P2" 2>/dev/null)" = "$(git rev-parse "$C^{tree}")" ] \
         || { echo "EXEMPT_ARM refused (iii): $C is not bot-written and not a clean sync of main"; exit 1; }
     done
     F=$(git -c core.quotePath=false diff --name-only --no-renames "$BASE" "$EXEMPT_HEAD") && [ -n "$F" ] \
       && ! printf '%s\n' "$F" | grep -q '^"' \
       && [ "$(printf '%s\n' "$F" | grep -cE "$DOMAIN_SURFACE_RE")" = 0 ] \
       && R=$(git diff --raw --no-renames "$BASE" "$EXEMPT_HEAD") && ! printf '%s\n' "$R" | grep -qE '^:(120000|160000) |^:[0-7]{6} (120000|160000) ' \
       && NS=$(git diff --numstat "$BASE" "$EXEMPT_HEAD") && ! printf '%s\n' "$NS" | grep -q $'^-\t-\t' \
       || { echo "EXEMPT_ARM refused (v): a domain surface, symlink, submodule, binary or unreadable path"; exit 1; }
     L=$(git diff "$BASE" "$EXEMPT_HEAD" | wc -l) && [ "$L" -le 1500 ] || { echo "EXEMPT_ARM refused (vi): the diff is $L lines, over 1500"; exit 1; }
     NOW=$(gh pr view <N> --json headRefOid --jq .headRefOid) && [ "$NOW" = "$EXEMPT_HEAD" ] || { echo "EXEMPT_ARM refused: the head moved during the read"; exit 1; }
     printf '%s\n' "$EXEMPT_HEAD" > "$G/soleur-exempt-<N>.head" || { echo "EXEMPT_ARM refused (setup): head file not written"; exit 1; }
     echo "EXEMPT_READ head=$EXEMPT_HEAD"
     git diff --stat "$BASE" "$EXEMPT_HEAD"
     git diff "$BASE" "$EXEMPT_HEAD"
     ```

     - Each capture stays separate from its test. Piping `git diff` straight into `grep -c` without pipefail would turn a failed git call into "0" and pass.
     - `core.quotePath=false` keeps non-ASCII paths unquoted, so the regex anchors still bite. A path git still quotes contains a control character, a quote or a backslash, and it is refused.
     - Deepen-time run, read-only, with the amended regex:
       - #12694, #12692, #12482 and #12406 print `EXEMPT_READ`.
       - #12691, #12489, #12700 and #11291 (a bot SKILL.md promote) refuse at (v).
       - #12633 refuses at (i).
       - A census of 17 merged bot PRs gave 10 exempt and 7 refused at (v), all `chore(infra)`.
       - An unset `CLAUDE_PLUGIN_ROOT` refuses at setup.
   - **Arm call.** Run it only after `EXEMPT_READ head=<sha>`, and after the agent has read the whole diff and found nothing that §5 would send to review:

     ```bash
     G=$(git rev-parse --git-dir) && EXEMPT_HEAD=$(cat "$G/soleur-exempt-<N>.head") && rm -f "$G/soleur-exempt-<N>.head" || { echo "EXEMPT_ARM refused: no read head on file; run the read call"; exit 1; }
     NOW=$(gh pr view <N> --json headRefOid --jq .headRefOid) && [ "$NOW" = "$EXEMPT_HEAD" ] || { echo "EXEMPT_ARM refused: the head moved since the read"; exit 1; }
     gh pr merge <N> --squash --auto --match-head-commit "${EXEMPT_HEAD:?run the exempt read call first}"
     ```

   - If the agent's read of the diff says "not exempt", it deletes the head file and uses the checked arm.
   - Record the exemption on the drain report line: `exempt: first-party bot, bot-only or clean-sync commits, no domain surface, read at <sha>`.
   - Two calls rather than the CTO's literal "same call": an agent cannot judge a diff inside the call that arms. The mechanical predicates bind to the captured head, the head reaches the arm through a file, not a paste, and the arm re-checks it before pinning. That delivers the ruling's property.
   - **Never assign `H`, `EV` or `EXEMPT_HEAD` by hand.** Only the canonical statement sets `H`, and only the read call's head file sets `EXEMPT_HEAD`.

5. **Dequeue bullet** (line 89). "re-arm `gh pr merge <N> --squash --auto` only when `autoMergeRequest` is `null`" becomes: re-arm only when `autoMergeRequest` is `null`, through [merge-queue-dequeue.md](${CLAUDE_PLUGIN_ROOT}/skills/ship/references/merge-queue-dequeue.md) step 3.
   - A dequeued exempt PR has no evidence, so the recipe's check would always refuse it. It re-arms through the exempt read and arm calls instead, and the read call's (iii) re-runs.
   - A push in the recipe's step 2 removes the exemption: `soleur:review`, then the checked arm. If that still refuses, report and skip.
   - "Cap it at ONE re-enqueue" stays.

6. **Prose rewording**, so A1 sees no bare arm span.
   - Line 88: "`gh pr merge <N> --squash --auto` **enqueues** the PR" becomes "arming **enqueues** the PR".
   - Line 131: "**`gh pr merge --squash --auto` cannot bypass …**" becomes "**Arming auto-merge cannot bypass …**".
   - The rest of both sentences is unchanged. admin-merge-ready-wiring.test.sh does not read these sentences: it guards `--admin` lines, the `admin-merge-ready.sh` mention and two banned phrases. Run it as a regression guard.

7. **§5.**
   - Add one bullet: bot-authored scheduled content PRs (community digests, campaign calendar, content-distribution promotes, weakness digests) take the inline diff read, the same route as single-file `priority/p3-low` bot-fixes. A PR that fails the exempt arm's predicates goes to `soleur:review`.
   - "Merge only if it passes" on the feature-PR bullet becomes "Merge only if it passes, then arm through the arm check".

### Phase 2 — product-roadmap Phase 4 step 3 (`plugins/soleur/skills/product-roadmap/SKILL.md`)

1. **Step 3 lead.** Arm only through the arm check in [review-evidence-comment.md](${CLAUDE_PLUGIN_ROOT}/skills/review/references/review-evidence-comment.md#arm-check): its first statement with `PR_NUMBER=<number>`, then the lock block below, in one Bash call. The check's `exit 1` stops the call before the lock.
   - On a refusal from the arm check, run `soleur:review`, then the call again. Never arm around it.
   - By step 3, ship Phase 6.5/7 may already have armed, queued or merged the PR. A non-zero `rc` other than 99 therefore means "read `gh pr view <number> --json state,autoMergeRequest` and report". A merged or already-armed PR is not a failure.
2. **Both lock arms** (lines 325 and 330): `gh pr merge <number> --squash --auto --match-head-commit "${H:?run the arm check in this call}"`.
3. **Byte-identical**. concurrent-ship.test.sh T1b pins exactly one `bash "$SS_LIB" with_lock merge-main` line and at least one `reason=running-unlocked`. T1c pins the plugin-root session-state anchor. Nothing pins the rc=99 branch or the `600 -- \` suffix, so keep them by review. New step-3 prose must not repeat the `bash "$SS_LIB" with_lock merge-main` call form, or T1b counts 2:
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

### Phase 3b — sync-pr-behind's dequeue recovery (`plugins/soleur/scripts/sync-pr-behind.sh`)

The `kind=dequeued` message, on the `tag dequeued 13` line, is the in-band copy of the dequeue recovery that ship's and merge-pr's Phase 7 poll and drain-prs relay to the agent. Its step (3) says "re-arm once: gh pr merge $PR --squash --auto", which is a bare arm instruction. The verify-the-negative pass found it at deepen time. Folding it in applies CTO Item C, the dequeue re-arms; it is not a new ruling.

- Step (3) becomes: "(3) re-arm once, only when autoMergeRequest is null, through the arm check (plugins/soleur/skills/review/references/review-evidence-comment.md#arm-check; procedure step 3); a refusal is reported, never armed around."
- The rc (13), the `kind=dequeued` tag, steps (1)-(2) and the "second dequeue: stop" sentence are unchanged.
- Two suites pin the old text and are edited in the same commit, so they are **not** "unedited":
  - `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` scenario 18b: its expected line `gh pr merge 4387 --squash --auto` becomes `review-evidence-comment\.md#arm-check`.
  - `plugins/soleur/test/sync-pr-behind.test.sh` dequeue tick 2: `grep -q "gh pr merge $QUEUE_PR --squash --auto"` becomes `grep -q 'review-evidence-comment.md#arm-check'`.
- A5 and M15 guard the message.

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
     DOMAIN_SURFACE_RE='(^|/)infra/|\.tf$|\.tfvars$|\.hcl$|(^|/)migrations/|\.sql$|^\.github/|(^|/)legal/|(^|/)o?auth[^/]*(/|\.)|(^|/)secrets?(/|\.|-)|doppler|(^|/)package(-lock)?\.json$|(^|/)bun\.lockb?$|\.lock$|(^|/)Dockerfile|(^|/)\.env|cloud-init|(^|/)middleware\.ts$|(^|/)\.claude/|(^|/)AGENTS[^/]*\.md$|(^|/)CLAUDE\.md$|^plugins/[^/]+/(hooks|agents|commands|scripts)/|^plugins/[^/]+/skills/.*\.(md|sh|m?js|ts|py|json)$|(^|/)\.claude-plugin/|^scripts/|(^|/)\.git(modules|attributes)$|(^|/)bunfig\.toml$|\.config\.[cm]?[jt]s$'
     ```

     In the canonical file this line sits at **column 0**, in an unindented fence, so the `sed` extraction and A3/A4 match it. The plan shows it indented only because it is nested in a list here.

     The deepen pass (security P1-2) added the agent-instruction and CI-execution classes after A-amend: `.claude/`, `AGENTS*.md`, `CLAUDE.md`, plugin hooks/agents/commands/scripts, plugin skill code and markdown, `.claude-plugin/`, `scripts/`, `.gitmodules`/`.gitattributes`, `bunfig.toml` and `*.config.[cm][jt]s`. A bot PR that edits this file, drain-prs' own SKILL.md or a hook would otherwise rewrite the gate for every later run. Measured cost: 2 of 37 bot PRs, both self-healing SKILL.md promotes (#11291, #11750), which belong in review anyway. `plugins/soleur/skills/legal-generate/NOTICE` (#12482) stays exempt through the extension filter.

     The prose says the regex is a floor, not the whole gate. Code classes it cannot name, such as input validation or auth helpers under other names, still route to `soleur:review` on the agent's read: in doubt, checked arm.
   - The `## Arm check` first sentence lists the same sites and adds: "drain-prs' exempt arm (first-party bot author, bot-written or clean-sync commits, no `DOMAIN_SURFACE_RE` path) is the one recorded exemption; it pins the head its read call wrote (drain-prs §4). Never assign `H`, `EV` or `EXEMPT_HEAD` by hand: only the statement, or the exempt read call, sets them." It also adds sync-pr-behind's dequeue message to the site list.
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
   - `bash plugins/soleur/test/sync-pr-behind.test.sh` (edited: dequeue tick 2's grep, Phase 3b);
   - `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` (edited: scenario 18b's expected line, Phase 3b);
   - `bun test plugins/soleur/test/pr-merge-poll.test.ts plugins/soleur/test/components.test.ts`. The #8593 unbounded-enumeration detector does not flag the new calls either way (`pulls/<N>/…` is an item scope, and it never matches `gh pr view`). `--paginate` is there for correctness past 30 commits, not for the gate.
   - `bash scripts/lint-orphan-test-suites.sh`;
   - `bash scripts/test-all-corpus-weight-budget.test.sh`;
   - `bash plugins/soleur/test/scripts-shard-manifest.test.sh`;
   - `bash plugins/soleur/test/regenerate-shard-manifest.test.sh`;
   - `npx markdownlint-cli2` on every edited `.md`.

### Phase 6 — dry-run proof (arms nothing)

- **Shim.** A PATH shim lives in the session scratchpad, never in the repo, and wraps `gh` (deepen, test-design):
  - It forwards only `pr view`, `pr checks` and `api` calls with no `-X`/`--method` other than GET and no `-f`/`-F`/`--input`.
  - `pr merge` prints `WOULD-ARM <args>` and exits 0.
  - Anything else is refused with exit 64 and logged to `shim-refused.log`, which must be empty at the end.
  - Every case first prints `type -p gh`, and that path must be the shim.
- **Composition.** A scratchpad script (`compose.sh`) pulls each fenced block from the **edited** site file by its anchor. It then appends the canonical check's first statement where the site says to, and substitutes `PR_NUMBER`/`<N>`/`<number>` with `sed`.
  - Record the sha256 of each composed block. Hand-pasting is not allowed.
  - Each case runs in one `bash` call with the shim first on PATH and `CLAUDE_PLUGIN_ROOT` exported to the worktree's `plugins/soleur`. It records rc, stdout and stderr.
- **Read-only.** Every PR used is merged, verified live at deepen time: #12619, #12518, #12633, #12694, #12691, #12489 and #11291. Every call is therefore read-only, and the shim blocks any write regardless.
- **Exempt cleanup.** Exempt-call cases write and remove `$(git rev-parse --git-dir)/soleur-exempt-<N>.head`. A case that leaves one behind fails.

| # | Block | PR | Expected |
|---|---|---|---|
| D1 | drain-prs checked arm | #12619 | `ARM_CHECK refused: no passing evidence covers the PR head`, rc 1, no `WOULD-ARM`. A separate read-only `git rev-list --first-parent --no-merges 0127b5dc45..7d20e7c1a6` prints `7d20e7c1a61aa99ff7cdaaae66919ca19f51e50b` |
| D2 | drain-prs checked arm | #12518 | `WOULD-ARM 12518 --squash --auto --match-head-commit 1af1ec063da61a0d2c467895756768f1ec7c1eed`, rc 0 |
| D3 | product-roadmap locked arm | #12619 | `ARM_CHECK refused: no passing evidence covers the PR head`, rc 1, no `WOULD-ARM`; no `merge-main` lock file appears under the session-state lock dir during the case |
| D4 | product-roadmap locked arm | #12633 | `WOULD-ARM 12633 --squash --auto --match-head-commit ee92097453ac789a3a8b4ee7360ed15138cae178`, rc 0 |
| D6 | product-roadmap lock block alone, no check | #12633 | stderr `H: run the arm check in this call`, no `WOULD-ARM` (the runtime half of A1-noH) |
| D7 | drain-prs exempt read call, then the arm call | #12694 (`app/soleur-ai`; sole commit by `github-actions[bot]` as author and committer; one `knowledge-base/support/community/` file) | `EXEMPT_READ head=f0972c275114b6f69cb3769c1840eaab43230578`, then `WOULD-ARM 12694 --squash --auto --match-head-commit f0972c275114b6f69cb3769c1840eaab43230578`; no head file left |
| D7b | drain-prs exempt arm call alone, no read | #12694 | `EXEMPT_ARM refused: no read head on file; run the read call`, no `WOULD-ARM` |
| D9 | merge-queue-dequeue step 3 | #12619 | `ARM_CHECK refused: no passing evidence covers the PR head`, rc 1, no `WOULD-ARM` |
| D11 | drain-prs exempt read call | #12691 (`app/soleur-ai`; sole commit by `github-actions[bot]`; `apps/web-platform/infra/cron-egress-allowlist-cidr.txt`) | `EXEMPT_ARM refused (v): …`; (i) and (iii) passed, no `EXEMPT_READ` |
| D13 | drain-prs exempt read call | #12633 (human author) | `EXEMPT_ARM refused (i): author and fork are deruelle false` |
| D14 | drain-prs exempt read call | #12489 (`app/soleur-infra`; two operator-authored `update-branch` merges) | `EXEMPT_ARM refused (v): …`: the clean-sync merges passed (iii) |
| D15 | drain-prs exempt read call | #11291 (bot promote editing a SKILL.md) | `EXEMPT_ARM refused (v): …` (the A-amend agent-instruction classes) |

Record the table in the PR body under `## Dry-run proof`, with each case's last output line, rc, the composed block's sha256 and the empty `shim-refused.log`.

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
- `plugins/soleur/scripts/sync-pr-behind.sh`: the `kind=dequeued` message's step (3) (Phase 3b).
- `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`: scenario 18b's expected line.
- `plugins/soleur/test/sync-pr-behind.test.sh`: dequeue tick 2's grep.
- `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`: one row each.

## Files to Create

- `plugins/soleur/test/arm-check-sites.test.sh`

## Open Code-Review Overlap

None. The bodies of `gh issue list --label code-review --state open --limit 200` were matched against every path above.

## User-Brand Impact

- **If this lands broken, the user experiences** one of two failures:
  - drain-prs or product-roadmap refuses to arm a PR that should merge. The operator sees `unarmed: no evidence covers the head` or `EXEMPT_ARM refused` on a drain report, or a refused roadmap PR, and one `soleur:review` resolves it.
  - A bare arm survives, and a PR merges with commits no review saw (the #12619 class). Unreviewed code reaches the operator's `main`.
- **If this leaks, the user's workflow is exposed via:** a merge of unreviewed code into the operator's repository. No user data, credentials or money path is touched. The diff is skill prose and a static test.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the change narrows when an agent may arm auto-merge in the operator's own repo, and it fails closed. Its worst failure is the existing bare-arm behaviour persisting. Required CI still gates every merge server-side, and no path in the diff matches the preflight Check 6 sensitive-path regex.

## Guard Contract

### Guard 1 — arm-check-sites (`plugins/soleur/test/arm-check-sites.test.sh`)

**Property.** Every skill site, and sync-pr-behind's dequeue message, that arms or re-arms auto-merge binds each arm to a head the arm check set: `--match-head-commit "${H:?…}"`. `H` is assigned nowhere but the canonical statement. The one exception is drain-prs' single exempt arm, bound to the head its read call wrote (`${EXEMPT_HEAD:?…}`). The exemption's path regex exists once, at column 0 of the canonical file, and every alternative in it is load-bearing against the fixtures.

**Assembly.**

- **Chokepoint:** every textual `gh pr merge … --auto` span an agent can copy out of the site files, fenced or inline, cut at the span terminators in Phase 0. That covers spans after `with_lock … --`, after `rtk`, and across backslash continuations.
- **Site set:** the `SITES` array, checked as set identity: each file present, each with at least one arm span. `sync-pr-behind.sh` sits beside it under A5 as the one script-emitted re-arm instruction.
- **Canonical copy:** `review-evidence-comment.md`, checked for presence (A3) and for uniqueness across `plugins/soleur/skills/` (A2b, A4).
- **Not in the assembly, by ruling:**
  - `schedule/SKILL.md` (a workflow template);
  - `standing-delegation.md` (#12712);
  - a new arm site in a sixth file. That is the residual. Its re-evaluation trigger is #12656's own: any PR found merged past its evidence head.

**Mutation matrix.** Each row must exit 1 naming the assertion ID shown.

| # | Mutation (temp copy) | Expected |
|---|---|---|
| M1 | strip `--match-head-commit "${H:?…}"` from drain-prs' checked arm | RED (A1) |
| M2 | append a second bare `gh pr merge <number> --squash --auto` after product-roadmap's compliant locked arm | RED (A1, second member) |
| M2b | on one line in ship: a bare `gh pr merge 7 --auto;`, then a pinned `gh pr merge 8 --auto --match-head-commit "${H:?x}"` | RED (A1: the span ends at `;`, so arm 7 cannot borrow arm 8's pin) |
| M3 | split a bare arm across a continuation in merge-queue-dequeue: `gh pr merge <N> \`, newline, an indented `--squash --auto` | RED (A1, join) |
| M5 | delete the `review-evidence-comment.md#arm-check` link from merge-queue-dequeue.md | RED (A2) |
| M6 | paste the canonical `echo "ARM_CHECK refused: …"` statement into drain-prs/SKILL.md | RED (A2b) |
| M7 | delete the `ARM_CHECK refused` statement line from the canonical copy | RED (A3) |
| M8 | point one `SITES` entry at a nonexistent path; separately, strip every arm span from merge-queue-dequeue.md (not drain-prs, so A1-exempt stays quiet) | RED (missing file; A1-floor) |
| M10 | above product-roadmap's lock block insert, one at a time: `H=$(gh pr view <number> --json headRefOid --jq .headRefOid)`, `read -r PR H`, `: "${H:=x}"` | RED (A1-noH, each spelling) |
| M11 | copy drain-prs' exempt arm line (`${EXEMPT_HEAD:?`) into product-roadmap; separately, add a second one in drain-prs | RED (A1-exempt: zero elsewhere, exactly one in drain-prs) |
| M14 | paste a second column-0 `DOMAIN_SURFACE_RE='…'` line into drain-prs (A4 single copy); and loop over every top-level alternative of the canonical regex (split on `\|` outside parentheses, since `(^\|/)` nests one), deleting it alone | RED for the paste; for EACH deleted alternative, at least one MUST-MATCH fixture misses (A4) |
| M15 | restore `(3) re-arm once: gh pr merge $PR --squash --auto` in sync-pr-behind.sh's `kind=dequeued` message | RED (A5) |

**Harness rows.**

| # | Harness edit / input | Expected |
|---|---|---|
| H1 | self-dispatch with `SPAN_RE` set to a pattern that matches nothing | exit 1 with `ZERO-SPANS` |
| H3 | must-PASS, non-canonical: `gh pr merge 7 --disable-auto` plus a compliant `gh pr merge "$N" --auto --squash --match-head-commit "${H:?x}"` (different flag order and placeholder) | GREEN |
| H4 | must-PASS near-miss: a `` `gh pr merge` unlocked `` span with no `--auto`, and an inline `` `gh pr merge <N> --squash` `` | GREEN (not an arm span) |
| H5 | must-PASS: a `# comment` line between the link sentence and a compliant arm inside a fenced block | GREEN (no assertion depends on markdown headings) |
| H6 | must-PASS: a pinned arm wrapped as `bash "$SS_LIB" with_lock merge-main 600 -- gh pr merge 7 --squash --auto --match-head-commit "${H:?x}"` | GREEN (the replacement for the cut M4, which duplicated M2) |
| H7 | must-PASS: a `gh api -H=Accept …` line in a site | GREEN (A1-noH does not false-RED on `-H=`) |
| H8 | control: self-dispatch on the untouched base copy | exit 0 with the full ledger; anything else aborts the suite with exit 2 |

**Anchor.** There is no stored hash or count. The per-file floor is 1. A2b and A4 are set identities over the tree, and M14's loop derives its rows from the canonical regex itself. The anchor outside the commit is `soleur:review` of this PR.

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
| follow-up issues #12711, #12712, #12715, #12721 | — | inferred — justification: CTO dissents, the plan-review residual and the deepen security P2-3 (#12721, the evidence-author filter that would edit the byte-identical canonical block); a deferral needs a tracking issue |
| sync-pr-behind.sh dequeue message plus its two test pins (Phase 3b) | — | inferred — justification: binding CTO Item C (dequeue re-arms); the deepen verify-the-negative pass found this in-band copy of the same bare re-arm |
| exempt-read hardening: author allowlist, clean-sync (iii), `--no-renames`/quotePath/symlink/binary (v), head file | — | inferred — justification: deepen security P1-1/P2-1/P2-2 bypasses, each reproduced; the clean-sync clause restores Item A's carve-out for conflict-free syncs |

### Split Assessment

- Subsystems touched: 2 (`plugins/soleur/` skills, scripts and tests; `scripts/` weight rows)
- Planned files: 11 (10 edit, including the 2 TSVs, + 1 create) | Estimated changed lines: about 380 (test about 230, prose and read call about 130, script and pins about 20)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `bash plugins/soleur/test/arm-check-sites.test.sh` exits 0. The ledger is exactly A1, A1-floor, A1-noH, A1-exempt, A2, A2b, A3, A4 and A5. M1, M2, M2b, M3, M5, M6, M7, M8, M10, M11, M14 (paste plus all 28 per-alternative deletions) and M15 each exit 1 naming their assertion. H1 exits 1 with `ZERO-SPANS`. H3-H7 stay GREEN, and the H8 control exits 0. The suite's first commit records a RED run against the unedited sites.
- [ ] AC2 — over the five site files plus `plugins/soleur/scripts/sync-pr-behind.sh`, `` grep -n -o 'gh pr merge[^`|;&)]*' <site> | grep -- --auto | grep -v -- --disable-auto `` (the scanner's terminators) prints only lines carrying `--match-head-commit "${H:?` or `--match-head-commit "${EXEMPT_HEAD:?`. Exactly one carries `${EXEMPT_HEAD:?`, and it is in drain-prs/SKILL.md.
- [ ] AC3 — `grep -rlF 'echo "ARM_CHECK refused:' plugins/soleur/skills/` and `grep -rlE "^DOMAIN_SURFACE_RE='" plugins/soleur/skills/` each print exactly `plugins/soleur/skills/review/references/review-evidence-comment.md`. `git diff 21202186df -- plugins/soleur/skills/review/references/review-evidence-comment.md` shows no change inside the arm check's fenced block.
- [ ] AC4 — drain-prs §4 carries the checked arm and the route rule. It also carries the exempt read call: one named fail-closed statement per predicate, (i) the author allowlist plus `isCrossRepository`, (iii) bot-written or clean-sync, (v) `--no-renames`, `core.quotePath=false`, symlink/submodule/binary refusal, (vi) the 1500-line cap, and the head file. Then the arm call, which reads the head file and re-checks the head before pinning `${EXEMPT_HEAD:?`. §5 names the bot scheduled content PRs.
- [ ] AC5 — product-roadmap step 3 links `#arm-check`, and both lock arms pin `${H:?run the arm check in this call}`. `bash plugins/soleur/test/concurrent-ship.test.sh` passes with that suite unedited.
- [ ] AC6 — each Phase 5 suite exits 0: ci-head-verdict, drain-prs, admin-merge-ready-wiring and monitor-lock unedited; sync-pr-behind and ship-phase-7-poll-fixtures with only the Phase 3b pin edits; plus `bun test` over pr-merge-poll and components.
- [ ] AC7 — `bash scripts/lint-orphan-test-suites.sh` and `bash scripts/test-all-corpus-weight-budget.test.sh` exit 0 with the new rows.
- [ ] AC8 — dry runs D1, D2, D3, D4, D6, D9 and D16-D18 (amended 2026-11-13 by R1/R4; D7, D7b, D11, D13-D15 went with the exempt arm) print exactly the tabled last lines, full 40-hex SHAs included. They are recorded in the PR body under `## Dry-run proof` with rc and composed-block sha256. `shim-refused.log` is empty, `type -p gh` resolved to the shim in every case, and no `soleur-exempt-*.head` file remains.
- [ ] AC9 — `technical-ruling-gate.sh --branch` passes on decision-challenges.md (5 rows). The PR body links #12711, #12712, #12715 and #12721, and says `Closes #12656` in the body, not the title.

### Post-merge (operator-free)

- [ ] AC10 — `soleur:postmerge` runs on the merge sha and reports no deploy for plugin-only paths. `gh release list --limit 1` shows a release tagged after the merge, on the PR's semver label.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO Rule interface (one batched ruling spawn, Items A-D) plus the plan-review devex advisory, which produced amendment A-amend. No product or UX surface: no UI files, and the mechanical UI-surface override did not fire. Legal, finance, marketing, sales, support and operations have no implications: this is internal skill prose plus a test. #12658, the marketing thread, is gated on this issue and handled by the calling session.

## Observability

The surface is skill prose that an agent executes, on the operator's CLI (layer 7, `cli-stdout-artifact`) and, because `plugins/` is vendored into the platform image, in hosted agent sessions (layers 1-6). There is no new server code, no catch block, and no Sentry call site. The signal is the refusal line on stdout, plus durable state on GitHub that any later session reads without SSH.

```yaml
liveness_signal:
  what: "per-run drain report line per PR (armed at <sha> | unarmed: no evidence covers the head | exempt: ... read at <sha>) on tool-result stdout; durable twin is the PR's GitHub autoMergeRequest (null when refused) plus its Review-Evidence comment"
  cadence: "per drain-prs / product-roadmap / dequeue re-arm run, once per PR"
  alert_target: "the running session's agent and operator (drain report), and any later session via gh pr view <N> --json autoMergeRequest"
  configured_in: "plugins/soleur/skills/drain-prs/SKILL.md §4; plugins/soleur/skills/review/references/review-evidence-comment.md ## Arm check"

error_reporting:
  destination: "layer 7 cli-stdout-artifact on the self-hosted CLI (no Soleur-side sink, by design); hosted sessions use the existing agent-runner Bash tool-result capture (layers 1-6), unchanged by this diff"
  fail_loud: "the lines ARM_CHECK refused: no passing evidence covers the PR head / EXEMPT_ARM refused: ... / H: run the arm check in this call, each with exit 1"

failure_modes:
  - mode: "a site arms without the check (bare arm reintroduced)"
    detection: "plugins/soleur/test/arm-check-sites.test.sh A1 in CI (test-all.sh scripts shard)"
    alert_route: "required CI check on the PR that reintroduces it (layer: CI, pre-merge)"
  - mode: "a PR merged past its evidence head despite the gate"
    detection: "Review-Evidence head= on the PR vs merged headRefOid, read with gh (layer 7 durable artifact: the PR comment and merge record on GitHub)"
    alert_route: "issue #12656's re-evaluation trigger; filed as a new issue by whichever session finds it"
  - mode: "an exempt arm on a PR that touched a domain surface"
    detection: "A4 MUST-MATCH fixture in arm-check-sites.test.sh (CI) plus the drain report's exempt line naming the read sha (layer 7)"
    alert_route: "required CI check; drain report read by the operator"

logs:
  where: "session tool-result stdout (layer 7); GitHub PR timeline (auto_merge_enabled events, Review-Evidence comments) as the durable record"
  retention: "GitHub PR timeline: life of the repository; session stdout: the session transcript"

discoverability_test:
  command: grep -lF 'review-evidence-comment.md#arm-check' plugins/soleur/skills/drain-prs/SKILL.md
  expected_output: "drain-prs"
```

## Infrastructure / Observability / Architecture gates

- **IaC (2.8):** none.
- **Observability (2.9):** see `## Observability`. deepen-plan Phase 4.7 fires on skill `.md` and `.test.sh` edits, and plan 2.9's narrower code-class trigger did not.
- **ADR/C4 (2.10):** none. This extends #12633's existing gate to more call sites. It moves no ownership, trust or substrate boundary, and the exemption is a site rule recorded in the canonical file. There is no C4 actor, system, container or relationship change, and a test suite is not a counted component for `c4-count-parity.test.sh`.
- **Encryption (2.11), GDPR (2.7), Task design (2.9.3):** do not fire.

## Test Scenarios

- T1: the static suite is RED on the unedited tree. It names drain-prs :84/:88/:89/:131, product-roadmap :325/:330, dequeue :30 and ship :473/:1616/:1635. A3/A4 fail on the missing `DOMAIN_SURFACE_RE` line, and A5 fails on sync-pr-behind's dequeue message.
- T2: the same suite is GREEN after Phases 1-4 and 3b.
- T3: the in-suite rows M1, M2, M2b, M3, M5, M6, M7, M8, M10, M11, M14 and M15 exit 1 naming their assertion. H1 exits 1 with `ZERO-SPANS`. H3-H7 stay GREEN, and the H8 control exits 0.
- T4: dry runs D1, D2, D3, D4, D6, D9 and D16-D18 (Phase 6; amended 2026-11-13 by R1/R4).
- T5: the existing suites stay green, unedited except for the two Phase 3b pins (Phase 5 list).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6. It is filled above.
- The canonical check's fenced statement must not change. Edit only the prose around it and add the `## The gate` regex block. A reworded jq or rev-list line silently changes every site.
- drain-prs must fetch `pull/<N>/head` before the check. Otherwise `merge-base` fails on a missing object and the PR reads as "no evidence".
- The ci-head-verdict L2 chain and the concurrent-ship lock lines must stay byte-identical.
- To the new suite, a `--auto` inside a backticked `gh pr merge` span in any of the five files is an arm. New prose says "arm" instead of quoting a command.
- Never run Phase 6 blocks without the shim first on PATH.
- In `X=$(cmd) && [ test ]`, a failed `cmd` short-circuits to the refusal. `[ -z "$(cmd)" ]` alone would pass on a failure. Keep every capture in the first form, and keep `// "?"` (never `// ""`) for null logins.
- Exempt predicate (iii) is a tripwire, not an identity proof. A write-access actor can forge author and committer emails, so (v), (vi) and the full diff read carry the weight. Signature checks would refuse every unsigned bot commit today.
- `git diff --name-only` with rename detection prints only the new path, and `core.quotePath` quotes non-ASCII paths, which breaks the `^`/`$` anchors. Keep `--no-renames` and `-c core.quotePath=false` in (v). Both were reproduced as bypasses at deepen time.
- The exempt head reaches the arm through `$(git rev-parse --git-dir)/soleur-exempt-<N>.head`, written only after every predicate passes. Never paste the sha into the arm call.
- New step-3 prose in product-roadmap must not repeat the `bash "$SS_LIB" with_lock merge-main` call form (concurrent-ship T1b counts it).
- Residual (#12721): the arm check accepts a `Review-Evidence:` comment from any commenter.
- Residual (#12715): `--match-head-commit` binds at arm time. Whether a later push to an armed PR merges the new head is unmeasured, for both arms.
