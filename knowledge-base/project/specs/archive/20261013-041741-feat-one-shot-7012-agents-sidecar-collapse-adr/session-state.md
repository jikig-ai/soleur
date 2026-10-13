# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-07-28-chore-collapse-agents-change-class-sidecars-plan.md`
- Tasks file: `knowledge-base/project/specs/feat-one-shot-7012-agents-sidecar-collapse-adr/tasks.md`
- Draft PR: #7034
- Status: complete — **paused by operator before Step 3 (`soleur:work`)**

### Errors
None blocking. Five plan-level defects were caught by the review panel and fixed before freeze:
- Compensating control for the knowingly-blinded ADR-092 gate covered 74 of 101 rules (`lint-rule-bodies.py` gates only `^(hr|wg)-`) and nominated a `cq-*` rule the gate never sees. Correct WORM-ack count is **zero**, not one.
- A **deployed** Inngest cron fails open on the missing file, inventing ~35 kB of phantom headroom, disabling its own overflow guard, and able to auto-PR `AGENTS.core.md` back into existence.
- Thresholds mirrored at **13 pinned sites** (3 in the deleted file, 2 live production constants) — Phase 6 would have wedged pre-commit.
- Phases read as commits; four `lefthook.yml` jobs make every boundary inside Phases 1–4 non-committable.
- Residual-sweep AC was blind to the brace form `AGENTS.{core,docs,rest}.md` and excluded `.md`/`.txt`/`.json`. Corrected sweep: **65 files / 355 hits**.

### Decisions
- **Option (c) — collapse.** (a) is unsafe (the `core`-default fall-through was confirmed by reading the loader directly); (b) degrades the compounding-knowledge moat.
- **Scope correction (main finding):** the split bundles **two separable mechanisms**. The large per-turn win comes from index/body separation; only the **change-class conditionality** is retired. The issue's "retires `session-rules-loader.sh` + 2 test files" is wrong — the hook has **nine** jobs (SOC 2 evidence, session-context, and the sole SessionStart read of the tmpfs alarm among them). It shrinks; it does not die.
- **Measured, not projected.** Multi-class rate **70.0%** (N=80) / **72.0%** (N=200) vs the issue's 68%/72%. Simulated merge is **lossless (101/101 rules)**; new `B_ALWAYS` = **42,425 B**, i.e. **1,255 B smaller** than what 70% of sessions already load. Two `lint-rule-ids.py` failures pre-identified, both core-pinning (45 + 5 ids).
- **The "23,000-byte harness ceiling" is not a harness limit** — the phrase exists only inside the lint's own warning string, and 70% of sessions already run at 1.9× it.
- **Byte claims de-confounded.** The −939 B/turn arrow removal is available today with the split intact, so it is *not* a collapse win. The decision rests on **correctness** (two silent-drop incidents; ADR-140 records a hard rule the split prevented from being written), not bytes.
- ADR number reserved: **ADR-151**. The ADR file itself is written in implementation Phase 9.1 via `soleur:architecture create` — it was correctly NOT written during planning.

### Downstream issue disposition (recorded, not implemented)
- **#7013** (B_FAILOPEN reporting) — premise retired by the collapse.
- **#6138**, **#3792** — premises likewise retired.

### Components Invoked
`soleur:plan` · `soleur:deepen-plan` · `learnings-researcher` · `Explore` · `architecture-strategist` · `code-simplicity-reviewer` · `spec-flow-analyzer` · deepen-plan gates 4.6/4.7/4.8/4.9/4.10/4.55 · merge simulation + live lint pre-validation

## Work Phase
- Status: **not started** — operator paused after planning.
