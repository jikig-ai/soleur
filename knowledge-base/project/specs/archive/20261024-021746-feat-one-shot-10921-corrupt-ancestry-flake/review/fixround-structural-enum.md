# Fix-Round Structural Enumeration — PR #10953 delta-MAP

Seat: STRUCTURAL ENUMERATION (fix round). Scope: `git diff 5403f5b30e..HEAD` only.
Re-enumerates the three path families of `review/structural-enum.md` over the FIXED
tree. A MAP, not findings. `VERIFIED` = exercised against scratch copies in
`mktemp -d` (`/tmp/tmp.WsqILEPx4I`); the worktree was never mutated, no git writes.

## What the fix round changed (the delta substrate)

- Census (`test-bump-….sh`, `_census_obj=`): verbs now `rm|unlink|mv|chmod|truncate`;
  `.git` literal widened to `\.git(/objects)?(/|[^[:alnum:]_.-]|$)`; `find` matches
  `-delete|-exec` on either side; `git[[:space:]].*prune` added; `[^#]*` → `.*`
  (mid-line `#` no longer exempts); `-I` dropped; pathspec now
  `.github/scripts/test/` + `plugins/soleur/test/lib/`; residual paragraph added.
- Roster (both suites): operand extracted as `'q'|"q"|$var|bare-dotted` —
  `_roster_names=$(grep -oE "corrupt_skip[[:space:]]+('[^']*'|\"[^\"]*\"|\\\$[A-Za-z_{]…|[A-Za-z0-9_.-]*\.[A-Za-z0-9_.-]*)" "$0"`;
  new per-prefix NON-selftest live-producer check (`grep -vF selftest`).
- Probe test `(q)`: pins `printf 'SKIP (loud): %s %s\n'` literal in
  `plugins/soleur/test/lib/git-corrupt-graph.sh`. Floor 27→28.
- `run-all.sh`: `_suite_class="$(suite_exit_class "$rc")"`; emits
  `=== $(basename "$t") done ===` unless class `killed`. Probe `GUARD_UNITS`
  discriminator moved to the done-line; `--status completed` added; `_pg_list_rc`
  distinguishes gh failure only when the union is empty; FAIL denominator now
  `g_observed`.
- Lib: `CORRUPT_DEAD_NONCE` exported+reused by both selftests; repack failure FATAL
  and propagated (`_corrupt_maybe_repack … || return`); header harvest bound to
  header block (`sed -n '/^$/q; …'`) + empty-harvest FATAL; `row` AND `reason`
  sanitized (`%`→`%25`, `[[:cntrl:]]`, U+2028/9); charge `10#$cost` (octal
  fail-open closed); forced-skip reason labelled `forced-divergence exercise`.
- Suites: forge rc now a fail-only construction invariant at every call site;
  forced/organic skip rungs split; selftest force knob env-prefixed (no
  persistence past the block); mint selftest verdict lands on live counters
  (MIN_ASSERTIONS 673→674).
- CI: `pr-quality-guards.yml` packed-arm leg re-runs the two suites with
  `SOLEUR_FIXTURE_PACKED=1` directly (no run-all wrapper); monitor dedupes on a
  stable body marker + legacy-title transition list.
- VERIFIED on real tree: new census produces zero hits over both swept dirs
  (no self-trip); no `corrupt_skip 'g1b./g2b./fl.'` comment-producers exist today;
  no workflow exports `CORRUPT_WALK_PROBE_FORCE`.

---

## (a) bypass lib/census — delta table

