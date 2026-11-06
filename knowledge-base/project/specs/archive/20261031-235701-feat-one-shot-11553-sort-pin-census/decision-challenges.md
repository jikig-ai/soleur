# Decision Challenges — feat-one-shot-11553-sort-pin-census

Headless one-shot planning record. Every technical ruling resolved by reading
the code/precedent; none deferred to the operator.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Lint home: new rule in `lint-followthrough-varq-ban.sh` vs standalone lint file | technical | Ruled by CTO agent, 2026-10-31: CONFIRM rule 6 inside the existing family file - it already accreted rules 2-5 onto one probe-set walk with per-rule counters/floors/exit contract and is registered once in `test-all.sh:5939-5940`; a standalone lint duplicates the probe-set machinery and needs new registration for zero property gain |
| Pin form for the 6 row-selecting probes (`&sort=-timestamp` vs `start=`/`end=` bound) | technical | Ruled by CTO agent, 2026-10-31: CONFIRM `&sort=-timestamp` - `statsPeriod` and `start`/`end` are mutually exclusive params, so bounding would replace each rolling window with computed timestamps (more machinery, same property); the mirror `discord-blog-webhook-fallback.sh:184` pins sort |
| `anthropic-admin-key-6297.sh` disposition (pin vs bound vs exempt) | technical | Ruled by CTO agent, 2026-10-31: EXEMPT via structure - the call is a `field=count()` aggregate (`.data[0]["count()"]`); ordering is meaningless on a one-row aggregate and `sort=-timestamp` on a select that omits `timestamp` risks a 400, so the lint exempts `field=<name>()` function-field calls rather than carrying an opt-out marker |
| Uniform pin on order-independent verdicts (all 7 are presence/count checks) | technical | Ruled by CTO agent, 2026-10-31: CONFIRM uniform pin - the convention states the rule unconditionally ("pin an ordering on every Sentry `/events/` coverage argument") and a lint cannot mechanically judge whether a verdict leans on ordering; the pin is behavior-neutral on presence/count verdicts and future-proofs the latent "newest N covers the window" argument |
| `sync-health-residual-5689.sh` (census member 8) | technical | Ruled by CTO agent, 2026-10-31: EXCLUDE from fix set - its call is `/api/0/projects/<org>/<project>/issues/` (statsPeriod=14d + limit=25), not `/events/`; issue census misclassified it. Untouched; recorded in the plan's census reconciliation so the post-change lint hit-count doesn't read as a missed probe |
| Per-probe `.test.sh` pin re-assertion for the 6 pinned probes (mirror pattern) | technical | Ruled by CTO agent, 2026-10-31: CUT - rule 6 re-asserts the bound harness-wide, strictly stronger than per-probe greps; only 1 of the 8 census members has a suite. One characterization assertion added to the existing `anthropic-admin-key-6297.test.sh` pinning the `field=count()` exemption basis instead |
| Census misclassification surfaced to operator | operator (scope) | deferred to ship - issue says 8 probes, true `/events/` set is 7 (one is `/issues/`); work proceeds on the true set per technical ruling above; `ship` Phase 6 renders this row into the PR body and files an `action-required` issue if the operator wants the issue text corrected |
| Brand-survival threshold | taste | `none` - internal CI/ops machinery; no user-facing artifact, no new data egress, no sensitive-path match against the canonical preflight regex |
| Plan-review panel shape on this harness | technical | Ruled by CTO agent, 2026-10-31: sequential in-process review WITH `Reviewed-Coverage: sequential-fallback` disclosure - Devin subagent has no Task/Skill spawn; same ruling as feat-one-shot-11532 |
| Scoped advisor consult (plan Step 4.5) | technical | Ruled by CTO agent, 2026-10-31: performed in-process on the riskiest phase (rule-6 folding/matching) - two refinements applied (physical-line citation, boundary-safe param regex); no operator-visible change |
