## Summary

<!-- What does this PR do? -->

Closes #

## Changelog

<!-- Required for plugin changes (plugins/soleur/).
     Describe what changed in user-facing terms: Added, Changed, Fixed, Removed.
     CI uses this section as the GitHub Release body at merge time.
     For non-plugin changes, write "N/A" or delete this section. -->

## Type of Change

- [ ] Bug fix
- [ ] New feature (agent, command, or skill)
- [ ] Documentation update
- [ ] Breaking change

## Testing

- [ ] I have tested these changes locally

## Observability (server-side changes only — `hr-observability-layer-citation`)

<!-- Delete this section if your PR does not add server-side code, infra, or new failure modes. -->

**Where will this surface in Sentry / Better Stack if it breaks?** Provide a concrete query URL or CLI invocation an operator can run without SSH:

```
e.g. curl -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://de.sentry.io/api/0/organizations/jikigai-eu/issues/?query=feature:<feature-tag>" | jq -r '.[].title'
```

**Which observability layer covers each new failure mode?** (One per failure mode; see `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md`.)

- [ ] Inngest sentry-correlation middleware (`server/inngest/middleware/sentry-correlation.ts`)
- [ ] Pino → Sentry breadcrumb mirror (`server/logger.ts` `hooks.logMethod`)
- [ ] Vector journald shipper (`infra/vector.toml`)
- [ ] Vector host_metrics (same agent)
- [ ] Sentry `release` context (`sentry.{server,client}.config.ts`)
- [ ] Sentry monitor (cron checkin)
- [ ] Better Stack heartbeat / monitor

## Vendor Compliance (if adding external services)

<!-- Delete this section if your PR does not add new vendors, infrastructure, or SaaS dependencies -->

- [ ] Expense ledger updated (`knowledge-base/operations/expenses.md`)
- [ ] DPA verified and signed (link to vendor DPA page)
- [ ] Privacy policy updated (both `docs/legal/` and `plugins/soleur/docs/pages/legal/`)
- [ ] Data protection disclosure updated (Section 4.2 processor table)
- [ ] GDPR policy updated (Sections 2.2, 3.x, 4.2, 6, 10)
- [ ] International transfer mechanism documented
