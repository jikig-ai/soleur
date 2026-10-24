# Structural Enumeration — PR #10953 (guard-shaped, `## Guard Contract`)

Seat: STRUCTURAL ENUMERATION. A MAP, not a findings list — every path is enumerated; none is
ranked or triaged. `VERIFIED` marks paths exercised against scratch copies in `mktemp -d`
(the tree was never mutated). Anchors cite content, not line numbers, per
`cq-cite-content-anchor-not-line-number` (line numbers given as `~` aids).

## Guard inventory (what the assembly is made of)

| Component | Anchor |
|---|---|
| Chokepoint lib | `plugins/soleur/test/lib/git-corrupt-graph.sh` — `dead_oid`, `corrupt_walk_break`, `corrupt_dead_tag`, `corrupt_invariant_dead_absent`, `corrupt_probe_forced_skip`, `corrupt_skip` |
| Census (standing) | `test-bump-inngest-bootstrap-pin.sh` — `_census_obj='.git/objects/'` + `grep -rInE` block (`~_census_hits=`), fail-only row `census:no-object-store-deletion`, pathspec `$REPO_ROOT/.github/scripts/test/` |
| Roster parity (suite side) | bump: `_roster_bad=$(grep -oE "corrupt_skip[[:space:]]+'[^']+'" "$0" ...)` vs `^(g1b\.|g2b\.)`; mint: same shape vs `^fl.` — both grep `"$0"` only |
| Floor + cap | bump: `TOTAL=$((PASS + FAIL + SKIPPED_ASSERTIONS))`, `MIN_ASSERTIONS=696`, `SKIP_CAP=28`; mint: `MIN_ASSERTIONS=673`, `SKIP_CAP=3` |
| Selftest capture rows | bump: `{ CORRUPT_WALK_PROBE_FORCE=skip ... } > "$LAST_OUT" 2>&1` + `st_run` (`{ "$@"; } >/dev/null 2>&1`); mint: `> "$TMP/skip.st1/2/3" 2>&1` |
| Monitor probe | `scripts/followthroughs/t5-skip-persistence-bound-7510.sh` — source 2: `GUARD_UNITS`, `--event merge_group` + `--event pull_request` sampling, per-suite banner discriminator `=== test-<name>.sh ===`, `unit_obs >= 1` per source |
| Probe test | `…7510.test.sh` — arms (l) g1b.→FAIL, (m) fl.→FAIL, (n) no-banner→TRANSIENT, (o) FAIL-dominates, (p) enumerated-prefix-has-producer |
| Workflow | `scheduled-rehearsal-skip-monitor.yml` — generalized title/body; verdict `broken` for out-of-contract rc |
| Carrier | `.github/scripts/test/run-all.sh` — `echo "=== $(basename "$t") ==="` printed BEFORE `bash "$t"`, streams uncaptured |

---

## (a) Paths by which a corrupt-walk construction can bypass the lib/census

