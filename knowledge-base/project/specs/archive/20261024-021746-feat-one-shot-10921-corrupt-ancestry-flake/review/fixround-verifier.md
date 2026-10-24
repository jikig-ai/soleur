# Fix-round verification — PR #10953 (fresh-eyes pass)

Range verified: `git diff 5403f5b30e..HEAD` (4 fix commits, 2026-10-23). Method: read every
non-report hunk, `bash -n` all six touched shell files, `shellcheck -S warning -x` (clean) and
`-S info` base-vs-HEAD delta, empirical re-run of the new census grep and the roster
extraction, probe verdict-order read. No git writes; scratch under mktemp only.

## Per-finding verdicts — all 27 CLOSED

P1
1. Mint selftest verdict inside snapshot window — CLOSED. `fl_pass` flag computed inside the
   window, counters restored at :1205, verdict emitted on live counters; floor re-derived
   673→674 with the +1 explained. Fail-open eliminated.
2. `_corrupt_maybe_repack` rc — CLOSED. `repack || { FATAL; return 1; }`, both forge helpers
   propagate (`|| return`).
3. `corrupt_skip` sanitizer — CLOSED. `[[:cntrl:]]` (covers C0 + \x7f) + `$'\u2028'`/`$'\u2029'`
   as escapes, no literals; row-id now sanitized too (extra hardening).
4. Forge rc at 5 call sites — CLOSED. B7:1624, B7c:1667, B7a:1694, I6:2670 (bump),
   fl.walk:1151 (mint) all `|| { fail '*:invariant-forge-applied' ...; *_ok=0; }`, fail-only
   zero-counted, never routed to skip. Verified no other call sites exist.
5. `CORRUPT_WALK_PROBE_FORCE=skip` scope — CLOSED. Env-prefix form at bump:2963, mint:1189;
   the `=present` probes are also env-prefixed (bump:2986, mint:1194). No standalone
   assignment remains.

P2
6. Packed-arm CI driver — CLOSED. `pr-quality-guards.yml` guard-script-fixture-tests job adds
   a step running the two corrupt-row suites under `SOLEUR_FIXTURE_PACKED=1` (narrowest scope:
   run-all takes no filter — correct call).
7. Roster parity — CLOSED. Extraction accepts `'x'`/`"x"`/`$var`/bare-dotted; `$var` and
   non-prefixed names fail deliberately; per-prefix ≥1 non-selftest producer enforced
   (bump loops g1b./g2b., mint fl.); third-suite residual commented. Empirical extraction on
   both suites yields exactly the registered names.
8. Done-banner discriminator — CLOSED. run-all.sh:204 emits `=== <basename> done ===` for every
   non-killed class; probe GUARD_UNITS and the fed-log test key on the new literal.
9. Per-source denominators — CLOSED. `g_observed` counts logs with ≥1 unit discriminator;
   FAIL headline reports hits/observed with sampled in parentheses.
10. Octal charge — CLOSED. `SKIPPED_ASSERTIONS=$((SKIPPED_ASSERTIONS + 10#$cost))`.
11. I6 rc∨stderr — CLOSED. Skip iff `rc∈{0,1} AND stderr empty`; rc∉{0,1} OR non-empty stderr
    exercises the row — matches SUT acceptance.
12. Alert dedupe stable marker — CLOSED. Body marker `soleur-skip-persistence-monitor-alert`
    via `in:body` search + legacy-title transition loop incl. current title; gh failure still
    fatal, never falls through to create.
13. sed harvest header-bound — CLOSED. `/^$/q` in both corrupt_walk_break (plus new
    empty-harvest FATAL) and corrupt_dead_tag.
14. Stale budget comment — CLOSED. Workflow comments refreshed (~43 calls, ~305s of 600s);
    probe header carried no stale volume comment and was updated for source 2 anyway.
15. Census breadth — CLOSED. verbs += mv/chmod/truncate/find -delete/-exec/`git *prune`;
    `[^#]*`→`.*`; scope += plugins/soleur/test/lib/; residual documented. Empirical grep over
    both dirs: zero hits (no self-trip).
16. Probe doc drift — CLOSED. Header, Close criteria, and exit-table all describe both
    sources.
17. `pg_ids` status filter — CLOSED. `--status completed` on both `gh run list` calls.
18. `unit_obs[bump]/[mint]` literal keys — CLOSED. PASS line derives tallies from GUARD_UNITS.
19. Forced-vs-organic — CLOSED. Lib header requires captured-only forced runs; every forced
    skip reason is labeled `forced-divergence exercise (CORRUPT_WALK_PROBE_FORCE=skip)`.
20. Plan scope-out — CLOSED. `## User-Brand Impact` gains the #10956 two-site scope-out line.
21. `SKIP (loud):` literal pin — CLOSED. Probe test section (q) greps the exact printf literal;
    floor raised 27→28, itemised.

P3
22. Nonce constant — CLOSED. `CORRUPT_DEAD_NONCE` single source; used by dead_oid and both
    suite selftests.
23. 2× SC2034 — CLOSED. Info-level delta vs base: mint 1→0, bump 1→0, no new instances; lib's
    pre-existing SC2317 unchanged.
24. Census regex — CLOSED. `\.git` escaped properly via `\.git(/objects)?(/|[^[:alnum:]_.-]|$)`
    (rejects .gitignore/.git-credentials suffixes); dead `rm -rf` alt folded into verb list.
25. merge_group starvation — CLOSED (documented-deliberate comment, CTO ruling cited).
26. Banner spoofable — CLOSED (bounded-risk comment; cannot hide markers).
27. gh-failure-vs-empty — CLOSED. `_pg_list_rc` separates "gh run list failed" from "no runs"
    TRANSIENT reasons.

## Defects introduced — none blocking; two cosmetic residuals

- R1 (cosmetic): `corrupt_probe_forced_skip` emits fail()+rc0 for UNWIRED knob values, so a
  `CORRUPT_WALK_PROBE_FORCE=present` run takes the forced-skip branch whose reason now says
  "(CORRUPT_WALK_PROBE_FORCE=skip)" — mislabels the mechanism in the marker text. The bogus
  value still produces a loud FAIL first, so coverage is unaffected.
- R2 (accepted residual): the new packed-leg step invokes the two suites directly, bypassing
  run-all.sh's entry-point GIT_* scrub and INCIDENTS_REPO_ROOT sandbox. Harmless on GHA (the
  scrub targets lefthook-exported vars; the fixture-env tripwire fails loud if any are set;
  incident telemetry drops silently or writes to the ephemeral checkout).

## Sanity results

- `bash -n`: all six touched shell files OK.
- `shellcheck -S warning -x`: zero diagnostics on all six.
- `shellcheck -S info` base-vs-HEAD delta: only change is the two SC2034 removals.
- Census grep over `.github/scripts/test/` + `plugins/soleur/test/lib/`: zero hits.
- Roster extraction on both suites: only registered prefixes (g1b./g2b./fl.).
- `set -e` semantics checked: `[[ cond ]] && fl_pass=1` does not exit on false (and the suites
  run `set -uo pipefail` anyway). Probe tail ordering verified: FAIL dominates TRANSIENT.
