# Decision Challenges — feat-one-shot-10859-pr3b-required-context

| Item | Class | Ruling |
|---|---|---|
| Draft-light participation for the two new required contexts | technical | Ruled by planning agent wearing the CTO role, 2026-11-07 (no Task-spawn available in this harness): `affected-index-ratchet` and `oracle-review-required` stay OUT of the draft-light gated set — a required context that skips does not report; cost is ~3.4 billed min/run (~2,250 min/wk on drafts), inside the spend the owner accepted in #12129; the lever exists for the four heavy families and a sub-5-min gate does not meet its complexity price. |
| Driver oracle-path list source | technical | Ruled same session: read `RATCHET_ORACLE` from the BASE commit's replay file at runtime (single source of truth); the driver is base-sourced on pull_request per the ci-oracle-lane precedent, so a PR cannot rewrite the classifier that judges it. |
| Member enumeration reuse | technical | Ruled same session: parity-pinned copy of the `merge-queue-cla-verify.sh:89-181` enumeration (O-DOCPARITY byte-equality precedent), not extraction to `scripts/lib/` — lower blast radius on a live production script. |
| Typed-kind set for accept-bad-kind | technical | Ruled same session: the six kinds of runbook ci-pr-affected-activation.md:244 verbatim (`message`, `JSDoc/comment`, `PR-body string`, `help/menu text`, `data row not fed to a read loop`, `code line in a file read only as text`); the ~160 `fixture:`-prefixed legacy rows are grandfathered because the verdicts are diff-scoped. |
| `oracle-review` manifest membership | technical | Ruled same session: `scripts/ci-oracle-review` joins `ci-oracle-lane-suites.txt` (the T3 membership criterion covers the review gate once it is part of the oracle control surface). |
