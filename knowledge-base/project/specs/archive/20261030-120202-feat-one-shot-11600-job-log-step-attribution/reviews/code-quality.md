# Code Quality Review — PR #11603 (feat-one-shot-11600-job-log-step-attribution)

**Seat:** soleur:engineering:review:code-quality-analyst
**Diff reviewed:** `git diff origin/main...HEAD` in the feat-one-shot-11600 worktree
**Scope:** `scripts/followthroughs/web-first-deploy-10585.sh` (+94/−~10), its `.test.sh` (+143), `followthrough-convention.md` (+16 runbook section), KB artifacts (plan, tasks, decision-challenges, session-state).

## Executive Summary

- **Smells by severity:** 0 High, 1 Medium, 8 Low/Informational.
- **Overall quality: 8.5/10.** The extraction of `emit_rows` is the correct Fowler "Extract Method + single chokepoint" play — it removes a real drift vector rather than adding abstraction for its own sake. The region-slice awk is claimed "verbatim" from `git-data-boot-poll-8178.sh:204-207` and that claim is accurate (byte-identical modulo the `ps` variable's source). Suite runs green: **69 passed / 0 failed**; shellcheck clean at `-S warning` on both files.
- **Top 3 items:** (1) the `recovery_cause` "no ##[group]Run header at or after" message mislabels the empty-region arm; (2) `usrc()` is a prescribed-but-never-invoked dead builder; (3) the jobs `--jq` now carries the step-selector literal twice in one expression.

## Verification performed (positive checks, all clean)

- **Shell correctness under `set -uo pipefail` (no `-e`):** the recovery block's `awk`/`emit_rows`/`grep -qE` calls sit inside `if`/`elif` conditions or assignments — a failed command substitution can only produce an empty `trail`, which lands fail-safe on the tripwire (exit 3 for success jobs, no obligation otherwise). No unguarded expansions; `recovery_cause` is reset per job iteration (`recovery_cause=""` inside the `while read` loop). `${jstart:0:19}` is only expanded inside the ISO-regex-gated branch — safe against hostile JSON.
- **errexit-in-condition:** `run_probe`'s `... || rc=$?` and `check`'s `{ ... || grep -qF ...; }` groups are correct; no `! grep` membership-test conflation anywhere in the diff.
- **`emit_rows` semantic equivalence:** `awk -F'\t' 'index($2,step)==1{print $3}' | emit_rows` is behavior-identical to the old inline filter for every input shape, including degenerate `<ts>`-only and empty-`$3` lines (both emit `\t\n`, ignored downstream). One inherent asymmetry noted: region lines preserve tabs embedded in content while named-path `$3` truncates them — immaterial because both downstream anchors are `^`-anchored on field 2.
- **BOM/CR strip:** `log=${log//$'\r'/}` + `log=${log//$'\357\273\277'/}` — correct order, correct global `//` form (one mark per section), placed before the named-path anchor so it also fixes the latent BOM-prefixed-`ts_to_epoch` edge the comment names. `jobs_tsv` `// "-"` correctly maps `started_at: null` / absent `steps[]` / empty array to `-`, which the `=~` gate then rejects into the `no usable started_at` arm.
- **Comment/code drift:** header ALGORITHM/RESIDUALS/exit-semantics updates match the code; `ulog` builder comment's "mutation rows 2-3" cross-reference resolves to the plan's Guard Contract rows 2–3; the "8178's exact idiom" / "verbatim" claims verified against `git-data-boot-poll-8178.sh:202-207`.
- **Fixture fidelity:** `ulog` reproduces the real document shape (bare `Set up job` head, BOM'd prelude before `started_at`, BOM'd trail header at `started_at`, BOM'd bound header). `ULOG_EARLY_HDR`/`ULOG_NO_BOUND` knobs drive the two must-cover arms.
- **Exit-code vocabulary:** the property sweep covers all 45 driven runs; every new path lands in {5,2,3,78}.

## Detailed findings

### F1 — Medium — Misleading diagnostic on the empty-region arm

- **Location:** `scripts/followthroughs/web-first-deploy-10585.sh:311-312`
- **What:** `region=$(awk ...)` returns empty in TWO distinct situations, but only one cause string exists: `"; no ##[group]Run header at or after ${jstart:0:19} in an attribution-expired log"`. The second situation — a header at/after `started_at` DID match but was the file's last line, so it opened and bound nothing (exactly what the suite's `ULOG_EARLY_HDR=1` arm produces: the `Post job cleanup` header opens `started` at EOF) — reports "no header at or after X" while a header at/after X demonstrably existed.
- **Impact:** the appended cause is the only thing distinguishing failure modes in a CANNOT ESTABLISH line; a mislabeled cause sends the operator toward "the runner never emitted headers" when the truth is "the trail step's header predates `started_at`" (clock-skew or wrong-step selection). The verdict itself is unaffected.
- **Recommended refactoring:** split the empty-region cause — e.g. track whether a header matched (`matched=1` in the awk, or a second awk pass) and emit "the first ##[group]Run header at/after X bound an empty region" vs "no header at or after X". Risk: Low. Dependencies: none.

### F2 — Low — Dead fixture builder `usrc()`

- **Location:** `scripts/followthroughs/web-first-deploy-10585.test.sh:157`
- **What:** `usrc` (ANSI-echoed line under UNKNOWN STEP) is defined and documented but never invoked — case 18's echoed-ready arm inlines the payload as a `$'\033[36;1m…'` argument to `ulog`, which produces the identical byte shape through `ul`'s printf.
- **Impact:** dispensable code a reader must reconcile against the plan (task 1.2 prescribes it) — or silently unused machinery that a future case might call believing it is already exercised.
- **Recommended refactoring:** either drop `usrc` + its comment mention, or convert case 18's inline payload to use it (keeps the builder live). Risk: Low. Dependencies: none.

### F3 — Low — Step-selector literal duplicated inside the `--jq` expression

- **Location:** `scripts/followthroughs/web-first-deploy-10585.sh:268`
- **What:** `[.steps[]? | select(.name | startswith("Surface fresh-host Sentry breadcrumb trail"))]` is written twice in one `--jq` program (once for `.conclusion`, once for `.started_at`).
- **Impact:** a step-name edit that lands in only one copy silently selects `conclusion` and `started_at` from different steps — the same drift class this PR removed for the emit filter, at smaller blast radius (adjacent, greppable).
- **Recommended refactoring:** `([.steps[]? | select(.name | startswith("…"))][0] // {}) as $s | "\(.id)\t\(.conclusion)\t\($s.conclusion // "absent")\t\($s.started_at // "-")"`. Risk: Low — the suite's stub evaluates the probe's own `--jq`, so a malformed rewrite fails green. Dependencies: none.

### F4 — Low — Double punctuation in the tripwire line

- **Location:** `scripts/followthroughs/web-first-deploy-10585.sh:334` (`unmeasured trail.%s`) + cause strings at 312/316/322/326 (each begins `; `)
- **What:** a populated `recovery_cause` renders `…unmeasured trail.; no ##[group]Run header…` — `.` immediately followed by `;`.
- **Recommended refactoring:** drop the trailing `.` from the format (the cause strings are self-terminating) or strip the leading `;` and join explicitly. Risk: Low; the suite greps `zero parseable`, which is unaffected.

### F5 — Low — Runbook `(#8262)` reads as the wrong script's citation

- **Location:** `knowledge-base/engineering/operations/runbooks/followthrough-convention.md:325-326`
- **What:** "adapted in `web-first-deploy-10585.sh` (#8262)" — #8262 is the PR that shipped the 8178 countermeasure (per `git-data-boot-poll-8178.sh:2` and the plan), not a reference attached to this probe (#10585 / tracker #11583 / fix #11600). The cite is correct in substance (tasks.md 3.1 asked for it) but sits adjacent to the wrong noun.
- **Recommended refactoring:** "adapted in `web-first-deploy-10585.sh` (this fix, #11600; proven at #8262)" or move `(#8262)` inside the `git-data-boot-poll-8178.sh` mention. Risk: Low. Dependencies: none.

### F6 — Low — `ulog` local `l` shadows the `l()` builder

- **Location:** `scripts/followthroughs/web-first-deploy-10585.test.sh:170` (`local base epoch pre post l hdr_ts`, `for l in "$@"`)
- **What:** the loop variable shares its name with the named-attribution line builder `l()` used throughout the suite. Harmless (never invoked inside `ulog`) but forces a double-take.
- **Recommended refactoring:** rename to `line`/`payload`. Risk: Low. Dependencies: none.

### F7 — Low/Informational — Anti-vacuity floor is now zero-headroom

- **Location:** `scripts/followthroughs/web-first-deploy-10585.test.sh:636`
- **What:** floor raised 30 → 69 and the suite's actual baseline is exactly 69 (verified by running it). The previous floor sat ~30 below its baseline; the new one trips on ANY single-check removal.
- **Impact:** this is arguably the intended hardening (deleting coverage requires a deliberate floor edit), but it also means consolidating two overlapping checks requires touching the floor — worth a one-line comment stating the floor is pinned to the baseline, not a round estimate.

### F8 — Low/Informational — Fixture fidelity nits in `job()`

- **Location:** `scripts/followthroughs/web-first-deploy-10585.test.sh:133-139`
- **What:** (a) several cases pass `$(ts …)` — `…T10:00:00.0000000Z` — as `started_at`; the real API emits second precision (no fraction). The probe tolerates it (`${jstart:0:19}` slices), so coverage isn't weakened, but the fixture over-fits the slice. (b) In the `-` arm, `completed_at` is also emitted `null` on a nominally-completed step — unfaithful to the API, but the field is never consumed.
- **Recommended refactoring:** none required; if touched, emit `completed_at` as a real timestamp in the `-` arm. Risk: Low. Dependencies: none.

### F9 — Informational — Region-awk duplication (deliberate)

- **Location:** `scripts/followthroughs/web-first-deploy-10585.sh:307-310` ≡ `git-data-boot-poll-8178.sh:204-207`
- **What:** verbatim second copy of the region-derivation awk. Follow-through probes are standalone by convention and the comment discloses the provenance, so this is accepted duplication — but `web-fresh-boot-zot-8651.sh` and `git-data-rehearsal-evidence.sh` are queued for the same fix (follow-up #11607 per session-state), which will make it four copies. If a third lands, the pattern graduates to candidacy for a shared source-able snippet.

## Refactoring roadmap

1. F2 (`usrc`) — trivial, zero risk.
2. F4, F5, F6 — cosmetic batch, zero risk.
3. F3 (jq selector bind) — small, suite-pinned.
4. F1 (split the empty-region cause) — small; would benefit from a matching fixture arm distinction (e.g. a `ULOG_BOUND_EMPTY` knob) if pursued.
5. F7/F8/F9 — record, no action needed this PR.

## Metrics

- Effort: all Small. Expected improvement: marginal — the diff is already at a high bar; the Medium finding touches diagnostic precision on an error path only.
