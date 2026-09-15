---
title: The anchor was read from the object it protects, and my guards pinned step content, not the wiring between steps
date: 2026-09-15
category: security-issues
module: git-data (ADR-220, #8189)
tags: [custody, terraform, github-actions, guards, mutation-testing, doppler, fan-out]
issue: 8189
pr: 8206
---

# Learning: a custody boundary measured nominal, and guards that pinned content instead of wiring

## Problem

#8189 delivered the git-data root SSH key: a separate Terraform root minting the key, an isolated Doppler
project, a reviewer-gated read, a committed SHA256 fingerprint checked at every git-data create, and a
read-only, fail-closed cutover proof. Four lessons came out of planning and a 12-seat review, and each
one is about a check that reads as protection while protecting something narrower.

1. **The custody boundary was nominal before any code was written.** ADR-220 D2 wanted "only a
   reviewer-gated job on `main` can read the key". Measured: any branch workflow can name the
   `DOPPLER_TOKEN` repo secret, which reads `prd_terraform`, which holds `DOPPLER_TOKEN_TF` (workplace
   scope), `CF_API_TOKEN_R2` (every state object, including the new root's plaintext private key) and
   `HCLOUD_TOKEN`. A reviewer-gated GitHub environment is a human gate on `main` bytes, never a secret
   boundary. The separate root still buys something real (the key never enters the web-platform
   root that dozens of jobs print from), but not custody. Filed as #8209 with both reach paths.
2. **A wrong-scope token's error read as "unset".** The old `read_flag` used a `prd_terraform`-scoped
   token to read `GIT_DATA_STORE_ENABLED` from `prd`; the scope error went through `|| echo ""` and became
   "flag unset", the reassuring answer. Measured Doppler CLI v3.75.3: `--no-exit-on-missing-secret`
   makes an absent secret exit 0 with empty stdout, while a bad config exits 1. The fix fails closed on
   rc and classifies stderr into fixed words, and it proves scope positively: the same token must
   read `DOPPLER_CONFIG == prd` and `DOPPLER_PROJECT == soleur`. A token bound to another config would
   otherwise read a missing secret as "unset" again.
3. **The anchor was read from the object it protects.** The committed fingerprint exists because a
   Hetzner key object's name and label are forgeable by any `HCLOUD_TOKEN` holder. The first
   implementation printed the fingerprint by listing Hetzner keys by that forgeable label. Five
   review seats caught it independently. The value now comes from Terraform state
   (`tls_private_key.public_key_fingerprint_sha256`, `SHA256:<base64>`, the same form `ssh-keygen -l -E
   sha256` prints) and must equal the Hetzner-derived value. Separately, Hetzner's own `fingerprint`
   field is MD5 colon-hex, so the gate derives SHA256 from `public_key` and never compares the vendor
   field.
4. **The guards pinned each step's CONTENT and never the WIRING between steps.** Both P1s, plus three
   P2s, had this shape. The root-key suite executed the real allowlist step bytes against synthesized
   plan JSON, yet adding `continue-on-error: true` to the allowlist or `if: always()` to the apply left
   it 104/0: the refusal no longer stopped the apply. The fingerprint check was fully tested, yet
   deleting or re-pointing the `GIT_DATA_ROOT_KEY_FINGERPRINT_FILE` export in both gate steps left every
   suite green, because each suite exported the variable itself. The same held for a step's `env:`
   mapping (`ROTATE_RAW`), a notify job's `if:` checked by substring, and cutover step gating.
   test-design-reviewer found them by mutating the GATING, not the content.

## Solution

- Pin wiring explicitly: no `continue-on-error` on a refusal step or the step it gates, no `if:`
  from the refusal through the mutation, exact (not substring) `if:` comparison on notify jobs, and the
  step `env:` mapping of every executed body. A mutation row for each.
- Pin a producer-to-consumer env wire from the workflow side: exactly one export of the literal path,
  before the call, in each job, with delete, re-point, move and reassign mutants.
- Read an anchor from the artifact that minted it (Terraform state), and treat the forgeable listing
  only as a second value that must agree.
- Make an additive-only apply mean it: creates limited to the root's own addresses (derived from its
  `.tf` files in the test), importing and moved refused, a re-mint refused once the anchor file exists,
  and no rotation exception (a rotation is a reviewed PR adding a typed arm for exactly its addresses).

## Key Insight

For every guard, ask two questions. First, *can the next step still run when this refuses?* That is
the wiring. Second, *where does the value I compare come from, and can the adversary this guard
exists for write there?* That is the anchor's source. A suite that executes the real step bytes
answers neither: content tests prove a step decides correctly, never that its decision is obeyed.

## Session Errors

1. **Provider-verification subagent ended twice without a report (planning).** Recovery: the checks were
   run directly (schema read, scratch plan-JSON, Doppler CLI probe). **Prevention:** give research
   subagents "your final message IS the deliverable" at spawn time, not on resume.
2. **The IaC plan-write guard blocked a Research Insights write containing verb tokens (planning).**
   Recovery: rephrased without the tokens, no opt-out. **Prevention:** none needed; the guard worked as
   designed.
3. **`lint-guard-contract.py` failed on prose mutation matrices (planning).** Recovery: converted to
   tables. **Prevention:** write Guard Contract matrices as tables from the first draft.
4. **(Carried from #8187) The fixture-relative ratchet went red on new relative-root write sites.**
   Recovery there: a code fix, not the baseline. **Prevention:** run
   `python3 plugins/soleur/test/lib/fixture-scan.py --rule relative --repo .` and
   `bash plugins/soleur/test/fixture-relative-assert.test.sh` on any new shell write site before push.
5. **(Carried) A local battery launched INSIDE a Monitor script died when the Monitor expired.**
   **Prevention:** launch from a Bash call with `setsid nohup`, and watch rc files from a separate Monitor.
6. **(Carried) The PR body said "merging applies no infrastructure"; true of the diff, false of the
   merge.** **Prevention:** phrase it as "this diff changes Terraform code; merging fires only the
   web-platform push apply, whose `-target` set does not include `hcloud_server.git_data`", then read
   the push apply's Plan line after merge.
7. **(Carried) CodeQL - Code Quality (non-required) failed at SARIF upload on a GitHub-managed run that
   cannot be retried.** **Prevention:** record it and do not chase it; it is not a merge gate.
8. **Error 4 recurred here despite the carried prevention: 15 new relative-root write sites across four
   suites, written by parallel fan-out agents whose briefs listed only their own suites.** Recovery:
   a dedicated fix agent added `assert_fixture_dir` guards (62/0, baseline unchanged). **Prevention:**
   every fan-out brief that creates or edits a `*.test.sh` or a `tests/scripts/lib/*` file lists the
   repo-global ratchets in its validation (routed to `work-subagent-fanout.md`).
9. **`echo "$(basename "$t") rc=$?"` reported rc=0 for a suite that printed 2 failed.** The command
   substitution resets `$?`. Recovery: re-read the failure lines. **Prevention:** already documented in
   `work/SKILL.md`; capture `rc=$?` on its own line before any expansion.
10. **The guards pinned step content, not wiring (Problem 4): two P1s.** Recovery: wiring rows and
    mutants. **Prevention:** a review defect-class bullet (routed to `review/SKILL.md`).
11. **The printed fingerprint was read from the forgeable object (Problem 3).** Recovery: read it from
    state and require equality. **Prevention:** the same review bullet asks where a compared value comes
    from.
12. **Three repo-global ratchets went red only in the full `TEST_GROUP=scripts` shard:
    `guard-vacuity-floor` (deferral ledger 47→49), `lint-trap-tempfile-ownership` (an `mktemp` with no
    owning trap) and `plan-gate-preamble` (a lib that grades a plan but is not named `*gate*`).**
    Recovery: covered the suites, removed the tempfile (`ssh-keygen -l -f -` on stdin) and renamed the
    lib. **Prevention:** documented in `work/SKILL.md` (a file-selected suite set cannot see a
    repo-global ratchet); the fan-out bullet in error 8 now names these three.
13. **A review fix introduced a new ratchet red: the TMPDIR guard kept the `mktemp`.** Recovery: removed
    the tempfile entirely. **Prevention:** same as 12. A fix touching a shared lib reruns the ratchets,
    not only its own suites.
14. **After `kill_mine test-all.sh`, the `setsid` runner script advanced to its next stage; the new
    `test-all.sh` and `flock` children were reparented to `systemd --user` and survived.** Recovery:
    killed by captured pid after resolving `/proc/<pid>/cwd`. **Prevention:** kill the RUNNER SCRIPT
    first, then its children, and re-enumerate by cwd (covered by the existing `work/SKILL.md` "stopping
    means killing the tree" bullet).
15. **A Monitor poll used `pgrep -f "$D/run.sh"`, which matches its own `bash -c` wrapper, so its
    "runner gone" arm could never fire.** The Bash hook blocks `pgrep -f`; the Monitor tool is not
    covered. **Prevention:** in Monitor scripts, detect completion from rc/marker files only, never
    `pgrep -f` (routed to `work/SKILL.md`).
16. **`git stash list` was blocked by the stash hook while probing.** **Prevention:** use
    `git rev-parse --verify --quiet refs/stash` (already documented).
17. **Plan claims measured false during work:** the heartbeat probe "runs `git ls-remote`" (it is
    `nc -z` to `:22`), "web-2 retired (#6538)" (still in `var.web_hosts`), AC3's literal grep could never
    return nothing, and the Phase 0.6 sweep missed `git-data-luks.test.sh`. Recovery: appended
    reconciliation sections to the plan. **Prevention:** already covered (plan-quoted claims are
    preconditions to verify).
18. **A fix agent ended its turn with "Waiting for the cutover-access suite to finish".** Recovery:
    resumed via SendMessage. **Prevention:** put "do not end your turn while a command whose result you
    need is still running" in every long-running brief.
19. **Both touched shards were refused (rc=4, sibling full-gate run), then queued about 30 minutes behind
    two other worktrees.** Recovery: cancelled local runs, relied on targeted suites plus CI's required
    `test`. **Prevention:** environmental; `bash scripts/test-all.sh --capacity` before launching.
20. **The plan's read-token rotation exception contradicted ADR-220 D3's key-rotation path (four seats),
    and it accepted delete-only or no-op "rotations".** Recovery: removed the exception; rotation is a
    reviewed PR. **Prevention:** for any allowlist exception, fixture the degenerate plans (delete-only,
    all no-op) in both directions at plan time.
21. **AC12's literal grep ("returns nothing") conflicted with restoring dated ADR text as append-only.**
    Recovery: amended AC12 in the plan. **Prevention:** a sweep AC over a dated record asserts "no LIVE
    claim", classified per hit, never a zero count.
