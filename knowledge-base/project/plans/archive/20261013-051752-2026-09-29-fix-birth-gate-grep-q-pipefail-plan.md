---
title: "fix(git-data): birth-readiness-gate — replace pipe-fed `grep -q` predicates with the herestring idiom (S1 flake)"
type: fix
date: 2026-09-29
slug: fix-birth-gate-grep-q-pipefail
branch: feat-one-shot-9210-birth-readiness-gate
issue: 9210
closes: 9210
priority: high
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: cross-domain
---

# fix(git-data): birth-readiness-gate — pipe-fed `grep -q` under pipefail flaked S1 red

Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-09-29
**Sections enhanced:** Observability (added — Phase 4.7 halt fires on any
non-docs diff), Research Insights (deepen-round gate ledger appended),
Files to Edit (W-family `_expect_rows` question resolved), Acceptance Criteria
(absence-grep kept count-oriented per the head-truncation sharp edge).
**Research agents used:** none spawnable — this harness exposes no
Task/Skill spawn tool; every conditional gate, the verify-the-negative sweep,
and the precedent-diff were run inline with shell evidence cited. No
independent review is claimed.

### Key Improvements

1. `## Observability` added — the gate's own suite ledger IS the observable
   surface; the `discoverability_test` probe is Check-10-clean (allowlisted
   `grep` verb, no shell-active bytes, sub-second).
2. Per-gate verdicts recorded as an auditable trail (see Research Insights →
   Deepen-plan round).
3. Precedent-diff resolved positively: the herestring idiom is this file's own
   documented convention (~line 2260 comment plus five live sites) and four
   sibling scripts — not novel.

### New Considerations Discovered

- The W2 row's label must carry the literal `pipe-fed` so the Check-10-safe
  probe (`grep -l pipe-fed …`) keeps working — pinned in tasks.md 3.1.
- Phase 4.5's keyword trigger matches the `.ssh` path text in the
  authorized_keys sweep; a false-positive in this context — recorded, no
  deep-dive spawned.

## Overview

`tests/scripts/test-git-data-birth-readiness-gate.sh` row S1 (`CLEAN => RELEASED`)
flaked once on main CI — run 36550702286, `test-scripts (6/7)`, attempt 1,
2026-09-29 09:43:45Z. The captured output shows
`tests/scripts/lib/git-data-birth-readiness-gate.sh: line 511: printf: write
error: Broken pipe` followed by the fail-closed ABORT claiming the fixture's
`modules/git-data-userdata/main.tf` `templatefile(` argument "is not a
single-line `${path.module}/…` literal". That claim is false: the fixture emits
exactly that literal (`_r2_write_module`, test file ~line 434), the same gate
call chain had already succeeded on the same bytes seconds earlier in the same
process (the rehearsal gate's own message says the evidence is "hash-valid" —
the `user_data_sha256` → `bound_files` call passed), the shard's attempt 2 went
green on identical code, and the whole suite passes locally 252/252.

The real defect is the predicate's construction, not the module's shape:
`if ! printf '%s\n' "$_shape_src" | grep -qE '…'; then` runs a producer→`grep -q`
pipeline under the suite's `set -o pipefail`. When the consumer exits before the
producer finishes — `grep -q` closes the pipe on first match (a false negative
above the ~64 KiB pipe buffer, reproduced deterministically), or dies early for
any environmental reason — the producer takes EPIPE/SIGPIPE, `pipefail`
promotes the transport failure to a non-zero pipeline, and `if !` reports a
*shape violation that never existed*. The file itself documents this exact
class at `git_data_rung2_bound_files`'s sibling site ("A HERESTRING, NOT A PIPE"
— lib ~line 2260) and ADR-119 records the same measurement; the surviving
pipe-fed sites were never converted.

This plan converts the four remaining `producer | grep -q*` predicates in
`tests/scripts/lib/git-data-birth-readiness-gate.sh` to the established
herestring/capture idiom, splits "instrument failure" (rc ≥ 2) from "no match"
(rc = 1) at the two verdict-bearing sites, and adds a W-family regression pin
(plus a control row proving the pin fires) so the banned idiom cannot drift
back.