| # | Path | Anchor | Guard window? | One-line member outside reach |
|---|---|---|---|---|
| a1 | New `rm`/`unlink`/`find -delete` site under `.github/scripts/test/`, canonical spelling | census grep | COVERED — runs every bump-suite invocation | `rm -f "$R/.git/objects/$fanout"` (this IS the covered member) |
| a2 | Non-enumerated verb: `mv` relocation, `chmod 000`, `truncate -s0`, `dd`, `> obj`, `shred -u`, `python3 os.remove`, `srm`, `cp /dev/null obj` | census alternates `(rm\|unlink)\s`, `rm -rf`, `find…-delete` only | NOT COVERED — VERIFIED (candidates 5,6,10 unmatched) | `mv "$R/.git/objects/ab/cd" "$R/.git/objects/ab/cd.bak"` |
| a3 | Obfuscated spelling inside pathspec: variable-indirect path, quote-split literal, line-continuation | census is a per-line literal grep | NOT COVERED — VERIFIED (candidates 3,4 unmatched) | `P=.git/objects; rm -f "$R/$P/ab/cd"` or `rm -f "$R/.git""/objects/ab/cd"` |
| a4 | Path without the trailing-slash literal: `rm -rf "$R/.git/objects"`, `find "$R/.git/objects" -type f -delete` | every census alternative requires `.git/objects/` WITH slash | NOT COVERED — VERIFIED (candidates 2,7 unmatched) | `rm -rf "$R/.git/objects"` |
| a5 | Verb AFTER the path on the same line: `find <objdir> -exec rm {} +`, `find -execdir unlink`, `xargs rm`, `ls … \| xargs rm` | `rm` alternatives all require the verb left of `.git/objects/` | NOT COVERED — VERIFIED (candidate 8 unmatched) | `find "$R/.git/objects/" -exec rm {} +` |
| a6 | Store-level deletion with no path literal: `git gc --prune=now`, `git prune`, `git prune-packed`, `git repack -ad` + pack `rm`, `update-ref -d` + gc | census greps path literals only | NOT COVERED — VERIFIED (`git gc --prune=now` unmatched) | `git -C "$R" update-ref -d refs/heads/side && git -C "$R" gc --prune=now` |
| a7 | Binary-file evasion: the census grep uses `-I` (`--binary-files=without-match`); one NUL byte anywhere in the suite file makes grep skip the WHOLE file | `grep -rInE` in census row | NOT COVERED — VERIFIED (NUL-mutated file with `rm -f $R/.git/objects/…` produced zero hits) | `printf '\x00' >>` the suite file, then any `rm` line |
| a8 | Site OUTSIDE the pathspec: `plugins/soleur/test/lib/` (incl. inside `git-corrupt-graph.sh` itself), `plugins/soleur/test/*.test.sh`, `scripts/**`, `apps/**`, inline `run:` blocks | census pathspec `"$REPO_ROOT/.github/scripts/test/"` — hardcoded one directory | NOT COVERED — two known sites deferred to #10956; the deferral covers THOSE files, not the class | add `rm -f "$repo/.git/objects/…"` inside a helper in `git-corrupt-graph.sh` |
| a9 | Non-deletion corrupt construction not routed through the lib: inline `hash-object -w -t commit` forge, `update-ref` to a hardcoded absent sha, `git clone --filter=*` partial-clone, `git replace`, `GIT_OBJECT_DIRECTORY` indirection | the census asserts absence of deletions; nothing asserts presence of the chokepoint | NOT COVERED — the "ONE spelling" property is enforced only against the old spelling | `git -C "$F_REPO" update-ref refs/heads/main "$(printf '0%.0s' {1..40})"` |
| a10 | Census-carrier loss: the only census lives inside the bump suite near EOF. (i) a mid-suite `exit 0` above the census block skips census+floor+cap+roster and still exits green — nothing downstream asserts the `Results:` tail ran (run-all.sh counts rc only). (ii) renaming `test-bump-…sh` out of the `test-*.sh` glob deletes the census; `MIN_SUITES=15` vs 16 suites on disk tolerates exactly one loss | `run-all.sh` `for t in "$DIR"/test-*.sh`, `MIN_SUITES=15` | NOT COVERED | insert `exit 0` above `_census_obj=` in the bump suite |
| a11 | `corrupt_invariant_dead_absent` is opt-in per row: a new corrupt row that simply omits the invariant check loses the `-w`-drift tripwire silently | per-row `if corrupt_invariant_dead_absent …` | NOT COVERED — nothing enumerates forge calls vs invariant calls | add a row calling `corrupt_walk_break "$F_REPO" refs/heads/main` with no invariant line |
| a12 | `dead_oid` nonce is a FIXED string (`'soleur-corrupt-graph dead-parent\n'`): any prior run that wrote it for real (the selftests at bump `selftest-c` / mint `fl-skip-selftest` DO write it, into fixture repos) leaves the oid dead only per-repo — a second forge in a repo where the blob was ever `-w`-written produces a readable "dead" parent; the invariant catches it, but a row without the invariant (a11) silently forges a healthy graph | `dead_oid()` fixed printf | PARTIAL — only via a11 | call `corrupt_walk_break` in a fixture where `hash-object -w` of the nonce ran |

---

## (b) Paths by which a `corrupt_skip` verdict can evade charging / cap / observation

