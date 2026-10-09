# Committed CI weights are not local costs — measure on the machine that pays

**Date:** 2026-10-09 · **Context:** #9763 — splitting `ALWAYS_ON_SUITES` into a local fast tier.

## What happened

The demotion was computed against `scripts/suite-durations.tsv` — committed weights measured on CI runners. A 10s committed cap moved 29 suites out. The first idle-machine `--affected` run then measured **12.8 min**: nine additional always-on suites were 10–185s *locally* (185s actual vs 8.5s committed for `lint-shell-trace-credential-refusal`; 55s vs 1.1s for `preflight-check10-suite-integrity`) plus the 82s vitest shard, which had **no weight row at all** — invisible to any check that reads the manifest.

A second demotion round driven by the *measured local* run landed the tier at **4.40 min**.

## The durable rules

1. **Budget against the paying machine's measurement.** CI-leg timings and local wall-clock differ ~2–3× per suite (different CPU, disk, cache warmth). A LOCAL budget pinned on CI weights is optimistic fiction. The cap's unit must be the same machine class the budget protects — or the budget is a claim, not a constraint.

2. **Unmeasured = unaccountable.** A suite absent from the durations manifest dodges any weight-based cap silently. The budget lint must red on missing weights (or hold a pinned, drift-closed exception set) — absence can never read as compliance.

3. **Demoting a corpus-walker is never just a list edit.** `lint-orphan-test-suites` forces every withdrawn suite to name its scope; the honest scope is "the dirs the suite actually scans" (`git ls-files '*.sh' | xargs dirname`), not a guessed subset — an under-covered edge array is a coverage hole, and an over-broad one leaks the suite back into the local tier. Enumerate mechanically, don't guess.

4. **Pins that quote their own subject self-mutate.** `grep "LOCAL_FAST_CAP_MS=10000"` inside the file being mutated is rewritten by the same sed that changes the constant — the pin stays green. Pin the *value* (`(( LOCAL_FAST_CAP_MS == 10000 ))`) or exercise the *predicate* against fixtures (red + green arms) — never the needle text.

5. **A cap predicate that never fails in practice is untested.** The lint's real-corpus check is green by construction — only synthetic fixture arms (heavy label → red, compliant → green) prove the predicate works at all. The house convention (mutation arms inline in the suite) exists for exactly this.

## Prevention

`scripts/test-all-fast-tier-budget` now: fails on missing weight rows (with a pinned exact-set allowlist closed under all three drift directions); sources the index for its census (text-shape edits can't hide entries); exercises cap predicates against synthetic fixtures every run; and the plan/issue record the measured wall-clock as the authoritative budget number, not the committed-weight sum.
