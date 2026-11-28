---
title: "fix(ship): merge-poll stderr isolation, absent required check, locked arm form vs kb-archive gate"
date: 2026-11-28
slug: fix-ship-poll-stderr-missing-check-kb-gate
branch: feat-one-shot-ship-poll-stderr-missing-check-kb-gate
issue: 12697
closes: [12697, 12963]
type: fix
priority: p2-medium
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix(ship): merge-poll stderr isolation, absent required check, locked arm form vs kb-archive gate

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). No `spec.md` exists for this branch; the one-shot path skipped brainstorm.

Three defects in the ship merge path surfaced while landing the Scope Grants phone-width e2e PR (#13017).
First, the Phase 7 merge poll folds `gh` stderr into the PR state string, so a stderr hint from a newer
`gh` corrupts every state comparison. Second, a required check whose only run was cancelled at the PR
head left the poll waiting with no signal. Third, the locked auto-merge arm block that the skills
document is refused by the KB-archive merge gate. This plan fixes all three and records one learning.

## Research Insights

### Premise Validation

- **"All fixes live under plugins/soleur/skills/ship" does not hold.** `pr-merge-poll.ts` is
  `plugins/soleur/lib/pr-merge-poll.ts`; the gate is `.claude/hooks/ship-kb-archive-gate.sh` (test:
  `.claude/hooks/ship-kb-archive-gate.test.sh`); `review-evidence-comment.md` is
  `plugins/soleur/skills/review/references/review-evidence-comment.md`. The Phase 7 fence's own header
  requires its mirror in `plugins/soleur/skills/merge-pr/SKILL.md` §5.2 and the fixture
  `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` to move with it. All paths confirmed with
  `git ls-files`.
- **Defect 1 reproduced live (gh 2.106.0, 2026-11-25).** `gh pr view 13112 --json state,mergeStateStatus
  --jq ...` exits 0, prints `OPEN BLOCKED` on stdout and a 9-line `hint: ... gh event listen --resource
  .../pull/13112 ...` block on stderr. Under `2>&1` the hint lands **before** the answer, so the captured
  string starts with `hint:` and `[[ "$s" == "OPEN BLOCKED" ]]` is false. `gh run view` of a PR-associated
  run prints a hint too; `gh pr checks`, `gh issue view`, `gh pr list` and `gh api` print none. `gh help
  environment` lists no switch that silences it, and `GH_NO_HINTS=1` has no effect.
- **What the hint breaks in the fence.** The terminal test `grep -qE "^(MERGED|CLOSED|fetch-error)"` is
  line-wise and still fires. Every OPEN arm is dead: `$s == OPEN*` is false, so the every-5th-tick
  `--queue-state` read never runs (no dequeue detection, `rs_v` never set); `== "OPEN BEHIND"` is false,
  so BEHIND auto-sync never fires; `== "OPEN BLOCKED"` is false, so the #11544 required-set dwell never
  counts. `isTerminalPollState()` in `pr-merge-poll.ts` anchors `^(MERGED|CLOSED)\b` on the trimmed
  string, so a hint prefix makes it false as well.
- **The same capture in `sync-pr-behind.sh` standalone mode** (`head_ref` read near the
  "Standalone: the PR number must name THIS branch" comment, and both `state_line` reads in the attempt
  loop): with the hint, `head_ref` is multi-line, so the standalone sync exits 12 `kind=wrong_branch`.
  That standalone command is the manual recovery the fence prints on `[ship.phase7.behind_no_sync]`. The
  `--step --fence` path the fence calls reads state through `qw_snapshot`, which already sends stderr to
  a temp file.
- **Other `2>&1` captures of hint-printing calls:** `.claude/hooks/ship-operator-step-gate.sh`
  (`cur=$(parked_gh pr view --json number --jq .number 2>&1)`) misreads the answer and falls to its
  fail-closed `parked_any_hold`, a spurious hold only while some PR carries `parked`. The ship post-merge
  run polls (`r=$(gh run view <id> ...` and `r=$(gh run list --workflow ...`) and `schedule/SKILL.md`'s
  `gh run view` poll break line-wise on `^completed`, and they watch push/dispatch runs on `main` that
  carry no PR, so they print no hint.
- **Defect 2: the incident.** PR #13017 head `80805cb2d7`: `cla-evidence` run 45624818815 attempt 1
  (`pull_request_target`) was cancelled 20 s after it started (13:33Z 2026-11-25). The workflow's
  concurrency group `cla-evidence-<PR#>` (`cancel-in-progress: false`) is shared with its
  `issue_comment` trigger, so a newer queued run in the group replaces a pending one. Attempt 2, a manual
  rerun, passed at 14:16Z, and the PR merged at 15:19Z. Same class as
  `2026-10-28-a-green-verdict-and-an-armed-auto-merge-do-not-prove-a-required-context-exists.md`.
- **Defect 2 already has an arm.** `ci-head-verdict.sh required` (#11542) names this exact class in its
  header ("a context owned by another workflow that never reported (its pull_request_target run was
  cancelled during a push) is invisible"). It prints `SOLEUR_CI_REQUIRED_SET state=absent` and `RECOVERY
  rerun run=<id> basis=workflow|candidate` hints. The fence's #11544 required-set read runs it through
  `scripts/required-set-report.sh` once the PR has been OPEN BLOCKED, armed, not queued and full-decided
  for 10 ticks, and exits `[ship.phase7.required_set] state=absent`. Under defect 1 none of those
  predicates can be true, so the arm can never fire. The brief's "poll waited forever" matches defect 1
  disabling the existing arm. It does not show that the arm is missing.
- **Defect 3, measured** by driving `.claude/hooks/ship-kb-archive-gate.sh` with PreToolUse JSON from
  this worktree:

  | Command | Verdict |
  |---|---|
  | `gh pr merge 13112 --squash --auto` | allowed |
  | `gh pr merge --squash --auto --match-head-commit <40-hex>` | allowed |
  | `bash "$SS_LIB" with_lock merge-main 600 -- gh pr merge --squash --auto --match-head-commit <40-hex>` | allowed |
  | `... gh pr merge 13112 --squash --auto --match-head-commit <40-hex>` (with or without the lock) | denied: extra operands alongside --match-head-commit |
  | `gh pr merge 13112 ... --match-head-commit "${H:?run the arm check in this call}"` | denied: a --match-head-commit flag names no 40-hex sha |
  | the documented arm check plus lock block, verbatim (ship, merge-pr, product-roadmap) | denied: more than one gh pr merge invocation in one command |

  The `--` passthrough already works. The brief's attribution ("rejects `with_lock … --` as extra
  operands") is off: the PR number beside `--match-head-commit` is what draws that deny. The documented
  block also fails twice more, on the variable SHA and on the second invocation in its lock/degrade-open
  `if/else`. Every other merge hook (pre-merge-rebase, operator-step, unpushed-commits, auto-close-scan,
  cla, net-issue-flow, soak, cmo, runbook-ssh) accepts the block. pre-merge-rebase's deny on this WIP
  branch is a legitimate "no review evidence" one.
- **Existing tracking:** #12697 (P2, open) and #12963 (P3, open) describe defect 3 exactly, with the same
  two candidate shapes. #12697 recommends the hook-side shape. This plan closes both.
- **Collision pre-check** (`collision-precheck.sh 12697` / `12963`): no open PR names either issue. One
  foreign process hit: a `test-all.sh` run owned by the unrelated `feat-12524-agent-liveness-monitoring`
  worktree. It is not a duplicate of this work.

### Property List

1. P1: whatever `gh` writes on stderr cannot change the state string any poll arm or gate compares
   (fence, mirror, standalone sync, operator-step gate, TS spec).
2. P2: when a `gh` read fails, the poll still names the failure (`fetch-error: <reason>`). Stderr text is
   used only on the failure path.
3. P3: a ready, armed PR held BLOCKED by a required context that has no passing run at the head ends the
   poll with a named marker and a recovery pointer, in bounded time. It never waits out the cap in silence.
4. P4: the arm form every skill documents (arm check, then the locked or degraded `gh pr merge <N>
   --squash --auto --match-head-commit "${H:?...}"`, all in one Bash call), and the admin hatch's
   `gh pr merge <N> --squash --admin --match-head-commit "$SHA"` named in #12697, pass the KB-archive
   gate when the KB is archived. The gate still censuses the head that will land.
5. P5: the gate keeps denying every shape it denies today that is not P4's shape: two different
   invocations, two SHAs, a variable PR number, xargs, global flags, a foreign repo, unresolved `cd`.
6. P6: each defect has a test that fails on today's code and passes after the fix. P4's test feeds the
   documented text **verbatim from the skill files** through the hook.
7. P7: one learning file records all three defects.

### Cut List

- **"A new poll arm that compares branch-protection/ruleset required contexts to the head's check
  runs"** buys P3. `ci-head-verdict.sh required`, `required-set-report.sh` and the fence's #11544
  required-set read already do exactly this, reusing `admin-merge-ready.sh`'s required-set resolution.
  The 2026-10-28 learning says a fix must reuse that logic rather than add a second copy. **Cut as a new
  mechanism.** What survives is restoring the existing arm (defect 1) and a fixture row that proves it
  fires on the incident's shape with the hint present. The CTO ruling below decides whether any gate
  predicate should also move.
- **A `gh` hint-suppression env var or config**: none exists in gh 2.106.0. Cut.
- **Rewriting the documented arm form to a literal SHA**: it would break the `${H:?...}` same-call
  binding that `plugins/soleur/test/arm-check-sites.test.sh` pins at every arm site (A1, CTO ruling R1,
  2026-11-13), and pre-merge-rebase's keying on the PR number (#12697). Superseded by the hook-side shape,
  pending the CTO ruling below.

### Relevant files

- `plugins/soleur/skills/ship/SKILL.md`: Phase 7 fence between `phase-7-poll-block:start` and `:end`
  (per-tick state read, post-sync re-read); arm lock block under "Wrap the `gh pr merge` call in the
  merge-main lock".
- `plugins/soleur/skills/merge-pr/SKILL.md`: §5.2 mirror (two state reads); arm lock block under
  "Merge gate".
- `plugins/soleur/lib/pr-merge-poll.ts` plus `plugins/soleur/test/pr-merge-poll.test.ts`; Grok text in
  `behindSyncInstructions()` and `plugins/soleur/lib/harness.ts` `pollInstructions()`.
- `plugins/soleur/scripts/sync-pr-behind.sh`: standalone `head_ref` / `state_line` reads; `qw_snapshot`
  (an `errf` temp file is the existing in-repo precedent for stdout/stderr separation).
- `plugins/soleur/scripts/required-set-report.sh`, `plugins/soleur/scripts/ci-head-verdict.sh` (`required`
  mode, `try_read_cancelled`).
- `.claude/hooks/ship-kb-archive-gate.sh`: the `_mhc_scan` arm ("extra operands alongside
  --match-head-commit" / "names no 40-hex sha"), the multi-invocation arm ("more than one gh pr merge
  invocation"), the positional census (`TARGET_KIND=pr`).
- `plugins/soleur/test/arm-check-sites.test.sh`: pins the documented arm text across SITES.

### Institutional learnings applied

- `2026-11-25-i-fixed-the-gate-instead-of-the-workflow-and-shipped-an-empty-token.md` §3: the measured
  accept/deny table for this gate. Widening a security gate's accept set changes its threat model, so
  ask what context the newly accepted shape runs in.
- `workflow-issues/2026-10-28-a-green-verdict-and-an-armed-auto-merge-do-not-prove-a-required-context-exists.md`:
  the same `cla-evidence` cancellation. Reuse the required-context logic, never a second copy.
- `2026-11-09-a-fix-round-closes-the-instance-the-reviewer-named-and-leaves-its-sibling-arms.md`:
  enumerate every sibling arm and mirror. Here that means both fence reads, both mirror reads, and all
  three standalone sync reads.
- `2026-07-20-adding-a-second-copy-of-a-guarded-literal-disarms-the-first.md`: accepting two identical
  invocations must not let a different second one through. A mutation row pins this.
- `2026-09-25-gh-stub-must-mirror-real-cli-flags.md` and
  `best-practices/2026-06-17-webhook-combinedoutput-success-path-must-be-pure-json.md`: the fixture's
  `gh` stub must emit the real hint shape on stderr **before** stdout, rc 0, and the success path is
  the one to test.
- `integration-issues/2026-04-06-doppler-stderr-contaminates-docker-env-file.md`: never fold stderr into
  a value that is parsed later.
- `2026-10-31-a-pattern-grep-guard-is-satisfied-by-dead-branches-pin-the-control-flow-skeleton.md` and
  `2026-10-04-an-allow-list-of-line-shapes-is-not-a-closed-sequence...md`: a hook test that feeds the
  documented block must extract it from the skill file, not hand-copy it.

### Conventions

- The fence is mirrored, and the fixture asserts mirror parity and that no temp file outlives the block.
- `cq-write-failing-tests-before`: each fix lands RED-first.
- `cq-test-fixtures-synthesized-only`: no live `gh` in fixtures.
- CI is the test gate.
- No edits under `docs/` or to legal documents. No production writes. The approval-queue flag is untouched.

### Functional overlap

`soleur:engineering:discovery:functional-discovery` found no community artifact that replaces these
fixes. All 3 registries answered; nothing was installed.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "All fixes live under plugins/soleur/skills/ship" | The fixes span `plugins/soleur/lib/`, `plugins/soleur/scripts/`, `plugins/soleur/skills/{ship,merge-pr,schedule,review}/`, `.claude/hooks/` and `plugins/soleur/test/` | Files to Edit lists the real paths. Every path stays in the ship merge path's own surfaces, and none is under `docs/` or legal. |
| (2) needs "a poll arm that detects a required check absent on the current head SHA" | That arm exists (#11544, merged 2026-11-09 in 40d23d1838): `required-set-report.sh` runs `ci-head-verdict.sh required`, which reads the required set from `admin-merge-ready.sh` and hunts cancelled owner runs. Defect 1 made it unreachable. | No new arm (CTO ruling F2). Restore it via defect 1 and pin with fence fixture rows that run with the hint present. |
| (3) the gate rejects "`with_lock merge-main … -- gh pr merge --match-head-commit <sha>` as extra operands" | The lock passthrough is accepted. "Extra operands" is drawn by the PR **number** beside `--match-head-commit`. The documented block is also denied for its variable SHA and for its second invocation. | Hook-side fix for all three causes (CTO ruling F3). The test runs every documented block verbatim. |
| (1) "separate stderr … in pr-merge-poll.ts" | `pr-merge-poll.ts` makes no `gh` call. It is the portable spec: the jq template, the state predicates and the Grok instruction text. | Add a stdout-only parse helper with a stderr-hint test, and one stdout-only sentence in the Grok/Claude instructions (CTO ruling F1). |

## Problem Statement

`gh` 2.106.0 (2026-11-25) prints an interactive "use `gh event listen` instead of polling" hint on stderr
for every `gh pr view` and for `gh run view` of a PR run. Every shell site that captures those calls
with `2>&1` now parses a 9-line string that starts with `hint:`. In the Phase 7 merge poll this
switches off every OPEN-state arm without a sound: BEHIND auto-sync, the queue-state and dequeue read,
and the #11544 required-set read that exists to catch a required check with no run at the head. When
PR #13017's `cla-evidence` head run was cancelled by its concurrency group (an `issue_comment` run
in the same group displaced the pending `pull_request_target` run, confirmed from the Actions API and
filed as #13115), the arm that should have reported `state=absent` never ran. The poll would have
heartbeated to its 90-minute cap, and a manual rerun recovered it.

Separately, the locked arm block every skill documents (`ship`, `merge-pr`, `product-roadmap`,
`drain-prs` and `review-evidence-comment.md`'s arm check) is refused by `ship-kb-archive-gate.sh` for three
independent reasons, so an agent following the doc is denied and drifts to the flag-only form, which
skips the merge-main lock (#12697, #12963).

## Proposed Solution

### Defect 1 — stdout is the answer, stderr is the diagnostic (CTO ruling F1)

- **Fence (ship Phase 7 and the merge-pr §5.2 mirror).** Pinned shape (plan-review: DHH, CTO devex,
  advisor):
  - Before any allocation: `SYNC_SNAP=""; GH_ERR=""` and ONE trap,
    `trap 'rm -f "$SYNC_SNAP" ${GH_ERR:+"$GH_ERR"}' EXIT`. It replaces the conditional
    `trap 'rm -f "$SYNC_SNAP"' EXIT` inside the precondition chain (that chain keeps its
    `SYNC_SNAP="$(mktemp)" && cp …` and loses its `trap`). No second `trap … EXIT` anywhere in the block.
  - `GH_ERR="$(mktemp 2>/dev/null)" || GH_ERR=""` right after the trap. Every read redirects
    `2>"${GH_ERR:-/dev/null}"`, so a failed mktemp never names `/dev/null` in an `rm`.
  - Both state reads (per tick, and the post-sync re-read):
    `s=$(gh pr view "$PR" --json state,mergeStateStatus --jq '"\(.state) \(.mergeStateStatus)"' 2>"${GH_ERR:-/dev/null}") || s="fetch-error: $(gh_err_line $?)"`.
  - `gh_err_line <rc>` is fence-local. It prints the first stderr line that is non-empty and starts with
    neither `hint:` nor whitespace, cut with `${e:0:200}` (never `| head -c`: SIGPIPE under pipefail, see
    the `sdisp` comment in `sync-pr-behind.sh`). When there is no such line, or no file, it prints `rc=<rc>`.
    `2>"$GH_ERR"` truncates on every call, so ticks never mix.
- **`sync-pr-behind.sh` standalone mode (3 sites).** Reuse `qw_snapshot`'s pattern: stderr to an
  `errf` temp file removed on every path. Add ONE script-side `gh_err_line` function (same filter as the
  fence) and use it for every stderr echo in the script, the three standalone reads **and** the existing
  `head -c 200 "$errf"` echoes in `queue_state_read` and `qw_snapshot`, so the next hint-prefix change
  is one edit on the script side and one in the fence (CTO devex). Drop the comment that says "a multi-line answer because stderr is merged by 2>&1" and the one
  above `sdisp` ("gh's stderr is merged into the answer"). Both become false.
- **`.claude/hooks/ship-operator-step-gate.sh`** (`cur=$(parked_gh pr view --json number --jq .number 2>&1)`):
  stdout only. Stderr goes to a function-local temp file, and the "no pull requests found" grep reads
  that file. The file is removed by `rm -f` on every return path, with the `# lint-trap-ownership: ok`
  convention `sync-pr-behind.sh` already uses. Never add a second `trap … EXIT`: the hook's later
  `trap 'rm -f "$PR_BODY_FILE"' EXIT INT TERM` would replace it, or be replaced by it. If mktemp fails,
  keep today's fail-closed hold.
- **`gh run view` poll snippets** (ship's post-merge release-run poll `r=$(gh run view <id> --json status,conclusion ...`,
  and `schedule/SKILL.md`'s `s=$(gh run view "$RUN_ID" ...`): use the same stderr-file form as the fence
  (their own `e=$(mktemp)`, trap and filtered-first-line `fetch-error:`). Never use the bare-rc option
  (b) the CTO rejected. Rewrite ship's "**Why this pattern:**" prose to say why stdout and stderr are
  kept apart, because that prose is the copy authors paste (CTO F1; dissent recorded in
  decision-challenges.md). Sites that print no hint and stay unedited (`gh run list` polls,
  `worktree-manager.sh`, `github-community.sh`, the admin-merge `err=$(…)`) go on Guard 2's shrink-only
  exclusion list.
- **`plugins/soleur/lib/pr-merge-poll.ts`:** add `parsePrPollStdout(stdout: string): string | null`. It
  returns the state line when the trimmed stdout is exactly one line matching
  `^(OPEN|MERGED|CLOSED) [A-Z_]+$`, else `null`, so a merged stream is refused instead of misread. Its doc
  comment says it is the portable spec (no runtime caller; the fence is the executing copy). Add one
  stdout-only sentence ("read stdout only; send stderr to a file, never `2>&1`") to every arm of
  `behindSyncInstructions()` and of `harness.ts` `pollInstructions()`. The test loops over every value
  of the `Harness` union, so a newly added harness cannot skip it (CTO devex). Test in
  `pr-merge-poll.test.ts`: `parsePrPollStdout(<fixture hint> + "\n" + "OPEN BEHIND")` is `null` and
  `parsePrPollStdout("OPEN BEHIND\n")` is `"OPEN BEHIND"`. The tautological "parse with stderr equals
  parse without" case is dropped (DHH, simplicity). The behavioural pin is fixture rows H1–H4.
- **One shared hint fixture:** `plugins/soleur/test/fixtures/gh-pr-view-hint.txt`, the real 9-line gh
  2.106.0 block with a synthesized PR number (`4387`) and resource URL. All four suites read it (fence
  fixture, sync, operator gate, TS), so the shape is stated once (CTO devex).

- **`ship/SKILL.md` byte ceiling (measured).** `plugins/soleur/test/skill-body-budget.json` pins ship at
  273955 B. Today it is 273886 B, so there are **69 B of headroom**, and `scripts/lint-skill-body-budget.py
  --base origin/main` fails a PR that crosses the ceiling. The fence growth alone (about 225 B: trap,
  `GH_ERR`, `gh_err_line`, two redirects) exceeds that. The ship diff therefore moves the post-merge
  poll's 681-byte "**Why this pattern:**" paragraph, rewritten to the stdout/stderr rationale, into
  `plugins/soleur/skills/ship/references/monitor-hygiene.md` (already linked from ship as
  `./references/monitor-hygiene.md`). One short relative-link pointer stays in its place, with no
  `${CLAUDE_PLUGIN_ROOT}` token added to the reference, so the W4a/W4b Read-surface census does not
  move. Target: ship ends at least 50 B under its ceiling. Measure with the lint before each commit
  that touches ship. A ceiling raise is the fallback only, and it lands as its own raise-only PR, which
  is the only form the lint admits. `merge-pr` and `schedule` have no ceiling row.

### Defect 2 — the existing required-set arm, made reachable and pinned (CTO ruling F2)

No new arm. The fence's #11544 read is the "required check absent on the head" arm, and it reuses
`admin-merge-ready.sh`'s required-set resolution as the 2026-10-28 learning asks. Its predicates (OPEN
BLOCKED, armed, not queued, full-decided, a 10-tick dwell) stay as they are: an earlier arm without
them would read "absent" while the `test` aggregate is legitimately still being created. The poll keeps
**printing** RECOVERY hints and never running `gh run rerun` itself. The rerun stays an agent act after
the `ready-run-wait.md` check. The fix proves reachability:

- New fence fixture rows, run against both `:ship` and `:merge-pr` and RED first against today's `2>&1`
  text. The `gh pr view` stub prints `fixtures/gh-pr-view-hint.txt` on stderr **before** stdout, rc 0.
  Each of H1–H3 also asserts that every state line matches
  `^[0-9:]{8} \[[0-9]+/90\] PR 4387 (OPEN|MERGED|CLOSED) ` and that no stdout line starts with `hint:`
  (folded in from a separate row, per simplicity):
  - **H1 / H1f:** OPEN BLOCKED, armed, not queued, verdict stub `full-decided`. The required-set stub is
    the R rows' chosen-body root (`RROOT`, not the default degraded stub), printing
    `SOLEUR_CI_REQUIRED_SET state=absent …` (H1) or `state=failed …` (H1f). The row reaches
    `[ship.phase7.required_set] state=absent — exiting poll` (or `state=failed`), with `X_RS_CALLS=1`.
    The incident's own classification (a required context whose only head run of its owning workflow
    was cancelled → `state=absent` plus `RECOVERY rerun run=<id> basis=workflow`) is already pinned by
    `plugins/soleur/test/ci-head-verdict.test.sh` row R2 (`cla-evidence`, a cancelled run at the head),
    so the fence rows stub the report and do not re-derive it (advisor).
  - **H2:** OPEN BEHIND, no queue rule. The row reaches `BEHIND detected — auto-sync attempt 1/6` and
    `auto-sync 1 pushed`.
  - **H3:** OPEN CLEAN, then a dequeue on the `--queue-state` read. The row reaches `[ship.phase7.dequeued]`
    within 5 ticks.
  - **H4:** `gh pr view` exits 1 with the hint plus `gh: HTTP 502` on stderr. The state line ends
    `fetch-error: gh: HTTP 502`, never a `hint:` line, and the poll breaks. **H4b:** exit 1 with only the
    hint on stderr → `fetch-error: rc=1`.
  - **H6:** `mktemp` fails at loop entry (a mock that fails only the first call). The poll still parses
    state, no temp file outlives the block, and `[[ -c /dev/null ]]` still holds afterwards.
- The cancellation root cause (shared concurrency group in `cla-evidence.yml`) is out of this PR:
  filed as **#13115** (CTO ruling, extra item).

### Defect 3 — the gate accepts the documented arm form, narrowly (CTO ruling F3)

In `.claude/hooks/ship-kb-archive-gate.sh`, keep the existing `_tok_scan != _tok_cmd` deny ahead of both
new rules.

- **(i) One bare PR number beside one `--match-head-commit`.** If the first positional is a literal bare
  PR number (`^[0-9]{1,9}$`, so a 40-digit SHA is never read as a number) and there is exactly one
  `--match-head-commit`:
  - a literal 40-hex operand → `TARGET_KIND=sha`, as today;
  - an operand whose **raw** text (quotes kept, read from `_cmd_args`) is exactly one double-quoted
    simple expansion, `"$NAME"`, `"${NAME}"` or `"${NAME:?msg}"`, where `msg` contains none of `$`, a
    backtick, `(`, `)`, `\` or `"` → `TARGET_KIND=pr` with that number (the head is censused by number);
  - anything else still denies: `"${H:-…}"`, `$(…)`, single quotes, an unquoted `$H` (already the
    operand-loss deny), a second positional, a second SHA.
- **Where rule (i) reads the operand (measured).** `_merge_args` builds residues with the class
  `[^;&|$\`()]*`, which **stops at `$`**. For the documented arm both `_scan_args` and `_cmd_args` end
  `--match-head-commit "`, and the operand never appears in either. Rule (i) therefore needs its own
  raw-operand read over `$CMD`: the text after the single `--match-head-commit` up to the end of its
  shell word, with quote awareness. That text is matched against the three allowed expansion shapes
  anchored at both ends. Do not try to widen `_merge_args`'s class. Every existing deny (operand-loss,
  `xargs`, the multi-invocation count) is calibrated on it.