## Problem Statement / Motivation

`wg-when-tests-fail-and-are-confirmed-pre` mandates fixing confirmed
non-pre-existing failures on main. More load-bearing than the one red row: a
fail-closed gate whose transport can lie about *which* check failed sends every
future incident investigation down the wrong trail — this one was filed as a
"fixture templatefile shape" bug when the fixture was never malformed. The same
class survives at three sibling sites in the file, one of which (the
`/home/git/.ssh/authorized_keys` outside-`write_files` sweep at ~line 2056)
fails **open** — a mid-pipe producer death skips a HOLD entirely.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality | Plan response |
|---|---|---|
| "the synthesized fixture's `main.tf` [has a] multi-line templatefile call" | The fixture emits a single-line `templatefile("${path.module}/../../ci.yml", {` (test ~line 434); the ABORT text is the gate's own hypothesis, printed on the `!` arm of a pipefed predicate | Do not touch the fixture; fix the predicate |
| "a sibling merge between 09:25 and 09:49 changed the fixture generator or the gate's bound-file derivation" | `git log 4b47b16748..4992f929e6` contains exactly ONE commit — the triggering merge #9183 itself, touching only `apps/web-platform` LinkedIn cron code + KB docs. `09c7cc31cd` (merged 09-25, already in the green run's tree) added only a `.soleur-owned` marker write inside `_git_data_rung2_hash_at_sha`; `a5b2e36b56` (#8711) merged 09-24, also pre-green | Exonerate both suspects; the delta was zero — the failure is nondeterministic |
| "either the fixture's main.tf needs a single-line literal, or the gate's parser needs to accept the multi-line shape" | Neither — the flake is a transport-level false negative in `producer \| grep -q` under `pipefail`; the observed `printf: write error: Broken pipe` at lib line 511 is the proximal evidence | Convert to the file's own documented herestring idiom; split instrument-failure rc from no-match rc |

## Proposed Solution

In `tests/scripts/lib/git-data-birth-readiness-gate.sh`, eliminate every
pipe-fed `grep -q*` predicate. The file's convention is a herestring
(`grep -qE '…' <<<"$var"` — see the measured rationale in its own comment at
~line 2260, and the same idiom at ~lines 1246, 1575, 2086, 2286, 2295); where a
middle stage exists, capture it first (`x="$(tr … <<<"$var")"`, then
herestring-grep). Sites:

1. **`git_data_rung2_bound_files` strict `templatefile` literal check
   (~line 511)** — the observed flake. `printf '%s\n' "$_shape_src" | grep -qE
   'templatefile\("\$\{path\.module\}/[^"]+"'` → herestring, AND split the
   verdict: `rc ≥ 2` (grep died/could not evaluate) ABORTs with a
   could-not-evaluate message distinct from the `rc == 1` shape-violation
   ABORT, because this incident's entire cost was a transport failure wearing a
   shape-violation's message.
2. **Anonymous-retry rate-limit check (~line 1135)** — `printf '%s' "$_resp" |
   sed '$d' | grep -qiE 'rate limit'`. A `grep -q` early exit EPIPEs `sed`,
   `pipefail` flips the `!`, and the gate drops the bearer mid-rate-limit —
   the branch the comment says makes things "strictly worse". Restructure:
   `_body="$(sed '$d' <<<"$_resp")"` then `! grep -qiE 'rate limit'
   <<<"$_body"`.
3. **`authorized_keys` outside-`write_files` sweep (~lines 2056–2057)** —
   `grep -nE … "$cloud_init" | grep -vE … | grep -qvE …` in a non-negated `if`:
   an early consumer exit (or producer death) skips the HOLD — **fail-open on
   the property that a runcmd/bootcmd may not silently rewrite the auth map**.
   Restructure: capture the filtered hits into a variable, `rc ≥ 2` → ABORT
   (instrument failure, honest cause), non-empty → HOLD. Capturing also lets
   the HOLD name the offending `line:content` like the sibling ABORTs do.
