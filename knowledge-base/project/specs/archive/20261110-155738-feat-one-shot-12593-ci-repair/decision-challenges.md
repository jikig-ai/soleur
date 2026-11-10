# Decision Challenges — feat-one-shot-12593-ci-repair

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Scope overlap with open PR #12560 (covers #12593 items 3+4 only) | technical | Ruled by pipeline runner, 2026-11-10: proceed with FULL issue scope — #12560 is red on legs items 1+2 cause (interlock: it cannot pass without this work or a fixed main), and both sides' baseline deltas are deterministic so same-content merges are clean. Recorded as collision notice, not an abort. |
| dpkg repair placement (inside vs outside the attempt `timeout`) | technical | Ruled by pipeline runner, 2026-11-10: inside the bounded `bash -c`, gated `try > 1` — a wedged repair burns its own attempt allotment and stays charged to `spent` via existing `dt` accounting; attempt-1 semantics stay byte-identical. |
| `git-data-rung2-boot-evidence.env` refresh | technical | Ruled by pipeline runner, 2026-11-10: out of scope — its gate (`deploy-script-tests-fixed`) is absent from the required canonical set and the file is a deliberately non-auto-committed rehearsal artifact needing a real `--ref main` rung-2 run; disclosed as remaining in the PR body. |
| `contexts=12 producers=11` literal at test line 641 | technical | Ruled by pipeline runner, 2026-11-10: unchanged — it is a synthetic control input to `engine_skipped` (C1b), where any well-formed OK line suffices; live-count tracking is only required of the `row_green` expected-substring args. |
