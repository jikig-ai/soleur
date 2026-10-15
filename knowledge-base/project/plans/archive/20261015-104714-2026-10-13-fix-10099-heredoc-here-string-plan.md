---
title: "fix: guard-vacuity-floor `<<<` here-strings read as phantom heredoc openers (#10099)"
date: 2026-10-13
slug: fix-10099-heredoc-here-string
branch: feat-one-shot-10099-heredoc-here-string-false-positive
issue: 10099
closes: 10099
type: fix
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# fix: guard-vacuity-floor `<<<` here-strings read as phantom heredoc openers (#10099)

## Overview

`scripts/guard-vacuity-floor.test.sh`'s `heredoc_lines_of()` (line 127) scans
each line for the awk ERE `<<-?[[:space:]]*['"]?[A-Za-z_][A-Za-z0-9_]*` at every
position. On a `<<< 'word'` here-string the match fires starting at the SECOND
`<` (`<<` + `'word` → tag `word`), opening a heredoc span that never terminates —
every later line is classified as fixture text and excluded from floor
detection. Measured live on the #10051 merge-queue attempt
(`lint-shell-trace-credential-refusal.test.sh`); the in-flight workaround bound
the probe feeds to variables (`<<< "$var"` — the `"`+`$` pair fails the tag
pattern), documented at `lint-shell-trace-credential-refusal.test.sh:2986-2989`.