| # | Path | Anchor | Guard window? | One-line member outside reach |
|---|---|---|---|---|
| b1 | Charge evaded by direct emit: `echo 'SKIP (loud): g1b.x …' >&2` with no `corrupt_skip` — no charge, no `::warning::`, no cost validation | roster check greps `corrupt_skip` call sites only | PARTIAL — floor catches only via exact-count coupling (MIN=green count), i.e. only for a converted existing row of cost ≥1 | `printf 'SKIP (loud): g1b.B7 gone\n' >&2` replacing the `corrupt_skip` line |
| b2 | Roster-check quoting hole: `corrupt_skip "zz.x"`, `corrupt_skip zz.x`, `corrupt_skip "$row"` — grep requires `corrupt_skip\s+'…'`; non-single-quoted names are invisible to BOTH suite roster blocks AND probe test (p) (`corrupt_skip 'PREFIX` also single-quote-keyed) | bump/mint `_roster_bad` grep; `.test.sh` `_guard_prefixes` producer grep | NOT COVERED — VERIFIED (double-quoted/bare/variable call sites produced zero grep hits) | `corrupt_skip "zz.freedom" 3 'x'` in the bump suite |
| b3 | Third-suite call site: roster parity greps `"$0"` only (bump greps bump, mint greps mint); a `corrupt_skip 'x.y'` in any of the other 14 `test-*.sh` files (or anywhere else) is roster-unaudited, and an unregistered-prefix marker is also probe-invisible | `_roster_bad=…"$0"` | NOT COVERED | add `source …/git-corrupt-graph.sh` + `corrupt_skip 'x.y' 1 'r'` to `test-tag-filter.sh` |
| b4 | Charge evaded by subshell: `( corrupt_skip … )`, `x=$(corrupt_skip …)`, `corrupt_skip … &` — `SKIPPED_ASSERTIONS+=` lands in a subshell and dies; stderr marker still reaches the job log (observed, uncharged) | `SKIPPED_ASSERTIONS=$((SKIPPED_ASSERTIONS + cost))` in lib | PARTIAL — floor catches the under-count for existing rows; cap never sees it | `n=$(corrupt_skip 'g1b.B7' 8 'reason')` |
| b5 | Counter tampering: `SKIPPED_ASSERTIONS=0` / `-=k` after a skip — cap evaded outright; floor catches the under-count unless the same diff moves a cost/floor constant | tail `TOTAL`/ceiling block | PARTIAL — floor-only, same exact-count coupling as b1 | `SKIPPED_ASSERTIONS=$((SKIPPED_ASSERTIONS - 8))` after the skip line |
| b6 | Under-declared cost: `corrupt_skip 'g1b.B7' 1 …` — validates as numeric, charges 1 | `case "$cost" in ''\|*[!0-9]*)` validation | PARTIAL — floor catches the delta for existing rows; a NEW row's declared cost is whatever the diff says (review-unit only) | change `8` to `1` at the B7 call site |
| b7 | Marker emitted into a captured stream: `corrupt_skip` inside a `{ } >f 2>&1` block or inside `run_bump`'s capture — charged, but never reaches the job log → monitor-observation evaded while the suite stays green | stream context of each call site is unchecked — roster greps the NAME, nothing greps the redirect context | NOT COVERED | wrap the call site: `( corrupt_skip 'g1b.B7' 8 'x' ) >>"$LAST_OUT" 2>&1` |
| b8 | Emission-literal drift in the lib: `corrupt_skip` prints `SKIP (loud): ` — the probe greps `SKIP (loud): g1b.` etc.; NOTHING pins the lib's emitted literal against the probe's enumerated literals for the guard source. The (k)-class value-pin in `.test.sh` covers only the rehearsal `arm_skip` echo; (l)/(m) hand-write the marker into fixtures; (p) derives prefixes FROM the probe file | `printf 'SKIP (loud): %s %s\n'` in lib vs `GUARD_UNITS` literals | NOT COVERED — the highest-leverage single edit: one `s/SKIP (loud):/SKIP:/` in the lib unobserves every guard-suite skip while banners keep the source "observed" → PASS | edit the lib's printf to `'SKIPPED: %s %s\n'` |
| b9 | Banner≠observation gap: the per-suite discriminator `=== test-<name>.sh ===` is printed by `run-all.sh` BEFORE invoking the suite — it proves enumeration, not stream delivery. Redirect the suite (`bash "$t" >"$cap" 2>&1`) and every marker is captured away while `unit_obs` keeps counting → zero hits, PASS | `run-all.sh` `echo "=== … ==="` then `bash "$t"` | NOT COVERED | `bash "$t" >"$LOGDIR/$(basename "$t").log" 2>&1 || rc=$?` in run-all.sh |
| b10 | Unsampled carrier: the marker can only be counted in `pr-quality-guards.yml` `merge_group`/`pull_request` run logs. A suite step added to any other workflow, or a `push`/`workflow_call` leg added to this workflow, emits markers into logs the probe never opens. No census asserts the suites run ONLY inside the sampled carrier | `gh run list --workflow pr-quality-guards.yml --event …` | NOT COVERED | add `run: bash .github/scripts/test/test-bump-….sh` to a step in any other workflow |
| b11 | Whole-run (not per-job) log scope: `gh run view --log` is one blob for the run; banner and marker attribution is `grep -F` over the blob — a foreign job's `SKIP (loud): g1b.` counts as a guard hit (over-count → false FAIL), and a banner printed by a different job makes `unit_obs>0` while the real suite's captured markers read as zero (under-count → false PASS when combined with b9) | probe `for _u … grep -qF "$_disc" <<<"$log"` | NOT COVERED | any other job in `pr-quality-guards.yml` printing `=== test-bump-inngest-bootstrap-pin.sh ===` |
| b12 | Marker counted only inside banner-bearing logs: the probe `continue`s per-unit when the banner is absent — a marker in a run lacking the banner is uncounted AND the unit reads TRANSIENT (loud, correct direction; enumerated for completeness) | `grep -qF "$_disc" <<<"$log" \|\| continue` | COVERED (degrades TRANSIENT) | — |
| b13 | Sampling window: `head -n "$SAMPLE"` (20) over deduped mg+pr ids; a skip confined to runs outside the window is uncounted — bounded-window is the declared ADR-188 design | `--limit "$SAMPLE"` ×2 + `head` | COVERED-BY-DESIGN (declared residual) | — |
| b14 | `CORRUPT_WALK_PROBE_FORCE=skip` leaking from an unsampled environment: inside the sampled suites the cap (28/3) bounds it; in a third suite with no cap, or a workflow not sampled (b10), forced skips run unbounded/unseen | env knob honoured by `corrupt_probe_forced_skip` unconditionally | PARTIAL — bounded only where cap+roster exist | `env:` `CORRUPT_WALK_PROBE_FORCE: skip` on a job outside `pr-quality-guards.yml` |
| b15 | `corrupt_skip` `row` operand unsanitized (only `reason` is `%`/CR/LF-scrubbed): a row carrying `\n`/`%` via ANSI-C quoting forges extra `SKIP (loud):`/`::warning::` lines — also evades the single-quote roster grep (b2). Direction: forged/misattributed hits, not silence | `reason=${reason//'%'/'%25'}` — no parallel line for `row` | NOT COVERED | `corrupt_skip $'g1b.x\nSKIP (loud): g1b.fake' 1 r` |
| b16 | `SKIP_CAP`/`MIN_ASSERTIONS`/`TOTAL` are per-suite constants; a weakening that edits the constant in the same diff is the declared review-unit boundary (plan "Anchor") — enumerated, not a structural blind spot | tail blocks both suites | COVERED-BY-REVIEW-UNIT | — |
| b17 | `SKIPPED_ASSERTIONS` undeclared in a third suite: `set -u` suites die (loud); a suite without `set -u` charges a never-folded, never-capped variable | lib relies on caller contract | PARTIAL | `corrupt_skip` call in a suite lacking the tail plumbing |

