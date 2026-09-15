---
title: "My access gate proved a different argv than the steps it gated, and my rollback reported green over a recovery that ran nothing"
date: 2026-09-15
category: security-issues
module: apps/web-platform/infra/git-data-cutover.sh
tags: [guard, access-gate, ssh, rollback, fail-closed, mutation-testing, never-run-workflow]
issue: 6680
pr: 8187
---

# Learning: a gate must prove the exact inputs the gated steps consume

## Problem

`git-data-cutover.yml` had never run. Three walls were enumerated statically (bridge called
`terraform output` in a job with no terraform; the bridge exported `GIT_DATA_SSH` as the web-1
invocation, so `10.0.1.20` was unroutable; no CI key is authorized for root on git-data). ADR-220
chose an `ssh -W` jump through web-1 and a fail-closed `access_gate` that runs before any host
mutation. The live branch dry-run measured `web ok`, `git-data-jump ok`,
`git-data-auth git_data_root_key_absent`, exit 3.

The first implementation was green on a 49-row suite, a 31-row mutation battery and a live run —
and a 10-agent review still found three converged defects, all in the guard's ASSEMBLY rather than
its logic:

1. **The gate and the gated steps parsed the same inputs two different ways.** `access_gate` split
   `WEB_HOSTS` and `WEB_HOST_SSH` with `read -ra` (first line only, no glob expansion); every later
   loop used `for h in $WEB_HOSTS` and `$WEB_HOST_SSH "$1" "$2"` (all lines, word-split, globbed).
   `WEB_HOSTS=$'10.0.1.10\n-oProxyCommand=…'` passed the gate on its first line while the drain loop
   handed the second line to ssh as an option. The gate proved a property of an argv nobody dialed.
2. **A recovery that warns-and-continues is a green run over a failed recovery.** ROLLBACK-only mode
   annotated each failed step with `::warning` and exited 0 — and the new test ASSERTED `RC=0` with
   all three steps failing. Worse, the steps call `systemctl restart soleur-web.service` /
   `stop soleur-drain.service`, units that exist nowhere (the app is a docker container), so on the
   live system a rollback writes the flag off and reloads nothing.
3. **The recovery path depended on the transport it does not need.** The flag-off write is a Doppler
   call; the workflow's Run step was skipped whenever the SSH bridge failed, so a bridge outage
   blocked the one recovery write that needs no SSH.

## Solution

- `resolve_roster` parses `WEB_HOSTS` and both invocations ONCE (multi-line and option-shaped
  inputs recorded, never dialed); `access_gate`, `gd_ssh`/`web_ssh` and every loop read that one
  result. The divergence class is removed rather than validated twice.
- `recovery_warn` increments a counter; ROLLBACK-only exits 4 when any step failed; a partial freeze
  release keeps `FREEZE_HELD` so a later abort retries it.
- The Run step's `if:` admits a rollback past a failed bridge but never past a failed
  confirm/Doppler/secrets step.
- Failed probe verdicts carry a fixed `reason=` word chosen by grep over the captured stderr
  (`forward_refused`, `connect_refused`, `timeout`, …) — diagnosable from the unauthenticated
  annotations API without printing probe bytes.
- The suite gained DRY_RUN=0 forward rows, shimmed `timeout`/stdin/argv pinning, digit-bearing
  option fixtures (an unanchored host regex accepted the old ones), exact annotation sets with
  `##[` and indented forgeries, a per-run token check, and an exit-0 trap. Battery v2: 49/49 killed.

## Key Insight

**A gate is only as good as the identity between what it inspects and what the guarded code
consumes.** Ask of every guard: *does it read its inputs through the same parser, the same
expansion and the same argv construction as the code after it?* If there are two parsers, the guard
certifies one and the system runs the other — and no mutation of either can reveal it, because each
is correct for its own reading. The fix is structural (parse once, share the result), not a second
validation.

The companion rule for recovery paths: **"exit 0 with warnings" is not a degraded success, it is
an unreported failure** — the run conclusion is the signal operators and agents read. And a
recovery step must never be gated on a dependency it does not use.

## Session Errors

