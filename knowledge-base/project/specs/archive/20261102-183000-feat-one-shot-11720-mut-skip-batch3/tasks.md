# Tasks — feat-one-shot-11720-mut-skip-batch3 (#11720 batch-3, final batch)

Plan: knowledge-base/project/plans/2026-11-02-chore-mut-skip-guard-batch3-plan.md (authoritative — incl. "Port Contract — per-file obligations").

## Phase 1 — bwrap-probe-rollback + faithful-canary-sandbox
- [ ] 1.1 Phantom sweep both files: `<<[-]SQL` in awk lines (bwrap :74, fcsb :75), `<<\x2dSQL` in python strings (bwrap :279/:360/:362/:424, fcsb :372); zero `<<-`-opener matches remain.
- [ ] 1.2 Port convention per file: `sql_local`/`res_block`/`param` + canon compare, `_red_verdict`/`mutate_red`/`mutate_green`/`mutate_floor_red`, decoy rows, `want=wrong` control, pristine control kept, `[note] MUT_SKIP active`.
- [ ] 1.3 Constructible floor tails (PRESENCE_ROWS/MUT_ROWS recomputed from ported counts; NOT today's 25+21 / 37+10 literals); floor/ledger `if`s multi-line, exit 1; instruments exit 2.
- [ ] 1.4 Add `BWRAP_GUARD_IV` / `FCSB_GUARD_IV` axes + `IV)` dispatch arms + seam-check block (IV_CODE literal-absence + run-line registration + IV mutation rows). fcsb keeps its `SELF` axis.
- [ ] 1.5 Both suites green; `MUT_SKIP=1` inner runs green; `mutate_floor_red` grades RED.

## Phase 2 — ghcr-blocked + web-nic-guard-unpinned-url
- [ ] 2.1 Phantom sweep (ghcr :90 awk + :420/:501/:503/:549/:557/:564 python; web-nic :84 awk + :296/:362 python).
- [ ] 2.2 `MUT_ROWS_EXPECTED`→`MUT_ROWS` normalization (keep `MUT_ROWS_RUN` conservation ledger + its exit 2); constructible floors replacing `[ -z ] &&` rebinds; exit-class conversion.
- [ ] 2.3 Keep existing step-anchored registration pins (ghcr :309-323, web-nic :239-255); ADD `GHCR_GUARD_`/`UNPINNED_GUARD_` + `MUT_SKIP` literal-absence seam rows + IV mutation rows (env: insertion, GUARD literal, dropped run line).
- [ ] 2.4 Battery port (`_red_verdict` + fragments + `want=wrong` + `mutate_green` TF-scoped); decoy rows (ghcr already has M15/M27 metadata decoys — extend to the five issue classes).
- [ ] 2.5 Both green + inner + floor RED.

## Phase 3 — inngest-step-524 (partial-generation port)
- [ ] 3.1 `mutate_red` signature gains `$4` expect-fragment + `$5` want; `_red_verdict` replaces inline `case "$rc"`; `>/dev/null`→`$olog`; explicit per-axis env arms → `env "SPEND_GUARD_${which}=$copy"` indirection.
- [ ] 3.2 `_floor=74`/`_floor=50` literals → `PRESENCE_ROWS`/`MUT_ROWS` + constructible window (discovery-coupled presence pinned to current real count; <3-discovery refusal stays its own pin); exit 2→1 on floor/ledger.
- [ ] 3.3 `SPEND_GUARD_IV` axis + `IV)` arm + seam block; H524/HBURN (:337) + s1.tf printf (:398) compose `<<-` at runtime (no literal in scanned text); python-regex `<<-SQL` at :126 → `\x2d`.
- [ ] 3.4 S1/C1 controls: fold into `mutate_green`/deliberate equivalents or keep as-is with justification; green + inner + floor RED.

## Phase 4 — sandbox-alerts
- [ ] 4.1 Full port (canon + block pins over .tf surface; DISP/CLS .ts emitter pins stay whole-line; `eval_row` evaluator preserved).
- [ ] 4.2 `SANDBOX_ALERTS_GUARD_IV` + `IV)` arm + seam block; phantom sweep (:77 awk, :364/:480/:482/:486 python); floor conversion; exit-class fix.
- [ ] 4.3 Green + inner + floor RED (30s suite — serial-leg watch item).

## Phase 5 — meta-guard promotion
- [ ] 5.1 `bash scripts/guard-vacuity-floor.test.sh`: all six classify FIRES (not CONSTRUCTION, not invisible).
- [ ] 5.2 Six `PROMOTED_FILES` entries at the LIVE :1096 site (escaped dots) + grounds comments each; `MIN_FIRING_SUITES` 65→71 with per-file comment convention.
- [ ] 5.3 Counters diff vs baseline: covered 387→393, fires 370→376, deferred 47→47 (def_fires 31, def_construct 16 unchanged). Any other movement is a finding.

## Phase 6 — rebaseline + measure
- [ ] 6.1 All six suites + `MUT_SKIP=1` inner green; `git diff --quiet $(git merge-base HEAD origin/main) -- registry-clientip-not-rfc1918-alert.test.sh inngest-cutover-flip-silent-alert.test.sh` empty (AC5).
- [ ] 6.2 Measure `deploy-script-tests-fixed` leg on-branch; conditional `timeout-minutes` bump at infra-validation.yml:854 only if near ceiling.
- [ ] 6.3 affected-suites + meta-guard green; `lint-shell-capture-exit` baseline check; zero `| grep -q` pipes introduced; no `env -u` anywhere.