Fix (the issue's direction, verified at plan time on the real corpus): reject an
opener match that is immediately preceded by `<` — `if (RSTART > 1 &&
substr($0, RSTART-1, 1) == "<")` inside the existing `match()` block. awk ERE
has no lookahead, so "the `<<` must not be the tail of `<<<`" is expressed as a
preceding-character check, not a pattern change. The same check also closes the
`<<<<<<<` git-conflict-marker string variant (`resolve-regenerable-conflicts
.test.sh:123` prints one inside a `printf` format string — measured below).

Plan-time measurement upgraded the issue's scope estimate: fixing the regex
makes the detector MORE precise, which un-hides floors — and two currently
invisible floors land in the mutation-tested scope, one of them
non-constructible as written. The fix therefore carries one REQUIRED companion
edit outside the guard file itself: `plugins/soleur/test/deploy-arm.test.sh`'s
`MIN_CASES=79` binding (line 697) must move adjacent to its floor `if` (line
703) or the suite classifies CONSTRUCTION and breaches
`MAX_CONSTRUCTION_FAILURES=15`, which sits at exactly 15 with zero headroom.

## Research Insights

### Premise Validation (Phase 0.6) — all verified live at plan time

- `#10099` — OPEN, labels `priority/p2-medium`, `type/bug`,
  `domain/engineering`, `meta/machinery`. Filed from the #10051 merge-queue
  conflict resolution.
- **Defect reproduced** on this branch (2026-10-13): a 7-line synthesized suite
  containing `grep -qE 'pat' <<< 'literal'` before its floor reports lines 5-8
  (the floor included) as heredoc body under the as-written `heredoc_lines_of`
  awk. With the preceding-`<` rejection the same fixture reports only the real
  heredoc bodies.
- **Here-string shapes enumerated** (`/tmp` probe matrix, both detector
  variants): `<<< 'lit'`, `<<<lit`, `x<<<"lit"` all currently open phantom
  spans; `<<<"$var"` and `<<< "$var"` never matched (`"$` fails the tag pattern —
  the issue's own note, confirmed). Under the fix none open. `<<EOF`, `<<-EOF`,
  `<<'EOF'`, tab-indented `<<-DELIM`, and `cat<<'T'` (opener directly after a
  word char) all still open and terminate correctly.
- **Population impact measured, not reasoned.** The guard's own derivation was
  replayed verbatim (the suite's `increments_of`/`harnesses_of`/`counters_of`/
  `floor_lines_of` extracted unmodified, `heredoc_lines_of` parameterized) over
  `git ls-files '*.test.sh'`:
  - baseline (as-written awk): **360 floor-bearing** (matches the suite's own
    printed `repo-wide floor-bearing: 360`, covered 313, deferred 47,
    unclassified 0, fires 298, nofire 0, construct 15 — full run, 23/23 green).
  - `<<<`-fix only: **362** — `plugins/soleur/scripts/
    resolve-regenerable-conflicts.test.sh` (its `<<<<<<< ours` printf literal at
    :123 opens a span today) and `plugins/soleur/test/deploy-arm.test.sh`
    (`<<< 'actions/runs?…'` needle literals at :652-655) join the population.
    Both are under COVERED_DIRS (`plugins/soleur/scripts/`,
    `plugins/soleur/test/`). Zero files lost (`comm -23` empty — the fix only
    ever shrinks the excluded-line set, so floors can only become MORE visible).
  - `<<<`-fix + comment-skip (`^[[:space:]]*#` never opens): **363** —
    additionally `apps/web-platform/infra/doppler-injection-bound.test.sh`,
    whose floor is hidden today by a `<<EOF` token inside a `#` comment at :42.
    That directory is DEFERRED → the ledger goes 47 → 48 against the shrink-only
    `MAX_DEFERRED=47` (line 1345) → **ARM 5c reds**. See Proposed Solution §3.
- **Verdicts measured through the suite's own `build_mutant`/`classify_suite`:**
  `resolve-regenerable-conflicts` → FIRES (`_min_cases=140` sits directly above
  its `if` at :766-767 — already the adjacent-literal shape); `deploy-arm` →
  CONSTRUCTION (`MIN_CASES=79` at :697 is separated from the `if` at :703 by
  echo/printf/conservation lines, so `build_mutant`'s backward
  simple-assignment slice at :1004-1018 stops before binding it — mutant dies
  `MIN_CASES: unbound variable`); `doppler-injection-bound` → FIRES
  (`MIN_ASSERTIONS=31` adjacent at :1141). Moving `MIN_CASES=79` adjacent to its
  `if` was simulated on a copy: deploy-arm → **FIRES**.
- **Ratchet headroom (measured):** `MAX_CONSTRUCTION_FAILURES=15` at exactly 15;
  `MAX_DEFERRED=47` at exactly 47; `MIN_FIRING_SUITES=52` vs. 298 live. With the
  plan as written: covered 313→315, fires 298→300, construct 15→15,
  deferred 47→47, unclassified 0→0. No ratchet is breached; raising
  `MIN_FIRING_SUITES` by the +2 newly-visible firing members follows the #6604
  derivation-widening precedent recorded in its own comment (carried as decision
  row D5).
- **Residual blind classes the fix deliberately does NOT close** (each verified,
  each a follow-up under umbrella #8689 — "guard-vacuity-floor silently drops a
  suite with an unterminated heredoc opener", OPEN):
  - `<< word` inside a quoted string on a code line:
    `scripts/lint-shell-capture-exit.test.sh:832` carries
    `if grep -qF "echo 'a;b'   << read:" <<<"$LINT_OUT"` — the needle's
    `<< read` opens a phantom span (`tag=read`, UNCLOSED) under ALL three
    detector variants, and the file is a **live derivation miss today**: its
    floor at :1497 is invisible, so it sits in no scope — not covered, not
    deferred, not unclassified — the blind spot the guard's header (:35-41)
    admits it cannot self-report. Rescue is subject-side de-tokenization (the
    `<[<]` idiom at `.github/actions/infra-credentials/
    infra-credentials.test.sh:370-376`) PLUS a floor-binding repair (its bound
    `${CAPTURE_LINT_MIN_ASSERTIONS:-133}` at :29 is not adjacent to the `if`),
    then a suite classification — follow-up issue, Phase 4.
  - `#` comment lines containing `<<TAG` — fixes ONLY under the comment-skip
    variant, which is deferred (Solution §3): measured cost is a deferred-ledger
    breach, and the sibling-measured needle class (`<<'LUKSEOF'` inside
    grep/awk needles in `inngest-redis-luks-loopback.test.sh`) is NOT covered by
    comment-skip anyway — it is the quoted-string class above.
  - `a<<b` arithmetic shift (`lint-shell-capture-exit.test.sh:1428` — inside a
    real heredoc fixture today) and `x << y` in `((…))`: lexically
    indistinguishable from `cat<<EOF` without a shell parser. Unchanged.
  - A genuine `<<TAG` opener later on the same line as a `<<<` trigger: the
    reject-and-`next` form skips the whole line. grep-verified no `*.test.sh`
    line carries both (all same-line `<<<`+`<<'EOF'` hits use the safe `<<<"`
    form, e.g. `cutover-inngest-workflow.test.sh:2093` — the `<<<"` never
    matches, the real `<<'EOF'` still opens). Rescan-loop variant costed and
    rejected — decision row D2.
- How the suite runs in CI: `test-scripts` shard matrix leg **7**
  (`scripts/suite-shard-legs.tsv:364`), `.github/workflows/ci.yml`
  `SCRIPTS_SHARD` env.
- Institutional learnings applied: the guard file's own comment corpus (it is
  the authority — every earlier "measured" claim in it was re-derived rather
  than trusted); sibling-session measurement from #10217 (de-tokenized
  `<<'LUKSEOF'`/`<<'GUARDEOF'` needles in the loopback suite — the
  quoted-string class).

### Property List (Phase 0.6b)

- P1. A `<<<` here-string — `<<< 'x'`, `<<<x`, `x<<<"lit"`, any position —
  never opens a heredoc span.
- P2. Real openers still open: `<<EOF`, `<<-EOF`, `<<'EOF'`, `<<"EOF"`,
  indented (`<<-`), opener directly after a word char (`cat<<EOF`), opener at
  column 0.
- P3. A line inside a real heredoc body is still excluded from floor detection
  (the fix must not neuter the exclusion — a detector that never opens a span
  also "fixes" the symptom).
- P4. The derived population's ledger arithmetic stays inside every hand
  ratchet: n_construct ≤ 15, n_deferred ≤ 47, n_unclassified = 0.
- P5. The two newly-visible covered floors are mutation-tested, not merely
  counted: resolve-regenerable-conflicts FIRES as-is; deploy-arm FIRES after
  its `MIN_CASES` binding moves adjacent to the `if`.
- P6. The guard suite's own floor/conservation/self-test tail is untouched and
  still balances (cases == passes + fails; `MIN_META_CASES=20`).

### Cut List (Phase 0.6b)

- *Lookahead/`<<(?!<)` regex* — POSIX awk ERE has no lookahead; expressed as
  the preceding-character check instead (equivalent: a `<<<` can only match
  starting at its second `<`, whose predecessor is `<`).
- *`(^|[^<])<<-?…` context-inside-the-match* — verified equivalent on the same
  corpus probe, but the `[^<]` prefix byte joins `tag` and needs an extra
  `sub()` in the extraction, and `^|`-alternation semantics inside `match()`
  are subtler to review than a two-line guard clause. Rejected for diff size,
  not correctness (D1).
- *Comment-skip (`^[[:space:]]*#` never opens)* — measured, not assumed:
  un-hides `doppler-injection-bound`'s floor → deferred ledger 47→48 → ARM 5c
  breach. The only lawful resolutions are a PROMOTED_FILES promotion (the suite
  increments its verdict counters INSIDE `pass()`/`fail()` at :101-102 — the
  exact shape every promotion rationale in this file rejects — and carries no
  `[FATAL] accounting` conservation check) or hardening that suite first. Both
  exceed the issue's "Fix-Size: small". Deferred to a follow-up (D3).
- *String-awareness (skip `<<` inside quotes)* — a shell parser, not a regex;
  the class that includes the sibling's needle strings and
  lint-shell-capture-exit's live miss. #8689's proposed `UNTERMINATED` sentinel
  is the systemic shape. Out of scope; filed (Phase 4).
- *Raising `MAX_DEFERRED` or `MAX_CONSTRUCTION_FAILURES`* — both are
  shrink-only ratchets the file's own comments forbid raising; the plan is
  built so neither moves.

### Deepen-pass verification (2026-10-13)

- **Gates:** 4.6 User-Brand Impact present, threshold `none` with a stated
  reason — meta/machinery under `scripts/`, no prod mutation, no user-data or
  runtime surface: pass. 4.7 Observability: five fields present;
  `discoverability_test.command` is `git grep -l 'RSTART-1' -- scripts/`
  (allowlisted verb `git`, ms runtime, no ssh; deliberately NOT
  `grep … guard-vacuity-floor.test.sh` — any command token ending `.test.`
  trips Check-10's over-inclusive suite-shape detector, so the probe greps for
  the fix's anchor token via git's pathspec instead of naming the file), and
  `expected_output` is the whitespace-free literal `guard-vacuity-floor.test.sh`
  that `-l` prints. 4.8 PAT-shaped variables: none. 4.9 UI: no
  UI-surface file, skipped. 4.10 Encryption Posture: fires only when a plan
  introduces a store or cross-component connection — neither; section included
  with empty lists for completeness. 4.11 Guard Contract: FIRES (the deliverable
  edits an anti-vacuity guard) — one entry with Property/Assembly/mutation
  matrix ≥3/harness rows/anchor; `python3 scripts/lint-guard-contract.py` to be
  re-run at work time. 4.12 Scope Check: one unfenced `## Scope Check`, three
  subsections, no `unmapped` cell, `Recommendation:` present. 4.5 network-outage
  and 4.55 downtime gates not fired (no SSH/firewall/prod-mutation surface).
- **Citations resolved live (2026-10-13):** #10099 OPEN (labels verified);
  #8689 OPEN (umbrella — the unterminated-opener class; quoted-string instance
  named verbatim in its body); `lint-shell-trace-credential-refusal.test.sh`
  workaround comment at :2986-2989 read; `infra-credentials.test.sh:363-376`
  `<[<]` de-tokenization idiom + its "phantom heredoc swallows the floor"
  measurement read; `suite-shard-legs.tsv:364` pins the suite on leg 7; the
  suite's own printed baseline (360/313/47/0/298/0/15; 31/0/16 deferred;
  23/23) captured from a full local run.
