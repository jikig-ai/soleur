---
title: "feat(git-data): name the cause of a wipe-assert rc=34 refusal with fixed-vocabulary fields"
type: feat
date: 2026-10-18
slug: wipe-assert-offlist-diagnostic-fields
branch: feat-one-shot-wipe-assert-offlist-diag
issue: 10138
lane: cross-domain
requires_cpo_signoff: true
---

# feat(git-data): name the cause of a wipe-assert rc=34 refusal with fixed-vocabulary fields

Refs: #10138, #6897 (Ref only; this PR never closes either). Spec lacks `lane:` (no spec.md for this
branch): defaulted to `cross-domain` (fail-closed).

## Overview

The first live `wipe_check` (run 39081408368, 2026-10-18) refused with host exit 34
(`wipe_boot_layout_signal_offlist`). The only evidence is the host stderr line, which prints counts
only: `wipe-assert: rc=34 reason=offlist top_d=3 top_f=0 top_l=0 top_o=0 repos=0`. Nobody can tell
which top-level entry tripped the path-typed allowlist. This change appends three fixed-vocabulary
fields to that one line, so the next run that reaches the listing can discriminate the competing
causes from the run log alone, with no name leaving the host:

```text
wipe-assert: rc=34 reason=offlist top_d=<n> top_f=<n> top_l=<n> top_o=<n> repos=<n> has_hooks_d=<0|1> lf_entries=<n> offlist_n=<n>
```

It is diagnostic only. The allowlist in `wl_classify` is not widened, no gate, predicate, W3/W5/W7
or `select_variant` logic changes, nothing is dispatched, and no sentence in the PR or the runbook
promises or schedules a next `wipe_check`.

## Research Insights

