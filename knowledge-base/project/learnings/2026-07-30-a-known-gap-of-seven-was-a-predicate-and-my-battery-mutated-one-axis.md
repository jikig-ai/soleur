---
date: 2026-07-30
category: test-failures
module: .github/scripts/test
issue: 7068
pr: 7072
tags: [guard-building-pr, mutation-testing, mutation-axes, known-gap-is-not-a-pin, shared-instrument, agreement-is-not-independence, void-ab-arm, grep-shim, stale-comment-sweep, timeout-attribution, perishable-evidence]
synced_to: [review, work]
---

# A "known gap of seven" was a predicate, and my battery mutated one axis five times

## Problem

#7068 registered seven infra test suites that ran in **no** CI job — invisible twice over: they
never ran, and they never reddened. The PR also added a bash-only fail-closed gate,
`.github/scripts/test/test-infra-suite-registration.sh`, into the `test-*.sh` auto-glob that
feeds `guard-script-fixture-tests` (REQUIRED, `merge_group`-triggered, path-filter-free) so the
next orphan could not appear silently.

I shipped that gate with a 5-row mutation battery reporting all-caught, 8 acceptance criteria
green by their literal commands, CI 7/7 `success`, and shellcheck clean. A five-lens review panel
then found a **P1 in the gate itself**, plus five comments of mine that asserted untrue things —
in a PR whose entire subject is comments that assert untrue things.

## Root cause

### 1. The battery mutated one axis, five times

All five rows mutated the **registration line**: delete it, reshape it to `run: |`, comment it
out, delete the excluded suite's invocation, add a trailing comment. None mutated the file's
**shape** (job membership, masking keys) or the suite **population** (adding or removing a
suite). The P1 lived in the unmutated axis.

The gate built a per-suite regex from the filename and matched the path verbatim, so it accepted
a `/`. `run-registered-suites.sh` derives with `[A-Za-z0-9._-]+`, which excludes one. So a new
suite in a **subdirectory**, registered perfectly, passed the gate and then never ran through the
local runner that both `work` and `ship` mandate as the infra exit gate.

Measured: adding `apps/web-platform/infra/newdir/zzz-parity.test.sh` plus a correct single-line
step gave `rc=0  all 95 suites registered`, with the runner deriving it **zero** times. That is
failure mode #2 **verbatim from the gate's own header**, and the gate printed an affirmative
all-clear on it.

### 2. "Known gap: these seven files" is documentation, not a pin

The gate's header disclosed the gap honestly — and framed it as a **closed set of seven**. It is
a *predicate on paths*, not a set. The 8th and 9th arrive green with no signal, and #7076 gets
harder to close with each one. That is precisely the accretion that produced the seven orphans
this PR existed to clean up: #7000 left seven → surfaced while working on #7025 → cleaned at
#7068. A disclosure that nothing enforces re-creates the class it describes.

### 3. Agreement across agents is not independence when they share an instrument

In an agent Bash session `grep` resolves to a **shim shell function**. The same gate measured
**~15s** under it and **136ms** with the real binary. Critically, a review agent's *independently
obtained* figure — "the per-suite form measures 1.2–1.9s, and a fork-free rewrite is a 12x win" —
was the **same artifact**: ~94 shim invocations at ~12ms each ≈ 1.1s. Two measurements agreed and
both were wrong, because they shared a distorted tool.

The existing rule ([[2026-07-27-my-refutation-measured-a-shim-and-my-safe-fixture-hid-12240-deletions]])
says *pin the binary*. This instance adds the corollary: **a concurring number from another agent
is not corroboration if it came through the same instrument.** Convergence raises confidence only
when the errors are independent.

## Solution

- **`KNOWN_UNDERIVABLE` pin + stale-entry check.** The seven subdirectory suites are now an
  explicit list; an 8th reds with a message naming the derivation gap and #7076, and a pinned
  entry that is no longer a tracked suite also reds — so the list must *shrink* as #7076 closes
  rather than silently licensing a gap that no longer exists. Mutation row M8.
- **One-pass extraction into associative arrays**, replacing the per-suite regex. This removed
  the escaping defect structurally (`${rel//./\\.}` escaped only `.`, so a legitimately
  registered `foo+bar.test.sh` produced a *false* message telling the author to add a step that
  already existed — fail-closed, but a lie), and made the gate ~7x faster and linear rather than
  quadratic in suite count.
- **Job-scoped `WF_CODE`** to `deploy-script-tests`, plus an assertion that the job carries no
  `continue-on-error:`/`if:`. A whole-file scan could not honestly say "runs in no CI job";
  relocating a step into the token-gated `plan` job measured GREEN.
- **`find` → `git ls-files`**, so a stray untracked fixture cannot red a required check.
- **A committed mutation harness**, `test-infra-suite-registration-mutations.sh`: a positive
  control, 10 RED arms each landing-checked against a pristine copy, 2 GREEN arms, and an
  assertion floor. 14/14, ~4s, never touches a tracked file.
