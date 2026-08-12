---
title: "Every fix I shipped for a silent failure had a silent failure in it"
date: 2026-08-12
category: workflow-patterns
issue: 7228
pr: 7457
tags: [review, guards, mutation-testing, systemd, observability, agent-convergence]
---

# Every fix I shipped for a silent failure had a silent failure in it

## Problem

#7228: the dedicated inngest host booted and never bound `:8288`. Twelve days of failed
dispatches passed with every monitor green, because the only monitor in the path was a
`curl "$HEARTBEAT_URL"` fired by a systemd timer — it proved a timer fired and asserted
nothing about the port.

The PR that fixes that shipped, at various points, **nine defects of the same family as
#7228 itself**. Not similar in theme — the same mechanism, inside the fix. A 12-agent
review found them; a green 261-suite run, clean shellcheck, and my own mutation batteries
did not.

## What the review actually found

Ordered by how badly each would have hurt, all pr-introduced:

1. **A Doppler key that boot-bricks the host it protects.** The instance stamp added a
   secret to `soleur-inngest/prd`, whose boot self-check is an EXACT-SET match that FATALs
   on any unadmitted name. From the first stamped flip, every re-provision would refuse to
   bootstrap — no Vector, no server, no flip timer — precisely when someone is recovering
   the host. The same file's comment documents that exact recurrence for `CUTOVER_FLIP`.
   I had read that comment while writing a different fix in the same file.
2. **`aborted` that left a live prod scheduler running.** The new post-start abort path
   never stopped the server, and `Restart=on-failure` kept it up — a live prod scheduler
   under a terminal flag the guard would never be consulted about again.
3. **Diagnostic boot could never have worked, two ways.** Its flag was in no allowlist (so
   setting it, which the runbook instructs, bricks the host) and never reached the
   bootstrap (so the bootstrap emitted the durable unit while the guard saw the request —
   a guaranteed BLOCK). It was the plan's stated centrepiece.
4. **Diagnostic boot adopted the PROD registry.** The sentinel the guard verifies governs
   the queue, not registry adoption; `--sdk-url` still pointed at the live app, so a
   diagnostic host would independently fire every prod cron.
5. **A verify window raised but never applied.** See below — the sharpest one.
6. **The flush durability gate sat AFTER the flush.** On an absent `/mnt/data` the queue
   was already destroyed by the time the guard spoke.
7. **A guard that named an unreachable recovery**, and no verb that could perform it.
8. **`RequiresMountsFor=` deleted the rollback control channel** on a host whose only
   control channel is the flag poll.
9. **A 503 would have beaten.** The listener gate's fixtures were `{200, 404, 000}`, which
   cannot distinguish an allowlist from a blocklist — so rewriting `!= "200"` into a
   two-member blocklist passed, and inngest's own not-ready code would have produced a
   green beat over a scheduler serving nothing. #7228, restored through its own fix.

## Key insight

**A lesson written up at length gets applied to one instance while its siblings three
lines away go unpinned.** This is the shape, and it recurred four times in one PR:

- I raised the verify window from 90s to 240s because 90s was below the poll interval —
  and the registry check sat OUTSIDE the retry loop, sampled once, so the window I raised
  never applied to the condition I raised it for. The drift test I added in the same
  commit asserts the *numeric* relation and its failure message describes the bug the code
  still had. A green test over the defect it names.
- I then fixed the registry retry with a stateful fixture — and left the `/health` retry
  fixtured at cardinality one, the identical defect in the other operand.
- I pinned `CUTOVER_VERIFY_WINDOW_S` because "a constant the tests always override is a
  constant nothing guards" — and left the three probe URL defaults one line above it
  unpinned, where a wrong port fails every cutover.
- I wrote a comment explaining that source-grepping a templatefile "asserts a property of
  a file no host ever sees" — directly above four behavioural tests that grep the source.

