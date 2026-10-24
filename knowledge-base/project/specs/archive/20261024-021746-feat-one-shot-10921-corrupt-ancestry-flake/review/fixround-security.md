# FIX-ROUND Security Review — PR #10953 (feat-one-shot-10921-corrupt-ancestry-flake)

Reviewer: `soleur:engineering:review:security-sentinel` · 2026-10-23 · report-only seat
Scope: **fix diff only** — `git diff 5403f5b30e..HEAD` (4 fix commits: a62f8a0e07, 807e3e78c6,
0df83e9ea5, 80bc9370f4). Prior seat report: `review/security.md` beside this file.

## Executive Summary

**Verdict: all seven named fixes CLOSED and verified; no new defect in the fix area that
changes the verdict.** Four info-level residuals noted below (N1–N4); none blocks.

Every verification below was re-run against the FIXED worktree; empirical repros ran in
`mktemp -d` scratch. `bash -n` clean on all six touched shell files; both workflow YAMLs
parse; the broadened census grep runs verbatim with **zero hits** on the tree (no self-trip).

## Per-fix verification

### 1. Sanitizer extended to `[[:cntrl:]]` + U+2028/9 — CLOSED (P1 resolved)

`plugins/soleur/test/lib/git-corrupt-graph.sh:285-292`. Order preserved: `%`→`%25` first
(annotation-forgery neutralization), then `[[:cntrl:]]`, then the two Unicode separators by
byte sequence — applied to **both** `reason` (285-288) and `row` (289-292). The row-side
extension closes the chokepoint gap the original P1 flagged.

Empirical (scratch): input carrying ESC, BEL, VT, DEL, U+2028, U+2029 and a literal `%0A`
emerges as `pre[31mmidpostend%250AX` — every control byte and both Unicode separators
stripped, `%0A` rendered inert as `%250A`. Verified byte-wise via `od`. Residual (info,
pre-existing class): invalid/non-ASCII high bytes that are neither cntrl nor U+2028/9 pass
through — they carry no annotation-forging capability.

### 2. Repack rc gated — CLOSED

`git-corrupt-graph.sh:125-128` — `git -C "$1" repack -adq || { FATAL…; return 1; }`; both
forge callers propagate via `|| return` (`:144` walk_break, `:185` dead_tag), and the
suite-level forge-rc gates (below) route that rc to fail(), never corrupt_skip. A packed-arm
repack failure can no longer degrade silently to a loose-store green.

### 3. Forge rc gated at all 5 call sites — CLOSED

- bump B7  `test-bump-inngest-bootstrap-pin.sh:1624-1625`
- bump B7c `:1667-1668`
- bump B7a `corrupt_dead_tag` `:1694-1695`
- bump I6  `:2670-2671`
- mint fl.walk `test-mint-inngest-bootstrap-tag.sh:1151-1152`

Each emits `fail '<row>:invariant-forge-applied'` (harness-defect rung, zero counted) and
gates the whole arm on the `*_ok` flag. Grep confirms no remaining unchecked
`corrupt_walk_break`/`corrupt_dead_tag` invocation in either suite.

### 4. Force-knob scoped — CLOSED

`CORRUPT_WALK_PROBE_FORCE=skip` is now an env-prefix on the `corrupt_probe_forced_skip`
invocation only: bump `:2963`, mint `:1189`; the `=present` unwired-value exercises are
equally scoped (mint `:1194`, bump `:2986` via `_st_force_bogus`). No standalone assignment
remains — the knob cannot persist past its block and force-skip later rows. The packed-arm
CI leg (`pr-quality-guards.yml:108-110`) does not export the knob, so the captured-exercise
invariant (lib header :66-72) holds in CI.

### 5. Octal-safe charge — CLOSED

`git-corrupt-graph.sh:293` `SKIPPED_ASSERTIONS=$((SKIPPED_ASSERTIONS + 10#$cost))`. The
case guard (`:269-278`) admits all-digit costs including `08`/`09`; empirical run charges
8+9+8+0+12 = 37 correctly (previously `08` would error mid-arithmetic and emit the marker
uncharged — fail-open). Marker literal `printf 'SKIP (loud): %s %s\n'` at `:294` is now
pinned by the probe test's (q) row (verified: the fixed-string pattern matches).

### 6. Stable alert-dedupe body marker — CLOSED

`scheduled-rehearsal-skip-monitor.yml:268` `ALERT_MARK='soleur-skip-persistence-monitor-alert'`
emitted as `<!-- … -->` at `:297` into the shared `body_file` — covers both the comment path
(`:323`) and the create path (`:325-326`). Dedupe searches `"$ALERT_MARK" in:body` (`:271`)
with gh failure fatal (`:273-276`), then a legacy-title transition loop (`:279-293`) whose
three literals I verified against `git log -p` as the complete set of titles this monitor
has used; `"$title"` covers the current one. A marker-carrying issue under any future title
is still found by the body search; a pre-marker issue is found by title. Gap named: GitHub
issue search indexes raw body text including HTML comments, and `in:body` does not cover
comment bodies — correct, since the mark lives in the body. Search-index lag is a
pre-existing dedupe property unchanged by this fix.

