# Decision challenges - feat-one-shot-10499-route-technical-forks-to-cto

Plan-phase forks, all technical; each was put to `soleur:engineering:cto` in one batched spawn (Rule interface, no AskUserQuestion). No item reached the operator.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| T1 where the canonical final-report and seat-dissent wording lives | technical | Ruled by CTO agent, 2026-10-18: a new section 8 in technical-ruling-delegation.md holds the procedure, review and work carry a short operative paragraph plus link, and one content-anchor test in components.test.ts pins the anchors - both SKILL.md bodies are 8 and 10 bytes under their ceilings, so inline text cannot fit and an unpinned paragraph is lost under byte pressure |
| T2 byte-ceiling strategy for review and work SKILL.md | technical | Ruled by CTO agent, 2026-10-18: net change <= 0 bytes per file by compressing the text that restates delegation section 3 (review item 4, work hard gate), moving unrelated text to a reference only as a last resort - the ceilings are read from the merge base, so a same-PR raise is impossible and a separate raise PR defeats the ratchet |
| T3 shape of the seat-dissent-from-ruling rule | technical | Ruled by CTO agent, 2026-10-18: read recorded Ruled-by lines once before the seats spawn and hand them to every seat, tag contradictions, send all of them (and any doubtful match) to the CTO in one batched spawn to uphold or amend, record an upheld or amended row against the original item id, count it in the two-spawn cap - seats cannot flag a ruling they never saw, and the orchestrator must not adjudicate a contradiction itself |
| T4 enforcement scope (prose gate vs hook or gate extension) | technical | Ruled by CTO agent, 2026-10-18: prose gate plus the content-anchor test only; extending the cue library or technical-ruling-gate.sh for an Owner-decisions heading is a separate change tracked in #10502 - the closing-prose hook is cue-based, fail-open and inert inside a one-shot loop, so extending it buys nothing on the failing path |
