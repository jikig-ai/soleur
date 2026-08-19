# Resume prompt — PR-B #7546, the post-review fix pass

**This file SUPERSEDES the 2026-08-14 resume prompt** (the one that carried the "14 surviving
mutants" list). That list was worked to completion on 2026-08-16 and is closed. Two of its
instructions were REFUTED by measurement and must not be re-applied — see §REFUTED below. Keeping
the old prompt would re-introduce them, which is why it is overwritten rather than appended to.

Copy everything below the line into a fresh session.

---

/soleur:go Resume PR-B in the EXISTING worktree
`.worktrees/feat-one-shot-7104-apply-verify-repost-pr-b` (same-named branch, draft PR #7546).
Do NOT create a worktree or branch. Do NOT re-run the terraform plan. HEAD is `f4f956911`,
tree clean, everything pushed, 31 ahead / 3 behind `origin/main`.

This is a REVIEW-FIX pass. A six-agent panel ran against `2fdd9e285` and found the PR **NOT
SHIPPABLE**. Read
`knowledge-base/project/specs/feat-one-shot-7104-apply-verify-repost-pr-b/review-findings-2026-08-16.md`
FIRST — it is the work list, it is committed, and it carries every finding with file:line and the
exact mutation that proves it. This prompt is the orientation; that file is the spec.

Also read `session-state.md`, but treat its `### Decisions` as INTENT, not accomplishment.

## BINDING RULING (soleur:engineering:cto) — unchanged, do not re-litigate

**(C) sequenced A-then-B.** Ship the bounded recovery (this PR) first; the root-cause readiness
probe is Phase 2, filed as **#7576**, blocked on the first firing's forensics.

- The root cause is NOT established. `infra-config-apply.sh:80` does `rm -f "$STATE_FILE"` before
  any work, so a handler that ran and was killed leaves NO frame. Nonce-1 observed a *readable
  stale 13/13 frame* → the handler never reached that line. "Async handler exec was disrupted" is
  inference.
- A readiness probe cannot be a proof. `webhook.service` is `Type=simple`; the bootstrap ALREADY
  asserts `is-active` at `server.tf:164` and that PASSED during nonce-1; `StartLimitIntervalSec=0`
  + `Restart=on-failure` + the handler's `+3 s` self-restart reopen the window. Residual 6+3 = 9 s.
- Blast radius is inverted from the naive read. Phase 2's probe must be advisory-with-timeout,
  never blocking — a fail-closed condition in the SOLE no-SSH path for an unreplaceable host
  (cx33, 0/6 stock) is worse than the race.
- The ≥3-in-30-days trigger is NOT a merge blocker and must NOT be built (unfireable at n=1 in
  ~13 months).
- Do NOT delete the sensing/adjudication/actuation split.

## REFUTED — two instructions from the old prompt. Do not re-apply either.

1. **"ADR-189 → ADR-190" — DO NOT RENUMBER. Keep 189.** The 7341 branch did claim 189
   (`5df0ab917`) and has since renumbered **itself** to 190. Re-derived across all `origin/*`
   refs: 187 = 7429, 188 = 7291, **189 = this branch, uncontested**, 190 = 7341, 191 = 7084.
   `origin/main`'s highest is 186, so all claims are provisional. Lowest free is now **192**.
   Task 10.3 stays OPEN — re-derive again immediately before merge; it moved twice in two days.
2. **"main-health-monitor infra step 15 → 20 min" — DO NOT CHANGE. 15 is correct.** Measured 8
   successful runs: 354/366/389/419/420/431/434/447 s. `roundup5(7.45 × 1.5) = 15`, floor 10 → 15.
   Reaching 20 needs an infra max above 10 min.

## DO NOT RE-DERIVE (measured; re-deriving costs a terraform plan or a live API sweep)

- The re-push plan replaces **exactly 1** managed resource, `terraform_data.deploy_pipeline_fix`
  (`delete,create`), `host_creates=0`. Measured against live prd state, read-only. **Do not re-run
  the terraform plan.**
- AC20 holds: the `DPF_REPLACED == "false"` arm is byte-identical to `origin/main`'s, **7269 B**,
  sha256 `83d8e73ee8518502` both sides. This licenses citing run **31714143720**; do not re-dispatch.
- The extraction body is **19,774 bytes / 240 lines** (file at commit `9c7a021b8` is 241 lines /
  19,794 B; minus the 20-byte shebang).
- Suite ordinal: **39 of 101** derivable (109 registered, 7 in subdirectories, 1 excluded).
- Eight sibling functions in `infra-config-gate.sh`, and only ONE (`infra_config_count_invariant`)
  is quiet-with-rc-as-verdict.
- `deploy-script-tests` basis re-derived to **581 s**; timeout moved 14 → 15 min.
- #7095 records a REVOKED baked token serving stale code with the site UP — not a bricked host.

## STATE — what is done and verified

Seven commits this pass, all pushed, all carrying `Co-Authored-By`. P0-3 shipped (a fourth
`recovered` reach mode with its own dedupe slot); the 14 surviving mutants from the old list are
closed; the correctness batch landed; 15 documented corrections applied; #7576 filed.

Last full verification, at `2fdd9e285`: gate **132/0**, verify **29/0**, red-alert **45/0**,
battery **22/22**, `run-registered-suites.sh` **101/101**, `TEST_GROUP=scripts` **310/312** (2
declined) rc=0, `TEST_GROUP=bun` **7/7** rc=0, actionlint rc=0, `lint-orphan-test-suites`,
`lint-workflow-errexit-capture`, `lint-guard-contract`, `test-infra-suite-registration` all clean.

**Those greens are exactly the problem.** The panel defeated three of this pass's own fixes while
both suites reported perfect green. Do not treat a green suite as evidence until the D1–D3 items
below are closed.

## WORK LIST — ordered. Full detail in `review-findings-2026-08-16.md`.

Work in this order; the first two are blocking and the next three are fixes to fixes.

1. **P0-A** — pass 2 lost the absolute `APPLY_START_EPOCH` pin
   (`infra-config-verify.sh:220-246`). Note the nuance: the host-clock-to-host-clock comparison is
   DELIBERATE, so the fix is not a naive AND — it needs the skew allowance and a DISTINCT
   `::error::`. Also add the missing fixture and bound the advance (a +1 s bump reads VERIFIED).
2. **P0-B** — a re-push that bricks the channel reports "the gate never ran". `id:` on the probe,
   a fourth `unreachable` arm, and change the predicate to `GATE_OUTCOME == 'skipped' || -z`.
3. **D1** — the loop-depth scanner does not strip `[[ ]]` spans; two balanced phantom lines restore
   #6594 at 132/0. Reuse the sweeper's stripper at `:627`; require `do`/`done` in command position.
4. **D2** — the tally's two producers are one `pass()` function. A real second producer must be
   structurally independent (count `^  PASS: ` from emitted stdout at teardown).
5. **D3** — the allow-list admits `awk` and `sed` (`system()`, `| "sh"`, `-e …e`, `-i`), and its
   token regex cannot see `/usr/bin/terraform`, `./x.sh`, `$TF`, or `> /etc/...`.
6. Ledger integrity; alert honesty (including the label the plan forbids); the `unadjudicated`
   re-arm posting a fabricated measurement onto #4804; the security reclaim asymmetry; the phantom
   ADR-072 precedent (register as AP-023 instead); the battery's dishonest omission list; the
   `G1_EXPECTED_REFERENCES` false-red generator.

Consolidate the **three** hand-rolled shell parsers into one `strip_noise` — their divergent
noise-stripping policies are the root cause of D1.

## TRAPS

Carried forward, each cost time:

- Don't edit while a suite/agent is reading the worktree — it invalidates their evidence.
- Spawn review agents REPORT-ONLY at panel scale; apply fixes yourself from one SHA.
- `pgrep -f <pattern>` matches its own command line — use `plugins/soleur/scripts/lib/proc.sh
  list_runs`.
- Verify the instrument before the finding.
- A python `.replace()` over a file whose declaration contains the literal rewrites the declaration.
- Commit each verified unit immediately.

New this pass:

- **A resume prompt is a snapshot, not an authority.** Two of the old prompt's instructions had
  gone stale in ~48 h, and one would have manufactured the collision it existed to prevent.
  Re-derive anything it asserts about OTHER branches before acting on it.
- **Never `git commit -m` a message containing quotes, backticks or parentheses** — the shell
  mangles or eats it. Write the body with the Write tool and use `-F`.
- **Never heredoc a file in the same Bash call as a hook-gated `gh issue create`** — a hook denial
  rejects the whole call, so the heredoc never runs and the retry fails `no such file`.
  `gh issue create` requires `--milestone` here.
- **`rm -rf "$var"` trips the guardrail** — it cannot resolve the variable. Use an explicit
  scratch path.
- **A suite reported green by a prior session may already be red.** `974a77c43` was recorded as
  DONE and verified; it had left a registered suite failing 28/2, because its verification measured
  an adjacent suite. Re-run the suites your diff touches before trusting any inherited count.
- **`test-all.sh` queues on an advisory lock** (`LOCK_WAITING`, 900 s) when a sibling worktree runs
  it. That is not a hang. Three foreign sessions were running it concurrently; do not kill them.
- A background task's completion notification reports the wrapper's exit, not the command's — read
  the rc FILE.

## THEN

Rebase onto `origin/main` (3 behind at time of writing; re-check). Re-run: both suites, the
battery, `run-registered-suites.sh` (that directory has **no required CI status check** — it is the
one half no gate covers), `actionlint`, `lint-orphan-test-suites`,
`lint-workflow-errexit-capture`, `lint-guard-contract`, `test-infra-suite-registration`, and the
`scripts` + `bun` shards. Then `/compound` → `/ship` → `/postmerge`.

`/ship` must: re-derive the ADR ordinal ONE more time, write a real PR body (it is still the
auto-created `WIP:` placeholder), and carry **`Closes #7104`** — #7104 is OPEN with
`closedByPullRequestsReferences: []`, so the PR-A/PR-B split still holds.
