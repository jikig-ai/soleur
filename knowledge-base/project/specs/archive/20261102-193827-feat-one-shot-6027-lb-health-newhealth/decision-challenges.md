# Decision Challenges — feat-one-shot-6027-lb-health-newhealth

Headless one-shot planning run for epic #6027's AC4 alerting leg. On this
harness the plugin agent roster is unavailable, so domain rulings were
obtained via a `run_subagent` spawn of the `soleur:engineering:cto` agent
definition (one batched Rule spawn, 2026-11-02; `cto_spawns=1`).

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| `new_health = ["Unhealthy"]` (not `["Healthy"]`, not both) | technical | Ruled by CTO agent, 2026-11-02: `["Unhealthy"]`-only is correct — CF's documented `load_balancing_health_alert.new_health` vocabulary is `{Unhealthy, Healthy}` (a single-element subset is legal), `["Down"]` is measured invalid (Error 17108, run 41504420340), the ask pins origin-down-only paging with recovery paging deliberately out of scope, `["Healthy"]`-only would never page on origin-down, and both-values would ship unverified recovery paging. |
| Brand-survival threshold `aggregate pattern` | taste | assumed: aggregate pattern — a missed page on origin-down converts a single-host failure into a sitewide outage for every active user; `single-user incident` understates it. Challengeable per the template's own marker. |
| Post-merge re-dispatch stays operator-authorized (not baked into ship/merge automation) | technical | Ruled by CTO agent, 2026-11-02: re-dispatch stays operator-authorized (manual) — `cf-lb-overlay.yml` header fixes the authorization model verbatim: "per-command operator go-ahead at dispatch"; automating it into ship/merge automation would silently change that model, and a production-mutating workflow dispatch is an operator-class act regardless. |
| `plan-review` panel + scoped advisor + domain leaders not spawned (plugin agent roster absent on this harness); inline self-review applied | technical | Ruled by CTO agent, 2026-11-02: inline self-review stands; no blocking panel re-run — the alternative (halting) leaves the CF policy uncreated and origin-down unpaged for a one-value mechanical correction backed by a measured API oracle; `Reviewed-Coverage: sequential-fallback` residual is disclosed in the plan's Enhancement Notes. |
| `credentials_required` waiver + `BASELINE_DECLARED_PROBES` 92→93 bump (second code file beyond the asked value+comment) | technical | Ruled by CTO agent, 2026-11-02: waiver + 92→93 bump is required — `preflight-discoverability-test.test.ts` G1 counts plans under `knowledge-base/project/plans` whose observability block declares a non-empty `credentials_required`; this plan declares one, so the corpus count becomes 93 and the same-PR bump is an enforcement consequence, not scope widening. |