- **Negative claims checked against code:** (a) "the fix only un-hides, never
  hides" — `comm -23` of the two population sweeps is empty on both variants;
  (b) "`<<<\"$var\"` never matched" — verified in the probe matrix AND in
  corpus grep (all ~95 `<<<"-`hits rely on the `"`+`$` failure, including the
  #10051 workaround lines); (c) "no line carries both a `<<<` trigger and a
  real opener" — `git grep -nE '<<<.*<<-?[[:space:]]*[...]'` over `*.test.sh`
  returns only `<<<"`+`$(cat <<'EOF'` shapes where `<<<"` cannot match;
  (d) "comment-skip adds exactly one deferred member" — population diff is
  exactly `doppler-injection-bound.test.sh`; (e) "deploy-arm's only floor
  candidate is line 703 and `$MIN_CASES` is referenced nowhere between :697 and
  :704" — `floor_lines_of` on the file returns exactly `703:` and grep confirms
  no other reference.
- **Semantic-change test audit (full enumeration):** the changed function
  `heredoc_lines_of` is file-local to `guard-vacuity-floor.test.sh` (grep over
  the repo for `heredoc_lines_of` returns only this file). Consumers of the
  DETECTOR'S OUTPUT are `floor_lines_of`→`is_floor_bearing`/`classify_suite`
  (same file) — the whole repo sweep is the audit. Suites whose own text embeds
  `<<`-shaped tokens and reference this detector in comments:
  `infra-credentials.test.sh` (`<[<]` idiom — a workaround that stays correct),
  `lint-shell-trace-credential-refusal.test.sh` (variable-bound feeds — stays
  correct; MAY be simplified back to literals in a follow-up, not required).
- **Additional learnings applied this pass:**
  `2026-10-13-a-sibling-session-shipped-the-same-fix-while-i-planned` (the
  #10217 sibling's de-tokenization was the workaround class this fix retires);
  the suite's own §"NARROWING…is bounded by ARM 3" doctrine (this fix is a
  WIDENING of detection — floors become more visible — bounded by the ratchet
  headroom measurements above rather than by ARM 3).

## Root Cause

`heredoc_lines_of` (:127-138) matches `/<<-?[[:space:]]*['"]?[A-Za-z_]
[A-Za-z0-9_]*/` via `match()`, which is position-agnostic. For `<<< 'literal'`
the leftmost match starts at the SECOND `<` (the first cannot start a match —
a `<` cannot be a tag-start character), so `tag` extracts as `literal` and
`inhd` opens. No subsequent line is a bare `literal`, so the span runs to EOF
and every floor after the here-string is silently excluded — the file drops
out of `floor_lines_of` entirely (derivation miss) or loses its real floor
while keeping earlier decoy candidates (the #10051 NO_FIRE shape).

The same mechanism explains the two extra population members the fix un-hides:
`resolve-regenerable-conflicts`'s `printf` literal `"<<<<<<< ours"` (match at
the 6th `<`, tag `ours`) and `deploy-arm`'s `<<< 'actions/runs?…'` probe
literals (tag `actions`).

## Proposed Solution

Rulings are recorded in `knowledge-base/project/specs/
feat-one-shot-10099-heredoc-here-string-false-positive/decision-challenges.md`.

1. **The opener rejects a match preceded by `<` (D1, D2).** Inside the existing
   `match()` block of `heredoc_lines_of`, before extracting `tag`:

   ```awk
   if (RSTART > 1 && substr($0, RSTART-1, 1) == "<") next
   ```

   `RSTART == 1` cannot be a `<<<` (nothing precedes it); any match preceded by
   `<` is the tail of `<<<`/`<<<<…`. `next` is correct on rejection — a
   rejected line opens nothing and prints nothing, and no corpus line mixes a
   `<<<` trigger with a real opener later in the line (verified). The heredoc
   semantics otherwise unchanged: same tag extraction `gsub`, same terminator
   `^[[:space:]]*tag[[:space:]]*$`, same body-line print. The function's
   comment block gains the measured-history paragraph this file's convention
   demands (the `<<<` class, the #10051 measurement, the `<<<<<<<` marker
   instance, and the residual classes left to #8689: quoted-string `<<`,
   arithmetic `a<<b`, `<<<`+real-opener same-line).
2. **Companion edit REQUIRED by the widened detection (D4).**
   `plugins/soleur/test/deploy-arm.test.sh`: move `MIN_CASES=79` from :697 to
   the line directly above `if [[ "$cases" -lt "$MIN_CASES" ]]` (:703) — the
   file's own convention and `build_mutant`'s documented contract ("the bound
   is a literal adjacent to the `if`"). Simulated at plan time: the file's
   verdict moves CONSTRUCTION → FIRES and `MIN_CASES` has no other reference
   between :697 and :704, so the move is semantics-free. Without it the suite
   newly enters the covered population as a 16th CONSTRUCTION and breaches the
   zero-headroom ratchet — the fix cannot land green without this edit.
3. **Comment-skip evaluated and DEFERRED (D3).** Adding `!/^[[:space:]]*#/`
   to the opener is a one-line change with a measured ledger consequence:
   `apps/web-platform/infra/doppler-injection-bound.test.sh` becomes
   floor-bearing, lands in DEFERRED, and grows the shrink-only ledger 47→48
   (ARM 5c red). The sanctioned resolution — promotion via PROMOTED_FILES —
   needs the promotion bar this file documents (call-site counter increments,
   conservation check, instrument self-test); doppler-injection-bound increments
   `PASS`/`FAIL` inside `pass()`/`fail()` and has no `[FATAL] accounting` check,
   so promotion means hardening that suite first. That is a second PR's worth
   of scope on an issue sized "small"; filed as a follow-up in Phase 4.
4. **New fixture rows in the guard's own suite — ARM 8c (D6).** Between ARM 8b
   (:1433) and ARM 9 (:1435), a synthesized `$SUITE_TMP` fixture exercising the
   detector directly through `floor_lines_of`, in the same `printf >` style as
   ARM 7/8/8b:

   - counter increments (`cases=$((cases + 1))`, twice — the minimum for a
     derivable counter),
   - a `<<< 'literal'` here-string line (the defect shape — also worth a
     `<<<literal` variant row in the same fixture),
   - a real `cat <<'HD'` heredoc whose body contains a floor-SHAPED decoy
     (`if [[ "$cases" -lt 99 ]]` — must stay excluded; a "fix" that deleted
     heredoc detection entirely would surface it),
   - the real floor after all of it (`if [[ "$cases" -lt 2 ]]`).

   Two assertions: (a) `floor_lines_of` on the fixture returns exactly one
   candidate and it is the real floor line — RED before the fix, GREEN after
   (the regression pin); (b) the decoy line inside the heredoc body is absent
   from the output — the other-direction pin. (Alternatively (b) folds into
   (a)'s exact-count assertion; kept as its own `cases++` row so each verdict
   names one property.) Suite total: 23 → 25 assertions; `MIN_META_CASES=20`
   untouched.

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| `match($0, /(^|[^<])<<-?…/)` — context inside the regex | Verified equivalent on the corpus probe, but the `[^<]` byte joins `tag` and forces an extra `sub()` in extraction; a review-obvious `RSTART` guard clause is the smaller diff. (D1) |
| Rescan-loop over the remainder after a rejected `<<<` | More correct for `<<< 'w' … <<EOF` on one line; no corpus line has that shape and the loop costs ~4 lines plus a second rejection path to keep in sync. `next` chosen; revisit if the corpus grows one. (D2) |
| Comment-skip in the same PR | Measured: forces a deferred-ledger breach or a suite hardening/promotion the issue didn't ask for. Follow-up. (D3) |
| Full shell tokenization (string-aware `<<`) | The residual class needs a parser; #8689's `UNTERMINATED` sentinel is the systemic shape and is a different defect fix (it makes misses LOUD, not fewer). |
| Fix only the fixture row, not the detector | The detector IS the defect; a fixture alone certifies nothing. |

## Implementation Phases

**Phase 0 — RED first (`cq-write-failing-tests-before`).** Add the ARM 8c
fixture + its two assertions to `scripts/guard-vacuity-floor.test.sh`; run
`bash scripts/guard-vacuity-floor.test.sh` — the fixture row must print FAIL
(assertion ~24) while the existing 23 stay green.

**Phase 1 — the detector fix.** Apply the `RSTART`-preceding-`<` rejection in
`heredoc_lines_of` + the comment paragraph recording the measured history.

**Phase 2 — the companion binding move.** `deploy-arm.test.sh`: relocate
`MIN_CASES=79` adjacent to the floor `if`. Re-run `bash plugins/soleur/test/
deploy-arm.test.sh` (must stay green — the move is inside the accounting
block, semantics-free).

**Phase 3 — green + population re-measurement.** Run the full guard suite;
expected ledger: `repo-wide floor-bearing 362`, `covered 315`, `deferred 47`,
`unclassified 0`, `fires 300`, `nofire 0`, `construct 15`; deferred unchanged
31/0/16; `Total: 25 passed, 0 failed`. If `MIN_FIRING_SUITES` is raised (D5:
52→54), the new value sits inside the same comment's changelog format
(`+2 (#10099): resolve-regenerable-conflicts, deploy-arm (derivation
widening)`).

**Phase 4 — follow-up filing.** One issue under the #8689 umbrella recording
the measured residuals: (a) comment-line `<<TAG` openers +
doppler-injection-bound's promotion-or-hardening decision (the measured
ARM 5c interaction); (b) the quoted-string/`<<`-in-needle class with
lint-shell-capture-exit's live derivation miss named (subject-side
de-tokenization + floor-binding repair described); (c) `a<<b` arithmetic
adjacency. Labels `domain/engineering`, `type/bug`, `meta/machinery`.
Optionally simplify `lint-shell-trace-credential-refusal.test.sh`'s
variable-bound workaround comment to note the detector fix (a comment edit
only — the workaround itself is harmless and reverting churn is not owed).

