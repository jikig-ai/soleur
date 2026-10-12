# Decision challenges: feat-one-shot-10065-sandbox-proc-suite-parity

Headless plan-review output (2026-10-12). Mechanical findings were applied to the plan. The rows below are Taste or
User-Challenge items: the plan keeps the operator's stated direction as the default and records the dissent so `ship` can surface it.

## Decision Classes

| # | Challenge | Class | Plan default | Dissent (source) |
|---|-----------|-------|--------------|------------------|
| 1 | Cut the C4 argv fixture, its pin test and the C4 docker replay; assert "no /proc mount token in the built argv" in vitest instead | user-challenge (drops operator-requested scope: "the outer-wrap and C4-render spawn paths") | keep fixture, pin and replay (replay gated by measurement M2) | DHH, code-simplicity, CTO |
| 2 | Cut the static builder-literal extractor and keep only the live-spawn equality row | user-challenge (drops operator-requested scope: "the vendored builder's live argv tail") | keep both; the live row covers one binary and one branch, the extractor covers both binaries, both branches and procfs-site counts | code-simplicity (DHH and CTO would keep the extractor) |
| 3 | Split into two PRs (tuple parity first; isolation, spawn paths and live tail second) | taste | single PR, commits ordered so Phases 2-3 can ship alone | architecture-strategist, CPO (scope vs p3 priority) |
| 4 | Posture-only tuple check instead of the closed-world grammar | taste | closed-world (learning 2026-10-09 on spelling-keyed guards) | DHH |
| 5 | Drop Phase 0 M3 (behavioral cover-vs-drop) as speculative, versus make it a hard gate that can reopen ADR-075 | taste | time-boxed hard gate for Phase 4 | DHH (cut) versus architecture-strategist (escalate) |
| 6 | Defer the C4 and outer-wrap docker replays and the extractor to a follow-up issue | user-challenge (drops requested scope) | keep in this PR | CTO |
