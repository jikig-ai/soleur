# Decision Challenges: feat-one-shot-12605-scope-grants-phone-e2e

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| F1. How fixtures reach `web_egress=true` | technical | Ruled by CTO agent, 2026-11-22: answer the mint path in the mock for new UUID fixtures only - runs the real read path with no production change or fail-closed bypass |
| F2. Overflow assertion | technical | Ruled by CTO agent, 2026-11-22: keep the literal document check and add a per-surface Range and scrollWidth check - the shell's `overflow-x-hidden` makes the literal check unable to fail |
| F3. Clipped action-class id in `scope-grant-row.tsx` | technical | Ruled by CTO agent, 2026-11-22: leave it out of this PR and track it in #13018 - the brief limits this PR to the mock and one spec, and the defect is live for phone users |
| F4. Dialog copy variant | technical | Ruled by CTO agent, 2026-11-22: `organization_id` null on both fixtures - the "unknown" copy is a superset, so it is the layout worst case |
| F5. Rejected approaches | technical | Ruled by CTO agent, 2026-11-22: do not reuse held fixtures, copy `expectNoHorizontalScroll`, or measure before proving state - each lets the spec pass without proving the layout |
| F6. How the ON state is reached (plan-review challenge: click to ON against a stub) | technical | Ruled by CTO agent, 2026-11-22: keep the mint path - the issue names the `web_egress` true row and the click path would leave it unread |
| F7. `user_session_state` branch and RPC value source | technical | Ruled by CTO agent, 2026-11-22: keep the pointer and return the RPC value from the fixture's row after the `sub` and `p_workspace_id` checks, else null - both row fields become load-bearing |
| F8. Vertical clipping checks on disclosure paragraphs | technical | Ruled by CTO agent, 2026-11-22: delete them and record the Non-Goal, including the confirm button's same blind spot - outside the acceptance, and a reviewer reproduced a false green |
| R1-r. Hidden disclosure text (review dissent on F8) | technical | Ruled by CTO agent, 2026-11-25: amended - a paragraph counts only with non-zero height and a visible text rect; two hiding mutations passed `checkVisibility` alone, and this is not F8's partial-clip check |
| R2-r. Unknown-org notice and the pointer branch (review dissent on F4, F7) | technical | Ruled by CTO agent, 2026-11-25: amended - assert the unknown notice renders, since removing it passed; keep the pointer, which mirrors the production read order and is not load-bearing (the resolver's error fallback reaches the same id) |
| R3-r. Switch position and the surface bound (review dissent on F2) | technical | Ruled by CTO agent, 2026-11-25: amended - bound text by the card and check the switch sits inside it; an off-screen switch passed, and the measured edges (281, 316, 320 against 350) leave the stricter bound stable |
| R4-r. Mobile emulation | technical | Ruled by CTO agent, 2026-11-25: amended - add `isMobile` and `hasTouch`; one line, the baseline passes, and it is closer to the phone users the issue names |
| R5-r. Refresh branch for egress fixtures (review dissent on the Cut List) | technical | Ruled by CTO agent, 2026-11-25: upheld - the session lasts 24 hours and a refresh would fail loudly with a 400; only the `heldSessionFor` docblock changes |