- **`MIN_SUITES` floor in `run-all.sh`** — the gate applied a cardinality floor to its *input*
  while its own runner had none, so deleting a suite from the glob printed
  `ALL FIXTURE TESTS PASS` over a smaller set.
- **`timeout-minutes: 3` → `1`** on the plugin-seed step (see Key insight #4).

## Key insights

1. **Enumerate the AXES a mutation battery varies, not the row count.** N mutations of one axis
   is one mutation. Before crediting a battery — especially your own — list the axes: the line,
   the file's shape, the population, the environment. Extends
   [[2026-07-19-my-mutation-battery-was-green-and-it-only-measured-the-mutations-i-thought-of]],
   which covers fixture *shape*; this adds the axis-count framing for batteries.
2. **A "known gap: these N things" claim is a pin only if something REDS when N grows.**
   Otherwise it is a disclosure that licenses accretion. Convert it to an enumerated list plus a
   stale-entry check.
3. **When a PR BUILDS a verifier, its vacuities live in the verifier and fail OPEN** — strictly
   more dangerous than a bug in guarded code, because the bug certifies broken-as-fine rather
   than erroring. Treat the author's own green battery as a floor, and ask an adversarial reader
   to find the axis it missed rather than to re-run its rows.
4. **A timeout justified as ATTRIBUTION must win the race against the enclosing ceiling.**
   `timeout-minutes: 3` on a step API-measured at 0–4s, inside a job at 242–270s against a 480s
   ceiling: `270 − 4 + 180 = 446s` leaves **34s** — less than the branch's own 28s job spread. The
   *job* cancels first, at whatever step the clock reached, defeating the attribution the step
   ceiling existed to provide. Check the arithmetic against the enclosing ceiling, not just the
   Nx multiple.
5. **Require every arm of an A/B to exit 0, and print rc, before reading any number.** A
   self-guarding script's early-exit is the most fast-pass-shaped failure there is (see Session
   Errors #4 and #6 — I made this mistake twice in one session).
6. **A PR that makes an existing comment false owns that comment.** Sweep the CLAIM, not the
   file; and a commit whose subject *is* "I replaced the stale number with the measured one" is
   exactly when to grep for that number's siblings — mine fixed one block and missed another 260
   lines away in the same file.

## Prevention

- Ask of every guard-building PR: *which axis did the battery not vary?*
- Ask of every "known gap" comment: *what reds when this list grows?*
- Pin binaries (`env -i PATH=/usr/bin:/bin`) and assert `type -t grep` is `file` before any
  timing claim — and treat a second agent's agreeing number as the same measurement unless it
  came through a different instrument.
- For any `timeout-minutes` justified as attribution, compute `job_max − step + ceiling` against
  the enclosing ceiling and require the margin to exceed the job's own observed spread.

## Session Errors

Forwarded from `session-state.md` (pre-crash pipeline phases):

1. **The IaC-routing PreToolUse hook rejected the plan** over a `systemctl enable --now …` token
   that was a verbatim quote of an existing line cited as liveness evidence, not a prescribed
   step. — *Recovery:* `iac-routing-ack` opt-out plus a justification comment. — **Prevention:**
   when quoting an infra command as evidence, expect the routing hook to match it; carry the ack
   and the reason together.
2. **Three self-inflicted plan defects caught by the review panel:** an AC that returned `7` on
   the untouched repo (it counted the orphan report, whose indent matches the derived list's); a
   fabricated citation attributing acceptance criteria to an issue that has none; an inverted
   loopback risk analysis (a possible false *green* was actually a permanent false *red*). —
   *Recovery:* all corrected in-plan. — **Prevention:** verify every AC RED against clean `main`
   before trusting it, and never attribute criteria to an issue without reading its body.
3. **Two deepen trigger checks matched the plan's own negation prose** rather than real file
   rows. — *Recovery:* verified as false positives. — **Prevention:** a trigger grep over a
   document that *discusses* the trigger will match itself; scope to code rows.

This session:

4. **A void A/B nearly shipped a number.** I copied the old gate to `/tmp`, breaking its
   `BASH_SOURCE`-relative `REPO_ROOT`; it hit its own cardinality guard and exited 1 in ~20ms,
   indistinguishable from a fast pass, and I had redirected rc to `/dev/null`. I reported "my
   rewrite is 5x slower" and nearly wrote it into a code comment. — *Recovery:* re-ran with both
   arms at their real path depth and rc asserted: ~950ms → ~135ms, a ~7x speedup. —
   **Prevention:** require and PRINT rc=0 for every arm before comparing.
5. **grep-shim mismeasurement** (~15s vs 136ms), which also invalidated a review agent's
   concurring figure. — *Recovery:* re-measured under `env -i PATH=/usr/bin:/bin`. —
   **Prevention:** pin the binary and assert `type -t grep` is `file` before any timing claim.
6. **I repeated #4** twenty minutes later, running the mutated harness copy from `/tmp` for the
   assertion-floor test; rc=2 was a setup failure I first misread as the floor firing. —
   *Recovery:* re-ran with the copy at a correct path depth. — **Prevention:** the repeat is the
   evidence this needs a written check rather than awareness; it is now in the gate's COST
   comment.
7. **`${!STUB_DIRS[@]/#/$SB/}`** parsed as indirect expansion → `1 1 1 1: invalid variable name`.
   — *Recovery:* built the prefixed list with an explicit loop. — **Prevention:** `${!arr[@]}`
   does not accept pattern substitution.
8. **An M6 mutation did not land** — it mutates the gate, not the workflow, and was scored by a
   workflow-scoped landing check. — *Recovery:* handled inline with a gate-scoped check. —
   **Prevention:** none needed; the landing check refusing to score it is the desired behaviour,
   recorded as positive evidence.
9. **4225ms of `$(dirname)` forks I introduced** in the harness — 97% of its runtime, on a
   required-gate path. — *Recovery:* parameter expansion + batched `mkdir`. — **Prevention:** no
   per-file forks in a loop that runs for every PR.
10. **`run-all.sh` rc=1 misattributed to my change**; the cause was `env -i` stripping
    `SSH_AUTH_SOCK`, so an unrelated suite failed on SSH passphrase prompts. — *Recovery:*
    re-ran preserving the socket → rc=0. — **Prevention:** preserve the sockets a suite needs
    when pinning binaries, and read the failing suite's name before attributing.
11. **A stale `old_string`** on `decision-challenges.md` — I quoted a read that predated my own
    earlier edit to the same file. — *Recovery:* re-read and re-quoted. — **Prevention:**
    `hr-always-read-a-file-before-editing-it` applies to re-quotes, not just first edits.
12. **The SSH agent refused to sign** (`agent refused operation`), failing `git fetch`. —
    *Recovery:* HTTPS via `git -c credential.helper='!gh auth git-credential'`; SSH later
    recovered on its own. — **Prevention:** on a signing/auth refusal, switch to the gh-token
    path immediately rather than retrying SSH.
12b. **`worktree-manager.sh cleanup-merged` timed out at 2 minutes** in the session-start
    preamble — the same root cause as #12, since it fetches. — *Recovery:* skipped, per the
    preamble's own skip-on-first-error instruction. — **Prevention:** honour that instruction
    rather than retrying; a slow git op in the preamble must never block routing.
13. **A Bash output file was reaped mid-run** by a concurrent Claude process (ENOENT), losing an
    AC verification run. — *Recovery:* re-ran writing into a session-unique `mktemp -d` the
    command created and read itself. — **Prevention:** never depend on the harness output file
    for multi-step verification.
14. **I targeted the bare-repo root for a route-to-definition edit** and the guardrails hook
    denied it (`Writing to main repo checkout while worktrees exist`). — *Recovery:* re-read and
    re-applied at the worktree path, then verified with `git status --short` that the worktree
    file was modified and the bare root untouched. — **Prevention:** compound's Step 8 already
    mandates worktree-absolute paths for exactly this reason; the hook is the mechanical
    backstop and it worked. Never construct a plugin path from the repo name alone — build it
    from the worktree root.
15. **Workflow deviation — I ended a turn on a forward-looking sentence.** I emitted "Chaining to
    `/soleur:compound` → `/soleur:ship` now" and then stopped; the operator had to ask "why did
    you stop?". — *Recovery:* resumed immediately on being asked. — **Prevention:** already
    prose-enforced twice (`hr-when-a-workflow-concludes-with-an`, and work/SKILL.md's Common
    Pitfalls "Emitting a forward-looking sentence as the last thing in a turn"). No new rule is
    warranted; the enforcement gap is that neither is mechanically checkable. The operative
    discipline: after a phase marker, the **next tool call in the same response** must be the
    successor skill invocation.

## Related

- [[2026-07-19-my-mutation-battery-was-green-and-it-only-measured-the-mutations-i-thought-of]] —
  fixture shape; this learning adds the axis-count framing.
- [[2026-07-27-my-refutation-measured-a-shim-and-my-safe-fixture-hid-12240-deletions]] — pin the
  binary; this adds *agreement across agents is not independence*.
- [[2026-07-15-ad-hoc-verification-evidence-is-as-perishable-as-uncommitted-code]] — the
  perishable-evidence rule the gate's `mutation-proved` comment violated.
- [[2026-07-29-every-guard-i-fixed-this-session-was-narrower-than-the-claim-it-carried]] —
  guard-building PRs and self-derived oracles.
- [[2026-06-16-infra-test-orphan-suites-and-node-options-env-file-clobber]] — the orphan
  generator whose human-habit prevention failed three times.
- #7076 — the runner's derivation gap; closing it should retire both `KNOWN_UNDERIVABLE` and the
  `EXCLUSIONS` entry.