| # | Path | Anchor | Covered NOW? | One-line outside-window edit |
|---|---|---|---|---|
| a1 | Canonical `rm`/`unlink`/`find -delete` spelling in swept dirs | census alternation 1,3 | COVERED | — |
| a2 | Non-enumerated verb | `(rm\|unlink\|mv\|chmod\|truncate)\s` | NARROWED — mv/chmod/truncate VERIFIED-HIT; `dd`, `: > obj`, `shred -u`, `cp /dev/null obj`, `python3 os.remove` VERIFIED-MISS | `: > "$R/.git/objects/ab/cd"` |
| a3 | Obfuscated spelling | per-line literal grep | NARROWED — quote-split `.git""/objects` now HITS (VERIFIED); variable-indirect path still misses (documented residual) | `P=.git/objects; rm -f "$R/$P/ab/cd"` (two lines, second has no `.git`) |
| a4 | Path without `.git/objects/` slash | `\.git(/objects)?(/…\|$)` | FIXED — `rm -rf "$R/.git/objects"` and `chmod 000 "$R/.git"` VERIFIED-HIT | — |
| a5 | Verb after path | `find … -delete\|-exec` both orders | NARROWED — `find <obj> -exec rm {} +` VERIFIED-HIT; `find … \| xargs rm` VERIFIED-MISS (no `-exec`/`-delete`, `rm` right of literal) | `find "$R/.git/objects" -type f -print0 \| xargs -0 rm -f` |
| a6 | Store-level prune | `git[[:space:]].*prune` | NARROWED — `git gc --prune=now` VERIFIED-HIT; bare `update-ref -d`, `git repack` without a `prune` literal, non-git deleters still miss | `git -C "$R" update-ref -d refs/heads/side` alone |
| a7 | NUL/binary exempts whole file | `-I` dropped | PLATFORM-DEPENDENT — VERIFIED-MISS on this host's `grep (GNU) 3.12-modified` (NUL file yields rc=1, NO "Binary file matches" line); standard GNU grep would emit `Binary file … matches` → hit. `-a` is the unadded belt | append `\x00` to the suite file, then any `rm` line — zero hits here |
| a8 | Site outside pathspec | pathspec = 2 dirs | NARROWED — `plugins/soleur/test/lib/` now swept (VERIFIED-HIT); `plugins/soleur/test/*.test.sh`, `scripts/`, `apps/`, inline `run:` blocks, packed-arm step bodies still outside | `rm -f "$repo/.git/objects/…"` inside a `scripts/` helper |
| a9 | Non-deletion construction | census asserts absence-of-deletions only | NOT COVERED — now explicitly documented ("deletion-spelling census, not a construction census") | `git -C "$F_REPO" update-ref refs/heads/main $(printf '0%.0s' {1..40})` |
| a10 | Census-carrier loss | census still lives only in bump tail; `exit 0` above it → rc 0 → `ok` → done-line printed | NOT COVERED — and the done-line now guarantees the truncated suite reads OBSERVED in the probe | `exit 0` above `_census_obj=` in the bump suite |
| a11 | Invariant opt-in per row | per-row `if corrupt_invariant_dead_absent` | NOT COVERED — forge-rc check added at all EXISTING sites, but nothing enumerates forge-calls vs invariant-calls for NEW rows | new row calling `corrupt_walk_break` with no invariant line |
| a12 | Fixed nonce drift | `CORRUPT_DEAD_NONCE` exported | NARROWED — suites' `-w` selftests now write the same constant (drift moves both together); the a11-shaped silent-forge path remains | `corrupt_walk_break` in a repo where the nonce was `-w`-written, row sans invariant |
| a-NEW | Mid-line `#` scanned | `.*` replaces `[^#]*` | COVERED w/ fail-safe inversion — a comment mentioning `rm … .git/objects` now trips the census → false RED, never silent | n/a (loud direction) |

## (b) evade charge/cap/observation — delta table

