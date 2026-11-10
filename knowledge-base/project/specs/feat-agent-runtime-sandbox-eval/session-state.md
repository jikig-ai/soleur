# Session state: feat-agent-runtime-sandbox-eval (2026-11-10)

Plan: `knowledge-base/project/plans/2026-11-09-feat-agent-runtime-sandbox-eval-injector-first-plan.md`. Tasks: `tasks.md` here. CTO rulings: `decision-challenges.md` here (F-a..F-g, R1..R42, D1..D4; R36..R42 are the review rulings).

## Where it stands

- Phases 1 to 3 done. The GO recorded on run 42823659776 is **withdrawn** (CTO R40): review found criterion 3 reported pass with two required items unmeasured, and that iron-proxy cuts request bodies above 1 MiB with no error.
- Review (13 seats) fixed inline on this branch: hook raw request-target parsing, GraphQL/method ambiguity refusals, consume no longer raced by the deadline, CONNECT and plaintext guards, the 3 MiB body cap, git's flush-only push probe (commits from 5bf076b697 on), and harness fixes (verdict instrument, unmeasurable harness inputs, criterion 3/6/8/9 probes, deadline, local-run DB guard).
- Each new hook/policy guard is mutation-proven in a sandbox (17/17 killed against a green control).

## Next

1. Land the harness patch and the new arms the review rulings require (R36 and R37 c6 probes; R38 recorded GraphQL out-of-allowlist probe; R39 about-2-MiB live push; R40 about-4-MiB refused push and the HTTP/1.1 plus HTTP/2 same-connection arm; the live GraphQL mutation lifecycle in criterion 3).
2. Push; the spike workflow re-runs. Rewrite `injector-spike-results.{json,md}`, ADR-325 "Measured outcome" and the ADR-311 addendum's measurement paragraph from the new run only.
3. `soleur:compound`, then `soleur:ship`. The PR body's first line names both merge effects (CTO R41). Re-merge main once #12559 and #12562 land.
