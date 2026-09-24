---
title: "fix(hooks): pre-merge-rebase review-evidence gate derives its commit range from the PR being merged, not the session cwd"
date: 2026-09-24
slug: fix-pre-merge-review-gate-pr-head-range
branch: feat-one-shot-8778-merge-gate-pr-head-range
issue: 8778
closes: 8778
type: fix
priority: p2-medium
domain: engineering
brand_survival_threshold: none
---

# fix(hooks): pre-merge review-evidence gate reads the PR head, not the session cwd

## Enhancement Summary

**Deepened on:** 2026-09-24, after a four-seat plan review (see `## Plan Review Revisions`).
Gates run: 4.6 User-Brand Impact, 4.7 Observability (discoverability literal fixed to a single
token), 4.8 PAT sweep (clean), 4.11 Guard Contract (`lint-guard-contract.py` green after splitting
the mutation matrix per guard). Live verification: `gh pr view 8650 --json
headRefName,headRefOid,isCrossRepository` returns all three fields; every cited rule id resolves;
#8777 CLOSED, #8616/#7822 OPEN, #8650/#8757 MERGED. The broad 40-agent research fan-out was not
run: the planning pass already applied the relevant learnings and verified every platform fact
live, and the change is ~40 lines of repo-local bash with no framework or external API surface.

## Overview

The review-evidence gate in `.claude/hooks/pre-merge-rebase.sh` decides whether a `gh pr merge <N>`
may proceed by scanning `origin/main..HEAD` in the directory named by the PreToolUse envelope's
`.cwd`. That field is the session's anchored directory, not the directory an in-command `cd` moves
to, so a subagent anchored at the repo root that runs `cd <worktree> && gh pr merge <N>` has the
gate scan the root's detached HEAD and deny a PR that does carry a `Reviewed-By-Soleur` trailer.
This plan moves the gate's range to the PR's own head commit, resolved from GitHub.

## Research Insights

### Premise Validation

- **#8778** is OPEN (`type/bug`, `priority/p2-medium`, `meta/machinery`); no PR closes it yet.
- **#8777**, the code-review issue filed only to satisfy Signal 3, is **already CLOSED**. The issue's
  "Cleanup: close #8777" step is done, so it is not a task in this plan.
- **Mechanism confirmed against the live layout.** The repo root
  (`/data/git-repositories/jikig-ai/soleur`) is a normal checkout in **detached HEAD**:
  `git rev-parse --abbrev-ref HEAD` prints `HEAD`. So a root-anchored session gets
  `CURRENT_BRANCH=HEAD`. That does not match the `main`/`master` early exit
  (`pre-merge-rebase.sh`, the `Skip if already on main/master` block), so the gate runs over
  `origin/main..HEAD` of the root, finds none of the PR's commits, and denies. The
  detached-HEAD exit (`Check for detached HEAD -- auto-sync needs a branch to push`) comes *after*
  the gate, so it never rescues this case.