- **(ii) Several identical invocations.** More than one `gh pr merge` invocation is accepted only when
  every raw invocation residue (`_cmd_args`, quotes kept, after `_strip_repo_flags`) is byte-identical,
  every quote-stripped residue (`_scan_args`) is identical, **and** every invocation's raw
  `--match-head-commit` operand (read as in rule (i)) is byte-identical. The operand check is needed
  because the residues are cut at `$` and cannot see it. They are then censused as one object. A
  merge nested in a quoted operand (`"$(gh pr merge 999 …)"`) still surfaces as its own raw invocation
  through the `(` boundary, while `$SCAN` blanks it, so the invocation counts differ and the existing
  `_tok_scan != _tok_cmd` deny fires before rule (ii) is reached.
  Any difference keeps today's "more than one gh pr merge invocation" deny.
- **Residuals header.** Add one paragraph to the hook's header residuals list.
  `--match-head-commit` can only restrict a merge, so every merge the new form admits is one the
  already-admitted `gh pr merge N --squash --auto` admits too: the census reads the PR head at invoke
  time, and `--auto` merges a later head. A merge nested inside the quoted operand is caught because
  `strip_command_bodies` blanks double-quoted spans while `_cmd_args` keeps them, so the token
  comparison denies.
- **Residual, stated rather than fixed:** with a variable SHA the census reads the PR head by number at
  hook time, and the arm check reads `H` moments later in the same call. A push in between lands a head
  the census did not read. That is the same window the gate already accepts for
  `gh pr merge N --squash --auto` (the census reads the invoke-time head and `--auto` merges a later
  one), and `--match-head-commit` narrows it to the head the evidence check read. Record it in the
  residuals paragraph. No mutation row, because it is not reachable from the command text (advisor).
