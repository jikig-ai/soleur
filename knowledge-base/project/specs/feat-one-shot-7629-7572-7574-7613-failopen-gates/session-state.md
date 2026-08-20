# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-20-fix-close-four-fail-open-gates-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Scope verified: `git diff origin/main...HEAD --name-only` shows only `plans/` + `specs/` — no source, workflow, or CHANGELOG edits.
- Post-plan collision re-probe: plan `closes: [7629, 7572, 7574, 7613]` is identical to the Step 0a.5 set; no re-targeting, no new refs to probe.

### Errors
- `gh` API returned `TLS handshake timeout` twice during planning; both retried successfully, no data loss.
- `git log --format='%G?'` reports `N` locally because `gpg.ssh.allowedSignersFile` is unset for local *verification*. Commits ARE signed (`gpgsig` present in the raw objects).
- Parent found a repo-scoped `commit.gpgsign=false` in `.git/config` overriding the global `true`; the override was removed so signing takes effect. Not a subagent error.
- First plan draft shipped three guards that could not be driven RED; caught by the review panel and fixed before finalizing.

### Decisions
- Both operator constraints honored. #7629's harness is two ordered steps with the RED proof as its own deliverable, asserted from git history (`git log --diff-filter=A` on the harness yields a SHA whose `git show --name-only` contains no workflow path). #7613's eight `.code.sh` consumer arms are enumerated by name — R3(1)/(2)/(2b)/(2c) over `luks-stage.code.sh`; R3(3b)/(3c)/(3d)/(2d) over `runcmd-all.code.sh` — with a RED and a GREEN for each.
- The #7613 stripper is a measured no-op (0 surviving trailing comments in the luks stage, 1 in the whole runcmd concatenation on a line no predicate reads). Per-arm budget moves to the anchoring work, which does re-flow all eight arms; stripper retained per operator direction but re-labelled prophylactic. Recorded as a user-challenge for `/ship` to surface.
- Two issue-body suggestions reversed on evidence: #7572's "replace `_SKIP_CEILING` with a grep of the call sites" makes the assertion a tautology (AP-023) and reverses ADR-188; #7613's "the suite already contains a correct stripper: `_b2_strip`" is false for this use (its zero-width prefix destroys `${var#pat}`, `$#`, and `#`-in-string).
- #7629 grew from two fail-open sites to six, including one previously unnamed: the scan loop's `continue` arms let `no_new_skills=false` produce zero verdicts and still exit 0.
- #7574's observer needed a new carrier, not a new mechanism — the existing probe is inert (`grep -q` + `pipefail` scores a successful match as a miss) and the follow-through sweeper closes on PASS then refuses to re-litigate. Carrier moves to a standing daily monitor.
- No new ADR: two amendments (ADR-152, ADR-188) instead.