- **The proposed range would have allowed the real incident.** PR #8650: `gh pr view 8650 --json
  headRefName,headRefOid` → `feat-8486-human-presence-guard` / `59c2e8089f29…`, and the trailer
  commit `3ec4e791e7` (`Reviewed-By-Soleur: soleur:review`) is an ancestor of that head
  (`git merge-base --is-ancestor` → true). `git ls-remote origin refs/pull/8650/head` returns the same
  oid, so the `pull/<N>/head` fetch fallback is served by GitHub.
- The issue cites `WORK_DIR="$HOOK_CWD"` "around line 108". That is correct on `origin/main`.
- **The bug has two sides; the issue names only one.** A session anchored in worktree A (reviewed,
  with a trailer) that runs `cd <worktree-B> && gh pr merge <N_B>` gets a false **ALLOW** today,
  because A's trailer is in the scanned range. The PR-head range closes that too. And in the same
  scenario the auto-sync block merges `origin/main` into **branch A** and pushes it, which mutates a
  branch that is not being merged.
- **ADR corpus.** ADR-127 (the trailer is a boolean, not a content attestation) is untouched: this
  plan changes *which commits* are scanned, not what the trailer means. ADR-131 (gate moratorium)
  is `status: proposed` and explicitly allows "existing ones may be fixed". Neither ADR rejects
  scanning the PR head.

### Property List (Phase 0.6b)

- **P1.** For `gh pr merge <N>`, the gate's verdict is computed over PR N's own commits
  (`origin/main..<PR N head oid per GitHub>`), whatever directory the session is anchored in.
- **P2.** A PR whose own commits carry no review evidence is still denied, including when the
  session's cwd is a *different* branch that does carry evidence. No new bypass.
- **P3.** When GitHub does not answer for PR N (no single PR number in the command, a `-R`/`--repo`
  flag, `gh` missing or failing, a malformed oid), behaviour is today's: the legacy
  `origin/main..HEAD` range in the session cwd. When GitHub answers but the head commit cannot be
  fetched, the local signals are skipped (Signal 3 only), so P2 still holds. The own-checkout case
  (cwd on the PR's branch, descending from its head) keeps today's range, so review evidence in an
  unpushed commit still counts there. States L/O/P/N in Proposed Solution.
- **P4.** The hook never runs the dirty-tree check, `git merge origin/main`, or `git push` against a
  checkout that is not PR N's own (state O), except in legacy state L.
- **P5.** The deny reason names the range it actually checked and where that range came from, so the
  next false DENY can be diagnosed from the one message an agent sees.

### Cut List (Phase 0.6b)

- **Parse a leading `cd <dir> &&` out of the command** (the issue's alternative 2) → P1 →
  `resolve_command_cwd` already exists (`.claude/hooks/lib/incidents.sh`, used by
  `guardrails.sh` and `context-reviewed-gate.sh`). It is **not** adopted for the gate: it recovers
  the *directory*, not the PR. It misses `pushd`, subshells and `git -C`-less spellings, and even
  the right worktree's local HEAD can carry unpushed commits that GitHub will not merge. The PR head
  oid is what GitHub merges. Cut.
- **Use `headRefName` to fetch `refs/heads/<name>`** → P1 fallback → `refs/pull/<N>/head` already
  covers it. It needs no branch-name interpolation into a git argv, and it also works for fork PRs.
  `headRefName` is kept for **P4** only (the sync-target comparison) and for the diagnostic line.
- **A new shared `lib/pr-head.sh` helper** reused by sibling gates → P1 for other hooks → out of
  scope. The resolver lives inline in this hook, and the sibling sweep is a tracked follow-up (see
  Non-Goals).

### Relevant files (all on `origin/main`)

- `.claude/hooks/pre-merge-rebase.sh`:
  - `WORK_DIR="$HOOK_CWD"`: the defect.
  - Check 1 uses `git log origin/main..HEAD -G'code-review' … -- todos/` **and**
    `git show "HEAD:$_todo"`. That is two range consumers, not one.
  - Check 2 uses the subject log `origin/main..HEAD --oneline` and the trailer log
    `%(trailers:key=Reviewed-By-Soleur,valueonly)`.
  - Check 3 extracts the PR number with `grep -oE 'gh\s+pr\s+merge\s+([0-9]+)' … | head -1`. The
    `head -1` is load-bearing; see its comment about #7409.
  - The `FETCH_OK` discard block. The auto-sync is the uncommitted-changes check, then
    `git merge origin/main`, then `git push origin HEAD`.
- `.claude/hooks/lib/hook-input.sh`: `HOOK_CWD="${_hi_s[3]:-${DEVIN_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}}"`.
  Devin envelopes carry no `.cwd`, so under Devin the hook already anchors at the project root.
  This fix helps there too.
- `.claude/hooks/pre-merge-auto-close-scan.sh` is the **precedent to copy** for the `gh` call:
  `(cd "$WORK_DIR" && timeout "$(gh_budget)" gh pr view "$PR_REF" --json title,body …)`, with no
  `--repo`. Its comment records why: a hand-built `--repo` slug kept `.git` on SSH remotes and
  made that arm dead code for 17 days (#6775). Running `gh` from inside `$WORK_DIR` also makes
  every existing fixture (origin = a local bare path) fail *fast and offline* ("no GitHub remote"),
  instead of resolving against the real `jikig-ai/soleur` from the test runner's cwd.
- `.claude/settings.json`: `pre-merge-rebase.sh` has **no `timeout` key**, so it runs under Claude
  Code's default hook timeout. The research agent reported "10 s", but that value belongs to
  `grep-rewrite.sh`. Every new network call is still bounded with `timeout` (see Sharp Edges).
- Test surfaces that drive this hook (all auto-discovered; no registration edit needed):
  - `.claude/hooks/pre-merge-rebase.test.sh` (bash, the one this plan extends). No `gh` stub today,
    so its `gh issue list` calls reach real `gh` from the runner's cwd.
  - `.claude/hooks/pre-merge-rebase-parity.test.sh`. Its source anchors are the Signal 2 `grep -E`
    call string and `trailers:key=Reviewed-By-Soleur,valueonly`, and both must stay byte-identical.
  - `.claude/hooks/pre-merge-rebase-headless.test.sh`.
  - `test/pre-merge-rebase.test.ts` (bun). Its `gh` stub answers unknown argv with exit 0 and
    empty stdout, so the new `gh pr view` falls back to legacy there. It should gain an explicit
    `pr view` arm (see Files to Edit).
  - `scripts/test-all.sh` globs `.claude/hooks/*.test.sh`. `scripts/suite-shard-legs.tsv` already
    lists all three bash suites.
- `.claude/hooks/stub-argv-fidelity.test.sh` pins `EXPECTED_STUBS=5`. A new heredoc-written `gh`
  stub in `pre-merge-rebase.test.sh` makes it **6**, and the pin must be bumped in the same commit.
  The stub must reference `"$@"`/`$*` and dispatch on it (the stub template in
  `pre-merge-auto-close-scan.test.sh` is the model).
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` holds row `5 .claude/hooks/pre-merge-rebase.sh` (tab-separated)
  and is compared row-by-row. New `git -C "$WORK_DIR" …` operands may move that count. If
  `bash plugins/soleur/test/fixture-relative-assert.test.sh` reddens, regenerate it with
  `--write-baseline` in the same commit, as the file header prescribes.

### Institutional learnings applied

- `2026-03-03-pre-merge-rebase-hook-implementation.md`: git stdout corrupts hook JSON. Every new
  `git`/`gh` call redirects or is captured.
- `2026-04-02-ship-review-evidence-coupling.md`: prefer the explicit PR number from the command;
  the gate fails closed only when every signal is empty.
- `2026-09-20-i-verified-by-reading-and-the-gate-that-mattered-failed-open.md`: an exit 0 on "could
  not evaluate" is fail-open. Here "could not resolve the PR head" deliberately means *legacy
  range*, never *allow*, and a test pins it (T-PR7).
- `2026-05-04-vacuous-red-via-shared-fixture-and-toolchain-pinning.md`: the regression fixture must
  be one only the new branch can satisfy. The root session's HEAD must not contain the trailer, and
  the control must prove the resolver *ran*. A DENY reached through the legacy path proves nothing.
- `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` and #6992 (the `grep -c` note in Check 1): no
  `grep -q` on a producer pipe under `pipefail`.
- The stub-argv-fidelity header (#6775): a `gh` stub that ignores argv hides a malformed invocation.
  Dispatch on the exact argv, and fail with `STUB-MISS` on anything else.
- Open issue #7822 (test fixtures inherit `GIT_DIR` under lefthook): new fixtures reuse the file's
  existing `init_git_repo`/`attach_origin` helpers, which route through `assert_fixture_dir`. Do not
  hand-roll new `git init` calls.

### External research

Skipped. The codebase has direct precedent: the `gh pr view` call shape, the binstub pattern and the
fixture helpers. The two platform facts this plan depends on were verified live instead:
`gh pr view --help` lists `headRefName` and `headRefOid` as JSON fields, and GitHub serves
`refs/pull/<N>/head` (see the `git ls-remote` above).

### Functional overlap

The `soleur:engineering:discovery:functional-discovery` agent found no community artifact that
derives a merge gate's range from the PR head. The nearest ones are approval-gate or
CI-wait workflows. Nothing was installed.

## Research Reconciliation — Issue vs. Codebase

| Issue claim | Reality | Plan response |
|---|---|---|
| The gate scans `git log origin/main..HEAD` in `.cwd` (~line 108) | True. And Check 1 **also** reads `git show "HEAD:$_todo"`, a second `HEAD` consumer the issue does not mention | All four range consumers move to one `EVIDENCE_TIP` variable (Guard 1) |
| The fix is to derive the range from `gh pr view` | Sound. The oid is exactly what GitHub merges, which is stronger than any cwd | Adopted |
| Fetch-ref fallback | GitHub serves `refs/pull/<N>/head` (verified with `ls-remote`), and it works for fork PRs | Fall back to `refs/pull/<N>/head`, never `refs/heads/<headRefName>` |
| The failure is only a false DENY | It is also a false ALLOW (the cwd branch is reviewed and the PR is not), and the auto-sync pushes the **cwd** branch | P2 and P4 cover both |
| The research agent said the hook timeout is 10 s | That value belongs to `grep-rewrite.sh`. `pre-merge-rebase.sh` has no `timeout` key | Every new network call is still bounded with `timeout` |
| Close #8777 | Already CLOSED | Dropped from tasks |

## Problem Statement

`pre-merge-rebase.sh` is the only thing between an agent and `gh pr merge` that asks "did review
run on these commits?". It answers that over whatever `HEAD` the session happens to be anchored on.
A subagent's session is anchored at the repo root (detached HEAD), or at a worktree other than the
PR's, far more often than at the PR's own worktree, and `EnterWorktree` refuses to move a
root-anchored session. So there are three outcomes today:

1. **False DENY.** PR has a trailer, session at root → denied. The operator's two 2026-09-24
   incidents (#8650, #8757). One agent handed the merge back. The other filed a hollow
   code-review issue to satisfy Signal 3, which is a gate workaround that pollutes the review
   record.
2. **False ALLOW.** PR has no evidence, session in another reviewed worktree → allowed.
3. **Wrong-branch mutation.** In case 2, and whenever the cwd branch differs from the PR's, the
   auto-sync runs `git merge origin/main` + `git push origin HEAD` **on the cwd branch**.

## Proposed Solution

Resolve the PR being merged, and evaluate the gate over the commits GitHub will merge. The
resolver ends in exactly one of four states (revised after plan review; the v1 five-state table
had an S3 that two panels independently flagged — see `## Plan Review Revisions`):

| State | Condition | Evidence tip (Signals 1–2 read `origin/main..<tip>`) | Auto-sync |
|---|---|---|---|
| **L** legacy | not exactly one distinct `gh pr merge <digits>` in `$SCAN`, **or** a `-R`/`--repo` flag, **or** `gh pr view` failed / returned no 40-hex `headRefOid` | `HEAD` of the session cwd (today's behaviour) | legacy (today's) |
| **O** own checkout | GitHub answered, `isCrossRepository` is false, cwd branch == `headRefName`, and `headRefOid` is an ancestor of (or equal to) cwd `HEAD` | `HEAD` of the session cwd | runs |
| **P** PR head | GitHub answered, not O, and the oid is local (or becomes local after `git fetch origin refs/pull/<N>/head`) | the oid | skipped, reported via `additionalContext` |
| **N** none | GitHub answered, not O, oid not fetchable | none — Signals 1–2 skipped, only Signal 3 can allow | skipped |

**Why O keeps `HEAD`.** The common flow is "run review in my own worktree, `emit-review-trailer.sh`,
merge" — often before pushing the trailer commit. Scanning only the remote head there would be a
new false DENY that reads as "review never ran", which is exactly what drives agents to the
hollow-issue workaround. Because O requires `HEAD` to *descend from* the PR head, `origin/main..HEAD`
is a superset of the PR's own commits, and every commit the auto-sync then pushes was in the
scanned range. That is today's invariant, unchanged for the own-worktree case.

**Why N is Signal-3-only.** Falling back to the cwd there would re-open the false ALLOW this plan
closes (session in reviewed worktree A merging unreviewed PR B). It reuses the shape the hook
already has for a stale `origin/main` (the `FETCH_OK` discard). L stays legacy: when `gh` cannot
reach GitHub, the `gh pr merge` that follows almost certainly fails too, and legacy is today's
exact behaviour (P3).

**Why `-R`/`--repo` is legacy.** `gh pr view <N>` from the cwd would resolve N against the cwd's repo,
a different PR from the one being merged, and could allow on that PR's evidence.

### Implementation sketch (a guide for `soleur:work`, not final code)

Insert after the `FETCH_OK` fetch and before Check 1 in `.claude/hooks/pre-merge-rebase.sh`:

```bash
# PR-head evidence range (#8778). .cwd is the SESSION anchor, not where an in-command `cd` lands,
# so a root-anchored subagent's `cd <wt> && gh pr merge N` used to scan the root's HEAD.
EVIDENCE_TIP="HEAD"; RANGE_LABEL="origin/main..HEAD"; RANGE_SOURCE="session cwd $WORK_DIR"
PR_HEAD_NUMBER=""; PR_HEAD_OID=""; PR_HEAD_REF=""; OWN_CHECKOUT=0
# $SCAN (quote-stripped), not $CMD: a `gh pr merge <X>` inside a -m "..." body must not choose
# which PR's evidence is read. `|| true` is load-bearing: a no-match grep exits 1 under pipefail
# and would abort the hook (fail-open). grep -c ., not wc -l: `wc -l <<<""` is 1.
_pr_nums=$(grep -oE 'gh\s+pr\s+merge\s+[0-9]+' <<<"$SCAN" | grep -oE '[0-9]+$' | sort -u || true)
_pr_count=$(grep -c . <<<"$_pr_nums" || true)
if [[ "$_pr_count" == "1" ]] && ! grep -qE '(^|\s)(-R|--repo)(\s|=|$)' <<<"$SCAN"; then
  PR_HEAD_NUMBER="$_pr_nums"
  _to=(); if command -v timeout >/dev/null 2>&1; then _to=(timeout 10)
  elif command -v gtimeout >/dev/null 2>&1; then _to=(gtimeout 10); fi
  _pr_json=$(cd "$WORK_DIR" && "${_to[@]}" gh pr view "$PR_HEAD_NUMBER" \
               --json headRefName,headRefOid,isCrossRepository 2>/dev/null) || _pr_json=""
  _oid=$(jq -r '.headRefOid // empty' <<<"$_pr_json" 2>/dev/null || true)
  if [[ "$_oid" =~ ^[0-9a-f]{40}$ ]]; then
    PR_HEAD_OID="$_oid"; PR_HEAD_REF=$(jq -r '.headRefName // empty' <<<"$_pr_json" 2>/dev/null || true)
    _xrepo=$(jq -r '.isCrossRepository // false' <<<"$_pr_json" 2>/dev/null || true)
    git -C "$WORK_DIR" cat-file -e "${_oid}^{commit}" 2>/dev/null \
      || "${_to[@]}" git -C "$WORK_DIR" fetch --no-tags --quiet origin \
           "refs/pull/${PR_HEAD_NUMBER}/head" >/dev/null 2>&1 || true
    if [[ "$_xrepo" != "true" && -n "$PR_HEAD_REF" && "$CURRENT_BRANCH" == "$PR_HEAD_REF" ]] \
       && git -C "$WORK_DIR" merge-base --is-ancestor "$_oid" HEAD 2>/dev/null; then       # O
      OWN_CHECKOUT=1; RANGE_SOURCE="PR #$PR_HEAD_NUMBER's own checkout ($WORK_DIR)"
    elif git -C "$WORK_DIR" cat-file -e "${_oid}^{commit}" 2>/dev/null; then               # P
      EVIDENCE_TIP="$_oid"; RANGE_LABEL="origin/main..${_oid:0:12}"
      RANGE_SOURCE="PR #$PR_HEAD_NUMBER head per GitHub"
    else                                                                                   # N
      EVIDENCE_TIP=""; RANGE_LABEL="none"
      RANGE_SOURCE="PR #$PR_HEAD_NUMBER head ${_oid:0:12} not fetchable; run: git fetch origin pull/$PR_HEAD_NUMBER/head"
    fi
  else                                                                                     # L
    RANGE_SOURCE+="; PR #$PR_HEAD_NUMBER head not resolved (gh pr view failed) — fix gh auth or run from the PR's worktree"
  fi
fi
```

Then:

- Checks 1 and 2 run **only when `EVIDENCE_TIP` is non-empty**. Never hand git an empty tip:
  `origin/main..` means `origin/main..HEAD`, which is N's false ALLOW re-entering through the back
  door. All four reads use `"origin/main..$EVIDENCE_TIP"` / `"$EVIDENCE_TIP:$_todo"`.
- The Signal 2 `grep -E "…"` call string and `trailers:key=Reviewed-By-Soleur,valueonly` stay
  **byte-identical** (`pre-merge-rebase-parity.test.sh` anchors on both).
- Check 3: one extraction. `PR_NUMBER` = the single distinct number from `$SCAN` (`_pr_nums` when
  `_pr_count == 1`); zero numbers → the existing branch-based `gh pr list` fallback; two or more
  distinct numbers → Signal 3 is skipped (it cannot attribute an issue to one PR). The old `$CMD`
  `head -1` extraction and its comment are removed. The #7409 locked/unlocked arms repeat the SAME
  number, which `sort -u` collapses to one.
- Deny reason: `"BLOCKED: No review evidence for commits in <RANGE_LABEL> (<RANGE_SOURCE>). …"`
  via `jq --arg`, keeping the `BLOCKED: No review evidence` prefix and the rest of today's text,
  plus one sentence: "A code-review issue filed only to satisfy this gate is not review."
- After the detached-HEAD exit, the P4 skip — keyed on `PR_HEAD_OID` set and `OWN_CHECKOUT=0`:

```bash
if [[ -n "$PR_HEAD_OID" && "$OWN_CHECKOUT" != "1" ]]; then
  jq -n --arg m "Pre-merge hook: $WORK_DIR ($CURRENT_BRANCH) is not PR #$PR_HEAD_NUMBER's checkout ($PR_HEAD_REF @ ${PR_HEAD_OID:0:12}); skipped the uncommitted-changes check and the origin/main auto-sync. GitHub will merge the PR head as pushed." \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
  exit 0
fi
```

- Update the file header and the `Determine working directory` comment so they state what `.cwd`
  is (the session anchor) and that the evidence range now comes from the PR.

## Implementation Phases

### Phase 0 — Tests first (RED)

Extend `.claude/hooks/pre-merge-rebase.test.sh` with the cases in **Test Scenarios** and the `gh`
binstub before touching the hook (`cq-write-failing-tests-before`). New cases follow the file's
existing per-function `mktemp -d` + `RETURN` trap shape (the tempfile-ownership lint already
accepts `RETURN` traps). `unset GH_REPO GH_HOST` in the suite preamble so no case — old or new — can
reach the real API. Run on the unmodified hook and record which cases fail and why. Expected RED:
T-PR1/1b/1c, T-PR2, T-PR3, T-PR4, T-PR8, T-PR10, T-PR11.

### Phase 1 — Resolver and range (Guard 1)

The resolver block, `EVIDENCE_TIP` in the four reads under one non-empty guard, the single
PR-number extraction for Signal 3, the deny text.

### Phase 2 — Sync targeting (Guard 2)

The P4 skip after the detached-HEAD exit.

### Phase 3 — Meta-guards

- `.claude/hooks/stub-argv-fidelity.test.sh`: `EXPECTED_STUBS` 5 → 6.
- `bash plugins/soleur/test/fixture-relative-assert.test.sh`; regenerate with `--write-baseline`
  only if it reddens, in the same commit, stating old/new counts.
- Run every hook-driving suite (AC10).

### Phase 4 — Mutation spot-check

Apply each Guard Contract mutation-matrix row once to the hook, confirm its named test goes RED, restore
with `git checkout -- <file>`. Record the result list in the PR body.

## Non-Goals (tracked, not silently dropped)

- **The `main`/`master` early exit still skips the gate** whenever the session cwd is on `main`.
  That is the same cwd-dependence in the fail-open direction. It is not folded in because the
  `soleur:schedule` workflow template runs `gh pr merge --squash --auto "$PR_URL"` under
  claude-code-action on a `main` checkout, so gating there would newly deny scheduled bot PRs that
  carry no review evidence. That needs its own decision. Tracked in the follow-up issue filed by
  this plan (see `## Deferred Follow-ups`).
- **Other PR-ref spellings** (a URL, a branch name, flags before the number, a bare `gh pr merge`)
  keep the legacy cwd range. The URL form is the one scheduled workflows use, which ties it to the
  item above.
- **Sibling gates with the same cwd dependence:**
  - `cla-signed-author-gate.sh` scans `origin/main..HEAD` in `HOOK_CWD`, which is a false ALLOW
    from a root session.
  - `ship-unpushed-commits-gate.sh` keys on the cwd branch.
  - `pre-merge-auto-close-scan.sh` has a commit-body arm that scans cwd commits (its PR title/body
    arm already uses `gh pr view <N>`).

  A shared `lib/pr-head.sh` resolver is the natural extraction once a second consumer exists.
  Tracked in a follow-up issue.
- **TOCTOU between the check and the merge.** A push after the hook runs changes what GitHub
  merges. This is pre-existing and unchanged. `gh pr merge --match-head-commit <oid>` is the known
  remedy and is out of scope.

## Technical Considerations

- **Trust.** `headRefOid` comes from the GitHub API over the authenticated `gh`: the commit GitHub
  will merge. It is validated as a 40-hex oid before it reaches any `git` argv. `headRefName` never
  reaches a `git` argv — string comparison and log text only.
- **Offline and test safety.** `gh` runs from inside `$WORK_DIR` with no `--repo`
  (`pre-merge-auto-close-scan.sh` precedent, #6775). In fixtures whose origin is a local bare path it
  fails fast (no GitHub remote) → L → today's verdicts. That holds only while `GH_REPO`/`GH_HOST`
  are unset, so the suite unsets them.
- **Which repo `gh` resolves.** With several remotes, `gh` may pick one other than `origin`; the oid
  then looks unfetchable → N (Signal 3 only). A clone of a fork has no `refs/pull/*` on origin → N.
  Both degrade toward "Signal 3 only", never toward allow.
- **Latency / fail-open.** One `gh pr view` per `gh pr merge <N>` (~1 s), bounded at 10 s with the
  `timeout` → `gtimeout` → unbounded array from `git-commit-secret-scan.sh` (no bare `timeout`:
  stock macOS has none, it would exit 127 and pin every Mac in L). One pull-ref fetch, same bound,
  only when the oid is not local — never from a worktree of this repo, which shares the object
  store. A PreToolUse hook killed by the harness timeout lets the tool proceed; this adds at most
  20 s of bounded network time to calls (`git fetch origin main`, `git push`, Signal 3's `gh`) that
  are already unbounded. Not widened here.
- **An empty tip is not "no range".** `git log origin/main..` means `origin/main..HEAD`. N must skip
  the reads, never pass `""` through.

## User-Brand Impact

- **If this lands broken, the user experiences:** the operator's agent merges stall. A wrong
  resolver denies reviewed PRs, which is today's bug made universal. Or a wrong fallback lets an
  unreviewed PR through the only pre-merge review gate. Neither reaches a Soleur end user directly:
  the hook is repo-local and is not in the shipped plugin (`plugins/soleur/`).
- **If this leaks, the user's workflow is exposed via:** an unreviewed change reaching `main` of
  this repo. It would still be bounded by the required CI checks and branch protection. No user
  data, credentials or money move through this path.
- **Brand-survival threshold:** `none`

*Scope-out override:* `threshold: none, reason: .claude/hooks/ is repo-local operator tooling that
is never shipped to plugin installs, and no path in this diff matches the preflight sensitive-path
regex.`

## Observability

```yaml
liveness_signal:
  what: "the hook's own verdict on every intercepted gh pr merge — a deny row in .claude/.rule-incidents.jsonl (rule rf-never-skip-qa-review-before-merging)"
  cadence: "per gh pr merge invocation"
  alert_target: "the invoking agent (permissionDecisionReason, which now names the range and its source) and the weekly rule-metrics aggregate over .claude/.rule-incidents.jsonl"
  configured_in: ".claude/hooks/pre-merge-rebase.sh (emit_incident + headless_or_stderr), .claude/settings.json PreToolUse Bash registration"

error_reporting:
  destination: "hook stderr, or under claude --bg the per-PPID headless log at $GIT_COMMON_DIR/soleur-session-state/logs/ via headless_or_stderr; deny rows to .claude/.rule-incidents.jsonl"
  fail_loud: "permissionDecisionReason 'BLOCKED: No review evidence for commits in origin/main..<tip> (<source>)' — the source names 'PR #N head per GitHub' or the reason the PR head was not resolved"

failure_modes:
  - mode: "gh pr view fails or times out (network, auth, gh absent)"
    detection: "deny reason source '…; PR #N head not resolved (gh pr view failed)'"
    alert_route: "the invoking agent reads it in the deny reason"
  - mode: "PR head oid not fetchable (pull ref fetch fails)"
    detection: "N-state source 'PR #N head <oid12> not fetchable; run: git fetch origin pull/N/head' in the deny reason"
    alert_route: "the invoking agent"
  - mode: "auto-sync skipped because the checkout is not the PR head"
    detection: "additionalContext 'Pre-merge hook: <dir> (<branch>) is not PR #N's checkout …; skipped … auto-sync.'"
    alert_route: "headless log / stderr"

logs:
  where: "stderr of the hook, or $GIT_COMMON_DIR/soleur-session-state/logs/$PPID.log under claude --bg; .claude/.rule-incidents.jsonl for deny rows"
  retention: "incident ledger rotated by .claude/hooks/lib/log-rotation.sh; headless logs follow session-state log rotation"

discoverability_test:
  command: "grep -o -m1 -F 'RANGE_SOURCE' .claude/hooks/pre-merge-rebase.sh"
  expected_output: "RANGE_SOURCE"
```

## Guard Contract

### Guard 1 — PR-scoped review-evidence range

**Property.** For a merge command carrying exactly one distinct `gh pr merge <N>` and no
`-R`/`--repo`, when GitHub reports PR N's head oid, Signals 1–2 read the session cwd's `HEAD` only
when that checkout is PR N's own branch *and descends from its head* (O); otherwise they read
`origin/main..<oid>` (P), or nothing when the oid cannot be fetched (N). When GitHub does not
answer (L), the reads are today's `origin/main..HEAD` in the session cwd.

**Assembly.** The chokepoint is the single variable `EVIDENCE_TIP`, assigned only inside the
resolver. Exactly four evidence reads consume it, all inside one `[[ -n "$EVIDENCE_TIP" ]]` guard:
Check 1's `git log … -- todos/` producer and its `git show "$EVIDENCE_TIP:$_todo"` blob read; Check
2's subject log and trailer log. Signal 3 reads the PR number from the same `_pr_nums` extraction.
After the change, `grep -nE 'origin/main\.\.HEAD|"HEAD:' .claude/hooks/pre-merge-rebase.sh` matches
no evidence read (comments and the sync's own `merge-base HEAD origin/main` may remain).

**Mutation matrix:**

| # | Mutation | Expected RED |
|---|---|---|
| 1 | Revert the trailer log (read 4) to `origin/main..HEAD` | T-PR1 |
| 2 | Revert only the Check 1 blob read to `HEAD:$_todo` (second read after a compliant first) | T-PR1c |
| 3 | Union: accept evidence from cwd `HEAD` **or** the PR range | T-PR3 |
| 4 | Drop the `refs/pull/<N>/head` fetch | T-PR2 |
| 5 | Drop the hex-oid validation | T-PR6 |
| 6 | `head -1` of the numbers instead of the distinct-count check | T-PR9 |
| 7 | Extract from `$CMD` instead of `$SCAN` | T-PR10 |
| 8 | N leaves the reads unguarded (git gets `origin/main..`) | T-PR11 |
| 9 | Drop the `-R`/`--repo` check | T-PR12 |

### Guard 2 — Auto-sync targets only the PR's own checkout

**Property.** The uncommitted-changes check, `git merge origin/main` and `git push origin HEAD` run
only in L (today's behaviour) or O. In P and N the hook exits 0 with `additionalContext` naming the
skip. So the hook never mutates or pushes a branch other than the PR's, and every commit it pushes
was in the scanned range.

**Assembly.** One skip, keyed on `PR_HEAD_OID` set and `OWN_CHECKOUT != 1`, after the detached-HEAD
exit and before the uncommitted-changes block — before the first branch-moving write.

**Mutation matrix:**

| # | Mutation | Expected RED |
|---|---|---|
| 1 | Delete the P4 skip | T-PR4 |
| 2 | O on branch name alone (drop `--is-ancestor`) | T-PR8 |
| 3 | Drop O (always P once GitHub answers) | T-PR5b |
| 4 | Move the P4 skip after the uncommitted-changes block | T-PR4 |

The `gh` stub dispatches on meaning (subcommand `pr view`, the PR number, a `--json` value holding
`headRefName`, `headRefOid` and `isCrossRepository`); T-PR1 alone asserts the exact argv line in
`gh.log`, which also catches a stub that ignores `<N>`.

## Architecture Decision (ADR/C4)

The gate does not fire. This is a bug fix on an existing surface. No ownership, tenancy or trust
boundary moves. The hook already called the GitHub API before this change (Signal 3's
`gh issue list` and the `gh pr list` fallback), so no new external system or edge is introduced.
ADR-127's decision (the trailer is a boolean, not a content attestation) is unchanged: this changes
which commits are scanned, not what the trailer asserts. The Hook Engine container
(`model.c4`, `hooks = container "Hook Engine"`) describes hook classes, not per-gate ranges, so
none of its text is falsified.

## Acceptance Criteria

- [ ] **AC1 (P1).** T-PR1, T-PR1b, T-PR1c: from a detached-HEAD root session whose
  `origin/main..HEAD` is empty, `cd <wt> && gh pr merge 4242 --squash` is **not denied** when PR
  4242's head carries only a trailer / only a `review(x): …` subject / only a `code-review` todo.
  `gh.log` contains `pr view 4242 --json headRefName,headRefOid,isCrossRepository`.
- [ ] **AC2 (P1 control).** T-PR-C: same layout, no evidence → denied with rule
  `rf-never-skip-qa-review-before-merging`; the reason contains `PR #4242 head per GitHub` (proves
  the resolver ran — a legacy DENY would not carry it).
- [ ] **AC3 (fetch).** T-PR2 allows from a `--no-local --single-branch` clone where the head exists
  only at origin's `refs/pull/4242/head`; a precondition asserts the oid is absent before the hook.
- [ ] **AC4 (P2).** T-PR3 (P) and T-PR11 (N) deny when the cwd branch has a trailer and the PR head
  has none / cannot be fetched; T-PR11's reason contains `not fetchable`.
- [ ] **AC5 (P3).** T-PR6 (non-hex oid) and T-PR7 (`gh` fails) take the legacy range: T-PR6 from the
  root denies with `not resolved`; T-PR7 from a reviewed cwd branch allows. Every pre-existing case in
  `pre-merge-rebase.test.sh`, `pre-merge-rebase-parity.test.sh`, `pre-merge-rebase-headless.test.sh`
  and `test/pre-merge-rebase.test.ts` keeps its verdict.
- [ ] **AC6 (extraction).** T-PR9 (two distinct numbers → no `pr view` in `gh.log`, deny from root),
  T-PR10 (a number inside a quoted body is ignored; `gh.log` shows `pr view 4243` only), T-PR12
  (`-R other/repo` → no `pr view` in `gh.log`).
- [ ] **AC7 (P4).** T-PR4: the unrelated, dirty, behind cwd branch keeps its HEAD and
  `origin/feat-a`, is not denied for its dirty tree, and `additionalContext` names the skip. T-PR8:
  cwd on the PR's branch but not descending from its head, with `origin/main` ahead → `origin/feat-x`
  unchanged. T-PR5 / T-PR5b: own checkout at / ahead of the head (unpushed trailer commit), with
  `origin/main` ahead → allowed and `merged origin/main into feat-x and pushed` appears.
- [ ] **AC8 (P5).** Every review-evidence deny names its range (`origin/main..<tip>` or `none`) and
  source, and still begins `BLOCKED: No review evidence`.
- [ ] **AC9 (mutation).** Every Guard Contract mutation-matrix row turned its named test RED; the PR body lists
  the results.
- [ ] **AC10 (commands).** All exit 0:
  - `bash .claude/hooks/pre-merge-rebase.test.sh`
  - `bash .claude/hooks/pre-merge-rebase-parity.test.sh`
  - `bash .claude/hooks/pre-merge-rebase-headless.test.sh`
  - `bun test test/pre-merge-rebase.test.ts`
  - `bash .claude/hooks/stub-argv-fidelity.test.sh`
  - `bash plugins/soleur/test/fixture-relative-assert.test.sh`
  - `python3 scripts/lint-trap-tempfile-ownership.py --changed`
  - `shellcheck .claude/hooks/pre-merge-rebase.sh .claude/hooks/pre-merge-rebase.test.sh`
- [ ] **AC11.** PR body uses `Closes #8778` and links the follow-up issues.

## Test Scenarios

New functions in `.claude/hooks/pre-merge-rebase.test.sh`, reusing `init_git_repo`,
`attach_origin`, `make_payload`, `assert_deny`, plus one `install_gh_stub <stubdir> [mode]` helper.
Per-PR answers are fixture files `<stubdir>/pr-<N>.json` written with `jq -nc`. The heredoc-written
stub references `"$@"`, appends `"$*"` to `gh.log`, and replays real `gh` (measured 2026-09-24):
`pr view <N> --json …` with `pr-<N>.json` present → one compact JSON line, rc 0; absent → rc 1 and
`GraphQL: Could not resolve to a PullRequest with the number of <N>. (repository.pullRequest)` on
stderr; `fail` mode → rc 1, `HTTP 502`; `issue list` / `pr list` → empty, rc 0; anything else →
`STUB-MISS`, rc 64.

Layout: a bare origin, a root checkout left in **detached HEAD** at `main` (the live layout), and
`git worktree add` worktrees sharing its object store. PR numbers 4242–4247 and every "unfetchable"
oid are synthetic; an unfetchable oid is asserted absent with `git cat-file -e` first. Every case
that asserts "no sync" first advances `origin/main` past the branch and asserts that precondition —
otherwise the hook's "already up-to-date" exit makes the assertion vacuous.

- **T-PR1 / 1b / 1c (P):** root session; PR 4242's head carries only a `Reviewed-By-Soleur` trailer
  under a neutral subject / only a `review(8778): findings (P2)` subject / only a `todos/x.md`
  containing `code-review` → allowed. Precondition: `git -C root log origin/main..HEAD` is empty.
  One parametrized helper.
- **T-PR-C (control):** as T-PR1 with no evidence → DENY + `PR #4242 head per GitHub`.
- **T-PR2 (P via fetch):** `git clone -q --no-local --single-branch --branch main` session dir; the
  head published only at origin's `refs/pull/4242/head` → allowed.
- **T-PR3 (P):** cwd worktree `feat-a` with a trailer; PR 4243 = `feat-b` without → DENY.
- **T-PR4 (P4):** cwd `feat-a` dirty and behind `origin/main`; PR 4244 = reviewed `feat-b` → not
  denied; `feat-a` HEAD and `origin/feat-a` unchanged; `additionalContext` names the skip.
- **T-PR5 (O):** cwd is PR 4242's worktree at `headRefOid`, reviewed, `origin/main` ahead → sync runs.
- **T-PR5b (O, unpushed trailer):** as T-PR5, but the trailer commit is local only (HEAD one commit
  ahead of `headRefOid`) → allowed, sync runs, `origin/feat-x` now contains the trailer commit.
- **T-PR6 (L):** stub returns `headRefOid: "feat-a"` (a reviewed local branch) from the root → DENY
  with `not resolved`.
- **T-PR7 (L):** stub in `fail` mode, cwd a reviewed branch → allowed (legacy).
- **T-PR8 (P, not own):** cwd `feat-x` == `headRefName`, but HEAD does not descend from the reviewed
  `headRefOid` (diverged local commit, unreviewed); `origin/main` ahead → allowed on the PR head's
  evidence; `origin/feat-x` unchanged; skip context present.
- **T-PR9:** `gh pr merge 4242 --squash && gh pr merge 4243 --squash` from root; 4242 reviewed, 4243
  not → DENY; no `pr view` in `gh.log`.
- **T-PR10:** `git commit --allow-empty -m "see gh pr merge 4242" && gh pr merge 4243 --squash` from
  root; stub serves 4243 unreviewed, 4242 reviewed → DENY; `gh.log` has `pr view 4243`, never 4242.
- **T-PR11 (N):** cwd `feat-a` with a trailer; PR 4245 answers `headRefName: feat-b` with an
  unfetchable oid → DENY, reason contains `not fetchable`.
- **T-PR12 (-R):** `gh pr merge 4242 -R other/repo --squash` from a reviewed cwd branch → allowed on
  the legacy range; no `pr view` in `gh.log`.

Each case runs the hook as `printf '%s' "$payload" | PATH="$stubdir:$PATH" "$HOOK"` with a fresh
stub dir per case; the suite already sources `lib/test-incident-sandbox.sh`.

## Open Code-Review Overlap

None. Checked `.claude/hooks/pre-merge-rebase.sh`, `pre-merge-rebase.test.sh`,
`stub-argv-fidelity.test.sh`, `test/pre-merge-rebase.test.ts` and
`fixture-relative-assert.baseline.txt` against all 78 open `code-review` issues. None names them.

Related but not code-review-labelled, and acknowledged rather than folded in:

- **#8616:** the `command -v jq … SKIP … exit 0` at the top of this suite reports "could not
  measure" as green. That is a separate cross-suite concern.
- **#7822:** fixtures inheriting `GIT_DIR` under lefthook. The new cases use the file's existing
  `assert_fixture_dir`-guarded helpers.

## Files to Edit

- `.claude/hooks/pre-merge-rebase.sh`: the resolver, `EVIDENCE_TIP` in the four reads, the single
  PR-number extraction for Signal 3, the deny text, the P4 skip, header comments.
- `.claude/hooks/pre-merge-rebase.test.sh`: `unset GH_REPO GH_HOST`, the `gh` stub helper, the
  cases above.
- `.claude/hooks/stub-argv-fidelity.test.sh`: `EXPECTED_STUBS` 5 → 6.
- `plugins/soleur/test/fixture-relative-assert.baseline.txt`: only if its checker reddens
  (regenerated, never hand-edited).

## Files to Create

None.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected. This is an infrastructure/tooling change: a repo-local
PreToolUse hook and its tests. No user-facing surface, legal, marketing, sales, finance, support
or operations impact. The mechanical UI-surface override does not fire, because no file in the lists
above matches a UI-surface path.

## Dependencies & Risks

- **Risk: the resolver denies reviewed PRs universally** (for example, a `gh` JSON shape
  mismatch). Mitigated by P3: every resolver failure keeps the legacy range. T-PR1 pins the happy
  path against the exact argv.
- **Risk: an agent learns to "break `gh`" to get the legacy range.** Legacy is today's behaviour.
  From a root session it denies, and from the PR's own worktree it is the correct range anyway. No
  new bypass.
- **Risk: the extra network latency on every merge.** Bounded (10 s and 20 s), and zero fetches
  from any worktree of this repo.

## Deferred Follow-ups

Filed by this PR: #8790 (CLA gate) and #8791 (residual tracker).

- **`cla-signed-author-gate.sh` scans the session cwd** — a false ALLOW from a root-anchored session
  on a compliance gate. Its own issue.
- **Sibling cwd-scoped PR checks:** `ship-unpushed-commits-gate.sh`, the commit-body arm of
  `pre-merge-auto-close-scan.sh` (plus its bare `timeout`, exit 127 on stock macOS); a shared
  `lib/pr-head.sh` once a second consumer exists.
- **`pre-merge-rebase.sh` residual scope:** the `main`/`master` early exit (fail-open for
  main-anchored sessions; the `soleur:schedule` template merges from `main`), unparsed PR-ref
  spellings (URL, branch, flags-first, bare), and suggesting `gh pr merge --match-head-commit <oid>`
  on ALLOW to close the check-then-merge race.

## Code Review Revisions (2026-09-24)

A ten-seat review of e4f48abdf0 found the resolver's INPUT narrower than its property. All fixed in
2ebaa49385 unless listed as tracked:

- **Target binding (security P1).** The number was the first digits after ANY `gh pr merge` text, so a
  donor PR's evidence could approve a different merge (echo, comment, `||` arm, quoted or suffixed
  number, or a MERGED PR whose squashed head never reaches main). Now every real invocation is parsed
  with the detector's anchor in both `$SCAN` and `$CMD`; the resolver runs only when all name the same
  bare number. State L carries the reason.
- **Repository retargeting (security P1).** `-Rx`, `-sdR x`, `GH_REPO`/`GH_HOST` and a `cd` into a
  checkout whose origin differs now force L; a `-R` elsewhere in the command no longer does.
- **Not-OPEN and fork PRs** read no local signals (Signal 3 only): a merged donor's head, or a fork
  author's self-written trailer, is not this merge's evidence.
- **Messages (agent-native).** The deny names the range actually read, a failed origin/main fetch, and
  the PR's checkout to run the trailer script in; the sync-skip notice now precedes the detached-HEAD
  exit and distinguishes a stale own branch.
- **Tests.** Donor, override, repeated-number (#7409), stacked-branch, fork, not-OPEN, cd, behind and
  Signal 3 cases; a call-site case floor + `_verdict` self-test (promoted in guard-vacuity-floor).
- **Tracked in #8791, not fixed here:** the main/master early exit; a PR stacked on another branch is
  measured against `origin/main`, not its base; detector spellings that never reach the gate (env
  prefix, `if`/`else` arms, pipes, `bash -c`); an `upstream`-vs-`origin` remote layout; state O on an
  up-to-date branch leaving a local-only trailer unpushed (relies on `ship-unpushed-commits-gate.sh`).

## Plan Review Revisions

Plan-review panel (DHH, Kieran, code-simplicity, CTO devex) on 2026-09-24. All Mechanical, applied:

- **S3 cut** (DHH, simplicity, CTO — both panels): replaced by state O. v1's S3 read an unscanned,
  possibly-behind local branch; v1's S2 would have newly denied the own-worktree unpushed-trailer
  flow (CTO, Kieran). O ("on the PR's branch and descending from its head → today's range and sync")
  fixes both and removes v1's `HEAD == headRefOid` sync conjunct.
- **One PR-number extraction** from `$SCAN` for Signal 3; multi-number skips Signal 3 (DHH, Kieran).
- **`-R`/`--repo` → legacy** (Kieran); `isCrossRepository` in `--json` (Kieran).
- **Cut:** the `_bounded` helper (inline array instead), T-PR13's reduced-PATH fixture, the
  `SUITE_TMP` restructure (its premise was false — the lint accepts `RETURN` traps), the highwater
  change, the ts stub arm (its catch-all already routes to L), the 64-hex arm, the 15+5+3 mutation
  ceremony (→ 12 rows), T-PR7a.
- **Fixture fixes** (Kieran): `--no-local` clone for T-PR2; `origin/main` ahead as a precondition
  for every "no sync" assertion; `unset GH_REPO GH_HOST`.
- **DX** (CTO): the P4 skip is reported via `additionalContext`, not stderr; the deny reason names
  the next action and that a hollow code-review issue is not review.
- **Correction:** v1 said `ship-unpushed-commits-gate.sh` "warns"; it denies.

## Sharp Edges

- `wc -l <<<""` prints `1`. Count distinct PR numbers with `grep -c .`.
- `git -C "" …` operates on the caller's cwd. The resolver runs after the existing
  `[[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] && exit 0` guard; keep it below that line.
- Under `set -eo pipefail`, a failing `$(…)` assignment aborts the hook (fail-open). Every new
  substitution carries `|| var=""` or `|| true`.
- Keep the Signal 2 `grep -E` call and `trailers:key=Reviewed-By-Soleur,valueonly` byte-identical.
- Never pass an empty `EVIDENCE_TIP` to git.
- No bare `timeout`.
- The fixture must be one only the new code can satisfy: the root's own `origin/main..HEAD` must be
  empty, or T-PR1 passes on the old hook.
- A "no sync happened" assertion is vacuous unless `origin/main` is ahead of the branch.
- A local-path `git clone` hardlinks the whole object store; use `--no-local` when a test needs an
  object to be absent.
