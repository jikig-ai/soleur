# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-02-fix-resend-inbound-webhook-500-dispatch-outage-plan.md
- Status: complete

### Errors
None. All mechanical gates passed (4.5 network-outage, 4.55 downtime/cutover, 4.6 user-brand,
4.7 observability, 4.8 PAT-shape, 4.10 encryption posture; 4.9 skipped — no UI surface).
Telemetry emitted for the two gates that fired. Citation, rule-ID, and issue-number checks
clean; verify-the-negative sweep returned 15/15 confirmed.

Scope verification (one-shot post-subagent gate): `git diff origin/main...HEAD --name-only`
after a fresh `git fetch origin main` listed only the plan file and
`knowledge-base/project/specs/feat-one-shot-resend-inbound-webhook-500/tasks.md`. No
out-of-scope source/workflow files were touched — the planning subagent stayed within its
plan-only mandate.

### Decisions
- **Root-caused to infrastructure, not the route.** Every observed 500 is the route's
  ADR-055 transient-dispatch path firing correctly: `inngest.send()` gets
  `ECONNREFUSED 10.0.1.40:8288`, the dedup row is released, 500 is returned so the svix
  retry is honoured. H2/H5/H6 refuted from committed code; H1 near-refuted by the errno;
  H3 refuted and H4 confirmed via the Hetzner API. Onset recovered as
  2026-07-30T15:13:06Z (~27h before the vendor alert), which the plan had recorded as
  UNKNOWN.
- **Durable-claim shape: extend `processed_resend_events`, not a new outbox table**;
  persist-then-200 unconditional, with the reconciler as sole dispatcher. Rejected the
  two-table shape (distributed-transaction hazard) and persist-only-on-failure
  (incident-only recovery code).
- **Retention: delete-on-drain rejected in favour of null-PII-and-keep-tombstone** —
  delete-on-drain would destroy the ADR-037 replay defense. Sweep uses a terminal-state
  allowlist, never an age-only predicate.
- **Observability fix contained to the route** (wrapper `Error` with `cause`), explicitly
  not `server/logger.ts`. Drain alarm is a `sentry_cron_monitor` off the Inngest
  substrate, since an Inngest-fired alarm cannot run during the outage it guards.
- **Probe-first preserved but de-merged** — Phase 0 produces no PR (all reads are
  read-only API calls), time-boxed ≤4h, gating on the first failing hop rather than on a
  single-winner hypothesis.

### Components Invoked
`soleur:plan`, `soleur:deepen-plan`; agents: `repo-research-analyst`, `learnings-researcher`,
`engineering:cto`, `legal:clo`, `product:cpo`, Fable advisor consult (ADR-083),
`data-integrity-guardian`, `observability-coverage-reviewer`, `spec-flow-analyzer`,
verify-the-negative sweep; tooling: `scripts/betterstack-query.sh`, `scripts/sentry-issue.sh`,
Sentry + Resend + Hetzner APIs, `gh`, Doppler.

### Decisions — 2026-08-04 work session (registry budget, second heartbeat, web-2)

