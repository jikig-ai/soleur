# Fix brief — PR #10953 panel findings (11 seats, 2026-10-23)

Seat reports live beside this file in `review/`. Read them for anchors; implement every item
below. PANEL_SHA=5403f5b30e.

## P1 — all must fix

1. **Mint selftest verdict inside snapshot window** — `test-mint-inngest-bootstrap-tag.sh:~1186-1192`
   emits pass/fail inside the snapshot block then restores `PASS/FAIL/SKIPPED_ASSERTIONS`: a
   machinery failure prints FAIL but exits 0 (fail-open), and the floor comment's "+1" is false.
   Fix like bump's rows: restore only `SKIPPED_ASSERTIONS`; verdicts land on live counters
   (block contributes its real count).
2. **`_corrupt_maybe_repack` ignores repack rc** (lib) — packed arm silently degrades to loose
   on repack failure, still reporting green. Check the rc; repack failure = harness FAIL.
3. **`corrupt_skip` sanitizer too narrow** (lib ~:236) — strips CR/LF only; C0 controls, \x7f,
   U+2028/U+2029 pass through (log-injection rule parity). Extend the strip — U+2028/U+2029 as
   \uXXXX escapes, NEVER literal chars (Edit tool mangles them to spaces).
4. **Forge-helper rc unchecked at all 5 call sites** — a failed forge leaves a healthy graph →
   probe reads contract-absent → SKIP charges a harness defect into the bounded skip budget.
   Check `corrupt_walk_break`/`corrupt_dead_tag` rc at each site; failure = harness-bug FAIL,
   never SKIP (B7a is incidentally covered; B7/B7c/I6/fl.walk are not).
5. **`CORRUPT_WALK_PROBE_FORCE=skip` persists globally** (bump ~:2941, mint ~:1178) — set on a
   standalone line inside `{ }` it leaks past the block and can force-skip any later row.
   Scope it: env-prefix the single invocation or unset before block end.

## P2 — fix all substantive items

6. **Packed arm has no CI driver** (6 seats) — `SOLEUR_FIXTURE_PACKED` is manual-only; the flake
   class this PR closes stays unexercised in CI. Wire it: add a step to the
   `guard-script-fixture-tests` job in `pr-quality-guards.yml` running
   `SOLEUR_FIXTURE_PACKED=1 bash .github/scripts/test/run-all.sh` (or the scoped two suites if
   run-all takes a filter — check first; prefer the narrowest correct scope).
7. **Roster parity blind spots** — greps only single-quoted `corrupt_skip 'x'` in `"$0"`. Accept
   `'`/`"`/unquoted names; require ≥1 producer per registered prefix EXCLUDING captured-selftest
   lines (mark/detect them); third-suite call sites are a documented residual (comment).
8. **Discriminator keys on start banner** — `=== test-*.sh ===` proves enumeration, not
   completion; a killed suite reads observed+0-hits. Make `run-all.sh` emit a completion banner
   (`=== <basename> done ===`) after each suite and key the per-suite discriminator on it.
9. **Mixed-denominator FAIL headline** (probe source-2) — hits counted over g_sampled but accrue
   per-observed-log; denominators per source.
10. **Octal-unsafe charge** — `cost=08` passes numeric guard then `$((+08))` errors → marker
    emits, charge lost. Use `10#$cost` in the charge arithmetic.
11. **I6 probe stricter than SUT** — SUT decides on rc∉{0,1} alone; non-empty-stderr probe
    over-skips a silently-failing git that still refuses. I6 probe contract = rc∉{0,1} OR
    stderr non-empty.
12. **Monitor alert dedupe breaks on title rename** — dedupe on a stable body marker/label, not
    the (new) title; check open issues across title variants.
13. **author/committer sed harvest** (lib) — bound to the commit header block (stop at first
    blank line), never scan the message body.
14. **Probe budget comment stale** — ~43 calls ≈51% of `timeout 600` (measured ~305s); refresh
    the "20 multi-MB logs" comment in the workflow and the probe header.
15. **Census coverage** — broaden verb set (`mv`, `chmod`, `truncate`, `find -exec`, `gc
    --prune`), tolerate `#`-separated paths, extend scope to `plugins/soleur/test/lib/` (the lib
    itself is outside the current census dir); document in a comment that indirection/spelling
    tricks are a residual (construction-census ≠ deletion-census).
16. **Probe doc drift** — header/`Close criteria`/exit-table describe only the
    infra-validation source; update for the second source.
17. **`pg_ids` no status filter** — add `--status` filter so partial/queued runs don't count as
    observed.
18. **`unit_obs[bump]/[mint]` literal keys under `set -u`** — fix (architecture P3).
19. **Forced-vs-organic marker** — forced skips emit identical markers; add a lib-header note
    that forced runs must only ever be captured exercises, and probe verdict text labels source.
20. **Plan `## User-Brand Impact`**: add one scope-out line for #10956's two deferred sites.
21. **`SKIP (loud):` literal pin** — probe-side test asserts the lib emits the exact marker
    literal (so an edit to the literal is a RED, not silent unobservation).

## P3 — cheap, fix in passing

22. Nonce literal triplicated → one constant. 23. 2× new SC2034 → fix or comment.
24. Census regex unescaped `.` + dead `rm -rf` alt → correct. 25. merge_group crowds out
    pull_request legs (pg_ids head -20 ordering) — note in comment or interleave.
26. Banner-discriminator spoofable (bounded: can't hide markers) — comment only.
27. gh-failure-vs-empty-window conflation in probe — distinguish TRANSIENT reasons if cheap.

## Verify before commit

`bash -n` all touched files; shellcheck -S warning; re-run both suites, the probe .test.sh,
run-all.sh scoped run; re-run AC4 (packed) and AC5 (forced-skip) arms. `git -C` for all git ops;
never git stash; bound outputs. Commit as `review: <summary> (P1)` fix commits.