4. **`ignore_changes on user_data` check (~line 2311)** — `tr '\n' ' '
   <<<"$_server_block" | grep -qE '…'`. Capture the flattened block, then
   herestring-grep.

Then a regression pin in `tests/scripts/test-git-data-birth-readiness-gate.sh`
(W-family, beside W1 at ~line 2812): the suite asserts zero pipe-fed `grep -q*`
call sites survive in `tests/scripts/lib/*.sh`, and a control row proves the
detector fires on a seeded copy. Floor comment bumps 252 → 254.

## Technical Considerations

- **Why pipefed `grep -q` is unsound under pipefail (measured, not
  conjectured):** `grep -q` exits 0 on first match without draining stdin; when
  the producer still has ≥1 byte pending (input > ~64 KiB pipe capacity —
  reproduced 40/40 at ≥150 KiB, 7/40 at 70 KiB), it takes SIGPIPE/EPIPE and the
  pipeline goes non-zero *although the pattern matched*. For small inputs the
  same inversion fires when the consumer dies before reading (signal, exec
  failure) — the producer's first write hits a closed pipe. Either way
  `pipefail` propagates the non-zero and `if !`/`if` reads transport as
  verdict. A herestring is backed by a shell-owned temp file — there is no
  producer to lose.
- **Directional asymmetry matters.** In `if ! prod | grep -q …` the flake
  produces a false ABORT/HOLD (fail-closed but wrong-cause — this incident). In
  `if prod | grep -q …` (sites 3 and 4) it produces a *missed* detection —
  fail-open. Both directions are the defect.
- **`grep -q` on a FILE is safe** (no producer) — sites like `grep -q '#' "$f"`
  are out of scope. The sweep must match only pipe-fed forms and must skip
  comment lines, because the lib's own prose documents the banned shape in a
  comment (~line 2260); the suite's existing comment-strip idiom
  (`sed 's/^[[:space:]]*#.*$//'`, or `grep -vE ':[[:space:]]*#'` on `grep -n`
  output) covers it.
- **Explicitly not in this fix:** loosening the canonical-shape assertion to
  accept multi-line `templatefile(`. That narrowing is deliberate (#7534 —
  indirection is statically unresolvable, so the digest could attest bytes that
  never boot). The flake was transport, not grammar.
- **NFR register:** no user-facing surface; reliability/CI-determinism only.
  `knowledge-base/engineering/architecture/nfr-register.md` — no entry
  affected.

## Files to Edit

- `tests/scripts/lib/git-data-birth-readiness-gate.sh` — convert the four
  pipe-fed `grep -q*` sites (~lines 511, 1135, 2056–2057, 2311) to the
  herestring/capture idiom; at sites 1 and 3 split `rc ≥ 2` (instrument
  failure, could-not-evaluate wording) from rc = 1 / non-empty (the measured
  verdict).
- `tests/scripts/test-git-data-birth-readiness-gate.sh` — add the W2 pin +
  W2-control rows; bump `_FLOOR` (252 → 254) and the floor comment ledger;
  the W family carries no `_expect_rows` pin today (verified — only S/P/R/A/H/F
  are pinned), so no family pin needs bumping.

## Files to Create

- None (the deferred repo-wide sweep below is a follow-up issue, not this PR).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — the
  blast radius is CI: the `test-scripts (6/7)` shard stays intermittently red
  on main and every PR's required `test` context flips red until a retry lands
  green. If the herestring conversion is done wrong, the gate could HOLD/ABORT
  on the live `cloud-init-git-data.yml` at birth-dispatch time — a blocked
  git-data host create, not a user-visible outage.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  exposure vector — the change restructures a predicate's stdin plumbing in a
  test gate; no secret, credential, or user data path is touched.
- **Brand-survival threshold:** `none`

## Observability

The deliverable IS a gate — its observable surface is the suite ledger and the
CI check status it feeds. No new infrastructure; the fields below describe how
a regression in this change is noticed.