**Phase 5 — closeout.** PR body `Closes #10099`; comment on #8689 noting the
`<<<` leg fixed and the residual classes carried in the new follow-up.

## Files to Edit

- `scripts/guard-vacuity-floor.test.sh` — `heredoc_lines_of` opener rejection +
  comment paragraph; new ARM 8c fixture + 2 assertions (cases 24-25);
  optionally `MIN_FIRING_SUITES` 52→54 (D5).
- `plugins/soleur/test/deploy-arm.test.sh` — `MIN_CASES=79` moved adjacent to
  its floor `if` (:697 → directly above :703).

## Files to Create

None in source. Spec artifacts only: `knowledge-base/project/specs/
feat-one-shot-10099-heredoc-here-string-false-positive/{decision-challenges.md,
tasks.md}`.

## Non-Goals

- No comment-line exclusion, no quoted-string awareness, no arithmetic-shift
  handling — all deferred to the follow-up (Phase 4) under #8689.
- No changes to `lint-shell-trace-credential-refusal.test.sh` or
  `infra-credentials.test.sh` workarounds beyond an optional comment touch-up.
- No ratchet is raised to absorb a regression — `MAX_CONSTRUCTION_FAILURES` and
  `MAX_DEFERRED` are shrink-only; `MIN_FIRING_SUITES` may only ratchet UP on a
  measured gain, never down.