The generalisation: **when a block's comment states a general rule, grep the same file for
every other instance of that rule's precondition.** The rule is usually right and its
application is usually incomplete.

## Agent convergence is not proof when the agents share a model

Two agents independently reported a P0: that systemd would truncate my 240s window at the
90s `DefaultTimeoutStartSec`. I acted on it. `man systemd.service` says the start timeout
is **disabled by default for `Type=oneshot`** — a third agent had it right and disagreed.

The change was still correct (an unbounded oneshot hangs *forever*, which is worse), but I
committed a **false rationale** and had to correct it. Convergence raises confidence only
when the errors are independent; two agents sharing one wrong model are one agent.

Corollary that also bit: a right verdict can rest on wrong reasoning. Evaluate the verdict
and the reasoning separately.

## A surviving mutant has two readings — label which

My "the marker is a file, not a directory" assertion survived two mutation attempts. The
honest reading was not "weak fixtures" but **equivalent mutant**: `record_done_owner`
mkdir -p's the parent and writes a file at whatever path it is given, so the marker is
deeper than the created directory by construction and any predicate comparing them is
tautological. I deleted the assertion and recorded why. A decorative assertion that cannot
fail adds a row to the count and nothing to the coverage.

## Instruments lie; verify them before reading the verdict

Four measurements in this session were themselves broken:

- **CWD drifted to the bare repo root twice.** A suite reported 68 assertions where I had
  seen 91, and I nearly wrote it up as a regression — it was the bare root's stale synced
  copy. Later, three suites reported 16/0/0 for the same reason. Pin CWD in every command.
- **A sandbox mutation control came back RED**, voiding every row measured against it; the
  suite needed repo-root context a copied `infra/` directory cannot provide. Re-run in-tree
  with a backup, and never read a mutation result whose control was not green.
- **An assertion floor I guessed** (115) instead of deriving from a green run (102).
- **`pkill -f <pattern>`** matched its own command line and killed the invoking shell.

## Prevention

- Before adding ANY name to a Doppler project, grep the boot isolation allowlist. The
  check is an exact-set match and its failure is a boot-brick.
- For any new emitter/gate/probe, ask **which of {format, self-consistency, content}** the
  test checks, and **which layer** the mutation battery edits. N mutations of one shape is
  one mutation.
- Fixture DIRECTION and CARDINALITY are coverage axes. Two negative fixtures cannot
  distinguish an allowlist from a blocklist; one member cannot distinguish `1-of-1` from
  `all-of-1`; a constant stub cannot exercise a retry.
- Give every suite an assertion-count floor, derived from a green run, placed BEFORE the
  summary so a breach is printed rather than exiting silently.
- When two agents agree, ask what model they share before acting.

## Session Errors

1. **Added a Doppler key to a project guarded by an exact-set boot check.** Recovery:
   replaced the mechanism with a root-disk marker. **Prevention:** grep the isolation
   allowlist before adding any secret name; the failure mode is a boot-brick, not an error.
2. **`verify_or_abort` did not stop the server it had started.** Recovery: `stop_server`
   with the outcome captured. **Prevention:** any abort reachable after a start must state
   what it does with the started process.
3. **Guard prescribed a recovery the monotonic latch refuses.** Recovery: named the real
   `flushed` re-entry. **Prevention:** trace every remedy a message names before shipping it.
4. **Raised a window that never applied to the condition it was raised for.** Recovery:
   both conditions now retry against one deadline. **Prevention:** after fixing a constant,
   confirm the code path actually consumes it.
5. **Acted on two agents' converged wrong systemd model; committed a false rationale.**
   Recovery: read `systemd.service(5)`, corrected the comment. **Prevention:** verify a
   converged claim against the primary source when it is cheap.
6. **CWD drifted to the bare repo root twice; nearly reported a false regression.**
   Recovery: pinned CWD and re-ran. **Prevention:** pin CWD in every Bash call; treat any
   surprising assertion-count drop as a CWD check first.
