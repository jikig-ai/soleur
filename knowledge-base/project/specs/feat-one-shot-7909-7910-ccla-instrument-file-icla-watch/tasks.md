# Tasks — chore(cla): `--instrument-file` and an epoch-aware ICLA signature watch

Derived from the finalised (post-review) plan at
[`../../plans/2026-09-07-chore-ccla-instrument-file-and-icla-signature-watch-plan.md`](../../plans/2026-09-07-chore-ccla-instrument-file-and-icla-signature-watch-plan.md).
Closes #7909 and #7910. Open questions for the CLO are in
[`decision-challenges.md`](./decision-challenges.md).

Read the plan's `## Guard Contract` before writing any guard — the mutation matrices are the
specification and were written before the code by design. Read §"What plan review changed" AND
§"Deepen-Plan Findings" before writing any probe code: between them, **nine claims this plan made
were falsified by measurement**, including a fail-open in its own prototyped predicate that returned
PASS on an unreadable coverage map. The Deepen-Plan Findings table carries a BLOCKER and seven HIGH
items that are still to be applied — work them before Phase 1, because two of them change the
shape of the deliverable.

## Phase 0 — Preconditions (no edits)

- [ ] 0.1 Re-run every row of the plan's Premise Validation table; a stale row re-scopes the phase.
- [ ] 0.2 Re-measure the depth-1 epoch hazard in a scratch clone and paste the output into the PR
      body.
- [ ] 0.3 Re-run the probe's `jq` predicate against the live ledger, roster and epoch; confirm 0.
- [ ] 0.4 Record the measured floors — the `Total:` line from
      `bash apps/cla-evidence/test/ccla-add.test.sh` and the `checked` count from
      `bash scripts/followthrough-exec-bit.test.sh`. **Do not guess either number.**
- [ ] 0.5 Determine whether `cron-follow-through-monitor` is currently dispatching, and record
      the answer. The `## Verification` block goes into the tracker either way.
- [ ] 0.6 **Measure whether the existing temporal arm at `ccla-add.test.sh:234-248` is already
      vacuous in CI.** `ci.yml:743-749` checks out `test-webplat` shallow, so the epoch there may
      be HEAD's own date, making every ledger entry pre-epoch and that assertion pass for the
      wrong reason. If confirmed, it is a pre-existing defect in a file this PR edits — fix it
      here.
- [ ] 0.7 Confirm `sha256sum`, `jq`, `git`, `realpath`, `timeout` on PATH and
      `apps/web-platform/node_modules/.bin/tsx` present.
- [ ] 0.9 **Work the `## Deepen-Plan Findings` table.** Its BLOCKER (no correction path exists for a
      wrong `executed_instrument_sha256` on an unerasable public record) must be decided while
      `organizations` is `[]` and the schema change is free. Its seven HIGH items change the shape
      of Phase 5.3 (the register relation is asymmetric, not parity), add a `record_ref` integrity
      prerequisite, and put two one-line hardening fixes in `sweep-followthroughs.sh` that protect
      all 78 probes.
- [ ] 0.10 Measure whether the probe's `git fetch` still succeeds with
      `persist-credentials: false` before deciding that half of Phase 5.1.
- [ ] 0.11 Read `apps/cla-evidence/scripts/ccla-add.sh` end to end before editing it.

## Phase 1 — RED: `--instrument-file` test arms

- [ ] 1.1 Synthesized fixtures under `$WORK`: a primary, a second with different bytes and length,
      a zero-byte one, an unreadable one, a directory, a symlink to a valid file outside the repo,
      a symlink whose target is inside the repo, and one whose basename is a synthesized
      organisation name.
- [ ] 1.2 The **agreement** arm in its non-vacuous form: assert `rc == 0` on BOTH arms and that
      the output is parseable JSON, *then* `cmp`. Cite the xtrace must-PASS pairing at `:219-232`.
- [ ] 1.3 The value arm: the emitted hash equals `sha256sum < <fixture> | awk '{print $1}'`.
- [ ] 1.4 The stderr-transcripts-differ arm.
- [ ] 1.5 Refusal arms with **distinct** messages: both flags, neither, relative path, missing,
      directory, empty, unreadable, inside-repo (rc 2).