- **Doc text, one site.** `plugins/soleur/skills/ship/references/merge-queue-dequeue.md` step 3 arms
  with `gh pr merge "$N" …`. A variable PR number stays denied by design (P5, T73), so that arm changes
  to the literal `<pr-number>` token the paragraph already asks the reader to substitute
  (`N=<pr-number>`), with a clause saying the merge gate censuses a literal number (simplicity). Every
  other site is already correct against the fixed gate. The 2026-11-25 learning's §3 table, which
  recommends the flag-only form, gets a dated follow-up line pointing at this fix. Learnings are
  append-only history, so the table itself stays.
- **The admin hatch** (`settle-then-admin-merge.md`, `gh pr merge <N> --squash --admin --match-head-commit "$SHA"`
  inside `err=$(…)`) is named in #12697 and is admitted by rule (i) as a consequence of the ruling. It
  gets its **own** Guard 1 row and its own residual sentence: `--admin` reach is gated by
  `admin-merge-ready.sh` exiting 0 immediately before, and the KB census is orthogonal to it. It is not
  folded into the `--auto` must-allow set (simplicity).

## Implementation Phases

### Phase 0 — RED tests first (`cq-write-failing-tests-before`)

0. `plugins/soleur/test/fixtures/gh-pr-view-hint.txt`: the shared hint fixture (synthesized PR number).
1. `plugins/soleur/test/pr-merge-poll.test.ts`: the `parsePrPollStdout` cases, the every-`Harness`
   sentence loop, and the Guard 2 regression scan. RED: the helper and sentence do not exist, and the
   scan reports **exactly** the 10 known sites (ship ×3, merge-pr ×2, sync-pr-behind ×3, schedule ×1,
   operator-step-gate ×1) plus no unexpected one. A RED count other than 10 means the matcher is wrong.