---

## (c) Paths for markers vs streams

| # | Path | Anchor | Guard window? | One-line member |
|---|---|---|---|---|
| c1 | Suite marker reaches the job log UNCOUNTED: any `SKIP (loud):` producer with a non-enumerated prefix (via b2 quoting hole, b3 third suite, or a direct `echo`) in a banner-bearing run — marker observed-by-nobody | probe `_marks` per unit | NOT COVERED | `corrupt_skip 'zz.x' 1 r` (bare word → invisible to roster AND probe) |
| c2 | Selftest/exercise marker reaches REAL streams: every capture is per-call-site convention (`{ } >f 2>&1`, `st_run`, `>/dev/null 2>&1`); nothing mechanically asserts capture — a new exercise without a redirect poisons the monitor with a phantom `g1b.`/`fl.` hit on every green run (loud misattribution, trust erosion) | Guard-1 row 8 is the pattern itself, not a check | NOT COVERED | append `corrupt_probe_forced_skip && corrupt_skip 'g1b.t' 1 x` unwrapped in either suite's selftest block |
| c3 | Selftest names use registered prefixes (`g1b.selftest-forced-skip`, `fl.selftest-forced-skip`): roster parity REQUIRES that, which means selftest rows can never be renamed out of monitor visibility — the only thing keeping them harmless is the capture convention (c2) | roster `grep -vE '^(g1b\.|g2b\.)'` flags non-prefixed names | NOT COVERED (structural coupling, correctly aligned but convention-only) | — |
| c4 | Marker text inside fixture data echoed verbatim: a fixture/fixture-log containing `SKIP (loud): g1b.` that a suite `cat`s or an assertion dumps on failure reaches the log as a real hit | e.g. `assert_out_has` prints `LAST_OUT` content on FAIL | NOT COVERED | fixture line `SKIP (loud): g1b.B7 …` in `MOCK_CRANE_LOG` + a failing row that echoes it |
| c5 | `SKIP (loud):` emitted on a run the probe cannot attribute: bump/mint run under a different runner that omits the `=== … ===` banner (e.g., invoked directly, not via run-all.sh) → marker in log, `unit_obs` stays 0 → TRANSIENT (safe direction) | probe per-unit `continue` | COVERED (TRANSIENT) | — |
| c6 | `::warning::` stdout annotation: reaches the log as an annotation, intentionally not grep'd by the monitor; a `::error::`-class or different-command emit from `corrupt_skip` is unobserved by design | `printf '::warning::…'` in lib | COVERED-BY-DESIGN | — |
| c7 | Selftest capture files under `$TMP`: `LAST_OUT`/`skip.st*` are suite-private; a suite that `cat`s its capture file on a fail path (e.g. the `fail "…captured: $(tr '\n' '|' < "$LAST_OUT")"` diagnostic ALREADY echoes captured markers into the log when the selftest itself fails) — real-marker text re-emitted as diagnostic ⇒ counted as a hit on a RED run (harmless: run is already red; marker content identical) | bump `fail … "captured: …"` line | PARTIAL — only on already-red runs | widen a diagnostic to `cat "$LAST_OUT"` on a green path |
| c8 | Probe-side: markers grepped `<<<"$log"` per unit — a `SKIP (loud): g1b.` line split across a log-chunk boundary (gh log stitching) is missed per-line; whole-line grep only | `grep -cF "$_m" <<<"$log"` | EDGE (log-format dependence, no chunk seam known in `gh run view --log`) | — |