**Premise Validation (Phase 0.6, run 2026-10-18).** Cited by reference: #10138 (open), #6897
(open), run 39081408368 (`gh run view`: workflow "git-data cutover (#5274 / ADR-220 / ADR-239)",
conclusion failure, created 2026-10-18T00:04Z). The log carries, in job `wipe` step "Host-side wipe
assertion (W7)", exactly `[git-data-cutover] probe-stderr: wipe-assert: rc=34 reason=offlist
top_d=3 top_f=0 top_l=0 top_o=0 repos=0` followed by `STORE probe=wipe-assert
verdict=wipe_boot_layout_signal_offlist` (measured by `gh run view 39081408368 --log`, read-only).
Cited paths verified on this tree: `wl_classify` (line ~316), the single `exit 34` site (line ~423,
after `wa_release`), `git-data-cutover.sh` rc 34 arm (line ~978). ADR corpus: ADR-239 carries no
output-vocabulary or posting rule (CLO, row L-3); no ADR rejects this mechanism. Nothing stale.

**Property List.** P1: a reader of the run log can tell whether the system `hooks` directory is
among the off-list entries. P2: a reader can tell whether the refusal came from entries inside
`lost+found` rather than from top-level names. P3: a reader can tell how many top-level entries
failed the allowlist. P4: none of P1-P3 reveals a name. P5: the refusal itself (exit code, verdict
word, allowlist) is byte-for-byte unchanged.

**Cut List.** (a) A per-name hash or a name list: buys P1-P3 but violates P4 (CLO: dictionary
oracle) - cut. (b) `has_repos_d` and a derived "hooks-only" field: buys nothing P1-P3 do not
already (CTO F-1) - cut. (c) Widening the allowlist for `hooks:d`: buys P5-opposite, is a CLO
decision (L-5) - cut, tracked as a follow-up. (d) Reading inside `hooks/` (what it holds): a
second measurement with its own CLO ruling (L-5 iii) - cut. (e) A new parser in the workflow: no
consumer parses the line (sweep below) - cut.

**Why `hooks` is the lead hypothesis (inherited, not confirmed).** `git-data-bootstrap.sh`
(`HOOKS_DIR="$GIT_DATA_ROOT/hooks"`, `mkdir -p "$REPO_ROOT" "$HOOKS_DIR"`, `root:git 0750`, holds
`pre-receive`) creates `hooks` beside `repositories`; `lost+found` comes from mkfs. Three
directories and nothing else is exactly `top_d=3 top_f=0 top_l=0 top_o=0`. The bootstrap's own
`plaintext-count unit` counts only `repositories/` and never models top-level names, so the port
in `wl_classify` added a top-level allowlist that does not list `hooks`. This PR does not decide
that; it makes the next run say.

**Consumer sweep of the rc=34 line (hr-type-widening-cross-consumer-grep applied to an output
line).** Grep over the whole tree (excluding plans/specs/learnings prose) for `rc=34`,
`reason=offlist`, `top_o=`, `probe-stderr`, `wipe_boot_layout_signal_offlist`:

| Consumer | Reads the rc=34 line? | Effect of an appended suffix |
|---|---|---|
| `git-data-cutover.sh` `mode_wipe_assert` | No. `gd_capture` returns the ssh rc; on non-zero it prints stderr via `_access_stderr` (`_access_clean`: printable ASCII, 8192-byte cap, behind `::stop-commands::`) and the rc 34 arm maps to the verdict word | None; line grows from ~80 to ~125 bytes |
| `pat=` success regex (line ~946) | Matches the stdout `wipe_assert pre ok ...` line only, not stderr | None |
| `.github/workflows/git-data-cutover.yml` (step W7 and the notify job) | Reads only `wipe_assert=` from `$GITHUB_OUTPUT` (the success stdout line, `sed -n 's/^wipe_assert=//p'`) and the `STORE probe=... verdict=` word; the stderr line never enters either | None |
| `.github/workflows/scheduled-actions-queue-health.yml` | Its `probe-stderr:` prefix (line ~87) is its own, unrelated to the wipe | None |
| `git-data-wipe-assert.test.sh` | `RE_ERR` (`( [a-z_]+=[0-9]+)*`) admits the suffix; A10 greps a prefix substring; `expect_refuse` is a prefix match; loopback `lb_expect` is a literal substring | Stays green; new strict row added |
| `git-data-wipe-access.test.sh`, `git-data-cutover-access.test.sh` | The access suite pins the generic `probe-stderr:` prefix and span only; neither names the rc=34 line | None; run as focused gates |
| Runbook lines ~1236 and ~1350 | Prose that routes the verdict ("verdict word and counts only") | Edited here |

**Learnings applied.** `grep-q-pipe-guard` (no `| grep -q`; here-strings only);
`cq-test-fixtures-synthesized-only` (the corpus names are synthesized); the suite's own forbidden
phrase row GP (erased, wiped, secure erasure, no copies, holds no personal data) scans the script
and the verb, so every new comment avoids those words; plan-sharp-edges: diff-scope AC lists
pipeline-written files; briefs to domain agents were given the disqualifying facts (the bootstrap
count reads only `repositories/`; an unread `hooks`).

## Research Reconciliation - Spec vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "the likely third dir is `hooks` ... unconfirmed" | Consistent with `git-data-bootstrap.sh` and the count; not provable from the old line | Keep it a hypothesis everywhere (CLO L-4); the new fields decide it on the next run |
| "consumers of the rc=34 line ... the cutover workflow's parser, run-records/summary code" | None parse the stderr line (table above); the run-record/summary code reads the verdict word | Sweep recorded; one verb-tier row proves passthrough |
| "runbook (around line 1236) routes exit 34 to the CLO: verdict word and counts only, never a name" | Line 1236 says "for an off-allowlist result post the word only" (stricter than the brief) | CLO L-2 relaxes it to a closed field list; edit both line ~1236 and the verdict-map cell at line ~1350 |
| (not in brief) runbook "Status (2026-10-14)" at line ~1106 says no `wipe_check` was dispatched | Stale against run 39081408368 | Out of the CTO's file scope for the exit-34 section; not edited; named under Not In Scope |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly (host-side diagnostic on a
  retired volume); indirectly, a misleading field (for example `has_hooks_d=1` for a symlink or a
  look-alike name) would let the owner misread the refusal and push toward widening the allowlist
  on a volume that still holds tenant repositories.
- **If this leaks, the user's data is exposed via:** a tenant-controlled top-level name reaching
  the run log (public, as public as #6897) if a later edit interpolates `$n` or any `find`
  output into the line; the design interpolates only three integers and one constant-derived bit.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the diff reads a tenant volume's top-level listing and
  prints to a public log, so one leaked tenant-shaped name is a single-user exposure; `aggregate
  pattern` is the next tier down. CPO plan-time sign-off 2026-10-18: approved with conditions (a)
  exact name `hooks` and type `d`; (b) `lf_entries` and `offlist_n` come from the existing
  classifier or lost+found count, are digit-validated and appended after `repos=`; (c) exit code,
  `OFFLIST` logic and allowlist unchanged, with a test pinning exit 34 and a strict digits/0-1
  regex; (d) the CLO sees the final strings before merge; (e) the post to #6897 states only the
  closed field list. `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Decision record

All forks and rulings (CTO F-1..F-6, CLO L-1..L-5, operator items) are rows of
`knowledge-base/project/specs/feat-one-shot-wipe-assert-offlist-diag/decision-challenges.md`. No
question was put to the owner. The operator-only items (the next dispatch, its exact command, the
new CLO addendum, the 2026-11-12 date) are named there and nowhere promised.

## Implementation Phases

### Phase 1 - RED first (`cq-write-failing-tests-before`)

Edit `apps/web-platform/infra/git-data-wipe-assert.test.sh` only. Plan-review revisions
(2026-10-18, see decision-challenges.md rows R-1..R-7) are folded in below.

1. **Strict check, whole-line equality.** Add `RE_34='^wipe-assert: rc=34 reason=offlist top_d=[0-9]+
   top_f=[0-9]+ top_l=[0-9]+ top_o=[0-9]+ repos=[0-9]+ has_hooks_d=[01] lf_entries=[0-9]+
   offlist_n=[0-9]+$'` and a `line34_ok <line>` helper that also enforces `offlist_n>0 ||
   lf_entries>0`. Give `expect_refuse` an optional 4th argument: the exact expected tail from
   `top_d=` onward. Inside a branch conditioned on BOTH the expected rc and the actual `$RC` being 34
   (so the H2 self-test, which runs against a clean host with `RC=0`, adds nothing and `executed - 4`
   stays correct) it asserts `line34_ok "$(tail -n 1 "$W/err")"`, increments
   `RC34_LINES_CHECKED` (initialised beside `INVARIANT_RUNS`; the suite runs under `set -u`) and,
   when the 4th argument is present, compares the WHOLE last stderr line for equality (a substring
   match would accept `offlist_n=10` or a trailing `digest=`).
