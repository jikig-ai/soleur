# Review — git-history-analyzer — PR #10953 (fixes #10921)

Seat: `soleur:engineering:research:git-history-analyzer` · Date: 2026-10-23
Worktree: `.worktrees/feat-one-shot-10921-corrupt-ancestry-flake`
Diff basis: `git diff origin/main...HEAD` (three-dot; merge-base `eb7df4de6e`, 2026-10-23 — branch is current, no main-side work on the touched files post-dates the fork point that this diff would silently revert).
Verdict: **SHIP** — no P0; one P1; six P2. All four CTO settled rulings are honored; nothing contradicts them.

## Verified claims (checked against the tree, not the diff's word)

- **Root-cause story is real.** The old fixture corrupted by `rm -f "$F_REPO/.git/objects/<fanout>"` at five sites across two suites (g1b.B7, g1b.B7c, g1b.B7a, g2b.I6 in `test-bump-inngest-bootstrap-pin.sh`; fl.walk in `test-mint-inngest-bootstrap-tag.sh`) — matches the lib header's #7849 census claim exactly. `rm -f` fails open on packed stores; the replacement writes objects whose `parent`/`object` fields name a never-persisted sha — layout-immune by construction, matching CTO Arm C.
- **SUT probe contracts mirror the real acceptance conditions.** `bump-inngest-bootstrap-pin.sh:294` and `mint-inngest-bootstrap-tag.sh:305` die on ANY non-empty `walk_err` from `tag --merged` — the rows' "non-empty walk stderr" probe is exactly the SUT's acceptance, not a stricter proxy. `build-inngest-bootstrap-image.yml:212–219` keys `could not decide` on merge-base rc outside {0,1} — I6's probe adds a non-empty-stderr requirement on top (see P2-5).
- **Declared skip costs check out.** g1b.B7 = 8 (1 `precondition-merged-set-empty` + 7 `assert_refused`), g1b.B7c = 8, g1b.B7a = 9 (`assert_excluded` = exit+result+target-merged-max+off-main-never-resolved+`assert_all_pins`(3)+gh-not-called+no-bump-branch), g2b.I6 = 3, fl.walk = 3. `SKIP_CAP=28` = full-skip cost; floor arithmetic 699−5+2=696 and the mint re-derivation comment are self-consistent (P2-3 caveat).
- **The standing census is clean and can't self-match.** Ran the exact census pattern against `.github/scripts/test/` — zero hits; the `.git/objects/` literal lives in `_census_obj` so the check's own source can't trip it. The two out-of-scope same-shape sites named in the header are real and match #10956's description verbatim: `scripts/ci-pr-selection.test.sh:432`, `apps/web-platform/infra/workspaces-luks-loopback.test.sh:868`. Issue #10956 is OPEN.
- **Monitor plumbing is coherent.** `run-all.sh:176` prints `=== $(basename "$t") ===` per suite — the probe's per-suite discriminators are the real banners. `guard-script-fixture-tests` in `pr-quality-guards.yml` runs `run-all.sh`; suite stderr reaches the job log, so `SKIP (loud): g1b./g2b./fl.` on stderr is monitor-visible. `scheduled-rehearsal-skip-monitor.yml:125` already exports `GH_TOKEN`; the probe keeps its 0/1/2 contract (FAIL dominates, per-source `observed≥1`, TRANSIENT never pooled).
- **Settled rulings honored.** Forged-oid over repack-aware rm ✓ (all five `rm -f` sites deleted); only walk-contract skip-eligible ✓ (B7a's `--merged` silent-drop contract was separately CTO-ruled and is documented at the call site); probe extended in this PR ✓ (second run-source + fed-log rows l–p); tier `aggregate pattern` consistent with a CI-only diff — AC10 holds, nothing under `.github/scripts/` outside `test/` is touched.
- **Selftest-poisoning is closed.** Every exercised `SKIP (loud):`/`::warning::` in both suites' selftests is captured to a file; `st_run` and the mint snapshot driver restore `SKIPPED_ASSERTIONS`; the tail `grep -qF 'TOTAL=$((PASS + FAIL + SKIPPED_ASSERTIONS))' "$0"` guards the fold.

## P0 — none

## P1

1. **`_corrupt_maybe_repack` swallows repack failure — a fail-open in the one arm that exists to prove packed-layout immunity** (`plugins/soleur/test/lib/git-corrupt-graph.sh`, `_corrupt_maybe_repack`). Under `SOLEUR_FIXTURE_PACKED=1`, a failed `git repack -adq` (disk, perms, or a prior forge's reflogged dead parent — the exact hazard the header documents) leaves the store loose; the helper continues, the forge proceeds, and the row reports PASS — a silently degraded arm, the same defect class this PR eliminates. Fix: `git -C "$1" repack -adq || { printf 'FATAL: packed-arm repack failed in %s\n' "$1" >&2; return 1; }` so a failed arm-setup fails the row (or the suite) loudly rather than reporting a green loose-store run under a packed-store label.

## P2

1. **Neither env knob is CI-wired.** `SOLEUR_FIXTURE_PACKED` and `CORRUPT_WALK_PROBE_FORCE` appear in no file under `.github/workflows/` (verified by grep). AC5's forced arm *is* standingly exercised — both suites' selftests set `CORRUPT_WALK_PROBE_FORCE=skip` inline — but AC4's packed arm has no automated exercise at all; a lib regression in the repack path would go unnoticed until a manual run. If deliberate, the lib header should say the arm is manual-only.
2. **Monitor alert-title rename breaks dedupe against still-open old-titled issues.** `scheduled-rehearsal-skip-monitor.yml` dedupes open issues by `in:title` (line ~263); titles changed (`the rehearsal skip-persistence probe…` → `the skip-persistence probe…`), so an old-titled alert still open at first new-style filing yields a duplicate. One-time, self-limiting — note only.
3. **Mint `MIN_ASSERTIONS=665→673` rests on a "floor drifted 8 below real count" re-derivation not verifiable without running the suite.** The arithmetic narrated (−1 precondition, +1 selftest, net 0 vs the corrected real count) is self-consistent and the floor is self-revealing if over-set (TOTAL < floor → loud FAIL), so worst case is a red run, not silent coverage loss.
4. **`pg_ids` starves `pull_request` legs.** Source 2 concatenates merge_group ids before pull_request ids then `head -n 20`; ≥20 merge_group runs means pull_request contributes nothing. Consistent with the CTO dissent (merge_group is the required leg) — recorded for completeness, not a defect.
5. **I6's probe is stricter than the SUT's acceptance.** The shipped body keys `could not decide` on merge-base rc alone (stderr discarded); the probe requires rc∉{0,1} AND non-empty stderr. A git that exits 128 silently would produce a counted skip despite the row's assertions all passing — over-skip, loud direction, bounded by cap+monitor. Deliberate per the comment; flagged as a known asymmetry.
6. **Census regex blind spots.** `[^#]*` cannot see a deletion whose `.git/objects/` path sits after a `#` on the same line, and (intended conservatism) it will flag *comments* mentioning `rm -f .git/objects/`. Narrow; the two known out-of-scope sites are tracked in #10956.

## History archaeology (deliverable per seat definition)

- **Timeline.** The `rm -f .git/objects/<fanout>` corruption spelling entered with the vinngest feature line (`a486967a0a` auto-mint era, #9079) and spread to five sites before anyone repacked a fixture store. Prior hardening in the same surface: #8782 (`--merged` walk-stderr refusal — the SUT contract these rows validate), #10786 (`SOLEUR| relay` — made the rehearsal markers log-visible at all), #10916 (streak artifact for this monitor). #10921 is the first measured packed-store failure of the construction itself.
- **Pattern.** This repo's recurring failure class is *fail-open instruments*: the 2026-08-19 SIGPIPE/`pipefail` probe inversion (comment preserved inline), the `_transient` leading-zero octal collapse (comment preserved), the dedupe `--state all` + open-filter mismatch (comment preserved). The PR continues the established remediation shape — construction-invariant FAIL rung above a counted-skip rung above the row — consistent with ADR-188's ownership axis.
- **Contributors.** Single-author branch (feat-one-shot pipeline commits, `fix(ci):`/`feat(ci):` conventional-commit titles, `(#10921)` trailers throughout — matches repo convention).

## Contract compliance

Report-only: no git writes (two hook-blocked scratch-repo plumbing attempts were abandoned, not routed around). No full test gate run. All command output bounded. `gh` used read-only (issue/PR views).