```yaml
liveness_signal:
  what: "Required `test` check conclusion + `test-scripts (6/7)` shard on CI runs"
  cadence: "per-run (every push/PR CI execution)"
  alert_target: "GitHub commit status; a red shard is auto-filed as a CI-failure issue (the #9210 path)"
  configured_in: ".github/workflows/ci.yml (test-scripts matrix job, ~line 1027)"

error_reporting:
  destination: "GitHub Actions job log — the suite prints `=== N passed, M failed ===` and per-row `FAIL <label>`; the gate prints `ABORT — …`"
  fail_loud: "any FAIL row or non-zero suite exit reds the shard and the PR's required `test` context"

failure_modes:
  - mode: "a pipe-fed `grep -q` reintroduced under tests/scripts/lib/"
    detection: "W2 sweep row fails naming the offending file:line"
    alert_route: "required `test` context red → merge blocked"
  - mode: "instrument failure misreported as a shape violation (the #9210 class)"
    detection: "the rc≥2 arm emits a could-not-evaluate ABORT distinct from the shape-violation text"
    alert_route: "shard reds with an honest-cause message on the first failure"

logs:
  where: "GitHub Actions job log for `test-scripts (6/7)`"
  retention: "repo Actions log retention (GitHub default 90 days)"

discoverability_test:
  command: grep -l pipe-fed tests/scripts/test-git-data-birth-readiness-gate.sh
  expected_output: test-git-data-birth-readiness-gate.sh
```

The probe is deliberately label-keyed, not count-keyed: `grep -l` prints the
filename whenever the W2 row exists, so it survives row-renumbering and
comment drift. The W2 row's label MUST therefore contain the literal
`pipe-fed` (tasks.md 3.1 pins this).

## Guard Contract

### Guard 1 — the no-pipe-fed-`grep -q` pin (W2)

