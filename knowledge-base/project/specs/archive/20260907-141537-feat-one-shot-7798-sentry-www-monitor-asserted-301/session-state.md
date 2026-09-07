# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-09-07-fix-sentry-www-monitor-asserted-301-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Scope verification: `git diff origin/main...HEAD --name-only` → `plans/`, `specs/`, and the
  lefthook-generated `knowledge-base/INDEX.md` (6400→6402, the two new artifacts). No
  product-code or workflow files touched — plan-only mandate held.
- Post-plan collision re-probe: plan frontmatter `issue: 7798` / `closes: 7798` — identical to
  the ref cleared at Step 0a.5, so no new target was discovered and no re-probe was required.

### Errors

- **IaC write-guard denial** on the first plan-body write: the Research Reconciliation quoted
  the issue's phrase "out-of-band", which the hook matches. Resolved by rephrasing to
  "originated outside Terraform" — deliberately NOT via the guard's ack opt-out, which would
  have falsely asserted a reviewed infrastructure step.
- **markdownlint blocked the first commit** (bare-URL `www.`, a space inside a code span, two
  double-blank-lines). Fixed; both artifacts lint clean.
- **Four substantive research errors, caught by plan-review and corrected in-plan** (recorded
  rather than quietly fixed, since each instantiates a class the repo's Sharp Edges warn about):
  (1) concluded no `-target=` coverage guard existed after reading only the first `describe` of
  a 250 KB test file; (2) ran the stale-claim sweep with `':!knowledge-base'`, excluding the
  corpus that hid an accepted ADR making now-false claims; (3) counted Better Stack quota from
  `.tf` declarations rather than live state, missing an unmanaged monitor; (4) cited a
  paid-tier-gated block as an "established pattern" when it has never run.
- No blocking errors remain. Deepen-plan gates 4.6, 4.7, 4.8, 4.10, 4.11 pass; 4.5, 4.9, 4.55
  correctly did not trigger.

### Decisions

- **The issue's own remediation was refuted by measurement.** `equals 301` is structurally
  unsatisfiable: Sentry's uptime checker always follows 3xx (reqwest `Policy::limited(10)`, no
  disable knob) and evaluates assertions against the *terminal* response, so it tests
  `equals 301` against the apex's 200. The live assertion is byte-identical to the declared one,
  so neither the "dispatch apply to converge" nor the "recreate" path could ever have worked.
  Incident `WEB-PLATFORM-11` (578 events) opened the day the assertion landed; 101 days, no
  recovery.
- **Root cause established from vendor source, not inferred** — `getsentry/uptime-checker` plus
  Sentry's own docs. The initial timing evidence (www median 101 ms *faster* than apex 128 ms)
  appeared to contradict redirect-following; it resolved as the same per-hop-row artifact as the
  `httpStatusCode: 301`, and is recorded as resolved rather than suppressed.
- **The redirect-health property moves vendors, because it is inexpressible in Sentry.** The
  whole op catalog reads the terminal response, which also kills the `op_header_check`-on-
  `Location` fix that looked most attractive. Better Stack's `follow_redirects = false` +
  `expected_status_codes = [301]` is the only knob in the stack that can express it; the
  "vendor isolation, not URL coverage" principle is amended in ADR-204 rather than ignored.
- **The first design was cut on minimality after CTO review** — an hourly GHA probe + script +
  cron monitor + test battery + five C4 parity clauses (~2 h MTTD) replaced by one Terraform
  resource (~20 min MTTD). That also uncovered the real stake: `dns.tf`'s Camp B ruling
  explicitly accepts a failure mode "for one monitor interval" on the strength of an assertion
  that never fired, so an hourly replacement would have silently widened a documented
  architectural bound.
- **A P0 apply-path defect was found and fixed in-plan:** the web-platform root is `-target=`
  scoped, not full-root, so the new monitor needs an allow-list line or it is declared and never
  applied.
- **The documentation-derived claim is falsified before merge, not after.** Phase 0 creates,
  observes and deletes a transient probe with `confirmation_period = 0`; a strong-model consult
  showed the original post-merge AC could not fail *inside* the confirmation window, so it now
  requires sustained-up past it AND a 301 on the check row, with an explicit containment
  sequence on failure.
- **The Sentry monitor is renamed, not just retargeted**, and gains a `description` (which the
  provider documents as reaching the resulting issue) — leaving a monitor named for a property
  it no longer checks would reproduce the very trap this issue is about.

### Components Invoked

- Skills: `soleur:plan`, `soleur:plan-review`, `soleur:deepen-plan`
- Agents: `repo-research-analyst`, `learnings-researcher`, `best-practices-researcher`,
  `framework-docs-researcher`, `functional-discovery`, `cto` (x2 — structural, then devex lens),
  `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`,
  `architecture-strategist`, `spec-flow-analyzer`, scoped strong-model consult, plus the two
  Phase 4.45 realism passes
- Live data pulled directly (no dashboard delegation, per `hr-no-dashboard-eyeball-pull-data-yourself`):
  Sentry uptime + checks + issues APIs, Better Stack monitors + heartbeats APIs, pinned-provider
  docs for `jianyuan/sentry 0.15.7` and `BetterStackHQ/better-uptime 0.20.17`
- Commits: `8d958eddb` (plan + tasks), `7c386599f` (deepened) — both pushed