| # | Path | Anchor | Covered NOW? | One-line outside-window edit |
|---|---|---|---|---|
| b1 | Direct emit bypasses `corrupt_skip` | roster greps call-sites only | UNCHANGED — floor-only via exact-count coupling | `printf 'SKIP (loud): g1b.B7 gone\n' >&2` replacing the call |
| b2 | Roster quoting hole | new 4-form operand extraction | NARROWED — `"q"`, `bare.dotted`, `$var`, `"$var"`, `${var.name}` all extracted→prefix-checked (VERIFIED). STILL INVISIBLE (VERIFIED): `$'ansi.c'` ANSI-C operand, `$(cmd)` substitution, undotted bare word, `corrupt_skip \`+newline continuation | `corrupt_skip $'zz.x\ny' 1 r` |
| b2b NEW | Comment satisfies live-producer check | `_roster_names` greps comments too; `grep -vF selftest` is the only exclusion | NOT COVERED — VERIFIED: `# corrupt_skip 'g1b.commented' 1 'x'` extracts `g1b.commented`, satisfying BOTH prefix parity and the new non-selftest-producer loop while emitting nothing | delete all real `g1b.` rows, leave one `# corrupt_skip 'g1b.x'` comment → green |
| b3 | Third-suite call site | `_roster_names … "$0"` | UNCHANGED — now documented residual | `corrupt_skip 'x.y' 1 r` in `test-tag-filter.sh` |
| b4 | Subshell charge | `SKIPPED_ASSERTIONS + 10#$cost` | UNCHANGED — floor-only | `n=$(corrupt_skip 'g1b.B7' 8 'r')` |
| b5 | Counter tamper | tail TOTAL | UNCHANGED — floor-only | `SKIPPED_ASSERTIONS=0` after the skip |
| b6 | Under-declared cost | `case "$cost" in ''\|*[!0-9]*)` | UNCHANGED — `0` is numeric: `corrupt_skip … 0 …` emits the marker charging nothing (extreme member of the class) | `corrupt_skip 'g1b.new' 0 'r'` on a new row |
| b7 | Call site inside captured stream | stream context unchecked | NOT COVERED | wrap site in `{ … } >>"$LAST_OUT" 2>&1` |
| b8 | Emitted-literal unpinned | `(q)` grep `printf 'SKIP (loud): %s %s\n'` | NARROWED — literal itself pinned (format edits → RED). RESIDUAL: `(q)` pins the FORMAT STRING, not the args — `"x$row"`/`"${row#g}"` keeps `(q)` green while `SKIP (loud): xg1b.` misses the probe's `SKIP (loud): g1b.` prefix; `>&2` unpinned (harmless — both streams reach the log) | change `"$row"` to `"x$row"` in the lib printf |
| b9 | Discriminator ≠ stream delivery | `=== <basename> done ===` emitted by run-all.sh itself | NARROWED, NOT CLOSED — killed suites now read TRANSIENT (the claimed fix, correct). VERIFIED-MISS persists: `bash "$t" >cap 2>&1` leaves the done-line in the job log → `unit_obs=1`, markers captured away → PASS. The probe comment "can NEVER hide real markers" is false under redirection | `bash "$t" >"$LOGDIR/$(basename "$t").log" 2>&1 \|\| rc=$?` in run-all.sh |
| b9b | Truncated suite | done-line printed for any non-`killed` rc incl. `ok`/`failed` | NOT COVERED — `exit 0`/`exit 1` before corrupt rows → done-line present → observed+clean(nonzero=already-red, documented) | `exit 0` above the corrupt rows (same edit as a10) |
| b10 | Unsampled carrier | `gh run list --workflow pr-quality-guards.yml` | UNCHANGED | add the suite step to any other workflow |
| b11 | Whole-run attribution | per-blob `grep -F` | UNCHANGED — done-line still forgeable text (now documented/accepted, over-state only) | foreign job echoing the done literal |
| b12 | Marker sans discriminator | per-unit `continue` | COVERED (TRANSIENT) | — |
| b13 | Bounded window | `head -n "$SAMPLE"` | COVERED-BY-DESIGN | — |
| b14 | Force-knob leak | `corrupt_probe_forced_skip` | NARROWED — no workflow exports the knob today; selftest persistence bug FIXED (env-prefix). STILL: a future FORCE-exporting leg in a SAMPLED workflow files real alerts — labelling is in `reason`, the probe greps prefix, forced markers still COUNT (lib header accepts this) | `env: CORRUPT_WALK_PROBE_FORCE: skip` on a `pr-quality-guards` job |
| b15 | `row` operand unsanitized | `row=${row//'%'/'%25'}` + cntrl + U+2028/9 | FIXED | — |
| b16 | Constant weakening | tail blocks | COVERED-BY-REVIEW-UNIT | — |
| b17 | Third-suite plumbing | caller contract | UNCHANGED | `corrupt_skip` in a `set +u` suite |
| b18 NEW | `(p)` producer grep narrower than roster | `corrupt_skip[[:space:]]+'PREFIX…'` still single-quote-keyed | NOT COVERED — VERIFIED: a roster-legal `corrupt_skip "g1b.B7"` reads as MISSING producer → `(p)` FAILs. Fail-safe direction (false RED, never silent) — inconsistency, not a hole | convert all g1b. producers to double quotes → probe test red |
| b19 NEW | Octal charge fail-open | `10#$cost` | FIXED | — |
| b20 NEW | One-side `gh run list` failure | `_pg_list_rc` consulted only when `pg_ids` empty | NOT COVERED — mg-list fails + pr-list succeeds → silently PR-only sample, no transient reason names the failed side | (runtime condition, not an edit) |