**Property.** No predicate in `tests/scripts/lib/*.sh` reads its verdict from a
`producer | grep -q*` pipeline, because under `pipefail` the pipeline's status
conflates "pattern absent" with "transport broke" (producer EPIPE after
`grep -q`'s early exit, or early consumer death).

**Assembly.** Every line of every `*.sh` file under `tests/scripts/lib/` — the
chokepoint is the directory listing itself (`"$ROOT"/tests/scripts/lib/*.sh`
glob, not an enumerated file list, so a new sibling lib is covered by
construction), filtered to non-comment lines (full-line `#` comments stripped —
the lib's own comments legitimately document the banned shape). A pinned count
or an enumerated file list would rot; the property is over the directory.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Append `printf 'x' \| grep -q y` to a copy of the gate lib and run the W2 extraction over it | Detector output non-empty (W2 reds if applied to the real lib) |
| 2 | Seed `cmd \| grep -qvE 'x'` — a DIFFERENT flag cluster — into the copy | Still flagged (the pin isn't anchored on `-qE`) |
| 3 | Seed a SECOND banned line after a compliant file (dir order: a clean lib first, the dirty one second) | Still flagged — the sweep must not stop at the first clean member |
| 4 (harness) | Neuter W2's own detector pattern in a suite copy (e.g. match `__NEVER__`) and seed nothing | Suite stays green BUT this is detected as vacuous by the control row: the control injects the banned shape into a fixture and asserts non-empty output — a detector that can't fire fails the control row |
| 5 (must-pass, non-canonical) | A lib line `grep -qE 'pat' "$file"` (file operand, no pipe) and `grep -q <<<"$x"` present | Detector stays clean — the pin must not flag the sanctioned forms it exists to protect |

Precondition-satisfied-but-property-fails row: row 5 — the file contains
`grep -q` (precondition: the class is exercised) yet the property holds (no
pipe-fed form). Detector-side ordering note: the sweep runs over a glob, so a
mutation renaming `git-data-birth-readiness-gate.sh` does not silently exempt
it — the glob enumerates whatever ships.

## Acceptance Criteria

- [ ] `grep -nE '\|[[:space:]]*grep[[:space:]]+-[a-zA-Z]*q'` over the
  comment-stripped body of `tests/scripts/lib/git-data-birth-readiness-gate.sh`
  returns zero hits (verification command, not prose).
- [ ] The strict `templatefile` shape check at the former ~line 511 reads
  `_shape_src` through a herestring; `bash -n` clean; the S1 arm and all
  14 S rows pass deterministically.
- [ ] An instrument-failure verdict is distinguishable from a no-match verdict
  at that site: a simulated `grep` exiting 2 produces an ABORT whose text does
  NOT claim the argument shape is wrong (assert by stubbing `grep` on PATH in
  the arm's subshell, or by extracting the predicate into a testable spot).
- [ ] The other three sites (rate-limit ~1135, authorized_keys ~2056,
  ignore_changes ~2311) contain no `| grep -q`.
- [ ] New W-family rows: W2 (zero pipe-fed `grep -q*` in `tests/scripts/lib/*.sh`)
  and W2-control (the detector flags a seeded copy). `_FLOOR` raised to 254
  with the ledger comment extended; family row-count pins unaffected or
  updated.
- [ ] Full suite green: `bash tests/scripts/test-git-data-birth-readiness-gate.sh`
  reports `0 failed` (current: 252 assertions; after: ≥254).
- [ ] The shard is green end-to-end in CI on this PR (`test-scripts (6/7)`).

## Test Scenarios

- Given a `main.tf` whose sole `templatefile(` argument IS the strict literal,
  when the bound-files roster is derived, then the check PASSES — unchanged
  behaviour (S1 contract preserved).
- Given a module dir whose concatenated `.tf` content exceeds the 64 KiB pipe
  buffer with the match on an early line, when the check runs under
  `set -o pipefail`, then it still PASSES — the mechanism that produced the CI
  false ABORT is structurally gone (no pipe exists to break). *(Deterministic
  reproducer of the OLD bug: `_shape_src` ≥ ~150 KiB → `printf | grep -q`
  returns non-zero 40/40 despite matching; the herestring form returns 0.)*
- Given `grep` exits 2 (regex/engine failure — simulated via a PATH stub) at
  the `templatefile` check, then the gate ABORTs naming an instrument failure,
  not a shape violation.
- Given a lib file seeded with `x | grep -q y`, when W2's extraction runs on
  it, then the output is non-empty (control row).
- Given `grep -q` on a FILE and `grep -q <<<"$x"` present in a lib file, then
  W2 does not flag them (the pin protects the sanctioned forms).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI test/tooling change confined to
`tests/scripts/`.

## Open Code-Review Overlap

None — queried `gh issue list --label code-review --state open` (87 open) for
`tests/scripts/lib/git-data-birth-readiness-gate.sh`,
`tests/scripts/test-git-data-birth-readiness-gate.sh`, and the bare
`git-data-birth-readiness-gate` token: zero bodies match.

## Success Metrics

- `test-scripts (6/7)` green on this PR's CI run and on the subsequent main
  merge run; the suite's flake surface at the four sites is structurally
  eliminated rather than retry-masked.
- The gate's ABORT vocabulary distinguishes "could not evaluate" from
  "evaluated and refused" — the next transport flake reports an instrument
  failure, not a shape violation.

## Dependencies & Risks

- **Risk — false positive in W2:** a prose/comment line in `tests/scripts/lib/`
  containing the literal `| grep -q` would flag. Mitigation: the extraction
  strips full-line comments first (the lib's ~line-2260 comment block is the
  known in-repo offender); a mid-line `#` inside a string literal remains a
  theoretical miss-classification the implementer resolves by inspection.
- **Risk — floor/pin bookkeeping:** the suite pins family row counts
  (`_expect_rows`) and a global assertion floor (`_FLOOR=252`, currently
  exactly 252). Adding rows without bumping the floor ledger leaves the ledger
  comment lying about provenance; the work phase raises the floor and extends
  the itemised comment.
- **Risk — scope creep:** `producer | grep -q*` survives elsewhere
  (`scripts/expenses-verify-by-check.sh` ~line 85,
  `scripts/resend-alert-path-discoverability.sh` ~line 45,
  `scripts/cutover-inngest.sh` ~line 1919,
  `scripts/lint-questionnaire-identity.sh` ~lines 118/123, plus numerous
  `tests/scripts/test-*.sh` assertion sites where a false negative is already
  fail-loud). Deferred to a follow-up issue — this PR fixes the load-bearing
  gate, not every consumer.
- **No ADR/C4 impact:** bug fix on an existing gate; the gate's trust boundary
  (fail-closed, static resolution) is unchanged — verified the decision makes
  no ownership/tenancy/substrate move and needs no `model.c4`/`views.c4`/
  `spec.c4` edit (no new external actor, system, or access relationship).
- **No Observability section:** the Files-to-Edit list touches only
  `tests/scripts/` — outside the Phase 2.9 trigger paths
  (`apps/*/server|src|infra`, `plugins/*/scripts/`, new infra). The gate's own
  ABORT/HOLD ledger IS the observability surface.
- **No Encryption Posture / no IaC section:** no persistent store, no new
  connection, no provisioned resource.

## Implementation Phases

### Phase 1 — the four conversions (lib)

1.1 At `git_data_rung2_bound_files` (~line 511): replace
`if ! printf '%s\n' "$_shape_src" | grep -qE '…'; then` with the herestring
form plus an `rc ≥ 2` instrument-failure split; keep the ABORT text for the
rc = 1 (genuine shape violation) arm byte-identical so existing needles
(A15/A15b family) still match.
1.2 Rate-limit site (~1135): capture `sed '$d' <<<"$_resp"`, then
herestring-grep `-qiE 'rate limit'`; retry semantics unchanged.
1.3 authorized_keys sweep (~2056): capture filtered hits; `rc ≥ 2` → ABORT
instrument-failure; non-empty → existing HOLD (optionally listing hits).
1.4 ignore_changes check (~2311): capture `tr` output, herestring-grep.

### Phase 2 — the regression pin (suite)

2.1 W2 row beside W1: comment-stripped `grep -nE '\|[[:space:]]*grep[[:space:]]+-[a-zA-Z]*q'`
over `"$ROOT"/tests/scripts/lib/*.sh` must be empty.
2.2 W2-control row: a synthesized copy of a lib file with a seeded
`producer | grep -q` line is flagged by the same extraction (proves dispatch —
the Guard Contract row-4 obligation).
2.3 Floor bookkeeping: `_FLOOR` 252 → 254, ledger comment extended; verify no
`_expect_rows` pin needs bumping for the new family.

### Phase 3 — verification

3.1 `bash tests/scripts/test-git-data-birth-readiness-gate.sh` → 0 failed.
3.2 Deterministic reproducer evidence in the commit/PR: the ≥150 KiB
`_shape_src` case ABORTs under the old pipe form and passes under the new
herestring form.
3.3 The deferred repo-wide `producer | grep -q` sweep is filed as #9217
(meta/machinery; scope: `scripts/` + `tests/scripts/test-*.sh`; why deferred:
this PR unblocks main CI; re-evaluate when the next gate is touched).

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Make the fixture emit a single-line `templatefile` literal | **Rejected — already true.** The fixture emits the strict form; the issue's diagnosis is the ABORT's own (wrong) hypothesis taken at face value. |
| Teach the gate's parser to accept multi-line `templatefile(` | **Rejected — wrong layer and wrong diagnosis.** The canonical-shape narrowing is deliberate (#7534): an indirected reference is statically unresolvable, so accepting it would unbind bytes from the evidence digest. And the input was never multi-line. |
| Retry the predicate on failure | **Rejected — masks instrument failure.** A fail-closed gate that retries its own measurement converts "the instrument is broken" into "eventually agreed" and still misreports the cause. |
| Drop `pipefail` inside the function | **Rejected — wrong trade.** `pipefail` is what makes every OTHER multi-stage extraction in this file honest (a failed `sed`/`grep -o` mid-pipe must propagate); removing it locally to shelter one predicate re-opens the class it closes. |
| `[[ "$_shape_src" =~ … ]]` (pure-bash regex) | **Viable but not chosen.** The file's established convention is `grep -q … <<<"$var"` (5+ existing sites); matching the local idiom beats introducing a second form. |
| Herestring conversion + rc split (chosen) | One mechanism the file already documents at ~line 2260; the rc split at the two verdict-bearing sites is what makes the NEXT flake diagnosable at first read. |

## Research Insights

**Premise Validation (Phase 0.6).** Checked: issue #9210 is OPEN; both cited
files exist on `origin/main` and are byte-identical to this worktree
(`git diff 4992f929e6 HEAD --` → empty). The green↔red delta
`4b47b16748..4992f929e6` contains exactly one commit — the triggering merge
#9183, whose stat list touches only `apps/web-platform` LinkedIn cron code +
KB docs. Suspects `09c7cc31cd` (in the *green* run's tree; its only lib change
is a `.soleur-owned` marker write in `_git_data_rung2_hash_at_sha`, a different
function) and `a5b2e36b56`/#8711 (merged 09-24, pre-green) are both
exonerated. Run 36550702286's `test-scripts (6/7)` attempt 2 PASSED on
identical code (`gh api .../jobs` shows `attempt=2 success`); sibling run
36550703958's shard failure was a DIFFERENT suite (`test-all-runtime-ceiling`
M7 contention — the birth-readiness suite itself logged `[ok]` in 159 s
there); local run here: 252/252 green. **Stale premise:** the issue's
"fixture templatefile shape / sibling merge" framing — the failure is a
transport-level flake in `producer | grep -q` under `pipefail`, evidenced by
`line 511: printf: write error: Broken pipe` immediately preceding the ABORT.

**Mechanism measurement (this session).** `printf|grep -q` under
`set -o pipefail`: 0/20000 false-ABORTs on a ~600 B input; 7/40 at 70 KiB,
29/40 at 100 KiB, 40/40 at ≥150 KiB — deterministic once the producer outlives
`grep -q`'s early exit. For the ~1.5 KB fixture input the CI event required
early consumer death (signal/exec hiccup — post-hoc unverifiable), which the
same construction mishandles identically; the fix removes the pipe regardless.

**Property List (Phase 0.6b).** (a) S1's verdict reflects whether the pattern
matched — never whether a pipe survived. (b) A transport/instrument failure
ABORTs with cause-attribution distinct from a shape violation (the
misattribution IS this incident's cost). (c) The class cannot silently
drift back — a pin, because three sibling sites survived one prior fix.

**Cut List.** Mechanism "fixture emits single-line literal" → property (a) →
already satisfied by the fixture as written (no-op). Mechanism "parser accepts
multi-line" → no property in the list; and re-opens the #7534 fail-open it
was built to close.

**Value-Proposition Measurement (0.6c).** Not applicable — the justification
is correctness/attribution, not a cost saving; nothing to quantify.

**Repo anchors.** `tests/scripts/lib/git-data-birth-readiness-gate.sh`
`git_data_rung2_bound_files` (~line 286; banned-idiom site ~511; convention
documentation ~2260); sibling pipe-fed sites ~1135, ~2056–2057, ~2311.
`tests/scripts/test-git-data-birth-readiness-gate.sh` `_r2_write_module`
(~line 428; emits the strict single-line literal), `_row`/W1 (~line 2812),
`_FLOOR=252` (~line 3057), `mutate_r2`/`mutate_suite` (~lines 879/910),
`_expect_rows` (~line 2066).

**Institutional learnings applied.** ADR-119 (~line 122: predicate "must carry
no pipe" — `grep -q` early close → producer SIGPIPE → pipefail 141); the lib's
own ~line-2260 measured comment; `scripts/inngest-liveness-classify.sh:70`,
`scripts/test-all-capacity-signal.test.sh:32`,
`scripts/lint-workflow-errexit-capture.test.sh:86`,
`scripts/zot-mirror-diagnosis.test.sh:32`,
`scripts/zot-restart-loop-alarm-scrub.test.sh:27` — five independent copies of
the same convention. Learning `2026-09-07-the-guard-i-wrote-died-on-the-case-it-was-written-to-catch.md`
(guard must survive its own trigger conditions);
`2026-07-16-five-documented-traps-recurred-and-a-perturbing-instrument-is-not-evidence.md`
(the class was documented and still recurred → the pin, not just the fix).

**CLAUDE.md conventions.** `set -uo pipefail` suite; `[[ ]]` tests; fail-loud
to stdout for operator-protection signals; comment anchors by symbol name not
line number.

**Deepen-plan round (2026-09-29, inline — no spawn-capable tool in this
harness).** Gate ledger: 4.4 precedent-diff — the herestring idiom is the
file's own convention (comment ~line 2260 + live sites ~1246/1575/2086/2286/
2295; sibling precedent `scripts/inngest-liveness-classify.sh:70` et al.), so
the pattern is NOT novel. 4.45 verify-the-negative — every negative claim
re-probed: the four-site census `grep -nE '\|[[:space:]]*grep[[:space:]]+-[a-zA-Z]*q'`
over the lib returns exactly 511/1135/2057/2311 (nothing else); attempt-2-green
verified via `gh api …/jobs`; fixture literal verified by reading
`_r2_write_module`; `tests/scripts/lib/*.sh` siblings carry zero hits.
4.5 network-outage trigger matches only the `.ssh` PATH text — not applicable,
no deep-dive. 4.55 downtime — no serving surface touched. 4.6 PASS (threshold
`none`, no sensitive-path diff). 4.7 FIRED — non-docs diff → `## Observability`
authored above. 4.8 PAT sweep clean. 4.9 no UI surface. 4.10 no store or new
connection. 4.11 `lint-guard-contract.py` green on Guard 1; adequacy read:
the Assembly quantifies over the directory glob (structure that produces
members), not today's site list, and the matrix includes a dispatch-mutation
row, a second-member row, and a must-PASS row. Quality-check sweep: rule-id
citations in this plan (`hr-weigh-every-decision-against-target-user-impact`,
`wg-when-tests-fail-and-are-confirmed-pre`, `cq-test-fixtures-synthesized-only`)
verified live in `AGENTS.md`; label `meta/machinery` verified via the #9217
filing; issue #7534 verified (CLOSED, bound-files derivation) — it is the issue
that narrowed admissible `templatefile` shape, which is why "accept multi-line"
is rejected.

## Sharp Edges

- A plan whose `## User-Brand Impact` is missing or placeholder fails
  deepen-plan 4.6 — filled above, threshold `none`, no sensitive-path
  scope-out required (diff touches only `tests/scripts/`, which the canonical
  `SENSITIVE_PATH_RE` does not reach).
- When changing the gate's strings, keep the rc = 1 ABORT needle text stable —
  suite rows assert on substrings (`mutate_r2` needles, A15-family).
- `pipefail` inside `$( )` capture and inside sourced-lib functions is
  inherited from the CALLER — the lib must stay correct under `set -uo
  pipefail` (test suite) and plain interactive shells; the herestring idiom
  is correct under both.
- `x="$(cmd || _rc=$?)"` does NOT propagate `_rc` (subshell) — capture rc via
  `x="$(cmd)"; _rc=$?` outside the substitution.
- Do not let the plan's own `| grep -q` prose examples enter W2's sweep scope —
  the pin targets `tests/scripts/lib/*.sh` only, comment-stripped.

## References & Research

- Issue: #9210 — ci: git-data-birth-readiness-gate fails on main (S1 …)
- Failing run: `gh run view --job 109347891989 --log` (attempt 1 of run
  36550702286; attempt 2 green)
- Convention authority: `tests/scripts/lib/git-data-birth-readiness-gate.sh`
  ~line 2260 ("A HERESTRING, NOT A PIPE"); ADR-119; ADR-149 (the gate's design).
- Related merged work: #8711 (`a5b2e36b56`, dm-snapshot/dirty-journal — in the
  green tree), #8738 (`09c7cc31cd`, scratch reclamation — `.soleur-owned`
  marker only, exonerated), #9183 (the triggering merge — unrelated files).
- Deferred: repo-wide `producer | grep -q` sweep → filed as #9217
  (meta/machinery, Post-MVP / Later).