---

## Verdict — does each guard's ASSEMBLY equal the property it names?

**Guard 1** ("every corrupt-ancestry break exists by construction; the census pins no-bypass"):
NO — the assembly enforces "no file under `.github/scripts/test/` contains one of the enumerated
deletion spellings," which is strictly weaker: a2–a7 are same-directory bypasses verified against
the census regex itself, a8 is the whole rest of the repo (including the lib's own file), a9 is the
unenforced chokepoint direction (deletion-census ≠ construction-census), and a10 removes the census
carrier with the job still green.

**Guard 2** ("exactly one counted, capped, observed SKIP; producers always observed"):
NO — charge/cap hold only through the exact-count floor coupling for existing rows (b1/b4–b6 are
floor-only, and a new row's cost is a review-unit decision), while observation has two structural
holes the monitor cannot see: the emitted marker literal is unpinned for the guard source (b8 — one
printf edit silently unobserves every g1b./g2b./fl. skip with banners still green), and the banner
discriminator proves suite enumeration, not stream delivery (b9 — one redirect in run-all.sh makes
every marker invisible while `unit_obs` keeps counting). Roster parity additionally greps only
single-quoted names in `"$0"` (b2/b3), so an unregistered-prefix producer is invisible to both the
self-check and the probe.

## Empirical verification log

- Census regex: 13-candidate battery in scratch → candidates 2,3,4,5,6,7,8,10 unmatched (a2–a5).
- `grep -rI` binary skip: NUL-mutated suite file containing `rm -f "$R/.git/objects/ab/cd"` → zero hits (a7).
- `git gc --prune=now` / `update-ref -d` construction → zero hits (a6).
- Roster grep: `corrupt_skip "zz.top"` / `zz.bare` / `"$row"` → extracted-name list omits all three (b2).
- run-all.sh banner ordering read directly: `echo "=== basename ==="` precedes `bash "$t"` (b9).