2. **Fold, do not clone.** Pass the exact suffix from the existing rows A06 and A07 (non-empty
   top-level `lost+found`: `lf_entries=1`, `offlist_n=0`), A10 (unknown directory; replaces its
   counts `grep`), and A12 (symlinked `repositories`). Add to the existing A20 (rc 37) row one
   assertion that its last stderr line contains no `has_hooks_d`.
3. **New worlds (five):**
   - A120 incident replay: `repositories`, `lost+found`, `hooks` (dirs) -> rc 34, suffix
     `top_d=3 top_f=0 top_l=0 top_o=0 repos=0 has_hooks_d=1 lf_entries=0 offlist_n=1`.
   - A122 `hooks` dir AND `$CORPUS_TOP_DIR` dir AND `$CORPUS_TOP_FILE` file in the SAME listing ->
     `has_hooks_d=1 offlist_n=3`; the per-run leak invariant shows no corpus name reached any stream
     (CLO condition d: only the bit leaves). Three off-list entries also separate a counter from a flag.
   - A123 one loop over four `hooks` variants, each its own labelled sub-check: a symlink, a regular
     file, a directory `hooks.d`, a directory `Hooks` -> `has_hooks_d=0` and `offlist_n=1` for each
     (exact, case-sensitive match, CLO condition b).
   - A124 non-canonical control: a nested `lost+found/hooks` directory in an otherwise allowlisted
     tree -> `has_hooks_d=0 lf_entries=1 offlist_n=0` (the top-level bit reads 0 although a `hooks`
     exists one level down).
   - A129 off-list directory AND a `lost+found` entry -> `offlist_n=1 lf_entries=1`.
   - A132 a valid `hooks` directory AND a name containing a control character -> rc 35
     `record_control` and NO `has_hooks_d` in the last stderr line (pins that the `hooks` test sits
     after the control-character refusal).
   Cut by plan review (already pinned): the clean-tree must-PASS (A02/A03), rc-37 as its own world
   (folded into A20), the single-entry `lost+found` clones (A06/A07), the two-entry count clone.
4. **Mutant rows** (existing `mutant_row` machinery). Each case function requires rc 34 AND the
   whole expected line for its world, so a crash or a different count cannot read as "caught"; each
   mutant world is the same world as a pristine whole-line row above, which is its control (against
   the unchanged script the new mutant rows read "anchor is not unique" - expected until Phase 2):
   - m-hooks-name-only: drop the type test (world: `hooks` regular file from A123).
   - m-hooks-glob: `[ "$n" = hooks ]` becomes `[[ "$n" == hooks* ]]` (world: `hooks.d` from A123).
   - m-lf-entries-zero: `LF_ENTRIES="$ln"` becomes `LF_ENTRIES=0` (world: A06).
   - m-offlist-n-flag: the increment becomes `OFFLIST_N=1` (world: A122, expects `offlist_n=3`).
   - m-hooks-allowlisted: add `hooks:d) : ;;` to the allowlist `case` (world: A120; the mutant exits 0).
   - m-line-leaks-name: two-edit mutant (`LEAK="$n"` inside the `wl_classify` loop and a
     ` x=$LEAK` suffix on the `say` line) -> the whole-line case and the leak invariant go RED.
   - The existing `m17-lostfound-contents-unread` anchors on `      [ "$ln" -eq 0 ] || OFFLIST=1`;
     that line stays byte-identical.
5. **Harness rows** (`line34_ok` driven directly): ACCEPT a non-canonical good line with
   `lf_entries=7 offlist_n=0`; REJECT `has_hooks_d=2`; REJECT a trailing token; REJECT a line with
   `offlist_n=0 lf_entries=0` (the OR-predicate). A loosened regex or a dropped predicate goes RED.
   Missing or reordered fields are caught by A120's whole-line equality.
6. **Loopback arm H only** (real ext4 image, real device-mapper snapshot): populate `mkdir -p
   repositories hooks && : > hooks/pre-receive`; compare `tail -n 1` of the arm's stderr file to the
   full line `wipe-assert: rc=34 reason=offlist top_d=3 top_f=0 top_l=0 top_o=0 repos=0
   has_hooks_d=1 lf_entries=0 offlist_n=1`; `EXPECTED_ARMS_C` 7 -> 8. Arms B, D and G are left
   unchanged (the shim worlds already pin their cases). Arm H needs root: locally it SKIPs, so
   RED-first for arm H is not locally observable; CI runs it.
7. **Verb-tier row (exactly one), passthrough only.** Extend the `ssh` shim with
   `[ -z "${SHIM_ERR:-}" ] || printf '%s\n' "$SHIM_ERR" >&2` before its final `exit`, passing
   `SHIM_ERR=<the A120 line>` as an extra `run_verb` argument (`run_verb` forwards `"$@"` into the
   env). Exit 5 and the verdict word for rc 34 are already pinned by the existing `RC 34` loop, so
   the new row asserts only `grep -qxF "[git-data-cutover] probe-stderr: <the A120 line>" "$TL/out"`
   (no pipe). Honest scope: it guards the 8192-byte cap and `_access_clean`, not the script.