### Components Invoked
- soleur:one-shot (Steps 0b/0c: worktree from origin/main @ 08d12eec8; draft PR #7653)
- Skill: soleur:plan -> Skill: soleur:deepen-plan (isolated general-purpose subagent)
- Agents: repo-research-analyst, learnings-researcher, kieran-rails-reviewer, code-simplicity-reviewer, spec-flow-analyzer, architecture-strategist, scoped strong-model consult
- Gates: lint-guard-contract.py (9 entries, green), lint-infra-no-human-steps.py (green), deepen-plan halts 4.5-4.11 (all pass; 4.5 fired on keywords, assessed false-positive and recorded)

## Known Hazard (cross-session alert, 2026-08-20)
`plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh` can commit fixture branches into the live checkout: `set -uo pipefail` (no `-e`) at line 10, silenced `git worktree add ... >/dev/null 2>&1` at lines 49/585/796, and bare `( cd "$WT.../feat-victim"` with no `&&` at lines 50/586/797. Fix is `5ecd6d71a` on branch `feat-one-shot-7580-7553-vacuity-floor-subagent-gate`, NOT yet on origin/main. A whole-commit cherry-pick is NOT clean — it also carries that PR's own subject matter (`fanout-suite-scope.test.sh`, `guard-vacuity-floor.test.sh`); only the 44-line `lease-protects-active.test.sh` hunk is the safety fix. Re-check before running `test-all.sh` at the pre-push gate.

## Work Phase
- Status: complete (all four issues implemented, RED then GREEN, each measured on a full run)

### RED -> GREEN, measured
| Issue | RED | GREEN |
|---|---|---|
| #7629 | 12 passed / 7 failed | 19 / 0 |
| #7574 | 3 / 4 | 9 / 0 |
| #7572 | 49p / 4f (53 assertions) | 58 / 0 (58) |
| #7613 | 61p / 7f (68 assertions) | 68 / 0 (68) |

AC2 (#7629 RED-before-GREEN) holds structurally: `git log --diff-filter=A` on
`scripts/skill-security-scan-step-body.test.sh` yields 042277242, whose
`git show --name-only` contains zero `.github/workflows/skill-security-scan-*` paths.

### Gates
- `TEST_GROUP=bun`: rc=0, 7/7 suites passed.
- `TEST_GROUP=scripts`: first run rc=1 (328/334) -> two real findings in this PR's own new
  code, both fixed (see below); clean re-run in progress at time of writing.
- `apps/web-platform/infra/run-registered-suites.sh`: run explicitly, because the `scripts`
  shard's own coverage NOTE states it excludes `apps/web-platform/infra/` and this diff
  touches that directory.
- Rehearsal suite run directly 9 times across RED/GREEN cycles.

### Repo gates that caught defects in THIS PR's new code
- `alarm-issue-filing-guard`: the new monitor's alert step inherited `success()` and would
  skip after any earlier failure — the alarm silent exactly when something went wrong. Fixed
  with `!cancelled()` (not `always()`, which is true on cancellation and the step mutates
  state). Baseline NOT raised; it ratchets down only.
- `lint-diagnosis-claims`: postmerge.yml asserted the bypass happened "via admin merge or
  force-push", a cause the job never measures. Pre-existing text made newly detectable by the
  restructure; message fixed rather than baseline raised.

### Deferred (filed at ship, not fixed here)
- `run-scan.sh` hangs indefinitely on a nonexistent POSITIONAL file (waits on stdin). NOT
  reachable from either gate — both invocations are `< "$path"` behind an `-f` guard.
  Different subsystem; a discovered defect, so it stays its own issue.
- #7572's plan-named scope-out: T17's and R1's `|| true` rc discards and `run_case()`'s
  `exit 100, expected 0` misclassification. #7572's own body says `run_case`'s defect "has a
  different defect worth its own measurement".

### Borrowed, not owned
`plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh` carries the cd-guard
from 5ecd6d71a (branch feat-one-shot-7580-7553-vacuity-floor-subagent-gate, unmerged). That
suite can commit fixture branches into the live checkout and is reached by the SUITE_GLOBS
loop inside `want_scripts` — the exact shard this PR's two new suites live in — so the branch
could not be verified without it. ONLY that file's 44-line hunk was taken, not the ~250 lines
of that PR's own subject matter. Drop in favour of the sibling's version if theirs merges
first; the content is identical.

### My own measurement errors this session, recorded
1. First #7574 RED was vacuous: 3-line fixtures fit inside the 64 KiB pipe buffer, so no
   SIGPIPE, so 6/7 green against an intact defect.
2. #7629 harness G1.3 was a false RED: `${arr[@]@Q}` interpolated into a Python list becomes
   adjacent string literals, which Python concatenates.
3. S1 structural guard used `grep -qx` against the driver FILE, where the marker sits inside
   `echo "..."`.
4. S1 residual guard used `(?!MUTATION)` (POSIX ERE has no lookahead) AND `grep -c` prints 0
   while exiting 1, so `|| echo 0` compared against "0\n0".
5. Guard 5(a) reported two byte-identical corpora as different: `sed` terminates its last
   line, `"\n".join()` does not.
6. R3(2)'s control asserted a violation its fixture never created — it failed IDENTICALLY in
   RED and GREEN, which is the tell.
7. Fixture B used `_luks_detail` where the arm derives `$_luks_detail`.
8. `actionlint EXIT=0` was read from `$?` after a pipe to `head`. Measured properly,
   actionlint exits 1 on origin/main too with an identical per-rule breakdown.
9. "4 positional run-scan.sh invocations" counted my own error-message prose.
