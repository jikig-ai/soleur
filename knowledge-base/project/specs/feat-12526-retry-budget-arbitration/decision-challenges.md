# Decision challenges

Technical forks were ruled by the CTO on 2026-11-16 (Rule interface). The CPO's fail-only advice and the CLO's permitted-with-guardrails note are assessments. They are in the brainstorm under Domain Assessments. They are not rows here: the Rule interface was not used for either, and dropping the three verbs the issue asked for was not adopted.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| T1 verb contract | technical | Ruled by CTO agent, 2026-11-16: one shared exemption, not a lifted stop. continue runs exactly one iteration while capped= stays set and the cap is not raised. goto may name only plan, work, review, qa, or test-fix-loop and must not resume ship or merge. continue and goto share that exemption. The second exhaustion is fail with no second spawn. fail is today's halt plus an on-disk ledger. A missing or unparseable verb is fail - incr does not read the latch, so the extra iteration does not clear capped=, and the stop hook can emit the keep-alive block exactly once. Dissent: ADR-268 lines 79-80 can be read as making continue and goto infeasible, because a capped run is resumable only by raised caps or --reset. |
| T2 first attachment | technical | Ruled by CTO agent, 2026-11-16: the first attachment is one-shot's halt on a child's budget-capped marker, and not one-shot's own agent_rounds gate - only the parent owns the phase list and can execute goto. continue or goto spends the single exemption and does not clear capped=. fail is the halt plus the ledger. A missing or empty attempt history is fail with no spawn. A review seat stop is in scope only after that child marker exists. Dissent: attaching first at test-fix-loop's fix_rounds stop is the smaller blast radius but drops goto. |
