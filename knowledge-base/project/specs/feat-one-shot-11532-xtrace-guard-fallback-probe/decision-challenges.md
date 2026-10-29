# Decision Challenges — feat-one-shot-11532-xtrace-guard-fallback-probe

Headless one-shot planning record. Every technical ruling resolved by reading
the code/precedent; none deferred to the operator.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Refusal form for content-publisher.sh (conditional `${VAR:+x}` vs unconditional) | technical | Conditional — the script binds inherited env credentials and does not acquire any at runtime; verified by running the lint's own `ACQUIRES`/`SIGNAL_INDIRECT` regexes (both false), so `unconditional_reason` returns null and the conditional form is lint-sanctioned |
| Credential set covered by the refusal limbs | technical | Union of the lint-measured `referenced_credentials` (8 names incl. `LINKEDIN_TRACKER_REASON_MISSING_TOKEN` — an in-file constant, unset at preamble time so harmless in the test) plus `DISCORD_BLOG_WEBHOOK_URL`, `DISCORD_WEBHOOK_URL`, `GH_TOKEN` (real credentials the `_TOKEN|_KEY|_SECRET|_PASSWORD|_PAT` name regex does not match); extra limbs are always legal under Rule C (`missing = referenced − guarded`) |
| Baseline handling for the remediated file | technical | Delete the `scripts/content-publisher.sh` row from `lint-shell-trace-credential-refusal.baseline.txt` — the file's own header mandates drawdown on remediation; a stale row would suppress future regressions |
| Probe secrets declaration (`secrets=GH_TOKEN,SENTRY_ACTIONS_RO_TOKEN` while the probe never calls `gh`) | technical | Keep both — the operator directive declares both verbatim ("the probe MAY use gh if needed"); the xtrace refusal covers both names; declared secrets are the only env the sweeper forwards |
| Exit-code mapping | technical | Liveness-not-met → 2 NOT YET; every measure failure (missing/bad token, missing tool, non-200, unparseable `.data`, unpinned org/host) → 3 CANNOT ESTABLISH; event ≥ cutoff → 1 FAIL; zero events → 0 PASS — per directive + convention vocabulary |
| `per_page=10` coverage of the FAIL arm | technical | pending - assumed: the events endpoint returns newest-first (same shape the sibling soak parses), so any `timestamp >= 2026-10-29T17:00:00Z` event sits inside page 1; directive fixes the query at per_page=10 |
| `AFFECTED_*_PATHS` array for the new suite | technical | Omit — name-stem derivation `<x>.test.sh → <x>.sh` classifies the registration (verified: `post-deploy-incident-soak.test.sh` declares none); re-declare only if `lint-orphan-test-suites.sh` reports it UNCLASSIFIED |
| CONTENT_DIR resolution inside the probe | technical | Repo-root relative per the sweeper contract (probes run from the checkout root), resolved from `BASH_SOURCE/../..` for manual runs + a `*_CONTENT_DIR` env seam for the harness fixtures |
| `earliest=2026-11-03T15:30:00Z` | technical | Directive verbatim — publish cron 14:00Z + ~1.5h for the `status: published` commit to land on main |
| Scoped advisor consult (plan Step 4.5) | technical | Skipped — the SKILL's own skip clause applies: contract pinned verbatim by the operator directive, every idiom copied from an in-repo proven instance, no architecture choice |
| Brand-survival threshold | taste | `none` — internal CI/ops machinery; refusal is additive-only and cannot alter a non-traced execution path; scope-out override line carried in the plan |
| Plan-review (eng panel + named panel) on this harness | technical | Ran in-process — Devin subagent has no Task tool; applied the panel's own checks (standing AC-independence check, simplicity/convention/correctness lenses, named-panel relevance scan — CTO activates on code files, found nothing blocking); no Taste/User-Challenge findings to surface |
