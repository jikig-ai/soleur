---
title: "feat(git-data-cutover): the read-only proof passes on a verified LUKS-served store (#8211 PR2, proof half)"
date: 2026-09-27
slug: feat-git-data-cutover-proof-on-luks-mapper
branch: feat-one-shot-8211-pr2-cutover-proof-already-cut-over
issue: 8211
closes: []
type: feat
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# git-data cutover: the read-only proof passes on a verified LUKS-served store

## Enhancement Summary

**Deepened on:** 2026-09-27

**Sections enhanced:**

- Technical Approach (Phases 1-5);
- Host-key step 5 evidence chain;
- Does merging mutate production;
- Observability;
- Guard Contract;
- Acceptance Criteria;
- Test Scenarios;
- Risks.

**Agents used:**

- soleur:engineering:review:security-sentinel
- soleur:engineering:review:test-design-reviewer
- soleur:engineering:review:observability-coverage-reviewer
- soleur:engineering:review:user-impact-reviewer
- soleur:engineering:research:git-history-analyzer
- a verify-the-negative and post-edit self-audit sweep

These came on top of the plan-phase panel: learnings-researcher, cto (twice), clo, cpo,
spec-flow-analyzer (twice), a scoped advisor, dhh-rails-reviewer, kieran-rails-reviewer,
code-simplicity-reviewer and architecture-strategist.

### Key Improvements

1. **The step-5 Art. 17 evidence chain is fail-closed.**
   - (b) binds to the instance's `boot_complete` line and the replace-run chain, not to the marker.
   - (c) pages the flag history back past the older volume's creation, across every Doppler config
     the web containers load.
   - The discharge wording is scoped to the git-data store.
   - An unreadable line or a short paging discharges nothing.
2. **Floors are exact.** Both checks use `-ne`, and `MUTANT_FLOOR` is computed from the matrices
   before it is measured. A missing matrix row can no longer be baked into the floor.
3. **RB checks the script-to-runbook coverage in both directions**, with two independent producers,
   and has its own mutants. P3 parity runs over copied directories and has mutants too.
4. **Security:**
   - the remote prefix is plain `%q` assignments, with `fz` single-quoted;
   - `LUKS_MAPPER` is validated (`arg_mapper`);
   - the operator's approval is the single human input for PM1;
   - a workflow-command injection row (VINJ) was added.
5. **Observability:** every failure mode cites layer 6 (the workflow-run log), and the false-clear
   mode is covered by the mutants going RED in CI.

### New Considerations Discovered

- A marker from an earlier bootstrap run can outlive a failed re-run, so the marker alone is never
  the binding evidence.
- Counting entries cannot see a repository that was written and then deleted. Only the flag's
  history since the volume was created excludes one.
- The earlier "precedent" commit 707c7d072d was wrong: that release failed. The production-effect
  claim now rests on the release workflow's own `path_filter`.
- The `origin/main` base is 2619b4f5f8. e99a0b8b81 is this branch's init commit.

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