- [ ] 1.6 The caller's-file-survives arm.
- [ ] 1.7 The **source-level** arm: grep the `git commit --file` heredoc span and the
      `gh pr create --body` span for `INSTRUMENT_FILE|RESOLVED`, assert 0 hits. (The runtime paths
      are unreachable under the suite's unconditional `CCLA_ADD_DRY_RUN=1`.)
- [ ] 1.8 The organisation-named-fixture arm.
- [ ] 1.9 Run the suite; confirm the new arms are RED for the right reason.

## Phase 2 — GREEN: `--instrument-file`

- [ ] 2.1 Add `INSTRUMENT_FILE=""` to the initialiser at `ccla-add.sh:129-130` — without it the
      first `[[ -n … ]]` aborts with a bare rc=1 and no message.
- [ ] 2.2 Add the parse arm.
- [ ] 2.3 In the `add` branch, in this order: mutual exclusion → required-ness naming both flags →
      absolute-path check → `-e` → `-f` → `-s` → `-r` → `realpath -e` both operands and the
      inside-repo custody refusal (trailing `/` on the prefix comparison).
- [ ] 2.4 `INSTRUMENT_SHA="$(sha256sum < "$RESOLVED" | awk '{print $1}')" || die "…" 2`, then fall
      through to the existing `^[0-9a-f]{64}$` assertion at `:170` unchanged.
- [ ] 2.5 Echo the resolved path, byte size and computed hash to **stderr** only.
- [ ] 2.6 Confirm the resolved path is in `TMP_FILES` nowhere and reaches neither the commit
      heredoc nor the PR body.
- [ ] 2.7 Update the `usage()` heredoc and the file header comment block.
- [ ] 2.8 Suite green.

## Phase 3 — Guard 1 mutations + floor

- [ ] 3.1 Add mutation arms for Guard 1 rows 1-7, each asserting the mutation LANDED first.
- [ ] 3.2 Add harness rows H1-H4.
- [ ] 3.3 Set `MIN_ASSERTIONS` to the measured new total, keeping the floor's syntactic shape
      (simple-assignment threshold line, `-lt` opener, `printf >&2` + `exit 1`) so
      `guard-vacuity-floor.test.sh` can slice it.
- [ ] 3.4 `bash scripts/guard-vacuity-floor.test.sh` reports `FIRES` for this file.

## Phase 4 — The probe and its suite

- [ ] 4.1 `gh issue create` the tracker WITHOUT the `follow-through` label (`type/chore`,
      `domain/legal`, `priority/p2-medium`), body carrying a `## Verification` YAML block with a
      stated `sla_business_days`. Title and body name the organisation and the purpose, and name
      no person. If the PR is abandoned, close the tracker in the same session.
- [ ] 4.2 Write `scripts/followthroughs/ccla-representative-icla-<TRACKER>.sh`. Header: the full
      exit contract, why exit 1 is never used (it is the sweeper's reopen trigger), why the epoch
      derivation must precede the ledger fetch, why the fetch omits `--depth=1`, and the
      `earliest=` reasoning. Body: `--print-epoch` plus `*) exit 64`; the derivation with
      `--format='%H %cI'`, status checked before `tail`, and an **explicit emptiness check**;
      control B (parent exists, parent lacks the anchor — remembering `grep -c` exits 1 on zero,
      which is the success case); the ledger fetch `--no-tags` **without** `--depth=1`; ledger and
      roster shape assertions; the **materialised, status-checked** roster read — NEVER a process
      substitution, whose exit status is invisible and which returned PASS on an unreadable roster
      (reproduced: `count=1 rc=0`); malformedness as a COUNTED predicate, never a caught exception
      (jq's error text carries the offending value and that text is published); "covered" as live
      OR withdrawn; **no exit 0 on any path** (the probe reports, it does not close);
      integer epoch comparison refusing on parse failure; every external command's stderr
      suppressed and replaced by a probe-authored line; every network call inside `timeout 30`;
      one `CANNOT ESTABLISH: <reason>` shape with an addressee tag; the checked count in the
      `REPORT` line.
- [ ] 4.3 Run `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main`
      and add the xtrace block if and only if the lint asks for it.
- [ ] 4.4 `chmod +x` **both** the probe and the companion suite; confirm both git INDEX modes are
      `100755` (`followthrough-exec-bit.test.sh` globs `*.sh`, which subsumes `*.test.sh`).
- [ ] 4.5 Write `scripts/followthroughs/ccla-representative-icla-<TRACKER>.test.sh`:
      `export TMPDIR="${TMPDIR:-/var/tmp}"`; a **family** of synthetic repos (one-touch,
      two-touch, merge-commit, rebase-replay, squash, grafted) built with `git -c` flags for
      identity and signing, never `git config` writes; each fixture's shape asserted before use;
      a tag-carrying synthetic origin for the `--no-tags` arm; the probe run under `env -i`;
      three counters (`passes`, `fails`, and `cases` incremented at the call site); Guard 2's
      mutation rows 1-14 and harness rows H1-H5; the per-fixture `tsx` parity arm, FAILing never
      skipping if `tsx` is absent; stubs whose FAILURE paths are driven for the no-naming arm;
      the floor and the accounting-conservation assertion.
- [ ] 4.6 `git add` the new suite **before** running `scripts/lint-orphan-test-suites.sh` — it
      enumerates via `git ls-files`, so an untracked suite passes vacuously.
- [ ] 4.7 Register the companion suite in `scripts/test-all.sh` inside `want_webplat` with the
      `tsx` rationale comment, plus a one-line note at `:1884` that one companion lives in that
      shard and why.
- [ ] 4.8 Add a back-pointer comment in `apps/web-platform/scripts/cla-evidence/roster-entry-gate.ts`
      naming the probe, so an edit to `%cI` / `--first-parent` / the oldest-match rule does not
      redden a suite in a third directory with no hint of the connection.
- [ ] 4.9 Raise `MIN_PROBES` in `scripts/followthrough-exec-bit.test.sh` to the measured count,
      **and add a sentence to its comment naming the lowering procedure** — retiring a probe when
      its tracker closes is the normal end of life, and the comment currently says the floor may
      only be raised.
- [ ] 4.10 Substitute the resolved `<TRACKER>` number back into the plan file in the same commit,
      so the shipped file is greppable from the plans corpus.

## Phase 5 — Sweeper, register, documentation

- [ ] 5.1 `.github/workflows/scheduled-followthrough-sweeper.yml`: `fetch-depth: 0` with a comment
      naming the probe and the measured reason; `timeout-minutes: 15`. No `env:` change.
- [ ] 5.2 `actionlint` clean on the modified workflow.
- [ ] 5.3 Extend `scripts/lint-legal-registers.sh`'s `REGISTER_FILES` to cover
      `knowledge-base/legal/ccla-register.md`, and add a register↔roster `Instrument hash` parity
      assertion (P11) — without it #7909 lets the two values diverge silently, which is worse than
      the status quo where one computed value is transcribed into both.
- [ ] 5.4 `knowledge-base/engineering/operations/runbooks/cla-signature-evidence-retrieval.md`:
      §10.1 step 2 rewritten to pass `--instrument-file` with an absolute path on the encrypted
      drive (and its `sha256sum <file>` argv form corrected to the stdin form); §10.2's worked
      example switched with `--instrument-sha256` kept as the fallback; §10.4's exit-code table
      extended; a short new §10.6 covering the watch, its exit classes, that a PASS is not
      authority to record, and `--print-epoch` as the command that distinguishes "waiting" from
      "broken".

## Phase 6 — Verification

- [ ] 6.1 `bash apps/cla-evidence/test/ccla-add.test.sh` green, `MIN_ASSERTIONS` at the measured
      total.
- [ ] 6.2 `bash scripts/followthroughs/ccla-representative-icla-<TRACKER>.test.sh` green.
- [ ] 6.3 `bash scripts/lint-orphan-test-suites.sh`, `bash scripts/followthrough-exec-bit.test.sh`,
      `bash scripts/lint-followthrough-varq-ban.sh`,
      `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main`,
      `bash scripts/guard-vacuity-floor.test.sh`, `python3 scripts/lint-guard-contract.py` all
      green, with no new baseline entry.
- [ ] 6.4 `plugins/soleur/test/c4-count-parity.test.sh` green.
- [ ] 6.5 Sandbox assertion: after a probe run in a synthetic sandbox,
      `[[ ! -e "$(git rev-parse --git-common-dir)/shallow" ]]` holds there and
      `git show-ref --tags` is empty.
- [ ] 6.6 Full battery `bash scripts/test-all.sh` at the `/ship` Phase 4 checkpoint.
- [ ] 6.7 Walk every Acceptance Criterion and record its evidence.

## Phase 7 — Enrolment (post-merge, via a committed script)

- [ ] 7.1 Write `scripts/bootstrap-ccla-watch-<TRACKER>.sh`
      (`hr-multi-step-post-merge-bootstrap-script` — four scriptable steps): fetch the tracker
      body, append the `<!-- soleur:followthrough script=… earliest=<filing date> -->` directive,
      `gh issue edit <TRACKER> --body-file … --add-label follow-through`, dispatch
      `gh workflow run scheduled-followthrough-sweeper.yml -f dry_run=true`, and assert the run
      log names the probe. Read-modify-append-write throughout — `--body-file` replaces the whole
      body.
- [ ] 7.2 Run it after merge.
- [ ] 7.3 Confirm #7909 and #7910 closed by the merge; #7846 still open and untouched.

## Phase 8 — Substrate follow-ups (file, do not fix here)

- [ ] 8.1 File a tracker for sweeper comment de-duplication (one existing tracker carries 33
      identical sweeper comments).
- [ ] 8.2 File a tracker for the sweeper's missing per-probe `timeout` — a hung probe currently
      takes the rest of the sweep with it, silently.
- [ ] 8.3 File a tracker for the sweeper's hard `--limit 50` against 51 open follow-through
      issues, sorted newest-first, so the two oldest are silently never swept.
- [ ] 8.4 File a tracker for adding `.git/shallow` to `scripts/lib/repo-write-boundary.sh`'s
      sampled dimensions — it is repository-wide, shared across worktrees, and currently invisible
      to both the boundary guard and `git status --porcelain`.
- [ ] 8.5 File a tracker for `gh issue edit --add-label follow-through` being ungated while
      `gh issue create --label follow-through` is gated.
