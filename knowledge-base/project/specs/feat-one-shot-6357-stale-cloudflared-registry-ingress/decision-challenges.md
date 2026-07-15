# Decision Challenges — feat-one-shot-6357-stale-cloudflared-registry-ingress

Recorded headless (one-shot pipeline). `ship` renders these into the PR body and files an
`action-required` issue for operator visibility.

## Challenge 1 — Issue #6357's prescribed fix rests on a false premise (User-Challenge)

**Operator/issue stated direction:** "Remove (or repoint) the stale `registry.soleur.ai →
tcp://10.0.1.30:5000` ingress rule — it's a dead origin left over from the registry migration
nbg1→hel1 (#6288)."

**Why the plan diverges (evidence):**
- The rule is **not stale** — it is the live registry-**push** ingress added in #6122 / ADR-096, with
  its own CF Access app + service token (`tunnel.tf:44-60,133-209`); recent active work through #6202.
- The origin is **not dead/migrated** — #6288 moved the registry **region** nbg1→hel1 but kept the
  **private IP `10.0.1.30:5000`** (`variables.tf:45`, `zot-registry.tf:40`). Repointing is a no-op;
  removing breaks CI registry push.
- #6288 is an **OPEN issue** about registry OOM/restart-loop instability — **not a migration PR**. The
  `dial … canceled` errors were the origin being transiently **down**, not a config error.

**Plan's response:** re-scoped from *remove/repoint* to (1) correct the false "stale" premise in
`tunnel.tf` (defuse the destructive mis-fix), (2) add minimal fail-fast `origin_request` to reduce the
shared-tunnel blast radius, (3) add an independent deploy-tunnel monitor. Root cause → #6288;
architectural decoupling → #6178.

**Decision class:** User-Challenge (operator's stated direction would cause a regression). Default is
the operator's direction; overridden here on falsified-premise evidence. Surface at ship for operator
confirmation.

## Challenge 2 — Sibling-degradation mechanism is a reasoned hypothesis, not proven (taste/uncertainty)

The `origin_request` fail-fast targets a **hypothesized** shared-daemon HA-stream saturation
mechanism; cloudflared `--metrics` were never captured during the incident. The mitigation is
defensible (it shortens ~30s-held dials and helps all candidate mechanisms) but is **not a proven
root-cause fix**. The proving signal (cloudflared metrics export) is deferred to #6178. If the operator
prefers to close #6357 as "misdiagnosed; root cause #6288" and defer ALL hardening to #6178, that is a
valid alternative — the plan keeps a tight in-scope deliverable instead.

## Challenge 3 — Plan-review converged to defer the deploy-tunnel monitor to #6178 (taste, applied)

The initial plan added an independent deploy-tunnel monitor (Phase 3). The 3-agent plan-review panel
(DHH, Kieran, code-simplicity) converged that this is out of scope for #6357:
- Kieran: a cheap `cloudflare_notification_policy` for tunnel-health is **structurally blind** to the
  #6357 failure (a sibling-route 502 while the daemon stays up) → green-but-blind.
- DHH + simplicity: the only real detector (CF-Access-authed synthetic 502) needs a service-token
  secret wired into a 3rd party — over-scope for a transient, CI-detected, self-recovered incident.

**Applied:** monitor + cloudflared `--metrics` export deferred to **#6178** (already owns deploy-tunnel
decoupling + telemetry). The plan retains the `## Observability` section + the no-SSH `deploy-status`
probe. Also applied from review: `connect_timeout` is an integer (`5`, not `"5s"`); dropped the
comment-string drift-test + prose-testing ACs. If the operator wants the independent page sooner, it
can be pulled forward into #6178's scope.
