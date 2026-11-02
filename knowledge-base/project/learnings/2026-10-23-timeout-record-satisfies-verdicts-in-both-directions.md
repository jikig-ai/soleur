---
module: CI
date: 2026-10-23
problem_type: flaky_test
component: proxy-session-driver + playwright-mcp-redact-proxy suite
symptoms:
  - "playwright-mcp-redact-proxy.test.sh failed 1/499 in CI (#10913, #10919): `v-load-outside` row elapsed ~6.07s = BOTH 3s driver deadline windows, recording rc=TIMEOUT over the proxy's real exit 1"
  - "The same TIMEOUT record is a FALSE-GREEN vector, not only a false-red: `m62`/`m63`'s disjunctive `red` verdicts (`rcof != \"2\"`, `! stderr_has <needle>`) are satisfied vacuously by a deadline kill with empty stderr"
  - "A predicate sweep ('verdict asserts a startup exit') missed `m62` — the dual-arm `||` row whose second disjunct IS a startup-exit assertion"
root_cause: deadline_to_verdict_coupling
tags: [ci, flake, test-design, mutation-matrix, timeout, determinism]
---

# A TIMEOUT record satisfies verdicts in both directions — audit disjunctive arms, not just exit-code asserts

## Problem

`proxy-session-driver.py` mapped "proxy still alive at the post-`--end` deadline" to `rc=TIMEOUT`, decoupled from whether the process had started at all. Two consequences of ONE coupling, asymmetric in danger:

1. **False-RED (what got filed, #10913):** a startup-exit row (`assert_refused_start`, `v-load-outside`'s rc-1 assert) needs the proxy's real exit code; a runner-stalled startup got killed at the deadline and recorded TIMEOUT instead — the row went red with the deadline's answer, not the proxy's.
2. **False-GREEN (what the panel caught, worse):** `red` mutation rows with `||` disjuncts whose non-`started` arm is a *negative* startup-exit observable (`rcof != "2"`, `! stderr_has <refusal-needle>`) are satisfied vacuously when the proxy dies silent — the mutant "survives" while the row reports a kill. #10913 blocked a merge-queue PR ~10h; this direction would never have been noticed at all.

## Fix

`--expect-death` at the driver chokepoint: skip the reply-wait phase and bound the post-end wait by `EXPECT_DEATH_TIMEOUT_S = 30` — a slow-but-correct startup death records its real rc; only a still-alive process at 30s records TIMEOUT. Swept to all ~70 startup-exit session lines (68 `assert_refused_start` feeders incl. loop sites + `v-load-outside` + `m63`), then in the fix round `m62` — which ALSO needed its verdict gated (`started || { refusing-to-start && ! HOME-is-set }`) so neither arm is TIMEOUT-satisfiable.

## The durable rule for this suite (and any deadline-driver)

- **Audit `red`/`assert` verdicts with `||` disjuncts for arms satisfiable by a deadline record** — an exit-code pin (`assert_rc 1`, `assert_refused_start` rc=2) false-REDS under TIMEOUT, but `!=` / `! has` arms false-GREEN. The dangerous direction is the one whose default-empty state satisfies the condition.
- **A startup-death fixture's sleep must exceed the SUM of the driver's deadline windows** (reply-wait + post-end wait ≈ 2×timeout), not one — a death inside the second window still records the real rc and looks green.
- **`stderr_has` presence over `assert_stderr_marker` count for traceback needles**: the exception class legitimately appears 2× (raise-site echo + exception line); a count pin is fragile across traceback formats.
- **`--expect-death` is NOT for `started`-verdict rows** — the flag names the expectation; residual ~25 served-mutant rows keep `--timeout` and can only false-RED (loud, bounded). If one flakes, the correct shape is a decoupled startup-marker window, not reusing the death flag.

## Session Errors

1. **New stderr assert pinned count=1 on `_OutsideBase`, which appears 2× in a traceback** — Recovery: switched to presence (`stderr_has`), named-observable goal preserved. — Prevention: run the fixture once and count the needle before pinning a count; prefer presence unless multiplicity itself is the contract.
2. **Negative-control fixture slept 4s < the ~6s combined deadline → recorded rc 1 instead of TIMEOUT** — Recovery: sleep(10) with margin documented. — Prevention: size reproducer delays to outlive *all* sequential deadline windows, plus driver-descheduling slop; state the arithmetic in a comment.
3. **`m62` missed by the predicate sweep — found by 4 panel seats independently** — Recovery: converted + verdict gated in the fix round. — Prevention: for verdict-sweep predicates, enumerate the *satisfaction shapes* (`==`, `!=`, `has`, `! has`) not the helper names; one `grep 'red .*||'` audit catches the class.
4. **tasks.md/plan drifted from shipped values mid-flight (sleep 4→10, marker→presence)** — Recovery: synced at fix round. — Prevention: amend the task text in the same commit that deviates.

## Evidence

- Suite: 504/504 green locally, twice (post-sweep and post-fix-round). Pairing check: 66/66 startup-exit verdicts on `--expect-death`, 0 misses.
- Driver probe: genuine-hang proxy under `--expect-death` → `rc=TIMEOUT` at the 30s cap (hang detection preserved); slow-death proxy (sleep 10) under `--timeout 3` → TIMEOUT, under `--expect-death` → rc 1 (the committed dual-arm proof).
