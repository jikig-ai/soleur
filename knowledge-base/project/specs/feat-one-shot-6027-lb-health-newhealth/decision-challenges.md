# Decision Challenges — feat-one-shot-6027-lb-health-newhealth

Headless one-shot planning run for epic #6027's AC4 alerting leg. This harness
has no Agent/Task tool, so the `soleur:plan-review` panel, domain leaders, and
any `soleur:engineering:cto` ruling could not be spawned; technical rows are
recorded with their evidence per the technical-ruling-delegation contract.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| `new_health = ["Unhealthy"]` (not `["Healthy"]`, not both) | technical | Decided inline — evidence-backed, no spawn needed: CF's documented `load_balancing_health_alert.new_health` vocabulary is `{Unhealthy, Healthy}` (developers.cloudflare.com health-monitor-notifications + notification-available docs), the CF API rejected `["Down"]` with Error 17108 (run 41504420340), and the ask pins origin-down-only paging — "recovery paging stays deliberately out of scope". `["Unhealthy"]` is the only value satisfying all three. |
| Brand-survival threshold `aggregate pattern` | taste | assumed: aggregate pattern — a missed page on origin-down converts a single-host failure into a sitewide outage for every active user; `single-user incident` understates it. Challengeable per the template's own marker. |
| Post-merge re-dispatch stays operator-authorized (not baked into ship/merge automation) | technical | pending - assumed: keep the dispatch manual — `cf-lb-overlay.yml`'s header fixes a per-command operator go-ahead for every production write and the ask forbids changing authorization semantics; automating the dispatch is a different change. |
| `plan-review` panel + scoped advisor + domain leaders not spawned (no Agent tool in this harness); inline self-review applied | technical | pending - assumed: no blocking panel re-run before `soleur:work` — every gate ran in-process against measured evidence; residual disclosed in the plan's Enhancement Notes (`Reviewed-Coverage: sequential-fallback`). |
| `credentials_required` waiver + `BASELINE_DECLARED_PROBES` 92→93 bump (second code file beyond the asked value+comment) | technical | pending - assumed: required by the repo-global corpus ratchet (`preflight-discoverability-test.test.ts` G1) — the sharp-edges catalogue (#8651 entry) prescribes the bump in the same PR or the bun battery reds; an enforcement consequence, not scope widening. |