Since ADR-239 (PR1 of #8211, PR #8564) the git-data host serves `/mnt/git-data` from the LUKS
mapper `/dev/mapper/git-data` from boot. Replace run 36118115758 put that layout into production.
The read-only dry run in `apps/web-platform/infra/git-data-cutover.sh` still asks the pre-PR1
question ("is the store still on a plaintext device?"). It therefore refuses every run with
`probe=store-not-cut-over verdict=already_cut_over` (exit 5) before it evaluates `store_not_empty`
(run 36119817656 is one). That blocks host-key post-merge step 5 in
`git-data-luks-cutover-5274.md`: the step discharges pending Art. 17 erasures by pointing at a dry
run that cleared `store_not_empty`, and no run can reach that probe today.

This plan rebuilds the proof for the layout that now exists. It does not simply invert the
refusal. After the change:

- a store that is **not** served by the LUKS mapper is refused (`store_not_on_mapper`), because
  ADR-239 D1 says the render never produces one;
- a mapper-served store passes only on **positive evidence**, read in one SSH session:
  - `/etc/git-data/store-verified` holds the UUID of the filesystem mounted at `/mnt/git-data`.
    That is the same positive marker every store-acting wrapper requires (ADR-239 D3), and the
    bootstrap writes it only after its boot proofs pass. It writes it on a mapper that it opened
    with `cryptsetup luksOpen`, and only after `cryptsetup isLuks` accepted the device;
  - the cutover freeze sentinel is absent. #8211 asks for this probe explicitly.
- the existing emptiness count and fence probe then run against the mapper as the accepted source.
  This is #8101's "fence probe passes on `/mnt/git-data` with the mapper expected".

**Scope: the proof half of PR2.** The PR1 plan (`2026-09-22-feat-git-data-cutover-real-modes-plan.md`
§Phase B) lists PR2 as five parts:

1. the real modes: `proof`, `flip`, and a flag-off-only `rollback`;
2. the same-version redeploy in `dispatch-web-redeploy/`;
3. the in-container `git_data_store=` startup line;
4. the ADR-220 D6 fresh replace with the LUKS key and volume rotation;
5. the ADR-237 D6 amendment.

Items 2 to 5, and the flip and rollback half of item 1, are blocked on open preconditions: #8209,
#5914, #8572 and #8573. Every one of those would refuse in production today. The proof has no such
blocker, and it is what unblocks runbook step 5. So this PR delivers the `proof` generalization
("PR2 generalizes `proof` to read it as a pass", PR1 plan §Operator sequence and runbook verdict
map). The flip, rollback, redeploy and D6 replace stay open on #8211 as its follow-on. The PR says
`Ref #8211`, never `Closes`. The real modes keep refusing with `verdict=real_cutover_unreconciled`.

## Research Reconciliation — Spec vs. Codebase

| Claim (task / prior docs) | Reality on `origin/main` (2619b4f5f8) | Plan response |
|---|---|---|
| "Make the proof step treat `already_cut_over` as a pass" | A bare flip of `!=` to `=` would pass any mapper-named source, including a non-crypt dm device or a mapper whose bootstrap FATALed before writing the marker. | The flip is paired with the `store-verified` probe. A pass needs the mapper, the bootstrap's marker bound to the mounted filesystem, and no freeze sentinel. |
| Header comment "expected until PR2 rebuilds the proof" (`git-data-cutover.sh:34`) | #8211's issue body never says "PR2". PR2 is defined in the PR1 plan's Phase B, as five parts. | This PR is the proof half. The rest stays tracked on #8211. The split is recorded in an ADR-239 amendment and in the script header. |
| Tests pin exit 5 at S5/G2 (`case_mapper`, lines ~663/697) and R7 (~2002) | Also pinned: AC2's exact remote timeline and annotation set (`src=/dev/sdb`, `store-not-cut-over`), H5 main order, mutants `g2-no-cut-over` and `g5-raw-capture` (their sed anchors match the deleted lines), FSRC and `f-m17` (`/dev/nvme1n1`, `/dev/sdb`), P2 (it pins the `OLD_ROOT` line, comment included), runtime R5/R5b/R5c/R7/RFSRC (this plan deletes RFSRC), and both floors. | Every pinned site is in Files to Edit (below), and the floors are re-derived. |
| Runbook step 5 "Blocked on #8211 PR2" | Correct. Step 5.2 also names "the step-4 dry run clearing `store_not_empty`", which never happened. | Rewrite step 5.2 to name a post-merge dry run, and add the new verdicts to the verdict map. |
| C4: "the run only reads the store (mounted, not cut over, empty)" (`model.c4`, the git-data-cutover edge) | This becomes false. | Edit the edge prose and regenerate `model.likec4.json`. |

## Research Insights

**Premise validation (Phase 0.6).**

- #8211 is OPEN, with no PR-closing reference.
- PR #9048 is this branch's draft.
- ADR-237 was flipped to accepted by 5d0c57f677 (#9036), which is on `origin/main`.
- The refusal line is at `git-data-cutover.sh:359`: `[ "$STORE_SOURCE" != "$LUKS_MAPPER" ] || _store_refuse store-not-cut-over already_cut_over`.
- Open preconditions: #8101 (tests-only overlap), #8209, #5914, #8571, #8572, #8573. #8210 and #7226
  are CLOSED.
- #8634 is a legal attestation issue. Its audit is not touched (operator constraint).
- The runbook confirms production serves the mapper: replace run 36118115758, then dry run
  36119817656 exited 5 on `already_cut_over`.
- No stale premise was found.

**Property List (Phase 0.6b).**

- P1: after this merges, a dispatch of `git-data-cutover.yml` from `main` against production exits 0
  with `verdict=clear` when git-data serves an empty, fenced, bootstrap-verified LUKS store.
- P2: the proof exits 5 with a named verdict when the store is served by anything other than the
  configured mapper.
- P3: a pass is backed by evidence read from the host in one session: the store is served by the
  mapper, the wrappers' marker is bound to the mounted filesystem, and the freeze sentinel is
  absent. It is
  never backed by the absence of a refusal.
- P4: the emptiness count and the fence probe keep their current semantics against the mapper as
  the accepted source.
- P5: runbook step 5 names a dry run that can actually clear `store_not_empty`. The verdict map
  renders every new verdict.
- P6: the real modes still refuse (`real_cutover_unreconciled`, exit 5, empty remote timeline).

**Cut List (Phase 0.6b).**

- A separate LUKS2 check, either `cryptsetup status` or the dm UUID prefix through
  `dmsetup info -c --noheadings -o uuid`. It was **cut at plan review**, where DHH and
  code-simplicity converged and the correctness findings on its argv and ARG rows dissolved with the
  cut.
  - A bound marker already implies LUKS. The bootstrap opens the mapper only after
    `cryptsetup isLuks` accepts the device (`git-data-bootstrap.sh`, the luksOpen block), and it
    writes the marker only after that.
  - The only case the check adds is post-boot tampering by root, which the proof does not defend
    against in any case.
  - Step 5 rests on emptiness, not encryption, and the CLO requires the proof not to assert
    encryption.
  - This cut is recorded as a Taste decision in `decision-challenges.md`.
- Re-checking the installed wrappers' mapper assertion (#8101 item b). That is the **pre-flip**
  check. It belongs to `flip`, which is not built here and stays on #8211.
- Renaming `OLD_ROOT` and `old_store_unmounted`. This is cosmetic, would widen the diff across the
  runbook and two ADRs, and buys no property. Only the stale `OLD_ROOT` comment is corrected.
- Asserting that the plaintext volume is unmounted. The bound marker already implies the boot's
  plaintext count passed, and ADR-239 D2 keeps that volume unmounted (CTO).
- Calling the wrappers' own verification. There is no extractable helper: the check is inline in
  each wrapper. Running a wrapper is a write path (a lock dotfile), which a read-only proof must not
  take (advisor).
- Aligning the `*.git` count with the bootstrap's full-entry `_repo_count`. The two emptiness checks
  differ. The chain "marker bound, so the boot's full count was 0; the flag has been off since; now
  `*.git` = 0" covers the difference. Changing the count would alter an existing verdict for no new
  property (CTO).
- A new standalone "freeze-absent" probe with its own SSH session. It is folded into the
  `store-verified` session, because one login attests the whole verified state.

**Mechanisms on `origin/main` reused, not rebuilt.**

- `gd_capture`: bounded, anchored, never prints the value.
- `_store_emit` and `_store_refuse`.
- The count probe's same-session source re-check (exit 6), reused for the new probe.
- The wrappers' marker contract, `git-data-provision.sh:79-84`:
  - `STORE_DEVICE=/dev/mapper/git-data`;
  - `STORE_VERIFIED=/etc/git-data/store-verified`;
  - `head -n 1` must equal `findmnt -n -o UUID --mountpoint`.
- The marker's only writer, `git-data-bootstrap.sh` step 5a. It writes the **filesystem** UUID
  (`findmnt -n -o UUID --mountpoint`) with `printf '%s\n'`, only after the plaintext and served
  full-entry counts and the fence-on-mapper check pass. It removes the marker if the boot erasure
  probe fails.
- The freeze sentinel `<root>/.cutover-freeze`, defined in four places:
  - provision, remove and transport-wrapper use `${MOUNT_ROOT}`;
  - pre-receive uses `${GIT_DATA_ROOT}`.

**Relevant files.**

- `apps/web-platform/infra/git-data-cutover.sh`:
  - header, lines 1-60;
  - `refuse_if_cut_over`, lines 356-361;
  - `refuse_if_store_not_empty`, lines 376-387;
  - `refuse_if_fence_not_intact`, lines 415-476;
  - `main`, lines 481-493.
- `apps/web-platform/infra/git-data-cutover-access.test.sh`:
  - shims, lines 108-222;
  - `run_case` and `mutate`, lines 266-320;
  - AC2, lines 613-650;
  - Guard 2, lines 652-780;
  - fence, lines 784-1003;
  - the mutation battery, lines ~1530-1745;
  - the runtime arm, lines 1745-2030;
  - the floors, lines 2030-2061.
- `.github/workflows/git-data-cutover.yml`: header items 4-5, lines 10-14.
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`:
  - preconditions, lines 14-59;
  - "What the read-only dispatch does", lines 61-110;
  - host-key step 5, lines 248-258;
  - the verdict map, lines 530-570.
- `knowledge-base/engineering/architecture/decisions/ADR-239-git-data-serves-from-luks-at-birth.md`,
  which gets a dated amendment.
- `knowledge-base/engineering/architecture/diagrams/model.c4`: the git-data-cutover edge prose, and
  the regenerated `model.likec4.json`.

**Institutional learnings applied.**

- `knowledge-base/project/learnings/2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md`: floors come from independent
  producers, and every mutant must land on an exact diff-line count. `mutate()` already enforces
  landing. Re-derive `MUTANT_FLOOR` and `FLOOR` by counting, never by adding deltas in your head.
- `knowledge-base/project/learnings/2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`: every new
  refusal has a must-RED fixture, and there is a must-PASS row that is not the canonical input.
- `knowledge-base/project/learnings/2026-09-20-the-ops-only-green-verdict-claimed-a-fact-the-gate-never-measured.md`: the `clear` verdict
  must claim only what the probes measured. The final log line is rewritten to list exactly the
  facts read. The runbook verdict map renders every new exit or reason.
- `knowledge-base/project/learnings/2026-09-08-the-guard-was-deleted-the-plan-still-cited-it-and-the-linter-validated-the-citation.md`: deleting `refuse_if_cut_over`
  cascades to every citing doc. The runbook, the workflow header and C4 are in scope. ADR-220's
  and ADR-237's dated addenda are historical records and are **not** rewritten; the ADR-239
  amendment supersedes them going forward.
- `knowledge-base/project/learnings/2026-06-18-c4-impact-requires-reading-all-diagrams-and-enumerating-external-actors.md`: the C4 edge prose is edited, the json is
  regenerated, and `c4-count-parity` and the render tests are run.
- `knowledge-base/project/learnings/2026-09-27-a-log-line-is-evidence-about-the-step-that-printed-it.md`: when the post-merge dry run is
  cited as evidence, cite each verdict by the `##[group]Run` step that printed it.
- `knowledge-base/project/learnings/2026-09-07-the-guard-i-wrote-died-on-the-case-it-was-written-to-catch.md`: run
  `scripts/lint-shell-capture-exit.py` over the script. `refuse_if_store_unverified` must reach its
  `_store_refuse` on every failure shape, and never die inside a `$( )`.

**CLAUDE.md / AGENTS.md conventions applied.**

- `hr-no-ssh-fallback-in-runbooks`: every runbook read is a workflow annotation.
- `cq-cite-content-anchor-not-line-number`: runbook and ADR prose cite anchors, not line numbers.
- `cq-test-fixtures-synthesized-only`.
- `wg-use-closes-n-in-pr-body-not-title-to`: the PR says `Ref #8211`.
- Commit with `LEFTHOOK_EXCLUDE=bun-test,plugin-component-test`, and rely on CI for the suite,
  because the machine is contended (operator constraint).

## Open Code-Review Overlap

None. The check ran on 2026-09-27 against open `code-review` issues for every path in Files to Edit.

## Technical Approach

The phase order follows the advisor and Kieran. Behaviour rows come first, then the script, then
the runtime arm. Sed-anchored mutants and floors come **last**, written against the real text and
measured once the row set is final. Commit each phase with
`LEFTHOOK_EXCLUDE=bun-test,plugin-component-test`.

### Phase 1 — flip the canonical fixture (mechanical, suite only)

All edits are in `apps/web-platform/infra/git-data-cutover-access.test.sh`.

1. **The `ssh` shim.**
   - The `findmnt -no SOURCE` default flips from `dev` (`/dev/sdb`) to `mapper`
     (`/dev/mapper/git-data`).
   - Add three modes:
     - `plain` answers `/dev/sdb`;
     - `mapperalt` answers `/dev/mapper/gd-alt`;
     - `mapperpre` answers `/dev/mapper/git-data-plain`.
   - `noeol` now answers `/dev/mapper/git-data` with no trailing newline, so H2 (`g2noeol`) keeps
     exiting 0.
2. **The `findmnt` shim.**
   - The `-T` default becomes `/dev/mapper/git-data`.
   - It answers `-no UUID <path>` from `SHIM_FINDMNT_UUID`. The default is a synthesized UUID; the
     value can also be `empty` or `fail`.
   - It answers positional `-no SOURCE <path>` from `SHIM_FINDMNT_S`. The default is the mapper; a
     two-line value simulates an over-mount.
3. **An `r=*` arm in the `ssh` shim**, for the new probe command. It is keyed on the command's first
   token, the way `d=` and `h=` are. `SHIM_VERIFY=ok|r<n>|line2|empty|notok|exec` mirrors `SHIM_FENCE`. `SHIM_VERIFY_STDERR` injects
   remote stderr for the injection row.
   The default is `ok`, so pre-existing rows keep reaching the count and the fence.
4. **`VX-*` (executed) rows always set fixture values.** They set `OLD_ROOT` to a fixture root
   under `$T` and `STORE_VERIFIED` to a fixture file under `$T`. They must never read the CI
   runner's real `/mnt/git-data` or `/etc/git-data`.
5. **Mechanical renames and value flips.**
   - Rename every `has_store store-not-cut-over ok` to the two new probes.
   - AC2's expected timeline:
     - it gains the verify command;
     - `src=/dev/mapper/git-data` replaces `src=/dev/sdb` in the count and the fence;
     - it has 7 SSH lines, 7 `timeout` entries and 7 `/dev/null` stdins.
   - AC2's annotation set has 9 lines: 3 access, `store-mounted`, `store-on-mapper`,
     `store-verified`, `store-empty`, `fence-shape`, and `verdict=clear`. The mapper device name is
     never printed. RVM covers the UUID and the marker content at runtime.
   - H5 `case_main_order`: the literal call list and its regex alternation are updated together.
     The list is `refuse_real_modes,resolve_roster,access_gate,refuse_if_unmounted,refuse_if_not_on_mapper,refuse_if_store_unverified,refuse_if_store_not_empty,refuse_if_fence_not_intact`.
   - FSRC becomes the alt-mapper unit row: `LUKS_MAPPER=/dev/mapper/gd-alt SHIM_FINDMNT=mapperalt`
     fence-probes with `src=/dev/mapper/gd-alt` and clears.
   - `_fence_call`'s `STORE_SOURCE=/dev/sdb` becomes the mapper.
   - P2 changes in tandem with the corrected `OLD_ROOT` comment line (Phase 3).
   - The `mutating()` helper is **not** widened. It matches `mountpoint`, which is why the proof
     uses positional `findmnt`. Add a comment saying so.

This commit is expected RED against the current script.

### Phase 2 — behaviour rows for the new probes (RED)

Add every unit row in the Test Scenarios table, plus:

1. **P3 parity.** The definer populations are **derived** over
   `apps/web-platform/infra/git-data-*.sh`, excluding `*.test.sh` and the cutover script itself.
   They are never listed by hand.

   | Default | Definers today | How they are compared |
   |---|---|---|
   | `^STORE_DEVICE=` | 5 | each must equal the script's `LUKS_MAPPER` default |
   | `^STORE_VERIFIED=` | 5 | each must equal the script's `STORE_VERIFIED` default |
   | `^cutover_freeze=` | 4 | on the `/.cutover-freeze` **suffix** |
   | `^(MOUNT_ROOT\|GIT_DATA_ROOT)=` | 6 | each must equal `OLD_ROOT`'s `/mnt/git-data` |

   - The `STORE_DEVICE` and `STORE_VERIFIED` definers are bootstrap, gc, provision, remove and
     transport-wrapper.
   - The `cutover_freeze` definers are pre-receive (`${GIT_DATA_ROOT}`), provision, remove and
     transport-wrapper (`${MOUNT_ROOT}`).
   - Each floor is paired with set identity. Each definer must yield a non-empty value, because two
     empty extractions never compare equal.
   - Write the check as `case_parity <script> <dir>`, run over a **copied** directory, because
     tracked definers must never be mutated in place. Each of these mutants must go RED
     (test-design P1-5):
     - the script's `LUKS_MAPPER` default flipped;
     - one definer copy's `STORE_VERIFIED` flipped;
     - an extra definer added with a different default.
   - Name the override-variable difference in a comment. The wrappers read
     `GIT_DATA_STORE_VERIFIED` and `GIT_DATA_CUTOVER_FREEZE`. The proof ignores those, because a
     host-side override is invisible to it.
2. **RB: runbook coverage, checked in both directions** (CTO devex; test-design P0-2).
   - **Scope.** The store-probe verdict and reason words. Access-gate words and
     `real_cutover_unreconciled` do not go through `_store_*`, and the row says so.
   - **Producer 1 (script).** Tokenize the `_store_refuse` and `_store_emit` lines with `read -ra`,
     keeping the literal `[a-z_]+` tokens in positions 2 and 4. Add every `reason=([a-z_]+)` from the
     `case` arms.
   - **Producer 2 (observed).** The union of the `STORE … verdict=X( reason=Y)?` lines printed by
     every unit row.
   - **The two producers must yield equal sets, and each must equal a pinned count.**
   - **Runbook side.** Read only the verdict-map section, with an awk flag range between its heading
     and the next `##` heading. Match with word boundaries (`[^A-Za-z0-9_]`), so `a|b|c` cells match.
   - **Forward:** every script word appears in the map.
   - **Reverse:** every store-probe word in the map is emitted by the script. This is what catches a
     stale `already_cut_over` row.
   - **Mutants.** `case_rb <script> <runbook>` runs on copies, and each of these must go RED:
     - drop one word from the runbook copy;
     - add a new `_store_refuse` word to the script copy;
     - rename a `reason=` word in a script-copy `case` arm.

### Phase 3 — the script (GREEN)

`apps/web-platform/infra/git-data-cutover.sh`:

1. **Configuration.**
   - Add `STORE_VERIFIED="${STORE_VERIFIED:-/etc/git-data/store-verified}"`. Its comment names the
     wrappers' identical default and the only writer, `git-data-bootstrap.sh` step 5a.
   - The `OLD_ROOT` comment becomes `# the store root every wrapper hardcodes (LUKS-served since ADR-239)`.
   - The `LUKS_MAPPER` comment becomes "the device that must serve the store".
2. **Replace `refuse_if_cut_over` with `refuse_if_not_on_mapper`** (probe `store-on-mapper`).
   - An empty `STORE_SOURCE` is `probe_failed`.
   - First, before the comparison, `LUKS_MAPPER` must match `^/dev/[A-Za-z0-9/_.-]+$`, else
     `probe=store-on-mapper verdict=probe_failed reason=arg_mapper`. It is an environment-overridable
     value, and a control byte would make `%q` emit a bash-only `$'…'` form (security P2-a).
   - Anything not string-equal to `$LUKS_MAPPER` is `store_not_on_mapper`.
   - Otherwise the result is `ok`.
3. **Add `refuse_if_store_unverified`** (probe `store-verified`).
   - It runs one `gd_capture '^ok$'` session.
   - The command is a `c=( … )` array joined by semicolons, like the fence probe's. Every element
     is single-quoted except the `%q`-built prefix, so the count probe's `c3-*` mutants cannot land
     on it.
   - Before anything is printed or dialed, it checks its arguments locally, with the fence probe's
     regex and reason words:
     - `OLD_ROOT` must match `^/[A-Za-z0-9/_.-]+$`, else `reason=arg_root`;
     - `STORE_VERIFIED` must match the same regex, else `reason=arg_marker`.
   - **The prefix is plain `%q` assignments only: `"r=$qr; src=$qs; mk=$qm"`** (security P1-a).
     - `src` is `STORE_SOURCE`. It is re-checked locally against `^/dev/[A-Za-z0-9/_.-]+$` right
       before `printf %q`, as `refuse_if_store_not_empty` does.
     - `fz="$r/.cutover-freeze"` is its own **single-quoted** array element, so `$r` can never
       expand on the runner.

   The remote command, in order, after that prefix:

   ```sh
   s=$(findmnt -no SOURCE "$r") || exit 5; [ "$s" = "$src" ] || exit 6
   fu=$(findmnt -no UUID "$r") || exit 5; [ -n "$fu" ] || exit 24
   [ -f "$mk" ] && [ -s "$mk" ] || exit 21
   m=$(head -n 1 "$mk") || exit 16; [ "$m" = "$fu" ] || exit 22
   [ ! -e "$fz" ] || exit 23
   echo ok
   ```

   The marker and freeze tests are exactly as strict as the wrappers:

   - `[ -f ]` and `[ -e ]` follow symlinks, as the wrappers' `[ -s ]`, `head` and `[ -e ]` do.
   - A symlink to a correct marker passes in both.
   - A directory at the marker path is refused by both: the proof says `marker_absent`, and the
     wrapper's `head` fails.
   - A dangling freeze symlink passes in both.

   So every refusal below also means the wrappers are refusing, and the proof is never stricter
   than the runtime gate it mirrors.

   Local mapping, in a `case` with an explicit `*)` arm:

   | Remote rc | Verdict | What it means on the host |
   |---|---|---|
   | 0 | `ok` | — |
   | 24 | `store_unverified reason=no_fs_uuid` | Every wrapper refuses **now**. Incident. |
   | 21 | `store_unverified reason=marker_absent` | Every wrapper refuses **now**. A boot FATAL (the marker is removed on an erasure-probe failure), or the marker was removed. |
   | 22 | `store_unverified reason=marker_mismatch` | Every wrapper refuses **now**. A mapper reopened on another volume, a writer defect, or tampering. |
   | 23 | `cutover_frozen` | Provision, remove, the transport wrapper (pushes and fetches) and pre-receive all refuse **now**. |
   | 5 | `probe_failed rc=5` | `findmnt` could not read the SOURCE or the UUID. |
   | 6 | `probe_failed rc=6` | The source changed since `store-mounted`, or something was over-mounted during the run. |
   | 16 | `probe_failed rc=16` | `head` could not read the marker. |
   | any other (95/96/97, 124, 141, 255, and shell 1/2/127) | `probe_failed rc=<n>` | gd_capture, transport or shell, as for every probe. |

   No captured value (UUID, marker content, device name) is ever printed.
4. **`main`.** It calls `refuse_if_unmounted`, `refuse_if_not_on_mapper`,
   `refuse_if_store_unverified`, `refuse_if_store_not_empty` and `refuse_if_fence_not_intact`, each
   as a plain statement. The start log and the final `clear` log list exactly the facts read:
   - access ok;
   - served by the mapper;
   - the bootstrap's marker is bound;
   - not frozen;
   - `*.git` = 0;
   - the fence is in place.

   Neither log line says "encrypted at rest"; that determination is #8634's.
5. **Header.**
   - Rewrite "WHAT THIS SCRIPT DOES TODAY", including what exit 0 means now.
   - Rewrite the `#8211 is split` paragraph. PR1 landed. This PR is the proof half of PR2, and the
     `DRY_RUN=1` probe chain **is** the `proof` that the follow-on builds on. Flip, rollback,
     redeploy and the ADR-220 D6 fresh replace remain.
   - Delete the "expected until PR2 rebuilds the proof" sentence.
   - Add the new reasons and exit codes.
6. **`refuse_real_modes` remedy line.** It says the flip and rollback remain on #8211.

Then run `python3 scripts/lint-shell-capture-exit.py apps/web-platform/infra/git-data-cutover.sh`,
`shellcheck` and `bash -n`.

### Phase 4 — runtime arm

1. **Fixtures.**
   - The fixture `findmnt` branches: `-no UUID` prints `/fixture/findmnt.uuid`, and every other
     query prints `/fixture/findmnt.out`.
   - The container writes `/etc/git-data/store-verified` from `/fixture/findmnt.uuid` with
     `printf '%s\n'`, the bootstrap's own shape.
   - **Every** `printf '/dev/sdb\n' > /fixture/findmnt.out` reset becomes the mapper. That covers the
     canonical setup and the resets before R8 and RFINC, so R6, RF2, RFINC, RF17 and RF18 keep
     reaching their probe.
2. **Rows.**
   - R5 (canonical) now runs on the mapper.
   - R5b's exact remote command list is 7 lines, in order:
     1. `findmnt -no SOURCE /mnt/git-data` (`store-mounted`);
     2. `findmnt -no SOURCE /mnt/git-data` (inside `store-verified`);
     3. `findmnt -no UUID /mnt/git-data`;
     4. `findmnt -no SOURCE -T /mnt/git-data/repositories`;
     5. `find -H /mnt/git-data/repositories … -name *.git -printf .`;
     6. `findmnt -no SOURCE -T /mnt/git-data/hooks`;
     7. `findmnt -no SOURCE -T /mnt/git-data/hooks/pre-receive`.
   - R5c's login counts become web 7 and gd 5.
   - R7 is inverted: `/dev/sdb` reads `store_not_on_mapper`.
   - **RVM** (new): a real marker mismatch reads `store_unverified reason=marker_mismatch`. It is the
     one row that carries a remote refusal code through real OpenSSH.
     - The marker is restored by a trap, not by row order.
     - RVM also asserts that the run's whole output contains neither the fixture UUID nor the marker
       bytes. This is the stderr-path leak check (observability P2).
   - **RVM2** (new): a canonical run right after RVM must clear, which proves the restore worked.
   - RFSRC is **deleted**. MAP-ALT (unit) holds the must-PASS non-canonical property, and the
     runtime `drive2` passes no `LUKS_MAPPER`.
3. **`RUNTIME_ROWS`** is set to the counted row total.

### Phase 5 — mutants and floors (against the real text, after every row exists)

1. **Re-anchor the existing mutants.**
   - `g2-no-cut-over` becomes `g2-no-on-mapper`. It deletes `refuse_if_not_on_mapper` from `main`,
     and `case_not_mapper` must go RED.
   - `g5-raw-capture` is re-anchored on the new `store-on-mapper probe_failed` line.
   - `f-m17`'s hardcoded source becomes `/dev/mapper/git-data`, and MAP-ALT must go RED.
   - `f-m2-no-read` and `f-m16-loose-anchor` gain the address range
     `/^refuse_if_fence_not_intact\(\) \{/,/^\}/`. The new probe also has a `gd_capture '^ok$'`
     line, and an unscoped sed would land on 4 diff lines, not 2. Guard 2's rows 2 and 7 use the
     `refuse_if_store_unverified` range.
2. **Add every Guard 1 and Guard 2 matrix row and harness row.** Each goes through `mutate()` with an
   exact diff-line count.
3. **Floors are exact, and `MUTANT_FLOOR` is computed independently** (test-design P0-1).
   - First compute the expected `MUTANT_FLOOR` from the plan's matrices: the existing rows, minus
     the rows this plan re-anchors (count each re-anchored row once), plus the Guard 1 and Guard 2
     rows, the harness rows, the RB mutants and the P3 mutants.
   - Change both checks from `-lt` to **`-ne`**. Every skip path adds `RUNTIME_ROWS`, so the totals
     are the same in every environment. In CI, `-ne` also proves `RUNTIME_ROWS` equals the rows that
     actually ran.
   - Run `GDC_SKIP_RUNTIME=1 bash apps/web-platform/infra/git-data-cutover-access.test.sh` **once**,
     after Phase 4, when `RUNTIME_ROWS` is final. The measured `MUTANTS_RUN` must equal the computed
     value before it is written. A mismatch means a matrix row is missing or extra.
   - Set `MUTANT_FLOOR` to the measured `MUTANTS_RUN`.
   - Set `FLOOR` to the measured `passes + fails + SKIPPED` of a green run.
   - Restate the per-section ledger comment from the measured counts. Never adjust by a guessed
     delta. Because the check is `-lt`, a floor that is too low would still pass, so an estimate
     here is a silent under-count.
4. **Merge order.** The #8101 wrapper work also edits this suite's floors. Whichever PR lands
   second re-measures after syncing `main`. The same applies after any sync of `main` that touches
   this suite (operator constraint).

### Phase 6 — docs, ADRs, workflow, C4

1. **`.github/workflows/git-data-cutover.yml` header**, items 4-5: "the store is served by the LUKS
   mapper with the bootstrap's store marker bound to it, is not frozen, and holds no repository".
   This is a comment only.
2. **Runbook `git-data-luks-cutover-5274.md`**:
   - **Preconditions, the #8211 bullet.** PR1 landed. The proof half of PR2 is this PR. Flip,
     rollback, redeploy and the ADR-220 D6 replace remain.
   - **"What the read-only dispatch does", step 7.**
     - List the probes.
     - Rewrite "Exit 0 means": access ok, served by the mapper with the bootstrap's marker bound to
       its filesystem, not frozen, zero `*.git`, and the fence intact.
     - Say explicitly that it does **not** determine when encryption at rest became active for the
       Art. 30 register. That determination is #8634's, and this PR leaves it alone.
   - **Host-key step 5, rewritten** (CLO, CPO and spec-flow conditions):
     - 5.1 is unchanged: collect the ids.
     - 5.2: after this PR merges, dispatch `git-data-cutover.yml` from `main`. Only a run ending
       `verdict=clear` discharges the collected ids. The discharge rests on two measured volume
       counts plus the flag history:
       - **(a) the served LUKS store.** The run's `clear`: `store-on-mapper`, `store-verified`,
         `store-empty` and `fence-shape` all `verdict=ok`.
       - **(b) the retained plaintext volume.** Read the `boot_complete` line of the **current**
         instance from Better Stack. It must read `plaintext_empty=yes`.
         - Record it together with its replace run id (36118115758 unless a later one ran).
         - Run `gh run list` over the replace and create workflows, and show that no run falls
           between that replace and the proof.
         - A bound marker proves only that *some* bootstrap run on this filesystem passed its
           full-entry counts. A re-run that FATALs before `rm -f "$STORE_VERIFIED"` can leave an
           older marker. So the `boot_complete` line is the binding evidence, not the marker
           (user-impact F3, F5).
         - The volume has been kernel-read-only and never mounted since (ADR-239 D2).
         - **If the line cannot be read, for example because Better Stack retention expired,
           nothing is discharged.**
       - **(c) the flag was never on, since before either volume existed.** Take the same run's
         precheck line, then page `doppler configs logs` for `GIT_DATA_STORE_ENABLED`.
         - Page back past the `created` time of the **older** of `hcloud_volume.git_data` and
           `git_data_luks`. Read both times from the Hetzner API (read-only) and record them.
         - Page every Doppler config the web containers load, not only `prd`. A branch config
           would not appear in the `prd` log (user-impact F2).
         - This extends the existing "Two reads to record", read 2. It is **required**. The counts
           see entries, not freed blocks, so a repository written and deleted earlier would be
           invisible to them. Only the flag's history since volume creation excludes it
           (user-impact F1).
         - If the paging cannot reach that time, nothing is discharged.
     - **A fill-in template for the #5914 record:**
       - the run id, dispatch time, head SHA, and the nine `::notice` lines;
       - the precheck line and the oldest Doppler log entry reached;
       - the instance's replace run id and `boot_complete` line;
       - the Sentry sweep window, from 2026-09-22T12:07:01Z (the #8511 merge) to the clearing
         run's start. Run it with the existing "Store not empty" step-3 query, widened to that
         window. Note that pagination was read to the end, and give the distinct id count.
       - the scoped wording "git-data store (`op=git-data-bare-repo-erasure`): no data held;
         nothing to erase", never "erased". The user's copy in web-1 `/workspaces` is erased by a
         separate operation, and this record must not read as covering it (user-impact F4);
       - the earliest request date and the Art. 12(3) deadline it implies.

       Requests after the window end need no discharge here: a verified store with a published pin
       answers each one live, as a normal `erasure_outcome`.
     - 5.3:
       - any other verdict follows its verdict-map row. Only `clear` discharges.
       - After the row's remedy, **one** re-dispatch. A repeat of the same verdict opens an
         incident instead of a loop.
       - Step 5 resumes with one re-dispatch after the incident closes.
       - If the Art. 12(3) deadline is at risk, escalate to the CLO.
   - **Verdict map**, grouped by action class (CTO devex). There is one row per class, listing its
     words, and every emitted word appears (RB row):
     - **Remove:** both `already_cut_over` rows.
     - **Incident, served device wrong:** `store_not_on_mapper`. The ADR-239 render cannot produce
       it. Read the current instance's `boot_complete` and the `stage:bootstrap` events first, then
       follow "If the fresh host fails a boot check after step 3". Never re-dispatch a replace
       before that read.
     - **Wrappers refusing now:** `store_unverified reason=no_fs_uuid|marker_absent|marker_mismatch`.
       Every erasure is refusing, so sweep Sentry for Art. 17 refusals. Route to "If the fresh host
       fails a boot check after step 3". A mismatch with no boot FATAL is a Breach-triage trigger.
     - **Frozen:** `cutover_frozen`. No writer and no remover exist, the sentinel sits on the
       retained LUKS volume, and SSH is barred.
       - Open an incident (Breach-triage trigger) and escalate to the CLO, because the Art. 12(3)
         clock runs.
       - The removal is a reviewed hotfix PR under that incident. It is **not** gated on #5914 or
         the #8211 follow-on.
       - Step 5 resumes by the 5.3 rule.
     - **Probe could not be answered:** `probe=store-verified verdict=probe_failed rc=5|6|16|<n>` and
       `reason=arg_root|arg_marker`. rc 6 reads "the store source changed or was over-mounted
       between probes", and rc 16 reads "`head` could not read the marker". The other rcs read as
       for the existing probes.
     - Update the `real_cutover_unreconciled` row: the flip and rollback remain on #8211.
3. **ADR-239: add a short `## Amendment 2026-09-27 — the proof reads the LUKS-served store (#8211 PR2, proof half)`.**
   It records:
   - the proof's polarity: a non-mapper source is refused;
   - the evidence it reads: the D3 marker, bound, plus freeze absence;
   - that `already_cut_over` is retired;
   - that the ADR-237 addendum's "making the proof read `already_cut_over` as a pass" is discharged
     by rebuilding the probes, not by passing that verdict;
   - that the `DRY_RUN=1` chain is the `proof` the follow-on builds on, and keeps `store_not_empty`;
   - what remains of PR2:
     - the flip;
     - the flag-off rollback;
     - the same-version redeploy;
     - the ADR-220 D6 fresh replace with its LUKS key and volume rotation;
     - the ADR-237 amendment that fresh replace needs.

     ADR-239 and the PR1 plan call that last item "ADR-237 D6". ADR-237 has decisions 1 to 5 only,
     so name it by what it is.
   - that the proof does not determine Art. 30 activation (#8634).

   The **status is not changed** by this PR (see PM4).
4. **ADR-220: a new amendment-log entry `### 2026-09-27 (#8211 PR2): the store probes read the LUKS-served store`.**
   Precedent: the 2026-09-21 #8454 fence entry.
   - The probe chain is now `store-mounted`, `store-on-mapper`, `store-verified`, `store-empty`,
     then `fence-shape`.
   - The D1b flip condition ("with all three store probes clear") is restated as "with the store
     probes and the fence probe clear". Without this, D1b could never flip, because one of its three
     probes is retired.
   - Dated history above it is not rewritten.
5. **C4.** In `model.c4`'s git-data-cutover edge prose, replace "(mounted, not cut over, empty)" with
   "(served by the LUKS mapper with its store marker bound, not frozen, empty)". Leave the "TARGET
   until ADR-220 D1b flips" marker as it is; PM4 flips it. Run `bash scripts/regenerate-c4-model.sh`
   and commit `model.likec4.json`.

### Phase 7 — verification (CI-first, per the operator constraint)

Push and let CI run the suite. It is registered by its presence under `apps/web-platform/infra/`,
and the docker runtime arm is required under `CI=true`. Cheap local checks only:

- `bash -n` on the script and the suite;
- `shellcheck`;
- `lint-shell-capture-exit.py`;
- the one `GDC_SKIP_RUNTIME=1` suite run from Phase 5;
- `bash plugins/soleur/test/c4-count-parity.test.sh` (green on `origin/main` today);
- `bash plugins/soleur/test/c4-model-freshness.test.sh`;
- `npx markdownlint-cli2` on the edited docs.

## Does merging this alone mutate production?

**No host configuration and no Terraform change. There is, however, a same-code container
redeploy.**

- **`web-platform-release.yml`** fires on `apps/web-platform/**`. The merge cuts a release, and its
  `workflow_run` arm deploys that release, taking `web-1-swap`. The in-run `check_changed` gate uses
  `path_filter: "apps/web-platform/ plugins/soleur/ …"` (`web-platform-release.yml`), so a change
  under `apps/web-platform/infra/` counts as changed. The deployed app code is unchanged.
- **`apply-web-platform-infra.yml`** fires on `apps/web-platform/infra/**`, but its plan reaches no
  changed resource. `git-data-cutover.sh` and its suite are bound into no `user_data` and no
  `file()`, and there is no `fileset()` or hash trigger. `git grep -n 'git-data-cutover'
  apps/web-platform/infra/*.tf apps/web-platform/infra/modules` returns comments only. The expected
  apply is a no-op.
- **`git-data-cutover.yml`** is `workflow_dispatch`-only.

PM1 waits for the release deploy to finish before dispatching.

## Files to Edit

- `apps/web-platform/infra/git-data-cutover.sh`
- `apps/web-platform/infra/git-data-cutover-access.test.sh`
- `.github/workflows/git-data-cutover.yml` (header comment only)
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`
- `knowledge-base/engineering/architecture/decisions/ADR-239-git-data-serves-from-luks-at-birth.md`
- `knowledge-base/engineering/architecture/decisions/ADR-220-git-data-root-access-via-web-1-jump-and-a-dedicated-terraform-minted-key.md`
  (a new amendment-log entry only)
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (regenerated)

The pipeline also writes `knowledge-base/project/specs/feat-one-shot-8211-pr2-cutover-proof-already-cut-over/`
(`tasks.md`, `session-state.md`, `decision-challenges.md`), and may regenerate
`knowledge-base/INDEX.md`.

## Files to Create

None.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly, because the store has never held
  a repository and the flag is off. Indirectly, the operator discharges pending Art. 17 erasures
  (host-key step 5) on the strength of this proof's `clear`. A false `clear` would record a deleted
  user's repository as "nothing to erase" while it still exists. That could come from a swallowed
  refusal, a count run on the wrong filesystem, or an empty value matching an empty marker.
- **If this leaks, the user's data is exposed via:** no new exposure vector. The proof only reads,
  and `gd_capture` never prints a captured value, which now includes the filesystem UUID and the
  marker content. A regression that printed them would put host identifiers in public workflow logs,
  which carry no user data.
- **Brand-survival threshold:** `single-user incident`. One deleted user's workspace history,
  recorded as having nothing to erase while it survives on a retained volume, is an Art. 17 failure
  for that user.

CPO sign-off was given at plan time, with the conditions under Domain Review. `user-impact-reviewer`
runs at review.

## Observability

```yaml
liveness_signal:
  what: "git-data-cutover.yml run conclusion plus its STORE annotations (probe=store-on-mapper, probe=store-verified, probe=store-empty, probe=fence-shape, verdict=clear)"
  cadence: "per dispatch (reviewer-gated, from main)"
  alert_target: "the dispatching operator: a failed run's ::error annotations name the fixed verdict and reason words"
  configured_in: "apps/web-platform/infra/git-data-cutover.sh (_store_emit / _store_refuse) and .github/workflows/git-data-cutover.yml"
error_reporting:
  destination: "GitHub Actions ::error annotations and the step summary (GITHUB_STEP_SUMMARY); no Sentry, because the script runs on a CI runner and not in the app"
  fail_loud: "exit 5 with '::error title=git-data-cutover store::probe=<name> verdict=<word>[ reason=<word>]'"
failure_modes:
  - mode: "store served by a non-mapper device"
    detection: "probe=store-on-mapper verdict=store_not_on_mapper (exit 5) (layer 6: workflow-run log, ::error:: annotation)"
    alert_route: "failed run; runbook verdict-map row (incident, boot events first)"
  - mode: "filesystem UUID empty, or the bootstrap's marker absent or unbound (wrappers refusing now)"
    detection: "probe=store-verified verdict=store_unverified reason=no_fs_uuid|marker_absent|marker_mismatch (layer 6: workflow-run log, ::error:: annotation)"
    alert_route: "failed run; runbook row routes to the boot-FATAL recovery and the Art. 17 sweep"
  - mode: "freeze sentinel present with no writer"
    detection: "probe=store-verified verdict=cutover_frozen (layer 6: workflow-run log, ::error:: annotation)"
    alert_route: "failed run; runbook row opens an incident with CLO escalation and a reviewed hotfix remover"
  - mode: "probe could not be answered, or was called with an unsafe argument"
    detection: "probe=store-on-mapper|store-verified verdict=probe_failed rc=<n>|reason=arg_mapper|arg_root|arg_marker (layer 6: workflow-run log, ::error:: annotation)"
    alert_route: "failed run; the runbook row maps each rc"
  - mode: "script and runbook drift (a new verdict word with no runbook row)"
    detection: "suite row RB fails in CI (layer 6: CI workflow-run log, required check)"
    alert_route: "red required check on the PR"
  - mode: "a false clear (a refusal swallowed, reordered or loosened), the brand-critical case"
    detection: "the Guard 1 and Guard 2 mutant rows go RED in CI (layer 6: CI workflow-run log, required check)"
    alert_route: "red required check on the PR; the change cannot merge"
logs:
  where: "GitHub Actions run log and check-run annotations (gh api repos/jikig-ai/soleur/check-runs/<job-id>/annotations)"
  retention: "GitHub Actions log retention (90 days)"
discoverability_test:
  command: "curl -fsS https://api.github.com/repos/jikig-ai/soleur/actions/workflows/git-data-cutover.yml/runs?per_page=1"
  expected_output: "\"conclusion\""
```

## Encryption Posture

Not required. This plan introduces no persistent store and no new cross-component connection. It
reads the state of an existing store (`hcloud_volume.git_data_luks`, ADR-239) and makes the proof
**require** the ADR-239 serving layout. None of the Phase 2.11 detection globs match (`.tf`,
migrations, cloud-init, docker-compose). No text this PR writes asserts when encryption at rest
became active; that is #8634's determination.

## Guard Contract

### Guard 1 — the store is served by the configured LUKS mapper

**Property.** The proof never reports `clear`, and never reaches the count, unless the `findmnt -no
SOURCE` answer for the store root is string-equal to `$LUKS_MAPPER`.

**Assembly.** The chokepoint is `STORE_SOURCE`, which only `refuse_if_unmounted` sets.
`refuse_if_not_on_mapper` compares it, and `main` calls that function as a plain statement before
`refuse_if_store_unverified`, `refuse_if_store_not_empty` and `refuse_if_fence_not_intact`. The same
equality is re-asserted inside the `store-verified` remote session (exit 6). The count's and the
fence's remote commands compare against `STORE_SOURCE`, which is the mapper by then. There is a
second chokepoint: `main`'s call list, pinned by `case_main_order`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Polarity reverted: `[ "$STORE_SOURCE" = "$LUKS_MAPPER" ]` becomes `!=` | RED (`case_not_mapper`, AC2) |
| 2 | Own dispatch: delete `refuse_if_not_on_mapper` from `main` | RED (`case_main_order`, `case_not_mapper`) |
| 3 | Second member: the equality loosened to a prefix match (`[[ $STORE_SOURCE == /dev/mapper/* ]]`), tested with `SHIM_FINDMNT=mapperpre` | RED (MAP-PRE) |
| 4 | REORDER: the on-mapper call moved after `refuse_if_store_not_empty`. Observed inside the window by a plaintext source plus `SHIM_COUNT=one` and an explicit `SHIM_VERIFY=ok`, which must read `store_not_on_mapper`, never `store_not_empty` | RED (ORD, `case_main_order`) |
| 5 | The refusal swallowed: `_store_refuse store-on-mapper store_not_on_mapper` becomes `_store_emit …` | RED (`case_not_mapper`: rc 0, not 5) |
| 6 | The `arg_mapper` check deleted | RED (ARG-mapper: `LUKS_MAPPER=$'/dev/x\n'` must be `reason=arg_mapper`) |

**Harness rows.**

- **RED:** the `ssh` shim's `findmnt` default is reverted to `/dev/sdb`. AC2 goes RED, which proves
  the canonical input is the mapper.
- **Must-PASS, non-canonical:** `LUKS_MAPPER=/dev/mapper/gd-alt` with consistent answers clears
  (MAP-ALT). The comparison keys on the configured value, not a literal.

**Anchor.** P3 parity. The script's `LUKS_MAPPER` default must equal the `STORE_DEVICE` default in
every derived definer: 5 today, a floor of 5, paired with set identity. Moving one side alone reds,
and so does a new definer with a different default.

### Guard 2 — a pass is backed by the bootstrap's verified-store evidence

**Property.** `probe=store-verified verdict=ok` is emitted only when, in one SSH session, the store
source is the mapper, the mounted filesystem's UUID is non-empty, `$STORE_VERIFIED` is a non-empty
file whose first line equals that UUID, and nothing exists at `$OLD_ROOT/.cutover-freeze`. Symlinks
are followed exactly as the wrappers follow them.

**Assembly.** The one remote command array in `refuse_if_store_unverified`, and its local
rc-to-verdict `case`. Each check is one array element. There are three chokepoints: the array, the
`case`, and the anchored `^ok$` pattern passed to `gd_capture`.

**Mutation matrix.** The sed for every row except row 1 is scoped to the `refuse_if_store_unverified`
function range. Row 1 edits `main`, by design.

| # | Mutation | Expected |
|---|---|---|
| 1 | Own dispatch: delete `refuse_if_store_unverified` from `main` | RED (`case_main_order`, and the V21 behaviour row) |
| 2 | Own dispatch: the probe "passes" without reading (`GD_CAPTURED=ok` in place of its `gd_capture` call) | RED (canned V22) |
| 3 | Second member after a compliant first: drop the marker equality, keeping presence | RED (VX-mismatch) |
| 4 | Second member: drop the freeze element | RED (VX-frozen) |
| 5a | Empty equals empty: delete `[ -n "$fu" ]` | RED (VX-nouuid: must be `no_fs_uuid`, never ok) |
| 5b | Delete `[ -s "$mk" ]` alone | RED (VX-emptymk: must be `marker_absent`) |
| 6 | Delete the same-session source re-check (exit 6) | RED (VX-overmount) |
| 7 | Anchor loosened: `gd_capture '.*'` | RED (`SHIM_VERIFY=empty` must be `probe_failed rc=96`) |
| 8 | An instrument failure rendered as state: rc 16 mapped to `marker_absent` | RED (V16 must be `probe_failed rc=16`) |
| 9 | `[ -f "$mk" ]` dropped, leaving `-s` only | RED (VX-dirmk: a **non-empty** directory at the marker path must be `marker_absent`. An empty directory can have size 0 on some filesystems, which would let the mutant survive) |
| 10 | The `*)` arm deleted from the `case` | RED (V127 must be `probe_failed rc=127`) |
| 11 | The anchor loosened from `^ok$` to `ok` | RED (`SHIM_VERIFY=notok` answers `nok`, which must be `probe_failed rc=96`) |
| 12 | The local `arg_root`/`arg_marker` check deleted | RED (ARG rows) |

**Harness rows.**

- **RED:** the `ssh` shim's `r=` arm hardwired to `ok`. The canned negative rows go RED.
- **RED:** the `findmnt` shim's UUID branch collapsed into SOURCE. VX-ok goes RED.
- **RED:** the positional SOURCE answer ignores `SHIM_FINDMNT_S`. VX-overmount goes RED.
- **Must-PASS, non-canonical:**
  - VX-2line: a marker whose first line is the UUID, followed by a second line;
  - VX-symlinkok: a marker that is a symlink to a file with the right UUID.

  Both clear, because the wrappers accept both, and the proof must not be stricter than the runtime
  gate it mirrors.

**Anchor.** P3 parity:

- the `STORE_VERIFIED` default equals every derived definer's (5 today);
- the `/.cutover-freeze` suffix equals every derived definer's (4 today);
- `OLD_ROOT`'s `/mnt/git-data` equals every derived `MOUNT_ROOT` and `GIT_DATA_ROOT` definer's (6
  today).

The value the probe compares against, the marker, is written on the host by the bootstrap, outside
this commit. No single diff can move both the check and the evidence.

## Architecture Decision (ADR/C4)

### ADR

**ADR-239 gets a dated amendment**; there is no new ordinal. Its content is in Phase 6 item 3. The
decision it records:

- the read-only proof now **requires** the ADR-239 serving layout, and reads the D3 marker;
- `already_cut_over` is retired;
- the proof is the base the rest of PR2 builds on.

**ADR-220 gets an amendment-log entry** (Phase 6 item 4) that restates D1b's flip condition over the
new probe chain.

ADR-220's and ADR-237's earlier dated addenda that cite `already_cut_over` are left as written.

### C4 views

In the **Container** view, the prose of the `git-data-cutover.yml` → git-data edge (`model.c4`, the
`github -> gitDataStore` edge) changes from "(mounted, not cut over, empty)" to "(served by the LUKS
mapper with its store marker bound, not frozen, empty)".

All three model files were checked:

- `model.c4`: the ssh-tunnel edge and the git-data-cutover edge;
- `views.c4` and `spec.c4`: no element or tag is added.

Each category was enumerated:

- external actors: none new; the operator and the reviewer approval are unchanged;
- external systems: GitHub Actions, the Cloudflare tunnel, web-1 and git-data are unchanged;
- containers: the git-data store is unchanged; only what the proof reads changes;
- access relationships: unchanged (read-only root SSH through the web-1 jump).

The "TARGET until ADR-220 D1b flips" marker stays until PM4. Regenerate `model.likec4.json`, then
run `plugins/soleur/test/c4-count-parity.test.sh` and the C4 render tests. The edited prose contains
no cardinality.

### Sequencing

There is no soak. The D1b flip and any ADR-239 status flip depend on post-merge evidence, so both
land in the PM4 docs PR, following the precedent of the ADR-237 flip in #9036.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1.** `git-data-cutover.sh` contains no `refuse_if_cut_over`, no `already_cut_over` and no
  `store-not-cut-over`, in code or comments.
  - `git grep -n 'already_cut_over' -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs' ':!knowledge-base/project/learnings'`
    returns hits only in:
    - the dated ADR-220 and ADR-237 addenda;
    - the ADR-239 amendment's "retired" sentence;
    - the runbook's Preconditions step-4 history record.
- [ ] **AC2.** With the canonical shims, the script exits 0. The canonical shims give a mapper
  source, a bound marker, no freeze, a count of 0 and an ok fence.
  - It emits exactly the 9 `::notice` lines listed in Phase 1, ending in `verdict=clear`. The
    mapper device name is never printed. The UUID and marker never reach the local process under
    canned shims, so their non-printing is proven by RVM, not here.
  - Its remote timeline equals the expected file: 7 SSH calls, each `timeout`-bounded with a
    `/dev/null` stdin.
- [ ] **AC3.** A plaintext source (`/dev/sdb`) exits 5 with
  `probe=store-on-mapper verdict=store_not_on_mapper`. No `r=` command and no `d=` command is
  dialed.
- [ ] **AC4.** Each of the following has a row that asserts the exact STORE line, exit 5, and that
  no `d=` command and no `h=` command is dialed:
  - `store_unverified reason=no_fs_uuid|marker_absent|marker_mismatch`;
  - `cutover_frozen`;
  - `probe_failed rc=5|6|16|96|127|255`;
  - a remote stderr carrying `::error::` and `::add-mask::` lines (VINJ): no annotation beyond the
    fixed verdict appears.

  `reason=arg_mapper|arg_root|arg_marker` additionally asserts that no `r=` command is dialed.
- [ ] **AC5.** Every Guard 1 and Guard 2 matrix row and harness row runs through `mutate()`, lands
  on its exact diff-line count, and its named case goes RED. The existing `f-m2` and `f-m16` mutants
  still land on 2 lines each.
- [ ] **AC6.** `MUTANT_FLOOR` and `FLOOR` equal the values measured after Phase 4, and the ledger
  comment is restated per section. The suite exits 0 in CI.
- [ ] **AC7.** Runtime arm:
  - R5 clears on real OpenSSH, and R5b equals the 7-line list in Phase 4.
  - R5c reads web 7 / gd 5.
  - R6, RF2, RFINC, RF17 and RF18 still read their original verdicts on the mapper fixture.
  - R7 reads `store_not_on_mapper`.
  - RVM reads `reason=marker_mismatch`, and its output contains neither the fixture UUID nor the
    marker bytes.
  - RVM2 clears after the trap restore.
- [ ] **AC8.** `DRY_RUN=0`, `ROLLBACK=1` and `CONFIRM_WIPE=1` still refuse `real_cutover_unreconciled`
  with an empty timeline. The existing G7 rows are unchanged and green.
- [ ] **AC9.** Runbook:
  - no "Blocked on #8211 PR2" sentence remains;
  - step 5.2 carries the three-part evidence chain and the #5914 template;
  - the verdict map is grouped by action class, and suite row RB passes (every emitted word is
    present);
  - no `already_cut_over` row remains;
  - "Exit 0 means" does not claim encryption-at-rest activation.
- [ ] **AC10.** ADR-239 carries the dated amendment, and its `status:` is unchanged by this PR.
  ADR-220 carries the new amendment-log entry, and its dated history above that entry is unchanged
  (`git diff` touches only added lines in ADR-220).
- [ ] **AC11.** The `model.c4` edge prose is updated, and `c4-model-freshness`, `c4-count-parity` and
  the C4 render tests are green.
- [ ] **AC12.** PR body:
  - it says `Ref #8211` and `Ref #5914`, never `Closes #8211` or `Closes #8101`;
  - its first line states the production effect: a same-code container redeploy, with no host or
    Terraform change;
  - it lists the PR2 items that remain;
  - it restates word for word the three CPO conditions carried to the flip half: "the per-host
    in-container proof fails the deploy on a mismatch; the rollback rehearsal runs a successful
    erasure; every flip blocker is kept". The same text is posted as a comment on #8211.
- [ ] **AC13.** The required checks are green by name on the exact head SHA before merge.

### Post-merge (operator-visible, automated where possible)

- [ ] **PM1.** Dispatch the dry run.
  1. Wait for the merge's `web-platform-release` deploy to conclude.
  2. Run `gh workflow run git-data-cutover.yml --ref main -f confirm=CUTOVER-GIT-DATA`.
  3. Capture the run id: `gh run list --workflow git-data-cutover.yml --limit 1 --json databaseId`.
  4. Arm a watch on it (`hr-dispatch-async-must-arm-watch`).

  The job then waits on the `web-platform-infra-apply` environment approval. **The operator's
  approval is the single human input** (security P1-b). The approval is what hands the job
  `DOPPLER_TOKEN_PRD` and the git-data root key, so "the script is read-only" does not bound what
  it authorizes (`hr-menu-option-ack-not-prod-write-auth`).

  The session may approve through `POST /repos/jikig-ai/soleur/actions/runs/<id>/pending_deployments`
  only with the operator's explicit in-session consent for this run, and only after checking that:
  - the run's `path` is `.github/workflows/git-data-cutover.yml`;
  - it is `event=workflow_dispatch` on `head_branch=main`;
  - its `head_sha` equals the merge SHA;
  - its actor is the session's own.

  A run still unapproved at the end of the session is cancelled (`gh run cancel <id>`), because it
  holds the `git-data-state` group.
- [ ] **PM2.** Get the job id with `gh run view <id> --json jobs --jq '.jobs[0].databaseId'`, then
  read the annotations with `gh api repos/jikig-ai/soleur/check-runs/<job-id>/annotations`.
  - Expect exactly the nine `::notice` lines of AC2.
  - Cite each line by the `##[group]Run` step that printed it, and record the flag precheck line.
- [ ] **PM3.** If the run is clear, complete host-key step 5 using the runbook's #5914 template:
  the Sentry sweep, the Doppler flag history, and the `boot_complete` line. Any other verdict
  follows its verdict-map row, and the 5.3 rule applies.
- [ ] **PM4.** If the run is clear, open a docs PR, following the #9036 precedent, that:
  - flips ADR-220 D1b and the C4 "TARGET until ADR-220 D1b flips" marker, citing the run;
  - reads the current instance's `boot_complete`. If it satisfies ADR-239's flip rule
    (`luks_mounted=yes fence_on_mapper=yes erasure_probe=yes` in production), flip ADR-239 to
    `accepted` in the same PR.

  If the run is not clear, file a tracking issue for both flips instead.

## Test Scenarios

Unit rows use PATH shims. `VX-*` rows run the remote bytes locally under `SHIM_VERIFY=exec`, with
fixture `OLD_ROOT` and `STORE_VERIFIED`. Runtime rows use real OpenSSH in the pinned ubuntu:24.04
image.

| ID | Input | Expected |
|---|---|---|
| AC2 | canonical mapper, all ok | exit 0, 9 notices, exact timeline |
| S5/G2 (`case_not_mapper`) | `SHIM_FINDMNT=plain` | exit 5 `store_not_on_mapper`; no `r=` or `d=` dialed |
| ORD | `SHIM_FINDMNT=plain SHIM_COUNT=one` | `store_not_on_mapper` (never `store_not_empty`) |
| MAP-ALT (must-PASS) | `LUKS_MAPPER=/dev/mapper/gd-alt SHIM_FINDMNT=mapperalt` | exit 0; fence `src=/dev/mapper/gd-alt` |
| MAP-PRE | `SHIM_FINDMNT=mapperpre` | `store_not_on_mapper` |
| H2 | `SHIM_FINDMNT=noeol` (mapper, no trailing newline) | exit 0 |
| V24/V21/V22 | `SHIM_VERIFY=r24/r21/r22` | `store_unverified reason=no_fs_uuid / marker_absent / marker_mismatch` |
| V23 | `SHIM_VERIFY=r23` | `cutover_frozen` |
| V5/V6/V16/V127/V255 | `SHIM_VERIFY=r5/r6/r16/r127/r255` | `probe_failed rc=<n>` |
| Vline2/Vempty | a second line, or an empty answer | `probe_failed rc=96`; the canary is never printed |
| VX-ok | executed: bound marker, no sentinel | ok |
| VX-nomk / VX-emptymk / VX-dirmk | marker missing, empty, or a non-empty directory | `reason=marker_absent` |
| Vnotok | `SHIM_VERIFY=notok` (answers `nok`) | `probe_failed rc=96` |
| VINJ | `SHIM_VERIFY=r22` with `SHIM_VERIFY_STDERR` carrying `::error::x` and `::add-mask::y` | `reason=marker_mismatch`; no extra annotation; the injected lines appear only behind `probe-stderr:` inside the `::stop-commands::` span |
| VX-symlinkok (must-PASS) | the marker is a symlink to a file with the right UUID | ok (the wrappers accept it) |
| VX-mismatch | the marker's first line differs from `SHIM_FINDMNT_UUID` | `reason=marker_mismatch` |
| VX-crlf | marker `<uuid>\r\n` | `reason=marker_mismatch` (the wrappers refuse it too) |
| VX-2line (must-PASS) | the first line matches, plus a trailing line | ok |
| VX-nouuid | `SHIM_FINDMNT_UUID=empty` with an empty marker | `reason=no_fs_uuid` (never ok) |
| VX-uuidfail | `SHIM_FINDMNT_UUID=fail` | `probe_failed rc=5` |
| VX-overmount | `SHIM_FINDMNT_S` answers two lines | `probe_failed rc=6` |
| VX-frozen | a `.cutover-freeze` file under the fixture root | `cutover_frozen` |
| VX-frozen-dangling (must-PASS) | a dangling `.cutover-freeze` symlink | ok (the wrappers test `-e` too) |
| ARG | an unsafe `OLD_ROOT`; an unsafe `STORE_VERIFIED` | `probe_failed reason=arg_root / arg_marker`; no `r=` dialed |
| ARG-mapper | `LUKS_MAPPER` holding a newline, or `/dev/x;y` | `probe=store-on-mapper verdict=probe_failed reason=arg_mapper`; no `r=` dialed |
| P3 | parity with every derived definer | equal; floors 5, 5, 4 and 6, with set identity; the three P3 mutants go RED |
| RB | the store-probe word sets, in both directions | script set = observed set = runbook-map set; the three RB mutants go RED |
| R5/R5b/R5c | runtime canonical | exit 0; the exact 7-line command list; logins web 7 / gd 5 |
| R6, RF2, RFINC, RF17, RF18 | runtime, on the mapper fixture | their original verdicts |
| R7 | runtime `/dev/sdb` | `store_not_on_mapper` |
| RVM | runtime marker mismatch (marker restored by a trap) | `reason=marker_mismatch`; no UUID or marker bytes in the output |
| RVM2 | runtime canonical, right after RVM | exit 0 |

## Domain Review

**Domains relevant:** Engineering, Legal, Product

### Engineering (CTO)

**Status:** reviewed (the domain pass plus a devex plan-review pass).

**Assessment.** The split is sound, and nothing from Phase B should move in. The evidence is read in
the right order: mapper, verified store, count, then fence.

Applied as Mechanical:

- corrected parity populations;
- `case_main_order` and its mutant anchors updated together;
- the ADR-239 amendment names the `DRY_RUN=1` chain as the follow-on's `proof` and keeps
  `store_not_empty`;
- PM1 captures the run id and arms a watch;
- PM2 derives the job id;
- a #5914 fill-in template;
- the merge-order note for #8101 floors.

Taste, adopted:

- positional `findmnt`, with no assertion that the plaintext volume is unmounted;
- the `*.git` count stays, and the evidence chain is stated;
- runbook rows grouped by action class, with the RB drift row;
- the runtime arm trimmed to one new negative row.

The CTO's first-pass `marker_not_regular` and `dmsetup` census suggestions fell away when plan
review cut those mechanisms.

### Legal (CLO)

**Status:** reviewed.

**Assessment.** The evidence is adequate with conditions, all applied:

- the discharge rests on the two measured volume counts, plus the flag history, which spec-flow
  made required;
- the #5914 record carries the run and replace ids, the precheck line and a bounded sweep window;
- it uses the wording "no data held; nothing to erase", and records the Art. 12(3) deadline;
- only `clear` discharges;
- no text implies encryption-at-rest activation; it points at #8634.

There is no impact on the Art. 30 register or on legal documents.

### Product/UX Gate

**Tier:** none. No UI surface is touched.
**Decision:** CPO sign-off at plan time (`requires_cpo_signoff: true`).
**Agents invoked:** soleur:product:cpo, soleur:product:spec-flow-analyzer.
**Skipped specialists:** none.
**Pencil available:** N/A (no UI surface).

#### Findings

**CPO:** sign-off with conditions, all encoded:

1. The PR body and a comment on #8211 restate the three PR2 CPO conditions (AC12).
2. The #5914 record carries the precheck line and the head SHA (PM2, PM3).
3. `user-impact-reviewer` runs at review.

**Spec-flow** ran twice. Everything from both passes is applied: the parity populations, the frozen
dead end, the wording of the marker verdicts, the rc split, the window end, the resume rule,
evidence link (c) is now required, the current-instance `boot_complete`, the unreachable ARG rows,
and the owner of requests arriving after the window.

## Plan Review Revisions (2026-09-27)

The panel had six seats: DHH, Kieran, code-simplicity, architecture-strategist and spec-flow on the
engineering side, and the CTO on the devex lens. The consolidated changes follow, with the scoped
advisor consult and the domain pass before them.

**Cut.** DHH and code-simplicity converged on these, and the correctness findings on the same
scope dissolved with them:

- the `dmsetup` LUKS2 check (`not_luks`, `arg_mapper`, the `dmsetup` shim and census rule, 7 test
  rows, 2 mutants, RNL);
- `marker_not_regular` and `dangling_symlink`. The marker and freeze tests now match the wrappers'
  strictness exactly;
- the runtime rows RFZ, RNL, RMS and RMAP-ALT;
- RFSRC.

**Fixed:**

- Kieran:
  - the unscoped `f-m2` and `f-m16` seds;
  - H2 `noeol`;
  - the runtime `/dev/sdb` resets that feed R6 and the RF rows;
  - the unreachable ARG rows;
  - P3 counting the script itself;
  - floors measured after the runtime arm;
  - `VX-*` rows pinned to fixture paths;
  - the transport wrapper added to the frozen row;
  - an explicit `*)` arm;
  - R5b as an exact ordered list;
  - single-quoted array elements.
- Architecture:
  - the production-effect section now names the release redeploy;
  - an ADR-220 amendment-log entry so D1b can still flip;
  - the ADR-239 status left to PM4;
  - "ADR-237 D6" named by its content.
- CTO devex: the RB drift row, action-class runbook rows, the PM1 watch and job-id capture, the
  #5914 template, and the #8101 merge-order note.
- Spec-flow v2: see Domain Review.

**Earlier revisions** (the scoped advisor):

- phase order;
- the marker contract quoted from its only writer;
- "call the wrappers' helper" cut, because no helper exists and running a wrapper is a write path;
- verdict words, not exit codes, are the mapping key.

**Deepen-plan revisions:**

- security: the prefix construction, `arg_mapper`, the PM1 approval gating, VINJ, and the
  stale-marker and two-`findmnt` risks;
- test-design: exact `-ne` floors, a computed `MUTANT_FLOOR`, RB in both directions with mutants,
  P3 mutants, the row 5 split, a non-empty `dirmk`, the shim-dispatch harness rows, `notok`, and
  the RVM trap plus RVM2;
- observability: layer-6 citations and the false-clear failure mode;
- user-impact: F1-F5 in step 5.2;
- git-history: the corrected base SHA, and 707c7d072d dropped.

**Taste and User-Challenge decisions** are persisted to
`knowledge-base/project/specs/feat-one-shot-8211-pr2-cutover-proof-already-cut-over/decision-challenges.md`:

- the cut of the `dmsetup` LUKS2 check;
- keeping the freeze probe (DHH: future scaffolding).

## Risks and Sharp Edges

- **A stale marker could outlive a failed bootstrap re-run.** `git-data-bootstrap.sh` removes the
  marker only after its early FATAL points: the key guard, luksOpen and the mapper. A replace always
  starts on a fresh root disk, so this cannot happen across a replace. It could happen only on a
  same-instance re-run. Step 5.2(b) therefore binds the evidence to the instance's `boot_complete`
  line and the replace-run chain, never to the marker alone (security P2-b, user-impact F5).
- **The source and the UUID come from two `findmnt` calls.** Stacked mounts fail closed: the SOURCE
  read returns several lines, which exits 6. The reason word then names "source changed or
  over-mounted", which is accurate enough to route the incident (security P2-c).

- **The suite is the only proof of this change before production.** Its sed mutants anchor on exact
  line text, so they are written after the Phase 3 text exists and are scoped by function range. A
  mutant that does not land is itself a failure: `mutate()` asserts it. Floors are measured once the
  row set is final, because the `-lt` check cannot see a floor that is too low.
- **The `mutating()` helper** matches `mountpoint`, `test -f` and ` mount `. The new remote command
  uses positional `findmnt` and `[ -f`, so it adds no false "mutating" hit. Do not switch to
  `--mountpoint` without narrowing that helper.
- **The marker is an unauthenticated answer from a pinned host**, like every other probe answer. A
  compromised git-data root can forge it. The proof bounds what a healthy host can mis-state; it does
  not authenticate a hostile one (ADR-220 amendment log).
- **`store_not_on_mapper` must never pair with "re-dispatch the replace" as its first remedy.** The
  boot events are read first. This follows `hr-no-ssh-fallback-in-runbooks` and ADR-239's
  forward-only recovery.
- **The `cutover_frozen` path has no automated remover.** The runbook routes it to an incident with a
  reviewed hotfix, rather than implying a remedy exists.
- **A plan whose `## User-Brand Impact` section is empty** will fail `deepen-plan` Phase 4.6, as will
  one containing only `TBD`, `TODO` or placeholder text, or one missing the threshold. That section
  is filled here.