- No promotion of `doppler-injection-bound` and no hardening of it.
- No `interface-contract.md` — one coherent two-file edit, no agent split
  (Tier-0 parallelism does not apply at this size).

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open` (200-limit) plus a
`guard-vacuity` search on 2026-10-13. Related-but-not-overlapping: **#8689**
(the umbrella for this defect class — the `UNTERMINATED`-sentinel proposal;
this PR fixes the `<<<` leg and cites it), **#7585** (promotion seam — the
mechanism D3's deferred option would need), **#7588** (consensus population
derivation — unrelated arm), **#8307** (extract derive-population triple —
refactor, textually adjacent but no behavioral overlap). No fold-ins; none of
the open review issues touch `guard-vacuity-floor.test.sh` or
`deploy-arm.test.sh`.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — the
  blast radius is a CI guard's detection accuracy. Worst cases: a suite's floor
  remains hidden (status quo ante, never worse) or the guard itself reds CI
  until reverted (self-revealing, not silent).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  exposure vector — a test-machinery regex over tracked `*.test.sh` files; no
  data surface, no credentials, no runtime path.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** meta/machinery (`domain/engineering`
  + `meta/machinery` labels on #10099); the change modifies a CI guard and one
  test-file constant placement — no production code, no user surface, no
  regulated data.

## Observability

```yaml
liveness_signal:
  what: "guard-vacuity-floor.test.sh exit 0 on CI test-scripts leg 7 with the printed ledger (floor-bearing/covered/fires counts) and 'Total: 25 passed, 0 failed'; the ARM 8c rows print '[ok] here-string does not open a phantom heredoc…'"
  cadence: "every PR (test-scripts shard matrix leg 7, suite-shard-legs.tsv:364)"
  alert_target: "CI failure on the PR — the guard is itself the observability for this class; a regression surfaces as a red required check"
  configured_in: "scripts/guard-vacuity-floor.test.sh (ARM 8c assertions + ledger print at :1150-1162)"
