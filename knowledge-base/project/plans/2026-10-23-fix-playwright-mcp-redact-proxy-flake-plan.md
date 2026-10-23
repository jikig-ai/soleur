---
title: "fix: de-flake playwright-mcp-redact-proxy G1 row — deadline-mapped rc and opaque assert"
type: fix
date: 2026-10-23
slug: fix-playwright-mcp-redact-proxy-flake
branch: feat-one-shot-10913-redact-proxy-flake
issue: 10913
closes: 10913
lane: cross-domain
domain: meta/machinery
brand_survival_threshold: none
---

# fix: de-flake playwright-mcp-redact-proxy G1 row — deadline-mapped rc and opaque assert

## Enhancement Summary

**Deepened on:** 2026-10-23
**Sections enhanced:** gates 4.6–4.12 all pass (see below); Network-Outage Deep-Dive emitted under Technical Considerations
**Research agents used:** sequential inline fallback — no subagent spawn exists in this harness (`Reviewed-Coverage: sequential-fallback`); lenses applied inline: CTO Rule interface (fix-shape ruling → `specs/…/decision-challenges.md`), plan-review eng panel (DHH overengineering / Kieran correctness / code-simplicity per-mechanism), spec-flow walk, determinism-checklist convention, Sharp-Edges catalogue

### Key Improvements (deepen-pass)

1. Gate verification: `lint-guard-contract.py` rc=0; Scope Check unfenced count=1; PAT sweep clean; Observability 5-field block validates (probe verb `grep`, literal `ok`); User-Brand Impact threshold `none` with no sensitive-path match.
2. Network-Outage Deep-Dive added (gate 4.5 fired on the `timeout` keyword — documented as a local-process deadline, all four layers N/A with the artifact cited).
3. Literal-command verification of the plan's census greps run on current state (65 `assert_refused_start`, 108 `session --timeout 3`, 0 `--expect-death` — the expected pre-implementation census).
4. Verify-the-negative pass (inline): every mutant row's assert type checked — all are `started`/`delivered_ok`/file-fact live-session asserts, none a startup-exit rc; the synthetic helper-control `assert_refused_start` confirmed to pair with no `session(` call; `B1` rows confirmed direct-run with no driver involvement.
5. Precedent-diff (gate 4.4): deadline-free startup-exit assertion precedent exists in-suite — the `B1` usage rows (`python3 "$PROXY" … </dev/null` direct, ~lines 675-678); the chosen driver-flag mechanism keeps refusal rows inside the driver's env/stdin plumbing, which `B1` does not exercise.

### New Considerations Discovered

- `expect_death` must be initialized `False` inside `parse()`'s options literal — an arm-only store produces `KeyError` on the ~110 sessions that never pass the flag (folded into FR-1).
- The sweep-completeness check is a structural pairing (each `assert_refused_start` ↔ nearest preceding `session(`), not a count equality — the synthetic helper-control row has no session and would break a naive count (folded into AC-3).

## Overview

