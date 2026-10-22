# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-22-fix-inngest-canary-inspect-duplicate-env-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None blocking. Follow-ups filed by the planner: #10855, #10856.

### Decisions
- Scrub INNGEST_BASE_URL and NODE_EXTRA_CA_CERTS from the env-file after the resolver; inspect check stays strict (CTO ruling).
- Scrub aborts only a strict (https) deploy; otherwise logs and continues.
- canary_failed names cause=inspect_failed|url_count|url_value|ca_count|ca_value plus clamped counts.
- Red test commit precedes the fix commit; resolver suite changes in same PR.
- PR stops before merge; owner types the merge go.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan, CTO and 8 review agents (planner).

## Review dedup ledger (panel SHA 31a081137c, 12 seats; fixes in f495f95fad)

structural-cause roll-up: durable runbook/ADR text was appended while the rows and sentences it supersedes stayed stale (A3 row, resolver-events reason sentence, ADR root cause), a proxy-for-fact claim ("Doppler pins it", "revert restored http") was written as observed, and read mechanics (T0, timestamps, deploy key) were left out. Seat that should have enumerated it: architecture (A3 row) and history (claims).

| raw finding | canonical defect key | reporting seat(s) | planned fix commit |
|---|---|---|---|
| A3 row says resolved is the only web-2 evidence; no apply-delivered precondition | stale durable runbook row | architecture | f495f95fad |
| Resolver-events paragraph names only canary_inngest_link_failed; reason prefix family | stale reason catalog sentence | observability, agent-native, pattern | f495f95fad |
| ADR states Doppler pin and revert result as observed; no rejected alternatives | claim stronger than evidence | history, architecture, security | f495f95fad |
| T0 not printed on failed flip; jq lacks timestamp; negative filter not executable; hostnames; same-deploy ambiguity | per-host read mechanics | agent-native, observability | f495f95fad |
| "either name" overclaim; env_scrubbed row says snapshot pins | CA arm unreachable past the overlay | history, security, agent-native | f495f95fad |
| composition-defect wording for inspect_failed | comment/doc accuracy | code-quality, history | f495f95fad |
| terminator treats . and - as ends of a name | scrub regex breadth | data-integrity | f495f95fad |
| call site re-types the reason; stale reason on non-strict | duplicate truth for the scrub reason | code-quality, data-integrity, pattern | f495f95fad |
| 10# can abort the shell; clamp written five times | count normalisation | code-quality, pattern | f495f95fad |
| M13b anchors splice a bare line; no regex/REQUIRED_ENV parity | test anchors and parity | pattern | f495f95fad |
| count anchors, precedence, clamps, locale flags unpinned (mutation survivors) | test power gaps | test-design, structural-enumeration | f495f95fad |
| T1 removed=1 unanchored; DEPLOY_ABORT line unasserted; SC2010 | test precision | code-quality, observability | f495f95fad |
| plan User-Brand omits #10543, 502, session cuts, half-flipped fleet, web-2 write | plan scope-outs | user-impact | f495f95fad |
| postmerge deploy-status table lacks the new reasons | doc coverage | data-integrity | f495f95fad |
| per-stage operator action missing | runbook gap | observability | f495f95fad |
| flip script closing hint queries only resolved; web-2 in-place write (#10856); overlay NBSP/BOM grep (#10855) | pre-existing | agent-native, user-impact, security | already tracked (#10856, #10855); no new filing |
| docker-run-tuple.py docstring; plan-id labels in comments; stage=write token reuse | settled ruling or cosmetic | architecture, pattern, code-quality | won't fix (ruling: census unchanged; labels cosmetic) |

Coverage consult (session model): three leads (abort-path parity, _gak_tmp aliasing, mock fidelity), each verified against the diff and dropped: pending scheme/CA-reset state is only committed after the prod start, the overlay clears _gak_tmp on every continue path, and real-Docker evidence covers the mock premise.