error_reporting:
  destination: "CI step output — '[FAIL] …' rows name the divergent assertion; population drift prints the offending suite paths verbatim (UNCLASSIFIED/NOFIRE/CONSTRUCT lists)"
  fail_loud: "a widened exclusion that re-hides a floor shows in the ledger counts (floor-bearing < 362) and/or ARM 8c red; a narrowed one shows as ARM 4 UNCLASSIFIED"
failure_modes:
  - mode: "<<< opens a phantom span again (rejection removed)"
    detection: "ARM 8c assertion (a) reds — floor_lines_of returns 0 candidates on the fixture"
    alert_route: "CI test-scripts leg 7 FAIL on the PR"
  - mode: "heredoc exclusion neutered entirely (every line is 'code')"
    detection: "ARM 8c assertion (b) reds — the in-body decoy floor leaks into candidates"
    alert_route: "CI test-scripts leg 7 FAIL on the PR"
  - mode: "a new floor-bearing suite becomes visible in an undeclared scope"
    detection: "ARM 4 closure names it in UNCLASSIFIED"
    alert_route: "CI FAIL listing the file"
  - mode: "deploy-arm binding drifts off-adjacent again"
    detection: "the suite classifies CONSTRUCTION → n_construct 16 > 15 → ARM 2 reds naming the file"
    alert_route: "CI FAIL + CONSTRUCT_LIST row"
logs:
  where: "CI step log (GitHub Actions, test-scripts leg 7); no runtime logs — this is test machinery"
  retention: "GitHub Actions run retention (inherited)"
discoverability_test:
  command: git grep -l 'RSTART-1' -- scripts/
  expected_output: guard-vacuity-floor.test.sh
```

## Encryption Posture

```yaml
at_rest: []
in_transit: []
```

No new store and no new cross-component/network connection; the deliverable is
test-guard regex correctness plus a constant's line placement in a test file.

## Guard Contract

### Guard 1 — `heredoc_lines_of` excludes exactly the heredoc-body lines

**Property.** For any tracked `*.test.sh`, `heredoc_lines_of` reports a line as
heredoc body IFF a real `<<[-]['"]?TAG['"]?` opener (never the tail of `<<<`,
never — pending the follow-up — inside a comment) precedes it and no bare `TAG`
terminator has intervened; here-strings, conflict-marker literals, and
`<<`-in-needles do not open spans.

**Assembly.** The single awk program in `heredoc_lines_of`
(`scripts/guard-vacuity-floor.test.sh:127-138`) — the chokepoint every
exclusion decision flows through — plus the ARM 8c fixture pair pinning both
directions, and the repo-wide ledger arms (ARM 1/2/4/5c ratchets) that bound
what a widened or narrowed exclusion can silently do to the population.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | `RSTART-1` rejection removed (the pre-fix shape restored) | RED: ARM 8c (a) — `<<< 'literal'` opens a phantom span, `floor_lines_of` returns 0 candidates on the fixture |
| 2 | `heredoc_lines_of` neutered to always-empty (no exclusions at all) | RED: ARM 8c (b) — the in-body `if [[ "$cases" -lt 99 ]]` decoy leaks into the candidate list |
| 3 | rejection weakened to `RSTART > 2` (misses `x<<<` at position 2 — the `<<<` at line start+1) | RED: a `<<<x`-at-column-1 fixture line still opens the phantom |
| 4 | terminator regex loosened (`tag` → `tag.*`) so spans close early | RED: real-heredoc bodies stop being excluded where the decoy sits — ARM 8c (b) or a live-population arm catches the drift |
| 5 | `MIN_CASES` adjacency in deploy-arm reverted | RED: ARM 2 — n_construct 16 > 15, and ARM 3's pin direction via the fires ledger |