## (c) marker vs streams — delta table

| # | Path | Anchor | Covered NOW? | One-line member |
|---|---|---|---|---|
| c1 | Marker uncounted (unregistered prefix) | `_marks` per unit | NARROWED w/ b2 — ANSI-C/`$(…)`/undotted-bare/continuation call sites still produce roster-invisible + probe-invisible markers | `corrupt_skip $'zz.x' 1 r` |
| c2 | Selftest marker → real streams | capture is per-call-site convention | NOT COVERED — nothing mechanical asserts the redirect | unwrapped `corrupt_skip 'g1b.t' 1 x` in a selftest block |
| c3 | Selftest names need registered prefixes | roster parity | UNCHANGED coupling | — |
| c4 | Fixture text echoed verbatim | `assert_out_has` dumps | UNCHANGED | `SKIP (loud): g1b.B7` in `MOCK_CRANE_LOG` + failing row |
| c5 | Marker sans discriminator | per-unit `continue` | COVERED (TRANSIENT) | — |
| c6 | `::warning::` channel | lib stdout printf | COVERED-BY-DESIGN | — |
| c7 | Diagnostic re-emit on red | `fail … "captured: …"` | UNCHANGED partial | `cat "$LAST_OUT"` on a green path |
| c8 | Log-chunk seam | whole-line `grep -cF` | UNCHANGED edge | — |
| c9 NEW | Forced marker counted | probe greps `SKIP (loud): g1b.` prefix; label lives in `reason` | NOT COVERED-by-design — label aids reading, marker still COUNTS; safe today only because no sampled leg exports the knob (verified) | a FORCE-exporting step inside a sampled workflow |
| c10 NEW | Packed-arm leg bypasses run-all wrapper | `SOLEUR_FIXTURE_PACKED=1 bash test-….sh` direct in job | COVERED-by-construction — markers land in the same job log where run-all's done-lines already mark the units observed; real packed-arm skips count (intended). The leg runs the census/floor too (full suite) | — |

## Verdict delta

**Guard 1 (no-bypass census):** still NO — narrowed from 8 open members to the
documented residual set (indirection, xargs-pipe, non-deletion verbs `dd`/redirect/
`shred`, store verbs without a `prune` literal, non-git deleters, dirs outside the
two swept, non-deletion constructions, carrier loss a10–a11). New finding: a7 NOT
closed on this host's grep 3.12-modified (NUL → zero hits, no Binary line) —
platform-dependent; add `-a` to pin it.

**Guard 2 (counted, capped, observed):** still NO — three holes narrowed, none
closed fully: b8 → arg-mutation survives the `(q)` format pin; b9 → done-line
proves completion, not delivery (redirect still hides markers green); b2 → ANSI-C/
`$(…)`/continuation operands still roster-invisible, and b2b (comments satisfy the
live-producer check) is a new same-class member. Charge side unchanged
(floor-only couplings, `cost 0` admitted). Fail-safe additions: b18 false-RED
inconsistency, census comment-scan false-positives.

## Empirical log (scratch `/tmp/tmp.WsqILEPx4I`)

- Census vs 21 mutants: HIT c1–c7, c13, c18, c21; MISS c8 (xargs), c9 (dd),
  c10 (`: >`), c11 (shred), c12 (indirect), c14 (python), c15 (var-objdir),
  c16 (cp /dev/null), c19 (outside dir), c20 (update-ref -d); c17 NUL →
  rc=1 no output on grep 3.12-modified (`grep -a` does match — belt unadded).
- Roster extraction vs 11 forms: `bare`, `$'ansi.c\n…'`, `$(gen.name)`, and
  `\`-continuation all invisible; `# corrupt_skip 'g1b.commented'` extracted →
  satisfies live-producer check.
- Done-line sim: suite→cap.log redirect → done-line in job.log, unit observed,
  hits=0 → PASS (b9 residual verified end-to-end).
- `(p)` grep: `corrupt_skip "g1b.B7"` → MISSING (false-RED); `'g1b.B7'` → FOUND.
- Real-tree census sweep: zero hits (self-trip absent).