2. `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`: rows H1, H1f, H2, H3, H4, H4b, H6 (a new
   `WANTH` row-set pin like `WANTQ`). RED against today's fence: H1/H1f never call the required-set
   stub, H2 never syncs, H3 never dequeues, H4 prints a `hint:` line as the error, and the state-line
   assertion in H1–H3 sees `hint:`.
3. `.claude/hooks/ship-kb-archive-gate.test.sh`: new rows from T83 on (Guard 1's matrix). **The site
   list is derived, not restated:** the suite parses the `SITES=( … )`, `LINK_ONLY=( … )` and `CANON=`
   assignments out of `plugins/soleur/test/arm-check-sites.test.sh`, so the two suites cannot drift
   (DHH, simplicity, CTO devex). From each site it extracts every fenced or inline-code span containing
   `gh pr merge` (the dequeue site's arm is inline code) and substitutes the `<number>`/`<N>`/
   `<pr-number>`/`PR_NUMBER` token with the fixture PR number. It asserts the extracted-span count
   equals the expected count per site, and it names the file and anchor whenever an extraction comes back
   empty. Spans are never hand-copied. **The first RED row asserts which deny reason fires today** for
   the verbatim ship block (`more than one gh pr merge invocation`, measured), so a fourth, unexpected
   reason cannot hide behind a generic deny (advisor). RED: each `--auto` block is denied today. The
   admin-hatch span's RED row asserts today's reason, `a --match-head-commit flag names no 40-hex sha`
   (measured). That deny sits after the `_tok_scan`/`_tok_cmd`, operand-loss and multi-invocation arms,
   so the `err=$(…)` wrapper and its `2>&1` redirect already pass every earlier arm, and rule (i) is the
   only change it needs.
4. A sync standalone row in `plugins/soleur/test/sync-pr-behind.test.sh` (the suite that owns `kind=wrong_branch`):
   with a hint on stderr and the right branch, the standalone run does **not** exit 12. RED today.
5. An operator-step-gate row in `.claude/hooks/ship-operator-step-gate.test.sh`: a flag-only merge,
   no parked PR, `gh pr view` printing the hint on stderr → allowed. RED today (unreadable answer →
   hold path; only observable when a parked PR exists, so the row seeds one parked PR other than
   the current one).

### Phase 1 — defect 1

- Fence and mirror, as in Proposed Solution. Update the mirror-parity token list in the fixture: the
  `trap 'rm -f "$SYNC_SNAP"' EXIT` token becomes `trap 'rm -f "$SYNC_SNAP" ${GH_ERR:+"$GH_ERR"}' EXIT`,
  and `2>"${GH_ERR:-/dev/null}"` and `gh_err_line` are added as tokens. Confirm the extraction still
  reports its 3 fingerprint tokens.
- `sync-pr-behind.sh` (3 standalone reads plus the shared `gh_err_line` for every stderr echo),
  `ship-operator-step-gate.sh`, the two `gh run view` poll snippets and the "Why this pattern" prose.
- Run `python3 scripts/lint-trap-tempfile-ownership.py` over the changed scripts. Its rule (c) gates
  every ADDED `mktemp`, so each new allocation needs an owning trap or the file's existing
  `# lint-trap-ownership: ok` convention with a reason.
- `pr-merge-poll.ts` helper and instruction sentences; `harness.ts` `pollInstructions()` sentence.

### Phase 2 — defect 2

- Rows H1–H6 go GREEN with no fence change beyond Phase 1. If H1 is still RED after Phase 1, it means
  a second predicate is broken. Diagnose it from the row's trace, and do not widen the arm.

### Phase 3 — defect 3

- Hook rules (i) and (ii), and the residuals paragraph (the quoted-operand argument, the
  census-vs-`H` window, the admin hatch). All Guard 1 rows GREEN, and every pre-existing row (T1–T82)
  unchanged.
- `merge-queue-dequeue.md` step 3: `gh pr merge "$N"` becomes `gh pr merge <pr-number>`. Re-run
  `bash plugins/soleur/test/arm-check-sites.test.sh`. Its A1 pin (`--match-head-commit "${H:?...}"`)
  and `DEQUEUE_FETCH` are untouched by this edit, and the suite must stay green.

### Phase 4 — learning and close-out

- `knowledge-base/project/learnings/workflow-issues/2026-11-28-a-cli-hint-on-stderr-switched-off-every-open-arm-of-the-merge-poll.md`:
  all three defects, and how they interlock. The stderr hint disabled the arm that would have caught
  the cancelled required check, and the gate's refusals pushed agents onto the unlocked flag-only form.
  Include the measured accept/deny table before and after, the incident timeline, and `## Session Errors`.
- Append a dated follow-up line to `2026-11-25-i-fixed-the-gate-instead-of-the-workflow-and-shipped-an-empty-token.md`
  §3 pointing at this fix.
- PR body: `Closes #12697`, `Closes #12963`, `Ref #13115`, `Ref #13017`.
- **Arming THIS PR** (it merges on pre-fix machinery, see Dependencies & Risks): after the arm check,
  arm with the measured-accepted form `bash "$SS_LIB" with_lock merge-main 600 -- gh pr merge --squash
  --auto --match-head-commit <40-hex>` from the PR worktree, and sync a BEHIND reading by hand with the
  standalone script if the installed poll does not (DHH).

## Files to Edit

- `plugins/soleur/skills/ship/SKILL.md` — Phase 7 fence (2 reads, combined trap, `gh_err_line`); the
  post-merge `gh run view` poll and its "Why this pattern" prose.
- `plugins/soleur/skills/merge-pr/SKILL.md` — §5.2 mirror (same edits).
- `plugins/soleur/skills/schedule/SKILL.md` — `gh run view` poll capture.
- `plugins/soleur/lib/pr-merge-poll.ts` — `parsePrPollStdout`, instruction sentences.
- `plugins/soleur/lib/harness.ts` — `pollInstructions()` sentence.
- `plugins/soleur/scripts/sync-pr-behind.sh` — 3 standalone reads, a shared `gh_err_line` for every stderr echo, 2 stale comments.
- `.claude/hooks/ship-operator-step-gate.sh` — current-branch PR read.
- `.claude/hooks/ship-kb-archive-gate.sh` — rules (i), (ii), residuals paragraph.
- `plugins/soleur/skills/ship/references/merge-queue-dequeue.md` — step 3 arm uses the literal `<pr-number>`.
- `plugins/soleur/test/pr-merge-poll.test.ts` — helper tests and the Guard 2 scan.
- `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` — rows H1, H1f, H2, H3, H4, H4b, H6, `WANTH`, parity tokens.
- `.claude/hooks/ship-kb-archive-gate.test.sh` — Guard 1 rows.
- `.claude/hooks/ship-operator-step-gate.test.sh` — hint row.
- `plugins/soleur/test/sync-pr-behind.test.sh` — standalone hint row. Re-anchor mutation rows G6-1…G6-8
  on the new failure-text lines (today they exact-match `gh pr view failed: $(printf '%s' "$head_ref" | head -c 200 | qb_clean)`
  and fail "anchor text is absent" once it is rewritten). Move the `lsa`–`lsh` sanitiser scenarios' junk
  from stderr to stdout (or to the failure-path stderr), so they keep exercising the sanitiser after
  stderr is split from the answer.
- `plugins/soleur/skills/ship/references/monitor-hygiene.md` — receives the relocated "Why this pattern" paragraph (byte ceiling).
- `knowledge-base/project/learnings/2026-11-25-i-fixed-the-gate-instead-of-the-workflow-and-shipped-an-empty-token.md` — dated follow-up line.

## Files to Create

- `knowledge-base/project/learnings/workflow-issues/2026-11-28-a-cli-hint-on-stderr-switched-off-every-open-arm-of-the-merge-poll.md`
- `plugins/soleur/test/fixtures/gh-pr-view-hint.txt` — the shared synthesized hint block.

## Open Code-Review Overlap

None. 96 open `code-review` issues were checked against every path in Files to Edit/Create, with no matches.
#12697 and #12963 carry `deferred-scope-out`/`meta/machinery`, not `code-review`. They are folded in
(**Closes #12697, Closes #12963**). #12739 (arm-walker, repo-wide arm sites) touches the same arm
text but not these files. **Acknowledge:** it is a different property (which sites arm), and this
plan changes no arm site.

## Guard Contract

### Guard 1 — kb-archive gate admits the documented arm form and nothing wider

**Property.** `ship-kb-archive-gate.sh` admits a `gh pr merge` command only when every invocation in it
resolves to the same single censusable target. That target is a literal bare PR number (optionally
beside one `--match-head-commit` that is a literal 40-hex or one double-quoted simple variable
expansion), a literal 40-hex with no number, or the HEAD path. The gate then runs the KB-archive census
on that target.

**Assembly.** The single chokepoint is the target-resolution block in `ship-kb-archive-gate.sh`, from
the multi-invocation arm through the `TARGET_KIND` assignment. Its only inputs are the two residue sets
produced by `_merge_args`: `_scan_args` (built from `$SCAN`, where `strip_command_bodies` has blanked
quoted spans) and `_cmd_args` (built from the raw `$CMD`). Both new rules quantify over **every**
residue line of **both** sets. The census below the block (`TARGET_KIND` = `pr` | `sha` | `head`) is
the one consumer, and an accepted shape must reach it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Rule (ii) compares only the first two residues; input: two identical `gh pr merge 5 --squash --auto --match-head-commit "${H:?x}"` followed by a third `gh pr merge 6 ...` | RED (denied: more than one invocation) |
| 2 | Rule (ii) compares only `_scan_args`; input: branch A `... --match-head-commit "$H"`, branch B `... --match-head-commit "$(gh pr merge 999 --admin)"` (identical once quotes are blanked) | RED (denied) |
| 3 | Rule (i) accepts any `$`-shaped operand; input: `--match-head-commit "${H:-$(gh pr merge 9)}"` | RED (denied) |
| 4 | Rule (i) number regex unbounded; input: a 40-digit first positional beside `--match-head-commit <40-hex>` | RED (denied: not a bare PR number) |
| 5 | Dispatch: the new branch sets no `TARGET_KIND` and exits 0 before the census; input: the documented ship block verbatim on a branch whose diff carries an **unarchived** `knowledge-base/project/specs/<branch>/tasks.md` | RED (denied by the census, not by target resolution) |
| 6 | Two branches with different literal SHAs | RED (denied) |
| 7 | Two branches with different PR numbers | RED (denied) |
| 8 | Delete rule (i); every `--auto` arm span extracted from the `arm-check-sites.test.sh` SITES plus CANON, on an archived KB | RED (each denied), because the suite asserts allowed |
| 9 | Delete rule (i); the admin-hatch span from `settle-then-admin-merge.md` (LINK_ONLY), on an archived KB | RED (denied), because its own row asserts allowed |
| 11 | Rule (ii) compares residues only (they are cut at `$`); input: branch A `... --match-head-commit "${H:?x}"`, branch B `... --match-head-commit "${G:?x}"` | RED (denied: operands differ) |
| 12 | Rule (i) reads the operand from `_cmd_args` instead of the raw extractor | RED: the documented block is still denied (`names no 40-hex sha`), because row 8 asserts allowed |
| 10 | Revert the `merge-queue-dequeue.md` doc edit (`gh pr merge "$N"`) | RED: that site's extracted span is denied (operand-loss), so a variable PR number stays outside the accept set |

**Harness rows:**

| # | Suite edit or input | Expected |
|---|---|---|
| H-a | Point the site-list parser at a temp copy of `arm-check-sites.test.sh` with `SITES=(` renamed, and separately at a site copy with its `gh pr merge` span removed | Suite FAILS loudly, naming the file ("site list empty" / "extracted 0 spans, want N"), never a 0-row pass |
| H-b | Must-PASS non-canonical: `gh pr merge 5 --squash --auto --match-head-commit "${SHA}"` (braced, no `:?`) on an archived KB | allowed |
| H-c | Must-PASS non-canonical: the documented ship block with the degrade-open `else` branch deleted (single locked invocation) | allowed |
| H-d | `fail()` positive control: one inverted assertion must increment the failure counter (the suite's existing positive-control idiom) | counter moves |

**Anchor.** There is no stored value. The gate compares live command text against the live git tree,
so no hash or floor can drift.

### Guard 2 — no `gh` capture merges stderr into the value it returns

**Property.** No tracked non-test `.sh`, `.md` or `.ts` file under `plugins/` or `.claude/hooks/`
captures a `gh` command's output in a command substitution with `2>&1`, except sites on a named,
shrink-only exclusion list. A later gh that adds the hint to `pr list` or `run list` then cannot
regress a parsed site unseen (CTO devex).

**Assembly.** One chokepoint: the file list from `git ls-files -- plugins .claude/hooks`, minus
`*.test.sh`, `*.test.ts` and `/archive/` paths (not Bun `Glob`, which skips dot-directories). Each
file's logical lines are joined across backslash-newline continuations, then matched by the capture
shape: a `$(`, then a command word equal to `gh` or ending in `_gh`, then `2>&1` before the **matching**
`)`. The matcher tracks quote state and paren depth, because every real site's jq template carries `)`
inside quotes (`'"\(.state) \(.mergeStateStatus)"'`): a `[^)]*` scan finds 1 of the 10 sites. The
scanner's own file is a `*.test.ts` and is excluded, and its planted violations are built by
concatenation (`"2>" + "&1"`), so it never matches itself.
The exclusion list holds `<path>` plus a literal substring of the matched text, one entry per site.
An entry that no longer matches anything fails the scan, which is what keeps the list shrink-only.
Initial entries: `--log-failed` dumps; ship's `gh run list --workflow` poll; `worktree-manager.sh`'s
`gh pr list` and `gh pr create`; `github-community.sh`'s six `gh api` reads; the admin-hatch
`err=$(gh pr merge …)`. The scan lives in `plugins/soleur/test/pr-merge-poll.test.ts`, so it adds no new
suite registration.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add `2>&1` to the fence's per-tick read in its verbatim two-line form, jq template included (`gh pr view "$PR" --json state,mergeStateStatus \` / `--jq '"\(.state) \(.mergeStateStatus)"' 2>&1)`) | RED (tests the joiner and the paren-depth matcher) |
| 2 | Dispatch: the file list resolves empty (a path typo) | RED via a floor: at least 10 scanned files contain `gh pr view` (73 today) |
| 3 | Leave a compliant first site and add a violating site in a second file under `.claude/hooks/` | RED (tests dot-dir coverage and that the scan does not stop at the first file) |
| 4 | Fix an excluded site (e.g. `worktree-manager.sh`'s `gh pr list`) without deleting its exclusion entry | RED (stale exclusion) |
| 5 | Add a new `$(gh run list … 2>&1)` capture in a skill file | RED (not excluded) |

**Harness rows:**

| # | Suite edit or input | Expected |
|---|---|---|
| H-a | Run the scanner over a temp fixture tree with one planted violation | reports exactly that file |
| H-b | Must-PASS non-canonical: a fixture with `gh pr view ... 2>"$errf"` and one with `2>/dev/null` | reports none |

**Anchor.** The exclusion list is the stored value. A weakening needs a new entry, and an entry is a
reviewed line in the diff. The scan fails on a stale entry, so the list cannot silently grow past
the sites that exist.

## User-Brand Impact

- **If this lands broken, the user experiences:** a Soleur operator's `soleur:ship` Phase 7 poll that
  never auto-syncs a BEHIND PR, never reports a missing required check, and times out after 90 minutes.
  Or an arm step whose documented command the KB-archive gate keeps refusing, so the agent drops the
  merge-main lock. The PR does not merge, or merges unserialized.
- **If this leaks, the user's workflow is exposed via:** a too-wide gate accept rule (Guard 1, rows
  2–3) that lets a merge whose KB artifacts are unarchived land on `main` without the census. The data
  is internal project-planning text, not user data. No credentials, tokens or user records pass through
  any changed path.
- **Brand-survival threshold:** none
- **Threshold decision (challengeable):** every changed surface is the operator's own merge tooling
  (agent shell fences, a PreToolUse hook, a sync script). No end-user data path, auth surface or deployed
  service changes, and the worst outcome is a stalled or unserialized merge of the operator's own PR.
  That is below `aggregate pattern`.

`threshold: none, reason: the diff touches no path matched by preflight's SENSITIVE_PATH_RE (no apps/web-platform server/lib, infra, doppler or workflow file); all edits are plugin skill text, plugin scripts, .claude/hooks and tests.`

## Observability

```yaml
liveness_signal:
  what: Phase 7 Monitor state lines "<hh:mm:ss> [i/90] PR <N> <STATE> <MERGESTATE>" plus the tagged lines
    "[ship.phase7.required_set] state=...", "BEHIND detected", "[ship.phase7.dequeued]"
  cadence: one poll tick per 60 s; a state line on every change and every 3rd tick
  alert_target: the agent session's Monitor notification stream (stdout only)
  configured_in: plugins/soleur/skills/ship/SKILL.md (phase-7-poll-block) and plugins/soleur/skills/merge-pr/SKILL.md §5.2
error_reporting:
  destination: Monitor stdout "fetch-error: <first non-hint stderr line>" for a failed gh read; the hook's
    permissionDecisionReason plus a row in .claude/.rule-incidents.jsonl for a gate deny
  fail_loud: "fetch-error:" ends the poll; "[ship.phase7.required_set] state=absent — exiting poll" names the missing context
failure_modes:
  - mode: gh writes new text on stderr (hint or warning) on an rc-0 read
    detection: fixture rows H1-H5 in plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh run in CI with the real hint shape on stderr
    alert_route: CI red on the PR that regresses it
  - mode: gh read fails (HTTP 5xx, auth)
    detection: the poll prints "fetch-error: <reason>" and stops (row H4)
    alert_route: Monitor notification to the agent session
  - mode: a required context has no passing run at the PR head
    detection: required-set read prints SOLEUR_CI_REQUIRED_SET state=absent and the poll exits [ship.phase7.required_set] (row H1)
    alert_route: Monitor notification, recovery pointer to skills/ship/references/ready-run-wait.md
  - mode: a stderr-merging capture of gh pr|run view is reintroduced
    detection: Guard 2 scan in plugins/soleur/test/pr-merge-poll.test.ts
    alert_route: CI red
  - mode: the gate refuses the documented arm form again, or admits a wider one
    detection: Guard 1 rows in .claude/hooks/ship-kb-archive-gate.test.sh
    alert_route: CI red
logs:
  where: the session's Monitor transcript; .claude/.rule-incidents.jsonl for hook denies
  retention: session transcript lifetime; the incidents file persists in the operator checkout until rotated
discoverability_test:
  command: bun test plugins/soleur/test/pr-merge-poll.test.ts -t stderr
  expected_output: "0 fail"
```

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "separate stderr from stdout in the fence and in pr-merge-poll.ts" [brief] | Defect 1: fence + mirror reads, `parsePrPollStdout`, instruction sentences | mapped |
| 2 | "with a test pinning that a stderr hint cannot alter the parsed state" [brief] | `pr-merge-poll.test.ts` cases (a)/(b); fixture rows H1–H5 | mapped |
| 3 | "add a poll arm that detects a required check absent on the current head SHA (compare branch-protection/ruleset required contexts to the head's check runs) and reports/reruns it instead of waiting silently" [brief] | Defect 2: the existing #11544 arm (`required-set-report.sh` → `ci-head-verdict.sh required`) made reachable, pinned by H1; reports via `[ship.phase7.required_set] state=absent` plus RECOVERY rerun hints | mapped — no NEW arm: the existing one already does exactly this (Cut List; CTO ruling F2) |
| 4 | "make the gate accept a `--`-delimited passthrough command (or fix the documented form so it matches the gate's real interface)" [brief] | Defect 3: hook rules (i)+(ii); the `--` passthrough is already accepted (measured) | mapped |
| 5 | "with a test exercising the documented form verbatim" [brief] | Guard 1 rows extracting the blocks by anchor from six files | mapped |
| 6 | "Capture a learning file for all three" [brief] | Phase 4 learning file | mapped |
| 7 | "no production writes; do not touch the approval-queue flag; no edits under docs/ or to legal documents" [brief] | Files to Edit carries none of these; the only GitHub write is the #13115 tracking issue | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Fence + mirror stdout-only reads, combined trap | "separate stderr from stdout in the fence" | asked |
| `pr-merge-poll.ts` helper + instruction sentences, `harness.ts` sentence | "and in pr-merge-poll.ts" | asked |
| `pr-merge-poll.test.ts` helper tests | "a test pinning that a stderr hint cannot alter the parsed state" | asked |
| Fixture rows H1–H6 + `WANTH` + parity tokens | asks 2–3 | asked |
| `sync-pr-behind.sh` 3 standalone reads + `sync-pr-behind.test.sh` row | — | inferred — justification: same defect, same poll family; the fence prints this standalone command as the manual recovery on `behind_no_sync`, and it exits 12 under the hint (CTO ruling F1) |
| `ship-operator-step-gate.sh` read + test row | — | inferred — justification: same capture defect in a merge-gate hook; it yields a spurious fail-closed hold on a flag-only merge while any PR is parked (CTO ruling F1) |
| `gh run view` poll snippets (ship post-merge poll, `schedule/SKILL.md`, ship "Why this pattern" prose), same stderr-file form | — | inferred — justification: they print the PR-run hint and are the copy future authors paste. CTO ruling F1, reaffirmed by the CTO devex seat. DHH/simplicity dissent recorded in decision-challenges.md |
| Shared `fixtures/gh-pr-view-hint.txt` | — | inferred — justification: four suites need the real hint shape. One file keeps them from drifting apart (CTO devex) |
| `merge-queue-dequeue.md` step-3 arm uses a literal `<pr-number>` | "the arm form every skill documents" (via ask 4: "or fix the documented form so it matches the gate's real interface") | asked |
| Guard 2 regression scan | — | inferred — justification: the enforcement contract that keeps defect 1 from returning, since the pattern was copied into ten sites (CTO risk 3) |
| Hook rules (i)+(ii) + residuals paragraph | "make the gate accept a `--`-delimited passthrough command (or fix the documented form…)" | asked |
| Guard 1 rows (extracted blocks) | "a test exercising the documented form verbatim" | asked |
| Learning file + follow-up line in the 2026-11-25 learning | "Capture a learning file for all three" | asked (the follow-up line is inferred — justification: that learning's §3 recommends the flag-only form this PR makes unnecessary; a reader of it would otherwise drop the lock) |
| #13115 tracking issue (filed at plan time) | — | inferred — justification: `wg-when-deferring-a-capability-create-a`; the CTO ruled the cla-evidence concurrency root cause out of this PR |

### Split Assessment

- Subsystems touched: 3 — `plugins/soleur`, `.claude`, `knowledge-base`
- Planned files: 17 | Estimated changed lines: ~760 (tests ~520, code/text ~150, learning ~90). The H5
  fold-in and the dropped tautological TS case offset the Guard 2 exclusion list and the admin-hatch row.
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. The three defects interlock: defect 2's proof (H1) needs defect 1's fix,
  and all three share the incident and the learning. The estimate sits near the line threshold. If the
  hook test rows push past 800, the fallback seam is "defect 3 (hook + Guard 1) as a second PR". That
  seam is recorded here and not pre-split.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

- [ ] AC1 — Fence and mirror: in each block extracted between the `phase-7-poll-block` markers (not
  file-wide), `grep -c '2>"${GH_ERR:-/dev/null}"'` returns 2 and `grep -c '2>&1)'` on a
  `gh pr view` line returns 0. The Guard 2 scan is green.
- [ ] AC2 — Each extracted fence has exactly one `trap … EXIT` line, and it reads
  `trap 'rm -f "$SYNC_SNAP" ${GH_ERR:+"$GH_ERR"}' EXIT`. Every fixture row still asserts that no temp
  file outlived the block. H6 also asserts `[[ -c /dev/null ]]`.
- [ ] AC3 — `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` passes with rows H1, H1f, H2,
  H3, H4, H4b and H6 on both `:ship` and `:merge-pr`, and the `WANTH` pin equals the rows run. In the
  RED commit (tests only, fence untouched) H1, H1f, H2, H3 and H4 fail.
- [ ] AC4 — H1 output contains `[ship.phase7.required_set] state=absent — exiting poll` and H1f
  `state=failed`. The arm's predicates are byte-unchanged in the diff: `git diff origin/main...HEAD --
  plugins/soleur/skills/ship/SKILL.md` touches no line containing `RS_AFTER=`, `RS_MAX=`, `rs_hold` or
  `full-decided`.
- [ ] AC5 — `bun test plugins/soleur/test/pr-merge-poll.test.ts` passes. `parsePrPollStdout("OPEN BEHIND\n")`
  returns `"OPEN BEHIND"`, and the fixture hint followed by `OPEN BEHIND` returns `null`.
- [ ] AC6 — For every value of the `Harness` union, `behindSyncInstructions(h)` contains the
  stdout-only sentence, and so does `pollInstructions(h)` **with the `behindSyncInstructions(h)` text
  removed from it** (it embeds that text, so a whole-string assert could not see a missing `harness.ts`
  sentence). The test iterates the union; it does not use a hand list. A mutant that deletes only the
  `harness.ts` sentence reds it.
- [ ] AC6b — `python3 scripts/lint-skill-body-budget.py --base origin/main` passes and ship/SKILL.md ends
  at least 50 B under its ceiling (`jq .ceilings.ship plugins/soleur/test/skill-body-budget.json` minus
  `wc -c < plugins/soleur/skills/ship/SKILL.md` ≥ 50).
- [ ] AC7 — `bash plugins/soleur/test/sync-pr-behind.test.sh` passes, including the standalone hint row: right branch, hint on stderr → no `kind=wrong_branch`.
- [ ] AC8 — `bash .claude/hooks/ship-operator-step-gate.test.sh` passes, including the hint row.
- [ ] AC9 — `bash .claude/hooks/ship-kb-archive-gate.test.sh` passes, with every Guard 1 matrix row and
  harness row present by name and T1–T82 unchanged. Every `--auto` arm span extracted from the
  `arm-check-sites.test.sh` SITES plus CANON, and the admin-hatch span, is **allowed** on an archived
  KB and **denied by the census** on an unarchived one (row 5). `bash plugins/soleur/test/arm-check-sites.test.sh`
  still passes after the dequeue doc edit.
- [ ] AC10 — Guard 2 scan: zero unexcluded violations on the tree, zero stale exclusions, and the
  floor of at least 10 scanned files holds. Harness rows H-a/H-b and mutation rows 1–5 behave as stated.
- [ ] AC11 — `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-11-28-fix-ship-poll-stderr-missing-check-kb-gate-plan.md` exits 0 and reports 2 entries.
- [ ] AC12 — The learning file exists at the path in Files to Create, with sections for all three defects, the interlock, the before/after gate table and `## Session Errors`. The 2026-11-25 learning carries the dated follow-up line.
- [ ] AC13 — The PR body carries `Closes #12697` and `Closes #12963` (body, not title) and `Ref #13115`. The diff contains no path under `docs/`, no legal document, no workflow file and no approval-queue flag change: `git diff --name-only origin/main...HEAD | grep -E '^docs/|^\.github/workflows/|legal' ` prints nothing.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** The CTO ruled all four forks (see `knowledge-base/project/specs/feat-one-shot-ship-poll-stderr-missing-check-kb-gate/decision-challenges.md`):
F1 stdout-only capture with a per-poll stderr file and a combined trap, across the poll family plus the
cosmetic sites; F2 no new arm, with reachability pinned by fixture rows and the poll never running a
rerun itself; F3 hook-side, narrowed to a bare number plus one double-quoted simple expansion, and
identical-invocation acceptance compared on both the raw and the stripped residues; and the
cla-evidence concurrency fix out of scope as #13115. Risks the CTO named are carried into Sharp
Edges: the fixture fingerprint and parity tokens, a second EXIT trap replacing the first, regression
of the pattern, and this PR's own arm step still hitting the old gate.

No other domain is implicated. This is tooling inside the operator's merge path, with no user-facing
surface, no copy, no pricing, no legal text and no infrastructure. The Product/UX gate is NONE: no
UI-surface file appears in Files to Edit/Create.

## Test Scenarios

- Given `gh pr view` prints the 9-line hint on stderr and `OPEN BLOCKED` on stdout (rc 0), with the PR armed, not queued, the verdict full-decided and the required-set stub `state=absent`, when the fence runs, then it exits on `[ship.phase7.required_set] state=absent` and the required-set stub was called once. (integration: fixture H1)
- Given the same hint with `OPEN BEHIND`, when the fence runs, then it auto-syncs once and prints `auto-sync 1 pushed`. (integration: H2)
- Given the hint with `OPEN CLEAN` and a dequeue on the queue-state read, then `[ship.phase7.dequeued]` within 5 ticks. (integration: H3)
- Given `gh pr view` exits 1 with the hint plus `HTTP 502` on stderr, then the state line is `fetch-error: HTTP 502` and the poll breaks. (integration: H4)
- Given H1–H3, then no stdout line starts with `hint:` and every state line matches the state-line shape. (integration, in-row)
- Given `gh pr view` exits 1 with only the hint on stderr, then `fetch-error: rc=1`. (integration: H4b)
- Given `mktemp` fails at entry, then the poll still parses state, nothing leaks and `/dev/null` is intact. (integration: H6)
- Given a merged stream (the fixture hint then `OPEN BEHIND`), `parsePrPollStdout` returns `null`. Given clean stdout, it returns the state. (unit)
- Given every arm span extracted from the arm-check-sites SITES plus CANON, and the admin-hatch span, with the PR-number token replaced by the fixture PR number, on an archived KB, when the hook runs, then each is allowed. On an unarchived KB each is denied by the census. (integration: Guard 1)
- Given each Guard 1 mutation input, the hook denies. Given H-b/H-c, it allows. (integration)
- Regression: the incident shape (PR #13017: cancelled `pull_request_target` run on the final head, required context absent) is H1.
- Regression: #12697 / #12963 — `gh pr merge <N> --squash --auto --match-head-commit "${H:?run the arm check in this call}"` inside `with_lock merge-main 600 --` and the degrade-open `else`, allowed.

## Dependencies & Risks

- **This PR's own merge runs on pre-fix machinery** (CTO risk 4). Hooks run from
  `$CLAUDE_PROJECT_DIR/.claude/hooks` and the skill text from the installed plugin. Until this PR lands,
  either may be `main`'s copy, so expect the documented arm block to be denied at this PR's own arm step,
  and expect this PR's own Phase 7 poll not to auto-sync a BEHIND reading. For this PR only, arm with the
  measured-accepted form, `bash "$SS_LIB" with_lock merge-main 600 -- gh pr merge --squash --auto
  --match-head-commit <40-hex>` (flag-only, lock kept), run from the PR worktree after the arm check. If
  BEHIND stalls, sync by hand with the standalone script. The fix is proven by the test suites in CI;
  on a live merge it is proven by the first PR that ships after this one.
- **Fixture parity tokens and the single EXIT trap** (CTO risks 1–2): covered in Phase 1 and AC2.
- **Gate widening** is a threat-model change (2026-11-25 learning). The residuals paragraph states the
  argument, and Guard 1 rows 2–3 and 5 are the mutants that would catch a too-wide rule.

## Sharp Edges

- `deepen-plan` Phase 4.6 halts on an empty, stub-only or threshold-less `## User-Brand Impact`
  section. This one is filled (`none`, with reason).
- `2>"$GH_ERR"` truncates per call. Do not switch it to `2>>`, which would mix ticks into the
  `fetch-error:` text.
- The fixture's `gh` stub prints `fixtures/gh-pr-view-hint.txt` on stderr **before** stdout, rc 0. A stub
  that prints it after stdout, or on stdout, tests nothing (`2026-09-25-gh-stub-must-mirror-real-cli-flags.md`).
- Rule (i)'s PR-number class is `^[0-9]{1,9}$`, so an all-digit 40-character operand is never a PR number.
- Rule (ii) compares raw **and** stripped residues. Comparing only the stripped set admits a merge
  hidden in a quoted operand (Guard 1 row 2).
