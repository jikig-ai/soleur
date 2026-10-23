# Decision Challenges — feat-one-shot-10913-redact-proxy-flake

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Fix vs quarantine the flaked G1 case | technical | pending - assumed: fix — mechanism identified (driver maps "alive at post-eof deadline" to `rc=TIMEOUT`; ~6.07s row elapsed = both 3s windows on three CI runs); determinism-checklist reserves quarantine for unfixable nondeterminism and says "triage to mechanism, never bump a timeout" (inline CTO Rule-lens applied; no subagent spawn available in this harness) |
| Fix shape: `--expect-death` driver mode + class sweep vs per-row timeout bump vs direct-run helper vs single-row fix | technical | pending - assumed: `--expect-death` driver flag + sweep of every startup-exit row — removes the deadline→verdict coupling at the chokepoint with one token per row, keeps each row's `--env`/`--proxy-arg`/`--server` plumbing identical; bump rejected by the determinism checklist, direct-run rejected for 66 heterogeneous arg re-mappings, single-row rejected as guaranteed recurrence across 65 sibling vectors |
| Death budget constant `EXPECT_DEATH_TIMEOUT_S = 30` | technical | pending - assumed: 30s — ~150× the 0.2s normal death path, 5× the worst observed stall (~6s); bounds genuine hangs without becoming a verdict-shaping deadline |
| Scope: sweep ~65 sibling startup-exit rows vs only the flaked row | technical | pending - assumed: sweep — identical `--timeout 3` + startup-exit coupling on every `assert_refused_start` row; single-row fix invites the next filing (cf. #10921, #10373); Scope Check records this as `inferred` with justification |