### 7. sed harvest bounded to header block — CLOSED

`git-corrupt-graph.sh:157` `sed -n '/^$/q; /^author /p; /^committer /p'` and `:191`
`sed -n '/^$/q; s/^committer //p'`. Verified against a synthetic commit object whose message
body contains `author EVIL <…>` / `committer EVIL2 <…>` lines plus a `gpgsig` continuation
line beginning ` author FORGED-IN-SIG`: only the header-block `author`/`committer` lines are
harvested (the continuation line's leading space fails `^author`/`^committer`, and `/^$/q`
stops the scan before the body). Empty harvest → FATAL (`:158-161`), mirroring the tagger
guard.

## Fix-area sweep for new defects

- **run-all.sh completion discriminator** (`:206`): `[[ "$_suite_class" == killed ]] || echo "=== … done ==="` — done-line suppressed only for signal-killed suites; emitted for ok/failed/unrecognized. Documented residual stands: a non-zero suite still earns the line, bounded because that run is already red. No bypass of the discriminator added.
- **Probe source-2** (`t5-…-7510.sh:289-370`): `--status completed` on both `gh run list` calls; `_pg_list_rc` distinguishes gh failure from an empty window; `g_observed` denominator fixes the mixed-denominator FAIL headline; `_obs_parts` derived from `GUARD_UNITS` (set -u safe). `gh run view --log` output still consumed only by fixed-string greps — no log-derived text reaches echo/issue surfaces.
- **Mint selftest window** (`test-mint-…:1179-1199`): counters restored BEFORE the verdict via `fl_pass`; `st_moved` now asserts `ds==0` on `SKIPPED_ASSERTIONS` (`:444-446`) — a skip charge can no longer hide inside the snapshot window.
- **Roster parity** (bump `:3004-3032`, mint `:2025-2045`): operand extraction covers `'…'`/`"…"`/`$var`/dotted-bare-word; ran verbatim — extraction yields exactly the registered names (g1b.B7/B7c/B7a, g2b.I6, selftest rows; fl.walk + selftest). Per-prefix live-producer loop excludes `selftest` producers; all three prefixes pass.
- **Probe (p)** (`t5-….test.sh:504-512`): per-prefix producer grep now excludes selftest call sites; all three prefixes verified present.
- **Broadened census** (bump `:2994-3001`): verbs extended (mv/chmod/truncate, find -exec both orders, `git.*prune`), scope extended to `plugins/soleur/test/lib/`, `-I` dropped, mid-line `#` no longer exempts. Ran the exact pattern over both dirs: **0 hits** — no self-trip, no false positive on the tree.
- **Packed-arm driver** (`pr-quality-guards.yml:104-110`): env-prefix scoped `SOLEUR_FIXTURE_PACKED=1` on the two corrupt-row suites inside `guard-script-fixture-tests` — packed-leg `SKIP (loud):` markers land in the same job log the probe samples, so a packed-arm skip is counted, not invisible.
- **Dangerous-pattern sweep** over all `+` lines: no new `eval`, `curl`/`wget`, `gh api` write, token echo, `set -x`, or log-derived-string echo. All regex hits are review-doc/comment text.

## Residuals (info — none blocking)

- **N1 — partial `gh run list` failure narrows the sample silently** (`t5-…-7510.sh:290-295`): `_pg_list_rc` is consulted only when `pg_ids` is empty; a failed merge_group list with a successful pull_request list proceeds on the PR-only — i.e., the more forgeable — source with no TRANSIENT marker. Not a regression (previously all failures masked); a one-line stderr note when `$_pg_list_rc` is set but ids exist would close it.
- **N2 — `grep -q` early-exit under `pipefail` reappears** in two added spots: probe test (p) (`:507-510`) and the bump live-producer loop (`:3028-3030`). This is the SIGPIPE/pipefail shape the test file's own header documents and that was just removed from `BUMP_BANNER`. Practically unreachable today (candidate output ≪ 64 kB pipe buffer) and fails conservative (false red, never false green) if ever hit — flagging for consistency, not as a defect.
- **N3 — bad-cost FATAL path echoes raw `row`** (`git-corrupt-graph.sh:272-275`): the case guard runs before `row` sanitization, so an unsanitized row-id is embedded in the fail() message on that path. Call-site literal, echoed not eval'd, reachable only alongside a cost bug — bounded.
- **N4 — `cost=0` still admitted** (`:270` accepts all-digit including `0`): a `corrupt_skip 'x' 0` emits a visible marker charging nothing. Pre-existing, unchanged; the standing cost-parity P2 remains the tracking item.

## Risk matrix (fix area)

| Severity | Count | Items |
|---|---|---|
| Critical/P0 | 0 | — |
| P1 | 0 | prior P1 closed |
| P2 | 0 | — |
| info | 4 | N1–N4 above |
