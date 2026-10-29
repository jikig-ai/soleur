# Decision Challenges — feat-one-shot-11532-xtrace-guard-fallback-probe

Headless one-shot planning record. Every technical ruling resolved by reading
the code/precedent; none deferred to the operator.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Refusal form for content-publisher.sh (conditional `${VAR:+x}` vs unconditional) | technical | Ruled by CTO agent, 2026-10-29: CONFIRM conditional `${VAR:+x}` form - verified no doppler/gh token capture and no `${!name}` indirection, so `unconditional_reason()` returns null and the conditional hatch is the lint's own emitted remedy |
| Credential set covered by the refusal limbs | technical | Ruled by CTO agent, 2026-10-29: CONFIRM 11-name limb set - lint-measured 8 referenced names (incl. in-file constant LINKEDIN_TRACKER_REASON_MISSING_TOKEN) + `DISCORD_*_WEBHOOK_URL` + `GH_TOKEN`; extra limbs always legal under Rule C (`missing = referenced − guarded`) |
| Baseline handling for the remediated file | technical | Ruled by CTO agent, 2026-10-29: CONFIRM baseline row deletion - the baseline file's own header mandates drawdown on remediation and a stale row would suppress future regressions |
| Probe secrets declaration (`secrets=GH_TOKEN,SENTRY_ACTIONS_RO_TOKEN` while the probe never calls `gh`) | technical | Ruled by CTO agent, 2026-10-29: CONFIRM verbatim declaration - both names are bound in scheduled-followthrough-sweeper.yml, declared secrets are the only env the sweeper forwards, and the xtrace refusal covers both; unused GH_TOKEN is accepted over-provisioning |
| Exit-code mapping | technical | Ruled by CTO agent, 2026-10-29: CONFIRM mapping - sweeper sub-vocabulary verbatim: liveness-not-met → 2 NOT YET, every measure failure → 3 CANNOT ESTABLISH, event ≥ cutoff → 1 FAIL, zero → 0 PASS; matches newest sibling precedents |
| `per_page=10` coverage of the FAIL arm | technical | Ruled by CTO agent, 2026-10-29: REFUTED bare newest-first assumption - `sort` is optional and `get_orderby` returns None when absent (no ORDER BY); AMEND the probe to pin `&sort=-timestamp` in the events URL (or bound server-side with `start=`/`end=`) so the FAIL arm is contract-sound |
| `AFFECTED_*_PATHS` array for the new suite | technical | Ruled by CTO agent, 2026-10-29: CONFIRM omit - name-stem derivation `<x>.test.sh → <x>.sh` classifies EDGE (post-deploy-incident-soak.test.sh declares none); re-declare only if `lint-orphan-test-suites.sh` reports UNCLASSIFIED |
| CONTENT_DIR resolution inside the probe | technical | Ruled by CTO agent, 2026-10-29: CONFIRM repo-root relative per sweeper contract, resolved from `BASH_SOURCE/../..` for manual runs + a `*_CONTENT_DIR` env seam for harness fixtures - the standing probe idiom |
| `earliest=2026-11-03T15:30:00Z` | technical | Ruled by CTO agent, 2026-10-29: CONFIRM - publisher cron runs daily 14:00Z; ~1.5h margin covers the `status: published` commit landing on main before the first eligible sweep |
| Scoped advisor consult (plan Step 4.5) | technical | Ruled by CTO agent, 2026-10-29: CONFIRM skip - contract pinned verbatim by directive, every idiom copied from an in-repo proven instance, no architecture choice |
| Brand-survival threshold | taste | `none` — internal CI/ops machinery; refusal is additive-only and cannot alter a non-traced execution path; scope-out override line carried in the plan |
| Plan-review (eng panel + named panel) on this harness | technical | Ruled by CTO agent, 2026-10-29: AMEND - sequential in-process review is acceptable for a MINIMAL machinery plan ONLY with the `Reviewed-Coverage: sequential-fallback` trailer (emit-review-trailer.sh --mode sequential-fallback); undisclosed sequential review is non-conforming regardless of plan size |