The agent-browser guard-contract suite (`plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh`, 499 cases) flaked the same single case in three observed CI attempts — run 39874186208 attempt 1 (PR #10881, the run that blocked the armed merge queue ~10h) and run 39937573660 attempts 1 and 2 (PR #10896, tracked as #10919): `FAIL - G1: a BaseException subclass outside the narrowed tuple at import → rc 1, nothing relayed, no child spawned`. The suite is green on main and locally (~0.23s for the row vs a ~6.07s elapsed gap on every failed CI run). The ~6.07s signature equals the session driver's two 3s deadline windows almost exactly, and the driver maps "proxy still alive when the post-eof deadline lapses" to `rc=TIMEOUT` — so a proxy whose startup was stalled on the runner past the deadline records TIMEOUT instead of its real exit 1, and the four-conjunct `assert_true` reports the failure with no per-observable detail. The fix removes the deadline from the verdict path for the startup-death class (~66 rows share the same coupling) and makes every surviving failure line self-explaining.

## Problem Statement / Motivation

**What fails:** one case of 499, on `test-scripts (5/8)` — a required check — so each occurrence blocks a PR's merge queue for the duration of a human rerun (measured: ~10h on PR #10881).

**Mechanism, established from the failed job logs (attempt-1 logs fetched via `gh api .../jobs/<id>/logs`):**

- `plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh` line ~735 drives the `v-load-outside` variant — a redactor copy that raises `class _OutsideBase(BaseException)` at import — through `fixtures/proxy-session-driver.py` with `--timeout 3`.
- The driver (proxy-session-driver.py `main`) burns up to `--timeout` waiting for sent request ids to be answered (phase A), then closes stdin and burns a *fresh* `--timeout` waiting for `p.poll()` to return non-None; a still-alive proxy is `p.kill()`ed and recorded `rc = "TIMEOUT"` (driver line ~121).
- The assertion requires `rcof == "1"` (and zero stdout lines, empty child_pgid, `_OutsideBase` on stderr). Locally the whole row takes ~0.23s. On the three failed runs the row consumed 6.077s / 6.076s / 6.065s — the two 3s deadline caps plus overhead — the signature of `rc=TIMEOUT`, i.e. the proxy stayed alive ~6s under runner load before being killed.
- The assert is opaque: `assert_true '<label>' bash -c '[[ ...4 conjuncts... ]] && stderr_has ...'` prints only the label on failure, so every recurrence is undiagnosable from the job log — which is why the issue prescribes "reproduce" instead of "fix".

**Why fix, not quarantine:** the mechanism is identified and the fix is small; the repo's own quarantine protocol (`plugins/soleur/skills/test-fix-loop/references/determinism-checklist.md`, seeded by PR #10738) reserves quarantine for nondeterminism with no mechanism fix, and its Contention axis says the honest fix for a load-sensitive suite is determinism work — "triage to mechanism, never bump a timeout."

## Research Insights

**Premise validation (Phase 0.6):** every cited reference verified — #10913 OPEN; sibling #10919 OPEN (same case, attempts 1+2 of run 39937573660 both red); related #9830 OPEN (8%-red-rate root-cause tracker); PR #10881 MERGED 2026-10-23 with a diff touching only `plugins/soleur/test/ci-pr-affected-replay.test.sh` + KB artifacts (confirmed unrelated to agent-browser); the suite file exists on `origin/main` (1599 lines); `SOLEUR_TEST_FORCE_ALL` is a real lever (`scripts/test-all.sh` lines ~421, 469, 2639). Nothing stale. PR-creation generality check: no workflow wrapper proposed.

**Property List (Phase 0.6b — what the fix must buy):**

1. The verdict for a startup-death row depends on the process's real exit code, never on a deadline the process is racing (deadline→verdict decoupling).
2. A still-alive proxy at a generous cap still reports TIMEOUT (hang detection preserved — a real startup hang must not pass silently).
3. Every surviving failure line names the observable that failed (rc value / line count / pgid / stderr needle) — self-explaining, per #10919's next-step ask.
4. The four asserted observables stay asserted (rc, nothing relayed, no child spawned, class named in traceback) — the fix narrows nothing.
5. Live-session rows (withheld/delivered/mutant/HOLD rows that genuinely wait on replies) keep their existing timeout semantics — no behavior change outside the startup-death class.

**Cut List:** nothing the issue proposed is cut — the issue proposes no mechanism ("fix or quarantine"). Cut at design time instead: (a) bumping `--timeout 3`→N — rejected by determinism-checklist ("never bump a timeout"; shrinks the window, keeps the coupling); (b) a suite-local `run_dead` helper driving `timeout(1)` directly — correct but requires per-row argument translation (`--env`/`--proxy-arg`/`--server`/`--config` interleaved) across ~66 call sites, higher edit risk than a driver flag for zero property gain.

**Findings (sequential inline fallback — no subagent spawn in this harness; `Reviewed-Coverage: sequential-fallback`):**

- repo-research-analyst equivalent (executed inline): the failing case is `v-load-outside` at `plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh:734-736`; added by PR #10503 (#10331 slice 1) on 2026-10-18, five days before the first failure. The G1 block sits amid ~65 `assert_refused_start` rows that all share the `session ... --send "$INIT" --end eof --timeout 3` + startup-exit-verdict shape — the same deadline→verdict coupling on every row.
- learnings-researcher equivalent (executed inline): `2026-06-29-review-rate-limit-fallback-and-wallclock-exact-assertion-flake.md` (bound, never pin, timing-derived assertions); `2026-09-29-i-pinned-a-flake-class-with-a-weaker-fork-of-the-detector-we-already-had.md` (adopt the canonical mechanism — here the determinism checklist — rather than a bespoke fork); `determinism-checklist.md` Contention axis is the governing convention and names this exact signature ("green in isolation … red in merge-group runs carrying unrelated diffs").
- functional-discovery equivalent (inline, zero results): a repo-internal test-harness flake has no community-registry analogue; nothing to install.
- Related issues/PRs: #10919 (same case, demands self-explaining failure lines — its stated next step is a deliverable here), #9830 (umbrella red-rate tracker — this fix removes one confirmed contributor), #10739/#10738 (quarantine methodology seed — defines "fix vs quarantine"), #10921/#10373 (sibling CI-flake filings — the whack-a-mole pattern the class-wide sweep avoids).
- CLAUDE.md conventions applied: `set -euo pipefail`, snake_case functions, error messages to stderr, symbol-anchor comments (cite `expect_death` not line numbers), minimalism ladder (the driver flag is rung 5 — "the minimum code that works" — over a new harness).
- Guard-floor context: `MIN_ASSERTIONS=499` at `playwright-mcp-redact-proxy.test.sh:1593` is a `-lt` floor — splitting one case into four raises the count to ~502 and stays above the floor; `scripts/guard-vacuity-floor.test.sh` promotes this suite on the floor's existence and shape, not the exact number.

**Research Reconciliation — Spec vs. Codebase:** no `spec.md` exists for this branch (one-shot pipeline: plan is the first artifact); nothing to reconcile. `lane:` absent → defaulted to `cross-domain` (TR2 fail-closed).

## Proposed Solution

**FR-1 — `--expect-death` mode in `proxy-session-driver.py`.** One new flag in the driver's `parse()` loop (`--expect-death`), storing `o["expect_death"] = True` — the key MUST be initialized `False` inside the `o = {...}` literal at the top of `parse()` so sessions without the flag do not hit `KeyError`. Semantics:

- The reply-wait loop (`while want - got and time.monotonic() < deadline …`) is skipped for expect-death sessions — the proxy is expected to die, not answer; `--send` lines are still written to stdin (BrokenPipe suppressed as today) so the "refused before serving" ordering evidence is unchanged.
- The post-`--end` wait uses a fixed death budget `EXPECT_DEATH_TIMEOUT_S = 30` (constant in the driver), not `o["timeout"]` — a real startup hang still records `rc = "TIMEOUT"` at 30s (informative, ~150× the normal 0.2s death path so environment stalls cannot trip it without masking a genuine hang).
- All capture outputs (`rc`, `stdout.bin`, `stderr.txt`, `child_pgid`, `group_after`, `responses.json`) are written identically — every existing `fact`/`rcof`/`stderr_has`/`assert_*` consumer works unchanged.

**FR-2 — sweep the startup-exit rows.** Every `session()` call whose verdict is a startup exit replaces `--timeout 3` with `--expect-death`: the ~64 session-fed `assert_refused_start` rows (the FR5 config-refusal block, FR6/B2/G1 variant refusals, UDD/fallback/sink/env refusal rows — the synthetic helper-control `assert_refused_start` on hand-written out-dirs has no session and is untouched) plus the `v-load-outside` row. The `B1` usage rows need no conversion: they already bypass the driver (`python3 "$PROXY" … </dev/null` direct, lines ~675-678) — the suite's existing precedent for deadline-free startup-exit asserts. Live-session rows — every `odd`, `m<N>` mutant (all assert `started`/`delivered_ok`/file facts, never a startup-exit rc — verified by reading all 86 mutant rows' assert types), `inst-hold`, `inst-grandchild`, spy/withheld/delivered rows — keep `--timeout` exactly as-is: they legitimately wait on replies or bounded group teardown.

