# Decision Challenges — feat-one-shot-8978-cold-load-first-paint

Persisted by `soleur:plan` running headless (one-shot pipeline, no TTY). Rendered by `soleur:ship` into the PR body per the plan skill's headless taste/user-challenge convention.

## 1. Warm FCP ≲500ms may be unreachable by arithmetic (User-Challenge)

The issue's DoD asks for "FCP ≲500 ms on the warm path". Measured floor today: authenticated warm document TTFB ~0.65s (the request alone exceeds the AC), and transport alone costs ~155ms unauthenticated. The plan's Phase-1 items (route migration + render-path `getUser` removal via the minted identity header) remove ~600ms of measured warm tax — plausible but thin. If the probe still reads >500ms warm, the honest outcomes are (a) accept the stated-verified bound per DoD item 2, or (b) reach for SW app-shell caching of an unauthenticated skeleton — rejected in the plan's Cut List because FCP of a skeleton is not "first meaningful content" and it sits next to GAP-G's `no-store` auth-document contract. The operator's stated direction (the AC as written) is the default; this note records that the AC may need reinterpretation.

## 2. SW generic-shell fast-paint (Cut List, taste)

An app-shell `sw.js` pattern could paint generic chrome in <500ms regardless of origin. Cut because: (a) it satisfies the letter (FCP) but not the intent (first meaningful content); (b) any real-document caching collides with the ADR-067/GAP-G no-store boundary. If the operator wants the skeleton-paint reading of the AC, this becomes a separate UX-gated change.

## 3. Fold-in of #8969 (mechanical, applied)

#8969's fix sketch (`sec-fetch-mode`/`request.mode` classification) is Phase-0 item 0.1 — folded in because it is a prerequisite for P4 measurement (the SW-controlled path is the dominant real-session case). `closes:` carries [8978, 8969].
