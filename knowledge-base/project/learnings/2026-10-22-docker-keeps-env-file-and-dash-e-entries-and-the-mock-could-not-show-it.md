# Learning: Docker keeps an --env-file entry AND a -e entry for one key, and a mock that models only -e could never show it

## Problem

The first production flip of the Inngest scheduler link to https (epic #10205, item #10136, ADR-294) failed at the canary's
`docker inspect` check with `INNGEST_LINK: class=canary_failed level=error check=inspect cause=none`. The check requires exactly one
`INNGEST_BASE_URL=` line (the https URL) and exactly one `NODE_EXTRA_CA_CERTS=` line in `Config.Env`. The canary `docker run` passes the Doppler
snapshot with `--env-file` and then `-e INNGEST_BASE_URL=...` and `-e NODE_EXTRA_CA_CERTS=...`.

Reproduced locally (Docker client 29.9.2, daemon 29.9.1): `--env-file` with `A=fromfile` plus `-e A=fromflag` leaves **both** entries in
`Config.Env`; the `-e` value wins when the process starts, but `docker inspect` lists two lines, so a strict count of one fails. The mock docker in
`ci-deploy.test.sh` built its inspect output from the `-e` pairs only and ignored the env-file, so no test could ever show a duplicate. The old
check also never set its `cause` variable on the inspect branch (it started as `none` and stayed there), so the event named no condition. The
Doppler key set was never read, so "the snapshot pins `INNGEST_BASE_URL`" is the most likely cause, not an observed one; the next flip's new
`check=inspect cause=<token> url_lines= ...` row is the first real measurement.

## Solution

- `ci-deploy.sh`: `inngest_link_scrub_env_file` removes every line naming `INNGEST_BASE_URL` or `NODE_EXTRA_CA_CERTS` from the env-file once per
  deploy (after the resolver, before the first `docker run`), so the `-e` flags are the only source. `LC_ALL=C grep -a`; count, write kept lines to
  a temp file, conservation (kept + removed = total), recount, then `mv`; every failure leaves the file byte-identical; a strict (flag-on) deploy
  aborts with `inngest_env_scrub_failed`, anything else logs and continues. The inspect check stays strict and now names its first failing
  condition (`inspect_failed|url_count|url_value|ca_count|ca_value` plus four integers clamped to 99, never a value) with its own deploy-state
  reason.
- Tests: the mock docker now reads the env-file (`<runlog>.eff<N>`), the Doppler snapshot can carry its own lines (`IL_SNAP_EXTRA`), stub inspect
  modes cover every cause and the clamp magnitudes, and mutation rows pin the scrub and the cause order.
- The decision (scrub the source, keep the proof strict) was ruled by the CTO agent; rejected: `-e` for everything (secrets on argv), an
  `--env-file` allowlist (the prd key set is open-ended), last-wins de-duplication at inspect time (weakens the proof).

## Key Insight

When a fake models only part of how the real tool composes its inputs, the suite can be fully green over a defect that exists only in the part the
fake leaves out. The unit that must be right is the **composition** (env-file plus flags), not each input. The same defect hid behind a diagnostic
default (`cause=none`) that named no cause: a failure message that cannot say which condition was off turns a 5-minute read into a re-flip.

Second insight, from the review rounds: a fix PR's own **sentences** are the least-audited surface. Round 1 of review found ADR and runbook text that
stated an inferred cause and a revert result as observed; round 1's corrections then wrote new unmeasured claims (a trial merge "clean" that
conflicts, a result "exactly as observed"); round 2's fix made a printed verdict sentence ask for a `canary_ok` row that a flag-off deploy never
emits. Each was caught by a command, not by reading.

Related: `2026-06-16-infra-test-orphan-suites-and-node-options-env-file-clobber.md` (an earlier env-file versus `-e` precedence trap in the same
script).

## Session Errors

1. **First production flip failed at the canary inspect check with `cause=none`** (forwarded from the earlier pipeline phases) — Recovery: root cause
   reproduced locally and fixed — Prevention: the mock now reads the env-file, and the check names its cause.
2. **Draft-PR creation failed for lack of commits** (forwarded) — Recovery: ship creates the PR once commits exist — Prevention: none needed (one-off).
3. **The Phase 2 affected-test gate queued ~28 minutes behind a sibling worktree's lock and was killed** (forwarded) — Recovery: reran at ship —
   Prevention: read the runner's `--capacity` verdict first (already in `risk-tier-and-fix-rounds.md`).
4. **The round-1 test-design seat stopped on an interim status line with its mutation run still going and delivered no report** — Recovery: read its
   mutation results file from its sandbox, then removed the sandbox — Prevention: already documented in the review skill (a seat whose last block is
   a tool call has not delivered; mandate file delivery at spawn). The round-2 spawn prompt now says so explicitly.
5. **Round-1 corrections introduced fresh unmeasured claims** (a #10697 "clean" trial merge that conflicts in the preflight counter file; "exactly as
   observed" for a count nobody recorded) — Recovery: re-measured by `git merge-tree` against the PR head and rewrote the sentences — Prevention:
   already documented (a correction round is where new unmeasured claims ship); run the falsifying command for each added sentence.
6. **Round-2's flip-script edit made the OFF and REVERTED verdict lines ask for a `canary_ok` row** (caught by the verification seat) — Recovery:
   `flip_read_line` asks for it only when the verdict's scheme is https, plus two assertions pinning both variants — Prevention: a test now pins the
   printed sentence by scheme (`inngest-link-flip-workflow.test.sh` A-readline-1/2).
7. **A duplicate Monitor was armed and the monitor-supersede hook flagged it** — Recovery: stopped the first one — Prevention: hook-enforced.
8. **`cat > "$TMPDIR/p1.py"` with `TMPDIR` unset wrote to `/p1.py` and was denied** — Recovery: none needed (the patch ran from a heredoc) —
   Prevention: one-off.
9. **The shell cwd reset to the bare repository root after several calls** — Recovery: every command started with an explicit `cd` into the
   worktree — Prevention: already covered by `hr-when-in-a-worktree-never-read-from-bare`.
10. **The coverage consult returned three leads (abort-path parity, `_gak_tmp` aliasing, mock fidelity) and all three were false against the diff** —
    Recovery: each verified and dropped — Prevention: by design the reply is a lead, not evidence.

## Tags

category: integration-issues
module: apps/web-platform/infra (ci-deploy.sh, Inngest link canary)