**FR-3 — self-explaining failure lines.** Split the single opaque `assert_true` on `v-load-outside` into per-observable verdicts using the suite's own helpers:

- `assert_rc 'G1: … proxy exit 1' "$r" 1` (prints `exit TIMEOUT, expected 1` on a recurrence — the conjunct that actually failed),
- `assert_true 'G1: … nothing relayed' bash -c '[[ "$(fact "$1" 0 lines)" == "0" ]]' _ "$r"`,
- `assert_true 'G1: … no child spawned' bash -c '[[ -z "$(cat "$1/child_pgid" 2>/dev/null)" ]]' _ "$r"`,
- `assert_stderr_marker 'G1: … traceback names the class' "$r" '_OutsideBase' 1`.

**FR-4 — mechanism-level reproduction + CI verification (the issue's "reproduce" ask).** Before the fix, prove the TIMEOUT mapping by driving a synthetic slow-death proxy (a redactor variant whose module top sleeps ~7s then raises `_OutsideBase`) through the current `--timeout 3` path and asserting `rc=TIMEOUT` lands the same opaque FAIL signature; after the fix, the same slow-death fixture under `--expect-death` records the real `rc=1` — the injected-stall regression test. The slow-death fixture may ship as a permanent row (`v-load-outside-slow`) so the decoupling is guarded, not assumed.

## Technical Considerations

- **Why a driver flag over a suite-local direct-run helper:** every refusal row passes heterogeneous args (`--env`, `--proxy-arg`, `--server`, `--config`) that a `timeout 30 python3 …` rewrite would have to re-map correctly 66 times; the flag change is one token per row with the driver's env/stdin/stderr plumbing untouched. Minimalism ladder rung 5.
- **Why 30s and not unbounded:** an unbounded wait turns a real startup hang into a suite hang caught by the outer watchdog with no per-row attribution; 30s is ~150× the measured 0.2s normal path and 5× the worst observed stall (~6.07s) — a bound that only a genuine hang can hit.
- **What the sweep cannot change:** `assert_refused_start` checks rc==2, the refusal reason needle, zero stdout lines, empty child_pgid — all file-based reads unaffected by the deadline semantics. Sessions that serve replies (`want` satisfied) never reach the death path.
- **Masking risk:** under `--expect-death`, a proxy that *serves* instead of dying still lands stdout lines → `lines != 0` → RED. A proxy that refuses with the wrong rc → `assert_rc`/`assert_refused_start` RED. Nothing is weakened.
- **Python-version safety:** the driver is stdlib-only; the flag adds no dependency.

### Network-Outage Deep-Dive

Gate 4.5 fired on the `timeout` keyword. The word in this plan names `proxy-session-driver.py`'s wall-clock deadline on a **local subprocess** (`subprocess.Popen` + `start_new_session`, stdio pipes to a repo fixture stub) — there is no SSH, DNS, TLS, or remote-service hypothesis anywhere in the change surface. Per-layer status, each with its opt-out artifact:

- **L3 firewall allow-list — N/A.** Opt-out: no host or firewall enters the path; the failing case is a `python3` subprocess on the runner itself. Artifact: suite source — the session launches `[sys.executable, proxy] + args + ["--"] + server` with stdio pipes, no sockets.
- **L3 DNS/routing — N/A.** Opt-out: no hostname is resolved on the flaked path; the "server" is `fake-playwright-mcp.py` spoken to over stdin/stdout.
- **L7 TLS/proxy — N/A.** Opt-out: no HTTPS surface; the protocol under test is newline-delimited JSON-RPC over stdio.
- **L7 application — verified (local analogue).** The service-side analogue is the proxy's own stderr/exit trace, already inspected from the failed job logs: row elapsed ~6.07s ≈ the driver's two 3s deadline windows, `rc` file would read `TIMEOUT` (the driver's only producer of that string is the `p.kill()` arm at ~line 121) — process-level evidence the proxy was still alive at the deadline, not evidence of any network fault.

## Files to Edit

- `plugins/soleur/skills/agent-browser/test/fixtures/proxy-session-driver.py` — add `--expect-death` parse arm, skip reply-wait when set, `EXPECT_DEATH_TIMEOUT_S = 30` death budget on the post-end wait, docstring flag line.
- `plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh` — convert every startup-exit `session … --timeout 3` row to `--expect-death` (~66 call sites: the 65 `assert_refused_start` rows + `v-load-outside` + `B1` usage rows); split the `v-load-outside` `assert_true` into the four per-observable rows (FR-3); add the `v-load-outside-slow` stall-injection row (FR-4); update `MIN_ASSERTIONS` comment/count as the case census moves (still ≥ floor; the suite's trailing count line is self-computed).

## Files to Create

None.

## User-Brand Impact

- **If this lands broken, the user experiences:** a required `test` check that can still go red on a load-stalled runner — for the soleur maintainer the artifact is a blocked merge-queue PR, not user-facing product behavior.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — the change is confined to test fixtures and a test suite (meta/machinery); no user data, credentials, or product path is touched.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the diff touches only `plugins/soleur/skills/agent-browser/test/` — no `apps/**` surface, no regulated-data regex path, no operator-facing artifact; the incident being fixed is itself internal CI cost (a blocked merge queue), not a user breach.

## Observability

```yaml
liveness_signal:
  what: suite verdict line "N passed, M failed, 499+ cases" inside the test-scripts shard of ci.yml
  cadence: per pull_request / merge_group / push CI run
  alert_target: the required `test` check gate on the PR (fail-closed by construction)
  configured_in: plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh (verdict printf + MIN_ASSERTIONS floor)

error_reporting:
  destination: the suite's own FAIL lines in the GitHub job log + per-suite log under /var/tmp/soleur-test-all-logs on the runner
  fail_loud: "FAIL - <label> — <observable>" line naming the failed conjunct (rc value, line count, pgid, stderr needle); suite exits non-zero, [FAIL] row in run_suite output

failure_modes:
  - mode: startup-exit proxy outlives the reply/death windows under runner load
    detection: after FR-1, the driver records the real rc; a >30s stall records "TIMEOUT" with the row's label naming the expected rc
    alert_route: red `test` check on the PR — self-explaining line, no reproduction step needed
  - mode: --expect-death applied to a session that should serve replies (misuse)
    detection: stdout lines are still captured — lines != 0 rows go RED; Guard Contract mutation matrix row 5 pins this
    alert_route: same FAIL line channel
  - mode: sweep misses a startup-exit row
    detection: grep census `assert_refused_start` count vs `expect-death` count on the file (AC-5)
    alert_route: local verify + PR diff review

logs:
  where: stdout stream of the suite inside the shard job log; suite copy at /var/tmp/soleur-test-all-logs/<run>/plugins__soleur__skills__agent-browser__test__playwright-mcp-redact-proxy.test.sh.log
  retention: GitHub Actions log retention (90 days) for the job log; runner-local tmp for the suite copy

discoverability_test:
  command: grep -q 'expect_death' plugins/soleur/skills/agent-browser/test/fixtures/proxy-session-driver.py && printf 'ok'
  expected_output: ok
```

## Guard Contract

### Guard 1 — deadline-decoupled startup-exit verdict

**Property.** For every startup-exit session row, the recorded rc is the proxy's real exit code whenever the proxy exits at all; a deadline can only produce TIMEOUT on a genuine hang, never on a slow-but-correct death.

**Assembly.** Every `session()` call in `playwright-mcp-redact-proxy.test.sh` whose verdict asserts a startup exit — the chokepoint is the pair `session()` → `proxy-session-driver.py` post-`--end` wait loop; the membership is enumerable: every row feeding `assert_refused_start` (65), `v-load-outside` (1), and the `B1` usage rows — vs. the disjoint live-session set (`odd`, `m<N>` mutant rows, `inst-hold`, `inst-grandchild`, spy/withheld rows) that keeps `--timeout` by design. A second chokepoint exists: the driver's reply-wait phase must be skipped under `--expect-death` or a stalled startup burns one deadline window for nothing.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Variant proxy exits rc 2 at import instead of rc 1 (e.g. raise `SystemExit(2)`) | RED — `assert_rc … expected 1` |
| 2 | Driver drops the `--expect-death` parse arm (flag unrecognized → usage exit 2, or falls back to `o["timeout"]` semantics) while `v-load-outside-slow` sleeps >3s | RED — records `TIMEOUT`, not the real rc |
| 3 | Variant redactor writes a JSON-RPC reply to stdout before raising (compliant first observable rc=1, failed second) | RED — "nothing relayed" row |
| 4 | Variant proxy spawns a child before dying (first two observables pass, third fails) | RED — "no child spawned" row |
| 5 | `--expect-death` swapped onto a live-session row (`inst-hold` or a mutant row expecting a reply) — dispatch-level misuse | RED — reply-wait skip changes nothing for a served session, but pinning the sweep boundary: any `assert_refused_start` row still carrying `--timeout` fails the AC-5 census |
| 6 | Harness row: `v-load-outside-slow` (sleep-then-raise) under `--expect-death` | PASS — proves the guard admits a non-canonical slow-but-correct death (a guard that rejects everything cannot be caught by RED rows alone) |
| 7 | `p.kill()`/TIMEOUT arm deleted entirely from the death path | RED — a genuinely hung proxy would hang the suite; the bound row asserting TIMEOUT-on-hang (or the outer ceiling) must fire |

**Anchor.** The sweep's completeness is checked by census, not by the suite's own green: `grep -c "assert_refused_start '"` vs `grep -c -- "--expect-death"` on the suite file must satisfy the declared relation (every refusal row converted). The census check lives in the plan ACs and is reproducible by any reviewer from `origin/main`'s diff.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "re-run locally with `SOLEUR_TEST_FORCE_ALL=1 bash scripts/test-all.sh` or dispatch ci.yml on a branch to catch the failing case" | FR-4 reproduction protocol + Test Scenarios + AC-4 (CI dispatch verification) | mapped |
| 2 | "then fix or quarantine it" | FR-1 (`--expect-death` driver mode), FR-2 (startup-exit sweep), FR-3 (self-explaining failure lines) — fix arm chosen; quarantine rejected because the mechanism is identified (decision-challenges row) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| FR-1 `--expect-death` driver mode | "then fix or quarantine it" | asked (mechanism choice inferred — justification: the determinism checklist forbids the timeout bump; the flag is the minimum change removing the deadline→verdict coupling at the chokepoint) |
| FR-2 startup-exit sweep (~66 rows) | — | inferred — justification: every `assert_refused_start` row shares the identical `--timeout 3` + startup-exit coupling; fixing one row leaves 65 identical flake vectors and guarantees the next filing (cf. #10921, #10373) |
| FR-3 per-observable asserts | — | inferred — justification: #10919 (open, same case) states the required next step verbatim: "Add the case's own `rc`, stderr head and elapsed time to the failure line so the next CI failure is self-explaining" |
| FR-4 slow-death reproduction row | "dispatch ci.yml on a branch to catch the failing case" | asked |
| Files to Edit entries (2 files) | "fix or quarantine it" (the suite named in the issue body) | asked |

### Split Assessment

- Subsystems touched: 1 — `plugins/soleur` (one skill's test directory)
- Planned files: 2 | Estimated changed lines: ~120 (≈66 one-token row edits + ~35 driver lines + ~20 assert/fixture lines)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — test-machinery change inside `plugins/soleur/skills/agent-browser/test/`; no user-facing surface, no product/UX files (mechanical UI-surface override scanned: zero `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx` in Files-to-Create/Edit), no infra, no regulated-data surface.

## Acceptance Criteria

- [ ] AC-1: `proxy-session-driver.py` accepts `--expect-death`; under it the reply-wait phase is skipped and the post-`--end` wait is bounded by `EXPECT_DEATH_TIMEOUT_S = 30`, recording `rc="TIMEOUT"` only when the process is still alive at that cap.
- [ ] AC-2: A stall-injected reproduction (`v-load-outside-slow`, module-level sleep >3s before `raise _OutsideBase()`) records `rc="TIMEOUT"` under `--timeout 3` semantics and the real `rc=1` under `--expect-death` — the before/after mechanism proof is itself a committed row.
- [ ] AC-3: Every `session()` call feeding an `assert_refused_start` verdict, plus `v-load-outside`, carries `--expect-death` — verified by a structural pairing check, not a bare count: a python/awk pass over the suite file that pairs each `assert_refused_start` with its nearest preceding `session(` call asserts `--expect-death` is present on it (the synthetic helper-control row on a hand-written out-dir pairs with no `session(` and is exempt), and `grep -n 'session .*--timeout'` reviewed against the pairing list confirms the only remaining `--timeout` sessions are the live-session set (`odd`, `m<N>`, `inst-*`, spy/withheld).
- [ ] AC-4: The `v-load-outside` verdict is four named observables (rc 1 / zero stdout lines / no child pgid / `_OutsideBase` on stderr); any single-conjunct failure prints which observable failed.
- [ ] AC-5: Full suite green locally: `bash plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh` exits 0 with `0 failed`; `MIN_ASSERTIONS` floor still satisfied (cases ≥ 499).
- [ ] AC-6: `SOLEUR_TEST_FORCE_ALL=1 bash scripts/test-all.sh` green on the feature branch (or the affected subset covering this suite), plus one `gh workflow run ci.yml` dispatch on the branch reporting `test-scripts (5/8)` green — the issue's own prescribed verification.

## Test Scenarios

- Given a redactor variant that raises `_OutsideBase` after a >3s module-level sleep, when the session runs under `--expect-death`, then `rc` file contains `1`, stdout has 0 lines, `child_pgid` is empty, and stderr names `_OutsideBase`. (integration)
- Given a proxy that hangs at startup (sleeps > `EXPECT_DEATH_TIMEOUT_S`), when the session runs under `--expect-death`, then `rc` is `TIMEOUT` and the row reports it against the expected exit code — a real hang stays a loud failure. (integration)
- Given a served reply instead of a death (misuse boundary), when a live-session row keeps `--timeout`, then reply capture, `want`-satisfaction, and group-teardown behavior are unchanged — pinned by the untouched `inst-hold`/`inst-grandchild`/mutant rows staying green. (integration)
- Given the suite file, when `grep -c "assert_refused_start '"` and `grep -c -- "--expect-death"` are compared, then every startup-exit row is on the new mode — the sweep-census gate. (unit)

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies searched for `playwright-mcp-redact-proxy` and `agent-browser`: zero matches.

## Context

- Failed-run evidence: run 39874186208 job 120155855639 (attempt 1); run 39937573660 jobs 120361334676 (attempt 1), 120371284399 (attempt 2). Row elapsed ~6.07s on all three; ~0.23s locally.
- Driver internals: `proxy-session-driver.py` lines ~96-123 (reply-wait deadline, post-end wait, `p.kill()` → `rc="TIMEOUT"`).
- The G1 row was added by PR #10503 (2026-10-18, slice 1 of #10331); the suite's guard-contract shape is from #7980/#8150.
- #10919 is the same case filed from PR #10896's run; its diagnostics ask is FR-3. Consider closing it in the same PR (it is the same mechanism) — ship decides via `Closes` lines.

## Alternative Approaches Considered

| Approach | Verdict |
|----------|---------|
| Bump `--timeout 3` → larger on the flaked row | Rejected — determinism checklist: "triage to mechanism, never bump a timeout"; narrows the window, keeps the deadline→verdict coupling |
| Quarantine the case | Rejected — mechanism is identified and fixable; quarantine protocol is for unfixable nondeterminism (filed issue + `flaky` label, never counts as fixed) |
| Suite-local `run_dead` helper driving `timeout(1)` directly | Rejected — correct property but requires per-row arg re-mapping across ~66 heterogeneous call sites; one-token driver flag is the smaller diff for the identical contract |
| Fix only the `v-load-outside` row | Rejected — leaves 65 sibling rows carrying the identical vector; the next stall files #10913 again under a new label |
| Retry-on-failure wrapper | Rejected — retry-until-green is the exact anti-pattern the determinism checklist exists to prevent |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- Do not touch `MIN_ASSERTIONS` semantics: the floor is `-lt`-bounded and promoted by `scripts/guard-vacuity-floor.test.sh`; adding cases is safe, removing them is not.
- The sweep must not touch live-session rows (`odd`, `m<N>`, `inst-*`, spy/withheld rows): those deadlines wait on replies and are the correct use of `--timeout`.
- `Reviewed-Coverage: sequential-fallback` — all skill-prescribed subagent fan-outs were executed sequentially inline; no independent reviewer ran.

## References

- Issue: #10913 (this plan's target); sibling: #10919; umbrella: #9830; methodology: #10739 / PR #10738
- Convention: `plugins/soleur/skills/test-fix-loop/references/determinism-checklist.md` (Contention axis, quarantine protocol)
- Learnings: `knowledge-base/project/learnings/2026-06-29-review-rate-limit-fallback-and-wallclock-exact-assertion-flake.md`, `knowledge-base/project/learnings/2026-09-29-i-pinned-a-flake-class-with-a-weaker-fork-of-the-detector-we-already-had.md`
- Prior art: suite introduced by #7980/#8150; G1 rows by #10503 (slice 1 of #10331)