1. **Plan write-guard blocked an Edit** on descriptive `ssh -J root@…` / `systemctl restart` prose (forwarded). Recovery: reworded. **Prevention:** describe probe commands in plans without their literal destructive-verb spelling.
2. **First plan draft over-built** (forwarded). Recovery: plan-review panel cut it. **Prevention:** existing plan-review gate; no change.
3. **`/soleur:go` readiness probe had an empty `CLAUDE_PLUGIN_ROOT`** (probe-unreachable). Recovery: ran `cleanup-merged` from the repo path per `wg-at-session-start-run-bash-plugins-soleur`. **Prevention:** none needed — the probe reported it by design.
4. **Brief listed #6733 as a git-data blocker**; it is a /workspaces cutover blocker. Recovery: re-classified from the issue body. **Prevention:** read each cited blocker's own file paths before tabling it.
5. **Filing hook refused #8189 twice** — `User-Impact:` named no user-surface taxonomy word, `Fix-Size:` was `>100`; the retry's per-component sum did not match its total. Recovery: named a component and a counted size. **Prevention:** write `Fix-Size` as a counted integer pair and check the arithmetic before filing.
6. **Bash CWD reset to the bare root** after a call that `cd /var/tmp`. Recovery: re-`cd`. **Prevention:** prefix every command with `cd <worktree> &&`.
7. **Runtime docker arm hung 10 minutes**: `WEB_OK=$(sshd_on …)` where `sshd_on` backgrounds `sshd` without redirecting its stdout, so the command substitution waited on the inherited pipe; the stale background notification then reported exit 0. Recovery: redirect the background child's stdout/stderr; bound `docker run` with `timeout -k 10 420` and `--name` + `docker rm -f`. **Prevention:** routed to work/SKILL.md shell-authoring traps.
8. **H5 false-failed on a trailing comment containing an apostrophe** (the stripper excluded quotes). Recovery: reworded the comment, then switched to whole-line stripping plus an explicit `(#.*)?$` tolerance on the call line. **Prevention:** existing `cq-assert-anchor-not-bare-token`.
9. **shellcheck notes and the xtrace-refusal lint debt on a baselined file surfaced post-commit.** Recovery: fixed and removed the stale baseline entry. **Prevention:** existing work Phase 0.5 check 6.5 — run it at Phase 0, not after the first commit.
10. **A battery row deleted the only line of a loop body**, producing a syntax error scored as a kill. Recovery: replaced with a well-formed `:` body. **Prevention:** existing work guidance ("a dispatch mutant must leave the program well-formed").
11. **Rebase conflict on generated `model.likec4.json`.** Recovery: took main's copy and regenerated. **Prevention:** none — generated artifacts conflict by nature.
12. **Three converged review P2s** (above). Recovery: parse-once roster, exit 4, rollback `if:`. **Prevention:** routed to review/SKILL.md defect classes.
13. **19 mutants survived** on axes battery v1 never edited (DRY_RUN=0, doppler argv, non-255 rc, timeout/stdin, digit-less fixtures, shape-matched annotation allowlist). Recovery: rows added; battery v2 49/49. **Prevention:** existing "audit the battery's AXES, not its count".
14. **Battery v2 crashed on a mutant's non-UTF-8 output.** Recovery: decode with `errors="replace"`. **Prevention:** decode subprocess output as bytes in mutation harnesses.
15. **Battery v2 contained a no-op mutant** (`set_flag … && true || …`, false SURVIVED) and a row whose anchor matched twice (not landed). Recovery: rewrote both. **Prevention:** existing "a surviving mutant is fixture-inadequate or equivalent — decide which".
16. **New step id `secrets` collided with the suite's own `secrets.` scan** (`steps.secrets.outcome`). Recovery: renamed to `secrets_check`. **Prevention:** none beyond running the suite after workflow edits.
17. **R4a raced the one-shot `nc` listener's restart** (a second confirming probe consumed it). Recovery: record the first success, settle, then probe. **Prevention:** one-off.
18. **A review agent's harness in the session scratchpad was swept** before it could be copied. Recovery: rebuilt the rows. **Prevention:** brief agents to keep harnesses under `/var/tmp`.
19. **The lead's docs brief prescribed `gh api` in a `discoverability_test.command`**, which preflight Check 10's verb allowlist rejects. Recovery: the agent used an unauthenticated `curl -sf`. **Prevention:** check `probe-verb-gate.sh` before prescribing a discoverability command.
20. **A plan claim "nothing drains, restarts or replaces a serving host" was false** once the bridge wall was removed (rollback now reaches web-1's reload calls). Recovery: corrected in the plan. **Prevention:** when removing a wall, re-read every claim that the wall made true.
21. **The cutover's freeze and reload target non-existent systemd units** (pre-existing). Recovery: filed as a blocker in #8189. **Prevention:** tracked in #8189.

## Tags
category: security-issues
module: apps/web-platform/infra/git-data-cutover.sh
