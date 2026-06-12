# Learning: Porting an external CI gate needs roster-calibration, a positive control, and fail-closed thresholds

## Problem

Porting a peer repo's CI gate (here: `msitarzewski/agency-agents`'s
`check-agent-originality.sh`, an 8-word-shingle Jaccard re-skin detector) into
Soleur as `plugins/soleur/test/agent-originality.test.ts`. The upstream tool
ships a default FAIL threshold of 40%. Adopting that default verbatim would
have turned CI red on day one, and the naive threshold-parsing port had a
silent fail-open hole.

## Solution

Three things a ported "compares-everything-against-a-bar" gate needs that the
upstream default does not give you for free:

1. **Calibrate the threshold against YOUR current corpus before adopting the
   upstream default.** Soleur's roster already had one legitimate pair at
   **41.66%** (`agent-finder` ↔ `functional-discovery` — distinct purposes
   sharing `/plan`-spawned scaffolding), above the upstream 40% FAIL line. The
   next-highest pair was 15.72%. A true re-skin scores ~90%+. So FAIL was set
   to 50% (above the legitimate-overlap ceiling, well below a re-skin) with the
   41.66% pair documented inline as the living calibration record. Never lower
   a bar to hide a real duplicate; never adopt a foreign bar without measuring
   your own distribution first.

2. **A green-only gate can go vacuous — add a positive control.** The roster
   loop only ever asserts "no pair is too similar," which stays green if the
   scorer itself regresses (e.g. `shingles()` returns empty sets after a body-
   extraction change → every pair skipped → "none" forever). The committed
   suite must prove the scorer *fires*: two hardcoded near-identical strings
   asserting `jaccard >= 0.5`, a distinct pair asserting `< 0.3`, plus a
   non-empty-shingle invariant (`bodies-with-shingles > n/2`). This is the
   in-suite version of RED-verification — without it, the only proof the gate
   works lives in an out-of-band `AGENT_ORIGINALITY_FAIL=40` manual run that CI
   never executes.

3. **Env-overridable thresholds must fail CLOSED.** `Number(process.env.X ?? 50)`
   returns `NaN` on any non-numeric value (a typo, a stray quote), and
   `score >= NaN` is always false — the integrity gate silently disables itself.
   Parse via a validator that throws on non-finite / out-of-range input: a CI
   gate's safe failure is "refuse to run," not "pass everything."

## Key Insight

A ported similarity/threshold gate is only as good as (a) a bar calibrated to
your own corpus, (b) a self-test proving the scorer discriminates, and (c)
fail-closed config parsing. The upstream default value, the green roster pass,
and the happy-path env var are each a false sense of security on their own.
Two orthogonal review agents (security-sentinel + test-design-reviewer)
independently surfaced (b) and (c) where the green suite did not.

## Session Errors

- **`./node_modules/.bin/bun` not found (exit 127).** Over-applied the
  work/review skill rule "invoke the pinned `./node_modules/.bin/<tool>`" to
  `bun` — but bun is the globally-installed runtime (`~/.bun/bin/bun`), not a
  node_modules-pinned dependency like `vitest`/`tsc`. Recovery: `which bun` →
  use the PATH binary. Prevention: the pinned-binary rule targets
  node_modules-resolved test tools; the runtime itself (`bun`) is invoked
  bare. One-off (trivial recovery), not a workflow gap.
- **`Edit` failed "File has not been read yet".** Read the READMEs via
  `Bash`/`sed` for grep efficiency, but the `Edit` tool requires a `Read`-tool
  read of the same file. Recovery: `Read` then re-Edit. Prevention: when an
  Edit is planned, read the file with the `Read` tool, not Bash. One-off
  (known harness behavior).

## Tags
category: best-practices
module: plugins/soleur/test
