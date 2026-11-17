# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-09-feat-ship-phase7-required-set-read-plan.md
- Status: complete
- cto_spawns=3 (in planning subagent; 1 earlier epic-routing spawn in go)

### Errors
Scope-out issue for the monitor dedupe refused by the filing gate (inline threshold); CTO re-ruled to document in the plan's Deferred section.

### Decisions
- Dispatch to required-set-report.sh (always exit 0); monitor-pr-checks.sh not refactored.
- Green-dwell rule: 10 counted ticks only where every gate holds; first read at tick 14 for a continuously-green PR (reads 14/24/34).
- Pre-push guards listed (context-sanitize disposition row, plugin-root-anchoring, registrations).

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan, CTO, review agents.

## Review Phase (PANEL_SHA a33f19e0be; tier none; 8 seats)
Seats: githistory, pattern, architecture, security, codequality, agentnative, testdesign, structural. Reports: /var/tmp/review-12476-<seat>.md (githistory delivered in-message only).
dedup: ~55 raw -> 25 unique. No finding is a design fork; all rulings stay inside the CTO decision-challenges rows.

| # | canonical defect (defect-class + root cause) | seat(s) | sev | disposition |
|---|---|---|---|---|
| D1 | fence `*)` arm collapses complete/pending/error/none into "polling on"; ready-run-wait Bound says stop+report after read 3; `error reason=untrusted-ci` is a human handoff; no-marker line prints undefined `state=none`, double-reports when the script printed its own degraded line, names a bare `ci-head-verdict.sh required N` | agentnative F1-F4,F6,F9; architecture F4 | P1 | fix inline (print-only; polling still continues per CTO row) |
| D2 | moved prose keeps "above/below/Trigger line" referents, drops the literal ordinal command, headers claim "verbatim" | githistory F1,F2; architecture F1; pattern 1,2; agentnative F7 | P2 | fix inline |
| D3 | stderr tail on the degraded line bypasses the shared sanitizer | security F2; codequality 2 | P3 | fix inline |
| D4 | `^[0-9]+$` / timeout regex accept non-ASCII digits under UTF-8 | security F4; codequality 1 | P3 | fix inline |
| D5 | RECOVERY lines allowlisted by prefix only | security F3 | P3 | fix inline if closed grammar <=25 lines, else document reliance on the resolver check + pin it |
| D6 | seams: TIMEOUT_S unbounded above, relative TIMEOUT_BIN | security F5 | P3 | fix inline (clamp <=120; absolute path if it contains `/`); no announcement line (same convention as the monitor's seams) |
| D7 | SIGTERM orphans the resolver until its own timeout | security F6; pattern | P3 | wontfix: bounded by `timeout -k 5`, identical to monitor; note in header |
| D8 | shared sanitizer lib single-pass NEL/LS/PS (pre-existing); script header overclaims "second layer" | security F1 | P3 pre-existing | fix the overclaiming comment only; lib defect noted in PR body, no live path (resolver cleans first) |
| D9 | wall-clock claim ("at most 3 x 125 s") ignores the 65 s verdict sample; no-`timeout` branch untested | architecture F2; codequality 3; testdesign F7; structural | P3 | fix inline (reword + PATH-without-timeout row) |
| D10 | header "ALWAYS exits 0" overstated (SIGPIPE) | codequality 4 | P3 | fix inline (wording) |
| D11 | dwell silently disabled when SYNC_SNAP empty; ADR-276 S3 comment says decoupled | architecture F3; githistory F4; structural | P3 | fix inline (document + row) |
| D12 | exit paragraph lacks "re-invoke the poll after recovery"; post-poll header omits required_set | architecture F5 | P3 | fix inline |
| D13 | ready-run-wait "any tick that misses a gate" (gates are sampled every 5th tick) | githistory F3 | P3 | fix inline |
| D14 | plan cites a learning that does not say the floor-price claim | githistory F6 | P3 | fix inline (re-cite) |
| D15 | PR body/title placeholder | githistory F7 | P3 | handled at ship (ready step) |
| D16 | plan SHA stamp af764001ee stale | githistory F8 | nit | skip (historical stamp) |
| D17 | script suite preamble drift: no `export TMPDIR`, no `assert_fixture_dir` | pattern 4 | P3 | fix inline |
| D18 | `rs_qs` alias redundant; RS_AFTER name | pattern 5; architecture F6 | P3 | drop `rs_qs` if verified write-only (also saves bytes); keep RS_AFTER (churn across 2 fences+fixtures+docs) |
| D19 | parity tokens miss `RS_AFTER=10; RS_MAX=3`, `"not_queued OPEN armed "*`, `rs_to` | pattern 6; structural D | P3 | fix inline |
| D20 | `chk` (decides all 221 cases) has no instrument control | testdesign F1 | P2 | fix inline |
| D21 | per-read `rs_state=""` reset unpinned (stubs answer every read identically) | testdesign F2; structural | P2 | fix inline (per-call stub bodies + complete-then-degraded row) |
| D22 | "RECOVERY never executed" has no fence-level control | testdesign F3 | P2 | fix inline (RREAL row with shim log, sentinels, positive control) |
| D23 | marker anchors unpinned in fence and script (decoy last line, `state=bogus`, mid-line marker in RECOVERY) | testdesign F4; structural C (M11,M17) | P2 | fix inline |
| D24 | mid-dwell transitions (armed->disarmed, verdict flips, queued->dequeued) unfixtured | testdesign F5; structural A | P3 | fix inline |
| D25 | `MIN_VERDICTS` slack (1700 vs 1751) | testdesign F6 | P3 | fix inline (ratchet to the measured count after new rows) |
| D26 | helpers `no_ctrl`/`gone`/`calls` lack controls; fallback sanitiser pinned only for CR | testdesign F8; structural C (M1,M2) | P3 | fix inline |
| D27 | `tail -c`/`head -c 160`/inner `</dev/null` removable at green | testdesign F9; structural C (M6) | P3 | fix inline |
| D28 | VERDICT_OK conjunct unpinned in the new sample gate; verdict sample keeps running (<=60 s each) after the 3-read cap | structural A | P3 | fix inline (add `rs_reads < RS_MAX` to the sample gate; rows) |
| D29 | pointer to monitor-hygiene.md sits after the fence, not at the arming sites (merge->deploy protocol, Monitor uses) | agentnative F8 | P3 | fix inline (one-line pointers) |
| D30 | no `timeout` on stock macOS -> read always degraded | codequality | P3 | wontfix: documented degrade |

structural-cause roll-up: (1) fence `*)` arm collapses states while per-state actions live only in ready-run-wait.md (D1,D11,D12,D13); (2) moved/mirrored prose not re-anchored (D2,D29); (3) fixture stubs answer every call identically within a row, so changed-answer and decoy-answer behaviour is invisible (D21,D23,D24,D28); (4) verdict-owning helpers lack controls (D20,D26); (5) sanitising contract not applied uniformly at the output chokepoint (D3,D4,D5,D8).
Byte constraint: ship/SKILL.md is 38 bytes under its ceiling (273955); every addition must be offset by moving prose to references.

## Operator Constraints
- Ref #9927 only (never Closes); PR body Closes #11544.
- Guard 1 evidence = merge_group/dispatch runs only; state run kind and leg.
- No .github/workflows edits; no sleep; Monitor for polling; bare gh pr merge; separate git add / git commit.
- Operator-held items untouched. Operator notes only on #12272.