7. **A sandbox mutation control came back RED, voiding a result.** Recovery: re-ran in-tree
   with a backup and a green control. **Prevention:** require a green control before
   reading any mutation row.
8. **Invented `require_env` / `hook_get` helpers that do not exist.** Recovery: used the
   file's real idioms. **Prevention:** grep for a helper before calling it.
9. **Used `pass`/`fail` in a suite that only defines `assert` (exit 127).** Recovery:
   rewrote as `assert`. **Prevention:** read the suite's helper block first.
10. **Guessed an assertion floor instead of deriving it.** Recovery: measured. **Prevention:**
    floors come from a green run, never from expectation.
11. **`pkill -f` matched its own command line and killed the shell.** Recovery: resolved
    PIDs and filtered by `/proc/<pid>/cwd`. **Prevention:** never `pkill -f` a pattern that
    appears in the pkill invocation.
12. **`grep -c` over two files printed per-file counts.** Recovery: `cat … | grep -c`.
    **Prevention:** the multi-file form emits `path:count` per file.
13. **A commit was blocked because the message prose contained a guarded command literal.**
    Recovery: reworded. **Prevention:** hooks scan commit messages too.
14. **A commit was blocked because CWD was the bare root, so the hook saw `main`.**
    Recovery: pinned CWD first. **Prevention:** same as (6).
15. **Diagnostic boot's flag was neither admitted nor delivered.** Recovery: both fixed and
    pinned. **Prevention:** "both files read the same variable" is satisfied by a variable
    nothing sets — assert delivery, not just reading.
16. **`op=resume` initially missed both the token gate and the required-reviewer gate.**
    Recovery: widened both; converted a byte-identity ratchet into a membership assertion.
    **Prevention:** a new op that writes prod inherits every gate the sibling ops have.
17. **Shipped a decorative assertion that could not fail.** Recovery: deleted it with the
    reasoning recorded. **Prevention:** label a surviving mutant as weak-fixture or
    equivalent; never leave it unlabelled.
18. **Three review agents died mid-run (API errors, one stall).** Recovery: resumed rather
    than respawned, preserving partial findings — one had already established a finding it
    was mid-way through proving. **Prevention:** resume, do not respawn; and cap
    sub-agent fan-out inside an agent that has stalled once.
19. **The plan's `discoverability_test.expected_output` was a string the suite never emits.**
    It read `"OK inngest-consumer-probe: all assertions passed"`, copied by analogy from the
    sibling suite `inngest-boot-emitter.test.sh`, which genuinely ends that way; this suite
    ends `=== $PASS passed, $FAIL failed ===`. The declared value appears nowhere in the repo.
    Caught by preflight Check 10, which EXECUTES the command rather than checking the field is
    present — every earlier gate checked presence and passed. Recovery: corrected to `0 failed`
    (stable across assertion-count changes). **Prevention:** a verification contract is not
    verified by existing. Run the command once at authoring time; and treat "the sibling
    artifact says X" as a hypothesis about THIS artifact, never as evidence — the nineteenth
    instance of this PR's own recurring shape, committed in the field that certifies the fix.
20. **The plan's brand-survival threshold was bold prose, not the canonical bullet.**
    `**Brand-survival threshold:** single-user incident.` instead of the required
    `- **Brand-survival threshold:** single-user incident`. Recovery: canonicalized.
    **Prevention:** the gate anchors on bullet shape deliberately — substring-matching prose
    would let "this is not a single-user incident" pass. Copy the literal from
    `plan-issue-templates.md` rather than approximating it.
21. **The plan frontmatter claimed `closes: [7228, 6617, 7308]`.** All three would have closed
    at merge on a promise; #7228 cannot close until the #7462 host restore lands. Recovery:
    `refs:`, and `Ref` rather than `Closes` in the PR body. **Prevention:** before writing a
    close keyword, ask what post-merge event proves the issue's ask is true — if one exists,
    the keyword is wrong.