- **REGISTRY_BUDGET was measuring a fiction, and the fiction was passing.** The node model in
  `cloud-init-user-data-size.test.ts` reports 31,572 B; terraform's own `base64gzip` reports
  **32,156 B** — already OVER the 32,000 sub-cap the test was green against. Decomposed and
  measured against the as-written files: 340 B from `"x".repeat(n)` stand-ins (every registry
  template var is a non-file value and five carry real entropy), 228 B from Go-vs-node zlib match
  choices, 16 B from level 9 vs Go's DefaultCompression 6. Real headroom is **612 B**, not the
  ~1,196 B recorded — roughly half.
  - Shipped `apps/web-platform/infra/registry-userdata-budget.sh` (the
    `git-data-userdata-budget.sh` shape) as the AUTHORITATIVE gate: renders through terraform,
    measures with `base64gzip`, hard cap 32,768 + a 32,450 sub-cap tripwire. Registered in
    `infra-validation.yml` in the job that already installs terraform with
    `terraform_wrapper:false` — registering it anywhere else would SKIP into a fake gate (#6454).
  - Node `REGISTRY_BUDGET` retained as a cheap fast-suite proxy, re-baselined to **31,866** with a
    new `REGISTRY_NODE_OFFSET = 584`, so `BUDGET + OFFSET` lands exactly on the script's sub-cap
    and the two gates trip at the same REAL size.
  - `registry-userdata-budget.test.sh` (43 assertions, registered) pins the honesty properties, not
    just the verdict: stub LENGTH **and** entropy (a same-length low-entropy stub gzips away and
    restores the optimism), the committed-value drift guard against `zot-registry.tf`'s locals, and
    all four arms driven behaviorally against sandbox copies with a control first — over-sub-cap,
    over-cap, fail-closed render (exit 2), terraform-absent SKIP.
  - Stub lengths are MEASURED, not assumed: a live length-only probe gave 72 B heartbeat URLs (not
    the 87 first drafted) and a 43-char token body. The first draft over-measured by ~30
    incompressible bytes; on a sub-1 KB margin a pessimistic gate is its own defect.

- **Second heartbeat: NO — keep one AND-folded beat.** architecture-strategist read the §1
  `zot_probe_repo` fold as contradicting the anti-masking rule 30 lines below it. It does not, and
  the direction is the whole point: OR-masking (beat fires if EITHER repo serves) loses alarms;
  this fold is AND (`web-zot-consumer-probe.sh` suppresses unless EVERY repo returns 200, 401 exits
  3 loudly), so a broken bootstrap repo suppresses the beat and absence alarms. AND can only
  over-suppress, never under-suppress — it strictly ADDS detection, since nothing verified the
  bootstrap repo before. The real cost is DISCRIMINABILITY, repaid by the suppress branch naming
  the offending repos in journald (Layer 3) rather than by a second beat, which would cost a
  heartbeat + doppler_secret per host and a second URL in the EnvironmentFile that feeds
  `terraform_data.web_zot_consumer_probe_install`'s `triggers_replace` (server.tf:686) — i.e. it
  re-provisions web-1. Adding a second never-observed gate to a host whose first gate has not met
  its promotion criterion is the wrong trade. §3's rule was SHARPENED to name the OR direction so
  it stops reading as a ban on all folding. **Named residual:** the fold changed the SUBJECT of an
  existing beat — `soleur-web-zot-consumer-web-1` now attests web-platform AND bootstrap, so
  absences read across 2026-08-04 are ambiguous.

- **web-2 is NOT retired; the comment was.** `variables.tf:112` records a DIFFERENT web-2 RE-ADDED
  2026-07-24 (#6459, ADR-143, hel1/10.0.1.11/cpx22) — not the fsn1 warm standby #6538 retired
  2026-07-17 — and it is in `var.web_hosts`' default map, so `for_each` already materialises web-2
  instances of both heartbeats and both doppler_secrets. What it does not materialise is a FEEDER:
  the probe/guard installers are hardcoded to web-1, so web-2's beats stay `paused = true` and the
  ADR-117 arm never fires. Corrected in `web-probe.tf` plus two siblings carrying the same stale
  claim (`inngest-host.tf` sdk_url, `inngest.tf` two-scheduler block). The `inngest.tf` fix needed
  care: deleting "web-2 retired" left the "TWO co-located schedulers" sentence dangling as a
  live-state claim, so the replacement states the actual mechanism — `web_colocate_inngest` flipped
  default-false 2026-07-11 and web-2 was born after it — and names why that matters: the variable
  is GLOBAL, so flipping it re-arms the 40 > 30 pool ceiling on either host's next fresh boot.

## Carried into Work Phase
- **Live legal exposure (Phase 1.0, cannot ride behind Phase 2):** statutory mail (DSAR
  Art. 12(3), service of process, regulator contact, or an inbound processor breach
  notice under Art. 33's 72h clock) arriving in the outage window was never escalated by
  PA-27. Phase 2's durable claim prevents recurrence but does not discharge a clock
  already running.
- **Answers to the brief's two questions:** the Resend webhook is still `status: enabled`
  (re-verified 2026-08-02 11:17Z), so no re-enable is required today; the *triage
  delegation* was lost for ≥15 distinct emails, but the *mail* was not — ADR-055's Sieve
  rule is forward-and-keep, so Proton should hold every original. Phase 1.0 verifies the
  keep-copy rather than assuming it.
