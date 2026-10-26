# Session state: feat-egress-audit-read-path (#9545 PR2, PR #11115)

## Review dedup ledger (panel SHA bdda54a4d795b2216fa3fc6e24e5e4b3678128d6)

dedup: ~95 raw -> 26 unique. Structural-cause roll-up: (1) the loader's fault matrix (op x level x paged x tested) was never enumerated, so silent arms, a paging-class mismatch and an unreachable "unknown" branch co-occur; (2) comments and prose asserting unmeasured facts (refresh pending, flag outage, "bounded", Cache-Control, owner notice, "cannot learn which person"); (3) tests pin endpoints but not the wire (page to loader, page to toggle); (4) the page query's cost is bounded by nothing but the role timeout.

| raw finding | canonical defect key | reporting seat(s) | planned fix |
|---|---|---|---|
| any 42501 treated as member denial, grant drift silent | rpc-42501-undiscriminated | observability, security, test-design | loader predicate on constant message + mirror + tests |
| readWebAccess errors unmirrored | web-access-read-silent | observability, code-quality, patterns | warn mirror op web_access_read (unpaged) |
| Flagsmith outage reads collection=false, not unknown | flag-fallback-not-unknown | code-quality, patterns, architecture, legal, user-impact | detailed flag read, tri-state for readers |
| page query generic-plan cliff, full group ranking, scan unbounded | page-query-cost | performance, security, user-impact | force_custom_plan, top-N, further bound per CTO |
| RPC lacks jti-denylist re-assert | rpc-jti-denylist | data-integrity | per CTO ruling |
| sum()::bigint overflow; shallow payload guard; probe skew predicate | rpc-numeric-and-probe-edges | data-integrity, performance, user-impact, code-quality | clamp, per-field guard, last_seen predicate in probe |
| card workspace_read_error can page | alert-op-classification | observability, patterns, architecture, code-quality | distinct unpaged op for the card |
| paged mirrors lose the cause | mirror-no-pg-code | observability | pg_code tag |
| op-contract test restates ops, no-op filter | contract-test-tautology | test-design, observability, patterns | derive ops from loader source |
| unbounded pointer/org reads, serial sequencing | loader-latency-bounds | patterns, performance, code-quality | parallel start + bounded() |
| refresh button pending/focus/comment | refresh-button-pending | patterns, code-quality | useTransition, comment, focus |
| agent prompt addendum "every decision is logged" | agent-prompt-overclaim | agent-native | reword |
| Cache-Control "private, no-store" claim | cache-header-claim | security | per CTO |
| sentry README rule count | sentry-readme-count | patterns | 48->49, 45->46 |
| test gaps (filters, overflow-only, wiring, defaults) | test-wire-gaps | test-design | tests |
| types/props/constants hygiene, casts, dead exports | type-hygiene | architecture, patterns, user-impact, code-quality | move types, required props, constants |
| mobile table semantics, title-only tooltip | view-a11y | code-quality | roles + visible text |
| anti-slop TWO-ICON-LIBS (false positive) | anti-slop-annotation | patterns | annotation per precedent |
| C4 read-path edge | c4-read-path | architecture | description + regenerate |
| legal: owner-notice claim, unknown sentence, processor/controller, DPIA overclaim, retention wording, sign-off | legal-copy-drift | legal-compliance-auditor, git-history | per CLO ruling |
| plan/runbook observability layer citation, triage section | plan-runbook-observability | observability | plan edit + runbook section |
| dsar-allowlist comment overstates | dsar-comment | git-history | reword |