8. **Floors.** Run the suite UNPRIVILEGED (loopback skipped), the way the local gate runs, and set
   `MIN_ASSERTIONS` and `EXPECTED_INVARIANT_RUNS` from that measured count (at plan time the
   unchanged suite measures 697/699 assertions and 116 invariant runs against floors of 697 and
   114); `EXPECTED_ARMS_C` 8; one line `RC34_LINES_CHECKED` floor beside them, named for its reason:
   deleting the strict check removes its assertions, and in CI the loopback tier lifts `executed`
   so `MIN_ASSERTIONS` alone is loose there.
9. Run the suite against the UNCHANGED script and record the new rows RED (a crash or an
   unbound-variable abort is not RED).

### Phase 2 - the script change (`git-data-wipe-assert.sh`)

1. `wl_classify`: extend the reset line to `... LOCKS_TOP=0 HAS_HOOKS=0 OFFLIST_N=0 LF_ENTRIES=0`
   (the script runs under `set -u`). Before the `case "$n:$t"`, add
   `if [ "$n" = hooks ] && [ "$t" = d ]; then HAS_HOOKS=1; fi`. In the `*)` arm:
   `*) OFFLIST=1; OFFLIST_N=$((OFFLIST_N + 1)) ;;`. No arm is added to the allowlist; `hooks:d`
   still falls into `*)`. None of the three variables is `local` (`wl_classify` runs in the
   current shell; `wipe_listing` reads them after it returns).
2. `wipe_listing`, inside the existing `if [ "$HAS_LF" = yes ]` block AFTER the digit check
   (`[[ "$ln" =~ ^[0-9]+$ ]] || die 33 lostfound_count_unparseable`): `LF_ENTRIES="$ln"` on the
   line before the untouched `[ "$ln" -eq 0 ] || OFFLIST=1`, with a one-line comment that the
   assignment must stay after the validation (a test cannot see a misplacement: `wc -c` always
   yields digits).
3. The verdict line: `say "wipe-assert: rc=34 reason=offlist top_d=$TOP_D top_f=$TOP_F top_l=$TOP_L
   top_o=$TOP_O repos=$REPOS has_hooks_d=$HAS_HOOKS lf_entries=$LF_ENTRIES offlist_n=$OFFLIST_N"`
   (prefix byte-identical; `exit 34` and the placement after `wa_release` and the origin checks
   unchanged).