**Harness rows.** (a) Suite-side edit that must RED it: restore the pre-fix
`match()` block — ARM 8c (a) fails with the phantom span swallowing the
fixture's floor. (b) Must-PASS inputs beyond the canonical `<<< 'x'`: `<<<x`,
`x<<<"lit"`, `<<-EOF` tab-indented terminator, `cat<<'T'` word-adjacent opener,
and the `<<<<<<< ours` printf literal (the resolve-regenerable-conflicts shape)
— all exercised by the live-repo population diff, the fixture rows, or both.
(c) Floors: `MIN_META_CASES=20` unchanged; population ratchets unchanged except
the optional D5 `MIN_FIRING_SUITES` +2.

**Anchor.** The detector feeds `is_floor_bearing` (the repo-wide sweep) and
`classify_suite` (the mutation battery) — the same code path the live 360-file
population flows through, so a wrong exclusion is measured against real suites
on every run, not only against the fixture. What must move outside the commit
for a weakening to pass: ARM 8c's fixture is synthesized in `$SUITE_TMP`
(outside `git ls-files`), so the pin cannot be gamed by editing a tracked
file's shape; the ledger ratchets are hand-pinned literals.

## Domain Review

**Domains relevant:** none

No cross-domain implications — a CI guard regex and one test-file constant
placement. Product/UX gate: no UI-surface file — mechanical override did not
fire. GDPR gate: no schema/auth/API-route/.sql surface. Technical forks were
recorded as `pending - assumed:` rows in `decision-challenges.md` (no Agent
tool on this harness); a `soleur:engineering:cto` ruling at review supersedes
them.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "the opener regex needs to reject a third `<` (e.g. `\<\<` NOT followed by `<`), so `<<<` never opens" [#10099] | Proposed Solution §1; Files to Edit `guard-vacuity-floor.test.sh` | mapped |
| 2 | "the tag pattern then also stops matching mid-`<<<`" [#10099] | Same edit — the match never reaches the tag pattern once the opener is rejected | mapped |
| 3 | "one regex correction + a fixture row in the guard's own suite" [#10099 Fix-Size] | Solution §1 + §4 (ARM 8c) | mapped |
| 4 | "If the fixed regex can ALSO cheaply exclude comment lines (`^\s*#`) … treat comment-stripping as a candidate enhancement to evaluate in the plan" [pipeline brief] | Evaluated with live measurement → deferred, Solution §3 / D3 + Phase-4 follow-up | mapped |
| 5 | "keep all 23 assertions green plus the new one" [pipeline brief] | Solution §4 — two rows; AC2 asserts `Total: 25 passed, 0 failed` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `RSTART`-preceded-by-`<` rejection | "the opener regex needs to reject a third `<`" | asked |
| ARM 8c fixture rows | "a fixture row in the guard's own suite" | asked |
| deploy-arm `MIN_CASES` adjacency move | — | inferred — measured consequence of the widened detection: without it the suite joins the covered population as CONSTRUCTION 16 > 15 and the fix cannot land green; the move is the file's own documented convention, not a workaround |
| `MIN_FIRING_SUITES` 52→54 (optional, D5) | — | inferred — the ratchet's own changelog records a +4 bump for the #6604 derivation widening; same class of change, same convention |
| Phase-4 follow-up issue under #8689 | — | inferred — `wg-when-an-audit-identifies-pre-existing`: the sweep measured two further live derivation-miss classes this issue does not own |
| Comment-skip deferred | "treat comment-stripping as a candidate enhancement to evaluate" | asked (evaluation delivered: measured ARM 5c consequence makes it non-cheap) |

### Split Assessment

- Subsystems touched: 2 — `scripts/`, `plugins/soleur/test/`
- Planned files: 2 source files | Estimated changed lines: ~60 (mostly
  comments + the fixture block)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated
  lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1: In `scripts/guard-vacuity-floor.test.sh`, `heredoc_lines_of` rejects
  an opener match preceded by `<`; `grep -n 'RSTART-1'
  scripts/guard-vacuity-floor.test.sh` returns a hit inside the `match()` block
  and the probe fixture (`<<< 'literal'` / `<<<lit` / `x<<<"lit"` before a
  floor line) yields the floor candidate instead of an empty body set.
- [ ] AC2: `bash scripts/guard-vacuity-floor.test.sh` exits 0 printing
  `Total: 25 passed, 0 failed` and a ledger of `repo-wide floor-bearing 362`,
  `covered 315`, `deferred 47`, `unclassified 0`, `fires 300`, `nofire 0`,
  `construct 15` (MIN_META_CASES unchanged; if D5 lands, MIN_FIRING_SUITES=54
  with the changelog annotation).
- [ ] AC3: `bash plugins/soleur/test/deploy-arm.test.sh` exits 0; `git diff` on
  it shows `MIN_CASES=79` relocated adjacent to its floor `if` and nothing else.
- [ ] AC4: The ARM 8c fixture rows RED on the pre-fix detector (shown in the
  Phase-0 capture attached to the PR) — `cq-write-failing-tests-before`.
- [ ] AC5: `git diff --name-only origin/main...HEAD` touches exactly
  `scripts/guard-vacuity-floor.test.sh`, `plugins/soleur/test/
  deploy-arm.test.sh`, and `knowledge-base/project/**` artifacts — no workflow,
  no subject-suite content edits.
- [ ] AC6: The follow-up issue exists (number recorded in the PR body) carrying
  the three measured residual classes under #8689; a comment on #8689 notes
  the `<<<` leg closed by this PR.
- [ ] AC7: PR body's first line answers "does merging this mutate production?"
  (`no — test machinery only`) and contains `Closes #10099`.

## Test Scenarios

- Given a synthesized suite with `grep -qE 'pat' <<< 'literal'` before its
  floor, when `floor_lines_of` runs, then the floor line is the sole candidate —
  before the fix it returned 0 candidates. (`guard-vacuity-floor` ARM 8c, unit)
- Given the same fixture carries a real `<<'HD'` heredoc containing a decoy
  `if [[ "$cases" -lt 99 ]]`, when `floor_lines_of` runs, then the decoy is
  excluded — the exclusion was narrowed at the opener, not deleted. (ARM 8c,
  unit)
- Given `deploy-arm.test.sh` post-move, when the guard mutation-tests it, then
  its floor FIRES (`MIN_CASES` bound by the backward slice; `cases=0` under
  neutering → `[FATAL] only 0 assertions ran`). (covered-scope, measured at
  plan time on a patched copy)
- Given `resolve-regenerable-conflicts.test.sh`, when the sweep runs, then its
  `<<<<<<< ours` printf literal no longer opens a span and its `CASES_RUN` floor
  classifies FIRES — a coverage gain, not just a parity change. (covered-scope,
  measured)
- Given any regression that re-hides a floor (rejection removed or exclusion
  neutered), when the suite runs, then ARM 8c (or ARM 1/2/4 on the live
  population) names it. (structural, mutation)
- Verification (read-only, local): `bash scripts/guard-vacuity-floor.test.sh`,
  `bash plugins/soleur/test/deploy-arm.test.sh`.

## Dependencies & Risks

- **Widening a detector moves the population — bounded.** The exclusion set can
  only shrink (a `<<<`-tail match is never a real heredoc in shell grammar —
  `<<<` is a single operator), so floors can only become MORE visible; the
  measured delta is exactly +2 covered / +0 deferred / +0 unclassified. The one
  unpleasant surprise class — a newly-visible floor that DOESN'T fire — is
  handled by the deploy-arm companion edit, not by excluding the file.
- **Future `<<<`+`<<TAG` same-line construct** — today absent from the corpus
  (verified); if one is ever written, the line's real opener is missed and the
  body below is treated as code. Direction of error is toward MORE visibility
  (a spurious candidate), the safe side.
- **`substr`/`RSTART` portability** — POSIX awk primitives; the suite already
  relies on `match`/`RSTART`/`RLENGTH`. No gawk-only feature introduced.
- **Sibling worktree overlap** — the #10217 sibling's de-tokenized loopback
  file is on ITS branch; this plan touches no overlapping file
  (`git diff --name-only` check in AC5).
- **Follow-up dependency** — the comment/needle classes stay live derivation
  misses until the filed issue lands; recorded explicitly rather than silently
  (the file's own header already documents the class).

## Context

- Issue: #10099 (`guard-vacuity-floor: \`<<<\` here-strings read as phantom
  heredoc openers in heredoc_lines_of`), labels `meta/machinery`,
  `ci/integration-suites` not present — `domain/engineering`, `type/bug`,
  `priority/p2-medium`.
- Umbrella: #8689 (`guard-vacuity-floor silently drops a suite with an
  unterminated heredoc opener`) — proposes an `UNTERMINATED` sentinel →
  UNCLASSIFIED classification; this PR's residual classes are exactly the
  instances that sentinel would surface.
- Key code: `scripts/guard-vacuity-floor.test.sh:127-138`
  (`heredoc_lines_of`), `:179-203` (`floor_lines_of`), `:997-1031`
  (`build_mutant` backward-slice binding rule), `:1164-1277` (ARMs 1-3),
  `:1345` (`MAX_DEFERRED=47`), `:1271` (`MIN_FIRING_SUITES=52`),
  `:1179` (`MAX_CONSTRUCTION_FAILURES=15`).
- Triggering subject (already worked around):
  `scripts/lint-shell-trace-credential-refusal.test.sh:2986-2993`.
- Measured baseline (this branch, 2026-10-13, full suite run): 360 / 313 / 47 /
  0 / 298 / 0 / 15; deferred 31+0+16=47; `23 passed, 0 failed`.

## Notes

- `lane:` `cross-domain` — meta/machinery with no `spec.md` authored upstream;
  spec artifacts (decision-challenges, tasks) ship with this plan.
- **No Task/Agent tool exists in this harness (Devin CLI subagent), so every
  research/verification fan-out the skills prescribe was executed inline by the
  planner** — the detector variants were run verbatim against the whole
  `*.test.sh` corpus and the three affected suites were classified through the
  suite's own extracted `build_mutant`/`classify_suite` functions, not
  re-implementations (established Devin-CLI substitution convention).
- The deepen-pass verification block above was authored by the planner (no
  independent review fan-out on this harness); its "sections enhanced"
  claims are limited to what was measured.
