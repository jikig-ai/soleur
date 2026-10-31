# Decision challenges — feat-one-shot-11578-ruling-gate-midnight-flake

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Which clock seam fixes the `dts` midnight flake in `technical-ruling-gate.test.sh` — (A) recompute `DTODAY` per scenario inside `dscn`, (B) a `TRG_NOW` env seam inside the production gate, or (C) an argv-strict `date` stub in the suite's `$DBIN` pinned to fixture noon | technical | pending - assumed: C — deterministic like B but test-only (zero production blast radius on a ship-time security gate); A leaves a residual intra-case window between fixture build and gate exec, so it shrinks the flake rather than eliminating it; C reuses the established stub-bin idiom (`ship-battery-refusal-wait.test.sh` fake clock) and needs no gate change |
