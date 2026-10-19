---
title: git-data cutover resume 2026-10-19, CTO rulings on the rehearsal sequence
tracking: "#8211"
brand_survival_threshold: single-user incident
---

# CTO rulings, 2026-10-19 (epic #8211)

> **Decision record, not authority.** No row below authorizes any dispatch, merge or approval; the owner names each production
> command. Superseded in part: PR #10535 was merged on 2026-10-19 at 11:43:22Z (GitHub `mergedAt`), before builds 1 to 3, so T1a
> ("authorise `gh pr ready 10535` and `gh pr merge 10535`"), the "Operator Holds" gate lines and the "Standing delegation offer" for
> #10535 below are historical; see `precondition-read-2026-10-19.md` ("Ordering note"). The "Draft A/B/D" wording and the
> runbook edits C-1 to C-5 belong to the wipe_check stream (PR #10523), copied here as the rulings recorded them.

Nothing here dispatched a workflow, applied terraform or wrote production state. Every cited fact was read in this worktree
or with a read-only `gh`/`curl` call on 2026-10-19 unless marked `unverified`. Dates: CLO re-ruling 2026-10-24, latest flip
stamp 2026-11-04, plaintext retention 2026-11-12.

No Standing Delegation exists on #8211 (the discovery command of standing-delegation.md section 1 printed nothing), so every
production act below stays an owner-named command.

## Decision Classes

<!-- lint-infra-ignore start: owner-named dispatches are recorded here as authorization classes, not as steps a person runs by hand -->

| Item | Class | Ruling |
|---|---|---|
| T1 merge #10535 before #10297 | technical | Ruled by CTO agent, 2026-10-19: merge order does not need #10297 (a stale soak anchor cannot satisfy the wipe: `git-data-flag-precheck.sh` `select_variant` sends any stamp to `flip_chained`, which needs the flag exactly `true`, and `wipe_last_rollback_epoch` refuses a rollback newer than the stamp), but #10535 merges LAST, after the flip-readiness builds in T2, because it is the only machine barrier to an unprepared production flip and no session control exists - merge order is the guard, no new code |
| T1a authorization to mark #10535 ready and to merge it | operator (production-mutating) | Authorise `gh pr ready 10535` and `gh pr merge 10535 --squash` only after T2 builds 1 to 3 are merged and build 4 is recorded (split from T1) |
| T2 rehearsal builds, required set and order | technical | Ruled by CTO agent, 2026-10-19: the flip path needs, in order, (1) a quiet-window control with an active-session read, (2) the rehearsal evidence collector, (3) the runbook edits that state Level 2 is an owner-run sequence, (4) a dated by-hand live read of the other flip preconditions; #10297 is cheap and goes in fifth but is a wipe precondition, not a flip precondition; the wipe_check hooks diagnostic (T3) is a separate stream off the flip path; do NOT build a scripted synthetic-account lifecycle, a `WORKTREE_ROOT` directory read, or a flip dry-run mode |
| T3 wipe_check `hooks` diagnostic shape | technical | Ruled by CTO agent, 2026-10-19: two new fields on the existing rc=34 line, `hooks_pre_receive_f` (0 or 1) and `hooks_other_n=<n>`, computed inside the existing snapshot window; classifier unchanged; the new fields need their own CLO ruling before the change merges (see "CLO routing") |
| T3a legal posture of the new fields and any later allowlist change | operator (legal-risk) | Ruled by CLO agent, 2026-10-19: approved under conditions C1 to C9 with the field renamed `hooks_pre_receive_f`, addendum 3 and runbook edits ship with the code, addendum 4 lifts C1 for one `wipe_check` after the merge; five rows in "CLO routing" below |
| T4a credential rotations versus the rehearsal | technical | Ruled by CTO agent, 2026-10-19: the rehearsal does not technically depend on the three rotations (`precondition_8209_open` reads only that `DOPPLER_TOKEN_INFRA_PRIVILEGED` is present); the order between them is the owner's priority call, with one technical rule: no credential rotation, no canary, and no `apply-web-platform-infra.yml` dispatch inside the flag-on window |
| T4b `DOPPLER_TOKEN_GIT_DATA_FLAG` scope unverified | technical | Ruled by CTO agent, 2026-10-19: no standalone probe; the flip freezes before the flag write and the finalizer unwinds a write that fails (`flag_write_attempted` marker), so a wrong scope costs one freeze window and surfaces in the rehearsal, where a failed flip is an acceptable rehearsal outcome |
| T4c #10211 store-measured-empty marker | technical | Ruled by CTO agent, 2026-10-19: not a rehearsal or flip precondition; the rehearsal flip closes the rotate door (the run-record scan counts any flag-write step, and a rollback does not clean it), the break-glass in the runbook covers the gap; build it after the real flip is booked |
| T4d #10343 wipe hardening | technical | Ruled by CTO agent, 2026-10-19: settle before the first `mode=wipe`, not before the flip; direction: a dedicated wipe environment with a required reviewer AND a wait timer (`prevent_self_review` deadlocks a one-reviewer owner); `delete_protection` on the LUKS volume with lift-first ordering in the rotate arm; both are terraform applies, owner-authorised |
| T5 authorization to dispatch the rehearsal flip, rollback, exit read and every wipe mode | operator (production-mutating) | Each is its own owner-named command; see the final reply for the next one |

<!-- lint-infra-ignore end -->

## T1. Sequencing of #10535 and #10297

Finding 1. A stale `GIT_DATA_LUKS_CUTOVER_AT` after a rolled-back flip is not a safety hazard today. Evidence:
`apps/web-platform/infra/git-data-flag-precheck.sh` `select_variant` returns `flip_chained` for any non-absent stamp and that
variant refuses `wipe_precondition_flag_not_true` while the flag is `false`; `scripts/lib/git-data-wipe-runs.sh`
`wipe_last_rollback_epoch` refuses `wipe_precondition_rollback_after_stamp` for a `git-data rollback` run created at or after the
stamp; the real flip overwrites the stamp (the flip tail, `git-data-cutover.yml` step "Write GIT_DATA_LUKS_CUTOVER_AT").
What a stale stamp costs is availability: the `separated` wipe variant is unreachable while it exists, and after any flip
dispatch it is unreachable anyway because the run-record scan (`scripts/lib/git-data-store-dirty-scan.sh`) counts the
flag-write step whatever it concluded. So #10297 is a precondition of `mode=wipe`, as the 10-12 design section 6 already
records, and not of the merge of #10535.

Finding 2. The real hazard of merging #10535 is different. It removes the broken precondition that currently refuses every flip
(run 39225916196 refused at `pin_fault_paging_absent` before any host was touched), so the next `mode=flip` dispatch performs a
production flip. The 10-12 design (section 3, "counts are not refusal") makes a session-refusal control or a recorded owner
acceptance a hard precondition of the first flip dispatch under the `single-user incident` threshold. Neither exists
(search of `apps/web-platform/server`: no maintenance mode, no active-session read), and the owner has already dispatched the flip
once without them. A stranded working tree under `WORKTREE_ROOT` can be the only copy of a user's work, and web-2 has no SSH
ingress, so no read can show it there.

Decision: do not mark #10535 ready and do not merge it until builds 1 to 3 of T2 are merged and build 4 is recorded. This needs no new code and
no precondition that would itself have to be rehearsed. While it waits, an agent verifies read-only that every other flip
precondition holds against live data (the same reads the step makes, run by hand, no dispatch): d6 stamp at index 6 of 100
(read 2026-10-19), floors `0.313.5` and `0.330.10` against `/health` `0.344.8`, no `web-platform-release.yml` run in progress,
the pin-fault workflow `1310055` `enabled` (already read by the owner's PR). The one unverifiable item is the scope of
`DOPPLER_TOKEN_GIT_DATA_FLAG` (T4b).

Rejected alternatives. (a) Merge #10535 now and rely on the owner not dispatching: the owner dispatched on 2026-10-19 with the
builds absent, so restraint is not a control. (b) Build #10297 first and then merge: #10297 does not close the hazard that
matters. (c) A new flip precondition that refuses until the builds exist: it must be passable by the rehearsal itself, so it
needs an arming input or variable, which is one more owner write and one more path to rehearse. (d) A preconditions-only
`flip_check` mode: it would have caught the Sentry defect at zero cost, but the workflow runs `mode != 'redeploy'` steps
(`git-data-cutover.yml`, the bridge and freeze setup steps) for every unlisted mode, so a new mode needs an audit of every negative
condition in a 1761-line safety-critical workflow; the by-hand reads above give most of the value.

Dissent: merging #10535 now is the schedule-safe option, and the stale-anchor risk is bounded. I hold it because the broken
check is currently the only machine barrier. Flip the ruling if a session-refusal control and an active-session read are merged
earlier than expected.

Order of pull requests and who does each: builds 1, 2, 3 and 5 of T2 are opened by an agent (build only, one PR each); the T3
diagnostic is a sixth PR on its own stream; build 4 is a dated file committed with PR 3 or the spec directory. Each merge is the
owner's `gh pr merge <N> --squash` (or a later delegation). #10535 is the owner's PR: the owner marks it ready and merges it
after builds 1 to 4, and #10297 (build 5) may land before or after it.

## T2. Rehearsal builds

Note on labels: `#10296` is the rung-2 rehearsal of the empty plaintext-volume-id render, a precondition of PR-C after the wipe;
it is NOT the Level 2 synthetic-account lifecycle and not a flip-rehearsal build. It is out of this sequence.

Required before the rehearsal flip (R1), in this order:

1. Quiet-window control and active-session read (app code plus a runtime flag, default off). A runtime kill-switch that refuses
   NEW agent sessions with a maintenance message, and a counts-only read of live sessions per web host. Required, not optional,
   because the design allows a control OR a recorded owner acceptance, and the acceptance would be the owner accepting a
   stranded-user-work risk that this ruling can remove at a cost of days. Creating the flag in Flagsmith/Doppler is a production
   write and stays an owner act; the agent builds the code with the flag absent meaning "sessions allowed".
2. Rehearsal evidence collector: read-only script plus offline test (`scripts/followthroughs/git-data-rehearsal-evidence.sh`,
   the name from design-rollback-rehearsal.md section 5), reading `gh run view --json jobs`, the pinned Better Stack queries
   and the Sentry read token, printing the section 5 evidence block. Counts and run ids only.
3. Runbook edits (documentation only): replace the rehearsal paragraph with the run sheet in operator form, add the flag-on
   window blast-radius row, the expected red `proof` before the Level 2 deletion, the "no rotate or credential change inside
   the flag-on window and never after the flip" rule, and an explicit statement that Level 2 is an owner-run sequence.
4. Pre-flip live read-only verification record (a short dated file; no PR needed beyond the spec directory): the by-hand
   precondition reads of T1.
5. #10297: the rollback arm deletes `GIT_DATA_LUKS_CUTOVER_AT` with the same `DOPPLER_TOKEN_GIT_DATA_FLAG` token in the same
   `flag_write` step, with read-back and a hard failure (design-rollback-rehearsal.md section 6). Not a flip precondition. The
   token's DELETE permission is unverified: build against a stub and keep R8 (owner-gated delete with read-back) as the fallback.

Not built, with reasons. A scripted synthetic-account lifecycle: `POST /api/account/delete` needs the synthetic user's own
authenticated session, so a script would hold a standing production credential (and widen the credential census #8209 is
shrinking) to automate a two-step owner action; the 10-12 design allows "an explicit statement in the runbook that Level 2 is an
owner-run sequence". The `WORKTREE_ROOT` directory read (R3b): web-2 cannot be read at all, and with the item-1 control holding
refusal from before R1 until after R4, only the canary can create a tree; pre-existing trees are excluded by the rotate
precondition having passed on run 38583657167 (no flag-write step has ever run: `unverified` beyond that scan's own coverage). A flip
dry-run mode: see T1 rejected (d).

## T3. wipe_check `hooks` diagnostic

Facts. The off-list entry is a top-level directory named `hooks`: run 39136900735, `has_hooks_d=1 lf_entries=0 offlist_n=1`
(runbook "Reading the exit-34 line"). The CURRENT `git-data-bootstrap.sh` (steps 4 and 5) creates `$GIT_DATA_ROOT/hooks` as
`root:git 0750` and installs one file in it, `pre-receive` (the CAS fence). The CLO read the source history and found that this
volume (created 2026-09-14, host destroyed 2026-09-24) predates the CAS-fence install (`a96d123938`, 2026-09-30): its bootstrap
installed a FAIL-CLOSED PLACEHOLDER `pre-receive` (inferred from `git show d579d8b68d:...git-data-bootstrap.sh`; the payload the host
actually received is `unverified`). So no post may call the file "the fence hook". The wipe assert script is streamed to the host on stdin
(`git-data-cutover.sh` `body="$here/git-data-wipe-assert.sh"`), so a change to it needs no host rebuild.

Design (ruled). In `wipe_listing`, inside the existing snapshot window and before `wa_release`, add two fixed fields to the
existing `rc=34` line, after `offlist_n`:

- `hooks_pre_receive_f=<0|1>`: 1 iff the top-level directory `hooks` (type `d`, exact case-sensitive name, so `has_hooks_d=1`) contains an
  entry named exactly `pre-receive` that is a regular file. A symlink, directory or other type reads 0. Constant 0 when
  `has_hooks_d=0`.
- `hooks_other_n=<n>`: the recursive count of every entry under that directory other than that one regular file, by `find`
  without following symlinks. A non-recursive count would hide a nested tree. Constant 0 when `has_hooks_d=0`.

Naming (CTO call under CLO condition C8, adopted): the field is `hooks_pre_receive_f`, not `hooks_fence`, because it states a file
name and type, not a function. Add `-xdev` to the `find` (CLO suggestion, adopted).

Reading rule: only `has_hooks_d=1 hooks_pre_receive_f=1 hooks_other_n=0` says "the top-level directory `hooks` held exactly one
regular file named `pre-receive` and nothing else at any depth (links not followed); content, owner, mode and size unread"; every other combination is posted as fields only, with no inference. It is evidence toward a later path-typed
allowlist amendment and never an instance of one.

Constraints on the build. The classifier does not change: a `hooks` directory stays off-list and exit 34 stays. No name, hash,
size, mode, owner or content is read or printed; stderr stays digits and fixed words. A failed or timed-out `find` is
`die 33 <fixed word>`, never a 0. The two counts are taken before the `errors_count` re-read (`e1`) so the existing
"origin not changed" checks cover them. The loopback suite gets worlds in which the count is not a flag (the lesson of
`knowledge-base/project/learnings/2026-10-18-a-counter-field-needs-a-world-where-the-count-is-not-a-flag.md`): fence only; fence
plus one file; fence plus a nested directory holding a file; `pre-receive` as a symlink; `pre-receive` as a directory; empty
`hooks`; `hooks` as a file or symlink (`has_hooks_d=0`, both fields 0); and a count of 3 so `hooks_other_n` cannot be a boolean.
`RE_34` in `git-data-wipe-assert.test.sh`, the runbook closed field list and the script header move together, and a parity row
pins the three.

Merge gate. Build now. The CLO has ruled (below): the change may merge once it satisfies conditions C1 to C9 and the CLO's
implementation attestation at ship (a separate step against the merged diff); the field values leave the host into a PUBLIC run log
at run time, so the ruling must precede the merge, and it does. A further `wipe_check` is covered by CLO addendum 4 (Draft B), which
takes effect on the merge and is spent after one run; the owner still names the command and approves the environment.

Rejected alternatives. Widening the allowlist to admit `hooks`: the policy forbids it before evidence. Printing a size or a mode:
extra fields, each needing a CLO ruling, for no extra decision. Comparing `pre-receive` content to a known hash on host: reads
file content from a volume that may hold tenant data, and a hash is the kind of value the posting list forbids; keep as a
separate, later proposal only if the CLO asks for it. Reading the directory by hand over SSH: `hr-no-ssh-fallback-in-runbooks`.

CLO routing: see the section below.

## CLO routing

Ruled by CLO agent, 2026-10-19 (v1 internal attestation, not external counsel; design approval only, the implementation attestation
is a separate step at ship against the merged diff). The CLO's field name `hooks_fence` is `hooks_pre_receive_f` here (condition C8).

| Item | Class | Ruling |
|---|---|---|
| T3a-1 the two new fields stay inside the counts-only, no-name, no-hash posture | operator (legal-risk) | Ruled by CLO agent, 2026-10-19: yes under conditions C1 to C9, a recursive count is acceptable as one scalar because only digits leave the host and no less intrusive instrument answers "is anything else in there" |
| T3a-2 owner may post the already-measured reading `has_hooks_d=1 offlist_n=1 lf_entries=0` | operator (legal-risk) | Ruled by CLO agent, 2026-10-19: confirmed, already posted (comments 6251307334 on #6897 and 6251307584 on #9066, 2026-10-18); a repost uses Draft D and must not say "the platform's hooks directory", "nothing tenant-owned is meant to live there" or "the CAS fence" |
| T3a-3 posting list and runbook change before the new fields are posted | operator (legal-risk) | Ruled by CLO agent, 2026-10-19: yes to a dated CLO addendum 3 (Draft A, fires on merge) and the runbook edits C-1 to C-5, in the same PR as the code; no Art. 30 or LIA change; no ADR-239 amendment for fields |
| T3a-4 conditions for a later allowlist amendment admitting `hooks` | operator (legal-risk) | Ruled by CLO agent, 2026-10-19: shape-conditional admission only (on-list iff `hooks_pre_receive_f=1` and `hooks_other_n=0` in the same snapshot), `wipe_check` and `wipe` share one classifier, claim only what is measured, ADR-239 amendment appended and dated, no deadline-driven widening; all evidence questions wait for a run that reads that shape |
| T3a-5 a further `wipe_check` needs a new CLO addendum | operator (legal-risk) | Ruled by CLO agent, 2026-10-19: yes, issued now conditioned on the merge (Draft B, addendum 4), void if the merged script differs from the design; spent after one run; authorise the owner-named `gh workflow run git-data-cutover.yml --ref main -f mode=wipe_check -f confirm=WIPE-CHECK-GIT-DATA -f volume_id=106867358` with the owner approving the environment in their own session |

### Conditions the implementation must meet (CLO C1 to C9, merge-gate checklist)

- C1. Exactly two new fields, `hooks_pre_receive_f` then `hooks_other_n`, on the rc=34 line only, after `offlist_n`; validated `0|1` and `^[0-9]+$` before printing; nothing on any other line or stream.
- C2. Derived by `find` predicates (`-name <constant>`, `-type f`) and `-printf x | wc -c`; no name enters a shell variable for the `hooks` subtree; no content read (no `cat`, `head`, hashing, `stat -c`, or any `-printf` format other than `x`).
- C3. No symlink following (no `-L`, `-H`, `-follow`); `-xdev` added.
- C4. A `find` failure, timeout or non-digit result is `die 33 <fixed word>`, never 0.
- C5. Reads inside the existing snapshot window, before the `e1` errors-count re-read and before `wa_release`.
- C6. The constants `hooks` and `pre-receive` are exact, case-sensitive, with no glob characters.
- C7. No further field about the subtree (depth, per-level or per-type counts, size, mtime, mode, owner, hash, content-equality); each needs its own ruling.
- C8. Field names state a file name and type, not a function; no post glosses the file as "the fence hook" (done: renamed).
- C9. `RE_34`, the script header ("NO NAME LEAVES THE HOST" paragraph) and the runbook closed list move together under a parity row; the loopback suite adds the CTO worlds plus one world where a name under `hooks` contains a space or control character (it counts once) and a canary-name assertion that no fixture name appears in captured stdout or stderr.

### Drafted wording (CLO), for the owner to post or commit. Substitute `hooks_fence` with `hooks_pre_receive_f` everywhere

Draft A, CLO addendum 3 (new comment on #6897; earlier comments are not edited):

> CLO addendum 3 (2026-10-19; v1 internal attestation, not external counsel). Appended; addendum 2 and the corrections are not edited.
> Fires on the merge of PR #<N>, which adds two fields to the host's `rc=34` line. If the merged script differs from the CTO's design (T3), this addendum does not apply.
> 1. Fields: `hooks_pre_receive_f` (0|1) and `hooks_other_n` (a count). Both are derived on the host from names compared against two constants and are never printed. No name, hash, path, size, mode, owner or content leaves the host. Symlinks are not followed.
> 2. Definitions: `hooks_pre_receive_f=1` means the top-level directory `hooks` contains an entry named exactly `pre-receive` that is a regular file. `hooks_other_n` is the recursive count of every entry under `hooks` other than that one file. Both are 0 when there is no `hooks` directory.
> 3. Reading: only `has_hooks_d=1 hooks_pre_receive_f=1 hooks_other_n=0` is read as a shape, in the words of the runbook's table row. Every other combination is posted as the fields only, with no inference.
> 4. The reading is evidence toward, never an instance of, an allowlist change. The refusal stands. A change needs a CTO ruling, a dated CLO addendum, an ADR-239 amendment, and a ruling for any further field (shape-conditional admission, no "exact content" claim).
> 5. Posting: the owner posts the fields copied verbatim from the line, labelled measured, dated, with the run URL, on #6897 and #9066 the same day. An agent reads and reports to the owner and does not post.
> 6. No post glosses `hooks_pre_receive_f` as "the fence hook" or the directory as "the platform's". The file may be the host era's placeholder (inferred, source history). Do not claim "empty", "clean", "erased" or "purged".
> 7. A line that does not match the grammar exactly (including one field missing) is posted as the verdict word and the five counts only.

Draft B, CLO addendum 4 (post only after the merge; fill `<SHA>`):

> CLO addendum 4 (2026-10-19; v1 internal attestation, not external counsel). C1 is lifted for ONE further run of mode=wipe_check only (wipe, wipe_finish and snapshot_clear stay held). It applies only if `main` at dispatch contains PR #<N> (merge `<SHA>`) and the script's rc=34 line carries `hooks_pre_receive_f` and `hooks_other_n`.
> 1. Command, exactly: `gh workflow run git-data-cutover.yml --ref main -f mode=wipe_check -f confirm=WIPE-CHECK-GIT-DATA -f volume_id=106867358`. The owner approves the environment in the owner's own session; an agent never approves.
> 2. Closed posting list: the verdict word, top_d, top_f, top_l, top_o, repos, has_hooks_d (0|1), lf_entries, offlist_n, hooks_pre_receive_f (0|1), hooks_other_n and, only if the run reaches them, lock_residue and store_root_repos. Each is labelled measured, dated, with the run URL, and read only through the runbook's "Reading the exit-34 line" table.
> 3. A line that does not match that grammar is posted as the verdict word and the five counts only.
> 4. Never post or infer a listing name, an owner or contents. Do not claim "empty", "clean", "erased" or "purged".
> 5. Post to #6897 and #9066 the same day. repos>0, or any nonzero or `na` residue count, goes to the CLO before 2026-10-24. Expect exit 34 and no residue counts: that is a valid result.
> 6. The allowlist is not widened.
> 7. This lift is spent after one run; any further run needs a new addendum. The DPD 10.3(b) re-ruling stays due 2026-10-24.

Draft D, permitted form of the already-measured reading:

> Measured 2026-10-18, run https://github.com/jikig-ai/soleur/actions/runs/39136900735 (mode=wipe_check, read-only): `has_hooks_d=1 offlist_n=1 lf_entries=0`. The only off-list entry is a directory named `hooks`, a name the bootstrap uses (inherited from `git-data-bootstrap.sh`). The bit proves the name only, not who created the entry or what it holds; its owner and contents are unread. This is not an emptiness reading and not a basis to widen the allowlist.

Runbook edits in `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`, same PR as the code (cite by section, not line):

- C-1. In the paragraph "Other results that route to the CLO", replace the closed-list sentence with: "For an off-allowlist result (`wipe_boot_layout_signal_offlist`), post the verdict word and, copied verbatim from the `wipe-assert: rc=34` line, only these fixed fields: `top_d`, `top_f`, `top_l`, `top_o`, `repos`, `has_hooks_d` (0 or 1), `lf_entries`, `offlist_n`, `hooks_pre_receive_f` (0 or 1) and `hooks_other_n`. These are counts and two booleans. `hooks_pre_receive_f` and `hooks_other_n` are posted only from the merge of the change that adds them (CLO ruling, 2026-10-19). Never post, quote, paraphrase, hash or guess a listing name, and never any field outside this list." Append under the old sentence: "> **Superseded 2026-10-19 (#6897), as to the eight-field list:** the list now also names `hooks_pre_receive_f` and `hooks_other_n`, from the merge of the change that adds them; see CLO addendum 3. The earlier list stands for any line printed before that merge."
- C-2. Replace "The last three fields appear only from the merge of the change that adds them" with: "`has_hooks_d`, `lf_entries` and `offlist_n` appear from the merge of #10480 (measured in run 39136900735). `hooks_pre_receive_f` and `hooks_other_n` appear only from the merge of the change that adds them; a line without them is read through the first row of the table below. A line with exactly one of the two, or any extra token, does not match the grammar and is posted as the verdict word and the five counts only."
- C-3. Definition bullets after `offlist_n`: "`hooks_pre_receive_f`: 1 if and only if the top-level directory `hooks` contains an entry named exactly `pre-receive` that is a regular file (a symbolic link, directory or other type reads 0); 0 when there is no top-level `hooks` directory. The field name states a file name and type, not a function: the file is not shown to be the platform's fence hook, and on this volume the host era's bootstrap installed a placeholder hook (inferred from source history; the payload the host received is `unverified`)." and "`hooks_other_n`: the count of every entry under the top-level `hooks` directory, at any depth, other than that one regular file, counted without following symbolic links; 0 when there is no `hooks` directory. A count at one moment in the transient snapshot; not a flag."
- C-4. New table rows: (a) `has_hooks_d=1 hooks_pre_receive_f=1 hooks_other_n=0`: "in the snapshot, the top-level directory `hooks` held exactly one entry, a regular file named `pre-receive`, and nothing else at any depth (links not followed). The file's content, owner, mode and size are unread, and the name does not show who put it there. This is evidence toward, never an instance of, an allowlist change; the refusal stands. Read `offlist_n` separately through the first row."; (b) `has_hooks_d=1` with any other value of the two new fields: "post the fields only; make no inference about which entries they are"; (c) `has_hooks_d=0` with `hooks_pre_receive_f=1` or `hooks_other_n>=1`: "both fields are constant 0 when there is no `hooks` directory: an instrument fault, route to the CTO".
- C-5. Append to the first existing row "For a line without `hooks_pre_receive_f` and `hooks_other_n`." and add under it: "> **Superseded 2026-10-19 (#6897), as to 'its owner and contents are unread' for a line that carries the two new fields:** entry names and types under `hooks` were counted on the host and no file content was read; owner, mode and content remain unread." Also append `Superseded` markers under every sibling file that quotes a superseded sentence (grep `knowledge-base/project/specs/**`, and the #6897 and #9066 corrections).

CLO notes that bind this stream. (1) Residue counts (`lock_residue`, `store_root_repos`) stay unmeasured because exit 34 stops before them, so the 2026-10-24 re-ruling proceeds on "unmeasured" inputs with no "erased" or "purged" wording. (2) Deadline pressure (2026-11-12 outer date, 2026-10-22 ledger date) is not a justification for widening the allowlist; a second slip returns to the CLO. (3) Unverified: the merged implementation, the payload the retired host received, and whether anyone else wrote to `hooks`.

## Operator Holds (text for the plan phase; no plan file exists on this branch yet)

No Standing Delegation exists, so there is no `Delegation:` or `Envelope:` line and the evaluator takes its legacy path (exit 3).
Gate lines are added by the plan phase when the build PR numbers exist; until then each hold stands and needs a person.

- Hold: do not mark #10535 ready or merge it until the quiet-window control, the rehearsal evidence collector and the runbook edits (T2 builds 1 to 3) are merged and the dated live read of the other flip preconditions (T2 build 4) is committed.
  Gate: pr-merged <N of T2 build 1>
  Gate: pr-merged <N of T2 build 2>
  Gate: pr-merged <N of T2 build 3>
- Hold: Operator-reserved: the owner names each production dispatch (rehearsal flip, rollback, exit read, every wipe mode) and approves its environment in their own session.

## Standing delegation offer (for the calling skill to ask; the CTO never records it)

Outcome: the flip rehearsal and the plaintext-volume retirement of #8211 move forward without you being asked technical questions; the merges of the preparation changes can be carried out on your standing approval.
Scope items (one per line, each names its target):

1. merge pull request #10535 (the fix that makes the flip check read the pin-fault alert from the right Sentry address) with a squash merge, only after the preparation changes ahead of it have merged
2. ready pull request #10535

Expiry: 2026-11-04. Not in scope and never delegable here: every flip, rollback, proof and wipe dispatch (a flag-on window can strand a customer's only copy of work, and the wipe destroys a volume), and every terraform apply. New preparation pull requests need their numbers added by a fresh delegation, because a Scope item must name its target.

## Addendum 2026-10-19 (review of PR #10565): forks the run sheet surfaced

Nothing here dispatched a workflow, applied terraform or wrote production state. The runbook run sheet carries the wording.

- **D6 and the real flip.** Ruled by CTO agent, 2026-10-19: a fresh replace plus a `GIT_DATA_LUKS_KEY` rotation is required before the FIRST
  flip of any kind, which is the rehearsal; the rehearsal flip executes the flag-write step, so the rotate guard (`store_dirty`) refuses every
  later rotate and the real cutover rides the 2026-10-14 stamp (run 38583657167). D6's "nothing planted survives" is established only as of that
  rotate; the rehearsal's R7 `proof` `clear`, the pin fingerprint match and the heartbeat cover the period since, not a fresh host. Follow-ups
  for the owner or an agent to file: the stale `d6_replace_stale` remedy text in `git-data-cutover.yml`; a dated ADR-220 D6 amendment.
- **Per-id re-erasure precondition (#8211).** Ruled by CTO agent, 2026-10-19: NARROWED, not waived, for the rehearsal flip (discharged only while the
  built session-refusal control is on from before R1 to after R4 with session counts of 0, because then the store can hold only the synthetic
  account's repository, which R6 and R7 erase and re-prove empty; owner acceptance of stranded-work risk alone does not discharge it). For the REAL
  flip it stands in full, in two parts, neither built: a per-id re-erasure path, and reaping of the flag-resolved `WORKTREE_ROOT` tree on account
  deletion (`deleteWorkspace` removes only `<workspaces root>/<id>`). Follow-up to file: the second part, and a mount for `WORKTREE_ROOT`.
- **`WORKTREE_ROOT`.** Ruled by CTO agent, 2026-10-19: R0 adds a names-only listing of the `prd` Doppler config for `WORKTREE_ROOT`; the tree is lost
  with the old container at the rollback redeploy (not merely unreachable by path). This is a configuration name check and does not reopen the
  rejected directory read.
- **Art. 17 in the window.** Ruled by CLO agent, 2026-10-19 (v1 internal attestation, not external counsel): the rehearsal flip may proceed with the
  per-id path unbuilt on three conditions (the built control holds, shown per host before R1 and before R4; R7 reads `clear`; the runbook carries the
  carve-out wording), a request received in the window is recorded as "received in window, bounded by R4, not observed erased", any failed read opens a
  `clo-attestation` issue with the Art. 12(3) deadline in its title, and the owner's acceptance covers the production-flip risk, not an Art. 17
  shortfall. The CLO suggested an audit record under `knowledge-base/legal/audits/` (`2026-10-19-clo-ruling-8211-rehearsal-art17-window.md`); this PR
  edits no legal document, so that record is left to the owner to request.
