# Learning: a fail-closed CI branch reds every runner that runs the suite, and uncommitted review fixes die with the worktree

## Problem

PR #11260 (the LUKS key-continuity probe) went through an 11-seat review, a 3-seat fix round and a 1-seat verification pass. Four patterns cost the most time, and three of them were defects I introduced while fixing findings.

1. **Fail-closed in one workflow, provisioned in one.** The test-design panel found that the probe suite's real-tool arm skipped green in CI when `cryptsetup` was absent (the count pin shrank to match). I made the arm FAIL under `CI` and added `cryptsetup-bin` to `infra-validation.yml`. The suite is also run by `main-health-monitor.yml`'s `test-infra` leg, which I did not touch; two fix-round seats found it independently. Without them the first scheduled monitor run after merge would have filed a main-red tracker.
2. **Two repo-wide lints that cannot both be satisfied by the obvious edit.** `lint-shell-trace-credential-refusal` (CI) demanded that the xtrace refusal test every credential name the file references, so I added `${INNGEST_REDIS_LUKS_KEY:+x}`. `doppler-injection-bound.test.sh` then read that expansion as a read of the secret and demanded the name be added to `--only-secrets`, which would put the passphrase in the process environment. My first fix exempted the NAME globally; the security seat showed any later real read of the key would be hidden. The correct exemption removes only the presence-test SHAPE before the read scan.
3. **The worktree vanished mid-review.** The directory disappeared (second time this session; the planning agent's worktree went the same way). The branch and remote were intact, but every uncommitted fix was gone. I re-applied them from patch scripts and from the seats' reports, and committed after each batch from then on.
4. **Cheap gates were not run before the panel.** `lint-shell-trace-credential-refusal`, `grep-q-pipe-guard.test.sh` and markdownlint were red on the reviewed head; seats found them (two as P1) instead of the lead running them first. The review skill already documents this ("run the cheap deterministic gate BEFORE the panel"), and it recurred.

## Solution

- For every new fail-closed branch in a suite, `grep -rn 'run-registered-suites.sh\|TEST_GROUP' .github/workflows` and provision the tool in EVERY workflow that runs it, plus an `command -v` assert in that workflow's toolchain step.
- When a lint demands a name appear in a file, scope any exemption in the sibling check to the exact shape the lint forced (a regex on `${NAME:+x}`), never to the name.
- Commit each fix batch locally as it lands (branch refs live in the shared git dir, so a local commit survives worktree loss); push only when the suites are green.
- Write patch scripts with the Write tool, not shell heredocs: a heredoc whose body contains a second heredoc ends at the inner marker, and the shell then executes the rest of the body as commands.
- Run the repo's deterministic lints (`lint-*`, `.claude/hooks/*.test.sh` guards, `scripts/markdown-lint.sh` on changed `.md`) on the combined tree BEFORE spawning seats.
- Do not change a pre-existing attribution (an issue number in prose) on a seat's claim: run `gh issue view` first. The history seat's `#6218` was a PR number for the cutover workflow, not the heartbeat; the original `#8054` was right.

## Key Insight

A fix that tightens a check moves its failure to the places that were relying on the check being loose: other runners, other lints, other readers of the same name. The fix is not finished until you have enumerated those consumers; the review round that follows is where you will otherwise find them.

## Session Errors

- **Planning subagent's worktree vanished mid-session** (forwarded) — Recovery: it rebuilt plan, tasks and rulings from its transcript — **Prevention:** commit the plan skeleton early (#7420); comment added on #11099.
- **PR worktree directory removed during the review fix round, uncommitted fixes lost** — Recovery: `git worktree prune`, re-add from the intact branch, re-apply from patch scripts — **Prevention:** commit locally after every fix batch; tracked by #11099 and #11162.
- **Nested `PY` heredoc inside a Python heredoc** ended the outer one early; the shell ran patch lines as commands and left the cwd outside the worktree — Recovery: verified nothing was written, redid the patch from a file — **Prevention:** write patch scripts with the Write tool, never a heredoc that contains a heredoc.
- **Edits to `inngest-cutover-flip.sh` broke literals the suites pin** (status argv, the G2-4 mutant anchor, count pins, the command-position sweep flagging `PIPESTATUS`, `local -a`) — Recovery: updated the pins and the sweep's built-in exemptions — **Prevention:** after editing a script, grep its suites for the edited literals before running them.
- **xtrace-refusal lint versus read-set check** — Recovery: exempt only the `${NAME:+x}` shape — **Prevention:** scope exemptions to the shape a lint forces, not the name.
- **First read-set exemption was global** (fix-introduced, found by the security seat) — Recovery: regex on the presence-test shape — **Prevention:** same as above.
- **CI fail-closed branch provisioned in one workflow only** (fix-introduced, found by two seats) — Recovery: added the install and assert to `main-health-monitor.yml` — **Prevention:** the bullet added to the review skill's fix-round reference (`references/risk-tier-and-fix-rounds.md`).
- **Rewrote a C4 attribution on an unverified seat claim** — Recovery: the verifier refuted it; reverted to `#8054` — **Prevention:** `gh issue view` before changing an attribution.
- **Stale mutant anchors and a surviving G4-2 mutant** (the stub logged before its early exit, so `tr` won the race) — Recovery: re-anchored; moved the stub's early exit to its first line — **Prevention:** after changing the text a mutation anchors on, re-run the battery and require every row to land.
- **Cheap repo-wide gates not run before the panel** — Recovery: fixed the reds the panel found — **Prevention:** already in the review skill; run them first.
- **Briefs and filings blocked by hooks, scan misreads of `gate:` and "status flips"** (earlier in the session) — Recovery: Write-tool briefs, literal paths, reworded prose — **Prevention:** already recorded in the plan-phase learnings.

- **Alert `check_period` 300 over `query_period` 10800 passed every offline gate and was refused at the merge apply** (Better Stack 422 "too resource intensive"; the exploration was created, the alert was not, and every later merge's apply then failed on it) — Recovery: `check_period = 900` (12x) in a follow-up PR — **Prevention:** before choosing a new alert's periods, take the largest `query_period / check_period` ratio among the accepted siblings in `betterstack-logs-alerts.tf` (27x then) and stay below it; offline tests and `terraform plan` cannot see this vendor-side limit.

## Tags
category: workflow-issues
module: review, infra
