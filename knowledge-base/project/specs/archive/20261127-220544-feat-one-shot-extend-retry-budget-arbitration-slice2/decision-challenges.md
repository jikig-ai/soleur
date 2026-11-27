# Decision challenges

Carried forward from slice 1 of #12526 (2026-11-16..19 CTO/CLO rulings) and applied to slice 2 wiring.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| T1 verb contract and single canonical reference | technical | Ruled by CTO agent, 2026-11-16: one shared exemption (`ruling_spawn: used`), `capped=` stays set, cap is not raised; `retry-budget-ruling.sh` and `one-shot/references/retry-budget-ruling.md` are the single canonical parser and reference (no skill-local duplicate reference files). |
| R1-r continue has no unit | technical | Ruled by CTO agent, 2026-11-19: `continue` is a parser token recorded as `applied: not-run` (`verb=fail reason=not-run`) with `ruling_spawn: used`; the caller runs no unit and preserves existing termination/reset rules. |
| T2 phase and earlier-only goto | technical | Ruled by CTO agent, 2026-11-16: `--phase` and `goto` tokens use the closed allow-list (`plan`, `work`, `review`, `qa`, `test-fix-loop`); a `goto` target not earlier than the halt boundary halts without starting that phase. |
