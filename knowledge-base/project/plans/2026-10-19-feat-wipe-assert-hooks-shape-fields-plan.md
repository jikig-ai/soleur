---
title: "feat(git-data): add hooks-directory shape fields to the wipe-assert rc=34 line"
type: feat
date: 2026-10-19
slug: wipe-assert-hooks-shape-fields
branch: feat-one-shot-wipe-assert-shape-fields-rc34
issue: 10138
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

# feat(git-data): add hooks-directory shape fields to the wipe-assert rc=34 line

Refs: #10138, #6897 (Ref only; this PR never closes either). Draft PR #10523 is open on this branch. Spec lacks
`lane:` (no spec.md for this branch): defaulted to `cross-domain` (fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-19. **Halts run:** 4.6 user-brand, 4.7 observability, 4.8 PAT sweep, 4.9 UI (not triggered),
4.10 encryption (skip section present; no new store), 4.11 guard contract (`lint-guard-contract.py` green), 4.12 scope
check: all pass. **Seats:** security-sentinel, test-design-reviewer, code-simplicity-reviewer (read-only), plus the CTO
(D1 to D6), CLO and CPO agents. Live checks: #10138, #6897, #9066, #10523 OPEN; #10480, #10506 MERGED; the stripped hook
size (2784 bytes at HEAD) re-computed with the Terraform strip regex; `HOOKS_DIR` / `PRE_RECEIVE` read from
`git-data-bootstrap.sh`; both cited AGENTS rule IDs exist.

Key improvements: (1) the count is taken in linear time (`${#ht}`, `tr | wc -c`): bash pattern substitution on the type
string was measured quadratic (100k chars 0.5 s, 400k chars 9.7 s) inside the live snapshot window; (2) the two
`pre-receive` finds became ONE that prints a single fixed letter, so `hk_pr_small <= hk_pr_f` holds by construction;
(3) `line34_ok` is split into a strict emit check and a posting-grammar check (the old eight-field line is a valid posted
grammar, and `${l##*offlist_n=}` would have misparsed the new tail); (4) the "file never opened" detector is a PATH
allowlist plus a closed-set check on the hooks block, honestly labelled structural, not a syscall trace; (5) per-call shim
flags, an alphabet-override loop, an `errors_count` reorder row and a trailing-slash mutant close the survivors the
test-design seat named; (6) a `budget` call before the reads and an inode-bounded memory note.

New considerations: a trailing slash on the `hooks` path would make the kernel follow a symlinked `hooks`; "exactly two
probed constants" means two names outside the existing allowlist arms; `OFFLIST` is always 1 when `HAS_HOOKS=1`, so the
reads run only on the refusal path. Dispositions are rows D1 to D6 of decision-challenges.md.

## Overview

The second read-only `wipe_check` (run 39136900735, 2026-10-18) refused at the host assertion with exit 34 and printed
(checked in the public log, so "printed"): `wipe-assert: rc=34 reason=offlist top_d=3 top_f=0 top_l=0 top_o=0 repos=0
has_hooks_d=1 lf_entries=0 offlist_n=1`. The sanctioned reading is that the only off-list entry is a directory named
`hooks`; its owner and contents are unread; this is not an emptiness reading. The allowlist and the refusal stand.

PR-A adds ONE optional group of four fixed-vocabulary fields to that exit-34 line, describing the shape of the
`hooks` directory by type and size metadata only: `hk_entries`, `hk_nonfile`, `hk_pr_f`, `hk_pr_small`. The group is
printed only when `has_hooks_d=1`. It changes the stderr text of one refusal. It does not widen `wl_classify`, does not
accept an entry by the name `hooks`, changes no verdict, gate, predicate, mode or workflow input, and dispatches
nothing. The next `wipe_check` cannot be named until this change is merged to `main` (the verb sends the script on stdin
from the dispatched ref) and a new CLO addendum exists; both are the owner's. PR body uses `Ref #10138` and `Ref #6897`
only.

Evidence vocabulary kept throughout: **printed** (in the public run log, checked with `grep -F`), **computed but not
printed** (read from code order), **not measured** (nothing ran). Until a run prints the new group, every `hk_` field is
"not measured".

## Research Insights

**Premise Validation (Phase 0.6), read-only, 2026-10-19:**

- #10138 and #6897 are OPEN; PR #10480 (the three earlier fields) and PR #10506 (the second-run record) are MERGED; PR
  #10523 is OPEN and draft with the placeholder body.
- The run 39136900735 line, quoted above, is in the runbook byte for byte and on #6897 comment 6251307334. CLO addendum 2
  (comment 6251181879) lifted the hold for ONE further `wipe_check`; item 7 says the lift is spent after one run.
- **Cited artifacts that do not exist in the repo:** the brief's "CTO plan" (the four field names) and "CLO evidence
  list" (hash match, UUID-shaped names, nested directories). `git grep` for `hk_entries|hk_nonfile|hk_pr_f|hk_pr_small`
  returned nothing; none of the four #6897 comments that mention the incident, nor any #10138 or #9066 comment, carries
  them. The names are taken as the owner's; the definitions are ruled in this plan, and the CLO list is reconciled below.
- ADR corpus: ADR-239 carries no output-vocabulary, posting or allowlist-change rule; no ADR rejects an optional field
  group. The mechanism is inside the "ids, counts and fixed verdict words only" envelope that the runbook ("What a run can
  claim") and the 2026-10-18 CLO ruling L-3 record.
- Code anchors confirmed on `origin/main`: single `exit 34` site in `git-data-wipe-assert.sh`; `wl_classify` is 25 lines;
  `RE_34`, `line34_ok`, `RC34_LINES_CHECKED`, `MIN_ASSERTIONS` and the loopback arm H live in
  `git-data-wipe-assert.test.sh`; the two access suites contain no `rc=34`, `has_hooks_d` or `offlist_n` string.
- Shipped-hook size fact (CTO, re-computed in this pass: 2784 bytes at HEAD): the hook a host receives is the
  comment-STRIPPED render (`modules/git-data-userdata/main.tf` `replace(file(...), git_data_rationale_strip, "")`):
  1870 to 2784 bytes over six versions, placeholder 197, against raw 6170 to 9325. Unverified: that the retired volume's
  hook came from that same strip render.

**Property List (Phase 0.6b):**

1. A future owner-read of an exit-34 line can say, by type and size metadata only, whether the one off-list entry's
   immediate contents are a single regular file named `pre-receive` of at most 4096 bytes, or something else, at one
   moment.
2. No listing name, size value, owner, mode or content reaches any output stream; only digits and 0/1 bits leave.
3. The refusal, the allowlist, the exit code and every other line are unchanged.
4. An absent group reads "not measured"; a printed `0` never stands in for "not read".
5. The already-printed eight-field line stays a valid posting grammar.

**Cut List (Phase 0.6b):** (a) hash/content read of `pre-receive` and a name-shape counter: owner-only scope items with
their own CLO rulings (decision-challenges.md operator rows). (b) A new loopback arm: arm H already reproduces the
incident layout on real ext4; it gains a tail instead. (c) A fifth "hooks-only-cause" derived field: the fields already
carry the inference (2026-10-18 ruling F-1). (d) A `na` or `0` for absent `hooks`: replaced by omission. (e) Two type
walks (security option B) and two `pre-receive` finds: replaced by one `%y` walk plus one fixed-letter find (D1, D2).
Authority grepped: the script and suite themselves, not a consumer.

**Institutional learnings applied:**

- `2026-10-18-a-counter-field-needs-a-world-where-the-count-is-not-a-flag.md`: every count needs a world where it is at
  least 2, a world with look-alikes, and a world where it is 0 while a neighbour is not.
- `2026-10-18-a-record-pr-said-measured-where-the-evidence-was-printed.md`: printed / computed-not-printed / not
  measured; never "measured" for a field no run has printed.
- `2026-07-24-count-vs-floor-guard-single-value-fixtures-cannot-discriminate-operator.md`: the bound needs 4096 and 4097.
- `2026-09-08-both-my-anti-vacuity-gates-ran-through-the-line-that-voided-them.md` and ADR-193: floors report directly.
- `2026-10-10-my-must-pass-arm-passed-wherever-its-mutation-landed-...md`: each field's must-pass row asserts it on the
  rc=34 line, and deleting the block trips the floor.
- `2026-07-20-the-fix-for-an-evidence-discarding-gate-discarded-its-evidence.md`: the loopback tier cannot run
  unprivileged; arm H's RED-first state is observable only in CI; floors come from an unprivileged, loopback-skipped run.
- `2026-10-11-the-rule-existed-and-the-carrier-...md`: run `technical-ruling-gate.sh --branch` right after editing
  `decision-challenges.md` (done: PASS).
- ADR-197: a zero from a log surface is not evidence of absence; `hk_entries=0` is "zero entries directly inside, at one
  moment", never "empty".

## Research Reconciliation - Spec vs. Codebase

### CTO four fields versus the CLO evidence list

| CLO evidence item | Covered by | What the four fields prove | Residual gap |
|---|---|---|---|
| 1. Hash match (`pre-receive` equals a shipped hook) | Not covered | `hk_pr_f=1` is the exact name as a regular file; `hk_pr_small=1` is size at most 4096 bytes. Necessary conditions only; any tenant file of that size passes | Content identity unproven. Closing it takes a fifth field (a content read compared with a table of stripped-render hashes), its own CLO ruling and likely an ADR-239 amendment. OUT of this PR; owner-only scope item |
| 2. UUID-shaped names | Derivable in one shape only | `hk_entries=1` with `hk_pr_f=1` means the only entry is named `pre-receive`, so no other name exists at that moment | With `hk_entries>=2` or `hk_pr_f=0`, nothing is known about the other names' shape. Enough to keep refusing. A name-shape counter is a new ruling, not recommended |
| 3. Nested directories | Derivable when `hk_nonfile=0` | A regular file has no children and `find` follows no link, so nothing exists below depth 1 | With `hk_nonfile>=1` a directory is indistinguishable from a link, FIFO or socket and depth 2 is unknown |

Sufficiency (CLO, 2026-10-19): the four fields can support a "shape recorded, refusal stands" addendum; they cannot
support "the contents of `hooks` are ours". CTO and CLO agree on this table; neither list is a repo artifact.

### Brief and rulings versus the code

| Claim | Reality | Plan response |
|---|---|---|
| CLO ruling: when `has_hooks_d=0` all four fields print 0 | CTO: a printed 0 reads as a measured zero and breaks the "group iff hooks directory" invariant | CLO withdrew it; the group is omitted when `has_hooks_d=0`; absence reads "not measured" |
| Candidate bound derived from the 9325-byte hook | The shipped hook is the comment-stripped render, 2784 bytes at HEAD | Bound is 4096, derived from stripped sizes; the suite pins the literal against the stripped HEAD size |
| Brief: the two access suites must pass | They contain no `rc=34` text and need no edit | Run unchanged as the passthrough regression |
| The find shim fails any call containing `-printf %y` (flag `fail_find_listing`) | The new shape read also contains `-printf %y` | New per-call flags keyed on the `/hooks` path, ordered first; the generic flag still dies at the top-level listing first |
| `line34_ok` reads `offlist_n` with `${l##*offlist_n=}` | With a tail, `n` swallows the group and `[ "$n" -gt 0 ]` errors | Cut at the first space; strict emit check and posting-grammar check become two functions |
| Runbook "What a run can claim": "an exit-34 refusal also carries one fixed 0/1 field and two counts" | Stale from the merge of this change | In-cell correction plus a dated Superseded marker conditioned on the merge |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly (a host-side diagnostic on a retired volume);
  indirectly, a misleading field (for example `hk_pr_f=1` for a symlinked `pre-receive`, or a printed `0` for an unread
  directory) would let the owner read the refusal as a small step from acceptance and push toward widening the allowlist
  on a volume that may still hold tenant repositories.
- **If this leaks, the user's data is exposed via:** a tenant-controlled name under `hooks` reaching the run log (public,
  as public as #6897) if a later edit interpolates `find` output, `%f`, `%p`, an error message or a size into the line;
  the design interpolates only four values derived in-process from type letters and one fixed letter, under the existing
  stderr discard. `hk_entries` is an uncapped tenant-derived count in a public log; accepted on the precedent of
  `lf_entries` and `repos`.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the diff reads a tenant volume's metadata and prints to a public log, so one
  leaked tenant-shaped name is a single-user exposure; `aggregate pattern` is the next tier down. Inherited from the arc.
  CPO plan-time sign-off 2026-10-19: approved with conditions (see Plan Review);
  `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Decision record

All forks and rulings (CTO R1 to R6, D1 to D6 and test design; CLO L1 to L6; the operator items) are rows of
`knowledge-base/project/specs/feat-one-shot-wipe-assert-shape-fields-rc34/decision-challenges.md`. No question was put to
the owner. Owner-only items are named there and nowhere promised: a fifth field (hash or name shape), acceptance of the
content-identity residual, allowlisting `hooks`, the next `wipe_check` and its new addendum, and the 2026-10-24 and
2026-11-12 dates.

Final design (Ruled by CTO agent, 2026-10-19, confirmed by CLO the same day; the single definition site):

| Field | Definition | Edge values |
|---|---|---|
| `hk_entries` | non-recursive count of entries directly inside the top-level `hooks` directory, dotfiles included | `0` for a directory with no entries (a count at one moment) |
| `hk_nonfile` | how many of them are not regular files (directory, symlink, FIFO, socket, device); from the SAME `find` as `hk_entries`, so never above it | a nested directory counts once at depth 1; depth 2 unknown |
| `hk_pr_f` | `1` iff an entry named exactly `pre-receive` (case-sensitive) is a regular file directly inside `hooks`, no link followed | symlink, directory, FIFO, `Pre-receive`, `pre-receive.bak`: `0` |
| `hk_pr_small` | `1` iff that same file is at most 4096 bytes (`WA_HK_PR_MAX`, one constant); size from inode metadata, content never opened, size never printed | implies `hk_pr_f=1`; 4096 bytes: `1`; 4097: `0` |

Grammar: appended after `offlist_n`, in the order above, as one optional group present iff `has_hooks_d=1`:
`... offlist_n=<n>( hk_entries=<n> hk_nonfile=<n> hk_pr_f=<0|1> hk_pr_small=<0|1>)?`. Prefix byte-identical.

## Implementation Phases

### Phase 1 - RED first (`cq-write-failing-tests-before`), `git-data-wipe-assert.test.sh`

Record each new row RED against the unchanged script before touching it (arm H's RED is observable only in CI; say so
in the PR). Mutants, harness rows and floors are listed once, in the Guard Contract below; the steps here point at it.

1. `RE_34` gains the optional group; `RE_ERR` is unchanged (every key `[a-z_]+`, every value digits).
2. Split the check in two. `line34_ok` is the strict EMIT check on every line the new script prints: group present iff
   `has_hooks_d=1`; `hk_nonfile <= hk_entries`; `hk_pr_small <= hk_pr_f`; `hk_entries >= hk_nonfile + hk_pr_f`;
   `hk_pr_f=1` implies `hk_entries >= 1`; the existing `has_hooks_d=1` implies `offlist_n >= 1` kept. Cut
   `n=${n%% *}` after `${l##*offlist_n=}` (otherwise `n` swallows the group and `[ "$n" -gt 0 ]` errors, reddening every
   group row for the wrong reason). A new `line34_grammar_ok` is the posting grammar (CLO L3): it additionally accepts the
   already-printed eight-field line (`has_hooks_d=1`, no group; the run-39136900735 line is its must-PASS row) and rejects
   everything else.
3. Existing rc=34 rows: those with `has_hooks_d=0` keep their expected tails; A120, A122, the `hooks` loop row with
   `has_hooks_d=1`, `caught_hookstenant`, `caught_hooksdir`, `L34` (B04b verb row) and arm H gain the group.
4. New worlds, each pinned by WHOLE-line equality (synthesized names only, `cq-test-fixtures-synthesized-only`):

   | World (`hooks` contents) | Group |
   |---|---|
   | empty directory (existing A120) | `hk_entries=0 hk_nonfile=0 hk_pr_f=0 hk_pr_small=0` |
   | `pre-receive` only, a 0-byte regular file | `1 0 1 1` |
   | a copy of the stripped HEAD hook as `pre-receive` + a tenant-shaped synthesized file + a dotfile | `3 0 1 1` |
   | `pre-receive` + a subdirectory holding two files | `2 1 1 1` |
   | a directory, a symlink, a FIFO, a regular file `post-receive` | `4 3 0 0` |
   | `pre-receive` as a symlink to a live regular file OUTSIDE `hooks` (a dangling link would make the follow-symlink mutant equivalent) | `1 1 0 0` |
   | four regular files `Pre-receive`, `pre-receive.bak`, `old-pre-receive`, `pre-receivX` (kills glob, case-insensitive, prefix and suffix mutants in one world) | `4 0 0 0` |
   | `pre-receive` of exactly 4096 bytes | `1 0 1 1` |
   | `pre-receive` of 4097 bytes | `1 0 1 0` |
   | top-level `hooks` as a symlink whose target holds entries (a followed link would change the line) | no group, `has_hooks_d=0` |
   | top-level `hooks` as a file, FIFO, `hooks.d`, `Hooks`, `old-hooks` (existing variants keep their tails) | no group |

5. Shim flags, keyed per call on the `/hooks` path (case arms ordered BEFORE the generic `-printf %y` arm; the generic
   flag still dies at the top-level listing before the hooks read): shape call (last argument `%y`) fails;
   `pre-receive` call (has `-name`) fails; a `$W/hooks_ht` override makes the shape call print an arbitrary type string
   (loop over `fsdcbpDUl`, because unprivileged worlds cannot create `s`, `c`, `b`, `D` or `U` entries, and an unknown
   character such as `x`); a flag that bumps `files/sys/fs/ext4/dm-3/errors_count` on the `/hooks` call. Rows: rc 33 for
   `hooks_shape_failed`, `hooks_shape_unparseable`, `hooks_pr_failed`, `hooks_pr_unparseable` (not an rc=34 line, no `hk_`
   text); an rc 33 `errors_count_changed_by_listing` row proving the reads sit before the `e1` read.
6. Mutants: see the Guard Contract matrix. Each case requires rc 34 AND the whole expected line (or the rc-33 word for
   the failure mutants); `line34_is` in mutant rows also checks every stderr line against `RE_ERR` and the corpus grep
   (it checks only the last line today, so a mutant emitting an earlier named line would pass).
7. "File never opened" detector (structural, NOT an open-syscall trace: the suite has no `strace`, A116 refuses xtrace,
   shims see only argv): the test PATH is shims plus an explicit allowlist so an unlisted reader (`cat`, `head`,
   `sha256sum`, `xxd`, `od`, `strings`) exits 127 and the case fails, plus a closed-set check that every line of the hooks
   block in the script equals a reviewed literal (covers the bash-builtin readers `$(<f)`, `read <f`, `mapfile`).
8. Suite rows: the script's `hooks` literal in `wl_classify` and `WA_HK_DIR` are equal; the basename of `HOOKS_DIR` and
   `PRE_RECEIVE` in `git-data-bootstrap.sh` equal `WA_HK_DIR` and `WA_HK_PR`; `WA_HK_PR` has none of `*?[\`; the new find
   path has no trailing slash; the stripped size of `git-data-pre-receive.sh` (method of
   `git-data-render-strip-parity.test.sh`) is at most `WA_HK_PR_MAX`, and the script literal equals the suite's pinned
   `4096`; `grep -c 'timeout 30 find "\$WA_MNT/\$WA_HK_DIR"'` equals 2.
9. Leak corpus: add ONE tenant-shaped synthesized name to the existing `PATS` listing. Do NOT add `pre-receive` (it is a
   compile-time constant and `state/argv` legitimately records `-name pre-receive` and `-size -4097c`); size digits are
   checked against stdout and stderr only, not `state`.
10. Floors re-measured from an UNPRIVILEGED, loopback-skipped run: `EXPECTED_RC34_LINES`, `EXPECTED_INVARIANT_RUNS`,
    `MIN_ASSERTIONS` (each literal set to the measured value and annotated "measured unprivileged, loopback skipped,
    2026-10-19"); a new exact `HK_GROUP_LINES_CHECKED` counter (the existing `RC34_LINES_CHECKED` is a `-lt` floor and
    CI's loopback tier lifts `executed`); `EXPECTED_ARMS_C` stays 8.

### Phase 2 - the script change (`git-data-wipe-assert.sh`)

1. Constants beside `WA_SNAP`: `readonly WA_HK_DIR=hooks`, `readonly WA_HK_PR=pre-receive`, `readonly WA_HK_PR_MAX=4096`,
   with a comment: the bound is a coarse plausibility bound derived from the STRIPPED hook (1870 to 2784 bytes over six
   versions, 197 for the placeholder), not an identity test; `hk_pr_small=1` says nothing about provenance or content,
   `hk_pr_small=0` is not evidence of foreign content (an unstripped copy reads 0); that the retired volume's hook came
   from the same render is unverified; any change of the value returns to the CLO.
2. `wl_classify` is NOT edited (its body must stay byte-identical; an AC checks it); its own `hooks` literal stays and a
   suite row ties it to `WA_HK_DIR`.
3. In `wipe_listing`, after the lost+found block and before the `e1` errors-count read (so a filesystem error induced by
   the reads is caught by `errors_count_changed_by_listing`; `wl_valid` and `wa_release` still follow), guarded by
   `HAS_HOOKS=1`. `HAS_HOOKS=1` implies `OFFLIST=1` (no allowlist arm for `hooks`), so the reads run only on the refusal
   path. Add the new names to the function's existing `local` list (declare, then assign with `|| die`); the group
   string is a global like `HAS_HOOKS` and `OFFLIST_N`:

   ```bash
   HK_TAIL=""
   if [ "$HAS_HOOKS" = 1 ]; then
     budget
     ht="$(timeout 30 find "$WA_MNT/$WA_HK_DIR" -mindepth 1 -maxdepth 1 -printf '%y')" || die 33 hooks_shape_failed
     nf="$(printf '%s' "$ht" | tr -d f | wc -c)" || die 33 hooks_shape_failed
     al="$(printf '%s' "$ht" | tr -d 'dflcbpsDU' | wc -c)" || die 33 hooks_shape_failed
     [[ "$nf" =~ ^[0-9]+$ && "$al" =~ ^[0-9]+$ ]] || die 33 hooks_shape_unparseable
     [ "$((10#$al))" -eq 0 ] || die 33 hooks_shape_unparseable
     pr="$(timeout 30 find "$WA_MNT/$WA_HK_DIR" -mindepth 1 -maxdepth 1 -name "$WA_HK_PR" -type f \( -size -$((WA_HK_PR_MAX + 1))c -printf s -o -printf b \))" || die 33 hooks_pr_failed
     [[ "$pr" =~ ^[sb]?$ ]] || die 33 hooks_pr_unparseable
     HK_PR_F=0; [ -n "$pr" ] && HK_PR_F=1
     HK_PR_SMALL=0; [ "$pr" = s ] && HK_PR_SMALL=1
     HK_TAIL=" hk_entries=${#ht} hk_nonfile=$((10#$nf)) hk_pr_f=$HK_PR_F hk_pr_small=$HK_PR_SMALL"
   fi
   ```

   (Sketch: work-time code is the authority; one statement per line so mutant anchors are unique. Invariants:
   `hk_nonfile <= hk_entries` by construction from one walk, `hk_pr_small <= hk_pr_f` by construction from one find. The
   letter `s` or `b` stays in a shell variable and never reaches the line. `${#ht}` counts bytes under the exported
   `LC_ALL=C`. The type string is bounded by the inode count; the bootstrap comment gives 655,360 inodes for the 10 GB
   volume, unverified for this exact volume, so at most about 0.65 MB, and `tr | wc -c` over it is linear. No `%f`/`%p`,
   no `-L`/`-H`, no trailing slash on the `hooks` path, no new fd, no `2>&1`, no read of file content, no `-iname`.)
4. The `say` gains `$HK_TAIL` after `offlist_n=$OFFLIST_N`; the single `exit 34` site is unchanged; the `OFFLIST` logic,
   the other `die` lines, rc 37 and the success line are unchanged. Update the script header comment (field list, "the
   group appears only from the merge of the change that adds it", "the bit proves the name only; the size is metadata,
   the content is never opened"). Check at work time how the suite derives the die-word set (it may check rc parity
   only) and add the four `hooks_*` words wherever it enumerates words.
5. `WA_BUDGET_S` stays 240. Worst case added wait is 2 x 30 s after the `budget` call; a pass at 240 s plus two full
   timeouts reaches the 300 s ssh bound: pathological only, not a reason to move the constant.
6. Run `bash -n` on the script.

### Phase 3 - the runbook (`git-data-luks-cutover-5274.md`, exit-34 section and its neighbours)

Five edit sites. Each added sentence says whether it is printed, computed-not-printed, not measured, inherited or policy,
carries the date 2026-10-19 where it states a fact, and is conditioned on the merge ("appear only from the merge of the
change that adds them"); none is past tense about a run having printed the group. Strings go to the CLO before merge (L6).
CPO wording guards bind every site: lead the new text with "shape recorded, refusal stands, content unread"; a decode
row states that `hk_pr_small=1` supports no inference about identity and that content identity (hash) stays uncovered;
the single shape `hk_entries=1 hk_nonfile=0 hk_pr_f=1 hk_pr_small=1` is never presented as a pass condition; the decode
text names no deadline or date other than evidence dates; nothing says when or whether a `wipe_check` runs.

1. **Posting list and grammar** ("Other results that route to the CLO" and the grammar paragraph of "Reading the exit-34
   line"): replace the closed-list sentence with the CLO L3 sentence verbatim (decision-challenges.md row L3), adding
   "an absent `hk_` group is 'not measured'; never post a 0 in its place"; state the two accepted exact grammars (the
   eight-field line, and the eight fields plus the four-field group present only when `has_hooks_d=1`) and the fallback
   (verdict word and five counts only for a partial group, a group with `has_hooks_d=0` or an extra token); run
   39136900735 stays valid under the first grammar and its `hk_` fields read "not measured".
2. **Field bullets and decode table**: the four definitions (bound, stripped-hook derivation, "unverified" strip-render
   provenance) and the CTO/CLO decode rows (one regular file `pre-receive` of at most 4096 bytes; zero entries; above the
   bound; any other combination post the fields only; `offlist_n>=2` says nothing about the other entries); the existing
   `has_hooks_d=1 offlist_n=1 lf_entries=0` row stays.
3. **Four rc-33 words** (`hooks_shape_failed`, `hooks_shape_unparseable`, `hooks_pr_failed`, `hooks_pr_unparseable`): named
   where the runbook enumerates host-listing refusals (at plan time the runbook names verdict words only, not rc-33
   words: add one sentence in "Reading the exit-34 line"), with "a failed shape read refuses at rc 33 with no `hk_`
   evidence".
4. **Superseded marker** under "What a run can claim"'s sentence ("an exit-34 refusal also carries one fixed 0/1 field and
   two counts"): in-cell correction plus a dated blockquote naming the sentence by its opening words, conditioned on the
   merge. Sweep every sibling repeating it (`git grep -n "one fixed 0/1 field"` returned only the runbook at plan time;
   re-run at work time).
5. **Status and Not proven**: a dated status note (the fields exist from the merge; none has been printed by a run) and a
   Not proven line: the fields are not measured until a run prints them; content identity and the strip-render provenance
   of the retired hook are unverified; the allowlist question stays tracked on #6897. Do not edit the first-run and
   second-run records, the Policy bullet or the verdict map.

### Phase 4 - hand-offs that dispatch nothing

1. Show the CLO the final strings (L6 list) and record the verdict in `decision-challenges.md`.
2. PR body (written by ship): "Ref #10138", "Ref #6897", never `Closes`/`Fixes`/`Resolves`; states the change alters the
   stderr output of the rc=34 refusal only, "the fields appear only from the merge of the change that adds them", no run
   was dispatched, no gate, allowlist, predicate or mode changed, no ledger row, `expires_on` or retention position moved,
   and nothing about the next `wipe_check`. No `wipe`, `wipe_finish`, `snapshot_clear` or `wipe_check` is dispatched;
   `git-data-cutover.yml` is never dispatched; nothing is posted to #6897 or #9066.
3. Never push or sync while the PR is in the merge queue (merge_group CI takes about 45 to 55 minutes).

### Phase 5 - local gate (focused suites only; CI's required test context is the gate)

`bash apps/web-platform/infra/git-data-wipe-assert.test.sh`, `git-data-wipe-access.test.sh`,
`git-data-cutover-access.test.sh`, `.claude/hooks/grep-q-pipe-guard.test.sh`, `bash -n` on the script, markdownlint on
every touched `.md` (including generated spec files), `python3 scripts/lint-guard-contract.py` on the plan.

## Files to Edit

- `apps/web-platform/infra/git-data-wipe-assert.sh` (constants, the guarded hooks reads, the `say` tail, header comment; `wl_classify` untouched)
- `apps/web-platform/infra/git-data-wipe-assert.test.sh` (RE_34, the two check functions, worlds, shim flags, mutants, detector, floors)
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` (Phase 3 edits only)

## Files to Create

- `knowledge-base/project/plans/2026-10-19-feat-wipe-assert-hooks-shape-fields-plan.md` (this file)
- `knowledge-base/project/specs/feat-one-shot-wipe-assert-shape-fields-rc34/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-wipe-assert-shape-fields-rc34/decision-challenges.md`
- `knowledge-base/project/learnings/2026-10-19-<slug>.md` (one learning, at work/compound time)

## Open Code-Review Overlap

None. Checked 2026-10-19 against the open `code-review` issues for the five files this plan names (the three edited files
and the two access suites it runs): no body contains any of the paths.

## Architecture Decision (ADR/C4)

Skipped: no architectural decision is made. The allowlist (the recorded gate) is unchanged; fields are added inside the
ruled envelope. Test applied: a competent engineer reading ADR-239 and the C4 model is not misled about the system after
this ships. C4 not touched: no actor, system, container, data store or access relationship changes (output text of an
existing host-to-runner edge only; the three `.c4` files were not changed and no cardinality embedded in them moves).
Ruled by CTO agent, 2026-10-19: neither ADR nor C4; a content-read hash field is where an ADR-239 amendment is expected.
Ruled by CLO agent, 2026-10-19: no ADR-239 amendment for this PR.

## Encryption Posture

Skipped (Phase 2.11): no persistent store and no new cross-component connection. The existing read-only listing of the
retired plaintext volume inside a transient host-local snapshot is unchanged.

## Infrastructure (IaC)

Skipped (Phase 2.8): no new infrastructure, no provisioning, no apply. The host script is already delivered by the
existing verb over its single ssh site; nothing here installs, enables or configures anything on a host.

## Observability

```yaml
liveness_signal:
  what: the line "[git-data-cutover] probe-stderr: wipe-assert: rc=34 reason=offlist ... offlist_n=<n> hk_entries=<n> hk_nonfile=<n> hk_pr_f=<0|1> hk_pr_small=<0|1>" in the job log of the git-data cutover workflow (step "Host-side wipe assertion (W7)"), beside the verdict annotation wipe_boot_layout_signal_offlist
  cadence: per dispatched wipe_check or wipe run (on demand, named by the owner; nothing is scheduled by this change)
  alert_target: the existing notify job of the cutover workflow (email and the ci/git-data-cutover issue), unchanged by this change
  configured_in: .github/workflows/git-data-cutover.yml (unchanged) and apps/web-platform/infra/git-data-cutover.sh _access_stderr (unchanged)
error_reporting:
  destination: GitHub Actions run log plus the verdict annotation; a one-shot host script on a retired volume, not a Sentry-instrumented server, so there is no Sentry project or DSN
  fail_loud: exit 34 maps to wipe_boot_layout_signal_offlist and the run fails; a failed hooks read dies at rc 33 (hooks_shape_failed, hooks_shape_unparseable, hooks_pr_failed, hooks_pr_unparseable) and the run fails
failure_modes:
  - mode: a field is missing, non-numeric, out of range, reordered, partial or present with has_hooks_d=0 in the rc=34 line, or truncated on its way to the log
    detection: the strict emit check on every rc-34 row, the line34_ok invariants, arm H equality and the verb-tier passthrough row (layer 6, workflow-run log)
    alert_route: CI red on the required test context (infra-validation)
  - mode: a listing name, size or error text reaches stdout, stderr or any state file
    detection: the per-run leak invariant over the synthesized corpus (hooks holding pre-receive plus a tenant-shaped name in one listing), the file-never-opened detector and the loopback corpus check (layer 6)
    alert_route: CI red on the required test context
  - mode: a field misdiagnoses (symlinked pre-receive read as a file, a prefix glob, a followed link or trailing slash, an off-by-one size bound, a flag where a counter is needed)
    detection: the world table and the named mutants of the Guard Contract matrix (layer 6)
    alert_route: CI red on the required test context
  - mode: the shape read itself fails or hangs on a live volume
    detection: rc 33 with a fixed hooks_* word, or rc 16 budget_exceeded, in the run log and the verdict annotation (layer 6, workflow-run log)
    alert_route: the existing notify-failure job
logs:
  where: GitHub Actions run log of the cutover workflow (gh run view <run> --log)
  retention: GitHub Actions log retention as configured for the repository; the setting was not read in this plan
discoverability_test:
  command: grep -cF 'hk_pr_small=$HK_PR_SMALL' apps/web-platform/infra/git-data-wipe-assert.sh
  expected_output: 1
```

Honest limit: the discoverability command proves the group is wired into the script (one construction site), not that a
live run printed it; the live signal exists only after the owner names a run, which this change neither dispatches nor
promises. The behavioural proof is the suite (shim, loopback and verb tiers) in CI. If work-time code spells the
construction differently, the command is updated with it.

## Guard Contract

### Guard 1 - rc=34 group grammar, shape-only and no-name invariant

**Property.** Every rc=34 line the host script can print carries the four `hk_` fields as one group if and only if
`has_hooks_d=1`; each is a pure function of depth-1 type and size metadata of a real top-level `hooks` directory; no
listing name, size value, owner, mode or content reaches any output stream; the allowlist, the verdict and every other
line are unchanged.

**Assembly.** The chokepoint is the single `say` ahead of the one `exit 34` (an anchored grep for the exit line finds it
once); the suite quantifies over it from the shim tier (`expect_refuse` whole-line check on every rc-34 row plus the
per-run `invariants` leak check), the `line34_is` cases of the mutant rows, the loopback tier (arm H equality and the
corpus leak check) and the verb tier (the `L34` B04b passthrough row proving `=`, `_` and digits survive
`_access_stderr`/`_access_clean`). Also the runbook field list and example line, the script header comment and the verb's
generic `probe-stderr:` passthrough (no change; run once). A second rc-34 emission site would not pass the strict check
unless added to the same chokepoint; the rc-table/`die`/verb-arm parity rows and the `RC34_LINES_CHECKED` and
`HK_GROUP_LINES_CHECKED` floors make one visible.

**Mutation matrix** (derived from the design, written before the guard; each case requires rc 34 and the whole expected
line, or the fixed rc-33 word for the failure rows):

| # | Mutation | Expected |
|---|---|---|
| 1 | `m-hk-fields-always`: the `HAS_HOOKS=1` guard on the group is dropped (the guard's own dispatch decides whether the group is emitted) | RED (file, symlink, FIFO and `hooks.d` worlds expect no group) |
| 2 | `m-hk-second-name`: a second probed name added after the compliant `pre-receive` (a second member) | RED (the `post-receive` world, `4 3 0 0`) |
| 3 | `m-hk-entries-flag`: `hk_entries` as 0/1 | RED (the three-entry world) |
| 4 | `m-hk-recursive`: `-maxdepth 1` dropped; and `m-hk-mindepth0`: `-mindepth 0` | RED (subdirectory world; empty world gains one entry) |
| 5 | `m-hk-nonfile-dirs-only` and `m-hk-nonfile-alphabet` (counts only `d`, `l`, `p`) | RED (mixed world; the `hooks_ht` override loop over `fsdcbpDUl`) |
| 6 | `m-hk-pr-follows-symlink` (`-type f` becomes `-xtype f`) | RED (symlink world pointing at a live file) |
| 7 | `m-hk-pr-glob`, `-iname`, prefix or suffix match | RED (the four look-alike-names world) |
| 8 | `m-hk-small-off-by-one` in both directions, and `m-hk-sb-swapped` (`s` and `b` exchanged) | RED (the 4096 and 4097 worlds) |
| 9 | failure ignored for the shape call, for the `pre-receive` call; the shape-unparseable and pr-unparseable checks dropped | RED (the four rc-33 rows and the `hooks_ht` override) |
| 10 | `m-hk-trailing-slash`: `"$WA_MNT/$WA_HK_DIR/"` | RED (the symlinked-`hooks` world and the negative-grep row) |
| 11 | `m-hk-after-e1`: the hooks block moved after the `e1` errors-count read (an ORDER property: a reorder row, not a delete row) | RED (the `errors_count` bump flag, rc 33 `errors_count_changed_by_listing` expected) |
| 12 | a content read of `pre-receive` added (`cat`, `head`, `sha256sum`, `$(<f)`) | RED (PATH allowlist and the closed-set hooks-block check) |

The matrix excludes "the strict check deleted or never reached" (a suite mutation, not a script mutation); that case is
caught by the floors: `RC34_LINES_CHECKED`, `HK_GROUP_LINES_CHECKED` and `MIN_ASSERTIONS`.

**Harness rows.** `line34_ok` (strict emit) is driven directly: it must REJECT a group with `has_hooks_d=0`, no group with
`has_hooks_d=1`, a partial group at each truncation point, a swapped order, `hk_nonfile>hk_entries`,
`hk_entries=1 hk_nonfile=1 hk_pr_f=1` (the only row isolating the `entries >= nonfile + pr_f` predicate),
`hk_pr_small=1 hk_pr_f=0`, `hk_pr_f=2` and a fifth token; it must ACCEPT a non-canonical good group
(`hk_entries=7 hk_nonfile=2 hk_pr_f=0 hk_pr_small=0`). `line34_grammar_ok` must ACCEPT the old eight-field line and
that non-canonical group, so a regex loosened to `.*`, a dropped predicate or a guard that rejects everything goes RED.
A neutered `fail` must still trip the floor (ADR-193).

**Post-change mutation (remediation validity).** After the group lands the existing `hooks` loop rows carry a tail; the
mutation that defeats the mechanism after the change is the one that deletes only the tail from the expected strings of
those rows: the must-PASS row for the group (the `1 0 1 1` world) and the harness ACCEPT rows keep it from reading green.

**Anchor.** No stored hash or count floor compares against the guarded thing; the strict regex and the literal `4096`
are literals in the suite, pinned against the stripped HEAD hook size (a repo file, never the volume). The external
anchor for a weakening is that the CLO sees the final strings before merge (L6) and the line prefix stays pinned by
whole-line equality.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add four shape fields on the wipe-assert rc=34 (reason=offlist) line ONLY: hk_entries, hk_nonfile, hk_pr_f, hk_pr_small (CTO plan)" [brief] | Phase 2, Decision record | mapped |
| 2 | "FIRST reconcile these with the CLO's evidence list (hash match, UUID-shaped names, nested directories), which differs from the CTO's four fields; record the reconciliation in the plan" [brief] | Research Reconciliation table | mapped |
| 3 | "spawn soleur:engineering:cto for the technical ruling and soleur:legal:clo for the legal posture" [brief] | decision-challenges.md rows R1 to R6, D1 to D6, L1 to L6 | mapped |
| 4 | "do NOT widen the allowlist (wl_classify) and do NOT accept an entry by the name \"hooks\"; the refusal stands" [brief] | Phase 2 step 2, AC allowlist check | mapped |
| 5 | "No wipe, wipe_finish, snapshot_clear or wipe_check is dispatched by the agent; never dispatch git-data-cutover.yml. Agents do not post to #6897 or #9066." [brief] | Phase 4 steps 1 and 2 | mapped |
| 6 | "PR body uses \"Ref #10138\" and \"Ref #6897\" only, never Closes/Fixes/Resolves" [brief] | Phase 4 step 2, AC | mapped |
| 7 | "Never push or sync while the PR is in the merge queue" [brief] | Phase 4 step 3 | mapped |
| 8 | "Tests: git-data-wipe-access.test.sh and git-data-cutover-access.test.sh must pass." [brief] | Phase 5, AC | mapped |
| 9 | "Evidence-strength vocabulary to keep: \"printed\" ..., \"computed but not printed\", \"not measured\"" [brief] | Overview, Phase 3 | mapped |
| 10 | "Persist every decision as a row of the `\| Item \| Class \| Ruling \|` table" [brief] | decision-challenges.md | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Script reads and `say` tail | "add four shape fields on the wipe-assert rc=34 (reason=offlist) line ONLY" | asked |
| Suite worlds, mutants, harness rows, floors | "Tests: git-data-wipe-access.test.sh and git-data-cutover-access.test.sh must pass." | inferred - justification: a new output field on a public-log line needs a suite that pins it (CTO ruling on test design); the brief names only the two access suites |
| Edit to `git-data-wipe-assert.test.sh` | - | inferred - justification: the unit suite is the only test of the script; the two access suites contain no rc=34 text (checked) |
| Runbook edits (closed list, grammar, decode rows, die words, Superseded marker, status) | "record the reconciliation" and "Evidence-strength vocabulary to keep" | inferred - justification: CLO L3 and L6 require the posting rule and decode text to ship with the fields; a field the owner may not read or post is unusable |
| CLO sight of final strings | - | inferred - justification: CLO ruling L6, a condition |

### Split Assessment

- Subsystems touched: 2 - `apps/web-platform/infra/`, `knowledge-base/engineering/operations/runbooks/`
- Planned files: 3 edited (+3 spec/plan files) | Estimated changed lines: about 450 (script about 30, test about 350, runbook about 70)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** Engineering, Legal

### Engineering

**Status:** reviewed
**Assessment:** Ruled by CTO agent, 2026-10-19 (rows R1 to R6, D1 to D6 and test design): definitions, the 4096-byte bound derived from the stripped hook, omission when `hooks` is not a directory, order and grammar, same-session reads before teardown, linear-time counting from one `%y` walk, one fixed-letter `pre-receive` find, `die 33` failure arms, test worlds and mutants, no ADR or C4, low host risk.

### Legal

**Status:** reviewed
**Assessment:** Ruled by CLO agent, 2026-10-19 (rows L1 to L6, follow-up Q1 to Q3): all four fields accepted with conditions, `pre-receive` accepted as the second and last name probed outside the allowlist arms, content read/hash out of scope and needing its own ruling, closed posting list amended, two accepted grammars, forbidden wording extended, no ADR-239 amendment or addendum for this PR (both needed before the next `wipe_check` is named). CTO D1 to D5 change none of the four accepted conditions; the CLO sees the final strings at work time. GDPR gate (Phase 2.7): the brand-survival trigger fires; the CLO ruling is the compliance review; no schema, auth or API surface, no new processing activity (PA-36 unchanged), no `compliance-posture.md` change.

### Product/UX Gate

**Tier:** none (no user-facing surface; no new component, page or flow). CPO plan-time sign-off: approved with conditions (see Plan Review); conditions are carried in Phase 3 and the acceptance criteria.

## Acceptance Criteria

<!-- founder-stated check: the owner stated that nothing is dispatched, no agent posts to #6897 or #9066, and the next wipe_check needs a deploy plus a new CLO addendum -->

### Pre-merge (PR)

- [ ] The group is built once and appended after `offlist_n`, prefix byte-identical, single exit: `grep -cF 'hk_pr_small=$HK_PR_SMALL' apps/web-platform/infra/git-data-wipe-assert.sh` prints `1` (spelling per work-time code) and `grep -cE '^ +exit 34$' apps/web-platform/infra/git-data-wipe-assert.sh` prints `1`.
- [ ] The allowlist is not widened and `hooks` is not accepted: `diff <(git show origin/main:apps/web-platform/infra/git-data-wipe-assert.sh | sed -n '/^  wl_classify() {/,/^  }/p') <(sed -n '/^  wl_classify() {/,/^  }/p' apps/web-platform/infra/git-data-wipe-assert.sh)` prints nothing (exit 0); the existing mutants `m-hooks-allowlisted` etc. stay RED in the suite output; A120 still expects rc 34.
- [ ] The `hk_` group is emitted if and only if `has_hooks_d=1`, all four together, in the order `hk_entries hk_nonfile hk_pr_f hk_pr_small`; no `0` or `na` is printed in its place; a line with `has_hooks_d=0` and any `hk_` field, or a partial group, is rejected by both check functions; a `has_hooks_d=1` line without the group is rejected by the strict emit check (the new script never emits it; a failed read dies at rc 33) and accepted only by the posting-grammar check.
- [ ] Exactly two names outside the existing allowlist arms are probed, each a readonly constant: `grep -cE '^  readonly WA_HK_(DIR|PR)=' apps/web-platform/infra/git-data-wipe-assert.sh` prints `2` (`hooks` as a directory at the top level; `pre-receive` as a regular file directly inside it); `hk_pr_f` and `hk_pr_small` are `0|1` only, exact and case-sensitive; the size and the `s`/`b` letter never reach the line; the file is never opened (detector row green, content-read mutant killed).
- [ ] Forbidden constructs absent from added script lines: `git diff origin/main -- apps/web-platform/infra/git-data-wipe-assert.sh | grep -cE '^\+[^#]*(-L |-H |-iname|%f|%p|2>&1|cat |head |sha[0-9]*sum|\$WA_HK_DIR/")'` prints `0`.
- [ ] Failed or unparseable reads die at rc 33 with one of the four fixed words, never default to 0 and never print a partial line; `budget` is called once before the reads; `WA_HK_PR_MAX` is one constant equal to the suite's pinned `4096` and at least the stripped HEAD hook size (suite row).
- [ ] `git diff origin/main --stat` lists only: the script, the unit suite, the runbook, this plan, `specs/feat-one-shot-wipe-assert-shape-fields-rc34/{tasks.md,decision-challenges.md}`, the learning file and the generated `knowledge-base/INDEX.md` if the pipeline rewrites it - no workflow, no `git-data-cutover.sh`, no access suite, no `.tf`.
- [ ] `bash apps/web-platform/infra/git-data-wipe-assert.test.sh` exits 0 with 0 failures and the new worlds, mutants, harness rows and failure rows listed `ok`; Phase 1 recorded those rows RED against the unchanged script first (arm H's RED observable only in CI, stated in the PR); floors are the measured unprivileged values.
- [ ] `git-data-wipe-access.test.sh` and `git-data-cutover-access.test.sh` (the brief's required tests) and `.claude/hooks/grep-q-pipe-guard.test.sh` exit 0, unchanged.
- [ ] CI's required test context is green, including the loopback step (arm H ran: `LOOPBACK_UNAVAILABLE` absent from that job's log).
- [ ] No `| grep -q` in the diff: `git diff origin/main -- apps/web-platform/infra/git-data-wipe-assert.sh apps/web-platform/infra/git-data-wipe-assert.test.sh knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md | grep -cE '^\+.*\| *grep -q'` prints `0`.
- [ ] Forbidden wording absent from every ADDED line of the three edited files (the plan and decision-challenges.md quote the list and are excluded): `git diff origin/main -- <the three files> | grep -ciE '^\+.*\b(erased|wiped|secure erasure|no copies|holds no personal data|benign|harmless|false positive|waivable|will pass|is unblocked|our hook|the hook is|contains only|holds only|consists of|verified|fingerprint|all clear|de-risked|would be accepted|can be allowlisted)\b'` prints `0`, with the negative control (an inserted `benign`) hitting; any hit that is a negation or an exclusion description is reviewed by hand and listed in the PR.
- [ ] The runbook carries the CLO L3 sentence verbatim, the two accepted grammars and the fallback, the four field definitions with the bound and "unverified" strip-render provenance, the decode rows, the four rc-33 words, the in-cell correction plus a dated Superseded marker under the "one fixed 0/1 field and two counts" sentence, and the status and Not proven lines; every added sentence about the fields is conditioned on the merge and none is past tense about a run having printed them; no runbook sentence says "measured" for an `hk_` field.
- [ ] The PR body uses `Ref #10138` and `Ref #6897` and never `Closes`/`Fixes`/`Resolves`; it says the PR changes the stderr output of the rc=34 refusal only, that the fields "appear only from the merge of the change that adds them", that no run was dispatched, no gate, allowlist, predicate or mode changed, no ledger row, `expires_on` or retention position moved, and says nothing about the next `wipe_check`.
- [ ] The CLO has seen the final strings (L6 list) and the verdict is recorded in `decision-challenges.md`; `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` passes.
- [ ] CPO conditions (Plan Review) are met and `soleur:engineering:review:user-impact-reviewer` ran at review time (threshold `single-user incident`).

### Post-merge (operator)

None. This change dispatches nothing and posts nothing; any later `wipe_check` is a separate owner-named command after a new CLO addendum, outside this PR's acceptance.

## Test Scenarios

Layers: `integration` (shell suite over a simulated host with PATH shims), `integration-loopback` (a real ext4 image with the
production layout; arm H only, one new tail), `integration-verb` (the `L34` passthrough row through
`_access_stderr`/`_access_clean`). No `e2e`, no browser. The worlds, mutants and harness rows are the tables in Phase 1 and
the Guard Contract; the three scenarios that matter most:

- Given a `hooks` directory holding only a 0-byte regular `pre-receive`, when the assertion refuses at rc 34, then the line
  ends `hk_entries=1 hk_nonfile=0 hk_pr_f=1 hk_pr_small=1` and equals the expected whole line.
- Given `hooks` holding the stripped HEAD hook as `pre-receive`, a tenant-shaped synthesized file and a dotfile, then the
  tail is `3 0 1 1` and the tenant-shaped name appears nowhere in stdout, stderr or any state file.
- Given the shape `find` fails or prints an unknown type character, then the run refuses at rc 33 with the fixed word and
  prints no `hk_` text.

## Dependencies & Risks

- Loopback arm H cannot run unprivileged: its RED-first state and its new tail are observable only in CI; floors come from
  the unprivileged run and CI's loopback tier lifts `executed`, so the exact counters stay as the floors of record.
- The CLO rule "exactly two names outside the allowlist arms are probed" binds future edits; a third name, a list or a
  configurable name is a new ruling.
- A failed shape read turns an rc-34 evidence run into an rc-33 refusal with no `hk_` evidence; fail-closed, costs a
  re-dispatch and a new addendum (CTO weighed and chose it over a partial tail).
- Host time: the added reads are at most 2 x 30 s after a `budget` check; a pass at 240 s plus both full timeouts reaches
  the 300 s ssh bound (pathological; `WA_BUDGET_S` is unchanged). The type string is bounded by the inode count
  (655,360 per the bootstrap comment, unverified for this volume).
- The group might be read as progress toward unblocking the wipe. Wording guard: every reading carries "at one moment",
  "content unread", the evidence word and the run URL; the PR body and the runbook say nothing about the next
  `wipe_check` passing. Deadlines 2026-10-24 (DPD 10.3(b) re-ruling) and 2026-11-12 (outer date) are unchanged and not
  promised.
- Time-of-check: the reads happen inside the same transient read-only host-local snapshot session, before teardown, so no
  fact changes between reads; the `errors_count` check after them covers induced filesystem errors.

## Not In Scope

- A hash or content read of `pre-receive` (`hk_pr_known`) and a name-shape counter: owner-only scope items with their own
  CLO rulings; recorded in decision-challenges.md operator rows, which `ship` renders and files as an `action-required`
  issue.
- Any allowlist change, any acceptance of `hooks`, any ADR-239 amendment.
- Any dispatch, any post to #6897 or #9066, any change to the ledger, `expires_on` or retention position.
- Pre-existing items noted by the 2026-10-18 review and left alone: a machine parity row between the runbook field list and
  the regexes, and naming the `hooks` literal inside `wl_classify` as a constant (it is not touched here; a suite row ties
  it to `WA_HK_DIR`).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold
  will fail `deepen-plan` Phase 4.6; this one carries the threshold `single-user incident`.
- Do not edit `wl_classify` to share a constant with the new reads: the byte-identity AC and the existing mutants' text
  anchors depend on it.
- The shim's `fail_find_listing` flag keys on `-printf %y`, which the new shape `find` also contains; the new `/hooks`
  flags must be ordered first and disjoint in their worlds.
- Bash pattern substitution (`${ht//f/}`) on a long string is quadratic; count with `${#ht}` and `tr | wc -c`.
- `find <symlink> -mindepth 1` prints nothing and exits 0, so a symlinked `hooks` would read as `hk_entries=0` if the
  `HAS_HOOKS=1` guard were dropped, and a trailing slash on the path makes the kernel follow the link: no trailing slash.
- `-size -4097c` is exactly at most 4096 bytes (`c` units are not rounded).
- Do not add `pre-receive` to the leak-corpus `PATS`: `state/argv` records the `-name` argument by design.
- The two `|| die 33 hooks_*` arms must sit one per line so `mutate_script`'s count-equals-one anchor is unique.
- Measure floors from an unprivileged, loopback-skipped run; a CI-measured count would FATAL the local gate.
- Never write a private chat message into a committed file as an approval; record approvals as inferred and flag them in
  the PR body.
- Run markdownlint on every touched `.md` before committing, including generated spec files.

## Plan Review

**CPO plan-time sign-off, 2026-10-19: APPROVED WITH CONDITIONS** (threshold `single-user incident` agreed; `aggregate
pattern` rejected as too low). Conditions a to g are carried as follows: (a) two readonly probed constants with the
bootstrap-compare suite row - Phase 2 step 1, Phase 1 step 8, AC 4; (b) one-unit group iff `has_hooks_d=1`, both grammars
pinned, values validated before interpolation - AC 3, Phase 1 steps 1 and 2; (c) exit code, `OFFLIST`, `wl_classify`
unchanged with the allowlist mutant RED - AC 2; (d) no name, content, size or open, `die 33` with fixed words, tenant-shaped
fixture - AC 4 to 6, Guard rows 9 and 12; (e) CLO sight of the L6 strings and `user-impact-reviewer` at review time - the
last two ACs; (f) posting uses the closed 12-field list, an absent group is "not measured", conditioned on the merge -
Phase 3 site 1; (g) `Ref` only, nothing dispatched, forbidden-wording grep with the CLO's extended list - the forbidden
wording and PR body ACs and Phase 4 (ACs are positional in this list). Owner-communication guard - the Phase 3 preamble.
Owner-only items named and not decided: allowlisting `hooks`, the next `wipe_check` and its addendum, a fifth field, the
item-1 residual, the 2026-10-24 and 2026-11-12 dates (decision-challenges.md operator rows). Not verified by the CPO: the
script and runbook themselves (they do not yet carry the change).

**Deepen-plan seats, 2026-10-19** (dispositions are rows D1 to D6 of decision-challenges.md): security (quadratic counting
P1, merged `pre-receive` find, `budget` call, constant for the new path, trailing slash: all applied); test design (strict
emit versus posting grammar and the `offlist_n` parse P1, structural file-never-opened detector P1, per-call shim flags
P1, leak-corpus `PATS` P2, `errors_count` reorder row P2, fixture details P2, stronger `line34_is` P2, exact hk counter
P3: all applied); simplicity (cut the `pre-receive`-as-directory world, merge look-alike worlds, drop the redundant
harness row, move the floor case out of the matrix, five runbook sites, de-duplicate Phase 1 against the Guard Contract:
applied). Rejected: none. Not applied: a cap on `hk_entries` (matches the `lf_entries` precedent; noted as accepted
in User-Brand Impact).