4. Comments: the unit's `Inputs/Outputs` comment, the header paragraph "NO NAME LEAVES THE HOST"
   (counts, plus one 0/1 bit for one constant system name) and the line above the verdict ("the
   counts on stderr are digits only; has_hooks_d is 0 or 1"). Wording avoids the forbidden list
   (row GP scans this file).
5. Out of the diff by design: the rc table, every `die`, `store_root_repos`, `wl_has_nr`,
   `select_variant`, the success `printf`, `git-data-cutover.sh`.

### Phase 3 - the runbook (`git-data-luks-cutover-5274.md`, exit-34 section only)

Exact text to apply (every sentence labelled measured, policy or inherited, with the date):

- Line ~1236, final clause of "Other results that route to the CLO": replace "Post the verdict
  word and the counts on #6897, never a name; for an off-allowlist result post the word only." with
  the CLO wording (L-2), marked `Policy (CLO ruling, 2026-10-18; takes effect on the merge of the PR
  that adds the fields)`.
- New `### Reading the exit-34 line` subsection directly after that paragraph, before `### Retention
  of the evidence row`: the line grammar; the three definitions (`has_hooks_d`: 1 iff a top-level
  directory named exactly `hooks`, case-sensitive, a file or symlink reads 0; `lf_entries`: entries
  inside the top-level `lost+found`, 0 when it is absent or not a directory; `offlist_n`: top-level
  entries failing the path-typed allowlist, `lost+found` contents not counted) labelled `Inherited
  from the script header and the code, 2026-10-18`; a decode table:

  | Fields | Reading the owner may post |
  |---|---|
  | `has_hooks_d=1 offlist_n=1 lf_entries=0` | the only off-list entry is a directory named `hooks`, the name the bootstrap uses; its owner and contents are unread |
  | `offlist_n=0 lf_entries>=1` | the refusal came from entries inside `lost+found`; the count only |
  | any other combination | post the fields only; no inference about which entries they are (`offlist_n=0 lf_entries=0` cannot occur with rc 34: an instrument fault, route to the CTO) |

  then `Measured 2026-10-18 (run 39081408368, read-only; the line as printed before these fields
  existed)`: the five counts; `Inherited`: the bootstrap creates `hooks` beside `repositories`
  (`git-data-bootstrap.sh`); `Not proven`: that `hooks` is the entry (unconfirmed until a run
  prints `has_hooks_d=1 offlist_n=1 lf_entries=0`, then recorded with that run's URL) and what
  `hooks` holds (unread); `Policy (CLO, 2026-10-18)`: allowlist unchanged, the refusal stands,
  widening needs a CTO ruling plus counts-only evidence, CLO review with a dated addendum and an
  ADR-239 amendment where the allowlist is part of the recorded gate, and each new field its own
  CLO ruling; and the follow-up issue number.
- Verdict-map cell at line ~1350 (`offlist`: "the verdict word and counts only, route to the CLO")
  becomes "the verdict word and the closed field list of 'Reading the exit-34 line', route to the
  CLO".
- No edit to the "Status (2026-10-14)" paragraph, the wedge, or any other section.

### Phase 4 - hand-offs that do not mutate production

1. File the allowlist follow-up (`hooks:d` legitimate or not, constrained to a root-owned
   directory holding only `pre-receive`) with `gh issue create` (label from the repo's set,
   milestone from `knowledge-base/product/roadmap.md`), body "Ref #10138, Ref #6897"; cite its
   number in the runbook subsection (`wg-when-deferring-a-capability`).
2. Before merge, route the actual new strings (the `say` line, the runbook subsection, the PR
   body) to `soleur:legal:clo` for sight, as L-3 requires; record the verdict in
   `decision-challenges.md`.
3. PR body: `Ref #10138`, `Ref #6897`; states the PR changes the stderr output of the rc=34
   refusal only; no gate, allowlist, predicate, mode or workflow input changes; no run
   dispatched. It contains none of the words listed in row L-4. No `## Changelog` semver bump
   beyond the repo's CI label flow (`wg-never-bump-version-files-in-feature`).

### Phase 5 - local gate (focused suites only; CI's required test context is the gate)

```bash
bash apps/web-platform/infra/git-data-wipe-assert.test.sh
bash apps/web-platform/infra/git-data-wipe-access.test.sh
bash apps/web-platform/infra/git-data-cutover-access.test.sh
bash .claude/hooks/grep-q-pipe-guard.test.sh
```

No `test-all.sh --affected`. The loopback tier (arm H) needs root/sudo; locally it SKIPs loudly
(`SKIP(LOOPBACK_UNAVAILABLE)`), and CI runs it with `WIPE_ASSERT_REQUIRE_LOOPBACK=1` (job in
`infra-validation.yml`), so arm H is exercised by CI, not by the local run - state that in the PR
body rather than claiming it ran. Bound each run's output (`hr-never-run-commands-with-unbounded-output`).

## Files to Edit

- `apps/web-platform/infra/git-data-wipe-assert.sh` (classifier variables, `hooks` bit, two
  assignments, one `say` line, comments)
- `apps/web-platform/infra/git-data-wipe-assert.test.sh` (rows, mutants, harness rows, arm H,
  one verb row, ssh-shim stderr passthrough, floors)
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` (exit-34 clause
  at ~1236, new subsection, verdict-map cell at ~1350)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-wipe-assert-offlist-diag/decision-challenges.md`
  (written during planning)
- `knowledge-base/project/specs/feat-one-shot-wipe-assert-offlist-diag/tasks.md`

Glob/path verification (`hr-when-a-plan-specifies-relative-paths-e-g`): every path above was
confirmed with `ls`/`git ls-files` on this worktree; the suite is registered by presence under
`apps/web-platform/infra/` (the suite header; `run-registered-suites.sh` derives it), nothing to
register.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (200 limit) bodies were searched with
`jq --arg path` for each of the three edited files and `git-data-cutover.sh`: no match.

## Architecture Decision (ADR/C4)

Skipped: no architectural decision is made. The allowlist (the recorded gate) is unchanged; the
change adds output fields inside the ruled envelope ("ids, counts and fixed verdict words only").
Test applied: a competent engineer reading ADR-239 plus the C4 model is not misled about the system
after this ships. C4 not touched: no actor, system, container, data store or access relationship
changes (output text of an existing host-to-runner edge only). CTO and CLO both ruled no ADR
amendment is needed (F-series, L-3).

## Encryption Posture

Skipped (Phase 2.11): no persistent store and no new cross-component connection. The existing
read-only listing of the retired plaintext volume is unchanged.

## Infrastructure (IaC)

Skipped (Phase 2.8): no new infrastructure, no provisioning, no apply. The host script is already
delivered by the existing verb over the single ssh site; nothing here installs, enables or
configures anything on a host.

## Observability

```yaml
liveness_signal:
  what: the line "[git-data-cutover] probe-stderr: wipe-assert: rc=34 reason=offlist ... has_hooks_d=<0|1> lf_entries=<n> offlist_n=<n>" in the job log of the git-data cutover workflow (job wipe, step "Host-side wipe assertion (W7)"), beside the existing verdict annotation wipe_boot_layout_signal_offlist
  cadence: per dispatched wipe_check or wipe run (on demand, named by the owner; nothing is scheduled by this change)
  alert_target: the existing notify job of the cutover workflow (email and the ci/git-data-cutover issue), unchanged by this change
  configured_in: .github/workflows/git-data-cutover.yml (unchanged) and apps/web-platform/infra/git-data-cutover.sh _access_stderr (unchanged)
error_reporting:
  destination: GitHub Actions run log plus the verdict annotation; this is a one-shot host script on a retired volume, not a Sentry-instrumented server, so there is no Sentry project or DSN
  fail_loud: exit 34 maps to verdict wipe_boot_layout_signal_offlist and the run fails; the new fields only add detail to the stderr line
failure_modes:
  - mode: a field is missing, non-numeric, out of 0/1 or reordered in the rc=34 line, or truncated on its way to the log
    detection: the strict whole-line check in git-data-wipe-assert.test.sh on every rc-34 row, the loopback arm H equality and the verb-tier passthrough row (layer 6, workflow-run log)
    alert_route: CI red on the required test context (infra-validation)
  - mode: a listing name reaches stdout, stderr or any state file
    detection: the per-run leak invariant over the synthesized corpus on every run, including A122 (hooks plus tenant-shaped names in one listing), and the loopback corpus check (layer 6)
    alert_route: CI red on the required test context
  - mode: the fields misdiagnose (for example has_hooks_d=1 for a symlink)
    detection: the A123 variants, A124 and the m-hooks-name-only and m-hooks-glob mutants (layer 6)
    alert_route: CI red on the required test context
logs:
  where: GitHub Actions run log of the cutover workflow (gh run view <run> --log)
  retention: GitHub Actions log retention as configured for the repository; the setting was not read in this plan
discoverability_test:
  command: grep -c has_hooks_d=.HAS_HOOKS apps/web-platform/infra/git-data-wipe-assert.sh
  expected_output: 1
```

Honest limit: the discoverability command proves the field is wired into the script (one line),
not that a live run printed it; the live signal exists only after the owner names a run, which this
change neither dispatches nor promises. The behavioural proof is the suite (shim, loopback and verb
tiers) in CI.

## Guard Contract

### Guard 1 - rc=34 line grammar and no-name invariant

**Property.** Every rc=34 line the host script can print carries exactly the closed field list
(five existing counts, then `has_hooks_d` as 0 or 1, `lf_entries`, `offlist_n` as digits), and no
listing name reaches any output stream.

**Assembly.** The chokepoint is the single `say` in `wipe_listing` ahead of the one `exit 34` (a
grep of the script finds `exit 34` once, at the verdict site); the suite quantifies over it from
three places: the shim tier (`expect_refuse` strict whole-line check on every rc-34 row, plus the
per-run `invariants` leak check over the whole corpus), the loopback tier (arm H equality and the
corpus leak check) and the verb tier (passthrough row). A second rc-34 emission site would not pass
through the strict check unless added to the same chokepoint; the parity rows (rc table equals
`die` calls equals verb arms) and the `RC34_LINES_CHECKED` floor make a second site visible.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `m-line-leaks-name`: a listing name is carried into the rc-34 line | RED (whole-line case and leak invariant) |
| 2 | Dispatch of the guard itself: the strict check is deleted or never reached (not a script mutation; the suite cannot mutate its own check) | RED via the `RC34_LINES_CHECKED` floor and `MIN_ASSERTIONS` |
| 3 | `m-offlist-n-flag`: a flag where a counter is needed, in a listing with three off-list entries (a SECOND and third member after a compliant first) | RED (`offlist_n=3` expected, A122) |
| 4 | `m-hooks-allowlisted`: `hooks:d` added to the allowlist arm | RED (A120 expects rc 34; the mutant exits 0) |
| 5 | `m-hooks-name-only` and `m-hooks-glob`: type test dropped, or a prefix glob | RED (A123 variants) |
| 6 | `m-lf-entries-zero`: `lf_entries` hard-coded 0 | RED (A06) |

**Harness rows.** `line34_ok` is driven directly: it must REJECT `has_hooks_d=2`, a trailing token
and `offlist_n=0 lf_entries=0`, and must ACCEPT a non-canonical good line (`lf_entries=7
offlist_n=0`), so a regex loosened to `.*`, a dropped predicate, or a guard that rejects everything
goes RED. **Anchor.** No stored hash or count floor compares against the guarded thing; the strict
regex is a literal in the suite, and the external anchor for a weakening is that the CLO sees the
new strings before merge (L-3) and the line prefix stays pinned by whole-line equality.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "adding fixed-vocabulary fields to the rc=34 line, such as has_hooks_d (0/1), lf_entries=<n> (entries inside lost+found) and offlist_n (count of off-list names)" [brief] | Phase 2 steps 1-3 | mapped |
| 2 | "change ONLY apps/web-platform/infra/git-data-wipe-assert.sh, its test (apps/web-platform/infra/git-data-wipe-assert.test.sh) and the runbook" [brief] | Files to Edit (3 files) | mapped |
| 3 | "The fields must leak no arbitrary names (counts and fixed booleans only)." [brief] | Guard 1, A122, leak invariant, CLO L-1 conditions | mapped |
| 4 | "The allowlist in wl_classify must NOT be widened" [brief] | Phase 2 step 1 (no arm added), mutant m-hooks-allowlisted | mapped |
| 5 | "No other gate, predicate, W3/W5/W7 or select_variant logic may change." [brief] | Phase 2 step 5 | mapped |
| 6 | "no workflow dispatch, terraform apply, Doppler write, or volume operation; ... the PR must not dispatch or promise it" [brief] | Overview, Phase 4 step 3, decision row "Next wipe_check dispatch" | mapped |
| 7 | "run only focused suites (git-data-wipe-assert.test.sh, git-data-wipe-access.test.sh, git-data-cutover-access.test.sh, .claude/hooks/grep-q-pipe-guard.test.sh)" [brief] | Phase 5 | mapped |
| 8 | "consumers of the rc=34 probe line ... must be swept and kept green" [brief] | Consumer sweep table, verb-tier row | mapped |
| 9 | "Any runbook sentence must say whether it is measured, policy or inherited and carry the date." [brief] | Phase 3 | mapped |
| 10 | "PR bodies use Ref #N, never Closes." [brief] | Phase 4 step 3, AC | mapped |
| 11 | "Persist every decision as a row of the `| Item | Class | Ruling |` table" [brief] | decision-challenges.md | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 2 classifier + `say` edit | "adding fixed-vocabulary fields to the rc=34 line" | asked |
| Phase 1 shim rows, mutants, harness rows | "the PR ... must be swept and kept green" (asks 3, 8) | asked |
| Loopback arm H (only; arms B, D, G unchanged) | - | inferred - justification: CTO ruling F-5 (2026-10-18) requires one real-ext4 reproduction of the incident layout; shims cannot reproduce a real directory tree |
| Verb-tier row + ssh-shim stderr passthrough | "consumers of the rc=34 probe line ... must be swept and kept green" | asked |
| Raised floors + `RC34_LINES_CHECKED` | - | inferred - justification: without them the new rows can be deleted without the suite noticing (the suite's own anti-vacuity convention) |
| Runbook subsection + cell edit | "the runbook (...) exit-34 section" | asked |
| Allowlist follow-up issue | - | inferred - justification: CTO F-series requires tracking the deferred `hooks:d` allowlist question (`wg-when-deferring-a-capability`) |
| CLO sight of the strings before merge | - | inferred - justification: CLO L-3 condition |

### Split Assessment

- Subsystems touched: 2 - `apps/web-platform/infra/`, `knowledge-base/engineering/operations/runbooks/`
- Planned files: 3 edited (+2 spec files) | Estimated changed lines: about 330 (script about 12, test about 250, runbook about 60)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** Engineering, Legal

### Engineering

**Status:** reviewed
**Assessment:** Ruled by CTO agent, 2026-10-18 (rows F-1 to F-6): field set and order, `hooks` as a directory-only separate statement, `offlist_n` semantics, rc=34 line only, test scope capped at the core rows, mutants, one loopback arm and one verb row; `hooks` is the right lead candidate but unconfirmed; no ADR.

### Legal

**Status:** reviewed
**Assessment:** Ruled by CLO agent, 2026-10-18 (rows L-1 to L-5): `has_hooks_d` accepted as a fixed field under four conditions; the runbook may post the closed field list; neither an ADR-239 amendment nor an addendum is needed for this PR; the forbidden-wording list and the no-promise rules bind the runbook, comments, summaries and PR body; widening would be a CLO-reviewed change. GDPR gate (Phase 2.7): the brand-survival trigger fires; the CLO ruling above is the compliance review, no schema/auth/API surface, no new processing activity (PA-36 unchanged), no `compliance-posture.md` change.

### Product/UX Gate

**Tier:** none (no user-facing surface; no new component, page or flow). CPO plan-time sign-off for the `single-user incident` threshold: approved with conditions (see User-Brand Impact), carried as acceptance criteria below.

## Acceptance Criteria

<!-- founder-stated check: the owner stated that nothing is dispatched and no next wipe_check is promised -->

### Pre-merge (PR)

- [ ] The rc=34 line prints the three fields appended after `repos=`, prefix byte-identical:
  `grep -cE 'say "wipe-assert: rc=34 reason=offlist top_d=\$TOP_D top_f=\$TOP_F top_l=\$TOP_L top_o=\$TOP_O repos=\$REPOS has_hooks_d=\$HAS_HOOKS lf_entries=\$LF_ENTRIES offlist_n=\$OFFLIST_N"' apps/web-platform/infra/git-data-wipe-assert.sh` prints `1`, and `grep -c 'exit 34' apps/web-platform/infra/git-data-wipe-assert.sh` still counts the single exit (comments excepted: assert with the exit-site anchor `      exit 34` returning `1`).
- [ ] The allowlist is not widened: `git diff origin/main -- apps/web-platform/infra/git-data-wipe-assert.sh` shows no added line of the shape `<name>:<type>)` inside `wl_classify` (`grep -cE '^\+\s+[a-z.*+_-]+:[dfl]( \| [a-z.*+_-]+:[dfl])*\)'` on that diff prints `0`; the only `case` change is the `*)` arm body), and the mutant m-hooks-allowlisted is RED in the suite output.
- [ ] `git diff origin/main --stat` lists only: the script, the test, the runbook, this plan, `specs/feat-one-shot-wipe-assert-offlist-diag/{tasks.md,decision-challenges.md,session-state.md}` and the generated `knowledge-base/INDEX.md` if the pipeline rewrites it - no workflow, no `git-data-cutover.sh`, no `.tf`.
- [ ] `bash apps/web-platform/infra/git-data-wipe-assert.test.sh` exits 0 with 0 failures and the new rows (A120-A132 as revised, six mutants, harness rows, verb row) listed `ok`; Phase 1 recorded those rows RED against the unchanged script first.
- [ ] `git-data-wipe-access.test.sh`, `git-data-cutover-access.test.sh` and `.claude/hooks/grep-q-pipe-guard.test.sh` exit 0.
- [ ] CI's required test context is green, including the loopback step (arm H ran: `LOOPBACK_UNAVAILABLE` absent from that job's log).
- [ ] No `| grep -q` in the diff: `git diff origin/main -- apps/web-platform/infra/git-data-wipe-assert.sh apps/web-platform/infra/git-data-wipe-assert.test.sh knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md | grep -cE '^\+.*\| *grep -q'` prints `0` (and the pipe-guard suite is green).
- [ ] Forbidden wording absent from every ADDED line of the three edited files (the plan and decision-challenges.md quote the list and are excluded): `git diff origin/main -- apps/web-platform/infra/git-data-wipe-assert.sh apps/web-platform/infra/git-data-wipe-assert.test.sh knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md | grep -ciE '^\+.*\b(erased|wiped|secure erasure|no copies|holds no personal data|benign|harmless|false positive|waivable|will pass|is unblocked)\b'` prints `0`.
- [ ] The runbook carries the CLO wording verbatim (L-2), the decode table, and the measured/inherited/policy labels with `2026-10-18`; every added runbook sentence about the fields is conditioned on the merge ("takes effect on the merge of the PR that adds the fields"), none in past tense about a run having printed them.
- [ ] The PR body uses `Ref #10138` and `Ref #6897` and never `Closes`/`Fixes`/`Resolves`; it says the PR changes the stderr output of the rc=34 refusal only and dispatched nothing.
- [ ] The allowlist follow-up issue exists and its number appears in the runbook subsection.
- [ ] The CLO has seen the final strings (script line, runbook subsection, PR body) and the verdict is recorded in `decision-challenges.md`.
- [ ] `soleur:engineering:review:user-impact-reviewer` ran at review time (threshold `single-user incident`).

### Post-merge (operator)

None. This change dispatches nothing; any later `wipe_check` is a separate owner-named command after a new CLO addendum, outside this PR's acceptance.

## Test Scenarios

Layers: all `integration` (shell suite over a simulated host, a real loop device, and the verb with
an ssh shim); no `e2e`.

- Given the production layout (`repositories`, `hooks`, `lost+found`), when `pre` runs with the
  listing, then rc 34 and `has_hooks_d=1 lf_entries=0 offlist_n=1` (A120, arm H).
- Given an unknown directory (A10), a symlinked `repositories` (A12) or a non-empty `lost+found`
  (A06/A07), then the whole last stderr line equals the expected suffix (fold-in of the existing rows).
- Given `hooks`, an unknown directory and an unknown file together, then `offlist_n=3` and only the
  bit about `hooks` leaves (A122).
- Given `hooks` as a symlink, a file, `hooks.d` or `Hooks`, then `has_hooks_d=0` (A123); given a
  nested `lost+found/hooks`, then `has_hooks_d=0 lf_entries=1 offlist_n=0` (A124).
- Given an off-list directory and a `lost+found` entry, then `offlist_n=1 lf_entries=1` (A129).
- Given a valid `hooks` and a control-character name, then rc 35 with no `has_hooks_d` field (A132);
  given `repositories/` entries, then rc 37 with no new field (folded into A20).
- Given the ssh shim emitting the A120 line with rc 34 (via `SHIM_ERR`), then the line is passed
  through verbatim behind the `probe-stderr:` prefix (verb row; exit 5 and the verdict word are
  already pinned by the existing RC loop).
- Regression: the existing A10/A14/A15/A16/A17 refusals, m17 and the parity rows stay green
  unchanged.

## Dependencies & Risks

- **The fields could be misread as a verdict on `hooks`.** Mitigation: the runbook decode table and
  the CLO wording; nothing says benign, expected or safe; the refusal stands.
- **A future edit interpolates a name into the line.** Mitigation: Guard 1 and the leak invariant;
  `has_hooks_d` is the result of one constant comparison.
- **Loopback arm H cannot run locally without root.** Mitigation: CI runs it with
  `WIPE_ASSERT_REQUIRE_LOOPBACK=1`; the PR body says so honestly instead of claiming a local run.
- **A snapshot is left behind by a run.** Out of scope: unchanged; the rc=34 path is after
  `wa_release` and the origin checks.
- **Runbook "Status (2026-10-14)" is stale against run 39081408368.** Noted, not edited (outside
  the CTO's file scope for this section).

## Not In Scope

Widening `wl_classify`; reading inside `hooks/`; any workflow, `git-data-cutover.sh`, `.tf` or
Doppler change; any dispatch or schedule of a next `wipe_check`; the 2026-11-12 outer date and the
ledger row; updating the runbook's stale status paragraph.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. Filled here: `single-user
  incident`.
- `m17-lostfound-contents-unread` anchors on the exact text `      [ "$ln" -eq 0 ] || OFFLIST=1`.
  Do not reformat that line; put `LF_ENTRIES="$ln"` on the line before it.
- `expect_refuse` is also the engine of the H2 self-test (`executed - 4`). Condition the new strict
  check on the ACTUAL rc being 34 so a probe against a clean host adds no assertion.
- The script header and the suite header forbid the words in row GP; comments written for this
  change are scanned by `grep -inE` over the script.
- The floors in the suite are literals directly above their `if`; set them from the measured
  counts after the suite is green, not from a guess.
- The suite pins the recorded argv of every selector-bearing call as one exact multiset per phase
  (`EXP_PRE`, `EXP_SKIP`, `EXP_POST`, `contract_eq`). The change must add NO external command
  (no second `find`, no `test -d`): `hooks` is classified from the record the existing listing
  `find` already prints, and `lost+found` reuses the existing count call. A new call turns every
  contract row RED and is the wrong fix.
